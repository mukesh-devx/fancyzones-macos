--- Zone editor (Option+Z).
---
--- A full-screen hs.canvas per display shows that display's layout over a dimmed
--- desktop. All input comes from one hs.eventtap which *swallows* every mouse
--- and key event while the editor is open, so nothing leaks to apps underneath.
--- The canvases only render; hit-testing is done here against the `ui` regions
--- and zone rects produced by editor_view, so drawing and interaction agree.
---
--- Edits are made on draft copies. Save (Enter / button) writes them through
--- layouts.commit; Cancel (Esc) discards. Every change is undoable (Cmd+Z).

local geometry = require("fancyzones.geometry")
local screens = require("fancyzones.screens")
local layouts = require("fancyzones.layouts")
local ops = require("fancyzones.editor_ops")
local view = require("fancyzones.editor_view")
local util = require("fancyzones.util")
local permissions = require("fancyzones.permissions")
local log = require("fancyzones.log")

local Editor = {}
Editor.__index = Editor

local MAX_UNDO = 60
local RENDER_INTERVAL = 1 / 60
local DRAG_ARM_PX = 3           -- pointer travel before a move gesture starts changing the zone
local CLICK_PX = 5              -- travel below which a draw gesture counts as a plain click
local MAX_NAME_CHARS = 32

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

local function copyZone(z) return { x = z.x, y = z.y, w = z.w, h = z.h } end

local function copyList(t)
  local out = {}
  for i, v in ipairs(t) do out[i] = v end
  return out
end

local function copyMap(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

local function copyDrafts(drafts)
  local out = {}
  for id, d in pairs(drafts) do out[id] = layouts.draft(d) end
  return out
end

--- Round edges (not sizes) to 4 decimals so neighbours stay exactly aligned.
local function quant(r)
  local x1, y1 = geometry.round4(r.x), geometry.round4(r.y)
  local x2, y2 = geometry.round4(r.x + r.w), geometry.round4(r.y + r.h)
  return { x = x1, y = y1, w = geometry.round4(x2 - x1), h = geometry.round4(y2 - y1) }
end

local function indexOf(list, value)
  for i, v in ipairs(list) do
    if v == value then return i end
  end
  return nil
end

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function dropLastChar(s)
  return (s:gsub(utf8.charpattern .. "$", ""))
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------

--- hooks = { onOpen = fn(), onClose = fn(saved) }
function Editor.new(cfg, palette, hooks)
  local self = setmetatable({
    cfg = cfg,
    pal = palette,
    hooks = hooks or {},
    isOpen = false,
  }, Editor)
  self:_resetState()
  return self
end

function Editor:_resetState()
  self.views = {}
  self.drafts, self.order, self.assign = {}, {}, {}
  self.sel = nil
  self.gesture = nil
  self.undo = {}
  self.dirty = false
  self.discardArmed = false
  self.hoverId = nil
  self.pressed = nil
  self.renaming = nil
  self.toastText = nil
  self.lastRender = 0
  self.lastNudge = 0
  self.measureCache = {}
  self.templates = layouts.templates()
end

function Editor:isActive() return self.isOpen end

---------------------------------------------------------------------------
-- Open / close
---------------------------------------------------------------------------

function Editor:toggle()
  if self.isOpen then self:requestClose() else self:open() end
end

function Editor:open()
  if self.isOpen then return end

  if not permissions.isGranted() then
    hs.alert.show("FancyZones needs Accessibility access to edit zones.\nOpening System Settings…", 4)
    permissions.openSettings()
    return
  end

  local infos = screens.all()
  if #infos == 0 then return end

  self:_resetState()
  for _, l in ipairs(layouts.list()) do
    self.drafts[l.id] = layouts.draft(l)
    self.order[#self.order + 1] = l.id
  end
  self.assign = copyMap(layouts.data.assignments) -- keep entries of disconnected displays
  for _, info in ipairs(infos) do
    self.assign[info.key] = layouts.layoutFor(info.key).id
  end

  for _, info in ipairs(infos) do
    local canvas = hs.canvas.new(info.full)
    canvas:level(hs.canvas.windowLevels.overlay)
    canvas:behavior({ "canJoinAllSpaces", "fullScreenAuxiliary" })
    canvas:canvasDefaultFor("textFont", self.pal.font)
    canvas:canvasDefaultFor("textSize", 13)
    self.views[#self.views + 1] = { info = info, canvas = canvas, ui = {}, templatesOpen = false }
  end

  local T = hs.eventtap.event.types
  self.tap = hs.eventtap.new({
    T.leftMouseDown, T.leftMouseUp, T.leftMouseDragged, T.mouseMoved,
    T.rightMouseDown, T.rightMouseUp, T.otherMouseDown, T.otherMouseUp,
    T.scrollWheel, T.keyDown, T.keyUp,
  }, function(e) return self:_handle(e) end)
  self.tap:start()
  if not permissions.verifyTap(self.tap, "editor input") then
    self.tap = nil
    for _, v in ipairs(self.views) do v.canvas:delete() end
    self:_resetState()
    return
  end

  local hk = self.cfg.hotkey
  self.hotkeyCode = hk and hs.keycodes.map[hk.key] or nil

  self.isOpen = true
  if self.hooks.onOpen then self.hooks.onOpen() end

  self:_renderNow()
  for _, v in ipairs(self.views) do v.canvas:show(self.cfg.fadeIn) end

  if hs.eventtap.isSecureInputEnabled() then
    self:toast("Secure input is active: keyboard shortcuts are unavailable. Use the buttons.", 5)
  end
end

--- Close the editor. `saved` only informs the onClose hook.
function Editor:close(saved)
  if not self.isOpen then return end
  self.isOpen = false

  if self.tap then self.tap:stop(); self.tap = nil end
  if self.toastTimer then self.toastTimer:stop(); self.toastTimer = nil end
  if self.renderTimer then self.renderTimer:stop(); self.renderTimer = nil end
  for _, v in ipairs(self.views) do v.canvas:delete(self.cfg.fadeOut) end
  self:_resetState()

  if self.hooks.onClose then self.hooks.onClose(saved and true or false) end
end

--- Esc / hotkey: unwind the innermost state first, warn before discarding edits.
function Editor:requestClose()
  if not self.isOpen then return end
  if self.renaming then
    self.renaming = nil
  elseif self.gesture then
    self:_cancelGesture()
  elseif self:_anyTemplatesOpen() then
    for _, v in ipairs(self.views) do v.templatesOpen = false end
  elseif self.dirty and not self.discardArmed then
    self.discardArmed = true
    self:toast("Unsaved changes. Press ⏎ to save, or esc again to discard.", 3.5)
    return
  else
    self:close(false)
    return
  end
  self:_renderNow()
end

--- Display layout changed while editing: drop the session rather than draw garbage.
function Editor:onScreensChanged()
  if self.isOpen then
    hs.alert.show("Display configuration changed. Zone editor closed without saving.", 3)
    self:close(false)
  end
end

function Editor:_anyTemplatesOpen()
  for _, v in ipairs(self.views) do
    if v.templatesOpen then return true end
  end
  return false
end

---------------------------------------------------------------------------
-- Undo
---------------------------------------------------------------------------

function Editor:_snapshot()
  return {
    drafts = copyDrafts(self.drafts),
    order = copyList(self.order),
    assign = copyMap(self.assign),
    sel = self.sel and { id = self.sel.id, index = self.sel.index } or nil,
  }
end

function Editor:_pushUndo(snapshot)
  self.undo[#self.undo + 1] = snapshot or self:_snapshot()
  if #self.undo > MAX_UNDO then table.remove(self.undo, 1) end
  self.dirty = true
  self.discardArmed = false
end

function Editor:_undo()
  local snap = table.remove(self.undo)
  if not snap then
    self:toast("Nothing to undo", 1.5)
    return
  end
  self.drafts, self.order, self.assign, self.sel = snap.drafts, snap.order, snap.assign, snap.sel
  self.dirty = #self.undo > 0
  self.gesture, self.renaming = nil, nil
  self:toast("Undone", 1.2)
end

function Editor:_cancelGesture()
  local g = self.gesture
  if not g then return end
  local snap = g.snapshot
  self.drafts, self.order, self.assign, self.sel = snap.drafts, snap.order, snap.assign, snap.sel
  self.gesture = nil
end

---------------------------------------------------------------------------
-- Toast
---------------------------------------------------------------------------

function Editor:toast(text, seconds)
  self.toastText = text
  if self.toastTimer then self.toastTimer:stop() end
  self.toastTimer = hs.timer.doAfter(seconds or 2, function()
    self.toastTimer = nil
    self.toastText = nil
    self.discardArmed = false
    if self.isOpen then self:_renderNow() end
  end)
  if self.isOpen then self:_renderNow() end
end

---------------------------------------------------------------------------
-- Rendering
---------------------------------------------------------------------------

function Editor:_measure(v, text, size)
  local key = text
  local w = self.measureCache[key]
  if not w then
    local ok, s = pcall(function() return v.canvas:minimumTextSize(text) end)
    w = (ok and type(s) == "table" and s.w) or (#text * 13 * 0.58)
    self.measureCache[key] = w
  end
  return w * size / 13
end

function Editor:_renderNow()
  if not self.isOpen then return end
  self.lastRender = hs.timer.secondsSinceEpoch()

  for vi, v in ipairs(self.views) do
    local layoutId = self.assign[v.info.key]
    local draft = self.drafts[layoutId]
    local g = self.gesture
    local ctx = {
      info = v.info,
      zones = draft.zones,
      layoutName = draft.name,
      layoutIndex = indexOf(self.order, layoutId) or 1,
      layoutCount = #self.order,
      sel = (self.sel and self.sel.id == layoutId) and self.sel.index or nil,
      gesture = (g and g.view == vi) and { draft = g.kind == "draw" and g.draftRect or nil, guides = g.guides } or nil,
      hoverId = self.hoverId,
      pressedId = self.pressed and self.pressed.view == vi and self.pressed.id or nil,
      renaming = (self.renaming and self.renaming.view == vi) and self.renaming or nil,
      showTemplates = v.templatesOpen,
      templates = self.templates,
      toast = self.toastText,
      pal = self.pal,
      cfg = self.cfg,
      measure = function(text, size) return self:_measure(v, text, size) end,
    }
    local els, ui = view.build(ctx)
    v.canvas:replaceElements(els)
    v.ui = ui
  end
end

--- Coalesce bursts of events (drags, hovers) into at most ~60 renders per second.
function Editor:_render()
  if not self.isOpen then return end
  local now = hs.timer.secondsSinceEpoch()
  if now - self.lastRender >= RENDER_INTERVAL then
    self:_renderNow()
  elseif not self.renderTimer then
    self.renderTimer = hs.timer.doAfter(RENDER_INTERVAL, function()
      self.renderTimer = nil
      self:_renderNow()
    end)
  end
end

---------------------------------------------------------------------------
-- Hit testing
---------------------------------------------------------------------------

function Editor:_viewAt(pt)
  local infos = {}
  for i, v in ipairs(self.views) do infos[i] = v.info end
  local info = screens.pick(infos, pt)
  for i, v in ipairs(self.views) do
    if v.info == info then return i end
  end
  return nil
end

function Editor:_hitUI(vi, pt)
  local ui = self.views[vi].ui
  for i = #ui, 1, -1 do -- last drawn = top-most
    local it = ui[i]
    if pt.x >= it.x and pt.x <= it.x + it.w and pt.y >= it.y and pt.y <= it.y + it.h then
      return it
    end
  end
  return nil
end

--- The display the pointer is on (for keyboard actions that need a screen).
function Editor:_activeView()
  return self:_viewAt(hs.mouse.absolutePosition()) or 1
end

function Editor:_viewForLayout(layoutId)
  for i, v in ipairs(self.views) do
    if self.assign[v.info.key] == layoutId then return i end
  end
  return nil
end

---------------------------------------------------------------------------
-- Event tap
---------------------------------------------------------------------------

function Editor:_handle(e)
  local ok, result = pcall(self._dispatch, self, e)
  if not ok then
    log.e("editor error:", result)
    util.after(0, function() self:close(false) end) -- never leave the user trapped
    return true
  end
  return result
end

function Editor:_isHotkey(e)
  local hk = self.cfg.hotkey
  return hk and self.hotkeyCode and e:getKeyCode() == self.hotkeyCode
    and util.hasModifiers(e:getFlags(), hk.mods)
end

--- Returns true to swallow the event.
function Editor:_dispatch(e)
  local T = hs.eventtap.event.types
  local t = e:getType()

  if t == T.keyDown then
    return self:_onKey(e)
  elseif t == T.keyUp then
    return not self:_isHotkey(e)
  elseif t == T.leftMouseDown then
    self:_onDown(e)
  elseif t == T.leftMouseDragged then
    self:_onDrag(e)
  elseif t == T.leftMouseUp then
    self:_onUp(e)
  elseif t == T.mouseMoved then
    self:_onMove(e)
  end
  return true
end

---------------------------------------------------------------------------
-- Keyboard
---------------------------------------------------------------------------

function Editor:_onKey(e)
  if self:_isHotkey(e) then return false end -- let the global hotkey toggle us

  local map = hs.keycodes.map
  local code, flags = e:getKeyCode(), e:getFlags()
  local isEnter = code == map["return"] or code == map.padenter

  if self.renaming then
    self:_renameKey(e, code, flags, isEnter)
    return true
  end

  if code == map.escape then
    self:requestClose()
  elseif isEnter then
    self:save()
  elseif code == map.delete or code == map.forwarddelete then
    self:_deleteSelectedZone()
  elseif code == map.tab then
    self:_cycleSelection(flags.shift and -1 or 1)
  elseif code == map.z and flags.cmd then
    self:_undo()
    self:_renderNow()
  elseif code == map.n and not (flags.cmd or flags.ctrl or flags.alt) then
    self:_addZone(self:_activeView())
  elseif code == map.left or code == map.right or code == map.up or code == map.down then
    local dx = (code == map.left and -1) or (code == map.right and 1) or 0
    local dy = (code == map.up and -1) or (code == map.down and 1) or 0
    self:_nudge(dx, dy, flags.shift and 5 or 1)
  end
  return true
end

function Editor:_renameKey(e, code, flags, isEnter)
  local map = hs.keycodes.map
  local r = self.renaming
  if code == map.escape then
    self.renaming = nil
  elseif isEnter then
    self:_commitRename()
  elseif code == map.delete then
    r.text = dropLastChar(r.text)
  elseif not (flags.cmd or flags.ctrl) then
    local ch = e:getCharacters()
    if ch and ch ~= "" and not ch:find("%c") and (utf8.len(r.text .. ch) or 99) <= MAX_NAME_CHARS then
      r.text = r.text .. ch
    end
  end
  self:_renderNow()
end

function Editor:_commitRename()
  local r = self.renaming
  if not r then return end
  self.renaming = nil
  local name = trim(r.text)
  local draft = self.drafts[r.layoutId]
  if draft and name ~= "" and name ~= draft.name then
    self:_pushUndo()
    draft.name = name
  end
end

---------------------------------------------------------------------------
-- Mouse
---------------------------------------------------------------------------

function Editor:_snapContext(v, zones, skip)
  if not self.cfg.editor.edgeSnapPx or self.cfg.editor.edgeSnapPx <= 0 then return nil end
  local fr = v.info.frame
  return ops.candidates(zones, skip, self.cfg.editor.edgeSnapPx / fr.w, self.cfg.editor.edgeSnapPx / fr.h)
end

function Editor:_onMove(e)
  local pt = e:location()
  local vi = self:_viewAt(pt)
  local hit = vi and self:_hitUI(vi, pt)
  local id = (hit and hit.id ~= "panel") and hit.id or nil
  if id ~= self.hoverId then
    self.hoverId = id
    self:_render()
  end
end

function Editor:_onDown(e)
  local pt, flags = e:location(), e:getFlags()
  local vi = self:_viewAt(pt)
  if not vi then return end
  local v = self.views[vi]

  local hit = self:_hitUI(vi, pt)
  if self.renaming and not (hit and hit.id == "name" and self.renaming.view == vi) then
    self:_commitRename()
  end

  if hit then
    if hit.id ~= "panel" then self.pressed = { id = hit.id, view = vi } end
    self:_renderNow()
    return
  end

  self.discardArmed = false
  local layoutId = self.assign[v.info.key]
  local zones = self.drafts[layoutId].zones
  local fr = v.info.frame
  local nx, ny = geometry.pointToNorm(pt, fr)

  -- 1. handles/edges of the already-selected zone win
  if self.sel and self.sel.id == layoutId and zones[self.sel.index] then
    local r = geometry.zoneToRect(zones[self.sel.index], fr)
    local handle = ops.hitHandle(r, pt.x, pt.y, view.HANDLE_HIT, view.EDGE_BAND)
    if handle then
      self:_beginResize(vi, layoutId, self.sel.index, handle, flags)
      return
    end
  end

  -- 2. edges/corners of any other zone (selects it and starts resizing).
  --    Holding Shift skips this so a new zone can be drawn right next to an edge.
  for i = #zones, 1, -1 do
    if flags.shift then break end
    local r = geometry.zoneToRect(zones[i], fr)
    local handle = ops.hitHandle(r, pt.x, pt.y, view.HANDLE_HIT, view.EDGE_BAND)
    if handle then
      self:_beginResize(vi, layoutId, i, handle, flags)
      return
    end
  end

  -- 3. body of a zone: select + move (Shift forces drawing instead)
  if not flags.shift then
    for i = #zones, 1, -1 do
      local r = geometry.zoneToRect(zones[i], fr)
      if geometry.contains(r, pt.x, pt.y) then
        self.sel = { id = layoutId, index = i }
        self.gesture = {
          kind = "move", view = vi, layoutId = layoutId, index = i,
          origin = copyZone(zones[i]), startNorm = { x = nx, y = ny }, startPt = pt,
          armed = false, changed = false, snapshot = self:_snapshot(),
        }
        self:_renderNow()
        return
      end
    end
  end

  -- 4. empty space (or Shift): draw a new zone
  local snap = (not flags.alt) and self:_snapContext(v, zones, nil) or nil
  local sx, sy = ops.snapPoint(nx, ny, snap)
  self.gesture = {
    kind = "draw", view = vi, layoutId = layoutId, start = { x = sx, y = sy }, startPt = pt,
    draftRect = nil, snapshot = self:_snapshot(), changed = false,
  }
  self:_renderNow()
end

function Editor:_beginResize(vi, layoutId, index, handle, flags)
  local zones = self.drafts[layoutId].zones
  local snapZones = {}
  for i, z in ipairs(zones) do snapZones[i] = copyZone(z) end

  local linkX, linkY = {}, {}
  if not flags.alt then linkX, linkY = ops.findLinks(snapZones, index, handle) end

  self.sel = { id = layoutId, index = index }
  self.gesture = {
    kind = "resize", view = vi, layoutId = layoutId, index = index, handle = handle,
    origin = copyZone(zones[index]), zones = snapZones, linkX = linkX, linkY = linkY,
    changed = false, snapshot = self:_snapshot(),
  }
  self:_renderNow()
end

function Editor:_onDrag(e)
  local g = self.gesture
  if not g then return end
  local pt, flags = e:location(), e:getFlags()
  local v = self.views[g.view]
  local fr = v.info.frame
  local nx, ny = geometry.pointToNorm(pt, fr)
  local draft = self.drafts[g.layoutId]
  local zones = draft.zones
  local useSnap = not flags.alt

  if g.kind == "move" then
    if not g.armed then
      local dx, dy = pt.x - g.startPt.x, pt.y - g.startPt.y
      if dx * dx + dy * dy < DRAG_ARM_PX * DRAG_ARM_PX then return end
      g.armed = true
    end
    local snap = useSnap and self:_snapContext(v, zones, { [g.index] = true }) or nil
    local rect, guides = ops.moveRect(g.origin, nx - g.startNorm.x, ny - g.startNorm.y, snap)
    zones[g.index] = quant(rect)
    g.guides, g.changed = guides, true

  elseif g.kind == "resize" then
    local skip = { [g.index] = true }
    for _, lk in ipairs(g.linkX) do skip[lk.index] = true end
    for _, lk in ipairs(g.linkY) do skip[lk.index] = true end
    local snap = useSnap and self:_snapContext(v, zones, skip) or nil
    local rect, updates, guides = ops.resize(g.origin, g.handle, nx, ny, {
      snap = snap, zones = g.zones, linkX = g.linkX, linkY = g.linkY,
      minW = self.cfg.editor.minZonePx / fr.w, minH = self.cfg.editor.minZonePx / fr.h,
    })
    zones[g.index] = quant(rect)
    for j, u in pairs(updates) do zones[j] = quant(u) end
    g.guides, g.changed = guides, true

  elseif g.kind == "draw" then
    local snap = useSnap and self:_snapContext(v, zones, nil) or nil
    local sx, sy, gx, gy = ops.snapPoint(nx, ny, snap)
    g.draftRect = ops.rectFromPoints(g.start.x, g.start.y, sx, sy)
    g.guides = { x = gx, y = gy }
  end

  self:_render()
end

function Editor:_onUp(e)
  local pt = e:location()

  if self.pressed then
    local p = self.pressed
    self.pressed = nil
    local vi = self:_viewAt(pt)
    local hit = vi and self:_hitUI(vi, pt)
    if hit and hit.id == p.id and vi == p.view then
      self:_activate(p.id, vi)
    end
    self:_renderNow()
    return
  end

  local g = self.gesture
  if not g then return end
  self.gesture = nil
  local fr = self.views[g.view].info.frame

  if g.kind == "draw" then
    local r = g.draftRect
    local zones = self.drafts[g.layoutId].zones
    local travelled = math.sqrt((pt.x - g.startPt.x) ^ 2 + (pt.y - g.startPt.y) ^ 2)
    if r and r.w * fr.w >= self.cfg.editor.minZonePx and r.h * fr.h >= self.cfg.editor.minZonePx then
      self:_pushUndo(g.snapshot)
      zones[#zones + 1] = quant(r)
      self.sel = { id = g.layoutId, index = #zones }
    elseif travelled > CLICK_PX then
      self:toast(("Zone too small (minimum %d px)"):format(self.cfg.editor.minZonePx), 1.8)
    else
      self.sel = nil -- plain click on empty space
    end
  elseif g.changed then
    self:_pushUndo(g.snapshot)
  end

  g.guides = nil
  self:_renderNow()
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------

function Editor:_activate(id, vi)
  local v = self.views[vi]
  local layoutId = self.assign[v.info.key]
  local draft = self.drafts[layoutId]

  if id == "prev" or id == "next" then
    local n = #self.order
    local i = indexOf(self.order, layoutId) or 1
    local ni = id == "next" and (i % n) + 1 or ((i - 2) % n) + 1
    self:_pushUndo()
    self.assign[v.info.key] = self.order[ni]
    self.sel = nil

  elseif id == "name" then
    self.renaming = { view = vi, layoutId = layoutId, text = draft.name }

  elseif id == "addzone" then
    self:_addZone(vi)

  elseif id == "templates" then
    v.templatesOpen = not v.templatesOpen

  elseif id:sub(1, 4) == "tpl:" then
    local tid = id:sub(5)
    for _, t in ipairs(layouts.templates()) do
      if t.id == tid then
        self:_pushUndo()
        draft.zones = t.zones
        self.sel = nil
        v.templatesOpen = false
        self:toast(("Applied “%s”"):format(t.name), 1.5)
      end
    end

  elseif id == "newlayout" then
    local taken = {}
    for _, lid in ipairs(self.order) do taken[lid] = true end
    local n = #self.order + 1
    local name = "Layout " .. n
    local newId = layouts.uniqueId(name, taken)
    self:_pushUndo()
    self.drafts[newId] = { id = newId, name = name, zones = {} }
    self.order[#self.order + 1] = newId
    self.assign[v.info.key] = newId
    self.sel = nil
    v.templatesOpen = true
    self:toast("New layout: draw zones or pick a template", 2.5)

  elseif id == "deletelayout" then
    self:_deleteLayout(layoutId)

  elseif id == "delzone" then
    self:_deleteSelectedZone()

  elseif id == "cancel" then
    self:close(false)

  elseif id == "save" then
    self:save()
  end
end

function Editor:_addZone(vi)
  local v = self.views[vi]
  if not v then return end
  local layoutId = self.assign[v.info.key]
  local zones = self.drafts[layoutId].zones
  self:_pushUndo()
  zones[#zones + 1] = quant(ops.newZone(#zones))
  self.sel = { id = layoutId, index = #zones }
  self:_renderNow()
end

function Editor:_deleteSelectedZone()
  local s = self.sel
  if not s then return end
  local draft = self.drafts[s.id]
  if not draft or not draft.zones[s.index] then return end
  self:_pushUndo()
  table.remove(draft.zones, s.index)
  self.sel = nil
  self:_renderNow()
end

function Editor:_cycleSelection(dir)
  local vi = self:_activeView()
  local v = self.views[vi]
  local layoutId = self.assign[v.info.key]
  local n = #self.drafts[layoutId].zones
  if n == 0 then return end
  local cur = (self.sel and self.sel.id == layoutId) and self.sel.index or 0
  local nxt = ((cur - 1 + dir) % n) + 1
  self.sel = { id = layoutId, index = nxt }
  self:_renderNow()
end

function Editor:_nudge(dx, dy, mult)
  local s = self.sel
  if not s then return end
  local draft = self.drafts[s.id]
  local vi = self:_viewForLayout(s.id)
  if not (draft and draft.zones[s.index] and vi) then return end
  local fr = self.views[vi].info.frame

  local now = hs.timer.secondsSinceEpoch()
  if now - self.lastNudge > 0.6 then self:_pushUndo() end -- one undo step per burst
  self.lastNudge = now

  local px = self.cfg.editor.nudgePx * mult
  draft.zones[s.index] = quant(ops.nudge(draft.zones[s.index], dx * px / fr.w, dy * px / fr.h))
  self:_renderNow()
end

function Editor:_deleteLayout(layoutId)
  if #self.order <= 1 then
    self:toast("At least one layout is required", 2)
    return
  end
  local name = self.drafts[layoutId].name
  local idx = indexOf(self.order, layoutId)
  self:_pushUndo()
  table.remove(self.order, idx)
  self.drafts[layoutId] = nil
  local fallback = self.order[math.max(1, idx - 1)]
  for key, id in pairs(self.assign) do
    if id == layoutId then self.assign[key] = fallback end
  end
  self.sel = nil
  self:toast(("Deleted “%s” (⌘Z to undo)"):format(name), 2.5)
end

--- Validate and persist all drafts, then close.
function Editor:save()
  if not self.isOpen then return end
  if self.renaming then self:_commitRename() end

  local list = {}
  for _, id in ipairs(self.order) do
    local d = self.drafts[id]
    if #d.zones == 0 then
      self:toast(("“%s” has no zones. Draw one or delete the layout."):format(d.name), 3.5)
      return
    end
    list[#list + 1] = d
  end

  local ok, err = layouts.commit(list, self.assign)
  if not ok then
    log.e("save failed:", err)
    self:toast("Could not save: " .. tostring(err), 4)
    return
  end
  self:close(true)
end

return Editor
