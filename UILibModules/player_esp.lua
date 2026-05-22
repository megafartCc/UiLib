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

        local win = controlsSection and controlsSection._win
        local main = win and win._main
        if not main then
            return nil
        end

        local initialVisible = true
        if menu._page then
            initialVisible = menu._page.Visible == true
        end

        local panel = Instance.new("Frame", main)
        panel.Name = "PlayerEspPreviewPanel"
        panel.AnchorPoint = Vector2.new(0, 0.5)
        panel.BackgroundColor3 = themeColor("Section", Color3.fromRGB(18, 18, 18))
        panel.BorderSizePixel = 0
        panel.ClipsDescendants = true
        panel.Position = UDim2.new(1, opts.PreviewGap or 8, 0.5, 0)
        panel.Size = UDim2.new(0, opts.PreviewWidth or 170, 1, -(opts.PreviewVerticalInset or 60))
        panel.Visible = initialVisible
        panel.ZIndex = 90
        bindTheme(panel, "BackgroundColor3", "Section")
        bindTheme(panel, "BackgroundTransparency", "SectionTransparency")
        Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 5)

        local panelStroke = Instance.new("UIStroke", panel)
        panelStroke.Color = themeColor("Line", Color3.fromRGB(60, 60, 60))
        panelStroke.Transparency = 0.35
        bindTheme(panelStroke, "Color", "Line")

        local title = Instance.new("TextLabel", panel)
        title.Name = "Title"
        title.BackgroundTransparency = 1
        title.BorderSizePixel = 0
        title.Position = UDim2.new(0, 10, 0, 10)
        title.Size = UDim2.new(1, -20, 0, 16)
        title.Font = Enum.Font.GothamBold
        title.Text = opts.PreviewName or "ESP PREVIEW"
        title.TextColor3 = themeColor("Text", Color3.fromRGB(235, 235, 235))
        title.TextSize = 10
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.ZIndex = 91
        bindTheme(title, "TextColor3", "Text")

        local sample = Instance.new("Frame", panel)
        sample.Name = "Box"
        sample.AnchorPoint = Vector2.new(0.5, 0.5)
        sample.BackgroundTransparency = 1
        sample.Position = UDim2.new(0.5, 0, 0.48, 0)
        sample.Size = UDim2.fromOffset(72, 150)
        sample.ZIndex = 91

        local boxStroke = Instance.new("UIStroke", sample)
        boxStroke.Color = themeColor("Line", Color3.fromRGB(60, 60, 60))
        boxStroke.Thickness = 1
        boxStroke.Transparency = 0.65

        local function layoutPreview()
            local panelHeight = panel.AbsoluteSize.Y
            local panelWidth = panel.AbsoluteSize.X
            if panelHeight <= 0 or panelWidth <= 0 then
                return
            end

            local boxHeight = math.clamp(math.floor(panelHeight * 0.42), 120, math.max(120, panelHeight - 64))
            local boxWidth = math.clamp(math.floor(boxHeight * 0.48), 56, math.max(56, panelWidth - 46))
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

        local function syncVisibility()
            panel.Visible = menu._page == nil or menu._page.Visible == true
        end

        local function syncLayout()
            panel.Size = UDim2.new(0, opts.PreviewWidth or 170, 1, -(opts.PreviewVerticalInset or 60))
            layoutPreview()
        end

        controlsSection:TrackInstance(panel, "PlayerEspPreviewPanel")
        controlsSection:TrackConnection(panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutPreview), "PlayerEspPreviewLayout")
        controlsSection:TrackConnection(main:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncLayout), "PlayerEspPreviewWindowLayout")
        if menu._page then
            controlsSection:TrackConnection(menu._page:GetPropertyChangedSignal("Visible"):Connect(syncVisibility), "PlayerEspPreviewVisibility")
        end
        if type(Library.RegisterThemeCallback) == "function" then
            Library:RegisterThemeCallback(function()
                if panel.Parent then
                    refreshPreview()
                end
            end)
        end

        task.defer(syncLayout)
        task.defer(syncVisibility)
        task.defer(refreshPreview)

        return {
            Frame = panel,
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
