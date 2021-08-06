-- AutoMilitaryEngineers_GameplayScript
-- Author: MadManCam
-- DateCreated: 5/6/2018 6:26:36 PM
--------------------------------------------------------------

-- This is a gameplay script to save the automated MilitaryEngineers table in. This way the data is saved even when the UI is refreshed.
-- This means the mod can support hot seat mode.

local b_HasMembers = false;

 -- Table of MilitaryEngineers.
local m_MilitaryEngineers_GP = {};

-- Table of plots.
local m_MilitaryEngineer_Plots_GP = {};

-- Set Automated MilitaryEngineer table data in this gameplay script
local function SetMilitaryEngineers( new_m_MilitaryEngineers )
	print( "AutoMilitaryEngineer Gameplay Script: Saved Automated MilitaryEngineers table in gameplay context." );
	m_MilitaryEngineers_GP = new_m_MilitaryEngineers;
	b_HasMembers = true;
end

-- Set MilitaryEngineer target plot data in this gameplay script
local function SetMilitaryEngineerPlots( new_m_MilitaryEngineer_Plots )
	m_MilitaryEngineer_Plots_GP = new_m_MilitaryEngineer_Plots;
end

-- Get MilitaryEngineer table data
local function GetMilitaryEngineers()
	b_HasMembers = false; -- Reset has members to true, indicating we have already retrieved the most up to date table.
	return m_MilitaryEngineers_GP;
end

-- Get MilitaryEngineer Plots table data
local function GetMilitaryEngineerPlots()
	return m_MilitaryEngineer_Plots_GP;
end

-- Returns true if there are members saved in table.
local function HasMembers()
	return b_HasMembers;
end

ExposedMembers.CNO_AutoMilitaryEngineer_GP_Initialized = false;

function Initialize()

	if ( not ExposedMembers.CNO_AutoMilitaryEngineer_GP ) then ExposedMembers.CNO_AutoMilitaryEngineer_GP = {}; end
	ExposedMembers.CNO_AutoMilitaryEngineer_GP.HasMembers = HasMembers;
	ExposedMembers.CNO_AutoMilitaryEngineer_GP.GetMilitaryEngineers = GetMilitaryEngineers;
	ExposedMembers.CNO_AutoMilitaryEngineer_GP.GetMilitaryEngineerPlots = GetMilitaryEngineerPlots;
	ExposedMembers.CNO_AutoMilitaryEngineer_GP.SetMilitaryEngineers = SetMilitaryEngineers;
	ExposedMembers.CNO_AutoMilitaryEngineer_GP.SetMilitaryEngineerPlots = SetMilitaryEngineerPlots;
	ExposedMembers.CNO_AutoMilitaryEngineer_GP_Initialized = true;

end

Initialize(); 
