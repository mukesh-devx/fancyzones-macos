--- Default configuration and deep-merge of user overrides.
---
--- Override anything by passing a table to `require("fancyzones").start{...}`.
--- Only the keys you pass are changed; everything else keeps its default.

local M = {}

--- hs.settings key where the gap chosen in the editor is remembered.
M.SPACING_SETTING = "fancyzones.spacing"
M.MAX_SPACING = 48
M.SPACING_STEP = 2

function M.defaults()
  return {
    -- Hotkey that opens/closes the zone editor.
    hotkey = { mods = { "alt" }, key = "z" },

    -- Modifier(s) that must be held while dragging a window to show the zones.
    -- Any combination of "shift", "alt", "ctrl", "cmd". Extra modifiers are tolerated.
    snapModifiers = { "shift" },

    -- Gap between snapped windows / screen edges, in points.
    spacing = 8,

    -- Seconds the window takes to glide into its zone (0 = instant).
    animationDuration = 0.14,

    -- Seconds for overlay fade in / out.
    fadeIn = 0.10,
    fadeOut = 0.12,

    -- Pointer travel (points) before a drag is classified as a window move.
    dragThreshold = 4,

    -- Draw zone numbers on the overlays.
    showZoneNumbers = true,

    -- Show a menu bar item (layout switcher, snapping toggle, ...).
    menubar = true,

    -- Bundle IDs whose windows must never be snapped, e.g. { "com.apple.finder" }.
    excludedApps = {},

    -- Where layouts.json is stored.
    dataDir = nil, -- resolved to <hs.configdir>/fancyzones-data when nil

    -- Zone editor behaviour.
    editor = {
      edgeSnapPx = 10,   -- magnetism to other zone edges / screen edges, in points
      minZonePx = 56,    -- smallest zone the editor will create or resize to
      nudgePx = 4,       -- arrow-key nudge (hold Shift for x5)
    },

    -- Colours are "#RRGGBB" strings. Alpha values are 0..1.
    theme = {
      accent = "#0A84FF",
      danger = "#FF453A",
      panel = "#1C1C1E",
      font = ".AppleSystemUIFont",
      overlayDim = 0.10,      -- subtle dimming while dragging a window
      editorDim = 0.55,       -- backdrop while editing
      cornerRadius = 10,
    },

    -- "debug", "info", "warning", "error"
    logLevel = "info",
  }
end

local function isArray(t)
  if type(t) ~= "table" then return false end
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n == #t
end

--- Recursively merge `over` into a copy of `base`. Arrays are replaced, not merged.
function M.merge(base, over)
  if type(over) ~= "table" then return base end
  local out = {}
  for k, v in pairs(base) do out[k] = v end
  for k, v in pairs(over) do
    if type(v) == "table" and type(out[k]) == "table" and not isArray(v) and not isArray(out[k]) then
      out[k] = M.merge(out[k], v)
    else
      out[k] = v
    end
  end
  return out
end

local MOD_ALIASES = {
  alt = "alt", option = "alt", opt = "alt", ["⌥"] = "alt",
  cmd = "cmd", command = "cmd", ["⌘"] = "cmd",
  ctrl = "ctrl", control = "ctrl", ["⌃"] = "ctrl",
  shift = "shift", ["⇧"] = "shift",
}

--- Canonical modifier names (alt/cmd/ctrl/shift). Returns the list, or nil + the bad name.
function M.normalizeMods(list)
  local out = {}
  for _, m in ipairs(list) do
    local canon = MOD_ALIASES[tostring(m):lower()]
    if not canon then return nil, tostring(m) end
    out[#out + 1] = canon
  end
  return out
end

--- Validate the merged config and fix obviously wrong values (with a warning list).
function M.validate(cfg)
  local warnings = {}
  local function warn(msg) warnings[#warnings + 1] = msg end

  if type(cfg.hotkey) ~= "table" or type(cfg.hotkey.key) ~= "string" or type(cfg.hotkey.mods) ~= "table" then
    warn("hotkey is invalid; hotkey disabled")
    cfg.hotkey = nil
  else
    local mods, bad = M.normalizeMods(cfg.hotkey.mods)
    if mods then
      cfg.hotkey = { mods = mods, key = cfg.hotkey.key }
    else
      warn("unknown hotkey modifier '" .. bad .. "'; hotkey disabled")
      cfg.hotkey = nil
    end
  end

  local snapMods, badSnap
  if type(cfg.snapModifiers) == "table" and #cfg.snapModifiers > 0 then
    snapMods, badSnap = M.normalizeMods(cfg.snapModifiers)
  end
  if snapMods then
    cfg.snapModifiers = snapMods
  else
    warn("snapModifiers must be a non-empty list of shift/alt/ctrl/cmd" ..
      (badSnap and (" (unknown '" .. badSnap .. "')") or "") .. "; using { \"shift\" }")
    cfg.snapModifiers = { "shift" }
  end

  for _, key in ipairs({ "spacing", "animationDuration", "fadeIn", "fadeOut", "dragThreshold" }) do
    if type(cfg[key]) ~= "number" or cfg[key] < 0 then
      warn(key .. " must be a number >= 0; using default")
      cfg[key] = M.defaults()[key]
    end
  end
  if cfg.spacing > M.MAX_SPACING then
    warn("spacing is limited to " .. M.MAX_SPACING)
    cfg.spacing = M.MAX_SPACING
  end
  return cfg, warnings
end

return M
