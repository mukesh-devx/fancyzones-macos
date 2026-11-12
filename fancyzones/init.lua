--- FancyZones for macOS (Hammerspoon)
---
--- Usage in ~/.hammerspoon/init.lua:
---
---   local fz = require("fancyzones")
---   fz.start()                        -- defaults
---   -- or: fz.start{ spacing = 12, snapModifiers = {"shift", "alt"} }
---
--- Public API:
---   fz.start(config)            start (or restart) with optional overrides
---   fz.stop()                   tear everything down
---   fz.openEditor() / fz.closeEditor() / fz.toggleEditor()
---   fz.setSnappingEnabled(bool) / fz.isSnappingEnabled()
---   fz.setLayout(layoutId[, hs.screen])   pick a layout for a display
---   fz.layouts                  the layout store (list(), get(), ...)

local config = require("fancyzones.config")
local theme = require("fancyzones.theme")
local log = require("fancyzones.log")
local layouts = require("fancyzones.layouts")
local permissions = require("fancyzones.permissions")
local windows = require("fancyzones.windows")
local screens = require("fancyzones.screens")
local util = require("fancyzones.util")
local Overlay = require("fancyzones.overlay")
local Snapper = require("fancyzones.snapper")
local Editor = require("fancyzones.editor")
local Menubar = require("fancyzones.menubar")

local M = { version = "1.0.0", layouts = layouts }

local SETTING_ENABLED = "fancyzones.snappingEnabled"

-- Everything that must stay referenced (timers, taps, canvases, menubar) lives
-- here; Hammerspoon objects stop working if they get garbage collected.
local state = {}

function M.isRunning() return state.running == true end

function M.start(userConfig)
  if state.running then M.stop() end

  local cfg, warnings = config.validate(config.merge(config.defaults(), userConfig or {}))
  cfg.dataDir = cfg.dataDir or (hs.configdir .. "/fancyzones-data")
  log.setLevel(cfg.logLevel)
  for _, w in ipairs(warnings) do log.w("config:", w) end
  if #warnings > 0 then hs.alert.show("FancyZones config: " .. warnings[1], 6) end

  local loaded, loadMsg = layouts.init(cfg.dataDir)
  if loaded == false and loadMsg then hs.alert.show(loadMsg, 6) end

  windows.setExcludedApps(cfg.excludedApps)
  local palette = theme.build(cfg.theme)

  local overlay = Overlay.new(cfg, palette)
  local snapper = Snapper.new(cfg, overlay)
  local editor = Editor.new(cfg, palette, {
    onOpen = function() snapper:suspend() end,
    onClose = function() snapper:resume() end,
  })

  if hs.settings.get(SETTING_ENABLED) == false then snapper:setEnabled(false) end

  state = { running = true, cfg = cfg, overlay = overlay, snapper = snapper, editor = editor }

  if cfg.hotkey then
    state.hotkey = hs.hotkey.bind(cfg.hotkey.mods, cfg.hotkey.key, function() editor:toggle() end)
  end

  -- Displays added/removed/rearranged: drop cached canvases and any drag in progress.
  state.screenWatcher = hs.screen.watcher.new(function()
    editor:onScreensChanged()
    snapper:cancel()
    overlay:destroy()
  end)
  state.screenWatcher:start()

  if cfg.menubar then
    state.menubar = Menubar.new({
      cfg = cfg,
      openEditor = function() editor:open() end,
      isSnapping = function() return snapper:isEnabled() end,
      setSnapping = M.setSnappingEnabled,
      reload = hs.reload,
    })
  end

  -- Taps only work once Accessibility is granted; wait for it if needed.
  permissions.ensure(function() snapper:start() end)

  log.i("FancyZones", M.version, "started")
  return M
end

function M.stop()
  if not state.running then return end
  permissions.cancel()
  if state.hotkey then state.hotkey:delete() end
  if state.screenWatcher then state.screenWatcher:stop() end
  if state.editor then state.editor:close(false) end
  if state.snapper then state.snapper:stop() end
  if state.overlay then state.overlay:destroy() end
  if state.menubar then state.menubar:delete() end
  util.cancelAll()
  state = {}
  log.i("FancyZones stopped")
end

function M.openEditor() if state.editor then state.editor:open() end end
function M.closeEditor() if state.editor then state.editor:close(false) end end
function M.toggleEditor() if state.editor then state.editor:toggle() end end

function M.isSnappingEnabled()
  return state.snapper ~= nil and state.snapper:isEnabled()
end

function M.setSnappingEnabled(flag)
  if not state.snapper then return end
  flag = flag and true or false
  state.snapper:setEnabled(flag)
  hs.settings.set(SETTING_ENABLED, flag)
  hs.alert.show(flag and "FancyZones snapping on" or "FancyZones snapping off", 1)
end

--- Use layout `layoutId` on `screen` (default: the display under the pointer).
function M.setLayout(layoutId, screen)
  screen = screen or hs.mouse.getCurrentScreen()
  if not screen then return false end
  return layouts.assign(screens.key(screen), layoutId)
end

return M
