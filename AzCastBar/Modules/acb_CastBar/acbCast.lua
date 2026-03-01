local min = min;
local unpack = unpack;
local UnitIsPossessed = UnitIsPossessed;
local UnitCastingInfo = UnitCastingInfo;
local UnitChannelInfo = UnitChannelInfo;

-- Midnight+ castbar API
local UnitCastingDuration = UnitCastingDuration;
local UnitChannelDuration = UnitChannelDuration;
local UnitEmpoweredChannelDuration = UnitEmpoweredChannelDuration;
local UnitEmpoweredStagePercentages = UnitEmpoweredStagePercentages;
local UnitEmpoweredStageDurations = UnitEmpoweredStageDurations;

local C_Timer = C_Timer;

local CreateColor = CreateColor;
local EvaluateColorFromBoolean = C_CurveUtil and C_CurveUtil.EvaluateColorFromBoolean;
local issecretvalue = issecretvalue;

------------------------------------------------------
-- Hide default Blizzard cast bars when AzCastBar bars are enabled
-- (mirrors DirasSuite's OnShow hook approach)
------------------------------------------------------
local blizzardHideHooked;
local function SetupBlizzardCastbarHiding()
	if blizzardHideHooked then
		return;
	end
	blizzardHideHooked = true;
	if not C_Timer then
		return;
	end

	C_Timer.After(0, function()
		local function hook(frame, bar)
			if not frame or frame._acbHideHooked then
				return;
			end
			frame._acbHideHooked = true;
			frame:HookScript("OnShow", function()
				if bar and bar.cfg and bar.cfg.enabled then
					frame:Hide();
				end
			end)
			if bar and bar.cfg and bar.cfg.enabled then
				frame:Hide();
			end
		end

		hook(PlayerCastingBarFrame, _G.AzCastBarPluginPlayer);
		hook(TargetFrameSpellBar, _G.AzCastBarPluginTarget);
		hook(FocusFrameSpellBar, _G.AzCastBarPluginFocus);
	end)
end

-- Extra Options
local extraOptions = {
	{
		[0] = "Additional",
		{ type = "Check", var = "showRank", default = false, label = "Show Spell Rank", tip = "If the spell being cast has a rank, it will be shown in brackets after the spell name." },
		{ type = "Color", var = "colNormal", default = { 0.4, 0.6, 0.8, 1 }, label = "Normal Cast Color", y = 16 },
		{ type = "Color", var = "colNonInterruptable", default = { 0.78, 0.82, 0.86, 1 }, label = "Uninterruptable Cast Bar Color", restrict = "Target" },	-- Only relevant for target bars
		{ type = "Check", var = "showTime", default = true, label = "Show Time Label", tip = "Display the time label on the bar", y = 20 },
		{ type = "Check", var = "showIcon", default = true, label = "Show Spell Icon", tip = "Display the spell icon on the bar" },

		-- Empowered casting (segmented stages)
		{ type = "Check", var = "showEmpower", default = true, label = "Show Empowered Stages", tip = "Shows segmented stage bars for empowered casts (like Blizzard)", y = 20 },
		{ type = "Color", var = "empowerColor1", default = { 0.15, 0.65, 1.00, 0.45 }, label = "Empower Stage 1 Color", y = 10 },
		{ type = "Color", var = "empowerColor2", default = { 0.15, 1.00, 0.55, 0.45 }, label = "Empower Stage 2 Color" },
		{ type = "Color", var = "empowerColor3", default = { 1.00, 0.85, 0.20, 0.45 }, label = "Empower Stage 3 Color" },
		{ type = "Color", var = "empowerColor4", default = { 1.00, 0.35, 0.35, 0.45 }, label = "Empower Stage 4 Color" },
	},
};

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
};

local events = {};

------------------------------------------------------
-- Empower Stage Helpers (DirasSuite-style)
------------------------------------------------------
local function EnsureEmpowerStages(self)
	if self.empowerStages then
		return;
	end

	self.empowerStages = {};
	local texPath = self.status and self.status:GetStatusBarTexture() and self.status:GetStatusBarTexture():GetTexture();

	for i = 1, 4 do
		local stage = {};
		stage.Texture = self:CreateTexture(nil, "ARTWORK");
		stage.Texture:SetColorTexture(1, 1, 1, 0);
		stage.Texture:Hide();

		stage.StageDurationBar = CreateFrame("StatusBar", nil, self);
		stage.StageDurationBar:SetAllPoints(stage.Texture);
		if texPath then
			stage.StageDurationBar:SetStatusBarTexture(texPath);
		end
		stage.StageDurationBar:SetMinMaxValues(0, 1);
		stage.StageDurationBar:SetValue(0);
		stage.StageDurationBar:Hide();

		-- Keep above the base bar texture
		stage.StageDurationBar:SetFrameLevel(self.status:GetFrameLevel() + 2);

		self.empowerStages[i] = stage;
	end
end

local function HideEmpowerStages(self)
	if not self.empowerStages then
		return;
	end
	for i = 1, #self.empowerStages do
		local s = self.empowerStages[i];
		if s then
			s.Texture:Hide();
			s.StageDurationBar:Hide();
		end
	end
end

local function ApplyEmpowerStageColors(self)
	if not self.empowerStages or not self.cfg then return end
	local cfg = self.cfg;
	local colors = { cfg.empowerColor1, cfg.empowerColor2, cfg.empowerColor3, cfg.empowerColor4 };
	for i = 1, 4 do
		local c = colors[i];
		if c then
			self.empowerStages[i].Texture:SetColorTexture(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1);
		end
	end
end

local function PlaceEmpowerStages(self, numStages, unit)
	if not self.cfg or not self.cfg.showEmpower then
		return;
	end
	EnsureEmpowerStages(self);
	ApplyEmpowerStageColors(self);

	local barWidth = self:GetWidth();
	local empowerStagePercentages = UnitEmpoweredStagePercentages(unit, true);
	local empowerStageDurations = UnitEmpoweredStageDurations(unit);

	if not empowerStagePercentages or not empowerStageDurations then
		return;
	end

	local accumulatedPercent = empowerStagePercentages[1] or 0;

	for stage = 2, (numStages or 0) + 1 do
		local index = stage - 1;
		local stageFrame = self.empowerStages[index];
		if not stageFrame then break end

		local startX = barWidth * accumulatedPercent;
		accumulatedPercent = accumulatedPercent + (empowerStagePercentages[stage] or 0);
		local isLast = (stage == (numStages or 0) + 1);

		stageFrame.Texture:ClearAllPoints();
		stageFrame.Texture:SetPoint("TOPLEFT", self.status, "TOPLEFT", startX, 0);
		stageFrame.Texture:SetPoint("BOTTOMLEFT", self.status, "BOTTOMLEFT", startX, 0);

		if isLast then
			stageFrame.Texture:SetPoint("RIGHT", self.status, "RIGHT", 0, 0);
		else
			stageFrame.Texture:SetWidth(barWidth * (empowerStagePercentages[stage] or 0));
		end

		stageFrame.Texture:Show();

		stageFrame.StageDurationBar:ClearAllPoints();
		stageFrame.StageDurationBar:SetPoint("TOPLEFT", stageFrame.Texture, "TOPLEFT", 0, 0);
		stageFrame.StageDurationBar:SetPoint("BOTTOMRIGHT", stageFrame.Texture, "BOTTOMRIGHT", 0, 0);

		if empowerStageDurations[stage] then
			-- DirasSuite passes duration directly; we do the same.
			stageFrame.StageDurationBar:SetTimerDuration(empowerStageDurations[stage]);
		end

		stageFrame.StageDurationBar:Show();
	end
end

------------------------------------------------------
-- Color + text update (DirasSuite-style secret handling)
------------------------------------------------------
local function ApplyInterruptibilityColor(self, notInterruptible)
	-- Only target bars should reflect interruptibility.
	if self.unit ~= "target" then
		notInterruptible = false;
	end

	local normal = self.cfg and self.cfg.colNormal or { 1, 1, 1, 1 };
	local ni = self.cfg and self.cfg.colNonInterruptable or normal;

	local normalC = CreateColor(normal[1] or 1, normal[2] or 1, normal[3] or 1, normal[4] or 1);
	local niC = CreateColor(ni[1] or 1, ni[2] or 1, ni[3] or 1, ni[4] or 1);

	local primaryColor = normalC;
	if EvaluateColorFromBoolean then
		primaryColor = EvaluateColorFromBoolean(notInterruptible, niC, normalC);
	end

	-- Match DirasSuite: avoid gradient calls in secured code when notInterruptible is a secret value.
	local tex = self.status and self.status:GetStatusBarTexture();
	if tex then
		tex:SetVertexColor(primaryColor.r, primaryColor.g, primaryColor.b, primaryColor.a);
	end
end

local function SetCastBarInformation(self, notInterruptible, isEmpowered, unit)
	if not self.duration then
		return;
	end

	local duration = self.duration;

	local elapsed = duration:GetElapsedDuration();
	local remaining = duration:GetRemainingDuration();

	if not isEmpowered then
		ApplyInterruptibilityColor(self, notInterruptible);
	end

	if self.cfg and self.cfg.showTime and self.time then
		if self.IsChannelSpell and not isEmpowered then
			self.time:SetText(string.format("%.1f", remaining));
		else
			self.time:SetText(string.format("%.1f", elapsed));
		end
	end
end

------------------------------------------------------
-- Core cast lifecycle (DirasSuite-style)
------------------------------------------------------
local function OnSpellCastStart(self, unit, isChannel)
	if not self or not self.status then
		return;
	end

	self.IsChannelSpell = isChannel;

	local name, text, texture, startTimeMS, endTimeMS, isTradeSkill, notInterruptible, castGUID, spellID, isEmpowered, numEmpowerStages, castBarID, duration;

	if self.IsChannelSpell then
		name, text, texture, startTimeMS, endTimeMS, isTradeSkill, notInterruptible, spellID, isEmpowered, numEmpowerStages, castBarID = UnitChannelInfo(unit);
		duration = UnitChannelDuration(unit);
	else
		name, text, texture, startTimeMS, endTimeMS, isTradeSkill, castGUID, notInterruptible, spellID, castBarID = UnitCastingInfo(unit);
		duration = UnitCastingDuration(unit);
	end

	if not castBarID then
		return;
	end

	self.castBarID = castBarID;

	if not name or not startTimeMS or not endTimeMS then
		self:Hide();
		self:SetScript("OnUpdate", nil);
		return;
	else
		self:Show();
	end

	self.startTimeMS = startTimeMS;
	self.endTimeMS = endTimeMS;
	self.duration = duration;

	if isEmpowered then
		self.duration = UnitEmpoweredChannelDuration(unit, true);
	end

	if self.name then
		self.name:SetText(name);
	end

	if self.icon then
		if self.cfg and self.cfg.showIcon then
			self.icon:SetTexture(texture);
			self.icon:Show();
		else
			self.icon:Hide();
		end
	end

	-- Base bar timer (Blizzard timer duration API)
	if self.duration then
		self.status:SetTimerDuration(self.duration, Enum.StatusBarInterpolation.Immediate,
			(isChannel and (not isEmpowered)) and Enum.StatusBarTimerDirection.RemainingTime or Enum.StatusBarTimerDirection.ElapsedTime
		);
	end

	-- Empower: show segmented stage bars and hide the base fill (like Blizzard/DirasSuite)
	if self.IsChannelSpell and isEmpowered and self.cfg and self.cfg.showEmpower then
		PlaceEmpowerStages(self, numEmpowerStages, unit);
		-- Hide base fill so segments are the visual representation
		self.status:SetStatusBarColor(0, 0, 0, 0);
	else
		HideEmpowerStages(self);
		-- Restore base fill color
		if self.cfg and self.cfg.colNormal then
			local c = self.cfg.colNormal;
			self.status:SetStatusBarColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1);
		end
	end

	self:SetScript("OnUpdate", function(frame)
		SetCastBarInformation(frame, notInterruptible, isEmpowered, unit);
	end);
end

local function OnSpellCastUpdate(self, unit, isChannel)
	if not self or not self.status then
		return;
	end

	self.IsChannelSpell = isChannel;

	local name, text, texture, startTimeMS, endTimeMS, isTradeSkill, notInterruptible, castGUID, spellID, isEmpowered, numEmpowerStages, castBarID, duration;

	if self.IsChannelSpell then
		name, text, texture, startTimeMS, endTimeMS, isTradeSkill, notInterruptible, spellID, isEmpowered, numEmpowerStages, castBarID = UnitChannelInfo(unit);
		duration = UnitChannelDuration(unit);
	else
		name, text, texture, startTimeMS, endTimeMS, isTradeSkill, castGUID, notInterruptible, spellID, castBarID = UnitCastingInfo(unit);
		duration = UnitCastingDuration(unit);
	end

	if self.castBarID ~= castBarID then
		return;
	end

	if not name then
		return;
	end

	self.startTimeMS = startTimeMS;
	self.endTimeMS = endTimeMS;
	self.duration = duration;

	if isEmpowered then
		self.duration = UnitEmpoweredChannelDuration(unit, true);
	end

	if self.duration then
		self.status:SetTimerDuration(self.duration, Enum.StatusBarInterpolation.Immediate,
			(isChannel and (not isEmpowered)) and Enum.StatusBarTimerDirection.RemainingTime or Enum.StatusBarTimerDirection.ElapsedTime
		);
	end

	if self.IsChannelSpell and isEmpowered and self.cfg and self.cfg.showEmpower then
		PlaceEmpowerStages(self, numEmpowerStages, unit);
	end
end

local function OnSpellCastStop(self, unit, castBarID, isChannel)
	if not self then
		return;
	end

	if not castBarID or self.castBarID ~= castBarID then
		return;
	end

	self.castBarID = nil;
	self.duration = nil;
	self.startTimeMS = 0;
	self.endTimeMS = 0;
	self.IsChannelSpell = false;

	if self.name then self.name:SetText(""); end
	if self.time then self.time:SetText(""); end
	if self.icon then self.icon:SetTexture(nil); end

	HideEmpowerStages(self);

	-- Restore base bar color
	if self.status and self.cfg and self.cfg.colNormal then
		local c = self.cfg.colNormal;
		self.status:SetStatusBarColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1);
	end

	self:Hide();
	self:SetScript("OnUpdate", nil);
end

------------------------------------------------------
-- Event Dispatch
------------------------------------------------------
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
	if events[event] then
		events[event](self,event,unit,...);
	end
end

-- Entering World + Target/Focus Change
function events:PLAYER_ENTERING_WORLD(event)
	-- Initialize by querying current cast/channel state like DirasSuite would on fresh enable.
	if (UnitCastingInfo(self.unit)) then
		OnSpellCastStart(self, self.unit, false);
	elseif (UnitChannelInfo(self.unit)) then
		OnSpellCastStart(self, self.unit, true);
	else
		self:Hide();
		self:SetScript("OnUpdate", nil);
	end
end
events.PLAYER_FOCUS_CHANGED = events.PLAYER_ENTERING_WORLD;
events.PLAYER_TARGET_CHANGED = events.PLAYER_ENTERING_WORLD;

function events:UNIT_SPELLCAST_START(event,unit)
	OnSpellCastStart(self, unit, false);
end

function events:UNIT_SPELLCAST_STOP(event,unit,...)
	local castGUID, spellID, castBarID = ...;
	OnSpellCastStop(self, unit, castBarID, false);
end

function events:UNIT_SPELLCAST_FAILED(event,unit,...)
	local castGUID, spellID, castBarID = ...;
	OnSpellCastStop(self, unit, castBarID, false);
end

function events:UNIT_SPELLCAST_INTERRUPTED(event,unit,...)
	local castGUID, spellID, _, castBarID = ...;
	OnSpellCastStop(self, unit, castBarID, false);
end

function events:UNIT_SPELLCAST_DELAYED(event,unit)
	OnSpellCastUpdate(self, unit, false);
end

function events:UNIT_SPELLCAST_CHANNEL_START(event,unit)
	OnSpellCastStart(self, unit, true);
end

function events:UNIT_SPELLCAST_CHANNEL_UPDATE(event,unit)
	OnSpellCastUpdate(self, unit, true);
end

function events:UNIT_SPELLCAST_CHANNEL_STOP(event,unit,...)
	local castGUID, spellID, _, castBarID = ...;
	OnSpellCastStop(self, unit, castBarID, true);
end

function events:UNIT_SPELLCAST_INTERRUPTIBLE(event,unit)
	-- DirasSuite refreshes state on these events by re-reading cast info.
	OnSpellCastStart(self, unit, false);
end

function events:UNIT_SPELLCAST_NOT_INTERRUPTIBLE(event,unit)
	-- DirasSuite refreshes state on these events by re-reading cast info.
	OnSpellCastStart(self, unit, false);
end

function events:UNIT_SPELLCAST_EMPOWER_START(event,unit)
	OnSpellCastStart(self, unit, true);
end

function events:UNIT_SPELLCAST_EMPOWER_UPDATE(event,unit)
	OnSpellCastUpdate(self, unit, true);
end

function events:UNIT_SPELLCAST_EMPOWER_STOP(event,unit,...)
	local castGUID, spellID, _, _, castBarID = ...;
	OnSpellCastStop(self, unit, castBarID, true);
end

------------------------------------------------------
-- Config Changed (minimal, event registration only)
------------------------------------------------------
local function OnConfigChanged(self,cfg)
	self:UnregisterAllEvents();

	if (cfg.enabled) then
		-- Hide the default Blizzard cast bars when our custom bars are enabled.
		SetupBlizzardCastbarHiding();
		for _, event in ipairs(registered_events) do
			self:RegisterEvent(event);
		end
		if (self.unit == "target") then
			self:RegisterEvent("PLAYER_TARGET_CHANGED");
		elseif (self.unit == "focus") then
			self:RegisterEvent("PLAYER_FOCUS_CHANGED");
		end
		events.PLAYER_ENTERING_WORLD(self,"PLAYER_ENTERING_WORLD");

		-- Best-effort immediate hide (the OnShow hook will keep them hidden on subsequent shows).
		if (self.unit == "player") and PlayerCastingBarFrame then
			PlayerCastingBarFrame:Hide();
		elseif (self.unit == "target") and TargetFrameSpellBar then
			TargetFrameSpellBar:Hide();
		elseif (self.unit == "focus") and FocusFrameSpellBar then
			FocusFrameSpellBar:Hide();
		end
	else
		self:Hide();
		self:SetScript("OnUpdate", nil);
	end
end

local function StartFadeOut(self)
	-- DirasSuite hides immediately; keep as a compatibility stub.
	self:Hide();
	self:SetScript("OnUpdate", nil);
end

------------------------------------------------------
-- Initialise Each Bar
------------------------------------------------------
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
	bar:SetScript("OnUpdate",nil);

	bar.OnConfigChanged = OnConfigChanged;
	bar.StartFadeOut = StartFadeOut;

	-- Ensure empower stages follow bar texture changes later
	-- (created lazily on first empower cast)
end
