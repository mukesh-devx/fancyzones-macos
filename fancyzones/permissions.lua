--- Accessibility permission handling.
---
--- Hammerspoon needs the macOS "Accessibility" permission to (a) observe
--- keyboard/mouse events with hs.eventtap and (b) move other apps' windows.
--- Without it, event taps silently never fire, so we detect that up front,
--- prompt once, and start the feature as soon as the user grants it.

local log = require("fancyzones.log")

local M = {}

M.SETTINGS_URL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

local poll -- timer waiting for the permission to be granted
local prompted = false

function M.isGranted()
  return hs.accessibilityState() == true
end

function M.openSettings()
  hs.urlevent.openURL(M.SETTINGS_URL)
end

--- Stop waiting for the permission (called on stop/reload).
function M.cancel()
  if poll then
    poll:stop()
    poll = nil
  end
end

--- Run `onGranted` now if Accessibility is enabled; otherwise show the system
--- prompt (once), explain what to do, and run it as soon as access is granted.
--- Returns true when permission was already available.
function M.ensure(onGranted)
  M.cancel()
  if M.isGranted() then
    onGranted()
    return true
  end

  log.w("Accessibility permission not granted yet")
  if not prompted then
    prompted = true
    hs.accessibilityState(true) -- triggers the macOS "would like to control this computer" dialog
  end
  hs.alert.show(
    "FancyZones needs Accessibility access\nSystem Settings → Privacy & Security → Accessibility → enable Hammerspoon",
    8)

  poll = hs.timer.doEvery(1.5, function()
    if M.isGranted() then
      M.cancel()
      log.i("Accessibility granted")
      hs.alert.show("Accessibility enabled. FancyZones is active.", 2)
      onGranted()
    end
  end)
  return false
end

--- After starting an event tap, confirm macOS actually enabled it.
--- Returns true when the tap is running; otherwise tells the user what to do.
function M.verifyTap(tap, what)
  if tap:isEnabled() then return true end
  log.e("event tap did not start:", what)
  hs.alert.show(
    "FancyZones could not start its " .. what .. " listener.\nQuit and reopen Hammerspoon, then check Accessibility permission.",
    8)
  return false
end

return M
