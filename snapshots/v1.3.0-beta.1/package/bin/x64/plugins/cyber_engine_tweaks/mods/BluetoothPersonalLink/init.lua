-- Bluetooth Personal Link 1.3.0-beta.1
-- An independent, local audio addon. It observes connections without replacing game logic.
local VERSION = "1.3.0-beta.1"
local pools = { connected = {}, disconnected = {} }
local bags = { connected = {}, disconnected = {} }
local previous = {}
local randomState = (math.floor(os.time()) % 2147483646) + 1
local lastEvent = nil
local DEFAULTS = { enabled = true, volume = 0.8, gainDb = 0, cooldownSeconds = 4, disconnectAnnouncement = false }
local config = {}
local warnings = {}
local pending, active = nil, nil
local playerKey, soundOwner, soundEvent = nil, nil, nil
local soundHandle, dynamicFactory, lastBackend = nil, nil, nil
local menuResumeRequests = 0
local audioMenuOpen = false
local lastClock, nextAllowed, busyUntil = 0, 0, 0
local playCount = 0
local overlayOpen, panelVisible, settingsDirty = false, true, false
local uiMessage, lastIssue = "", nil
local nativeMenu, nativeOptions = nil, {}
local nativeSyncing = false
local importInboxCount = 0
local pendingPreview, lastDuration = nil, nil

local function warnOnce(key, message)
  lastIssue = message
  if warnings[key] then return end
  warnings[key] = true
  print("[BluetoothPersonalLink] " .. message)
end

local function clock()
  lastClock = math.max(lastClock, os.time())
  return lastClock
end

local function bounded(value, fallback, minimum, maximum)
  if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
    return fallback
  end
  return math.max(minimum, math.min(maximum, value))
end

local function loadSettings()
  local data = {}
  local file = io.open("settings.json", "r")
  if file then
    local content = file:read("*a")
    file:close()
    local ok, decoded = pcall(function() return json.decode(content) end)
    if ok and type(decoded) == "table" then
      data = decoded
    else
      warnOnce("settings", "Invalid settings.json; using defaults.")
    end
  end
  config.enabled = DEFAULTS.enabled
  if type(data.enabled) == "boolean" then config.enabled = data.enabled end
  config.disconnectAnnouncement = DEFAULTS.disconnectAnnouncement
  if type(data.disconnectAnnouncement) == "boolean" then config.disconnectAnnouncement = data.disconnectAnnouncement end
  config.volume = bounded(data.volume, DEFAULTS.volume, 0, 1)
  config.gainDb = bounded(data.gainDb, DEFAULTS.gainDb, 0, 24)
  config.cooldownSeconds = bounded(data.cooldownSeconds, DEFAULTS.cooldownSeconds, 0, 30)
end

local function effectiveVolume()
  return config.volume * 10 ^ (config.gainDb / 20)
end

local function syncNativeOptions()
  if not nativeMenu or type(nativeMenu.setOption) ~= "function" or nativeSyncing then return end
  nativeSyncing = true
  local ok, problem = pcall(function()
    for key, option in pairs(nativeOptions) do nativeMenu.setOption(option, config[key]) end
  end)
  nativeSyncing = false
  if not ok then warnOnce("native_sync", "Cannot refresh the optional settings menu: " .. tostring(problem)) end
end

local function loadPools()
  local data = nil
  local file = io.open("clips.json", "r")
  if file then
    local content = file:read("*a")
    file:close()
    local ok, decoded = pcall(function() return json.decode(content) end)
    if ok and type(decoded) == "table" then data = decoded end
  end
  for _, kind in ipairs({ "connected", "disconnected" }) do
    pools[kind], bags[kind] = {}, {}
    local seen = {}
    if data and type(data[kind]) == "table" then
      for _, name in ipairs(data[kind]) do
        if #pools[kind] >= 128 then break end
        if type(name) == "string" and #name <= 128 and name:match("^[A-Za-z0-9_]+$") and not seen[name] then
          seen[name] = true
          pools[kind][#pools[kind] + 1] = name
        end
      end
    end
  end
  if #pools.connected == 0 then
    warnOnce("pool", "No valid connection recordings in clips.json; connection announcements are silent.")
  end
end

local function shuffled(items)
  local result = {}
  for i, item in ipairs(items) do result[i] = item end
  for i = #result, 2, -1 do
    -- A private PRNG avoids reseeding or consuming another mod's random stream.
    randomState = (randomState * 48271) % 2147483647
    local j = (randomState % i) + 1
    result[i], result[j] = result[j], result[i]
  end
  return result
end

local function entityKey(object)
  if not object then return nil end
  local ok, key = pcall(function()
    local id = object:GetEntityID()
    if not id or id.hash == nil then return nil end
    return tostring(id.hash)
  end)
  if ok and key and key ~= "0" and key ~= "0ULL" then return key end
  return nil
end

local function localPlayer()
  local ok, player = pcall(function() return Game.GetPlayer() end)
  if ok then return player end
  return nil
end

local function isLocal(puppet)
  local key = entityKey(puppet)
  return key ~= nil and key == entityKey(localPlayer())
end

local function stopSound()
  local handle, owner, event = soundHandle, soundOwner, soundEvent
  soundHandle, soundOwner, soundEvent = nil, nil, nil
  if handle then
    pcall(function() handle:Stop() end)
  elseif owner and event then
    pcall(function()
      Game.GetAudioSystemExt():Stop(CName.new(event), owner, CName.new("V"))
    end)
  end
end

local function resolveDynamicFactory()
  dynamicFactory = nil
  if type(GetSingleton) ~= "function" then return end
  local ok, factory = pcall(function()
    local value = GetSingleton("Audioware.DynamicSoundEvent")
    if value and type(value.Create) == "function" then return value end
    return nil
  end)
  if ok then dynamicFactory = factory
  else warnOnce("dynamic_factory", "Tracked audio is unavailable; using ordinary Audioware playback. " .. tostring(factory)) end
end

local function resumeOwnSound()
  if not config.enabled or config.volume <= 0 or not soundHandle then return end
  if clock() >= busyUntil then return end
  local ok, problem = pcall(function() soundHandle:Resume() end)
  if ok then menuResumeRequests = menuResumeRequests + 1
  else warnOnce("menu_resume", "Cannot resume this addon's sound after the menu transition: " .. tostring(problem)) end
end

local function onAudioMenu(_, opened)
  if type(opened) ~= "boolean" then return end
  audioMenuOpen = opened
  if opened then resumeOwnSound() end
end

local function reset()
  stopSound()
  pending, active = nil, nil
  nextAllowed, busyUntil = 0, 0
  pendingPreview = nil
end

local function refreshPlayer()
  local key = entityKey(localPlayer())
  if key ~= playerKey then
    reset()
    playerKey = key
  end
end

local function gamePaused()
  local ok, paused = pcall(function() return Game.GetTimeSystem():IsPausedState() end)
  if not ok then return nil, tostring(paused) end
  if type(paused) ~= "boolean" then return nil, "Pause query returned no boolean state." end
  return paused
end

local function gameInMenu()
  local ok, inMenu = pcall(function()
    local definitions = Game.GetAllBlackboardDefs()
    local blackboard = Game.GetBlackboardSystem():Get(definitions.UI_System)
    return blackboard:GetBool(definitions.UI_System.IsInMenu)
  end)
  if not ok then return nil, tostring(inMenu) end
  if type(inMenu) ~= "boolean" then return nil, "Menu query returned no boolean state." end
  return inMenu
end

local function makeAudioSettings()
  local settings = NewObject("Audioware.AudioSettingsExt")
  if not settings then error("Cannot construct Audioware.AudioSettingsExt.") end
  local initialRate = settings.playbackRate
  settings.startPosition = 0.0
  settings.loop = false
  settings.volume = effectiveVolume()
  settings.panning = 0.0
  settings.playbackRate = 1.0
  settings.affectedByTimeDilation = false
  return settings, initialRate
end

local function diagnostic()
  local player = localPlayer()
  local paused, pauseError = gamePaused()
  local inMenu, menuError = gameInMenu()
  local result = {
    version = VERSION, playerPresent = entityKey(player) ~= nil,
    playerEntity = entityKey(player), paused = paused, pauseError = pauseError,
    inMenu = inMenu, menuError = menuError,
    overlayOpen = overlayOpen, pendingPreview = pendingPreview ~= nil,
    dynamicPlaybackAvailable = dynamicFactory ~= nil, lastBackend = lastBackend,
    menuResumeRequests = menuResumeRequests, audioMenuOpen = audioMenuOpen,
    requestedPlaybackRate = 1.0,
    effectiveVolume = effectiveVolume(),
    config = { enabled = config.enabled, volume = config.volume, gainDb = config.gainDb,
      cooldownSeconds = config.cooldownSeconds, disconnectAnnouncement = config.disconnectAnnouncement },
    recordings = {}
  }
  local ok, audio = pcall(function() return Game.GetAudioSystemExt() end)
  result.audioAvailable = ok and audio ~= nil
  if not result.audioAvailable then
    result.audioError = ok and "Audioware is unavailable." or tostring(audio)
    return result
  end
  local versionOk, version = pcall(function() return audio:Version() end)
  if versionOk then result.audioVersion = tostring(version) else result.audioVersionError = tostring(version) end
  local settingsOk, settings, initialRate = pcall(makeAudioSettings)
  if settingsOk then
    result.constructedPlaybackRate = initialRate
    result.requestedSettings = { startPosition = settings.startPosition, loop = settings.loop,
      volume = settings.volume, panning = settings.panning, playbackRate = settings.playbackRate,
      affectedByTimeDilation = settings.affectedByTimeDilation }
  else result.settingsError = tostring(settings) end
  for _, name in ipairs(pools.connected) do
    local found, seconds = pcall(function() return audio:Duration(CName.new(name)) end)
    local entry = { event = name }
    if found then entry.durationSeconds = seconds else entry.error = tostring(seconds) end
    result.recordings[#result.recordings + 1] = entry
  end
  return result
end

local function play(kind)
  if not config.enabled or config.volume <= 0 then return false end
  local now = clock()
  if now < nextAllowed or now < busyUntil then return false end
  local player = localPlayer()
  if not entityKey(player) then return false end
  if #pools[kind] == 0 then return false end
  local ok, audio, settings = pcall(function()
    local system = Game.GetAudioSystemExt()
    if not system then error("Audioware is unavailable.") end
    local settings = makeAudioSettings()
    return system, settings
  end)
  if not ok then
    warnOnce("audio", "Cannot play announcement: " .. tostring(audio))
    return false
  end
  local available, durationByName, errors = {}, {}, {}
  for _, name in ipairs(pools[kind]) do
    local valid, seconds = pcall(function() return audio:Duration(CName.new(name)) end)
    if valid and type(seconds) == "number" and seconds > 0 and seconds == seconds and seconds ~= math.huge then
      available[#available + 1], durationByName[name] = name, seconds
    else
      errors[#errors + 1] = "Duration(" .. name .. "): " .. tostring(seconds)
    end
  end
  if #available == 0 then
    warnOnce("missing_" .. kind, "No playable " .. kind .. " recordings; check Audioware and restart. " .. table.concat(errors, " | "))
    return false
  end
  local savedRandomState = randomState
  local queue = {}
  for _, name in ipairs(bags[kind]) do
    if durationByName[name] then queue[#queue + 1] = name end
  end
  if #queue == 0 then queue = shuffled(available) end
  if queue[1] == previous[kind] and #available > 1 then
    if #queue == 1 then queue = shuffled(available) end
    for i = 2, #queue do
      if queue[i] ~= previous[kind] then queue[1], queue[i] = queue[i], queue[1]; break end
    end
  end
  local chosen, duration, chosenHandle = nil, nil, nil
  local owner = player:GetEntityID()
  local attempted = {}
  -- Stop the previous handle before queuing a replacement. Ext fallback stops
  -- by event/owner, which would also match a newly queued copy of the same clip.
  stopSound()
  while true do
    if #queue == 0 then
      local untried = {}
      for _, name in ipairs(available) do
        if not attempted[name] then untried[#untried + 1] = name end
      end
      queue = shuffled(untried)
      if #queue == 0 then break end
      if queue[1] == previous[kind] and #queue > 1 then queue[1], queue[2] = queue[2], queue[1] end
    end
    local name = table.remove(queue, 1)
    attempted[name] = true
    local candidateHandle = nil
    local played, playError = pcall(function()
      if dynamicFactory then
        candidateHandle = dynamicFactory:Create(CName.new(name), settings)
        if not candidateHandle then error("Audioware did not create a tracked sound event.") end
        player:QueueEvent(candidateHandle)
      else
        audio:Play(CName.new(name), owner, CName.new("V"), Enum.new("scnDialogLineType", "Regular"), settings)
      end
    end)
    if played then chosen, duration, chosenHandle = name, durationByName[name], candidateHandle; break end
    if candidateHandle then pcall(function() candidateHandle:Stop() end) end
    errors[#errors + 1] = "Play(" .. name .. "): " .. tostring(playError)
  end
  if not chosen then
    randomState = savedRandomState
    warnOnce("playback_" .. kind, "Playback failed for every available " .. kind .. " recording. " .. table.concat(errors, " | "))
    return false
  end
  bags[kind], previous[kind], lastEvent = queue, chosen, chosen
  soundOwner, soundEvent, soundHandle = owner, chosen, chosenHandle
  lastBackend = chosenHandle and "dynamic" or "ext"
  -- os.time is unscaled but has one-second resolution. The extra second prevents overlap.
  busyUntil = now + math.ceil(duration) + 1
  nextAllowed = now + config.cooldownSeconds
  playCount = playCount + 1
  lastDuration = duration
  lastIssue = #errors > 0 and ("Skipped audio events: " .. table.concat(errors, " | ")) or nil
  if soundHandle and audioMenuOpen then resumeOwnSound() end
  return true
end

local function saveSettings()
  local ok, problem = pcall(function()
    local payload = json.encode({
      enabled = config.enabled,
      volume = bounded(config.volume, DEFAULTS.volume, 0, 1),
      gainDb = bounded(config.gainDb, DEFAULTS.gainDb, 0, 24),
      cooldownSeconds = bounded(config.cooldownSeconds, DEFAULTS.cooldownSeconds, 0, 30),
      disconnectAnnouncement = config.disconnectAnnouncement
    })
    if type(payload) ~= "string" then error("JSON encoder returned no settings.") end
    local file, reason = io.open("settings.json", "w")
    if not file then error(reason or "Cannot open settings.json for writing.") end
    local written, writeError = pcall(function()
      local result, detail = file:write(payload .. "\n")
      if not result then error(detail or "Cannot write settings.json.") end
      local closed, closeError = file:close()
      if not closed then error(closeError or "Cannot close settings.json.") end
    end)
    if not written then
      pcall(function() file:close() end)
      error(writeError)
    end
  end)
  if not ok then
    uiMessage = "Settings were not saved. Check file access and the CET log."
    warnOnce("save", "Cannot save settings: " .. tostring(problem))
    return false
  end
  settingsDirty = false
  syncNativeOptions()
  uiMessage = "Settings saved."
  return true
end

local function reloadSettings()
  loadSettings()
  loadPools()
  settingsDirty = false
  syncNativeOptions()
  if not config.enabled or config.volume <= 0 then pendingPreview = nil; stopSound() end
  uiMessage = "Settings and sound lists reloaded."
end

local function setEnabled(enabled)
  if type(enabled) ~= "boolean" then return false end
  if config.enabled ~= enabled then settingsDirty = true end
  config.enabled = enabled
  if not enabled then pendingPreview = nil; stopSound() end
  return true
end

local function runPreview()
  local result = play("connected")
  if result then
    uiMessage = "Playback requested: " .. tostring(lastEvent) .. " (" .. tostring(lastDuration) .. " s, rate 1.0)."
  elseif not config.enabled then
    uiMessage = "Enable announcements before testing."
  elseif config.volume <= 0 then
    uiMessage = "Raise the volume before testing."
  elseif #pools.connected == 0 then
    uiMessage = "No connection sounds loaded. Check clips.json and reload sound lists."
  elseif not entityKey(localPlayer()) then
    uiMessage = "Load a game save before testing audio."
  else
    uiMessage = "Not played. Wait for the current sound/cooldown; check the message below if it stays silent."
  end
  print("[BluetoothPersonalLink] Preview: " .. uiMessage .. (lastIssue and (" " .. lastIssue) or ""))
  return result
end

local function preview()
  refreshPlayer()
  local paused, pauseError = gamePaused()
  local inMenu, menuError = gameInMenu()
  if overlayOpen or paused ~= false or inMenu ~= false then
    pendingPreview = { expires = clock() + 30 }
    uiMessage = "Test queued. Close the game menus and CET overlay to hear it."
    local queryError = pauseError or menuError
    if queryError then lastIssue = "Preview state query: " .. queryError end
    print("[BluetoothPersonalLink] Preview: " .. uiMessage .. (queryError and (" " .. queryError) or ""))
    return false
  end
  return runPreview()
end

local function update()
  refreshPlayer()
  if not pendingPreview then return end
  if clock() >= pendingPreview.expires then
    pendingPreview = nil
    uiMessage = "Queued test expired. Close menus and request another test."
    print("[BluetoothPersonalLink] Preview: " .. uiMessage)
    return
  end
  if overlayOpen then return end
  local paused, pauseError = gamePaused()
  if paused == false then
    local inMenu, menuError = gameInMenu()
    if inMenu == false then
      pendingPreview = nil
      runPreview()
    elseif menuError then
      warnOnce("preview_menu", "Cannot check game menu state for queued preview: " .. menuError)
    end
  elseif pauseError then
    warnOnce("preview_pause", "Cannot check game pause state for queued preview: " .. pauseError)
  end
end

local function scanInbox()
  importInboxCount = 0
  local discovered = { connected = {}, disconnected = {} }
  if type(dir) ~= "function" then return discovered end
  for _, kind in ipairs({ "connected", "disconnected" }) do
    local ok, entries = pcall(dir, "audio-inbox/" .. kind)
    if ok and type(entries) == "table" then
      for _, entry in ipairs(entries) do
        local name = type(entry) == "table" and entry.name or nil
        local ext = type(name) == "string" and name:lower():match("%.([a-z0-9]+)$") or nil
        if type(name) == "string" and #name <= 180 and not name:find("[/\\%c]")
          and (ext == "wav" or ext == "mp3" or ext == "ogg" or ext == "flac")
          and entry.type == "file" and #discovered[kind] < 128 then
          discovered[kind][#discovered[kind] + 1] = { file = name, volume = 1.0 }
          importInboxCount = importInboxCount + 1
        end
      end
    end
    table.sort(discovered[kind], function(a, b) return a.file < b.file end)
  end
  return discovered
end

local function reloadSoundLists()
  stopSound()
  loadPools()
  local discovered = scanInbox()
  if importInboxCount > 0 then
    local ok, problem = pcall(function()
      local content = json.encode({ schema = 1, connected = discovered.connected, disconnected = discovered.disconnected })
      local file = io.open("audio-inbox/pending-import.json", "w")
      if not file then error("Cannot save the inbox plan.") end
      local wrote, writeError = pcall(function() local result, problem = file:write(content); if not result then error(problem or "Cannot write inbox plan.") end end)
      file:close()
      if not wrote then error(writeError) end
    end)
    if not ok then warnOnce("inbox_plan", tostring(problem)) end
    uiMessage = tostring(importInboxCount) .. " inbox files detected. Run Manage Audio, import, then restart the game. Registered sound selections have been reloaded."
  else
    uiMessage = "Registered sound selections reloaded. New files need import and a full game restart. CET Reload all mods does not load new Audioware banks."
  end
  return true
end

local function showAudioHelp()
  panelVisible = true
  uiMessage = "Add recordings: put .wav, .mp3, .ogg or .flac files in this mod's audio-inbox/connected or disconnected folder. Run docs/tools/Manage-Audio.cmd and click Import, then restart Cyberpunk. It generates the sound manifest and lists for you."
end

local function registerNativeMenu()
  if type(GetMod) ~= "function" then return end
  local ok, ns = pcall(GetMod, "nativeSettings")
  if not ok or not ns or type(ns.addTab) ~= "function" then return end
  local success, problem = pcall(function()
    local path = "/bluetoothPersonalLink"
    if not ns.pathExists or not ns.pathExists(path) then
      ns.addTab(path, "Bluetooth Personal Link", function() if settingsDirty then saveSettings() end end)
    end
    ns.addSubcategory(path .. "/playback", "Connection notifications")
    local group = path .. "/playback"
    local function commit() if nativeSyncing then return end; settingsDirty = true; saveSettings() end
    nativeOptions.enabled = ns.addSwitch(group, "Enable notifications", "Play a local notification after V's personal cable connects.", config.enabled, DEFAULTS.enabled, function(value) setEnabled(value); commit() end)
    nativeOptions.volume = ns.addRangeFloat(group, "Volume", "Adjust these notifications only. Close menus to hear the test.", 0, 1, 0.05, "%.2f", config.volume, DEFAULTS.volume, function(value) config.volume = bounded(value, DEFAULTS.volume, 0, 1); commit(); if config.volume <= 0 then stopSound() end end)
    nativeOptions.gainDb = ns.addRangeFloat(group, "Notification boost (dB)", "Additional gain for quiet recordings. Start low. Applies to the next notification.", 0, 24, 1, "%.0f dB", config.gainDb, DEFAULTS.gainDb, function(value) config.gainDb = bounded(value, DEFAULTS.gainDb, 0, 24); commit() end)
    nativeOptions.cooldownSeconds = ns.addRangeInt(group, "Cooldown", "Minimum seconds between notifications.", 0, 30, 1, math.floor(config.cooldownSeconds), DEFAULTS.cooldownSeconds, function(value) config.cooldownSeconds = bounded(value, DEFAULTS.cooldownSeconds, 0, 30); commit() end)
    nativeOptions.disconnectAnnouncement = ns.addSwitch(group, "Disconnect notifications", "Use the disconnected sound list when V unplugs.", config.disconnectAnnouncement, DEFAULTS.disconnectAnnouncement, function(value) config.disconnectAnnouncement = value == true; commit() end)
    ns.addButton(group, "Test connection sound", "Queues a test. Close the game menu and CET to hear it.", "Test", 45, function() preview() end)
    ns.addSubcategory(path .. "/sounds", "Add your own sounds")
    ns.addButton(path .. "/sounds", "Reload sound selections", "Reloads clips.json and scans audio-inbox. New files need import and a full restart with stable Audioware.", "Reload", 45, reloadSoundLists)
    ns.addButton(path .. "/sounds", "How to add recordings", "Drop recordings into audio-inbox, run docs/tools/Manage-Audio.cmd, import, then restart Cyberpunk. Open CET for the guide and diagnostics.", "Show guide", 45, showAudioHelp)
    nativeMenu = ns
  end)
  if not success then warnOnce("native_settings", "Optional settings integration unavailable; CET controls still work. " .. tostring(problem)) end
end


local function drawPanel()
  if not overlayOpen or not panelVisible then return end
  local began = false
  local ok, problem = pcall(function()
    if type(ImGui.SetNextWindowSize) == "function" then ImGui.SetNextWindowSize(590, 650, ImGuiCond and ImGuiCond.FirstUseEver or 0) end
    local flags = ImGuiWindowFlags and ImGuiWindowFlags.NoCollapse or 0
    local visible = ImGui.Begin("Bluetooth Personal Link", true, flags)
    began = true
    if not visible then panelVisible = false; return end
    ImGui.Text("Version " .. VERSION)
    ImGui.TextWrapped("Requires Audioware and its dependencies, plus Cyber Engine Tweaks. Native Settings / Unified Mod Settings are optional.")
    ImGui.Separator()
    local value, changed = ImGui.Checkbox("Enabled", config.enabled)
    if changed and type(value) == "boolean" then setEnabled(value) end
    value, changed = ImGui.SliderFloat("Volume", config.volume, 0.0, 1.0)
    if changed then
      config.volume = bounded(value, DEFAULTS.volume, 0, 1)
      settingsDirty = true
      if config.volume <= 0 then pendingPreview = nil; stopSound() end
    end
    value, changed = ImGui.SliderFloat("Audio boost (dB)", config.gainDb, 0.0, 24.0)
    if changed then config.gainDb = bounded(value, DEFAULTS.gainDb, 0, 24); settingsDirty = true end
    ImGui.TextWrapped("Boost increases only these notifications and applies to the next sound.")
    value, changed = ImGui.SliderInt("Cooldown (seconds)", math.floor(config.cooldownSeconds), 0, 30)
    if changed then config.cooldownSeconds = bounded(value, DEFAULTS.cooldownSeconds, 0, 30); settingsDirty = true end
    value, changed = ImGui.Checkbox("Disconnect announcements", config.disconnectAnnouncement)
    if changed and type(value) == "boolean" then config.disconnectAnnouncement = value; settingsDirty = true end
    ImGui.Text("Connection sounds: " .. #pools.connected .. " | Disconnect sounds: " .. #pools.disconnected)
    ImGui.TextWrapped("Last requested: " .. tostring(lastEvent or "none"))
    if ImGui.Button("Test connection sound") then preview() end
    if uiMessage ~= "" then ImGui.TextWrapped(uiMessage) end
    if lastIssue then ImGui.TextWrapped(lastIssue) end
    if ImGui.Button("Reload sound selections / scan inbox") then reloadSoundLists() end
    if ImGui.Button("Save settings") then saveSettings() end
    if ImGui.Button("Reload saved settings") then reloadSettings() end
    ImGui.Text(settingsDirty and "Unsaved settings" or "Settings saved or unchanged")
    ImGui.Separator()
    ImGui.TextWrapped("Settings also appear in Mods > Bluetooth Personal Link when Native Settings is installed. Unified Mod Settings can display that same tab.")
    ImGui.Separator()
    ImGui.Text("ADD YOUR OWN RECORDINGS")
    ImGui.TextWrapped("1. Drop short .wav, .mp3, .ogg or .flac recordings into audio-inbox/connected or disconnected inside this mod folder.")
    ImGui.TextWrapped("2. Run docs/tools/Manage-Audio.cmd. Click Open Inbox to open the sound folder. Click Import to generate the sound manifest and lists automatically.")
    ImGui.TextWrapped("3. Fully restart Cyberpunk, then use Test. Reload sound selections changes registered selections immediately. CET Reload all mods cannot register new files in stable Audioware.")
    if ImGui.Button("Copy audio inbox location") then
      if type(ImGui.SetClipboardText) == "function" then ImGui.SetClipboardText("bin\\x64\\plugins\\cyber_engine_tweaks\\mods\\BluetoothPersonalLink\\audio-inbox"); uiMessage = "Inbox path copied (relative to Cyberpunk 2077). Manage Audio has an Open Inbox button." end
    end
    if ImGui.Button("Show audio setup guide") then showAudioHelp() end
    ImGui.TextWrapped("Use recordings you own or have permission to use. Keep active audio files in place until the game is closed.")
  end)
  if began then
    local ended, endError = pcall(function() ImGui.End() end)
    if not ended then warnOnce("ui_end", "Cannot close settings panel: " .. tostring(endError)) end
  end
  if not ok then warnOnce("ui", "Settings panel error: " .. tostring(problem)) end
end

local function onToggle(device, toggle, puppet)
  refreshPlayer()
  if not isLocal(puppet) then return end
  local key = entityKey(device)
  if not key then return end
  if toggle then
    if active ~= key then pending = key end
  else
    if pending == key then pending = nil end
    if active == key then
      active = nil
      if config.disconnectAnnouncement then play("disconnected") end
    end
  end
end

local function onAction(device, evt)
  refreshPlayer()
  local key = entityKey(device)
  if not key or key ~= pending or key == active then return end
  if not evt or not evt:IsCompleted() then return end
  -- The initial toggle only starts the animation. Announce after the device reports CONNECTED.
  if not isLocal(evt:GetExecutor()) then return end
  if not device:GetDevicePS():IsPersonalLinkConnected() then return end
  pending, active = nil, key
  play("connected")
end

local function guarded(name, callback)
  return function(...)
    local ok, problem = pcall(callback, ...)
    if not ok then warnOnce(name, name .. ": " .. tostring(problem)) end
  end
end

registerForEvent("onInit", function()
  loadSettings()
  loadPools()
  resolveDynamicFactory()
  if dynamicFactory then
    audioMenuOpen = gameInMenu() == true
    local ok, problem = pcall(function()
      ObserveAfter("Audioware.LifecycleSubSystem", "OnMenu", guarded("menu_resume", onAudioMenu))
    end)
    if not ok then
      dynamicFactory = nil
      warnOnce("menu_hook", "Tracked menu playback is unavailable; using ordinary Audioware playback. " .. tostring(problem))
    end
  end
  ObserveAfter("Device", "TogglePersonalLink", guarded("toggle", onToggle))
  ObserveAfter("Device", "OnTogglePersonalLink", guarded("connection", onAction))
  ObserveAfter("PlayerPuppet", "OnGameAttached", guarded("attach", function(puppet)
    if isLocal(puppet) then
      reset()
      playerKey = entityKey(puppet)
    end
  end))
  ObserveBefore("PlayerPuppet", "OnDetach", guarded("detach", function(puppet)
    local key = entityKey(puppet)
    if key and key == playerKey then reset(); playerKey = nil end
  end))
  refreshPlayer()
  scanInbox()
  registerNativeMenu()
  print("[BluetoothPersonalLink] " .. VERSION .. " ready (local audio only).")
end)

registerForEvent("onUpdate", guarded("update", update))
registerForEvent("onShutdown", reset)
registerForEvent("onOverlayOpen", function() overlayOpen, panelVisible = true, true end)
registerForEvent("onOverlayClose", function() overlayOpen = false end)
registerForEvent("onDraw", drawPanel)

return {
  test = preview,
  diagnostic = diagnostic,
  reloadSettings = reloadSettings,
  reloadSounds = reloadSoundLists,
  showAudioHelp = showAudioHelp,
  setEnabled = setEnabled,
  saveSettings = saveSettings,
  showPanel = function(show)
    if show == nil then show = true end
    if type(show) ~= "boolean" then return false end
    panelVisible = show
    return true
  end,
  status = function()
    return {
      version = VERSION, enabled = config.enabled, volume = config.volume, gainDb = config.gainDb,
      effectiveVolume = effectiveVolume(),
      cooldownSeconds = config.cooldownSeconds,
      disconnectAnnouncement = config.disconnectAnnouncement,
      pendingDevice = pending, activeDevice = active, announcements = playCount,
      connectedClips = #pools.connected, disconnectedClips = #pools.disconnected,
      lastEvent = lastEvent, connectedRemaining = #bags.connected,
      settingsDirty = settingsDirty, panelVisible = panelVisible,
      overlayOpen = overlayOpen, lastIssue = lastIssue,
      pendingPreview = pendingPreview ~= nil, lastDuration = lastDuration,
      nativeSettingsAvailable = nativeMenu ~= nil, importInboxFiles = importInboxCount,
      dynamicPlaybackAvailable = dynamicFactory ~= nil, lastBackend = lastBackend,
      menuResumeRequests = menuResumeRequests, audioMenuOpen = audioMenuOpen
    }
  end
}
