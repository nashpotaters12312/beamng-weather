-- BeamNG Weather: rain particles and sky (extension name: beamngWeather_precipitation)
--
-- The mod makes its own rain in two layers that follow the camera:
--   near: a small, dense box of thin, fast streaks right around you
--   far:  a big box of longer streaks that gives depth to the storm
-- It uses its own high-resolution drop textures (art/beamng_weather). If the
-- game won't take a new datablock, it falls back to the map's rain datablock.
-- The map's own rain object, if any, is left alone.
-- Clouds, fog and wind move toward a stormy look as the rain gets heavier,
-- and go back afterwards.

local M = {}
local logTag = "beamngWeather"

local OWN_DATA = "beamngWeather_rainData"
local FALLBACK_DATABLOCKS = {"rain_medium", "rain_heavy", "rain_drop", "rain", "HeavyRain", "LightRain"}

-- Rain layers. Drops are per layer at 100% intensity on "high" quality.
local LAYERS = {
  { name = "beamngWeather_rainNear", drops = 7000, boxWidth = 36,  boxHeight = 24,
    dropSize = 0.22, splashSize = 0.25, minSpeed = 3.5, maxSpeed = 4.5 },
  { name = "beamngWeather_rainFar",  drops = 9000, boxWidth = 140, boxHeight = 70,
    dropSize = 0.45, splashSize = 0.0,  minSpeed = 3.0, maxSpeed = 4.0 },
}
local QUALITY = { low = 0.35, medium = 0.65, high = 1.0, ultra = 1.6 }

local objs = {}              -- created Precipitation objects, by layer index
local triedSetup = false
local dataBlockName = nil
local quality = "high"
local skyOrig = nil
local lastIntensity = -1
local lastSky = -1
local status = "not started"
local builtInSplashes = true -- turned off when the particle splashes work

local function findObj(name)
  local ok, o = pcall(scenetree.findObject, name)
  if ok then return o end
  return nil
end

local function classObjects(className)
  local ok, list = pcall(scenetree.findClassObjects, className)
  if ok and type(list) == "table" then return list end
  return {}
end

local function setF(obj, field, value)
  pcall(function() obj:setField(field, 0, tostring(value)) end)
end

local function getF(obj, field)
  local ok, v = pcall(function() return obj:getField(field, 0) end)
  if ok then return v end
  return nil
end

-- Field changes made from Lua only reach the renderer after postApply()
local function commit(obj) pcall(function() obj:postApply() end) end

local function createOwnDatablock()
  if findObj(OWN_DATA) then return OWN_DATA end
  local ok = pcall(function()
    local db = createObject("PrecipitationData")
    db:setField("dropTexture", 0, "/art/beamng_weather/rain_drops.png")
    db:setField("splashTexture", 0, "/art/beamng_weather/rain_splash.png")
    db:setField("dropsPerSide", 0, "4")
    db:setField("splashesPerSide", 0, "2")
    db:registerObject(OWN_DATA)
  end)
  if ok and findObj(OWN_DATA) then return OWN_DATA end
  return nil
end

local preferMapLook = false -- true: use the map's rain textures instead of the mod's

local function pickDatablock()
  local own = (not preferMapLook) and createOwnDatablock() or nil
  if own then return own, "mod textures" end
  for _, name in ipairs(FALLBACK_DATABLOCKS) do
    if findObj(name) then return name, "map datablock" end
  end
  local list = classObjects("PrecipitationData")
  for _, name in ipairs(list) do
    if name ~= OWN_DATA then return name, "map datablock" end
  end
  return nil
end

local function layerDrops(layer)
  return math.floor(layer.drops * (QUALITY[quality] or 1))
end

local function createLayer(i, layer)
  local ok, err = pcall(function()
    local p = createObject("Precipitation")
    p:setField("dataBlock", 0, dataBlockName)
    p:setField("numDrops", 0, tostring(layerDrops(layer)))
    p:setField("boxWidth", 0, tostring(layer.boxWidth))
    p:setField("boxHeight", 0, tostring(layer.boxHeight))
    p:setField("dropSize", 0, tostring(layer.dropSize))
    p:setField("splashSize", 0, tostring(builtInSplashes and layer.splashSize or 0))
    p:setField("splashMS", 0, "220")
    p:setField("animateSplashes", 0, (builtInSplashes and layer.splashSize > 0) and "1" or "0")
    p:setField("dropAnimateMS", 0, "0")
    p:setField("fadeDist", 0, tostring(layer.boxWidth * 0.35))
    p:setField("fadeDistEnd", 0, tostring(layer.boxWidth * 0.5))
    p:setField("useTrueBillboards", 0, "0")
    p:setField("useLighting", 0, "1")
    p:setField("glowIntensity", 0, "0 0 0 0")
    p:setField("reflect", 0, "0")
    p:setField("rotateWithCamVel", 0, "1")
    p:setField("doCollision", 0, "1")
    p:setField("hitPlayers", 0, "0")
    p:setField("hitVehicles", 0, "0")
    p:setField("followCam", 0, "1")
    p:setField("useWind", 0, "1")
    p:setField("minSpeed", 0, tostring(layer.minSpeed))
    p:setField("maxSpeed", 0, tostring(layer.maxSpeed))
    p:setField("minMass", 0, "0.75")
    p:setField("maxMass", 0, "0.85")
    p:setField("canSave", 0, "0")
    p:registerObject(layer.name)
    pcall(function() scenetree.MissionGroup:addObject(p) end)
    pcall(function() p:setPercentage(0) end)
    objs[i] = p
  end)
  if not ok then log("W", logTag, "Could not create rain layer " .. layer.name .. ": " .. tostring(err)) end
  return ok
end

local function setupRain()
  -- Never create anything when no map is loaded
  local ok, mg = pcall(function() return scenetree.MissionGroup end)
  if not ok or not mg then return end
  triedSetup = true

  local how
  dataBlockName, how = pickDatablock()
  if not dataBlockName then
    status = "no rain datablock could be made or found"
    log("W", logTag, "Rain particles are off: " .. status)
    return
  end
  local made = 0
  for i, layer in ipairs(LAYERS) do
    -- Remove leftovers from an earlier load of the mod
    local old = findObj(layer.name)
    if old then pcall(function() old:delete() end) end
    if createLayer(i, layer) then made = made + 1 end
  end
  status = string.format("%d rain layers, %s (%s), %s quality", made, dataBlockName, how, quality)
  log("I", logTag, "Rain: " .. status)
end

local function applyRain(pI)
  -- Light rain is sparse, heavy rain is dense
  local pct = (pI > 0) and math.min(1, 0.04 + pI ^ 1.25) or 0
  for i, p in pairs(objs) do
    -- The far layer only joins in from moderate rain upward
    local layerPct = pct
    if i == 2 then layerPct = math.max(0, (pI - 0.15) / 0.85) ^ 1.2 end
    pcall(function() p:setPercentage(layerPct) end)
    pcall(function() p:setHidden(layerPct <= 0) end)
  end
end

-- Sky ------------------------------------------------------------------

local function envGet(fn)
  if core_environment and core_environment[fn] then
    local ok, v = pcall(core_environment[fn])
    if ok and type(v) == "number" then return v end
  end
  return nil
end

local function envSet(fn, v)
  if v ~= nil and core_environment and core_environment[fn] then pcall(core_environment[fn], v) end
end

local function captureSky()
  skyOrig = { cloud = envGet("getCloudCover"), fog = envGet("getFogDensity"), wind = envGet("getWindSpeed") }
end

local function lerp(a, b, t) return a + (b - a) * t end

local function applySky(intensity)
  if not core_environment then return end
  if intensity > 0 and not skyOrig then captureSky() end
  if not skyOrig then return end
  if skyOrig.cloud then envSet("setCloudCover", lerp(skyOrig.cloud, math.max(skyOrig.cloud, 1.0), math.min(1, intensity * 1.5))) end
  if skyOrig.fog then envSet("setFogDensity", lerp(skyOrig.fog, math.max(skyOrig.fog, 0.006), intensity)) end
  if skyOrig.wind then envSet("setWindSpeed", lerp(skyOrig.wind, math.max(skyOrig.wind, 6), intensity)) end
  if intensity <= 0 then skyOrig = nil end
end

-- Public ---------------------------------------------------------------

function M.apply(intensity, particlesOn, skyOn, force)
  local pI = particlesOn and intensity or 0
  if force or math.abs(pI - lastIntensity) > 0.01 then
    if pI > 0 and not triedSetup then setupRain() end
    applyRain(pI)
    lastIntensity = pI
  end

  local sI = skyOn and intensity or 0
  if force or math.abs(sI - lastSky) > 0.02 then
    applySky(sI)
    lastSky = sI
  end
end

-- The game's own flat splash pictures: on or off
function M.setBuiltInSplashes(on)
  builtInSplashes = on and true or false
  for i, p in pairs(objs) do
    local size = builtInSplashes and LAYERS[i].splashSize or 0
    setF(p, "splashSize", size)
    setF(p, "animateSplashes", size > 0 and 1 or 0)
    commit(p)
  end
end

-- "low", "medium", "high" or "ultra": how many drops each layer has
function M.setQuality(q)
  if not QUALITY[q] then return end
  quality = q
  for i, p in pairs(objs) do
    setF(p, "numDrops", layerDrops(LAYERS[i]))
    commit(p)
  end
  if triedSetup and dataBlockName then
    status = string.gsub(status, "%a+ quality", quality .. " quality")
  end
end

-- Console: beamngWeather_precipitation.useMapLook(true) if the mod's rain is invisible
function M.useMapLook(on)
  preferMapLook = on and true or false
  for _, p in pairs(objs) do pcall(function() p:delete() end) end
  objs, triedSetup = {}, false
  local i = lastIntensity
  lastIntensity = -1
  if i and i > 0 then M.apply(i, true, false, false) end
  return status
end

function M.getDebugInfo()
  local info = { status = status, quality = quality, lastIntensity = lastIntensity, dataBlock = dataBlockName }
  local n = 0
  for i, p in pairs(objs) do
    n = n + 1
    info["layer" .. i .. ".numDrops"] = getF(p, "numDrops")
  end
  info.layers = n
  info.mapRainObjects = classObjects("Precipitation")
  info.datablocks = classObjects("PrecipitationData")
  return info
end

local function forget()
  objs, triedSetup, dataBlockName, skyOrig = {}, false, nil, nil
  lastIntensity, lastSky = -1, -1
  status = "not started"
end

function M.onClientEndMission() forget() end -- objects go away with the map

function M.onExtensionUnloaded()
  for _, p in pairs(objs) do pcall(function() p:delete() end) end
  if skyOrig then applySky(0) end
  forget()
end

return M
