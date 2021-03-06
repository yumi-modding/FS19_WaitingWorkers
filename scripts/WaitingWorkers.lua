--
-- WaitingWorkers
-- Specialization for preventing worker to stop engine and tools when task is finished.
-- Only stop after a given time and inform.
-- Update attached to update event of the map
--
-- @author  yumi
-- free for noncommercial-usage
--

WaitingWorkers = {};
WaitingWorkers.myCurrentModDirectory = g_currentModDirectory;

WaitingWorkers.debug = false --true --
-- TODO: Capability to change waiting time

-- @doc First code called during map loading (before we can actually interact)
function WaitingWorkers:loadMap(name)
  if WaitingWorkers.debug then print("WaitingWorkers:loadMap(name)") end
  self.initializing = true
  if self.initialized then
    return;
  end;
  self:init()
  self.initialized = true;
end;

-- @doc Last code called when leaving game
function WaitingWorkers:deleteMap()
  if WaitingWorkers.debug then print("WaitingWorkers:deleteMap()") end
  self.initialized = false;
end;
 
-- @doc Called once at the beginning when nothing is initialized yet
function WaitingWorkers:init()
  if WaitingWorkers.debug then print("WaitingWorkers:init()") end
  self.implementStopTimerDuration = 120000  -- 120s by default
  self.engineStopTimerDuration = 180000     -- 180s by default
  if WaitingWorkers.debug then 
    self.implementStopTimerDuration = 5000    -- 5s in debug
    self.engineStopTimerDuration = 10000     -- 10s in debug
  end
  self.implementStopTimers = {}
  self.engineStopTimers = {}
end

-- @doc Prevent to stop motor when worker end
function WaitingWorkers:replaceOnAIEnd(superfunc)
  if WaitingWorkers.debug then print("WaitingWorkers:replaceOnAIEnd "..tostring(self:getFullName())) end
  local vehicleID = NetworkUtil.getObjectId(self)
  -- print("WaitingWorkers:startTimer "..tostring(self:getFullName()))
  table.insert(WaitingWorkers.engineStopTimers, {
    id = vehicleID,
    timer = WaitingWorkers.engineStopTimerDuration,
    superfunc = superfunc
  })
  return
end
Motorized.onAIEnd = Utils.overwrittenFunction(Motorized.onAIEnd, WaitingWorkers.replaceOnAIEnd)

-- @doc Prevent to stop motor and implements when player takes back vehicle control 
function WaitingWorkers:appStopAIVehicle(reason, noEventSend)
  if WaitingWorkers.debug then print("WaitingWorkers:appStopAIVehicle>>") end
  -- DebugUtil.printTableRecursively(WaitingWorkers.implementStopTimers, " ", 1, 3);
  -- DebugUtil.printTableRecursively(WaitingWorkers.engineStopTimers, " ", 1, 3);
  if self:getIsControlled() then --and reason ~= nil and reason == AIVehicle.STOP_REASON_USER then
    -- Won't stop engine or implement if vehicle is controlled 
    if WaitingWorkers.debug then print("WaitingWorkers:appStopAIVehicle Worker vehicle is controlled") end
    local vehicleID = NetworkUtil.getObjectId(self)
    if WaitingWorkers.engineStopTimers ~= nil then
      for i=#WaitingWorkers.engineStopTimers, 1, -1 do
        if WaitingWorkers.engineStopTimers[i].id == vehicleID then
          self:restoreVehicleCharacter()
          table.remove(WaitingWorkers.engineStopTimers, i)
          -- print("WaitingWorkers:stopTimer "..tostring(self:getFullName()))
          if WaitingWorkers.implementStopTimers ~= nil then
            for j=#WaitingWorkers.implementStopTimers, 1, -1 do
              if WaitingWorkers.implementStopTimers[j].rootId == vehicleID then
                table.remove(WaitingWorkers.implementStopTimers, j)
                -- print("WaitingWorkers:stopTimer tool "..tostring(self:getFullName()))
              end
            end
          end
          break
        end
      end
    end
  end
  -- DebugUtil.printTableRecursively(WaitingWorkers.implementStopTimers, " ", 1, 3);
  -- DebugUtil.printTableRecursively(WaitingWorkers.engineStopTimers, " ", 1, 3);
  if WaitingWorkers.debug then print("WaitingWorkers:appStopAIVehicle<<") end
end
AIVehicle.stopAIVehicle = Utils.appendedFunction(AIVehicle.stopAIVehicle, WaitingWorkers.appStopAIVehicle)

-- @doc Prevent to stop implement when worker end
function WaitingWorkers:replaceOnAIImplementEnd(superfunc)
  if WaitingWorkers.debug then print("WaitingWorkers:replaceOnAIImplementEnd "..tostring(self:getFullName())) end
  if self.specializations ~= nil then
    -- Always stop sprayer with effects (for liquid fertilizer for ex.) but don't stop other sprayers like sowingMachine for instance
    if SpecializationUtil.hasSpecialization(Sprayer, self.specializations) then
      local spec = self.spec_sprayer
      if spec.effects ~= nil then
        if #spec.effects > 0 then
          if WaitingWorkers.debug then print("WaitingWorkers:replaceOnAIImplementEnd - No replace for Sprayer with effects") end
          return superfunc(self)
        end
      end
    end
  end
  local implementID = NetworkUtil.getObjectId(self)
  local rootVehicle = self:getRootVehicle()
  local rootId = nil
  if rootVehicle ~= nil then
    rootId = NetworkUtil.getObjectId(rootVehicle)
  end
  table.insert(WaitingWorkers.implementStopTimers, {
    id = implementID,
    rootId = rootId,
    timer = WaitingWorkers.implementStopTimerDuration,
    superfunc = superfunc
  })
  return
end
TurnOnVehicle.onAIImplementEnd = Utils.overwrittenFunction(TurnOnVehicle.onAIImplementEnd, WaitingWorkers.replaceOnAIImplementEnd)

-- @doc Prevent to stop implement when worker has been stopped and restarted
function WaitingWorkers:appOnAIImplementStart()
  if WaitingWorkers.debug then print("WaitingWorkers:appOnAIImplementStart ") end
  local implementID = NetworkUtil.getObjectId(self)
  if WaitingWorkers.implementStopTimers ~= nil then
    for i=#WaitingWorkers.implementStopTimers, 1, -1 do
      if WaitingWorkers.implementStopTimers[i].id == implementID then
        table.remove(WaitingWorkers.implementStopTimers, i)
        -- print("WaitingWorkers:stopTimer tool "..tostring(self:getFullName()))
        break
      end
    end
  end
end
TurnOnVehicle.onAIImplementStart = Utils.appendedFunction(TurnOnVehicle.onAIImplementStart, WaitingWorkers.appOnAIImplementStart)

-- @doc Prevent to lift the implement when Player takes back control inside the field
function WaitingWorkers:ReplaceOnAIImplementEndLine(superfunc)
  if WaitingWorkers.debug then print("WaitingWorkers:ReplaceOnAIImplementEndLine ") end
  local spec = self.spec_attachable
  local rootAttacherVehicle = self:getRootVehicle()
  if rootAttacherVehicle ~= nil then
    -- print("WaitingWorkers:ReplaceOnAIImplementEndLine rootAttacherVehicle "..tostring(rootAttacherVehicle:getName()))
    local vX,vY,vZ = getWorldTranslation(rootAttacherVehicle:getAIVehicleSteeringNode())
    local dt = 1  --unused value
    -- print("WaitingWorkers:ReplaceOnAIImplementEndLine getAIVehicleSteeringNode "..tostring(vX)..";"..tostring(vY)..";"..tostring(vZ))
    local spec_aiVehicle = rootAttacherVehicle.spec_aiVehicle
    if spec_aiVehicle ~= nil and #spec_aiVehicle.driveStrategies > 0 then
      -- Only consider 1st strategy to know if we are in the field
      local driveStrategy = spec_aiVehicle.driveStrategies[1]
      -- print("WaitingWorkers:driveStrategy"..tostring(driveStrategy))
      local distanceToEndOfField, hasField, ownedField = driveStrategy:getDistanceToEndOfField(dt, vX,vY,vZ)
      -- print("WaitingWorkers:ReplaceOnAIImplementEndLine distanceToEndOfField "..tostring(distanceToEndOfField))
      if rootAttacherVehicle:getIsControlled() and distanceToEndOfField > 0 then
        -- Player takes back control inside the field => we don't want to lift the implement
        return
      end
    end
  end
  superfunc(self)
end
Attachable.onAIImplementEndLine = Utils.overwrittenFunction(Attachable.onAIImplementEndLine, WaitingWorkers.ReplaceOnAIImplementEndLine)

-- @doc Prevent to remove driver character when worker is waiting
function WaitingWorkers:ReplaceRestoreVehicleCharacter(superfunc)
  if WaitingWorkers.debug then print("WaitingWorkers:ReplaceRestoreVehicleCharacter ") end
  if WaitingWorkers.engineStopTimers ~= nil then
    for _, vehicle in pairs(WaitingWorkers.engineStopTimers) do
      if vehicle ~= nil then
        if vehicle.id == NetworkUtil.getObjectId(self) then
          if WaitingWorkers.debug then print("WaitingWorkers:ReplaceRestoreVehicleCharacter delete character") end
          superfunc(self)
        end
      end
    end
  end
  if WaitingWorkers.debug then print("WaitingWorkers:ReplaceRestoreVehicleCharacter keep character") end
  return
end
Enterable.restoreVehicleCharacter = Utils.overwrittenFunction(Enterable.restoreVehicleCharacter, WaitingWorkers.ReplaceRestoreVehicleCharacter)

-- @doc Check timers during map update calls
function WaitingWorkers:update(dt)
  -- if WaitingWorkers.debug then print("WaitingWorkers:update ") end
  -- DebugUtil.printTableRecursively(self.implementStopTimers, " ", 1, 3);
  -- DebugUtil.printTableRecursively(self.engineStopTimers, " ", 1, 3);

  if self.implementStopTimers ~= nil then
    for _, implement in pairs(self.implementStopTimers) do
      implement.timer = implement.timer - dt
      if implement.timer <= 0 then
        -- Timer is over, request implement to stop
        WaitingWorkers:stopImplement(implement)
      end
    end
  end

  -- Clean table by removing already stopped implements
  for i=#self.implementStopTimers, 1, -1 do
    local implement = self.implementStopTimers[i]
    if implement ~= nil then
      local v = NetworkUtil.getObject(implement.rootId)
      if implement.timer <= 0 or (v ~= nil and v:getIsControlled()) then
        table.remove(self.implementStopTimers, i)
        -- print("WaitingWorkers:stopTimer tool "..tostring(v:getFullName()))
      end
    end
  end

  if self.engineStopTimers ~= nil then
    for _, vehicle in pairs(self.engineStopTimers) do
      vehicle.timer = vehicle.timer - dt
      if vehicle.timer <= 0 then
        -- Timer is over, request engine to stop
        WaitingWorkers:stopEngine(vehicle)
      end
    end
  end

  -- Clean table by removing already stopped engines or controlled vehicles
  for i=#self.engineStopTimers, 1, -1 do
    local vehicle = self.engineStopTimers[i]
    if vehicle ~= nil then
      local v = NetworkUtil.getObject(vehicle.id)
      if vehicle.timer <= 0 or (v ~= nil and v:getIsControlled()) then
        table.remove(self.engineStopTimers, i)
        -- print("WaitingWorkers:stopTimer "..tostring(v:getFullName()))
      end
    end
  end

end

-- @doc Call default onAIImplementEnd function now
function WaitingWorkers:stopImplement(implement)
  if WaitingWorkers.debug then print("WaitingWorkers:stopImplement ") end
  if implement.id ~= nil then
    local i = NetworkUtil.getObject(implement.id)
    if i ~= nil then
      implement.superfunc(i)
      -- WaitingWorkers:displayNotif(i)
    end
  end
end

-- @doc Call default onAIEnd function now
function WaitingWorkers:stopEngine(vehicle)
  if WaitingWorkers.debug then print("WaitingWorkers:stopEngine ") end
  if vehicle.id ~= nil then
    local v = NetworkUtil.getObject(vehicle.id)
    if v ~= nil then
      vehicle.superfunc(v)
      v:restoreVehicleCharacter()
      WaitingWorkers:displayNotif(v)
    end
  end
end

-- @doc Display a notif to inform user that engine has stop
function WaitingWorkers:displayNotif(item)
  if WaitingWorkers.debug then print("WaitingWorkers:displayNotif ") end
  if item ~= nil then
    if item.isClient then
      if g_currentMission.player ~= nil then
        if g_currentMission.accessHandler:canPlayerAccess(item) then
          g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK,
          item:getFullName() .. " " .. g_i18n:getText("WaitingWorkers_VEHICLE_HAS_STOPPED"))
          -- string.format(g_i18n:getText("WaitingWorkers_VEHICLE_HAS_STOPPED")), item:getFullName())
          --item:getFullName().." has stopped due to inactivity.")
        end
      end
    end
  end
end

addModEventListener(WaitingWorkers);
