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
  "beamngWeather_wetGrip",
}

local logTag = "beamngWeather"
local settingsPath = "settings/beamng_weather.json"

-- Default settings, saved to the user folder
local defaults = {
  intensity      = 0.6,   -- target rain intensity 0..1 used when rain is on
  rainOn         = false,
  wetRate        = 1/45,  -- wetness gained per second at full intensity (fully wet in ~45 s)
  dryRate        = 1/240, -- wetness lost per second when dry (~4 min to dry out)
  wipers         = 0,     -- 0 off, 1 intermittent, 2 slow, 3 fast
  features = {
    particles  = true,  -- falling rain
    sky        = true,  -- clouds, fog and wind follow the rain
    roads      = true,  -- wet roads
    body       = true,  -- wet car paint
    grip       = true,  -- less grip on wet roads
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
  if ok and type(data) == "table" then mergeSettings(settings, data) end
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

local function playerSpeed()
  local veh = (getPlayerVehicle and getPlayerVehicle(0)) or (be and be:getPlayerVehicle(0))
  if not veh then return 0, nil end
  local ok, vel = pcall(function() return veh:getVelocity() end)
  local speed = 0
  if ok and vel then speed = vel:length() end
  return speed, veh
end

local function sendUI()
  if not guihooks then return end
  local speed = playerSpeed()
  local cam = cameraName()
  guihooks.trigger("BeamNGWeatherUpdate", {
    rainOn     = settings.rainOn,
    target     = settings.intensity,
    intensity  = state.intensity,
    wetness    = state.wetness,
    wipers     = settings.wipers,
    speed      = speed,
    camera     = cam,
    inCar      = (cam == "driver" or cam == "onboard.driver" or cam == "relative"),
    features   = settings.features,
    wetSeconds = math.floor(1 / settings.wetRate + 0.5),
    drySeconds = math.floor(1 / settings.dryRate + 0.5),
  })
end

local function pushToModules(force)
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
    for k, v in pairs(beamngWeather_precipitation.getDebugInfo()) do add("rain." .. k, v) end
  end
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

  applyTimer = applyTimer + dt
  if applyTimer >= 0.25 then
    applyTimer = 0
    pushToModules(false)
  end

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
  -- Start at a wetness that matches the saved rain state.
  state.intensity = targetIntensity()
  state.wetness = settings.rainOn and clamp(0.35 + state.intensity, 0, 1) or 0
  log("I", logTag, "Rain Overhaul loaded")
end

function M.onExtensionUnloaded()
  -- Put the world back to dry
  state.wetness, state.intensity = 0, 0
  pushToModules(true)
  if saveTimer then saveSettings() end
end

function M.onClientPostStartMission()
  -- A new level was loaded: the sub-modules rescan their objects
  pushToModules(true)
end

function M.onClientEndMission()
  if saveTimer then saveTimer = nil; saveSettings() end
end

return M
