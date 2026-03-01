local GetTime = GetTime;

-- Extra Options
local extraOptions = {
	{
		[0] = "Options",
		{ type = "Check", var = "showInstants", default = true, label = "Show For Instant Casts" },
		{ type = "Color", var = "colNormal", default = { 0.4, 0.6, 0.8 }, label = "Global Cooldown Bar Color", y = 16 },
	},
};

-- Plugin
local plugin = AzCastBar:CreateMainBar("Frame","GlobalCooldown",extraOptions);

local GLOBAL_COOLDOWN_TIME = 1.5;

-- Midnight+: cooldown fields may be "secret values" (protected) that cannot be compared or used
-- in arithmetic. Avoid using cooldown.startTime/duration entirely and estimate GCD from haste.
local GetHaste = GetHaste;
local function EstimateGCDDuration()
	local hastePct = 0;
	if GetHaste then
		hastePct = GetHaste() or 0;
	end
	local gcd = GLOBAL_COOLDOWN_TIME / (1 + hastePct / 100);
	-- Retail minimum GCD
	if (gcd < 0.75) then
		gcd = 0.75;
	end
	-- Clamp to base
	if (gcd > GLOBAL_COOLDOWN_TIME) then
		gcd = GLOBAL_COOLDOWN_TIME;
	end
	return gcd;
end

--------------------------------------------------------------------------------------------------------
--                                            Frame Scripts                                           --
--------------------------------------------------------------------------------------------------------

-- OnUpdate
local function OnUpdate(self,elapsed)
	-- Update
	if (not self.fadeTime) then
		self.timeLeft = max(0,self.endTime - GetTime());
		self.status:SetValue(self.duration - self.timeLeft);
		self:SetTimeText(self.timeLeft);
		if (self.timeLeft == 0) then
			self.fadeTime = self.cfg.fadeTime;
		end
	-- Fadeout
	elseif ((self.fadeElapsed + elapsed) <= self.fadeTime) then--elseif (self.fadeElapsed <= self.fadeTime) then
		self.fadeElapsed = (self.fadeElapsed + elapsed);
		self:SetAlpha(self.cfg.alpha - self.fadeElapsed / self.fadeTime * self.cfg.alpha);
	else
		self:Hide();
	end
end

-- OnEvents
local function OnEvent(self,event,unit,castGUID,spellID)
	-- End if Wrong Unit
	if (unit ~= "player") then
		return;
	-- Start GCD -- START events are for casts, SUCCEEDED are for instants
	-- NOTE: If a spell is cast right after /stopcasting, GetSpellCooldown() returns zero (must be a bug)
	elseif (event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_SUCCEEDED") then
		-- We intentionally do not read/compare cooldown.duration because it may be a protected
		-- "secret value". Instead, estimate the GCD and show it.
		local duration = EstimateGCDDuration();
		self.duration = duration;
		self.endTime = (GetTime() + duration);
		self.icon:SetTexture(C_Spell.GetSpellTexture(spellID) or "Interface\\Icons\\INV_Misc_PocketWatch_02");
		self:ResetAndShow(self.duration,1);
	-- Abort GCD
	elseif (event == "UNIT_SPELLCAST_STOP") then
		self.fadeTime = self.cfg.fadeTime;
	end
end

-- Config Changed
function plugin:OnConfigChanged(cfg)
	self:UnregisterAllEvents();
	if (cfg.enabled) then
		self:RegisterEvent("UNIT_SPELLCAST_START");
		if (cfg.showInstants) then
			self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED");
		end
		self:RegisterEvent("UNIT_SPELLCAST_STOP");
		self.status:SetStatusBarColor(unpack(cfg.colNormal));
	end
end

--------------------------------------------------------------------------------------------------------
--                                          Initialise Plugin                                         --
--------------------------------------------------------------------------------------------------------

plugin.name:SetText(C_Spell.GetSpellName(61304));
plugin:SetScript("OnEvent",OnEvent);
plugin:SetScript("OnUpdate",OnUpdate);
