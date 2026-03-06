return function(Library, helpers)
    local win = helpers.win
    local trackGlobal = helpers.trackGlobal
    local nextCleanupKey = helpers.nextCleanupKey
    local UserInputService = helpers.UserInputService

    local popupStates = {}
    local transientPopupClosers = {}

    local function closeTransientPopups(exceptPanel)
        for panel, closeFn in pairs(transientPopupClosers) do
            if not panel or not panel.Parent then
                transientPopupClosers[panel] = nil
            elseif panel ~= exceptPanel then
                closeFn()
            end
        end
    end

    local function registerTransientPopup(panel, closeFn)
        if not panel then
            return function()
            end
        end

        transientPopupClosers[panel] = closeFn

        return function()
            transientPopupClosers[panel] = nil
        end
    end

    local function setPopupOpen(panel, isOpen, opts)
        local state = popupStates[panel]
        if state == nil then
            state = {
                revision = 0,
                open = false,
            }
            popupStates[panel] = state
        end

        state.revision = state.revision + 1
        state.open = isOpen

        local revision = state.revision
        local closedSize = opts.ClosedSize

        Library:Stop(panel, "Size")

        if isOpen then
            panel.Visible = true
            panel.Size = closedSize
            Library:Animate(panel, opts.OpenToken or "Open", {
                Size = opts.OpenSize,
            })
            if opts.OnOpen then
                opts.OnOpen()
            end
            return
        end

        if opts.OnClose then
            opts.OnClose()
        end

        Library:Animate(panel, opts.CloseToken or "Close", {
            Size = closedSize,
        })

        task.delay(opts.HideDelay or 0.24, function()
            if win._destroyed then
                return
            end
            if state.revision ~= revision or state.open then
                return
            end

            Library:Stop(panel, "Size")
            panel.Size = closedSize
            panel.Visible = false
        end)
    end

    local function bindOutsideClose(opts)
        local cleanupKey = opts.cleanupKey or nextCleanupKey(opts.keyPrefix or "PopupOutside")

        return trackGlobal(UserInputService.InputBegan:Connect(function(input)
            if not opts.isOpen() then
                return
            end
            if input.UserInputType ~= Enum.UserInputType.MouseButton1
                and input.UserInputType ~= Enum.UserInputType.Touch then
                return
            end

            local mx, my = input.Position.X, input.Position.Y

            task.defer(function()
                if win._destroyed or not opts.isOpen() then
                    return
                end

                for _, target in ipairs(opts.targets()) do
                    if target and target.Parent then
                        local pos = target.AbsolutePosition
                        local size = target.AbsoluteSize
                        local inside = mx >= pos.X and mx <= pos.X + size.X
                            and my >= pos.Y and my <= pos.Y + size.Y
                        if inside then
                            return
                        end
                    end
                end

                opts.close()
            end)
        end), cleanupKey)
    end

    return {
        bindOutsideClose = bindOutsideClose,
        closeTransientPopups = closeTransientPopups,
        registerTransientPopup = registerTransientPopup,
        setPopupOpen = setPopupOpen,
    }
end
