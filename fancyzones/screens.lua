--- Multi-monitor helpers.
---
--- Hammerspoon uses one global coordinate space: origin at the top-left of the
--- primary screen, y growing downwards. Screens left of / above the primary one
--- have negative coordinates. Everything here returns plain tables.

local M = {}

local function toTable(r)
  return { x = r.x, y = r.y, w = r.w, h = r.h }
end

--- Stable identifier for a physical display (survives reboots / re-plugging).
function M.key(screen)
  return screen:getUUID() or tostring(screen:id())
end

--- Snapshot of one screen: full frame (incl. menu bar/Dock) and usable frame.
function M.info(screen)
  return {
    screen = screen,
    key = M.key(screen),
    name = screen:name() or "Display",
    full = toTable(screen:fullFrame()),
    frame = toTable(screen:frame()),
  }
end

--- Snapshots of all connected screens (primary first, then left-to-right).
function M.all()
  local primaryId = hs.screen.primaryScreen():id()
  local list = {}
  for _, s in ipairs(hs.screen.allScreens()) do
    local info = M.info(s)
    info.order = (s:id() == primaryId) and -math.huge or info.full.x -- strict, consistent sort key
    list[#list + 1] = info
  end
  table.sort(list, function(a, b) return a.order < b.order end)
  return list
end

local function distanceToRect(pt, r)
  local dx = math.max(r.x - pt.x, 0, pt.x - (r.x + r.w))
  local dy = math.max(r.y - pt.y, 0, pt.y - (r.y + r.h))
  return dx * dx + dy * dy
end

--- Pick the entry of `infos` whose full frame contains `pt`; if the point sits
--- in a gap between displays, pick the nearest one.
function M.pick(infos, pt)
  local best, bestDist
  for _, info in ipairs(infos) do
    local d = distanceToRect(pt, info.full)
    if d == 0 then return info end
    if not bestDist or d < bestDist then best, bestDist = info, d end
  end
  return best
end

--- Fingerprint of the current display arrangement, to detect changes.
function M.signature(infos)
  local parts = {}
  for _, i in ipairs(infos) do
    parts[#parts + 1] = string.format("%s@%d,%d,%d,%d/%d,%d,%d,%d", i.key,
      i.full.x, i.full.y, i.full.w, i.full.h, i.frame.x, i.frame.y, i.frame.w, i.frame.h)
  end
  return table.concat(parts, "|")
end

return M
