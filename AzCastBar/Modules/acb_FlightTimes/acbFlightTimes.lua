local GetTime = GetTime;
local UnitOnTaxi = UnitOnTaxi;

-- Extra Options
local extraOptions = {
	{
		{ var = "reverseGrowth", default = true },
		{ var = "showTotalTime", default = true },

		[0] = "Colors",
		{ type = "Color", var = "colNormal", default = { 0.4, 0.6, 0.8 }, label = "Flight Bar Color" },
	},
};

-- Vars
local plugin = AzCastBar:CreateMainBar("Frame","Flight",extraOptions);
local flightDB;
local transit = {};
plugin.transit = transit;

-- minimum flight time to check
local MIX_FLIGHT_TIME = 10;

--------------------------------------------------------------------------------------------------------
--                                           Frame Scripts                                            --
--------------------------------------------------------------------------------------------------------

-- OnUpdate
local function OnUpdate(self,elapsed)
	-- Progression
	if (not self.fadeTime) then
		self.timeProgress = (GetTime() - self.startTime);
		if (self.duration ~= 0) then
			self.status:SetValue(self.timeProgress);
			self:SetTimeText(self.duration - self.timeProgress);
		else
			self:SetTimeText(self.timeProgress);
		end
		-- Check if we landed
		if (self.timeProgress > MIX_FLIGHT_TIME) and (not UnitOnTaxi("player")) then
			flightDB[transit.outbound] = self.timeProgress;
			self.fadeTime = self.cfg.fadeTime;
		end
	-- FadeOut
	elseif ((self.fadeElapsed + elapsed) <= self.fadeTime) then--elseif (self.fadeElapsed < self.fadeTime) then
		self.fadeElapsed = (self.fadeElapsed + elapsed);
		self:SetAlpha(1 - self.fadeElapsed / self.fadeTime);
	else
		self:Hide();
	end
end

-- OnEvent -- Cancel Flight if Player Accepts Summon or Leaves the World
local function OnEvent(self,event)
	if (self:IsVisible()) then
		self.fadeTime = self.cfg.fadeTime;
		AzMsg("|2FlightTimes|r Flight Timer Aborted, Player Summoned or Zoned.");
	end
end

--------------------------------------------------------------------------------------------------------
--                                     HOOK: TaxiNodeOnButtonEnter                                    --
--------------------------------------------------------------------------------------------------------

local function GetTaxiOriginAndDestination(nodeId)
	local from, dest = nil, TaxiNodeName(nodeId);
	for i = 1, NumTaxiNodes() do
		if (TaxiNodeGetType(i) == "CURRENT") then
			from = TaxiNodeName(i);
			break;
		end
	end
	return from, dest;
end

hooksecurefunc("TaxiNodeOnButtonEnter",function(button)
	local nodeId = button:GetID();
	-- If enabled, Add flight time on all flightpoints except current
	if (flightDB) and (plugin.cfg.enabled) and (TaxiNodeGetType(nodeId) ~= "CURRENT") then
		-- Find From and Dest Nodes
		transit.from, transit.dest = GetTaxiOriginAndDestination(nodeId);
		-- Continue only if both points are found
		if (transit.from and transit.dest) then
			transit.time1 = flightDB[transit.from.." / "..transit.dest];
			transit.time2 = flightDB[transit.dest.." / "..transit.from];
			if (transit.time1 or transit.time2) then
				if (transit.time1) then
					GameTooltip:AddDoubleLine("Flight Time:",plugin:FormatTime(transit.time1),nil,nil,nil,1,1,1);
				end
				if (transit.time2) then
					GameTooltip:AddDoubleLine("Return Flight Time:",plugin:FormatTime(transit.time2),nil,nil,nil,1,1,1);
				end
			else
				GameTooltip:AddLine("Unknown Flight Time");
			end
			GameTooltip:Show();
		end
	end
end);

--------------------------------------------------------------------------------------------------------
--                                         HOOK: TakeTaxiNode                                         --
--------------------------------------------------------------------------------------------------------

local TakeTaxiNode_Real = TakeTaxiNode;
function TakeTaxiNode(nodeId)
	-- Check if enabled
	if (flightDB) and (plugin.cfg.enabled) and (TaxiNodeGetType(nodeId) ~= "CURRENT") then
		-- Find From and Dest Nodes
		transit.from, transit.dest = GetTaxiOriginAndDestination(nodeId);
		-- Find Table Entry, but do only so if both points are found
		if (transit.from and transit.dest) then
			transit.outbound = transit.from.." / "..transit.dest;
			transit.inbound = transit.dest.." / "..transit.from;
			plugin:StartFlight();
		end
	end
	-- Take Taxi
	TakeTaxiNode_Real(nodeId);
end

--------------------------------------------------------------------------------------------------------
--                                                Code                                                --
--------------------------------------------------------------------------------------------------------

-- Init Bar for Flight
function plugin:StartFlight()
	self.startTime = GetTime();
	self.duration = (flightDB[transit.outbound] or flightDB[transit.inbound] or 0);

	self.name:SetText(transit.dest);

	self:ResetAndShow(self.duration);
end

-- ConfigChanged
function plugin:OnConfigChanged(cfg)
	if (self.MergeSuppliedDatabase) then
		flightDB = FlightTimes_Data or {};
		FlightTimes_Data = self:MergeSuppliedDatabase(flightDB);
	end

	if (cfg.enabled) then
		self:RegisterEvent("CONFIRM_SUMMON");
		self:RegisterEvent("PLAYER_LEAVING_WORLD");
		self.status:SetStatusBarColor(unpack(cfg.colNormal));
	else
		self:UnregisterAllEvents();
	end
end

--------------------------------------------------------------------------------------------------------
--                                          Initialise Plugin                                         --
--------------------------------------------------------------------------------------------------------

plugin.icon:SetTexture("Interface\\Icons\\Ability_Druid_FlightForm");
plugin:SetScript("OnUpdate",OnUpdate);
plugin:SetScript("OnEvent",OnEvent);
