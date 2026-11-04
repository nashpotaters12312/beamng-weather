-- BeamNG Weather: wet roads (extension name: beamngWeather_wetRoads)
--
-- Finds the level's road materials (asphalt, concrete, road lines, kerbs...)
-- and makes them look wet: less rough, with a smooth, glossy clear coat on
-- top so they reflect the sky, lights and other cars. The original values are
-- saved and put back when the road dries.

local M = {}
local logTag = "beamngWeather"

-- A material is a "road" if its name or mapTo has one of these words
local INCLUDE = {
  "road", "asphalt", "tarmac", "concrete", "pavement", "street", "highway",
  "crossing", "crosswalk", "sidewalk", "parking", "line", "kerb", "curb",
  "cobble", "brick", "pothole", "patch", "crack", "decal_road", "track",
  "runway", "bridge", "tunnel",
}
-- ...unless it also has one of these (plants, dirt, vehicles, glass...)
local EXCLUDE = {
  "grass", "tree", "leaf", "leaves", "foliage", "bush", "plant", "dirt", "mud",
  "sand", "gravel", "rock", "cliff", "water", "glass", "window", "sky", "cloud",
  "vehicle", "tire", "tyre", "wheel", "light", "lamp", "sign", "fence", "railtrack",
  "trackmania",
}

local LAYERS = 4

-- How wet roads look at full wetness
local WET_ROUGHNESS_MULT   = 0.25  -- roughness is cut to 25%
local WET_ROUGHNESS_MIN    = 0.08
local WET_CLEARCOAT        = 1.0   -- glossy water film on top
local WET_CLEARCOAT_ROUGH  = 0.04  -- very smooth = sharp reflections

local cache = nil        -- list of {obj=, name=, layers={[i]={rough=,cc=,ccr=}}}
local lastWet = -1
local STEP = 0.04        -- only re-apply when wetness moves this much (reload is not free)

local function lower(s) return string.lower(tostring(s or "")) end

local function hasAny(s, words)
  for _, w in ipairs(words) do
    if string.find(s, w, 1, true) then return true end
  end
  return false
end

local function getF(obj, field, layer)
  local ok, v = pcall(function() return obj:getField(field, layer) end)
  if ok and v ~= nil and v ~= "" then return tonumber(v) end
  return nil
end

local function setF(obj, field, layer, value)
  pcall(function() obj:setField(field, layer, string.format("%.4f", value)) end)
end

local function isRoadMaterial(obj, name)
  local mapTo = ""
  pcall(function() mapTo = obj:getField("mapTo", 0) or "" end)
  local s = lower(name) .. " " .. lower(mapTo)
  return hasAny(s, INCLUDE) and not hasAny(s, EXCLUDE)
end

local function scan()
  cache = {}
  local ok, names = pcall(scenetree.findClassObjects, "Material")
  if not ok or type(names) ~= "table" then return end
  for _, name in ipairs(names) do
    local obj = scenetree.findObject(name)
    if obj and isRoadMaterial(obj, name) then
      local entry = {obj = obj, name = name, layers = {}}
      local any = false
      for i = 0, LAYERS - 1 do
        local rough = getF(obj, "roughnessFactor", i)
        local cc    = getF(obj, "clearCoatFactor", i)
        local ccr   = getF(obj, "clearCoatRoughnessFactor", i)
        if rough or cc or ccr then
          entry.layers[i] = {rough = rough, cc = cc, ccr = ccr}
          any = true
        end
        -- Only the first layer is needed when the material has one
        if i == 0 and not any then break end
      end
      if any then table.insert(cache, entry) end
    end
  end
  log("I", logTag, string.format("Wet roads: %d road materials found", #cache))
end

local function applyEntry(e, wet)
  for i, orig in pairs(e.layers) do
    if orig.rough then
      local wetRough = math.max(WET_ROUGHNESS_MIN, orig.rough * WET_ROUGHNESS_MULT)
      if orig.rough < WET_ROUGHNESS_MIN then wetRough = orig.rough end
      setF(e.obj, "roughnessFactor", i, orig.rough + (wetRough - orig.rough) * wet)
    end
    -- Clear coat: blend from the original to a smooth water film.
    -- Clear coat roughness is only set while wet, so a dry road keeps its look.
    local cc0 = orig.cc or 0
    local ccr0 = orig.ccr or 1
    setF(e.obj, "clearCoatFactor", i, cc0 + (math.max(cc0, WET_CLEARCOAT) - cc0) * wet)
    setF(e.obj, "clearCoatRoughnessFactor", i, ccr0 + (WET_CLEARCOAT_ROUGH - ccr0) * wet)
  end
  pcall(function() e.obj:flush() end)
  pcall(function() e.obj:reload() end)
end

function M.apply(wet, force)
  wet = math.max(0, math.min(1, wet or 0))
  -- Snap to steps so reloads only happen now and then
  local snapped = math.floor(wet / STEP + 0.5) * STEP
  if wet <= 0 then snapped = 0 end
  if not force and math.abs(snapped - lastWet) < STEP * 0.5 then return end
  if not cache then
    if snapped <= 0 then lastWet = 0; return end -- dry and never touched: nothing to do
    scan()
  end
  for _, e in ipairs(cache) do applyEntry(e, snapped) end
  lastWet = snapped
end

-- Re-scan in a new level
function M.onClientEndMission() cache = nil; lastWet = -1 end

function M.onExtensionUnloaded()
  if cache then for _, e in ipairs(cache) do applyEntry(e, 0) end end
  cache = nil
end

-- Console helper: list what the mod treats as road
function M.dump()
  if not cache then scan() end
  for _, e in ipairs(cache) do print(e.name) end
end

return M
