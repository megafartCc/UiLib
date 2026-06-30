return function(Library, context)
    local HttpService = context.HttpService
    local SharedState = context.SharedState

    local function sanitizePathSegment(value)
        local text = tostring(value or "uilib")
        text = text:gsub("[%c<>:\"/\\|%?%*]", "_")
        text = text:gsub("%s+", "_")
        text = text:gsub("_+", "_")
        text = text:gsub("^_+", "")
        text = text:gsub("_+$", "")
        if text == "" then
            text = "uilib"
        end
        return string.sub(text, 1, 120)
    end

    Library._configItems = {}
    Library._configName = nil
    Library._windowStorageName = nil
    Library._autoSave = true
    Library._autoSaveDelay = 2
    Library._dirty = false
    Library._controlSyncDepth = 0
    Library._configReplayDepth = 0
    Library._configItemOrder = {}
    Library._loadedConfigData = nil
    Library._configReplayToken = 0
    Library._configMutationSerial = 0
    Library._configLoadGeneration = 0
    Library._configAppliedGenerationByKey = {}
    Library._autoLoadEnabled = true
    Library._autoLoadData = nil
    Library.AutoLoadBootstrapUrl = "https://raw.githubusercontent.com/megafartCc/UiLib/main/build.lua"

    local CONFIG_FOLDER = "UnknownHub"
    local runtimeDataStore = {}
    Library._configFolder = CONFIG_FOLDER

    function Library:GetConfigFolder()
        return CONFIG_FOLDER
    end

    function Library:_ensureFolder()
        if type(isfolder) == "function" then
            local ok, exists = pcall(isfolder, CONFIG_FOLDER)
            if ok and exists then
                return true
            end
        end

        if type(makefolder) == "function" then
            pcall(makefolder, CONFIG_FOLDER)
        end

        if type(isfolder) == "function" then
            local ok, exists = pcall(isfolder, CONFIG_FOLDER)
            return ok and exists
        end

        return type(makefolder) ~= "function"
    end

    function Library:_getConfigFileName()
        if not self._configName then return nil end
        return sanitizePathSegment(self._configName)
    end

    function Library:_getConfigPath()
        local fileName = self:_getConfigFileName()
        if not fileName then return nil end
        return CONFIG_FOLDER .. "/" .. fileName .. ".json"
    end

    function Library:_getFlatConfigPath()
        local fileName = self:_getConfigFileName()
        if not fileName then return nil end
        return CONFIG_FOLDER .. "_" .. fileName .. ".json"
    end

    function Library:_getStorageBaseName()
        return sanitizePathSegment(self._configName or self._windowStorageName or "uilib")
    end

    function Library:_getDataPath(tag)
        if type(tag) ~= "string" or tag == "" then
            return nil
        end
        return CONFIG_FOLDER .. "/" .. self:_getStorageBaseName() .. "_" .. sanitizePathSegment(tag) .. ".json"
    end

    function Library:_getFlatDataPath(tag)
        if type(tag) ~= "string" or tag == "" then
            return nil
        end
        return CONFIG_FOLDER .. "_" .. self:_getStorageBaseName() .. "_" .. sanitizePathSegment(tag) .. ".json"
    end

    function Library:_getRuntimeDataKey(tag)
        if type(tag) ~= "string" or tag == "" then
            return nil
        end
        return self:_getStorageBaseName() .. "::" .. sanitizePathSegment(tag)
    end

    local function normalizePresetName(value)
        local valueType = type(value)
        if valueType == "table" then
            value = value.Name or value.name or value.label or value.Label
            valueType = type(value)
        end

        if valueType ~= "string" and valueType ~= "number" then
            return nil
        end

        local text = tostring(value or ""):match("^%s*(.-)%s*$")
        if text == "" then
            return nil
        end

        if text == "No Presets" then
            return nil
        end

        if text:sub(1, 6):lower() == "table:" then
            return nil
        end

        return text
    end

    function Library:_readJsonFile(path)
        if type(path) ~= "string" or path == "" or type(readfile) ~= "function" then
            return nil
        end

        if type(isfile) == "function" then
            local okExists, exists = pcall(isfile, path)
            if okExists and not exists then
                return nil
            end
        end

        local ok, raw = pcall(readfile, path)
        if not ok or type(raw) ~= "string" or raw == "" then
            return nil
        end

        local okDecode, decoded = pcall(function()
            return HttpService:JSONDecode(raw)
        end)
        if not okDecode then
            return nil
        end

        return decoded
    end

    function Library:ReadData(tag)
        local memoryKey = self:_getRuntimeDataKey(tag)
        if memoryKey and runtimeDataStore[memoryKey] ~= nil then
            return runtimeDataStore[memoryKey]
        end

        local primary = self:_getDataPath(tag)
        local fallback = self:_getFlatDataPath(tag)

        local decoded = self:_readJsonFile(primary)
        if decoded ~= nil then
            return decoded
        end

        return self:_readJsonFile(fallback)
    end

    function Library:WriteData(tag, value)
        local memoryKey = self:_getRuntimeDataKey(tag)
        if memoryKey then
            runtimeDataStore[memoryKey] = value
        end

        local path = self:_getDataPath(tag)
        if not path or type(writefile) ~= "function" then
            return memoryKey ~= nil, "memory"
        end

        local okEncode, encoded = pcall(function()
            return HttpService:JSONEncode(value)
        end)
        if not okEncode or type(encoded) ~= "string" then
            return false, "json encode failed"
        end

        local paths = {}
        if self:_ensureFolder() then
            table.insert(paths, path)
        end

        local flatPath = self:_getFlatDataPath(tag)
        if flatPath and flatPath ~= path then
            table.insert(paths, flatPath)
        end

        local lastError = "writefile failed"
        for _, candidatePath in ipairs(paths) do
            local okWrite, writeErr = pcall(writefile, candidatePath, encoded)
            if okWrite then
                return true, candidatePath
            end
            lastError = tostring(writeErr or lastError)
        end

        lastError = lastError:gsub("[%c\r\n]+", " ")
        if memoryKey then
            return true, "memory"
        end
        return false, lastError
    end

    local function trimString(value)
        return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
    end

    local function quoteLuaString(value)
        local text = tostring(value or "")
        text = text:gsub("\\", "\\\\")
        text = text:gsub("\"", "\\\"")
        text = text:gsub("\r", "\\r")
        text = text:gsub("\n", "\\n")
        return "\"" .. text .. "\""
    end

    local function getQueueOnTeleport()
        if type(queue_on_teleport) == "function" then
            return queue_on_teleport
        end
        if type(queueonteleport) == "function" then
            return queueonteleport
        end
        if type(syn) == "table" then
            if type(syn.queue_on_teleport) == "function" then
                return function(source)
                    return syn.queue_on_teleport(source)
                end
            end
            if type(syn.queueonteleport) == "function" then
                return function(source)
                    return syn.queueonteleport(source)
                end
            end
        end
        if type(fluxus) == "table" and type(fluxus.queue_on_teleport) == "function" then
            return function(source)
                return fluxus.queue_on_teleport(source)
            end
        end
        return nil
    end

    local function getAutoLoadStore()
        if type(getgenv) == "function" then
            local ok, env = pcall(getgenv)
            if ok and type(env) == "table" then
                return env
            end
        end
        if type(_G) == "table" then
            return _G
        end
        return nil
    end

    local function readOptionalBoolean(payload)
        if type(payload) == "boolean" then
            return payload
        end
        if type(payload) ~= "table" then
            return nil
        end

        local value = payload.enabled
        if value == nil then
            value = payload.Enabled
        end
        if value == nil then
            value = payload.autoLoad
        end
        if value == nil then
            value = payload.AutoLoad
        end
        if value == nil then
            return nil
        end

        return value == true
    end

    local function appendNormalizedId(out, seen, value)
        local text = trimString(value)
        if text == "" then
            return
        end
        if seen[text] then
            return
        end
        seen[text] = true
        table.insert(out, text)
    end

    local function normalizeIdList(...)
        local out = {}
        local seen = {}

        local function collect(value)
            if type(value) == "table" then
                for _, entry in ipairs(value) do
                    collect(entry)
                end
                for key, entry in pairs(value) do
                    if type(key) ~= "number" then
                        if entry == true then
                            appendNormalizedId(out, seen, key)
                        else
                            collect(entry)
                        end
                    end
                end
                return
            end

            appendNormalizedId(out, seen, value)
        end

        for index = 1, select("#", ...) do
            collect(select(index, ...))
        end

        return out
    end

    local function currentGameId()
        local ok, value = pcall(function()
            return game.GameId
        end)
        if ok then
            return trimString(value)
        end
        return ""
    end

    local function currentPlaceId()
        local ok, value = pcall(function()
            return game.PlaceId
        end)
        if ok then
            return trimString(value)
        end
        return ""
    end

    local function currentJobId()
        local ok, value = pcall(function()
            return game.JobId
        end)
        if ok then
            return trimString(value)
        end
        return ""
    end

    local function listContains(values, target)
        target = trimString(target)
        if target == "" then
            return false
        end
        for _, value in ipairs(values or {}) do
            if trimString(value) == target then
                return true
            end
        end
        return false
    end

    local function normalizeAutoLoadData(payload)
        if type(payload) ~= "table" then
            payload = {}
        end

        local enabled = readOptionalBoolean(payload)
        if enabled == nil then
            enabled = true
        end

        local loaderUrl = trimString(payload.loaderUrl or payload.LoaderUrl or payload.url or payload.Url)
        local bootstrapUrl = trimString(payload.bootstrapUrl or payload.BootstrapUrl or Library.AutoLoadBootstrapUrl)
        if bootstrapUrl == "" then
            bootstrapUrl = Library.AutoLoadBootstrapUrl
        end

        return {
            version = 1,
            enabled = enabled,
            loaderUrl = loaderUrl,
            bootstrapUrl = bootstrapUrl,
            gameIds = normalizeIdList(payload.gameIds, payload.GameIds, payload.game_id, payload.gameId, payload.GameId),
            placeIds = normalizeIdList(payload.placeIds, payload.PlaceIds, payload.place_id, payload.placeId, payload.PlaceId),
            scriptId = trimString(payload.scriptId or payload.ScriptId or payload.script_id),
            projectId = trimString(payload.projectId or payload.ProjectId or payload.project_id),
            mode = trimString(payload.mode or payload.Mode),
            configName = trimString(payload.configName or payload.ConfigName),
        }
    end

    local function autoLoadMatchesCurrentTarget(data)
        local gameIds = data.gameIds or {}
        if #gameIds > 0 then
            return listContains(gameIds, currentGameId())
        end

        local placeIds = data.placeIds or {}
        if #placeIds > 0 then
            return listContains(placeIds, currentPlaceId())
        end

        return false
    end

    function Library:_getAutoLoadTag()
        return "__uilib.autoload"
    end

    function Library:_buildAutoLoadQueuedSource(data)
        data = normalizeAutoLoadData(data)
        if data.loaderUrl == "" then
            return nil
        end

        local okEncode, encoded = pcall(function()
            return HttpService:JSONEncode(data)
        end)
        if not okEncode or type(encoded) ~= "string" then
            return nil
        end

        return table.concat({
            "do\n",
            "local HttpService = game:GetService(\"HttpService\")\n",
            "local payload = HttpService:JSONDecode(", quoteLuaString(encoded), ")\n",
            "local bootstrapUrl = ", quoteLuaString(data.bootstrapUrl), "\n",
            "local okSource, source = pcall(function()\n",
            "    return game:HttpGet(bootstrapUrl)\n",
            "end)\n",
            "if okSource and type(source) == \"string\" and source ~= \"\" then\n",
            "    local chunk = loadstring(source)\n",
            "    if chunk then\n",
            "        local okLibrary, Library = pcall(chunk)\n",
            "        if okLibrary and type(Library) == \"table\" and type(Library.RunAutoLoad) == \"function\" then\n",
            "            pcall(function()\n",
            "                Library:RunAutoLoad(payload)\n",
            "            end)\n",
            "        end\n",
            "    end\n",
            "end\n",
            "end",
        })
    end

    function Library:QueueAutoLoad(data)
        data = normalizeAutoLoadData(data)
        if data.enabled == false then
            return false, "autoload disabled"
        end
        if data.loaderUrl == "" then
            return false, "loader url missing"
        end

        local queueOnTeleport = getQueueOnTeleport()
        if type(queueOnTeleport) ~= "function" then
            return false, "queue_on_teleport unavailable"
        end

        local source = self:_buildAutoLoadQueuedSource(data)
        if type(source) ~= "string" or source == "" then
            return false, "autoload source build failed"
        end

        local ok, err = pcall(queueOnTeleport, source)
        if not ok then
            return false, tostring(err or "queue_on_teleport failed")
        end

        return true
    end

    function Library:RunAutoLoad(data)
        data = normalizeAutoLoadData(data)
        if data.enabled == false then
            return false, "autoload disabled"
        end
        if data.loaderUrl == "" then
            return false, "loader url missing"
        end

        pcall(function()
            self:QueueAutoLoad(data)
        end)

        if not autoLoadMatchesCurrentTarget(data) then
            return false, "game mismatch"
        end

        local runKey = table.concat({ data.loaderUrl, currentGameId(), currentPlaceId(), currentJobId() }, "::")
        local store = getAutoLoadStore()
        if store then
            if type(store.__UnknownHubUiAutoLoadRan) ~= "table" then
                store.__UnknownHubUiAutoLoadRan = {}
            end
            if store.__UnknownHubUiAutoLoadRan[runKey] then
                return false, "already loaded"
            end
            store.__UnknownHubUiAutoLoadRan[runKey] = true
        end

        local okSource, source = pcall(function()
            return game:HttpGet(data.loaderUrl)
        end)
        if not okSource or type(source) ~= "string" or source == "" then
            return false, tostring(source or "loader download failed")
        end

        local chunk, compileError = loadstring(source)
        if not chunk then
            return false, tostring(compileError or "loader compile failed")
        end

        local okRun, runResult = pcall(chunk)
        if not okRun then
            return false, tostring(runResult or "loader run failed")
        end

        return true, runResult
    end

    function Library:ConfigureAutoLoad(options)
        options = type(options) == "table" and options or {}
        local saved = self:ReadData(self:_getAutoLoadTag())
        local savedData = normalizeAutoLoadData(saved)
        local optionData = normalizeAutoLoadData(options)

        local explicitEnabled = readOptionalBoolean(options)
        local savedEnabled = readOptionalBoolean(saved)
        local enabled = explicitEnabled
        if enabled == nil then
            enabled = savedEnabled
        end
        if enabled == nil then
            enabled = true
        end

        local gameIds = normalizeIdList(savedData.gameIds, optionData.gameIds, currentGameId())
        local placeIds = normalizeIdList(savedData.placeIds, optionData.placeIds)
        local data = {
            version = 1,
            enabled = enabled,
            loaderUrl = optionData.loaderUrl ~= "" and optionData.loaderUrl or savedData.loaderUrl,
            bootstrapUrl = optionData.bootstrapUrl ~= "" and optionData.bootstrapUrl or savedData.bootstrapUrl,
            gameIds = gameIds,
            placeIds = placeIds,
            scriptId = optionData.scriptId ~= "" and optionData.scriptId or savedData.scriptId,
            projectId = optionData.projectId ~= "" and optionData.projectId or savedData.projectId,
            mode = optionData.mode ~= "" and optionData.mode or savedData.mode,
            configName = self._configName,
        }
        if data.loaderUrl == "" then
            data.enabled = false
        end

        self._autoLoadEnabled = data.enabled
        self._autoLoadData = data
        self:WriteData(self:_getAutoLoadTag(), data)

        if data.enabled then
            pcall(function()
                self:QueueAutoLoad(data)
            end)
        end

        return data
    end

    function Library:SetAutoLoadEnabled(enabled, options)
        options = type(options) == "table" and options or {}
        options.enabled = enabled == true

        local existing = self._autoLoadData
        if type(existing) ~= "table" then
            existing = self:ReadData(self:_getAutoLoadTag())
        end
        existing = normalizeAutoLoadData(existing)

        for key, value in pairs(existing) do
            if options[key] == nil then
                options[key] = value
            end
        end

        return self:ConfigureAutoLoad(options)
    end

    function Library:_resolveLoadedConfigEntry(key, item)
        local data = self._loadedConfigData
        if type(data) ~= "table" then
            return nil
        end

        local direct = data[key]
        if type(direct) == "table" and direct.value ~= nil then
            return direct
        end

        local aliases = item and item.aliases
        if type(aliases) == "table" then
            for _, alias in ipairs(aliases) do
                if type(alias) == "string" and alias ~= "" then
                    local aliasEntry = data[alias]
                    if type(aliasEntry) == "table" and aliasEntry.value ~= nil then
                        return aliasEntry
                    end
                end
            end
        end

        return nil
    end

    function Library:_applyLoadedConfigEntry(key, item, entry)
        if not item or not entry or entry.value == nil then
            return false
        end

        local ok = pcall(item.set, entry.value, { fireCallbacks = true, fromConfig = true })
        if ok then
            self._configAppliedGenerationByKey[key] = self._configLoadGeneration or 0
        end

        return ok
    end

    function Library:RegisterConfig(key, cType, getter, setter, registerOptions)
        registerOptions = registerOptions or {}
        local aliases = {}
        local seenAliases = {}
        local sourceAliases = registerOptions.Aliases or registerOptions.aliases
        if type(sourceAliases) == "table" then
            for _, alias in ipairs(sourceAliases) do
                if type(alias) == "string" and alias ~= "" and alias ~= key and not seenAliases[alias] then
                    seenAliases[alias] = true
                    table.insert(aliases, alias)
                end
            end
        end

        if self._configItems[key] == nil then
            table.insert(self._configItemOrder, key)
        end
        self._configItems[key] = { type = cType, get = getter, set = setter, aliases = aliases }

        local loadedEntry = self:_resolveLoadedConfigEntry(key, self._configItems[key])
        if loadedEntry and loadedEntry.value ~= nil then
            self:_beginConfigReplay()
            self:_applyLoadedConfigEntry(key, self._configItems[key], loadedEntry)
            self:_endConfigReplay()
            self:_scheduleConfigReplay()
        end
    end

    function Library:_beginControlSync()
        self._controlSyncDepth = (self._controlSyncDepth or 0) + 1
    end

    function Library:_endControlSync()
        local depth = self._controlSyncDepth or 0
        if depth > 0 then
            self._controlSyncDepth = depth - 1
        end
    end

    function Library:_callbacksSuppressed()
        return (self._controlSyncDepth or 0) > 0
    end

    function Library:_beginConfigReplay()
        self._configReplayDepth = (self._configReplayDepth or 0) + 1
    end

    function Library:_endConfigReplay()
        local depth = self._configReplayDepth or 0
        if depth > 0 then
            self._configReplayDepth = depth - 1
        end
    end

    function Library:_isConfigReplaying()
        return (self._configReplayDepth or 0) > 0
    end

    function Library:_scheduleConfigReplay()
        self._configReplayToken = (self._configReplayToken or 0) + 1
        local replayToken = self._configReplayToken
        local mutationSerial = self._configMutationSerial or 0

        task.delay(0.2, function()
            if self._configReplayToken ~= replayToken then
                return
            end
            if (self._configMutationSerial or 0) ~= mutationSerial then
                return
            end

            local data = self._loadedConfigData
            if type(data) ~= "table" then
                return
            end

            self:_beginConfigReplay()
            for _, key in ipairs(self._configItemOrder) do
                if self._configAppliedGenerationByKey[key] == (self._configLoadGeneration or 0) then
                    continue
                end
                local item = self._configItems[key]
                local entry = self:_resolveLoadedConfigEntry(key, item)
                if item and entry and entry.value ~= nil then
                    self:_applyLoadedConfigEntry(key, item, entry)
                end
            end
            self:_endConfigReplay()
        end)
    end

    function Library:_getConfigSnapshot()
        local data = {}
        for key, item in pairs(self._configItems) do
            local ok, value = pcall(item.get)
            if ok then
                data[key] = {
                    type = item.type,
                    value = value,
                }
            end
        end
        return data
    end

    function Library:_applyConfigSnapshot(data)
        if type(data) ~= "table" then
            self._loadedConfigData = nil
            return false
        end

        self._loadedConfigData = data
        self._configLoadGeneration = (self._configLoadGeneration or 0) + 1
        self._configAppliedGenerationByKey = {}
        self:_beginConfigReplay()
        for _, key in ipairs(self._configItemOrder) do
            local item = self._configItems[key]
            local entry = self:_resolveLoadedConfigEntry(key, item)
            if item and entry and entry.value ~= nil then
                self:_applyLoadedConfigEntry(key, item, entry)
            end
        end
        self:_endConfigReplay()
        self:_scheduleConfigReplay()
        return true
    end

    function Library:SaveConfig()
        local path = self:_getConfigPath()
        if not path or type(writefile) ~= "function" then
            return false, "writefile unavailable"
        end

        local data = self:_getConfigSnapshot()
        local okEncode, encoded = pcall(function()
            return HttpService:JSONEncode(data)
        end)
        if not okEncode or type(encoded) ~= "string" then
            return false, "json encode failed"
        end

        local paths = {}
        if self:_ensureFolder() then
            table.insert(paths, path)
        end

        local flatPath = self:_getFlatConfigPath()
        if flatPath and flatPath ~= path then
            table.insert(paths, flatPath)
        end

        local lastError = "writefile failed"
        for _, candidatePath in ipairs(paths) do
            local okWrite, writeErr = pcall(writefile, candidatePath, encoded)
            if okWrite then
                self._dirty = false
                return true, candidatePath
            end
            lastError = tostring(writeErr or lastError)
        end

        lastError = lastError:gsub("[%c\r\n]+", " ")
        return false, lastError
    end

    function Library:LoadConfig()
        local path = self:_getConfigPath()
        if not path then
            self._loadedConfigData = nil
            return false, "config name missing"
        end

        local data = self:_readJsonFile(path)
        local loadedPath = path
        if data == nil then
            loadedPath = self:_getFlatConfigPath()
            data = self:_readJsonFile(loadedPath)
        end

        if type(data) ~= "table" then
            self._loadedConfigData = nil
            return false, "config not found"
        end

        self:_applyConfigSnapshot(data)
        return true, loadedPath
    end

    function Library:_readNamedPresetIndex(indexTag)
        local payload = self:ReadData(indexTag)
        if type(payload) ~= "table" then
            return {}
        end

        local names = {}
        local seen = {}
        for _, value in ipairs(payload) do
            local text = normalizePresetName(value)
            if text then
                local normalizedKey = text:lower()
                if not seen[normalizedKey] then
                    seen[normalizedKey] = true
                    table.insert(names, text)
                end
            end
        end
        return names
    end

    function Library:_writeNamedPresetIndex(indexTag, names)
        local cleaned = {}
        local seen = {}
        for _, value in ipairs(names or {}) do
            local text = normalizePresetName(value)
            if text then
                local normalizedKey = text:lower()
                if not seen[normalizedKey] then
                    seen[normalizedKey] = true
                    table.insert(cleaned, text)
                end
            end
        end

        table.sort(cleaned, function(left, right)
            return tostring(left):lower() < tostring(right):lower()
        end)

        local success, writeResult = self:WriteData(indexTag, cleaned)
        if not success then
            return nil, writeResult or "failed to write preset index"
        end

        return cleaned, writeResult
    end

    function Library:_getConfigPresetTag(name)
        local sanitized = sanitizePathSegment(name)
        if sanitized == "" then
            return nil
        end
        return "config_preset_" .. sanitized
    end

    function Library:_getConfigPresetIndexTag()
        return "config_presets_index"
    end

    function Library:_readConfigPresetIndex()
        return self:_readNamedPresetIndex(self:_getConfigPresetIndexTag())
    end

    function Library:_writeConfigPresetIndex(names)
        return self:_writeNamedPresetIndex(self:_getConfigPresetIndexTag(), names)
    end

    function Library:SaveConfigPreset(name)
        local trimmedName = tostring(name or ""):match("^%s*(.-)%s*$")
        if trimmedName == "" then
            return false, "enter a preset name"
        end

        local tag = self:_getConfigPresetTag(name)
        if not tag then
            return false, "invalid preset name"
        end

        local success, writeResult = self:WriteData(tag, {
            Name = trimmedName,
            Config = self:_getConfigSnapshot(),
        })
        if not success then
            return false, writeResult or "failed to write preset"
        end

        local payload = self:ReadData(tag)
        if type(payload) ~= "table" or type(payload.Config) ~= "table" then
            return false, "preset write verification failed"
        end

        local presets = self:_readConfigPresetIndex()
        table.insert(presets, trimmedName)
        local cleaned, indexResult = self:_writeConfigPresetIndex(presets)
        if not cleaned then
            return false, indexResult or "failed to update preset list"
        end

        return true, string.format("saved config preset: %s", trimmedName)
    end

    function Library:LoadConfigPreset(name)
        local trimmedName = tostring(name or ""):match("^%s*(.-)%s*$")
        if trimmedName == "" then
            return false, "select a preset to load"
        end

        local tag = self:_getConfigPresetTag(name)
        if not tag then
            return false, "invalid preset name"
        end

        local payload = self:ReadData(tag)
        local configData = type(payload) == "table" and (payload.Config or payload.config or payload.Settings or payload.settings) or nil
        if type(configData) ~= "table" then
            return false, string.format("config preset not found: %s", trimmedName)
        end

        self:_applyConfigSnapshot(configData)
        pcall(function()
            self:SaveConfig()
        end)
        return true, string.format("loaded config preset: %s", trimmedName)
    end

    function Library:ListConfigPresets()
        local presets = self:_readConfigPresetIndex()
        if #presets > 0 then
            return presets
        end

        if type(listfiles) ~= "function" then
            return {}
        end

        self:_ensureFolder()

        local ok, files = pcall(listfiles, CONFIG_FOLDER)
        if not ok or type(files) ~= "table" then
            return {}
        end

        local prefix = self:_getStorageBaseName() .. "_config_preset_"
        for _, filePath in ipairs(files) do
            local normalized = tostring(filePath):gsub("\\", "/")
            local fileName = normalized:match("([^/]+)$")
            if fileName and fileName:sub(1, #prefix) == prefix and fileName:sub(-5) == ".json" then
                local presetTagName = fileName:sub(#prefix + 1, -6)
                local payload = self:ReadData("config_preset_" .. presetTagName)
                local presetName = normalizePresetName(type(payload) == "table" and payload.Name or presetTagName)
                if presetName then
                    table.insert(presets, presetName)
                end
            end
        end

        local cleaned = self:_writeConfigPresetIndex(presets)
        if cleaned then
            return cleaned
        end

        return {}
    end

    function Library:_markDirty()
        if self:_callbacksSuppressed() then return end
        if self:_isConfigReplaying() then return end
        self._configMutationSerial = (self._configMutationSerial or 0) + 1
        if not self._autoSave then return end
        self._dirty = true
    end

    SharedState.ActiveLibrary = Library
    if not SharedState.AutoSaveLoopStarted then
        SharedState.AutoSaveLoopStarted = true

        task.spawn(function()
            while true do
                task.wait(2)

                local activeLibrary = SharedState.ActiveLibrary
                if activeLibrary and activeLibrary._autoSave and activeLibrary._dirty then
                    activeLibrary._dirty = false
                    pcall(function()
                        activeLibrary:SaveConfig()
                    end)
                end
            end
        end)
    end

    local defaultTheme = {
        Black = Color3.fromRGB(16, 16, 16),
        Main = Color3.fromRGB(255, 106, 133),
        Background = Color3.fromRGB(19, 19, 19),
        Header = Color3.fromRGB(21, 21, 21),
        Bottom = Color3.fromRGB(21, 21, 21),
        Line = Color3.fromRGB(29, 29, 29),
        Scroll = Color3.fromRGB(90, 90, 90),
        TabBg = Color3.fromRGB(30, 30, 30),
        TabBgActive = Color3.fromRGB(38, 38, 38),
        Text = Color3.fromRGB(229, 229, 229),
        TextDim = Color3.fromRGB(150, 150, 150),
        TextMuted = Color3.fromRGB(100, 100, 100),
        TextStrong = Color3.fromRGB(255, 255, 255),
        Section = Color3.fromRGB(24, 24, 24),
        Panel = Color3.fromRGB(22, 22, 22),
        Control = Color3.fromRGB(35, 35, 35),
        ControlAlt = Color3.fromRGB(30, 30, 30),
        ControlHover = Color3.fromRGB(50, 50, 50),
        AccentSurface = Color3.fromRGB(45, 25, 30),
        TitleStroke = Color3.fromRGB(205, 67, 218),
        Shadow = Color3.fromRGB(0, 0, 0),
        BackgroundTransparency = 0,
        HeaderTransparency = 0,
        BottomTransparency = 0,
        SectionTransparency = 0,
        PanelTransparency = 0,
        ControlTransparency = 0,
        AccentTransparency = 0,
        ShadowTransparency = 0.75,
    }

    Library.Colors = {}
    Library.Theme = {}
    Library._themeBindings = {}
    Library._themeCallbacks = {}

    local function cloneThemeValue(value)
        if typeof(value) == "Color3" then
            return Color3.new(value.R, value.G, value.B)
        end
        return value
    end

    for key, value in pairs(defaultTheme) do
        Library.Colors[key] = cloneThemeValue(value)
        Library.Theme[key] = cloneThemeValue(value)
    end

    local function serializeThemeValue(value)
        if typeof(value) == "Color3" then
            return {
                __type = "Color3",
                R = value.R,
                G = value.G,
                B = value.B,
            }
        end
        return value
    end

    local function getSerializedThemeSnapshot(themeTable)
        local payload = {}
        for key, value in pairs(themeTable) do
            payload[key] = serializeThemeValue(value)
        end
        return payload
    end

    local deserializeThemeValue

    local function applyThemeSnapshot(target, payload)
        if type(payload) ~= "table" then
            return
        end

        for key, defaultValue in pairs(defaultTheme) do
            local nextValue = payload[key]
            if nextValue ~= nil then
                nextValue = deserializeThemeValue(nextValue)
                if typeof(defaultValue) == "Color3" and typeof(nextValue) == "Color3" then
                    target.Theme[key] = nextValue
                    target.Colors[key] = cloneThemeValue(nextValue)
                elseif type(defaultValue) == "number" and type(nextValue) == "number" then
                    target.Theme[key] = nextValue
                    target.Colors[key] = nextValue
                end
            end
        end
    end

    deserializeThemeValue = function(value)
        if type(value) == "table" and value.__type == "Color3" then
            return Color3.new(tonumber(value.R) or 0, tonumber(value.G) or 0, tonumber(value.B) or 0)
        end
        return value
    end

    function Library:RegisterThemeBinding(instance, propertyName, themeKey, transform)
        if not instance or type(propertyName) ~= "string" or type(themeKey) ~= "string" then
            return
        end

        table.insert(self._themeBindings, {
            Instance = instance,
            Property = propertyName,
            ThemeKey = themeKey,
            Transform = transform,
        })
    end

    function Library:RegisterThemeCallback(callback)
        if type(callback) ~= "function" then
            return
        end

        table.insert(self._themeCallbacks, callback)
    end

    function Library:ApplyTheme()
        for index = #self._themeBindings, 1, -1 do
            local binding = self._themeBindings[index]
            local instance = binding and binding.Instance
            if not binding or not instance or instance.Parent == nil then
                table.remove(self._themeBindings, index)
            else
                local value = self.Theme[binding.ThemeKey]
                if value ~= nil then
                    local resolved = binding.Transform and binding.Transform(value, self.Theme) or value
                    pcall(function()
                        instance[binding.Property] = resolved
                    end)
                end
            end
        end

        for _, callback in ipairs(self._themeCallbacks) do
            pcall(callback, self.Theme)
        end
    end

    function Library:SetThemeValue(themeKey, value, shouldPersist)
        if type(themeKey) ~= "string" or self.Theme[themeKey] == nil then
            return
        end

        self.Theme[themeKey] = cloneThemeValue(value)
        self.Colors[themeKey] = cloneThemeValue(value)
        self:ApplyTheme()

        if shouldPersist ~= false then
            self:SaveTheme()
        end
    end

    function Library:GetThemeValue(themeKey)
        return self.Theme[themeKey]
    end

    function Library:SaveTheme()
        return self:WriteData("theme", getSerializedThemeSnapshot(self.Theme))
    end

    function Library:LoadTheme()
        local payload = self:ReadData("theme")
        if type(payload) ~= "table" then
            self:ApplyTheme()
            return
        end

        applyThemeSnapshot(self, payload)
        self:ApplyTheme()
    end

    function Library:ResetThemeDefaults(shouldPersist)
        for key, value in pairs(defaultTheme) do
            self.Theme[key] = cloneThemeValue(value)
            self.Colors[key] = cloneThemeValue(value)
        end

        self:ApplyTheme()

        if shouldPersist ~= false then
            self:SaveTheme()
        end
    end

    function Library:_getThemePresetTag(name)
        local sanitized = sanitizePathSegment(name)
        if sanitized == "" then
            return nil
        end
        return "theme_preset_" .. sanitized
    end

    function Library:_getThemePresetIndexTag()
        return "theme_presets_index"
    end

    function Library:_readThemePresetIndex()
        return self:_readNamedPresetIndex(self:_getThemePresetIndexTag())
    end

    function Library:_writeThemePresetIndex(names)
        return self:_writeNamedPresetIndex(self:_getThemePresetIndexTag(), names)
    end

    function Library:SaveThemePreset(name)
        local trimmedName = tostring(name or ""):match("^%s*(.-)%s*$")
        if trimmedName == "" then
            return false, "enter a preset name"
        end

        local tag = self:_getThemePresetTag(name)
        if not tag then
            return false, "invalid preset name"
        end

        local success, writeResult = self:WriteData(tag, {
            Name = trimmedName,
            Theme = getSerializedThemeSnapshot(self.Theme),
        })
        if not success then
            return false, writeResult or "failed to write preset"
        end

        local payload = self:ReadData(tag)
        if type(payload) ~= "table" or type(payload.Theme) ~= "table" then
            return false, "preset write verification failed"
        end

        local presets = self:_readThemePresetIndex()
        table.insert(presets, trimmedName)
        local cleaned, indexResult = self:_writeThemePresetIndex(presets)
        if not cleaned then
            return false, indexResult or "failed to update preset list"
        end

        return true, string.format("saved preset: %s", trimmedName)
    end

    function Library:LoadThemePreset(name)
        local trimmedName = tostring(name or ""):match("^%s*(.-)%s*$")
        if trimmedName == "" then
            return false, "select a preset to load"
        end

        local tag = self:_getThemePresetTag(name)
        if not tag then
            return false, "invalid preset name"
        end

        local payload = self:ReadData(tag)
        if type(payload) ~= "table" or type(payload.Theme) ~= "table" then
            return false, string.format("preset not found: %s", trimmedName)
        end

        applyThemeSnapshot(self, payload.Theme)
        self:ApplyTheme()
        self:SaveTheme()
        return true, string.format("loaded preset: %s", trimmedName)
    end

    function Library:ListThemePresets()
        local presets = self:_readThemePresetIndex()
        if #presets > 0 then
            return presets
        end

        if type(listfiles) ~= "function" then
            return {}
        end

        self:_ensureFolder()

        local ok, files = pcall(listfiles, CONFIG_FOLDER)
        if not ok or type(files) ~= "table" then
            return {}
        end

        local prefix = self:_getStorageBaseName() .. "_theme_preset_"
        for _, filePath in ipairs(files) do
            local normalized = tostring(filePath):gsub("\\", "/")
            local fileName = normalized:match("([^/]+)$")
            if fileName and fileName:sub(1, #prefix) == prefix and fileName:sub(-5) == ".json" then
                local presetTagName = fileName:sub(#prefix + 1, -6)
                local payload = self:ReadData("theme_preset_" .. presetTagName)
                local presetName = normalizePresetName(type(payload) == "table" and payload.Name or presetTagName)
                if presetName then
                    table.insert(presets, presetName)
                end
            end
        end

        local cleaned = self:_writeThemePresetIndex(presets)
        if cleaned then
            return cleaned
        end

        return {}
    end

    Library.Config = {
        WindowWidth    = 750,
        WindowHeight   = 500,
        MinWindowWidth = 640,
        MinWindowHeight = 400,
        ContentScale   = 1,
        ResizeBorder   = 8,
        HeaderHeight   = 40,
        BottomHeight   = 25,
        Font           = Enum.Font.GothamBold,
        FontMedium     = Enum.Font.GothamMedium,
        FontSemiBold   = Enum.Font.GothamSemibold,
        ToggleKey      = Enum.KeyCode.Insert,
    }
end
