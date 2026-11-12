--- Menu bar item: open the editor, toggle snapping, pick a layout per display.

local screens = require("fancyzones.screens")
local layouts = require("fancyzones.layouts")
local permissions = require("fancyzones.permissions")
local icon = require("fancyzones.icon")

local Menubar = {}
Menubar.__index = Menubar

local SYMBOLS = { alt = "⌥", cmd = "⌘", ctrl = "⌃", shift = "⇧" }
local ORDER = { "ctrl", "alt", "shift", "cmd" }

--- "⌥Z" style label for a hotkey/modifier list.
local function label(mods, key)
  local set, out = {}, {}
  for _, m in ipairs(mods) do set[m] = true end
  for _, m in ipairs(ORDER) do
    if set[m] then out[#out + 1] = SYMBOLS[m] end
  end
  return table.concat(out) .. (key and key:upper() or "")
end

--- ctrl = { cfg, openEditor(), isSnapping(), setSnapping(flag), reload() }
function Menubar.new(ctrl)
  local self = setmetatable({ ctrl = ctrl }, Menubar)
  self.item = hs.menubar.new(true, "fancyzones")
  if not self.item then return nil end
  self.item:setMenu(function() return self:_build() end)
  self:refresh()
  return self
end

--- Redraw the icon/tooltip to match the snapping state.
function Menubar:refresh()
  if not self.item then return end
  local on = self.ctrl.isSnapping()
  local image = icon.get(on)
  if image then
    self.item:setTitle(nil)
    self.item:setIcon(image, true) -- template: follows light/dark menu bar
  else
    self.item:setTitle(on and "FZ" or "fz") -- icon could not be drawn: plain text fallback
  end
  self.item:setTooltip(on and "FancyZones: snapping on" or "FancyZones: snapping off")
end

function Menubar:_layoutItems(info)
  local current = layouts.layoutFor(info.key)
  local items = {}
  for _, l in ipairs(layouts.list()) do
    items[#items + 1] = {
      title = l.name,
      checked = current and current.id == l.id,
      fn = function() layouts.assign(info.key, l.id) end,
    }
  end
  return items
end

function Menubar:_build()
  local cfg = self.ctrl.cfg
  local items = {}

  local editTitle = "Edit Zones…"
  if cfg.hotkey then editTitle = editTitle .. "   " .. label(cfg.hotkey.mods, cfg.hotkey.key) end
  items[#items + 1] = { title = editTitle, fn = self.ctrl.openEditor }

  items[#items + 1] = {
    title = "Snap windows while dragging with " .. label(cfg.snapModifiers),
    checked = self.ctrl.isSnapping(),
    fn = function() self.ctrl.setSnapping(not self.ctrl.isSnapping()) end,
  }
  items[#items + 1] = { title = "-" }

  local infos = screens.all()
  if #infos == 1 then
    items[#items + 1] = { title = "Layout", disabled = true }
    for _, it in ipairs(self:_layoutItems(infos[1])) do items[#items + 1] = it end
  else
    for _, info in ipairs(infos) do
      items[#items + 1] = { title = "Layout: " .. info.name, menu = self:_layoutItems(info) }
    end
  end

  items[#items + 1] = { title = "-" }
  if not permissions.isGranted() then
    items[#items + 1] = { title = "⚠︎ Grant Accessibility access…", fn = permissions.openSettings }
  end
  items[#items + 1] = { title = "Open layouts folder", fn = function() hs.open(self.ctrl.cfg.dataDir) end }
  items[#items + 1] = { title = "Reload Hammerspoon config", fn = self.ctrl.reload }
  return items
end

function Menubar:delete()
  if self.item then
    self.item:delete()
    self.item = nil
  end
end

return Menubar
