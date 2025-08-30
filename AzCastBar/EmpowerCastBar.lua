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

-- label + stage text
local label = EmpowerBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
label:SetPoint("LEFT", EmpowerBar, "LEFT", 4, 0)
label:SetText("Empower")

local stageText = EmpowerBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
stageText:SetPoint("RIGHT", EmpowerBar, "RIGHT", -4, 0)
stageText:SetText("")

-- tick container
EmpowerBar.ticks = {}
local function clearTicks()
  for _, t in ipairs(EmpowerBar.ticks) do t:Hide() end
  wipe(EmpowerBar.ticks)
end

-- state
local unit       = "player"
local activeGUID = nil
local spellID    = nil
local stageDur   = {}   -- per stage seconds
local totalDur   = 0
local elapsed    = 0

-- WoW 11.0 removed the global GetSpellInfo function, so fall back to the
-- C_Spell API when the global does not exist.
local GetSpellInfo = GetSpellInfo or (C_Spell and C_Spell.GetSpellInfo);

-- Helper: obtain empower stage duration regardless of API changes
local function GetStageDuration(stageIndex)
  if GetUnitEmpowerStageDuration then
    return GetUnitEmpowerStageDuration(unit, stageIndex)
  elseif C_Spell and C_Spell.GetSpellEmpowerStageDuration and spellID then
    return C_Spell.GetSpellEmpowerStageDuration(spellID, stageIndex)
  end
end

-- Helper: build stage ticks using GetUnitEmpowerStageDuration
local function buildTicks()
  clearTicks()
  wipe(stageDur)
  totalDur = 0

  local numStages
  -- Attempt to use newer API providing full empower info
  if C_Spell and C_Spell.GetSpellEmpowerInfo and spellID then
    local info = C_Spell.GetSpellEmpowerInfo(spellID)
    if info and info.numStages and info.numStages > 0 then
      numStages = info.numStages
      if info.stageDurations then
        for i = 1, numStages do
          local d = info.stageDurations[i] or 0
          stageDur[i] = d
          totalDur = totalDur + d
        end
      end
    end
  end

  -- Fallback: query stage duration per index until API returns nil
  if not numStages then
    local stageIndex = 1
    while true do
      local d = GetStageDuration(stageIndex)
      if d == nil then break end
      stageDur[stageIndex] = d
      totalDur = totalDur + (d > 0 and d or 0)
      stageIndex = stageIndex + 1
    end
    numStages = #stageDur
  end

  -- If we know stages but total duration is zero (API returned 0 for final stage),
  -- fall back to equally spaced ticks so stage count is still represented.
  if numStages <= 0 then return end
  if totalDur <= 0 then
    totalDur = numStages
    for i = 1, numStages do stageDur[i] = 1 end
  end

  -- place visual ticks at stage thresholds
  local acc = 0
  for i = 1, numStages - 1 do
    acc = acc + stageDur[i]
    local tick = EmpowerBar:CreateTexture(nil, "OVERLAY")
    tick:SetColorTexture(1, 1, 1, 0.6)
    tick:SetSize(2, EmpowerBar:GetHeight())
    local x = (acc / totalDur) * EmpowerBar:GetWidth()
    tick:SetPoint("LEFT", EmpowerBar, "LEFT", x - 1, 0)
    tick:Show()
    table.insert(EmpowerBar.ticks, tick)
  end
end

-- compute current stage from elapsed time
local function currentStage()
  local sum = 0
  for i = 1, #stageDur do
    sum = sum + stageDur[i]
    if elapsed < sum - 1e-6 then
      return i
    end
  end
  return #stageDur
end

-- OnUpdate drives the bar while holding
EmpowerBar:SetScript("OnUpdate", function(self, dt)
  elapsed = elapsed + dt
  if totalDur > 0 then
    local v = math.min(elapsed / totalDur, 1)
    self:SetValue(v)
    stageText:SetText(("Stage %d/%d"):format(currentStage(), #stageDur))
  else
    self:SetValue(0)
    stageText:SetText("")
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
    elapsed = 0
    buildTicks()
    local info = GetSpellInfo and GetSpellInfo(spellID)
    local spellName = type(info) == "table" and info.name or info
    label:SetText(spellName or "")
    EmpowerBar:SetMinMaxValues(0, 1)
    EmpowerBar:SetValue(0)
    EmpowerBar:Show()

  elseif event == "UNIT_SPELLCAST_EMPOWER_UPDATE" then
    -- Durations can change per spell; rebuild in case (cheap)
    buildTicks()

  elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" or event == "UNIT_SPELLCAST_INTERRUPTED" then
    -- Fire the spell or cancel → hide and reset
    if castGUID == activeGUID then
      EmpowerBar:Hide()
      activeGUID, spellID = nil, nil
      clearTicks()
      wipe(stageDur)
      totalDur, elapsed = 0, 0
      stageText:SetText("")
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

