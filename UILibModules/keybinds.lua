return function(Library, context)
    local UserInputService = context.UserInputService

    local keyLookup = nil
    local digitAliases = {
        ["0"] = "Zero",
        ["1"] = "One",
        ["2"] = "Two",
        ["3"] = "Three",
        ["4"] = "Four",
        ["5"] = "Five",
        ["6"] = "Six",
        ["7"] = "Seven",
        ["8"] = "Eight",
        ["9"] = "Nine",
    }

    local function buildKeyLookup()
        if keyLookup then
            return
        end

        keyLookup = {}
        for _, keyCode in ipairs(Enum.KeyCode:GetEnumItems()) do
            local name = keyCode.Name
            local lower = name:lower()
            keyLookup[lower] = keyCode
            keyLookup[lower:gsub("[%s_%-%p]", "")] = keyCode
        end
    end

    local function toKeyCode(value)
        if typeof(value) == "EnumItem" and value.EnumType == Enum.KeyCode then
            return value
        end

        if type(value) ~= "string" then
            return nil
        end

        local trimmed = value:gsub("^%s+", ""):gsub("%s+$", "")
        if trimmed == "" then
            return nil
        end

        buildKeyLookup()

        local lower = trimmed:lower()
        local direct = keyLookup[lower] or keyLookup[lower:gsub("[%s_%-%p]", "")]
        if direct then
            return direct
        end

        if #trimmed == 1 then
            local upper = trimmed:upper()
            if upper:match("[A-Z]") then
                return Enum.KeyCode[upper]
            end
            local alias = digitAliases[upper]
            if alias then
                return Enum.KeyCode[alias]
            end
        end

        return nil
    end

    local function toMode(value)
        if type(value) == "string" and value:lower() == "hold" then
            return "hold"
        end
        return "toggle"
    end

    local function isRecordAlive(record)
        if type(record) ~= "table" then
            return false
        end

        local control = record.Control
        if type(control) ~= "table" or control._destroyed then
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
        local holdActive = {}
        local showList = true
        local captureRecord = nil
        local editorOpen = false

        local manager = {}

        local function removeRecordFromOrdered(record)
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
            if bucket then
                for index = #bucket, 1, -1 do
                    if bucket[index] == record then
                        table.remove(bucket, index)
                    end
                end
                if #bucket == 0 then
                    recordsByKey[keyCode] = nil
                end
            end

            record.KeyCode = nil
            holdActive[record] = nil
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

        local keybindsPanel = Instance.new("Frame", main)
        keybindsPanel.Name = "KeybindsPanel"
        keybindsPanel.AnchorPoint = Vector2.new(0, 0)
        keybindsPanel.Position = UDim2.new(0, 8, 0, (config.HeaderHeight or 40) + 8)
        keybindsPanel.Size = UDim2.fromOffset(220, 0)
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

        local editorWidth = 220
        local editorOpenHeight = 126
        local bindEditor = Instance.new("Frame", clipFrame)
        bindEditor.Name = "KeybindEditor"
        bindEditor.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
        bindEditor.BorderSizePixel = 0
        bindEditor.Size = UDim2.fromOffset(editorWidth, 0)
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
        bindEditorTitle.Text = "Keybind"
        bindEditorTitle.TextColor3 = colors.TextStrong
        bindEditorTitle.TextSize = 11
        bindEditorTitle.TextXAlignment = Enum.TextXAlignment.Left
        bindEditorTitle.ZIndex = 171

        local bindEditorTarget = Instance.new("TextLabel", bindEditor)
        bindEditorTarget.BackgroundTransparency = 1
        bindEditorTarget.Position = UDim2.new(0, 8, 0, 20)
        bindEditorTarget.Size = UDim2.new(1, -16, 0, 14)
        bindEditorTarget.Font = config.FontMedium
        bindEditorTarget.Text = "Toggle"
        bindEditorTarget.TextColor3 = colors.TextDim
        bindEditorTarget.TextSize = 10
        bindEditorTarget.TextXAlignment = Enum.TextXAlignment.Left
        bindEditorTarget.ZIndex = 171

        local keyLabel = Instance.new("TextLabel", bindEditor)
        keyLabel.BackgroundTransparency = 1
        keyLabel.Position = UDim2.new(0, 8, 0, 38)
        keyLabel.Size = UDim2.new(0.3, 0, 0, 16)
        keyLabel.Font = config.FontMedium
        keyLabel.Text = "Key"
        keyLabel.TextColor3 = colors.Text
        keyLabel.TextSize = 10
        keyLabel.TextXAlignment = Enum.TextXAlignment.Left
        keyLabel.ZIndex = 171

        local keyInput = Instance.new("TextBox", bindEditor)
        keyInput.AnchorPoint = Vector2.new(1, 0)
        keyInput.Position = UDim2.new(1, -8, 0, 38)
        keyInput.Size = UDim2.new(0.68, 0, 0, 18)
        keyInput.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
        keyInput.BorderSizePixel = 0
        keyInput.Font = config.FontMedium
        keyInput.Text = ""
        keyInput.TextColor3 = colors.TextStrong
        keyInput.TextSize = 10
        keyInput.PlaceholderText = "Press or type key"
        keyInput.ClearTextOnFocus = false
        keyInput.TextXAlignment = Enum.TextXAlignment.Left
        keyInput.ZIndex = 172
        Instance.new("UICorner", keyInput).CornerRadius = UDim.new(0, 3)
        local keyInputStroke = Instance.new("UIStroke", keyInput)
        keyInputStroke.Color = colors.Line
        keyInputStroke.Transparency = 0.45

        local modeLabel = Instance.new("TextLabel", bindEditor)
        modeLabel.BackgroundTransparency = 1
        modeLabel.Position = UDim2.new(0, 8, 0, 62)
        modeLabel.Size = UDim2.new(0.3, 0, 0, 16)
        modeLabel.Font = config.FontMedium
        modeLabel.Text = "Mode"
        modeLabel.TextColor3 = colors.Text
        modeLabel.TextSize = 10
        modeLabel.TextXAlignment = Enum.TextXAlignment.Left
        modeLabel.ZIndex = 171

        local toggleModeBtn = Instance.new("TextButton", bindEditor)
        toggleModeBtn.AnchorPoint = Vector2.new(1, 0)
        toggleModeBtn.Position = UDim2.new(1, -79, 0, 62)
        toggleModeBtn.Size = UDim2.new(0, 67, 0, 18)
        toggleModeBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
        toggleModeBtn.BorderSizePixel = 0
        toggleModeBtn.Font = config.FontMedium
        toggleModeBtn.Text = "Toggle"
        toggleModeBtn.TextColor3 = colors.TextStrong
        toggleModeBtn.TextSize = 10
        toggleModeBtn.ZIndex = 172
        toggleModeBtn.AutoButtonColor = false
        toggleModeBtn.Selectable = false
        Instance.new("UICorner", toggleModeBtn).CornerRadius = UDim.new(0, 3)

        local holdModeBtn = Instance.new("TextButton", bindEditor)
        holdModeBtn.AnchorPoint = Vector2.new(1, 0)
        holdModeBtn.Position = UDim2.new(1, -8, 0, 62)
        holdModeBtn.Size = UDim2.new(0, 67, 0, 18)
        holdModeBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
        holdModeBtn.BorderSizePixel = 0
        holdModeBtn.Font = config.FontMedium
        holdModeBtn.Text = "Hold"
        holdModeBtn.TextColor3 = colors.TextStrong
        holdModeBtn.TextSize = 10
        holdModeBtn.ZIndex = 172
        holdModeBtn.AutoButtonColor = false
        holdModeBtn.Selectable = false
        Instance.new("UICorner", holdModeBtn).CornerRadius = UDim.new(0, 3)

        local clearBtn = Instance.new("TextButton", bindEditor)
        clearBtn.Position = UDim2.new(0, 8, 0, 86)
        clearBtn.Size = UDim2.new(1, -16, 0, 18)
        clearBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
        clearBtn.BorderSizePixel = 0
        clearBtn.Font = config.FontMedium
        clearBtn.Text = "Clear Keybind"
        clearBtn.TextColor3 = colors.TextStrong
        clearBtn.TextSize = 10
        clearBtn.ZIndex = 172
        clearBtn.AutoButtonColor = false
        clearBtn.Selectable = false
        Instance.new("UICorner", clearBtn).CornerRadius = UDim.new(0, 3)

        local bindEditorHint = Instance.new("TextLabel", bindEditor)
        bindEditorHint.BackgroundTransparency = 1
        bindEditorHint.Position = UDim2.new(0, 8, 0, 108)
        bindEditorHint.Size = UDim2.new(1, -16, 0, 14)
        bindEditorHint.Font = config.FontMedium
        bindEditorHint.Text = "Right click toggle opens this panel."
        bindEditorHint.TextColor3 = colors.TextDim
        bindEditorHint.TextSize = 10
        bindEditorHint.TextXAlignment = Enum.TextXAlignment.Left
        bindEditorHint.ZIndex = 171

        bindTheme(bindEditor, "BackgroundColor3", "Panel")
        bindTheme(bindEditor, "BackgroundTransparency", "PanelTransparency")
        bindTheme(bindEditorStroke, "Color", "Line")
        bindTheme(bindEditorTitle, "TextColor3", "TextStrong")
        bindTheme(bindEditorTarget, "TextColor3", "TextDim")
        bindTheme(keyLabel, "TextColor3", "Text")
        bindTheme(modeLabel, "TextColor3", "Text")
        bindTheme(keyInput, "BackgroundColor3", "ControlAlt")
        bindTheme(keyInput, "BackgroundTransparency", "ControlTransparency")
        bindTheme(keyInput, "TextColor3", "TextStrong")
        bindTheme(keyInput, "PlaceholderColor3", "TextMuted")
        bindTheme(keyInputStroke, "Color", "Line")
        bindTheme(clearBtn, "BackgroundColor3", "Control")
        bindTheme(clearBtn, "BackgroundTransparency", "ControlTransparency")
        bindTheme(clearBtn, "TextColor3", "TextStrong")
        bindTheme(bindEditorHint, "TextColor3", "TextDim")

        local editorPopupConfig = {
            ClosedSize = UDim2.fromOffset(editorWidth, 0),
            OpenSize = UDim2.fromOffset(editorWidth, editorOpenHeight),
            OpenToken = "Open",
            CloseToken = "Close",
            HideDelay = 0.2,
        }

        local function setModeButtonsVisual(mode)
            local toggleActive = mode ~= "hold"
            local holdActiveMode = mode == "hold"
            Library:Animate(toggleModeBtn, "Hover", {
                BackgroundColor3 = toggleActive and colors.Main or colors.Control,
                BackgroundTransparency = toggleActive and (colors.AccentTransparency or 0) or (colors.ControlTransparency or 0),
            })
            Library:Animate(holdModeBtn, "Hover", {
                BackgroundColor3 = holdActiveMode and colors.Main or colors.Control,
                BackgroundTransparency = holdActiveMode and (colors.AccentTransparency or 0) or (colors.ControlTransparency or 0),
            })
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

        local function positionEditor(anchorPos)
            local clipPos = clipFrame.AbsolutePosition
            local clipSize = clipFrame.AbsoluteSize
            local x = math.clamp(anchorPos.X - clipPos.X + 6, 4, math.max(4, clipSize.X - editorWidth - 4))
            local y = math.clamp(anchorPos.Y - clipPos.Y + 6, 4, math.max(4, clipSize.Y - editorOpenHeight - 4))
            bindEditor.Position = UDim2.fromOffset(x, y)
        end

        local function applyEditorRecord()
            if not captureRecord then
                return
            end
            bindEditorTarget.Text = tostring(captureRecord.Name or "Toggle")
            keyInput.Text = captureRecord.KeyCode and captureRecord.KeyCode.Name or ""
            setModeButtonsVisual(captureRecord.Mode or "toggle")
            bindEditorHint.Text = "Press key while key field is focused."
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

        local function pruneRecords()
            for index = #orderedRecords, 1, -1 do
                local record = orderedRecords[index]
                if not isRecordAlive(record) then
                    manager:DetachControl(record and record.Control)
                end
            end
        end

        local function refreshListPanel()
            pruneRecords()
            for _, child in ipairs(keybindsList:GetChildren()) do
                if child:IsA("GuiObject") then
                    child:Destroy()
                end
            end

            local rows = {}
            for _, record in ipairs(orderedRecords) do
                if record.KeyCode then
                    table.insert(rows, record)
                end
            end

            local visibleCount = math.min(#rows, 10)
            for index = 1, visibleCount do
                local record = rows[index]
                local row = Instance.new("TextLabel", keybindsList)
                row.BackgroundTransparency = 1
                row.Size = UDim2.new(1, 0, 0, 14)
                row.LayoutOrder = index
                row.Font = config.FontMedium
                row.Text = ("[%s] %s (%s)"):format(record.KeyCode.Name, tostring(record.Name), record.Mode == "hold" and "HOLD" or "TOGGLE")
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
            keybindsPanel.Size = UDim2.fromOffset(220, targetHeight)
            keybindsList.Size = UDim2.new(1, -16, 0, math.max(0, targetHeight - 30))

            local panelState = win._floatingPanels[keybindsPanel]
            if panelState then
                panelState.Active = showList and hasRows
            end
            syncFloatingPanels()
        end

        local function setRecordKey(record, value, shouldMarkDirty)
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

        local function setRecordMode(record, mode, shouldMarkDirty)
            if type(record) ~= "table" then
                return false
            end

            record.Mode = toMode(mode)
            if shouldMarkDirty then
                Library:_markDirty()
            end
            if captureRecord == record then
                setModeButtonsVisual(record.Mode)
            end
            refreshListPanel()
            return true
        end

        function manager:SetControlKeybind(control, value, shouldMarkDirty)
            local record = recordsByControl[control]
            if not record then
                return false
            end

            local keyValue = value
            local modeValue = nil
            if type(value) == "table" then
                keyValue = value.key or value.Key or value.value or value.Value
                modeValue = value.mode or value.Mode
            end

            local ok = setRecordKey(record, keyValue, shouldMarkDirty == true)
            if modeValue ~= nil then
                setRecordMode(record, modeValue, shouldMarkDirty == true)
            end
            return ok
        end

        function manager:GetControlKeybind(control)
            local record = recordsByControl[control]
            if not record then
                return nil
            end
            return {
                key = record.KeyCode and record.KeyCode.Name or nil,
                mode = record.Mode or "toggle",
            }
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

        function manager:DetachControl(control)
            local record = recordsByControl[control]
            if not record then
                return
            end

            if captureRecord == record then
                captureRecord = nil
            end

            recordsByControl[control] = nil
            holdActive[record] = nil
            detachFromKey(record)
            removeRecordFromOrdered(record)
        end

        local function openEditorForRecord(record)
            if not isRecordAlive(record) then
                return
            end
            if record.Control.Disabled then
                return
            end
            if not isRuntimeEnabled() then
                return
            end

            captureRecord = record
            applyEditorRecord()
            positionEditor(UserInputService:GetMouseLocation())
            closeTransientPopups(bindEditor)
            setEditorOpen(true)
        end

        function manager:AttachToggle(control, meta)
            if not control or recordsByControl[control] then
                return
            end

            meta = meta or {}
            local record = {
                Control = control,
                ConfigKey = meta.ConfigKey,
                KeyCode = nil,
                Mode = "toggle",
                Name = tostring(meta.Name or "Toggle"),
            }

            recordsByControl[control] = record
            table.insert(orderedRecords, record)

            local targets = meta.Targets
            if type(targets) == "table" then
                for _, target in ipairs(targets) do
                    if target and target:IsA("GuiButton") then
                        control:TrackConnection(target.MouseButton2Click:Connect(function()
                            openEditorForRecord(record)
                        end))
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
                        if not current then
                            return nil
                        end
                        return {
                            key = current.KeyCode and current.KeyCode.Name or nil,
                            mode = current.Mode or "toggle",
                        }
                    end,
                    function(value)
                        manager:SetControlKeybind(control, value, false)
                    end
                )
            end

            refreshListPanel()
        end

        local function applyTextInputKey()
            if not captureRecord then
                return
            end

            local raw = tostring(keyInput.Text or "")
            if raw == "" then
                setRecordKey(captureRecord, nil, true)
                applyEditorRecord()
                return
            end

            if setRecordKey(captureRecord, raw, true) then
                applyEditorRecord()
            else
                bindEditorHint.Text = "Invalid key."
            end
        end

        keyInput.Focused:Connect(function()
            bindEditorHint.Text = "Press a key now or type key name."
            Library:Animate(keyInputStroke, "Hover", { Color = colors.Main, Transparency = 0.2 })
        end)

        keyInput.FocusLost:Connect(function()
            Library:Animate(keyInputStroke, "Hover", { Color = colors.Line, Transparency = 0.45 })
            applyTextInputKey()
        end)

        clearBtn.Activated:Connect(function()
            if not captureRecord then
                return
            end
            setRecordKey(captureRecord, nil, true)
            applyEditorRecord()
        end)

        toggleModeBtn.Activated:Connect(function()
            if not captureRecord then
                return
            end
            setRecordMode(captureRecord, "toggle", true)
            applyEditorRecord()
        end)

        holdModeBtn.Activated:Connect(function()
            if not captureRecord then
                return
            end
            setRecordMode(captureRecord, "hold", true)
            applyEditorRecord()
        end)

        trackGlobal(UserInputService.InputBegan:Connect(function(input, gpe)
            if input.UserInputType ~= Enum.UserInputType.Keyboard then
                return
            end

            local keyCode = input.KeyCode
            if keyCode == Enum.KeyCode.Unknown then
                return
            end

            if editorOpen and captureRecord then
                local focused = UserInputService:GetFocusedTextBox()
                if focused == keyInput then
                    if keyCode == Enum.KeyCode.Escape then
                        setEditorOpen(false)
                        return
                    end
                    if keyCode == Enum.KeyCode.Backspace or keyCode == Enum.KeyCode.Delete then
                        keyInput.Text = ""
                        setRecordKey(captureRecord, nil, true)
                        applyEditorRecord()
                        return
                    end
                    if keyCode ~= Enum.KeyCode.Return and keyCode ~= Enum.KeyCode.KeypadEnter and keyCode ~= Enum.KeyCode.Tab then
                        if setRecordKey(captureRecord, keyCode, true) then
                            applyEditorRecord()
                        end
                        return
                    end
                elseif keyCode == Enum.KeyCode.Escape then
                    setEditorOpen(false)
                    return
                end
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
                if not isRecordAlive(record) then
                    manager:DetachControl(control)
                elseif control and not control.Disabled then
                    local mode = record.Mode or "toggle"
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
                        if mode == "hold" then
                            holdActive[record] = true
                            pcall(control.Set, control, true)
                        else
                            pcall(control.Set, control, not currentState)
                        end
                    end
                end
            end

            refreshListPanel()
        end), "ToggleKeybindWidgetsBegan")

        trackGlobal(UserInputService.InputEnded:Connect(function(input, gpe)
            if input.UserInputType ~= Enum.UserInputType.Keyboard then
                return
            end
            if gpe or not isRuntimeEnabled() then
                return
            end

            local keyCode = input.KeyCode
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
                if not isRecordAlive(record) then
                    manager:DetachControl(control)
                elseif record.Mode == "hold" and holdActive[record] and control and not control.Disabled then
                    holdActive[record] = nil
                    if type(control.Get) == "function" and type(control.Set) == "function" then
                        local ok, value = pcall(control.Get, control)
                        if ok and type(value) == "boolean" then
                            pcall(control.Set, control, false)
                        end
                    end
                end
            end
        end), "ToggleKeybindWidgetsEnded")

        refreshListPanel()

        return manager
    end
end
