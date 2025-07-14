if (select(2,UnitClass("player")) ~= "SHAMAN") then
	return;
end

local GetTime = GetTime;
local UnitAura = UnitAura;

local LWE = LibWeaponEnchant;

-- Extra Options
local extraOptions = {
	{
		[0] = "Filters",
		{ type = "Check", var = "showEnchants", default = true, label = "Show Weapon Imbues" },
		{ type = "Check", var = "showShields", default = true, label = "Show Elemental Shields" },
		{ type = "Check", var = "showBloodlust", default = true, label = "Show Blodlust / Heroism" },
		{ type = "Check", var = "showEleMastery", default = true, label = "Show Elemental Mastery" },
		{ type = "Check", var = "showMaelstrom", default = true, label = "Show Maelstrom" },
		{ type = "Check", var = "showWolves", default = true, label = "Show Spirit Wolves" },
		{ type = "DropDown", var = "maelstromSound", default = "Sound\\Creature\\Murmur\\MurmurWoundA.wav", label = "Maelstrom Sound", media = "sound", y = 12 },
	},
	{
		[0] = "Colors",
		{ type = "Color", var = "colNormal", default = { 0.4, 0.6, 0.8 }, label = "Normal Color" },
		{ type = "Color", var = "colGood", default = { 0.45, 0.82, 0.55 }, label = "Good Color" },
		{ type = "Color", var = "colWarn", default = { 0.8, 0.8, 0.2 }, label = "Warning Color" },
		{ type = "Color", var = "colFail", default = { 1.0, 0.5, 0.5 }, label = "Failed Color" },
	},
};

-- Addon
local plugin = AzCastBar:CreateMainBar("Button","Shaman",extraOptions,true);
local uToken = "player";
local timers = LibTableRecycler:New();

-- Spell Names
local maelstrom = GetSpellInfo(53817);
local spiritWolves, _, spiritWolvesIcon = GetSpellInfo(51533);
local bloodlust = GetSpellInfo(UnitFactionGroup("player") == FACTION_ALLIANCE and 32182 or 2825);
local elemastery = GetSpellInfo(16166);
local elementalShields = {
--	[GetSpellInfo(324)] = true,		-- Lightning
--	[GetSpellInfo(52127)] = true,	-- Water
--	[GetSpellInfo(974)] = true,		-- Earth

	[GetSpellInfo(8788)] = true,		-- Lightning
	[GetSpellInfo(34827)] = true,	-- Water
	[GetSpellInfo(379)] = true,		-- Earth

--	[GetSpellInfo("Lightning Shield")] = true,		-- Lightning
--	[GetSpellInfo("Water Shield")] = true,	-- Water
--	[GetSpellInfo("Earth Shield")] = true,		-- Earth
};

-- Variables
local lastMaelstromStack;
local wolvesStartTime = 0;
local ICON_QUESTIONMARK = "Interface\\Icons\\INV_Misc_QuestionMark";
local enchantShort = { Flametongue = "FT", Windfury = "WF", Earthliving = "EL", Frostbrand = "FB", Rockbiter = "RB", [UNKNOWN] = "??" };

--------------------------------------------------------------------------------------------------------
--                                            Frame Scripts                                           --
--------------------------------------------------------------------------------------------------------

-- OnUpdate
local function OnUpdate(self,elapsed)
	local timer = self.timer;
	self.timeLeft = timer.endTime - GetTime();
	if (self.timeLeft < 0) then
		self.timeLeft = 0;
	end
	self.status:SetValue(self.timeLeft);
	self:SetTimeText(self.timeLeft);
	-- Blink Maelstrom Timer on 5 Stacks
	if (timer.blink) then
		local change = (sin(GetTime() * 600) + 1) / 2 * self.cfg.alpha / 2;
		self:SetAlpha(self.cfg.alpha - change);
	end
end

-- OnClick
local function OnClick(self,button)
	if (self.timer.enchant) then
		-- Az: As of 4.0.1, this function is now secure
--		CancelItemTempEnchantment(1);
--		CancelItemTempEnchantment(2);
	end
end

--------------------------------------------------------------------------------------------------------
--                                                Code                                                --
--------------------------------------------------------------------------------------------------------

-- Callback Function for the LibWeaponEnchant
function plugin:UpdateEnchantTimers(mhSlot,mhEnchant,mhDuration,mhEndTime,ohSlot,ohEnchant,ohDuration,ohEndTime)
	self:ScanPlayerAuras();
end

-- Configure Bar
function plugin:ConfigureBar(bar)
	bar = (bar or self);
	bar:EnableMouse(1);
	bar:RegisterForClicks("RightButtonUp");
	bar:SetScript("OnClick",OnClick);
	return bar;
end

-- Update Timers
function plugin:UpdateTimers()
	-- Loop timers and update bars
	for index, timer in ipairs(timers) do
		local bar = self.bars[index] or self:ConfigureBar(AzCastBar:CreateBar("Button",self));
		bar.timer = timer;
		bar.totalTimeText = bar:FormatTotalTime(timer.duration);

		bar.status:SetMinMaxValues(0,timer.duration or 1);
		bar.status:SetStatusBarColor(unpack(timer.color or self.cfg.colNormal));
		if (timer.duration) and (timer.duration > 0) then
			bar:SetScript("OnUpdate",OnUpdate);
		else
			bar.time:SetText("");
			bar.status:SetValue(1);
			bar:SetScript("OnUpdate",nil);
		end
		bar.name:SetFormattedText(timer.count and timer.count > 1 and "%s (%d)" or "%s",timer.label,timer.count);
		bar.icon:SetTexture(timer.icon);

		bar:SetAlpha(self.cfg.alpha);
		bar:Show();
	end
	-- Hide all other frames
	for i = #timers + 1, #self.bars do
		self.bars[i]:Hide();
	end
end

-- returns the UnitAura returns for the first aura with the given name -- Also check AuraUtil.FindAuraByName()
function plugin:UnitAuraByName(unit,auraToFind)
	local index = 1;
	while (true) do
		local auraName = UnitAura(unit,index);
		if not (auraName) then
 			return;
		elseif (auraName == auraToFind) then
 			return UnitAura(unit,index);
		end
		index = (index + 1);
	end
end

-- Scan Player Buffs
function plugin:ScanPlayerAuras()
	timers:Recycle();
	-- Weapon Enchants
	if (self.cfg.showEnchants) then
		local mhSlot, mhEnchant, mhDuration, mhEndTime, ohSlot, ohEnchant, ohDuration, ohEndTime = LWE:GetEnchantData();
		local icon = GetInventoryItemTexture(uToken,mhSlot) or ICON_QUESTIONMARK;
		local tbl = timers:Fetch();
		if (not mhEnchant) and (not ohEnchant) then
			tbl.label = "No Weapon Imbue"; tbl.icon = icon; tbl.color = self.cfg.colFail;
		elseif (mhEnchant) and (not OffhandHasWeapon()) then
			local mhShort = enchantShort[mhEnchant:gsub(" %d+","")] or mhEnchant;
			tbl.label = "Weapon Imbue ("..mhShort..")"; tbl.icon = icon; tbl.duration = mhDuration; tbl.endTime = mhEndTime; tbl.enchant = 1; tbl.color = self.cfg.colGood;
		else
			local mhShort = mhEnchant and enchantShort[mhEnchant:gsub(" %d+","")] or mhEnchant or "??";
			local ohShort = ohEnchant and enchantShort[ohEnchant:gsub(" %d+","")] or ohEnchant or "??";
			tbl.label = "Weapon Imbue ("..mhShort.."/"..ohShort..")"; tbl.icon = icon; tbl.duration = max(mhDuration,ohDuration); tbl.endTime = min(mhEndTime,ohEndTime); tbl.enchant = 1; tbl.color = (mhEnchant and ohEnchant and self.cfg.colGood or self.cfg.colWarn);
			if (not mhEnchant or not ohEnchant) then
				tbl.duration = nil;
			end
		end
	end
	-- Shields
	if (self.cfg.showShields) then
		local name, rank, icon, count, debuffType, duration, expirationTime;
		for shield in next, elementalShields do
			name, icon, count, debuffType, duration, expirationTime = self:UnitAuraByName(uToken,shield);
			if (name) then
				break;
			end
		end
		local tbl = timers:Fetch();
		if (name) then
			tbl.label = name; tbl.icon = icon; tbl.count = count; tbl.duration = duration; tbl.endTime = expirationTime; tbl.color = (count == 1 and self.cfg.colWarn or nil);
		else
			tbl.label = "No Elemental Shield"; tbl.icon = ICON_QUESTIONMARK; tbl.color = self.cfg.colFail;
		end
	end
	-- Heroism/Bloodlust
	if (self.cfg.showBloodlust) then
		local name, icon, count, debuffType, duration, expirationTime = self:UnitAuraByName(uToken,bloodlust);
		if (name) then
			local tbl = timers:Fetch();
			tbl.label = name; tbl.icon = icon; tbl.duration = duration; tbl.endTime = expirationTime;
		end
	end
	-- Elemental Mastery
	if (self.cfg.showEleMastery) then
		local name, icon, count, debuffType, duration, expirationTime = self:UnitAuraByName(uToken,elemastery);
		if (name) then
			local tbl = timers:Fetch();
			tbl.label = name; tbl.icon = icon; tbl.duration = duration; tbl.endTime = expirationTime;
		end
	end
	-- Maelstrom
	if (self.cfg.showMaelstrom) then
		local name, icon, count, debuffType, duration, expirationTime = self:UnitAuraByName(uToken,maelstrom);
		if (name) then
			if (lastMaelstromStack ~= 5) and (count == 5) then
				PlaySoundFile(self.cfg.maelstromSound);
			end
			lastMaelstromStack = count;
			local tbl = timers:Fetch();
			tbl.label = name; tbl.icon = icon; tbl.count = count; tbl.duration = duration; tbl.endTime = expirationTime; tbl.blink = (count == 5); tbl.color = (count == 5 and self.cfg.colGood or nil);
		end
	end
	-- Spirit Wolves
	if (self.cfg.showWolves) and (GetTime() - wolvesStartTime <= 45) then
		local tbl = timers:Fetch();
		tbl.label = "Spirit Wolves"; tbl.icon = spiritWolvesIcon; tbl.duration = 45; tbl.endTime = (wolvesStartTime + 45);
	end
	-- Update
	self:UpdateTimers();
end

--------------------------------------------------------------------------------------------------------
--                                           Event Handling                                           --
--------------------------------------------------------------------------------------------------------

-- Ability Cast
function plugin:UNIT_SPELLCAST_SUCCEEDED(event,unit,spell,rank,id)
	if (unit == uToken) and (spell == spiritWolves) then
		wolvesStartTime = GetTime();
		self:ScanPlayerAuras();
	end
end

-- Aura Change
function plugin:UNIT_AURA(event,unit)
	if (unit == uToken) then
		self:ScanPlayerAuras();
	end
end

-- Config Change
function plugin:OnConfigChanged(cfg)
	LWE:UnregisterCallback(self);
	self:UnregisterAllEvents();
	if (cfg.enabled) then
		if (cfg.showEnchants) then
			LWE:RegisterCallback(self,self.UpdateEnchantTimers);
		end
		self:RegisterEvent("UNIT_AURA");
		if (cfg.showWolves) then
			self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED");
		end
		self:ScanPlayerAuras();
	else
		timers:Recycle();
		self:UpdateTimers();
	end
end

--------------------------------------------------------------------------------------------------------
--                                          Initialise Plugin                                         --
--------------------------------------------------------------------------------------------------------

plugin:ConfigureBar();