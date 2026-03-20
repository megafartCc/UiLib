return function(Library, context)
    local UserInputService = context.UserInputService
    local RunService = context.RunService

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
            local lower = keyCode.Name:lower()
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
        local screenGui = opts.screenGui
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
        local getWindowRect = opts.getWindowRect or function()
            return main.AbsolutePosition, main.AbsoluteSize
        end

        local recordsByControl = {}
        local orderedRecords = {}
        local recordsByKey = {}
        local holdActive = {}
        local showList = true
        local captureRecord = nil
        local editorOpen = false
        local captureKeyFromNextInput = false

        local manager = {}

        local listPanel = Instance.new("Frame", screenGui or main)
        listPanel.Name = "KeybindsPanel"
        listPanel.Size = UDim2.fromOffset(230, 0)
        listPanel.Position = UDim2.fromOffset(0, 0)
        listPanel.BackgroundColor3 = Color3.fromRGB(22, 22, 22)
        listPanel.BorderSizePixel = 0
        listPanel.ClipsDescendants = true
        listPanel.Visible = false
        listPanel.ZIndex = 120
        Instance.new("UICorner", listPanel).CornerRadius = UDim.new(0, 5)
        local listPanelStroke = Instance.new("UIStroke", listPanel)
        listPanelStroke.Color = colors.Line
        listPanelStroke.Transparency = 0.35

        local listHeader = Instance.new("TextLabel", listPanel)
        listHeader.BackgroundTransparency = 1
        listHeader.Position = UDim2.new(0, 8, 0, 6)
        listHeader.Size = UDim2.new(1, -16, 0, 14)
        listHeader.Font = config.Font
        listHeader.Text = "KEYBINDS"
        listHeader.TextColor3 = colors.TextStrong
        listHeader.TextSize = 12
        listHeader.TextXAlignment = Enum.TextXAlignment.Left
        listHeader.ZIndex = 121

        local listSep = Instance.new("Frame", listPanel)
        listSep.BackgroundColor3 = colors.Line
        listSep.BorderSizePixel = 0
        listSep.Position = UDim2.new(0, 8, 0, 22)
        listSep.Size = UDim2.new(1, -16, 0, 1)
        listSep.ZIndex = 121

        local listBody = Instance.new("Frame", listPanel)
        listBody.BackgroundTransparency = 1
        listBody.Position = UDim2.new(0, 8, 0, 26)
        listBody.Size = UDim2.new(1, -16, 0, 0)
        listBody.ZIndex = 121

        local listLayout = Instance.new("UIListLayout", listBody)
        listLayout.SortOrder = Enum.SortOrder.LayoutOrder
        listLayout.Padding = UDim.new(0, 4)

        bindTheme(listPanel, "BackgroundColor3", "Panel")
        bindTheme(listPanel, "BackgroundTransparency", "PanelTransparency")
        bindTheme(listPanelStroke, "Color", "Line")
        bindTheme(listHeader, "TextColor3", "TextStrong")
        bindTheme(listSep, "BackgroundColor3", "Line")

        win._floatingPanels[listPanel] = { Active = false }

        local editorWidth = 230
        local editorHeight = 124
        local editor = Instance.new("Frame", clipFrame)
        editor.Name = "KeybindEditor"
        editor.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
        editor.BorderSizePixel = 0
        editor.Size = UDim2.fromOffset(editorWidth, 0)
        editor.Visible = false
        editor.ClipsDescendants = true
        editor.ZIndex = 170
        Instance.new("UICorner", editor).CornerRadius = UDim.new(0, 4)
        local editorStroke = Instance.new("UIStroke", editor)
        editorStroke.Color = colors.Line
        editorStroke.Transparency = 1

        local editorTitle = Instance.new("TextLabel", editor)
        editorTitle.BackgroundTransparency = 1
        editorTitle.Position = UDim2.new(0, 8, 0, 6)
        editorTitle.Size = UDim2.new(1, -16, 0, 14)
        editorTitle.Font = config.Font
        editorTitle.Text = "KEYBIND"
        editorTitle.TextColor3 = colors.TextStrong
        editorTitle.TextSize = 11
        editorTitle.TextXAlignment = Enum.TextXAlignment.Left
        editorTitle.ZIndex = 171

        local editorTarget = Instance.new("TextLabel", editor)
        editorTarget.BackgroundTransparency = 1
        editorTarget.Position = UDim2.new(0, 8, 0, 20)
        editorTarget.Size = UDim2.new(1, -16, 0, 14)
        editorTarget.Font = config.FontMedium
        editorTarget.Text = "Toggle"
        editorTarget.TextColor3 = colors.TextDim
        editorTarget.TextSize = 10
        editorTarget.TextXAlignment = Enum.TextXAlignment.Left
        editorTarget.ZIndex = 171

        local keyRowLabel = Instance.new("TextLabel", editor)
        keyRowLabel.BackgroundTransparency = 1
        keyRowLabel.Position = UDim2.new(0, 8, 0, 38)
        keyRowLabel.Size = UDim2.new(0.3, 0, 0, 16)
        keyRowLabel.Font = config.FontMedium
        keyRowLabel.Text = "Key"
        keyRowLabel.TextColor3 = colors.Text
        keyRowLabel.TextSize = 10
        keyRowLabel.TextXAlignment = Enum.TextXAlignment.Left
        keyRowLabel.ZIndex = 171

        local keyCaptureBtn = Instance.new("TextButton", editor)
        keyCaptureBtn.AnchorPoint = Vector2.new(1, 0)
        keyCaptureBtn.Position = UDim2.new(1, -8, 0, 38)
        keyCaptureBtn.Size = UDim2.new(0.68, 0, 0, 18)
        keyCaptureBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
        keyCaptureBtn.BorderSizePixel = 0
        keyCaptureBtn.Font = config.FontMedium
        keyCaptureBtn.Text = ""
        keyCaptureBtn.TextColor3 = colors.TextStrong
        keyCaptureBtn.TextSize = 10
        keyCaptureBtn.AutoButtonColor = false
        keyCaptureBtn.Selectable = false
        keyCaptureBtn.ZIndex = 172
        Instance.new("UICorner", keyCaptureBtn).CornerRadius = UDim.new(0, 3)

        local keyCaptureText = Instance.new("TextLabel", keyCaptureBtn)
        keyCaptureText.BackgroundTransparency = 1
        keyCaptureText.Position = UDim2.new(0, 6, 0, 0)
        keyCaptureText.Size = UDim2.new(1, -12, 1, 0)
        keyCaptureText.Font = config.FontMedium
        keyCaptureText.Text = "None"
        keyCaptureText.TextColor3 = colors.TextStrong
        keyCaptureText.TextSize = 10
        keyCaptureText.TextXAlignment = Enum.TextXAlignment.Left
        keyCaptureText.ZIndex = 173

        local modeLabel = Instance.new("TextLabel", editor)
        modeLabel.BackgroundTransparency = 1
        modeLabel.Position = UDim2.new(0, 8, 0, 62)
        modeLabel.Size = UDim2.new(0.3, 0, 0, 16)
        modeLabel.Font = config.FontMedium
        modeLabel.Text = "Mode"
        modeLabel.TextColor3 = colors.Text
        modeLabel.TextSize = 10
        modeLabel.TextXAlignment = Enum.TextXAlignment.Left
        modeLabel.ZIndex = 171

        local toggleModeBtn = Instance.new("TextButton", editor)
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

        local holdModeBtn = Instance.new("TextButton", editor)
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

        local clearBtn = Instance.new("TextButton", editor)
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

        local editorHint = Instance.new("TextLabel", editor)
        editorHint.BackgroundTransparency = 1
        editorHint.Position = UDim2.new(0, 8, 0, 108)
        editorHint.Size = UDim2.new(1, -16, 0, 14)
        editorHint.Font = config.FontMedium
        editorHint.Text = "Click key field, then press key."
        editorHint.TextColor3 = colors.TextDim
        editorHint.TextSize = 10
        editorHint.TextXAlignment = Enum.TextXAlignment.Left
        editorHint.ZIndex = 171

        bindTheme(editor, "BackgroundColor3", "Panel")
        bindTheme(editor, "BackgroundTransparency", "PanelTransparency")
        bindTheme(editorStroke, "Color", "Line")
        bindTheme(editorTitle, "TextColor3", "TextStrong")
        bindTheme(editorTarget, "TextColor3", "TextDim")
        bindTheme(keyRowLabel, "TextColor3", "Text")
        bindTheme(modeLabel, "TextColor3", "Text")
        bindTheme(keyCaptureBtn, "BackgroundColor3", "ControlAlt")
        bindTheme(keyCaptureBtn, "BackgroundTransparency", "ControlTransparency")
        bindTheme(keyCaptureText, "TextColor3", "TextStrong")
        bindTheme(toggleModeBtn, "BackgroundColor3", "Control")
        bindTheme(toggleModeBtn, "BackgroundTransparency", "ControlTransparency")
        bindTheme(toggleModeBtn, "TextColor3", "TextStrong")
        bindTheme(holdModeBtn, "BackgroundColor3", "Control")
        bindTheme(holdModeBtn, "BackgroundTransparency", "ControlTransparency")
        bindTheme(holdModeBtn, "TextColor3", "TextStrong")
        bindTheme(clearBtn, "BackgroundColor3", "Control")
        bindTheme(clearBtn, "BackgroundTransparency", "ControlTransparency")
        bindTheme(clearBtn, "TextColor3", "TextStrong")
        bindTheme(editorHint, "TextColor3", "TextDim")

        local editorPopupConfig = {
            ClosedSize = UDim2.fromOffset(editorWidth, 0),
            OpenSize = UDim2.fromOffset(editorWidth, editorHeight),
            OpenToken = "Open",
            CloseToken = "Close",
            HideDelay = 0.2,
        }

        local function setModeButtonsVisual(mode)
            local isHold = mode == "hold"
            Library:Animate(toggleModeBtn, "Hover", {
                BackgroundColor3 = isHold and colors.Control or colors.Main,
                BackgroundTransparency = isHold and (colors.ControlTransparency or 0) or (colors.AccentTransparency or 0),
            })
            Library:Animate(holdModeBtn, "Hover", {
                BackgroundColor3 = isHold and colors.Main or colors.Control,
                BackgroundTransparency = isHold and (colors.AccentTransparency or 0) or (colors.ControlTransparency or 0),
            })
        end

        local function setEditorOpen(nextOpen)
            if editorOpen == nextOpen then
                return
            end
            editorOpen = nextOpen
            if not editorOpen then
                captureRecord = nil
                captureKeyFromNextInput = false
            end
            if setPopupOpen then
                setPopupOpen(editor, editorOpen, editorPopupConfig)
            else
                editor.Visible = editorOpen
                editor.Size = editorOpen and editorPopupConfig.OpenSize or editorPopupConfig.ClosedSize
            end
        end

        local function positionEditor(mousePos)
            local clipPos = clipFrame.AbsolutePosition
            local clipSize = clipFrame.AbsoluteSize
            local x = math.clamp(mousePos.X - clipPos.X + 6, 4, math.max(4, clipSize.X - editorWidth - 4))
            local y = math.clamp(mousePos.Y - clipPos.Y + 6, 4, math.max(4, clipSize.Y - editorHeight - 4))
            editor.Position = UDim2.fromOffset(x, y)
        end

        local function detachFromKey(record)
            local keyCode = record and record.KeyCode
            if not keyCode then
                return
            end

            local bucket = recordsByKey[keyCode]
            if bucket then
                for i = #bucket, 1, -1 do
                    if bucket[i] == record then
                        table.remove(bucket, i)
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

        local function refreshListPanel()
            for _, child in ipairs(listBody:GetChildren()) do
                if child:IsA("GuiObject") then
                    child:Destroy()
                end
            end

            local rows = {}
            for _, record in ipairs(orderedRecords) do
                if isRecordAlive(record) and record.KeyCode then
                    table.insert(rows, record)
                end
            end

            local visibleCount = math.min(#rows, 10)
            for i = 1, visibleCount do
                local record = rows[i]
                local row = Instance.new("TextLabel", listBody)
                row.BackgroundTransparency = 1
                row.Size = UDim2.new(1, 0, 0, 14)
                row.LayoutOrder = i
                row.Font = config.FontMedium
                row.Text = ("[%s] %s (%s)"):format(record.KeyCode.Name, record.Name, record.Mode == "hold" and "HOLD" or "TOGGLE")
                row.TextColor3 = colors.Text
                row.TextSize = 10
                row.TextXAlignment = Enum.TextXAlignment.Left
                row.ZIndex = 121
                bindTheme(row, "TextColor3", "Text")
            end

            local hasRows = #rows > 0
            local targetHeight = hasRows and (30 + (visibleCount * 18)) or 0
            listPanel.Size = UDim2.fromOffset(230, targetHeight)
            listBody.Size = UDim2.new(1, -16, 0, math.max(0, targetHeight - 30))

            local panelState = win._floatingPanels[listPanel]
            if panelState then
                panelState.Active = showList and hasRows
            end
            syncFloatingPanels()
        end

        local function removeRecordFromOrdered(record)
            for i = #orderedRecords, 1, -1 do
                if orderedRecords[i] == record then
                    table.remove(orderedRecords, i)
                    break
                end
            end
        end

        local function setRecordKey(record, value, shouldMarkDirty)
            local keyCode = toKeyCode(value)
            if value == nil or value == false or value == "" then
                keyCode = nil
            end

            if keyCode and type(getReservedKey) == "function" then
                local reserved = getReservedKey()
                if reserved and reserved == keyCode then
                    editorHint.Text = ("'%s' is reserved by UI toggle."):format(keyCode.Name)
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
            record.Mode = toMode(mode)
            if shouldMarkDirty then
                Library:_markDirty()
            end
            setModeButtonsVisual(record.Mode)
            refreshListPanel()
        end

        local function applyEditorRecord()
            if not captureRecord then
                return
            end
            editorTarget.Text = captureRecord.Name
            keyCaptureText.Text = captureRecord.KeyCode and captureRecord.KeyCode.Name or "None"
            setModeButtonsVisual(captureRecord.Mode or "toggle")
            editorHint.Text = "Click key field, then press key."
        end

        registerTransientPopup(editor, function()
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
                    return { editor }
                end,
            })
        end

        function manager:SetControlKeybind(control, value, shouldMarkDirty)
            local record = recordsByControl[control]
            if not record then
                return false
            end
            local keyValue, modeValue = value, nil
            if type(value) == "table" then
                keyValue = value.key or value.Key
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
                captureKeyFromNextInput = false
            end
            recordsByControl[control] = nil
            holdActive[record] = nil
            detachFromKey(record)
            removeRecordFromOrdered(record)
            refreshListPanel()
        end

        function manager:AttachToggle(control, meta)
            if not control or recordsByControl[control] then
                return
            end
            meta = meta or {}
            local record = {
                Control = control,
                ConfigKey = meta.ConfigKey,
                Name = tostring(meta.Name or "Toggle"),
                Mode = "toggle",
                KeyCode = nil,
            }
            recordsByControl[control] = record
            table.insert(orderedRecords, record)

            local targets = meta.Targets
            if type(targets) == "table" then
                for _, target in ipairs(targets) do
                    if target and target:IsA("GuiButton") then
                        control:TrackConnection(target.MouseButton2Click:Connect(function()
                            if control.Disabled or not isRuntimeEnabled() then
                                return
                            end
                            captureRecord = record
                            applyEditorRecord()
                            positionEditor(UserInputService:GetMouseLocation())
                            closeTransientPopups(editor)
                            setEditorOpen(true)
                        end))
                    end
                end
            end

            if control._root then
                control:TrackConnection(control._root.AncestryChanged:Connect(function(_, parent)
                    if parent == nil then
                        manager:DetachControl(control)
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

        keyCaptureBtn.Activated:Connect(function()
            if not captureRecord then
                return
            end
            captureKeyFromNextInput = true
            keyCaptureText.Text = "Press key..."
            editorHint.Text = "Waiting for key input..."
        end)

        clearBtn.Activated:Connect(function()
            if not captureRecord then
                return
            end
            setRecordKey(captureRecord, nil, true)
            applyEditorRecord()
        end)

        toggleModeBtn.Activated:Connect(function()
            if captureRecord then
                setRecordMode(captureRecord, "toggle", true)
                applyEditorRecord()
            end
        end)

        holdModeBtn.Activated:Connect(function()
            if captureRecord then
                setRecordMode(captureRecord, "hold", true)
                applyEditorRecord()
            end
        end)

        trackGlobal(UserInputService.InputBegan:Connect(function(input, gpe)
            if input.UserInputType ~= Enum.UserInputType.Keyboard then
                return
            end

            local keyCode = input.KeyCode
            if keyCode == Enum.KeyCode.Unknown then
                return
            end

            if editorOpen and captureRecord and captureKeyFromNextInput then
                captureKeyFromNextInput = false
                if keyCode == Enum.KeyCode.Escape then
                    applyEditorRecord()
                    return
                end
                if keyCode == Enum.KeyCode.Backspace or keyCode == Enum.KeyCode.Delete then
                    setRecordKey(captureRecord, nil, true)
                    applyEditorRecord()
                    return
                end
                if setRecordKey(captureRecord, keyCode, true) then
                    applyEditorRecord()
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
            if type(bucket) ~= "table" then
                return
            end

            local snapshot = {}
            for _, record in ipairs(bucket) do
                table.insert(snapshot, record)
            end

            for _, record in ipairs(snapshot) do
                if not isRecordAlive(record) then
                    manager:DetachControl(record.Control)
                else
                    local control = record.Control
                    if control and not control.Disabled and type(control.Set) == "function" then
                        local mode = record.Mode or "toggle"
                        if mode == "hold" then
                            holdActive[record] = true
                            pcall(control.Set, control, true)
                        else
                            local current = false
                            if type(control.Get) == "function" then
                                local ok, value = pcall(control.Get, control)
                                if ok and type(value) == "boolean" then
                                    current = value
                                end
                            end
                            pcall(control.Set, control, not current)
                        end
                    end
                end
            end

            refreshListPanel()
        end), "ToggleKeybindWidgetsBegan")

        trackGlobal(UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.Keyboard then
                return
            end
            if not isRuntimeEnabled() then
                return
            end
            local keyCode = input.KeyCode
            local bucket = recordsByKey[keyCode]
            if type(bucket) ~= "table" then
                return
            end

            local snapshot = {}
            for _, record in ipairs(bucket) do
                table.insert(snapshot, record)
            end

            for _, record in ipairs(snapshot) do
                if not isRecordAlive(record) then
                    manager:DetachControl(record.Control)
                elseif record.Mode == "hold" and holdActive[record] then
                    holdActive[record] = nil
                    local control = record.Control
                    if control and not control.Disabled and type(control.Set) == "function" then
                        pcall(control.Set, control, false)
                    end
                end
            end
        end), "ToggleKeybindWidgetsEnded")

        trackGlobal(RunService.RenderStepped:Connect(function()
            if not listPanel.Visible then
                return
            end
            local windowPos, windowSize = getWindowRect()
            if not windowPos or not windowSize then
                return
            end

            local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
            local x = windowPos.X + windowSize.X + 12
            local y = windowPos.Y + 8
            if x + 230 > viewport.X - 8 then
                x = windowPos.X - 230 - 12
            end
            x = math.clamp(x, 8, math.max(8, viewport.X - 238))
            y = math.clamp(y, 8, math.max(8, viewport.Y - math.max(40, listPanel.AbsoluteSize.Y + 8)))
            listPanel.Position = UDim2.fromOffset(x, y)
        end), "KeybindPanelReposition")

        refreshListPanel()
        return manager
    end
end
