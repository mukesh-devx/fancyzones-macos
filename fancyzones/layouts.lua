--- Layout store: persistence (JSON), validation, templates and per-screen assignment.
---
--- File format (layouts.json):
---   {
---     "version": 1,
---     "layouts": [ { "id": "two-columns", "name": "Two columns",
---                    "zones": [ {"x":0,"y":0,"w":0.5,"h":1}, ... ] }, ... ],
---     "assignments": { "<screen UUID>": "<layout id>" }
---   }
--- Zone values are fractions (0..1) of the screen's usable area, so a layout
--- works on any resolution.

local geometry = require("fancyzones.geometry")
local log = require("fancyzones.log")

local M = {}

local FORMAT_VERSION = 1
local MAX_ZONES = 64
local MIN_ZONE = 0.02

M.path = nil
M.data = { version = FORMAT_VERSION, layouts = {}, assignments = {} }
--- Bumped on every change so caches (overlay canvases) know when to rebuild.
M.revision = 0

---------------------------------------------------------------------------
-- Templates (also used to seed a fresh install)
---------------------------------------------------------------------------

local function columns(weights)
  local total = 0
  for _, w in ipairs(weights) do total = total + w end
  local zones, x = {}, 0
  for _, w in ipairs(weights) do
    local fw = w / total
    zones[#zones + 1] = { x = geometry.round4(x), y = 0, w = geometry.round4(fw), h = 1 }
    x = x + fw
  end
  return zones
end

local function rows(n)
  local zones = {}
  for i = 0, n - 1 do
    zones[#zones + 1] = { x = 0, y = geometry.round4(i / n), w = 1, h = geometry.round4(1 / n) }
  end
  return zones
end

local function grid(nr, nc)
  local zones = {}
  for r = 0, nr - 1 do
    for c = 0, nc - 1 do
      zones[#zones + 1] = {
        x = geometry.round4(c / nc), y = geometry.round4(r / nr),
        w = geometry.round4(1 / nc), h = geometry.round4(1 / nr),
      }
    end
  end
  return zones
end

--- Built-in templates. Each call returns fresh tables (safe to mutate).
function M.templates()
  return {
    { id = "full", name = "Full screen", zones = { { x = 0, y = 0, w = 1, h = 1 } } },
    { id = "columns-2", name = "2 columns", zones = columns({ 1, 1 }) },
    { id = "columns-3", name = "3 columns", zones = columns({ 1, 1, 1 }) },
    { id = "priority", name = "Priority", zones = columns({ 1, 2, 1 }) },
    { id = "rows-2", name = "2 rows", zones = rows(2) },
    { id = "grid-2x2", name = "2 × 2 grid", zones = grid(2, 2) },
    {
      id = "main-side", name = "Main + side",
      zones = {
        { x = 0, y = 0, w = 0.6667, h = 1 },
        { x = 0.6667, y = 0, w = 0.3333, h = 0.5 },
        { x = 0.6667, y = 0.5, w = 0.3333, h = 0.5 },
      },
    },
  }
end

local function defaultLayouts()
  local out = {}
  for _, t in ipairs(M.templates()) do
    if t.id ~= "rows-2" then out[#out + 1] = t end -- keep the seed list short
  end
  return out
end

---------------------------------------------------------------------------
-- Validation
---------------------------------------------------------------------------

local function finite(v)
  return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

--- Return a cleaned copy of a raw zone, or nil if it is unusable.
local function cleanZone(raw)
  if type(raw) ~= "table" then return nil end
  if not (finite(raw.x) and finite(raw.y) and finite(raw.w) and finite(raw.h)) then return nil end
  local z = geometry.sanitizeZone(raw, MIN_ZONE)
  return { x = geometry.round4(z.x), y = geometry.round4(z.y), w = geometry.round4(z.w), h = geometry.round4(z.h) }
end

--- Return a cleaned copy of a raw layout, or nil (with reason) if unusable.
function M.cleanLayout(raw)
  if type(raw) ~= "table" then return nil, "not a table" end
  if type(raw.id) ~= "string" or raw.id == "" then return nil, "missing id" end
  if type(raw.zones) ~= "table" then return nil, "missing zones" end
  local zones = {}
  for _, rz in ipairs(raw.zones) do
    local z = cleanZone(rz)
    if z and #zones < MAX_ZONES then zones[#zones + 1] = z end
  end
  if #zones == 0 then return nil, "no valid zones" end
  local name = type(raw.name) == "string" and raw.name ~= "" and raw.name or raw.id
  return { id = raw.id, name = name, zones = zones }
end

local function deepCopyZones(zones)
  local out = {}
  for i, z in ipairs(zones) do out[i] = { x = z.x, y = z.y, w = z.w, h = z.h } end
  return out
end

---------------------------------------------------------------------------
-- Persistence
---------------------------------------------------------------------------

local function fileExists(path)
  return hs.fs.attributes(path) ~= nil
end

local function readFile(path)
  local f, err = io.open(path, "r")
  if not f then return nil, err end
  local s = f:read("a")
  f:close()
  return s
end

local function seed()
  M.data = { version = FORMAT_VERSION, layouts = defaultLayouts(), assignments = {} }
  M.revision = M.revision + 1
end

--- Set the storage directory and load (or create) the layouts file.
function M.init(dataDir)
  M.path = dataDir .. "/layouts.json"
  if not fileExists(dataDir) then
    local ok, err = hs.fs.mkdir(dataDir)
    if not ok then log.e("cannot create data dir", dataDir, err) end
  end
  return M.load()
end

--- Load layouts from disk. A missing file is seeded with defaults; a corrupt
--- file is moved aside (never silently overwritten) and replaced with defaults.
function M.load()
  if not fileExists(M.path) then
    seed()
    M.save()
    log.i("created default layouts at", M.path)
    return true
  end

  local text, rerr = readFile(M.path)
  local ok, decoded = false, nil
  if text then ok, decoded = pcall(hs.json.decode, text) end

  if not (ok and type(decoded) == "table" and type(decoded.layouts) == "table") then
    local backup = M.path .. ".corrupt-" .. os.date("%Y%m%d-%H%M%S")
    os.rename(M.path, backup)
    log.e("layouts.json unreadable (" .. tostring(rerr or decoded) .. "); moved to", backup)
    seed()
    M.save()
    return false, "Layout file was unreadable and has been backed up"
  end

  local layouts, seen = {}, {}
  for _, raw in ipairs(decoded.layouts) do
    local clean, why = M.cleanLayout(raw)
    if clean and not seen[clean.id] then
      seen[clean.id] = true
      layouts[#layouts + 1] = clean
    else
      log.w("skipping invalid layout:", why or "duplicate id")
    end
  end

  local assignments = {}
  if type(decoded.assignments) == "table" then
    for screenKey, layoutId in pairs(decoded.assignments) do
      if type(screenKey) == "string" and seen[layoutId] then assignments[screenKey] = layoutId end
    end
  end

  if #layouts == 0 then
    seed()
    M.save()
    return true
  end
  M.data = { version = FORMAT_VERSION, layouts = layouts, assignments = assignments }
  M.revision = M.revision + 1
  return true
end

--- Write layouts.json atomically (temp file + rename).
function M.save()
  if not M.path then return false, "store not initialised" end
  local ok, json = pcall(hs.json.encode, M.data, true)
  if not ok then
    log.e("json encode failed", json)
    return false, tostring(json)
  end
  local tmp = M.path .. ".tmp"
  local f, err = io.open(tmp, "w")
  if not f then
    log.e("cannot write", tmp, err)
    return false, tostring(err)
  end
  f:write(json)
  f:close()
  local renamed, rerr = os.rename(tmp, M.path)
  if not renamed then
    log.e("cannot replace", M.path, rerr)
    return false, tostring(rerr)
  end
  return true
end

---------------------------------------------------------------------------
-- Queries
---------------------------------------------------------------------------

function M.list() return M.data.layouts end

function M.get(id)
  for _, l in ipairs(M.data.layouts) do
    if l.id == id then return l end
  end
  return nil
end

--- The layout used on a screen (falls back to the first layout).
function M.layoutFor(screenKey)
  local id = M.data.assignments[screenKey]
  return (id and M.get(id)) or M.data.layouts[1]
end

--- Use layout `layoutId` on a screen and persist the choice.
function M.assign(screenKey, layoutId)
  if not M.get(layoutId) then return false end
  M.data.assignments[screenKey] = layoutId
  M.revision = M.revision + 1
  return M.save()
end

--- A copy of layout `id` that can be edited freely.
function M.draft(layout)
  return { id = layout.id, name = layout.name, zones = deepCopyZones(layout.zones) }
end

--- Make an id from a name that does not collide with `taken` (set of ids).
function M.uniqueId(name, taken)
  local base = tostring(name):lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
  if base == "" then base = "layout" end
  local id, n = base, 1
  while taken[id] do
    n = n + 1
    id = base .. "-" .. n
  end
  return id
end

--- Replace all layouts + assignments at once (used by the editor's Save).
--- `list` is an ordered array of layouts, `assignments` maps screenKey -> id.
function M.commit(list, assignments)
  local cleaned, seen = {}, {}
  for _, raw in ipairs(list) do
    local clean, why = M.cleanLayout(raw)
    if not clean then return false, ("layout '%s': %s"):format(tostring(raw.name), why) end
    if seen[clean.id] then return false, "duplicate layout id " .. clean.id end
    seen[clean.id] = true
    cleaned[#cleaned + 1] = clean
  end
  if #cleaned == 0 then return false, "at least one layout is required" end

  local newAssign = {}
  for screenKey, id in pairs(assignments) do
    if seen[id] then newAssign[screenKey] = id end
  end

  local previous = M.data
  M.data = { version = FORMAT_VERSION, layouts = cleaned, assignments = newAssign }
  local ok, err = M.save()
  if not ok then
    M.data = previous -- keep memory consistent with what is on disk
    return false, err
  end
  M.revision = M.revision + 1
  return true
end

return M
