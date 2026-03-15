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
    Library._autoSave = false
    Library._autoSaveDelay = 2
    Library._dirty = false
    Library._controlSyncDepth = 0
    Library._configReplayDepth = 0
    Library._configItemOrder = {}
    Library._loadedConfigData = nil
    Library._configReplayToken = 0

    local CONFIG_FOLDER = "Eps1lonScript"

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

        return true
    end

    function Library:_getConfigPath()
        if not self._configName then return nil end
        return CONFIG_FOLDER .. "/" .. self._configName .. ".json"
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

    function Library:ReadData(tag)
        local path = self:_getDataPath(tag)
        if not path or type(isfile) ~= "function" or not isfile(path) then
            return nil
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

    function Library:WriteData(tag, value)
        local path = self:_getDataPath(tag)
        if not path or type(writefile) ~= "function" then
            return false, "writefile unavailable"
        end

        if not self:_ensureFolder() then
            return false, "storage folder unavailable"
        end

        local okEncode, encoded = pcall(function()
            return HttpService:JSONEncode(value)
        end)
        if not okEncode or type(encoded) ~= "string" then
            return false, "json encode failed"
        end

        local okWrite, writeErr = pcall(writefile, path, encoded)
        if not okWrite then
            local message = tostring(writeErr or "writefile failed")
            message = message:gsub("[%c\r\n]+", " ")
            return false, message
        end

        return true, path
    end

    function Library:RegisterConfig(key, cType, getter, setter)
        if self._configItems[key] == nil then
            table.insert(self._configItemOrder, key)
        end
        self._configItems[key] = { type = cType, get = getter, set = setter }

        local loadedEntry = self._loadedConfigData and self._loadedConfigData[key]
        if loadedEntry and loadedEntry.value ~= nil then
            self:_beginControlSync()
            pcall(setter, loadedEntry.value)
            self:_endControlSync()
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

        task.delay(0.2, function()
            if self._configReplayToken ~= replayToken then
                return
            end

            local data = self._loadedConfigData
            if type(data) ~= "table" then
                return
            end

            self:_beginConfigReplay()
            for _, key in ipairs(self._configItemOrder) do
                local item = self._configItems[key]
                local entry = data[key]
                if item and entry and entry.value ~= nil then
                    pcall(item.set, entry.value)
                end
            end
            self:_endConfigReplay()
        end)
    end

    function Library:SaveConfig()
        local path = self:_getConfigPath()
        if not path then return end
        self:_ensureFolder()
        local data = {}
        for key, item in pairs(self._configItems) do
            local ok, val = pcall(item.get)
            if ok then
                data[key] = { type = item.type, value = val }
            end
        end
        local json = HttpService:JSONEncode(data)
        writefile(path, json)
    end

    function Library:LoadConfig()
        local path = self:_getConfigPath()
        if not path then return end
        if not isfile(path) then return end
        local ok, json = pcall(readfile, path)
        if not ok then return end
        local ok2, data = pcall(function() return HttpService:JSONDecode(json) end)
        if not ok2 or type(data) ~= "table" then return end
        self._loadedConfigData = data
        for _, key in ipairs(self._configItemOrder) do
            local entry = data[key]
            local item = self._configItems[key]
            if item and entry and entry.value ~= nil then
                self:_beginControlSync()
                pcall(item.set, entry.value)
                self:_endControlSync()
            end
        end
        self:_scheduleConfigReplay()
    end

    function Library:_markDirty()
        if not self._autoSave then return end
        if self:_callbacksSuppressed() then return end
        if self:_isConfigReplaying() then return end
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
        local payload = self:ReadData(self:_getThemePresetIndexTag())
        if type(payload) ~= "table" then
            return {}
        end

        local names = {}
        local seen = {}
        for _, value in ipairs(payload) do
            local text = tostring(value or ""):match("^%s*(.-)%s*$")
            if text ~= "" then
                local normalizedKey = text:lower()
                if not seen[normalizedKey] then
                    seen[normalizedKey] = true
                    table.insert(names, text)
                end
            end
        end
        return names
    end

    function Library:_writeThemePresetIndex(names)
        local cleaned = {}
        local seen = {}
        for _, value in ipairs(names or {}) do
            local text = tostring(value or ""):match("^%s*(.-)%s*$")
            if text ~= "" then
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

        local success, writeResult = self:WriteData(self:_getThemePresetIndexTag(), cleaned)
        if not success then
            return nil, writeResult or "failed to write preset index"
        end

        return cleaned, writeResult
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
            local dataPath = self:_getDataPath(tag)
            if type(isfile) == "function" and dataPath and isfile(dataPath) then
                payload = { Theme = true }
            else
                return false, "preset write verification failed"
            end
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
                local presetName = type(payload) == "table" and tostring(payload.Name or "") or presetTagName
                if presetName ~= "" then
                    table.insert(presets, presetName)
                end
            end
        end

        local cleaned = self:_writeThemePresetIndex(presets)
        return cleaned or presets
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
