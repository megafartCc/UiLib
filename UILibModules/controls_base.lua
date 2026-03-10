return function(Library, context)
    local Cleaner = context.Cleaner
    local TextService = context.TextService

    local function removeArrayValue(array, value)
        if type(array) ~= "table" then
            return
        end

        for index = #array, 1, -1 do
            if array[index] == value then
                table.remove(array, index)
                return
            end
        end
    end

    local function createRow(parent, name, opts)
        opts = opts or {}

        local row = Instance.new("Frame", parent)
        row.Name = name or "Row"
        row.BackgroundTransparency = 1
        row.BorderSizePixel = 0
        row.Size = opts.Size or UDim2.new(1, 0, 0, opts.Height or 22)
        row.ZIndex = opts.ZIndex or 5
        row.ClipsDescendants = opts.ClipsDescendants == true
        return row
    end

    local function createLabel(parent, text, opts)
        opts = opts or {}

        local label = Instance.new("TextLabel", parent)
        label.Name = opts.Name or "Label"
        label.BackgroundTransparency = 1
        label.Position = opts.Position or UDim2.new(0, 0, 0, 0)
        label.Size = opts.Size or UDim2.new(1, 0, 1, 0)
        label.Font = opts.Font
        label.Text = text or ""
        label.TextColor3 = opts.TextColor3
        label.TextSize = opts.TextSize or 12
        label.TextTransparency = opts.TextTransparency or 0
        label.TextXAlignment = opts.TextXAlignment or Enum.TextXAlignment.Left
        label.TextWrapped = false
        label.ZIndex = opts.ZIndex or 5
        return label
    end

    local function bindAdaptiveLabel(control, label, opts)
        opts = opts or {}
        if not label then
            return function() end
        end

        local baseTextSize = tonumber(opts.BaseTextSize or label.TextSize) or 12
        local minTextSize = tonumber(opts.MinTextSize or math.max(8, baseTextSize - 3)) or 9
        local widthPadding = tonumber(opts.WidthPadding or 0) or 0
        local getAvailableWidth = opts.GetAvailableWidth

        label.TextTruncate = opts.TextTruncate or Enum.TextTruncate.AtEnd
        label.TextWrapped = false

        local function refresh()
            if not label.Parent then
                return
            end

            local availableWidth = nil
            if type(getAvailableWidth) == "function" then
                local ok, value = pcall(getAvailableWidth)
                if ok and type(value) == "number" then
                    availableWidth = value
                end
            end
            if type(availableWidth) ~= "number" then
                availableWidth = label.AbsoluteSize.X - widthPadding
            end
            availableWidth = math.max(0, availableWidth or 0)
            if availableWidth <= 0 then
                return
            end

            local nextTextSize = baseTextSize
            if TextService then
                nextTextSize = minTextSize
                local text = tostring(label.Text or "")
                for size = baseTextSize, minTextSize, -1 do
                    local ok, bounds = pcall(function()
                        return TextService:GetTextSize(
                            text,
                            size,
                            label.Font,
                            Vector2.new(4096, math.max(12, label.AbsoluteSize.Y))
                        )
                    end)
                    if ok and bounds and bounds.X <= availableWidth then
                        nextTextSize = size
                        break
                    end
                end
            end

            label.TextSize = nextTextSize
        end

        local function track(signal, key)
            local conn = signal:Connect(refresh)
            if control and control.TrackConnection then
                control:TrackConnection(conn, key)
            end
        end

        track(label:GetPropertyChangedSignal("AbsoluteSize"), (label.Name or "Label") .. "_AdaptiveSize")
        track(label:GetPropertyChangedSignal("Text"), (label.Name or "Label") .. "_AdaptiveText")
        track(label:GetPropertyChangedSignal("Font"), (label.Name or "Label") .. "_AdaptiveFont")
        refresh()

        return refresh
    end

    local function createRightBox(parent, opts)
        opts = opts or {}

        local className = opts.ClassName or "Frame"
        local box = Instance.new(className, parent)
        box.Name = opts.Name or className
        box.AnchorPoint = Vector2.new(1, 0.5)
        box.Position = opts.Position or UDim2.new(1, opts.RightOffset or 0, 0.5, 0)
        box.Size = opts.Size or UDim2.new(0, opts.Width or 18, 0, opts.Height or 18)
        box.BackgroundColor3 = opts.BackgroundColor3 or Color3.fromRGB(35, 35, 35)
        box.BorderSizePixel = 0
        box.ZIndex = opts.ZIndex or 5
        box.ClipsDescendants = opts.ClipsDescendants == true

        if box:IsA("GuiButton") then
            box.Text = opts.Text or ""
            box.AutoButtonColor = false
            box.Selectable = false
        end

        Instance.new("UICorner", box).CornerRadius = UDim.new(0, opts.CornerRadius or 3)

        local stroke
        if opts.WithStroke ~= false then
            stroke = Instance.new("UIStroke", box)
            stroke.Color = opts.StrokeColor
            stroke.Transparency = opts.StrokeTransparency
        end

        return box, stroke
    end

    local function createOverlayButton(parent, opts)
        opts = opts or {}

        local button = Instance.new("TextButton", parent)
        button.Name = opts.Name or "Button"
        button.BackgroundTransparency = 1
        button.Size = opts.Size or UDim2.new(1, 0, 1, 0)
        button.Position = opts.Position or UDim2.new(0, 0, 0, 0)
        button.ZIndex = opts.ZIndex or 7
        button.Text = opts.Text or ""
        button.AutoButtonColor = false
        button.Selectable = false
        button.BorderSizePixel = 0
        return button
    end

    local function createCheckbox(parent, colors, opts)
        opts = opts or {}

        local frame, stroke = createRightBox(parent, {
            Name = opts.Name or "Check",
            Width = opts.Width or 18,
            Height = opts.Height or 18,
            ZIndex = opts.ZIndex or 5,
            BackgroundColor3 = opts.BackgroundColor3 or Color3.fromRGB(35, 35, 35),
            StrokeColor = opts.StrokeColor or colors.Line,
            StrokeTransparency = opts.StrokeTransparency or 0.5,
        })

        local icon = Instance.new("ImageLabel", frame)
        icon.Name = "Icon"
        icon.BackgroundTransparency = 1
        icon.AnchorPoint = Vector2.new(0.5, 0.5)
        icon.Position = UDim2.new(0.5, 0, 0.5, 0)
        icon.Size = UDim2.new(0, opts.IconWidth or 12, 0, opts.IconHeight or 12)
        icon.Image = opts.Image or "rbxassetid://122354904349171"
        icon.ImageColor3 = opts.ImageColor3 or colors.Main
        icon.ImageTransparency = opts.ImageTransparency or 1
        icon.ZIndex = (opts.ZIndex or 5) + 1

        return frame, stroke, icon
    end

    local function attachControlLifecycle(section, control, opts)
        opts = opts or {}
        local cleanup = Cleaner.new()
        local searchEntry
        local saveKey = opts.saveKey

        if section and section._cleanup then
            section._cleanup:Add(cleanup, "Cleanup")
        end

        if opts.root then
            cleanup:Add(opts.root, "Destroy", "Root")
        end

        if section and section._controls then
            table.insert(section._controls, control)
        end

        if opts.searchName and section and section._win and section._win._searchItems then
            searchEntry = {
                name = opts.searchName,
                menuName = section._menuName,
                secName = section._secName,
                menuRef = section._menu,
            }
            table.insert(section._win._searchItems, searchEntry)
        end

        control._cleanup = cleanup
        control._root = opts.root
        control.Visible = opts.root == nil or opts.root.Visible ~= false
        control.Disabled = false

        if type(saveKey) == "string" and saveKey ~= "" then
            Library._widgetRegistry = Library._widgetRegistry or {}
            Library._widgetRegistry[saveKey] = control
        end

        function control:TrackConnection(conn, key)
            return cleanup:Add(conn, "Disconnect", key)
        end

        function control:TrackInstance(instance, key)
            return cleanup:Add(instance, "Destroy", key)
        end

        function control:Get()
            if opts.getValue then
                return opts.getValue()
            end
            return rawget(self, "Value")
        end

        function control:GetValue()
            return self:Get()
        end

        function control:GetState()
            return self:Get()
        end

        function control:Set(value, setOptions)
            if opts.setValue then
                local suppressCallbacks = not (type(setOptions) == "table" and setOptions.fireCallbacks == true)
                if suppressCallbacks and type(Library._beginControlSync) == "function" then
                    Library:_beginControlSync()
                end
                local ok, err = pcall(opts.setValue, value, setOptions)
                if suppressCallbacks and type(Library._endControlSync) == "function" then
                    Library:_endControlSync()
                end
                if not ok then
                    error(err, 0)
                end
                return self
            end

            if rawget(self, "Value") ~= nil then
                self.Value = value
            end
            return self
        end

        function control:SetValue(value, setOptions)
            return self:Set(value, setOptions)
        end

        function control:SetState(value, setOptions)
            return self:Set(value, setOptions)
        end

        function control:Refresh()
            if opts.refresh then
                opts.refresh()
            end
            return self
        end

        function control:SetVisible(visible)
            visible = visible ~= false
            self.Visible = visible

            if opts.root then
                opts.root.Visible = visible
            end

            if opts.onVisible then
                opts.onVisible(visible)
            end

            return self
        end

        function control:SetDisabled(disabled)
            self.Disabled = disabled == true

            if opts.clickTargets then
                for _, target in ipairs(opts.clickTargets) do
                    if target and target.Parent and target:IsA("GuiButton") then
                        target.Active = not self.Disabled
                        target.Selectable = not self.Disabled
                        target.AutoButtonColor = false
                    end
                end
            end

            if opts.updateDisabled then
                opts.updateDisabled(self.Disabled)
            end

            return self
        end

        function control:Destroy()
            if self._destroyed then
                return
            end

            self._destroyed = true

            if opts.onDestroy then
                pcall(opts.onDestroy, self)
            end

            if section and section._controls then
                removeArrayValue(section._controls, self)
            end

            if searchEntry and section and section._win and section._win._searchItems then
                removeArrayValue(section._win._searchItems, searchEntry)
            end

            if type(saveKey) == "string" and saveKey ~= "" and Library._widgetRegistry then
                if Library._widgetRegistry[saveKey] == self then
                    Library._widgetRegistry[saveKey] = nil
                end
            end

            cleanup:Cleanup()
        end

        return control
    end

    return {
        attachControlLifecycle = attachControlLifecycle,
        bindAdaptiveLabel = bindAdaptiveLabel,
        createCheckbox = createCheckbox,
        createLabel = createLabel,
        createOverlayButton = createOverlayButton,
        createRightBox = createRightBox,
        createRow = createRow,
    }
end
