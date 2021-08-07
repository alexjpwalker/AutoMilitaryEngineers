--------------------------------------------------------------------------------------------------------
local debug: boolean = false; -- Set to true to enable basic debug messages in the Lua.log
local debug_GameInfo: boolean = false; -- Set to true to enable printing all of the routes, unit commands, unit ops loaded into mod.
local debug_AllActions: boolean = false; -- Set to true to enable VERY VERBOSE debug messages printed to log
--------------------------------------------------------------------------------------------------------
--[[
AUTOMATED MILITARY ENGINEERS SCRIPT
--]]
--------------------------------------------------------------------------------------------------------

--======================================================================================================
-- MEMBERS
--======================================================================================================
local BAD_DISTANCE = 9999;

--------------------------------------------------------------------------------------------------------
function print_table(node, full)
    local cache, stack, output = {},{},{}
    local depth = 1
    local output_str = "{\n"
	
	if node == nil then
		print("<nil>")
	elseif type(node) == "string" then
		print(node)
	else
		while true do
			local size = 0
			for k,v in pairs(node) do size = size + 1 end

			local cur_index = 1
			for k,v in pairs(node) do
				if (cache[node] == nil) or (cur_index >= cache[node]) then

					if (string.find(output_str,"}",output_str:len())) then
						output_str = output_str .. ",\n"
					elseif not (string.find(output_str,"\n",output_str:len())) then
						output_str = output_str .. "\n"
					end

					-- This is necessary for working with HUGE tables otherwise we run out of memory using concat on huge strings
					table.insert(output,output_str)
					output_str = ""

					local key
					if (type(k) == "number" or type(k) == "boolean") then key = "["..tostring(k).."]";
					else key = "['"..tostring(k).."']"; end

					if (type(v) == "number" or type(v) == "boolean") then
						output_str = output_str .. string.rep('\t',depth) .. key .. " = "..tostring(v)
					elseif (type(v) == "table") then
						if full == true then
							output_str = output_str .. string.rep('\t',depth) .. key .. " = {\n"
							table.insert(stack,node)
							table.insert(stack,v)
							cache[node] = cur_index+1
							break
						else
							output_str = output_str .. "[SHORTENED]"
						end
					else
						output_str = output_str .. string.rep('\t',depth) .. key .. " = '"..tostring(v).."'"
					end

					if (cur_index == size) then output_str = output_str .. "\n" .. string.rep('\t',depth-1) .. "}";
					else output_str = output_str .. ","; end
				else
					-- close the table
					if (cur_index == size) then output_str = output_str .. "\n" .. string.rep('\t',depth-1) .. "}"; end
				end

				cur_index = cur_index + 1;
			end

			if (size == 0) then output_str = output_str .. "\n" .. string.rep('\t',depth-1) .. "}"; end

			if (#stack > 0) then
				node = stack[#stack]
				stack[#stack] = nil
				depth = cache[node] == nil and depth + 1 or depth - 1
			else
				break;
			end
		end

		-- This is necessary for working with HUGE tables otherwise we run out of memory using concat on huge strings
		table.insert(output,output_str)
		
		for _, v in ipairs(output) do print(v); end
	end
end

if debug == nil then debug = false; end
if debug_GameInfo == nil then debug_GameInfo = false; end

-- Some functions for debug/error usage.
local function Error() print( "ERROR!" ); end
local function Error( message ) if not message then Error() else print( "ERROR: " .. message ); end end
local function DebugError() print( "debug ERROR" ); end
local function Debug(message) if debug then if message then print( "Debug: " .. message ); else DebugError(); end end end
local function Debug_AllActions(message) if debug_AllActions == true then if message then print( "Debug: " .. message ); else DebugError(); end end end

local m_Player = Players[0]; -- Stores player data for local processing.
local m_PlayerTechs = m_Player:GetTechs();
local m_PlayerRoutes = {}; -- Contains a list of valid routes for each human player.

-- Object tables.
local m_MilitaryEngineers = { members = {}; };
local m_PlannedRoutes = { members = {}; };
local m_SleepRequests = { members = {}; };

local m_AutoMilitaryEngineer_GP = {}; -- Gameplay script for storing tables
local m_isAutoMilitaryEngineer_GP_Loaded = false;

--======================================================================================================
-- CONSTANTS
--======================================================================================================

local STATUSES = {};-- Used for UI unit status text.
local ROUTES = {};
local UNIT_COMMANDS = {};
local UNIT_OPS = {};
local map_width, map_height = Map.GetGridSize();

--------------------------------------------------------------------------------------------------------
local function GetGameRoutes()
	if debug_GameInfo then print( "Populating ROUTES table from GameInfo: " ); end

	local id = 0;

	for row in GameInfo.Routes() do
		local o = {};
		o.ID = id;
		id = id + 1;
		o.NAME = row.RouteType;
		o.TEXT = row.Name;
		o.HASH = row.Hash;
		if row.PrereqTech then o.TECH = row.PrereqTech; end

		if debug_GameInfo then 
			print("Added route type: ");
			for key, data in pairs( o ) do print( tostring( key ) .. ": " .. tostring( data ) ); end
			print();
		end
		ROUTES[o.ID] = o;
	end
end

--------------------------------------------------------------------------------------------------------
local function GetGameUnitCommands()
	for row in GameInfo.UnitCommands() do 
		local o = {};
		o.NAME = row.CommandType;
		o.HASH = row.Hash;
		if debug_GameInfo then 
			print("Added unit command: ");
			for key, data in pairs(o) do print( tostring( key ) .. ": " .. tostring( data ) ); end
			print();
		end
		UNIT_COMMANDS[o.NAME] = o;
	end
end

--------------------------------------------------------------------------------------------------------
local function GetGameUnitOps()
	for row in GameInfo.UnitOperations() do 
		local o = {};
		o.NAME = row.OperationType;
		o.HASH = row.Hash;
		if debug_GameInfo then 
			print( "Added unit operation: " );
			for key, data in pairs( o ) do print( tostring( key ) .. ": " .. tostring( data ) ); end
			print();
		end
		UNIT_OPS[o.NAME] = o;
	end
end

-- Load some game data whenever the UI is refreshed, including that from all mods enabled.
GetGameRoutes();
GetGameUnitCommands();
GetGameUnitOps();

--======================================================================================================
-- STATIC OBJECTS
--======================================================================================================

function m_MilitaryEngineers:count() -- Number of military engineers currently automated.
	local totalAutomated = 0;
	for key, keyData in ipairs(self.members) do
		if keyData.isAutomated then totalAutomated = totalAutomated + 1; end
	end
	return totalAutomated;
end
function m_MilitaryEngineers:add(o) -- Adds a new object to the table.
	if not o then Error( "Nil data passed to mMilitaryEngineers' add function! No data was added." ); end
	table.insert(self.members, o);
end
function m_MilitaryEngineers:get(unit) -- Returns a MilitaryEngineer object from the table.
	if not unit then Error( "Nil unit passed to mMilitaryEngineers' get function!" ); return nil; end
	if not self then
		Error("Nil data passed to mMilitaryEngineers' get function!");
		return nil;
	end
	if (not ipairs) or (not self.members) then
		print(ipairs)
		print(self.members)
		Error("Invalid data found when calling mMilitaryEngineers:get");
		return nil;
	end
	for _, aMilitaryEngineer in ipairs( self.members ) do 
		if (aMilitaryEngineer.ID == unit:GetID() and aMilitaryEngineer:getOwner() == unit:GetOwner() ) 
			or (aMilitaryEngineer.ID == unit.ID and aMilitaryEngineer:getOwner() == unit:getOwner()) then 
			return aMilitaryEngineer;
		end
	end return nil;
end
function m_MilitaryEngineers:getByPlayerAndUnitID(playerID, unitID) -- Returns a MilitaryEngineer object from the table.
	if not self then
		Error("Nil data passed to mMilitaryEngineers' getByPlayerAndUnitID function!");
		return nil;
	end
	if (not playerID) or (not unitID) then
		print(playerID)
		print(unitID)
		print(Error)
		Error("Invalid data passed to mMilitaryEngineers:getByPlayerAndUnitID");
		return nil;
	end
	if (not ipairs) or (not self.members) then
		print(ipairs)
		print(self.members)
		Error("Invalid data found when calling mMilitaryEngineers:getByPlayerAndUnitID");
		return nil;
	end
	for _, aMilitaryEngineer in ipairs(self.members) do 
		if (aMilitaryEngineer.owner == playerID) and (aMilitaryEngineer.ID == unitID) then
			return aMilitaryEngineer;
		end
	end return nil;
end
function m_MilitaryEngineers:save( o ) -- Overwrites updated MilitaryEngineer object data into the table.
	if not o then Error( "Nil data passed to mMilitaryEngineers' save function! No data was saved." ); return; end
	for key, aMilitaryEngineer in ipairs( self.members ) do 
		if ( aMilitaryEngineer.ID == o.ID and ( ( aMilitaryEngineer:getOwner() == o:getOwner() ) or ( aMilitaryEngineer.owner == o.owner ) ) ) then self.members[key] = o; end
	end
end

function m_PlannedRoutes:getUnassigned()
	local pTable = {};
	for key, keyData in ipairs(self.members) do
		if keyData.projectState == "UNASSIGNED" then table.insert(pTable, keyData); end
	end
	return pTable;
end
function m_PlannedRoutes:getUnassignedFromOrigin(x, y)
	local pTable = {};
	for key, data in ipairs( self.members ) do
		if data.projectState == "UNASSIGNED" and data.originPlot.x == x and data.originPlot.y == y then table.insert(pTable, data); end
	end
	return pTable;
end
function m_PlannedRoutes:add( o )
	if not o then Error( "Nil data passed to m_PlannedRoutes' add function! No data was added." );
	else table.insert( self.members, o ); end
end
function m_PlannedRoutes:get( o )
	if not o then Error( "Nil data passed to m_PlannedRoutes' get function!" ); return nil; end
	for _, data in ipairs( self.members ) do 
		if ( data.originPlot.x == o.originPlot.x and data.originPlot.y == o.originPlot.y and data.destinationPlot.x == o.destinationPlot.x and data.destinationPlot.y == o.destinationPlot.y ) then 
			return data;
		end
	end
	return nil;
end
function m_PlannedRoutes:save( o )
	if not o then Error( "Nil data passed to m_PlannedRoutes' save function! No data was saved." ); return; end
	for key, data in ipairs( self.members ) do
		if ( data.originPlot.x == o.originPlot.x and data.originPlot.y == o.originPlot.y and data.destinationPlot.x == o.destinationPlot.x and data.destinationPlot.y == o.destinationPlot.y ) then 
			self.members[key] = o;
		end
	end
end

function m_SleepRequests:getAll()
	return self.members;
end
function m_SleepRequests:add(unitID)
	if not unitID then Error( "Nil data passed to m_SleepRequests' add function! No data was added." );
	else table.insert(self.members, unitID); end
end
function m_SleepRequests:contains(unitID)
	if not unitID then Error("Nil data passed to m_SleepRequests' contains function!"); return false; end
	for _, data in ipairs(self.members) do 
		if data == unitID then return true; end
	end
	return false;
end
function m_SleepRequests:delete(unitID)
	if not unitID then Error( "Nil data passed to m_SleepRequests' delete function! No data was deleted." ); return; end
	for _, data in ipairs(self.members) do
		if data == unitID then
			table.remove(self.members, unitID);
			return;
		end
	end
end

--------------------------------------------------------------------------------------------------------
-- -- Sets a MilitaryEngineer in the game to not automated.
local function StopAutomateMilitaryEngineer(unit)
	m_MilitaryEngineer = m_MilitaryEngineers:get(unit);
	if m_MilitaryEngineer then 
		if m_MilitaryEngineer.isAutomated then
			m_MilitaryEngineer:setAutomated(false); -- Set MilitaryEngineer to not automated.
			m_MilitaryEngineer.ID = unit:GetID(); -- Refresh unit ID
			m_MilitaryEngineer.unit_data = unit; -- Refresh unit data.
			m_MilitaryEngineer:abandonMoveTarget();
			m_MilitaryEngineer:abandonRoute();
			m_MilitaryEngineer:cancel(); -- Cancel anything the MilitaryEngineer is doing.
			m_MilitaryEngineers:save( m_MilitaryEngineer ); -- Save the data back to the list.
			Debug("Stopped Automation for MilitaryEngineer (" .. m_MilitaryEngineer.ID .. ").");
		else Error( "Attempt to stop MilitaryEngineer automation for a MilitaryEngineer that is already not automated." ); end
	else Error("StopAutomateMilitaryEngineer was called with an invalid unit."); end
end


--======================================================================================================
-- OBJECT CLASSES AND METHODS
--======================================================================================================

local function PlotCoordinatesToString(x, y)
	local city = CityManager.GetCityAt(x, y);
	if city then
		return "[" .. Locale.Lookup(city:GetName()) .. "{x=" .. x .. ",y=" .. y .. "}]";
	else
		return "{x=" .. x .. ",y=" .. y .. "}";
	end
end

local function PlotToString(plot)
	return PlotCoordinatesToString(plot:GetX(), plot:GetY());
end

local function IsWaterTile(plot)
	local terrain = plot:GetTerrainType();
	return GameInfo.Terrains[terrain].Water == true or GameInfo.Terrains[terrain].Water == 1;
end

--------------------------------------------------------------------------------------------------------
local function CheckUnitType(unitType, key)
	if unitType ~= nil and GameInfo.Units[key] ~= nil then return unitType == GameInfo.Units[key].Index; end
	return false
end

local function IsSupportUnit(unit)
	local isSupport = false;
	local unitType = unit:GetUnitType();

	if CheckUnitType(unitType, "UNIT_MILITARY_ENGINEER") then isSupport = true;
	elseif (GameInfo.Units[unitType].FormationClass == "FORMATION_CLASS_SUPPORT") then isSupport = true;
	end

	return isSupport;
end

--------------------------------------------------------------------------------------------------------
-- If there is a friendly MilitaryEngineer at this plot, that is obstructing the given MilitaryEngineer from moving to it, return it.
local function GetFriendlyUnitObstructingPlot(unit, aPlot)
	if (not unit) or (not aPlot) then return nil; end
	local canMoveToPlot = true;

	local units = Units.GetUnitsInPlot(aPlot);
	for _, aUnit in pairs(units) do
		if aUnit:GetID() ~= unit:GetID() and aUnit:GetOwner() == unit:GetOwner() and IsSupportUnit(aUnit) then
			Debug("The plot " .. PlotToString(aPlot) .. " is obstructed by a friendly " .. Locale.Lookup(GameInfo.Units[aUnit:GetUnitType()].Name));
			return aUnit;
		end
	end
	return nil;
end

-- PlannedRoute Object Class
local PlannedRouteClass = {
	originPlot = nil;
	destinationPlot = nil;
	projectState = "UNASSIGNED"; -- UNASSIGNED | ASSIGNED | COMPLETED
}

-- Object Constructor
function PlannedRouteClass:new ( o )
	o = o or {};
	setmetatable( o, self );
	self.__index = self;
	return o;
end

-- MilitaryEngineer Object Class
local MilitaryEngineerClass = {
	ID = 0; -- The MilitaryEngineer's unit ID for this game.
	owner = -1;
	unit_data = nil; -- Unit data for this MilitaryEngineer.
	isAutomated = true; -- If this MilitaryEngineer is currently automated.
	moveTarget = nil;
	plannedRoute = nil;
	movesRemainingOnPreviousSelection = -1;
	has_error = false; -- Error flag
};
function MilitaryEngineerClass:GetX() 
	if self.unit_data then 
		local unit = UnitManager.GetUnit( self:getOwner(), self.unit_data:GetID() );
		if unit then return unit:GetX(); else return 0; end
	else return 0; end 
end
function MilitaryEngineerClass:GetY() 
	if self.unit_data then 
		local unit = UnitManager.GetUnit( self:getOwner(), self.unit_data:GetID() );
		if unit then return unit:GetY(); else return 0; end
	else return 0; end 
end

function MilitaryEngineerClass:setAutomated(automated: boolean) self.isAutomated = automated; end

function MilitaryEngineerClass:setMoveTarget(target)
	self.moveTarget = target;
end

function MilitaryEngineerClass:getOwner()
	local unit = UnitManager.GetUnit(self.unit_data:GetOwner(), self.unit_data:GetID());
	if unit then self.owner = unit:GetOwner(); return unit:GetOwner(); else return -1; end
end

-- Commands this MilitaryEngineer to build a railroad
function MilitaryEngineerClass:buildRoad()
	if not self then Error( "Nil object data when using MilitaryEngineer's BuildRoad." ); return; end
	UnitManager.RequestOperation(UnitManager.GetUnit( self:getOwner(), self.ID ), UnitOperationTypes.BUILD_ROUTE);
	Debug(Locale.Lookup(PlayerConfigurations[self:getOwner()]:GetLeaderTypeName()) .. " commanded MilitaryEngineer (" .. self.ID ..") to build a Railroad at" .. PlotCoordinatesToString(self:GetX(), self:GetY()));
end

-- Commands the MilitaryEngineer to cancel whatever it is doing.
function MilitaryEngineerClass:cancel()
	if not self then Error( "Nil object data when using MilitaryEngineer's Cancel." ); return; end
	local unit = UnitManager.GetUnit( self:getOwner(), self.ID );
	UnitManager.RequestCommand( unit, UNIT_COMMANDS["UNITCOMMAND_CANCEL"].HASH );
	UnitManager.RequestCommand( unit, UNIT_COMMANDS["UNITCOMMAND_WAKE"].HASH ); -- Wake the unit.
end

-- Commands the MilitaryEngineer to sleep.
function MilitaryEngineerClass:sleep()
	if not self then Error("Nil object data when using MilitaryEngineer's Sleep."); return; end
	local unit = UnitManager.GetUnit(self:getOwner(), self.ID);
	UnitManager.RequestOperation(unit, UNIT_OPS["UNITOPERATION_SLEEP"].HASH);
	Debug(Locale.Lookup(PlayerConfigurations[self:getOwner()]:GetLeaderTypeName()) .. " commanded MilitaryEngineer (" .. self.ID ..") to sleep at" .. PlotCoordinatesToString(self:GetX(), self:GetY()));
end

-- Returns true if this MilitaryEngineer unit has more than 0 moves remaining.
function MilitaryEngineerClass:hasMovementLeft()
	if not self then Error( "Nil object data when using MilitaryEngineer's HasMovementLeft" ); return; end
	local unit = UnitManager.GetUnit( self:getOwner(), self.ID );
	if unit and unit:GetMovesRemaining() > 0 then return true; else return false; end
end

 -- Commands this MilitaryEngineer to move to a plot coordinate. Returns true if successful (mostly)
function MilitaryEngineerClass:moveTo(newX, newY, fallbackStrategy)
	if not self then Error("Nil object data when using MilitaryEngineer's MoveTo."); return; end
	if not newX or not newY then Error("Nil x and y coordinates passed to MilitaryEngineer's MoveTo."); return; end
	
	local plot = Map.GetPlot(newX, newY);

	if newX == self:GetX() and newY == self:GetY() then
		if debug then Debug("moveTo: MilitaryEngineer is already at the requested plot " .. PlotToString(plot)); end
		return;
	end

	Debug_AllActions("moveTo: Called for [" .. self.ID .. "] with " .. PlotToString(plot));

	local tParameters = {};
	tParameters[UnitOperationTypes.PARAM_X] = newX;
	tParameters[UnitOperationTypes.PARAM_Y] = newY;
	local unit = UnitManager.GetUnit(self:getOwner(), self.ID);
	UnitManager.RequestCommand(unit, UNIT_COMMANDS["UNITCOMMAND_WAKE"].HASH);

	local canMove = UnitManager.CanStartOperation(unit, UnitOperationTypes.MOVE_TO, nil, tParameters);
	local obstructingUnit = GetFriendlyUnitObstructingPlot(unit, plot);
	if obstructingUnit then canMove = false; end

	if canMove then
		Debug("moveTo: Commanding MilitaryEngineer [" .. self.ID .. "] to move to " .. PlotToString(plot));
		UnitManager.RequestOperation(unit, UnitOperationTypes.MOVE_TO, tParameters);
		return true;
	else
		local adjacentPlotsToTarget = {};
		for key, adjPlot in ipairs(Map.GetAdjacentPlots(newX, newY)) do
			-- Can't move to a mountain. TODO: also check for Ice feature
			if not adjPlot:IsMountain() then table.insert(adjacentPlotsToTarget, adjPlot); end
		end

		-- If obstructed by a unit that's adjacent to us, try to swap places with it
		if obstructingUnit then
			local targetIsAdjacent = false;
			for key, adjPlot in ipairs(adjacentPlotsToTarget) do
				if adjPlot:GetX() == self:GetX() and adjPlot:GetY() == self:GetY() then
					targetIsAdjacent = true;
					break;
				end
			end
			if targetIsAdjacent then
				local activityType = UnitManager.GetActivityType(obstructingUnit);
				local unitWasAsleep = false;
				if activityType == ActivityTypes.ACTIVITY_SLEEP then unitWasAsleep = true; end

				UnitManager.RequestCommand(obstructingUnit, UNIT_COMMANDS["UNITCOMMAND_WAKE"].HASH);
				if UnitManager.CanStartOperation(unit, UnitOperationTypes.SWAP_UNITS, nil, tParameters) then
					Debug("moveTo [" .. fallbackStrategy .. "]: Commanding MilitaryEngineer [" .. self.ID .. "] to switch places with [" .. Locale.Lookup(GameInfo.Units[obstructingUnit:GetUnitType()].Name) .. "] at plot " .. PlotToString(plot));
					UnitManager.RequestOperation(unit, UnitOperationTypes.SWAP_UNITS, tParameters);
					if unitWasAsleep then
						Debug("moveTo [" .. fallbackStrategy .. "]: " .. Locale.Lookup(GameInfo.Units[obstructingUnit:GetUnitType()].Name) .. " [" .. obstructingUnit:GetID() .. "] was asleep; flagging it so it can go back to sleep");
						m_SleepRequests:add(obstructingUnit:GetID());
					end
					return true;
				elseif debug then
					Debug("moveTo [" .. fallbackStrategy .. "]: Unable to swap units, perhaps insufficient movement?");
				end
			end
		end
			
		if fallbackStrategy == "FALLBACK_STRATEGY_GIVE_UP" then
			if debug then Debug_AllActions("moveTo [" .. fallbackStrategy .. "]: " .. PlotToString(plot) .. " is unreachable."); end
			return false;
		end

		Debug("moveTo [" .. fallbackStrategy .. "]: Trying to find fallback plot to move to.");
		local fallbackPlots = {};
		if fallbackStrategy == "FALLBACK_STRATEGY_ADJACENT_PLOTS" then
			fallbackPlots = adjacentPlotsToTarget;
		elseif fallbackStrategy == "FALLBACK_STRATEGY_SHARED_ADJACENCY_LAND" then
			local adjacentPlotsToUnit: table = Map.GetAdjacentPlots(self:GetX(), self:GetY());
			for key, adjPlotToUnit in ipairs(adjacentPlotsToUnit) do
				if not (IsWaterTile(adjPlotToUnit)) then
					for key, adjPlotToTarget in ipairs(adjacentPlotsToTarget) do
						if adjPlotToTarget:GetIndex() == adjPlotToUnit:GetIndex() then
							table.insert(fallbackPlots, adjPlotToUnit);
						end
					end
				end
			end
		end

		for key, fallbackPlot in ipairs(fallbackPlots) do
			-- Check that this isn't the plot the unit is already on
			if (fallbackPlot:GetX() ~= self:GetX()) or (fallbackPlot:GetY() ~= self:GetY()) then
				local newXFallback = fallbackPlot:GetX();
				local newYFallback = fallbackPlot:GetY();
				local success = self:moveTo(newXFallback, newYFallback, "FALLBACK_STRATEGY_GIVE_UP");
				if success then return true; end
			end
		end

		Debug("moveTo [" .. fallbackStrategy .. "]: Target plot and all fallback plots are unreachable. No action will be taken.");
		return false;
	end
end

-- Commands this MilitaryEngineer to move to its movement target.
function MilitaryEngineerClass:moveToTarget(fallbackStrategy)
	self:moveTo(self.moveTarget:GetX(), self.moveTarget:GetY(), fallbackStrategy);
end

-- Returns true if this MilitaryEngineer has reached its target plot.
function MilitaryEngineerClass:hasReachedTarget()
	local hasReachedTarget = false;
	if self.isAutomated then 
		if self.moveTarget then
			Debug_AllActions("hasReachedTarget: MilitaryEngineer [" .. self.ID .. "] is at " .. PlotCoordinatesToString(self:GetX(), self:GetY()) .. " and its target is " .. PlotToString(self.moveTarget));
			if self.moveTarget:GetX() == self:GetX() and self.moveTarget:GetY() == self:GetY() then hasReachedTarget = true; end
		else Error( "Nil move target data when using MilitaryEngineer's hasReachedTarget." ); end
	else Error( "Invalid object data when using MilitaryEngineer's hasReachedTarget." ); end
	if debug then
		if hasReachedTarget then Debug_AllActions("hasReachedTarget: MilitaryEngineer [" .. self.ID .. "] has reached its target plot.");
		else Debug_AllActions("hasReachedTarget: MilitaryEngineer [" .. self.ID .. "] has not yet reached its target plot."); end
	end
	return hasReachedTarget;
end

function MilitaryEngineerClass:completeMoveTarget()
	if not self.moveTarget then return; end
	if debug then Debug_AllActions("completeMoveTarget: MilitaryEngineer [" .. self.ID .. "] has successfully reached " .. PlotToString(self.moveTarget)); end
	self.moveTarget = nil;
end

function MilitaryEngineerClass:abandonMoveTarget()
	if not self.moveTarget then return; end
	if debug then
		Debug("abandonMoveTarget: MilitaryEngineer [" .. self.ID .. "] has been un-automated or destroyed, and will no longer move to " .. PlotToString(self.moveTarget));
	end
	self.moveTarget = nil;
end

function MilitaryEngineerClass:completeRoute()
	if not self.plannedRoute then return; end
	self.plannedRoute.projectState = "COMPLETED";
	if debug then Debug("completeRoute: MilitaryEngineer [" .. self.ID .. "] has COMPLETED the route from " .. PlotCoordinatesToString(self.plannedRoute.originPlot.x, self.plannedRoute.originPlot.y) .. " to " .. PlotCoordinatesToString(self.plannedRoute.destinationPlot.x, self.plannedRoute.destinationPlot.y)); end
	m_PlannedRoutes:save(self.plannedRoute);
	self.plannedRoute = nil;
end

function MilitaryEngineerClass:abandonRoute()
	if not self.plannedRoute then return; end
	self.plannedRoute.projectState = "UNASSIGNED";
	if debug then Debug("abandonRoute: MilitaryEngineer [" .. self.ID .. "] has been un-automated or destroyed, so the route from " .. PlotCoordinatesToString(self.plannedRoute.originPlot.x, self.plannedRoute.originPlot.y) .. " to " .. PlotCoordinatesToString(self.plannedRoute.destinationPlot.x, self.plannedRoute.destinationPlot.y) .. " is now UNASSIGNED."); end
	m_PlannedRoutes:save(self.plannedRoute);
	self.plannedRoute = nil;
end

function MilitaryEngineerClass:markRouteAsUnreachable()
	if not self.plannedRoute then return; end
	self.plannedRoute.projectState = "UNREACHABLE";
	if debug then Debug("markRouteAsUnreachable: MilitaryEngineer [" .. self.ID .. "] has marked the route from " .. PlotCoordinatesToString(self.plannedRoute.originPlot.x, self.plannedRoute.originPlot.y) .. " to " .. PlotCoordinatesToString(self.plannedRoute.destinationPlot.x, self.plannedRoute.destinationPlot.y) .. " as UNREACHABLE, because it can't find a valid path to the destination, or any of its adjacent tiles."); end
	m_PlannedRoutes:save(self.plannedRoute);
	self.plannedRoute = nil;
end
--------------------------------------------------------------------------------------------------------

-- Returns the unit's current status.
function MilitaryEngineerClass:GetStatus()
	if self.plannedRoute then
		local pOriginCity = CityManager.GetCityAt(self.plannedRoute.originPlot.x, self.plannedRoute.originPlot.y);
		local pDestinationCity = CityManager.GetCityAt(self.plannedRoute.destinationPlot.x, self.plannedRoute.destinationPlot.y);
		if pOriginCity and pDestinationCity then
			return "Building railroad from " .. Locale.Lookup(pOriginCity:GetName()) .. " to " .. Locale.Lookup(pDestinationCity:GetName());
		else
			return "Building railroad";
		end
	elseif self.moveTarget then
		local pCity = CityManager.GetCityAt(self.moveTarget:GetX(), self.moveTarget:GetY());
		if pCity then return "Moving to " .. Locale.Lookup(pCity:GetName());
		else return "Moving"; end
	else
		return "Sleeping";
	end
end

-- Object Constructor
function MilitaryEngineerClass:new(o)
	o = o or {};
	setmetatable( o, self );
	self.__index = self;
	return o;
end


--======================================================================================================
-- FUNCTIONS
--======================================================================================================

--------------------------------------------------------------------------------------------------------
-- Sets a MilitaryEngineer in the game to automated.
local function AutomateMilitaryEngineer(unit)
	m_MilitaryEngineer = m_MilitaryEngineers:get(unit); -- Get any existing object data for this MilitaryEngineer.
	if not m_MilitaryEngineer then -- Make a new MilitaryEngineer object and add it to the list.
		m_MilitaryEngineer = 
			MilitaryEngineerClass:new{ 
				ID = unit:GetID();
				owner = unit:GetOwner();
				unit_data = unit;
			};
		m_MilitaryEngineer:performAction();
		m_MilitaryEngineers:add( m_MilitaryEngineer ); -- Add MilitaryEngineer to the list.
		Debug("Added a new MilitaryEngineer (" .. m_MilitaryEngineer.ID .. ") object to the list.");
	else
		m_MilitaryEngineer:setAutomated( true ); -- If it already exists, then set it to Automated.
		m_MilitaryEngineer.ID = unit:GetID(); -- Refresh unit ID
		m_MilitaryEngineer.unit_data = unit; -- Refresh unit data.
		m_MilitaryEngineer:performAction();
		m_MilitaryEngineers:save( m_MilitaryEngineer ); -- Save the data back to the list.
		Debug("Set an existing MilitaryEngineer (" .. m_MilitaryEngineer.ID .. ") to automated.");
	end
end

--------------------------------------------------------------------------------------------------------
-- Returns true if the given unit is an automated MilitaryEngineer
local function IsMilitaryEngineerAutomated(pUnit)
	m_MilitaryEngineer = m_MilitaryEngineers:get(pUnit);
	if m_MilitaryEngineer then 
		return m_MilitaryEngineer.isAutomated;
	else 
		return false;
	end
end

--------------------------------------------------------------------------------------------------------
-- Returns string status of the given unit if it is an automated MilitaryEngineer.
local function GetMilitaryEngineerStatus( pUnit )
	m_MilitaryEngineer = m_MilitaryEngineers:get( pUnit );
	if m_MilitaryEngineer and m_MilitaryEngineer.isAutomated then 
		return m_MilitaryEngineer:GetStatus();
	else 
		return "";
	end
end

--------------------------------------------------------------------------------------------------------
-- Returns the distance between two plots.
local function GetDistance( firstPlot, secondPlot )
	local distance = BAD_DISTANCE;
	if firstPlot and secondPlot and firstPlot.GetX and secondPlot.GetX then -- Check for good data.
		distance = Map.GetPlotDistance( firstPlot:GetX(), firstPlot:GetY(), secondPlot:GetX(), secondPlot:GetY() );
	else
		Debug( "GetDistance: Bad plot data given, returned BAD_DISTANCE." );
	end
	return distance;
end

--------------------------------------------------------------------------------------------------------
-- Returns the number of turns it will take for the given unit to move to the plot.
local function GetTurnDistance(militaryEngineer, plot)
	local turnsList		= nil;
	local obstacles		= nil;
	local pathPlots		: table = {};
	local endPlotId		:number = -1;
	local nTurnCount 	:number = BAD_DISTANCE;
	local validInput = false;

	endPlotID = plot:GetIndex();
	local iPlayer = militaryEngineer:getOwner();
	unit = UnitManager.GetUnit(iPlayer, militaryEngineer.ID);

	local pathInfo, turnsList = UnitManager.GetMoveToPath(unit, endPlotID);
	nTurnCount = turnsList[table.count(turnsList)] or nTurnCount;
	
	if (debug and nTurnCount < BAD_DISTANCE) then
		local pathString = "GetTurnDistance: Found path with turn distance of [" .. nTurnCount .. "]:";
		for key, plotID in ipairs(pathInfo) do
			local plot = Map.GetPlotByIndex(plotID);
			pathString = pathString .. " [" .. key .. "]: " .. PlotToString(plot);
		end
		Debug_AllActions(pathString);
	end
	
	if nTurnCount < BAD_DISTANCE then
		return nTurnCount;
	else
		-- No path; is it a bad path or is the destination on the same hex as the unit?
		local startPlotID: number = Map.GetPlot(unit:GetX(),unit:GetY()):GetIndex();
		if startPlotID == endPlotID then				
			Debug_AllActions("GetTurnDistance: Found path with turn distance of [0]: unit is already at the target plot");
			return 0;
		else
			Debug_AllActions("GetTurnDistance: Failed to find path for Unit (" .. unit:GetID() .. ") to reach plot: " .. endPlotID);
			return BAD_DISTANCE;
		end
	end
end

-- MergeSort: Modified lua implementation from LouisBC at https://gist.github.com/LouiseBC/ab5ab8c3aa9434ce6217b355d0ec6e08
--------------------------------------------------------------------------------------------------------
local function mergeHalves(array:table, o:table, first:number, last:number)
	local left = first;
	local leftTail = math.floor((first + last) / 2);
	local right = leftTail + 1;
	local temp = {unpack(array)};
	local temp_o = {};
	local useO = false;
	if o and type(o) == "table" and #o == #array then useO = true; end
	if useO then temp_o = {unpack(o)}; end
	for i = first, last do
		if (right > last or ((array[left] <= array[right]) and left <= leftTail)) then
			temp[i] = array[left];
			if useO then temp_o[i] = o[left]; end
			left = left + 1;
		else 
			temp[i] = array[right];
			if useO then temp_o[i] = o[right]; end
			right = right + 1;
		end
	end
	for i = first, last do 
		array[i] = temp[i];
		if useO then o[i] = temp_o[i]; end
	end
	return {array, o};
end
--------------------------------------------------------------------------------------------------------
-- MergeSort: Modified lua implementation from LouisBC at https://gist.github.com/LouiseBC/ab5ab8c3aa9434ce6217b355d0ec6e08
local function MergeSort(array:table, o:table, first:number, last:number)
	local first = first or 1;
	local last = last or #array;
	if first >= last then if o then return o, array; else return array; end end
	local middle = math.floor((first + last) / 2);
	MergeSort(array, o, first, middle);
	MergeSort(array, o, (middle+1), last);
	local result = mergeHalves(array, o, first, last);
	array = result[1];
	o = result[2];
	if o then return o, array; else return array; end
end

--------------------------------------------------------------------------------------------------------
-- Sorts a table of plots based on least plot distance and turn distance away from assigned militaryEngineer.
local function SortPlots(militaryEngineer, plots, idx)
	local idx = idx or 1;
	local distances = {};
	for i = idx, #plots do
		local plot = plots[i];
		local physicalDistance = GetDistance(plot, Map.GetPlot(militaryEngineer:GetX(), militaryEngineer:GetY()));
		table.insert(distances, physicalDistance);
		Debug_AllActions("SortPlots: Found physical distance [" .. physicalDistance .. "] from unit [" .. militaryEngineer.ID .. 
			"] at " .. PlotCoordinatesToString(militaryEngineer:GetX(), militaryEngineer:GetY()) .. " to plot at " .. PlotToString(plot));
	end
	--print("Done finding distances.");
	--[[ Debug info
	print( "MergeSort test (before):" );
	for key, element in ipairs( distances ) do print( element .. ": " .. plots[key].id .. " (" .. plots[key].distance .. ")" ); end
	plots = MergeSort( distances, plots ); -- Use mergesort algorithm to sort object table by using the least distance array.
	distances = MergeSort( distances );
	print( "MergeSort test (after):" );
	for key, element in ipairs( distances ) do print( element .. ": " .. plots[key].id .. " (" .. plots[key].distance .. ")" ); end
	--]]
	-- The Merge Sort algorithm is stable, so after sorting by least plot distance, that order plots will be preserved for plots with the same move turns.

	-- Sort by turn distance (ascending), then by physical distance (ascending)
	plots = MergeSort(distances, plots, idx);
	
	local turn_distances = {};
	for i = idx, #plots do -- Go through plots
		local plot = plots[i];
		local turnDistance = GetTurnDistance(militaryEngineer, plot);
		if turnDistance >= BAD_DISTANCE then useTurnDistance = false; end
		table.insert(turn_distances, turnDistance);
		
		Debug_AllActions("SortPlots: Found turn distance [" .. turnDistance .. "] from unit [" .. militaryEngineer.ID .. 
			"] at " .. PlotCoordinatesToString(militaryEngineer:GetX(), militaryEngineer:GetY()) .. " to plot at " .. PlotToString(plot));
	end

	plots = MergeSort(turn_distances, plots, idx);
	if debug then
		local msg = "SortPlots: After sorting by turn distance and physical distance, the order is: ";
		for i = 1, #plots do
			local plot = plots[i];
			msg = msg .. PlotToString(plot) .. " ";
		end
		Debug_AllActions(msg);
	end
	if not plots then plots = {}; end
	return plots;
end

--------------------------------------------------------------------------------------------------------
-- Checks if player has required techs for an object.
local function PlayerHasResearchFor(o, iPlayer)
	local addO = false;
	if iPlayer then 
		m_Player = Players[iPlayer];
		m_PlayerTechs = m_Player:GetTechs();
	end
	if o.TECH and GameInfo.Technologies[o.TECH] then -- Check for required tech and valid database data.
		if m_PlayerTechs:HasTech( GameInfo.Technologies[o.TECH].Index ) then 
			addO = true; -- Player has required tech
		end
	else addO = true; end -- No required tech
	return addO;
end

--------------------------------------------------------------------------------------------------------
-- Add valid routes to a player based on technologies.
local function PopulateListData( table, iPlayer )
	if iPlayer then m_Player = Players[iPlayer]; end
	m_PlayerTechs = m_Player:GetTechs();
	-- Get out of function if there is nil data.
	if not m_PlayerTechs then Error( "Nil player Tech data when entering function PopulateListData." ); return nil; end
	local List = {};	
	
	for _, o in pairs(table) do
		local addO = PlayerHasResearchFor( o );
		
		if addO then List[o.NAME] = o; end
	end

	return List;
end

-- Refresh valid routes for a player.
local function RefreshPlayerValidRoutes( playerID )
	m_Player = Players[playerID];
	if not m_Player then Error( "Nil player data when entering function RefreshPlayerValidRoutes." ); return; end
	-- Only create a list for human players.
	if m_Player:IsHuman() then 
		m_PlayerRoutes[playerID] = PopulateListData(ROUTES, playerID);
	end
end

--------------------------------------------------------------------------------------------------------
-- Get a list of all plots containing this player's cities.
local function GetPlayerCityPlots(playerID)
	local mapWidth, mapHeight = Map.GetGridSize();
	local playerCityPlots = {};
	for x = 0, ( mapWidth - 1 ) do
		for y = 0, ( mapHeight - 1 ) do
			local thePlot = CityManager.GetCityAt(x, y);
			if thePlot then
				if thePlot:GetOwner() == playerID then 
					table.insert( playerCityPlots, {x = x, y = y} );
				end
			end
		end
	end
	return playerCityPlots;
end

local function RefreshPlannedRoutes(playerID, originX, originY)
	local cityPlots = GetPlayerCityPlots(playerID);
	-- TODO: With 50 cities this would be over 2000 routes, may need to optimise out transitive connections 
	for cityPlot1Key, cityPlot1 in ipairs(cityPlots) do
		if originX == nil or (originX == cityPlot1.x and originY == cityPlot1.y) then
			for cityPlot2Key, cityPlot2 in ipairs(cityPlots) do
				if cityPlot1Key ~= cityPlot2Key then
					local alreadyPlanned = false;
					for key, plannedRoute in ipairs(m_PlannedRoutes.members) do
						if plannedRoute.originPlot.x == cityPlot1.x and plannedRoute.originPlot.y == cityPlot1.y and plannedRoute.destinationPlot.x == cityPlot2.x and plannedRoute.destinationPlot.y == cityPlot2.y then
							alreadyPlanned = true;
							break;
						end
					end
					if not alreadyPlanned then m_PlannedRoutes:add(PlannedRouteClass:new({ originPlot = cityPlot1, destinationPlot = cityPlot2, projectState = "UNASSIGNED" })); end
				end
			end
		end
	end
	-- TODO: We should also REMOVE any planned routes for coordinates that are no longer valid (e.g: former cities that have been captured)
	if debug then
		for key, pr in ipairs(m_PlannedRoutes.members) do
			if originX == nil or (originX == pr.originPlot.x and originY == pr.originPlot.y) then
				Debug_AllActions("RefreshPlannedRoutes: Route from " .. PlotCoordinatesToString(pr.originPlot.x, pr.originPlot.y) .. " to " .. PlotCoordinatesToString(pr.destinationPlot.x, pr.destinationPlot.y) .. " has state " .. pr.projectState);
			end
		end
	end
end

--------------------------------------------------------------------------------------------------------
 -- Performs an automated action
function MilitaryEngineerClass:performAction()
	local unit = UnitManager.GetUnit(self:getOwner(), self.ID);
	if not unit then return; end
	
	if not self.moveTarget and not self.plannedRoute then
		self:selectOrigin();

		if not self.moveTarget then
			-- No origin was found. This indicates that every route is already assigned or completed. Go to sleep.
			self:sleep();
			return;
		end
	end

	-- We have either a moveTarget or a plannedRoute.

	if self.moveTarget then
		if self:hasReachedTarget() then
			self:completeMoveTarget();
		else
			if self.plannedRoute then self:moveToTarget("FALLBACK_STRATEGY_SHARED_ADJACENCY_LAND");
			else self:moveToTarget("FALLBACK_STRATEGY_ADJACENT_PLOTS"); end
			return;
		end
	end

	-- We don't have a moveTarget. Either plan a route, or work on the one we already have.

	if not self.plannedRoute then
		self:selectDestination();

		if not self.plannedRoute then
			-- No destination was found, most likely because they all became invalid (or were taken by other MilitaryEngineers) after the origin was selected. Retry.
			self:performAction();
			return;
		end
	end

	-- We have a plannedRoute, so work on it.

	self:workOnPlannedRoute();
end

function MilitaryEngineerClass:selectOrigin()
	RefreshPlannedRoutes(self:getOwner());

	if table.count(m_PlannedRoutes:getUnassigned()) == 0 then
		Debug("selectOrigin: There are no unassigned routes. Sleeping.");
		return;
	end

	local originCityPlots = {};
	local msg = "selectOrigin: Found candidate origin cities:";
	for key, plannedRoute in ipairs(m_PlannedRoutes:getUnassigned()) do
		local alreadyInserted = false;
		for key, plot in ipairs(originCityPlots) do
			if plot:GetX() == plannedRoute.originPlot.x and plot:GetY() == plannedRoute.originPlot.y then
				alreadyInserted = true;
				break;
			end
		end
		if not alreadyInserted then
			table.insert(originCityPlots, Map.GetPlot(plannedRoute.originPlot.x, plannedRoute.originPlot.y));
			if debug then msg = msg .. " " .. PlotCoordinatesToString(plannedRoute.originPlot.x, plannedRoute.originPlot.y); end
		end
	end
	Debug_AllActions(msg);

	Debug_AllActions("selectOrigin: Evaluating candidate origin cities.");
	originCityPlots = SortPlots(self, originCityPlots);
	local preferredOrigin = originCityPlots[1];

	if debug then Debug("selectOrigin: Selected origin city " .. PlotToString(preferredOrigin)); end

	self:setMoveTarget(preferredOrigin);
end

function MilitaryEngineerClass:selectDestination()
	RefreshPlannedRoutes(self:getOwner(), self:GetX(), self:GetY());

	if table.count(m_PlannedRoutes:getUnassigned()) == 0 then
		Debug("selectDestination: There are no unassigned routes. Sleeping.");
		return;
	end

	local plannedRoutesFromCurrentLocation = m_PlannedRoutes:getUnassignedFromOrigin(self:GetX(), self:GetY());
	if table.count(plannedRoutesFromCurrentLocation) == 0 then
		if debug then
			Debug("selectDestination: There are no unassigned routes from " .. PlotCoordinatesToString(self:GetX(), self:GetY()) ". Reselecting origin city.");
		end
		return;
	end

	local msg = "selectDestination: Found candidate destination cities:";
	local destinationCityPlots = {};
	for key, plannedRoute in ipairs(plannedRoutesFromCurrentLocation) do
		if debug then
			msg = msg .. " " .. PlotCoordinatesToString(plannedRoute.destinationPlot.x, plannedRoute.destinationPlot.y);
		end
		table.insert(destinationCityPlots, Map.GetPlot(plannedRoute.destinationPlot.x, plannedRoute.destinationPlot.y));
	end
	Debug_AllActions(msg);

	Debug_AllActions("selectDestination: Evaluating candidate destination cities.");
	destinationCityPlots = SortPlots(self, destinationCityPlots);
	local preferredDestination = destinationCityPlots[1];
	if debug then Debug("selectDestination: Selected destination city " .. PlotToString(preferredDestination)); end

	for key, plannedRoute in ipairs(plannedRoutesFromCurrentLocation) do
		if plannedRoute.destinationPlot.x == preferredDestination:GetX() and plannedRoute.destinationPlot.y == preferredDestination:GetY() then
			plannedRoute.projectState = "ASSIGNED";
			self.plannedRoute = plannedRoute;
			break;
		end
	end

	if self.plannedRoute then m_PlannedRoutes:save(self.plannedRoute); end
end

function MilitaryEngineerClass:workOnPlannedRoute()
	UnitManager.RequestCommand(UnitManager.GetUnit(self:getOwner(), self.ID), UNIT_COMMANDS["UNITCOMMAND_WAKE"].HASH);
	local unit = UnitManager.GetUnit(self:getOwner(), self.ID);
	if not unit then
		Error("workOnPlannedRoute: Unit does not exist!");
		return;
	end
	
	local currentPlot = Map.GetPlot(self:GetX(), self:GetY());
	if IsWaterTile(currentPlot) then
		Debug("workOnPlannedRoute: Current plot is a Water tile, so Railroad cannot be built here. Moving to next plot.");
	else
		local routeType = "NONE";
		if ROUTES[currentPlot:GetRouteType()] then routeType = ROUTES[currentPlot:GetRouteType()].NAME; end
		Debug_AllActions("workOnPlannedRoute: Current plot has RouteType [" .. routeType .. "]");
		if routeType ~= "ROUTE_RAILROAD" then
			 -- TODO: handle insufficient Iron/Coal and missing Steam Power tech - maybe with alert?
			self:buildRoad();
			return;
		end
		-- TODO: check if the current plot has a pillaged Railroad, if so, repair it
	end

	if self:GetX() == self.plannedRoute.destinationPlot.x and self:GetY() == self.plannedRoute.destinationPlot.y then
		self:completeRoute();
		self:performAction();
		return;
	end

	local endPlot = Map.GetPlot(self.plannedRoute.destinationPlot.x, self.plannedRoute.destinationPlot.y);
	local adjacentPlotsToDestination = Map.GetAdjacentPlots(endPlot:GetX(), endPlot:GetY());
	local isAdjacentToDestination = false;
	for key, adjPlotToDest in ipairs(adjacentPlotsToDestination) do
		if adjPlotToDest:GetIndex() == currentPlot:GetIndex() then
			isAdjacentToDestination = true;
			break;
		end
	end

	-- We check for this because moveToTarget also supports swapping places with another support unit.
	if isAdjacentToDestination then
		self:setMoveTarget(endPlot);
		self:moveToTarget("FALLBACK_STRATEGY_GIVE_UP");
		return;
	end

	local pathInfo = UnitManager.GetMoveToPath(unit, endPlot:GetIndex());
	if table.count(pathInfo) == 0 then
		if debug then Debug_AllActions("workOnPlannedRoute: There is no path to " .. PlotToString(endPlot) .. ". It may be blocked by another unit. Trying adjacent destination plots."); end
		local endPlotFallback;
		for key, adjPlot in ipairs(adjacentPlotsToDestination) do
			pathInfo = UnitManager.GetMoveToPath(unit, adjPlot:GetIndex());
			if table.count(pathInfo) > 0 then
				endPlotFallback = adjPlot;
				break;
			end
		end
		if endPlotFallback then
			if debug then Debug("workOnPlannedRoute: There is no path to " .. PlotToString(endPlot) .. ". Moving towards " .. PlotToString(endPlotFallback) .. " instead."); end
		else
			self:markRouteAsUnreachable();
			self:performAction();
			return;
		end
	end

	local nextPlot = Map.GetPlotByIndex(pathInfo[2]); -- pathInfo[1] is the current plot
	self:setMoveTarget(nextPlot);
	self:moveToTarget("FALLBACK_STRATEGY_SHARED_ADJACENCY_LAND");
	return;
end

--------------------------------------------------------------------------------------------------------
-- Refreshes Automated MilitaryEngineer instructions and automatically gives a command to each MilitaryEngineer.
local function PerformAutomatedMilitaryEngineerActions( iPlayer )
	for _, engineer in ipairs(m_MilitaryEngineers.members) do -- Go through militaryEngineers.
		if engineer.isAutomated and engineer:getOwner() == iPlayer then -- Check if they are automated and belong to the player
			local unit = UnitManager.GetUnit(iPlayer, engineer.ID);
			if unit and CheckUnitType(unit:GetUnitType(), "UNIT_MILITARY_ENGINEER") then
				Debug("PerformAutomatedMilitaryEngineerActions: Taking next action");
				engineer:performAction(); -- Refresh the MilitaryEngineer's next action.
				m_MilitaryEngineers:save(engineer); -- Save the data to m_MilitaryEngineers table.
			end
		end
	end
end

--------------------------------------------------------------------------------------------------------
local function OnUnitMovementPointsChanged(playerID, unitID, movement)
	if not UnitManager then return; end
	local unit = UnitManager.GetUnit(playerID, unitID);
	if not unit then return; end
	if movement == 0 then return; end -- only try to perform an action if the unit has moves left.
	if CheckUnitType(unit:GetUnitType(), "UNIT_MILITARY_ENGINEER") then
		local engineer = m_MilitaryEngineers:get(unit);
		if engineer and engineer.isAutomated then
			Debug_AllActions("OnUnitMovementPointsChanged: MilitaryEngineer (" .. engineer.ID .. ") has moves remaining, continuing work.");
			m_MilitaryEngineers:save(engineer);
			engineer:performAction();
		end
	elseif IsSupportUnit(unit) and m_SleepRequests:contains(unit:GetID()) then
		Debug("OnUnitMovementPointsChanged: " .. Locale.Lookup(GameInfo.Units[unit:GetUnitType()].Name) .. "[" .. unit:GetID() .. "] was woken by automation, commanding it to sleep now.");
		UnitManager.RequestOperation(unit, UNIT_OPS["UNITOPERATION_SLEEP"].HASH);
		m_SleepRequests:delete(unit:GetID());
	end
end

--------------------------------------------------------------------------------------------------------
local function OnUnitSelectionChanged(playerID, unitID, x, y, z, isSelected, isEditable)
	if not isSelected then return; end
	if not UnitManager then return; end
	local unit = UnitManager.GetUnit(playerID, unitID);
	local movement = unit:GetMovesRemaining();
	if movement == 0 then return; end

	if CheckUnitType(unit:GetUnitType(), "UNIT_MILITARY_ENGINEER") then
		local engineer = m_MilitaryEngineers:get(unit);
		if engineer and engineer.isAutomated then
			-- If movement > 0 and the last call to performAction resulted in no movement, that means the desired move is too expensive to perform this turn
			-- (e.g: moving into forest with 1.5 moves remaining). So there's no point in trying again this time round.
			if movement == engineer.movesRemainingOnPreviousSelection then
				Debug_AllActions("OnUnitSelectionChanged: Automated MilitaryEngineer [" .. unitID .. "] has not moved since it was last selected, so no further action will be attempted.");
				return;
			else engineer.movesRemainingOnPreviousSelection = movement; end
		end
	end
	-- Race conditions can cause actions to fail, triggering the unit to become selected, so we include this as a fallback event handler.
	OnUnitMovementPointsChanged(playerID, unitID, movement);
end

--------------------------------------------------------------------------------------------------------
local function OnUnitRemovedFromMap(playerID, unitID)
	local theMilitaryEngineer = m_MilitaryEngineers:getByPlayerAndUnitID(playerID, unitID);
	if theMilitaryEngineer and theMilitaryEngineer.isAutomated then 
		Debug("OnUnitRemovedFromMap: Automated MilitaryEngineer (" .. theMilitaryEngineer.ID .. ") was removed from the map, resetting object data in table...");
		-- Reset object data for this unit ID and save it back to the table.
		theMilitaryEngineer:setAutomated(false);
		theMilitaryEngineer:abandonRoute();
		m_MilitaryEngineers:save(theMilitaryEngineer);
	end
end

--------------------------------------------------------------------------------------------------------
local function OnResearchCompleted( iPlayer, param2, param3, param4 )
	if Players and iPlayer and Players[iPlayer]:IsHuman() then 
		m_Player = Players[iPlayer];
		Debug( "Tech completed for Player: " .. iPlayer .. ". Refreshing player valid routes." );
		if m_Player then 
			RefreshPlayerValidRoutes(iPlayer);
		end
	end
end

--------------------------------------------------------------------------------------------------------
local function OnPlayerTurnDeactivated( iPlayer )
	if Players and iPlayer and Players[iPlayer]:IsHuman() then 
		m_Player = Players[iPlayer];
		if m_Player then 
			if (GameConfiguration.IsHotseat() == true) and (m_isAutoMilitaryEngineer_GP_Loaded == true) then -- Save tables in gameplay script	after player turn ends
				m_AutoMilitaryEngineer_GP.SetMilitaryEngineers( m_MilitaryEngineers );
			end
		end
	end
end

--------------------------------------------------------------------------------------------------------
local function OnPlayerTurnActivated( iPlayer )
	if Players and iPlayer and Players[iPlayer]:IsHuman() then 
		m_Player = Players[iPlayer];
		if m_Player then 
			if ( ( GameConfiguration.IsHotseat() == true ) and ( m_isAutoMilitaryEngineer_GP_Loaded == true ) and ( m_AutoMilitaryEngineer_GP.HasMembers() == true ) ) then
				-- Retrieve tables from gameplay script
				m_MilitaryEngineers = m_AutoMilitaryEngineer_GP.GetMilitaryEngineers();
			end
			Debug("OnPlayerTurnActivated: Performing actions for all automated MilitaryEngineers.");
			PerformAutomatedMilitaryEngineerActions(iPlayer); -- Tell MilitaryEngineers to perform their queued actions.
		end
	end
end

--------------------------------------------------------------------------------------------------------
local function InitializeAutoMilitaryEngineerGP()
	if ExposedMembers.CNO_AutoMilitaryEngineer_GP_Initialized then 
        m_AutoMilitaryEngineer_GP = ExposedMembers.CNO_AutoMilitaryEngineer_GP;   -- contains functions from other context
        Events.GameCoreEventPublishComplete.Remove( InitializeAutoMilitaryEngineerGP );
		m_isAutoMilitaryEngineer_GP_Loaded = true;
		print( "AutoMilitaryEngineer: Loaded gameplay script context." );	
    end
end

ExposedMembers.CNO_AutoMilitaryEngineer_Initialized = false;

--------------------------------------------------------------------------------------------------------
function Initialize()
	-- Populate player data for all human players when initializing.
	for ID = 0, PlayerManager.GetWasEverAliveCount() - 1 do -- go through players.
		local player = Players[ID];
		if player:IsHuman() then
			RefreshPlayerValidRoutes(ID);
		end
	end

	Events.UnitMovementPointsChanged.Add(OnUnitMovementPointsChanged);
	Events.ResearchCompleted.Add(OnResearchCompleted);
	Events.PlayerTurnActivated.Add(OnPlayerTurnActivated);
	Events.PlayerTurnDeactivated.Add(OnPlayerTurnDeactivated);
	Events.UnitRemovedFromMap.Add(OnUnitRemovedFromMap);
	-- Fallback event in case a user is asked to select an action for a MilitaryEngineer
	Events.UnitSelectionChanged.Add(OnUnitSelectionChanged);
	
	-- Gedemon's method for sharing functions between different contexts using the ExposedMembers table.
	if ( not ExposedMembers.CNO_AutoMilitaryEngineer ) then ExposedMembers.CNO_AutoMilitaryEngineer = {}; end
	ExposedMembers.CNO_AutoMilitaryEngineer.AutomateMilitaryEngineer = AutomateMilitaryEngineer;
	ExposedMembers.CNO_AutoMilitaryEngineer.StopAutomateMilitaryEngineer = StopAutomateMilitaryEngineer;
	ExposedMembers.CNO_AutoMilitaryEngineer.debug = debug;
	ExposedMembers.CNO_AutoMilitaryEngineer.IsMilitaryEngineerAutomated = IsMilitaryEngineerAutomated;
	ExposedMembers.CNO_AutoMilitaryEngineer.GetUnitStatus = GetMilitaryEngineerStatus;
	ExposedMembers.CNO_AutoMilitaryEngineer_Initialized = true;

	Events.GameCoreEventPublishComplete.Add( InitializeAutoMilitaryEngineerGP );
end

Initialize();
