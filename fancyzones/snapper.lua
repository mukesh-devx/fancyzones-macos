--- Drag-to-snap: watches the mouse with hs.eventtap, shows the overlay while a
--- window is being dragged with the snap modifier held, and snaps on release.
---
--- Detection strategy
--- macOS gives no "a window is being dragged" event, so we infer it:
---   1. leftMouseDown starts a potential drag (cheap: we only remember the point).
---   2. While the snap modifier is held during leftMouseDragged we pick the
---      window under the pointer and compare its frame between two samples.
---      If it moved along with the pointer and kept its size, the user is
---      dragging that window by its title bar. If it did not move (text
---      selection, scrollbar, ...) or its size changed (a resize), the drag is
---      ignored. Nothing expensive happens unless the modifier is held.
---   3. Releasing the modifier hides the overlay; releasing the mouse over a
---      highlighted zone snaps the window there.
--- The tap callback never consumes events (always returns false), so apps keep
--- receiving the drag untouched.

local windows = require("fancyzones.windows")
local permissions = require("fancyzones.permissions")
local util = require("fancyzones.util")
local log = require("fancyzones.log")

local Snapper = {}
Snapper.__index = Snapper

local SAMPLE_INTERVAL = 0.03 -- seconds between window-frame samples while classifying
local FOLLOW_RATIO = 0.5      -- window must travel at least this fraction of the pointer
local GIVE_UP_DISTANCE = 48   -- pointer travel after which a non-following window is ignored

function Snapper.new(cfg, overlay)
  local self = setmetatable({
    cfg = cfg,
    overlay = overlay,
    enabled = true,
    suspended = false,
    tap = nil,
    watchdog = nil,
    guard = nil,
  }, Snapper)
  self:_resetState()
  return self
end

function Snapper:_resetState()
  self.st = {
    phase = "idle",      -- idle | pressed | dragging
    downPt = nil,
    winState = nil,      -- nil | candidate | moving | rejected
    win = nil,
    s1 = nil,            -- first window-frame sample
    lastSample = 0,
    active = false,      -- overlay is showing
  }
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

function Snapper:_shouldRun()
  return self.enabled and not self.suspended
end

--- Start/stop the underlying tap so it matches enabled/suspended.
function Snapper:_sync()
  if not self.tap then return end
  if self:_shouldRun() then
    if not self.tap:isEnabled() then self.tap:start() end
  else
    self:_cancel()
    if self.tap:isEnabled() then self.tap:stop() end
  end
end

--- Create and start the event tap. Returns false if macOS refused it
--- (usually: Accessibility permission missing).
function Snapper:start()
  if self.tap then return self.tap:isEnabled() end
  local T = hs.eventtap.event.types
  self.tap = hs.eventtap.new(
    { T.leftMouseDown, T.leftMouseUp, T.leftMouseDragged, T.flagsChanged },
    function(e) return self:_handle(e) end)

  if self:_shouldRun() then self.tap:start() end

  -- macOS disables a tap that is too slow or after sleep/wake; revive it.
  self.watchdog = hs.timer.doEvery(5, function()
    if self.tap and self:_shouldRun() and not self.tap:isEnabled() then
      log.w("event tap was disabled; restarting")
      self.tap:start()
    end
  end)

  return permissions.verifyTap(self.tap, "window-drag")
end

function Snapper:stop()
  self:_cancel()
  if self.watchdog then self.watchdog:stop(); self.watchdog = nil end
  if self.tap then self.tap:stop(); self.tap = nil end
end

function Snapper:setEnabled(flag)
  self.enabled = flag and true or false
  self:_sync()
end

function Snapper:isEnabled() return self.enabled end

--- Temporarily stop listening (the editor is open).
function Snapper:suspend()
  self.suspended = true
  self:_sync()
end

function Snapper:resume()
  self.suspended = false
  self:_sync()
end

---------------------------------------------------------------------------
-- Event handling
---------------------------------------------------------------------------

function Snapper:_handle(e)
  local ok, err = pcall(self._dispatch, self, e)
  if not ok then
    log.e("snapper error:", err)
    self:_cancel()
  end
  return false -- never swallow events
end

function Snapper:_dispatch(e)
  local T = hs.eventtap.event.types
  local t = e:getType()
  local st = self.st

  if t == T.leftMouseDown then
    self:_cancel()
    self.st.phase = "pressed"
    self.st.downPt = e:location()
  elseif t == T.leftMouseDragged then
    if st.phase == "idle" then return end
    st.phase = "dragging"
    self:_onDrag(e:location(), e:getFlags())
  elseif t == T.flagsChanged then
    if st.phase == "dragging" then
      self:_onDrag(hs.mouse.absolutePosition(), e:getFlags())
    end
  elseif t == T.leftMouseUp then
    self:_onRelease(e:location())
  end
end

function Snapper:_onDrag(pt, flags)
  local st = self.st

  if not util.hasModifiers(flags, self.cfg.snapModifiers) then
    -- Modifier released (or never pressed): hide the zones, but remember
    -- that this drag moves a window so pressing it again is instant.
    if st.active then
      self.overlay:hide()
      st.active = false
    end
    if st.winState == "rejected" then st.winState, st.win, st.s1 = nil, nil, nil end
    return
  end

  if st.winState == "moving" then
    if not st.active then self:_activate(pt) end
    self.overlay:update(pt)
    return
  end
  if st.winState == "rejected" then return end

  local now = hs.timer.secondsSinceEpoch()
  if now - st.lastSample < SAMPLE_INTERVAL then return end
  st.lastSample = now
  self:_classify(pt)
end

--- Decide whether the drag moves a window; activates the overlay if so.
function Snapper:_classify(pt)
  local st = self.st

  if not st.win then -- first sample
    local win = windows.draggedWindow(pt)
    if not win then
      st.winState = "rejected"
      return
    end
    local f = win:frame()
    st.win = win
    st.s1 = { pt = { x = pt.x, y = pt.y }, x = f.x, y = f.y, w = f.w, h = f.h }
    st.winState = "candidate"
    return
  end

  -- second (and later) samples: did the window follow the pointer?
  local s1 = st.s1
  local dx, dy = pt.x - s1.pt.x, pt.y - s1.pt.y
  local dist = math.sqrt(dx * dx + dy * dy)
  if dist < self.cfg.dragThreshold then return end

  local f = st.win:frame()
  if math.abs(f.w - s1.w) > 2 or math.abs(f.h - s1.h) > 2 then
    st.winState = "rejected" -- a resize, not a move
    return
  end

  local wx, wy = f.x - s1.x, f.y - s1.y
  local wdist = math.sqrt(wx * wx + wy * wy)
  if wx * dx + wy * dy > 0 and wdist >= dist * FOLLOW_RATIO then
    st.winState = "moving"
    self:_activate(pt)
  elseif dist > GIVE_UP_DISTANCE then
    st.winState = "rejected" -- pointer moved a lot, window did not: not a window drag
  end
end

function Snapper:_activate(pt)
  local st = self.st
  st.active = true
  self.overlay:show()
  self.overlay:update(pt)
  self:_startGuard()
end

function Snapper:_onRelease(pt)
  local st = self.st
  local win, wasActive = st.win, st.active
  local target
  if wasActive then target = self.overlay:update(pt) end
  self:_cancel()

  if wasActive and target and win then
    local rect = { x = target.rect.x, y = target.rect.y, w = target.rect.w, h = target.rect.h }
    -- Let the app finish its own end-of-drag handling before we move the window.
    util.after(0.03, function()
      windows.moveToRect(win, rect, self.cfg.animationDuration)
    end)
  end
end

--- Safety net: if a mouse-up was missed (tap timed out, screen locked, ...)
--- the overlay would stay on screen, so poll the real button state.
function Snapper:_startGuard()
  if self.guard then return end
  self.guard = hs.timer.doEvery(0.4, function()
    if not hs.eventtap.checkMouseButtons().left then
      log.d("mouse button no longer down; cancelling drag")
      self:_cancel()
    end
  end)
end

--- Abort any drag in progress and hide the overlay (public).
function Snapper:cancel() self:_cancel() end

--- Abort any drag in progress and hide the overlay.
function Snapper:_cancel()
  if self.guard then
    self.guard:stop()
    self.guard = nil
  end
  if self.st.active then self.overlay:hide() end
  self:_resetState()
end

return Snapper
