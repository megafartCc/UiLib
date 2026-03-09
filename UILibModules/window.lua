return function(Library, context, moduleRequire)
    local UserInputService = context.UserInputService
    local RunService = context.RunService
    local Players = context.Players
    local HttpService = context.HttpService
    local TextService = context.TextService
    local Client = context.Client
    local Cleaner = context.Cleaner
    local getHiddenParent = context.getHiddenParent
    local protectGui = context.protectGui
    local randomStr = context.randomStr

function Library:CreateWindow(opts)
    opts = opts or {}
    local name = opts.Name or "FATALITY"
    local expire = opts.Expire or "never"
    local keybind = opts.Keybind or self.Config.ToggleKey
    local configName = opts.ConfigName or nil
    local colors = self.Colors
    local config = self.Config
    local rootCleanup = Cleaner.new()

    -- Set config name for save/load
    self._configName = configName
    self._configItems = {}

    local win = {
        Menus = {},
        ActiveMenu = nil,
        Visible = true,
        _cleanup = rootCleanup,
    }
    local startupReady = false
    local setResizeCursor

    local function track(taskObject, methodName, key)
        return rootCleanup:Add(taskObject, methodName, key)
    end

    local function trackGlobal(conn, key)
        return track(conn, "Disconnect", key)
    end

    local cleanupKeySeed = 0
    local function nextCleanupKey(prefix)
        cleanupKeySeed += 1
        return string.format("%s_%d", prefix or "Cleanup", cleanupKeySeed)
    end

    local smoothScrollStates = {}

    local function createSmoothScrollState(opts)
        local state = {
            current = opts.InitialOffset or 0,
            target = opts.InitialOffset or 0,
            speed = opts.Speed or 18,
            epsilon = opts.Epsilon or 0.1,
            getMaxOffset = opts.GetMaxOffset,
            apply = opts.Apply,
            _lastApplied = nil,
        }

        function state:_clamp()
            local maxOffset = math.max(0, self.getMaxOffset())
            self.target = math.clamp(self.target, 0, maxOffset)
            self.current = math.clamp(self.current, 0, maxOffset)
            return maxOffset
        end

        function state:SetTarget(offset, snap)
            local maxOffset = math.max(0, self.getMaxOffset())
            self.target = math.clamp(offset, 0, maxOffset)
            if snap then
                self.current = self.target
            end

            self.apply(self.current)
            self._lastApplied = self.current
        end

        function state:ScrollBy(delta)
            self:SetTarget(self.target + delta, false)
        end

        function state:Refresh(snap)
            self:SetTarget(self.target, snap)
        end

        function state:Destroy()
            smoothScrollStates[self] = nil
        end

        smoothScrollStates[state] = true
        state:Refresh(true)

        return state
    end

    trackGlobal(RunService.RenderStepped:Connect(function(dt)
        for state in pairs(smoothScrollStates) do
            state:_clamp()

            if math.abs(state.target - state.current) <= state.epsilon then
                if state.current ~= state.target then
                    state.current = state.target
                end

                if state._lastApplied ~= state.current then
                    state.apply(state.current)
                    state._lastApplied = state.current
                end
            else
                local alpha = 1 - math.exp(-state.speed * dt)
                state.current += (state.target - state.current) * alpha

                if math.abs(state.target - state.current) <= state.epsilon then
                    state.current = state.target
                end

                state.apply(state.current)
                state._lastApplied = state.current
            end
        end
    end), "SmoothScrollTick")

    local popupManager = moduleRequire("popup_manager.lua")(Library, {
        nextCleanupKey = nextCleanupKey,
        trackGlobal = trackGlobal,
        UserInputService = UserInputService,
        win = win,
    })
    local controlBase = moduleRequire("controls_base.lua")(Library, context)
    local dropdownControls = moduleRequire("dropdowns.lua")(Library, context)
    local closeTransientPopups = popupManager.closeTransientPopups
    local registerTransientPopup = popupManager.registerTransientPopup
    local setPopupOpen = popupManager.setPopupOpen

    -- ScreenGui
    local sg = Instance.new("ScreenGui")
    sg.Name = randomStr()
    sg.ResetOnSpawn = false
    sg.IgnoreGuiInset = true
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Global

    -- Kill blue selection borders globally
    pcall(function()
        game:GetService("GuiService").AutoSelectGuiEnabled = false
        game:GetService("GuiService").GuiNavigationEnabled = false
    end)

    protectGui(sg)
    sg.Parent = getHiddenParent()

    function win:Destroy()
        if self._destroyed then
            return
        end

        self._destroyed = true
        setResizeCursor(nil, Vector2.new(0, 0))
        win.Resizing = false
        closeTransientPopups()

        for panel in pairs(self._floatingPanels or {}) do
            panel.Visible = false
        end

        pcall(function()
            rootCleanup:Cleanup()
        end)

        pcall(function()
            if sg then
                sg:Destroy()
            end
        end)

        self.Menus = {}
        self.ActiveMenu = nil
        self._floatingPanels = {}
    end

    -- ==============================
    -- MAIN FRAME
    -- ==============================
    local blankSel = Instance.new("Frame")
    blankSel.BackgroundTransparency = 1
    blankSel.BorderSizePixel = 0
    blankSel.Size = UDim2.new(0, 0, 0, 0)
    blankSel.Selectable = false

    local dropShadow = Instance.new("ImageLabel")
    dropShadow.Name = randomStr()
    dropShadow.AnchorPoint = Vector2.new(0.5, 0.5)
    dropShadow.BackgroundTransparency = 1
    dropShadow.BorderSizePixel = 0
    dropShadow.Position = UDim2.new(0.5, 0, 0.5, 0)
    dropShadow.Size = UDim2.new(1, 47, 1, 47)
    dropShadow.ZIndex = -1
    dropShadow.Image = "rbxassetid://6014261993"
    dropShadow.ImageColor3 = Color3.fromRGB(0, 0, 0)
    dropShadow.ImageTransparency = 0.75
    dropShadow.ScaleType = Enum.ScaleType.Slice
    dropShadow.SliceCenter = Rect.new(49, 49, 450, 450)

    local clipFrame = Instance.new("Frame")
    clipFrame.Name = "ClipFrame"
    clipFrame.BackgroundTransparency = 1
    clipFrame.BorderSizePixel = 0
    clipFrame.Size = UDim2.new(1, 0, 1, 0)
    clipFrame.ClipsDescendants = true
    clipFrame.ZIndex = 1
    local clipCorner = Instance.new("UICorner")
    clipCorner.CornerRadius = UDim.new(0, 5)
    clipCorner.Parent = clipFrame

    local main = Instance.new("Frame")
    main.Parent = sg
    main.Name = randomStr()
    main.Active = true
    main.AnchorPoint = Vector2.new(0.5, 0)
    main.BackgroundColor3 = colors.Background
    main.BorderSizePixel = 0
    main.Position = UDim2.new(0.5, 0, 0.2, 0)
    main.Size = UDim2.fromOffset(config.WindowWidth, config.WindowHeight)
    main.ClipsDescendants = false
    main.Visible = false
    main.SelectionImageObject = blankSel

    local mainCorner = Instance.new("UICorner")
    mainCorner.CornerRadius = UDim.new(0, 5)
    mainCorner.Parent = main
    dropShadow.Parent = main
    clipFrame.Parent = main

    -- ==============================
    -- HEADER BAR (40px)
    -- ==============================
    local header = Instance.new("Frame", clipFrame)
    header.Name = randomStr()
    header.Active = true
    header.BackgroundColor3 = colors.Header
    header.BorderSizePixel = 0
    header.Size = UDim2.new(1, 0, 0, config.HeaderHeight)
    header.ZIndex = 2

    Instance.new("UICorner", header).CornerRadius = UDim.new(0, 5)

    -- Header line (1px separator at bottom)
    local headerLine = Instance.new("Frame", header)
    headerLine.Name = randomStr()
    headerLine.AnchorPoint = Vector2.new(0, 1)
    headerLine.BackgroundColor3 = colors.Line
    headerLine.BorderSizePixel = 0
    headerLine.Position = UDim2.new(0, 0, 1, 0)
    headerLine.Size = UDim2.new(1, 0, 0, 1)
    headerLine.ZIndex = 3

    -- Header shadow gradient
    local headerShadow = Instance.new("Frame", header)
    headerShadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    headerShadow.BorderSizePixel = 0
    headerShadow.Size = UDim2.new(1, 0, 1, 10)
    headerShadow.ZIndex = 1
    Instance.new("UICorner", headerShadow).CornerRadius = UDim.new(0, 5)
    local shadowGrad = Instance.new("UIGradient", headerShadow)
    shadowGrad.Rotation = 90
    shadowGrad.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(1, 1),
    })

    -- Title text
    local headerText = Instance.new("TextLabel", header)
    headerText.Name = randomStr()
    headerText.AnchorPoint = Vector2.new(0.5, 0.5)
    headerText.BackgroundTransparency = 1
    headerText.BorderSizePixel = 0
    headerText.Position = UDim2.new(0, 57, 0.5, 0)
    headerText.Size = UDim2.new(0, 115, 1, 0)
    headerText.ZIndex = 4
    headerText.Font = config.Font
    headerText.Text = name
    headerText.TextColor3 = colors.Text
    headerText.TextSize = 21
    headerText.TextXAlignment = Enum.TextXAlignment.Center
    headerText.TextStrokeColor3 = Color3.fromRGB(205, 67, 218)
    headerText.TextStrokeTransparency = 0.64

    -- ==============================
    -- TAB CONTAINER (scrolling)
    -- ==============================
    local menuBtnCont = Instance.new("Frame", header)
    menuBtnCont.Name = randomStr()
    menuBtnCont.AnchorPoint = Vector2.new(0, 0.5)
    menuBtnCont.BackgroundTransparency = 1
    menuBtnCont.BorderSizePixel = 0
    menuBtnCont.ClipsDescendants = true
    menuBtnCont.Position = UDim2.new(0, 115, 0.5, 0)
    menuBtnCont.Size = UDim2.new(1, -275, 0.75, 0)
    menuBtnCont.ZIndex = 4
    menuBtnCont.Active = true  -- sinks mouse input

    local tbc = Instance.new("Frame", menuBtnCont)
    tbc.Name = randomStr()
    tbc.Active = true
    tbc.AnchorPoint = Vector2.new(0, 0.5)
    tbc.BackgroundTransparency = 1
    tbc.BorderSizePixel = 0
    tbc.Position = UDim2.new(0, 0, 0.5, 0)
    tbc.Size = UDim2.new(0, 5000, 1, 0)  -- wide enough for all tabs
    tbc.ZIndex = 4

    local tabListLayout = Instance.new("UIListLayout", tbc)
    tabListLayout.FillDirection = Enum.FillDirection.Horizontal
    tabListLayout.SortOrder = Enum.SortOrder.LayoutOrder
    tabListLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    tabListLayout.Padding = UDim.new(0, 4)

    -- Horizontal scroll for tabs
    local TAB_SCROLL_STEP = 40
    local tabScrollState = createSmoothScrollState({
        Speed = 16,
        GetMaxOffset = function()
            local contentW = tabListLayout.AbsoluteContentSize.X + 4
            local visibleW = menuBtnCont.AbsoluteSize.X
            return math.max(0, contentW - visibleW)
        end,
        Apply = function(offset)
            tbc.Position = UDim2.new(0, -math.floor(offset + 0.5), 0.5, 0)
        end,
    })
    track(tabScrollState, "Destroy", nextCleanupKey("TabScrollState"))

    menuBtnCont.InputChanged:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseWheel then return end
        tabScrollState:ScrollBy(-input.Position.Z * TAB_SCROLL_STEP)
    end)

    -- ==============================
    -- USER PROFILE (right side of header)
    -- ==============================
    local userProfile = Instance.new("Frame", header)
    userProfile.Name = randomStr()
    userProfile.AnchorPoint = Vector2.new(1, 0.5)
    userProfile.BackgroundTransparency = 1
    userProfile.BorderSizePixel = 0
    userProfile.Position = UDim2.new(1, -5, 0.5, 0)
    userProfile.Size = UDim2.new(0, 150, 0.75, 0)
    userProfile.ZIndex = 4

    -- Avatar
    local userIcon = Instance.new("ImageLabel", userProfile)
    userIcon.Name = randomStr()
    userIcon.AnchorPoint = Vector2.new(1, 0.5)
    userIcon.BackgroundTransparency = 1
    userIcon.BorderSizePixel = 0
    userIcon.Position = UDim2.new(1, -10, 0.5, 0)
    userIcon.Size = UDim2.new(0.8, 0, 0.8, 0)
    userIcon.SizeConstraint = Enum.SizeConstraint.RelativeYY
    userIcon.ZIndex = 5
    userIcon.Image = Players:GetUserThumbnailAsync(Client.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size180x180)

    Instance.new("UICorner", userIcon).CornerRadius = UDim.new(1, 0)

    local avatarStroke = Instance.new("UIStroke", userIcon)
    avatarStroke.Thickness = 2.5
    avatarStroke.Transparency = 0.9

    -- Username
    local userName = Instance.new("TextLabel", userProfile)
    userName.Name = randomStr()
    userName.AnchorPoint = Vector2.new(1, 0)
    userName.BackgroundTransparency = 1
    userName.BorderSizePixel = 0
    userName.Position = UDim2.new(1, -40, 0, 3)
    userName.Size = UDim2.new(0, 200, 0, 15)
    userName.ZIndex = 4
    userName.Font = config.FontMedium
    userName.Text = Client.DisplayName
    userName.TextColor3 = Color3.fromRGB(255, 255, 255)
    userName.TextSize = 13
    userName.TextStrokeTransparency = 0.7
    userName.TextXAlignment = Enum.TextXAlignment.Right

    -- Expire / Premium text
    local expireDays = Instance.new("TextLabel", userProfile)
    expireDays.Name = randomStr()
    expireDays.AnchorPoint = Vector2.new(1, 0)
    expireDays.BackgroundTransparency = 1
    expireDays.BorderSizePixel = 0
    expireDays.Position = UDim2.new(1, -40, 0, 16)
    expireDays.Size = UDim2.new(0, 200, 0, 15)
    expireDays.ZIndex = 4
    expireDays.Font = config.FontMedium
    expireDays.RichText = true
    expireDays.Text = string.format('<font transparency="0.5">expires:</font> <font color="#f53174">%s</font>', expire)
    expireDays.TextColor3 = Color3.fromRGB(255, 255, 255)
    expireDays.TextSize = 12
    expireDays.TextStrokeTransparency = 0.7
    expireDays.TextXAlignment = Enum.TextXAlignment.Right

    -- ==============================
    -- MENU CONTENT AREA
    -- ==============================
    local menuFrame = Instance.new("Frame", clipFrame)
    menuFrame.Name = randomStr()
    menuFrame.BackgroundTransparency = 1
    menuFrame.BorderSizePixel = 0
    menuFrame.Position = UDim2.new(0, 0, 0, config.HeaderHeight + 10)
    menuFrame.Size = UDim2.new(1, 0, 1, -(config.HeaderHeight + 10 + config.BottomHeight + 7))
    menuFrame.ZIndex = 1
    menuFrame.ClipsDescendants = true

    local menuContent = Instance.new("Frame", menuFrame)
    menuContent.Name = "ContentRoot"
    menuContent.BackgroundTransparency = 1
    menuContent.BorderSizePixel = 0
    menuContent.Position = UDim2.new(0, 0, 0, 0)
    menuContent.Size = UDim2.new(1, 0, 1, 0)
    menuContent.ZIndex = 1

    local menuScale = Instance.new("UIScale", menuContent)
    local contentScaleOptions = {
        { Label = "90%", Value = 0.9 },
        { Label = "100%", Value = 1.0 },
        { Label = "110%", Value = 1.1 },
        { Label = "125%", Value = 1.25 },
        { Label = "140%", Value = 1.4 },
    }
    local currentContentScale = config.ContentScale or 1
    local function refreshMenuScrolls()
    end
    local function updateContentScaleHost(scaleValue)
        local safeScale = math.max(scaleValue or 1, 0.01)
        menuContent.Size = UDim2.new(1 / safeScale, 0, 1 / safeScale, 0)
    end

    local function getContentScaleOption(rawValue)
        local numericValue = tonumber(rawValue)
        for _, option in ipairs(contentScaleOptions) do
            if option.Label == rawValue then
                return option
            end
            if numericValue and math.abs(option.Value - numericValue) < 0.001 then
                return option
            end
        end
        return contentScaleOptions[2]
    end

    local function setContentScale(rawValue)
        local option = getContentScaleOption(rawValue)
        currentContentScale = option.Value
        updateContentScaleHost(option.Value)
        menuScale.Scale = option.Value
        refreshMenuScrolls()
        return option
    end

    setContentScale(currentContentScale)

    -- ==============================
    -- BOTTOM BAR (25px)
    -- ==============================
    local bottom = Instance.new("Frame", clipFrame)
    bottom.Name = randomStr()
    bottom.Active = true
    bottom.AnchorPoint = Vector2.new(0, 1)
    bottom.BackgroundColor3 = colors.Header
    bottom.BorderSizePixel = 0
    bottom.Position = UDim2.new(0, 0, 1, 0)
    bottom.Size = UDim2.new(1, 0, 0, config.BottomHeight)
    bottom.ZIndex = 2

    Instance.new("UICorner", bottom).CornerRadius = UDim.new(0, 4)

    -- Bottom top line
    local bottomLine = Instance.new("Frame", bottom)
    bottomLine.BackgroundColor3 = colors.Line
    bottomLine.BorderSizePixel = 0
    bottomLine.Size = UDim2.new(1, 0, 0, 1)
    bottomLine.ZIndex = 3

    -- Bottom shadow (upward gradient)
    local bottomShadow = Instance.new("Frame", bottom)
    bottomShadow.AnchorPoint = Vector2.new(0, 1)
    bottomShadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    bottomShadow.BackgroundTransparency = 0.5
    bottomShadow.BorderSizePixel = 0
    bottomShadow.Position = UDim2.new(0, 0, 1, 0)
    bottomShadow.Size = UDim2.new(1, 0, 1, 5)
    local bottomGrad = Instance.new("UIGradient", bottomShadow)
    bottomGrad.Rotation = -90
    bottomGrad.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(1, 1),
    })
    Instance.new("UICorner", bottomShadow).CornerRadius = UDim.new(0, 5)

    -- ==============================
    -- SETTINGS GEAR BUTTON
    -- ==============================
    local gearBtn = Instance.new("ImageButton", bottom)
    gearBtn.Name = "SettingsGear"
    gearBtn.AnchorPoint = Vector2.new(1, 0.5)
    gearBtn.Position = UDim2.new(1, -8, 0.5, 0)
    gearBtn.Size = UDim2.new(0, 16, 0, 16)
    gearBtn.BackgroundTransparency = 1
    gearBtn.BorderSizePixel = 0
    gearBtn.Image = "rbxassetid://128549102277434"
    gearBtn.ImageColor3 = colors.TextDim
    gearBtn.ZIndex = 4
    gearBtn.AutoButtonColor = false

    gearBtn.MouseEnter:Connect(function()
        Library:Animate(gearBtn, "Hover", { ImageColor3 = colors.Main })
    end)
    gearBtn.MouseLeave:Connect(function()
        Library:Animate(gearBtn, "Hover", { ImageColor3 = colors.TextDim })
    end)

    -- ==============================
    -- SETTINGS FLOATING PANEL
    -- ==============================
    local settingsPanel = Instance.new("Frame", clipFrame)
    settingsPanel.Name = "SettingsPanel"
    settingsPanel.AnchorPoint = Vector2.new(1, 1)
    settingsPanel.Position = UDim2.new(1, -8, 1, -(config.BottomHeight + 6))
    settingsPanel.Size = UDim2.new(0, 180, 0, 0)
    settingsPanel.BackgroundColor3 = Color3.fromRGB(22, 22, 22)
    settingsPanel.BorderSizePixel = 0
    settingsPanel.ClipsDescendants = true
    settingsPanel.Visible = false
    settingsPanel.ZIndex = 100
    Instance.new("UICorner", settingsPanel).CornerRadius = UDim.new(0, 5)
    local spStroke = Instance.new("UIStroke", settingsPanel)
    spStroke.Color = colors.Line
    spStroke.Transparency = 0.3

    -- Settings header
    local spHeader = Instance.new("TextLabel", settingsPanel)
    spHeader.BackgroundTransparency = 1
    spHeader.Position = UDim2.new(0, 10, 0, 0)
    spHeader.Size = UDim2.new(1, -20, 0, 28)
    spHeader.Font = config.Font
    spHeader.Text = "SETTINGS"
    spHeader.TextColor3 = Color3.fromRGB(255, 255, 255)
    spHeader.TextSize = 12
    spHeader.TextXAlignment = Enum.TextXAlignment.Left
    spHeader.ZIndex = 101

    -- Separator
    local spSep = Instance.new("Frame", settingsPanel)
    spSep.Position = UDim2.new(0, 8, 0, 28)
    spSep.Size = UDim2.new(1, -16, 0, 1)
    spSep.BackgroundColor3 = colors.Line
    spSep.BorderSizePixel = 0
    spSep.ZIndex = 101

    -- Auto-save row
    local autoSaveRow = Instance.new("Frame", settingsPanel)
    autoSaveRow.Position = UDim2.new(0, 10, 0, 34)
    autoSaveRow.Size = UDim2.new(1, -20, 0, 20)
    autoSaveRow.BackgroundTransparency = 1
    autoSaveRow.ZIndex = 101

    local asLabel = Instance.new("TextLabel", autoSaveRow)
    asLabel.BackgroundTransparency = 1
    asLabel.Size = UDim2.new(0.6, 0, 1, 0)
    asLabel.Font = config.FontMedium
    asLabel.Text = "Auto-save"
    asLabel.TextColor3 = colors.Text
    asLabel.TextSize = 11
    asLabel.TextXAlignment = Enum.TextXAlignment.Left
    asLabel.ZIndex = 101

    local asChkFrame = Instance.new("Frame", autoSaveRow)
    asChkFrame.AnchorPoint = Vector2.new(1, 0.5)
    asChkFrame.Position = UDim2.new(1, 0, 0.5, 0)
    asChkFrame.Size = UDim2.new(0, 12, 0, 12)
    asChkFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    asChkFrame.BorderSizePixel = 0
    asChkFrame.ZIndex = 101
    Instance.new("UICorner", asChkFrame).CornerRadius = UDim.new(0, 3)
    local asChkStroke = Instance.new("UIStroke", asChkFrame)
    asChkStroke.Color = colors.Line
    asChkStroke.Transparency = 0.5

    local asCheckIcon = Instance.new("ImageLabel", asChkFrame)
    asCheckIcon.BackgroundTransparency = 1
    asCheckIcon.AnchorPoint = Vector2.new(0.5, 0.5)
    asCheckIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
    asCheckIcon.Size = UDim2.new(0, 10, 0, 10)
    asCheckIcon.Image = "rbxassetid://122354904349171"
    asCheckIcon.ImageColor3 = colors.Main
    asCheckIcon.ImageTransparency = 1
    asCheckIcon.ZIndex = 102

    local asBtn = Instance.new("TextButton", autoSaveRow)
    asBtn.BackgroundTransparency = 1
    asBtn.Size = UDim2.new(1, 0, 1, 0)
    asBtn.Text = ""
    asBtn.ZIndex = 103
    asBtn.AutoButtonColor = false
    asBtn.Selectable = false
    asBtn.BorderSizePixel = 0

    local function updateAutoSaveVisual(enabled, animate)
        local checkTransparency = enabled and 0 or 1
        local frameColor = enabled and Color3.fromRGB(45, 25, 30) or Color3.fromRGB(35, 35, 35)
        local strokeColor = enabled and colors.Main or colors.Line
        local strokeTransparency = enabled and 0.3 or 0.5

        if animate then
            Library:Spring(asCheckIcon, "Smooth", { ImageTransparency = checkTransparency })
            Library:Spring(asChkFrame, "Smooth", { BackgroundColor3 = frameColor })
            Library:Spring(asChkStroke, "Smooth", { Color = strokeColor, Transparency = strokeTransparency })
            return
        end

        asCheckIcon.ImageTransparency = checkTransparency
        asChkFrame.BackgroundColor3 = frameColor
        asChkStroke.Color = strokeColor
        asChkStroke.Transparency = strokeTransparency
    end

    local function setAutoSaveEnabled(enabled, animate)
        Library._autoSave = enabled and true or false
        updateAutoSaveVisual(Library._autoSave, animate)
    end

    updateAutoSaveVisual(Library._autoSave, false)

    asBtn.Activated:Connect(function()
        setAutoSaveEnabled(not Library._autoSave, true)
        pcall(function() Library:SaveConfig() end)
    end)

    -- Save button
    local saveBtn = Instance.new("TextButton", settingsPanel)
    saveBtn.Position = UDim2.new(0, 10, 0, 60)
    saveBtn.Size = UDim2.new(0.45, -12, 0, 22)
    saveBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    saveBtn.BorderSizePixel = 0
    saveBtn.Font = config.FontMedium
    saveBtn.Text = "Save"
    saveBtn.TextColor3 = colors.Text
    saveBtn.TextSize = 11
    saveBtn.ZIndex = 101
    saveBtn.AutoButtonColor = false
    saveBtn.Selectable = false
    Instance.new("UICorner", saveBtn).CornerRadius = UDim.new(0, 3)

    saveBtn.MouseEnter:Connect(function()
        Library:Animate(saveBtn, "Hover", { BackgroundColor3 = Color3.fromRGB(50, 50, 50) })
    end)
    saveBtn.MouseLeave:Connect(function()
        Library:Animate(saveBtn, "Hover", { BackgroundColor3 = Color3.fromRGB(35, 35, 35) })
    end)
    saveBtn.Activated:Connect(function()
        pcall(function() Library:SaveConfig() end)
        Library:Animate(saveBtn, "Press", { BackgroundColor3 = Color3.fromRGB(45, 25, 30) })
        task.delay(0.3, function() Library:Animate(saveBtn, "Hover", { BackgroundColor3 = Color3.fromRGB(35, 35, 35) }) end)
    end)

    -- Load button
    local loadBtn = Instance.new("TextButton", settingsPanel)
    loadBtn.Position = UDim2.new(0.5, 2, 0, 60)
    loadBtn.Size = UDim2.new(0.45, -12, 0, 22)
    loadBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    loadBtn.BorderSizePixel = 0
    loadBtn.Font = config.FontMedium
    loadBtn.Text = "Load"
    loadBtn.TextColor3 = colors.Text
    loadBtn.TextSize = 11
    loadBtn.ZIndex = 101
    loadBtn.AutoButtonColor = false
    loadBtn.Selectable = false
    Instance.new("UICorner", loadBtn).CornerRadius = UDim.new(0, 3)

    loadBtn.MouseEnter:Connect(function()
        Library:Animate(loadBtn, "Hover", { BackgroundColor3 = Color3.fromRGB(50, 50, 50) })
    end)
    loadBtn.MouseLeave:Connect(function()
        Library:Animate(loadBtn, "Hover", { BackgroundColor3 = Color3.fromRGB(35, 35, 35) })
    end)
    loadBtn.Activated:Connect(function()
        pcall(function() Library:LoadConfig() end)
        Library:Animate(loadBtn, "Press", { BackgroundColor3 = Color3.fromRGB(45, 25, 30) })
        task.delay(0.3, function() Library:Animate(loadBtn, "Hover", { BackgroundColor3 = Color3.fromRGB(35, 35, 35) }) end)
    end)

    local SETTINGS_DROPDOWN_ARROW_CLOSED = utf8.char(9660)
    local SETTINGS_DROPDOWN_ARROW_OPEN = utf8.char(9650)
    local uiScalePanel
    local uiScaleDropdownOpen = false
    local setUiScaleDropdownOpen = function()
    end

    -- Toggle settings panel
    local settingsOpen = false
    local SETTINGS_HEIGHT = 146
    local settingsPopupConfig = {
        ClosedSize = UDim2.new(0, 180, 0, 0),
        OpenSize = UDim2.new(0, 180, 0, SETTINGS_HEIGHT),
        OpenToken = "Open",
        CloseToken = "Close",
        HideDelay = 0.24,
    }

    local function setSettingsOpen(nextOpen)
        if settingsOpen == nextOpen then
            return
        end

        settingsOpen = nextOpen

        if settingsOpen then
            closeTransientPopups(settingsPanel)
        else
            setUiScaleDropdownOpen(false)
        end

        setPopupOpen(settingsPanel, settingsOpen, settingsPopupConfig)
    end

    registerTransientPopup(settingsPanel, function()
        setSettingsOpen(false)
    end)

    gearBtn.Activated:Connect(function()
        setSettingsOpen(not settingsOpen)
    end)

    popupManager.bindOutsideClose({
        cleanupKey = "SettingsOutsideClick",
        close = function()
            setSettingsOpen(false)
        end,
        isOpen = function()
            return settingsOpen
        end,
        targets = function()
            return { settingsPanel, gearBtn, uiScalePanel }
        end,
    })

    -- ==============================
    -- SEARCH REGISTRY
    -- ==============================
    win._searchItems = {} -- { { name, menuName, secName, menuRef } }

    -- ==============================
    -- SEARCH ICON (bottom-left)
    -- ==============================
    local searchBtn = Instance.new("ImageButton", bottom)
    searchBtn.Name = "SearchBtn"
    searchBtn.AnchorPoint = Vector2.new(0, 0.5)
    searchBtn.Position = UDim2.new(0, 8, 0.5, 0)
    searchBtn.Size = UDim2.new(0, 16, 0, 16)
    searchBtn.BackgroundTransparency = 1
    searchBtn.BorderSizePixel = 0
    searchBtn.Image = "rbxassetid://105694268950175"
    searchBtn.ImageColor3 = colors.TextDim
    searchBtn.ZIndex = 4
    searchBtn.AutoButtonColor = false

    searchBtn.MouseEnter:Connect(function()
        Library:Animate(searchBtn, "Hover", { ImageColor3 = colors.Main })
    end)
    searchBtn.MouseLeave:Connect(function()
        Library:Animate(searchBtn, "Hover", { ImageColor3 = colors.TextDim })
    end)

    -- ==============================
    -- SEARCH FLOATING PANEL
    -- ==============================
    local searchPanel = Instance.new("Frame", clipFrame)
    searchPanel.Name = "SearchPanel"
    searchPanel.AnchorPoint = Vector2.new(0, 1)
    searchPanel.Position = UDim2.new(0, 8, 1, -(config.BottomHeight + 6))
    searchPanel.Size = UDim2.new(0, 240, 0, 0)
    searchPanel.BackgroundColor3 = Color3.fromRGB(22, 22, 22)
    searchPanel.BorderSizePixel = 0
    searchPanel.Active = true
    searchPanel.ClipsDescendants = true
    searchPanel.Visible = false
    searchPanel.ZIndex = 100
    Instance.new("UICorner", searchPanel).CornerRadius = UDim.new(0, 5)
    local srStroke = Instance.new("UIStroke", searchPanel)
    srStroke.Color = colors.Line
    srStroke.Transparency = 0.3

    -- Search input row
    local searchInputFrame = Instance.new("Frame", searchPanel)
    searchInputFrame.Position = UDim2.new(0, 8, 0, 6)
    searchInputFrame.Size = UDim2.new(1, -16, 0, 28)
    searchInputFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
    searchInputFrame.BorderSizePixel = 0
    searchInputFrame.ZIndex = 101
    Instance.new("UICorner", searchInputFrame).CornerRadius = UDim.new(0, 2)
    local sifStroke = Instance.new("UIStroke", searchInputFrame)
    sifStroke.Color = colors.Line
    sifStroke.Transparency = 0.5

    local searchBox = Instance.new("TextBox", searchInputFrame)
    searchBox.BackgroundTransparency = 1
    searchBox.Position = UDim2.new(0, 8, 0, 0)
    searchBox.Size = UDim2.new(1, -16, 1, 0)
    searchBox.Font = config.FontMedium
    searchBox.PlaceholderText = "Search..."
    searchBox.PlaceholderColor3 = colors.TextDim
    searchBox.Text = ""
    searchBox.TextColor3 = Color3.fromRGB(255, 255, 255)
    searchBox.TextSize = 13
    searchBox.TextXAlignment = Enum.TextXAlignment.Left
    searchBox.ClearTextOnFocus = false
    searchBox.ZIndex = 102

    -- Results scroll area
    local resultsFrame = Instance.new("Frame", searchPanel)
    resultsFrame.Position = UDim2.new(0, 4, 0, 40)
    resultsFrame.Size = UDim2.new(1, -8, 1, -44)
    resultsFrame.BackgroundTransparency = 1
    resultsFrame.BorderSizePixel = 0
    resultsFrame.Active = true
    resultsFrame.ClipsDescendants = true
    resultsFrame.ZIndex = 101

    -- Inner container for scroll
    local resultsInner = Instance.new("Frame", resultsFrame)
    resultsInner.Name = "ResultsInner"
    resultsInner.BackgroundTransparency = 1
    resultsInner.BorderSizePixel = 0
    resultsInner.Position = UDim2.new(0, 0, 0, 0)
    resultsInner.Size = UDim2.new(1, 0, 0, 5000)
    resultsInner.ZIndex = 101

    local resultsLayout = Instance.new("UIListLayout", resultsInner)
    resultsLayout.SortOrder = Enum.SortOrder.LayoutOrder
    resultsLayout.Padding = UDim.new(0, 2)

    -- Search scroll state
    local SEARCH_SCROLL_STEP = 30
    local searchScrollState = createSmoothScrollState({
        Speed = 16,
        GetMaxOffset = function()
            local contentH = resultsLayout.AbsoluteContentSize.Y + 4
            local visibleH = resultsFrame.AbsoluteSize.Y
            return math.max(0, contentH - visibleH)
        end,
        Apply = function(offset)
            resultsInner.Position = UDim2.new(0, 0, 0, -math.floor(offset + 0.5))
        end,
    })
    track(searchScrollState, "Destroy", nextCleanupKey("SearchScrollState"))

    local function isMouseInside(guiObject)
        if not guiObject or not guiObject.Parent then
            return false
        end
        local mp = UserInputService:GetMouseLocation()
        local ap = guiObject.AbsolutePosition
        local as = guiObject.AbsoluteSize
        return mp.X >= ap.X and mp.X <= ap.X + as.X and mp.Y >= ap.Y and mp.Y <= ap.Y + as.Y
    end

    trackGlobal(UserInputService.InputChanged:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseWheel then return end
        if not isMouseInside(resultsFrame) then return end
        searchScrollState:ScrollBy(-input.Position.Z * SEARCH_SCROLL_STEP)
    end), "SearchScroll")

    local SEARCH_PANEL_HEIGHT = 250
    local searchOpen = false
    local resultButtons = {}
    local setSearchOpen

    local function clearResults()
        for _, rb in ipairs(resultButtons) do
            rb:Destroy()
        end
        resultButtons = {}
    end

    local function doSearch(query)
        clearResults()
        searchScrollState:SetTarget(0, true)
        query = string.lower(query)

        local idx = 0
        for _, item in ipairs(win._searchItems) do
            local haystack = string.lower(item.name .. " " .. item.secName .. " " .. item.menuName)
            if query == "" or string.find(haystack, query, 1, true) then
                idx = idx + 1
                if idx > 30 then break end -- cap results

                local rb = Instance.new("TextButton", resultsInner)
                rb.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
                rb.BackgroundTransparency = 1
                rb.BorderSizePixel = 0
                rb.Size = UDim2.new(1, 0, 0, 36)
                rb.Text = ""
                rb.ZIndex = 102
                rb.LayoutOrder = idx
                rb.AutoButtonColor = false
                rb.Selectable = false
                Instance.new("UICorner", rb).CornerRadius = UDim.new(0, 3)

                -- Component name
                local nameLabel = Instance.new("TextLabel", rb)
                nameLabel.BackgroundTransparency = 1
                nameLabel.Position = UDim2.new(0, 8, 0, 2)
                nameLabel.Size = UDim2.new(1, -16, 0, 16)
                nameLabel.Font = config.FontMedium
                nameLabel.Text = item.name
                nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
                nameLabel.TextSize = 11
                nameLabel.TextXAlignment = Enum.TextXAlignment.Left
                nameLabel.ZIndex = 103

                -- Path
                local pathLabel = Instance.new("TextLabel", rb)
                pathLabel.BackgroundTransparency = 1
                pathLabel.Position = UDim2.new(0, 8, 0, 18)
                pathLabel.Size = UDim2.new(1, -16, 0, 14)
                pathLabel.Font = config.Font
                pathLabel.Text = item.menuName .. "  >  " .. item.secName .. "  >  " .. item.name
                pathLabel.TextColor3 = colors.TextDim
                pathLabel.TextSize = 9
                pathLabel.TextXAlignment = Enum.TextXAlignment.Left
                pathLabel.ZIndex = 103

                rb.MouseEnter:Connect(function()
                    Library:Animate(rb, "Hover", { BackgroundTransparency = 0 })
                end)
                rb.MouseLeave:Connect(function()
                    Library:Animate(rb, "Hover", { BackgroundTransparency = 1 })
                end)

                rb.Activated:Connect(function()
                    -- Navigate to that tab
                    if item.menuRef and item.menuRef._select then
                        if win.ActiveMenu and win.ActiveMenu ~= item.menuRef then
                            win.ActiveMenu._select(false)
                        end
                        win.ActiveMenu = item.menuRef
                        item.menuRef._select(true)
                    end
                    -- Close search
                    setSearchOpen(false)
                end)

                table.insert(resultButtons, rb)
            end
        end
    end

    searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        doSearch(searchBox.Text)
    end)

    local searchPopupConfig = {
        ClosedSize = UDim2.new(0, 240, 0, 0),
        OpenSize = UDim2.new(0, 240, 0, SEARCH_PANEL_HEIGHT),
        OpenToken = "Open",
        CloseToken = "Close",
        HideDelay = 0.24,
        OnOpen = function()
            doSearch(searchBox.Text)
            task.delay(0.15, function()
                if searchOpen and not win._destroyed then
                    searchBox:CaptureFocus()
                end
            end)
        end,
        OnClose = function()
            searchBox:ReleaseFocus()
        end,
    }

    setSearchOpen = function(nextOpen)
        if searchOpen == nextOpen then
            return
        end

        searchOpen = nextOpen

        if searchOpen then
            closeTransientPopups(searchPanel)
        end

        setPopupOpen(searchPanel, searchOpen, searchPopupConfig)
    end

    registerTransientPopup(searchPanel, function()
        setSearchOpen(false)
    end)

    -- Toggle search panel
    searchBtn.Activated:Connect(function()
        setSearchOpen(not searchOpen)
    end)

    popupManager.bindOutsideClose({
        cleanupKey = "SearchOutsideClick",
        close = function()
            setSearchOpen(false)
        end,
        isOpen = function()
            return searchOpen
        end,
        targets = function()
            return { searchPanel, searchBtn }
        end,
    })

    -- ==============================
    -- DRAGGING / RESIZING
    -- ==============================
    local dragInput, dragStart, dragBounds, dragInputType, dragPending
    local resizeStart, resizeBounds, resizeInputType, resizeEndInputType
    local resizeDirection, hoverResizeDirection
    local resizeBorder = config.ResizeBorder or 8
    local dragThreshold = 3
    local minWindowWidth = math.max(config.MinWindowWidth or 640, 520)
    local minWindowHeight = math.max(config.MinWindowHeight or 400, config.HeaderHeight + config.BottomHeight + 120)

    setResizeCursor = function()
    end

    local function getResizeDirection(position)
        if not win.Visible or not main.Visible then
            return nil
        end

        local boundsPos = main.AbsolutePosition
        local boundsSize = main.AbsoluteSize
        local x = position.X
        local y = position.Y

        if x < boundsPos.X or x > boundsPos.X + boundsSize.X or y < boundsPos.Y or y > boundsPos.Y + boundsSize.Y then
            return nil
        end

        local onLeft = x <= boundsPos.X + resizeBorder
        local onRight = x >= boundsPos.X + boundsSize.X - resizeBorder
        local onTop = y <= boundsPos.Y + resizeBorder
        local onBottom = y >= boundsPos.Y + boundsSize.Y - resizeBorder

        if onTop and onLeft then
            return "topLeft"
        elseif onTop and onRight then
            return "topRight"
        elseif onBottom and onLeft then
            return "bottomLeft"
        elseif onBottom and onRight then
            return "bottomRight"
        elseif onLeft then
            return "left"
        elseif onRight then
            return "right"
        elseif onTop then
            return "top"
        elseif onBottom then
            return "bottom"
        end

        return nil
    end

    local fullWindowSize = UDim2.fromOffset(config.WindowWidth, config.WindowHeight)
    local fullClipSize = UDim2.new(1, 0, 1, 0)

    local windowBounds = {
        left = math.floor(main.AbsolutePosition.X + 0.5),
        top = math.floor(main.AbsolutePosition.Y + 0.5),
        width = config.WindowWidth,
        height = config.WindowHeight,
    }

    local function applyWindowBounds(left, top, width, height)
        local clampedLeft = math.floor(left + 0.5)
        local clampedTop = math.floor(top + 0.5)
        local clampedWidth = math.max(minWindowWidth, math.floor(width + 0.5))
        local clampedHeight = math.max(minWindowHeight, math.floor(height + 0.5))
        local centerX = clampedLeft + (clampedWidth * 0.5)

        windowBounds.left = clampedLeft
        windowBounds.top = clampedTop
        windowBounds.width = clampedWidth
        windowBounds.height = clampedHeight

        main.Position = UDim2.fromOffset(math.floor(centerX + 0.5), clampedTop)
        main.Size = UDim2.fromOffset(clampedWidth, clampedHeight)
        fullWindowSize = UDim2.fromOffset(clampedWidth, clampedHeight)
        refreshMenuScrolls()
    end

    applyWindowBounds(windowBounds.left, windowBounds.top, windowBounds.width, windowBounds.height)

    local function updateResizeHover(position)
        if win.Resizing then
            setResizeCursor(resizeDirection, position)
            return
        end

        if win.Dragging then
            hoverResizeDirection = nil
            setResizeCursor(nil, position)
            return
        end

        hoverResizeDirection = getResizeDirection(position)
        setResizeCursor(hoverResizeDirection, position)
    end

    header.InputBegan:Connect(function(input)
        if win.Resizing then
            return
        end

        if getResizeDirection(input.Position) then
            return
        end

        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragPending = true
            dragStart = input.Position
            dragBounds = {
                left = windowBounds.left,
                top = windowBounds.top,
                width = windowBounds.width,
                height = windowBounds.height,
            }
            dragInputType = input.UserInputType == Enum.UserInputType.Touch and Enum.UserInputType.Touch or Enum.UserInputType.MouseMovement
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragPending = false
                    dragInputType = nil
                    win.Dragging = false
                    updateResizeHover(UserInputService:GetMouseLocation())
                end
            end)
        end
    end)

    header.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    trackGlobal(UserInputService.InputBegan:Connect(function(input)
        if win.Dragging or win.Resizing then
            return
        end

        if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end

        local direction = hoverResizeDirection or getResizeDirection(input.Position)
        if not direction then
            return
        end

        resizeDirection = direction
        dragInput = nil
        dragStart = nil
        dragBounds = nil
        dragPending = false
        dragInputType = nil
        win.Dragging = false
        resizeStart = input.Position
        resizeInputType = input.UserInputType == Enum.UserInputType.Touch and Enum.UserInputType.Touch or Enum.UserInputType.MouseMovement
        resizeEndInputType = input.UserInputType
        resizeBounds = {
            left = windowBounds.left,
            top = windowBounds.top,
            width = windowBounds.width,
            height = windowBounds.height,
        }
        win.Resizing = true
        self:Stop(main, "Position")
        self:Stop(main, "Size")
        setResizeCursor(resizeDirection, input.Position)
    end), "WindowResizeBegin")

    trackGlobal(UserInputService.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            updateResizeHover(input.Position)
        end

        if dragPending and not win.Dragging and not win.Resizing and dragInputType and input.UserInputType == dragInputType then
            local delta = input.Position - dragStart
            if math.abs(delta.X) >= dragThreshold or math.abs(delta.Y) >= dragThreshold then
                dragPending = false
                win.Dragging = true
                self:Stop(main, "Position")
            end
        end

        if input == dragInput and win.Dragging then
            local delta = input.Position - dragStart
            applyWindowBounds(
                dragBounds.left + delta.X,
                dragBounds.top + delta.Y,
                dragBounds.width,
                dragBounds.height
            )
            return
        end

        if not win.Resizing or not resizeBounds then
            return
        end

        if resizeInputType and input.UserInputType ~= resizeInputType then
            return
        end

        local delta = input.Position - resizeStart
        local left = resizeBounds.left
        local top = resizeBounds.top
        local width = resizeBounds.width
        local height = resizeBounds.height

        if resizeDirection == "left" or resizeDirection == "topLeft" or resizeDirection == "bottomLeft" then
            width = resizeBounds.width - delta.X
            left = resizeBounds.left + delta.X
            if width < minWindowWidth then
                left = resizeBounds.left + (resizeBounds.width - minWindowWidth)
                width = minWindowWidth
            end
        end

        if resizeDirection == "right" or resizeDirection == "topRight" or resizeDirection == "bottomRight" then
            width = math.max(minWindowWidth, resizeBounds.width + delta.X)
        end

        if resizeDirection == "top" or resizeDirection == "topLeft" or resizeDirection == "topRight" then
            height = resizeBounds.height - delta.Y
            top = resizeBounds.top + delta.Y
            if height < minWindowHeight then
                top = resizeBounds.top + (resizeBounds.height - minWindowHeight)
                height = minWindowHeight
            end
        end

        if resizeDirection == "bottom" or resizeDirection == "bottomLeft" or resizeDirection == "bottomRight" then
            height = math.max(minWindowHeight, resizeBounds.height + delta.Y)
        end

        applyWindowBounds(left, top, width, height)
        setResizeCursor(resizeDirection, input.Position)
    end), "WindowDragResize")

    trackGlobal(UserInputService.InputEnded:Connect(function(input)
        if not win.Resizing or not resizeEndInputType or input.UserInputType ~= resizeEndInputType then
            return
        end

        resizeStart = nil
        resizeBounds = nil
        resizeInputType = nil
        resizeEndInputType = nil
        resizeDirection = nil
        win.Resizing = false
        updateResizeHover(UserInputService:GetMouseLocation())
    end), "WindowResizeEnd")

    -- ==============================
    -- TOGGLE (Insert key)
    -- ==============================
    local guiKeybind = keybind  -- mutable keybind
    
    win._floatingPanels = {} -- panels that live outside clipFrame and need independent toggle states

    local function syncFloatingPanels()
        for panel, state in pairs(win._floatingPanels) do
            panel.Visible = startupReady and win.Visible and state.Active or false
        end
    end

    local function smoothToggle()
        win.Visible = not win.Visible

        if not startupReady then
            syncFloatingPanels()
            return
        end

        if win.Visible then
            main.Visible = true
            main.Size = fullWindowSize
            clipFrame.Size = fullClipSize
            updateResizeHover(UserInputService:GetMouseLocation())
            syncFloatingPanels()
        else
            closeTransientPopups()
            hoverResizeDirection = nil
            resizeDirection = nil
            dragInput = nil
            dragStart = nil
            dragBounds = nil
            dragPending = false
            dragInputType = nil
            resizeStart = nil
            resizeBounds = nil
            resizeInputType = nil
            resizeEndInputType = nil
            win.Resizing = false
            setResizeCursor(nil, Vector2.new(0, 0))
            main.Visible = false
            syncFloatingPanels()
        end
    end

    trackGlobal(UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if input.KeyCode == guiKeybind or (typeof(guiKeybind) == "string" and input.KeyCode.Name == guiKeybind) then
            smoothToggle()
        end
    end), "ToggleKeybind")

    -- ==============================
    -- CONTENT SCALE (settings panel)
    -- ==============================
    local uiScaleRow = Instance.new("Frame", settingsPanel)
    uiScaleRow.Position = UDim2.new(0, 10, 0, 88)
    uiScaleRow.Size = UDim2.new(1, -20, 0, 20)
    uiScaleRow.BackgroundTransparency = 1
    uiScaleRow.ZIndex = 101

    local uiScaleLabel = Instance.new("TextLabel", uiScaleRow)
    uiScaleLabel.BackgroundTransparency = 1
    uiScaleLabel.Size = UDim2.new(0.5, 0, 1, 0)
    uiScaleLabel.Font = config.FontMedium
    uiScaleLabel.Text = "UI Scale"
    uiScaleLabel.TextColor3 = colors.Text
    uiScaleLabel.TextSize = 11
    uiScaleLabel.TextXAlignment = Enum.TextXAlignment.Left
    uiScaleLabel.ZIndex = 101

    local uiScaleValueBtn = Instance.new("TextButton", uiScaleRow)
    uiScaleValueBtn.AnchorPoint = Vector2.new(1, 0.5)
    uiScaleValueBtn.Position = UDim2.new(1, 0, 0.5, 0)
    uiScaleValueBtn.Size = UDim2.new(0.45, 0, 0, 16)
    uiScaleValueBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    uiScaleValueBtn.BorderSizePixel = 0
    uiScaleValueBtn.Font = config.FontMedium
    uiScaleValueBtn.TextColor3 = colors.TextDim
    uiScaleValueBtn.TextSize = 10
    uiScaleValueBtn.TextXAlignment = Enum.TextXAlignment.Left
    uiScaleValueBtn.ZIndex = 102
    uiScaleValueBtn.AutoButtonColor = false
    uiScaleValueBtn.Selectable = false
    Instance.new("UICorner", uiScaleValueBtn).CornerRadius = UDim.new(0, 3)
    local uiScaleStroke = Instance.new("UIStroke", uiScaleValueBtn)
    uiScaleStroke.Color = colors.Line
    uiScaleStroke.Transparency = 0.5

    local uiScaleArrow = Instance.new("TextLabel", uiScaleValueBtn)
    uiScaleArrow.BackgroundTransparency = 1
    uiScaleArrow.AnchorPoint = Vector2.new(1, 0.5)
    uiScaleArrow.Position = UDim2.new(1, -4, 0.5, 0)
    uiScaleArrow.Size = UDim2.new(0, 12, 0, 12)
    uiScaleArrow.Font = config.Font
    uiScaleArrow.Text = SETTINGS_DROPDOWN_ARROW_CLOSED
    uiScaleArrow.TextColor3 = colors.TextDim
    uiScaleArrow.TextSize = 7
    uiScaleArrow.ZIndex = 103

    local function updateContentScaleVisual()
        uiScaleValueBtn.Text = getContentScaleOption(currentContentScale).Label
    end

    updateContentScaleVisual()

    local uiScalePanelWidth = 90
    local uiScalePanelHeight = (#contentScaleOptions * 20) + 6
    uiScalePanel = Instance.new("Frame", clipFrame)
    uiScalePanel.Name = "UiScalePanel"
    uiScalePanel.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
    uiScalePanel.BorderSizePixel = 0
    uiScalePanel.Size = UDim2.fromOffset(uiScalePanelWidth, 0)
    uiScalePanel.Visible = false
    uiScalePanel.ClipsDescendants = true
    uiScalePanel.ZIndex = 110
    Instance.new("UICorner", uiScalePanel).CornerRadius = UDim.new(0, 4)
    local uiScalePanelStroke = Instance.new("UIStroke", uiScalePanel)
    uiScalePanelStroke.Color = colors.Line
    uiScalePanelStroke.Transparency = 0.5

    local uiScaleLayout = Instance.new("UIListLayout", uiScalePanel)
    uiScaleLayout.SortOrder = Enum.SortOrder.LayoutOrder

    local uiScalePad = Instance.new("UIPadding", uiScalePanel)
    uiScalePad.PaddingTop = UDim.new(0, 3)
    uiScalePad.PaddingBottom = UDim.new(0, 3)

    local function positionUiScalePanel()
        local buttonPos = uiScaleValueBtn.AbsolutePosition
        local buttonSize = uiScaleValueBtn.AbsoluteSize
        local clipPos = clipFrame.AbsolutePosition
        local clipSize = clipFrame.AbsoluteSize
        local panelX = math.clamp(
            buttonPos.X - clipPos.X + buttonSize.X - uiScalePanelWidth,
            4,
            math.max(4, clipSize.X - uiScalePanelWidth - 4)
        )
        local preferredBelowY = buttonPos.Y - clipPos.Y + buttonSize.Y + 2
        local maxPanelY = math.max(4, clipSize.Y - uiScalePanelHeight - 4)
        local panelY = preferredBelowY

        if panelY > maxPanelY then
            panelY = buttonPos.Y - clipPos.Y - uiScalePanelHeight - 2
        end

        panelY = math.clamp(panelY, 4, maxPanelY)
        uiScalePanel.Position = UDim2.fromOffset(panelX, panelY)
    end

    for index, option in ipairs(contentScaleOptions) do
        local optionButton = Instance.new("TextButton", uiScalePanel)
        optionButton.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
        optionButton.BackgroundTransparency = 1
        optionButton.BorderSizePixel = 0
        optionButton.Size = UDim2.new(1, 0, 0, 20)
        optionButton.LayoutOrder = index
        optionButton.Text = ""
        optionButton.ZIndex = 111
        optionButton.AutoButtonColor = false
        optionButton.Selectable = false

        local optionLabel = Instance.new("TextLabel", optionButton)
        optionLabel.BackgroundTransparency = 1
        optionLabel.Position = UDim2.new(0, 8, 0, 0)
        optionLabel.Size = UDim2.new(1, -16, 1, 0)
        optionLabel.Font = config.FontMedium
        optionLabel.Text = option.Label
        optionLabel.TextColor3 = math.abs(option.Value - currentContentScale) < 0.001 and colors.Main or colors.Text
        optionLabel.TextSize = 10
        optionLabel.TextXAlignment = Enum.TextXAlignment.Left
        optionLabel.ZIndex = 112

        optionButton.MouseEnter:Connect(function()
            Library:Animate(optionButton, "Hover", { BackgroundTransparency = 0.5 })
            if math.abs(option.Value - currentContentScale) >= 0.001 then
                Library:Animate(optionLabel, "Hover", { TextColor3 = Color3.fromRGB(255, 255, 255) })
            end
        end)

        optionButton.MouseLeave:Connect(function()
            Library:Animate(optionButton, "Hover", { BackgroundTransparency = 1 })
            optionLabel.TextColor3 = math.abs(option.Value - currentContentScale) < 0.001 and colors.Main or colors.Text
        end)

        optionButton.Activated:Connect(function()
            setContentScale(option.Value)
            updateContentScaleVisual()
            for _, child in ipairs(uiScalePanel:GetChildren()) do
                if child:IsA("TextButton") then
                    local childLabel = child:FindFirstChildOfClass("TextLabel")
                    if childLabel then
                        local selected = childLabel.Text == option.Label
                        childLabel.TextColor3 = selected and colors.Main or colors.Text
                    end
                end
            end
            setUiScaleDropdownOpen(false)
            pcall(function() Library:SaveConfig() end)
        end)
    end

    local uiScalePopupConfig = {
        ClosedSize = UDim2.fromOffset(uiScalePanelWidth, 0),
        OpenSize = UDim2.fromOffset(uiScalePanelWidth, uiScalePanelHeight),
        OpenToken = "Open",
        CloseToken = "Close",
        HideDelay = 0.2,
    }

    setUiScaleDropdownOpen = function(nextOpen)
        if uiScaleDropdownOpen == nextOpen then
            return
        end

        uiScaleDropdownOpen = nextOpen
        if uiScaleDropdownOpen then
            positionUiScalePanel()
        end

        setPopupOpen(uiScalePanel, uiScaleDropdownOpen, uiScalePopupConfig)
        uiScaleArrow.Text = uiScaleDropdownOpen and SETTINGS_DROPDOWN_ARROW_OPEN or SETTINGS_DROPDOWN_ARROW_CLOSED
    end

    registerTransientPopup(uiScalePanel, function()
        setUiScaleDropdownOpen(false)
    end)

    uiScaleValueBtn.Activated:Connect(function()
        setUiScaleDropdownOpen(not uiScaleDropdownOpen)
    end)

    popupManager.bindOutsideClose({
        cleanupKey = "UiScaleOutsideClick",
        close = function()
            setUiScaleDropdownOpen(false)
        end,
        isOpen = function()
            return uiScaleDropdownOpen
        end,
        targets = function()
            return { uiScalePanel, uiScaleValueBtn }
        end,
    })

    -- ==============================
    -- KEYBIND CHANGER (in settings panel)
    -- ==============================
    local kbRow = Instance.new("Frame", settingsPanel)
    kbRow.Position = UDim2.new(0, 10, 0, 114)
    kbRow.Size = UDim2.new(1, -20, 0, 20)
    kbRow.BackgroundTransparency = 1
    kbRow.ZIndex = 101

    local kbLabel = Instance.new("TextLabel", kbRow)
    kbLabel.BackgroundTransparency = 1
    kbLabel.Size = UDim2.new(0.5, 0, 1, 0)
    kbLabel.Font = config.FontMedium
    kbLabel.Text = "Toggle Key"
    kbLabel.TextColor3 = colors.Text
    kbLabel.TextSize = 11
    kbLabel.TextXAlignment = Enum.TextXAlignment.Left
    kbLabel.ZIndex = 101

    local kbValueBtn = Instance.new("TextButton", kbRow)
    kbValueBtn.AnchorPoint = Vector2.new(1, 0.5)
    kbValueBtn.Position = UDim2.new(1, 0, 0.5, 0)
    kbValueBtn.Size = UDim2.new(0.45, 0, 0, 16)
    kbValueBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    kbValueBtn.BorderSizePixel = 0
    kbValueBtn.Font = config.FontMedium
    kbValueBtn.Text = typeof(keybind) == "string" and keybind or keybind.Name
    kbValueBtn.TextColor3 = colors.TextDim
    kbValueBtn.TextSize = 10
    kbValueBtn.ZIndex = 102
    kbValueBtn.AutoButtonColor = false
    kbValueBtn.Selectable = false
    Instance.new("UICorner", kbValueBtn).CornerRadius = UDim.new(0, 3)
    local kbStroke = Instance.new("UIStroke", kbValueBtn)
    kbStroke.Color = colors.Line
    kbStroke.Transparency = 0.5

    local kbListening = false
    local kbConn = nil

    local function updateKeybindVisual(currentKey)
        if typeof(currentKey) == "EnumItem" then
            kbValueBtn.Text = currentKey.Name
        elseif typeof(currentKey) == "string" then
            kbValueBtn.Text = currentKey
        else
            kbValueBtn.Text = tostring(currentKey)
        end
    end

    local function setGuiKeybind(newKey, shouldSave)
        if typeof(newKey) == "string" then
            local enumKey = Enum.KeyCode[newKey]
            if enumKey then
                newKey = enumKey
            end
        end

        if typeof(newKey) ~= "EnumItem" or newKey.EnumType ~= Enum.KeyCode then
            return false
        end

        guiKeybind = newKey
        updateKeybindVisual(newKey)

        if shouldSave then
            pcall(function() Library:SaveConfig() end)
        end

        return true
    end

    updateKeybindVisual(guiKeybind)

    kbValueBtn.Activated:Connect(function()
        if kbListening then return end
        kbListening = true
        kbValueBtn.Text = "..."
        Library:Spring(kbStroke, "Smooth", { Color = colors.Main, Transparency = 0 })

        kbConn = trackGlobal(UserInputService.InputBegan:Connect(function(input, gpe)
            if input.UserInputType == Enum.UserInputType.Keyboard then
                -- Ignore modifier keys alone
                if input.KeyCode == Enum.KeyCode.Unknown then return end
                setGuiKeybind(input.KeyCode, true)
                Library:Spring(kbStroke, "Smooth", { Color = colors.Line, Transparency = 0.5 })
                kbListening = false
                if kbConn then
                    rootCleanup:Remove("KeybindCapture")
                    kbConn = nil
                end
            end
        end), "KeybindCapture")
    end)

    Library:RegisterConfig("__uilib.settings.auto_save", "setting",
        function()
            return Library._autoSave and true or false
        end,
        function(val)
            setAutoSaveEnabled(val == true, false)
        end
    )

    Library:RegisterConfig("__uilib.settings.content_scale", "setting",
        function()
            return currentContentScale
        end,
        function(val)
            setContentScale(val)
            updateContentScaleVisual()
            for _, child in ipairs(uiScalePanel:GetChildren()) do
                if child:IsA("TextButton") then
                    local childLabel = child:FindFirstChildOfClass("TextLabel")
                    if childLabel then
                        local selected = childLabel.Text == getContentScaleOption(currentContentScale).Label
                        childLabel.TextColor3 = selected and colors.Main or colors.Text
                    end
                end
            end
        end
    )

    Library:RegisterConfig("__uilib.settings.toggle_key", "setting",
        function()
            if typeof(guiKeybind) == "EnumItem" then
                return guiKeybind.Name
            end
            return tostring(guiKeybind)
        end,
        function(val)
            setGuiKeybind(val, false)
        end
    )

    -- ==============================
    -- AddMenu (creates tab + page)
    -- ==============================
    function win:AddMenu(menuOpts)
        menuOpts = menuOpts or {}
        local menuName = menuOpts.Name or "TAB"
        local menuIcon = menuOpts.Icon or "eye"
        local numColumns = menuOpts.Columns or 3

        local menu = { Sections = {}, _columns = {}, _columnScrollers = {} }

        -- Tab button (in header scroll)
        local menuBtn = Instance.new("Frame", tbc)
        menuBtn.Name = randomStr()
        menuBtn.BackgroundColor3 = colors.TabBg
        menuBtn.BackgroundTransparency = 1
        menuBtn.BorderSizePixel = 0
        menuBtn.Size = UDim2.new(0, 80, 0.85, 0)
        menuBtn.ZIndex = 5

        Instance.new("UICorner", menuBtn).CornerRadius = UDim.new(0, 3)

        local btnStroke = Instance.new("UIStroke", menuBtn)
        btnStroke.Transparency = 1

        -- Tab label text (centered, no icon)
        local menuLabel = Instance.new("TextLabel", menuBtn)
        menuLabel.Name = randomStr()
        menuLabel.AnchorPoint = Vector2.new(0.5, 0.5)
        menuLabel.BackgroundTransparency = 1
        menuLabel.BorderSizePixel = 0
        menuLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
        menuLabel.Size = UDim2.new(1, 0, 1, 0)
        menuLabel.ZIndex = 5
        menuLabel.Font = config.Font
        menuLabel.Text = menuName
        menuLabel.TextColor3 = colors.TextDim
        menuLabel.TextSize = 13
        menuLabel.TextStrokeTransparency = 1
        menuLabel.TextTransparency = 0
        menuLabel.TextXAlignment = Enum.TextXAlignment.Center

        -- Click area (overlaid TextButton)
        local clickBtn = Instance.new("TextButton", menuBtn)
        clickBtn.BackgroundTransparency = 1
        clickBtn.Size = UDim2.new(1, 0, 1, 0)
        clickBtn.ZIndex = 6
        clickBtn.Text = ""
        clickBtn.AutoButtonColor = false
        clickBtn.Selectable = false

        -- Page content frame (inside menuFrame)
        local pageFrame = Instance.new("Frame", menuContent)
        pageFrame.Name = "Page_" .. menuName
        pageFrame.BackgroundTransparency = 1
        pageFrame.BorderSizePixel = 0
        pageFrame.Size = UDim2.new(1, 0, 1, 0)
        pageFrame.Visible = false
        pageFrame.ZIndex = 2
        pageFrame.ClipsDescendants = true

        -- ==============================
        -- CREATE COLUMNS inside page
        -- ==============================
        local columnPadding = 8
        local colWidth = (1 / numColumns)

        local function getVisibleColumnHeight()
            local viewportHeight = math.max(0, menuFrame.AbsoluteSize.Y - 4)
            return viewportHeight / math.max(currentContentScale, 0.01)
        end

        for i = 1, numColumns do
            local col = Instance.new("Frame", pageFrame)
            col.Name = "Column_" .. i
            col.BackgroundTransparency = 1
            col.BorderSizePixel = 0
            col.Position = UDim2.new(colWidth * (i - 1), 4, 0, 4)
            col.Size = UDim2.new(colWidth, -8, 1, -4)
            col.ZIndex = 3
            col.ClipsDescendants = true
            col.Active = true  -- sinks mouse input so camera doesn't zoom

            -- Inner container that moves on scroll
            local inner = Instance.new("Frame", col)
            inner.Name = "Inner"
            inner.BackgroundTransparency = 1
            inner.BorderSizePixel = 0
            inner.Position = UDim2.new(0, 0, 0, 0)
            inner.Size = UDim2.new(1, 0, 0, 5000)
            inner.ZIndex = 3

            local colLayout = Instance.new("UIListLayout", inner)
            colLayout.SortOrder = Enum.SortOrder.LayoutOrder
            colLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
            colLayout.Padding = UDim.new(0, 8)

            -- Top padding so first section title isn't clipped
            local colPad = Instance.new("UIPadding", inner)
            colPad.PaddingTop = UDim.new(0, 4)

            -- Mouse wheel scroll (frame-level to consume input)
            local BASE_SCROLL_STEP = 30
            local scrollState = createSmoothScrollState({
                Speed = 14,
                GetMaxOffset = function()
                    local contentH = colLayout.AbsoluteContentSize.Y + 8
                    local visibleH = getVisibleColumnHeight()
                    return math.max(0, contentH - visibleH)
                end,
                Apply = function(offset)
                    inner.Position = UDim2.new(0, 0, 0, -math.floor(offset + 0.5))
                end,
            })
            track(scrollState, "Destroy", nextCleanupKey("ColumnScrollState"))

            local function refreshScroll()
                scrollState:Refresh(false)
            end

            col.InputChanged:Connect(function(input)
                if input.UserInputType ~= Enum.UserInputType.MouseWheel then return end
                if searchOpen and isMouseInside(searchPanel) then
                    return
                end
                local scrollStep = BASE_SCROLL_STEP / math.max(currentContentScale, 0.01)
                scrollState:ScrollBy(-input.Position.Z * scrollStep)
            end)

            table.insert(menu._columnScrollers, refreshScroll)
            menu._columns[i] = inner -- sections parent to inner
        end

        function menu:_refreshScroll()
            for _, refreshScroll in ipairs(self._columnScrollers) do
                refreshScroll()
            end
        end

        menu._btn = menuBtn
        menu._label = menuLabel
        menu._page = pageFrame
        menu._stroke = btnStroke

        -- Select/deselect
        local function selectMenu(selected)
            if selected then
                Library:Spring(menuBtn, "Smooth", { BackgroundTransparency = 0 })
                Library:Spring(btnStroke, "Smooth", { Transparency = 0.85 })
                Library:Spring(menuLabel, "Smooth", { TextColor3 = Color3.fromRGB(255, 255, 255) })
                pageFrame.Visible = true
                menu:_refreshScroll()
            else
                Library:Spring(menuBtn, "Smooth", { BackgroundTransparency = 1 })
                Library:Spring(btnStroke, "Smooth", { Transparency = 1 })
                Library:Spring(menuLabel, "Smooth", { TextColor3 = colors.TextDim })
                pageFrame.Visible = false
            end
        end

        menu._select = selectMenu

        -- Click handler
        clickBtn.Activated:Connect(function()
            if win.ActiveMenu and win.ActiveMenu ~= menu then
                win.ActiveMenu._select(false)
            end
            win.ActiveMenu = menu
            selectMenu(true)
        end)

        -- Hover
        clickBtn.MouseEnter:Connect(function()
            if win.ActiveMenu ~= menu then
                Library:Spring(menuBtn, "Smooth", { BackgroundTransparency = 0.5 })
            end
        end)
        clickBtn.MouseLeave:Connect(function()
            if win.ActiveMenu ~= menu then
                Library:Spring(menuBtn, "Smooth", { BackgroundTransparency = 1 })
            end
        end)

        table.insert(win.Menus, menu)

        -- Auto-select first menu
        if #win.Menus == 1 then
            win.ActiveMenu = menu
            selectMenu(true)
        end

        -- ==============================
        -- AddSection (auto-height box in a column)
        -- ==============================
        function menu:AddSection(sectionOpts)
            sectionOpts = sectionOpts or {}
            local secName = sectionOpts.Name or "SECTION"
            local colNum = math.clamp(sectionOpts.Column or 1, 1, numColumns)

            local targetCol = menu._columns[colNum]
            local section = {}
            local sectionCleanup = Cleaner.new()

            -- Section container (The dark panel)
            local secFrame = Instance.new("Frame", targetCol)
            secFrame.Name = "SectionBox_" .. secName
            secFrame.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
            secFrame.BorderSizePixel = 0
            secFrame.Size = UDim2.new(1, 0, 0, 30)
            secFrame.AutomaticSize = Enum.AutomaticSize.Y
            secFrame.ClipsDescendants = false
            secFrame.ZIndex = 4

            Instance.new("UICorner", secFrame).CornerRadius = UDim.new(0, 4)

            -- Section title (physically sits overlapping the top edge)
            local secTitle = Instance.new("TextLabel", secFrame)
            secTitle.Name = "SectionTitle"
            secTitle.BackgroundTransparency = 1
            secTitle.Position = UDim2.new(0, 8, 0, -6) -- Overlaps top edge (70% inside, 30% outside)
            secTitle.Size = UDim2.new(1, -16, 0, 14)
            secTitle.Font = config.Font
            secTitle.Text = secName
            secTitle.TextColor3 = colors.Text
            secTitle.TextSize = 10
            secTitle.TextXAlignment = Enum.TextXAlignment.Left
            secTitle.ZIndex = 5

            -- Inner container for elements (so UIListLayout doesn't affect title position)
            local contentContainer = Instance.new("Frame", secFrame)
            contentContainer.Name = "Content"
            contentContainer.BackgroundTransparency = 1
            contentContainer.BorderSizePixel = 0
            contentContainer.Size = UDim2.new(1, 0, 0, 30)
            contentContainer.AutomaticSize = Enum.AutomaticSize.Y
            contentContainer.ZIndex = 4

            -- Section padding (inside the content container)
            local secPad = Instance.new("UIPadding", contentContainer)
            secPad.PaddingTop = UDim.new(0, 10) -- space below the title
            secPad.PaddingBottom = UDim.new(0, 8)
            secPad.PaddingLeft = UDim.new(0, 10)
            secPad.PaddingRight = UDim.new(0, 10)

            -- Section inner layout (elements inline)
            local secLayout = Instance.new("UIListLayout", contentContainer)
            secLayout.SortOrder = Enum.SortOrder.LayoutOrder
            secLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
            secLayout.Padding = UDim.new(0, 5)

            section.Frame = secFrame
            section.Container = contentContainer
            section._layout = secLayout
            section._title = secTitle
            section._controls = {}
            section._cleanup = sectionCleanup
            section._menu = menu
            section._menuName = menuName
            section._secName = secName
            section._win = win
            table.insert(menu.Sections, section)
            track(sectionCleanup, "Cleanup", nextCleanupKey("SectionCleanup"))

            function section:TrackConnection(conn, key)
                return self._cleanup:Add(conn, "Disconnect", key)
            end

            function section:Destroy()
                if self._destroyed then
                    return
                end

                self._destroyed = true

                for index = #self._controls, 1, -1 do
                    local control = self._controls[index]
                    if control and control.Destroy then
                        control:Destroy()
                    end
                end

                self._cleanup:Cleanup()

                for index = #win._searchItems, 1, -1 do
                    local item = win._searchItems[index]
                    if item and item.menuRef == menu and item.secName == secName then
                        table.remove(win._searchItems, index)
                    end
                end

                for index = #menu.Sections, 1, -1 do
                    if menu.Sections[index] == self then
                        table.remove(menu.Sections, index)
                        break
                    end
                end

                if secFrame.Parent then
                    secFrame:Destroy()
                end
            end

            local function sectionTrackGlobal(conn, key)
                return section:TrackConnection(conn, key or nextCleanupKey("SectionConn"))
            end

            local sectionDropdownBase = {
                bindOutsideClose = popupManager.bindOutsideClose,
                closeTransientPopups = closeTransientPopups,
                colors = colors,
                config = config,
                contentContainer = contentContainer,
                makeControl = function(control, opts)
                    return controlBase.attachControlLifecycle(section, control, opts)
                end,
                menu = menu,
                menuName = menuName,
                nextCleanupKey = nextCleanupKey,
                registerTransientPopup = registerTransientPopup,
                secName = secName,
                section = section,
                trackGlobal = sectionTrackGlobal,
                win = win,
            }

            -- ==============================
            -- AddToggle (checkbox style)
            -- ==============================
            function section:AddToggle(toggleOpts)
                toggleOpts = toggleOpts or {}
                local tName = toggleOpts.Name or "Toggle"
                local tDefault = toggleOpts.Default or false
                local tCallback = toggleOpts.Callback or function() end

                local toggle = { Value = tDefault }

                local row = controlBase.createRow(contentContainer, "Toggle_" .. tName)
                local label = controlBase.createLabel(row, tName, {
                    Font = config.FontMedium,
                    Size = UDim2.new(1, -22, 1, 0),
                    TextColor3 = colors.Text,
                    TextSize = 12,
                })
                local checkFrame, checkStroke, checkIcon = controlBase.createCheckbox(row, colors, {
                    Name = "Check",
                    ImageTransparency = tDefault and 0 or 1,
                })
                local clickBtn = controlBase.createOverlayButton(row)

                -- Lazy sub-container (only created when AddDropdown/AddSlider is called)
                local subContainer = nil
                local function ensureSubContainer()
                    if subContainer then return subContainer end
                    subContainer = Instance.new("Frame", contentContainer)
                    subContainer.Name = "ToggleSub_" .. tName
                    subContainer.BackgroundTransparency = 1
                    subContainer.BorderSizePixel = 0
                    subContainer.Size = UDim2.new(1, 0, 0, 0)
                    subContainer.AutomaticSize = Enum.AutomaticSize.Y
                    subContainer.ClipsDescendants = false
                    subContainer.ZIndex = 5
                    subContainer.Visible = toggle.Value

                    local subLayout = Instance.new("UIListLayout", subContainer)
                    subLayout.SortOrder = Enum.SortOrder.LayoutOrder
                    subLayout.Padding = UDim.new(0, 4)

                    local subPad = Instance.new("UIPadding", subContainer)
                    subPad.PaddingLeft = UDim.new(0, 12)
                    subPad.PaddingTop = UDim.new(0, 2)
                    subPad.PaddingBottom = UDim.new(0, 2)

                    if toggle.TrackInstance then
                        toggle:TrackInstance(subContainer, "SubContainer")
                    end

                    return subContainer
                end

                local function updateVisual()
                    if toggle.Value then
                        Library:Spring(checkIcon, "Smooth", { ImageTransparency = 0 })
                        Library:Spring(checkFrame, "Smooth", { BackgroundColor3 = Color3.fromRGB(45, 25, 30) })
                        Library:Spring(checkStroke, "Smooth", { Color = colors.Main, Transparency = 0.3 })
                        if subContainer then subContainer.Visible = true end
                    else
                        Library:Spring(checkIcon, "Smooth", { ImageTransparency = 1 })
                        Library:Spring(checkFrame, "Smooth", { BackgroundColor3 = Color3.fromRGB(35, 35, 35) })
                        Library:Spring(checkStroke, "Smooth", { Color = colors.Line, Transparency = 0.5 })
                        if subContainer then subContainer.Visible = false end
                    end
                end

                local function setToggleValue(nextValue, shouldMarkDirty)
                    toggle.Value = nextValue and true or false
                    updateVisual()
                    pcall(tCallback, toggle.Value)
                    if shouldMarkDirty then
                        Library:_markDirty()
                    end
                end

                toggle = controlBase.attachControlLifecycle(section, toggle, {
                    clickTargets = { clickBtn },
                    getValue = function()
                        return toggle.Value
                    end,
                    onDestroy = function()
                        subContainer = nil
                    end,
                    refresh = updateVisual,
                    root = row,
                    searchName = tName,
                    setValue = function(val)
                        setToggleValue(val == true, true)
                    end,
                    updateDisabled = function(disabled)
                        label.TextTransparency = disabled and 0.35 or 0
                        clickBtn.Active = not disabled
                    end,
                })

                toggle:TrackConnection(clickBtn.Activated:Connect(function()
                    if toggle.Disabled then
                        return
                    end

                    setToggleValue(not toggle.Value, true)
                end), "ToggleClick")

                -- Hover
                toggle:TrackConnection(clickBtn.MouseEnter:Connect(function()
                    if toggle.Disabled then
                        return
                    end
                    Library:Spring(label, "Smooth", { TextColor3 = Color3.fromRGB(255, 255, 255) })
                end), "ToggleHoverEnter")
                toggle:TrackConnection(clickBtn.MouseLeave:Connect(function()
                    Library:Spring(label, "Smooth", { TextColor3 = colors.Text })
                end), "ToggleHoverLeave")

                -- Init visual
                updateVisual()

                -- ==============================
                -- Toggle:AddColorPicker (inline)
                -- ==============================
                function toggle:AddColorPicker(cpOpts)
                    cpOpts = cpOpts or {}
                    local cpName = cpOpts.Name or "Color"
                    local cpDefault = cpOpts.Default or Color3.fromRGB(255, 255, 255)
                    local cpCallback = cpOpts.Callback or function() end
                    local cpSaveKey = cpOpts.SaveKey

                    local cpicker = { Value = cpDefault }
                    local hue, sat, val = cpDefault:ToHSV()

                    local colorBox, boxStroke = controlBase.createRightBox(row, {
                        BackgroundColor3 = cpDefault,
                        ClassName = "TextButton",
                        StrokeColor = colors.Line,
                        StrokeTransparency = 0.3,
                        RightOffset = -24,
                        Width = 16,
                        Height = 10,
                        ZIndex = 20,
                    })

                    clickBtn.Size = UDim2.new(1, -44, 1, 0)

                    local cpPanel = Instance.new("Frame", clipFrame)
                    cpPanel.Name = "CP_" .. cpName
                    cpPanel.BackgroundColor3 = Color3.fromRGB(19, 19, 19)
                    cpPanel.BorderSizePixel = 0
                    cpPanel.Size = UDim2.new(0, 175, 0, 0)
                    cpPanel.Position = UDim2.new(0, 0, 0, 0)
                    cpPanel.ZIndex = 200
                    cpPanel.ClipsDescendants = true
                    cpPanel.Visible = false
                    cpPanel.Active = true
                    Instance.new("UICorner", cpPanel).CornerRadius = UDim.new(0, 4)
                    local cpStroke = Instance.new("UIStroke", cpPanel)
                    cpStroke.Color = Color3.fromRGB(40, 40, 40)
                    cpStroke.Transparency = 1

                    local svBox = Instance.new("ImageLabel", cpPanel)
                    svBox.BackgroundColor3 = Color3.fromHSV(hue, 1, 1)
                    svBox.BorderSizePixel = 0
                    svBox.Position = UDim2.new(0, 7, 0, 7)
                    svBox.Size = UDim2.new(0, 135, 0, 135)
                    svBox.ZIndex = 201
                    svBox.Image = "http://www.roblox.com/asset/?id=112554223509763"
                    Instance.new("UICorner", svBox).CornerRadius = UDim.new(0, 2)
                    local svStroke = Instance.new("UIStroke", svBox)
                    svStroke.Color = Color3.fromRGB(29, 29, 29)

                    local crosshair = Instance.new("ImageLabel", svBox)
                    crosshair.BackgroundTransparency = 1
                    crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
                    crosshair.Position = UDim2.new(sat, 0, 1 - val, 0)
                    crosshair.Size = UDim2.new(0, 12, 0, 12)
                    crosshair.ZIndex = 205
                    crosshair.Image = "rbxassetid://4805639000"

                    local hueBar = Instance.new("Frame", cpPanel)
                    hueBar.AnchorPoint = Vector2.new(1, 0)
                    hueBar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                    hueBar.BorderSizePixel = 0
                    hueBar.Position = UDim2.new(1, -7, 0, 7)
                    hueBar.Size = UDim2.new(0, 20, 0, 135)
                    hueBar.ZIndex = 206
                    Instance.new("UICorner", hueBar).CornerRadius = UDim.new(0, 3)

                    local hueGrad = Instance.new("UIGradient", hueBar)
                    hueGrad.Color = ColorSequence.new{
                        ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 0, 0)),
                        ColorSequenceKeypoint.new(0.10, Color3.fromRGB(255, 153, 0)),
                        ColorSequenceKeypoint.new(0.20, Color3.fromRGB(203, 255, 0)),
                        ColorSequenceKeypoint.new(0.30, Color3.fromRGB(50, 255, 0)),
                        ColorSequenceKeypoint.new(0.40, Color3.fromRGB(0, 255, 102)),
                        ColorSequenceKeypoint.new(0.50, Color3.fromRGB(0, 255, 255)),
                        ColorSequenceKeypoint.new(0.60, Color3.fromRGB(0, 101, 255)),
                        ColorSequenceKeypoint.new(0.70, Color3.fromRGB(50, 0, 255)),
                        ColorSequenceKeypoint.new(0.80, Color3.fromRGB(204, 0, 255)),
                        ColorSequenceKeypoint.new(0.90, Color3.fromRGB(255, 0, 153)),
                        ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 0, 0))
                    }
                    hueGrad.Rotation = 90

                    local hueSlide = Instance.new("Frame", hueBar)
                    hueSlide.AnchorPoint = Vector2.new(0.5, 0)
                    hueSlide.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                    hueSlide.BorderSizePixel = 0
                    hueSlide.Position = UDim2.new(0.5, 0, hue, 0)
                    hueSlide.Size = UDim2.new(1, 5, 0, 2)
                    hueSlide.ZIndex = 207
                    local hsStroke = Instance.new("UIStroke", hueSlide)
                    hsStroke.Color = Color3.fromRGB(29, 29, 29)
                    hsStroke.Transparency = 0.75

                    local hexFrame = Instance.new("Frame", cpPanel)
                    hexFrame.AnchorPoint = Vector2.new(0.5, 0)
                    hexFrame.Position = UDim2.new(0.5, 0, 0, 149)
                    hexFrame.Size = UDim2.new(1, -15, 0, 18)
                    hexFrame.BackgroundColor3 = Color3.fromRGB(12, 12, 12)
                    hexFrame.BackgroundTransparency = 0.4
                    hexFrame.BorderSizePixel = 0
                    hexFrame.ZIndex = 206
                    Instance.new("UICorner", hexFrame).CornerRadius = UDim.new(0, 4)

                    local hexText = Instance.new("TextLabel", hexFrame)
                    hexText.BackgroundTransparency = 1
                    hexText.Position = UDim2.new(0, 6, 0, 0)
                    hexText.Size = UDim2.new(1, -12, 1, 0)
                    hexText.Font = config.FontMedium
                    hexText.Text = "#" .. cpDefault:ToHex()
                    hexText.TextColor3 = Color3.fromRGB(255, 255, 255)
                    hexText.TextTransparency = 0.45
                    hexText.TextSize = 11
                    hexText.TextXAlignment = Enum.TextXAlignment.Left
                    hexText.ZIndex = 209

                    local function applyColor(shouldMarkDirty)
                        local c = Color3.fromHSV(hue, sat, val)
                        cpicker.Value = c
                        colorBox.BackgroundColor3 = c
                        svBox.BackgroundColor3 = Color3.fromHSV(hue, 1, 1)
                        hexText.Text = "#" .. c:ToHex()
                        crosshair.Position = UDim2.new(sat, 0, 1 - val, 0)
                        hueSlide.Position = UDim2.new(0.5, 0, hue, 0)
                        pcall(cpCallback, c)
                        if shouldMarkDirty then Library:_markDirty() end
                    end

                    local cpOpen = false
                    local Mouse = Client:GetMouse()
                    local closePanel

                    local function setColorValue(rawValue, shouldMarkDirty)
                        local c = rawValue
                        if type(rawValue) == "table" then
                            c = Color3.fromRGB(rawValue.R or 255, rawValue.G or 255, rawValue.B or 255)
                        end
                        if typeof(c) ~= "Color3" then return end
                        hue, sat, val = c:ToHSV()
                        applyColor(shouldMarkDirty)
                    end

                    local function openPanel()
                        if toggle.Disabled then return end
                        cpOpen = true
                        closeTransientPopups(cpPanel)
                        local bp = colorBox.AbsolutePosition
                        cpPanel.Position = UDim2.fromOffset(
                            math.clamp(bp.X - 80, 10, clipFrame.AbsoluteSize.X - 185),
                            math.clamp(bp.Y + 20 - clipFrame.AbsolutePosition.Y, 10, clipFrame.AbsoluteSize.Y - 185)
                        )
                        cpPanel.Visible = true
                        cpPanel.Size = UDim2.new(0, 175, 0, 0)
                        Library:Spring(cpPanel, "Smooth", { Size = UDim2.new(0, 175, 0, 175) })
                        Library:Spring(cpStroke, "Smooth", { Transparency = 0 })
                    end

                    closePanel = function()
                        cpOpen = false
                        Library:Spring(cpPanel, "Smooth", { Size = UDim2.new(0, 175, 0, 0) })
                        Library:Spring(cpStroke, "Smooth", { Transparency = 1 })
                        task.delay(0.2, function() if not cpOpen then cpPanel.Visible = false end end)
                    end

                    cpicker = controlBase.attachControlLifecycle(section, cpicker, {
                        clickTargets = { colorBox },
                        getValue = function() return cpicker.Value end,
                        onDestroy = function() cpOpen = false end,
                        refresh = function() setColorValue(cpicker.Value, false) end,
                        root = row,
                        searchName = cpName,
                        setValue = function(value) setColorValue(value, true) end,
                        updateDisabled = function(disabled)
                            colorBox.Active = not disabled
                            if disabled and cpOpen then closePanel() end
                        end,
                    })

                    cpicker:TrackInstance(cpPanel, "ColorPickerPanel")
                    registerTransientPopup(cpPanel, closePanel)

                    cpicker:TrackConnection(colorBox.Activated:Connect(function()
                        if cpicker.Disabled then return end
                        if cpOpen then closePanel() else openPanel() end
                    end), "ColorPickerToggleMode")

                    cpicker:TrackConnection(UserInputService.InputBegan:Connect(function(input)
                        if not cpOpen then return end
                        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                            task.defer(function()
                                if not cpOpen then return end
                                local pp, ps = cpPanel.AbsolutePosition, cpPanel.AbsoluteSize
                                local mx, my = input.Position.X, input.Position.Y
                                local inPanel = mx >= pp.X and mx <= pp.X + ps.X and my >= pp.Y and my <= pp.Y + ps.Y
                                local bp, bs = colorBox.AbsolutePosition, colorBox.AbsoluteSize
                                local inBox = mx >= bp.X and mx <= bp.X + bs.X and my >= bp.Y and my <= bp.Y + bs.Y
                                if not inPanel and not inBox then closePanel() end
                            end)
                        end
                    end), nextCleanupKey("ColorPickerOutsideTgl"))

                    cpicker:TrackConnection(svBox.InputBegan:Connect(function(input)
                        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
                        if cpicker.Disabled then return end
                        local dragKey = "ColorPickerSVDragTgl"
                        local conn
                        conn = cpicker:TrackConnection(RunService.Heartbeat:Connect(function()
                            if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
                                if conn then cpicker._cleanup:Remove(dragKey); conn = nil end
                                return
                            end
                            local px, py = svBox.AbsolutePosition.X, svBox.AbsolutePosition.Y
                            local sx, sy = svBox.AbsoluteSize.X, svBox.AbsoluteSize.Y
                            sat = math.clamp((Mouse.X - px) / sx, 0, 1)
                            val = 1 - math.clamp((Mouse.Y - py) / sy, 0, 1)
                            applyColor(true)
                        end), dragKey)
                    end), "ColorPickerSVInputTgl")

                    cpicker:TrackConnection(hueBar.InputBegan:Connect(function(input)
                        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
                        if cpicker.Disabled then return end
                        local dragKey = "ColorPickerHueDragTgl"
                        local conn
                        conn = cpicker:TrackConnection(RunService.Heartbeat:Connect(function()
                            if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
                                if conn then cpicker._cleanup:Remove(dragKey); conn = nil end
                                return
                            end
                            local px, py = hueBar.AbsolutePosition.X, hueBar.AbsolutePosition.Y
                            local sx, sy = hueBar.AbsoluteSize.X, hueBar.AbsoluteSize.Y
                            hue = math.clamp((Mouse.Y - py) / sy, 0, 1)
                            applyColor(true)
                        end), dragKey)
                    end), "ColorPickerHueInputTgl")

                    Library:RegisterConfig(section._secName .. "." .. tName .. "_" .. cpName, "colorpicker",
                        function() return cpicker.Value end,
                        function(val) setColorValue(val, false) end
                    )

                    return cpicker
                end

                -- ==============================
                -- Toggle:AddDropdown (chained)
                -- ==============================
                function toggle:AddDropdown(dropOpts)
                    return dropdownControls.addToggleDropdown({
                        bindOutsideClose = popupManager.bindOutsideClose,
                        closeTransientPopups = closeTransientPopups,
                        colors = colors,
                        config = config,
                        ensureSubContainer = ensureSubContainer,
                        makeControl = function(control, opts)
                            return controlBase.attachControlLifecycle(section, control, opts)
                        end,
                        nextCleanupKey = nextCleanupKey,
                        registerTransientPopup = registerTransientPopup,
                        section = section,
                        trackGlobal = sectionTrackGlobal,
                    }, dropOpts)
                end

                -- ==============================
                -- Toggle:AddSlider (chained)
                -- ==============================
                function toggle:AddSlider(sliderOpts)
                    sliderOpts = sliderOpts or {}
                    local sName = sliderOpts.Name or "Slider"
                    local sMin = sliderOpts.Min or 0
                    local sMax = sliderOpts.Max or 100
                    local sDefault = math.clamp(sliderOpts.Default or sMin, sMin, sMax)
                    local sSuffix = sliderOpts.Suffix or "%"
                    local sCallback = sliderOpts.Callback or function() end

                    local slider = { Value = sDefault }

                    local sRow = Instance.new("Frame", ensureSubContainer())
                    sRow.Name = "SubSlider_" .. sName
                    sRow.BackgroundTransparency = 1
                    sRow.BorderSizePixel = 0
                    sRow.Size = UDim2.new(1, 0, 0, 20)
                    sRow.ZIndex = 5

                    local sLabel = Instance.new("TextLabel", sRow)
                    sLabel.BackgroundTransparency = 1
                    sLabel.Size = UDim2.new(0.4, 0, 1, 0)
                    sLabel.Font = config.FontMedium
                    sLabel.Text = sName
                    sLabel.TextColor3 = colors.TextDim
                    sLabel.TextSize = 11
                    sLabel.TextXAlignment = Enum.TextXAlignment.Left
                    sLabel.ZIndex = 5

                    local barBg = Instance.new("Frame", sRow)
                    barBg.AnchorPoint = Vector2.new(1, 0.5)
                    barBg.Position = UDim2.new(1, 0, 0.5, 0)
                    barBg.Size = UDim2.new(0.55, 0, 0, 14)
                    barBg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
                    barBg.BorderSizePixel = 0
                    barBg.ClipsDescendants = true
                    barBg.ZIndex = 5
                    Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 3)

                    local fill = Instance.new("Frame", barBg)
                    fill.BackgroundColor3 = colors.Main
                    fill.BorderSizePixel = 0
                    fill.Size = UDim2.new((sDefault - sMin) / (sMax - sMin), 0, 1, 0)
                    fill.ZIndex = 6
                    Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 3)

                    local sValLabel = Instance.new("TextLabel", barBg)
                    sValLabel.BackgroundTransparency = 1
                    sValLabel.Size = UDim2.new(1, 0, 1, 0)
                    sValLabel.Font = config.Font
                    sValLabel.Text = tostring(sDefault) .. sSuffix
                    sValLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
                    sValLabel.TextSize = 11
                    sValLabel.ZIndex = 7

                    local dragging = false
                    local function updateSlider(inputX)
                        local bx, bw = barBg.AbsolutePosition.X, barBg.AbsoluteSize.X
                        local relX = math.clamp((inputX - bx) / bw, 0, 1)
                        local val = math.floor(sMin + (sMax - sMin) * relX + 0.5)
                        slider.Value = val
                        Library:Spring(fill, "Responsive", { Size = UDim2.new(relX, 0, 1, 0) })
                        sValLabel.Text = tostring(val) .. sSuffix
                        sCallback(val)
                        Library:_markDirty()
                    end

                    local dragBtn = Instance.new("TextButton", barBg)
                    dragBtn.BackgroundTransparency = 1
                    dragBtn.Size = UDim2.new(1, 0, 1, 0)
                    dragBtn.ZIndex = 8
                    dragBtn.Text = ""
                    dragBtn.AutoButtonColor = false
                    dragBtn.Selectable = false
                    dragBtn.BorderSizePixel = 0

                    dragBtn.InputBegan:Connect(function(input)
                        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                            dragging = true
                            updateSlider(input.Position.X)
                        end
                    end)
                    dragBtn.InputEnded:Connect(function(input)
                        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                            dragging = false
                        end
                    end)
                    sectionTrackGlobal(UserInputService.InputChanged:Connect(function(input)
                        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                            updateSlider(input.Position.X)
                        end
                    end), nextCleanupKey("ToggleSliderDrag"))

                    return slider
                end

                -- Register for config save/load
                Library:RegisterConfig(secName .. "." .. tName, "toggle",
                    function() return toggle.Value end,
                    function(val)
                        setToggleValue(val == true, false)
                    end
                )

                return toggle
            end

            -- ==============================
            -- AddSlider (draggable bar)
            -- ==============================
            function section:AddSlider(sliderOpts)
                sliderOpts = sliderOpts or {}
                local sName = sliderOpts.Name or "Slider"
                local sMin = sliderOpts.Min or 0
                local sMax = sliderOpts.Max or 100
                local sDefault = math.clamp(sliderOpts.Default or sMin, sMin, sMax)
                local sSuffix = sliderOpts.Suffix or "%"
                local sCallback = sliderOpts.Callback or function() end

                local slider = { Value = sDefault }

                local row = controlBase.createRow(contentContainer, "Slider_" .. sName)
                local label = controlBase.createLabel(row, sName, {
                    Font = config.FontMedium,
                    Size = UDim2.new(0.4, 0, 1, 0),
                    TextColor3 = colors.Text,
                    TextSize = 12,
                })

                -- Slider bar background (right side)
                local barBg = Instance.new("Frame", row)
                barBg.Name = "BarBg"
                barBg.AnchorPoint = Vector2.new(1, 0.5)
                barBg.Position = UDim2.new(1, 0, 0.5, 0)
                barBg.Size = UDim2.new(0.55, 0, 0, 16)
                barBg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
                barBg.BorderSizePixel = 0
                barBg.ClipsDescendants = true
                barBg.ZIndex = 5

                Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 3)

                -- Fill bar (pink)
                local fill = Instance.new("Frame", barBg)
                fill.Name = "Fill"
                fill.BackgroundColor3 = colors.Main
                fill.BorderSizePixel = 0
                fill.Size = UDim2.new((sDefault - sMin) / (sMax - sMin), 0, 1, 0)
                fill.ZIndex = 6

                Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 3)

                -- Value text (inside bar, centered)
                local valLabel = Instance.new("TextLabel", barBg)
                valLabel.Name = "Value"
                valLabel.BackgroundTransparency = 1
                valLabel.Size = UDim2.new(1, 0, 1, 0)
                valLabel.Font = config.Font
                valLabel.Text = tostring(sDefault) .. sSuffix
                valLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
                valLabel.TextSize = 12
                valLabel.ZIndex = 7

                -- Drag interaction
                local dragging = false

                local function updateSlider(inputX)
                    local barAbsPos = barBg.AbsolutePosition.X
                    local barAbsSize = barBg.AbsoluteSize.X
                    local relX = math.clamp((inputX - barAbsPos) / barAbsSize, 0, 1)
                    local rawVal = sMin + (sMax - sMin) * relX
                    local val = math.floor(rawVal + 0.5)
                    slider.Value = val
                    Library:Spring(fill, "Responsive", { Size = UDim2.new(relX, 0, 1, 0) })
                    valLabel.Text = tostring(val) .. sSuffix
                    pcall(sCallback, val)
                    Library:_markDirty()
                end

                local function setSliderValue(val, shouldMarkDirty)
                    val = math.clamp(tonumber(val) or sMin, sMin, sMax)
                    local relX = (val - sMin) / (sMax - sMin)
                    slider.Value = math.floor(val + 0.5)
                    Library:Spring(fill, "Responsive", { Size = UDim2.new(relX, 0, 1, 0) })
                    valLabel.Text = tostring(slider.Value) .. sSuffix
                    pcall(sCallback, slider.Value)
                    if shouldMarkDirty then
                        Library:_markDirty()
                    end
                end

                local dragBtn = Instance.new("TextButton", barBg)
                dragBtn.BackgroundTransparency = 1
                dragBtn.Size = UDim2.new(1, 0, 1, 0)
                dragBtn.ZIndex = 8
                dragBtn.Text = ""
                dragBtn.AutoButtonColor = false
                dragBtn.Selectable = false

                slider = controlBase.attachControlLifecycle(section, slider, {
                    clickTargets = { dragBtn },
                    getValue = function()
                        return slider.Value
                    end,
                    refresh = function()
                        setSliderValue(slider.Value, false)
                    end,
                    root = row,
                    searchName = sName,
                    setValue = function(val)
                        setSliderValue(val, true)
                    end,
                    updateDisabled = function(disabled)
                        label.TextTransparency = disabled and 0.35 or 0
                        dragBtn.Active = not disabled
                    end,
                })

                slider:TrackConnection(dragBtn.InputBegan:Connect(function(input)
                    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                        dragging = true
                        updateSlider(input.Position.X)
                    end
                end), "SliderInputBegan")

                slider:TrackConnection(dragBtn.InputEnded:Connect(function(input)
                    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                        dragging = false
                    end
                end), "SliderInputEnded")

                slider:TrackConnection(UserInputService.InputChanged:Connect(function(input)
                    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                        if slider.Disabled then
                            return
                        end
                        updateSlider(input.Position.X)
                    end
                end), nextCleanupKey("SliderDrag"))

                -- Register for config save/load
                Library:RegisterConfig(secName .. "." .. sName, "slider",
                    function() return slider.Value end,
                    function(val)
                        setSliderValue(val, false)
                    end
                )

                return slider
            end

            -- ==============================
            -- AddMultiDropdown (multi-select)
            -- ==============================
            function section:AddMultiDropdown(dropOpts)
                return dropdownControls.addMultiDropdown(sectionDropdownBase, dropOpts)
            end

            -- ==============================
            -- AddSliderToggle (slider + checkbox)
            -- ==============================
            function section:AddSliderToggle(opts)
                opts = opts or {}
                local sName = opts.Name or "Slider"
                local sMin = opts.Min or 0
                local sMax = opts.Max or 100
                local sDefault = math.clamp(opts.Default or sMin, sMin, sMax)
                local sSuffix = opts.Suffix or "%"
                local sEnabled = opts.Enabled ~= false
                local sCallback = opts.Callback or function() end
                local sToggleCallback = opts.OnToggle or function() end

                local st = { Value = sDefault, Enabled = sEnabled }

                local row = controlBase.createRow(contentContainer, "SliderToggle_" .. sName)
                local label = controlBase.createLabel(row, sName, {
                    Font = config.FontMedium,
                    Size = UDim2.new(0.3, 0, 1, 0),
                    TextColor3 = colors.Text,
                    TextSize = 12,
                })
                local chkFrame, chkStroke, checkIcon = controlBase.createCheckbox(row, colors, {
                    ImageTransparency = sEnabled and 0 or 1,
                })
                local chkBtn = controlBase.createOverlayButton(chkFrame, {
                    ZIndex = 7,
                })

                -- Slider bar (between label and checkbox)
                local barBg = Instance.new("Frame", row)
                barBg.AnchorPoint = Vector2.new(1, 0.5)
                barBg.Position = UDim2.new(1, -20, 0.5, 0)
                barBg.Size = UDim2.new(0.45, 0, 0, 16)
                barBg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
                barBg.BorderSizePixel = 0
                barBg.ClipsDescendants = true
                barBg.ZIndex = 5
                Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 3)

                local fill = Instance.new("Frame", barBg)
                fill.BackgroundColor3 = colors.Main
                fill.BorderSizePixel = 0
                fill.Size = UDim2.new((sDefault - sMin) / (sMax - sMin), 0, 1, 0)
                fill.ZIndex = 6
                Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 3)

                local valLabel = Instance.new("TextLabel", barBg)
                valLabel.BackgroundTransparency = 1
                valLabel.Size = UDim2.new(1, 0, 1, 0)
                valLabel.Font = config.Font
                valLabel.Text = tostring(sDefault) .. sSuffix
                valLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
                valLabel.TextSize = 12
                valLabel.ZIndex = 7

                local dragging = false
                local function applyEnabled(enabled, shouldMarkDirty)
                    st.Enabled = enabled == true
                    if st.Enabled then
                        Library:Spring(checkIcon, "Smooth", { ImageTransparency = 0 })
                        Library:Spring(chkFrame, "Smooth", { BackgroundColor3 = Color3.fromRGB(45, 25, 30) })
                        Library:Spring(chkStroke, "Smooth", { Color = colors.Main, Transparency = 0.3 })
                    else
                        Library:Spring(checkIcon, "Smooth", { ImageTransparency = 1 })
                        Library:Spring(chkFrame, "Smooth", { BackgroundColor3 = Color3.fromRGB(35, 35, 35) })
                        Library:Spring(chkStroke, "Smooth", { Color = colors.Line, Transparency = 0.5 })
                    end

                    pcall(sToggleCallback, st.Enabled)
                    if shouldMarkDirty then
                        Library:_markDirty()
                    end
                end

                local function setSliderValue(val, shouldMarkDirty)
                    val = math.clamp(tonumber(val) or sMin, sMin, sMax)
                    st.Value = math.floor(val + 0.5)
                    local relX = (st.Value - sMin) / (sMax - sMin)
                    Library:Spring(fill, "Responsive", { Size = UDim2.new(relX, 0, 1, 0) })
                    valLabel.Text = tostring(st.Value) .. sSuffix
                    pcall(sCallback, st.Value)
                    if shouldMarkDirty then
                        Library:_markDirty()
                    end
                end

                local function updateSlider(inputX)
                    local bx, bw = barBg.AbsolutePosition.X, barBg.AbsoluteSize.X
                    local relX = math.clamp((inputX - bx) / bw, 0, 1)
                    local val = sMin + (sMax - sMin) * relX
                    setSliderValue(val, true)
                end

                local dragBtn = Instance.new("TextButton", barBg)
                dragBtn.BackgroundTransparency = 1
                dragBtn.Size = UDim2.new(1, 0, 1, 0)
                dragBtn.ZIndex = 8
                dragBtn.Text = ""
                dragBtn.AutoButtonColor = false
                dragBtn.Selectable = false
                dragBtn.BorderSizePixel = 0

                st = controlBase.attachControlLifecycle(section, st, {
                    clickTargets = { chkBtn, dragBtn },
                    getValue = function()
                        return { value = st.Value, enabled = st.Enabled }
                    end,
                    refresh = function()
                        setSliderValue(st.Value, false)
                        applyEnabled(st.Enabled, false)
                    end,
                    root = row,
                    searchName = sName,
                    setValue = function(val)
                        if type(val) ~= "table" then
                            return
                        end

                        if val.value ~= nil then
                            setSliderValue(val.value, true)
                        end
                        if val.enabled ~= nil then
                            applyEnabled(val.enabled, true)
                        end
                    end,
                    updateDisabled = function(disabled)
                        label.TextTransparency = disabled and 0.35 or 0
                        chkBtn.Active = not disabled
                        dragBtn.Active = not disabled
                        if disabled then
                            dragging = false
                        end
                    end,
                })

                st:TrackConnection(chkBtn.Activated:Connect(function()
                    if st.Disabled then
                        return
                    end

                    applyEnabled(not st.Enabled, true)
                end), "SliderToggleToggle")

                st:TrackConnection(dragBtn.InputBegan:Connect(function(input)
                    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                        if st.Disabled then
                            return
                        end
                        dragging = true
                        updateSlider(input.Position.X)
                    end
                end), "SliderToggleInputBegan")
                st:TrackConnection(dragBtn.InputEnded:Connect(function(input)
                    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                        dragging = false
                    end
                end), "SliderToggleInputEnded")
                st:TrackConnection(UserInputService.InputChanged:Connect(function(input)
                    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                        if st.Disabled then
                            return
                        end
                        updateSlider(input.Position.X)
                    end
                end), nextCleanupKey("SliderToggleDrag"))

                -- Register for config save/load
                Library:RegisterConfig(secName .. "." .. sName, "slidertoggle",
                    function() return { value = st.Value, enabled = st.Enabled } end,
                    function(val)
                        if type(val) ~= "table" then return end
                        if val.value ~= nil then
                            setSliderValue(val.value, false)
                        end
                        if val.enabled ~= nil then
                            applyEnabled(val.enabled, false)
                        end
                    end
                )

                return st
            end

            -- ==============================
            -- AddDropdownToggle (dropdown + checkbox)
            -- ==============================
            function section:AddDropdownToggle(opts)
                return dropdownControls.addDropdownToggle(sectionDropdownBase, opts)
            end

            -- ==============================
            -- AddDropdown (standalone single-select, no toggle)
            -- ==============================
            function section:AddDropdown(dropOpts)
                return dropdownControls.addStandaloneDropdown(sectionDropdownBase, dropOpts)
            end

            -- ==============================
            -- AddButton (clickable action button with icon)
            -- ==============================
            function section:AddButton(btnOpts)
                btnOpts = btnOpts or {}
                local bName = btnOpts.Name or "Button"
                local bCallback = btnOpts.Callback or function() end

                local buttonControl = {}
                local row = controlBase.createRow(contentContainer, "Button_" .. bName)
                local label = controlBase.createLabel(row, bName, {
                    Font = config.FontMedium,
                    Size = UDim2.new(1, -24, 1, 0),
                    TextColor3 = colors.Text,
                    TextSize = 12,
                })

                -- Button box (right side)
                local btnBox, boxStroke = controlBase.createRightBox(row, {
                    ClassName = "TextButton",
                    StrokeColor = colors.Line,
                    StrokeTransparency = 0.5,
                })

                -- Icon inside box
                local icon = Instance.new("ImageLabel", btnBox)
                icon.BackgroundTransparency = 1
                icon.AnchorPoint = Vector2.new(0.5, 0.5)
                icon.Position = UDim2.new(0.5, 0, 0.5, 0)
                icon.Size = UDim2.new(0, 12, 0, 12)
                icon.Image = "rbxassetid://124717201027551"
                icon.ImageColor3 = colors.TextDim
                icon.ZIndex = 6

                local function flashButton()
                    Library:Spring(btnBox, "Smooth", { BackgroundColor3 = colors.Main })
                    task.delay(0.2, function()
                        if btnBox.Parent then
                            Library:Spring(btnBox, "Smooth", { BackgroundColor3 = Color3.fromRGB(35, 35, 35) })
                        end
                    end)
                end

                buttonControl = controlBase.attachControlLifecycle(section, buttonControl, {
                    clickTargets = { btnBox },
                    root = row,
                    searchName = bName,
                    updateDisabled = function(disabled)
                        label.TextTransparency = disabled and 0.35 or 0
                        btnBox.Active = not disabled
                        icon.ImageTransparency = disabled and 0.4 or 0
                    end,
                })

                -- Hover
                buttonControl:TrackConnection(btnBox.MouseEnter:Connect(function()
                    if buttonControl.Disabled then
                        return
                    end
                    Library:Spring(boxStroke, "Smooth", { Color = colors.Main, Transparency = 0.3 })
                    Library:Spring(icon, "Smooth", { ImageColor3 = colors.Main })
                end), "ButtonHoverEnter")
                buttonControl:TrackConnection(btnBox.MouseLeave:Connect(function()
                    Library:Spring(boxStroke, "Smooth", { Color = colors.Line, Transparency = 0.5 })
                    Library:Spring(icon, "Smooth", { ImageColor3 = colors.TextDim })
                end), "ButtonHoverLeave")

                -- Click
                buttonControl:TrackConnection(btnBox.Activated:Connect(function()
                    if buttonControl.Disabled then
                        return
                    end

                    flashButton()
                    pcall(bCallback)
                end), "ButtonActivated")

                function buttonControl:Fire()
                    flashButton()
                    return bCallback()
                end

                return buttonControl
            end

            -- ==============================
            -- AddColorPicker (HSV color palette popup)
            -- Adapted from 4lpaca-pin/Fatality
            -- ==============================
            function section:AddColorPicker(cpOpts)
                cpOpts = cpOpts or {}
                local cpName = cpOpts.Name or "Color"
                local cpDefault = cpOpts.Default or Color3.fromRGB(255, 255, 255)
                local cpCallback = cpOpts.Callback or function() end
                local cpSaveKey = cpOpts.SaveKey

                local cpicker = { Value = cpDefault }

                -- Current HSV state
                local hue, sat, val = cpDefault:ToHSV()

                local row = controlBase.createRow(contentContainer, "ColorPicker_" .. cpName)
                local label = controlBase.createLabel(row, cpName, {
                    Font = config.FontMedium,
                    Size = UDim2.new(1, -24, 1, 0),
                    TextColor3 = colors.Text,
                    TextSize = 12,
                })

                -- Color preview box (clickable)
                local colorBox, boxStroke = controlBase.createRightBox(row, {
                    BackgroundColor3 = cpDefault,
                    ClassName = "TextButton",
                    StrokeColor = colors.Line,
                    StrokeTransparency = 0.3,
                })

                -- ====== POPUP PANEL (parented to window) ======
                local cpPanel = Instance.new("Frame", clipFrame)
                cpPanel.Name = "CP_" .. cpName
                cpPanel.BackgroundColor3 = Color3.fromRGB(19, 19, 19)
                cpPanel.BorderSizePixel = 0
                cpPanel.Size = UDim2.new(0, 175, 0, 0) -- starts collapsed
                cpPanel.Position = UDim2.new(0, 0, 0, 0)
                cpPanel.ZIndex = 200
                cpPanel.ClipsDescendants = true
                cpPanel.Visible = false
                cpPanel.Active = true
                Instance.new("UICorner", cpPanel).CornerRadius = UDim.new(0, 4)
                local cpStroke = Instance.new("UIStroke", cpPanel)
                cpStroke.Color = Color3.fromRGB(40, 40, 40)
                cpStroke.Transparency = 1

                -- SV Box (saturation + value picker)
                local svBox = Instance.new("ImageLabel", cpPanel)
                svBox.BackgroundColor3 = Color3.fromHSV(hue, 1, 1)
                svBox.BorderSizePixel = 0
                svBox.Position = UDim2.new(0, 7, 0, 7)
                svBox.Size = UDim2.new(0, 135, 0, 135)
                svBox.ZIndex = 201
                svBox.Image = "http://www.roblox.com/asset/?id=112554223509763"
                Instance.new("UICorner", svBox).CornerRadius = UDim.new(0, 2)
                local svStroke = Instance.new("UIStroke", svBox)
                svStroke.Color = Color3.fromRGB(29, 29, 29)

                -- Crosshair on SV box
                local crosshair = Instance.new("ImageLabel", svBox)
                crosshair.BackgroundTransparency = 1
                crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
                crosshair.Position = UDim2.new(sat, 0, 1 - val, 0)
                crosshair.Size = UDim2.new(0, 12, 0, 12)
                crosshair.ZIndex = 205
                crosshair.Image = "rbxassetid://4805639000"

                -- Hue rainbow bar (vertical)
                local hueBar = Instance.new("Frame", cpPanel)
                hueBar.AnchorPoint = Vector2.new(1, 0)
                hueBar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                hueBar.BorderSizePixel = 0
                hueBar.Position = UDim2.new(1, -7, 0, 7)
                hueBar.Size = UDim2.new(0, 20, 0, 135)
                hueBar.ZIndex = 206
                Instance.new("UICorner", hueBar).CornerRadius = UDim.new(0, 3)

                local hueGrad = Instance.new("UIGradient", hueBar)
                hueGrad.Color = ColorSequence.new{
                    ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 0, 0)),
                    ColorSequenceKeypoint.new(0.10, Color3.fromRGB(255, 153, 0)),
                    ColorSequenceKeypoint.new(0.20, Color3.fromRGB(203, 255, 0)),
                    ColorSequenceKeypoint.new(0.30, Color3.fromRGB(50, 255, 0)),
                    ColorSequenceKeypoint.new(0.40, Color3.fromRGB(0, 255, 102)),
                    ColorSequenceKeypoint.new(0.50, Color3.fromRGB(0, 255, 255)),
                    ColorSequenceKeypoint.new(0.60, Color3.fromRGB(0, 101, 255)),
                    ColorSequenceKeypoint.new(0.70, Color3.fromRGB(50, 0, 255)),
                    ColorSequenceKeypoint.new(0.80, Color3.fromRGB(204, 0, 255)),
                    ColorSequenceKeypoint.new(0.90, Color3.fromRGB(255, 0, 153)),
                    ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 0, 0))
                }
                hueGrad.Rotation = 90

                -- Hue slider indicator
                local hueSlide = Instance.new("Frame", hueBar)
                hueSlide.AnchorPoint = Vector2.new(0.5, 0)
                hueSlide.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                hueSlide.BorderSizePixel = 0
                hueSlide.Position = UDim2.new(0.5, 0, hue, 0)
                hueSlide.Size = UDim2.new(1, 5, 0, 2)
                hueSlide.ZIndex = 207
                local hsStroke = Instance.new("UIStroke", hueSlide)
                hsStroke.Color = Color3.fromRGB(29, 29, 29)
                hsStroke.Transparency = 0.75

                -- Hex code display
                local hexFrame = Instance.new("Frame", cpPanel)
                hexFrame.AnchorPoint = Vector2.new(0.5, 0)
                hexFrame.Position = UDim2.new(0.5, 0, 0, 149)
                hexFrame.Size = UDim2.new(1, -15, 0, 18)
                hexFrame.BackgroundColor3 = Color3.fromRGB(12, 12, 12)
                hexFrame.BackgroundTransparency = 0.4
                hexFrame.BorderSizePixel = 0
                hexFrame.ZIndex = 206
                Instance.new("UICorner", hexFrame).CornerRadius = UDim.new(0, 4)

                local hexText = Instance.new("TextLabel", hexFrame)
                hexText.BackgroundTransparency = 1
                hexText.Position = UDim2.new(0, 6, 0, 0)
                hexText.Size = UDim2.new(1, -12, 1, 0)
                hexText.Font = config.FontMedium
                hexText.Text = "#" .. cpDefault:ToHex()
                hexText.TextColor3 = Color3.fromRGB(255, 255, 255)
                hexText.TextTransparency = 0.45
                hexText.TextSize = 11
                hexText.TextXAlignment = Enum.TextXAlignment.Left
                hexText.ZIndex = 209

                local function applyColor(shouldMarkDirty)
                    local c = Color3.fromHSV(hue, sat, val)
                    cpicker.Value = c
                    colorBox.BackgroundColor3 = c
                    svBox.BackgroundColor3 = Color3.fromHSV(hue, 1, 1)
                    hexText.Text = "#" .. c:ToHex()
                    crosshair.Position = UDim2.new(sat, 0, 1 - val, 0)
                    hueSlide.Position = UDim2.new(0.5, 0, hue, 0)
                    pcall(cpCallback, c)
                    if shouldMarkDirty then
                        Library:_markDirty()
                    end
                end

                -- Panel open/close
                local cpOpen = false
                local Mouse = Client:GetMouse()
                local closePanel

                local function setColorValue(rawValue, shouldMarkDirty)
                    local c = rawValue
                    if type(rawValue) == "table" then
                        c = Color3.fromRGB(rawValue.R or 255, rawValue.G or 255, rawValue.B or 255)
                    end
                    if typeof(c) ~= "Color3" then
                        return
                    end

                    hue, sat, val = c:ToHSV()
                    applyColor(shouldMarkDirty)
                end

                local function openPanel()
                    if cpicker.Disabled then
                        return
                    end

                    cpOpen = true
                    closeTransientPopups(cpPanel)
                    local bp = colorBox.AbsolutePosition
                    cpPanel.Position = UDim2.fromOffset(
                        math.clamp(bp.X - 80, 10, clipFrame.AbsoluteSize.X - 185),
                        math.clamp(bp.Y + 20 - clipFrame.AbsolutePosition.Y, 10, clipFrame.AbsoluteSize.Y - 185)
                    )
                    cpPanel.Visible = true
                    cpPanel.Size = UDim2.new(0, 175, 0, 0)
                    Library:Spring(cpPanel, "Smooth", { Size = UDim2.new(0, 175, 0, 175) })
                    Library:Spring(cpStroke, "Smooth", { Transparency = 0 })
                end

                closePanel = function()
                    cpOpen = false
                    Library:Spring(cpPanel, "Smooth", { Size = UDim2.new(0, 175, 0, 0) })
                    Library:Spring(cpStroke, "Smooth", { Transparency = 1 })
                    task.delay(0.2, function()
                        if not cpOpen then cpPanel.Visible = false end
                    end)
                end

                cpicker = controlBase.attachControlLifecycle(section, cpicker, {
                    clickTargets = { colorBox },
                    getValue = function()
                        return cpicker.Value
                    end,
                    onDestroy = function()
                        cpOpen = false
                    end,
                    refresh = function()
                        setColorValue(cpicker.Value, false)
                    end,
                    root = row,
                    searchName = cpName,
                    setValue = function(value)
                        setColorValue(value, true)
                    end,
                    updateDisabled = function(disabled)
                        label.TextTransparency = disabled and 0.35 or 0
                        colorBox.Active = not disabled
                        if disabled and cpOpen then
                            closePanel()
                        end
                    end,
                })
                cpicker:TrackInstance(cpPanel, "ColorPickerPanel")

                registerTransientPopup(cpPanel, closePanel)

                cpicker:TrackConnection(colorBox.Activated:Connect(function()
                    if cpicker.Disabled then
                        return
                    end

                    if cpOpen then closePanel() else openPanel() end
                end), "ColorPickerToggle")

                -- Click outside to close
                cpicker:TrackConnection(UserInputService.InputBegan:Connect(function(input)
                    if not cpOpen then return end
                    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                        task.defer(function()
                            if not cpOpen then return end
                            local pp, ps = cpPanel.AbsolutePosition, cpPanel.AbsoluteSize
                            local mx, my = input.Position.X, input.Position.Y
                            local inPanel = mx >= pp.X and mx <= pp.X + ps.X and my >= pp.Y and my <= pp.Y + ps.Y
                            local bp, bs = colorBox.AbsolutePosition, colorBox.AbsoluteSize
                            local inBox = mx >= bp.X and mx <= bp.X + bs.X and my >= bp.Y and my <= bp.Y + bs.Y
                            if not inPanel and not inBox then closePanel() end
                        end)
                    end
                end), nextCleanupKey("ColorPickerOutside"))

                -- SV box drag
                cpicker:TrackConnection(svBox.InputBegan:Connect(function(input)
                    if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
                    if cpicker.Disabled then
                        return
                    end

                    local dragKey = "ColorPickerSVDrag"
                    local conn
                    conn = cpicker:TrackConnection(RunService.Heartbeat:Connect(function()
                        if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
                            if conn then
                                cpicker._cleanup:Remove(dragKey)
                                conn = nil
                            end
                            return
                        end
                        local px, py = svBox.AbsolutePosition.X, svBox.AbsolutePosition.Y
                        local sx, sy = svBox.AbsoluteSize.X, svBox.AbsoluteSize.Y
                        sat = math.clamp((Mouse.X - px) / sx, 0, 1)
                        val = 1 - math.clamp((Mouse.Y - py) / sy, 0, 1)
                        applyColor(true)
                    end), dragKey)
                end), "ColorPickerSVInput")

                -- Hue bar drag
                cpicker:TrackConnection(hueBar.InputBegan:Connect(function(input)
                    if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
                    if cpicker.Disabled then
                        return
                    end

                    local dragKey = "ColorPickerHueDrag"
                    local conn
                    conn = cpicker:TrackConnection(RunService.Heartbeat:Connect(function()
                        if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
                            if conn then
                                cpicker._cleanup:Remove(dragKey)
                                conn = nil
                            end
                            return
                        end
                        local py = hueBar.AbsolutePosition.Y
                        local sy = hueBar.AbsoluteSize.Y
                        hue = math.clamp((Mouse.Y - py) / sy, 0, 1)
                        applyColor(true)
                    end), dragKey)
                end), "ColorPickerHueInput")

                -- Config save/load
                if cpSaveKey then
                    Library:RegisterConfig(cpSaveKey, "colorpicker",
                        function()
                            local c = cpicker.Value
                            return { R = math.floor(c.R * 255), G = math.floor(c.G * 255), B = math.floor(c.B * 255) }
                        end,
                        function(v)
                            setColorValue(v, false)
                        end
                    )
                end

                return cpicker
            end

            -- ==============================
            -- AddHitboxPreview (interactive body part selector)
            -- ==============================
            function section:AddHitboxPreview(opts)
                opts = opts or {}
                local hName = opts.Name or "Hitbox Preview"
                local hCallback = opts.Callback or function() end
                local hLinked = opts.LinkedDropdown or nil -- ref to a multi-dropdown object
                local defaultParts = {
                    { Body = "Head", Label = "Head", Values = {"Head"} },
                    { Body = "Chest", Label = "Chest", Values = {"Chest"} },
                    { Body = "Stomach", Label = "Stomach", Values = {"Stomach"} },
                    { Body = "Left Arm", Label = "Left Arm", Values = {"Left Arm"} },
                    { Body = "Right Arm", Label = "Right Arm", Values = {"Right Arm"} },
                    { Body = "Left Leg", Label = "Left Leg", Values = {"Left Leg"} },
                    { Body = "Right Leg", Label = "Right Leg", Values = {"Right Leg"} },
                }
                local rawParts = opts.Parts or defaultParts
                local partConfigs = {}
                local partConfigByBody = {}
                local visibleBodies = {}

                local function normalizeValues(entry, fallback)
                    if type(entry) == "table" then
                        local values = {}
                        for _, value in ipairs(entry) do
                            table.insert(values, value)
                        end
                        if #values > 0 then
                            return values
                        end
                    elseif entry ~= nil then
                        return { entry }
                    end

                    return fallback and { fallback } or {}
                end

                for _, rawPart in ipairs(rawParts) do
                    local body
                    local label
                    local values

                    if type(rawPart) == "string" then
                        body = rawPart
                        label = rawPart
                        values = { rawPart }
                    elseif type(rawPart) == "table" then
                        body = rawPart.Body or rawPart.BodyPart or rawPart.Frame or rawPart.Name or rawPart.Label or rawPart.Display
                        label = rawPart.Label or rawPart.Display or rawPart.Name or body
                        values = normalizeValues(
                            rawPart.Values or rawPart.Value or rawPart.LinkedValues or rawPart.LinkedValue or rawPart.Keys or rawPart.Parts,
                            body
                        )
                    end

                    if body then
                        local configEntry = {
                            Body = body,
                            Label = label or body,
                            Values = values,
                        }
                        table.insert(partConfigs, configEntry)
                        partConfigByBody[body] = configEntry
                        visibleBodies[body] = true
                    end
                end

                local function buildSelectedState(raw)
                    local selected = {}

                    if type(raw) ~= "table" then
                        return selected
                    end

                    local sequenceCount = #raw
                    if sequenceCount > 0 then
                        for _, value in ipairs(raw) do
                            local matched = false
                            if type(value) == "string" then
                                for _, configEntry in ipairs(partConfigs) do
                                    if configEntry.Body == value or configEntry.Label == value then
                                        matched = true
                                        for _, actualValue in ipairs(configEntry.Values) do
                                            selected[actualValue] = true
                                        end
                                        break
                                    end
                                end
                            end

                            if not matched and value ~= nil then
                                selected[value] = true
                            end
                        end
                    end

                    for key, enabled in pairs(raw) do
                        if not (type(key) == "number" and key >= 1 and key <= sequenceCount) and enabled then
                            local matched = false
                            if type(key) == "string" then
                                for _, configEntry in ipairs(partConfigs) do
                                    if configEntry.Body == key or configEntry.Label == key then
                                        matched = true
                                        for _, actualValue in ipairs(configEntry.Values) do
                                            selected[actualValue] = true
                                        end
                                        break
                                    end
                                end
                            end

                            if not matched then
                                selected[key] = true
                            end
                        end
                    end

                    return selected
                end

                local hitbox

                local function cloneSelectedState()
                    local copy = {}
                    for key, value in pairs(hitbox.Selected) do
                        if value then
                            copy[key] = true
                        end
                    end
                    return copy
                end

                local function applySelectedState(raw)
                    local nextSelected = buildSelectedState(raw)
                    for key in pairs(hitbox.Selected) do
                        hitbox.Selected[key] = nil
                    end
                    for key, value in pairs(nextSelected) do
                        hitbox.Selected[key] = value
                    end
                end

                hitbox = {
                    Selected = buildSelectedState(opts.Default),
                    Visible = false
                }

                local row = controlBase.createRow(contentContainer, "HitboxPreview_" .. hName)
                local label = controlBase.createLabel(row, hName, {
                    Font = config.FontMedium,
                    Size = UDim2.new(1, -20, 1, 0),
                    TextColor3 = colors.Text,
                    TextSize = 12,
                })

                -- Checkbox (right side)
                local chkFrame, chkStroke, cl1 = controlBase.createCheckbox(row, colors, {
                    IconWidth = 10,
                    IconHeight = 10,
                })
                local cl2 = cl1 -- alias for existing references

                local clickBtn = controlBase.createOverlayButton(row)

                -- ==============================
                -- FLOATING HITBOX PANEL (child of main, outside clipFrame)
                -- ==============================
                local panelW = 150
                local hPanel = Instance.new("Frame", main)
                hPanel.Name = "HitboxPanel"
                hPanel.AnchorPoint = Vector2.new(0, 0.5)
                hPanel.Position = UDim2.new(1, 4, 0.5, 0)
                hPanel.Size = UDim2.new(0, panelW, 1, -60)
                hPanel.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
                hPanel.BorderSizePixel = 0
                hPanel.Visible = false
                hPanel.ZIndex = 90
                Instance.new("UICorner", hPanel).CornerRadius = UDim.new(0, 5)
                local hpStroke = Instance.new("UIStroke", hPanel)
                hpStroke.Color = colors.Line
                hpStroke.Transparency = 0.3

                -- ==============================
                -- MANUALLY BUILT CHARACTER SILHOUETTE
                -- ==============================
                local bodyColor = Color3.fromRGB(45, 45, 45)
                local outlineColor = Color3.fromRGB(55, 55, 55)

                -- Character container (centered in panel)
                local charFrame = Instance.new("Frame", hPanel)
                charFrame.AnchorPoint = Vector2.new(0.5, 0.5)
                charFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
                charFrame.Size = UDim2.new(0, 90, 0, 210)
                charFrame.BackgroundTransparency = 1
                charFrame.ZIndex = 91

                -- Helper: create a body part frame (TextButton for clickability)
                local function makeBodyPart(parent, posX, posY, sizeX, sizeY, cornerRadius)
                    local f = Instance.new("TextButton", parent)
                    f.AnchorPoint = Vector2.new(0.5, 0)
                    f.Position = UDim2.fromOffset(posX, posY)
                    f.Size = UDim2.fromOffset(sizeX, sizeY)
                    f.BackgroundColor3 = bodyColor
                    f.BorderSizePixel = 0
                    f.ZIndex = 91
                    f.Text = ""
                    f.AutoButtonColor = false
                    f.Selectable = false
                    Instance.new("UICorner", f).CornerRadius = UDim.new(0, cornerRadius or 3)
                    local s = Instance.new("UIStroke", f)
                    s.Color = outlineColor
                    s.Transparency = 0.4
                    return f
                end

                -- Head (circle)
                local headPart = makeBodyPart(charFrame, 45, 0, 28, 28, 14)

                -- Neck
                makeBodyPart(charFrame, 45, 28, 10, 8, 2)

                -- Torso (chest area)
                local torsoPart = makeBodyPart(charFrame, 45, 36, 44, 40, 4)

                -- Stomach
                local stomachPart = makeBodyPart(charFrame, 45, 76, 44, 32, 4)

                -- Left Arm
                local lArmPart = makeBodyPart(charFrame, 14, 36, 18, 72, 4)

                -- Right Arm
                local rArmPart = makeBodyPart(charFrame, 76, 36, 18, 72, 4)

                -- Left Leg
                local lLegPart = makeBodyPart(charFrame, 33, 108, 20, 70, 4)

                -- Right Leg
                local rLegPart = makeBodyPart(charFrame, 57, 108, 20, 70, 4)

                -- Shoes
                makeBodyPart(charFrame, 33, 175, 22, 14, 4)
                makeBodyPart(charFrame, 57, 175, 22, 14, 4)

                -- ==============================
                -- BODY PART BUTTONS (+)
                -- ==============================
                -- Format: { name, body frame ref, offsetX, offsetY }
                local partDefs = {
                    { "Head",      headPart,    0, 0 },
                    { "Chest",     torsoPart,   0, 0 },
                    { "Stomach",   stomachPart, 0, 0 },
                    { "Left Arm",  lArmPart,    0, 6 },
                    { "Right Arm", rArmPart,    0, 6 },
                    { "Left Leg",  lLegPart,    0, 10 },
                    { "Right Leg", rLegPart,    0, 10 },
                }

                local partButtons = {}

                local function isPartSelected(partName)
                    local configEntry = partConfigByBody[partName]
                    if not configEntry then
                        return hitbox.Selected[partName] or false
                    end

                    for _, actualValue in ipairs(configEntry.Values) do
                        if hitbox.Selected[actualValue] then
                            return true
                        end
                    end

                    return false
                end

                local updatePartVisual
                local function refreshPartVisuals()
                    for partName in pairs(partButtons) do
                        updatePartVisual(partName, isPartSelected(partName))
                    end
                end

                updatePartVisual = function(partName, selected)
                    local pbt = partButtons[partName]
                    if not pbt then return end
                    if selected then
                        Library:Spring(pbt.bodyFrame, "Smooth", { BackgroundColor3 = Color3.fromRGB(80, 30, 40) })
                        Library:Spring(pbt.btn, "Smooth", { BackgroundColor3 = colors.Main, BackgroundTransparency = 0 })
                        Library:Spring(pbt.label, "Smooth", { TextColor3 = Color3.fromRGB(255, 255, 255) })
                    else
                        Library:Spring(pbt.bodyFrame, "Smooth", { BackgroundColor3 = bodyColor })
                        Library:Spring(pbt.btn, "Smooth", { BackgroundColor3 = Color3.fromRGB(60, 60, 60), BackgroundTransparency = 0.3 })
                        Library:Spring(pbt.label, "Smooth", { TextColor3 = colors.TextDim })
                    end
                end

                local function syncToLinked()
                    if not hLinked then return end
                    if hLinked.Values then
                        for k in pairs(hLinked.Values) do hLinked.Values[k] = nil end
                        for k, v in pairs(hitbox.Selected) do
                            if v then hLinked.Values[k] = true end
                        end
                        if hLinked.Refresh then hLinked:Refresh() end
                    end
                end

                local function syncFromLinked()
                    if hLinked and hLinked.Values then
                        applySelectedState(hLinked.Values)
                        refreshPartVisuals()
                    end
                end

                local function onPartToggle(partName)
                    if hitbox.Disabled then
                        return
                    end

                    -- Sync FROM linked dropdown first to get current state
                    if hLinked and hLinked.Values then
                        applySelectedState(hLinked.Values)
                    end

                    local configEntry = partConfigByBody[partName]
                    local nextState = not isPartSelected(partName)
                    if configEntry then
                        for _, actualValue in ipairs(configEntry.Values) do
                            hitbox.Selected[actualValue] = nextState or nil
                        end
                    else
                        hitbox.Selected[partName] = nextState or nil
                    end

                    refreshPartVisuals()
                    syncToLinked()
                    hCallback(cloneSelectedState())
                    Library:_markDirty()
                end

                local linkedSyncHandler
                for _, pDef in ipairs(partDefs) do
                    local pName = pDef[1]
                    local bodyFrame = pDef[2]

                    local allowed = visibleBodies[pName] == true
                    if allowed then

                    -- + indicator (Frame, not TextButton - clicks pass through to bodyFrame)
                    local pBtn = Instance.new("Frame", bodyFrame)
                    pBtn.AnchorPoint = Vector2.new(0.5, 0.5)
                    pBtn.Position = UDim2.new(0.5, 0, 0.5, 0)
                    pBtn.Size = UDim2.new(0, 18, 0, 18)
                    pBtn.BackgroundColor3 = isPartSelected(pName) and colors.Main or Color3.fromRGB(60, 60, 60)
                    pBtn.BackgroundTransparency = isPartSelected(pName) and 0 or 0.3
                    pBtn.BorderSizePixel = 0
                    pBtn.ZIndex = 93
                    Instance.new("UICorner", pBtn).CornerRadius = UDim.new(1, 0)

                    local pLabel = Instance.new("TextLabel", pBtn)
                    pLabel.BackgroundTransparency = 1
                    pLabel.Size = UDim2.new(1, 0, 1, 0)
                    pLabel.Font = Enum.Font.GothamBold
                    pLabel.Text = "+"
                    pLabel.TextColor3 = isPartSelected(pName) and Color3.fromRGB(255, 255, 255) or colors.TextDim
                    pLabel.TextSize = 14
                    pLabel.ZIndex = 94

                    partButtons[pName] = { btn = pBtn, label = pLabel, bodyFrame = bodyFrame }

                    -- Highlight the body part if default selected
                    if isPartSelected(pName) then
                        bodyFrame.BackgroundColor3 = Color3.fromRGB(80, 30, 40)
                    end

                    -- Click anywhere on body part (bodyFrame is a TextButton)
                    bodyFrame.Activated:Connect(function()
                        onPartToggle(pName)
                    end)

                    -- Hover on body part frame
                    bodyFrame.MouseEnter:Connect(function()
                        if not isPartSelected(pName) then
                            Library:Spring(bodyFrame, "Smooth", { BackgroundColor3 = Color3.fromRGB(55, 55, 55) })
                        end
                        Library:Spring(pBtn, "Smooth", { BackgroundTransparency = 0 })
                    end)
                    bodyFrame.MouseLeave:Connect(function()
                        local sel = isPartSelected(pName)
                        Library:Spring(bodyFrame, "Smooth", { BackgroundColor3 = sel and Color3.fromRGB(80, 30, 40) or bodyColor })
                        Library:Spring(pBtn, "Smooth", { BackgroundTransparency = sel and 0 or 0.3 })
                    end)
                    end -- if allowed
                end

                -- Sync FROM linked dropdown
                if hLinked then
                    -- Initial sync
                    task.defer(function()
                        syncFromLinked()
                    end)
                    -- Live sync: dropdown notifies us on every change
                    linkedSyncHandler = function()
                        syncFromLinked()
                    end
                    hLinked._onChange = linkedSyncHandler
                end

                -- Method to update from external source
                function hitbox:SetParts(selected)
                    applySelectedState(selected)
                    refreshPartVisuals()
                end

                -- Toggle panel visibility
                local function togglePanel()
                    hitbox.Visible = not hitbox.Visible
                    if hitbox.Visible then
                        Library:Spring(cl1, "Smooth", { ImageTransparency = 0 })
                        Library:Spring(chkFrame, "Smooth", { BackgroundColor3 = Color3.fromRGB(45, 25, 30) })
                        Library:Spring(chkStroke, "Smooth", { Color = colors.Main, Transparency = 0.3 })
                        
                        -- Set active state so the UI toggle will show it, and show it now if window is open
                        win._floatingPanels[hPanel] = { Active = true }
                        if startupReady and win.Visible then hPanel.Visible = true end
                        
                        -- Sync from linked on show
                        syncFromLinked()
                    else
                        Library:Spring(cl1, "Smooth", { ImageTransparency = 1 })
                        Library:Spring(chkFrame, "Smooth", { BackgroundColor3 = Color3.fromRGB(35, 35, 35) })
                        Library:Spring(chkStroke, "Smooth", { Color = colors.Line, Transparency = 0.5 })
                        
                        win._floatingPanels[hPanel] = { Active = false }
                        hPanel.Visible = false
                    end
                end

                hitbox = controlBase.attachControlLifecycle(section, hitbox, {
                    clickTargets = { clickBtn },
                    getValue = cloneSelectedState,
                    onDestroy = function()
                        if hLinked and hLinked._onChange == linkedSyncHandler then
                            hLinked._onChange = nil
                        end
                        win._floatingPanels[hPanel] = nil
                    end,
                    refresh = refreshPartVisuals,
                    root = row,
                    searchName = hName,
                    setValue = function(selected)
                        applySelectedState(selected)
                        refreshPartVisuals()
                        hCallback(cloneSelectedState())
                    end,
                    updateDisabled = function(disabled)
                        label.TextTransparency = disabled and 0.35 or 0
                        clickBtn.Active = not disabled
                        if disabled and hitbox.Visible then
                            togglePanel()
                        end
                    end,
                })
                hitbox:TrackInstance(hPanel, "HitboxPanel")
                hitbox:TrackConnection(clickBtn.Activated:Connect(function()
                    if hitbox.Disabled then
                        return
                    end

                    togglePanel()
                end), "HitboxToggle")

                return hitbox
            end

            return section
        end

        return menu
    end

    refreshMenuScrolls = function()
        for _, menu in ipairs(win.Menus or {}) do
            if menu and menu._refreshScroll then
                menu:_refreshScroll()
            end
        end
    end



    -- Store refs
    win._main = main
    win._sg = sg
    win._library = Library

    task.defer(function()
        RunService.Heartbeat:Wait()

        if win._destroyed then
            return
        end

        if configName then
            pcall(function()
                Library:LoadConfig()
            end)
        end

        if win._destroyed then
            return
        end

        refreshMenuScrolls()
        startupReady = true

        if win.Visible then
            main.Visible = true
            main.Size = fullWindowSize
            clipFrame.Size = fullClipSize
            updateResizeHover(UserInputService:GetMouseLocation())
        end

        syncFloatingPanels()
    end)

    return win
end
end
