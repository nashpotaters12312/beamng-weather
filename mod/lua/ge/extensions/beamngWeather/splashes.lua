-- BeamNG Weather: rain splashes on the ground (extension name: beamngWeather_splashes)
--
-- Replaces the flat, built-in rain splash pictures with particle splashes:
--   crown:  tiny water droplets thrown up and falling back where a drop lands
--   ripple: a ring that lies flat on the ground and spreads out
-- A pool of particle emitters is moved to new random spots on the ground
-- around the camera every frame, so splashes appear all over the road.
-- Ground height comes from a ray cast down at each spot.

local M = {}
local logTag = "beamngWeather"

local NAMES = {
  dropData     = "beamngWeather_splashDropData",
  rippleData   = "beamngWeather_splashRippleData",
  crownEmitter = "beamngWeather_splashCrownEmitter",
  rippleEmitter= "beamngWeather_splashRippleEmitter",
  nodeData     = "beamngWeather_splashNodeData",
  nodePrefix   = "beamngWeather_splashNode",
}

-- Emitter pairs (crown + ripple) per quality level
local POOL = { low = 4, medium = 8, high = 12, ultra = 20 }
-- Each frame only some emitters jump to a new spot (round robin), so the
-- Lua work and ground ray casts per frame stay small
local MOVES_PER_FRAME = { low = 2, medium = 3, high = 4, ultra = 6 }
local moveCursor = 0
local RADIUS = 22        -- metres around the camera
local MIN_RADIUS = 0.8   -- not right on top of the camera

local nodes = {}         -- { {crown=obj, ripple=obj}, ... }
local ready = false
local tried = false
local quality = "high"
local intensity = 0
local enabled = true
local status = "not started"

local function findObj(name)
  local ok, o = pcall(scenetree.findObject, name)
  if ok then return o end
  return nil
end

local function setF(obj, field, idx, value) obj:setField(field, idx, tostring(value)) end

local function makeDatablock(cls, name, fields, indexed)
  local existing = findObj(name)
  if existing then return true end
  local ok, err = pcall(function()
    local o = createObject(cls)
    for k, v in pairs(fields) do setF(o, k, 0, v) end
    for k, list in pairs(indexed or {}) do
      for i, v in ipairs(list) do setF(o, k, i - 1, v) end
    end
    o:registerObject(name)
  end)
  if not ok then log("W", logTag, "Splashes: could not make " .. name .. ": " .. tostring(err)) end
  return ok and findObj(name) ~= nil
end

local function makeDatablocks()
  local ok = true
  ok = ok and makeDatablock("ParticleData", NAMES.dropData, {
    textureName = "/art/beamng_weather/splash_droplet.png",
    lifetimeMS = 260, lifetimeVarianceMS = 70,
    gravityCoefficient = 1.6, dragCoefficient = 0.6, inheritedVelFactor = 0,
    windCoefficient = 0.2, useInvAlpha = 0,
    spinRandomMin = 0, spinRandomMax = 0,
  }, {
    colors = {"0.85 0.9 0.95 0.85", "0.8 0.86 0.92 0.6", "0.8 0.86 0.92 0"},
    sizes  = {0.022, 0.018, 0.010},
    times  = {0, 0.6, 1},
  })
  ok = ok and makeDatablock("ParticleData", NAMES.rippleData, {
    textureName = "/art/beamng_weather/splash_ripple.png",
    lifetimeMS = 520, lifetimeVarianceMS = 120,
    gravityCoefficient = 0, dragCoefficient = 0, inheritedVelFactor = 0,
    windCoefficient = 0, useInvAlpha = 0,
    spinRandomMin = -180, spinRandomMax = 180,
  }, {
    colors = {"0.8 0.86 0.92 0.55", "0.8 0.86 0.92 0.3", "0.8 0.86 0.92 0"},
    sizes  = {0.03, 0.22, 0.34},
    times  = {0, 0.5, 1},
  })
  -- Crown: a burst of drops thrown up in a cone
  ok = ok and makeDatablock("ParticleEmitterData", NAMES.crownEmitter, {
    particles = NAMES.dropData,
    ejectionPeriodMS = 8, periodVarianceMS = 2,
    ejectionVelocity = 1.5, velocityVariance = 0.7, ejectionOffset = 0.01,
    thetaMin = 5, thetaMax = 40, phiReferenceVel = 0, phiVariance = 360,
    blendStyle = "NORMAL", softnessDistance = 0,
  })
  -- Ripple: one flat ring per spot, lying on the ground
  ok = ok and makeDatablock("ParticleEmitterData", NAMES.rippleEmitter, {
    particles = NAMES.rippleData,
    ejectionPeriodMS = 30, periodVarianceMS = 6,
    ejectionVelocity = 0, velocityVariance = 0, ejectionOffset = 0.01,
    thetaMin = 0, thetaMax = 0, phiVariance = 0,
    alignParticles = 1, alignDirection = "0 0 1",
    blendStyle = "NORMAL", softnessDistance = 0,
  })
  ok = ok and makeDatablock("ParticleEmitterNodeData", NAMES.nodeData, { timeMultiple = 1 })
  return ok
end

local function makeNode(name, emitter)
  local old = findObj(name)
  if old then pcall(function() old:delete() end) end
  local node
  local ok, err = pcall(function()
    node = createObject("ParticleEmitterNode")
    setF(node, "dataBlock", 0, NAMES.nodeData)
    setF(node, "emitter", 0, emitter)
    setF(node, "active", 0, 0)
    setF(node, "velocity", 0, 1)
    setF(node, "canSave", 0, 0)
    node:registerObject(name)
    pcall(function() scenetree.MissionGroup:addObject(node) end)
  end)
  if not ok then log("W", logTag, "Splashes: could not make emitter: " .. tostring(err)); return nil end
  return node
end

local function setup()
  local ok, mg = pcall(function() return scenetree.MissionGroup end)
  if not ok or not mg then return end
  tried = true
  if not makeDatablocks() then
    status = "particle datablocks could not be made"
    return
  end
  local n = POOL[quality] or POOL.high
  for i = 1, n do
    local crown = makeNode(NAMES.nodePrefix .. "C" .. i, NAMES.crownEmitter)
    local ripple = makeNode(NAMES.nodePrefix .. "R" .. i, NAMES.rippleEmitter)
    if crown and ripple then nodes[#nodes + 1] = {crown = crown, ripple = ripple, on = false} end
  end
  ready = #nodes > 0
  status = ready and string.format("%d splash emitters", #nodes) or "no splash emitters could be made"
  log("I", logTag, "Splashes: " .. status)
  -- The built-in flat splashes are no longer needed
  if ready and beamngWeather_precipitation and beamngWeather_precipitation.setBuiltInSplashes then
    beamngWeather_precipitation.setBuiltInSplashes(false)
  end
end

local function destroy()
  for _, n in ipairs(nodes) do
    pcall(function() n.crown:delete() end)
    pcall(function() n.ripple:delete() end)
  end
  nodes, ready = {}, false
end

-- Camera position, from whichever helper this game version has
local function cameraPos()
  if core_camera and core_camera.getPosition then
    local ok, p = pcall(core_camera.getPosition)
    if ok and p then return p end
  end
  if getCameraPosition then
    local ok, p = pcall(getCameraPosition)
    if ok and p then return p end
  end
  return nil
end

-- Ground height below a point, or nil
local function groundZ(x, y, z)
  if castRayStatic then
    local ok, d = pcall(castRayStatic, vec3(x, y, z + 15), vec3(0, 0, -1), 80)
    if ok and type(d) == "number" and d < 80 then return z + 15 - d end
  end
  if be and be.getSurfaceHeightBelow then
    local ok, h = pcall(function() return be:getSurfaceHeightBelow(vec3(x, y, z + 15)) end)
    if ok and type(h) == "number" and h > -1e6 then return h end
  end
  return nil
end

local function setActive(n, on)
  if n.on == on then return end
  pcall(function() setF(n.crown, "active", 0, on and 1 or 0) end)
  pcall(function() setF(n.ripple, "active", 0, on and 1 or 0) end)
  n.on = on
end

local function moveNode(n, cam)
  local a = math.random() * 2 * math.pi
  local r = MIN_RADIUS + (RADIUS - MIN_RADIUS) * (math.random() ^ 1.6)
  local x, y = cam.x + math.cos(a) * r, cam.y + math.sin(a) * r
  local z = groundZ(x, y, cam.z)
  if not z then return false end -- nowhere to land (over water, off the map)
  local p = vec3(x, y, z + 0.01)
  pcall(function() n.crown:setPosition(p) end)
  pcall(function() n.ripple:setPosition(p) end)
  return true
end

function M.onUpdate(dtReal)
  if not ready then return end
  local want = enabled and math.floor(#nodes * math.min(1, intensity * 1.15) + 0.5) or 0
  if want == 0 then
    for _, n in ipairs(nodes) do setActive(n, false) end
    return
  end
  local cam = cameraPos()
  if not cam then return end
  for i = want + 1, #nodes do setActive(nodes[i], false) end
  -- Move a few of the active emitters to new spots this frame
  local moves = math.min(want, MOVES_PER_FRAME[quality] or 4)
  for _ = 1, moves do
    moveCursor = moveCursor % want + 1
    local n = nodes[moveCursor]
    setActive(n, moveNode(n, cam))
  end
end

-- Called by the main controller
function M.apply(rainIntensity, on)
  intensity = rainIntensity or 0
  enabled = on and true or false
  if enabled and intensity > 0 and not tried then setup() end
end

function M.setQuality(q)
  if not POOL[q] then return end
  local changed = q ~= quality
  quality = q
  if changed and tried then destroy(); tried = false end -- rebuilt on next rain
end

function M.getStatus() return status end

function M.onClientEndMission() nodes, ready, tried = {}, false, false; status = "not started" end

function M.onExtensionUnloaded() destroy() end

return M
