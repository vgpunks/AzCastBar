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

	local bank = Enum.SpellBookSpellBank.Player;

	local function SafeTest(fn)
		local ok, res = pcall(fn);
		if ok then
			return res;
		end
		return false;
	end

	local function SafeAdd(a, b)
		local ok, res = pcall(function() return a + b; end);
		if ok and type(res) == "number" then
			return res;
		end
		return nil;
	end

	for skillLineIndex = 1, (C_SpellBook.GetNumSpellBookSkillLines() or 0) do
		-- Some clients return nil unless the bank is provided; extra args are harmless if unused.
		local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(skillLineIndex, bank) or C_SpellBook.GetSpellBookSkillLineInfo(skillLineIndex);
		if skillLineInfo and skillLineInfo.itemIndexOffset and skillLineInfo.numSpellBookItems then
			local offset = skillLineInfo.itemIndexOffset;
			local numItems = skillLineInfo.numSpellBookItems;

			for itemIndex = offset + 1, offset + numItems do
				local itemType, actionID, spellID = C_SpellBook.GetSpellBookItemType(itemIndex, bank);
				if itemType == Enum.SpellBookItemType.Spell then
					local sid = spellID or actionID;
					if sid and (not (C_Secrets and C_Secrets.ShouldSpellCooldownBeSecret) or not C_Secrets.ShouldSpellCooldownBeSecret(sid)) then
						local cd = C_SpellBook.GetSpellBookItemCooldown(itemIndex, bank);
						local start, duration, enabled;
						if type(cd) == "table" then
							start = cd.startTime;
							duration = cd.duration;
							enabled = cd.isEnabled;
						else
							start, duration, enabled = C_SpellBook.GetSpellBookItemCooldown(itemIndex, bank);
						end

						local isEnabled = (enabled == nil) and true or SafeTest(function() return enabled ~= 0 and enabled ~= false; end);
						local withinRange = SafeTest(function()
							if not start or not duration then return false; end
							if start <= 0 then return false; end -- only show active cooldowns
							if duration <= self.cfg.minShownCooldown then return false; end
							if self.cfg.maxShownCooldown ~= 0 and duration >= self.cfg.maxShownCooldown then return false; end
							return true;
						end);

						if isEnabled and withinRange then
							local endTime = SafeAdd(start, duration);
							if endTime then
								local tbl = timers:Fetch();
								local spellInfo = C_Spell.GetSpellInfo(sid);
								tbl.name = (spellInfo and spellInfo.name) or (C_Spell.GetSpellName and C_Spell.GetSpellName(sid)) or "";
								tbl.texture = (spellInfo and spellInfo.iconID) or nil;
								tbl.duration = duration;
								tbl.startTime = start;
								tbl.endTime = endTime;
							end
						end
					end
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
