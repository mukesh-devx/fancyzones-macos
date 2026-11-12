--- Colour palette derived from the user theme config.
---
--- hs.canvas colours are tables {red, green, blue, alpha}. We convert hex
--- strings ourselves so we do not depend on optional colour-parsing features.

local M = {}

local function hexToRGB(hex)
  local r, g, b = tostring(hex):match("^#?(%x%x)(%x%x)(%x%x)$")
  if not r then return 0.04, 0.52, 1.0 end -- fall back to macOS blue
  return tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255
end

--- Build a colour table from a hex string (or {r,g,b} 0..1) and alpha.
function M.color(hex, alpha)
  local r, g, b = hexToRGB(hex)
  return { red = r, green = g, blue = b, alpha = alpha or 1 }
end

function M.withAlpha(c, a)
  return { red = c.red, green = c.green, blue = c.blue, alpha = a }
end

--- Linear interpolation between two colour tables.
function M.lerp(a, b, t)
  return {
    red = a.red + (b.red - a.red) * t,
    green = a.green + (b.green - a.green) * t,
    blue = a.blue + (b.blue - a.blue) * t,
    alpha = a.alpha + (b.alpha - a.alpha) * t,
  }
end

--- Build the palette used by the overlay and the editor.
function M.build(t)
  local accent = M.color(t.accent, 1)
  local danger = M.color(t.danger, 1)
  local white = M.color("#FFFFFF", 1)
  local black = M.color("#000000", 1)
  local panel = M.color(t.panel, 0.94)

  return {
    font = t.font,
    radius = t.cornerRadius,

    accent = accent,
    danger = danger,
    white = white,
    black = black,

    -- Snap overlay (shown while dragging a window)
    overlayDim = M.withAlpha(black, t.overlayDim),
    zoneFill = M.withAlpha(white, 0.10),
    zoneStroke = M.withAlpha(white, 0.50),
    zoneText = M.withAlpha(white, 0.80),
    zoneFillHot = M.withAlpha(accent, 0.42),
    zoneStrokeHot = M.withAlpha(accent, 1.0),
    zoneTextHot = M.withAlpha(white, 1.0),

    -- Editor
    editorDim = M.withAlpha(black, t.editorDim),
    editorBounds = M.withAlpha(white, 0.18),
    editZoneFill = M.withAlpha(accent, 0.16),
    editZoneStroke = M.withAlpha(accent, 0.85),
    editZoneFillSel = M.withAlpha(accent, 0.30),
    editZoneStrokeSel = M.withAlpha(white, 0.95),
    editText = M.withAlpha(white, 0.92),
    editTextDim = M.withAlpha(white, 0.55),
    guide = M.withAlpha(accent, 0.95),
    handleFill = white,
    handleStroke = accent,
    draftFill = M.withAlpha(accent, 0.14),
    draftStroke = M.withAlpha(accent, 0.9),

    panel = panel,
    panelStroke = M.withAlpha(white, 0.10),
    button = M.withAlpha(white, 0.08),
    buttonHover = M.withAlpha(white, 0.18),
    buttonPressed = M.withAlpha(white, 0.28),
    buttonPrimary = accent,
    buttonPrimaryHover = M.lerp(accent, white, 0.18),
    buttonDanger = M.withAlpha(danger, 0.22),
    buttonDangerHover = M.withAlpha(danger, 0.45),
    separator = M.withAlpha(white, 0.14),

    toastFill = M.withAlpha(black, 0.78),
    previewStroke = M.withAlpha(white, 0.35),
  }
end

return M
