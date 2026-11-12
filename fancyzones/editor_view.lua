--- Zone editor rendering: turns editor state into hs.canvas elements plus a list
--- of clickable regions (`ui`). Pure function of its input, no side effects, so
--- what is drawn and what is hit-tested can never drift apart.

local geometry = require("fancyzones.geometry")
local ops = require("fancyzones.editor_ops")

local M = {}

M.PANEL_Y = 14        -- toolbar distance from the top of the usable area
M.BUTTON_H = 32
M.PANEL_PAD = 10
M.HANDLE_R = 6        -- drawn handle radius
M.HANDLE_HIT = 10     -- handle hit tolerance
M.EDGE_BAND = 6       -- edge grab band
M.CHIP_R = 11         -- delete-chip radius

local TEXT = 13

local function rounded(r) return { xRadius = r, yRadius = r } end

--- Build everything one display's canvas needs.
--- ctx = {
---   info        screens.info of this display
---   zones       list of normalized zones of the layout shown here
---   layoutName  string
---   layoutIndex, layoutCount
---   sel         selected zone index or nil
---   gesture     nil | { draft = <normalized rect|nil>, guides = {x=,y=} }
---   hoverId, pressedId   ids from `ui`
---   renaming    nil | { text = "..." }
---   showTemplates bool,  templates = { {id, name}, ... }
---   toast       nil | string
---   pal, cfg    palette and config
---   measure     function(text, size) -> width
--- }
--- Returns elements (array), ui (array of {id, x, y, w, h} in absolute coords).
function M.build(ctx)
  local pal, info = ctx.pal, ctx.info
  local ox, oy = info.full.x, info.full.y
  local fr = info.frame
  local els, ui = {}, {}

  local function add(e) els[#els + 1] = e end

  -- absolute rect -> canvas-local frame
  local function lf(x, y, w, h) return { x = x - ox, y = y - oy, w = w, h = h } end

  local function text(str, x, y, w, size, color, align, h)
    h = h or size * 1.3
    add({
      type = "text", text = str, frame = lf(x, y, w, h),
      textAlignment = align or "center", textSize = size, textFont = pal.font,
      textColor = color, textLineBreak = "clip",
    })
  end

  -- 1. backdrop + usable-area outline ------------------------------------
  add({ type = "rectangle", action = "fill", fillColor = pal.editorDim,
        frame = { x = 0, y = 0, w = info.full.w, h = info.full.h } })
  add({ type = "rectangle", action = "stroke", strokeColor = pal.editorBounds, strokeWidth = 1,
        strokeDashPattern = { 6, 6 }, roundedRectRadii = rounded(4),
        frame = lf(fr.x + 0.5, fr.y + 0.5, fr.w - 1, fr.h - 1) })
  text(info.name, fr.x + 16, fr.y + 22, 300, 11, pal.editTextDim, "left")

  if #ctx.zones == 0 then
    text("Drag anywhere to draw a zone", fr.x, fr.y + fr.h / 2 - 16, fr.w, 22, pal.editTextDim)
  end

  -- 2. zones -------------------------------------------------------------
  local function drawZone(i, z, selected)
    local r = geometry.zoneToRect(z, fr)
    add({
      type = "rectangle", action = "strokeAndFill",
      frame = lf(r.x + 1, r.y + 1, math.max(r.w - 2, 1), math.max(r.h - 2, 1)),
      roundedRectRadii = rounded(6),
      fillColor = selected and pal.editZoneFillSel or pal.editZoneFill,
      strokeColor = selected and pal.editZoneStrokeSel or pal.editZoneStroke,
      strokeWidth = selected and 3 or 2,
    })
    if r.w >= 44 and r.h >= 40 then
      local fs = geometry.clamp(math.min(r.w, r.h) * 0.22, 14, 40)
      text(tostring(i), r.x, r.y + r.h / 2 - fs * 0.85, r.w, fs, pal.editText)
      if r.w >= 90 and r.h >= 70 then
        text(string.format("%d × %d", geometry.round(r.w), geometry.round(r.h)),
          r.x, r.y + r.h / 2 + fs * 0.55, r.w, 11, pal.editTextDim)
      end
    end
    return r
  end

  for i, z in ipairs(ctx.zones) do
    if i ~= ctx.sel then drawZone(i, z, false) end
  end

  -- selected zone on top, with handles and delete chip
  local selRect
  if ctx.sel and ctx.zones[ctx.sel] then
    selRect = drawZone(ctx.sel, ctx.zones[ctx.sel], true)

    local pts = ops.handlePoints(selRect)
    for _, name in ipairs(ops.HANDLE_ORDER) do
      local p = pts[name]
      add({
        type = "rectangle", action = "strokeAndFill", roundedRectRadii = rounded(M.HANDLE_R),
        frame = lf(p.x - M.HANDLE_R, p.y - M.HANDLE_R, M.HANDLE_R * 2, M.HANDLE_R * 2),
        fillColor = pal.handleFill, strokeColor = pal.handleStroke, strokeWidth = 2,
      })
    end

    local cx, cy = selRect.x + selRect.w - 20, selRect.y + 20
    local hot = ctx.hoverId == "delzone"
    add({
      type = "rectangle", action = "fill", roundedRectRadii = rounded(M.CHIP_R),
      frame = lf(cx - M.CHIP_R, cy - M.CHIP_R, M.CHIP_R * 2, M.CHIP_R * 2),
      fillColor = hot and pal.danger or { red = pal.danger.red, green = pal.danger.green, blue = pal.danger.blue, alpha = 0.8 },
    })
    text("×", cx - M.CHIP_R, cy - M.CHIP_R + 1, M.CHIP_R * 2, 16, pal.white, "center", 18)
    ui[#ui + 1] = { id = "delzone", x = cx - 14, y = cy - 14, w = 28, h = 28 }
  end

  -- 3. in-progress draw preview and snap guides ---------------------------
  local g = ctx.gesture
  if g and g.draft then
    local r = geometry.zoneToRect(g.draft, fr)
    add({
      type = "rectangle", action = "strokeAndFill", roundedRectRadii = rounded(6),
      frame = lf(r.x, r.y, r.w, r.h), fillColor = pal.draftFill,
      strokeColor = pal.draftStroke, strokeWidth = 2, strokeDashPattern = { 8, 6 },
    })
    text(string.format("%d × %d", geometry.round(r.w), geometry.round(r.h)),
      r.x, r.y + r.h / 2 - 8, r.w, 13, pal.editText)
  end
  if g and g.guides then
    if g.guides.x then
      local gx = fr.x + g.guides.x * fr.w
      add({ type = "segments", action = "stroke", strokeColor = pal.guide, strokeWidth = 1,
            coordinates = { { x = gx - ox, y = fr.y - oy }, { x = gx - ox, y = fr.y + fr.h - oy } } })
    end
    if g.guides.y then
      local gy = fr.y + g.guides.y * fr.h
      add({ type = "segments", action = "stroke", strokeColor = pal.guide, strokeWidth = 1,
            coordinates = { { x = fr.x - ox, y = gy - oy }, { x = fr.x + fr.w - ox, y = gy - oy } } })
    end
  end

  -- 4. toolbar ----------------------------------------------------------
  local function measure(str, size)
    return ctx.measure(str, size)
  end

  local function buttonWidth(label, minW)
    return math.max(minW or 56, math.ceil(measure(label, TEXT)) + 28)
  end

  local items = {}
  local nameLabel = ctx.renaming and (ctx.renaming.text .. "▏") or ctx.layoutName
  items[#items + 1] = { id = "prev", label = "‹", w = 34, disabled = ctx.layoutCount < 2 }
  items[#items + 1] = {
    id = "name", label = nameLabel, kind = ctx.renaming and "field" or "name",
    w = geometry.clamp(math.ceil(measure(nameLabel, TEXT)) + 40, 150, 300),
  }
  items[#items + 1] = { id = "next", label = "›", w = 34, disabled = ctx.layoutCount < 2 }
  items[#items + 1] = { sep = true }
  items[#items + 1] = { id = "addzone", label = "+ Zone", w = buttonWidth("+ Zone") }
  items[#items + 1] = { id = "templates", label = "Templates", w = buttonWidth("Templates"), active = ctx.showTemplates }
  items[#items + 1] = { id = "newlayout", label = "New layout", w = buttonWidth("New layout") }
  items[#items + 1] = { id = "deletelayout", label = "Delete layout", kind = "danger", w = buttonWidth("Delete layout") }
  items[#items + 1] = { sep = true }
  items[#items + 1] = { id = "cancel", label = "Cancel", w = buttonWidth("Cancel") }
  items[#items + 1] = { id = "save", label = "Save", kind = "primary", w = buttonWidth("Save", 64) }

  local GAP = 6
  local totalW = M.PANEL_PAD * 2 - GAP
  for _, it in ipairs(items) do totalW = totalW + (it.sep and 13 or it.w) + GAP end
  local panelH = M.BUTTON_H + M.PANEL_PAD * 2
  local panelX = fr.x + (fr.w - totalW) / 2
  local panelY = fr.y + M.PANEL_Y

  local function drawPanel(x, y, w, h)
    add({
      type = "rectangle", action = "strokeAndFill", roundedRectRadii = rounded(14),
      frame = lf(x, y, w, h), fillColor = pal.panel, strokeColor = pal.panelStroke, strokeWidth = 1,
      withShadow = true,
      shadow = { blurRadius = 26, color = { alpha = 0.45 }, offset = { h = -8, w = 0 } },
    })
    ui[#ui + 1] = { id = "panel", x = x, y = y, w = w, h = h }
  end

  local function drawButton(it, x, y, h)
    local hovered = ctx.hoverId == it.id and not it.disabled
    local pressed = ctx.pressedId == it.id and hovered
    local fill, color = pal.button, pal.editText
    if it.kind == "primary" then
      fill = hovered and pal.buttonPrimaryHover or pal.buttonPrimary
      color = pal.white
    elseif it.kind == "danger" then
      fill = hovered and pal.buttonDangerHover or pal.buttonDanger
    elseif it.kind == "field" then
      fill = { red = 0, green = 0, blue = 0, alpha = 0.35 }
    elseif hovered or it.active then
      fill = pal.buttonHover
    end
    if pressed then fill = pal.buttonPressed end
    if it.disabled then color = pal.editTextDim end

    add({
      type = "rectangle", action = it.kind == "field" and "strokeAndFill" or "fill",
      roundedRectRadii = rounded(8), frame = lf(x, y, it.w, h), fillColor = fill,
      strokeColor = pal.accent, strokeWidth = 1.5,
    })
    local size = (it.id == "prev" or it.id == "next") and 20 or TEXT
    local th = size * 1.3
    text(it.label, x, y + (h - th) / 2 - (size == 20 and 2 or 0), it.w, size, color, "center", th)
    if not it.disabled then ui[#ui + 1] = { id = it.id, x = x, y = y, w = it.w, h = h } end
  end

  drawPanel(panelX, panelY, totalW, panelH)
  local cx = panelX + M.PANEL_PAD
  for _, it in ipairs(items) do
    if it.sep then
      add({ type = "segments", action = "stroke", strokeColor = pal.separator, strokeWidth = 1,
            coordinates = { { x = cx + 6 - ox, y = panelY + 12 - oy }, { x = cx + 6 - ox, y = panelY + panelH - 12 - oy } } })
      cx = cx + 13 + GAP
    else
      drawButton(it, cx, panelY + M.PANEL_PAD, M.BUTTON_H)
      cx = cx + it.w + GAP
    end
  end

  -- templates row
  if ctx.showTemplates then
    local tw = M.PANEL_PAD * 2 - GAP
    local chips = {}
    for _, t in ipairs(ctx.templates) do
      chips[#chips + 1] = { id = "tpl:" .. t.id, label = t.name, w = buttonWidth(t.name, 60) }
      tw = tw + chips[#chips].w + GAP
    end
    local ty = panelY + panelH + 8
    local tx = fr.x + (fr.w - tw) / 2
    drawPanel(tx, ty, tw, panelH)
    local x = tx + M.PANEL_PAD
    for _, chip in ipairs(chips) do
      drawButton(chip, x, ty + M.PANEL_PAD, M.BUTTON_H)
      x = x + chip.w + GAP
    end
  end

  -- 5. hint line + toast --------------------------------------------------
  local hint = "Drag to draw   ·   Drag a zone to move   ·   Drag edges to resize (⌥ detaches)   ·   ⌫ delete   ·   ⌘Z undo   ·   ⏎ save   ·   esc cancel"
  local hw = math.ceil(measure(hint, 12)) + 36
  local hx = fr.x + (fr.w - hw) / 2
  local hy = fr.y + fr.h - 44
  add({ type = "rectangle", action = "fill", roundedRectRadii = rounded(14),
        frame = lf(hx, hy, hw, 28), fillColor = pal.toastFill })
  text(hint, hx, hy + 6, hw, 12, pal.editTextDim)

  if ctx.toast then
    local tw = math.ceil(measure(ctx.toast, TEXT)) + 40
    local tx = fr.x + (fr.w - tw) / 2
    local ty = hy - 46
    add({ type = "rectangle", action = "strokeAndFill", roundedRectRadii = rounded(16),
          frame = lf(tx, ty, tw, 34), fillColor = pal.toastFill, strokeColor = pal.accent, strokeWidth = 1,
          withShadow = true, shadow = { blurRadius = 18, color = { alpha = 0.4 }, offset = { h = -4, w = 0 } } })
    text(ctx.toast, tx, ty + 8, tw, TEXT, pal.white)
  end

  return els, ui
end

return M
