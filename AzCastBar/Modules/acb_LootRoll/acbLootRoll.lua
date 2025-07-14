local GetLootRollTimeLeft = GetLootRollTimeLeft;
local gtt = GameTooltip;

-- Variables
local plugin = AzCastBar:CreateMainBar("Button","LootRolls",nil,true);
local rolls = LibTableRecycler:New();

-- Cleanup Blizz Roll Windows
UIParent:UnregisterEvent("START_LOOT_ROLL");
UIParent:UnregisterEvent("CANCEL_LOOT_ROLL");
--[[for i = 1, NUM_GROUP_LOOT_FRAMES do
	_G["GroupLootFrame"..i]:UnregisterAllEvents();
end
GroupLootFrame_OpenNewFrame = nil;
GroupLootFrame_OnShow = nil;
GroupLootFrame_OnHide = nil;
GroupLootFrame_OnEvent = nil;
GroupLootFrame_OnUpdate = nil;
]]--
--------------------------------------------------------------------------------------------------------
--                                            Frame Scripts                                           --
--------------------------------------------------------------------------------------------------------

-- OnUpdate
local function OnUpdate(self,elapsed)
	local roll = self.roll;
	-- Update Progression
	self.timeLeft = (GetLootRollTimeLeft(roll.id) / 1000);
	if (self.timeLeft > roll.time) then	-- As a roll runs out of time, the time returned from GetLootRollTimeLeft wraps and becomes something like 2^32 (uint32)
		self.timeLeft = 0;
	end
	self.status:SetValue(self.timeLeft);
	self:SetTimeText(self.timeLeft);
	-- Change Cursor Icon
	if (gtt:IsOwned(self)) then
		gtt:SetOwner(self,AzCastBar:GetOptimalAnchor(self));
		gtt:SetLootRollItem(roll.id);
		if (IsModifiedClick("DRESSUP")) then
			ShowInspectCursor();
		else
			ResetCursor();
		end
	end
end

-- OnClick
local function OnClick(self,button,down)
	if (button == "LeftButton") then
		HandleModifiedItemClick(GetLootRollItemLink(self.roll.id));
	elseif (button == "RightButton") then
		RollOnLoot(self.roll.id,0);
	end
end

-- OnEnter
local function OnEnter(self)
	gtt:SetOwner(self,AzCastBar:GetOptimalAnchor(self));
	gtt:SetLootRollItem(self.roll.id);
end

-- HideGTT
local function OnLeave(self)
	gtt:Hide();
	ResetCursor();
end

-- Roll Start
function plugin:START_LOOT_ROLL(event,rollId,rollTime)
	local tbl = rolls:Fetch();
	tbl.id = rollId;
	tbl.time = rollTime / 1000;
	self:UpdateRollBars();
end

-- Roll Canceled
function plugin:CANCEL_LOOT_ROLL(event,rollId)
	for index, table in ipairs(rolls) do
		if (table.id == rollId) then
			StaticPopup_Hide("CONFIRM_LOOT_ROLL",rollId);
			rolls:RecycleIndex(index);
			self:UpdateRollBars();
			break;
		end
	end
end

--------------------------------------------------------------------------------------------------------
--                                                Code                                                --
--------------------------------------------------------------------------------------------------------

-- RollButtons OnClick
local function RollButtons_OnClick(self,button,down)
	RollOnLoot(self:GetParent().roll.id,self.type);
end

-- RollButtons OnEnter
local function RollButtons_OnEnter(self)
	gtt:SetOwner(self,AzCastBar:GetOptimalAnchor(self));
	gtt:SetText(self.type == 1 and NEED or self.type == 2 and GREED or ROLL_DISENCHANT);
	-- Az: perhaps add a second line here saying: "Right click bar to pass"
end

-- ConfigureBar
function plugin:ConfigureBar(bar)
	bar = (bar or self);
	-- Need Button
	bar.need = CreateFrame("Button",nil,bar);
	bar.need:RegisterForClicks("LeftButtonUp");
	bar.need:SetSize(32,32);
	bar.need:SetPoint("TOPLEFT",bar,"TOPRIGHT",6,2);
	bar.need:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Dice-Up");
	bar.need:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Dice-Highlight");
	bar.need:SetPushedTexture("Interface\\Buttons\\UI-GroupLoot-Dice-Down");
	bar.need:SetScript("OnClick",RollButtons_OnClick);
	bar.need:SetScript("OnEnter",RollButtons_OnEnter);
	bar.need:SetScript("OnLeave",OnLeave);
	bar.need.type = 1;
	-- Greed Button
	bar.greed = CreateFrame("Button",nil,bar);
	bar.greed:RegisterForClicks("LeftButtonUp");
	bar.greed:SetSize(32,32);
	bar.greed:SetPoint("LEFT",bar.need,"RIGHT",2,0);
	bar.greed:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Coin-Up");
	bar.greed:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Coin-Highlight");
	bar.greed:SetPushedTexture("Interface\\Buttons\\UI-GroupLoot-Coin-Down");
	bar.greed:SetScript("OnClick",RollButtons_OnClick);
	bar.greed:SetScript("OnEnter",RollButtons_OnEnter);
	bar.greed:SetScript("OnLeave",OnLeave);
	bar.greed.type = 2;
	-- Disenchant Button -- Added for patch 3.3
	bar.diss = CreateFrame("Button",nil,bar);
	bar.diss:RegisterForClicks("LeftButtonUp");
	bar.diss:SetSize(32,32);
	bar.diss:SetPoint("LEFT",bar.greed,"RIGHT",2,0);
	bar.diss:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-DE-Up");
	bar.diss:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-DE-Highlight");
	bar.diss:SetPushedTexture("Interface\\Buttons\\UI-GroupLoot-DE-Down");
	bar.diss:SetScript("OnClick",RollButtons_OnClick);
	bar.diss:SetScript("OnEnter",RollButtons_OnEnter);
	bar.diss:SetScript("OnLeave",OnLeave);
	bar.diss.type = 3;
	-- Other
	bar:EnableMouse(1);
	bar:RegisterForClicks("LeftButtonUp","RightButtonUp");
	bar:SetScript("OnUpdate",OnUpdate);
	bar:SetScript("OnClick",OnClick);
	bar:SetScript("OnEnter",OnEnter);
	bar:SetScript("OnLeave",OnLeave);
	return bar;
end

-- Update Bars
function plugin:UpdateRollBars()
	-- Loop Rolls
	for index, table in ipairs(rolls) do
		local bar = self.bars[index] or self:ConfigureBar(AzCastBar:CreateBar("Button",self));
		-- Modified for patch 3.3 - New values returned by the method
		local texture, name, count, quality, bindOnPickUp, canNeed, canGreed, canDE = GetLootRollItemInfo(table.id);
		local color = ITEM_QUALITY_COLORS[quality];
		bar.status:SetMinMaxValues(0,table.time);
		bar.status:SetStatusBarColor(color.r,color.g,color.b);
		bar.name:SetText((bindOnPickUp and "|cffffff00BoP|r " or "")..tostring(name)..(count and count > 1 and " ("..count..")" or ""));
		bar.icon:SetTexture(texture);
		bar.totalTimeText = bar:FormatTotalTime(table.time);
		bar.roll = table;
		bar.index = index;
		bar:Show();
		-- Added for patch 3.3 - Enable/disable and saturate/desaturate buttons
		SetDesaturation(bar.need:GetNormalTexture(),not canNeed);
		if (canNeed) then
			bar.need:Enable();
		else
			bar.need:Disable();
		end
		SetDesaturation(bar.greed:GetNormalTexture(),not canGreed);
		if (canGreed) then
			bar.greed:Enable();
		else
			bar.greed:Disable();
		end
		SetDesaturation(bar.diss:GetNormalTexture(),not canDE);
		if (canDE) then
			bar.diss:Enable();
		else
			bar.diss:Disable();
		end
	end
	-- Hide Remaining
	for i = #rolls + 1, #self.bars do
		self.bars[i]:Hide();
	end
	-- Update Tooltip
	local mouseFocus = GetMouseFocus();
	if (mouseFocus) and (gtt:IsOwned(mouseFocus)) and (mouseFocus.cfg == plugin.cfg) then
		OnEnter(mouseFocus);
	end
end

--------------------------------------------------------------------------------------------------------
--                                          Initialise Plugin                                         --
--------------------------------------------------------------------------------------------------------

plugin:RegisterEvent("START_LOOT_ROLL");
plugin:RegisterEvent("CANCEL_LOOT_ROLL");
plugin:ConfigureBar();
