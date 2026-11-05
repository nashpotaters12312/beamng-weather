-- BeamNG Weather: water drops on cars (extension name: beamngWeather_wetDroplets)
--
-- Puts a tiling water-droplet normal map on the detail slot of vehicle
-- materials, so beads of water catch the light on the paint and on the
-- windows, from any camera:
--   paint: materials with instance (car paint) colour, small beads
--   glass: windshield and window materials, bigger drops and short runs
-- Drops get stronger as things get wetter, and are taken off when dry.
-- The material's original detail settings are saved and put back.
--
-- BeamNG has used two names for these fields over the years, so both are set.

local M = {}
local logTag = "beamngWeather"

local TEX = {
  paint = "/art/beamng_weather/droplets_body_n.png",
  glass = "/art/beamng_weather/droplets_glass_n.png",
}
-- Colour detail: neutral grey with brighter beads, so drops show even
-- where the normal detail slot isn't used
local COLOR_TEX = {
  paint = "/art/beamng_weather/droplets_body_d.png",
  glass = "/art/beamng_weather/droplets_glass_d.png",
}
local SCALE = { paint = 9, glass = 5 }        -- tiles per UV unit (bigger = smaller drops)
local MAX_STRENGTH = { paint = 1.0, glass = 1.4 }

local MAP_FIELDS      = {"detailNormalMap", "normalDetailMap"}
local COLOR_FIELDS    = {"detailMap", "baseColorDetailMap"}
local STRENGTH_FIELDS = {"detailNormalMapStrength", "normalDetailMapStrength"}
local SCALE_FIELDS    = {"detailScale"}

local GLASS_WORDS = {"glass", "windshield", "windscreen", "window"}
local GLASS_SKIP  = {"mirror", "light", "lamp", "gauge", "display", "lens", "headl", "taill", "signal", "reflector"}
-- Car paint flag: "instanceDiffuse" in old materials, "instanceBaseColor" in newer ones
local PAINT_FLAGS = {"instanceBaseColor", "instanceDiffuse"}

local STAGES = {0, 0.35, 0.65, 1.0}    -- few steps: every change reloads the materials

local cache = nil       -- [matName] = {obj=, kind=, layers={i...}, orig={[layer]={[field]=value}}}
local currentStage = 1
local lastWet = 0
local dirty = false     -- new vehicles spawned: look for new materials

local function lower(s) return string.lower(tostring(s or "")) end

local function hasAny(s, words)
  for _, w in ipairs(words) do if string.find(s, w, 1, true) then return true end end
  return false
end

local function getF(obj, field, layer)
  local ok, v = pcall(function() return obj:getField(field, layer) end)
  if ok then return v end
  return nil
end

local function setF(obj, field, layer, value)
  pcall(function() obj:setField(field, layer, tostring(value)) end)
end

local function truthy(v) v = lower(v) return v == "1" or v == "true" end

local function fileOf(obj)
  local ok, f = pcall(function() return obj:getFileName() end)
  if ok and type(f) == "string" and f ~= "" then return lower(f) end
  return nil
end

-- Model names of the cars in the world (e.g. "pickup", "etk800"), to spot
-- their materials by name when the material's file is not known
local function vehicleModels()
  local models = {}
  if not be or not be.getObjectCount then return models end
  for i = 0, be:getObjectCount() - 1 do
    local veh = be:getObject(i)
    if veh then
      local ok, jb = pcall(function() return veh:getJBeamFilename() end)
      if ok and type(jb) == "string" and jb ~= "" then models[lower(jb)] = true end
    end
  end
  return models
end

local function isPaintLayer(obj, i)
  for _, f in ipairs(PAINT_FLAGS) do
    if truthy(getF(obj, f, i)) then return true end
  end
  return false
end

-- What kind of vehicle material is this, and which layers to change?
local function classify(obj, name, models)
  local file = fileOf(obj)
  local lname = lower(name) .. " " .. lower(getF(obj, "mapTo", 0))
  local isVehicle = file and string.find(file, "/vehicles/", 1, true) ~= nil
  if not isVehicle and not file then
    for m in pairs(models) do
      if string.find(lname, m, 1, true) then isVehicle = true; break end
    end
  end
  -- Paint: any layer with car paint colour (only cars have that)
  local paintLayers = {}
  for i = 0, 3 do
    if isPaintLayer(obj, i) then paintLayers[#paintLayers + 1] = i end
  end
  if #paintLayers > 0 and (isVehicle or file == nil) then return "paint", paintLayers end
  -- Glass: only on cars (map buildings have windows too)
  if isVehicle and hasAny(lname, GLASS_WORDS) and not hasAny(lname, GLASS_SKIP) then return "glass", {0} end
  return nil
end

local function remember(entry)
  entry.orig = {}
  for _, i in ipairs(entry.layers) do
    local o = {}
    for _, list in ipairs({MAP_FIELDS, COLOR_FIELDS, STRENGTH_FIELDS, SCALE_FIELDS}) do
      for _, f in ipairs(list) do o[f] = getF(entry.obj, f, i) or "" end
    end
    entry.orig[i] = o
  end
end

local function scan()
  cache = cache or {}
  local ok, names = pcall(scenetree.findClassObjects, "Material")
  if not ok or type(names) ~= "table" then return end
  local added = 0
  local models = vehicleModels()
  for _, name in ipairs(names) do
    if not cache[name] then
      local obj = scenetree.findObject(name)
      if obj then
        local kind, layers = classify(obj, name, models)
        if kind then
          local e = {obj = obj, kind = kind, layers = layers}
          remember(e)
          cache[name] = e
          added = added + 1
        end
      end
    end
  end
  if added > 0 then log("I", logTag, string.format("Car drops: %d vehicle materials added", added)) end
  dirty = false
end

local function reload(obj)
  pcall(function() obj:flush() end)
  pcall(function() obj:reload() end)
end

local function applyEntry(e, wet)
  for _, i in ipairs(e.layers) do
    if wet <= 0 then
      for f, v in pairs(e.orig[i]) do setF(e.obj, f, i, v) end
    else
      for _, f in ipairs(MAP_FIELDS) do setF(e.obj, f, i, TEX[e.kind]) end
      for _, f in ipairs(COLOR_FIELDS) do setF(e.obj, f, i, COLOR_TEX[e.kind]) end
      for _, f in ipairs(STRENGTH_FIELDS) do setF(e.obj, f, i, string.format("%.3f", MAX_STRENGTH[e.kind] * wet)) end
      local s = SCALE[e.kind]
      for _, f in ipairs(SCALE_FIELDS) do setF(e.obj, f, i, s .. " " .. s) end
    end
  end
  reload(e.obj)
end

local function stageFor(wet)
  if wet < 0.12 then return 1 end
  local st = 2
  for i = 2, #STAGES do if wet >= STAGES[i] - 0.05 then st = i end end
  return st
end

function M.apply(wet, force)
  wet = math.max(0, math.min(1, wet or 0))
  lastWet = wet
  local stage = stageFor(wet)
  if stage == currentStage and not force and not dirty then return end
  if stage == 1 and not cache then currentStage = 1; return end -- dry and never touched
  local before = {}
  if cache then for k in pairs(cache) do before[k] = true end end
  if not cache or dirty then scan() end
  local value = STAGES[stage]
  for name, e in pairs(cache) do
    -- Only reload what changed: everything on a stage change, new ones otherwise
    if stage ~= currentStage or force or (not before[name] and value > 0) then applyEntry(e, value) end
  end
  currentStage = stage
end

-- New car: its materials may be new too
function M.onVehicleSpawned() dirty = true end

function M.onClientEndMission() cache = nil; currentStage = 1; dirty = false end

function M.onExtensionUnloaded()
  if cache then for _, e in pairs(cache) do applyEntry(e, 0) end end
  cache = nil
end

function M.getStatus()
  if not cache then return "waiting for rain" end
  local paint, glass = 0, 0
  for _, e in pairs(cache) do
    if e.kind == "paint" then paint = paint + 1 else glass = glass + 1 end
  end
  return string.format("%d paint, %d glass materials", paint, glass)
end

-- Console helper: list the materials that get drops
function M.dump()
  if not cache then scan() end
  for name, e in pairs(cache or {}) do print(e.kind .. "  " .. name) end
end

return M
