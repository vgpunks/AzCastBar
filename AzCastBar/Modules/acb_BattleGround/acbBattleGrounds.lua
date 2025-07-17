local GetTime = GetTime;

-- General
local BASE_ATTACK = "^.+ claims the (.+)!  If left unchallenged, the (.+) will control it";	-- Happens when base was uncontrolled, Neutral to Horde or Alliance

-- Warsong Gulch
local WSG_GAME_START = "^The battle for (.+) begins in (%d+) (.+)%.";
local WSG_FLAG_CAPTURE ="^.+ captured the (.+) flag!";
local WSG_FLAG_PICK = "^The (.+) [Ff]lag was picked up by (.+)!$";	-- No idea why the "F" can be both lower and upper case
local WSG_FLAG_RESPAWN = 22;
local WSG_FLAG_DROP = "^The (.+) [Ff]lag was dropped by (.+)!";
local WSG_ZONE_NAME = "Warsong Gulch";

-- Alterac Valley
local AV_GAME_START = "^(%d+) (.+) until the battle for (.+) begins%.";
local AV_CAPTURE_TIME = (60 * 4);
local AV_GY_ATTACK =  "^The (.+) is under attack!  If left unchecked, the (.+) will .+ it!";	-- Last .+ is either "destroy" or "control"
local AV_TOWER_ATTACK = "^(.+) is under attack!  If left unchecked, the (.+) will destroy it!";	-- Sometimes starts with "The" at the start, but then it will be cought by the AV_GY_ATTACK
local AV_DEFEND = "^The (.+) was taken by the (.+)!";
local AV_DEFEND2 = "^(.+) was taken by the (.+)!";

-- Arathi Basin
local AB_GAME_START ="^The Battle for (.+) will begin in (%d+) (.+)";
local AB_CAPTURE_TIME = 63;
local AB_BASE_ATTACK = "^.+ has assaulted the (.+)!";
local AB_BASE_DEFEND = "^.+ has defended the (.+)!";

-- Arena
local ARENA_GAME_START = "^(%d+) (.+) until the Arena battle begins!$";

-- Eye of the Storm
local EOTS_GAME_START = "^The battle begins in (%d+) (.+)!";

-- Strand of the Ancients
local SOTA_ROUND2_START_A = "^Round 2 of the Battle for the (.+) begins in (%d+) (.+)%.";
local SOTA_ROUND2_START_B = "^Round 2 begins in (.+) (.+)%.";

-- Icons
local BG_ICONS = {
	Horde = "Interface\\Icons\\INV_BannerPVP_01",
	Alliance = "Interface\\Icons\\INV_BannerPVP_02",
};

-- Colors
local CLASS_COLORS = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS;

-- Extra Options
local extraOptions = {
	{
		[0] = "Colors",
		{ type = "Color", var = "colNeutral", default = { 0.25, 0.76, 0.58 }, label = "Neutral Color" },
		{ type = "Color", var = "colAlliance", default = { 0.4, 0.6, 0.8 }, label = "Alliance Color" },
		{ type = "Color", var = "colHorde", default = { 1.0, 0.5, 0.5 }, label = "Horde Color" },
	},
};

-- Vars
local plugin = AzCastBar:CreateMainBar("Button","BattleGround",extraOptions,true);
local timers = LibTableRecycler:New();
local frames = {};
local defNameColor = { r = 0.2, g = 1, b = 0.2 };

--------------------------------------------------------------------------------------------------------
--                                   WSG Flag Carrier Secure Frames                                   --
--------------------------------------------------------------------------------------------------------

-- Create Button
local function CreateNameButton(index)
	local button = CreateFrame("Button",nil,UIParent,"SecureActionButtonTemplate");
	button.text = button:CreateFontString(nil,"ARTWORK","GameFontNormal");
	button.text:SetPoint("LEFT",4,0);
	button:SetSize(85,20);
	button:SetPoint("LEFT","AlwaysUpFrame"..(index + 1).."DynamicIconButton","RIGHT",8,2);
	button:EnableMouse(1);
	button:SetAttribute("type","macro");
	return button;
end

-- Make Both Frames
local function MakeWSGFrames()
	if (InCombatLockdown()) or (frames.Alliance and frames.Horde) then
 		return;
	end
	-- Req BG Score Info
	SetBattlefieldScoreFaction(nil);
	RequestBattlefieldScoreData();
	-- Create Frame if it doesn't exist
	frames.Alliance = CreateNameButton(2);
	frames.Horde = CreateNameButton(1);
	return true;
end

-- Setup the Frame
local function SetupWSGFrame(faction,name)
	MakeWSGFrames();
	local button = frames[faction];
	if (not button) then
 		return;
	end
	-- Req BG Score Info
	SetBattlefieldScoreFaction(nil);
	RequestBattlefieldScoreData();
	-- Set Text & Find BG Names
	if (name) then
		button.name = name;
		button.text:SetText(name);
		button.text:SetTextColor(0,1,0);
		local color = defNameColor;
		if (faction ~= UnitFactionGroup("player")) then
			for i = 1, GetNumRaidMembers() do
				if (name == UnitName("raid"..i)) then
					local _, class = UnitClass("raid"..i);
					color = CLASS_COLORS[class];
					break;
				end
			end
		else
			for i = 1, GetNumBattlefieldScores() do
				local boardName, _, _, _, _, _, _, _, class = GetBattlefieldScore(i);
				if (name == boardName:match("^(.+)%-")) then
					color = CLASS_COLORS[class];
					break;
				end
			end
		end
		button.text:SetTextColor(color.r,color.g,color.b);
	end
	-- Set Macro
	if (InCombatLockdown()) then
		button.fixAfter = 1;
	elseif (button.name == "") then
		button:Hide();
	else
		button:SetAttribute("macrotext","/target "..button.name);
		button:Show();
	end
end

--------------------------------------------------------------------------------------------------------
--                                           Timer Functions                                          --
--------------------------------------------------------------------------------------------------------

-- Sort Timers
local function SortFunc(a,b)
	return (a.startTime + a.duration) < (b.startTime + b.duration)
end

-- Add Timer
local function AddTimer(label,duration,faction)
	for index, table in ipairs(timers) do
		if (table.label == label) then
			timers:RecycleIndex(index);
			break;
		end
	end
	local tbl = timers:Fetch();
	tbl.label = label; tbl.duration = duration; tbl.faction = faction; tbl.startTime = GetTime(); tbl.fadeElapsed = 0;
	sort(timers,SortFunc);
	plugin:UpdateTimers();
end

-- Remove Timer with given label
local function RemoveTimer(label)
	for index, table in ipairs(timers) do
		if (table.label == label) then
			timers:RecycleIndex(index);
			plugin:UpdateTimers();
			break;
		end
	end
end

--------------------------------------------------------------------------------------------------------
--                                            Bar OnUpdate                                            --
--------------------------------------------------------------------------------------------------------

local function OnUpdate(self,elapsed)
	local timer = self.timer;
	-- Progress
	if (not timer.fadeTime) then
		self.timeLeft = max(0,timer.startTime + timer.duration - GetTime());
		self.status:SetValue(timer.duration - self.timeLeft);
		self:SetTimeText(self.timeLeft);
		if (self.timeLeft == 0) then
			timer.fadeTime = self.cfg.fadeTime;
		end
	-- FadeOut
	elseif ((self.fadeElapsed + elapsed) <= self.fadeTime) then--elseif (timer.fadeElapsed < timer.fadeTime) then
		timer.fadeElapsed = (timer.fadeElapsed + elapsed);
		self:SetAlpha(self.cfg.alpha - timer.fadeElapsed / timer.fadeTime * self.cfg.alpha);
	else
		RemoveTimer(timer.label);
	end
end

--------------------------------------------------------------------------------------------------------
--                                           Event Handling                                           --
--------------------------------------------------------------------------------------------------------

-- Get time duration
local function GetZoneDuration()
	return (GetRealZoneText() == "Alterac Valley") and AV_CAPTURE_TIME or AB_CAPTURE_TIME;
end

local function OnEvent(self,event,p1,p2,...)
	-- Hide all bars upon zoning.
	if (event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA") then
		if (event == "PLAYER_ENTERING_WORLD") then
			for index, table in ipairs(timers) do
				table.fadeTime = self.cfg.fadeTime;
			end
		end
		if (GetRealZoneText() == WSG_ZONE_NAME) then
			MakeWSGFrames();
		elseif (frames.Alliance) and (frames.Alliance:IsShown()) then
			if (not InCombatLockdown()) then
				frames.Alliance:Hide();
				frames.Horde:Hide();
			else
				AzMsg("BGTimers Debug: Could not hide WSG Flag Frames, was in combat on zone change!"); -- Az: Debug
			end
		end
	-- BG Status Update
	elseif (event == "UPDATE_BATTLEFIELD_STATUS") then
		for i = #timers, 1, -1 do
			if (timers[i].faction == event) then
				tremove(timers,i);
			end
		end
		local status, mapName, instanceID;
		for i = 1, GetMaxBattlefieldID() do
			status, mapName, instanceID = GetBattlefieldStatus(i);
			if (status == "confirm") then
				AddTimer(mapName.." "..instanceID,GetBattlefieldPortExpiration(i) / 1000,event);
			end
		end
		plugin:UpdateTimers();
	------------------------
	-- End if not in a BG --
	------------------------
	elseif (select(2,IsInInstance()) ~= "pvp") then
		return;
	-- Yells
	elseif (event == "CHAT_MSG_MONSTER_YELL") and (p2 == "Herald") then
		-- attack (gy + tower)
		local place, faction = p1:match(AV_GY_ATTACK);
		if (not place) then
			place, faction = p1:match(AV_TOWER_ATTACK);
		end
		if (place) then
			AddTimer(place,GetZoneDuration(),faction);
			return;
		end
		-- defend
		place, faction = p1:match(AV_DEFEND);
		if (not place) then
			place, faction = p1:match(AV_DEFEND2);
		end
		if (place) then
			RemoveTimer(place);
			return;
		end
	-- Alliance / Horde
	elseif (event == "CHAT_MSG_BG_SYSTEM_HORDE" or event == "CHAT_MSG_BG_SYSTEM_ALLIANCE") then
		-- attack
		local name, faction = p1:match(BASE_ATTACK);
		if (not name) then
			name = p1:match(AB_BASE_ATTACK);
		end
		if (name) then
			faction = (event == "CHAT_MSG_BG_SYSTEM_HORDE" and "Horde" or "Alliance");
			AddTimer(name,GetZoneDuration(),faction);
			return;
		end
		-- defend
		name = p1:match(AB_BASE_DEFEND);
		if (name) then
			RemoveTimer(name);
			return;
		end
		-- wsg: flag pick
		faction, name = p1:match(WSG_FLAG_PICK);
		if (faction) then
			SetupWSGFrame(faction,name);
			return;
		end
		-- wsg: flag capture
		faction = p1:match(WSG_FLAG_CAPTURE);
		if (faction) then
			AddTimer("Flag Respawn",WSG_FLAG_RESPAWN,faction);
			if (frames[faction]) then
				SetupWSGFrame(faction,"");
			end
			return;
		end
		-- wsg: flag drop
		faction, name = p1:match(WSG_FLAG_DROP);
		if (name) then
			if (frames[faction]) then
				SetupWSGFrame(faction,"");
			end
		end
	-- Neutral
	elseif (event == "CHAT_MSG_BG_SYSTEM_NEUTRAL") then
		local bg, time, units = p1:match(WSG_GAME_START);
		if (not time) then
			time, units, bg = p1:match(AV_GAME_START);
			if (not time) then
				bg, time, units = p1:match(AB_GAME_START);
				if (not time) then
					bg, time, units = p1:match(SOTA_ROUND2_START_A);
					if (not time) then
						time, units = p1:match(SOTA_ROUND2_START_B);
						if (not time) then
							time, units = p1:match(EOTS_GAME_START);
						end
					end
				end
			end
		end
		if (time) then
			time = tonumber(time);
			AddTimer((bg or "The Game").." Begins",units:match("minutes?") and time * 60 or time);
			return;
		end
	-- Combat End
	elseif (event == "PLAYER_REGEN_ENABLED") then
		for faction, frame in next, frames do
			if (frame.fixAfter) then
				SetupWSGFrame(faction);
				frame.fixAfter = nil;
			end
		end
	end
end

--------------------------------------------------------------------------------------------------------
--                                                Code                                                --
--------------------------------------------------------------------------------------------------------

-- Configure Bar
function plugin:ConfigureBar(bar)
	bar = (bar or self);
	bar:SetScript("OnUpdate",OnUpdate);
	return bar;
end

-- Title Case, first letter, and every letter after a space
local function TitleCase(string)
	return string:gsub("^(.)",strupper):gsub("( .)",strupper);
end

-- Update Timers
function plugin:UpdateTimers()
	-- Loop Timers and update bars
	local bar;
	for index, table in ipairs(timers) do
		bar = self.bars[index] or self:ConfigureBar(AzCastBar:CreateBar("Frame",self));
		bar.timer = table;

		bar.status:SetMinMaxValues(0,table.duration);
		bar.status:SetStatusBarColor(unpack(table.faction and self.cfg["col"..table.faction] or self.cfg.colNeutral));

		bar.name:SetText(TitleCase(table.label));
		bar.icon:SetTexture(table.faction and BG_ICONS[table.faction] or "Interface\\Icons\\Spell_Nature_UnrelentingStorm");

		bar.totalTimeText = bar:FormatTotalTime(table.duration);
		if (not table.fadeTime) then
			bar:SetAlpha(self.cfg.alpha);
		end
		bar:Show();
	end
	-- Hide all other frames
	for i = #timers + 1, #self.bars do
		self.bars[i]:Hide();
	end
end

-- OnConfigChanged
function plugin:OnConfigChanged(cfg)
	if (cfg.enabled) then
		self:RegisterEvent("PLAYER_ENTERING_WORLD");
		self:RegisterEvent("CHAT_MSG_MONSTER_YELL");
		self:RegisterEvent("CHAT_MSG_BG_SYSTEM_HORDE");
		self:RegisterEvent("CHAT_MSG_BG_SYSTEM_ALLIANCE");
		self:RegisterEvent("CHAT_MSG_BG_SYSTEM_NEUTRAL");
		self:RegisterEvent("UPDATE_BATTLEFIELD_STATUS");
		self:RegisterEvent("PLAYER_REGEN_ENABLED");
		self:RegisterEvent("ZONE_CHANGED_NEW_AREA");
        else
                self:UnregisterAllEvents();
                timers:Recycle();
        end
        self:UpdateTimers();

       -- Refresh existing bars with new appearance
       for _, bar in ipairs(self.bars) do
               bar:SetAlpha(cfg.alpha)
               local color = bar.table and self.cfg["col"..bar.table.faction] or self.cfg.colNeutral
               if color then
                       bar.status:SetStatusBarColor(unpack(color))
               end
       end
end

--------------------------------------------------------------------------------------------------------
--                                          Initialise Plugin                                         --
--------------------------------------------------------------------------------------------------------

plugin:SetScript("OnEvent",OnEvent);
plugin:ConfigureBar();
