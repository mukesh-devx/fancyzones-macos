--- Menu bar icon, drawn with hs.canvas and handed to macOS as a *template*
--- image: macOS only uses its alpha channel and tints it itself, so the icon is
--- always right on light and dark menu bars (and when the bar is tinted).
---
--- Glyph: a screen split into one tall zone and two small ones.
---   snapping on  -> solid shapes
---   snapping off -> outlines only (readable at a glance, clearly "paused")

local M = {}

local SCALE = 4            -- drawn 4x, then shrunk, so it stays crisp on Retina
local W, H = 22, 18        -- menu bar icon size in points

-- {x, y, w, h, fill alpha when on}  (points, relative to the glyph origin)
local SHAPES = {
  { 0, 0, 9, 15, 1.0 },
  { 10.5, 0, 9.5, 7, 0.55 },
  { 10.5, 8, 9.5, 7, 0.55 },
}
local ORIGIN_X, ORIGIN_Y = 1, 1.5
local RADIUS = 2.2
local OUTLINE = 1.3

local cache = {}

local function black(alpha) return { red = 0, green = 0, blue = 0, alpha = alpha } end

local function render(enabled)
  local canvas = hs.canvas.new({ x = 0, y = 0, w = W * SCALE, h = H * SCALE })
  if not canvas then return nil end

  for _, s in ipairs(SHAPES) do
    local x, y, w, h, alpha = s[1] + ORIGIN_X, s[2] + ORIGIN_Y, s[3], s[4], s[5]
    local el = {
      type = "rectangle",
      roundedRectRadii = { xRadius = RADIUS * SCALE, yRadius = RADIUS * SCALE },
    }
    if enabled then
      el.action = "fill"
      el.fillColor = black(alpha)
      el.frame = { x = x * SCALE, y = y * SCALE, w = w * SCALE, h = h * SCALE }
    else
      -- keep the stroke inside the same footprint as the solid version
      local inset = OUTLINE / 2
      el.action = "stroke"
      el.strokeColor = black(0.8)
      el.strokeWidth = OUTLINE * SCALE
      el.frame = {
        x = (x + inset) * SCALE, y = (y + inset) * SCALE,
        w = (w - OUTLINE) * SCALE, h = (h - OUTLINE) * SCALE,
      }
    end
    canvas:insertElement(el)
  end

  local image = canvas:imageFromCanvas()
  canvas:delete()
  if not image then return nil end
  image:size({ w = W, h = H }) -- point size; the bitmap keeps its 4x detail
  image:template(true)
  return image
end

--- The menu bar image for the given state, or nil if it could not be drawn.
function M.get(enabled)
  local key = enabled and "on" or "off"
  if cache[key] == nil then cache[key] = render(enabled) or false end
  return cache[key] or nil
end

return M
