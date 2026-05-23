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

        local previewWidth = opts.PreviewWidth or 240
        local previewVerticalInset = opts.PreviewVerticalInset or 0

        local panel = Instance.new("Frame", main)
        panel.Name = "PlayerEspPreviewPanel"
        panel.AnchorPoint = Vector2.new(0, 0.5)
        panel.BackgroundColor3 = themeColor("Section", Color3.fromRGB(24, 24, 24))
        panel.BackgroundTransparency = themeColor("SectionTransparency", 0)
        panel.BorderSizePixel = 0
        panel.ClipsDescendants = true
        panel.Position = UDim2.new(1, opts.PreviewGap or 8, 0.5, 0)
        panel.Size = UDim2.new(0, previewWidth, 1, -previewVerticalInset)
        panel.Visible = initialVisible
        panel.ZIndex = 90
        bindTheme(panel, "BackgroundColor3", "Section")
        bindTheme(panel, "BackgroundTransparency", "SectionTransparency")
        Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 5)

        local panelStroke = Instance.new("UIStroke", panel)
        panelStroke.Color = themeColor("Line", Color3.fromRGB(60, 60, 60))
        panelStroke.Transparency = 0.8
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

        local function makeText(name, parent, textSize, align)
            local label = Instance.new("TextLabel", parent)
            label.Name = name
            label.BackgroundTransparency = 1
            label.BorderSizePixel = 0
            label.Font = Enum.Font.GothamBold
            label.TextColor3 = themeColor("Text", Color3.fromRGB(235, 235, 235))
            label.TextSize = textSize or 11
            label.TextStrokeTransparency = 0.35
            label.TextXAlignment = align or Enum.TextXAlignment.Center
            label.TextYAlignment = Enum.TextYAlignment.Center
            label.ZIndex = 92
            bindTheme(label, "TextColor3", "Text")
            return label
        end

        local nameLabel = makeText("NameLabel", sample, 11)
        nameLabel.Text = opts.PreviewPlayerName or "PreviewPlayer"
        nameLabel.Position = UDim2.new(0, -70, 0, -24)
        nameLabel.Size = UDim2.new(1, 140, 0, 16)

        local teamLabel = makeText("TeamLabel", sample, 11, Enum.TextXAlignment.Left)
        teamLabel.Text = opts.PreviewTeamName or "No Team"
        teamLabel.Position = UDim2.new(1, 8, 0, 0)
        teamLabel.Size = UDim2.new(0, 74, 0, 15)

        local healthBack = Instance.new("Frame", sample)
        healthBack.Name = "HealthBack"
        healthBack.BackgroundColor3 = themeColor("Line", Color3.fromRGB(60, 60, 60))
        healthBack.BorderSizePixel = 0
        healthBack.Position = UDim2.new(0, -8, 0, 0)
        healthBack.Size = UDim2.new(0, 3, 1, 0)
        healthBack.ZIndex = 92
        bindTheme(healthBack, "BackgroundColor3", "Line")

        local healthFill = Instance.new("Frame", healthBack)
        healthFill.Name = "HealthFill"
        healthFill.AnchorPoint = Vector2.new(0, 1)
        healthFill.BackgroundColor3 = Color3.fromRGB(76, 255, 115)
        healthFill.BorderSizePixel = 0
        healthFill.Position = UDim2.new(0, 0, 1, 0)
        healthFill.Size = UDim2.new(1, 0, 0.82, 0)
        healthFill.ZIndex = 93

        local healthText = makeText("HealthText", sample, 10, Enum.TextXAlignment.Right)
        healthText.Text = opts.PreviewHealthText or "82 HP"
        healthText.Position = UDim2.new(0, -58, 0, 8)
        healthText.Size = UDim2.new(0, 46, 0, 14)

        local heldItemLabel = makeText("HeldItemLabel", sample, 11)
        heldItemLabel.Text = opts.PreviewHeldItem or "Knife"
        heldItemLabel.TextColor3 = themeColor("Main", Color3.fromRGB(245, 49, 116))
        heldItemLabel.Position = UDim2.new(0, -45, 1, 5)
        heldItemLabel.Size = UDim2.new(1, 90, 0, 16)
        bindTheme(heldItemLabel, "TextColor3", "Main")

        local tracerLine = Instance.new("Frame", panel)
        tracerLine.Name = "Tracer"
        tracerLine.AnchorPoint = Vector2.new(0.5, 0.5)
        tracerLine.BackgroundColor3 = themeColor("Main", Color3.fromRGB(245, 49, 116))
        tracerLine.BorderSizePixel = 0
        tracerLine.Size = UDim2.fromOffset(1, 1)
        tracerLine.ZIndex = 91
        bindTheme(tracerLine, "BackgroundColor3", "Main")

        local skeletonLines = {}
        local function makeLine(name)
            local line = Instance.new("Frame", sample)
            line.Name = name
            line.AnchorPoint = Vector2.new(0.5, 0.5)
            line.BackgroundColor3 = Color3.fromRGB(0, 255, 255)
            line.BorderSizePixel = 0
            line.Size = UDim2.fromOffset(1, 1)
            line.ZIndex = 92
            table.insert(skeletonLines, line)
            return line
        end

        local skeleton = {
            Shoulders = makeLine("SkeletonShoulders"),
            Neck = makeLine("SkeletonNeck"),
            Spine = makeLine("SkeletonSpine"),
            Hips = makeLine("SkeletonHips"),
            LeftArm = makeLine("SkeletonLeftArm"),
            RightArm = makeLine("SkeletonRightArm"),
            LeftLeg = makeLine("SkeletonLeftLeg"),
            RightLeg = makeLine("SkeletonRightLeg"),
        }

        local function snapPixel(value)
            return math.floor(value + 0.5)
        end

        local function setLine(line, x1, y1, x2, y2, thickness)
            x1 = snapPixel(x1)
            y1 = snapPixel(y1)
            x2 = snapPixel(x2)
            y2 = snapPixel(y2)

            local dx = x2 - x1
            local dy = y2 - y1
            local length = math.sqrt((dx * dx) + (dy * dy))
            local resolvedThickness = thickness
            if not resolvedThickness then
                resolvedThickness = (math.abs(dx) < 0.01 or math.abs(dy) < 0.01) and 2 or 1
            end

            line.Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2)
            line.Size = UDim2.fromOffset(math.max(1, length + 1), resolvedThickness)
            line.Rotation = math.deg((math.atan2 or math.atan)(dy, dx))
        end

        local function layoutPreview()
            local panelHeight = panel.AbsoluteSize.Y
            local panelWidth = panel.AbsoluteSize.X
            if panelHeight <= 0 or panelWidth <= 0 then
                return
            end

            local boxHeight = math.clamp(math.floor(panelHeight * 0.42), 120, math.max(120, panelHeight - 64))
            boxHeight = math.max(120, math.floor(boxHeight / 2) * 2)
            local boxWidth = math.clamp(math.floor(boxHeight * 0.48), 56, math.max(56, panelWidth - 46))
            boxWidth = math.max(56, math.floor(boxWidth / 2) * 2)
            sample.Size = UDim2.fromOffset(boxWidth, boxHeight)

            local boxCenterY = snapPixel(panelHeight * 0.48)
            local boxBottomY = boxCenterY + (boxHeight / 2)
            local boxCenterX = snapPixel(panelWidth / 2)
            sample.Position = UDim2.fromOffset(boxCenterX, boxCenterY)
            setLine(tracerLine, boxCenterX, panelHeight - 18, boxCenterX, boxBottomY, 1)

            local cx = snapPixel(boxWidth / 2)
            local headY = snapPixel(boxHeight * 0.23)
            local shoulderY = snapPixel(boxHeight * 0.35)
            local hipY = snapPixel(boxHeight * 0.61)
            local handY = snapPixel(boxHeight * 0.55)
            local footY = snapPixel(boxHeight * 0.91)

            local shoulderHalf = snapPixel(boxWidth * 0.30)
            local hipHalf = snapPixel(boxWidth * 0.17)
            local handHalf = snapPixel(boxWidth * 0.43)
            local footHalf = snapPixel(boxWidth * 0.28)

            setLine(skeleton.Shoulders, cx - shoulderHalf, shoulderY, cx + shoulderHalf, shoulderY)
            setLine(skeleton.Neck, cx, headY, cx, shoulderY)
            setLine(skeleton.Spine, cx, shoulderY, cx, hipY)
            setLine(skeleton.Hips, cx - hipHalf, hipY, cx + hipHalf, hipY)
            setLine(skeleton.LeftArm, cx - shoulderHalf, shoulderY, cx - handHalf, handY)
            setLine(skeleton.RightArm, cx + shoulderHalf, shoulderY, cx + handHalf, handY)
            setLine(skeleton.LeftLeg, cx - hipHalf, hipY, cx - footHalf, footY)
            setLine(skeleton.RightLeg, cx + hipHalf, hipY, cx + footHalf, footY)
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

            nameLabel.Visible = state.Name == true
            teamLabel.Visible = state.Team == true
            healthBack.Visible = state.Health == true
            healthText.Visible = state.Health == true
            tracerLine.Visible = state.Tracers == true
            heldItemLabel.Visible = state.HeldItem == true
            for _, line in ipairs(skeletonLines) do
                line.Visible = state.Skeleton == true
            end
        end

        local function syncVisibility()
            panel.Visible = menu._page == nil or menu._page.Visible == true
        end

        local function syncLayout()
            panel.Size = UDim2.new(0, previewWidth, 1, -previewVerticalInset)
            layoutPreview()
        end

        if controlsSection._cleanup and type(controlsSection._cleanup.Add) == "function" then
            controlsSection._cleanup:Add(panel, "Destroy", "PlayerEspPreviewPanel")
        end
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
