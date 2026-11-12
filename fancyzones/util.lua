--- Small shared helpers.

local M = {}

-- Hammerspoon timers (like eventtaps and canvases) stop working if Lua garbage
-- collects them. One-shot timers are therefore parked here until they fire.
local live = {}

--- Like hs.timer.doAfter, but keeps the timer referenced until it fires.
--- Returns a handle with :stop() to cancel.
function M.after(seconds, fn)
  local timer
  timer = hs.timer.doAfter(seconds, function()
    live[timer] = nil
    fn()
  end)
  live[timer] = true
  return timer
end

--- Cancel every pending M.after timer (used on stop/reload).
function M.cancelAll()
  for timer in pairs(live) do timer:stop() end
  live = {}
end

--- Case-insensitive set of modifier names -> true.
function M.modSet(list)
  local s = {}
  for _, m in ipairs(list) do s[m] = true end
  return s
end

--- Do the event flags (table with cmd/alt/ctrl/shift = true) include all of `mods`?
function M.hasModifiers(flags, mods)
  for _, m in ipairs(mods) do
    if not flags[m] then return false end
  end
  return true
end

return M
