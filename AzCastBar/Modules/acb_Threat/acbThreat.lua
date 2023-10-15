local GetTime = GetTime;

-- Extra Options
local extraOptions = {
	{
		[0] = "Options",
		{ type = "Slider", var = "threshold", default = 75, label = "Display Threshold", min = 0, max = 100, step = 1 },
	},
};

-- Plugin
local plugin = AzCastBar:CreateMainBar("Frame","Threat",extraOptions);

--------------------------------------------------------------------------------------------------------
--                                            Frame Scripts                                           --
--------------------------------------------------------------------------------------------------------

-- OnUpdate
local function OnUpdate(self,elapsed)
	if (self.fadeElapsed <= self.fadeTime) then
		self.fadeElapsed = (self.fadeElapsed + elapsed);
		self:SetAlpha(self.cfg.alpha - self.fadeElapsed / self.fadeTime * self.cfg.alpha);
	else
		self:Hide();
	end
end

-- Target Changed
function plugin:PLAYER_TARGET_CHANGED(event)
	-- Update Threat
	if (UnitExists("target")) and (GetNumGroupMembers() > 0) then
		local isTanking, status, threatpct, rawthreatpct, threatvalue = UnitDetailedThreatSituation("player","target");
		if (threatpct) and (threatvalue ~= 0) and (threatpct >= self.cfg.threshold) then
			local r, g, b = GetThreatStatusColor(status);
			self.status:SetStatusBarColor(r,g,b,1);
			self.name:SetFormattedText("%.1fk (%.1f%%)",threatvalue / 1000,rawthreatpct);
			self.time:SetFormattedText("%.1f%%",threatpct);
			self.status:SetValue(threatpct);
			self.fadeTime = nil;
			self:SetAlpha(self.cfg.alpha);
			self:SetScript("OnUpdate",nil);
			self:Show();
			return;
		end
	end
	-- Start FadeOut
	if (self:IsShown()) and (not self.fadeTime) then
		self.fadeElapsed = 0;
		self.fadeTime = self.cfg.fadeTime;
		self:SetScript("OnUpdate",OnUpdate);
	end
end

-- Threat Update
function plugin:UNIT_THREAT_LIST_UPDATE(event,unit)
	if (unit == "target" or unit == "player") then
		plugin:PLAYER_TARGET_CHANGED(event);
	end
end
plugin.UNIT_THREAT_SITUATION_UPDATE = plugin.UNIT_THREAT_LIST_UPDATE;

-- Config Changed
function plugin:OnConfigChanged(cfg)
	self:UnregisterAllEvents();
	if (cfg.enabled) then
		self:RegisterEvent("PLAYER_TARGET_CHANGED");
		self:RegisterEvent("UNIT_THREAT_LIST_UPDATE");
		self:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE");
	else
		self:Hide();
	end
end

--------------------------------------------------------------------------------------------------------
--                                          Initialise Plugin                                         --
--------------------------------------------------------------------------------------------------------

plugin.icon:SetTexture("Interface\\Icons\\Ability_Vehicle_SonicShockwave");
plugin.status:SetMinMaxValues(0,100);