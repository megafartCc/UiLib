return function(Library, context)
    local UserInputService = context.UserInputService

    local function resolveDropdownValue(options, rawValue, allowFallback)
        if type(options) ~= "table" or #options == 0 then
            return nil
        end

        if rawValue == nil then
            return allowFallback and options[1] or nil
        end

        if type(rawValue) == "number" and rawValue % 1 == 0 and options[rawValue] ~= nil then
            return options[rawValue]
        end

        for _, opt in ipairs(options) do
            if opt == rawValue or tostring(opt) == tostring(rawValue) then
                return opt
            end
        end

        return allowFallback and options[1] or nil
    end

    local function buildSelectedSet(options, rawValue)
        local selected = {}
        if type(rawValue) ~= "table" then
            return selected
        end

        local sequenceCount = #rawValue
        if sequenceCount > 0 then
            for _, value in ipairs(rawValue) do
                local resolved = resolveDropdownValue(options, value, false)
                if resolved ~= nil then
                    selected[resolved] = true
                end
            end
        end

        for key, value in pairs(rawValue) do
            if not (type(key) == "number" and key >= 1 and key <= sequenceCount) then
                if value == true then
                    local resolved = resolveDropdownValue(options, key, false)
                    if resolved ~= nil then
                        selected[resolved] = true
                    end
                elseif value then
                    local resolved = resolveDropdownValue(options, value, false)
                    if resolved ~= nil then
                        selected[resolved] = true
                    end
                end
            end
        end

        return selected
    end

    local function getSelectedValues(options, selectedSet)
        local values = {}
        for _, opt in ipairs(options or {}) do
            if selectedSet and selectedSet[opt] then
                table.insert(values, opt)
            end
        end
        return values
    end

    local function getDropdownConfigKey(requestedKey, sectionName, dropdownName)
        if requestedKey == false then
            return nil
        end
        if requestedKey ~= nil then
            return requestedKey
        end
        return string.format("%s.%s", tostring(sectionName or "Section"), tostring(dropdownName or "Dropdown"))
    end

    local function fireMultiDropdownCallback(callback, selectedSet)
        callback(selectedSet, selectedSet)
    end

    local function closeTransientPopups(base, exceptPanel)
        if base.closeTransientPopups then
            base.closeTransientPopups(exceptPanel)
        end
    end

    local function registerTransientPopup(base, panel, closeFn)
        if base.registerTransientPopup then
            base.registerTransientPopup(panel, closeFn)
        end
    end

    local function bindOutsideClose(base, isOpenFn, panel, button, closeFn, keyPrefix)
        if base.bindOutsideClose then
            return base.bindOutsideClose({
                cleanupKey = base.nextCleanupKey(keyPrefix),
                close = closeFn,
                isOpen = isOpenFn,
                targets = function()
                    return {panel, button}
                end,
            })
        end

        base.trackGlobal(UserInputService.InputBegan:Connect(function(input)
            if not isOpenFn() then
                return
            end
            if input.UserInputType ~= Enum.UserInputType.MouseButton1
                and input.UserInputType ~= Enum.UserInputType.Touch then
                return
            end

            local mx, my = input.Position.X, input.Position.Y
            task.defer(function()
                if not isOpenFn() then
                    return
                end

                local pp, ps = panel.AbsolutePosition, panel.AbsoluteSize
                local bp, bs = button.AbsolutePosition, button.AbsoluteSize
                local inPanel = mx >= pp.X and mx <= pp.X + ps.X and my >= pp.Y and my <= pp.Y + ps.Y
                local inButton = mx >= bp.X and mx <= bp.X + bs.X and my >= bp.Y and my <= bp.Y + bs.Y

                if not inPanel and not inButton then
                    closeFn()
                end
            end)
        end), base.nextCleanupKey(keyPrefix))
    end

    local function addToggleDropdown(base, dropOpts)
        dropOpts = dropOpts or {}
        local dName = dropOpts.Name or "Dropdown"
        local dOptions = dropOpts.Options or {"Option 1", "Option 2"}
        local dDefault = resolveDropdownValue(dOptions, dropOpts.Default, true)
        local dCallback = dropOpts.Callback or function() end

        local dropdown = { Value = dDefault }

        local dRow = Instance.new("Frame", base.ensureSubContainer())
        dRow.Name = "SubDrop_" .. dName
        dRow.BackgroundTransparency = 1
        dRow.BorderSizePixel = 0
        dRow.Size = UDim2.new(1, 0, 0, 20)
        dRow.ZIndex = 5
        dRow.ClipsDescendants = false

        local dLabel = Instance.new("TextLabel", dRow)
        dLabel.BackgroundTransparency = 1
        dLabel.Size = UDim2.new(0.4, 0, 1, 0)
        dLabel.Font = base.config.FontMedium
        dLabel.Text = dName
        dLabel.TextColor3 = base.colors.TextDim
        dLabel.TextSize = 11
        dLabel.TextXAlignment = Enum.TextXAlignment.Left
        dLabel.ZIndex = 5

        local selBtn = Instance.new("TextButton", dRow)
        selBtn.AnchorPoint = Vector2.new(1, 0.5)
        selBtn.Position = UDim2.new(1, 0, 0.5, 0)
        selBtn.Size = UDim2.new(0.55, 0, 0, 16)
        selBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
        selBtn.BorderSizePixel = 0
        selBtn.Text = ""
        selBtn.ZIndex = 5
        selBtn.AutoButtonColor = false
        selBtn.Selectable = false
        selBtn.ClipsDescendants = false
        Instance.new("UICorner", selBtn).CornerRadius = UDim.new(0, 3)

        local selStroke = Instance.new("UIStroke", selBtn)
        selStroke.Color = base.colors.Line
        selStroke.Transparency = 0.5

        local selVal = Instance.new("TextLabel", selBtn)
        selVal.BackgroundTransparency = 1
        selVal.Position = UDim2.new(0, 6, 0, 0)
        selVal.Size = UDim2.new(1, -20, 1, 0)
        selVal.Font = base.config.FontMedium
        selVal.Text = tostring(dDefault)
        selVal.TextColor3 = base.colors.Text
        selVal.TextSize = 10
        selVal.TextXAlignment = Enum.TextXAlignment.Left
        selVal.ZIndex = 6

        local selArrow = Instance.new("TextLabel", selBtn)
        selArrow.BackgroundTransparency = 1
        selArrow.AnchorPoint = Vector2.new(1, 0.5)
        selArrow.Position = UDim2.new(1, -4, 0.5, 0)
        selArrow.Size = UDim2.new(0, 12, 0, 12)
        selArrow.Font = base.config.Font
        selArrow.Text = "â–¼"
        selArrow.TextColor3 = base.colors.TextDim
        selArrow.TextSize = 7
        selArrow.ZIndex = 6

        local fullHeight = #dOptions * 22 + 6
        local dPanel = Instance.new("Frame", selBtn)
        dPanel.Position = UDim2.new(0, 0, 1, 2)
        dPanel.Size = UDim2.new(1, 0, 0, 0)
        dPanel.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
        dPanel.BorderSizePixel = 0
        dPanel.Visible = false
        dPanel.ZIndex = 50
        dPanel.ClipsDescendants = true
        Instance.new("UICorner", dPanel).CornerRadius = UDim.new(0, 3)

        local dpStroke = Instance.new("UIStroke", dPanel)
        dpStroke.Color = base.colors.Line
        dpStroke.Transparency = 0.5

        local dpLayout = Instance.new("UIListLayout", dPanel)
        dpLayout.SortOrder = Enum.SortOrder.LayoutOrder

        local dpPad = Instance.new("UIPadding", dPanel)
        dpPad.PaddingTop = UDim.new(0, 3)
        dpPad.PaddingBottom = UDim.new(0, 3)

        local optBtns = {}
        local isOpen = false
        local function closeDropdown()
            isOpen = false
            Library:Spring(dPanel, "Smooth", { Size = UDim2.new(1, 0, 0, 0) })
            task.delay(0.15, function()
                if not isOpen and dPanel.Parent then
                    dPanel.Visible = false
                end
            end)
        end

        registerTransientPopup(base, dPanel, closeDropdown)
        for idx, opt in ipairs(dOptions) do
            local optBtn = Instance.new("TextButton", dPanel)
            optBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
            optBtn.BackgroundTransparency = 1
            optBtn.BorderSizePixel = 0
            optBtn.Size = UDim2.new(1, 0, 0, 22)
            optBtn.Text = ""
            optBtn.ZIndex = 51
            optBtn.LayoutOrder = idx
            optBtn.AutoButtonColor = false
            optBtn.Selectable = false

            local optLabel = Instance.new("TextLabel", optBtn)
            optLabel.BackgroundTransparency = 1
            optLabel.Position = UDim2.new(0, 6, 0, 0)
            optLabel.Size = UDim2.new(1, -12, 1, 0)
            optLabel.Font = base.config.FontMedium
            optLabel.Text = tostring(opt)
            optLabel.TextColor3 = (opt == dropdown.Value) and base.colors.Main or base.colors.Text
            optLabel.TextSize = 10
            optLabel.TextXAlignment = Enum.TextXAlignment.Left
            optLabel.ZIndex = 52

            optBtn.MouseEnter:Connect(function()
                Library:Spring(optBtn, "Smooth", { BackgroundTransparency = 0.5 })
                if dropdown.Value ~= opt then
                    Library:Spring(optLabel, "Smooth", { TextColor3 = Color3.fromRGB(255, 255, 255) })
                end
            end)
            optBtn.MouseLeave:Connect(function()
                Library:Spring(optBtn, "Smooth", { BackgroundTransparency = 1 })
                if dropdown.Value ~= opt then
                    Library:Spring(optLabel, "Smooth", { TextColor3 = base.colors.Text })
                end
            end)
            optBtn.Activated:Connect(function()
                dropdown.Value = opt
                selVal.Text = tostring(opt)
                closeDropdown()
                selArrow.Text = "â–¼"
                for _, button in ipairs(optBtns) do
                    local label = button:FindFirstChildOfClass("TextLabel")
                    if label then
                        label.TextColor3 = (label.Text == tostring(opt)) and base.colors.Main or base.colors.Text
                    end
                end
                dCallback(opt)
            end)

            table.insert(optBtns, optBtn)
        end

        selBtn.Activated:Connect(function()
            isOpen = not isOpen
            if isOpen then
                closeTransientPopups(base, dPanel)
                dPanel.Visible = true
                dPanel.Size = UDim2.new(1, 0, 0, 0)
                Library:Spring(dPanel, "Smooth", { Size = UDim2.new(1, 0, 0, fullHeight) })
                selArrow.Text = "â–²"
            else
                closeDropdown()
                selArrow.Text = "â–¼"
            end
        end)

        bindOutsideClose(base, function()
            return isOpen
        end, dPanel, selBtn, function()
            closeDropdown()
            selArrow.Text = "â–¼"
        end, "ToggleDropdownOutside")

        return dropdown
    end

    local function addStandaloneDropdown(base, dropOpts)
        dropOpts = dropOpts or {}
        local dName = dropOpts.Name or "Dropdown"
        local dOptions = dropOpts.Options or dropOpts.Items or {"Option 1", "Option 2"}
        local dDefault = resolveDropdownValue(dOptions, dropOpts.Default, true)
        local dCallback = dropOpts.Callback or function() end
        local dSaveKey = getDropdownConfigKey(dropOpts.SaveKey, base.secName, dName)

        local dropdown = { Value = dDefault }

        local row = Instance.new("Frame", base.contentContainer)
        row.Name = "Drop_" .. dName
        row.BackgroundTransparency = 1
        row.BorderSizePixel = 0
        row.Size = UDim2.new(1, 0, 0, 22)
        row.ZIndex = 5
        row.ClipsDescendants = false

        local label = Instance.new("TextLabel", row)
        label.BackgroundTransparency = 1
        label.Size = UDim2.new(0.35, 0, 1, 0)
        label.Font = base.config.FontMedium
        label.Text = dName
        label.TextColor3 = base.colors.Text
        label.TextSize = 12
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.ZIndex = 5

        local selectBtn = Instance.new("TextButton", row)
        selectBtn.AnchorPoint = Vector2.new(1, 0.5)
        selectBtn.Position = UDim2.new(1, 0, 0.5, 0)
        selectBtn.Size = UDim2.new(0.6, 0, 0, 18)
        selectBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
        selectBtn.BorderSizePixel = 0
        selectBtn.Text = ""
        selectBtn.ZIndex = 5
        selectBtn.AutoButtonColor = false
        selectBtn.Selectable = false
        selectBtn.ClipsDescendants = false
        Instance.new("UICorner", selectBtn).CornerRadius = UDim.new(0, 3)

        local selStroke = Instance.new("UIStroke", selectBtn)
        selStroke.Color = base.colors.Line
        selStroke.Transparency = 0.5

        local valText = Instance.new("TextLabel", selectBtn)
        valText.BackgroundTransparency = 1
        valText.Position = UDim2.new(0, 8, 0, 0)
        valText.Size = UDim2.new(1, -26, 1, 0)
        valText.Font = base.config.FontMedium
        valText.Text = tostring(dropdown.Value)
        valText.TextColor3 = base.colors.Text
        valText.TextSize = 11
        valText.TextXAlignment = Enum.TextXAlignment.Left
        valText.ZIndex = 6

        local arrow = Instance.new("TextLabel", selectBtn)
        arrow.BackgroundTransparency = 1
        arrow.AnchorPoint = Vector2.new(1, 0.5)
        arrow.Position = UDim2.new(1, -6, 0.5, 0)
        arrow.Size = UDim2.new(0, 14, 0, 14)
        arrow.Font = base.config.Font
        arrow.Text = "â–¼"
        arrow.TextColor3 = base.colors.TextDim
        arrow.TextSize = 8
        arrow.ZIndex = 6

        local fullHeight = #dOptions * 24 + 6
        local dropPanel = Instance.new("Frame", selectBtn)
        dropPanel.Position = UDim2.new(0, 0, 1, 2)
        dropPanel.Size = UDim2.new(1, 0, 0, 0)
        dropPanel.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
        dropPanel.BorderSizePixel = 0
        dropPanel.Visible = false
        dropPanel.ZIndex = 50
        dropPanel.ClipsDescendants = true
        Instance.new("UICorner", dropPanel).CornerRadius = UDim.new(0, 3)

        local pStroke = Instance.new("UIStroke", dropPanel)
        pStroke.Color = base.colors.Line
        pStroke.Transparency = 0.5

        local pLayout = Instance.new("UIListLayout", dropPanel)
        pLayout.SortOrder = Enum.SortOrder.LayoutOrder

        local pPad = Instance.new("UIPadding", dropPanel)
        pPad.PaddingTop = UDim.new(0, 3)
        pPad.PaddingBottom = UDim.new(0, 3)

        local optionButtons = {}
        local isOpen = false
        local function closeDropdown()
            isOpen = false
            Library:Spring(dropPanel, "Smooth", { Size = UDim2.new(1, 0, 0, 0) })
            task.delay(0.15, function()
                if not isOpen and dropPanel.Parent then
                    dropPanel.Visible = false
                end
            end)
        end

        registerTransientPopup(base, dropPanel, closeDropdown)
        for idx, opt in ipairs(dOptions) do
            local optBtn = Instance.new("TextButton", dropPanel)
            optBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
            optBtn.BackgroundTransparency = 1
            optBtn.BorderSizePixel = 0
            optBtn.Size = UDim2.new(1, 0, 0, 24)
            optBtn.Text = ""
            optBtn.ZIndex = 51
            optBtn.LayoutOrder = idx
            optBtn.AutoButtonColor = false
            optBtn.Selectable = false

            local optLabel = Instance.new("TextLabel", optBtn)
            optLabel.BackgroundTransparency = 1
            optLabel.Position = UDim2.new(0, 8, 0, 0)
            optLabel.Size = UDim2.new(1, -16, 1, 0)
            optLabel.Font = base.config.FontMedium
            optLabel.Text = tostring(opt)
            optLabel.TextColor3 = (dropdown.Value == opt) and base.colors.Main or base.colors.Text
            optLabel.TextSize = 11
            optLabel.TextXAlignment = Enum.TextXAlignment.Left
            optLabel.ZIndex = 52

            optBtn.MouseEnter:Connect(function()
                Library:Spring(optBtn, "Smooth", { BackgroundTransparency = 0.5 })
                if dropdown.Value ~= opt then
                    Library:Spring(optLabel, "Smooth", { TextColor3 = Color3.fromRGB(255, 255, 255) })
                end
            end)
            optBtn.MouseLeave:Connect(function()
                Library:Spring(optBtn, "Smooth", { BackgroundTransparency = 1 })
                if dropdown.Value ~= opt then
                    Library:Spring(optLabel, "Smooth", { TextColor3 = base.colors.Text })
                end
            end)
            optBtn.Activated:Connect(function()
                dropdown.Value = opt
                valText.Text = tostring(opt)
                closeDropdown()
                arrow.Text = "â–¼"
                for _, button in ipairs(optionButtons) do
                    local labelRef = button:FindFirstChildOfClass("TextLabel")
                    if labelRef then
                        labelRef.TextColor3 = (labelRef.Text == tostring(opt)) and base.colors.Main or base.colors.Text
                    end
                end
                dCallback(opt)
                Library:_markDirty()
            end)

            table.insert(optionButtons, optBtn)
        end

        selectBtn.Activated:Connect(function()
            isOpen = not isOpen
            if isOpen then
                closeTransientPopups(base, dropPanel)
                dropPanel.Visible = true
                dropPanel.Size = UDim2.new(1, 0, 0, 0)
                Library:Spring(dropPanel, "Smooth", { Size = UDim2.new(1, 0, 0, fullHeight) })
                arrow.Text = "â–²"
            else
                closeDropdown()
                arrow.Text = "â–¼"
            end
        end)

        bindOutsideClose(base, function()
            return isOpen
        end, dropPanel, selectBtn, function()
            closeDropdown()
            arrow.Text = "â–¼"
        end, "StandaloneDropdownOutside")

        if dSaveKey then
            Library:RegisterConfig(dSaveKey, "dropdown",
                function() return dropdown.Value end,
                function(val)
                    local resolved = resolveDropdownValue(dOptions, val, true)
                    dropdown.Value = resolved
                    valText.Text = tostring(resolved)
                    for _, button in ipairs(optionButtons) do
                        local labelRef = button:FindFirstChildOfClass("TextLabel")
                        if labelRef then
                            labelRef.TextColor3 = (labelRef.Text == tostring(resolved)) and base.colors.Main or base.colors.Text
                        end
                    end
                    dCallback(resolved)
                end
            )
        end

        table.insert(base.win._searchItems, {
            name = dName,
            menuName = base.menuName,
            secName = base.secName,
            menuRef = base.menu,
        })

        return dropdown
    end

    local function addMultiDropdown(base, dropOpts)
        dropOpts = dropOpts or {}
        local dName = dropOpts.Name or "Multi Select"
        local dOptions = dropOpts.Options or {"Option 1", "Option 2"}
        local dDefaults = dropOpts.Default or {}
        local dCallback = dropOpts.Callback or function() end
        local dSaveKey = getDropdownConfigKey(dropOpts.SaveKey, base.secName, dName)

        local selectedSet = buildSelectedSet(dOptions, dDefaults)
        local multi = { Values = selectedSet }

        local function getDisplayText()
            local selected = {}
            for _, opt in ipairs(dOptions) do
                if selectedSet[opt] then
                    table.insert(selected, tostring(opt))
                end
            end
            if #selected == 0 then
                return "None"
            end
            local text = table.concat(selected, ", ")
            if #text > 20 then
                text = string.sub(text, 1, 18) .. ".."
            end
            return text
        end

        local row = Instance.new("Frame", base.contentContainer)
        row.Name = "MultiDrop_" .. dName
        row.BackgroundTransparency = 1
        row.BorderSizePixel = 0
        row.Size = UDim2.new(1, 0, 0, 22)
        row.ZIndex = 5
        row.ClipsDescendants = false

        local label = Instance.new("TextLabel", row)
        label.BackgroundTransparency = 1
        label.Size = UDim2.new(0.4, 0, 1, 0)
        label.Font = base.config.FontMedium
        label.Text = dName
        label.TextColor3 = base.colors.Text
        label.TextSize = 12
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.ZIndex = 5

        local selectBtn = Instance.new("TextButton", row)
        selectBtn.AnchorPoint = Vector2.new(1, 0.5)
        selectBtn.Position = UDim2.new(1, 0, 0.5, 0)
        selectBtn.Size = UDim2.new(0.55, 0, 0, 18)
        selectBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
        selectBtn.BorderSizePixel = 0
        selectBtn.Text = ""
        selectBtn.ZIndex = 5
        selectBtn.AutoButtonColor = false
        selectBtn.Selectable = false
        selectBtn.ClipsDescendants = false
        Instance.new("UICorner", selectBtn).CornerRadius = UDim.new(0, 3)

        local selStroke = Instance.new("UIStroke", selectBtn)
        selStroke.Color = base.colors.Line
        selStroke.Transparency = 0.5

        local valText = Instance.new("TextLabel", selectBtn)
        valText.BackgroundTransparency = 1
        valText.Position = UDim2.new(0, 8, 0, 0)
        valText.Size = UDim2.new(1, -26, 1, 0)
        valText.Font = base.config.FontMedium
        valText.Text = getDisplayText()
        valText.TextColor3 = base.colors.Text
        valText.TextSize = 11
        valText.TextXAlignment = Enum.TextXAlignment.Left
        valText.ZIndex = 6

        local arrow = Instance.new("TextLabel", selectBtn)
        arrow.BackgroundTransparency = 1
        arrow.AnchorPoint = Vector2.new(1, 0.5)
        arrow.Position = UDim2.new(1, -6, 0.5, 0)
        arrow.Size = UDim2.new(0, 14, 0, 14)
        arrow.Font = base.config.Font
        arrow.Text = "â–¼"
        arrow.TextColor3 = base.colors.TextDim
        arrow.TextSize = 8
        arrow.ZIndex = 6

        local fullHeight = #dOptions * 24 + 6
        local dropPanel = Instance.new("Frame", selectBtn)
        dropPanel.Position = UDim2.new(0, 0, 1, 2)
        dropPanel.Size = UDim2.new(1, 0, 0, 0)
        dropPanel.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
        dropPanel.BorderSizePixel = 0
        dropPanel.Visible = false
        dropPanel.ZIndex = 50
        dropPanel.ClipsDescendants = true
        Instance.new("UICorner", dropPanel).CornerRadius = UDim.new(0, 3)

        local pStroke = Instance.new("UIStroke", dropPanel)
        pStroke.Color = base.colors.Line
        pStroke.Transparency = 0.5

        local pLayout = Instance.new("UIListLayout", dropPanel)
        pLayout.SortOrder = Enum.SortOrder.LayoutOrder

        local pPad = Instance.new("UIPadding", dropPanel)
        pPad.PaddingTop = UDim.new(0, 3)
        pPad.PaddingBottom = UDim.new(0, 3)

        local optVisuals = {}
        local isOpen = false
        local function closeDropdown()
            isOpen = false
            Library:Spring(dropPanel, "Smooth", { Size = UDim2.new(1, 0, 0, 0) })
            task.delay(0.15, function()
                if not isOpen and dropPanel.Parent then
                    dropPanel.Visible = false
                end
            end)
        end

        registerTransientPopup(base, dropPanel, closeDropdown)
        for idx, opt in ipairs(dOptions) do
            local optBtn = Instance.new("TextButton", dropPanel)
            optBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
            optBtn.BackgroundTransparency = 1
            optBtn.BorderSizePixel = 0
            optBtn.Size = UDim2.new(1, 0, 0, 24)
            optBtn.Text = ""
            optBtn.ZIndex = 51
            optBtn.LayoutOrder = idx
            optBtn.AutoButtonColor = false
            optBtn.Selectable = false

            local chk = Instance.new("Frame", optBtn)
            chk.AnchorPoint = Vector2.new(0, 0.5)
            chk.Position = UDim2.new(0, 8, 0.5, 0)
            chk.Size = UDim2.new(0, 10, 0, 10)
            chk.BackgroundColor3 = selectedSet[opt] and Color3.fromRGB(45, 25, 30) or Color3.fromRGB(35, 35, 35)
            chk.BorderSizePixel = 0
            chk.ZIndex = 52
            Instance.new("UICorner", chk).CornerRadius = UDim.new(0, 2)

            local chkStroke = Instance.new("UIStroke", chk)
            chkStroke.Color = selectedSet[opt] and base.colors.Main or base.colors.Line
            chkStroke.Transparency = selectedSet[opt] and 0.3 or 0.5

            local chkIcon = Instance.new("ImageLabel", chk)
            chkIcon.BackgroundTransparency = 1
            chkIcon.AnchorPoint = Vector2.new(0.5, 0.5)
            chkIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
            chkIcon.Size = UDim2.new(0, 8, 0, 8)
            chkIcon.Image = "rbxassetid://122354904349171"
            chkIcon.ImageColor3 = base.colors.Main
            chkIcon.ImageTransparency = selectedSet[opt] and 0 or 1
            chkIcon.ZIndex = 53

            local optLabel = Instance.new("TextLabel", optBtn)
            optLabel.BackgroundTransparency = 1
            optLabel.Position = UDim2.new(0, 24, 0, 0)
            optLabel.Size = UDim2.new(1, -30, 1, 0)
            optLabel.Font = base.config.FontMedium
            optLabel.Text = tostring(opt)
            optLabel.TextColor3 = selectedSet[opt] and base.colors.Main or base.colors.Text
            optLabel.TextSize = 11
            optLabel.TextXAlignment = Enum.TextXAlignment.Left
            optLabel.ZIndex = 52

            optBtn.MouseEnter:Connect(function()
                Library:Spring(optBtn, "Smooth", { BackgroundTransparency = 0.5 })
            end)
            optBtn.MouseLeave:Connect(function()
                Library:Spring(optBtn, "Smooth", { BackgroundTransparency = 1 })
            end)
            optBtn.Activated:Connect(function()
                selectedSet[opt] = not selectedSet[opt]
                chkIcon.ImageTransparency = selectedSet[opt] and 0 or 1
                if selectedSet[opt] then
                    Library:Spring(chk, "Smooth", { BackgroundColor3 = Color3.fromRGB(45, 25, 30) })
                    Library:Spring(chkStroke, "Smooth", { Color = base.colors.Main, Transparency = 0.3 })
                    optLabel.TextColor3 = base.colors.Main
                else
                    Library:Spring(chk, "Smooth", { BackgroundColor3 = Color3.fromRGB(35, 35, 35) })
                    Library:Spring(chkStroke, "Smooth", { Color = base.colors.Line, Transparency = 0.5 })
                    optLabel.TextColor3 = base.colors.Text
                end
                valText.Text = getDisplayText()
                multi.Values = selectedSet
                fireMultiDropdownCallback(dCallback, selectedSet)
                if multi._onChange then
                    multi._onChange()
                end
                Library:_markDirty()
            end)

            optVisuals[opt] = {
                chk = chk,
                chkIcon = chkIcon,
                chkStroke = chkStroke,
                optLabel = optLabel,
            }
        end

        selectBtn.Activated:Connect(function()
            isOpen = not isOpen
            if isOpen then
                closeTransientPopups(base, dropPanel)
                dropPanel.Visible = true
                dropPanel.Size = UDim2.new(1, 0, 0, 0)
                Library:Spring(dropPanel, "Smooth", { Size = UDim2.new(1, 0, 0, fullHeight) })
                arrow.Text = "â–²"
            else
                closeDropdown()
                arrow.Text = "â–¼"
            end
        end)

        bindOutsideClose(base, function()
            return isOpen
        end, dropPanel, selectBtn, function()
            closeDropdown()
            arrow.Text = "â–¼"
        end, "MultiDropdownOutside")

        if dSaveKey then
            Library:RegisterConfig(dSaveKey, "multi",
                function() return getSelectedValues(dOptions, selectedSet) end,
                function(val)
                    if type(val) ~= "table" then
                        return
                    end
                    for key in pairs(selectedSet) do
                        selectedSet[key] = nil
                    end
                    for key, enabled in pairs(buildSelectedSet(dOptions, val)) do
                        selectedSet[key] = enabled
                    end
                    multi.Values = selectedSet
                    multi:Refresh()
                    fireMultiDropdownCallback(dCallback, selectedSet)
                    if multi._onChange then
                        multi._onChange()
                    end
                end
            )
        end

        table.insert(base.win._searchItems, {
            name = dName,
            menuName = base.menuName,
            secName = base.secName,
            menuRef = base.menu,
        })

        function multi:Refresh()
            valText.Text = getDisplayText()
            for optName, visuals in pairs(optVisuals) do
                local selected = selectedSet[optName]
                visuals.chkIcon.ImageTransparency = selected and 0 or 1
                visuals.chk.BackgroundColor3 = selected and Color3.fromRGB(45, 25, 30) or Color3.fromRGB(35, 35, 35)
                visuals.chkStroke.Color = selected and base.colors.Main or base.colors.Line
                visuals.chkStroke.Transparency = selected and 0.3 or 0.5
                visuals.optLabel.TextColor3 = selected and base.colors.Main or base.colors.Text
            end
        end

        return multi
    end

    local function addDropdownToggle(base, opts)
        opts = opts or {}
        local dName = opts.Name or "Dropdown"
        local dOptions = opts.Options or {"Option 1", "Option 2"}
        local dDefault = resolveDropdownValue(dOptions, opts.Default, true)
        local dEnabled = opts.Enabled ~= false
        local dCallback = opts.Callback or function() end
        local dToggleCallback = opts.OnToggle or function() end

        local dt = { Value = dDefault, Enabled = dEnabled }

        local row = Instance.new("Frame", base.contentContainer)
        row.Name = "DropToggle_" .. dName
        row.BackgroundTransparency = 1
        row.BorderSizePixel = 0
        row.Size = UDim2.new(1, 0, 0, 22)
        row.ZIndex = 5
        row.ClipsDescendants = false

        local label = Instance.new("TextLabel", row)
        label.BackgroundTransparency = 1
        label.Size = UDim2.new(0.3, 0, 1, 0)
        label.Font = base.config.FontMedium
        label.Text = dName
        label.TextColor3 = base.colors.Text
        label.TextSize = 12
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.ZIndex = 5

        local chkFrame = Instance.new("Frame", row)
        chkFrame.AnchorPoint = Vector2.new(1, 0.5)
        chkFrame.Position = UDim2.new(1, 0, 0.5, 0)
        chkFrame.Size = UDim2.new(0, 18, 0, 18)
        chkFrame.BackgroundColor3 = dEnabled and Color3.fromRGB(45, 25, 30) or Color3.fromRGB(35, 35, 35)
        chkFrame.BorderSizePixel = 0
        chkFrame.ZIndex = 5
        Instance.new("UICorner", chkFrame).CornerRadius = UDim.new(0, 3)

        local chkStroke = Instance.new("UIStroke", chkFrame)
        chkStroke.Color = dEnabled and base.colors.Main or base.colors.Line
        chkStroke.Transparency = dEnabled and 0.3 or 0.5

        local checkIcon = Instance.new("ImageLabel", chkFrame)
        checkIcon.BackgroundTransparency = 1
        checkIcon.AnchorPoint = Vector2.new(0.5, 0.5)
        checkIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
        checkIcon.Size = UDim2.new(0, 12, 0, 12)
        checkIcon.Image = "rbxassetid://122354904349171"
        checkIcon.ImageColor3 = base.colors.Main
        checkIcon.ImageTransparency = dEnabled and 0 or 1
        checkIcon.ZIndex = 6

        local chkBtn = Instance.new("TextButton", chkFrame)
        chkBtn.BackgroundTransparency = 1
        chkBtn.Size = UDim2.new(1, 0, 1, 0)
        chkBtn.ZIndex = 7
        chkBtn.Text = ""
        chkBtn.AutoButtonColor = false
        chkBtn.Selectable = false
        chkBtn.BorderSizePixel = 0

        chkBtn.Activated:Connect(function()
            dt.Enabled = not dt.Enabled
            if dt.Enabled then
                Library:Spring(checkIcon, "Smooth", { ImageTransparency = 0 })
                Library:Spring(chkFrame, "Smooth", { BackgroundColor3 = Color3.fromRGB(45, 25, 30) })
                Library:Spring(chkStroke, "Smooth", { Color = base.colors.Main, Transparency = 0.3 })
            else
                Library:Spring(checkIcon, "Smooth", { ImageTransparency = 1 })
                Library:Spring(chkFrame, "Smooth", { BackgroundColor3 = Color3.fromRGB(35, 35, 35) })
                Library:Spring(chkStroke, "Smooth", { Color = base.colors.Line, Transparency = 0.5 })
            end
            dToggleCallback(dt.Enabled)
            Library:_markDirty()
        end)

        local selectBtn = Instance.new("TextButton", row)
        selectBtn.AnchorPoint = Vector2.new(1, 0.5)
        selectBtn.Position = UDim2.new(1, -20, 0.5, 0)
        selectBtn.Size = UDim2.new(0.45, 0, 0, 18)
        selectBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
        selectBtn.BorderSizePixel = 0
        selectBtn.Text = ""
        selectBtn.ZIndex = 5
        selectBtn.AutoButtonColor = false
        selectBtn.Selectable = false
        selectBtn.ClipsDescendants = false
        Instance.new("UICorner", selectBtn).CornerRadius = UDim.new(0, 3)

        local selStroke = Instance.new("UIStroke", selectBtn)
        selStroke.Color = base.colors.Line
        selStroke.Transparency = 0.5

        local valText = Instance.new("TextLabel", selectBtn)
        valText.BackgroundTransparency = 1
        valText.Position = UDim2.new(0, 8, 0, 0)
        valText.Size = UDim2.new(1, -26, 1, 0)
        valText.Font = base.config.FontMedium
        valText.Text = tostring(dDefault)
        valText.TextColor3 = base.colors.Text
        valText.TextSize = 11
        valText.TextXAlignment = Enum.TextXAlignment.Left
        valText.ZIndex = 6

        local arrow = Instance.new("TextLabel", selectBtn)
        arrow.BackgroundTransparency = 1
        arrow.AnchorPoint = Vector2.new(1, 0.5)
        arrow.Position = UDim2.new(1, -6, 0.5, 0)
        arrow.Size = UDim2.new(0, 14, 0, 14)
        arrow.Font = base.config.Font
        arrow.Text = "â–¼"
        arrow.TextColor3 = base.colors.TextDim
        arrow.TextSize = 8
        arrow.ZIndex = 6

        local fullHeight = #dOptions * 24 + 6
        local dropPanel = Instance.new("Frame", selectBtn)
        dropPanel.Position = UDim2.new(0, 0, 1, 2)
        dropPanel.Size = UDim2.new(1, 0, 0, 0)
        dropPanel.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
        dropPanel.BorderSizePixel = 0
        dropPanel.Visible = false
        dropPanel.ZIndex = 50
        dropPanel.ClipsDescendants = true
        Instance.new("UICorner", dropPanel).CornerRadius = UDim.new(0, 3)

        local pStroke = Instance.new("UIStroke", dropPanel)
        pStroke.Color = base.colors.Line
        pStroke.Transparency = 0.5

        local pLayout = Instance.new("UIListLayout", dropPanel)
        pLayout.SortOrder = Enum.SortOrder.LayoutOrder

        local pPad = Instance.new("UIPadding", dropPanel)
        pPad.PaddingTop = UDim.new(0, 3)
        pPad.PaddingBottom = UDim.new(0, 3)

        local optionButtons = {}
        local isOpen = false
        local function closeDropdown()
            isOpen = false
            Library:Spring(dropPanel, "Smooth", { Size = UDim2.new(1, 0, 0, 0) })
            task.delay(0.15, function()
                if not isOpen and dropPanel.Parent then
                    dropPanel.Visible = false
                end
            end)
        end

        registerTransientPopup(base, dropPanel, closeDropdown)
        for idx, opt in ipairs(dOptions) do
            local optBtn = Instance.new("TextButton", dropPanel)
            optBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
            optBtn.BackgroundTransparency = 1
            optBtn.BorderSizePixel = 0
            optBtn.Size = UDim2.new(1, 0, 0, 24)
            optBtn.Text = ""
            optBtn.ZIndex = 51
            optBtn.LayoutOrder = idx
            optBtn.AutoButtonColor = false
            optBtn.Selectable = false

            local optLabel = Instance.new("TextLabel", optBtn)
            optLabel.BackgroundTransparency = 1
            optLabel.Position = UDim2.new(0, 8, 0, 0)
            optLabel.Size = UDim2.new(1, -16, 1, 0)
            optLabel.Font = base.config.FontMedium
            optLabel.Text = tostring(opt)
            optLabel.TextColor3 = (opt == dt.Value) and base.colors.Main or base.colors.Text
            optLabel.TextSize = 11
            optLabel.TextXAlignment = Enum.TextXAlignment.Left
            optLabel.ZIndex = 52

            optBtn.MouseEnter:Connect(function()
                Library:Spring(optBtn, "Smooth", { BackgroundTransparency = 0.5 })
                if dt.Value ~= opt then
                    Library:Spring(optLabel, "Smooth", { TextColor3 = Color3.fromRGB(255, 255, 255) })
                end
            end)
            optBtn.MouseLeave:Connect(function()
                Library:Spring(optBtn, "Smooth", { BackgroundTransparency = 1 })
                if dt.Value ~= opt then
                    Library:Spring(optLabel, "Smooth", { TextColor3 = base.colors.Text })
                end
            end)
            optBtn.Activated:Connect(function()
                dt.Value = opt
                valText.Text = tostring(opt)
                closeDropdown()
                arrow.Text = "â–¼"
                for _, button in ipairs(optionButtons) do
                    local labelRef = button:FindFirstChildOfClass("TextLabel")
                    if labelRef then
                        labelRef.TextColor3 = (labelRef.Text == tostring(opt)) and base.colors.Main or base.colors.Text
                    end
                end
                dCallback(opt)
                Library:_markDirty()
            end)

            table.insert(optionButtons, optBtn)
        end

        selectBtn.Activated:Connect(function()
            isOpen = not isOpen
            if isOpen then
                closeTransientPopups(base, dropPanel)
                dropPanel.Visible = true
                dropPanel.Size = UDim2.new(1, 0, 0, 0)
                Library:Spring(dropPanel, "Smooth", { Size = UDim2.new(1, 0, 0, fullHeight) })
                arrow.Text = "â–²"
            else
                closeDropdown()
                arrow.Text = "â–¼"
            end
        end)

        bindOutsideClose(base, function()
            return isOpen
        end, dropPanel, selectBtn, function()
            closeDropdown()
            arrow.Text = "â–¼"
        end, "DropdownToggleOutside")

        Library:RegisterConfig(base.secName .. "." .. dName, "dropdowntoggle",
            function() return { value = dt.Value, enabled = dt.Enabled } end,
            function(val)
                if type(val) ~= "table" then
                    return
                end
                if val.value ~= nil then
                    local resolved = resolveDropdownValue(dOptions, val.value, true)
                    dt.Value = resolved
                    valText.Text = tostring(resolved)
                    for _, button in ipairs(optionButtons) do
                        local labelRef = button:FindFirstChildOfClass("TextLabel")
                        if labelRef then
                            labelRef.TextColor3 = (labelRef.Text == tostring(resolved)) and base.colors.Main or base.colors.Text
                        end
                    end
                    dCallback(resolved)
                end
                if val.enabled ~= nil then
                    dt.Enabled = val.enabled
                    checkIcon.ImageTransparency = val.enabled and 0 or 1
                    chkFrame.BackgroundColor3 = val.enabled and Color3.fromRGB(45, 25, 30) or Color3.fromRGB(35, 35, 35)
                    chkStroke.Color = val.enabled and base.colors.Main or base.colors.Line
                    chkStroke.Transparency = val.enabled and 0.3 or 0.5
                    dToggleCallback(dt.Enabled)
                end
            end
        )

        table.insert(base.win._searchItems, {
            name = dName,
            menuName = base.menuName,
            secName = base.secName,
            menuRef = base.menu,
        })

        return dt
    end

    return {
        addDropdownToggle = addDropdownToggle,
        addMultiDropdown = addMultiDropdown,
        addStandaloneDropdown = addStandaloneDropdown,
        addToggleDropdown = addToggleDropdown,
    }
end