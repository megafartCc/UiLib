return function(Library, context)
    local HttpService = context.HttpService
    local SharedState = context.SharedState

    Library._configItems = {}
    Library._configName = nil
    Library._autoSave = false
    Library._autoSaveDelay = 2
    Library._dirty = false

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
        self._configItems[key] = { type = cType, get = getter, set = setter }
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
        for key, entry in pairs(data) do
            local item = self._configItems[key]
            if item and entry.value ~= nil then
                pcall(item.set, entry.value)
            end
        end
    end

    function Library:_markDirty()
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
