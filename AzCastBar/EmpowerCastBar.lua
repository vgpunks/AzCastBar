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

-- Helper: build stage ticks using GetUnitEmpowerStageDuration
local function buildTicks()
  clearTicks()
  wipe(stageDur)
  totalDur = 0

  -- Blizzard exposes durations per stage; index is 1..N
  -- GetUnitEmpowerStageDuration(unit, stage) -> duration (seconds)
  -- (Warcraft Wiki notes this API; works for empowered casts.)
  local stageIndex = 1
  while true do
    local d = GetUnitEmpowerStageDuration(unit, stageIndex)
    if not d or d <= 0 then break end
    stageDur[stageIndex] = d
    totalDur = totalDur + d
    stageIndex = stageIndex + 1
  end

  if totalDur <= 0 then return end

  -- place visual ticks at stage thresholds
  local acc = 0
  for i = 1, #stageDur - 1 do
    acc = acc + stageDur[i]
    local tick = EmpowerBar:CreateTexture(nil, "OVERLAY")
    tick:SetColorTexture(1, 1, 1, 0.6)
    tick:SetSize(2, EmpowerBar:GetHeight())
    local x = (acc / totalDur) * EmpowerBar:GetWidth()
    tick:SetPoint("LEFT", EmpowerBar, "LEFT", x - 1, 0)
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

