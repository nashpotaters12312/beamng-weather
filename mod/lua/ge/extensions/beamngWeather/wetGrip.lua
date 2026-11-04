-- BeamNG Weather: wet grip (extension name: beamngWeather_wetGrip) — EXPERIMENTAL
--
-- Lowers the friction of paved ground models (asphalt, concrete, road lines...)
-- while the road is wet, so braking distances get longer and the car slides
-- sooner. If the game ships an ASPHALT_WET ground model, its numbers are used
-- as the "fully wet" target.
--
-- Changing ground models makes the game reload collision, which can cause a
-- short hitch on big maps. To keep that rare, grip only changes in 4 stages:
-- dry, damp, wet and soaked.

local M = {}
local logTag = "beamngWeather"

-- Ground models treated as paved road
local PAVED = {"ASPHALT", "ASPHALT_OLD", "ASPHALT_PREPPED", "CONCRETE", "RUMBLE_STRIP", "COBBLESTONE", "KERB"}
local WET_SOURCE = "ASPHALT_WET"

-- Fallback: at full wetness, keep this share of dry friction
local WET_STATIC_MULT  = 0.75
local WET_SLIDING_MULT = 0.68

local STAGES = {0, 0.33, 0.66, 1.0}

local dryModels = nil   -- [name] = table of the dry values
local wetTarget = nil   -- values from ASPHALT_WET, if present
local currentStage = 1
local available = nil   -- nil = not checked yet, false = API missing

local function deepcopyTable(t)
  local o = {}
  for k, v in pairs(t) do o[k] = type(v) == "table" and deepcopyTable(v) or v end
  return o
end

-- Find ground models in the game's json (it can be flat or nested)
local function collectModels(tbl, out)
  for k, v in pairs(tbl) do
    if type(v) == "table" then
      if v.staticFrictionCoefficient then
        out[string.upper(tostring(k))] = v
      else
        collectModels(v, out)
      end
    end
  end
end

local function loadDryModels()
  dryModels = {}
  local all = {}
  for _, path in ipairs({"art/groundmodels.json", "/art/groundmodels.json"}) do
    local ok, data = pcall(jsonReadFile, path)
    if ok and type(data) == "table" then collectModels(data, all); break end
  end
  -- A level may add or override ground models
  local levelPath = nil
  if getMissionFilename then
    local ok, mis = pcall(getMissionFilename)
    if ok and type(mis) == "string" and mis ~= "" then levelPath = string.match(mis, "^(.*/)") end
  end
  if levelPath then
    local ok, data = pcall(jsonReadFile, levelPath .. "groundmodels.json")
    if ok and type(data) == "table" then collectModels(data, all) end
    ok, data = pcall(jsonReadFile, levelPath .. "art/groundmodels.json")
    if ok and type(data) == "table" then collectModels(data, all) end
  end
  for _, name in ipairs(PAVED) do
    if all[name] then dryModels[name] = deepcopyTable(all[name]) end
  end
  if all[WET_SOURCE] then wetTarget = deepcopyTable(all[WET_SOURCE]) end
  local n = 0
  for _ in pairs(dryModels) do n = n + 1 end
  log("I", logTag, string.format("Wet grip: %d paved ground models found%s", n, wetTarget and " (using ASPHALT_WET)" or ""))
end

local function checkApi()
  available = (be ~= nil and be.setGroundModel ~= nil)
  if not available then
    log("W", logTag, "Wet grip: be:setGroundModel is missing in this game version, grip stays dry")
  end
  return available
end

local function frictionFor(name, dry, wet)
  local gm = deepcopyTable(dry)
  local sMul, kMul = WET_STATIC_MULT, WET_SLIDING_MULT
  if wetTarget and dryModels.ASPHALT and wetTarget.staticFrictionCoefficient then
    -- Use the game's own dry -> wet asphalt ratio for every paved surface
    local a = dryModels.ASPHALT
    sMul = wetTarget.staticFrictionCoefficient / math.max(0.01, a.staticFrictionCoefficient)
    kMul = (wetTarget.slidingFrictionCoefficient or a.slidingFrictionCoefficient) / math.max(0.01, a.slidingFrictionCoefficient or 1)
    sMul, kMul = math.min(1, sMul), math.min(1, kMul)
  end
  gm.staticFrictionCoefficient = dry.staticFrictionCoefficient * (1 + (sMul - 1) * wet)
  if dry.slidingFrictionCoefficient then
    gm.slidingFrictionCoefficient = dry.slidingFrictionCoefficient * (1 + (kMul - 1) * wet)
  end
  return gm
end

local function setStage(stage)
  if available == nil then checkApi() end
  if not available then return end
  if not dryModels then loadDryModels() end
  local wet = STAGES[stage]
  local failed, total = 0, 0
  for name, dry in pairs(dryModels) do
    total = total + 1
    local gm = (wet <= 0) and dry or frictionFor(name, dry, wet)
    local ok = pcall(function() be:setGroundModel(name, gm) end)
    if not ok then failed = failed + 1 end
  end
  if failed > 0 then
    log("W", logTag, string.format("Wet grip: %d ground models could not be changed", failed))
    if failed == total then
      available = false -- the API is there but does not take our data: stop trying
      return
    end
  end
  -- Collision has to reload for new ground values to be used
  if be.reloadCollision then pcall(function() be:reloadCollision() end) end
  currentStage = stage
end

function M.apply(wet, force)
  wet = math.max(0, math.min(1, wet or 0))
  -- Pick the stage, with a small gap so it does not flip back and forth
  local stage = 1
  if wet > 0.05 then
    for i = #STAGES, 2, -1 do
      if wet >= STAGES[i] - 0.05 then stage = i; break end
    end
    if stage == 1 then stage = 2 end -- any real wetness counts as damp
  end
  if stage == currentStage and not force then return end
  if stage == 1 and currentStage == 1 and not dryModels then return end -- never touched
  setStage(stage)
end

function M.onClientEndMission()
  dryModels, wetTarget, currentStage = nil, nil, 1
end

function M.onExtensionUnloaded()
  if dryModels and currentStage ~= 1 then setStage(1) end
end

return M
