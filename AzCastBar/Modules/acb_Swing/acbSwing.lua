local _, classID = UnitClass("player");
if (classID == "MAGE" or classID == "WARLOCK" or classID == "PRIEST") then
	return;
end

local GetTime = GetTime;
local UnitAttackSpeed = UnitAttackSpeed;

-- Extra Options
local extraOptions = {
	{
		[0] = "Colors",
		{ type = "Color", var = "colNormal", default = { 0.4, 0.6, 0.8 }, label = "Normal Swing Color" },
		{ type = "Color", var = "colParry", default = { 1, 0.75, 0.5 }, label = "Parry Color" },
	},
};

-- Constants
local COMBAT_EVENT_PREFIX_SUFFIX = "(.-)_(.+)";

-- Variables
local plugin = AzCastBar:CreateMainBar("Frame","Swing",extraOptions);
local playerGUID = UnitGUID("player");

-- Localized Names
-- Spell Ids
local slamId = 1464;
-- WoW 11.0 removed the global GetSpellInfo function, so fall back to the
-- C_Spell API when the global does not exist.
local GetSpellInfo = GetSpellInfo or (C_Spell and C_Spell.GetSpellInfo);
--local autoShotId = 75;
--local autoShot = GetSpellInfo(autoShotId);
--local wandShotId = 5019;
--local wandShot = GetSpellInfo(wandShotId);
--local meleeSwing = GetLocale() == "enUS" and "Melee Swing" or GetSpellInfo(6603);
--local meleeSwing = C_Spell.GetSpellInfo(6603);
--[[local spellSwingReset = {
	[GetSpellInfo(78)] = true,		-- Heroic Strike
	[GetSpellInfo(845)] = true,		-- Cleave
	[GetSpellInfo(2973)] = true,	-- Raptor Strike
	[GetSpellInfo(6807)] = true,	-- Maul
	[GetSpellInfo(56815)] = true,	-- Rune Strike
};]]

--local autoShotSpells = {
--	[75] = C_Spell.GetSpellInfo(75),			-- autoshot
--	[5019] = C_Spell.GetSpellInfo(5019),		-- wand
--}

local slam = GetSpellInfo(slamId) or { name = "Slam" }
local meleeSwing = GetSpellInfo(6603) or { name = "Melee" }
local autoShotSpells = {
        [75] = GetSpellInfo(75) or { name = "Auto Shot" },
        [5019] = GetSpellInfo(5019) or { name = "Shoot" },
}

--------------------------------------------------------------------------------------------------------
--                                           Event Handling                                           --
--------------------------------------------------------------------------------------------------------

-- handles return values from CombatLogGetCurrentEventInfo() with varargs
function plugin:OnCombatEvent(timestamp,event,hideCaster,sourceGUID,sourceName,sourceFlags,sourceRaidFlags,destGUID,destName,destFlags,destRaidFlags,...)
	-- Something our Player does
	if (sourceGUID == playerGUID) then
		local prefix, suffix = event:match(COMBAT_EVENT_PREFIX_SUFFIX);
		if (prefix == "SWING") then
			self:StartSwing(UnitAttackSpeed("player"), meleeSwing.name or "Swing")
			--self:StartSwing(UnitAttackSpeed("player"),meleeSwing);
		end
	-- Something Happens to our Player
	elseif (destGUID == playerGUID) then
		local prefix, suffix = event:match(COMBAT_EVENT_PREFIX_SUFFIX);
		local missType = ...;
		-- Az: the info on wowwiki seemed obsolete, so this might not be 100% correct, I had to ignore the 20% rule as that didn't seem to be correct from tests
		if (prefix == "SWING") and (suffix == "MISSED") and (self.duration) and (missType == "PARRY") then
			local newDuration = (self.duration * 0.6);
--			local newTimeLeft = (self.startTime + newDuration - GetTime());
			self.duration = newDuration;
			self.status:SetMinMaxValues(0,self.duration);
			self.status:SetStatusBarColor(unpack(self.cfg.colParry));
			self.totalTimeText = self:FormatTotalTime(self.duration,1);
		end
	end
end

-- Combat Log Parser
function plugin:COMBAT_LOG_EVENT_UNFILTERED(event)
	self:OnCombatEvent(CombatLogGetCurrentEventInfo());
end

-- Spell Cast Succeeded
function plugin:UNIT_SPELLCAST_SUCCEEDED(event,unit,castGUID,spellId)
if (unit == "player") then
	local autoShotInfo = autoShotSpells[spellId];
if (autoShotInfo) then
	self:StartSwing(UnitAttackSpeed("player"), autoShotInfo.name or "Auto");
elseif (spellId == slamId) and (self.slamStart) then
	self.startTime = (self.startTime + GetTime() - self.slamStart);
self.slamStart = nil;
-- Az: cata has no spells that are on next melee afaik?
--              elseif (spellSwingReset[spell]) then
--                      self:StartSwing(UnitAttackSpeed("player"),meleeSwing);
end
end
end
 
 -- Warrior Only
 
 --------------------------------------------------------------------------------------------------------
 --                                          Initialise Plugin                                         --
 --------------------------------------------------------------------------------------------------------
 

-- Warrior Only
if (classID == "WARRIOR") then
	-- Spell Cast Start
	function plugin:UNIT_SPELLCAST_START(event,unit,castGUID,spellId)
		if (unit == "player") and (spellId == slamId) then
			self.slamStart = GetTime();
		end
	end
	-- Spell Cast Interrupted
	function plugin:UNIT_SPELLCAST_INTERRUPTED(event,unit,castGUID,spellId)
		if (unit == "player") and (spellId == slamId) and (self.slamStart) then
			self.slamStart = nil;
		end
	end
end

--------------------------------------------------------------------------------------------------------
--                                          Initialise Plugin                                         --
--------------------------------------------------------------------------------------------------------

-- OnUpdate
function plugin:OnUpdate(elapsed)
	-- No update on slam suspend
	if (self.slamStart) then
		return;
	-- Progression
	elseif (not self.fadeTime) then
		self.timeLeft = max(0,self.startTime + self.duration - GetTime());
		self.status:SetValue(self.duration - self.timeLeft);
		self:SetTimeText(self.timeLeft);
		if (self.timeLeft == 0) then
			self.fadeTime = self.cfg.fadeTime;
		end
	-- FadeOut
elseif ((self.fadeElapsed + elapsed) <= self.fadeTime) then--	elseif (self.fadeElapsed < self.fadeTime) then
		self.fadeElapsed = (self.fadeElapsed + elapsed);
		self:SetAlpha(self.cfg.alpha - self.fadeElapsed / self.fadeTime * self.cfg.alpha);
	else
		self:Hide();
	end
end

-- initializes the bar to show a swing
function plugin:StartSwing(time,text)
	self.duration = time;
	self.name:SetText(text);
	self.startTime = GetTime();

	self.status:SetStatusBarColor(unpack(self.cfg.colNormal));	-- reset here in case it was set due to parry

	self:ResetAndShow(time,1);
end

-- OnConfigChanged
function plugin:OnConfigChanged(cfg)
	if (cfg.enabled) then
		self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED");
		self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED");
		if (classID == "WARRIOR") then
			self:RegisterEvent("UNIT_SPELLCAST_START");
			self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED");
		end
        else
                self:UnregisterAllEvents();
        end

       -- Update bar appearance
       self:SetAlpha(cfg.alpha)
       self.status:SetStatusBarColor(unpack(self.cfg.colNormal))
end

plugin.icon:SetTexture("Interface\\Icons\\Spell_Shadow_SoulLeech_2");
plugin:SetScript("OnUpdate",plugin.OnUpdate);
