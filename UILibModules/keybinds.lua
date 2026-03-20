return function(Library, context)
    local UserInputService = context.UserInputService

    local function toKeyCode(value)
        if typeof(value) == "EnumItem" and value.EnumType == Enum.KeyCode then
            return value
        end

        if type(value) == "string" then
            local trimmed = value:gsub("^%s+", ""):gsub("%s+$", "")
            if trimmed == "" then
                return nil
            end
            return Enum.KeyCode[trimmed]
        end

        return nil
    end

    local function isRecordAlive(record)
        if type(record) ~= "table" then
            return false
        end

        local control = record.Control
        if type(control) ~= "table" then
            return false
        end
        if control._destroyed then
            return false
        end

        local root = control._root
        if root and root.Parent == nil then
            return false
        end

        return true
    end

    return function(opts)
        opts = opts or {}

        local win = opts.win
        local main = opts.main
        local clipFrame = opts.clipFrame
        local colors = opts.colors or Library.Colors
        local config = opts.config or Library.Config
        local bindTheme = opts.bindTheme or function() end
        local closeTransientPopups = opts.closeTransientPopups or function() end
        local registerTransientPopup = opts.registerTransientPopup or function() return function() end end
        local setPopupOpen = opts.setPopupOpen
        local bindOutsideClose = opts.bindOutsideClose
        local syncFloatingPanels = opts.syncFloatingPanels or function() end
        local trackGlobal = opts.trackGlobal or function(connection) return connection end
        local isRuntimeEnabled = opts.isRuntimeEnabled or function() return true end
        local getReservedKey = opts.getReservedKey

        local recordsByControl = {}
        local orderedRecords = {}
        local recordsByKey = {}
        local showList = true
        local captureRecord = nil
        local editorOpen = false

        local keybindsPanel = Instance.new("Frame", main)
        keybindsPanel.Name = "KeybindsPanel"
        keybindsPanel.AnchorPoint = Vector2.new(0, 0)
        keybindsPanel.Position = UDim2.new(0, 8, 0, (config.HeaderHeight or 40) + 8)
        keybindsPanel.Size = UDim2.fromOffset(190, 0)
        keybindsPanel.BackgroundColor3 = Color3.fromRGB(22, 22, 22)
        keybindsPanel.BorderSizePixel = 0
        keybindsPanel.ClipsDescendants = true
        keybindsPanel.Visible = false
        keybindsPanel.ZIndex = 120
        Instance.new("UICorner", keybindsPanel).CornerRadius = UDim.new(0, 5)
        local keybindsStroke = Instance.new("UIStroke", keybindsPanel)
        keybindsStroke.Color = colors.Line
        keybindsStroke.Transparency = 0.35

        local keybindsHeader = Instance.new("TextLabel", keybindsPanel)
        keybindsHeader.BackgroundTransparency = 1
        keybindsHeader.Position = UDim2.new(0, 8, 0, 6)
        keybindsHeader.Size = UDim2.new(1, -16, 0, 14)
        keybindsHeader.Font = config.Font
        keybindsHeader.Text = "KEYBINDS"
        keybindsHeader.TextColor3 = colors.TextStrong
        keybindsHeader.TextSize = 12
        keybindsHeader.TextXAlignment = Enum.TextXAlignment.Left
        keybindsHeader.ZIndex = 121

        local keybindsSep = Instance.new("Frame", keybindsPanel)
        keybindsSep.BackgroundColor3 = colors.Line
        keybindsSep.BorderSizePixel = 0
        keybindsSep.Position = UDim2.new(0, 8, 0, 22)
        keybindsSep.Size = UDim2.new(1, -16, 0, 1)
        keybindsSep.ZIndex = 121

        local keybindsList = Instance.new("Frame", keybindsPanel)
        keybindsList.BackgroundTransparency = 1
        keybindsList.Position = UDim2.new(0, 8, 0, 26)
        keybindsList.Size = UDim2.new(1, -16, 0, 0)
        keybindsList.ZIndex = 121

        local keybindsLayout = Instance.new("UIListLayout", keybindsList)
        keybindsLayout.SortOrder = Enum.SortOrder.LayoutOrder
        keybindsLayout.Padding = UDim.new(0, 4)

        bindTheme(keybindsPanel, "BackgroundColor3", "Panel")
        bindTheme(keybindsPanel, "BackgroundTransparency", "PanelTransparency")
        bindTheme(keybindsStroke, "Color", "Line")
        bindTheme(keybindsHeader, "TextColor3", "TextStrong")
        bindTheme(keybindsSep, "BackgroundColor3", "Line")

        win._floatingPanels[keybindsPanel] = { Active = false }

        local bindEditor = Instance.new("Frame", clipFrame)
        bindEditor.Name = "KeybindEditor"
        bindEditor.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
        bindEditor.BorderSizePixel = 0
        bindEditor.Size = UDim2.fromOffset(190, 0)
        bindEditor.Visible = false
        bindEditor.ClipsDescendants = true
        bindEditor.ZIndex = 170
        Instance.new("UICorner", bindEditor).CornerRadius = UDim.new(0, 4)
        local bindEditorStroke = Instance.new("UIStroke", bindEditor)
        bindEditorStroke.Color = colors.Line
        bindEditorStroke.Transparency = 1

        local bindEditorTitle = Instance.new("TextLabel", bindEditor)
        bindEditorTitle.BackgroundTransparency = 1
        bindEditorTitle.Position = UDim2.new(0, 8, 0, 6)
        bindEditorTitle.Size = UDim2.new(1, -16, 0, 14)
        bindEditorTitle.Font = config.Font
        bindEditorTitle.Text = "Set Keybind"
        bindEditorTitle.TextColor3 = colors.TextStrong
        bindEditorTitle.TextSize = 11
        bindEditorTitle.TextXAlignment = Enum.TextXAlignment.Left
        bindEditorTitle.ZIndex = 171

        local bindEditorHint = Instance.new("TextLabel", bindEditor)
        bindEditorHint.BackgroundTransparency = 1
        bindEditorHint.Position = UDim2.new(0, 8, 0, 24)
        bindEditorHint.Size = UDim2.new(1, -16, 0, 32)
        bindEditorHint.Font = config.FontMedium
        bindEditorHint.Text = "Press any key\nBackspace = clear | Esc = cancel"
        bindEditorHint.TextColor3 = colors.TextDim
        bindEditorHint.TextSize = 10
        bindEditorHint.TextXAlignment = Enum.TextXAlignment.Left
        bindEditorHint.TextYAlignment = Enum.TextYAlignment.Top
        bindEditorHint.ZIndex = 171

        bindTheme(bindEditor, "BackgroundColor3", "Panel")
        bindTheme(bindEditor, "BackgroundTransparency", "PanelTransparency")
        bindTheme(bindEditorStroke, "Color", "Line")
        bindTheme(bindEditorTitle, "TextColor3", "TextStrong")
        bindTheme(bindEditorHint, "TextColor3", "TextDim")

        local editorPopupConfig = {
            ClosedSize = UDim2.fromOffset(190, 0),
            OpenSize = UDim2.fromOffset(190, 62),
            OpenToken = "Open",
            CloseToken = "Close",
            HideDelay = 0.2,
        }

        local manager = {}

        local function removeRecordFromOrder(record)
            for index = #orderedRecords, 1, -1 do
                if orderedRecords[index] == record then
                    table.remove(orderedRecords, index)
                    break
                end
            end
        end

        local function detachFromKey(record)
            local keyCode = record.KeyCode
            if not keyCode then
                return
            end

            local bucket = recordsByKey[keyCode]
            if not bucket then
                record.KeyCode = nil
                return
            end

            for index = #bucket, 1, -1 do
                if bucket[index] == record then
                    table.remove(bucket, index)
                end
            end

            if #bucket == 0 then
                recordsByKey[keyCode] = nil
            end

            record.KeyCode = nil
        end

        local function attachToKey(record, keyCode)
            if not keyCode then
                return
            end

            local bucket = recordsByKey[keyCode]
            if not bucket then
                bucket = {}
                recordsByKey[keyCode] = bucket
            end

            table.insert(bucket, record)
            record.KeyCode = keyCode
        end

        function manager:DetachControl(control)
            local record = recordsByControl[control]
            if not record then
                return
            end

            if captureRecord == record then
                captureRecord = nil
            end

            recordsByControl[control] = nil
            detachFromKey(record)
            removeRecordFromOrder(record)
        end

        local function pruneRecords()
            for index = #orderedRecords, 1, -1 do
                local record = orderedRecords[index]
                if not isRecordAlive(record) then
                    manager:DetachControl(record and record.Control)
                end
            end
        end

        local function setEditorOpen(nextOpen)
            if editorOpen == nextOpen then
                return
            end

            editorOpen = nextOpen
            if not editorOpen then
                captureRecord = nil
            end

            if setPopupOpen then
                setPopupOpen(bindEditor, editorOpen, editorPopupConfig)
            else
                bindEditor.Visible = editorOpen
                bindEditor.Size = editorOpen and editorPopupConfig.OpenSize or editorPopupConfig.ClosedSize
            end
        end

        local function positionEditor(mousePos)
            local clipPos = clipFrame.AbsolutePosition
            local clipSize = clipFrame.AbsoluteSize
            local x = math.clamp(
                mousePos.X - clipPos.X + 6,
                4,
                math.max(4, clipSize.X - 194)
            )
            local y = math.clamp(
                mousePos.Y - clipPos.Y + 6,
                4,
                math.max(4, clipSize.Y - 66)
            )
            bindEditor.Position = UDim2.fromOffset(x, y)
        end

        registerTransientPopup(bindEditor, function()
            setEditorOpen(false)
        end)

        if bindOutsideClose then
            bindOutsideClose({
                cleanupKey = "KeybindEditorOutside",
                close = function()
                    setEditorOpen(false)
                end,
                isOpen = function()
                    return editorOpen
                end,
                targets = function()
                    return { bindEditor }
                end,
            })
        end

        local function buildDisplayRows()
            local rows = {}
            for _, record in ipairs(orderedRecords) do
                if record.KeyCode then
                    table.insert(rows, record)
                end
            end
            return rows
        end

        local function refreshListPanel()
            pruneRecords()

            for _, child in ipairs(keybindsList:GetChildren()) do
                if child:IsA("GuiObject") then
                    child:Destroy()
                end
            end

            local rows = buildDisplayRows()
            local visibleCount = math.min(#rows, 10)

            for index = 1, visibleCount do
                local record = rows[index]
                local row = Instance.new("TextLabel", keybindsList)
                row.BackgroundTransparency = 1
                row.Size = UDim2.new(1, 0, 0, 14)
                row.LayoutOrder = index
                row.Font = config.FontMedium
                row.Text = ("[%s] %s"):format(record.KeyCode.Name, tostring(record.Name))
                row.TextColor3 = colors.Text
                row.TextSize = 10
                row.TextXAlignment = Enum.TextXAlignment.Left
                row.ZIndex = 121
                bindTheme(row, "TextColor3", "Text")
            end

            if #rows > 10 then
                local more = Instance.new("TextLabel", keybindsList)
                more.BackgroundTransparency = 1
                more.Size = UDim2.new(1, 0, 0, 14)
                more.LayoutOrder = 1000
                more.Font = config.FontMedium
                more.Text = ("+ %d more"):format(#rows - 10)
                more.TextColor3 = colors.TextDim
                more.TextSize = 10
                more.TextXAlignment = Enum.TextXAlignment.Left
                more.ZIndex = 121
                bindTheme(more, "TextColor3", "TextDim")
            end

            local hasRows = #rows > 0
            local targetHeight = hasRows and (30 + (math.min(#rows, 10) * 18) + (#rows > 10 and 14 or 0)) or 0
            keybindsPanel.Size = UDim2.fromOffset(190, targetHeight)
            keybindsList.Size = UDim2.new(1, -16, 0, math.max(0, targetHeight - 30))

            local panelState = win._floatingPanels[keybindsPanel]
            if panelState then
                panelState.Active = showList and hasRows
            end
            syncFloatingPanels()
        end

        local function setRecordBind(record, value, shouldMarkDirty)
            if type(record) ~= "table" then
                return false
            end

            local keyCode = toKeyCode(value)
            if value == nil or value == false or value == "" then
                keyCode = nil
            end

            if keyCode and keyCode == Enum.KeyCode.Unknown then
                return false
            end

            if keyCode and type(getReservedKey) == "function" then
                local reserved = getReservedKey()
                if reserved and keyCode == reserved then
                    bindEditorHint.Text = ("'%s' is reserved by UI toggle"):format(keyCode.Name)
                    return false
                end
            end

            detachFromKey(record)
            if keyCode then
                attachToKey(record, keyCode)
            end

            if shouldMarkDirty then
                Library:_markDirty()
            end
            refreshListPanel()
            return true
        end

        function manager:SetControlKeybind(control, value, shouldMarkDirty)
            local record = recordsByControl[control]
            if not record then
                return false
            end
            return setRecordBind(record, value, shouldMarkDirty == true)
        end

        function manager:GetControlKeybind(control)
            local record = recordsByControl[control]
            if not record or not record.KeyCode then
                return nil
            end
            return record.KeyCode.Name
        end

        function manager:SetListEnabled(enabled, shouldMarkDirty)
            showList = enabled ~= false
            if shouldMarkDirty then
                Library:_markDirty()
            end
            refreshListPanel()
        end

        function manager:GetListEnabled()
            return showList
        end

        function manager:CloseEditor()
            setEditorOpen(false)
        end

        function manager:AttachToggle(control, meta)
            if not control or recordsByControl[control] then
                return
            end

            meta = meta or {}
            local record = {
                Control = control,
                Name = tostring(meta.Name or "Toggle"),
                MenuName = tostring(meta.MenuName or ""),
                SectionName = tostring(meta.SectionName or ""),
                ConfigKey = meta.ConfigKey,
                KeyCode = nil,
            }

            recordsByControl[control] = record
            table.insert(orderedRecords, record)

            local function openEditorForRecord()
                if control.Disabled then
                    return
                end
                if not isRuntimeEnabled() then
                    return
                end

                captureRecord = record
                bindEditorTitle.Text = "Set Keybind: " .. record.Name
                bindEditorHint.Text = "Press any key\nBackspace = clear | Esc = cancel"
                positionEditor(UserInputService:GetMouseLocation())
                closeTransientPopups(bindEditor)
                setEditorOpen(true)
            end

            local targets = meta.Targets
            if type(targets) == "table" then
                for _, target in ipairs(targets) do
                    if target and target:IsA("GuiButton") then
                        control:TrackConnection(target.MouseButton2Click:Connect(openEditorForRecord))
                    end
                end
            end

            if control._root then
                control:TrackConnection(control._root.AncestryChanged:Connect(function(_, parent)
                    if parent == nil then
                        manager:DetachControl(control)
                        refreshListPanel()
                    end
                end))
            end

            if type(record.ConfigKey) == "string" and record.ConfigKey ~= "" then
                local bindConfigKey = "__uilib.bind." .. record.ConfigKey
                Library:RegisterConfig(bindConfigKey, "keybind",
                    function()
                        local current = recordsByControl[control]
                        if current and current.KeyCode then
                            return current.KeyCode.Name
                        end
                        return nil
                    end,
                    function(value)
                        manager:SetControlKeybind(control, value, false)
                    end
                )
            end

            refreshListPanel()
        end

        trackGlobal(UserInputService.InputBegan:Connect(function(input, gpe)
            if input.UserInputType ~= Enum.UserInputType.Keyboard then
                return
            end

            local keyCode = input.KeyCode
            if keyCode == Enum.KeyCode.Unknown then
                return
            end

            if editorOpen and captureRecord then
                if keyCode == Enum.KeyCode.Escape then
                    setEditorOpen(false)
                    return
                end

                if keyCode == Enum.KeyCode.Backspace or keyCode == Enum.KeyCode.Delete then
                    setRecordBind(captureRecord, nil, true)
                    setEditorOpen(false)
                    return
                end

                if setRecordBind(captureRecord, keyCode, true) then
                    setEditorOpen(false)
                end
                return
            end

            if gpe or not isRuntimeEnabled() then
                return
            end
            if UserInputService:GetFocusedTextBox() ~= nil then
                return
            end

            local bucket = recordsByKey[keyCode]
            if type(bucket) ~= "table" or #bucket == 0 then
                return
            end

            local snapshot = {}
            for _, entry in ipairs(bucket) do
                table.insert(snapshot, entry)
            end
            for _, record in ipairs(snapshot) do
                local control = record and record.Control
                if control and not control._destroyed and not control.Disabled then
                    local currentState = nil
                    if type(control.Get) == "function" then
                        local ok, value = pcall(control.Get, control)
                        if ok then
                            currentState = value
                        end
                    else
                        currentState = control.Value
                    end

                    if type(currentState) == "boolean" and type(control.Set) == "function" then
                        pcall(control.Set, control, not currentState)
                    end
                else
                    manager:DetachControl(control)
                end
            end

            refreshListPanel()
        end), "ToggleKeybindWidgets")

        refreshListPanel()
        return manager
    end
end
