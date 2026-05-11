local ADDON_NAME = ...

-- Per-character DB (kept intentionally small; UHCC is the UI host).
UHCC_AnnoyMeMoreDB = UHCC_AnnoyMeMoreDB or {}

local UHCCAMM = {
  fatigue = 0, -- 0..100
  tickAcc = 0,
  bar = nil,
  speedFs = nil,
  speedFrame = nil,
  barTargetShown = false,
  isRunningNow = false,
  exhausted = false,
  exhaustedIcon = nil,
  exhaustedAlert = nil,
  lastExhaustedAlertAt = 0,
  exhaustedAlertLatched = false,
  debug = {},
  posture = "stand", -- "stand" | "sit" | "lay" (best-effort; Classic clients can lack UnitStandState)
  lastEmoteToken = nil,
  hotFirstTickAt = {}, -- key -> last applied time (periodic heals: only first tick counts)
  lastJumpFatigueAt = 0,
}

local function ensureDB()
  if type(UHCC_AnnoyMeMoreDB) ~= "table" then UHCC_AnnoyMeMoreDB = {} end
  if type(UHCC_AnnoyMeMoreDB.fatigueEnabled) ~= "boolean" then UHCC_AnnoyMeMoreDB.fatigueEnabled = false end
  if type(UHCC_AnnoyMeMoreDB.debugEnabled) ~= "boolean" then UHCC_AnnoyMeMoreDB.debugEnabled = false end
  if type(UHCC_AnnoyMeMoreDB.fatigueValue) ~= "number" then UHCC_AnnoyMeMoreDB.fatigueValue = nil end
  if type(UHCC_AnnoyMeMoreDB.fatigueSavedAt) ~= "number" then UHCC_AnnoyMeMoreDB.fatigueSavedAt = nil end
  if type(UHCC_AnnoyMeMoreDB.exhausted) ~= "boolean" then UHCC_AnnoyMeMoreDB.exhausted = false end
  if type(UHCC_AnnoyMeMoreDB.exhaustedAlertLatched) ~= "boolean" then UHCC_AnnoyMeMoreDB.exhaustedAlertLatched = false end
  if type(UHCC_AnnoyMeMoreDB.fatigueBarPoint) ~= "string" then UHCC_AnnoyMeMoreDB.fatigueBarPoint = "TOP" end
  if type(UHCC_AnnoyMeMoreDB.fatigueBarRelPoint) ~= "string" then UHCC_AnnoyMeMoreDB.fatigueBarRelPoint = "TOP" end
  if type(UHCC_AnnoyMeMoreDB.fatigueBarX) ~= "number" then UHCC_AnnoyMeMoreDB.fatigueBarX = 0 end
  if type(UHCC_AnnoyMeMoreDB.fatigueBarY) ~= "number" then UHCC_AnnoyMeMoreDB.fatigueBarY = -120 end
end

-- Mirrors UltimateHardcoreChallengeUI `uhccAnnoyEnabled()` (Annoy me checkbox); do not modify that addon.
local function uhccParentAnnoyEnabled()
  if type(_G.UHCC_CharDB) ~= "table" then return false end
  local s = _G.UHCC_CharDB.settings
  if type(s) ~= "table" then return false end
  return s["SETTINGS-ANNOY"] == true
end

local function uhccammFatigueEnabled()
  ensureDB()
  return uhccParentAnnoyEnabled() and (UHCC_AnnoyMeMoreDB.fatigueEnabled == true)
end

-- Debug overlay is disabled for normal play. To work on it again, replace the body with the block below.
local function uhccammDebugEnabled()
  return false
  --[[
  ensureDB()
  return uhccParentAnnoyEnabled() and (UHCC_AnnoyMeMoreDB.debugEnabled == true)
  ]]
end

local function uhccammPlayerLevel()
  local lvl = (UnitLevel and UnitLevel("player")) or 1
  lvl = tonumber(lvl) or 1
  if lvl < 1 then lvl = 1 end
  return lvl
end

local function uhccammHiddenStartValue()
  return -uhccammPlayerLevel()
end

local function uhccammFatigueMax()
  return 110
end

local function clamp(v, mn, mx)
  v = tonumber(v) or 0
  mn = tonumber(mn) or 0
  mx = tonumber(mx) or 0
  if v < mn then return mn end
  if v > mx then return mx end
  return v
end

local function uhccammIsInCombat()
  return (UnitAffectingCombat and UnitAffectingCombat("player")) and true or false
end

local function uhccammIsEatingOrDrinking()
  if not UnitBuff then return false end
  for i = 1, 40 do
    local name, icon = UnitBuff("player", i)
    if not name then break end
    local n = tostring(name):lower()
    if n:find("food", 1, true) or n:find("drink", 1, true) then
      return true
    end
    if type(icon) == "string" then
      -- Heuristic: most food/drink buffs use these icon folders.
      if icon:find("INV_Drink", 1, true) or icon:find("INV_Misc_Food", 1, true) then
        return true
      end
    end
  end
  return false
end

local function uhccammIsLaying()
  -- Prefer UnitStandState when available (sleep/lay), otherwise rely on our best-effort posture tracker.
  if UnitStandState then
    local s = tonumber(UnitStandState("player")) or 0
    return s >= 2
  end
  return UHCCAMM.posture == "lay"
end

local function uhccammIsSitting()
  -- Prefer a dedicated helper if the client exposes it, otherwise rely on our best-effort posture tracker.
  if UnitIsSitting then
    return UnitIsSitting("player") and true or false
  end
  if UnitStandState then
    local s = tonumber(UnitStandState("player")) or 0
    return s == 1
  end
  return UHCCAMM.posture == "sit"
end

local function uhccammStandState()
  if not UnitStandState then return nil end
  return tonumber(UnitStandState("player"))
end

local function uhccammRestoreFatigueFromDB()
  ensureDB()
  local minV = uhccammHiddenStartValue()
  local v = tonumber(UHCC_AnnoyMeMoreDB.fatigueValue)
  if v == nil then
    UHCCAMM.fatigue = minV
    UHCCAMM.exhausted = false
    UHCCAMM.exhaustedAlertLatched = false
    return
  end
  UHCCAMM.fatigue = clamp(v, minV, uhccammFatigueMax())
  UHCCAMM.exhausted = (UHCC_AnnoyMeMoreDB.exhausted == true)
  UHCCAMM.exhaustedAlertLatched = (UHCC_AnnoyMeMoreDB.exhaustedAlertLatched == true)
  -- Safety: exhausted never persists once we've reached 0 or below.
  if UHCCAMM.exhausted and (tonumber(UHCCAMM.fatigue) or 0) <= 0 then
    UHCCAMM.exhausted = false
  end
  -- Stale tired-alert latch if fatigue is back in the safe zone (same rule as runtime: 90 or below).
  if UHCCAMM.exhaustedAlertLatched and (tonumber(UHCCAMM.fatigue) or 0) <= 90 then
    UHCCAMM.exhaustedAlertLatched = false
  end
end

local function uhccammSaveFatigueToDB(now)
  ensureDB()
  UHCC_AnnoyMeMoreDB.fatigueValue = tonumber(UHCCAMM.fatigue) or uhccammHiddenStartValue()
  UHCC_AnnoyMeMoreDB.fatigueSavedAt = tonumber(now) or (GetTime and GetTime()) or 0
  UHCC_AnnoyMeMoreDB.exhausted = (UHCCAMM.exhausted == true)
  UHCC_AnnoyMeMoreDB.exhaustedAlertLatched = (UHCCAMM.exhaustedAlertLatched == true)
end

-- Forward declarations (used by slash command handler).
local createFatigueBar, updateFatigueBar

local function uhccammApplyFatigueValue(v)
  local minV = uhccammHiddenStartValue()
  local maxV = uhccammFatigueMax()
  UHCCAMM.fatigue = clamp(v, minV, maxV)
  -- Exhausted debuff only applies when overcapping past 110.
  if UHCCAMM.fatigue >= 110 then
    UHCCAMM.exhausted = true
  elseif UHCCAMM.fatigue <= 0 then
    UHCCAMM.exhausted = false
  end
  createFatigueBar()
  updateFatigueBar()
  uhccammSaveFatigueToDB(GetTime and GetTime())
end

local JUMP_FATIGUE_DEBOUNCE = 0.2
local function uhccammApplyJumpFatigue()
  if not uhccammFatigueEnabled() then return end
  local now = (GetTime and GetTime()) or 0
  if (now - (tonumber(UHCCAMM.lastJumpFatigueAt) or 0)) < JUMP_FATIGUE_DEBOUNCE then return end
  UHCCAMM.lastJumpFatigueAt = now
  local minV = uhccammHiddenStartValue()
  UHCCAMM.fatigue = clamp((tonumber(UHCCAMM.fatigue) or minV) + 1, minV, uhccammFatigueMax())
  if (not UHCCAMM.exhausted) and UHCCAMM.fatigue >= 110 then
    UHCCAMM.exhausted = true
  end
  createFatigueBar()
  updateFatigueBar()
  uhccammSaveFatigueToDB(now)
end

local UHCCAMM_SLASH_WRAPPED = false
local function uhccammTryWrapUhccSlash()
  if UHCCAMM_SLASH_WRAPPED then return true end
  if not SlashCmdList or type(SlashCmdList["UHCC"]) ~= "function" then return false end

  local prev = SlashCmdList["UHCC"]

  local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
  end

  SlashCmdList["UHCC"] = function(msg)
    local m = trim(msg)
    local low = string.lower(m)
    local n = low:match("^fatigue%s+(-?%d+)$")
    if n then
      if not uhccammFatigueEnabled() then
        print("|cffff3333UHCCAMM|r: Enable UHCC Annoy me, then Fatigue in Annoy Me More.")
        return
      end
      local iv = tonumber(n)
      if iv == nil then
        print("|cffff3333UHCCAMM|r: Usage: /uhcc fatigue n")
        return
      end
      uhccammApplyFatigueValue(iv)
      print(("|cffff3333UHCCAMM|r: Fatigue set to %d"):format(iv))
      return
    end
    return prev(msg)
  end

  UHCCAMM_SLASH_WRAPPED = true
  return true
end

local UHCCAMM_BANDAGE_SPELLIDS = {
  [3275] = true, -- Linen Bandage
  [3276] = true, -- Heavy Linen Bandage
  [3277] = true, -- Wool Bandage
  [3278] = true, -- Heavy Wool Bandage
  [7928] = true, -- Silk Bandage
  [7929] = true, -- Heavy Silk Bandage
  [10840] = true, -- Mageweave Bandage
  [10841] = true, -- Heavy Mageweave Bandage
  [18629] = true, -- Runecloth Bandage
  [18630] = true, -- Heavy Runecloth Bandage
}

local function uhccammIsInInn()
  return (IsResting and IsResting()) and true or false
end

local function uhccammIsMounted()
  return (IsMounted and IsMounted()) and true or false
end

local function uhccammSpeedBonusBySpeed(speed)
  -- Locale-free approximation:
  -- If you're moving faster than normal run speed, treat it as "speed boost active" (+1 fatigue rate).
  -- This covers mount speed and common sprint/forms/aspects without relying on buff names.
  speed = tonumber(speed) or 0
  local BASE_RUN_SPEED = 7.0
  local BOOST_THRESHOLD = BASE_RUN_SPEED * 1.12
  if speed >= BOOST_THRESHOLD then return 1 end
  return 0
end

local function uhccammIsMoving()
  if IsPlayerMoving and IsPlayerMoving() then return true end
  local speed = (GetUnitSpeed and GetUnitSpeed("player")) or 0
  speed = tonumber(speed) or 0
  return speed > 0.01
end

createFatigueBar = function()
  if UHCCAMM.bar then return UHCCAMM.bar end

  local PAD = 10
  local BAR_W, BAR_H = 240, 16
  local LABEL_H = 14

  -- Outer stone panel (padding around the bar).
  local panel = CreateFrame("Frame", "UHCCAMM_FatiguePanel", UIParent, "BackdropTemplate")
  panel:SetSize(BAR_W + PAD * 2, BAR_H + PAD * 2 + LABEL_H)
  ensureDB()
  panel:ClearAllPoints()
  panel:SetPoint(
    UHCC_AnnoyMeMoreDB.fatigueBarPoint or "TOP",
    UIParent,
    UHCC_AnnoyMeMoreDB.fatigueBarRelPoint or "TOP",
    tonumber(UHCC_AnnoyMeMoreDB.fatigueBarX) or 0,
    tonumber(UHCC_AnnoyMeMoreDB.fatigueBarY) or -120
  )
  panel:SetFrameStrata("HIGH")
  panel:SetClampedToScreen(true)
  panel:SetMovable(true)
  panel:EnableMouse(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetBackdrop({
    bgFile = "Interface\\FrameGeneral\\UI-Background-Marble",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  -- Slight transparency so it blends with the world.
  panel:SetBackdropColor(1, 1, 1, 0.65)
  panel:SetBackdropBorderColor(1, 1, 1, 0.75)

  -- No fade effects (instant show/hide).
  panel:SetAlpha(1)

  -- Drag with Alt key only.
  panel:SetScript("OnDragStart", function(self)
    if not IsAltKeyDown or not IsAltKeyDown() then return end
    self:Show()
    self:SetAlpha(1)
    self:StartMoving()
  end)
  panel:SetScript("OnDragStop", function(self)
    if self:IsMoving() then
      self:StopMovingOrSizing()
      ensureDB()
      local p, _, rp, x, y = self:GetPoint(1)
      UHCC_AnnoyMeMoreDB.fatigueBarPoint = p or "TOP"
      UHCC_AnnoyMeMoreDB.fatigueBarRelPoint = rp or "TOP"
      UHCC_AnnoyMeMoreDB.fatigueBarX = tonumber(x) or 0
      UHCC_AnnoyMeMoreDB.fatigueBarY = tonumber(y) or -120
    end
  end)

  local label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  label:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -6)
  label:SetJustifyH("LEFT")
  label:SetTextColor(1, 0.82, 0, 1)
  label:SetText("Fatigue")

  -- Inner bar container.
  local f = CreateFrame("Frame", "UHCCAMM_FatigueFrame", panel)
  f:SetSize(BAR_W, BAR_H)
  f:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -(PAD + LABEL_H))

  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(true)
  bg:SetColorTexture(0, 0, 0, 0.55)

  local bar = CreateFrame("StatusBar", nil, f)
  bar:SetAllPoints(true)
  bar:SetMinMaxValues(0, 100)
  bar:SetValue(0)
  bar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
  bar:SetStatusBarColor(0.2, 0.8, 0.2, 1)

  -- Restore the original simple bar border thickness.
  local bd = CreateFrame("Frame", nil, f, "BackdropTemplate")
  bd:SetAllPoints(true)
  bd:SetBackdrop({
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  bd:SetBackdropBorderColor(1, 1, 1, 0.6)

  panel:Hide()
  UHCCAMM.bar = panel
  UHCCAMM.status = bar
  return f
end

local function ensureExhaustedIcon()
  if UHCCAMM.exhaustedIcon then return UHCCAMM.exhaustedIcon end
  if not PlayerFrame then return nil end

  local b = CreateFrame("Button", "UHCCAMM_ExhaustedIcon", PlayerFrame)
  b:SetSize(22, 22)
  b:SetPoint("LEFT", PlayerFrame, "RIGHT", 6, 0)
  b:SetFrameStrata("HIGH")
  b:EnableMouse(true)

  local tex = b:CreateTexture(nil, "ARTWORK")
  tex:SetAllPoints(true)
  tex:SetTexture("Interface\\ICONS\\Ability_Warrior_Rampage")
  tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.icon = tex

  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Exhausted", 1, 0.82, 0, 1)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)

  b:Hide()
  UHCCAMM.exhaustedIcon = b
  return b
end

local function updateExhaustedIcon()
  local b = ensureExhaustedIcon()
  if not b then return end
  if UHCCAMM.exhausted then
    b:Show()
  else
    b:Hide()
  end
end

local function ensureExhaustedAlert()
  if UHCCAMM.exhaustedAlert then return UHCCAMM.exhaustedAlert end
  local f = CreateFrame("Frame", "UHCCAMM_ExhaustedAlert", UIParent)
  f:SetAllPoints(UIParent)
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetFrameLevel(1000)
  f:EnableMouse(false)

  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(true)
  bg:SetColorTexture(1, 0, 0, 0.0)
  f.bg = bg

  local msg = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  msg:SetPoint("CENTER", f, "CENTER", 0, 0)
  msg:SetTextColor(1, 0.1, 0.1, 1)
  msg:SetText("You are tired now, please rest")
  f.msg = msg

  local msg2 = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  msg2:SetPoint("TOP", msg, "BOTTOM", 0, -10)
  msg2:SetTextColor(1, 0.65, 0.65, 1)
  msg2:SetText("You are exhausted")
  msg2:Hide()
  f.msg2 = msg2

  f:Hide()
  UHCCAMM.exhaustedAlert = f
  return f
end

local function updateExhaustedAlert()
  local f = ensureExhaustedAlert()
  if not f then return end

  if not uhccammFatigueEnabled() then
    UHCCAMM.exhaustedAlertLatched = false
    if f.msg2 then f.msg2:Hide() end
    f:Hide()
    return
  end

  local fat = tonumber(UHCCAMM.fatigue) or 0

  -- Always tear down overlay + latch once fatigue is 90 or below (no red screen / no chat line in that band).
  if fat <= 90 then
    UHCCAMM.exhaustedAlertLatched = false
    if f.msg2 then f.msg2:Hide() end
    if f.bg then f.bg:SetColorTexture(1, 0, 0, 0.0) end
    f:Hide()
    return
  end

  -- Red overlay + "tired" from 100 fatigue upward while above 90.
  if (not UHCCAMM.exhaustedAlertLatched) and fat >= 100 then
    UHCCAMM.exhaustedAlertLatched = true
  end

  local keepShown = (UHCCAMM.exhaustedAlertLatched == true)

  if f.msg2 then
    if keepShown and (UHCCAMM.exhausted == true) then
      f.msg2:Show()
    else
      f.msg2:Hide()
    end
  end

  if keepShown then
    if not f:IsShown() then
      if print then
        print("|cffff3333UHCCAMM|r: You are tired now, please rest")
      end
    end
    f:Show()
    f:SetAlpha(1)
    if f.bg then f.bg:SetColorTexture(1, 0, 0, 0.22) end
  else
    if f.msg2 then f.msg2:Hide() end
    f:Hide()
  end
end

local function setFatiguePanelShown(shown)
  if not UHCCAMM.bar then return end
  shown = shown and true or false
  if UHCCAMM.barTargetShown == shown then return end
  UHCCAMM.barTargetShown = shown

  local panel = UHCCAMM.bar
  if shown then
    panel:Show()
    panel:SetAlpha(1)
  else
    panel:Hide()
  end
end

local function ensureSpeedDebugText()
  if UHCCAMM.speedFs then return UHCCAMM.speedFs end

  local f = CreateFrame("Frame", "UHCCAMM_SpeedDebugFrame", UIParent)
  f:SetPoint("TOP", UIParent, "TOP", 0, -20)
  f:SetSize(360, 54)
  f:SetFrameStrata("HIGH")

  local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  fs:SetAllPoints(true)
  fs:SetJustifyH("CENTER")
  fs:SetJustifyV("TOP")
  fs:SetNonSpaceWrap(false)
  fs:SetText("SPD: 0")

  UHCCAMM.speedFrame = f
  UHCCAMM.speedFs = fs
  return fs
end

local function updateSpeedDebugText()
  if not uhccammDebugEnabled() then
    if UHCCAMM.speedFrame then UHCCAMM.speedFrame:Hide() end
    return
  end

  local fs = ensureSpeedDebugText()
  if not fs then return end

  local d = UHCCAMM.debug or {}
  local spd = tonumber(d.speed) or 0
  local rounded = math.floor(spd + 0.5)
  local delta = tonumber(d.delta) or 0
  local restBonus = tonumber(d.restBonus) or 0
  local spdBonus = tonumber(d.speedBonus) or 0
  local s = ("SPD: %d  Δ: %.3f/tick  F: %.1f\nMOV:%s RUN:%s MNT:%s CMB:%s REST:%s SIT:%s LAY:%s POS:%s\nUST:%s UIS:%s ST:%s EMO:%s\nREST+:%d  SPD+:%d  HEAL:%s\nCLEU:%s"):format(
    rounded,
    delta,
    tonumber(UHCCAMM.fatigue) or 0,
    d.moving and "1" or "0",
    d.running and "1" or "0",
    d.mounted and "1" or "0",
    d.combat and "1" or "0",
    d.resting and "1" or "0",
    d.sitting and "1" or "0",
    d.laying and "1" or "0",
    tostring(d.posture or ""),
    d.hasUnitStandState and "1" or "0",
    d.hasUnitIsSitting and "1" or "0",
    tostring(d.stand or ""),
    tostring(d.lastEmote or ""),
    restBonus,
    spdBonus,
    d.lastHealText and tostring(d.lastHealText) or "",
    d.lastCleuText and tostring(d.lastCleuText) or ""
  )
  fs:SetText(s)
  if UHCCAMM.speedFrame then UHCCAMM.speedFrame:Show() end
end

updateFatigueBar = function()
  if not UHCCAMM.status then return end
  local v = clamp(UHCCAMM.fatigue, 0, 100) -- visual clamp
  UHCCAMM.status:SetValue(v)
  -- Color: blue by default, turns red late.
  do
    local r, g, b = 0.25, 0.55, 1.0 -- blue
    if v >= 70 and v < 90 then
      -- blue -> orange
      local t = (v - 70) / 20
      r = 0.25 + (1.0 - 0.25) * t
      g = 0.55 + (0.45 - 0.55) * t
      b = 1.0 + (0.05 - 1.0) * t
    elseif v >= 90 then
      -- orange -> red
      local t = (v - 90) / 10
      r = 1.0
      g = 0.45 + (0.1 - 0.45) * t
      b = 0.05 + (0.05 - 0.05) * t
    end
    UHCCAMM.status:SetStatusBarColor(clamp(r, 0, 1), clamp(g, 0, 1), clamp(b, 0, 1), 1)
  end

  -- Delay appearance: fatigue starts at -playerLevel and the panel only shows when it is strictly > 0.
  local enabled = uhccammFatigueEnabled()
  setFatiguePanelShown(enabled and (tonumber(UHCCAMM.fatigue) or 0) > 0)
  updateExhaustedIcon()
  updateExhaustedAlert()
end

local function uhccammCaptureDebugSnapshot()
  local WALK_RUN_THRESHOLD = 4.0
  local speed = (GetUnitSpeed and GetUnitSpeed("player")) or 0
  speed = tonumber(speed) or 0
  local moving = uhccammIsMoving()
  UHCCAMM.isRunningNow = (speed > WALK_RUN_THRESHOLD) or (uhccammIsMounted() and moving)

  local dbg = UHCCAMM.debug or {}
  dbg.speed = speed
  dbg.moving = moving
  dbg.running = UHCCAMM.isRunningNow
  dbg.mounted = uhccammIsMounted()
  dbg.combat = uhccammIsInCombat()
  dbg.resting = uhccammIsInInn()
  dbg.hasUnitStandState = UnitStandState and true or false
  dbg.hasUnitIsSitting = UnitIsSitting and true or false
  dbg.stand = uhccammStandState()
  dbg.sitting = uhccammIsSitting()
  dbg.laying = uhccammIsLaying()
  dbg.posture = UHCCAMM.posture
  dbg.lastEmote = UHCCAMM.lastEmoteToken
  dbg.lastHealText = dbg.lastHealText or nil
  dbg.lastCleuText = dbg.lastCleuText or nil
  dbg.delta = 0
  dbg.restBonus = 0
  dbg.speedBonus = 0
  UHCCAMM.debug = dbg
  return speed, moving
end

local function fatigueTick60()
  --[[ Debug-only tick without Fatigue (disabled while uhccammDebugEnabled returns false):
  if uhccammDebugEnabled() and not uhccammFatigueEnabled() then
    uhccammCaptureDebugSnapshot()
    updateSpeedDebugText()
    return
  end
  ]]

  if not uhccammFatigueEnabled() then
    UHCCAMM.fatigue = uhccammHiddenStartValue()
    updateFatigueBar()
    return
  end

  -- Very simple v1 (rates are per second, applied at 60Hz):
  -- - running: 60s of running fills 100%  => +100/60 per sec
  -- - walking: slower than running (currently 90s to fill 100%) => +100/90 per sec
  -- - standing still: recover at the same speed as running by default (60s from 100 to 0) => -100/60 per sec
  local STEP = 1 / 60
  local RUN_PER_SEC = 100 / 60
  local WALK_PER_SEC = 100 / 90
  local REST_PER_SEC = 100 / 60
  local EXH_DELTA = 0.5 -- debuff: +0.5 fatigue, -0.5 regen

  local speed, moving = uhccammCaptureDebugSnapshot()

  if not moving then
    -- In combat, fatigue does not go down (even if you're standing still).
    if uhccammIsInCombat() then
      -- no-op
      UHCCAMM.debug.delta = 0
    else
      -- Bonus recovery conditions (+1 each, relative to base recovery).
      local bonus = 0
      if uhccammIsEatingOrDrinking() then bonus = bonus + 2 end
      if uhccammIsSitting() then bonus = bonus + 1 end
      if uhccammIsLaying() then bonus = bonus + 1 end
      if uhccammIsInInn() then bonus = bonus + 1 end
      local regen = REST_PER_SEC + bonus
      if UHCCAMM.exhausted then
        regen = regen - EXH_DELTA
        if regen < 0 then regen = 0 end
      end
      local delta = -(regen * STEP)
      UHCCAMM.debug.restBonus = bonus
      UHCCAMM.debug.delta = delta
      UHCCAMM.fatigue = UHCCAMM.fatigue + delta

      -- Keep recovering below 0 down to -playerLevel (hidden), do NOT snap to avoid "stop 1s to reset" abuse.
      UHCCAMM.fatigue = clamp(UHCCAMM.fatigue, uhccammHiddenStartValue(), uhccammFatigueMax())

      -- Exhausted ends at 0 (not at -playerLevel).
      if UHCCAMM.exhausted and UHCCAMM.fatigue <= 0 then
        UHCCAMM.exhausted = false
      end
    end
  else
    local bonus = uhccammSpeedBonusBySpeed(speed)
    UHCCAMM.debug.speedBonus = bonus
    if UHCCAMM.isRunningNow then
      local rate = RUN_PER_SEC + bonus + (UHCCAMM.exhausted and EXH_DELTA or 0)
      local delta = (rate * STEP)
      UHCCAMM.debug.delta = delta
      UHCCAMM.fatigue = clamp(UHCCAMM.fatigue + delta, uhccammHiddenStartValue(), uhccammFatigueMax())
    else
      local rate = WALK_PER_SEC + bonus + (UHCCAMM.exhausted and EXH_DELTA or 0)
      local delta = (rate * STEP)
      UHCCAMM.debug.delta = delta
      UHCCAMM.fatigue = clamp(UHCCAMM.fatigue + delta, uhccammHiddenStartValue(), uhccammFatigueMax())
    end

    -- Exhausted debuff applies only when reaching the max (110).
    if (not UHCCAMM.exhausted) and UHCCAMM.fatigue >= 110 then
      UHCCAMM.exhausted = true
    end
  end

  createFatigueBar()
  updateFatigueBar()
  updateSpeedDebugText()
end

-- UHCC never refreshes `disabled` on external checkboxes when "Annoy me" toggles (unlike Money Management).
-- We mirror that behavior: sync enable state + grey text, and clear our toggles when Annoy me turns off.
local uhccammAnnoyCbHooked = nil

local function uhccammSyncAnnoyDependentSettingsControls()
  ensureDB()
  local mf = _G.UHCC and UHCC.mainFrame
  if not mf or type(mf.UHCC_settingsControls) ~= "table" then return end

  local on = uhccParentAnnoyEnabled()
  local keys = { "UHCCAMM-FATIGUE" } -- "UHCCAMM-DEBUG" removed while debug mode is hidden

  if not on then
    UHCC_AnnoyMeMoreDB.fatigueEnabled = false
    UHCC_AnnoyMeMoreDB.debugEnabled = false
    UHCCAMM.fatigue = uhccammHiddenStartValue()
    if UHCCAMM.bar then setFatiguePanelShown(false) end
    if UHCCAMM.speedFrame then UHCCAMM.speedFrame:Hide() end
    createFatigueBar()
    updateFatigueBar()
  end

  for _, key in ipairs(keys) do
    local cb = mf.UHCC_settingsControls[key]
    if cb and cb.SetEnabled then
      cb:SetEnabled(on)
      if cb.Text and cb.Text.SetTextColor then
        if on then
          cb.Text:SetTextColor(1, 1, 1, 1)
        else
          cb.Text:SetTextColor(0.7, 0.7, 0.7, 1)
        end
      end
      if cb.SetChecked and key == "UHCCAMM-FATIGUE" then
        cb:SetChecked(on and (UHCC_AnnoyMeMoreDB.fatigueEnabled == true))
      end
    end
  end
end

local function uhccammHookAnnoyCheckboxIfNeeded()
  local mf = _G.UHCC and UHCC.mainFrame
  local annoy = mf and mf.UHCC_settingsControls and mf.UHCC_settingsControls["SETTINGS-ANNOY"]
  if not annoy then return end
  if annoy == uhccammAnnoyCbHooked then return end
  uhccammAnnoyCbHooked = annoy
  annoy:HookScript("OnClick", function()
    local function run()
      uhccammSyncAnnoyDependentSettingsControls()
    end
    if C_Timer and C_Timer.After then
      C_Timer.After(0, run)
    else
      run()
    end
  end)
end

local function uhccammWrapUhccRebuildSettingsTabOnce()
  local mf = _G.UHCC and UHCC.mainFrame
  if not mf or mf.UHCCAMM_RebuildWrapped then return end
  local orig = mf.UHCC_RebuildSettingsTab
  if type(orig) ~= "function" then return end
  mf.UHCCAMM_RebuildWrapped = true
  mf.UHCC_RebuildSettingsTab = function(self, ...)
    local ret = { orig(self, ...) }
    uhccammAnnoyCbHooked = nil
    uhccammHookAnnoyCheckboxIfNeeded()
    uhccammSyncAnnoyDependentSettingsControls()
    return unpack(ret)
  end
end

local function uhccammTryInstallUhccSettingsHooksOnce()
  local mf = _G.UHCC and UHCC.mainFrame
  if not mf then return false end
  uhccammWrapUhccRebuildSettingsTabOnce()
  uhccammHookAnnoyCheckboxIfNeeded()
  uhccammSyncAnnoyDependentSettingsControls()
  return true
end

local function registerWithUHCC()
  if not _G.UHCC or type(_G.UHCC.RegisterSettingsProvider) ~= "function" then return false end
  ensureDB()

  _G.UHCC:RegisterSettingsProvider("Annoy Me More", function()
    ensureDB()
    local parentAnnoy = uhccParentAnnoyEnabled()
    return {
      {
        kind = "checkbox",
        key = "UHCCAMM-FATIGUE",
        label = "Fatigue",
        description = "You’ll need to rest or run less.",
        get = function() return UHCC_AnnoyMeMoreDB.fatigueEnabled end,
        set = function(v)
          UHCC_AnnoyMeMoreDB.fatigueEnabled = v and true or false
          if not UHCC_AnnoyMeMoreDB.fatigueEnabled then
            UHCCAMM.fatigue = uhccammHiddenStartValue()
            if UHCCAMM.bar then setFatiguePanelShown(false) end
            if UHCCAMM.speedFrame then UHCCAMM.speedFrame:Hide() end
          end
        end,
        disabled = not parentAnnoy,
      },
      --[[ Debug checkbox (hidden): re-enable with uhccammDebugEnabled() above.
      {
        kind = "checkbox",
        key = "UHCCAMM-DEBUG",
        label = "Debug",
        description = "Show speed/fatigue debug overlay (works without Fatigue).",
        get = function() return UHCC_AnnoyMeMoreDB.debugEnabled end,
        set = function(v)
          UHCC_AnnoyMeMoreDB.debugEnabled = v and true or false
          if not UHCC_AnnoyMeMoreDB.debugEnabled then
            if UHCCAMM.speedFrame then UHCCAMM.speedFrame:Hide() end
          end
        end,
        disabled = not parentAnnoy,
      },
      ]],
      {
        kind = "info",
        text = "Fatigue requires Annoy me in the main UHCC settings.",
      },
    }
  end)

  return true
end

-- Register after dependencies are loaded.
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
  registerWithUHCC()

  if type(hooksecurefunc) == "function" and _G.UHCC and type(UHCC.ToggleMainFrame) == "function" then
    hooksecurefunc(UHCC, "ToggleMainFrame", function()
      local function run()
        uhccammTryInstallUhccSettingsHooksOnce()
      end
      if C_Timer and C_Timer.After then
        C_Timer.After(0, run)
      else
        run()
      end
    end)
  end
  do
    local poll = CreateFrame("Frame")
    local acc = 0
    poll:SetScript("OnUpdate", function(self, elapsed)
      acc = acc + (tonumber(elapsed) or 0)
      if uhccammTryInstallUhccSettingsHooksOnce() then
        self:SetScript("OnUpdate", nil)
        return
      end
      if acc >= 90 then
        self:SetScript("OnUpdate", nil)
      end
    end)
  end
  uhccammTryInstallUhccSettingsHooksOnce()

  -- Restore last fatigue value (1s granularity persistence).
  uhccammRestoreFatigueFromDB()
    -- Sync exhausted icon immediately after restore.
    createFatigueBar()
    updateFatigueBar()

  -- Extend /uhcc with: /uhcc fatigue n
  do
    if not uhccammTryWrapUhccSlash() then
      -- Retry a few times in case another addon reassigns /uhcc during login.
      local tries = 0
      local rf = CreateFrame("Frame")
      rf:SetScript("OnUpdate", function(self, elapsed)
        tries = tries + (tonumber(elapsed) or 0)
        if tries < 0.25 then return end
        tries = 0
        if uhccammTryWrapUhccSlash() then
          self:SetScript("OnUpdate", nil)
        end
      end)
    end
  end

  -- Best-effort posture tracking (locale-free):
  -- - /sit and the sit keybind call SitStandOrDescendStart()
  -- - /lay calls DoEmote("LAY")
  -- We maintain a local posture state and reset it on movement/mount/combat.
  local function setPosture(p)
    if p ~= "stand" and p ~= "sit" and p ~= "lay" then p = "stand" end
    UHCCAMM.posture = p
  end

  if type(hooksecurefunc) == "function" then
    if type(SitStandOrDescendStart) == "function" then
      hooksecurefunc("SitStandOrDescendStart", function()
        if UHCCAMM.posture == "sit" then
          setPosture("stand")
        else
          setPosture("sit")
        end
      end)
    end
    if type(DoEmote) == "function" then
      hooksecurefunc("DoEmote", function(token)
        token = tostring(token or ""):upper()
        UHCCAMM.lastEmoteToken = token
        if token == "LAY" then
          setPosture("lay")
        elseif token == "LAYDOWN" or token == "SLEEP" then
          setPosture("lay")
        elseif token == "SIT" then
          setPosture("sit")
        elseif token == "STAND" then
          setPosture("stand")
        end
      end)
    end
    if type(JumpOrAscendStart) == "function" then
      hooksecurefunc("JumpOrAscendStart", function()
        uhccammApplyJumpFatigue()
      end)
    end
  end

  local pf = CreateFrame("Frame")
  pf:RegisterEvent("PLAYER_STARTED_MOVING")
  pf:RegisterEvent("PLAYER_REGEN_DISABLED")
  pf:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
  pf:SetScript("OnEvent", function()
    setPosture("stand")
  end)

  -- Consumable detection (locale-free via spellID).
  local cf = CreateFrame("Frame")
  cf:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
  cf:SetScript("OnEvent", function(_, _, unit, _, spellId)
    if unit ~= "player" then return end
    spellId = tonumber(spellId)
    if not spellId then return end
    local dbg = UHCCAMM.debug or {}
    if UHCCAMM_BANDAGE_SPELLIDS[spellId] then
      dbg.lastHealText = ("bandage:%d"):format(spellId)
      dbg.lastHealAt = (GetTime and GetTime()) or 0
      UHCCAMM.debug = dbg
    end
  end)

  -- Generic "player received healing" detection (locale-free).
  -- This catches potions, bandages, spells, and periodic heals.
  local playerGUID = UnitGUID and UnitGUID("player") or nil
  local hf = CreateFrame("Frame")
  hf:RegisterEvent("PLAYER_ENTERING_WORLD")
  hf:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
  hf:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
      playerGUID = UnitGUID and UnitGUID("player") or playerGUID
      return
    end
    if not playerGUID then
      playerGUID = UnitGUID and UnitGUID("player") or nil
      if not playerGUID then return end
    end

    local info = { CombatLogGetCurrentEventInfo() }
    local subevent = info[2]
    local sourceGUID = info[4]
    local destGUID = info[8]
    local spellId = tonumber(info[12]) or 0

    if destGUID ~= playerGUID then return end

    -- Always capture last CLEU targeting the player (debug).
    do
      local amt = tonumber(info[15]) -- for heals this is amount; for others it's often nil
      local dbg = UHCCAMM.debug or {}
      dbg.lastCleuText = ("%s id:%d a:%s"):format(tostring(subevent or "?"), spellId, amt ~= nil and tostring(amt) or "-")
      UHCCAMM.debug = dbg
    end

    if subevent ~= "SPELL_HEAL" and subevent ~= "SPELL_PERIODIC_HEAL" then return end

    local amount = tonumber(info[15]) or 0
    local overheal = tonumber(info[16]) or 0
    local effective = amount - overheal
    local dbg = UHCCAMM.debug or {}
    dbg.lastHealText = ("+%d (oh:%d) id:%d"):format(amount, overheal, spellId)
    dbg.lastHealAt = (GetTime and GetTime()) or 0
    UHCCAMM.debug = dbg

    -- Healing reduces fatigue by 10, but only if it actually heals (not full HP overheal).
    -- For HoTs, only the "first tick" counts: we apply once per spellId+source within a short window.
    if uhccammFatigueEnabled() then
      if effective <= 0 then return end
      local apply = false
      if subevent == "SPELL_HEAL" then
        apply = true
      else
        local now = (GetTime and GetTime()) or 0
        local key = tostring(spellId) .. ":" .. tostring(sourceGUID or "?")
        local last = tonumber(UHCCAMM.hotFirstTickAt[key]) or -999
        -- Window long enough to ignore subsequent ticks, short enough to allow refresh/re-application later.
        if (now - last) >= 6 then
          UHCCAMM.hotFirstTickAt[key] = now
          apply = true
        end
      end

      if apply then
        local minV = uhccammHiddenStartValue()
        UHCCAMM.fatigue = clamp((tonumber(UHCCAMM.fatigue) or minV) - 10, minV, uhccammFatigueMax())
        createFatigueBar()
        updateFatigueBar()
      end
    end
  end)
end)

-- 60 FPS-style fatigue loop (quantized). When debug mode is re-enabled, restore dbg-only tick branch below.
local ticker = CreateFrame("Frame")
ticker.UHCCAMM_saveAcc = 0
ticker.UHCCAMM_idleAcc = 0
ticker:SetScript("OnUpdate", function(_, elapsed)
  elapsed = tonumber(elapsed) or 0
  local fatOn = uhccammFatigueEnabled()

  if not fatOn then
    ticker.UHCCAMM_idleAcc = (ticker.UHCCAMM_idleAcc or 0) + elapsed
    if ticker.UHCCAMM_idleAcc >= 0.2 then
      ticker.UHCCAMM_idleAcc = 0
      createFatigueBar()
      updateFatigueBar()
      if UHCCAMM.speedFrame then UHCCAMM.speedFrame:Hide() end
    end
    return
  end
  ticker.UHCCAMM_idleAcc = 0

  --[[ Debug overlay tick without Fatigue:
  local dbgWanted = uhccammDebugEnabled()
  if dbgWanted and not fatOn then
    ticker.UHCCAMM_dbgAcc = (ticker.UHCCAMM_dbgAcc or 0) + elapsed
    local dbgStep = 1 / 20
    while ticker.UHCCAMM_dbgAcc >= dbgStep do
      ticker.UHCCAMM_dbgAcc = ticker.UHCCAMM_dbgAcc - dbgStep
      fatigueTick60()
    end
    return
  end
  ]]

  UHCCAMM.tickAcc = (UHCCAMM.tickAcc or 0) + elapsed
  ticker.UHCCAMM_saveAcc = (ticker.UHCCAMM_saveAcc or 0) + elapsed
  local step = 1 / 60
  while UHCCAMM.tickAcc >= step do
    UHCCAMM.tickAcc = UHCCAMM.tickAcc - step
    fatigueTick60()
  end

  if (ticker.UHCCAMM_saveAcc or 0) >= 1 then
    ticker.UHCCAMM_saveAcc = 0
    uhccammSaveFatigueToDB(GetTime and GetTime())
  end
end)
