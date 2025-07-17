local tsort = table.sort;
local GetTime = GetTime;

local LWE = LibWeaponEnchant;

-- Extra Options
local extraOptions = {
	{
		[0] = "Filtering",
		-- override default options
		{ var = "enabled", default = false },
		{ var = "unit", default = "target", restrict = "TargetAuras" },
		{ var = "selfAurasOnly", default = true, restrict = "TargetAuras" },
		{ var = "showEnchants", default = false, restrict = "TargetAuras" },

		{ type = "Text", var = "unit", default = "player", label = "Watched Unit" },
		{ type = "Check", var = "showBuffs", default = true, label = "Show Buffs", y = 16 },
		{ type = "Check", var = "showDebuffs", default = true, label = "Show Debuffs" },
	--	{ type = "Check", var = "showEnchants", default = true, label = "Show Temporary Weapon Enchants (Player Only)" },
	--	{ type = "Check", var = "showTracking", default = false, label = "Show Active Tracking Type (Player Only)" },
		{ type = "Check", var = "selfAurasOnly", default = false, label = "Only Show Auras Coming from You", tip = "Enable this to only monitor auras applied to the unit by you", y = 12 },
		{ type = "Check", var = "showPetAuras", default = false, label = "Also Show Pet and Vehicle Auras", tip = "In addition to the above option, you can check this to also view auras added by your pet or vehicle" },
		{ type = "Check", var = "showStealable", default = false, label = "Show Stealable Buffs", y = 12 },
		{ type = "DropDown", var = "auraLabelFormat", default = "FULL", label = "Aura Label Format", list = { ["Name & Stack"] = "FULL", ["Name Only"] = "NAME", ["Stack Only"] = "STACK" }, y = 16 },
		{ type = "Check", var = "showAuraCaster", default = true, label = "Tooltips: Show Name of Aura Caster", tip = "Recommended to keep disabled if using TipTacItemRef", y = 16 },
	},
	{
		[0] = "Colors",
		{ type = "Check", var = "defaultDebuffColors", default = true, label = "Use the Default Debuff Colors", tip = "Use default debuff colors instead of a configurable one for all types" },
		{ type = "Slider", var = "bgColorAlpha", default = 0.2, label = "Background Color Alpha", min = 0, max = 1, step = 0.01, y = 12 },
		{ type = "Color", var = "colBuff", default = { 0.4, 0.6, 0.8 }, label = "Buff & Tracking Color", y = 20 },
		{ type = "Color", var = "colDebuff", default = { 1.0, 0.5, 0.5 }, label = "Debuff Color" },
		{ type = "Color", var = "colTimeOut", default = { 0.8, 0.8, 0.2 }, label = "Buff Timeout Color" },
		{ type = "Color", var = "colEnchant", default = { 0.6, 0.2, 0.9 }, label = "Temporary Weapon Enchant Color" },
		{ type = "Slider", var = "shortBuffDuration", default = 30, label = "Short Buff Timeout Duration", min = 0, max = 600, step = 1, y = 12 },
		{ type = "Check", var = "fullBarTimeless", default = false, label = "Show full bar for auras with no duration", y = 12 },
	},
	{
		[0] = "Blizzard",
		{ type = "Check", var = "hideAuras", default = false, label = "Hide Default Aura Frame", restrict = "PlayerAuras" },
		{ type = "Check", var = "hideEnchants", default = false, label = "Hide Default Temporary Enchant Frame", restrict = "PlayerAuras" },
		{ type = "Check", var = "hideTracking", default = false, label = "Hide Default Tracking Frame", restrict = "PlayerAuras" },
	},
};

-- Variables
local events = {};
local auraPriority = { ENCHANT = 1, TRACKING = 2, HELPFUL = 3, HARMFUL = 4 };
local updateInterval = 1 / 60;

-- Debuff Colors
local DebuffColors = {};
for type, color in next, DebuffTypeColor do
	DebuffColors[type] = { color.r, color.g, color.b };
end

-- Az: Tanking buff test!
--local vengeance = 76691;

--------------------------------------------------------------------------------------------------------
--                                            Frame Scripts                                           --
--------------------------------------------------------------------------------------------------------

-- OnUpdate
local function OnUpdate(self,elapsed)
	-- Update Limiter
	self.nextUpdate = (self.nextUpdate - elapsed);
	if (self.nextUpdate > 0) then
		return;
	end
	self.nextUpdate = updateInterval;
	-- Update Bar
	local timer = self.timer;
	self.timeLeft = (timer.endTime - GetTime());
	if (self.timeLeft < 0) then
		self.timeLeft = 0;
	end
	self.status:SetValue(self.timeLeft);
	self:SetTimeText(self.timeLeft);
	-- Change to TimeOut Color
	if (self.colorTimeoutFlag) and (self.timeLeft <= self.colorTimeoutFlag) then
		self.colorTimeoutFlag = nil;
		self.status:SetStatusBarColor(unpack(self.cfg.colTimeOut));
               if (self.cfg.bgColorAlpha > 0) then
                       self.bg:SetVertexColor(unpack(self.cfg.colTimeOut));
               end
               self.bg:SetAlpha(self.cfg.bgColorAlpha);
	end
end

-- OnClick
local function OnClick(self,button)
	local isPlayerUnit = (self.cfg.unit == "player")
	if (self.cfg.unit == "player") then
		local timer = self.timer;
		if (button == "LeftButton") then
			local editBox = ChatEdit_GetActiveWindow();
			if (IsModifiedClick("CHATLINK")) and (editBox) and (editBox:IsVisible()) then
				local auraData = C_UnitAuras.GetAuraDataByIndex(self.cfg.unit,timer.index,timer.type)
				local spellName = auraData and auraData.name
				local spellId = auraData and auraData.spellId;	-- [18.07.19] 8.0/BfA: "dropped second parameter"
				if (spellName or spellId) then
					securecall(editBox.SetText,editBox,format("/cancelaura %s",spellName));
--					editBox:Insert(format("/cancelaura %s",spellName));
--					editBox:Insert(GetSpellLink(spellId) or format("|cff71d5ff|Hspell:%d|h[%s]|h|r",id,GetSpellInfo(id)));
				end
			end
		else
			if (timer.type == "ENCHANT") then
				-- Az: still protected out of combat despite the change made to CancelUnitBuff()
--				CancelItemTempEnchantment(timer.slot - 15);
			elseif (timer.type == "TRACKING") then
				ToggleDropDownMenu(1,nil,MiniMapTrackingDropDown,"cursor",0,-5);
			elseif (not InCombatLockdown()) then
				CancelUnitBuff(self.cfg.unit,timer.index,timer.type);
			end
		end
	end
end

-- OnEnter
local function OnEnter(self)
	local isPlayerUnit = (self.cfg.unit == "player")
	local timer = self.timer;
	GameTooltip:SetOwner(self,AzCastBar:GetOptimalAnchor(self));
	if (timer.type == "ENCHANT") then
		GameTooltip:SetInventoryItem("player",timer.slot);
	elseif (timer.type == "TRACKING") then
		GameTooltip:AddLine(timer.label);
		GameTooltip:AddLine("Tracking",1,1,1);
		GameTooltip:Show();
	else
		GameTooltip:SetUnitAura(self.cfg.unit,timer.index,timer.type);
		if (self.cfg.showAuraCaster) then
			local auraData = C_UnitAuras.GetAuraDataByIndex(self.cfg.unit,timer.index,timer.type)
			local casterUnit = auraData and auraData.sourceUnit;	-- [18.07.19] 8.0/BfA: "dropped second parameter"
			if (casterUnit) then
				GameTooltip:AddLine("<Applied by "..tostring(UnitName(casterUnit))..">",0.4,0.72,1);
				GameTooltip:Show();
			end
		end
	end
end

-- OnLeave
local function HideGTT()
	GameTooltip:Hide();
end

--------------------------------------------------------------------------------------------------------
--                                          Helper Functions                                          --
--------------------------------------------------------------------------------------------------------

-- Sort Auras
local function SortAurasFunc(a,b)
	if (a.type ~= b.type) then
		return auraPriority[a.type] < auraPriority[b.type];
	elseif (a.type == "ENCHANT") then
		return a.slot < b.slot;
	elseif (a.endTime == b.endTime) then
	local aLabel = type(a.label) == "table" and a.label.name or a.label
	local bLabel = type(b.label) == "table" and b.label.name or b.label
	return (aLabel or "") < (bLabel or "");
	elseif (a.endTime == 0 or b.endTime == 0) then
		return a.endTime == 0;
	else
		return a.endTime > b.endTime;
	end
end

-- Callback Function for LibWeaponEnchant
local function UpdateEnchantTimers(self,mhSlot,mhEnchant,mhDuration,mhEndTime,ohSlot,ohEnchant,ohDuration,ohEndTime)
	self:RemoveTimerType("ENCHANT");
	if (mhEnchant) then
		local t = self:NewTimer("ENCHANT",mhEnchant,GetInventoryItemTexture("player",mhSlot),mhDuration,mhEndTime);
		t.slot = mhSlot;
	end
	if (ohEnchant) then
		local t = self:NewTimer("ENCHANT",ohEnchant,GetInventoryItemTexture("player",ohSlot),ohDuration,ohEndTime);
		t.slot = ohSlot;
	end
	self:UpdateTimers();
end

--------------------------------------------------------------------------------------------------------
--                                               Events                                               --
--------------------------------------------------------------------------------------------------------

-- OnEvent
local function OnEvent(self,event,...)
	events[event](self,event,...);
end

-- Tracking Update -- [Fixed in 3.1] When going from a "spell" type tracking to "None", tracking data still hasn't updated on the MINIMAP_UPDATE_TRACKING event. But it will trigger a UNIT_AURA event.
function events:MINIMAP_UPDATE_TRACKING(event,button,...)
	self:RemoveTimerType("TRACKING");
	for i = 1, GetNumTrackingTypes() do
		local name, texture, active = GetTrackingInfo(i);
		if (active) then
			self:NewTimer("TRACKING",name or NONE,texture,0,0);
		end
	end
	self:UpdateTimers();
end

-- Aura Update
function events:UNIT_AURA(event,unit)
	if (unit == self.cfg.unit) then
		if (self.cfg.showBuffs) then
			self:RemoveTimerType("HELPFUL");
			self:QueryAuras(unit,"HELPFUL",self.cfg.selfAurasOnly,self.cfg.showPetAuras,self.cfg.showStealable);
		end
		if (self.cfg.showDebuffs) then
			self:RemoveTimerType("HARMFUL");
			self:QueryAuras(unit,"HARMFUL",self.cfg.selfAurasOnly,self.cfg.showPetAuras,self.cfg.showStealable);
		end
		self:UpdateTimers();
	end
end

-- Pet Changed -- Only check when player's pet change
function events:UNIT_PET(event,unit)
	if (unit == "player") then
		self:ScanAllAuras();
	end
end

-- Focus + Target Changed
function events:PLAYER_TARGET_CHANGED(event,...)
	self:ScanAllAuras();
end
events.PLAYER_FOCUS_CHANGED = events.PLAYER_TARGET_CHANGED;

--------------------------------------------------------------------------------------------------------
--                                         Aura Plugin Mixin                                          --
--------------------------------------------------------------------------------------------------------

local AuraPluginMixin = {};

-- Removes all timer entries of the given type
function AuraPluginMixin:RemoveTimerType(type)
	local t = self.timers;
	for i = #t, 1, -1 do
		if (t[i].type == type) then
			t:RecycleIndex(i);
		end
	end
end

-- Fetches a recycled table a fills in the basic fields and returns it
function AuraPluginMixin:NewTimer(type,label,icon,duration,endTime)
	local t = self.timers:Fetch();
	t.type = type;
	t.label = label;
	t.icon = icon;
	t.duration = duration;
	t.endTime = endTime;
	return t;
end

-- Query Auras
function AuraPluginMixin:QueryAuras(unit,auraType,showSelfAuras,showPetAuras,showStealable)
        local index = 1
        local isFiltered = (showSelfAuras or showPetAuras or showStealable)
        while true do
                local name, icon, count, debuffType, duration, endTime, casterUnit, isStealable = C_UnitAuras.GetAuraDataByIndex(unit,index,auraType)
                if type(name) == "table" then
                        local auraData = name
                        if not auraData.name then
                                break
                        end
                        name = auraData.name
                        icon = auraData.icon
                        count = auraData.applications
                        debuffType = auraData.dispelName or auraData.debuffType
                        duration = auraData.duration
                        endTime = auraData.expirationTime
                        casterUnit = auraData.sourceUnit
                        isStealable = auraData.isStealable
                elseif not name then
                        break
                end
                if (not isFiltered) or (showStealable and isStealable) or (showSelfAuras and casterUnit == "player") or (showPetAuras and (casterUnit == "pet" or casterUnit == "vehicle")) then
                        local t = self:NewTimer(auraType, name, icon, duration or 0, endTime or 0)
                        t.index = index
                        t.count = count
                        t.debuffType = debuffType
                end
                index = index + 1
        end
end

-- Configure Bar
function AuraPluginMixin:ConfigureBar(bar)
	bar = (bar or self);
	bar:EnableMouse(true);
	bar:RegisterForClicks("LeftButtonUp","RightButtonUp");
	bar:SetScript("OnClick",OnClick);
	bar:SetScript("OnEnter",OnEnter);
	bar:SetScript("OnLeave",HideGTT);
	return bar;
end

-- Update Timers
function AuraPluginMixin:UpdateTimers()
	tsort(self.timers,SortAurasFunc);
	-- Update Timer Bars
	for index, timer in ipairs(self.timers) do
		local bar = self.bars[index] or self:ConfigureBar(AzCastBar:CreateBar("Button",self));
		bar.timer = timer;
		bar.totalTimeText = bar:FormatTotalTime(timer.duration);
		local dur = tonumber(timer.duration) or 0
		bar.colorTimeoutFlag = (timer.type == "HELPFUL") and (self.cfg.shortBuffDuration > 0) and (dur > self.cfg.shortBuffDuration) and self.cfg.shortBuffDuration or nil and (self.cfg.shortBuffDuration) or nil;
		bar.status:SetMinMaxValues(0,timer.duration == 0 and 1 or timer.duration);

		-- color
		local color;
		if (self.cfg.defaultDebuffColors) and (timer.type == "HARMFUL") then
			color = DebuffColors[timer.debuffType] or DebuffColors["none"];
		elseif (timer.type == "HELPFUL") then
			color = (timer.duration > 0 and timer.duration <= self.cfg.shortBuffDuration and self.cfg.colTimeOut) or (self.cfg.colBuff);
		else
			color = (timer.type == "ENCHANT" and self.cfg.colEnchant) or (timer.type == "HARMFUL" and self.cfg.colDebuff) or (self.cfg.colBuff);
		end
		bar.status:SetStatusBarColor(unpack(color));
               if (self.cfg.bgColorAlpha > 0) then
                       bar.bg:SetVertexColor(unpack(color));
               else
                       bar.bg:SetVertexColor(unpack(self.cfg.colBackGround));
               end
               bar.bg:SetAlpha(self.cfg.bgColorAlpha);

		-- OnUpdate script?
		if (timer.duration == 0) then
			bar.time:SetText("");
			bar.status:SetValue(self.cfg.fullBarTimeless and 1 or 0);
			bar:SetScript("OnUpdate",nil);
		else
			bar.nextUpdate = 0;
			bar:SetScript("OnUpdate",OnUpdate);
		end

		-- Stack format
		if (self.cfg.auraLabelFormat == "STACK") then
			local label = type(timer.label) == "table" and timer.label.name or timer.label or ""
		bar.name:SetFormattedText(timer.count and timer.count > 1 and "%d" or "",timer.count);
		else
			local labelText = type(timer.label) == "table" and timer.label.name or timer.label
			labelText = tostring(labelText or "")

			bar.name:SetFormattedText(
				timer.count and timer.count > 1 and self.cfg.auraLabelFormat == "FULL" and "%s (%d)" or "%s",
									  labelText,
							 timer.count
			)
		end

		-- misc
		bar.icon:SetTexture(timer.icon or "Interface\\Icons\\INV_Misc_QuestionMark");
		bar:Show();
		if (GameTooltip:IsOwned(bar)) then
			OnEnter(bar);
		end
	end

	-- Hide all other frames
	for i = #self.timers + 1, #self.bars do
		self.bars[i]:Hide();
	end
end

-- Scan Unit Auras
function AuraPluginMixin:ScanAllAuras()
	if (self.cfg.unit == "player" and self.cfg.showEnchants) then
		UpdateEnchantTimers(self,LWE:GetEnchantData());
	end
	if (self.cfg.unit == "player" and self.cfg.showTracking) then
		events.MINIMAP_UPDATE_TRACKING(self,"MINIMAP_UPDATE_TRACKING");
	end
	if (self.cfg.showBuffs or self.cfg.showDebuffs) then
		events.UNIT_AURA(self,"UNIT_AURA",self.cfg.unit);
	end
	self:UpdateTimers();
end

-- OnConfigChanged -- Enable/Disable Plugin & Blizz Buff Frames
function AuraPluginMixin:OnConfigChanged(cfg)
	-- Configure Ourself
	self.timers:Recycle();
	self:UnregisterAllEvents();
	LWE:UnregisterCallback(self);
	if (cfg.enabled) then
		if (cfg.showBuffs or cfg.showDebuffs) then
			self:RegisterEvent("UNIT_AURA");
			if (cfg.unit == "target") then
				self:RegisterEvent("PLAYER_TARGET_CHANGED");
			elseif (cfg.unit == "focus") then
				self:RegisterEvent("PLAYER_FOCUS_CHANGED");
			elseif (cfg.unit == "pet") then
				self:RegisterEvent("UNIT_PET");
			end
		end
		if (cfg.unit == "player") then
			if (cfg.showEnchants) then
				LWE:RegisterCallback(self,UpdateEnchantTimers);
			end
			if (cfg.showTracking) then
				self:RegisterEvent("MINIMAP_UPDATE_TRACKING");
			end
		end
		self:ScanAllAuras();
	else
		self:UpdateTimers();
	end
	-- Blizzard UI Fixup -- Player unit only -- PlayerAuras bar only
	if (cfg.unit == "player") and (self.token == "PlayerAuras") and (cfg.enabled) then
		-- BuffFrame
		if (cfg.hideAuras) then
			BuffFrame:UnregisterEvent("UNIT_AURA");
			BuffFrame:Hide();
		else
			BuffFrame:RegisterEvent("UNIT_AURA");
			BuffFrame:Show();
			if (BuffFrame:GetScript("OnEvent")) then
				BuffFrame:GetScript("OnEvent")(BuffFrame,"UNIT_AURA","player");
			end
		end
		--[[ TempEnchantFrame
		if (cfg.hideEnchants) then
			TemporaryEnchantFrame:Hide();
		else
			TemporaryEnchantFrame:Hide();
		end
		-- MiniMapTracking
		if (cfg.hideTracking) then
			MiniMapTracking:Hide();
			MiniMapTrackingButton:UnregisterEvent("MINIMAP_UPDATE_TRACKING");
		else
			MiniMapTracking:Show();
			MiniMapTrackingButton:RegisterEvent("MINIMAP_UPDATE_TRACKING");
			MiniMapTracking_Update();
		end]]
	end
end

--------------------------------------------------------------------------------------------------------
--                                          Initialise Plugin                                         --
--------------------------------------------------------------------------------------------------------

-- Spawns a new Aura Plugin
local function SpawnAuraPlugin(token)
	local bar = AzCastBar:CreateMainBar("Button",token,extraOptions,true);

	Mixin(bar,AuraPluginMixin);

	bar.timers = LibTableRecycler:New();

	bar:ClearAllPoints();
	bar:SetPoint("CENTER");
	bar:SetScript("OnEvent",OnEvent);
	bar:ConfigureBar();
end

-- You can spawn any amount of aura plugins here, besides the default PlayerAuras & TargetAuras. Just make sure to call them something unique
SpawnAuraPlugin("PlayerAuras");
SpawnAuraPlugin("TargetAuras");
