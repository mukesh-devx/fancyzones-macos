--- Window lookup and positioning (hs.window).

local geometry = require("fancyzones.geometry")
local log = require("fancyzones.log")
local util = require("fancyzones.util")

local M = {}

local excluded = {} -- set of bundle IDs that must not be snapped

function M.setExcludedApps(list)
  excluded = {}
  for _, id in ipairs(list or {}) do excluded[id] = true end
end

--- Can this window be snapped? (Standard, visible, not native fullscreen, not excluded.)
function M.snappable(win)
  if not win then return false end
  local okStd, std = pcall(win.isStandard, win)
  if not okStd or not std then return false end
  if win:isFullScreen() or win:isMinimized() then return false end
  local app = win:application()
  if app and excluded[app:bundleID() or ""] then return false end
  return true
end

local function frameContains(win, pt, margin)
  local f = win:frame()
  return pt.x >= f.x - margin and pt.x <= f.x + f.w + margin
    and pt.y >= f.y - margin and pt.y <= f.y + f.h + margin
end

--- Best guess for "the window the user is dragging right now".
--- While dragging a window by its title bar the pointer stays on that window,
--- and the window was just raised, so it is almost always the frontmost one.
--- Fall back to the top-most window under the pointer.
function M.draggedWindow(pt)
  local margin = 12
  local front = hs.window.frontmostWindow()
  if front and M.snappable(front) and frameContains(front, pt, margin) then
    return front
  end
  for _, w in ipairs(hs.window.orderedWindows()) do
    if M.snappable(w) and frameContains(w, pt, margin) then return w end
  end
  return nil
end

--- Move/resize `win` to the absolute `rect`, animated.
--- Some windows (minimum sizes, windows crossing displays) reject the first
--- attempt, so after the animation we verify and retry once without animation.
function M.moveToRect(win, rect, duration)
  duration = duration or 0
  local ok, err = pcall(function() win:setFrame(rect, duration) end)
  if not ok then
    log.e("setFrame failed:", err)
    return false
  end

  util.after(duration + 0.08, function()
    local okF, f = pcall(function() return win:frame() end)
    if not okF or not f then return end
    if not geometry.rectsNear(f, rect, 2) then
      log.d("retrying setFrame; wanted", hs.inspect(rect), "got", hs.inspect({ f.x, f.y, f.w, f.h }))
      pcall(function() win:setFrame(rect, 0) end)
    end
  end)
  return true
end

return M
