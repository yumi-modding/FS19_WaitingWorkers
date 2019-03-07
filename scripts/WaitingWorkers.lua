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

WaitingWorkers.debug = true --false --
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
    self.implementStopTimerDuration = 10000  -- 10s in debug
    self.engineStopTimerDuration = 15000     -- 15s in debug
  end
  self.implementStopTimers = {}
  self.engineStopTimers = {}
end

-- @doc Prevent to stop motor when worker end
function WaitingWorkers:preOnStopAiVehicle()
  if WaitingWorkers.debug then print("WaitingWorkers:preOnStopAiVehicle "..tostring(WaitingWorkers:getFullName(self))) end
  if self.aiIsStarted then
    printCallstack()
    local vehicleID = networkGetObjectId(self)
    table.insert(WaitingWorkers.engineStopTimers, {
      id = vehicleID,
      timer = WaitingWorkers.engineStopTimerDuration
    })
  end
end
AIVehicle.onStopAiVehicle = Utils.prependedFunction(AIVehicle.onStopAiVehicle, WaitingWorkers.preOnStopAiVehicle)

-- @doc Prevent to stop motor when worker end
function WaitingWorkers:replaceStopMotor(superfunc, noEventSend)
  if WaitingWorkers.debug then print("WaitingWorkers:replaceStopMotor "..tostring(WaitingWorkers:getFullName(self))) end
  local vehicleID = networkGetObjectId(self)
  local bDontStopMotor = false
  if WaitingWorkers.engineStopTimers ~= nil then
    for _, vehicle in pairs(WaitingWorkers.engineStopTimers) do
      if vehicle.id == vehicleID then
        bDontStopMotor = true
        break
      end
    end
  end
  if bDontStopMotor then
    return
  end
  return superfunc(self, noEventSend)
end
Motorized.stopMotor = Utils.overwrittenFunction(Motorized.stopMotor, WaitingWorkers.replaceStopMotor)

-- @doc Prevent to stop motor and implements when player takes back vehicle control
function WaitingWorkers:appStopAIVehicle(reason, noEventSend)
  if WaitingWorkers.debug then print("WaitingWorkers:appStopAIVehicle>>") end
  if self.isControlled and reason ~= nil and reason == AIVehicle.STOP_REASON_USER then
    if WaitingWorkers.debug then print("WaitingWorkers:appStopAIVehicle STOP_REASON_USER") end
    local vehicleID = networkGetObjectId(self)
    if WaitingWorkers.engineStopTimers ~= nil then
      for i=#WaitingWorkers.engineStopTimers, 1, -1 do
        if WaitingWorkers.engineStopTimers[i].id == vehicleID then
          table.remove(WaitingWorkers.engineStopTimers, i)
          if WaitingWorkers.implementStopTimers ~= nil then
            for j=#WaitingWorkers.implementStopTimers, 1, -1 do
              if WaitingWorkers.implementStopTimers[j].rootId == vehicleID then
                table.remove(WaitingWorkers.implementStopTimers, j)
              end
            end
          end
          break
        end
      end
    end
  end
  if WaitingWorkers.debug then print("WaitingWorkers:appStopAIVehicle<<") end
end
AIVehicle.stopAIVehicle = Utils.appendedFunction(AIVehicle.stopAIVehicle, WaitingWorkers.appStopAIVehicle)

-- @doc Prevent to stop implement when worker end
function WaitingWorkers:replaceOnAiTurnOff(superfunc)
  if WaitingWorkers.debug then print("WaitingWorkers:replaceOnAiTurnOff "..tostring(WaitingWorkers:getFullName(self))) end
  if self.specializations ~= nil then
    -- Always stop sprayer with effects (for liquid fertilizer for ex.) but don't stop other sprayers like sowingMachine for instance
    if SpecializationUtil.hasSpecialization(Sprayer, self.specializations) then
      if self.sprayerEffects ~= nil then
        if #self.sprayerEffects > 0 then
          if WaitingWorkers.debug then print("WaitingWorkers:replaceOnAiTurnOff - No replace for Sprayer with effects") end
          return superfunc(self)
        end
      end
    end
  end
  local implementID = networkGetObjectId(self)
  local rootVehicle = self:getRootAttacherVehicle()
  local rootId = nil
  if rootVehicle ~= nil then
    rootId = networkGetObjectId(rootVehicle)
  end
  table.insert(WaitingWorkers.implementStopTimers, {
    id = implementID,
    rootId = rootId,
    timer = WaitingWorkers.implementStopTimerDuration,
    superfunc = superfunc
  })
  return
end
TurnOnVehicle.onAiTurnOff = Utils.overwrittenFunction(TurnOnVehicle.onAiTurnOff, WaitingWorkers.replaceOnAiTurnOff)

-- @doc Prevent to stop implement when worker has been stopped and restarted
function WaitingWorkers:appOnAiTurnOn()
  if WaitingWorkers.debug then print("WaitingWorkers:appOnAiTurnOn ") end
  local implementID = networkGetObjectId(self)
  if WaitingWorkers.implementStopTimers ~= nil then
    for i=#WaitingWorkers.implementStopTimers, 1, -1 do
      if WaitingWorkers.implementStopTimers[i].id == implementID then
        table.remove(WaitingWorkers.implementStopTimers, i)
        break
      end
    end
  end
end
Vehicle.onAiTurnOn = Utils.appendedFunction(Vehicle.onAiTurnOn, WaitingWorkers.appOnAiTurnOn)


function WaitingWorkers:mouseEvent(posX, posY, isDown, isUp, button)
end;

function WaitingWorkers:keyEvent(unicode, sym, modifier, isDown)
end;

function WaitingWorkers:draw()
end;

-- @doc Check timers during map update calls
function WaitingWorkers:update(dt)
  -- DebugUtil.printTableRecursively(self.implementStopTimers, " ", 1, 3);
  -- if WaitingWorkers.debug then print("WaitingWorkers:update ") end
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
      if implement.timer <= 0 then
        table.remove(self.implementStopTimers, i)
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

  -- Clean table by removing already stopped engines
  for i=#self.engineStopTimers, 1, -1 do
    local vehicle = self.engineStopTimers[i]
    if vehicle ~= nil then
      if vehicle.timer <= 0 then
        table.remove(self.engineStopTimers, i)
      end
    end
  end

end

-- @doc Call default onAIImplementEnd function now
function WaitingWorkers:stopImplement(implement)
  if WaitingWorkers.debug then print("WaitingWorkers:stopImplement ") end
  if implement.id ~= nil then
    local i = networkGetObject(implement.id)
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
    local v = networkGetObject(vehicle.id)
    if v ~= nil then
      --vehicle.superfunc(v)
      -- Remove vehicle from list
      for i=#self.engineStopTimers, 1, -1 do
        local v = self.engineStopTimers[i]
        if v ~= nil then
          if v.id == vehicle.id then
            table.remove(self.engineStopTimers, i)
          end
        end
      end
      -- and call stopMotor
      v:stopMotor()
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
        -- printCallstack()
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK,
        WaitingWorkers:getFullName(item) .. g_i18n:getText("WaitingWorkers_VEHICLE_HAS_STOPPED"))
        -- string.format(g_i18n:getText("WaitingWorkers_VEHICLE_HAS_STOPPED")), item:getFullName())
        --item:getFullName().." has stopped due to inactivity.")
      end
    end
  end
end

-- @doc Build vehicle full name
function WaitingWorkers:getFullName(item)
  local name = "Unknown"
  local storeItem = StoreItemsUtil.storeItemsByXMLFilename[item.configFileName:lower()]
  if storeItem ~= nil then
    name = tostring(storeItem.name)
  end
  return name
end

addModEventListener(WaitingWorkers);
