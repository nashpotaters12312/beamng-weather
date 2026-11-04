-- BeamNG Weather: wet car paint (extension name: beamngWeather_wetBody)
--
-- Every vehicle stores three paints in its "metallicPaintData" field as
-- 12 numbers: metallic, roughness, clearcoat, clearcoatRoughness for each
-- paint. In the rain the mod lowers the roughness and makes the clear coat
-- smooth and strong, so the body looks soaked and glossy, with sharper
-- reflections. When it dries the saved paint is put back.
--
-- If the player changes the paint while it's wet, the mod notices that the
-- value is not the one it wrote and takes the new paint as the dry original.

local M = {}
local logTag = "beamngWeather"

local WET_ROUGH_MULT  = 0.35
local WET_CLEARCOAT   = 1.0
local WET_CC_ROUGH    = 0.02

local tracked = {}   -- [vehId] = {orig = {12 numbers}, written = "string"}
local lastWet = -1
local STEP = 0.02
local warned = false

local function parse(s)
  if type(s) ~= "string" then return nil end
  local t = {}
  for n in string.gmatch(s, "[-%d%.eE]+") do t[#t + 1] = tonumber(n) end
  if #t < 4 or #t % 4 ~= 0 then return nil end
  return t
end

local function encode(t)
  local parts = {}
  for i = 1, #t do parts[i] = string.format("%.4f", t[i]) end
  return table.concat(parts, " ")
end

local function getPaint(veh)
  local ok, v = pcall(function() return veh:getField("metallicPaintData", 0) end)
  if ok and v and v ~= "" then return v end
  ok, v = pcall(function() return veh.metallicPaintData end)
  if ok and type(v) == "string" and v ~= "" then return v end
  return nil
end

local function setPaint(veh, s)
  local ok = pcall(function() veh:setField("metallicPaintData", 0, s) end)
  if not ok then ok = pcall(function() veh.metallicPaintData = s end) end
  if not ok and not warned then
    warned = true
    log("W", logTag, "Wet body: this game version does not allow paint changes from Lua")
  end
  return ok
end

local function wetPaint(orig, wet)
  local out = {}
  for i = 1, #orig, 4 do
    local metallic, rough, cc, ccr = orig[i], orig[i + 1], orig[i + 2], orig[i + 3]
    out[i]     = metallic
    out[i + 1] = rough + (rough * WET_ROUGH_MULT - rough) * wet
    out[i + 2] = cc + (math.max(cc, WET_CLEARCOAT) - cc) * wet
    out[i + 3] = ccr + (math.min(ccr, WET_CC_ROUGH) - ccr) * wet
  end
  return out
end

local function eachVehicle(fn)
  if not be or not be.getObjectCount then return end
  local count = be:getObjectCount()
  for i = 0, count - 1 do
    local veh = be:getObject(i)
    if veh then fn(veh) end
  end
end

local function applyVehicle(veh, wet)
  local id = veh:getID()
  local current = getPaint(veh)
  if not current then return end
  local t = tracked[id]
  if not t or current ~= t.written then
    -- New car, or the paint was changed by the player: this is the dry paint
    local orig = parse(current)
    if not orig then return end
    t = {orig = orig, written = current}
    tracked[id] = t
  end
  local s = (wet <= 0) and encode(t.orig) or encode(wetPaint(t.orig, wet))
  if s ~= t.written then
    if setPaint(veh, s) then
      -- Read back what the engine stored, so the next compare is exact
      t.written = getPaint(veh) or s
    end
  end
  if wet <= 0 then tracked[id] = nil end
end

function M.apply(wet, force)
  wet = math.max(0, math.min(1, wet or 0))
  local snapped = (wet <= 0) and 0 or (math.floor(wet / STEP + 0.5) * STEP)
  if not force and math.abs(snapped - lastWet) < STEP * 0.5 then return end
  if snapped <= 0 and next(tracked) == nil then lastWet = 0; return end
  eachVehicle(function(veh) applyVehicle(veh, snapped) end)
  lastWet = snapped
end

-- A new or replaced car gets the wet look right away
function M.onVehicleSpawned(vehId)
  tracked[vehId] = nil
  if lastWet > 0 then
    local veh = be:getObjectByID(vehId)
    if veh then applyVehicle(veh, lastWet) end
  end
end

function M.onVehicleResetted(vehId)
  if lastWet > 0 then
    local veh = be:getObjectByID(vehId)
    if veh then applyVehicle(veh, lastWet) end
  end
end

function M.onVehicleDestroyed(vehId) tracked[vehId] = nil end

function M.onClientEndMission() tracked = {}; lastWet = -1 end

function M.onExtensionUnloaded()
  eachVehicle(function(veh)
    local t = tracked[veh:getID()]
    if t then setPaint(veh, encode(t.orig)) end
  end)
  tracked = {}
end

return M
