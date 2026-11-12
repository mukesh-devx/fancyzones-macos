--- Pure geometry helpers (no Hammerspoon dependencies).
---
--- Zones are stored *normalized*: {x, y, w, h} with every value in 0..1,
--- relative to a screen's usable frame (the area without menu bar and Dock).
--- That is what makes a layout independent of the monitor resolution.

local M = {}

local EPS = 0.002 -- tolerance used to decide whether a zone touches a screen edge

function M.clamp(v, lo, hi)
  if v < lo then return lo elseif v > hi then return hi end
  return v
end

function M.round(v) return math.floor(v + 0.5) end

--- Round to 4 decimals so saved JSON stays tidy.
function M.round4(v) return math.floor(v * 10000 + 0.5) / 10000 end

function M.copyRect(r) return { x = r.x, y = r.y, w = r.w, h = r.h } end

function M.area(r) return r.w * r.h end

--- Point-in-rect test, inclusive on all edges.
function M.contains(r, x, y)
  return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
end

--- Length of the overlap between intervals [a1,a2] and [b1,b2] (negative if apart).
function M.overlap(a1, a2, b1, b2)
  return math.min(a2, b2) - math.max(a1, b1)
end

--- Convert a normalized zone to an absolute rect inside `frame`.
function M.zoneToRect(zone, frame)
  return {
    x = frame.x + zone.x * frame.w,
    y = frame.y + zone.y * frame.h,
    w = zone.w * frame.w,
    h = zone.h * frame.h,
  }
end

--- Convert an absolute rect to a normalized zone relative to `frame`.
function M.rectToZone(rect, frame)
  return {
    x = (rect.x - frame.x) / frame.w,
    y = (rect.y - frame.y) / frame.h,
    w = rect.w / frame.w,
    h = rect.h / frame.h,
  }
end

--- Clamp an absolute point into `frame` and return it as normalized coordinates.
function M.pointToNorm(pt, frame)
  local x = M.clamp(pt.x, frame.x, frame.x + frame.w)
  local y = M.clamp(pt.y, frame.y, frame.y + frame.h)
  return (x - frame.x) / frame.w, (y - frame.y) / frame.h
end

--- The rect a window should get for `zone` on a screen with usable `frame`.
--- `spacing` is the gap in px: the full gap against screen edges, half of it
--- against other zones (so two neighbouring windows end up `spacing` apart).
--- Edges are rounded individually so neighbouring zones never gain a 1px gap.
function M.targetRect(zone, frame, spacing)
  spacing = spacing or 0
  local half = spacing / 2
  local l = zone.x <= EPS and spacing or half
  local t = zone.y <= EPS and spacing or half
  local r = (zone.x + zone.w) >= 1 - EPS and spacing or half
  local b = (zone.y + zone.h) >= 1 - EPS and spacing or half

  local abs = M.zoneToRect(zone, frame)
  local x1 = M.round(abs.x + l)
  local y1 = M.round(abs.y + t)
  local x2 = M.round(abs.x + abs.w - r)
  local y2 = M.round(abs.y + abs.h - b)
  if x2 - x1 < 1 or y2 - y1 < 1 then -- zone smaller than the gaps: ignore spacing
    x1, y1 = M.round(abs.x), M.round(abs.y)
    x2, y2 = M.round(abs.x + abs.w), M.round(abs.y + abs.h)
  end
  return { x = x1, y = y1, w = x2 - x1, h = y2 - y1 }
end

--- Index of the zone containing the normalized point, or nil.
--- With overlapping zones the smallest wins (it is the more specific target);
--- on a tie the later (visually top-most) zone wins.
function M.zoneAt(zones, nx, ny)
  local best, bestArea
  for i, z in ipairs(zones) do
    if M.contains(z, nx, ny) then
      local a = M.area(z)
      if not best or a <= bestArea then best, bestArea = i, a end
    end
  end
  return best
end

--- Clamp a zone so it is valid (inside 0..1, at least `minSize` large).
function M.sanitizeZone(z, minSize)
  minSize = minSize or 0.02
  local w = M.clamp(z.w, minSize, 1)
  local h = M.clamp(z.h, minSize, 1)
  local x = M.clamp(z.x, 0, 1 - w)
  local y = M.clamp(z.y, 0, 1 - h)
  return { x = x, y = y, w = w, h = h }
end

--- Snap `v` to the nearest candidate within `thr`. Returns value, candidate-or-nil.
function M.snapValue(v, candidates, thr)
  local best, bestDist = nil, thr
  for _, c in ipairs(candidates) do
    local d = math.abs(c - v)
    if d <= bestDist then best, bestDist = c, d end
  end
  if best ~= nil then return best, best end
  return v, nil
end

--- Are two absolute rects equal within `tol` px?
function M.rectsNear(a, b, tol)
  tol = tol or 2
  return math.abs(a.x - b.x) <= tol and math.abs(a.y - b.y) <= tol
    and math.abs(a.w - b.w) <= tol and math.abs(a.h - b.h) <= tol
end

return M
