local GetTime = GetTime;

-- Extra Options
local extraOptions = {
	{
		[0] = "Additional",
		{ type = "Color", var = "colNormal", default = { 0.4, 0.6, 0.8 }, label = "Cooldown Bar Color" },
		{ type = "Slider", var = "minShownCooldown", default = 10, label = "Minimum Shown Cooldown", min = 0, max = 600, step = 1, y = 12 },
		{ type = "Slider", var = "maxShownCooldown", default = 0, label = "Maximum Shown Cooldown", min = 0, max = 600, step = 1 },
	},
};

-- Variables
local plugin = AzCastBar:CreateMainBar("Frame","Cooldowns",extraOptions,true);
local timers = LibTableRecycler:New();

--------------------------------------------------------------------------------------------------------
--                                            Frame Scripts                                           --
--------------------------------------------------------------------------------------------------------

-- OnUpdate
local function OnUpdate(self,elapsed)
	local timer = self.timer;
	-- Progression
	if (not self.fadeTime) then
		self.timeLeft = (timer.endTime - GetTime());
		if (self.timeLeft < 0) then
			self.timeLeft = 0;
		end
		self.status:SetValue(self.timeLeft);
		self:SetTimeText(self.timeLeft);
		if (self.timeLeft == 0) then
			self.fadeTime = self.cfg.fadeTime;
		end
	-- FadeOut
	elseif ((self.fadeElapsed + elapsed) <= self.fadeTime) then--elseif (self.fadeElapsed <= self.fadeTime) then
		self.fadeElapsed = (self.fadeElapsed + elapsed);
		self:SetAlpha(self.cfg.alpha - self.fadeElapsed / self.fadeTime * self.cfg.alpha);
	else
		self:Hide();
		timers:RecycleIndex(self.index);
		plugin:QueryCooldowns();
	end
end

-- Cooldown Update
function plugin:SPELL_UPDATE_COOLDOWN(event)
	self:QueryCooldowns();
end

--------------------------------------------------------------------------------------------------------
--                                                Code                                                --
--------------------------------------------------------------------------------------------------------

local function SortCooldownsFunc(a,b)
	return a.endTime > b.endTime;
end

-- ConfigureBar
function plugin:ConfigureBar(bar)
	bar = (bar or self);
	bar:SetScript("OnUpdate",OnUpdate);
	return bar;
end


-- Query Cooldowns
function plugin:QueryCooldowns()
        timers:Recycle();
        for tab = 1, C_SpellBook.GetNumSpellBookSkillLines() do
                local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(tab)
                local offset = skillLineInfo.itemIndexOffset or skillLineInfo.spellOffset or 0
                local numSpells = skillLineInfo.numSpellBookItems or skillLineInfo.numSlots or 0
                local name = skillLineInfo.name
                if (not name) then
                        break;
                end
                for i = offset + 1, offset + numSpells do
                        local info = C_SpellBook.GetSpellBookItemInfo(i, Enum.SpellBookSpellBank.Player)
                        local spellID = info and info.spellID
                        if spellID then
                                local cooldown = C_Spell.GetSpellCooldown(spellID)
                                local start, duration = cooldown.startTime, cooldown.duration
                                if (duration) and (duration > 0) and (duration > self.cfg.minShownCooldown) and (self.cfg.maxShownCooldown == 0 or duration < self.cfg.maxShownCooldown) then
                                        local tbl = timers:Fetch();
                                        local spellName, _, texture = C_Spell.GetSpellInfo(spellID);
                                        tbl.name = spellName; tbl.duration = duration; tbl.startTime = start; tbl.endTime = start + duration; tbl.texture = texture;
                                end
                        end
                end
        end
        sort(timers,SortCooldownsFunc);
        self:UpdateTimers();
end

-- Updates Timers
function plugin:UpdateTimers()
	for index, timer in ipairs(timers) do
		local bar = self.bars[index] or self:ConfigureBar(AzCastBar:CreateBar("Frame",self));

		bar.index = index;
		bar.timer = timer;

		bar.icon:SetTexture(timer.texture);
		bar.name:SetText(timer.name);

		bar.status:SetStatusBarColor(unpack(self.cfg.colNormal));

		bar:ResetAndShow(timer.duration);
	end
	-- Hide the rest
	for i = #timers + 1, #self.bars do
		self.bars[i]:Hide();
	end
end

-- OnConfigChanged
function plugin:OnConfigChanged(cfg)
	if (cfg.enabled) then
		self:RegisterEvent("SPELL_UPDATE_COOLDOWN");
		self:QueryCooldowns();
	else
		self:UnregisterAllEvents();
		timers:Recycle();
		self:UpdateTimers();
	end
end

--------------------------------------------------------------------------------------------------------
--                                          Initialise Plugin                                         --
--------------------------------------------------------------------------------------------------------

plugin:ConfigureBar();
