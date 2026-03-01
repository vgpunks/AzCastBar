local GetTime = GetTime;

-- Midnight (12.0+) reputation API compatibility
-- Some legacy globals like GetNumFactions/GetFactionInfo may be removed.
local GetNumFactions = _G.GetNumFactions
if (not GetNumFactions) and C_Reputation and C_Reputation.GetNumFactions then
	GetNumFactions = C_Reputation.GetNumFactions
end

local GetFactionInfo = _G.GetFactionInfo
if (not GetFactionInfo) and C_Reputation and C_Reputation.GetFactionDataByIndex then
	GetFactionInfo = function(factionIndex)
		local d = C_Reputation.GetFactionDataByIndex(factionIndex)
		if not d then
			return nil
		end
		-- Mirror the legacy GetFactionInfo return order for the fields used by this module.
		return d.name, d.description, d.reaction, d.currentReactionThreshold, d.nextReactionThreshold, d.currentStanding,
			d.atWarWith, d.canToggleAtWar, d.isHeader, d.isCollapsed, d.hasRep, d.isWatched, d.isChild,
			d.factionID, d.hasBonusRepGain, d.canSetInactive, d.isAccountWide
	end
end


-- Extra Options
local extraOptions = {
	{
		{ var = "width", default = 400 },
		{ var = "fadeOutTime", default = 1.2 },

		[0] = "Additional",
		{ type = "Slider", var = "sustainTime", default = 8.5, label = "Time Before Fading Out", min = 0, max = 60, step = 0.5 },
		{ type = "Color", var = "colXP", default = { 0.2, 0.5, 0.3 }, label = "XP Bar Color", y = 16 },	-- 0.96,0.55,0.73
	},
};

-- Vars
local plugin = AzCastBar:CreateMainBar("Frame","Experience",extraOptions);
local repStats;

local FACTION_COLORS = CUSTOM_FACTION_COLORS or FACTION_BAR_COLORS;

local ICON_REP = "Interface\\Icons\\Achievement_Reputation_01"
local ICON_XP = "Interface\\Icons\\Spell_Fire_FelFlameRing";

--------------------------------------------------------------------------------------------------------
--                                           Frame Scripts                                            --
--------------------------------------------------------------------------------------------------------

-- OnUpdate
local function OnUpdate(self,elapsed)
	-- Progression
	if (not self.fadeTime) then
		self.timeProgress = (GetTime() - self.startTime);
		if (self.timeProgress > self.cfg.sustainTime) then
			self.fadeTime = self.cfg.fadeTime;
		end
	-- FadeOut
elseif ((self.fadeElapsed + elapsed) <= self.fadeTime) then--	elseif (self.fadeElapsed < self.fadeTime) then
		self.fadeElapsed = (self.fadeElapsed + elapsed);
		self:SetAlpha(1 - self.fadeElapsed / self.fadeTime);
	else
		self.type = nil;
		self:Hide();
	end
end

-- xp update
function plugin:PLAYER_XP_UPDATE(event,unit)
	if (unit == "player") then
		self:DisplayXP();
	end
end

-- faction update
function plugin:UPDATE_FACTION(event)
	-- Normal faction gains
	if (repStats) then
		self:DisplayRep();
		return;
	end

	-- Initialise snapshot of faction standings
	local numFactions = GetNumFactions and GetNumFactions() or 0;
	if (numFactions > 0) then
		repStats = {};
		self.repStats = repStats;
		for factionIndex = 1, numFactions do
			local name, _, standingId, _, _, earnedValue = GetFactionInfo(factionIndex);
			if (name) then
				repStats[name] = { standingId = standingId, earnedValue = earnedValue };
			end
		end
	end
end

-- player login
function plugin:PLAYER_LOGIN(event)
	self.lastXP = UnitXP("player");
	self.lastXPMax = UnitXPMax("player");
	self.lastLevel = UnitLevel("player");
end

--------------------------------------------------------------------------------------------------------
--                                                Code                                                --
--------------------------------------------------------------------------------------------------------

function plugin:Emulate(type)
	if (not type) then
		type = math.random(2) == 1 and "xp" or "rep";
	end

	if (type == "xp") then
		self.lastXP = (self.lastXP - 100 - math.random(500));
		self:DisplayXP();
	else
		--local faction = "Warsong Outriders";
		local faction = "Gilneas";
		repStats[faction].earnedValue = (repStats[faction].earnedValue - 33 - math.random(500));
		self:DisplayRep();
	end
end
emu = function(type) AzCastBarPluginExperience:Emulate(type) end
-- Update Progress Bar
-- /script AzCastBarPluginExperience:UpdateProgress("Warsong Outriders",0,UnitXPMax("player"),UnitXP("player"),"bla bla",0.2,0.5,0.3)
-- /script AzCastBarPluginExperience:Emulate("rep")
function plugin:UpdateProgress(title, min, max, value, diff, text, r, g, b)
	-- Change Progress
	self.status:SetStatusBarColor(r or 0.2, g or 0.4, b or 0.9);
	self.status:SetMinMaxValues(min,max);
	self.status:SetValue(value);

	-- convert quick color codes
	if (text and text ~= "") then
		text = text:gsub("|1","|cffffff80"):gsub("|2","|cffffffff");
	end

	local valPrefix = diff > 0 and "+|cff80ff80" or "-|cffff8080";
	self.name:SetFormattedText("%s%d|r %s %s",valPrefix,abs(diff),title,text);

	self.time:SetFormattedText("%d / %d (%.1f%%)",value,max,value / max * 100);

	self.icon:SetTexture(self.type == "xp" and ICON_XP or ICON_REP);

	-- Show Progress
	self.startTime = GetTime();

	self.fadeTime = nil;
	self.fadeElapsed = 0;
	self:SetAlpha(self.cfg.alpha);
	self:Show();
end

-- displays xp gain
function plugin:DisplayXP()
	local level, xp, xpMax = UnitLevel("player"), UnitXP("player"), UnitXPMax("player");
	local xpGain = (xp - self.lastXP);
	local repeats = (xpGain and xpGain > 0) and ((xpMax - xp) / xpGain) or 0;
	local xpMsg = format("|1%d|r tnl, |1%d|r rested, |1%.2f|r repeats",xpMax - xp,GetXPExhaustion() or 0,repeats);

	self.type = "xp";
	self:UpdateProgress("Experience",0,xpMax,xp,xpGain,xpMsg,unpack(self.cfg.colXP));

	-- Backup Values
	self.lastXP = xp;
	self.lastXPMax = xpMax;
	self.lastLevel = level;
end

-- displays reputation gain
function plugin:DisplayRep()
	if (not repStats) then
		return;
	end
	local numFactions = GetNumFactions and GetNumFactions() or 0;
	for factionIndex = 1, numFactions do
		local name, _, standingId, minValue, maxValue, earnedValue, _, _, isHeader = GetFactionInfo(factionIndex);
		-- Skip headers or incomplete rows
		if (name and (not isHeader) and standingId and minValue and maxValue and earnedValue) then
			if (not repStats[name] or repStats[name].earnedValue ~= earnedValue) then
				local repMsg = "";
				-- Generate text to go with it
				local diff = repStats[name] and (earnedValue - repStats[name].earnedValue) or (earnedValue);
				if (diff >= 0) then
					if (standingId < 8) then
						repMsg = repMsg..format("|1%d|r until |1%s|r, repeat |1%.1f|r",maxValue - earnedValue,_G["FACTION_STANDING_LABEL"..standingId + 1], diff > 0 and (maxValue - earnedValue) / diff or 0);
					elseif (standingId == 8) then
						repMsg = repMsg..format("|1%d|r until |1Fully Exalted|r, repeat |1%.1f|r",maxValue - 1 - earnedValue, diff > 0 and (maxValue - earnedValue) / diff or 0);
					end
				else
					diff = abs(diff);
					if (standingId > 1) then
						repMsg = repMsg..format("|1%d|r until |1%s|r, repeat |1%.1f|r",earnedValue-minValue,_G["FACTION_STANDING_LABEL"..standingId - 1], diff > 0 and (earnedValue - minValue) / diff or 0);
					elseif (standingId == 1) then
						repMsg = repMsg..format("|1%d|r until |1Fully Hated|r, repeat |1%.1f|r",earnedValue - minValue, diff > 0 and (earnedValue - minValue) / diff or 0);
					end
				end

				-- Update Progress
				local repColor = FACTION_COLORS and FACTION_COLORS[standingId];
				local repVal, repMax = (earnedValue - minValue), (maxValue - minValue);
				self.type = "rep";
				if (repColor) then
					self:UpdateProgress(name,0,repMax,repVal,diff,repMsg,repColor.r,repColor.g,repColor.b);
				else
					self:UpdateProgress(name,0,repMax,repVal,diff,repMsg,1,1,1);
				end

				-- Update table
				if (not repStats[name]) then
					repStats[name] = {};
				end
				repStats[name].standingId = standingId;
				repStats[name].earnedValue = earnedValue;
			end
		end
	end
end


-- ConfigChanged
function plugin:OnConfigChanged(cfg)
	if (cfg.enabled) then
		self:RegisterEvent("UPDATE_FACTION");
		self:RegisterEvent("PLAYER_XP_UPDATE");
		if (self.type == "xp") then
			self.status:SetStatusBarColor(unpack(cfg.colXP));
		end
	else
		self:UnregisterAllEvents();
	end
end

--------------------------------------------------------------------------------------------------------
--                                          Initialise Plugin                                         --
--------------------------------------------------------------------------------------------------------

plugin:SetScript("OnUpdate",OnUpdate);
plugin:SetScript("OnEvent",function(self,event,...) self[event](self,event,...) end);

plugin:RegisterEvent("PLAYER_LOGIN");
