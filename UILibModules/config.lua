return function(Library, context)
    local HttpService = context.HttpService
    local SharedState = context.SharedState

    Library._configItems = {}
    Library._configName = nil
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
        if not isfolder(CONFIG_FOLDER) then
            makefolder(CONFIG_FOLDER)
        end
    end

    function Library:_getConfigPath()
        if not self._configName then return nil end
        return CONFIG_FOLDER .. "/" .. self._configName .. ".json"
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

    Library.Colors = {
        Black        = Color3.fromRGB(16, 16, 16),
        Main         = Color3.fromRGB(255, 106, 133),
        Background   = Color3.fromRGB(19, 19, 19),
        Header       = Color3.fromRGB(21, 21, 21),
        Line         = Color3.fromRGB(29, 29, 29),
        TabBg        = Color3.fromRGB(30, 30, 30),
        TabBgActive  = Color3.fromRGB(38, 38, 38),
        Text         = Color3.fromRGB(229, 229, 229),
        TextDim      = Color3.fromRGB(150, 150, 150),
        TextMuted    = Color3.fromRGB(100, 100, 100),
    }

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
