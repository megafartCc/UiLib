return function(Library, context)
    local DEFAULT_ESP_URL = "https://raw.githubusercontent.com/megafartCc/SAB/main/espmodule.lua"

    local function themeColor(key, fallback)
        if type(Library.GetThemeValue) == "function" then
            local value = Library:GetThemeValue(key)
            if value ~= nil then
                return value
            end
        end
        return fallback
    end

    local function bindTheme(instance, propertyName, themeKey, transform)
        if type(Library.RegisterThemeBinding) == "function" then
            Library:RegisterThemeBinding(instance, propertyName, themeKey, transform)
        end
    end

    local function loadEspModule(sourceUrl)
        local okGame, isGameInstance = pcall(function()
            return typeof(game) == "Instance"
        end)
        if not okGame or not isGameInstance then
            return nil
        end
        if type(game.HttpGet) ~= "function" or type(loadstring) ~= "function" then
            return nil
        end

        local ok, result = pcall(function()
            return loadstring(game:HttpGet(sourceUrl or DEFAULT_ESP_URL))()
        end)
        if ok then
            return result
        end
        return nil
    end

    local function safeEspCall(esp, methodName, value)
        if esp and type(esp[methodName]) == "function" then
            pcall(esp[methodName], esp, value)
        end
    end

    local function makePreview(menu, controlsSection, state, opts)
        opts = opts or {}

        local previewSection = menu:AddSection({
            Name = opts.PreviewName or "ESP PREVIEW",
            Column = opts.PreviewColumn or 2,
        })

        local row = Instance.new("Frame", previewSection.Container)
        row.Name = "PlayerEspPreview"
        row.BackgroundColor3 = themeColor("ControlAlt", Color3.fromRGB(30, 30, 30))
        row.BorderSizePixel = 0
        row.ClipsDescendants = true
        row.Size = UDim2.new(1, 0, 0, 96)
        row.ZIndex = 5
        bindTheme(row, "BackgroundColor3", "ControlAlt")
        bindTheme(row, "BackgroundTransparency", "ControlTransparency")
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)

        local rowStroke = Instance.new("UIStroke", row)
        rowStroke.Color = themeColor("Line", Color3.fromRGB(60, 60, 60))
        rowStroke.Transparency = 0.45
        bindTheme(rowStroke, "Color", "Line")

        local sample = Instance.new("Frame", row)
        sample.Name = "Box"
        sample.AnchorPoint = Vector2.new(0.5, 0.5)
        sample.BackgroundTransparency = 1
        sample.Position = UDim2.new(0.5, 0, 0.5, 0)
        sample.Size = UDim2.new(0, 48, 0, 88)
        sample.ZIndex = 6

        local boxStroke = Instance.new("UIStroke", sample)
        boxStroke.Color = themeColor("Line", Color3.fromRGB(60, 60, 60))
        boxStroke.Thickness = 1
        boxStroke.Transparency = 0.65

        local function layoutPreview()
            local height = row.AbsoluteSize.Y
            if height <= 0 then
                return
            end

            local boxHeight = math.clamp(height - 22, 48, 128)
            local boxWidth = math.clamp(math.floor(boxHeight * 0.52), 28, 72)
            sample.Size = UDim2.fromOffset(boxWidth, boxHeight)
        end

        local function refreshPreview()
            local activeColor = themeColor("Main", Color3.fromRGB(245, 49, 116))
            local inactiveColor = themeColor("Line", Color3.fromRGB(60, 60, 60))

            if state.Box then
                boxStroke.Color = activeColor
                boxStroke.Transparency = 0.05
            else
                boxStroke.Color = inactiveColor
                boxStroke.Transparency = 0.65
            end
        end

        local function syncHeight()
            local targetHeight = controlsSection.Frame and controlsSection.Frame.AbsoluteSize.Y or 0
            if targetHeight > 0 then
                row.Size = UDim2.new(1, 0, 0, math.max(70, targetHeight - 18))
            end
            layoutPreview()
        end

        previewSection:TrackConnection(row:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutPreview), "PlayerEspPreviewLayout")
        if controlsSection.Frame then
            previewSection:TrackConnection(controlsSection.Frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncHeight), "PlayerEspPreviewHeight")
        end
        if type(Library.RegisterThemeCallback) == "function" then
            Library:RegisterThemeCallback(function()
                if row.Parent then
                    refreshPreview()
                end
            end)
        end

        task.defer(syncHeight)
        task.defer(refreshPreview)

        return {
            Section = previewSection,
            Frame = row,
            Box = sample,
            Refresh = refreshPreview,
        }
    end

    local function addPlayerEspSection(selfOrMenu, menuOrOpts, maybeOpts)
        local menu = selfOrMenu
        local opts = menuOrOpts

        if selfOrMenu == Library then
            menu = menuOrOpts
            opts = maybeOpts
        end

        opts = opts or {}
        if type(menu) ~= "table" or type(menu.AddSection) ~= "function" then
            error("AddPlayerESPSection requires a UiLib menu", 2)
        end

        local esp = opts.ESP or opts.Esp or opts.Module
        if not esp and opts.LoadEsp ~= false then
            esp = loadEspModule(opts.SourceUrl or opts.Url)
        end
        if esp and type(esp.Init) == "function" then
            pcall(esp.Init, esp)
        end

        local section = opts.Section or menu:AddSection({
            Name = opts.Name or "PLAYER ESP",
            Column = opts.Column or 1,
        })

        local state = {
            Box = opts.BoxDefault == true,
            Name = opts.NameDefault == true,
            Health = opts.HealthDefault == true,
            Team = opts.TeamDefault == true,
            Tracers = opts.TracersDefault == true,
            Skeleton = opts.SkeletonDefault == true,
            HeldItem = opts.HeldItemDefault == true,
            MaxDistance = opts.MaxDistance or 1000,
        }

        local api = {
            ESP = esp,
            Section = section,
            State = state,
            Controls = {},
        }

        local preview
        local function refreshPreview()
            if preview and preview.Refresh then
                preview.Refresh()
            end
        end

        local function notifyChange(key, value)
            local callback = opts["On" .. key .. "Changed"]
            if type(callback) == "function" then
                pcall(callback, value, api)
            end
            if type(opts.Callback) == "function" then
                pcall(opts.Callback, key, value, api)
            end
        end

        local function setToggle(key, methodName, value)
            state[key] = value and true or false
            safeEspCall(esp, methodName, state[key])
            refreshPreview()
            notifyChange(key, state[key])
        end

        local function addToggle(name, key, methodName, defaultValue)
            local control = section:AddToggle({
                Name = name,
                Default = defaultValue == true,
                Callback = function(value)
                    setToggle(key, methodName, value)
                end,
            })
            api.Controls[key] = control
            return control
        end

        api.Controls.Box = addToggle("Box ESP", "Box", "SetBoxEsp", state.Box)

        if type(opts.AfterBox) == "function" then
            pcall(opts.AfterBox, section, api)
        end

        api.Controls.Name = addToggle("Name ESP", "Name", "SetNameEsp", state.Name)
        api.Controls.Health = addToggle("Health ESP", "Health", "SetHealthEsp", state.Health)
        api.Controls.Team = addToggle("Team ESP", "Team", "SetTeamEsp", state.Team)
        api.Controls.Tracers = addToggle("Tracers", "Tracers", "SetTracers", state.Tracers)
        api.Controls.Skeleton = addToggle("Skeleton ESP", "Skeleton", "SetSkeletonEsp", state.Skeleton)
        api.Controls.HeldItem = addToggle("Held Item ESP", "HeldItem", "SetHeldItemEsp", state.HeldItem)

        api.Controls.MaxDistance = section:AddSlider({
            Name = "Max Distance",
            Min = opts.MinDistance or 100,
            Max = opts.MaxDistanceLimit or 5000,
            Default = state.MaxDistance,
            Suffix = opts.DistanceSuffix or " studs",
            Callback = function(value)
                state.MaxDistance = value
                safeEspCall(esp, "SetMaxDist", value)
                notifyChange("MaxDistance", value)
            end,
        })

        if opts.Preview ~= false then
            preview = makePreview(menu, section, state, opts)
            api.Preview = preview
        end

        safeEspCall(esp, "SetMaxDist", state.MaxDistance)
        refreshPreview()

        function api:SetEsp(nextEsp)
            esp = nextEsp
            self.ESP = nextEsp
            if esp and type(esp.Init) == "function" then
                pcall(esp.Init, esp)
            end
            safeEspCall(esp, "SetMaxDist", state.MaxDistance)
            return self
        end

        function api:GetState()
            local copy = {}
            for key, value in pairs(state) do
                copy[key] = value
            end
            return copy
        end

        function api:RefreshPreview()
            refreshPreview()
            return self
        end

        return api
    end

    Library.AddPlayerESPSection = addPlayerEspSection
    Library.CreatePlayerESPSection = addPlayerEspSection
end
