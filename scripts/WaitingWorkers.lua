--
-- WaitingWorkers
-- Specialization for preventing worker to stop engine and tools when task is finished.
-- Only stop after a given time and inform.z
-- Update attached to update event of the map
--
-- @author  yumi
-- free for noncommercial-usage
--

WaitingWorkers = {};
WaitingWorkers.myCurrentModDirectory = g_currentModDirectory;

WaitingWorkers.debug = true --false --
-- TODO:


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
 
-- @doc register InputBindings if any
function WaitingWorkers:registerActionEvents()
  if WaitingWorkers.debug then print("WaitingWorkers:registerActionEvents()") end
  -- for _,actionName in pairs({ "" }) do
  --   -- print("actionName "..actionName)
  --   local __, eventName, event, action = InputBinding.registerActionEvent(g_inputBinding, actionName, self, WaitingWorkers.activateWorker ,false ,true ,false ,true)
  --   -- print("__ "..tostring(__))
  --   -- print("eventName "..eventName)
  --   -- print("event "..tostring(event))
  --   -- print("action "..tostring(action))
  --   if __ then
  --     g_inputBinding.events[eventName].displayIsVisible = false
  --   end
  --   -- DebugUtil.printTableRecursively(actionName, " ", 1, 2);
  --   --__, eventName = self:addActionEvent(self.actionEvents, actionName, self, WaitingWorkers.activateWorker, false, true, false, true)
  -- end
  
end

-- @doc registerActionEvents need to be called regularly
function WaitingWorkers:appRegisterActionEvents()
  if WaitingWorkers.debug then print("WaitingWorkers:appRegisterActionEvents()") end
  WaitingWorkers:registerActionEvents()
end
-- Only needed for global action event 
FSBaseMission.registerActionEvents = Utils.appendedFunction(FSBaseMission.registerActionEvents, WaitingWorkers.appRegisterActionEvents);

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
  vehicleID = NetworkUtil.getObjectId(self)
  table.insert(WaitingWorkers.engineStopTimers, {
    id = vehicleID,
    timer = WaitingWorkers.engineStopTimerDuration,
    superfunc = superfunc
  })
  return
end
Motorized.onAIEnd = Utils.overwrittenFunction(Motorized.onAIEnd, WaitingWorkers.replaceOnAIEnd)

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
  implementID = NetworkUtil.getObjectId(self)
  table.insert(WaitingWorkers.implementStopTimers, {
    id = implementID,
    timer = WaitingWorkers.implementStopTimerDuration,
    superfunc = superfunc
  })
  return
end
TurnOnVehicle.onAIImplementEnd = Utils.overwrittenFunction(TurnOnVehicle.onAIImplementEnd, WaitingWorkers.replaceOnAIImplementEnd)

-- @doc Draw something
function WaitingWorkers:draw()
  --if WaitingWorkersWorker.debug then print("WaitingWorkers:draw()") end

end

-- @doc Check timers during map update calls
function WaitingWorkers:update(dt)
  -- print("WaitingWorkers:update ")
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
          item:getFullName() .. g_i18n:getText("WaitingWorkers_VEHICLE_HAS_STOPPED"))
          -- string.format(g_i18n:getText("WaitingWorkers_VEHICLE_HAS_STOPPED")), item:getFullName())
          --item:getFullName().." has stopped due to inactivity.")
        end
      end
    end
  end
end

addModEventListener(WaitingWorkers);
