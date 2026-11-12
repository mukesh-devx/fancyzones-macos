--- Pure gesture math for the zone editor (no Hammerspoon dependencies).
---
--- Everything here works on normalized zones {x, y, w, h} (0..1). The editor
--- controller feeds it pointer positions and gets back new rects, which keeps
--- the interaction logic testable and the controller small.

local geometry = require("fancyzones.geometry")

local M = {}

local EPS = 0.003 -- two edges closer than this count as "the same line"

---------------------------------------------------------------------------
-- Snapping candidates
---------------------------------------------------------------------------

--- Lines a dragged edge may snap to: screen bounds, centre, and the edges of
--- every zone except those in `skip` (a set of indices, e.g. the zone being dragged).
--- `snap` = { xs = {...}, ys = {...}, tx = thr, ty = thr } with thresholds normalized.
function M.candidates(zones, skip, thrX, thrY)
  local xs, ys = { 0, 0.5, 1 }, { 0, 0.5, 1 }
  for i, z in ipairs(zones) do
    if not (skip and skip[i]) then
      xs[#xs + 1] = z.x
      xs[#xs + 1] = z.x + z.w
      ys[#ys + 1] = z.y
      ys[#ys + 1] = z.y + z.h
    end
  end
  return { xs = xs, ys = ys, tx = thrX, ty = thrY }
end

--- Snap a point; returns sx, sy, guideX (line snapped to or nil), guideY.
function M.snapPoint(nx, ny, snap)
  if not snap then return nx, ny, nil, nil end
  local sx, gx = geometry.snapValue(nx, snap.xs, snap.tx)
  local sy, gy = geometry.snapValue(ny, snap.ys, snap.ty)
  return sx, sy, gx, gy
end

--- Snap whichever end of the span [start, start+size] is closer to a candidate.
local function snapSpan(start, size, cands, thr)
  local s1, c1 = geometry.snapValue(start, cands, thr)
  local s2, c2 = geometry.snapValue(start + size, cands, thr)
  local d1 = c1 and math.abs(s1 - start) or math.huge
  local d2 = c2 and math.abs(s2 - (start + size)) or math.huge
  if d1 == math.huge and d2 == math.huge then return start, nil end
  if d1 <= d2 then return s1, c1 end
  return s2 - size, c2
end

---------------------------------------------------------------------------
-- Draw
---------------------------------------------------------------------------

--- Rect spanning two (already snapped) points, clamped into 0..1.
function M.rectFromPoints(ax, ay, bx, by)
  local x1, x2 = geometry.clamp(math.min(ax, bx), 0, 1), geometry.clamp(math.max(ax, bx), 0, 1)
  local y1, y2 = geometry.clamp(math.min(ay, by), 0, 1), geometry.clamp(math.max(ay, by), 0, 1)
  return { x = x1, y = y1, w = x2 - x1, h = y2 - y1 }
end

---------------------------------------------------------------------------
-- Move
---------------------------------------------------------------------------

--- Move `origin` by (dx, dy) (normalized), keeping it on screen and snapping
--- its edges. Returns rect, guides = { x = line or nil, y = line or nil }.
function M.moveRect(origin, dx, dy, snap)
  local x = geometry.clamp(origin.x + dx, 0, 1 - origin.w)
  local y = geometry.clamp(origin.y + dy, 0, 1 - origin.h)
  local guides = {}
  if snap then
    x, guides.x = snapSpan(x, origin.w, snap.xs, snap.tx)
    y, guides.y = snapSpan(y, origin.h, snap.ys, snap.ty)
    x = geometry.clamp(x, 0, 1 - origin.w)
    y = geometry.clamp(y, 0, 1 - origin.h)
  end
  return { x = x, y = y, w = origin.w, h = origin.h }, guides
end

--- Nudge a zone, keeping it on screen.
function M.nudge(zone, dx, dy)
  return {
    x = geometry.clamp(zone.x + dx, 0, 1 - zone.w),
    y = geometry.clamp(zone.y + dy, 0, 1 - zone.h),
    w = zone.w, h = zone.h,
  }
end

---------------------------------------------------------------------------
-- Resize (with linked "splitter" edges)
---------------------------------------------------------------------------

--- Zones whose edge lies on the same vertical/horizontal line as the edge
--- being dragged and which are contiguous with the dragged zone along it.
--- Dragging that edge moves all of them together, like a splitter.
--- axis: "x" (vertical line) or "y"; which: 1 = start edge (left/top), 2 = end edge.
--- Returns a list of { index = j, which = 1|2 } describing each linked zone's edge.
local function line(zones, i, axis, which)
  local z = zones[i]
  local v, s1, s2
  if axis == "x" then
    v = (which == 1) and z.x or (z.x + z.w)
    s1, s2 = z.y, z.y + z.h
  else
    v = (which == 1) and z.y or (z.y + z.h)
    s1, s2 = z.x, z.x + z.w
  end

  local segs = {}
  for j, zj in ipairs(zones) do
    if j ~= i then
      local a1, a2, p1, p2
      if axis == "x" then
        a1, a2, p1, p2 = zj.x, zj.x + zj.w, zj.y, zj.y + zj.h
      else
        a1, a2, p1, p2 = zj.y, zj.y + zj.h, zj.x, zj.x + zj.w
      end
      if math.abs(a1 - v) < EPS then
        segs[#segs + 1] = { index = j, which = 1, p1 = p1, p2 = p2 }
      elseif math.abs(a2 - v) < EPS then
        segs[#segs + 1] = { index = j, which = 2, p1 = p1, p2 = p2 }
      end
    end
  end

  -- Grow the contiguous run starting from the dragged zone's span.
  local lo, hi = s1, s2
  local used, changed = {}, true
  while changed do
    changed = false
    for k, s in ipairs(segs) do
      if not used[k] and s.p1 <= hi + EPS and s.p2 >= lo - EPS then
        used[k] = true
        lo, hi = math.min(lo, s.p1), math.max(hi, s.p2)
        changed = true
      end
    end
  end

  local out = {}
  for k, s in ipairs(segs) do
    if used[k] then out[#out + 1] = { index = s.index, which = s.which } end
  end
  return out
end

--- Links for dragging `handle` of zone `i`. Returns linkX, linkY (lists, maybe empty).
function M.findLinks(zones, i, handle)
  local linkX, linkY = {}, {}
  if handle:find("w") then linkX = line(zones, i, "x", 1)
  elseif handle:find("e") then linkX = line(zones, i, "x", 2) end
  if handle:find("n") then linkY = line(zones, i, "y", 1)
  elseif handle:find("s") then linkY = line(zones, i, "y", 2) end
  return linkX, linkY
end

local function resolveEdge(v, lo, hi, cands, thr)
  local snapped, c = v, nil
  if cands then snapped, c = geometry.snapValue(v, cands, thr) end
  local clamped = math.max(lo, math.min(hi, snapped))
  if c and math.abs(clamped - c) > 1e-9 then c = nil end -- clamped away from the line
  return clamped, c
end

--- Resize `origin` by dragging `handle` (n, s, e, w, ne, nw, se, sw) to the
--- normalized pointer position (nx, ny).
--- opts = { snap = <candidates|nil>, zones = <snapshot of all zones>,
---          linkX = {...}, linkY = {...}, minW = n, minH = n }
--- Returns newRect, updates ({ [index] = rect } for linked zones), guides.
function M.resize(origin, handle, nx, ny, opts)
  local l, t = origin.x, origin.y
  local r, b = origin.x + origin.w, origin.y + origin.h
  local minW, minH = opts.minW, opts.minH
  local snap = opts.snap
  local guides = {}
  local updates = {}

  local function upd(j)
    if not updates[j] then
      local z = opts.zones[j]
      updates[j] = { x = z.x, y = z.y, w = z.w, h = z.h }
    end
    return updates[j]
  end

  local movesL, movesR = handle:find("w") ~= nil, handle:find("e") ~= nil
  local movesT, movesB = handle:find("n") ~= nil, handle:find("s") ~= nil

  if movesL or movesR then
    local lo, hi
    if movesL then lo, hi = 0, r - minW else lo, hi = l + minW, 1 end
    for _, lk in ipairs(opts.linkX or {}) do
      local zj = opts.zones[lk.index]
      if lk.which == 1 then hi = math.min(hi, zj.x + zj.w - minW) else lo = math.max(lo, zj.x + minW) end
    end
    local v, g = resolveEdge(nx, lo, hi, snap and snap.xs, snap and snap.tx)
    if movesL then l = v else r = v end
    guides.x = g
    for _, lk in ipairs(opts.linkX or {}) do
      local zj, u = opts.zones[lk.index], upd(lk.index)
      if lk.which == 1 then u.x, u.w = v, zj.x + zj.w - v else u.w = v - zj.x end
    end
  end

  if movesT or movesB then
    local lo, hi
    if movesT then lo, hi = 0, b - minH else lo, hi = t + minH, 1 end
    for _, lk in ipairs(opts.linkY or {}) do
      local zj = opts.zones[lk.index]
      if lk.which == 1 then hi = math.min(hi, zj.y + zj.h - minH) else lo = math.max(lo, zj.y + minH) end
    end
    local v, g = resolveEdge(ny, lo, hi, snap and snap.ys, snap and snap.ty)
    if movesT then t = v else b = v end
    guides.y = g
    for _, lk in ipairs(opts.linkY or {}) do
      local zj, u = opts.zones[lk.index], upd(lk.index)
      if lk.which == 1 then u.y, u.h = v, zj.y + zj.h - v else u.h = v - zj.y end
    end
  end

  return { x = l, y = t, w = r - l, h = b - t }, updates, guides
end

---------------------------------------------------------------------------
-- Handles / hit testing (absolute pixel rects)
---------------------------------------------------------------------------

M.HANDLE_ORDER = { "nw", "ne", "se", "sw", "n", "e", "s", "w" }

--- Handle positions for an absolute rect.
function M.handlePoints(r)
  local cx, cy = r.x + r.w / 2, r.y + r.h / 2
  local x2, y2 = r.x + r.w, r.y + r.h
  return {
    nw = { x = r.x, y = r.y }, n = { x = cx, y = r.y }, ne = { x = x2, y = r.y },
    e = { x = x2, y = cy }, se = { x = x2, y = y2 }, s = { x = cx, y = y2 },
    sw = { x = r.x, y = y2 }, w = { x = r.x, y = cy },
  }
end

--- Which handle (if any) is under (px, py)? Grab points win over edge bands.
function M.hitHandle(r, px, py, tol, band)
  local pts = M.handlePoints(r)
  for _, name in ipairs(M.HANDLE_ORDER) do
    local p = pts[name]
    if math.abs(px - p.x) <= tol and math.abs(py - p.y) <= tol then return name end
  end
  local x2, y2 = r.x + r.w, r.y + r.h
  local inX = px >= r.x and px <= x2
  local inY = py >= r.y and py <= y2
  if inY and math.abs(px - r.x) <= band then return "w" end
  if inY and math.abs(px - x2) <= band then return "e" end
  if inX and math.abs(py - r.y) <= band then return "n" end
  if inX and math.abs(py - y2) <= band then return "s" end
  return nil
end

--- A default rect for the "+ Zone" button, cascaded so repeated clicks do not
--- stack exactly on top of each other.
function M.newZone(existingCount)
  local size = 0.3
  local shift = (existingCount % 5) * 0.03
  return geometry.sanitizeZone({ x = 0.35 + shift - 0.06, y = 0.35 + shift - 0.06, w = size, h = size })
end

return M
