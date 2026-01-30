local min = min;
local unpack = unpack;
local wipe = wipe;
local GetTime = GetTime;
local GetNetStats = GetNetStats;
local C_CastingInfo = C_CastingInfo;
local C_Spell = C_Spell;

local function SafeTimeMs(value)
	if (value == nil) then
		return nil;
	end
	local valueType = type(value);
	if (valueType == "number") then
		local ok = pcall(function()
			return value + 0;
		end);
		if (ok) then
			return value;
		end
	end
	if (valueType == "string") then
		return tonumber(value);
	end
	local ok, asString = pcall(tostring, value);
	if (ok) then
		return tonumber(asString);
	end
	return nil;
end

local function GetSpellNameAndIcon(spellID)
	if not spellID then
		return nil, nil;
	end
	if (C_Spell and C_Spell.GetSpellInfo) then
		local info = C_Spell.GetSpellInfo(spellID);
		if (type(info) == "table") then
			return info.name, info.iconID;
		end
		if (info) then
			return info, nil;
		end
	end
	if (GetSpellInfo) then
		local name, _, icon = GetSpellInfo(spellID);
		if (type(name) == "table") then
			return name.name, name.iconID;
		end
		return name, icon;
	end
	return nil, nil;
end

local function NormalizeSpellData(spell, texture)
	if (type(spell) == "table") then
		return spell.name, spell.iconID or texture;
	end
	return spell, texture;
end

-- Several casting APIs moved under C_CastingInfo in 11.x; provide wrappers
local BaseUnitCastingInfo = UnitCastingInfo;
local BaseUnitChannelInfo = UnitChannelInfo;

local function UnitCastingInfo(unit)
	if C_CastingInfo and C_CastingInfo.GetCastingInfo then
		local info = C_CastingInfo.GetCastingInfo(unit);
		if info then
			if type(info) == "table" then
				return info.spellName or info.name, nil, info.iconID or info.icon, info.startTimeMS or info.startTimeMs, info.endTimeMS or info.endTimeMs, info.isTradeSkill, info.castID, info.notInterruptible, info.spellID;
			end
			return info;
		end
	end
	if BaseUnitCastingInfo then
		return BaseUnitCastingInfo(unit);
	end
end

local function UnitChannelInfo(unit)
	if C_CastingInfo and C_CastingInfo.GetChannelInfo then
		local info = C_CastingInfo.GetChannelInfo(unit);
		if info then
			if type(info) == "table" then
				return info.spellName or info.name, nil, info.iconID or info.icon, info.startTimeMS or info.startTimeMs, info.endTimeMS or info.endTimeMs, info.isTradeSkill, info.notInterruptible, info.spellID, info.numStages;
			end
			return info;
		end
	end
	if BaseUnitChannelInfo then
		return BaseUnitChannelInfo(unit);
	end
end

-- WoW 11.0 removed the global GetSpellInfo function, so fall back to the
-- C_Spell API when the global does not exist.
local GetSpellInfo = GetSpellInfo or (C_Spell and C_Spell.GetSpellInfo);

-- Extra Options
local extraOptions = {
	{
		[0] = "Additional",
		{ type = "Check", var = "showRank", default = false, label = "Show Spell Rank", tip = "If the spell being cast has a rank, it will be shown in brackets after the spell name." },
		{ type = "Color", var = "colNormal", default = { 0.4, 0.6, 0.8 }, label = "Normal Cast Color", y = 16 },
		{ type = "Color", var = "colFailed", default = { 1.0, 0.5, 0.5 }, label = "Failed Cast Bar Color" },
		{ type = "Color", var = "colInterrupt", default = { 1.0, 0.75, 0.5 }, label = "Interrupted Cast Bar Color" },
		{ type = "Color", var = "colNonInterruptable", default = { 0.78, 0.82, 0.86 }, label = "Uninterruptable Cast Bar Color" },	-- Az: yes, this var is misspelled :S
		{ type = "Check", var = "safeZone", default = false, label = "Show Safe Zone Area", tip = "The 'Safe Zone' is the time equal to your latency, with this option enabled, it will show this duration on the cast bar. A spell canceled after it has reached the safe zone, will still go off.", restrict = "Player", y = 16 },
		{ type = "Color", var = "colSafezone", default = { 0.3, 0.8, 0.3, 0.6 }, label = "Safe Zone Color", restrict = "Player", y = 6 },
		{ type = "Check", var = "mergeTrade", default = false, label = "Merge Tradeskill Cast Times", tip = "Will show the combined time it takes to craft all items", restrict = "Player", y = 20 },
		{ type = "Check", var = "showSpellTarget", default = false, label = "Show Spell Target", tip = "Shows who the spell is being cast on", restrict = "Player" },
	},
};

-- Casting Bar Events
local events = {};
local registered_events = {
	"PLAYER_ENTERING_WORLD",
	"UNIT_SPELLCAST_START",
	"UNIT_SPELLCAST_STOP",
	"UNIT_SPELLCAST_FAILED",
	"UNIT_SPELLCAST_INTERRUPTED",
	"UNIT_SPELLCAST_DELAYED",
	"UNIT_SPELLCAST_CHANNEL_START",
	"UNIT_SPELLCAST_CHANNEL_STOP",
	"UNIT_SPELLCAST_CHANNEL_UPDATE",
	"UNIT_SPELLCAST_INTERRUPTIBLE",
	"UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
	"UNIT_SPELLCAST_EMPOWER_START",
	"UNIT_SPELLCAST_EMPOWER_UPDATE",
	"UNIT_SPELLCAST_EMPOWER_STOP",
	--"UPDATE_TRADESKILL_RECAST",	-- Az: improve tradeskill tracking using this and C_TradeSkillUI.GetRecipeRepeatCount()?
};

-- Channeled Ticks -- Az: wip
--local channeled_ticks = {
--	[GetSpellInfo(15407)] = 3,	-- Mind Flay
--};

-- Spell Names for Hearthstone & Astral Recall
local astral = select(1, GetSpellNameAndIcon(556));
local hearth = select(1, GetSpellNameAndIcon(8690));

-- Trade Hook
local tradeCountTotal, allowTradeMerge;
hooksecurefunc(C_TradeSkillUI,"CraftRecipe",function(index,num) if (allowTradeMerge) then tradeCountTotal = num; end end);

--------------------------------------------------------------------------------------------------------
--                                              OnUpdate                                              --
--------------------------------------------------------------------------------------------------------

local function OnUpdate(self,elapsed)
	-- Progress -- Back in WoW 2.x only the player unit gave the UNIT_SPELLCAST_STOP event, so we had to force fadeout here when casts completes, now we just rely on the event
	if (not self.fadeTime) then
		self.timeProgress = min(GetTime() - self.startTime,self.castTime);
		self.timeLeft = (self.castTime - self.timeProgress);
		self.status:SetValue(self.isCast and self.timeProgress or self.timeLeft);
		self.time:SetFormattedText("%s%s%s",self.delayText,self:FormatTime(self.timeLeft),self.cfg.showTotalTime and self.totalTimeText or "");
		-- Az: not completely happy with the trademerge implementation
		if (self.isTrade) and (self.timeLeft == 0) then
			self:StartFadeOut();
		end
	-- FadeOut
	elseif ((self.fadeElapsed + elapsed) <= self.fadeTime) then
		self.fadeElapsed = (self.fadeElapsed + elapsed);
		self:SetAlpha(self.cfg.alpha - self.fadeElapsed / self.fadeTime * self.cfg.alpha);
        else
                self:Hide();
        end
end

--------------------------------------------------------------------------------------------------------
--                                           Event Handling                                           --
--------------------------------------------------------------------------------------------------------

-- OnEvent -- Entering World + Target/Focus Change has no "unit" arg
local function OnEvent(self,event,unit,...)
	if (unit) then
		-- Invalid Unit -- Do not process SpellCast events for units that is not our unit
		if (self.unit ~= unit) then
			return;
		-- Use the Player Bar for Possessed Pets/Vehicles
		elseif (self.unit == "pet") and (UnitIsPossessed("pet")) and (AzCastBarPluginPlayer.cfg.enabled) then
			self = AzCastBarPluginPlayer;
		end
	end
	-- Handle This Event
	events[event](self,event,unit,...);
end

-- Entering World + Target/Focus Change
function events:PLAYER_ENTERING_WORLD(event)
	if (UnitCastingInfo(self.unit)) then
		events.UNIT_SPELLCAST_START(self,"UNIT_SPELLCAST_START",self.unit);
	elseif (UnitChannelInfo(self.unit)) then
		events.UNIT_SPELLCAST_CHANNEL_START(self,"UNIT_SPELLCAST_CHANNEL_START",self.unit);
	else
		self:Hide();
	end
end
events.PLAYER_FOCUS_CHANGED = events.PLAYER_ENTERING_WORLD;
events.PLAYER_TARGET_CHANGED = events.PLAYER_ENTERING_WORLD;

-- Interruptible
function events:UNIT_SPELLCAST_INTERRUPTIBLE(event,unit)
	self.status:SetStatusBarColor(unpack(self.cfg.colNormal));
end

-- Not Interruptible
function events:UNIT_SPELLCAST_NOT_INTERRUPTIBLE(event,unit)
	self.status:SetStatusBarColor(unpack(self.cfg.colNonInterruptable));
end

-- Obtain Target of Spell [Player Only Event] -- Also Happens during a cast if you spam, but we will allow it, as it is ok to cast the next spell before current ends, that is the "safe zone"
function events:UNIT_SPELLCAST_SENT(event,unit,target,lineID,spellID,...)
	self.spellTarget = target;
end

-- Cast/Channel Start -- lineID is zero for channeled
-- [18.07.19] 8.0/BfA: UnitCastingInfo/UnitChannelInfo "dropped second parameter (nameSubtext)"
function events:UNIT_SPELLCAST_START(event,unit,lineID,spellID)
       -- Initialise
	local isCast = (event == "UNIT_SPELLCAST_START");
	local isChannel = (event == "UNIT_SPELLCAST_CHANNEL_START");
	local spell, _, texture, startTime, endTime, isTrade, nonInterruptible, infoSpellID;
	local subText = spellID and C_Spell and C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(spellID) or ""
	if (isCast) then
		spell, _, texture, startTime, endTime, isTrade, lineID, nonInterruptible, infoSpellID = UnitCastingInfo(unit);	-- 8 returns, lineID is reused from args
	else
		spell, _, texture, startTime, endTime, isTrade, nonInterruptible, infoSpellID = UnitChannelInfo(unit);			-- 7 returns
	end
	if (not spellID) and (infoSpellID) then
		spellID = infoSpellID;
	end
	if (not startTime) then
		return;
	end
	spell, texture = NormalizeSpellData(spell, texture);
	if (not spell or not texture) and (spellID) then
		local resolvedSpell, resolvedTexture = GetSpellNameAndIcon(spellID);
		spell = spell or resolvedSpell;
		texture = texture or resolvedTexture;
	end
	startTime = SafeTimeMs(startTime);
	endTime = SafeTimeMs(endTime);
	if (not startTime) or (not endTime) then
		return;
	end
	startTime = (startTime / 1000);
	endTime = (endTime / 1000);
	local castTime = (endTime - startTime);

	-- Player Specific
	if (self.unit == "player") then
		if (self.cfg.mergeTrade) and (isTrade) and (tradeCountTotal) and (tradeCountTotal > 1) then
			if (not self.tradeCount) then
				self.tradeCount = 1;
				self.tradeStart = startTime;
				castTime = ((castTime + 0.5) * tradeCountTotal);
			else
				castTime = (GetTime() - self.tradeStart) / self.tradeCount * tradeCountTotal;
				self.tradeCount = (self.tradeCount + 1);
			end
			startTime = self.tradeStart;
			endTime = (startTime + castTime);
			spell = spell.." ("..self.tradeCount.."/"..tradeCountTotal..")";
		else
			self.tradeCount = nil;
		end
		if (spell and (spell == hearth or spell == astral)) then --(spell == hearth or spell == astral) then	--if (spellID == 556 or spellID == 8690) then
			subText = GetBindLocation();
		end
		if (self.cfg.safeZone) then
			local latency = select(3, GetNetStats()) or 0;
			self.safezone:ClearAllPoints();
			self.safezone:SetPoint(isCast and "TOPRIGHT" or "TOPLEFT");
			self.safezone:SetPoint(isCast and "BOTTOMRIGHT" or "BOTTOMLEFT");
			self.safezone:SetWidth(min(1,latency / 1000 / castTime) * self.status:GetWidth());
			self.safezone:Show();
		end
	end

	-- Init Objects
	self.status:SetStatusBarColor(unpack(nonInterruptible and self.cfg.colNonInterruptable or self.cfg.colNormal));
	self.icon:SetTexture(texture);

-- [18.07.20] old code that set the formatted text directly in the name FontString (will remove once new code is confirmed working)
--[[
	if (self.unit == "player" and self.cfg.showSpellTarget and self.spellTarget ~= "") then
		self.name:SetFormattedText(self.cfg.showRank and subText ~= "" and "%s (%s) -> %s" or "%s -> %3$s",spell,subText,self.spellTarget or "<nil>");
	else
		self.name:SetFormattedText(self.cfg.showRank and subText ~= "" and "%s (%s)" or "%s",spell,subText);
	end
--]]

----[[
	-- should we show rank/subText
	if (self.cfg.showRank and subText and subText ~= "") then
		spell = spell.." ("..subText..")";
	end
	-- should we show spell target name
	if (self.unit == "player" and self.cfg.showSpellTarget and self.spellTarget and self.spellTarget ~= "") then
		spell = spell.." -> "..self.spellTarget;
	end
	self.name:SetText(spell or "");
--]]

	-- Copy vars into self
	self.isCast = isCast;
	self.isChannel = isChannel;
	self.castTime = castTime;
	self.startTime, self.endTime, self.isTrade, self.lineID, self.nonInterruptible = startTime, endTime, isTrade, lineID, nonInterruptible;	-- lineID is zero for channeled

	-- Reset Variables and Show
	self.castDelay = 0;
	self.delayText = "";
	self:ResetAndShow(castTime,1);
end
events.UNIT_SPELLCAST_CHANNEL_START = events.UNIT_SPELLCAST_START;

-- Cast Failed
function events:UNIT_SPELLCAST_FAILED(event,unit,lineID,spellID)
	if (self.isCast) and (self.lineID == lineID) and (event == "UNIT_SPELLCAST_FAILED" or self.tradeCount) then
		self.status:SetValue(self.castTime);
		self.status:SetStatusBarColor(unpack(self.cfg.colFailed));
		self.time:SetText(FAILED);
		self:StartFadeOut();
	end
end
events.UNIT_SPELLCAST_FAILED_QUIET = events.UNIT_SPELLCAST_FAILED;	-- quiet = tradeskill cast fail

-- Interrupted -- This event is often spammed, four times per interrupt, no idea why. Happens both before and after UNIT_SPELLCAST_STOP
function events:UNIT_SPELLCAST_INTERRUPTED(event,unit,lineID,spellID)
	if (self.isCast) and (self.lineID == lineID) then
		self.status:SetValue(self.castTime);
		self.status:SetStatusBarColor(unpack(self.cfg.colInterrupt));
		self.time:SetText(INTERRUPTED);
		self:StartFadeOut();
	end
end

-- Cast Stop
function events:UNIT_SPELLCAST_STOP(event,unit,lineID,spellID)
	if (self.isCast) and (self.lineID == lineID) and not (self.fadeTime) and not (self.tradeCount) then
		self.status:SetValue(self.castTime);
		self:StartFadeOut();
	end
end

-- Channel Stop
function events:UNIT_SPELLCAST_CHANNEL_STOP(event,unit,lineID,spellID)
	if (self.isChannel) and not (self.fadeTime) then
		self.status:SetValue(0);
		self:StartFadeOut();
	end
end

-- Cast/Channel Delayed -- This will fire for channeled spells on interrupts, not UNIT_SPELLCAST_INTERRUPTED.
function events:UNIT_SPELLCAST_DELAYED(event,unit,lineID,spellID)
	local castInfoFunc = (event == "UNIT_SPELLCAST_DELAYED" and UnitCastingInfo or UnitChannelInfo);
	local _, _, _, startTimeNew, endTimeNew = castInfoFunc(self.unit);	-- [18.07.19] 8.0/BfA: UnitCastingInfo/UnitChannelInfo "dropped second parameter (nameSubtext)"
	startTimeNew = SafeTimeMs(startTimeNew);
	endTimeNew = SafeTimeMs(endTimeNew);
	if (startTimeNew and endTimeNew) then
		local endTimeOld = self.endTime;
		self.startTime, self.endTime = (startTimeNew / 1000), (endTimeNew / 1000);
		self.castDelay = (self.castDelay + self.endTime - endTimeOld);
		self.delayText = format("|cffff8080%s%.1f|r  ",self.castDelay > 0 and "+" or "",self.castDelay);
	end
end
events.UNIT_SPELLCAST_CHANNEL_UPDATE = events.UNIT_SPELLCAST_DELAYED;

-- Empower Start
function events:UNIT_SPELLCAST_EMPOWER_START(event, unit, lineID, spellID)
        if (self.unit ~= unit) then return end

        -- Empowered casts behave like channels, so fall back to UnitChannelInfo
        local spell, _, texture, startTime, endTime = UnitCastingInfo(unit)
        if not startTime then
                spell, _, texture, startTime, endTime = UnitChannelInfo(unit)
        end
        startTime = SafeTimeMs(startTime)
        endTime = SafeTimeMs(endTime)
        if not startTime or not endTime then
                spell, _, texture = GetSpellInfo(spellID)
                return
        end

        startTime = startTime / 1000
        endTime   = endTime / 1000
        local castTime = endTime - startTime

        self.isCast = true
        self.isChannel = false
        self.isEmpower = true
        self.castTime = castTime
        self.startTime, self.endTime = startTime, endTime
        self.lineID = lineID
        self.nonInterruptible = false

        self.status:SetStatusBarColor(unpack(self.cfg.colNormal))
        self.icon:SetTexture(texture)
        self.name:SetText(spell or "")

       self.castDelay = 0
       self.delayText = ""

       self:ResetAndShow(castTime, 1)
end

-- Empower Stage Update
function events:UNIT_SPELLCAST_EMPOWER_UPDATE(event, unit, lineID, spellID)
        if (self.unit ~= unit) or not self.isEmpower then return end

        -- Refresh timing using channel info so the bar progresses correctly
        local _, _, _, startTime, endTime = UnitChannelInfo(unit)
        startTime = SafeTimeMs(startTime)
        endTime = SafeTimeMs(endTime)
        if startTime and endTime then
                startTime = startTime / 1000
                endTime = endTime / 1000
                self.startTime = startTime
                self.endTime = endTime
                self.castTime = endTime - startTime
        end

end
-- Empower Stop
function events:UNIT_SPELLCAST_EMPOWER_STOP(event, unit, lineID, spellID)
        if (self.unit ~= unit) or not self.isEmpower then return end

        -- Final update to ensure timing is correct when release happens
        local _, _, _, startTime, endTime = UnitChannelInfo(unit)
        startTime = SafeTimeMs(startTime)
        endTime = SafeTimeMs(endTime)
        if startTime and endTime then
                startTime = startTime / 1000
                endTime = endTime / 1000
                self.startTime = startTime
                self.endTime = endTime
                self.castTime = endTime - startTime
        end

       self.isEmpower = nil
       self.status:SetValue(self.castTime)
       self:StartFadeOut()
end


--------------------------------------------------------------------------------------------------------
--                                          Initialise Plugin                                         --
--------------------------------------------------------------------------------------------------------

-- Config Changed
local function OnConfigChanged(self,cfg)

-- For All CastBars
	self:UnregisterAllEvents();
	if (cfg.enabled) then
		for _, event in ipairs(registered_events) do
			self:RegisterEvent(event);
		end
		if (self.unit == "target") then
			self:RegisterEvent("PLAYER_TARGET_CHANGED");
		elseif (self.unit == "focus") then
			self:RegisterEvent("PLAYER_FOCUS_CHANGED");
		elseif (self.unit == "player") then
			self:RegisterEvent("UNIT_SPELLCAST_SENT");
		--	self:RegisterEvent("UNIT_SPELLCAST_EMPOWER_START");
		--	self:RegisterEvent("UNIT_SPELLCAST_EMPOWER_UPDATE");
		--	self:RegisterEvent("UNIT_SPELLCAST_EMPOWER_STOP");
			if (cfg.mergeTrade) then
				self:RegisterEvent("UNIT_SPELLCAST_FAILED_QUIET");	-- This event fires when a tradeskill cast fails!
			end
		end
		events.PLAYER_ENTERING_WORLD(self,"PLAYER_ENTERING_WORLD");
	else
		self:StartFadeOut();
	end
	-- For Player + Pet
        if (self.unit == "player" or self.unit == "pet") then
		if (self.unit == "player") then
			tradeCountTotal = nil;
			allowTradeMerge = (cfg.enabled and cfg.mergeTrade);
		end
		local frame = (self.unit == "player" and PlayerCastingBarFrame or PetCastingBarFrame);
		if (cfg.enabled) then
			if (self.safezone) then
				self.safezone:SetColorTexture(unpack(cfg.colSafezone));
			end
			frame:UnregisterAllEvents();
			frame.showCastbar = nil;
			frame:Hide();
                else
                        frame.showCastbar = (self.unit == "player" and true or UnitIsPossessed("pet"));
			for _, event in ipairs(registered_events) do
				frame:RegisterEvent(event);
			end
			if (self.unit == "pet") then
				frame:RegisterEvent("UNIT_PET");
			end
			if (frame:GetScript("OnEvent")) then
				frame:GetScript("OnEvent")(frame,"PLAYER_ENTERING_WORLD");
			end
		end
	end
end

-- Start Frame FadeOut
local function StartFadeOut(self)
        if (not self.fadeTime) then
                self.isCast = nil;
                self.isChannel = nil;
                self.isEmpower = nil;
                self.fadeTime = self.cfg.fadeTime;
                if (self.unit == "player") then
                        tradeCountTotal = nil;
                        self.tradeCount = nil;
                        self.safezone:Hide();
                end
        end

       -- Apply updated visual settings immediately
       self:SetAlpha(self.cfg.alpha)
       self.status:SetStatusBarColor(unpack(self.cfg.colNormal))
       if (self.safezone) then
               self.safezone:SetColorTexture(unpack(self.cfg.colSafezone))
       end
end

-- Initialise Each Bar
local bars = { "Player", "Target", "Focus", "Pet" };
local lastBar;
for _, token in ipairs(bars) do
	local bar = AzCastBar:CreateMainBar("Frame",token,extraOptions);
	bar.unit = token:lower();
	-- Anchor
	bar:ClearAllPoints();
	if (lastBar) then
		bar:SetPoint("TOP",lastBar,"BOTTOM",0,-8);
	else
		bar:SetPoint("CENTER",0,-100);
	end
	lastBar = bar;
	-- Events
	for _, event in ipairs(registered_events) do
		bar:RegisterEvent(event);
	end
	bar:SetScript("OnEvent",OnEvent);
	bar:SetScript("OnUpdate",OnUpdate);
	bar.OnConfigChanged = OnConfigChanged;
	bar.StartFadeOut = StartFadeOut;
	-- Create Safezone
	if (token == "Player") then
		bar.safezone = bar.status:CreateTexture(nil,"OVERLAY");
		bar.safezone:SetColorTexture(0.3,0.8,0.3,0.6);
		bar.safezone:SetPoint("TOPRIGHT");
		bar.safezone:SetPoint("BOTTOMRIGHT");
		bar.safezone:Hide();
	end
end
