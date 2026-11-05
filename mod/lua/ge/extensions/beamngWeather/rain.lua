-- BeamNG Weather: Rain Overhaul — main controller (extension name: beamngWeather_rain)
--
-- This module holds the weather state and drives the sub-modules:
--   beamngWeather_precipitation  rain particles and sky (clouds, fog, wind)
--   beamngWeather_wetRoads       glossy, reflective road materials
--   beamngWeather_wetBody        wet clear coat on vehicle paint
--   beamngWeather_wetGrip        lower tyre grip on wet tarmac (experimental)
-- It also streams data to the UI app, which draws drops on the windshield.
--
-- Console examples (open the console with the ~ key):
--   beamngWeather_rain.setIntensity(0.7)   -- 0 = dry, 1 = downpour
--   beamngWeather_rain.toggleRain()
--   beamngWeather_rain.setWetness(1)       -- soak the world instantly
--   beamngWeather_rain.setFeature("grip", false)

local M = {}
M.dependencies = {
  "beamngWeather_precipitation",
  "beamngWeather_wetRoads",
  "beamngWeather_wetBody",
  "beamngWeather_wetDroplets",
  "beamngWeather_splashes",
  "beamngWeather_wetGrip",
}

local logTag = "beamngWeather"
local settingsPath = "settings/beamng_weather.json"

-- Default settings, saved to the user folder
local SETTINGS_VERSION = 2

local defaults = {
  version        = SETTINGS_VERSION,
  intensity      = 0.6,   -- target rain intensity 0..1 used when rain is on
  rainOn         = false,
  wetRate        = 1/45,  -- wetness gained per second at full intensity (fully wet in ~45 s)
  dryRate        = 1/240, -- wetness lost per second when dry (~4 min to dry out)
  wipers         = 0,     -- 0 off, 1 intermittent, 2 slow, 3 fast
  quality        = "high", -- rain particle quality: low, medium, high, ultra
  features = {
    particles  = true,  -- falling rain
    sky        = true,  -- clouds, fog and wind follow the rain
    roads      = true,  -- wet roads
    body       = true,  -- wet car paint
    droplets   = true,  -- water drops on car paint and windows
    splashes   = true,  -- 3D particle splashes on the ground
    grip       = false, -- less grip on wet roads (experimental, off by default)
    windshield = true,  -- drops on the windshield (UI overlay)
    allCameras = false, -- drops on the "lens" in outside cameras too
  },
}

local settings = deepcopy(defaults)

-- Live state
local state = {
  intensity = 0,   -- current rain intensity (eases toward the target)
  wetness   = 0,   -- how wet surfaces are 0..1 (lags behind the rain)
}

local uiTimer = 0
local applyTimer = 0
local saveTimer = nil

-- Nothing in the world is touched until a map is loaded and has settled.
-- Creating rain objects or changing ground models at the main menu can
-- crash the game.
local levelReady = false
local readyDelay = 0
local READY_DELAY = 3 -- seconds after the map loads

-- Helpers ---------------------------------------------------------------

local function clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end

local function targetIntensity()
  return settings.rainOn and settings.intensity or 0
end

local function mergeSettings(dst, src)
  for k, v in pairs(src or {}) do
    if type(v) == "table" and type(dst[k]) == "table" then
      mergeSettings(dst[k], v)
    elseif dst[k] ~= nil and type(dst[k]) == type(v) then
      dst[k] = v
    end
  end
end

local function loadSettings()
  local ok, data = pcall(jsonReadFile, settingsPath)
  if ok and type(data) == "table" then
    -- Older settings files had wet grip on by default: drop that choice
    if data.version ~= SETTINGS_VERSION and type(data.features) == "table" then
      data.features.grip = nil
    end
    data.version = nil
    mergeSettings(settings, data)
  end
  settings.version = SETTINGS_VERSION
  -- Every game session starts dry; rain only starts when you ask for it
  settings.rainOn = false
end

local function levelIsLoaded()
  local ok, mg = pcall(function() return scenetree and scenetree.MissionGroup end)
  return ok and mg ~= nil
end

local function saveSettingsSoon() saveTimer = 1.0 end

local function saveSettings()
  local ok, err = pcall(jsonWriteFile, settingsPath, settings, true)
  if not ok then log("W", logTag, "Could not save settings: " .. tostring(err)) end
end

local function cameraName()
  if core_camera and core_camera.getActiveCamName then
    local ok, name = pcall(core_camera.getActiveCamName, 0)
    if ok and name then return name end
  end
  return "unknown"
end

-- Cameras that look out through the windshield
local IN_CAR_WORDS = {"driver", "cockpit", "interior", "inside", "onboard", "relative", "firstperson", "first_person", "dash"}
local NOT_IN_CAR = {"hood", "bonnet", "bumper", "wheel", "rear", "mirror"}
local function isInCarCamera(cam)
  cam = string.lower(tostring(cam or ""))
  for _, w in ipairs(NOT_IN_CAR) do if string.find(cam, w, 1, true) then return false end end
  for _, w in ipairs(IN_CAR_WORDS) do if string.find(cam, w, 1, true) then return true end end
  return false
end

-- Is the camera physically inside the player's car? Works whatever the
-- camera is called: the driver seat is within ~2.5 m of the car's reference
-- point, while outside cameras are further away.
local IN_CAR_DISTANCE = 2.5
local function cameraInsideCar()
  local veh = (getPlayerVehicle and getPlayerVehicle(0)) or (be and be:getPlayerVehicle(0))
  if not veh then return false, nil end
  local camPos
  if core_camera and core_camera.getPosition then
    local ok, p = pcall(core_camera.getPosition)
    if ok and p then camPos = p end
  end
  if not camPos and getCameraPosition then
    local ok, p = pcall(getCameraPosition)
    if ok and p then camPos = p end
  end
  if not camPos then return false, nil end
  local ok, vp = pcall(function() return veh:getPosition() end)
  if not ok or not vp then return false, nil end
  local dx, dy, dz = camPos.x - vp.x, camPos.y - vp.y, camPos.z - vp.z
  local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
  return dist <= IN_CAR_DISTANCE, dist
end

local function playerSpeed()
  local veh = (getPlayerVehicle and getPlayerVehicle(0)) or (be and be:getPlayerVehicle(0))
  if not veh then return 0, nil end
  local ok, vel = pcall(function() return veh:getVelocity() end)
  local speed = 0
  if ok and vel then speed = vel:length() end
  return speed, veh
end

local function isPaused()
  for _, get in ipairs({
    function() return simTimeAuthority and simTimeAuthority.getPause and simTimeAuthority.getPause() end,
    function() return bullettime and bullettime.getPause and bullettime.getPause() end,
  }) do
    local ok, v = pcall(get)
    -- Only trust a real yes/no answer. In Lua the number 0 counts as true,
    -- so a numeric answer is compared explicitly.
    if ok and type(v) == "boolean" then return v end
    if ok and type(v) == "number" then return v ~= 0 end
  end
  return false
end

-- Short report for the panel's diagnostics line
local diagCache, diagTimer = nil, 0
local function diagnostics()
  local d = {}
  if beamngWeather_precipitation and beamngWeather_precipitation.getDebugInfo then
    local ok, info = pcall(beamngWeather_precipitation.getDebugInfo)
    if ok and info then d.rain = info.status end
  end
  if beamngWeather_splashes and beamngWeather_splashes.getStatus then d.splashes = beamngWeather_splashes.getStatus() end
  if beamngWeather_wetDroplets and beamngWeather_wetDroplets.getStatus then d.carDrops = beamngWeather_wetDroplets.getStatus() end
  if beamngWeather_wetRoads and beamngWeather_wetRoads.getStatus then d.roads = beamngWeather_wetRoads.getStatus() end
  d.mapLoaded = levelReady
  d.paused = isPaused()
  return d
end

local function sendUI()
  if not guihooks then return end
  local speed = playerSpeed()
  local cam = cameraName()
  local inside, camDist = cameraInsideCar()
  local inCar = isInCarCamera(cam) or inside
  guihooks.trigger("BeamNGWeatherUpdate", {
    rainOn     = settings.rainOn,
    target     = settings.intensity,
    intensity  = state.intensity,
    wetness    = state.wetness,
    wipers     = settings.wipers,
    speed      = speed,
    camera     = cam,
    inCar      = inCar,
    camDist    = camDist and math.floor(camDist * 10 + 0.5) / 10 or nil,
    quality    = settings.quality,
    features   = settings.features,
    wetSeconds = math.floor(1 / settings.wetRate + 0.5),
    drySeconds = math.floor(1 / settings.dryRate + 0.5),
    paused     = isPaused(),
    diag       = diagCache,
  })
end

local function pushToModules(force)
  if not levelReady or readyDelay > 0 then return end
  local f = settings.features
  if beamngWeather_precipitation then
    beamngWeather_precipitation.apply(state.intensity, f.particles, f.sky, force)
  end
  if beamngWeather_wetRoads then
    beamngWeather_wetRoads.apply(f.roads and state.wetness or 0, force)
  end
  if beamngWeather_wetBody then
    beamngWeather_wetBody.apply(f.body and state.wetness or 0, force)
  end
  if beamngWeather_splashes then
    beamngWeather_splashes.apply(f.particles and state.intensity or 0, f.splashes)
  end
  if beamngWeather_wetDroplets then
    beamngWeather_wetDroplets.apply(f.droplets and state.wetness or 0, force)
  end
  if beamngWeather_wetGrip then
    beamngWeather_wetGrip.apply(f.grip and state.wetness or 0, force)
  end
end

-- Public API ------------------------------------------------------------

function M.setIntensity(v)
  v = clamp(tonumber(v) or 0, 0, 1)
  if v <= 0.001 then
    settings.rainOn = false
  else
    settings.intensity = v
    settings.rainOn = true
  end
  saveSettingsSoon()
  sendUI()
end

function M.changeIntensity(delta)
  local base = settings.rainOn and settings.intensity or 0
  M.setIntensity(base + (tonumber(delta) or 0))
end

function M.toggleRain()
  settings.rainOn = not settings.rainOn
  if settings.rainOn and settings.intensity < 0.05 then settings.intensity = 0.6 end
  if ui_message then
    ui_message(settings.rainOn and "Rain started" or "Rain stopping", 3, "beamngWeather")
  end
  saveSettingsSoon()
  sendUI()
end

-- Set wetness at once (0..1), e.g. to start a session on soaked roads.
function M.setWetness(v)
  state.wetness = clamp(tonumber(v) or 0, 0, 1)
  pushToModules(true)
  sendUI()
end

function M.setWipers(mode)
  settings.wipers = clamp(math.floor(tonumber(mode) or 0), 0, 3)
  saveSettingsSoon()
  sendUI()
end

function M.cycleWipers()
  M.setWipers((settings.wipers + 1) % 4)
  if ui_message then
    local names = {[0] = "Wipers off", "Wipers intermittent", "Wipers slow", "Wipers fast"}
    ui_message(names[settings.wipers], 2, "beamngWeatherWipers")
  end
end

function M.setFeature(name, enabled)
  if settings.features[name] == nil then
    log("W", logTag, "Unknown feature: " .. tostring(name))
    return
  end
  settings.features[name] = enabled and true or false
  saveSettingsSoon()
  pushToModules(true)
  sendUI()
end

function M.setQuality(q)
  if q ~= "low" and q ~= "medium" and q ~= "high" and q ~= "ultra" then return end
  settings.quality = q
  if beamngWeather_precipitation and beamngWeather_precipitation.setQuality then
    beamngWeather_precipitation.setQuality(q)
  end
  if beamngWeather_splashes and beamngWeather_splashes.setQuality then
    beamngWeather_splashes.setQuality(q)
  end
  saveSettingsSoon()
  sendUI()
end

function M.setRates(wetSeconds, drySeconds)
  if tonumber(wetSeconds) and wetSeconds > 0 then settings.wetRate = 1 / wetSeconds end
  if tonumber(drySeconds) and drySeconds > 0 then settings.dryRate = 1 / drySeconds end
  saveSettingsSoon()
  sendUI()
end

function M.resetSettings()
  settings = deepcopy(defaults)
  saveSettings()
  pushToModules(true)
  sendUI()
end

function M.getState()
  return {settings = deepcopy(settings), intensity = state.intensity, wetness = state.wetness}
end

-- Console: beamngWeather_rain.debug()  prints what the mod sees and does
function M.debug()
  local lines = {}
  local function add(k, v)
    if type(v) == "table" then v = table.concat((function() local t = {} for _, x in pairs(v) do t[#t + 1] = tostring(x) end return t end)(), ", ") end
    lines[#lines + 1] = string.format("  %-20s %s", k, tostring(v))
  end
  add("rainOn", settings.rainOn)
  add("target intensity", settings.intensity)
  add("intensity now", string.format("%.2f", state.intensity))
  add("wetness", string.format("%.2f", state.wetness))
  add("camera", cameraName())
  local f = {}
  for k, v in pairs(settings.features) do f[#f + 1] = k .. "=" .. tostring(v) end
  add("features", f)
  if beamngWeather_precipitation and beamngWeather_precipitation.getDebugInfo then
    for k, v in pairs(beamngWeather_precipitation.getDebugInfo(true)) do add("rain." .. k, v) end
  end
  for k, v in pairs(diagnostics()) do add("status." .. k, v) end
  local text = "BeamNG Weather debug:\n" .. table.concat(lines, "\n")
  print(text)
  log("I", logTag, text)
  return text
end

-- Called by the UI app when it loads, so it gets data at once.
function M.requestUIUpdate() sendUI() end

-- Hooks -----------------------------------------------------------------

function M.onUpdate(dtReal, dtSim, dtRaw)
  local dt = dtReal or 0
  if dt <= 0 then return end
  if dt > 0.25 then dt = 0.25 end

  -- Ease intensity toward the target (about 6 s to change fully)
  local target = targetIntensity()
  local step = dt / 6
  if state.intensity < target then
    state.intensity = math.min(target, state.intensity + step)
  elseif state.intensity > target then
    state.intensity = math.max(target, state.intensity - step)
  end

  -- Wetness grows with rain and dries slowly when it stops.
  -- Light rain only soaks the road part of the way.
  local wetCap = clamp(0.35 + state.intensity, 0, 1)
  if state.intensity > 0.02 and state.wetness < wetCap then
    state.wetness = math.min(wetCap, state.wetness + settings.wetRate * (0.3 + state.intensity) * dt)
  elseif state.intensity <= 0.02 then
    state.wetness = math.max(0, state.wetness - settings.dryRate * dt)
  end

  if readyDelay > 0 then
    readyDelay = readyDelay - dt
    if readyDelay <= 0 then readyDelay = 0; pushToModules(true) end
  end

  applyTimer = applyTimer + dt
  if applyTimer >= 0.25 then
    applyTimer = 0
    local ok, err = pcall(pushToModules, false)
    if not ok then log("E", logTag, "Update failed: " .. tostring(err)) end
  end

  diagTimer = diagTimer - dt
  if diagTimer <= 0 then diagTimer = 1; diagCache = diagnostics() end

  uiTimer = uiTimer + dt
  if uiTimer >= 0.1 then
    uiTimer = 0
    sendUI()
  end

  if saveTimer then
    saveTimer = saveTimer - dt
    if saveTimer <= 0 then saveTimer = nil; saveSettings() end
  end
end

function M.onExtensionLoaded()
  loadSettings()
  state.intensity, state.wetness = 0, 0
  if beamngWeather_precipitation and beamngWeather_precipitation.setQuality then
    beamngWeather_precipitation.setQuality(settings.quality)
  end
  if beamngWeather_splashes and beamngWeather_splashes.setQuality then
    beamngWeather_splashes.setQuality(settings.quality)
  end
  -- The mod can be turned on while a map is already loaded
  levelReady = levelIsLoaded()
  readyDelay = levelReady and READY_DELAY or 0
  log("I", logTag, "Rain Overhaul loaded" .. (levelReady and " (map already loaded)" or ""))
end

function M.onExtensionUnloaded()
  -- Put the world back to dry
  state.wetness, state.intensity = 0, 0
  if levelReady then pushToModules(true) end
  if saveTimer then saveSettings() end
end

function M.onClientPostStartMission()
  -- A map finished loading: wait a moment, then the sub-modules rescan it
  levelReady = true
  readyDelay = READY_DELAY
end

function M.onClientEndMission()
  levelReady = false
  readyDelay = 0
  if saveTimer then saveTimer = nil; saveSettings() end
end

return M
