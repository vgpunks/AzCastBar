-- EmpowerCastBar.lua
-- Drop-in support for Empowered spells (Evoker etc.)

local EmpowerBar = CreateFrame("StatusBar", "MyEmpowerBar", UIParent)
EmpowerBar:SetSize(250, 18)
EmpowerBar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
EmpowerBar:SetMinMaxValues(0, 1)
EmpowerBar:SetValue(0)
EmpowerBar:Hide()

-- simple background + border
local bg = EmpowerBar:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints(true)
bg:SetColorTexture(0, 0, 0, 0.5)
local bd = CreateFrame("Frame", nil, EmpowerBar, "BackdropTemplate")
bd:SetAllPoints(true)
bd:SetBackdrop({edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", edgeSize=12})

local label = EmpowerBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
label:SetPoint("LEFT", EmpowerBar, "LEFT", 4, 0)
label:SetText("Empower")

-- state
local unit       = "player"
local activeGUID = nil
local spellID    = nil
local startTime  = 0
local endTime    = 0

-- WoW 11.0 removed the global GetSpellInfo function, so fall back to the
-- C_Spell API when the global does not exist.
local GetSpellInfo = GetSpellInfo or (C_Spell and C_Spell.GetSpellInfo);
local C_Spell = C_Spell;

-- OnUpdate drives the bar while holding
EmpowerBar:SetScript("OnUpdate", function(self)
  if endTime > startTime then
    local now = GetTime()
    local duration = endTime - startTime
    local v = math.min((now - startTime) / duration, 1)
    self:SetValue(v)
  else
    self:SetValue(0)
  end
end)

-- Positioning: attach to your existing cast bar if you like
-- Example: anchor under the default player cast bar
EmpowerBar:SetPoint("TOP", CastingBarFrame, "BOTTOM", 0, -6)

-- Event handling
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_SPELLCAST_EMPOWER_START")
f:RegisterEvent("UNIT_SPELLCAST_EMPOWER_UPDATE")
f:RegisterEvent("UNIT_SPELLCAST_EMPOWER_STOP")
f:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")

f:SetScript("OnEvent", function(_, event, unitToken, castGUID, argSpellID)
  if event == "PLAYER_ENTERING_WORLD" then
    EmpowerBar:Hide()
    activeGUID, spellID = nil, nil
    return
  end

  if unitToken ~= unit then return end

  if event == "UNIT_SPELLCAST_EMPOWER_START" then
    activeGUID = castGUID
    spellID = argSpellID
    local info = GetSpellInfo and GetSpellInfo(spellID)
    local spellName = type(info) == "table" and info.name or info
    label:SetText(spellName or "")
    local _, _, _, sTime, eTime = UnitCastingInfo(unit)
    if not sTime then
      _, _, _, sTime, eTime = UnitChannelInfo(unit)
    end
    if sTime and eTime then
      startTime = sTime / 1000
      endTime = eTime / 1000
    else
      startTime, endTime = GetTime(), GetTime()
    end
    EmpowerBar:SetMinMaxValues(0, 1)
    EmpowerBar:SetValue(0)
    EmpowerBar:Show()

  elseif event == "UNIT_SPELLCAST_EMPOWER_UPDATE" then
    local _, _, _, sTime, eTime = UnitChannelInfo(unit)
    if sTime and eTime then
      startTime = sTime / 1000
      endTime = eTime / 1000
    end

  elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" or event == "UNIT_SPELLCAST_INTERRUPTED" then
    if castGUID == activeGUID then
      EmpowerBar:Hide()
      activeGUID, spellID = nil, nil
      startTime, endTime = 0, 0
    end
  end
end)

-- Optional: slash to move the bar
SLASH_MYEMPOWER1 = "/empbar"
SlashCmdList.MYEMPOWER = function(msg)
  if msg == "unlock" then
    EmpowerBar:EnableMouse(true)
    EmpowerBar:SetMovable(true)
    EmpowerBar:RegisterForDrag("LeftButton")
    EmpowerBar:SetScript("OnDragStart", EmpowerBar.StartMoving)
    EmpowerBar:SetScript("OnDragStop", EmpowerBar.StopMovingOrSizing)
    print("Empower bar unlocked. Drag to move. /empbar lock to finish.")
  elseif msg == "lock" then
    EmpowerBar:EnableMouse(false)
    EmpowerBar:RegisterForDrag()
    EmpowerBar:SetMovable(false)
    EmpowerBar:SetScript("OnDragStart", nil)
    EmpowerBar:SetScript("OnDragStop", nil)
    print("Empower bar locked.")
  else
    print("Usage: /empbar unlock | lock")
  end
end

