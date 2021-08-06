-- AutomatedMilitaryEngineers_UI
-- Author: MadManCam
-- DateCreated: 4/22/2018 8:51:11 PM
-- Automation for all added by Adriaman in April 2021.
--------------------------------------------------------------

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
			for k,v in pairs(node) do
				size = size + 1
			end

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
					if (type(k) == "number" or type(k) == "boolean") then
						key = "["..tostring(k).."]"
					else
						key = "['"..tostring(k).."']"
					end

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

					if (cur_index == size) then
						output_str = output_str .. "\n" .. string.rep('\t',depth-1) .. "}"
					else
						output_str = output_str .. ","
					end
				else
					-- close the table
					if (cur_index == size) then
						output_str = output_str .. "\n" .. string.rep('\t',depth-1) .. "}"
					end
				end

				cur_index = cur_index + 1
			end

			if (size == 0) then
				output_str = output_str .. "\n" .. string.rep('\t',depth-1) .. "}"
			end

			if (#stack > 0) then
				node = stack[#stack]
				stack[#stack] = nil
				depth = cache[node] == nil and depth + 1 or depth - 1
			else
				break
			end
		end

		-- This is necessary for working with HUGE tables otherwise we run out of memory using concat on huge strings
		table.insert(output,output_str)
		
		
		-- A for loop + print makes the ouput easier to handle by the lua engine.
		-- output_str = table.concat(output)
		-- print(output_str)
		
		for _, v in ipairs(output) do
		  print(v)
		end
	end
end

local function GetCivFromTrait( trait )
	local civs = {};
	for row in GameInfo.CivilizationTraits() do 
		if row.TraitType == trait then table.insert( civs, row.CivilizationType ); end
	end
	if civs[1] then return civs; else return nil; end
end

local function GetLeaderFromTrait( trait )
	local leaders = {};
	for row in GameInfo.LeaderTraits() do 
		if row.TraitType == trait then table.insert( leaders, row.LeaderType ); end
	end
	if leaders[1] then return leaders; else return nil; end
end


--------------------------------------------------------------------------------------------------------


local m_AutoMilitaryEngineer     = {};

local m_GameMods        = Modding.GetActiveMods();
local m_ScriptsLoaded   = false;
local m_isOkayToProcess = true;

local m_isMinibarClosed    = true;
local m_isTitleStackClosed = true;

local m_selectedPlayerId  = -1;
local m_UnitId            = -1;
local m_defaultUnitStatus = "";
local m_UnitStatus        = m_defaultUnitStatus;

local MAX_STATUS_LENGTH = 36;
local MINIBAR_PARENT    = "/InGame/UnitPanel/MainPanel";


-- =========================================================================================================================================
-- AutoMilitaryEngineers mod
local function InitializeAutoMilitaryEngineer()
  if ExposedMembers.CNO_AutoMilitaryEngineer_Initialized then 
    m_AutoMilitaryEngineer = ExposedMembers.CNO_AutoMilitaryEngineer;   -- contains local functions from other context
    Events.GameCoreEventPublishComplete.Remove( InitializeAutoMilitaryEngineer );
    print("AutoMilitaryEngineer: Exposed Functions from AutoMilitaryEngineers.lua context added...");
    if ExposedMembers.CNO_AutoMilitaryEngineer.debug then print ("AutoMilitaryEngineer: Debug logging is currently enabled.");
    else print ("AutoMilitaryEngineer: Debug logging is currently disabled."); end
    
    m_ScriptsLoaded = true;
    ContextPtr:RequestRefresh();
  end
end

-- =========================================================================================================================================
-- Returns nothing if the local function is not callable.
local function callIfCallable( f )
  return function( ... )
           error, result = pcall( f, ... );
           if error then return result;
                   else return nil; end
         end
end

-- =========================================================================================================================================
local function UpdateUnitStatus( status_string )
  --print( status_string );
  --status_string = "abcdefghijklmnopqrstuvwxyz12345678"
  local string_length = status_string:len();
  --print( "Status string length: " .. string_length );
  if string_length > MAX_STATUS_LENGTH then -- separate status string into two boxes
    local divider_index = math.ceil( string_length / 2.0 ); -- About halfway through the string
    for i = 0,10 do -- iterate up to 10 more characters to the right to try to find a space.
      local nextChar = status_string:sub( divider_index + 1, divider_index + 1 );
      if nextChar == " " then -- Stop iterating if we found a space.
        divider_index = divider_index + 1;
        break;
      end 
      divider_index = divider_index + 1;
    end
    local string1 = status_string:sub( 1, divider_index );
    local string2 = status_string:sub( divider_index + 1 );
    Controls.UnitStatus:SetText( "" );
    Controls.UnitStatusTop:SetText( string1 );
    Controls.UnitStatusBottom:SetText( string2 );
  else 
    Controls.UnitStatus:SetText( status_string );
    Controls.UnitStatusTop:SetText( "" );
    Controls.UnitStatusBottom:SetText( "" );
  end
end

-- =========================================================================================================================================
 -- eudaimonia
local function Hide()
  if not Controls.CNO_AutomatedMilitaryEngineers_Minibar_Container:IsHidden() then -- play collapse animation.
    Controls.CNO_AutoMilitaryEngineers_Minibar_CollapseAnim:SetToBeginning();
    Controls.CNO_AutoMilitaryEngineers_Minibar_CollapseAnim:Play();
    Controls.CNO_AutomatedMilitaryEngineers_Minibar_Container:SetHide( true );
  end
  
  m_isMinibarClosed = true;
end

-- =========================================================================================================================================
 -- eudaimonia
local function Show()
  if Controls.CNO_AutomatedMilitaryEngineers_Minibar_Container:IsHidden() then -- play expand animation.
    Controls.CNO_AutomatedMilitaryEngineers_Minibar_Container:SetHide( false );
    Controls.CNO_AutoMilitaryEngineers_Minibar_Alpha:SetToBeginning();
    Controls.CNO_AutoMilitaryEngineers_Minibar_Alpha:Play();
    Controls.CNO_AutoMilitaryEngineers_Minibar_ExpandAnim:SetToBeginning();
    Controls.CNO_AutoMilitaryEngineers_Minibar_ExpandAnim:Play();
  end
  
  m_isMinibarClosed = false;
end

-- =========================================================================================================================================
-- Refreshes the Automated Units Minibar.
local function RefreshUnitActions( player, unit )

  local b_UseMinibar = false; -- Used to determine whether or not to show the Automated Units Minibar.	
  m_UnitStatus = m_defaultUnitStatus;

  -- Is this a MilitaryEngineer?
  if unit:GetUnitType() == GameInfo.Units["UNIT_MILITARY_ENGINEER"].Index then
    
    b_UseMinibar = true; -- Show the Automated Units Minibar
    if not m_AutoMilitaryEngineer.IsMilitaryEngineerAutomated( unit ) then -- MilitaryEngineer is not automated by main version
      Controls.StopAutomateButton:SetHide( true ); -- Hide Stop Automation button
      Controls.AutomateButton:SetHide( false ); -- Show Automate Actions button	
    else -- MilitaryEngineer automated by main version 
      m_UnitStatus = m_AutoMilitaryEngineer.GetUnitStatus( unit );
      Controls.StopAutomateButton:SetHide( false ); -- Show Stop Automation button
      Controls.AutomateButton:SetHide( true ); -- Hide Automate Actions button
    end
	
    local units = Players[player]:GetUnits();

	local anyAutomated = false
	
	if units ~= nil then 
		for i, unit in units:Members() do
			if unit:GetUnitType() == GameInfo.Units["UNIT_MILITARY_ENGINEER"].Index then
				if m_AutoMilitaryEngineer.IsMilitaryEngineerAutomated(unit) then
					anyAutomated = true
					break
				end
			end
		end
	end

	
    if not anyAutomated then -- Not all builders are automated by main version
      Controls.StopAutomateAllButton:SetHide( true ); -- Hide Stop Automation All button
      Controls.AutomateAllButton:SetHide( false ); -- Show Automate Actions All button	
    else -- MilitaryEngineer automated by main version 
      Controls.StopAutomateAllButton:SetHide( false ); -- Show Stop Automation All button
      Controls.AutomateAllButton:SetHide( true ); -- Hide Automate Actions All button
    end
  end
  
  UpdateUnitStatus( m_UnitStatus ); -- Set Unit Status text.

  local unitType = GameInfo.Units[unit:GetUnitType()].UnitType;
  if b_UseMinibar then Show(); else Hide(); end -- eudaimonia

end

-- =========================================================================================================================================
-- TO be used every time before an action controlled by this script is clicked.
local function BeforeUnitActionClicked()
  -- Change interface mode back to selection, this prevents old interface modes (such as range attack) sticking around after action is pressed.
  local currentMode = UI.GetInterfaceMode();
  if currentMode ~= InterfaceModeTypes.SELECTION then
    print( "Automated MilitaryEngineers forcing interface mode back to selection before performing operation/action" ); --Debug
    UI.SetInterfaceMode( InterfaceModeTypes.SELECTION );
  end
end
--
-- =========================================================================================================================================
local function AutomateUnit(unit)
      -- Is this a MilitaryEngineer?
      if unit:GetUnitType() == GameInfo.Units["UNIT_MILITARY_ENGINEER"].Index then
        if not m_AutoMilitaryEngineer.IsMilitaryEngineerAutomated( unit ) then -- don't proceed if MilitaryEngineer is already automated by main version
          BeforeUnitActionClicked();
          m_AutoMilitaryEngineer.AutomateMilitaryEngineer( unit );
        else
          print( "ERROR: Attempt to Automate Actions for a MilitaryEngineer that is already automated." );
        end
        ContextPtr:RequestRefresh(); -- Refresh UI
      end
end

-- Automate Actions button was pressed.
local function OnAutomate()
  
  if ( m_isOkayToProcess ) then
    local pSelectedUnit = UI.GetHeadSelectedUnit();
    if ( pSelectedUnit ~= nil ) then
      local units = Players[m_selectedPlayerId]:GetUnits();
      local unit = units:FindID(m_UnitId);
	  AutomateUnit(unit)
	  RefreshUnitActions(m_selectedPlayerId, unit)
    end
  end

end

function OnAutomateAll()
  if ( m_isOkayToProcess ) then
      local pSelectedUnit = UI.GetHeadSelectedUnit();
		if ( pSelectedUnit ~= nil ) then
		unitType = pSelectedUnit:GetUnitType()
		 if unitType == GameInfo.Units["UNIT_MILITARY_ENGINEER"].Index then
			local units = Players[m_selectedPlayerId]:GetUnits();

			if units ~= nil then 
				for i, unit in units:Members() do
					if unit:GetUnitType() == unitType then
						if not m_AutoMilitaryEngineer.IsMilitaryEngineerAutomated(unit) then
							AutomateUnit(unit)
						end
					end
				end
			end
			RefreshUnitActions(m_selectedPlayerId, pSelectedUnit)
		end
	end
  end
end

local function StopAutomateUnit(unit)
  -- Is this a MilitaryEngineer?
  if unit:GetUnitType() == GameInfo.Units["UNIT_MILITARY_ENGINEER"].Index then
	BeforeUnitActionClicked();
	m_AutoMilitaryEngineer.StopAutomateMilitaryEngineer( unit );
	ContextPtr:RequestRefresh(); -- Refresh UI
  end
end
-- =========================================================================================================================================
-- Stop Automation button was pressed.
local function OnStopAutomate()
  if ( m_isOkayToProcess ) then
    local pSelectedUnit = UI.GetHeadSelectedUnit();
    if ( pSelectedUnit ~= nil ) then
      local units = Players[m_selectedPlayerId]:GetUnits();
      local unit = units:FindID(m_UnitId);
	  StopAutomateUnit(unit)
      RefreshUnitActions(m_selectedPlayerId, unit)
    end
  end

end

function OnStopAutomateAll()
  if ( m_isOkayToProcess ) then
      local pSelectedUnit = UI.GetHeadSelectedUnit();
		if ( pSelectedUnit ~= nil ) then
		unitType = pSelectedUnit:GetUnitType()
		if unitType == GameInfo.Units["UNIT_MILITARY_ENGINEER"].Index then
			local units = Players[m_selectedPlayerId]:GetUnits();

			if units ~= nil then 
				for i, unit in units:Members() do
					if unit:GetUnitType() == unitType then
						if m_AutoMilitaryEngineer.IsMilitaryEngineerAutomated(unit) then
							StopAutomateUnit(unit)
						end
					end
				end
			end
			
			RefreshUnitActions(m_selectedPlayerId, pSelectedUnit)
		end
	end
  end
end


-- =========================================================================================================================================
local function Refresh(player, unitId)
  if( Players and Players[player] and player ~= nil and player ~= -1 and unitId ~= nil and unitId ~= -1) then
    local units = Players[player]:GetUnits();
    local unit = units:FindID(unitId);
    if(unit ~= nil) then
      RefreshUnitActions( player, unit );
    else
      Hide();
    end
  else
    Hide();
  end
end

-- =========================================================================================================================================
local function OnRefresh()
  ContextPtr:ClearRequestRefresh();   -- Clear the refresh request, in case we got here from some other means.  This cuts down on redundant updates.
  Refresh(m_selectedPlayerId, m_UnitId);
end

-- =========================================================================================================================================
local function OnBeginWonderReveal()
  Hide();
end

-------------------------------------------------------------------------------
local function OnUnitSelectionChanged(player, unitId, locationX, locationY, locationZ, isSelected, isEditable)
  --print("UnitPanel::OnUnitSelectionChanged(): ",player,unitId,isSelected);
  if (isSelected) then
    m_selectedPlayerId = player;
    m_UnitId = unitId;
    Refresh(m_selectedPlayerId, m_UnitId);
  else
    m_selectedPlayerId  = nil;
    m_UnitId      = nil;
    -- This event is raised on deselected units too; only hide if there
    -- is no selected units left.
    if UI and (UI.GetHeadSelectedUnit()== nil) then
      Hide();
    end
  end

end

-- =========================================================================================================================================
local function ShowHideSelectedUnit()
  m_isOkayToProcess = true;
  local pSelectedUnit :table = UI.GetHeadSelectedUnit();
  if pSelectedUnit ~= nil then
    m_selectedPlayerId        = pSelectedUnit:GetOwner();
    m_UnitId            = pSelectedUnit:GetID();
    Refresh( m_selectedPlayerId, m_UnitId );
  else
    Hide();
  end
end

-- =========================================================================================================================================
local function OnGameConfigChanged_Hotseat_Paused()
  Events.GameConfigChanged.Remove(OnGameConfigChanged_Hotseat_Paused);
  if(not GameConfiguration.IsPaused()) then
    ShowHideSelectedUnit();
  end
end

-- =========================================================================================================================================
local function OnPlayerChangeClose( ePlayer )
  local isPaused = GameConfiguration.IsPaused();
  --print("OnPlayerChangeClose: " .. ePlayer .. ", GameConfiguration.IsPaused()=" .. tostring(isPaused));
  if(isPaused) then
    Events.GameConfigChanged.Add(OnGameConfigChanged_Hotseat_Paused);
  end
end

-- =========================================================================================================================================
local function OnPlayerTurnDeactivated( ePlayer )
  if ePlayer == Game.GetLocalPlayer() then
    m_isOkayToProcess = false;
  end
end

-- =========================================================================================================================================
local function OnPlayerTurnActivated( ePlayer, isFirstTime )
  if ePlayer == Game.GetLocalPlayer() then
    ShowHideSelectedUnit();
  end
end

-- =========================================================================================================================================
local function OnPhaseBegin()
  ContextPtr:RequestRefresh();
end

-- =========================================================================================================================================
local function OnContextInitialize( isHotload : boolean)
  if isHotload then
    -- OnPlayerTurnActivated( Game.GetLocalPlayer(), true ) ;  -- Fake player activated call.
  end
end

-- =========================================================================================================================================
local function OnCitySelectionChanged(owner, ID, i, j, k, bSelected, bEditable)
  Hide();
end

-- =========================================================================================================================================
local function OnUnitRemovedFromMap( playerID: number, unitID : number )
  if(playerID == m_selectedPlayerId and unitID == m_UnitId) then
    Hide();
  end
end

-- =========================================================================================================================================
local function OnInterfaceModeChanged( eOldMode, eNewMode )
  if (eNewMode == InterfaceModeTypes.CITY_RANGE_ATTACK) then
    Show();
  elseif (eNewMode == InterfaceModeTypes.DISTRICT_RANGE_ATTACK) then
    Show();
  end
  if (eOldMode == InterfaceModeTypes.CITY_RANGE_ATTACK or eOldMode == InterfaceModeTypes.DISTRICT_RANGE_ATTACK) then
    Hide();
  end
end

-- =========================================================================================================================================
local function OnTitleStackMouseExit() -- Hide the title stack.
  if not ( Controls.TitleStack:IsHidden() ) then
    UI.PlaySound("Main_Menu_Mouse_Over");
    Controls.TitleStack:SetHide( true );
  end
  m_isTitleStackClosed = true;
end

-- =========================================================================================================================================
local function OnTitleStackMouseEnter() -- Show the title stack.
  if not ( m_isMinibarClosed ) then -- Only show if Minibar itself is open.
    if ( Controls.TitleStack:IsHidden() ) then
      UI.PlaySound("Main_Menu_Mouse_Over");
      Controls.TitleStack:SetHide( false );
      Controls.CNO_AutoMilitaryEngineers_Minibar_TitleStack_Alpha:SetToBeginning();
      Controls.CNO_AutoMilitaryEngineers_Minibar_TitleStack_Alpha:Play();
    end
    m_isTitleStackClosed = false;
  end
end

-- =========================================================================================================================================
local function OnUnitStatusUpdate()
  ContextPtr:RequestRefresh(); -- Refresh selected unit status info.	
end

-- =========================================================================================================================================
local function InitializeControls()
  -- Register button callbacks.
  Controls.AutomateButton:RegisterCallback( Mouse.eLClick, OnAutomate );
  Controls.AutomateButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);	
  Controls.StopAutomateButton:RegisterCallback( Mouse.eLClick, OnStopAutomate );
  Controls.StopAutomateButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);

  Controls.AutomateAllButton:RegisterCallback( Mouse.eLClick, OnAutomateAll );
  Controls.AutomateAllButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);	
  Controls.StopAutomateAllButton:RegisterCallback( Mouse.eLClick, OnStopAutomateAll );
  Controls.StopAutomateAllButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
  
  Controls.CNO_AutomatedMilitaryEngineers_Main_Container:RegisterMouseEnterCallback( OnTitleStackMouseEnter );
  Controls.TitleStack_Container:RegisterMouseEnterCallback( OnTitleStackMouseEnter );
  Controls.CNO_AutomatedMilitaryEngineers_Minibar_Container:RegisterMouseEnterCallback( OnTitleStackMouseEnter );
  Controls.CNO_AutomatedMilitaryEngineers_Minibar_Container:RegisterMouseExitCallback( OnTitleStackMouseExit );
end

-- =========================================================================================================================================
-- eudaimonia
local function AttachMinibarToPanel()
  Controls.CNO_AutomatedMilitaryEngineers_Minibar_Container:ChangeParent( ContextPtr:LookUpControl( MINIBAR_PARENT ) );
  Controls.CNO_AutomatedMilitaryEngineers_Minibar_Container:SetAnchor( "R,B" );
  Controls.CNO_AutomatedMilitaryEngineers_Minibar_Container:SetOffsetX( -80 );
  Controls.CNO_AutomatedMilitaryEngineers_Minibar_Container:SetOffsetY( 220 );
end

-- =========================================================================================================================================
function Initialize()

  ContextPtr:SetInitHandler( OnContextInitialize );
  ContextPtr:SetRefreshHandler( OnRefresh );

  -- Automated Units, initialize scripts if mod is loaded.
  Events.GameCoreEventPublishComplete.Add( InitializeAutoMilitaryEngineer );

  Events.BeginWonderReveal.Add( OnBeginWonderReveal );
  Events.CitySelectionChanged.Add( OnCitySelectionChanged );
  Events.InterfaceModeChanged.Add( OnInterfaceModeChanged );
  Events.PhaseBegin.Add( OnPhaseBegin );
  Events.PlayerTurnActivated.Add( OnPlayerTurnActivated );
  Events.PlayerTurnDeactivated.Add( OnPlayerTurnDeactivated );
  Events.UnitRemovedFromMap.Add( OnUnitRemovedFromMap );
  Events.UnitSelectionChanged.Add( OnUnitSelectionChanged );

  LuaEvents.PlayerChange_Close.Add( OnPlayerChangeClose );
  LuaEvents.CNO_AutoMilitaryEngineer_OnMilitaryEngineerActionsUpdate.Add( OnUnitStatusUpdate );
  
  InitializeControls();

  Events.LoadGameViewStateDone.Add(AttachMinibarToPanel);  -- eudaimonia
end

--Events.LoadScreenClose.Add( Initialize );
Initialize();