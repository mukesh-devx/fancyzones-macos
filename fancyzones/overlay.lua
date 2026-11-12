--- Zone overlay shown while the user drags a window with the snap modifier held.
---
--- One transparent, click-through hs.canvas per display covers that screen and
--- draws its assigned layout. The zone under the pointer glows in the accent
--- colour; the highlight eases in and out via a short 60 Hz animation timer
--- that only runs while a transition is in flight.

local geometry = require("fancyzones.geometry")
local screens = require("fancyzones.screens")
local layouts = require("fancyzones.layouts")
local theme = require("fancyzones.theme")

local Overlay = {}
Overlay.__index = Overlay

local EASE = 0.38      -- fraction of the remaining distance covered per frame
local FRAME = 1 / 60

function Overlay.new(cfg, palette)
  return setmetatable({
    cfg = cfg,
    pal = palette,
    views = {},
    signature = nil,
    hover = nil,
    visible = false,
    animTimer = nil,
  }, Overlay)
end

---------------------------------------------------------------------------
-- View construction
---------------------------------------------------------------------------

function Overlay:_buildView(info, layout)
  local pal, cfg = self.pal, self.cfg
  local ox, oy = info.full.x, info.full.y

  local canvas = hs.canvas.new(info.full)
  canvas:level(hs.canvas.windowLevels.overlay)
  canvas:behavior({ "canJoinAllSpaces", "fullScreenAuxiliary" })
  -- No mouseCallback is set, so the canvas ignores the mouse and the window
  -- being dragged keeps receiving the drag.

  local els = {
    {
      id = "dim", type = "rectangle", action = "fill", fillColor = pal.overlayDim,
      frame = { x = info.frame.x - ox, y = info.frame.y - oy, w = info.frame.w, h = info.frame.h },
    },
  }

  local rects = {}
  for i, zone in ipairs(layout.zones) do
    local r = geometry.targetRect(zone, info.frame, cfg.spacing)
    rects[i] = r
    local lx, ly = r.x - ox, r.y - oy
    els[#els + 1] = {
      id = "zone" .. i, type = "rectangle", action = "strokeAndFill",
      frame = { x = lx + 1, y = ly + 1, w = math.max(r.w - 2, 1), h = math.max(r.h - 2, 1) },
      roundedRectRadii = { xRadius = pal.radius, yRadius = pal.radius },
      fillColor = pal.zoneFill, strokeColor = pal.zoneStroke, strokeWidth = 2,
    }
    local fs = geometry.clamp(math.min(r.w, r.h) * 0.26, 16, 56)
    local showNumber = cfg.showZoneNumbers and r.w >= 48 and r.h >= 48
    els[#els + 1] = {
      id = "label" .. i, type = "text", text = showNumber and tostring(i) or "",
      frame = { x = lx, y = ly + (r.h - fs * 1.25) / 2, w = r.w, h = fs * 1.25 },
      textAlignment = "center", textSize = fs, textFont = pal.font,
      textColor = pal.zoneText, textLineBreak = "clip",
    }
  end
  canvas:replaceElements(els)

  return { info = info, layout = layout, canvas = canvas, rects = rects, levels = {}, targets = {} }
end

function Overlay:_destroyViews()
  if self.animTimer then
    self.animTimer:stop()
    self.animTimer = nil
  end
  for _, v in ipairs(self.views) do v.canvas:delete() end
  self.views = {}
  self.signature = nil
  self.hover = nil
end

--- (Re)build canvases when displays or layouts changed since last time.
function Overlay:_ensureViews()
  local infos = screens.all()
  local sig = screens.signature(infos) .. "#" .. layouts.revision
  if sig == self.signature then return end

  self:_destroyViews()
  for _, info in ipairs(infos) do
    local layout = layouts.layoutFor(info.key)
    if layout then self.views[#self.views + 1] = self:_buildView(info, layout) end
  end
  self.signature = sig
end

---------------------------------------------------------------------------
-- Highlight animation
---------------------------------------------------------------------------

function Overlay:_applyLevel(view, i, t)
  local pal = self.pal
  local c = view.canvas
  local idx = 1 + (i - 1) * 2 + 1 -- element index of zone i (1 is the dim layer)
  c:elementAttribute(idx, "fillColor", theme.lerp(pal.zoneFill, pal.zoneFillHot, t))
  c:elementAttribute(idx, "strokeColor", theme.lerp(pal.zoneStroke, pal.zoneStrokeHot, t))
  c:elementAttribute(idx, "strokeWidth", 2 + 2 * t)
  c:elementAttribute(idx + 1, "textColor", theme.lerp(pal.zoneText, pal.zoneTextHot, t))
end

function Overlay:_tick()
  local busy = false
  for _, view in ipairs(self.views) do
    for i = 1, #view.layout.zones do
      local cur, tgt = view.levels[i] or 0, view.targets[i] or 0
      if cur ~= tgt then
        local nxt = cur + (tgt - cur) * EASE
        if math.abs(tgt - nxt) < 0.02 then nxt = tgt end
        view.levels[i] = nxt
        self:_applyLevel(view, i, nxt)
        if nxt ~= tgt then busy = true end
      end
    end
  end
  if not busy and self.animTimer then
    self.animTimer:stop()
    self.animTimer = nil
  end
end

function Overlay:_startAnim()
  if self.animTimer then return end
  self.animTimer = hs.timer.doEvery(FRAME, function() self:_tick() end)
end

function Overlay:_resetLevels()
  for _, view in ipairs(self.views) do
    for i = 1, #view.layout.zones do
      if (view.levels[i] or 0) ~= 0 then self:_applyLevel(view, i, 0) end
      view.levels[i], view.targets[i] = 0, 0
    end
  end
  self.hover = nil
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function Overlay:show()
  if self.visible then return end
  self:_ensureViews()
  self:_resetLevels()
  for _, v in ipairs(self.views) do v.canvas:show(self.cfg.fadeIn) end
  self.visible = true
end

function Overlay:hide()
  if not self.visible then return end
  self.visible = false
  for _, v in ipairs(self.views) do v.canvas:hide(self.cfg.fadeOut) end
  self.hover = nil
end

function Overlay:isVisible() return self.visible end

local function setHover(self, view, index)
  local cur = self.hover
  if cur and view and cur.view == view and cur.index == index then return end
  if not cur and not view then return end

  if cur then cur.view.targets[cur.index] = 0 end
  if view then
    view.targets[index] = 1
    self.hover = { view = view, index = index, rect = view.rects[index], screen = view.info.screen }
  else
    self.hover = nil
  end
  self:_startAnim()
end

--- Highlight the zone under `pt` (absolute coordinates). Returns the hovered
--- target `{ rect = <absolute window rect>, screen = hs.screen, index = n }` or nil.
function Overlay:update(pt)
  if not self.visible or #self.views == 0 then return nil end

  local infos = {}
  for i, v in ipairs(self.views) do infos[i] = v.info end
  local info = screens.pick(infos, pt)
  local view
  for _, v in ipairs(self.views) do
    if v.info == info then view = v end
  end

  local index
  if view then
    -- The pointer may be over the menu bar / Dock while grabbing a title bar;
    -- clamping into the usable frame keeps edge zones easy to hit.
    local nx, ny = geometry.pointToNorm(pt, view.info.frame)
    index = geometry.zoneAt(view.layout.zones, nx, ny)
  end
  setHover(self, index and view or nil, index)
  return self.hover
end

--- Currently highlighted target (see update) or nil.
function Overlay:target() return self.hover end

--- Tear everything down immediately (stop / reload / display change).
function Overlay:destroy()
  self.visible = false
  self:_destroyViews()
end

return Overlay
