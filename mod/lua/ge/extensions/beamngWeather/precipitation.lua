-- BeamNG Weather: rain particles and sky (extension name: beamngWeather_precipitation)
--
-- Uses the level's own Precipitation object if it has one. If not, it creates
-- one that follows the camera. Clouds, fog and wind are moved toward a
-- stormy look as the rain gets heavier, and set back when it stops.

local M = {}
local logTag = "beamngWeather"

local OWN_NAME = "beamngWeather_rainObject"
local OWN_DATA = "beamngWeather_rainData"

-- Datablocks that ship with the game or with common levels, tried in order
local DATABLOCK_CANDIDATES = {"rain_medium", "rain_heavy", "rain_drop", "rain", "HeavyRain", "LightRain"}

local MAX_DROPS = 6000

local rainObj = nil          -- the Precipitation object we control
local createdOwn = false     -- did we create it (so we delete it on unload)?
local triedSetup = false
local origDrops = nil        -- the level's own drop count, put back when dry
local skyOrig = nil          -- the level's clouds, fog and wind before the rain
local lastIntensity = -1
local lastSky = -1

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

-- Make our own datablock with the drop textures shipped in this mod.
local function createOwnDatablock()
  local existing = findObj(OWN_DATA)
  if existing then return OWN_DATA end
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

local function pickDatablock()
  for _, name in ipairs(DATABLOCK_CANDIDATES) do
    if findObj(name) then return name end
  end
  local list = classObjects("PrecipitationData")
  if list[1] then return list[1] end
  return createOwnDatablock()
end

local function setupRainObject()
  triedSetup = true

  -- 1) The level already has rain
  local list = classObjects("Precipitation")
  for _, name in ipairs(list) do
    local o = findObj(name)
    if o then
      rainObj = o
      origDrops = tonumber(getF(o, "numDrops")) or 0
      log("I", logTag, "Using level precipitation object: " .. tostring(name))
      return
    end
  end

  -- 2) Make our own rain that follows the camera
  local db = pickDatablock()
  if not db then
    log("W", logTag, "No rain datablock found, rain particles are off. Wet roads, body and windshield still work.")
    return
  end
  local ok, err = pcall(function()
    local p = createObject("Precipitation")
    p:setField("dataBlock", 0, db)
    p:setField("numDrops", 0, "0")
    p:setField("boxWidth", 0, "200")
    p:setField("boxHeight", 0, "100")
    p:setField("dropSize", 0, "0.5")
    p:setField("splashSize", 0, "0.5")
    p:setField("splashMS", 0, "250")
    p:setField("animateSplashes", 0, "1")
    p:setField("dropAnimateMS", 0, "0")
    p:setField("fadeDist", 0, "0")
    p:setField("fadeDistEnd", 0, "0")
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
    p:setField("minSpeed", 0, "1.5")
    p:setField("maxSpeed", 0, "2")
    p:setField("minMass", 0, "0.75")
    p:setField("maxMass", 0, "0.85")
    p:registerObject(OWN_NAME)
    rainObj = p
  end)
  if ok and rainObj then
    createdOwn = true
    origDrops = 0
    log("I", logTag, "Created rain object with datablock " .. tostring(db))
  else
    rainObj = nil
    log("W", logTag, "Could not create rain object: " .. tostring(err))
  end
end

local function setDrops(n)
  if rainObj then
    setF(rainObj, "numDrops", math.floor(n))
    return true
  end
  -- Fallback: the game's own environment helper
  if core_environment and core_environment.setPrecipitation then
    pcall(core_environment.setPrecipitation, math.floor(n))
    return true
  end
  return false
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
  skyOrig = {
    cloud = envGet("getCloudCover"),
    fog   = envGet("getFogDensity"),
    wind  = envGet("getWindSpeed"),
  }
end

local function lerp(a, b, t) return a + (b - a) * t end

local function applySky(intensity)
  if not core_environment then return end
  if intensity > 0 and not skyOrig then captureSky() end
  if not skyOrig then return end
  if skyOrig.cloud then envSet("setCloudCover", lerp(skyOrig.cloud, math.max(skyOrig.cloud, 1.0), math.min(1, intensity * 1.5))) end
  if skyOrig.fog then envSet("setFogDensity", lerp(skyOrig.fog, math.max(skyOrig.fog, 0.006), intensity)) end
  if skyOrig.wind then envSet("setWindSpeed", lerp(skyOrig.wind, math.max(skyOrig.wind, 6), intensity)) end
  if intensity <= 0 then skyOrig = nil end -- back to the level's sky, capture again next storm
end

-- Public ---------------------------------------------------------------

function M.apply(intensity, particlesOn, skyOn, force)
  local pI = particlesOn and intensity or 0
  if force or math.abs(pI - lastIntensity) > 0.01 then
    if pI > 0 and not triedSetup then setupRainObject() end
    if rainObj or pI > 0 or force then
      -- Light rain is sparse, heavy rain is dense (curve weights the top end)
      local drops = (pI > 0) and (MAX_DROPS * (pI ^ 1.5)) or (origDrops or 0)
      if not createdOwn and origDrops and pI > 0 then drops = math.max(drops, origDrops) end
      setDrops(drops)
    end
    lastIntensity = pI
  end

  local sI = skyOn and intensity or 0
  if force or math.abs(sI - lastSky) > 0.02 then
    applySky(sI)
    lastSky = sI
  end
end

local function cleanup()
  if rainObj then
    if createdOwn then
      pcall(function() rainObj:delete() end)
    elseif origDrops then
      setF(rainObj, "numDrops", math.floor(origDrops))
    end
  end
  if skyOrig then applySky(0) end
  rainObj, createdOwn, triedSetup, origDrops, skyOrig = nil, false, false, nil, nil
  lastIntensity, lastSky = -1, -1
end

function M.onClientEndMission()
  -- The level is going away: forget our objects, they are deleted with it
  rainObj, createdOwn, triedSetup, origDrops, skyOrig = nil, false, false, nil, nil
  lastIntensity, lastSky = -1, -1
end

function M.onExtensionUnloaded() cleanup() end

return M
