-- NameplateSCT-Vanilla v0.5.0b-test
-- Development build for WoW 1.12.1.
-- Native nameplate discovery works without enhanced client APIs. Enhanced GUID
-- resolution is disabled by default and only enabled through /np native off.

NameplateSCTVanilla = NameplateSCTVanilla or {}
local NSCT = NameplateSCTVanilla

local VERSION = "0.5.0b-test"
local PREFIX = "|cff33ff99NSCT-V|r"
local MAX_LOG = 250
local MAX_ERRORS = 50

-- v0.5.0 visual focus policy. These are internal defaults for now and will
-- become SavedVariables-backed settings in the configuration milestone.
local TARGET_SCALE = 1.00
local TARGET_ALPHA = 1.00
local TARGET_STRATA = "HIGH"
local OFFTARGET_SCALE = 0.75
local OFFTARGET_ALPHA = 0.72
local OFFTARGET_STRATA = "MEDIUM"

local platesByGUID = {}
local guidByPlate = {}
local knownPlates = {}
local visiblePlatesByName = {}
local plateNameByPlate = {}
local plateNameRegion = {}
local plateGeneration = {}
local hookedPlates = {}
local fontPool = {}
local activeTexts = {}
local dotBindings = {}
local scanElapsed = 0
local initializedChildren = 0
local rawCombatLogRegistered = nil
local nativeCombatEventCount = 0
local nativeOptionalCombatEventCount = 0
local nativeCombatBackendAvailable = nil
local nativePatternCache = {}
local oldErrorHandler = nil
local inErrorHandler = nil
local playerGUID = nil
local spellTextures = {}
local arcDirection = 1
local fontTestFrame = nil
local fontTestHideAt = nil
local sizeTestFrame = nil
local sizeTestHideAt = nil

local function Chat(msg)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. ": " .. tostring(msg))
  end
end

local function EnsureDB()
  if not NameplateSCTVanillaDB then NameplateSCTVanillaDB = {} end
  if NameplateSCTVanillaDB.enabled == nil then NameplateSCTVanillaDB.enabled = 1 end
  if NameplateSCTVanillaDB.debug == nil then NameplateSCTVanillaDB.debug = 1 end
  if NameplateSCTVanillaDB.autoDisplay == nil then NameplateSCTVanillaDB.autoDisplay = 1 end
  -- Native-only is the default so enhanced client APIs never influence addon
  -- behavior unless the user explicitly opts in for comparison/debugging.
  if NameplateSCTVanillaDB.forceNative == nil then NameplateSCTVanillaDB.forceNative = 1 end
  if not NameplateSCTVanillaDebug then NameplateSCTVanillaDebug = {} end
  if not NameplateSCTVanillaDebug.log then NameplateSCTVanillaDebug.log = {} end
  if not NameplateSCTVanillaDebug.errors then NameplateSCTVanillaDebug.errors = {} end
end

local function PushLimited(tbl, value, maxn)
  table.insert(tbl, value)
  while table.getn(tbl) > maxn do
    table.remove(tbl, 1)
  end
end

local function DebugLog(kind, msg)
  EnsureDB()
  local line = string.format("%.3f [%s] %s", GetTime() or 0, tostring(kind), tostring(msg))
  PushLimited(NameplateSCTVanillaDebug.log, line, MAX_LOG)
end

local function CaptureError(err)
  EnsureDB()
  local stack = ""
  if debugstack then
    stack = debugstack(2, 20, 20) or ""
  end
  local record = string.format("%.3f ERROR: %s\n%s", GetTime() or 0, tostring(err), tostring(stack))
  PushLimited(NameplateSCTVanillaDebug.errors, record, MAX_ERRORS)
  DebugLog("ERROR", tostring(err))
end

local function InstallErrorCapture()
  if not geterrorhandler or not seterrorhandler then
    DebugLog("ERRORCAP", "geterrorhandler/seterrorhandler unavailable")
    return
  end
  oldErrorHandler = geterrorhandler()
  seterrorhandler(function(err)
    if not inErrorHandler then
      inErrorHandler = 1
      CaptureError(err)
      inErrorHandler = nil
    end
    if oldErrorHandler then oldErrorHandler(err) end
  end)
  DebugLog("ERRORCAP", "global Lua error capture installed")
end

local function IsGUID(value)
  if type(value) ~= "string" then return nil end
  if string.find(value, "^0x[%x]+$") then return 1 end
  return nil
end

local function NativeOnlyEnabled()
  -- Default to native-only even before SavedVariables are available. A stored
  -- value of 0 is the only explicit opt-in to enhanced client APIs.
  return not (NameplateSCTVanillaDB and NameplateSCTVanillaDB.forceNative == 0)
end

local function GetGUID(unit)
  if NativeOnlyEnabled() then return nil end
  if not unit then return nil end

  -- Some 1.12-compatible clients expose UnitGUID directly.
  if UnitGUID then
    local ok, guid = pcall(UnitGUID, unit)
    if ok and IsGUID(guid) then return guid end
  end

  -- Other enhanced 1.12 clients return a GUID as UnitExists' second value.
  -- Stock Vanilla only returns the existence flag, so this safely falls back.
  if UnitExists then
    local ok, exists, guid = pcall(UnitExists, unit)
    if ok and exists and IsGUID(guid) then return guid end
  end
  return nil
end

local function CheckRegionForNameplateBorder(region)
  if region and region.GetObjectType and region.GetTexture and region:GetObjectType() == "Texture" then
    return region:GetTexture() == "Interface\\Tooltips\\Nameplate-Border"
  end
  return nil
end

local function IsNamePlate(frame)
  if not frame or not frame.GetObjectType then return nil end
  local objectType = frame:GetObjectType()
  if objectType ~= "Frame" and objectType ~= "Button" then return nil end

  -- Vanilla's native nameplate has this border texture among its first regions.
  -- Avoid allocating a temporary regions table on every scan.
  local r1, r2, r3, r4, r5, r6 = frame:GetRegions()
  if CheckRegionForNameplateBorder(r1) then return 1 end
  if CheckRegionForNameplateBorder(r2) then return 1 end
  if CheckRegionForNameplateBorder(r3) then return 1 end
  if CheckRegionForNameplateBorder(r4) then return 1 end
  if CheckRegionForNameplateBorder(r5) then return 1 end
  if CheckRegionForNameplateBorder(r6) then return 1 end
  return nil
end

local function PlateGUID(plate)
  if NativeOnlyEnabled() then return nil end
  if not plate or not plate.GetName then return nil end
  -- Enhanced clients may expose the represented unit GUID through GetName(1).
  -- Stock Vanilla may simply ignore the extra argument, so validate the result
  -- strictly before treating it as an identity.
  local ok, guid = pcall(function() return plate:GetName(1) end)
  if ok and IsGUID(guid) then return guid end
  return nil
end

local function FindPlateNameRegion(plate)
  if not plate then return nil end
  local cached = plateNameRegion[plate]
  if cached then return cached end

  local r1, r2, r3, r4, r5, r6 = plate:GetRegions()
  -- Native 1.12 nameplates normally expose the unit name as region 3.
  if r3 and r3.GetObjectType and r3:GetObjectType() == "FontString" and r3.GetText then
    plateNameRegion[plate] = r3
    return r3
  end

  -- Conservative fallback for clients/addons that preserve the native border
  -- but alter region order. Prefer a non-empty, non-level FontString.
  local regions = { r1, r2, r3, r4, r5, r6 }
  local i
  for i = 1, table.getn(regions) do
    local region = regions[i]
    if region and region.GetObjectType and region:GetObjectType() == "FontString" and region.GetText then
      local text = region:GetText()
      if text and text ~= "" and text ~= "??" and not string.find(text, "^%d+$") then
        plateNameRegion[plate] = region
        return region
      end
    end
  end
  return nil
end

local function ReadPlateName(plate)
  local region = FindPlateNameRegion(plate)
  if not region or not region.GetText then return nil end
  local name = region:GetText()
  if name and name ~= "" then return name end
  return nil
end

local function RemovePlateNameIndex(plate)
  local oldName = plateNameByPlate[plate]
  if not oldName then return end
  local set = visiblePlatesByName[oldName]
  if set then
    set[plate] = nil
    if not next(set) then visiblePlatesByName[oldName] = nil end
  end
  plateNameByPlate[plate] = nil
end

local function IndexPlateName(plate, name)
  if not plate then return end
  local oldName = plateNameByPlate[plate]
  if oldName == name then return end
  if oldName then RemovePlateNameIndex(plate) end
  if not name or name == "" then return end

  if not visiblePlatesByName[name] then visiblePlatesByName[name] = {} end
  visiblePlatesByName[name][plate] = 1
  plateNameByPlate[plate] = name
end

-- Native Vanilla periodic combat messages identify DoT destinations by unit
-- name only. Remember the exact native plate selected when a harmful aura is
-- applied so later ticks can stay attached even when other same-named units
-- are visible. A binding is valid only for the visibility generation in which
-- it was learned; recycled/hidden plates are never reused implicitly.
local function GetDotBucket(spell, targetName, create)
  if not spell or spell == "" or not targetName or targetName == "" then return nil end
  local byName = dotBindings[spell]
  if not byName and create then
    byName = {}
    dotBindings[spell] = byName
  end
  if not byName then return nil end

  local bucket = byName[targetName]
  if not bucket and create then
    bucket = {}
    byName[targetName] = bucket
  end
  return bucket
end

local function RemoveEmptyDotBucket(spell, targetName)
  local byName = dotBindings[spell]
  if not byName then return end
  local bucket = byName[targetName]
  if bucket and not next(bucket) then
    byName[targetName] = nil
  end
  if not next(byName) then
    dotBindings[spell] = nil
  end
end

local function PruneDotBucket(spell, targetName)
  local bucket = GetDotBucket(spell, targetName, nil)
  if not bucket then return nil, 0 end

  local count = 0
  local invalid = {}
  local plate, entry
  for plate, entry in pairs(bucket) do
    local valid = plate
      and plate.IsShown and plate:IsShown()
      and plateNameByPlate[plate] == targetName
      and (plateGeneration[plate] or 0) == (entry.generation or -1)
    if valid then
      count = count + 1
    else
      table.insert(invalid, plate)
    end
  end

  local i
  for i = 1, table.getn(invalid) do
    bucket[invalid[i]] = nil
  end

  RemoveEmptyDotBucket(spell, targetName)
  return GetDotBucket(spell, targetName, nil), count
end

local function BindDotTarget(spell, targetName, plate, resolutionMode)
  if not spell or not targetName or not plate then return nil end
  local bucket = GetDotBucket(spell, targetName, 1)
  bucket[plate] = {
    generation = plateGeneration[plate] or 0,
    boundAt = GetTime(),
    resolutionMode = resolutionMode,
  }

  local _, count = PruneDotBucket(spell, targetName)
  DebugLog("DOTBIND", "spell=" .. tostring(spell) .. " name=" .. tostring(targetName) .. " mode=" .. tostring(resolutionMode) .. " generation=" .. tostring(plateGeneration[plate] or 0) .. " bindings=" .. tostring(count))
  return 1
end

local function RemoveDotBindingsForPlate(plate, reason)
  if not plate then return end
  local removed = 0
  local emptySpells = {}
  local spell, byName
  for spell, byName in pairs(dotBindings) do
    local emptyNames = {}
    local targetName, bucket
    for targetName, bucket in pairs(byName) do
      if bucket[plate] then
        bucket[plate] = nil
        removed = removed + 1
      end
      if not next(bucket) then table.insert(emptyNames, targetName) end
    end
    local i
    for i = 1, table.getn(emptyNames) do
      byName[emptyNames[i]] = nil
    end
    if not next(byName) then table.insert(emptySpells, spell) end
  end

  local i
  for i = 1, table.getn(emptySpells) do
    dotBindings[emptySpells[i]] = nil
  end

  if removed > 0 then
    DebugLog("DOTDROP", "plate=" .. tostring(plateNameByPlate[plate] or ReadPlateName(plate)) .. " bindings=" .. tostring(removed) .. " reason=" .. tostring(reason))
  end
end

local function ResolveDotTarget(spell, targetName)
  local bucket, count = PruneDotBucket(spell, targetName)
  if not bucket or count == 0 then
    return nil, nil, "none", 0
  end
  if count > 1 then
    return nil, nil, "ambiguous", count
  end

  local plate
  for plate in pairs(bucket) do
    return plate, "dot-binding", "resolved", 1
  end
  return nil, nil, "none", 0
end

local function CountDotBindings()
  local buckets = 0
  local entries = 0
  local ambiguous = 0
  local spell, byName
  for spell, byName in pairs(dotBindings) do
    local targetName, bucket
    for targetName, bucket in pairs(byName) do
      local count = 0
      local plate, entry
      for plate, entry in pairs(bucket) do
        if plate
          and plate.IsShown and plate:IsShown()
          and plateNameByPlate[plate] == targetName
          and (plateGeneration[plate] or 0) == (entry.generation or -1)
        then
          count = count + 1
        end
      end
      if count > 0 then
        buckets = buckets + 1
        entries = entries + count
        if count > 1 then ambiguous = ambiguous + 1 end
      end
    end
  end
  return buckets, entries, ambiguous
end

local function UnbindPlate(plate)
  if not plate then return end
  local oldGUID = guidByPlate[plate]
  if oldGUID then
    if platesByGUID[oldGUID] == plate then
      platesByGUID[oldGUID] = nil
    end
    guidByPlate[plate] = nil
  end
end

local function BindPlateGUID(plate, guid)
  if not plate then return end

  local oldGUID = guidByPlate[plate]
  if oldGUID and oldGUID ~= guid then
    if platesByGUID[oldGUID] == plate then
      platesByGUID[oldGUID] = nil
    end
    guidByPlate[plate] = nil
    DebugLog("PLATEGUID", "recycled plate old=" .. tostring(oldGUID) .. " new=" .. tostring(guid))
  end

  if not guid then return end

  local oldPlate = platesByGUID[guid]
  if oldPlate and oldPlate ~= plate and guidByPlate[oldPlate] == guid then
    guidByPlate[oldPlate] = nil
  end

  platesByGUID[guid] = plate
  guidByPlate[plate] = guid
end

local function RefreshPlateIdentity(plate)
  if not plate then return end
  knownPlates[plate] = 1

  if not plate.IsShown or not plate:IsShown() then
    RemoveDotBindingsForPlate(plate, "plate-hidden")
    RemovePlateNameIndex(plate)
    UnbindPlate(plate)
    return
  end

  IndexPlateName(plate, ReadPlateName(plate))

  local guid = PlateGUID(plate)
  if guid then
    BindPlateGUID(plate, guid)
  elseif guidByPlate[plate] then
    -- A recycled/reshown frame without a currently valid GUID must never retain
    -- the previous unit's enhanced identity.
    UnbindPlate(plate)
  end
end

local function HookFrameScript(frame, scriptName, callback)
  if not frame or not frame.GetScript or not frame.SetScript then return end
  local previous = frame:GetScript(scriptName)
  frame:SetScript(scriptName, function(a1, a2, a3, a4, a5, a6, a7, a8, a9)
    if previous then previous(a1, a2, a3, a4, a5, a6, a7, a8, a9) end
    callback(frame)
  end)
end

local function OnNativePlateShow(plate)
  plateGeneration[plate] = (plateGeneration[plate] or 0) + 1
  -- Clear any identity from the previous visibility cycle before reading the
  -- frame again. The periodic refresh will pick up name text if Blizzard fills
  -- it a moment after OnShow.
  RemoveDotBindingsForPlate(plate, "plate-show-generation")
  RemovePlateNameIndex(plate)
  UnbindPlate(plate)
  RefreshPlateIdentity(plate)
  DebugLog("PLATESHOW", "name=" .. tostring(plateNameByPlate[plate]) .. " guid=" .. tostring(guidByPlate[plate]))
end

local function OnNativePlateHide(plate)
  plateGeneration[plate] = (plateGeneration[plate] or 0) + 1
  DebugLog("PLATEHIDE", "name=" .. tostring(plateNameByPlate[plate]) .. " guid=" .. tostring(guidByPlate[plate]))
  RemoveDotBindingsForPlate(plate, "plate-hide")
  RemovePlateNameIndex(plate)
  UnbindPlate(plate)
end

local function RegisterNativePlate(plate)
  if not plate then return end
  knownPlates[plate] = 1
  if not plateGeneration[plate] then plateGeneration[plate] = 1 end

  if not hookedPlates[plate] then
    hookedPlates[plate] = 1
    HookFrameScript(plate, "OnShow", OnNativePlateShow)
    HookFrameScript(plate, "OnHide", OnNativePlateHide)
    DebugLog("PLATEREG", "registered native nameplate frame")
  end

  RefreshPlateIdentity(plate)
end

local function ResetNameplateIdentity()
  platesByGUID = {}
  guidByPlate = {}
  visiblePlatesByName = {}
  plateNameByPlate = {}
  knownPlates = {}
  dotBindings = {}
  initializedChildren = 0
end

function NSCT:ScanNameplates(force)
  if not WorldFrame then return end
  local count = WorldFrame:GetNumChildren() or 0

  -- WorldFrame children are normally appended. If a zone/client transition ever
  -- reduces the count, restart discovery rather than trusting the old index.
  if count < initializedChildren then initializedChildren = 0 end

  if force or count > initializedChildren then
    local children = { WorldFrame:GetChildren() }
    local first = force and 1 or (initializedChildren + 1)
    local found = 0
    local i
    for i = first, count do
      local plate = children[i]
      if IsNamePlate(plate) then
        RegisterNativePlate(plate)
        found = found + 1
      end
    end
    initializedChildren = count
    if found > 0 or force then
      DebugLog("PLATES", "worldChildren=" .. tostring(count) .. " newNativePlates=" .. tostring(found) .. " force=" .. tostring(force and 1 or 0))
    end
  end

  -- This does not rescan WorldFrame. It only refreshes the small registry of
  -- already discovered plates so delayed name text and optional GUIDs stay current.
  local plate
  for plate in pairs(knownPlates) do
    RefreshPlateIdentity(plate)
  end
end

function NSCT:GetNameplate(guid)
  if NativeOnlyEnabled() then return nil end
  if not IsGUID(guid) then return nil end

  -- Prefer a direct GUID -> nameplate API when the client exposes one.
  if UnitNameplate then
    local ok, plate = pcall(UnitNameplate, guid)
    if ok and plate and IsNamePlate(plate) then
      RegisterNativePlate(plate)
      BindPlateGUID(plate, guid)
      return plate
    end
  end

  local plate = platesByGUID[guid]
  if plate and guidByPlate[plate] == guid and plate.IsShown and plate:IsShown() then
    return plate
  end

  self:ScanNameplates(1)
  plate = platesByGUID[guid]
  if plate and guidByPlate[plate] == guid and plate.IsShown and plate:IsShown() then
    return plate
  end
  return nil
end

function NSCT:GetNameplateByName(name)
  if not name or name == "" then return nil end
  local set = visiblePlatesByName[name]
  if not set then return nil end

  local found = nil
  local count = 0
  local plate
  for plate in pairs(set) do
    if plate.IsShown and plate:IsShown() and plateNameByPlate[plate] == name then
      count = count + 1
      found = plate
      if count > 1 then return nil end
    end
  end
  if count == 1 then return found end
  return nil
end

function NSCT:GetTargetNameplate()
  local targetName = UnitName and UnitName("target") or nil
  if not targetName then return nil end

  local targetGUID = GetGUID("target")
  if targetGUID then
    local exact = self:GetNameplate(targetGUID)
    if exact then return exact, "guid" end
  end

  self:ScanNameplates(nil)
  local set = visiblePlatesByName[targetName]
  if not set then return nil end

  local highAlpha = nil
  local highCount = 0
  local only = nil
  local total = 0
  local plate
  for plate in pairs(set) do
    if plate.IsShown and plate:IsShown() and plateNameByPlate[plate] == targetName then
      total = total + 1
      only = plate
      if plate.GetAlpha and plate:GetAlpha() > 0.9 then
        highCount = highCount + 1
        highAlpha = plate
      end
    end
  end

  if highCount == 1 then return highAlpha, "target-alpha" end
  if total == 1 then return only, "target-unique-name" end
  return nil
end

function NSCT:ResolveNameplate(guid, name, preferTarget)
  if guid then
    local exact = self:GetNameplate(guid)
    if exact then return exact, "guid" end
  end

  if name and preferTarget and UnitName and UnitName("target") == name then
    local targetPlate, mode = self:GetTargetNameplate()
    if targetPlate then return targetPlate, mode end
  end

  if name then
    local unique = self:GetNameplateByName(name)
    if unique then return unique, "unique-name" end
  end

  return nil
end

local function IsTargetResolutionMode(mode)
  return mode == "target-alpha" or mode == "target-unique-name"
end

local function IsResolvedPlateTarget(plate, guid, name, resolutionMode)
  if not plate then return nil end

  -- Native target-specific resolution modes already prove that this frame is
  -- the current target, even when the client cannot map its GUID directly.
  if IsTargetResolutionMode(resolutionMode) then return 1 end

  local targetName = UnitName and UnitName("target") or nil
  if not targetName then return nil end

  local targetGUID = GetGUID("target")
  if guid and targetGUID and guid == targetGUID then return 1 end

  -- If the names differ, this cannot be the current target. When names are the
  -- same, compare the resolved frames rather than trusting the name alone so a
  -- second same-named enemy is never promoted to target styling.
  if name and name ~= targetName then return nil end
  local targetPlate = NSCT:GetTargetNameplate()
  if targetPlate and targetPlate == plate then return 1 end
  return nil
end

local function ApplyTargetVisualPolicy(fs, isTarget)
  if not fs or not fs.holder then return end
  if isTarget then
    fs.targetState = "target"
    fs.visualScale = TARGET_SCALE
    fs.baseAlpha = TARGET_ALPHA
    fs.frameStrata = TARGET_STRATA
  else
    fs.targetState = "offtarget"
    fs.visualScale = OFFTARGET_SCALE
    fs.baseAlpha = OFFTARGET_ALPHA
    fs.frameStrata = OFFTARGET_STRATA
  end
  fs.holder:SetScale(fs.visualScale)
  fs.holder:SetFrameStrata(fs.frameStrata)
end

-- Build a spell-name -> icon lookup from the player spellbook.  This is
-- intentionally independent of modern GetSpellInfo APIs, which do not exist
-- in the 1.12 client, which uses the classic spellbook functions.
local function RebuildSpellTextureCache()
  spellTextures = {}
  if not GetNumSpellTabs or not GetSpellTabInfo or not GetSpellName then return end
  local tabs = GetNumSpellTabs() or 0
  local t
  for t = 1, tabs do
    local _, _, offset, numSpells = GetSpellTabInfo(t)
    offset = offset or 0
    numSpells = numSpells or 0
    local i
    for i = offset + 1, offset + numSpells do
      local name = GetSpellName(i, BOOKTYPE_SPELL)
      if name and name ~= "" then
        local texture = nil
        if GetSpellTexture then texture = GetSpellTexture(i, BOOKTYPE_SPELL) end
        if texture then spellTextures[name] = texture end
      end
    end
  end
  local n = 0
  local k
  for k in pairs(spellTextures) do n = n + 1 end
  DebugLog("SPELLS", "cached spell icons=" .. tostring(n))
end

local function GetSpellTextureByName(spell)
  if not spell then return nil end
  local texture = spellTextures[spell]
  if texture then return texture end
  -- A spell can be learned while logged in; refresh once on a cache miss.
  RebuildSpellTextureCache()
  texture = spellTextures[spell]
  if texture then return texture end

  -- Some combat-log formats expand the active Seal in Judgement's damage name,
  -- while the spellbook icon is stored under the base "Judgement" spell.
  if string.find(spell, "^Judgement of ") then
    return spellTextures["Judgement"]
  end
  return nil
end

local SCHOOL_COLORS = {
  Physical = {1.00, 1.00, 1.00},
  Holy     = {1.00, 0.90, 0.50},
  Fire     = {1.00, 0.45, 0.15},
  Nature   = {0.30, 1.00, 0.30},
  Frost    = {0.40, 0.75, 1.00},
  Shadow   = {0.75, 0.45, 1.00},
  Arcane   = {1.00, 0.50, 1.00},
}

local function SetTextHeightSafe(fontString, height)
  if not fontString or not height then return nil end
  if fontString.SetTextHeight then
    local ok = pcall(function() fontString:SetTextHeight(height) end)
    if ok then return 1 end
  end
  return nil
end

local function PrepareFontString(fontString, path, height, flags)
  if not fontString then return nil end
  path = path or "Fonts\\FRIZQT__.TTF"
  height = height or 18
  flags = flags or "OUTLINE"
  -- MSBT's Vanilla workaround: make SetFont establish a valid font, then use
  -- SetTextHeight for the actual visible size. SetFont alone caps around 22px.
  local base = height - 1
  if base < 8 then base = 8 end
  local ok = fontString:SetFont(path, base, flags)
  if not ok then
    ok = fontString:SetFont("Fonts\\FRIZQT__.TTF", math.min(base, 21), flags)
  end
  if ok then SetTextHeightSafe(fontString, height) end
  return ok
end

local function AcquireFontString(plate)
  local fs = table.remove(fontPool)
  if not fs then
    local holder = CreateFrame("Frame", nil, WorldFrame)
    holder:SetWidth(320)
    holder:SetHeight(120)
    holder:SetFrameStrata("HIGH")

    fs = holder:CreateFontString(nil, "OVERLAY")
    PrepareFontString(fs, "Fonts\\FRIZQT__.TTF", 18, "OUTLINE")
    fs:SetShadowOffset(1, -1)

    fs.holder = holder
    fs.icon = holder:CreateTexture(nil, "OVERLAY")
    fs.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  end

  fs.holder:SetScale(1)
  fs.holder:ClearAllPoints()
  fs.holder:SetPoint("CENTER", plate, "CENTER", 0, 30)
  fs.holder:Show()

  fs:ClearAllPoints()
  fs:SetPoint("CENTER", fs.holder, "CENTER", 0, 0)
  fs:SetAlpha(1)
  fs:Show()

  fs.icon:Hide()
  fs.icon:ClearAllPoints()
  return fs
end

local function ReleaseFontString(fs)
  if not fs then return end
  fs:SetText("")
  fs:SetTextColor(1, 0.82, 0)
  PrepareFontString(fs, "Fonts\\FRIZQT__.TTF", 18, "OUTLINE")
  fs:Show()
  if fs.icon then
    fs.icon:Hide()
    fs.icon:SetTexture(nil)
    fs.icon:ClearAllPoints()
  end
  fs.holder:SetScale(1)
  fs.holder:Hide()
  fs.guid = nil
  fs.plate = nil
  fs.plateName = nil
  fs.plateGeneration = nil
  fs.resolutionMode = nil
  fs.targetState = nil
  fs.visualScale = nil
  fs.baseAlpha = nil
  fs.frameStrata = nil
  fs.started = nil
  fs.duration = nil
  fs.animation = nil
  fs.critical = nil
  fs.pow = nil
  fs.baseTextHeight = nil
  fs.popStartHeight = nil
  fs.popPeakHeight = nil
  fs.popDuration = nil
  fs.arcX = nil
  fs.arcY = nil
  fs.startY = nil
  fs.lastPlateX = nil
  fs.lastPlateY = nil
  fs.detached = nil
  table.insert(fontPool, fs)
end

local function DisplayOnPlate(plate, guid, text, info, resolutionMode)
  if not plate then return nil end

  local fs = AcquireFontString(plate)
  info = info or {}

  local size = 18
  if info.kind == "miss" then size = 18 end
  -- NameplateSCT WotLK defaults: crits are embiggened x1.5, misses are not
  -- permanently embiggened unless the optional setting is enabled.
  if info.critical then size = 27 end

  fs.critical = info.critical
  -- In the original addon both criticals and miss outcomes are sent with pow=true.
  fs.pow = (info.critical or info.kind == "miss") and 1 or nil
  fs.baseTextHeight = size
  fs.popDuration = fs.pow and (1.00 / 6) or nil
  -- Original POW: start=height/2 -> peak=height*2 -> finish=height.
  fs.popStartHeight = fs.pow and (size / 2) or size
  fs.popPeakHeight = fs.pow and (size * 2) or size

  PrepareFontString(fs, "Fonts\\FRIZQT__.TTF", size, "OUTLINE")

  local c = SCHOOL_COLORS[info.school]
  if info.kind == "miss" then
    -- WotLK NameplateSCT uses its normal default combat-text color for misses.
    fs:SetTextColor(1, 0.82, 0)
  elseif c then
    fs:SetTextColor(c[1], c[2], c[3])
  else
    fs:SetTextColor(1, 0.82, 0)
  end
  fs:SetText(tostring(text))
  -- SetTextHeight must be applied after valid font/text setup on this client.
  SetTextHeightSafe(fs, fs.popStartHeight)

  local texture = GetSpellTextureByName(info.spell)
  if texture and info.spell then
    local iconSize = size
    if fs.pow then iconSize = fs.popStartHeight end
    if iconSize < 14 then iconSize = 14 end
    fs.icon:SetTexture(texture)
    fs.icon:SetWidth(iconSize)
    fs.icon:SetHeight(iconSize)
    fs.icon:SetPoint("RIGHT", fs, "LEFT", -3, 0)
    fs.icon:SetAlpha(1)
    fs.icon:Show()
  end

  fs.guid = IsGUID(guid) and guid or nil
  fs.plate = plate
  fs.plateName = plateNameByPlate[plate] or ReadPlateName(plate)
  fs.plateGeneration = plateGeneration[plate] or 0
  fs.resolutionMode = resolutionMode or (fs.guid and "guid" or "native")
  local isTarget = IsResolvedPlateTarget(plate, fs.guid, fs.plateName, fs.resolutionMode)
  ApplyTargetVisualPolicy(fs, isTarget)
  fs:SetAlpha(fs.baseAlpha or 1)
  if fs.icon and fs.icon:IsShown() then fs.icon:SetAlpha(fs.baseAlpha or 1) end
  fs.started = GetTime()
  -- Preserve a WorldFrame-relative position in case this is a killing blow
  -- and the native plate disappears before the next OnUpdate.
  fs.lastPlateX, fs.lastPlateY = plate:GetCenter()
  fs.detached = nil
  -- WotLK defaults animation speed to 1.0s. Keep normal fountain behavior, but
  -- criticals use VerticalUp so the initial pow reads as an impact rather than
  -- immediately flying sideways.
  fs.duration = 1.00
  fs.startY = 30

  if info.kind == "miss" or info.critical then
    fs.animation = "verticalUp"
    fs.arcX = 0
    fs.arcY = info.critical and 72 or 52
  else
    fs.animation = "fountain"
    fs.arcX = arcDirection * math.random(28, 52)
    arcDirection = arcDirection * -1
    fs.arcY = math.random(42, 60)
  end

  table.insert(activeTexts, fs)
  DebugLog("DISPLAY", "mode=" .. tostring(fs.resolutionMode) .. " focus=" .. tostring(fs.targetState) .. " scale=" .. tostring(fs.visualScale) .. " baseAlpha=" .. tostring(fs.baseAlpha) .. " strata=" .. tostring(fs.frameStrata) .. " guid=" .. tostring(fs.guid) .. " name=" .. tostring(fs.plateName) .. " text=" .. tostring(text) .. " kind=" .. tostring(info.kind) .. " type=" .. tostring(info.damageType) .. " result=" .. tostring(info.result) .. " spell=" .. tostring(info.spell) .. " school=" .. tostring(info.school) .. " crit=" .. tostring(info.critical) .. " periodic=" .. tostring(info.periodic) .. " reflected=" .. tostring(info.reflected) .. " pow=" .. tostring(fs.pow) .. " icon=" .. tostring(texture) .. " height=" .. tostring(size) .. " popStart=" .. tostring(fs.popStartHeight))
  return 1
end

function NSCT:Display(guid, text, info)
  local plate = self:GetNameplate(guid)
  if not plate then
    DebugLog("DISPLAY", "no nameplate for guid=" .. tostring(guid) .. " text=" .. tostring(text))
    return nil
  end
  return DisplayOnPlate(plate, guid, text, info, "guid")
end

function NSCT:DisplayResolved(guid, name, text, info, preferTarget)
  local plate, mode = self:ResolveNameplate(guid, name, preferTarget)
  if not plate then
    DebugLog("DISPLAY", "unresolved destination guid=" .. tostring(guid) .. " name=" .. tostring(name) .. " text=" .. tostring(text))
    return nil
  end
  return DisplayOnPlate(plate, guid, text, info, mode)
end

local function UpdateTexts()
  local now = GetTime()
  local i = table.getn(activeTexts)
  while i >= 1 do
    local fs = activeTexts[i]
    local elapsed = now - fs.started
    if elapsed >= fs.duration then
      table.remove(activeTexts, i)
      ReleaseFontString(fs)
    else
      local progress = elapsed / fs.duration
      local x, y = 0, fs.startY or 30
      if fs.animation == "fountain" then
        x = (fs.arcX or 0) * progress
        y = y + (fs.arcY or 50) * (4 * progress * (1 - progress)) + 18 * progress
      else
        -- NameplateSCT WotLK uses InQuad for vertical animations. This starts
        -- almost stationary and accelerates upward, making crits linger near
        -- the nameplate while the pow animation happens.
        y = y + (fs.arcY or 52) * (progress * progress)
      end

      local plate = nil
      if not fs.detached then
        -- Keep the plate resolved at Display() time for the lifetime of the text.
        -- The visibility generation protects native resolutions from recycled
        -- frames, while exact GUID resolutions additionally validate the reverse
        -- GUID mapping.
        local cachedPlate = fs.plate
        local generationMatches = cachedPlate and (plateGeneration[cachedPlate] or 0) == (fs.plateGeneration or 0)
        -- A GUID may be available even when the destination itself was resolved
        -- through the native target/name fallback. Only texts whose original
        -- resolution mode was exact GUID resolution should require a GUID mapping
        -- on subsequent frames. Native resolutions remain sticky to the frame and
        -- visibility generation chosen at display time.
        local exactGUIDTracking = fs.guid and fs.resolutionMode == "guid"
        if exactGUIDTracking then
          if cachedPlate and generationMatches and guidByPlate[cachedPlate] == fs.guid and cachedPlate.IsShown and cachedPlate:IsShown() then
            plate = cachedPlate
          else
            plate = NSCT:GetNameplate(fs.guid)
            fs.plate = plate
            if plate then fs.plateGeneration = plateGeneration[plate] or 0 end
          end
        elseif cachedPlate and generationMatches and cachedPlate.IsShown and cachedPlate:IsShown() then
          -- Native resolution is deliberately sticky: once a text is bound to a
          -- frame, never jump it to another same-named mob. If this plate enters
          -- a new visibility generation, detach the text instead.
          if not fs.plateName or plateNameByPlate[cachedPlate] == fs.plateName then
            plate = cachedPlate
          end
        end
      end

      if plate then
        fs.lastPlateX, fs.lastPlateY = plate:GetCenter()
        fs.holder:ClearAllPoints()
        fs.holder:SetPoint("CENTER", plate, "CENTER", x, y)
      elseif fs.lastPlateX and fs.lastPlateY then
        -- A dead unit's plate can vanish before the floating text expires.
        -- Continue its established motion from the last valid plate position
        -- rather than freezing the holder at its prior point. Once detached, do
        -- not perform further nameplate lookups for this text.
        fs.holder:ClearAllPoints()
        fs.holder:SetPoint("CENTER", WorldFrame, "BOTTOMLEFT", fs.lastPlateX + x, fs.lastPlateY + y)
        if not fs.detached then
          fs.detached = 1
          fs.plate = nil
          DebugLog("DISPLAY", "plate disappeared; continuing text guid=" .. tostring(fs.guid) .. " name=" .. tostring(fs.plateName))
        end
      end

      -- WotLK-style POW: over the first sixth of the animation, grow from
      -- half-size to 2x base with OutQuint, then settle to base with InQuint.
      -- This uses SetTextHeight(), the Vanilla-safe path confirmed in v0.3.5.
      if fs.pow and fs.popDuration and elapsed < fs.popDuration then
        local pp = elapsed / fs.popDuration
        local startH = fs.popStartHeight or ((fs.baseTextHeight or 27) / 2)
        local peakH = fs.popPeakHeight or ((fs.baseTextHeight or 27) * 2)
        local baseH = fs.baseTextHeight or 27
        local h
        if pp < 0.5 then
          local t = pp * 2
          -- OutQuint: 1 - (1-t)^5
          local eased = 1 - math.pow(1 - t, 5)
          h = startH + (peakH - startH) * eased
        else
          local t = (pp - 0.5) * 2
          -- InQuint: t^5
          local eased = math.pow(t, 5)
          h = peakH + (baseH - peakH) * eased
        end
        SetTextHeightSafe(fs, h)
        if fs.icon and fs.icon:IsShown() then
          fs.icon:SetWidth(h)
          fs.icon:SetHeight(h)
        end
      elseif fs.pow then
        SetTextHeightSafe(fs, fs.baseTextHeight or 18)
        if fs.icon and fs.icon:IsShown() then
          fs.icon:SetWidth(fs.baseTextHeight or 18)
          fs.icon:SetHeight(fs.baseTextHeight or 18)
        end
      end

      local fadeAlpha = 1
      -- Keep the crit visually solid through its impact, then fade. Normal hits
      -- retain the proven v0.3.5 timing. Off-target text multiplies this fade by
      -- its lower base alpha instead of replacing the established fade curve.
      local fadeStart = fs.critical and 0.48 or (fs.pow and 0.48 or 0.62)
      if progress > fadeStart then fadeAlpha = 1 - ((progress - fadeStart) / (1 - fadeStart)) end
      if fadeAlpha < 0 then fadeAlpha = 0 end
      local alpha = fadeAlpha * (fs.baseAlpha or 1)
      fs:SetAlpha(alpha)
      if fs.icon and fs.icon:IsShown() then fs.icon:SetAlpha(alpha) end
    end
    i = i - 1
  end
end

-- Native Vanilla outgoing-combat backend. Blizzard's own localized global
-- strings are compiled into Lua search patterns, so this parser does not depend
-- on hard-coded English combat-log sentences.
local NATIVE_COMBAT_EVENTS = {
  "CHAT_MSG_COMBAT_SELF_HITS",
  "CHAT_MSG_COMBAT_SELF_MISSES",
  "CHAT_MSG_SPELL_SELF_DAMAGE",
  "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE",
  "CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE",
}

-- Useful classification sources that are not required to activate the native
-- backend. Keeping them optional prevents a client missing one niche event from
-- forcing the addon back to RAW_COMBATLOG for all normal outgoing combat.
local OPTIONAL_NATIVE_COMBAT_EVENTS = {
  "CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF",
}

local function EscapeLuaPatternChar(ch)
  if string.find(ch, "[%^%$%(%)%.%[%]%*%-%+%?]") then
    return "%" .. ch
  end
  return ch
end

local function CompileGlobalPattern(globalName)
  if nativePatternCache[globalName] ~= nil then
    local cached = nativePatternCache[globalName]
    if cached == false then return nil end
    return cached
  end

  local globalString = getglobal and getglobal(globalName) or nil
  if not globalString or globalString == "" then
    nativePatternCache[globalName] = false
    return nil
  end

  local search = "^"
  local capturesByArgument = {}
  local captureCount = 0
  local i = 1
  local len = string.len(globalString)

  while i <= len do
    local ch = string.sub(globalString, i, i)
    if ch ~= "%" then
      search = search .. EscapeLuaPatternChar(ch)
      i = i + 1
    else
      local nextCh = string.sub(globalString, i + 1, i + 1)
      if nextCh == "%" then
        search = search .. "%%"
        i = i + 2
      else
        local j = i + 1
        local formatCode = "%"
        local typeChar = nil
        while j <= len do
          local fc = string.sub(globalString, j, j)
          formatCode = formatCode .. fc
          if string.find(fc, "[cEefgGiouXxqsd]") then
            typeChar = fc
            break
          end
          j = j + 1
        end

        if not typeChar then
          -- Invalid/incomplete formatting code: treat the percent literally.
          search = search .. "%%"
          i = i + 1
        else
          captureCount = captureCount + 1
          local _, _, explicitPosition = string.find(formatCode, "(%d+)%$")
          local argumentPosition = explicitPosition and tonumber(explicitPosition) or captureCount
          capturesByArgument[argumentPosition] = captureCount

          if typeChar == "d" then
            search = search .. "(%d+)"
          else
            search = search .. "(.+)"
          end
          i = j + 1
        end
      end
    end
  end

  local info = {
    search = search,
    capturesByArgument = capturesByArgument,
    source = globalString,
  }
  nativePatternCache[globalName] = info
  return info
end

local function CaptureGlobal(message, globalName, fields)
  if not message then return nil end
  local pattern = CompileGlobalPattern(globalName)
  if not pattern then return nil end

  local startPos, endPos, c1, c2, c3, c4, c5, c6 = string.find(message, pattern.search)
  if not startPos then return nil end
  local captures = { c1, c2, c3, c4, c5, c6 }
  local out = {}
  local i
  for i = 1, table.getn(fields) do
    local field = fields[i]
    local captureIndex = pattern.capturesByArgument[i] or i
    local value = captures[captureIndex]
    if field == "amount" then
      out.amount = tonumber(value)
    elseif field == "targetName" then
      out.targetName = value
    elseif field == "spell" then
      out.spell = value
    elseif field == "school" then
      out.school = value
    end
  end
  return out
end

local function CanonicalSchool(localizedSchool)
  if not localizedSchool then return nil end
  if SPELL_SCHOOL0_CAP and localizedSchool == SPELL_SCHOOL0_CAP then return "Physical" end
  if SPELL_SCHOOL1_CAP and localizedSchool == SPELL_SCHOOL1_CAP then return "Holy" end
  if SPELL_SCHOOL2_CAP and localizedSchool == SPELL_SCHOOL2_CAP then return "Fire" end
  if SPELL_SCHOOL3_CAP and localizedSchool == SPELL_SCHOOL3_CAP then return "Nature" end
  if SPELL_SCHOOL4_CAP and localizedSchool == SPELL_SCHOOL4_CAP then return "Frost" end
  if SPELL_SCHOOL5_CAP and localizedSchool == SPELL_SCHOOL5_CAP then return "Shadow" end
  if SPELL_SCHOOL6_CAP and localizedSchool == SPELL_SCHOOL6_CAP then return "Arcane" end
  -- English clients already use these canonical values. Unknown localized
  -- schools are retained for diagnostics and will use the default text color.
  return localizedSchool
end

local function NewNormalizedDamage(data, damageType, critical, periodic, reflected)
  if not data then return nil end

  local finalType = damageType
  if periodic then
    finalType = "periodic"
  elseif reflected then
    finalType = "reflected"
  end

  return {
    kind = "damage",
    source = "player",
    damageType = finalType,
    result = critical and "crit" or "hit",
    targetName = data.targetName,
    amount = data.amount,
    spell = data.spell,
    school = CanonicalSchool(data.school) or "Physical",
    critical = critical and 1 or nil,
    periodic = periodic and 1 or nil,
    reflected = reflected and 1 or nil,
  }
end

local function NewNormalizedMiss(data, result, damageType, periodic)
  if not data then return nil end
  return {
    kind = "miss",
    source = "player",
    damageType = damageType,
    result = string.lower(result or "MISS"),
    targetName = data.targetName,
    spell = data.spell,
    text = result,
    periodic = periodic and 1 or nil,
  }
end

local function ParseNativeMeleeHit(message)
  local data = CaptureGlobal(message, "COMBATHITSELFOTHER", { "targetName", "amount" })
  if data then return NewNormalizedDamage(data, "autoattack", nil, nil, nil) end

  data = CaptureGlobal(message, "COMBATHITCRITSELFOTHER", { "targetName", "amount" })
  if data then return NewNormalizedDamage(data, "autoattack", 1, nil, nil) end
  return nil
end

local function ParseNativeMeleeMiss(message)
  local missPatterns = {
    { "MISSEDSELFOTHER", "MISS" },
    { "VSDODGESELFOTHER", "DODGE" },
    { "VSPARRYSELFOTHER", "PARRY" },
    { "VSBLOCKSELFOTHER", "BLOCK" },
    { "VSABSORBSELFOTHER", "ABSORB" },
    { "VSIMMUNESELFOTHER", "IMMUNE" },
    { "VSEVADESELFOTHER", "EVADE" },
  }
  local i
  for i = 1, table.getn(missPatterns) do
    local data = CaptureGlobal(message, missPatterns[i][1], { "targetName" })
    if data then return NewNormalizedMiss(data, missPatterns[i][2], "autoattack", nil) end
  end
  return nil
end

local function ParseNativeSpell(message)
  local data

  -- Physical abilities omit a school suffix in the Vanilla combat log.
  data = CaptureGlobal(message, "SPELLLOGCRITSELFOTHER", { "spell", "targetName", "amount" })
  if data then return NewNormalizedDamage(data, "ability", 1, nil, nil) end

  data = CaptureGlobal(message, "SPELLLOGSELFOTHER", { "spell", "targetName", "amount" })
  if data then return NewNormalizedDamage(data, "ability", nil, nil, nil) end

  -- Spells with an explicit damage school.
  data = CaptureGlobal(message, "SPELLLOGCRITSCHOOLSELFOTHER", { "spell", "targetName", "amount", "school" })
  if data then return NewNormalizedDamage(data, "spell", 1, nil, nil) end

  data = CaptureGlobal(message, "SPELLLOGSCHOOLSELFOTHER", { "spell", "targetName", "amount", "school" })
  if data then return NewNormalizedDamage(data, "spell", nil, nil, nil) end

  -- Avoidance results that require a physical attack are classified as
  -- abilities; spell-like outcomes remain spells. SPELLMISSSELFOTHER is kept
  -- under spell because Vanilla does not expose enough data to infer otherwise.
  local missPatterns = {
    { "SPELLMISSSELFOTHER", "MISS", "spell" },
    { "SPELLDODGEDSELFOTHER", "DODGE", "ability" },
    { "SPELLPARRIEDSELFOTHER", "PARRY", "ability" },
    { "SPELLBLOCKEDSELFOTHER", "BLOCK", "ability" },
    { "SPELLRESISTSELFOTHER", "RESIST", "spell" },
    { "SPELLLOGABSORBSELFOTHER", "ABSORB", "spell" },
    { "SPELLIMMUNESELFOTHER", "IMMUNE", "spell" },
    { "SPELLREFLECTSELFOTHER", "REFLECT", "spell" },
    { "SPELLEVADEDSELFOTHER", "EVADE", "ability" },
  }
  local i
  for i = 1, table.getn(missPatterns) do
    data = CaptureGlobal(message, missPatterns[i][1], { "spell", "targetName" })
    if data then return NewNormalizedMiss(data, missPatterns[i][2], missPatterns[i][3], nil) end
  end
  return nil
end

local function ParseNativeAuraApplication(message)
  -- Harmful aura applications share the periodic-damage chat event in Vanilla.
  -- They do not display SCT themselves; they teach the resolver which exact
  -- native nameplate owns a later periodic tick. Prefer the stacked-aura form
  -- when a compatible client exposes it so the stack count is not folded into
  -- the captured spell name.
  local data = CaptureGlobal(message, "AURAAPPLICATIONADDEDOTHERHARMFUL", { "targetName", "spell", "stack" })
  if data then return data end

  data = CaptureGlobal(message, "AURAADDEDOTHERHARMFUL", { "targetName", "spell" })
  if data then return data end
  return nil
end

local function ParseNativePeriodic(message)
  local data = CaptureGlobal(message, "PERIODICAURADAMAGESELFOTHER", { "targetName", "amount", "school", "spell" })
  if data then return NewNormalizedDamage(data, "spell", nil, 1, nil) end

  -- A periodic tick can be completely absorbed and use the normal spell absorb
  -- combat string instead of the periodic-damage string.
  data = CaptureGlobal(message, "SPELLLOGABSORBSELFOTHER", { "spell", "targetName" })
  if data then
    return NewNormalizedMiss(data, "ABSORB", "periodic", 1)
  end
  return nil
end

local function ParseNativeDamageShield(message)
  -- DAMAGESHIELDSELFOTHER carries amount, localized damage school, and target.
  -- The originating aura name is not included in this Vanilla combat string.
  local data = CaptureGlobal(message, "DAMAGESHIELDSELFOTHER", { "amount", "school", "targetName" })
  if data then return NewNormalizedDamage(data, "reflected", nil, nil, 1) end
  return nil
end

local function ParseNativeCombatEvent(eventName, message)
  if eventName == "CHAT_MSG_COMBAT_SELF_HITS" then
    return ParseNativeMeleeHit(message)
  elseif eventName == "CHAT_MSG_COMBAT_SELF_MISSES" then
    return ParseNativeMeleeMiss(message)
  elseif eventName == "CHAT_MSG_SPELL_SELF_DAMAGE" then
    return ParseNativeSpell(message)
  elseif eventName == "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE" or eventName == "CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE" then
    return ParseNativePeriodic(message)
  elseif eventName == "CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF" then
    return ParseNativeDamageShield(message)
  end
  return nil
end

local function EventTargetGUID(info)
  if not info or not info.targetName or not UnitName then return nil end
  if UnitName("target") == info.targetName then
    return GetGUID("target")
  end
  return nil
end

function NSCT:HandleNativeCombatEvent(eventName, message)
  DebugLog("NATIVELOG", tostring(eventName) .. " || " .. tostring(message))
  if not NameplateSCTVanillaDB.autoDisplay then return end

  -- Aura-application messages use the same Vanilla chat events as periodic
  -- damage. Consume them as resolver metadata instead of reporting them as
  -- unmatched combat damage.
  if eventName == "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE" or eventName == "CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE" then
    local aura = ParseNativeAuraApplication(message)
    if aura and aura.targetName and aura.spell then
      local preferTarget = UnitName and UnitName("target") == aura.targetName and 1 or nil
      local plate, mode = self:ResolveNameplate(nil, aura.targetName, preferTarget)
      if plate then
        BindDotTarget(aura.spell, aura.targetName, plate, mode)
      else
        DebugLog("DOTBIND", "unresolved spell=" .. tostring(aura.spell) .. " name=" .. tostring(aura.targetName))
      end
      return
    end
  end

  local info = ParseNativeCombatEvent(eventName, message)
  if not info then
    DebugLog("UNMATCHED", tostring(eventName) .. " || " .. tostring(message))
    return
  end

  info.guid = EventTargetGUID(info)
  local text = info.text or info.amount
  if not text or not info.targetName then
    DebugLog("UNMATCHED", "parsed incomplete event=" .. tostring(eventName) .. " target=" .. tostring(info.targetName) .. " text=" .. tostring(text) .. " raw=" .. tostring(message))
    return
  end

  DebugLog("PARSED", "backend=native event=" .. tostring(eventName) .. " kind=" .. tostring(info.kind) .. " type=" .. tostring(info.damageType) .. " result=" .. tostring(info.result) .. " amount=" .. tostring(info.amount) .. " text=" .. tostring(info.text) .. " target=" .. tostring(info.targetName) .. " guid=" .. tostring(info.guid) .. " spell=" .. tostring(info.spell) .. " school=" .. tostring(info.school) .. " crit=" .. tostring(info.critical) .. " periodic=" .. tostring(info.periodic) .. " reflected=" .. tostring(info.reflected))

  if info.periodic and info.spell then
    local plate, mode, state, bindingCount = ResolveDotTarget(info.spell, info.targetName)
    if state == "resolved" and plate then
      DebugLog("DOTRESOLVE", "spell=" .. tostring(info.spell) .. " name=" .. tostring(info.targetName) .. " result=bound")
      DisplayOnPlate(plate, info.guid, text, info, mode)
      return
    elseif state == "ambiguous" then
      DebugLog("DOTAMBIGUOUS", "spell=" .. tostring(info.spell) .. " name=" .. tostring(info.targetName) .. " bindings=" .. tostring(bindingCount) .. " action=suppress")
      return
    end
    DebugLog("DOTRESOLVE", "spell=" .. tostring(info.spell) .. " name=" .. tostring(info.targetName) .. " result=fallback")
  end

  -- Direct player actions prefer the current target when names match. Periodic
  -- events without a learned binding remain conservative and only use an
  -- unambiguous unique visible name.
  local preferTarget = info.periodic and nil or 1
  self:DisplayResolved(info.guid, info.targetName, text, info, preferTarget)
end

local function RegisterNativeCombatEvents(frame)
  nativeCombatEventCount = 0
  nativeOptionalCombatEventCount = 0

  local i
  for i = 1, table.getn(NATIVE_COMBAT_EVENTS) do
    local eventName = NATIVE_COMBAT_EVENTS[i]
    local ok = pcall(function() frame:RegisterEvent(eventName) end)
    if ok then nativeCombatEventCount = nativeCombatEventCount + 1 end
  end

  for i = 1, table.getn(OPTIONAL_NATIVE_COMBAT_EVENTS) do
    local eventName = OPTIONAL_NATIVE_COMBAT_EVENTS[i]
    local ok = pcall(function() frame:RegisterEvent(eventName) end)
    if ok then nativeOptionalCombatEventCount = nativeOptionalCombatEventCount + 1 end
  end

  nativeCombatBackendAvailable = nativeCombatEventCount == table.getn(NATIVE_COMBAT_EVENTS) and 1 or nil
end

local function CountNativePatterns()
  local names = {
    "COMBATHITSELFOTHER", "COMBATHITCRITSELFOTHER",
    "MISSEDSELFOTHER", "VSDODGESELFOTHER", "VSPARRYSELFOTHER", "VSBLOCKSELFOTHER", "VSABSORBSELFOTHER", "VSIMMUNESELFOTHER", "VSEVADESELFOTHER",
    "SPELLLOGSELFOTHER", "SPELLLOGCRITSELFOTHER", "SPELLLOGSCHOOLSELFOTHER", "SPELLLOGCRITSCHOOLSELFOTHER",
    "SPELLMISSSELFOTHER", "SPELLDODGEDSELFOTHER", "SPELLPARRIEDSELFOTHER", "SPELLBLOCKEDSELFOTHER", "SPELLRESISTSELFOTHER", "SPELLLOGABSORBSELFOTHER", "SPELLIMMUNESELFOTHER", "SPELLREFLECTSELFOTHER", "SPELLEVADEDSELFOTHER",
    "PERIODICAURADAMAGESELFOTHER", "AURAADDEDOTHERHARMFUL", "DAMAGESHIELDSELFOTHER",
  }
  local found = 0
  local i
  for i = 1, table.getn(names) do
    if CompileGlobalPattern(names[i]) then found = found + 1 end
  end
  return found, table.getn(names)
end

-- Parser for English RAW_COMBATLOG strings when an enhanced 1.12 client exposes that event.
-- It deliberately matches only player-owned
-- outgoing damage/misses, so party members' hits are ignored.
local function ParseOutgoing(rawText)
  if not rawText then return nil end
  local _, _, guid, amount
  local _, _, spell, school
  local data

  -- White melee hits / crits.
  _, _, guid, amount = string.find(rawText, "^You hit (0x[%x]+) for (%d+)%.")
  if guid then
    data = { amount=tonumber(amount), school="Physical" }
    local info = NewNormalizedDamage(data, "autoattack", nil, nil, nil)
    info.guid = guid
    return info
  end
  _, _, guid, amount = string.find(rawText, "^You crit (0x[%x]+) for (%d+)%.")
  if guid then
    data = { amount=tonumber(amount), school="Physical" }
    local info = NewNormalizedDamage(data, "autoattack", 1, nil, nil)
    info.guid = guid
    return info
  end

  -- Direct spell damage.
  _, _, spell, guid, amount, school = string.find(rawText, "^Your (.-) hits (0x[%x]+) for (%d+) ([%a]+) damage%.")
  if guid then
    data = { amount=tonumber(amount), school=school, spell=spell }
    local info = NewNormalizedDamage(data, "spell", nil, nil, nil)
    info.guid = guid
    return info
  end
  _, _, spell, guid, amount, school = string.find(rawText, "^Your (.-) crits (0x[%x]+) for (%d+) ([%a]+) damage%.")
  if guid then
    data = { amount=tonumber(amount), school=school, spell=spell }
    local info = NewNormalizedDamage(data, "spell", 1, nil, nil)
    info.guid = guid
    return info
  end

  -- Physical abilities such as Maul omit an explicit damage-school suffix.
  _, _, spell, guid, amount = string.find(rawText, "^Your (.-) hits (0x[%x]+) for (%d+)%.")
  if guid then
    data = { amount=tonumber(amount), school="Physical", spell=spell }
    local info = NewNormalizedDamage(data, "ability", nil, nil, nil)
    info.guid = guid
    return info
  end
  _, _, spell, guid, amount = string.find(rawText, "^Your (.-) crits (0x[%x]+) for (%d+)%.")
  if guid then
    data = { amount=tonumber(amount), school="Physical", spell=spell }
    local info = NewNormalizedDamage(data, "ability", 1, nil, nil)
    info.guid = guid
    return info
  end

  -- Player-owned periodic spell damage, e.g. Moonfire.
  _, _, guid, amount, school, spell = string.find(rawText, "^(0x[%x]+) suffers (%d+) ([%a]+) damage from your (.-)%.")
  if guid then
    data = { amount=tonumber(amount), school=school, spell=spell }
    local info = NewNormalizedDamage(data, "spell", nil, 1, nil)
    info.guid = guid
    return info
  end

  -- Player-owned damage shields / reflected damage.
  _, _, amount, school, guid = string.find(rawText, "^You reflect (%d+) ([%a]+) damage to (0x[%x]+)%.")
  if guid then
    data = { amount=tonumber(amount), school=school }
    local info = NewNormalizedDamage(data, "reflected", nil, nil, 1)
    info.guid = guid
    return info
  end

  -- Miss/resist outcomes observed in captured combat-log samples.
  _, _, spell, guid = string.find(rawText, "^Your (.-) was resisted by (0x[%x]+)%.")
  if guid then data={spell=spell}; local info=NewNormalizedMiss(data,"RESIST","spell",nil); info.guid=guid; return info end
  _, _, spell, guid = string.find(rawText, "^Your (.-) was dodged by (0x[%x]+)%.")
  if guid then data={spell=spell}; local info=NewNormalizedMiss(data,"DODGE","ability",nil); info.guid=guid; return info end
  _, _, spell, guid = string.find(rawText, "^Your (.-) is parried by (0x[%x]+)%.")
  if guid then data={spell=spell}; local info=NewNormalizedMiss(data,"PARRY","ability",nil); info.guid=guid; return info end
  _, _, guid = string.find(rawText, "^You miss (0x[%x]+)%.")
  if guid then data={}; local info=NewNormalizedMiss(data,"MISS","autoattack",nil); info.guid=guid; return info end
  _, _, guid = string.find(rawText, "^You attack%. (0x[%x]+) dodges%.")
  if guid then data={}; local info=NewNormalizedMiss(data,"DODGE","autoattack",nil); info.guid=guid; return info end
  _, _, guid = string.find(rawText, "^You attack%. (0x[%x]+) parries%.")
  if guid then data={}; local info=NewNormalizedMiss(data,"PARRY","autoattack",nil); info.guid=guid; return info end
  _, _, guid = string.find(rawText, "^You attack%. (0x[%x]+) blocks%.")
  if guid then data={}; local info=NewNormalizedMiss(data,"BLOCK","autoattack",nil); info.guid=guid; return info end
  _, _, spell, guid = string.find(rawText, "^Your (.-) was immune to (0x[%x]+)%.")
  if guid then data={spell=spell}; local info=NewNormalizedMiss(data,"IMMUNE","spell",nil); info.guid=guid; return info end
  _, _, spell, guid = string.find(rawText, "^Your (.-) was absorbed by (0x[%x]+)%.")
  if guid then data={spell=spell}; local info=NewNormalizedMiss(data,"ABSORB","spell",nil); info.guid=guid; return info end
  _, _, guid = string.find(rawText, "^You attack%. (0x[%x]+) evades%.")
  if guid then data={}; local info=NewNormalizedMiss(data,"EVADE","autoattack",nil); info.guid=guid; return info end

  return nil
end

function NSCT:HandleRawCombatLog(originalEvent, rawText)
  -- Native-only mode intentionally ignores RAW_COMBATLOG completely so an
  -- enhanced client cannot influence display or diagnostic interpretation.
  if NativeOnlyEnabled() then return end
  DebugLog("RAW", tostring(originalEvent) .. " || " .. tostring(rawText))
  if not NameplateSCTVanillaDB.autoDisplay then return end
  -- Prevent duplicate SCT when both native CHAT_MSG_* and RAW_COMBATLOG exist.
  if nativeCombatBackendAvailable then return end

  local info = ParseOutgoing(rawText)
  if not info then return end
  if not info.guid then
    DebugLog("PARSE", "matched outgoing event without destination GUID: " .. tostring(rawText))
    return
  end

  local text = info.text or info.amount
  DebugLog("PARSE", "backend=raw event=" .. tostring(originalEvent) .. " kind=" .. tostring(info.kind) .. " type=" .. tostring(info.damageType) .. " result=" .. tostring(info.result) .. " amount=" .. tostring(info.amount) .. " text=" .. tostring(info.text) .. " dst=" .. tostring(info.guid) .. " spell=" .. tostring(info.spell) .. " school=" .. tostring(info.school) .. " crit=" .. tostring(info.critical) .. " periodic=" .. tostring(info.periodic) .. " reflected=" .. tostring(info.reflected))
  self:Display(info.guid, text, info)
end

function NSCT:PrintStatus()
  self:ScanNameplates(nil)
  local plateCount = 0
  local visibleCount = 0
  local namedCount = 0
  local guidCount = 0
  local reverseCount = 0
  local p
  for p in pairs(knownPlates) do
    plateCount = plateCount + 1
    if p.IsShown and p:IsShown() then visibleCount = visibleCount + 1 end
  end
  local name, set
  for name, set in pairs(visiblePlatesByName) do
    local plate
    for plate in pairs(set) do
      if plate.IsShown and plate:IsShown() then namedCount = namedCount + 1 end
    end
  end
  local g
  for g in pairs(platesByGUID) do guidCount = guidCount + 1 end
  for p in pairs(guidByPlate) do reverseCount = reverseCount + 1 end
  local targetPlate, targetMode = self:GetTargetNameplate()

  local unitExistsGUID = nil
  if UnitExists then
    local ok, exists, guid = pcall(UnitExists, "player")
    if ok and exists and IsGUID(guid) then unitExistsGUID = 1 end
  end

  local nativeOnly = NativeOnlyEnabled()
  Chat("version " .. VERSION)
  Chat("native-only mode: " .. (nativeOnly and "ON" or "OFF") .. (nativeOnly and " (enhanced identity APIs ignored)" or " (enhanced identity APIs allowed)"))
  Chat("native scanner: active; known=" .. tostring(plateCount) .. ", visible=" .. tostring(visibleCount) .. ", named=" .. tostring(namedCount))
  local ignored = nativeOnly and " (ignored)" or ""
  Chat("UnitExists GUID: " .. (unitExistsGUID and "yes" or "no") .. ignored .. "; UnitGUID API: " .. (UnitGUID and "yes" or "no") .. ignored .. "; UnitNameplate API: " .. (UnitNameplate and "yes" or "no") .. ignored)
  local selectedBackend = nativeCombatBackendAvailable and "native CHAT_MSG" or ((not nativeOnly and rawCombatLogRegistered) and "RAW_COMBATLOG" or "none")
  Chat("native combat backend: " .. (nativeCombatBackendAvailable and "active" or "partial/unavailable") .. " (" .. tostring(nativeCombatEventCount) .. "/" .. tostring(table.getn(NATIVE_COMBAT_EVENTS)) .. " required; " .. tostring(nativeOptionalCombatEventCount) .. "/" .. tostring(table.getn(OPTIONAL_NATIVE_COMBAT_EVENTS)) .. " optional); display backend: " .. selectedBackend)
  if nativeOnly then
    Chat("RAW_COMBATLOG backend: " .. (rawCombatLogRegistered and "available but ignored" or "unavailable"))
  else
    Chat("RAW_COMBATLOG backend: " .. (rawCombatLogRegistered and "registered" or "unavailable") .. (nativeCombatBackendAvailable and " (diagnostic/fallback only)" or ""))
  end
  Chat("GUID mappings: " .. tostring(guidCount) .. ", reverse mappings: " .. tostring(reverseCount) .. (nativeOnly and " (expected 0 in native-only mode)" or ""))
  Chat("target: " .. tostring(UnitName and UnitName("target") or nil) .. ", GUID=" .. tostring(GetGUID("target")) .. ", plate=" .. tostring(targetPlate and "resolved" or "unresolved") .. ", mode=" .. tostring(targetMode))
  Chat("focus styling: target scale=" .. tostring(TARGET_SCALE) .. " alpha=" .. tostring(TARGET_ALPHA) .. " strata=" .. TARGET_STRATA .. "; off-target scale=" .. tostring(OFFTARGET_SCALE) .. " alpha=" .. tostring(OFFTARGET_ALPHA) .. " strata=" .. OFFTARGET_STRATA)
  local dotBucketCount, dotEntryCount, dotAmbiguousCount = CountDotBindings()
  Chat("DoT bindings: buckets=" .. tostring(dotBucketCount) .. ", plates=" .. tostring(dotEntryCount) .. ", ambiguous=" .. tostring(dotAmbiguousCount))
  Chat("debug saved entries: " .. tostring(table.getn(NameplateSCTVanillaDebug.log)) .. ", errors: " .. tostring(table.getn(NameplateSCTVanillaDebug.errors)))
end

function NSCT:SetNativeOnly(enabled)
  EnsureDB()
  NameplateSCTVanillaDB.forceNative = enabled and 1 or 0

  -- Never retain enhanced GUID/nameplate mappings across a mode transition.
  ResetNameplateIdentity()
  playerGUID = GetGUID("player")
  self:ScanNameplates(1)

  DebugLog("MODE", "nativeOnly=" .. tostring(enabled and 1 or 0) .. " playerGUID=" .. tostring(playerGUID))
  if enabled then
    Chat("native-only mode: ON. Enhanced GUID/nameplate APIs and RAW_COMBATLOG are ignored.")
  else
    Chat("native-only mode: OFF. Enhanced identity APIs may be used when available.")
  end
  self:PrintStatus()
end

function NSCT:TestTarget()
  self:ScanNameplates(1)
  local guid = GetGUID("target")
  local name = UnitName and UnitName("target") or nil
  if not name then
    Chat("No target. Target a unit with its native nameplate visible.")
    return
  end

  local plate, mode = self:ResolveNameplate(guid, name, 1)
  if plate and DisplayOnPlate(plate, guid, "TEST 123", { kind="damage", source="player", damageType="autoattack", result="hit", school="Physical" }, mode) then
    Chat("Test text sent to target nameplate using " .. tostring(mode) .. " resolution.")
  else
    Chat("Target nameplate was not resolved. Show its nameplate, then use /np status and /np dump 50.")
  end
end

function NSCT:TestCritTarget()
  self:ScanNameplates(1)
  local guid = GetGUID("target")
  local name = UnitName and UnitName("target") or nil
  if not name then
    Chat("No target. Target a unit with its native nameplate visible.")
    return
  end

  local plate, mode = self:ResolveNameplate(guid, name, 1)
  if plate and DisplayOnPlate(plate, guid, "CRIT 999", { kind="damage", source="player", damageType="autoattack", result="crit", school="Physical", critical=1 }, mode) then
    Chat("Synthetic CRIT sent using " .. tostring(mode) .. " resolution. Existing movement is unchanged.")
  else
    Chat("Target nameplate was not resolved.")
  end
end

function NSCT:TestOffTarget()
  self:ScanNameplates(1)
  local targetPlate = self:GetTargetNameplate()
  local targetName = UnitName and UnitName("target") or nil
  local candidate = nil
  local candidateName = nil
  local plate
  for plate in pairs(knownPlates) do
    if plate ~= targetPlate and plate.IsShown and plate:IsShown() then
      local name = plateNameByPlate[plate] or ReadPlateName(plate)
      -- If the target frame itself cannot be resolved, a same-named plate is
      -- ambiguous and is not safe for a synthetic off-target assertion.
      local safeOffTarget = not targetName or name ~= targetName or targetPlate
      if name and name ~= "" and safeOffTarget then
        candidate = plate
        candidateName = name
        break
      end
    end
  end

  if not candidate then
    Chat("No visible off-target nameplate found. Show at least two enemy nameplates and try /np testoff again.")
    return
  end

  local guid = guidByPlate[candidate] or PlateGUID(candidate)
  if DisplayOnPlate(candidate, guid, "OFF 123", { kind="damage", source="player", damageType="spell", result="hit", school="Shadow" }, "test-offtarget") then
    Chat("Synthetic off-target text sent to " .. tostring(candidateName) .. " using off-target styling.")
  else
    Chat("Visible off-target nameplate was found but test display failed.")
  end
end

function NSCT:SizeTest()
  if sizeTestFrame then
    sizeTestFrame:Hide()
    sizeTestFrame = nil
  end

  local f = CreateFrame("Frame", nil, UIParent)
  f:SetWidth(700)
  f:SetHeight(430)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  f:SetFrameStrata("TOOLTIP")
  sizeTestFrame = f
  sizeTestHideAt = GetTime() + 15

  local title = f:CreateFontString(nil, "OVERLAY")
  title:SetPoint("TOP", f, "TOP", 0, -12)
  PrepareFontString(title, "Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
  title:SetText("NSCT " .. VERSION .. " SetTextHeight test")
  title:SetTextColor(1, 0.82, 0)

  local heights = {12, 18, 22, 30, 40, 60}
  local i
  for i = 1, table.getn(heights) do
    local h = heights[i]
    local fs = f:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("CENTER", f, "TOP", 0, -55 - ((i - 1) * 58))
    -- Deliberately keep SetFont <= 21, then request the visible size with
    -- SetTextHeight. This is the exact technique used by Vanilla MSBT.
    local ok = fs:SetFont("Fonts\\FRIZQT__.TTF", math.min(h - 1, 21), "OUTLINE")
    if ok then
      fs:SetText(tostring(h) .. "px  ABC 123")
      local th = SetTextHeightSafe(fs, h)
      fs:SetTextColor(1, 1, 1)
      local path, reported, flags = fs:GetFont()
      local w = fs.GetStringWidth and fs:GetStringWidth() or -1
      DebugLog("SIZETEST", "requestedHeight=" .. tostring(h) .. " setfont=" .. tostring(ok) .. " setTextHeight=" .. tostring(th) .. " reportedFont=" .. tostring(reported) .. " path=" .. tostring(path) .. " width=" .. tostring(w))
    else
      DebugLog("SIZETEST", "requestedHeight=" .. tostring(h) .. " SetFont failed")
    end
  end
  Chat("SetTextHeight diagnostics shown for 15 seconds: 12 / 18 / 22 / 30 / 40 / 60.")
end

function NSCT:FontTest()
  if fontTestFrame then
    fontTestFrame:Hide()
    fontTestFrame = nil
  end

  local f = CreateFrame("Frame", nil, UIParent)
  f:SetWidth(980)
  f:SetHeight(620)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  f:SetFrameStrata("TOOLTIP")
  fontTestFrame = f
  fontTestHideAt = GetTime() + 15

  local title = f:CreateFontString(nil, "OVERLAY")
  title:SetPoint("TOP", f, "TOP", 0, -8)
  local titleOK = title:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
  if titleOK then
    title:SetText("NSCT " .. VERSION .. " font diagnostics - same sample text in every cell")
    title:SetTextColor(1, 0.82, 0)
  else
    DebugLog("FONTTEST", "title SetFont failed")
  end

  local fonts = {
    { label="FRIZQT", path="Fonts\\FRIZQT__.TTF" },
    { label="ARIALN", path="Fonts\\ARIALN.TTF" },
    { label="SKURRI", path="Fonts\\SKURRI.TTF" },
  }
  local sizes = {12, 22, 35, 48, 72}
  local startX = -300
  local colGap = 300
  local startY = 220
  local rowGap = 58
  local sample = "ABC 123"
  local fi, si

  for fi = 1, table.getn(fonts) do
    local font = fonts[fi]
    local header = f:CreateFontString(nil, "OVERLAY")
    header:SetPoint("CENTER", f, "CENTER", startX + (fi - 1) * colGap, startY + 52)
    if header:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE") then
      header:SetText(font.label)
      header:SetTextColor(1, 0.82, 0)
    end

    for si = 1, table.getn(sizes) do
      local requested = sizes[si]
      local y = startY - (si - 1) * rowGap
      local x = startX + (fi - 1) * colGap

      local label = f:CreateFontString(nil, "OVERLAY")
      label:SetPoint("RIGHT", f, "CENTER", x - 45, y)
      if label:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE") then
        label:SetText(tostring(requested) .. "px")
        label:SetTextColor(0.70, 0.70, 0.70)
      end

      local fs = f:CreateFontString(nil, "OVERLAY")
      fs:SetPoint("LEFT", f, "CENTER", x - 35, y)
      local ok = fs:SetFont(font.path, requested, "OUTLINE")
      if ok then
        fs:SetText(sample)
        fs:SetTextColor(1, 1, 1)
        local path, reported, flags = fs:GetFont()
        local w = fs.GetStringWidth and fs:GetStringWidth() or -1
        local h = fs.GetStringHeight and fs:GetStringHeight() or -1
        DebugLog("FONTTEST", "font=" .. font.label .. " requested=" .. tostring(requested) .. " setfont=1 reported=" .. tostring(reported) .. " path=" .. tostring(path) .. " flags=" .. tostring(flags) .. " width=" .. tostring(w) .. " height=" .. tostring(h))
      else
        DebugLog("FONTTEST", "font=" .. font.label .. " requested=" .. tostring(requested) .. " setfont=nil path=" .. tostring(font.path))
      end
    end
  end

  local objectNames = {
    "NumberFontNormalSmall",
    "NumberFontNormal",
    "NumberFontNormalLarge",
    "GameFontNormal",
    "GameFontHighlight",
    "CombatTextFont",
  }
  local oy = -105
  local oi
  for oi = 1, table.getn(objectNames) do
    local name = objectNames[oi]
    local obj = getglobal and getglobal(name) or nil
    if obj and obj.GetFont then
      local path, size, flags = obj:GetFont()
      DebugLog("FONTOBJ", "name=" .. name .. " exists=1 path=" .. tostring(path) .. " size=" .. tostring(size) .. " flags=" .. tostring(flags))

      local fs = f:CreateFontString(nil, "OVERLAY")
      fs:SetPoint("LEFT", f, "CENTER", -440, oy)
      if fs.SetFontObject then fs:SetFontObject(obj) end
      local p2, s2, fl2 = fs:GetFont()
      if p2 then
        fs:SetText(name .. "  ABC 123")
        fs:SetTextColor(0.85, 0.95, 1)
        local w = fs.GetStringWidth and fs:GetStringWidth() or -1
        DebugLog("FONTOBJTEST", "name=" .. name .. " applied=1 path=" .. tostring(p2) .. " size=" .. tostring(s2) .. " flags=" .. tostring(fl2) .. " width=" .. tostring(w))
      else
        DebugLog("FONTOBJTEST", "name=" .. name .. " applied=nil")
      end
      oy = oy - 28
    else
      DebugLog("FONTOBJ", "name=" .. name .. " exists=nil")
    end
  end

  local eff = f.GetEffectiveScale and f:GetEffectiveScale() or -1
  local uiscale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or -1
  DebugLog("FONTTEST", "diagnosticFrameEffectiveScale=" .. tostring(eff) .. " UIParentEffectiveScale=" .. tostring(uiscale))
  Chat("Font diagnostics shown for 15 seconds. Compare FRIZQT / ARIALN / SKURRI, then /np dump 50.")
end

function NSCT:Dump(n)
  EnsureDB()
  n = tonumber(n) or 20
  if n < 1 then n = 1 end
  if n > 50 then n = 50 end
  local total = table.getn(NameplateSCTVanillaDebug.log)
  local first = total - n + 1
  if first < 1 then first = 1 end
  Chat("last " .. tostring(total - first + 1) .. " debug entries:")
  local i
  for i = first, total do
    DEFAULT_CHAT_FRAME:AddMessage("|cffaaaaaa" .. tostring(NameplateSCTVanillaDebug.log[i]) .. "|r")
  end
end

function NSCT:PrintErrors()
  EnsureDB()
  local total = table.getn(NameplateSCTVanillaDebug.errors)
  Chat("captured Lua errors: " .. tostring(total))
  local first = total - 4
  if first < 1 then first = 1 end
  local i
  for i = first, total do
    DEFAULT_CHAT_FRAME:AddMessage("|cffff5555" .. tostring(NameplateSCTVanillaDebug.errors[i]) .. "|r")
  end
end

function NSCT:ClearDebug()
  NameplateSCTVanillaDebug = { log = {}, errors = {} }
  Chat("debug log cleared")
end

local function SlashHandler(msg)
  msg = msg or ""
  local cmd, rest = string.match and string.match(msg, "^(%S*)%s*(.-)$") or nil, nil
  -- Vanilla Lua compatibility: string.match may not exist, use string.find.
  if not cmd then
    local _, _, c, r = string.find(msg, "^(%S*)%s*(.-)$")
    cmd, rest = c or "", r or ""
  else
    local _, _, c, r = string.find(msg, "^(%S*)%s*(.-)$")
    cmd, rest = c or "", r or ""
  end
  cmd = string.lower(cmd or "")

  if cmd == "test" then
    NSCT:TestTarget()
  elseif cmd == "crit" or cmd == "testcrit" then
    NSCT:TestCritTarget()
  elseif cmd == "testoff" or cmd == "offtest" then
    NSCT:TestOffTarget()
  elseif cmd == "fonttest" then
    NSCT:FontTest()
  elseif cmd == "sizetest" then
    NSCT:SizeTest()
  elseif cmd == "status" or cmd == "" then
    NSCT:PrintStatus()
  elseif cmd == "plates" then
    NSCT:ScanNameplates(1)
    NSCT:PrintStatus()
  elseif cmd == "dump" then
    NSCT:Dump(rest)
  elseif cmd == "errors" then
    NSCT:PrintErrors()
  elseif cmd == "clear" or cmd == "clearlog" then
    NSCT:ClearDebug()
  elseif cmd == "auto" then
    NameplateSCTVanillaDB.autoDisplay = not NameplateSCTVanillaDB.autoDisplay
    Chat("automatic parsed damage display: " .. (NameplateSCTVanillaDB.autoDisplay and "ON" or "OFF"))
  elseif cmd == "native" then
    rest = string.lower(rest or "")
    if rest == "on" then
      NSCT:SetNativeOnly(1)
    elseif rest == "off" then
      NSCT:SetNativeOnly(nil)
    else
      Chat("usage: /np native on | off (currently " .. (NativeOnlyEnabled() and "ON" or "OFF") .. ")")
    end
  else
    Chat("commands: /np status | native on|off | test | crit | testoff | sizetest | fonttest | plates | dump [1-50] | errors | clear | clearlog | auto")
  end
end

local frame = CreateFrame("Frame", "NameplateSCTVanillaFrame")
frame:RegisterEvent("VARIABLES_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("SPELLS_CHANGED")
RegisterNativeCombatEvents(frame)
local rawOK = pcall(function() frame:RegisterEvent("RAW_COMBATLOG") end)
if rawOK then rawCombatLogRegistered = 1 end

frame:SetScript("OnEvent", function()
  if event == "VARIABLES_LOADED" then
    EnsureDB()
    InstallErrorCapture()
    DebugLog("INIT", "loaded version=" .. VERSION)
    local patternCount, patternTotal = CountNativePatterns()
    DebugLog("INIT", "native nameplate scanner enabled; nativeOnly=" .. tostring(NativeOnlyEnabled() and 1 or 0) .. " UnitNameplate=" .. tostring(UnitNameplate and 1 or nil) .. " UnitGUID=" .. tostring(UnitGUID and 1 or nil) .. " RAW_COMBATLOG=" .. tostring(rawCombatLogRegistered))
    DebugLog("INIT", "native combat events=" .. tostring(nativeCombatEventCount) .. "/" .. tostring(table.getn(NATIVE_COMBAT_EVENTS)) .. " required optional=" .. tostring(nativeOptionalCombatEventCount) .. "/" .. tostring(table.getn(OPTIONAL_NATIVE_COMBAT_EVENTS)) .. " patterns=" .. tostring(patternCount) .. "/" .. tostring(patternTotal) .. " selected=" .. tostring(nativeCombatBackendAvailable and "native" or ((not NativeOnlyEnabled() and rawCombatLogRegistered) and "raw" or "none")))
    RebuildSpellTextureCache()
    Chat("loaded " .. VERSION .. ". Native-only mode is " .. (NativeOnlyEnabled() and "ON" or "OFF") .. ". Type /np status.")
  elseif event == "SPELLS_CHANGED" then
    RebuildSpellTextureCache()
  elseif event == "PLAYER_ENTERING_WORLD" then
    ResetNameplateIdentity()
    playerGUID = GetGUID("player")
    NSCT:ScanNameplates(1)
    DebugLog("WORLD", "playerGUID=" .. tostring(playerGUID) .. " native scanner reset")
  elseif event == "PLAYER_TARGET_CHANGED" then
    NSCT:ScanNameplates(1)
    DebugLog("TARGET", "name=" .. tostring(UnitName("target")) .. " guid=" .. tostring(GetGUID("target")))
  elseif event == "CHAT_MSG_COMBAT_SELF_HITS" or event == "CHAT_MSG_COMBAT_SELF_MISSES" or event == "CHAT_MSG_SPELL_SELF_DAMAGE" or event == "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE" or event == "CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE" or event == "CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF" then
    NSCT:HandleNativeCombatEvent(event, arg1)
  elseif event == "RAW_COMBATLOG" then
    if not NativeOnlyEnabled() then
      NSCT:HandleRawCombatLog(arg1, arg2)
    end
  end
end)

frame:SetScript("OnUpdate", function()
  UpdateTexts()
  if fontTestFrame and fontTestHideAt and GetTime() >= fontTestHideAt then
    fontTestFrame:Hide()
    fontTestFrame = nil
    fontTestHideAt = nil
  end
  if sizeTestFrame and sizeTestHideAt and GetTime() >= sizeTestHideAt then
    sizeTestFrame:Hide()
    sizeTestFrame = nil
    sizeTestHideAt = nil
  end
  scanElapsed = scanElapsed + arg1
  if scanElapsed >= 0.20 then
    scanElapsed = 0
    NSCT:ScanNameplates(nil)
  end
end)

SLASH_NAMEPLATESCTVANILLA1 = "/np"
SLASH_NAMEPLATESCTVANILLA2 = "/nsct"
SlashCmdList["NAMEPLATESCTVANILLA"] = SlashHandler
