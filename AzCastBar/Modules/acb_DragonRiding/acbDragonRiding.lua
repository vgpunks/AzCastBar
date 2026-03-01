local GetTime = GetTime
local UnitPowerBarID = UnitPowerBarID

local C_PlayerInfo = C_PlayerInfo
local C_Spell = C_Spell
local C_UnitAuras = C_UnitAuras
local C_Secrets = C_Secrets

-- Dragonriding / Skyriding power bar id (same check used by DirasSuite)
local DRAGONRIDING_POWER_BAR_ID = 631

-- Spells / Auras (ported from DirasSuite Dragonriding module)
local SPELL_SURGE_FORWARD = 372608
local AURA_THRILL_OF_THE_SKIES = 377234
local AURA_SKYRIDING_RACE = 369968

-- Helpers
local function Clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

local function HasPlayerAura(spellID)
	if C_Secrets and C_Secrets.ShouldSpellAuraBeSecret and C_Secrets.ShouldSpellAuraBeSecret(spellID) then
		return false
	end
	if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
		return C_UnitAuras.GetPlayerAuraBySpellID(spellID) ~= nil
	end
	return false
end


local function GetSpellTextureSafe(spellID)
	if C_Spell and C_Spell.GetSpellTexture then
		return C_Spell.GetSpellTexture(spellID)
	end
	if GetSpellTexture then
		return GetSpellTexture(spellID)
	end
	return nil
end

-- Normalize speed if in downscaled zone (DirasSuite behavior)
local function GetZoneSpeedModifier()
	local zones = {
		[2444] = true, -- Dragon Isles
		[2454] = true, -- Zaralek Cavern
		[2516] = true, -- Nokhud Offensive
		[2522] = true, -- Vault of the Incarnates
		[2548] = true, -- Emerald Dream
		[2569] = true, -- Aberrus, the Shadowed Crucible
	}

	if HasPlayerAura(AURA_SKYRIDING_RACE) and not HasOverrideActionBar() then
		return 1
	end

	local instanceID = select(8, GetInstanceInfo())
	if instanceID and zones[instanceID] then
		return 1
	end

	return 705 / 830
end

local function SmoothLerp(prev, cur)
	-- DirasSuite uses FrameDeltaLerp(prev, cur, 0.2)
	if FrameDeltaLerp then
		return FrameDeltaLerp(prev, cur, 0.2)
	end
	return prev + (cur - prev) * 0.2
end

local function SetStatusValue(statusBar, value)
	if not value then
		return
	end
	if Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut then
		statusBar:SetValue(value, Enum.StatusBarInterpolation.ExponentialEaseOut)
	else
		statusBar:SetValue(value)
	end
end

local function EnsureSegmentDividers(bar, maxSegments)
	if not bar or not bar.status then
		return
	end

	if maxSegments == nil or maxSegments < 2 then
		if bar._segmentDividers then
			for _, t in ipairs(bar._segmentDividers) do
				t:Hide()
			end
		end
		bar._segmentDividerMax = nil
		return
	end

	bar._segmentDividers = bar._segmentDividers or {}
	bar._segmentDividerMax = maxSegments

	-- Create / reuse textures
	for i = 1, (maxSegments - 1) do
		if not bar._segmentDividers[i] then
			local t = bar.status:CreateTexture(nil, "OVERLAY")
			t:SetColorTexture(0, 0, 0, 0.6)
			t:SetWidth(1)
			bar._segmentDividers[i] = t
		end
		bar._segmentDividers[i]:Show()
	end
	-- Hide extras
	for i = (maxSegments), #bar._segmentDividers do
		if bar._segmentDividers[i] then
			bar._segmentDividers[i]:Hide()
		end
	end

	-- Layout
	local w = bar.status:GetWidth() or 0
	if w <= 0 then
		return
	end
	local step = w / maxSegments
	for i = 1, (maxSegments - 1) do
		local t = bar._segmentDividers[i]
		t:ClearAllPoints()
		t:SetPoint("TOPLEFT", bar.status, "TOPLEFT", step * i, 0)
		t:SetPoint("BOTTOMLEFT", bar.status, "BOTTOMLEFT", step * i, 0)
	end

	-- Keep layout correct on resizes
	if not bar._segmentHooked then
		bar._segmentHooked = true
		bar.status:HookScript("OnSizeChanged", function()
			if bar._segmentDividerMax then
				EnsureSegmentDividers(bar, bar._segmentDividerMax)
			end
		end)
	end
end

-- Extra Options
local extraOptions = {
	{
		[0] = "Dragonriding",
		{ type = "Color", var = "colSpeed",  default = { 53/255, 167/255, 225/255, 1 }, label = "Speed Bar Color" },
		{ type = "Color", var = "colThrill", default = { 140/255, 207/255,  99/255, 1 }, label = "Speed Color (Thrill of the Skies)" },
		{ type = "Color", var = "colVigor",  default = { 225/255, 221/255, 200/255, 1 }, label = "Vigor Bar Color" },
	},
}

-- Vars
local plugin = AzCastBar:CreateMainBar("Frame", "Dragonriding", extraOptions, true)
local vigorBar = AzCastBar:CreateBar("Frame", plugin)

plugin.speedBar = plugin
plugin.vigorBar = vigorBar

-- Default labels
plugin.name:SetText("Speed")
vigorBar.name:SetText("Vigor")

local function IsDragonridingActive()
	return UnitPowerBarID("player") == DRAGONRIDING_POWER_BAR_ID
end

function plugin:UpdateVisibility()
	if not self.cfg or not self.cfg.enabled then
		self.inDragonriding = false
		self:Hide()
		self.vigorBar:Hide()
		return
	end

	self.inDragonriding = IsDragonridingActive()

	if self.inDragonriding then
		self:Show()
		self.vigorBar:Show()
	else
		self:Hide()
		self.vigorBar:Hide()
	end
end

function plugin:ApplyColors()
	if not self.cfg then
		return
	end

	-- Speed color (may be overridden in UpdateSpeedColor)
	if self.cfg.colSpeed then
		self.status:SetStatusBarColor(unpack(self.cfg.colSpeed))
	end
	if self.cfg.colVigor then
		self.vigorBar.status:SetStatusBarColor(unpack(self.cfg.colVigor))
	end
end

function plugin:UpdateSpeedColor()
	if not self.cfg then
		return
	end

	local col = self.cfg.colSpeed
	if HasPlayerAura(AURA_THRILL_OF_THE_SKIES) and self.cfg.colThrill then
		col = self.cfg.colThrill
	end

	if col then
		self.status:SetStatusBarColor(unpack(col))
	end
end

local function GetSurgeForwardCharges()
	if C_Secrets and C_Secrets.ShouldSpellCooldownBeSecret and C_Secrets.ShouldSpellCooldownBeSecret(SPELL_SURGE_FORWARD) then
		return nil
	end
	if C_Spell and C_Spell.GetSpellCharges then
		return C_Spell.GetSpellCharges(SPELL_SURGE_FORWARD)
	end
	return nil
end

-- OnUpdate
local function OnUpdate(self, elapsed)
	self._updateThrottle = (self._updateThrottle or 0) + elapsed
	if self._updateThrottle < 0.015 then
		return
	end
	self._updateThrottle = 0

	if not self.inDragonriding then
		return
	end

	-- Icons
	if not self._iconsSet then
		self._iconsSet = true
		local tex = GetSpellTextureSafe(SPELL_SURGE_FORWARD)
		if tex then
			self.icon:SetTexture(tex)
			self.vigorBar.icon:SetTexture(tex)
		end
	end

	-- Speed
	local forwardSpeed = 0
	if C_PlayerInfo and C_PlayerInfo.GetGlidingInfo then
		local _, _, fwd = C_PlayerInfo:GetGlidingInfo()
		forwardSpeed = fwd or 0
	end

	local speed = forwardSpeed / GetZoneSpeedModifier()
	local prev = self._prevSpeed or speed
	local newSpeed = SmoothLerp(prev, speed)
	self._prevSpeed = newSpeed

	self.status:SetMinMaxValues(0, 100)
	SetStatusValue(self.status, newSpeed)
	self.name:SetText("Speed")
	self.time:SetFormattedText("%d%%", newSpeed)

	-- Update speed color based on Thrill aura
	self:UpdateSpeedColor()

	-- Vigor / Charges
	local charges = GetSurgeForwardCharges()
	if charges and charges.maxCharges and charges.maxCharges > 0 then
		local current = charges.currentCharges or 0
		local max = charges.maxCharges or 0
		local startTime = charges.cooldownStartTime or 0
		local duration = charges.cooldownDuration or 0

		local value = current
		if current < max and startTime > 0 and duration > 0 then
			local frac = Clamp((GetTime() - startTime) / duration, 0, 1)
			value = current + frac
		end

		self.vigorBar.status:SetMinMaxValues(0, max)
		SetStatusValue(self.vigorBar.status, value)
		self.vigorBar.name:SetText("Vigor")
		self.vigorBar.time:SetFormattedText("%d / %d", current, max)

		EnsureSegmentDividers(self.vigorBar, max)
	else
		self.vigorBar.status:SetMinMaxValues(0, 1)
		SetStatusValue(self.vigorBar.status, 0)
		self.vigorBar.name:SetText("Vigor")
		self.vigorBar.time:SetText("")
		EnsureSegmentDividers(self.vigorBar, 0)
	end
end

-- Events
function plugin:PLAYER_ENTERING_WORLD()
	self:UpdateVisibility()
end

function plugin:UNIT_POWER_BAR_SHOW(event, unit)
	if unit == "player" then
		self:UpdateVisibility()
	end
end

function plugin:UNIT_POWER_BAR_HIDE(event, unit)
	if unit == "player" then
		self:UpdateVisibility()
	end
end

function plugin:PLAYER_CAN_GLIDE_CHANGED()
	self:UpdateVisibility()
end

function plugin:PLAYER_IS_GLIDING_CHANGED()
	self:UpdateVisibility()
end

function plugin:OnConfigChanged(cfg)
	if cfg.enabled then
		self:RegisterEvent("PLAYER_ENTERING_WORLD")
		self:RegisterEvent("UNIT_POWER_BAR_SHOW")
		self:RegisterEvent("UNIT_POWER_BAR_HIDE")
		self:RegisterEvent("PLAYER_CAN_GLIDE_CHANGED")
		self:RegisterEvent("PLAYER_IS_GLIDING_CHANGED")

		self:ApplyColors()
		self:UpdateVisibility()
		self:SetScript("OnUpdate", OnUpdate)
	else
		self:UnregisterAllEvents()
		self:SetScript("OnUpdate", nil)
		self:Hide()
		self.vigorBar:Hide()
	end
end
