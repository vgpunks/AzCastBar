if (select(2,UnitClass("player")) ~= "SHAMAN") then
	return;
end

local GetTime = GetTime;

-- Extra Options
local extraOptions = {
	{
		[0] = "Colors",
		{ type = "Color", var = "colNormal", default = { 0.4, 0.6, 0.8 }, label = "Totem Bar Color" },
	},
};

-- Variables
local plugin = AzCastBar:CreateMainBar("Button","Totems",extraOptions,true);
local totems = LibTableRecycler:New();

--------------------------------------------------------------------------------------------------------
--                                            Frame Scripts                                           --
--------------------------------------------------------------------------------------------------------

-- OnUpdate
local function OnUpdate(self,elapsed)
	local totem = self.totem;
	-- Progression
	if (not self.fadeTime) then
		self.timeLeft = (totem.endTime - GetTime());
		if (self.timeLeft < 0) then
			self.timeLeft = 0;
		end
		self.status:SetValue(self.timeLeft);
		self:SetTimeText(self.timeLeft);
		if (self.timeLeft == 0) then
			self.fadeTime = self.cfg.fadeTime
		end
	-- FadeOut
	elseif ((self.fadeElapsed + elapsed) <= self.fadeTime) then--elseif (self.fadeElapsed <= self.fadeTime) then
		self.fadeElapsed = (self.fadeElapsed + elapsed);
		self:SetAlpha(self.cfg.alpha - self.fadeElapsed / self.fadeTime * self.cfg.alpha);
	else
		totems:RecycleIndex(self.index);
		plugin:UpdateTotemBars();
	end
end

-- OnClick -- DestroyTotem is secure and we cannot use it here anymore
local function OnClick(self,button,down)
	if (button == "RightButton") then
		--DestroyTotem(self.totem.id);
		--securecall(DestroyTotem,self.totem.id);
	end
end

-- OnEvent
local function OnEvent(self,event,...)
	totems:Recycle();
	for i = 1, MAX_TOTEMS do
		local haveTotem, totemName, startTime, duration, texture = GetTotemInfo(i);
		if (totemName and totemName ~= "") then
			local totem = totems:Fetch();
			totem.name = totemName;
			totem.duration = duration;
			totem.endTime = startTime + duration;
			totem.texture = texture;
			totem.id = i;
		end
	end
	plugin:UpdateTotemBars();
end

--------------------------------------------------------------------------------------------------------
--                                                Code                                                --
--------------------------------------------------------------------------------------------------------

-- ConfigureBar
function plugin:ConfigureBar(bar)
	bar = (bar or self);
	bar:EnableMouse(1);
	bar:RegisterForClicks("AnyUp");
	bar:SetScript("OnUpdate",OnUpdate);
	bar:SetScript("OnClick",OnClick);
	return bar;
end

-- UpdateBars
function plugin:UpdateTotemBars()
	-- Loop Totems
	for index, totem in ipairs(totems) do
		local bar = self.bars[index] or self:ConfigureBar(AzCastBar:CreateBar("Button",self));

		bar.index = index;
		bar.totem = totem;

		bar.name:SetText(totem.name);
		bar.icon:SetTexture(totem.texture);

		bar.status:SetStatusBarColor(unpack(self.cfg.colNormal));

		bar:ResetAndShow(totem.duration);
	end
	-- Hide Remaining
	for i = #totems + 1, #self.bars do
		self.bars[i]:Hide();
	end
end

-- OnConfigChanged
function plugin:OnConfigChanged(cfg)
	if (cfg.enabled) then
		self:RegisterEvent("PLAYER_TOTEM_UPDATE");
		self:RegisterEvent("PLAYER_ENTERING_WORLD");
		OnEvent(self);
	else
		self:UnregisterAllEvents();
		totems:Recycle();
		self:UpdateTotemBars();
	end
end

--------------------------------------------------------------------------------------------------------
--                                          Initialise Plugin                                         --
--------------------------------------------------------------------------------------------------------

plugin:SetScript("OnEvent",OnEvent);
plugin:ConfigureBar();
