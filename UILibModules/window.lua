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

    local function getThemeValueOr(L, key, fallback)
        local value = nil
        if type(L.GetThemeValue) == "function" then
            value = L:GetThemeValue(key)
        elseif L.Colors then
            value = L.Colors[key]
        end
        if value == nil then
            return fallback
        end
        return value
    end

    local function parseNotifyArgs(options, text, duration)
        if type(options) == "table" then
            local title = options.Title or options.Name or options.Header or "Notification"
            local body = options.Text or options.Description or options.Content or ""
            local time = options.Duration or options.Time or options.Timeout or 3
            return tostring(title), tostring(body), math.clamp(tonumber(time) or 3, 0.5, 60)
        end

        local title = tostring(options or "Notification")
        local body = tostring(text or "")
        local time = math.clamp(tonumber(duration) or 3, 0.5, 60)
        return title, body, time
    end

    local function ensureNotifyApi()
        if Library._notifyApiInstalled then
            return
        end

        Library._notifyApiInstalled = true

        function Library:_ensureNotifyHost(hostGui)
            local targetHost = hostGui
            if not targetHost and self._activeWindow and self._activeWindow._sg then
                targetHost = self._activeWindow._sg
            end
            if not targetHost or not targetHost.Parent then
                return nil
            end

            local state = self._notifyState
            if state and state.host == targetHost and state.root and state.root.Parent then
                return state
            end

            if state and state.root then
                pcall(function()
                    state.root:Destroy()
                end)
            end

            state = {
                host = targetHost,
                toasts = {},
                serial = 0,
            }
            self._notifyState = state

            local root = Instance.new("Frame")
            root.Name = "NotifyRoot"
            root.AnchorPoint = Vector2.new(1, 0)
            root.Position = UDim2.new(1, -14, 0, 14)
            root.Size = UDim2.new(0, 330, 1, -20)
            root.BackgroundTransparency = 1
            root.BorderSizePixel = 0
            root.ZIndex = 900
            root.ClipsDescendants = false
            root.Parent = targetHost

            local layout = Instance.new("UIListLayout")
            layout.FillDirection = Enum.FillDirection.Vertical
            layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
            layout.VerticalAlignment = Enum.VerticalAlignment.Top
            layout.SortOrder = Enum.SortOrder.LayoutOrder
            layout.Padding = UDim.new(0, 7)
            layout.Parent = root

            state.root = root
            return state
        end

        function Library:Notify(options, text, duration)
            local state = self:_ensureNotifyHost()
            if not state or not state.root then
                return nil
            end

            local title, body, displayTime = parseNotifyArgs(options, text, duration)
            local fontTitle = (self.Config and self.Config.Font) or Enum.Font.GothamBold
            local fontBody = (self.Config and self.Config.FontMedium) or Enum.Font.Gotham
            local titleSize = 13
            local bodySize = 12
            local textWidth = 302

            local measuredBodyHeight = bodySize + 2
            local okMeasure, bounds = pcall(TextService.GetTextSize, TextService, body, bodySize, fontBody, Vector2.new(textWidth, 1000))
            if okMeasure and bounds then
                measuredBodyHeight = math.max(bodySize + 2, bounds.Y)
            end

            local toastHeight = math.clamp(16 + titleSize + 3 + measuredBodyHeight + 14, 52, 130)
            state.serial += 1

            local slot = Instance.new("Frame")
            slot.Name = "NotifySlot_" .. tostring(state.serial)
            slot.Size = UDim2.new(1, 0, 0, 0)
            slot.BackgroundTransparency = 1
            slot.BorderSizePixel = 0
            slot.ClipsDescendants = true
            slot.ZIndex = 900
            slot.LayoutOrder = -state.serial
            slot.Parent = state.root

            local card = Instance.new("Frame")
            card.Name = "NotifyCard"
            card.AnchorPoint = Vector2.new(1, 0)
            card.Position = UDim2.new(1, 26, 0, 0)
            card.Size = UDim2.new(1, 0, 0, toastHeight)
            card.BackgroundColor3 = getThemeValueOr(self, "Panel", Color3.fromRGB(22, 22, 22))
            card.BackgroundTransparency = 1
            card.BorderSizePixel = 0
            card.ZIndex = 901
            card.Parent = slot
            Instance.new("UICorner", card).CornerRadius = UDim.new(0, 6)

            local stroke = Instance.new("UIStroke")
            stroke.Color = getThemeValueOr(self, "Line", Color3.fromRGB(60, 60, 60))
            stroke.Transparency = 1
            stroke.Parent = card

            local titleLabel = Instance.new("TextLabel")
            titleLabel.BackgroundTransparency = 1
            titleLabel.Position = UDim2.new(0, 10, 0, 8)
            titleLabel.Size = UDim2.new(1, -20, 0, titleSize + 2)
            titleLabel.Font = fontTitle
            titleLabel.Text = title
            titleLabel.TextColor3 = getThemeValueOr(self, "TextStrong", Color3.fromRGB(255, 255, 255))
            titleLabel.TextSize = titleSize
            titleLabel.TextXAlignment = Enum.TextXAlignment.Left
            titleLabel.TextYAlignment = Enum.TextYAlignment.Top
            titleLabel.TextTransparency = 1
            titleLabel.ZIndex = 902
            titleLabel.Parent = card

            local bodyLabel = Instance.new("TextLabel")
            bodyLabel.BackgroundTransparency = 1
            bodyLabel.Position = UDim2.new(0, 10, 0, 8 + titleSize + 3)
            bodyLabel.Size = UDim2.new(1, -20, 0, toastHeight - (8 + titleSize + 3 + 8))
            bodyLabel.Font = fontBody
            bodyLabel.Text = body
            bodyLabel.TextColor3 = getThemeValueOr(self, "TextDim", Color3.fromRGB(194, 194, 194))
            bodyLabel.TextSize = bodySize
            bodyLabel.TextWrapped = true
            bodyLabel.TextXAlignment = Enum.TextXAlignment.Left
            bodyLabel.TextYAlignment = Enum.TextYAlignment.Top
            bodyLabel.TextTransparency = 1
            bodyLabel.ZIndex = 902
            bodyLabel.Parent = card

            local progressBack = Instance.new("Frame")
            progressBack.AnchorPoint = Vector2.new(0, 1)
            progressBack.Position = UDim2.new(0, 0, 1, 0)
            progressBack.Size = UDim2.new(1, 0, 0, 2)
            progressBack.BackgroundColor3 = getThemeValueOr(self, "Line", Color3.fromRGB(54, 54, 54))
            progressBack.BackgroundTransparency = 0.55
            progressBack.BorderSizePixel = 0
            progressBack.ZIndex = 903
            progressBack.Parent = card

            local progressFill = Instance.new("Frame")
            progressFill.Size = UDim2.new(1, 0, 1, 0)
            progressFill.BackgroundColor3 = getThemeValueOr(self, "Main", Color3.fromRGB(245, 49, 116))
            progressFill.BorderSizePixel = 0
            progressFill.ZIndex = 904
            progressFill.Parent = progressBack

            if type(self.RegisterThemeBinding) == "function" then
                self:RegisterThemeBinding(card, "BackgroundColor3", "Panel")
                self:RegisterThemeBinding(stroke, "Color", "Line")
                self:RegisterThemeBinding(titleLabel, "TextColor3", "TextStrong")
                self:RegisterThemeBinding(bodyLabel, "TextColor3", "TextDim")
                self:RegisterThemeBinding(progressBack, "BackgroundColor3", "Line")
                self:RegisterThemeBinding(progressFill, "BackgroundColor3", "Main")
            end

            local toast = { closed = false }
            local tickerConnection
            local function closeToast()
                if toast.closed then
                    return
                end
                toast.closed = true

                if tickerConnection then
                    pcall(function()
                        tickerConnection:Disconnect()
                    end)
                    tickerConnection = nil
                end

                self:Spring(card, "Close", {
                    Position = UDim2.new(1, 24, 0, 0),
                    BackgroundTransparency = 1,
                })
                self:Spring(stroke, "Close", { Transparency = 1 })
                self:Spring(titleLabel, "Close", { TextTransparency = 1 })
                self:Spring(bodyLabel, "Close", { TextTransparency = 1 })
                self:Spring(progressBack, "Close", { BackgroundTransparency = 1 })
                self:Spring(progressFill, "Close", { BackgroundTransparency = 1 })
                self:Spring(slot, "Close", { Size = UDim2.new(1, 0, 0, 0) })

                for i = #state.toasts, 1, -1 do
                    if state.toasts[i] == toast then
                        table.remove(state.toasts, i)
                        break
                    end
                end

                task.delay(0.24, function()
                    if slot and slot.Parent then
                        slot:Destroy()
                    end
                end)
            end
            toast.close = closeToast

            local dismissButton = Instance.new("TextButton")
            dismissButton.Name = "Dismiss"
            dismissButton.BackgroundTransparency = 1
            dismissButton.Size = UDim2.new(1, 0, 1, 0)
            dismissButton.Text = ""
            dismissButton.AutoButtonColor = false
            dismissButton.Selectable = false
            dismissButton.ZIndex = 905
            dismissButton.Parent = card
            dismissButton.Activated:Connect(closeToast)

            table.insert(state.toasts, 1, toast)
            while #state.toasts > 5 do
                local oldest = state.toasts[#state.toasts]
                if oldest and oldest.close then
                    oldest.close()
                else
                    break
                end
            end

            self:Spring(slot, "Open", { Size = UDim2.new(1, 0, 0, toastHeight) })
            self:Spring(card, "Popup", {
                Position = UDim2.new(1, 0, 0, 0),
                BackgroundTransparency = getThemeValueOr(self, "PanelTransparency", 0),
            })
            self:Spring(stroke, "Open", { Transparency = 0.35 })
            self:Spring(titleLabel, "Open", { TextTransparency = 0 })
            self:Spring(bodyLabel, "Open", { TextTransparency = 0 })

            local startedAt = tick()
            tickerConnection = RunService.Heartbeat:Connect(function()
                if toast.closed then
                    return
                end
                local elapsed = tick() - startedAt
                local alpha = math.clamp(elapsed / displayTime, 0, 1)
                progressFill.Size = UDim2.new(1 - alpha, 0, 1, 0)
                if alpha >= 1 then
                    closeToast()
                end
            end)

            return {
                Close = closeToast,
            }
        end
    end

    ensureNotifyApi()

    local luarmorLibraryCache = {}

    local function trimText(value)
        local text = tostring(value or "")
        text = string.gsub(text, "^%s+", "")
        text = string.gsub(text, "%s+$", "")
        return text
    end

    local function cloneTableShallow(source)
        if type(source) ~= "table" then
            return source
        end

        local cloned = {}
        for key, value in pairs(source) do
            cloned[key] = value
        end

        local metatableValue = getmetatable(source)
        if metatableValue ~= nil then
            setmetatable(cloned, metatableValue)
        end

        return cloned
    end

    local function loadLuarmorApi(libraryUrl)
        libraryUrl = trimText(libraryUrl)
        if libraryUrl == "" then
            return nil, "Luarmor library URL is missing."
        end

        local cached = luarmorLibraryCache[libraryUrl]
        if type(cached) == "table" and cached._error then
            return nil, cached._error
        end
        if type(cached) == "table" then
            return cloneTableShallow(cached), nil
        end

        local loader = loadstring or load
        if type(loader) ~= "function" then
            local errorMessage = "Executor does not support loadstring."
            luarmorLibraryCache[libraryUrl] = { _error = errorMessage }
            return nil, errorMessage
        end

        local okSource, source = pcall(function()
            return game:HttpGet(libraryUrl)
        end)
        if not okSource or type(source) ~= "string" or source == "" then
            local errorMessage = "Failed to fetch Luarmor key library."
            luarmorLibraryCache[libraryUrl] = { _error = errorMessage }
            return nil, errorMessage
        end

        local okChunk, chunkOrError = pcall(loader, source)
        if not okChunk or type(chunkOrError) ~= "function" then
            local errorMessage = "Failed to compile Luarmor key library."
            luarmorLibraryCache[libraryUrl] = { _error = errorMessage }
            return nil, errorMessage
        end

        local okApi, apiOrError = pcall(chunkOrError)
        if not okApi or type(apiOrError) ~= "table" then
            local errorMessage = "Failed to initialize Luarmor key library."
            luarmorLibraryCache[libraryUrl] = { _error = errorMessage }
            return nil, errorMessage
        end

        luarmorLibraryCache[libraryUrl] = apiOrError
        return cloneTableShallow(apiOrError), nil
    end

    local function checkLuarmorKey(libraryUrl, scriptId, submittedKey)
        local api, apiError = loadLuarmorApi(libraryUrl)
        if type(api) ~= "table" then
            return false, {
                code = "LUARMOR_LIBRARY_ERROR",
                message = apiError or "Failed to load Luarmor key library.",
            }
        end

        scriptId = trimText(scriptId)
        if scriptId == "" then
            return false, {
                code = "LUARMOR_SCRIPT_ID_MISSING",
                message = "LuarmorScriptId is missing.",
            }
        end

        local keyValue = trimText(submittedKey)
        if keyValue == "" then
            return false, {
                code = "KEY_EMPTY",
                message = "Enter a key first.",
            }
        end

        api.script_id = scriptId

        local okStatus, status = pcall(api.check_key, keyValue)
        if (not okStatus or type(status) ~= "table") and type(api.check_key) == "function" then
            okStatus, status = pcall(function()
                return api:check_key(keyValue)
            end)
        end

        if not okStatus or type(status) ~= "table" then
            return false, {
                code = "LUARMOR_CHECK_FAILED",
                message = "Luarmor key check failed.",
            }
        end

        if status.code == "KEY_VALID" then
            return true, status
        end

        return false, status
    end

function Library:CreateWindow(opts)
    opts = opts or {}
    local name = opts.Name or opts.Title or "FATALITY"
    local expire = opts.Expire or "never"
    local keybind = opts.Keybind or self.Config.ToggleKey
    local configName = opts.ConfigName or nil
    local keySystemEnabled = opts.KeySystem == true
    local requiredKey = trimText(opts.Key)
    local luarmorKeySystemEnabled = opts.LuarmorKey == true or opts.LuarmorKeySystem == true
    local luarmorScriptId = trimText(opts.LuarmorScriptId or opts.LuarmorScriptID or opts.ScriptId)
    local luarmorLibraryUrl = trimText(opts.LuarmorLibraryUrl or opts.LuarmorKeyLibraryUrl or "https://sdkapi-public.luarmor.net/library.lua")
    local keyStorageTag = opts.KeyStorageTag
    local keyLink = opts.GetKeyLink or opts.KeyLink or opts.LuarmorKeyLink
    local onGetKey = opts.OnGetKey
    local keySubmitText = opts.SubmitKeyText or "Unlock"
    local keyLinkText = opts.GetKeyText or "Get Key"
    local colors = self.Colors
    local config = self.Config
    local rootCleanup = Cleaner.new()
    local desktopMinWindowWidth = math.max(config.MinWindowWidth or 640, 520)
    local desktopMinWindowHeight = math.max(config.MinWindowHeight or 400, config.HeaderHeight + config.BottomHeight + 120)
    local forcedMobileOverride = opts.ForceMobile == true
    local camera = workspace.CurrentCamera
    local viewportSize = camera and camera.ViewportSize or Vector2.new(config.WindowWidth, config.WindowHeight)
    local hasTouchInput = UserInputService.TouchEnabled
    local likelyMobileViewport = viewportSize.X <= 950 or viewportSize.Y <= 760
    local isMobileClient = forcedMobileOverride
        or (hasTouchInput and (not UserInputService.KeyboardEnabled or not UserInputService.MouseEnabled or likelyMobileViewport))
    local mobileMinWindowWidth = math.max(450, desktopMinWindowWidth - 64)
    local mobileMinWindowHeight = math.max(config.HeaderHeight + config.BottomHeight + 110, desktopMinWindowHeight - 56)
    local minWindowWidth = isMobileClient and mobileMinWindowWidth or desktopMinWindowWidth
    local minWindowHeight = isMobileClient and mobileMinWindowHeight or desktopMinWindowHeight
    local initialWindowWidth = config.WindowWidth
    if isMobileClient then
        initialWindowWidth = math.min(math.max(minWindowWidth + 16, 596), math.max(minWindowWidth, viewportSize.X - 20))
    end
    local initialWindowHeight = isMobileClient and minWindowHeight or config.WindowHeight

    -- Set config name for save/load
    self._configName = configName
    self._windowStorageName = configName or name
    self._configItems = {}
    self._configItemOrder = {}
    self._loadedConfigData = nil
    self._configReplayToken = 0

    local hardcodedKeySystemActive = (not luarmorKeySystemEnabled) and keySystemEnabled and requiredKey ~= ""
    local keyValidationMode = luarmorKeySystemEnabled and "luarmor" or (hardcodedKeySystemActive and "hardcoded" or "none")
    local keySystemActive = luarmorKeySystemEnabled or hardcodedKeySystemActive
    local keyGateUnlocked = not keySystemActive
    local keyContentBootstrapped = false
    local keyValidationBusy = false
    local initialKeyInputText = ""

    if type(keyStorageTag) ~= "string" or keyStorageTag == "" then
        if keyValidationMode == "luarmor" and luarmorScriptId ~= "" then
            keyStorageTag = "__luarmor_key_system_" .. luarmorScriptId
        else
            keyStorageTag = "__key_system"
        end
    end

    local function normalizeKeyInput(value)
        return trimText(value)
    end

    local function isAcceptedKey(value)
        return keyValidationMode == "hardcoded" and normalizeKeyInput(value) == requiredKey
    end

    local function validateSubmittedKey(value)
        local submitted = normalizeKeyInput(value)
        if submitted == "" then
            return false, {
                code = "KEY_EMPTY",
                message = "Enter a key first.",
            }
        end

        if keyValidationMode == "hardcoded" then
            if isAcceptedKey(submitted) then
                return true, {
                    code = "KEY_VALID",
                    message = "Key valid.",
                }
            end

            return false, {
                code = "KEY_INVALID",
                message = "Invalid key.",
            }
        end

        if keyValidationMode == "luarmor" then
            return checkLuarmorKey(luarmorLibraryUrl, luarmorScriptId, submitted)
        end

        return true, {
            code = "KEY_VALID",
            message = "Key system disabled.",
        }
    end

    if keySystemActive and type(Library.ReadData) == "function" then
        local savedKeyData = Library:ReadData(keyStorageTag)
        local savedKey = savedKeyData
        if type(savedKeyData) == "table" then
            savedKey = savedKeyData.key or savedKeyData.value
        end
        savedKey = normalizeKeyInput(savedKey)
        initialKeyInputText = savedKey
        local savedKeyAccepted = false
        if savedKey ~= "" then
            if keyValidationMode == "hardcoded" then
                savedKeyAccepted = isAcceptedKey(savedKey)
            elseif keyValidationMode == "luarmor" and luarmorScriptId ~= "" then
                local okSaved = nil
                okSaved = select(1, validateSubmittedKey(savedKey))
                savedKeyAccepted = okSaved == true
            end
        end
        if savedKeyAccepted then
            keyGateUnlocked = true
        end
    end

    local win = {
        Menus = {},
        ActiveMenu = nil,
        Visible = true,
        _cleanup = rootCleanup,
        KeyVerified = keyGateUnlocked,
    }
    local startupReady = false
    local setResizeCursor

    local function callbacksSuppressed()
        return type(Library._callbacksSuppressed) == "function" and Library:_callbacksSuppressed()
    end

    local function track(taskObject, methodName, key)
        return rootCleanup:Add(taskObject, methodName, key)
    end

    local function trackGlobal(conn, key)
        return track(conn, "Disconnect", key)
    end

    local function bindTheme(instance, propertyName, themeKey, transform)
        Library:RegisterThemeBinding(instance, propertyName, themeKey, transform)
    end

    local function onThemeChanged(callback)
        Library:RegisterThemeCallback(callback)
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

    local touchScrollZones = {}
    local activeTouchScroll = nil

    local function pointInsideGui(guiObject, position)
        if not guiObject or not guiObject.Parent or not guiObject.Visible then
            return false
        end

        local absolutePosition = guiObject.AbsolutePosition
        local absoluteSize = guiObject.AbsoluteSize
        return position.X >= absolutePosition.X
            and position.X <= absolutePosition.X + absoluteSize.X
            and position.Y >= absolutePosition.Y
            and position.Y <= absolutePosition.Y + absoluteSize.Y
    end

    local function bindTouchScroll(guiObject, scrollState, opts)
        if not isMobileClient or not guiObject or not scrollState then
            return
        end

        opts = opts or {}
        table.insert(touchScrollZones, {
            GuiObject = guiObject,
            ScrollState = scrollState,
            Axis = opts.Axis or "Y",
            Threshold = opts.Threshold or 6,
            Priority = opts.Priority or 0,
            CanScroll = opts.CanScroll,
            GetScale = opts.GetScale,
        })
    end

    local function findTouchScrollZone(position)
        local bestZone = nil
        local bestArea = math.huge

        for _, zone in ipairs(touchScrollZones) do
            if pointInsideGui(zone.GuiObject, position) then
                local size = zone.GuiObject.AbsoluteSize
                local area = size.X * size.Y
                if not bestZone
                    or zone.Priority > bestZone.Priority
                    or (zone.Priority == bestZone.Priority and area < bestArea) then
                    bestZone = zone
                    bestArea = area
                end
            end
        end

        return bestZone
    end

    if isMobileClient then
        trackGlobal(UserInputService.TouchPan:Connect(function(touchPositions, totalTranslation, velocity, state, gameProcessedEvent)
            local primaryTouch = touchPositions and touchPositions[1]
            if not primaryTouch then
                if state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
                    activeTouchScroll = nil
                end
                return
            end

            if state == Enum.UserInputState.Begin then
                local bestZone = findTouchScrollZone(primaryTouch)
                if bestZone then
                    activeTouchScroll = {
                        Zone = bestZone,
                        LastTranslation = Vector2.new(0, 0),
                        Dragging = false,
                    }
                else
                    activeTouchScroll = nil
                end
                return
            end

            local active = activeTouchScroll
            if not active then
                local bestZone = findTouchScrollZone(primaryTouch)
                if bestZone then
                    active = {
                        Zone = bestZone,
                        LastTranslation = Vector2.new(0, 0),
                        Dragging = false,
                    }
                    activeTouchScroll = active
                else
                    return
                end
            end

            local zone = active.Zone
            if not zone or not zone.GuiObject or not zone.GuiObject.Parent then
                activeTouchScroll = nil
                return
            end

            if state == Enum.UserInputState.Change then
                local delta = totalTranslation - (active.LastTranslation or Vector2.new(0, 0))
                local primaryDelta = zone.Axis == "X" and delta.X or delta.Y
                local crossDelta = zone.Axis == "X" and delta.Y or delta.X

                if not active.Dragging then
                    if math.abs(primaryDelta) < zone.Threshold or math.abs(primaryDelta) <= math.abs(crossDelta) then
                        active.LastTranslation = totalTranslation
                        return
                    end

                    active.Dragging = true
                end

                if zone.CanScroll and zone.CanScroll(primaryTouch) == false then
                    active.LastTranslation = totalTranslation
                    return
                end

                local scale = zone.GetScale and zone.GetScale() or 1
                zone.ScrollState:ScrollBy((-primaryDelta) / math.max(scale, 0.01))
                active.LastTranslation = totalTranslation
                return
            end

            if state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
                activeTouchScroll = nil
            end
        end), "TouchScrollPan")
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
    local chatModule = moduleRequire("chat.lua")(Library, context)
    local controlBase = moduleRequire("controls_base.lua")(Library, context)
    local dropdownControls = moduleRequire("dropdowns.lua")(Library, context)
    local createKeybindManager = moduleRequire("keybinds.lua")(Library, context)
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
    Library._activeWindow = win
    Library:_ensureNotifyHost(sg)

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
        if Library._activeWindow == self then
            Library._activeWindow = nil
        end
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
    dropShadow.ImageColor3 = colors.Shadow
    dropShadow.ImageTransparency = colors.ShadowTransparency
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
    main.Size = UDim2.fromOffset(initialWindowWidth, initialWindowHeight)
    main.ClipsDescendants = false
    main.Visible = false
    main.SelectionImageObject = blankSel
    bindTheme(main, "BackgroundColor3", "Background")
    bindTheme(main, "BackgroundTransparency", "BackgroundTransparency")
    bindTheme(dropShadow, "ImageColor3", "Shadow")
    bindTheme(dropShadow, "ImageTransparency", "ShadowTransparency")

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
    bindTheme(header, "BackgroundColor3", "Header")
    bindTheme(header, "BackgroundTransparency", "HeaderTransparency")

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
    bindTheme(headerLine, "BackgroundColor3", "Line")

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

    local HEADER_LEFT_PADDING = 14
    local HEADER_TITLE_GAP = 0
    local HEADER_RIGHT_PADDING = isMobileClient and 4 or 6
    local MOBILE_TOGGLE_SIZE = 18
    local MOBILE_TOGGLE_GAP = 6
    local USER_PROFILE_WIDTH = isMobileClient and 172 or 150
    local USER_PROFILE_OFFSET_X = isMobileClient and -16 or -5
    local AVATAR_RIGHT_INSET = isMobileClient and (2 + MOBILE_TOGGLE_SIZE + MOBILE_TOGGLE_GAP) or 10
    local PROFILE_TEXT_RIGHT_INSET = isMobileClient and (AVATAR_RIGHT_INSET + 30) or 40
    local TABS_MIN_WIDTH = 120

    -- Title text
    local headerText = Instance.new("TextLabel", header)
    headerText.Name = randomStr()
    headerText.AnchorPoint = Vector2.new(0, 0.5)
    headerText.BackgroundTransparency = 1
    headerText.BorderSizePixel = 0
    headerText.Position = UDim2.new(0, HEADER_LEFT_PADDING, 0.5, 0)
    headerText.Size = UDim2.new(0, 160, 1, 0)
    headerText.ZIndex = 4
    headerText.Font = config.Font
    headerText.Text = name
    headerText.TextColor3 = colors.Text
    headerText.TextSize = 21
    headerText.TextXAlignment = Enum.TextXAlignment.Left
    headerText.TextStrokeColor3 = Color3.fromRGB(205, 67, 218)
    headerText.TextStrokeTransparency = 0.64
    bindTheme(headerText, "TextColor3", "Text")
    bindTheme(headerText, "TextStrokeColor3", "TitleStroke")

    -- ==============================
    -- TAB CONTAINER (scrolling)
    -- ==============================
    local menuBtnCont = Instance.new("Frame", header)
    menuBtnCont.Name = randomStr()
    menuBtnCont.AnchorPoint = Vector2.new(0, 0.5)
    menuBtnCont.BackgroundTransparency = 1
    menuBtnCont.BorderSizePixel = 0
    menuBtnCont.ClipsDescendants = true
    menuBtnCont.Position = UDim2.new(0, 210, 0.5, 0)
    menuBtnCont.Size = UDim2.new(0, 300, 0.75, 0)
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
    bindTouchScroll(menuBtnCont, tabScrollState, {
        Axis = "X",
        Priority = 5,
    })

    -- ==============================
    -- USER PROFILE (right side of header)
    -- ==============================
    local userProfile = Instance.new("Frame", header)
    userProfile.Name = randomStr()
    userProfile.AnchorPoint = Vector2.new(1, 0.5)
    userProfile.BackgroundTransparency = 1
    userProfile.BorderSizePixel = 0
    userProfile.Position = UDim2.new(1, USER_PROFILE_OFFSET_X, 0.5, 0)
    userProfile.Size = UDim2.new(0, USER_PROFILE_WIDTH, 0.75, 0)
    userProfile.ZIndex = 4

    local function measureTitleWidth()
        local ok, bounds = pcall(TextService.GetTextSize, TextService, tostring(name or ""), headerText.TextSize, headerText.Font, Vector2.new(1000, config.HeaderHeight))
        if ok and bounds then
            return math.clamp(math.ceil(bounds.X) + 6, 120, 320)
        end
        return 160
    end

    local function refreshHeaderLayout()
        local titleWidth = measureTitleWidth()
        headerText.Size = UDim2.new(0, titleWidth, 1, 0)

        local tabsStartX = HEADER_LEFT_PADDING + titleWidth + HEADER_TITLE_GAP
        local rightReserved = USER_PROFILE_WIDTH + HEADER_RIGHT_PADDING + 12
        local tabsWidth = math.max(TABS_MIN_WIDTH, header.AbsoluteSize.X - tabsStartX - rightReserved)

        menuBtnCont.Position = UDim2.new(0, tabsStartX, 0.5, 0)
        menuBtnCont.Size = UDim2.new(0, tabsWidth, 0.75, 0)
        tabScrollState:Refresh(true)
    end

    trackGlobal(header:GetPropertyChangedSignal("AbsoluteSize"):Connect(refreshHeaderLayout), "HeaderLayoutChanged")
    task.defer(refreshHeaderLayout)

    -- Avatar
    local userIcon = Instance.new("ImageLabel", userProfile)
    userIcon.Name = randomStr()
    userIcon.AnchorPoint = Vector2.new(1, 0.5)
    userIcon.BackgroundTransparency = 1
    userIcon.BorderSizePixel = 0
    userIcon.Position = UDim2.new(1, -AVATAR_RIGHT_INSET, 0.5, 0)
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
    userName.Position = UDim2.new(1, -PROFILE_TEXT_RIGHT_INSET, 0, 3)
    userName.Size = UDim2.new(0, 200, 0, 15)
    userName.ZIndex = 4
    userName.Font = config.FontMedium
    userName.Text = Client.DisplayName
    userName.TextColor3 = Color3.fromRGB(255, 255, 255)
    userName.TextSize = 13
    userName.TextStrokeTransparency = 0.7
    userName.TextXAlignment = Enum.TextXAlignment.Right
    bindTheme(userName, "TextColor3", "TextStrong")

    -- Expire / Premium text
    local expireDays = Instance.new("TextLabel", userProfile)
    expireDays.Name = randomStr()
    expireDays.AnchorPoint = Vector2.new(1, 0)
    expireDays.BackgroundTransparency = 1
    expireDays.BorderSizePixel = 0
    expireDays.Position = UDim2.new(1, -PROFILE_TEXT_RIGHT_INSET, 0, 16)
    expireDays.Size = UDim2.new(0, 200, 0, 15)
    expireDays.ZIndex = 4
    expireDays.Font = config.FontMedium
    expireDays.RichText = true
    expireDays.Text = string.format('<font transparency="0.5">expires:</font> <font color="#f53174">%s</font>', expire)
    expireDays.TextColor3 = Color3.fromRGB(255, 255, 255)
    expireDays.TextSize = 12
    expireDays.TextStrokeTransparency = 0.7
    expireDays.TextXAlignment = Enum.TextXAlignment.Right
    bindTheme(expireDays, "TextColor3", "TextStrong")

    local mobileUi = {}
    if isMobileClient then
        local mobileMinimizeBtn = Instance.new("ImageButton", userProfile)
        mobileMinimizeBtn.Name = "MobileMinimizeButton"
        mobileMinimizeBtn.AnchorPoint = Vector2.new(1, 0.5)
        mobileMinimizeBtn.Position = UDim2.new(1, -1, 0.5, 0)
        mobileMinimizeBtn.Size = UDim2.new(0, MOBILE_TOGGLE_SIZE, 0, MOBILE_TOGGLE_SIZE)
        mobileMinimizeBtn.BackgroundTransparency = 1
        mobileMinimizeBtn.BorderSizePixel = 0
        mobileMinimizeBtn.Image = "rbxassetid://118845250851570"
        mobileMinimizeBtn.ImageColor3 = colors.TextDim
        mobileMinimizeBtn.ZIndex = 6
        mobileMinimizeBtn.AutoButtonColor = false
        mobileMinimizeBtn.Selectable = false

        mobileMinimizeBtn.MouseEnter:Connect(function()
            Library:Animate(mobileMinimizeBtn, "Hover", { ImageColor3 = colors.Main })
        end)
        mobileMinimizeBtn.MouseLeave:Connect(function()
            Library:Animate(mobileMinimizeBtn, "Hover", { ImageColor3 = colors.TextDim })
        end)

        mobileUi.MinimizeButton = mobileMinimizeBtn
    end

    -- ==============================
    -- MENU CONTENT AREA
    -- ==============================
    local menuFrameTopInset = 7
    local menuFrameBottomInset = 7

    local menuFrame = Instance.new("Frame", clipFrame)
    menuFrame.Name = randomStr()
    menuFrame.BackgroundTransparency = 1
    menuFrame.BorderSizePixel = 0
    menuFrame.Position = UDim2.new(0, 0, 0, config.HeaderHeight + menuFrameTopInset)
    menuFrame.Size = UDim2.new(1, 0, 1, -(config.HeaderHeight + menuFrameTopInset + config.BottomHeight + menuFrameBottomInset))
    menuFrame.ZIndex = 1
    menuFrame.ClipsDescendants = true

    local menuContent = Instance.new("Frame", menuFrame)
    menuContent.Name = "ContentRoot"
    menuContent.BackgroundTransparency = 1
    menuContent.BorderSizePixel = 0
    menuContent.Position = UDim2.new(0, 0, 0, 0)
    menuContent.Size = UDim2.new(1, 0, 1, 0)
    menuContent.ZIndex = 1

    local keyUi = {}
    do
        local keyGateRoot = Instance.new("Frame", clipFrame)
        keyGateRoot.Name = "KeyGateRoot"
        keyGateRoot.BackgroundTransparency = 1
        keyGateRoot.BorderSizePixel = 0
        keyGateRoot.Position = UDim2.new(0, 0, 0, 0)
        keyGateRoot.Size = UDim2.new(1, 0, 1, 0)
        keyGateRoot.Visible = false
        keyGateRoot.ZIndex = 3

        local keyGateCard = Instance.new("Frame", keyGateRoot)
        keyGateCard.Name = "KeyGateCard"
        keyGateCard.AnchorPoint = Vector2.new(0.5, 0.5)
        keyGateCard.Position = UDim2.new(0.5, 0, 0.5, 0)
        keyGateCard.Size = UDim2.fromOffset(360, 176)
        keyGateCard.BackgroundColor3 = Color3.fromRGB(22, 22, 22)
        keyGateCard.BorderSizePixel = 0
        keyGateCard.ZIndex = 4
        Instance.new("UICorner", keyGateCard).CornerRadius = UDim.new(0, 6)

        local keyGateStroke = Instance.new("UIStroke", keyGateCard)
        keyGateStroke.Color = colors.Line
        keyGateStroke.Transparency = 0.25

        local keyGateTitle = Instance.new("TextLabel", keyGateCard)
        keyGateTitle.BackgroundTransparency = 1
        keyGateTitle.Position = UDim2.new(0, 18, 0, 14)
        keyGateTitle.Size = UDim2.new(1, -36, 0, 22)
        keyGateTitle.Font = config.Font
        keyGateTitle.Text = "KEY SYSTEM"
        keyGateTitle.TextColor3 = colors.Text
        keyGateTitle.TextSize = 18
        keyGateTitle.TextXAlignment = Enum.TextXAlignment.Left
        keyGateTitle.ZIndex = 5

        local keyGateSubtitle = Instance.new("TextLabel", keyGateCard)
        keyGateSubtitle.BackgroundTransparency = 1
        keyGateSubtitle.Position = UDim2.new(0, 18, 0, 38)
        keyGateSubtitle.Size = UDim2.new(1, -36, 0, 18)
        keyGateSubtitle.Font = config.FontMedium
        keyGateSubtitle.Text = "Enter your key to unlock the window."
        keyGateSubtitle.TextColor3 = colors.TextDim
        keyGateSubtitle.TextSize = 11
        keyGateSubtitle.TextXAlignment = Enum.TextXAlignment.Left
        keyGateSubtitle.ZIndex = 5

        local keyInput = Instance.new("TextBox", keyGateCard)
        keyInput.Name = "KeyInput"
        keyInput.Position = UDim2.new(0, 18, 0, 72)
        keyInput.Size = UDim2.new(1, -36, 0, 34)
        keyInput.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
        keyInput.BorderSizePixel = 0
        keyInput.ClearTextOnFocus = false
        keyInput.Font = config.FontMedium
        keyInput.PlaceholderText = "Enter key here"
        keyInput.PlaceholderColor3 = colors.TextMuted
        keyInput.Text = ""
        keyInput.TextColor3 = colors.Text
        keyInput.TextSize = 13
        keyInput.TextXAlignment = Enum.TextXAlignment.Left
        keyInput.ZIndex = 5
        Instance.new("UICorner", keyInput).CornerRadius = UDim.new(0, 4)

        local keyInputPadding = Instance.new("UIPadding", keyInput)
        keyInputPadding.PaddingLeft = UDim.new(0, 10)
        keyInputPadding.PaddingRight = UDim.new(0, 10)

        local keyInputStroke = Instance.new("UIStroke", keyInput)
        keyInputStroke.Color = colors.Line
        keyInputStroke.Transparency = 0.45

        local keyStatus = Instance.new("TextLabel", keyGateCard)
        keyStatus.BackgroundTransparency = 1
        keyStatus.Position = UDim2.new(0, 18, 0, 112)
        keyStatus.Size = UDim2.new(1, -36, 0, 18)
        keyStatus.Font = config.FontMedium
        keyStatus.Text = ""
        keyStatus.TextColor3 = colors.TextDim
        keyStatus.TextSize = 10
        keyStatus.TextXAlignment = Enum.TextXAlignment.Left
        keyStatus.ZIndex = 5

        local keyGetButton = Instance.new("TextButton", keyGateCard)
        keyGetButton.Name = "GetKeyButton"
        keyGetButton.Position = UDim2.new(0, 18, 1, -50)
        keyGetButton.Size = UDim2.new(0.5, -23, 0, 30)
        keyGetButton.BackgroundColor3 = Color3.fromRGB(32, 32, 32)
        keyGetButton.BorderSizePixel = 0
        keyGetButton.Font = config.FontMedium
        keyGetButton.Text = keyLinkText
        keyGetButton.TextColor3 = colors.Text
        keyGetButton.TextSize = 11
        keyGetButton.ZIndex = 5
        keyGetButton.AutoButtonColor = false
        keyGetButton.Selectable = false
        Instance.new("UICorner", keyGetButton).CornerRadius = UDim.new(0, 4)

        local keyGetStroke = Instance.new("UIStroke", keyGetButton)
        keyGetStroke.Color = colors.Line
        keyGetStroke.Transparency = 0.4

        local keySubmitButton = Instance.new("TextButton", keyGateCard)
        keySubmitButton.Name = "SubmitKeyButton"
        keySubmitButton.AnchorPoint = Vector2.new(1, 0)
        keySubmitButton.Position = UDim2.new(1, -18, 1, -50)
        keySubmitButton.Size = UDim2.new(0.5, -23, 0, 30)
        keySubmitButton.BackgroundColor3 = Color3.fromRGB(45, 25, 30)
        keySubmitButton.BorderSizePixel = 0
        keySubmitButton.Font = config.FontMedium
        keySubmitButton.Text = keySubmitText
        keySubmitButton.TextColor3 = Color3.fromRGB(255, 255, 255)
        keySubmitButton.TextSize = 11
        keySubmitButton.ZIndex = 5
        keySubmitButton.AutoButtonColor = false
        keySubmitButton.Selectable = false
        Instance.new("UICorner", keySubmitButton).CornerRadius = UDim.new(0, 4)

        local keySubmitStroke = Instance.new("UIStroke", keySubmitButton)
        keySubmitStroke.Color = colors.Main
        keySubmitStroke.Transparency = 0.35

        keyUi.Root = keyGateRoot
        keyUi.Input = keyInput
        keyUi.InputStroke = keyInputStroke
        keyUi.StatusLabel = keyStatus
        keyUi.GetButton = keyGetButton
        keyUi.SubmitButton = keySubmitButton
    end

    if initialKeyInputText ~= "" then
        keyUi.Input.Text = initialKeyInputText
    end

    if isMobileClient then
        local mobileRestoreBar = Instance.new("TextButton", sg)
        mobileRestoreBar.Name = "MobileRestoreBar"
        mobileRestoreBar.AnchorPoint = Vector2.new(1, 0)
        mobileRestoreBar.Position = UDim2.new(1, -14, 0, 14)
        mobileRestoreBar.Size = UDim2.fromOffset(154, 34)
        mobileRestoreBar.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
        mobileRestoreBar.BorderSizePixel = 0
        mobileRestoreBar.Text = ""
        mobileRestoreBar.ZIndex = 150
        mobileRestoreBar.Visible = false
        mobileRestoreBar.AutoButtonColor = false
        mobileRestoreBar.Selectable = false
        Instance.new("UICorner", mobileRestoreBar).CornerRadius = UDim.new(0, 8)

        local mobileRestoreStroke = Instance.new("UIStroke", mobileRestoreBar)
        mobileRestoreStroke.Color = colors.Line
        mobileRestoreStroke.Transparency = 0.2

        local restoreLabel = Instance.new("TextLabel", mobileRestoreBar)
        restoreLabel.Name = "Label"
        restoreLabel.BackgroundTransparency = 1
        restoreLabel.Position = UDim2.new(0, 12, 0, 0)
        restoreLabel.Size = UDim2.new(1, -42, 1, 0)
        restoreLabel.Font = config.FontMedium
        restoreLabel.Text = string.upper(tostring(name))
        restoreLabel.TextColor3 = colors.Text
        restoreLabel.TextSize = 11
        restoreLabel.TextXAlignment = Enum.TextXAlignment.Left
        restoreLabel.ZIndex = 151

        local restoreIcon = Instance.new("ImageLabel", mobileRestoreBar)
        restoreIcon.Name = "Icon"
        restoreIcon.AnchorPoint = Vector2.new(1, 0.5)
        restoreIcon.BackgroundTransparency = 1
        restoreIcon.Position = UDim2.new(1, -10, 0.5, 0)
        restoreIcon.Size = UDim2.new(0, 16, 0, 16)
        restoreIcon.Image = "rbxassetid://118845250851570"
        restoreIcon.ImageColor3 = colors.Text
        restoreIcon.ZIndex = 151

        mobileRestoreBar.MouseEnter:Connect(function()
            Library:Animate(mobileRestoreBar, "Hover", { BackgroundColor3 = Color3.fromRGB(34, 34, 34) })
        end)
        mobileRestoreBar.MouseLeave:Connect(function()
            Library:Animate(mobileRestoreBar, "Hover", { BackgroundColor3 = Color3.fromRGB(24, 24, 24) })
        end)

        mobileUi.RestoreBar = mobileRestoreBar
    end

    local menuScale = Instance.new("UIScale", menuContent)
    local contentScaleOptions = {
        { Label = "90%", Value = 0.9 },
        { Label = "100%", Value = 1.0 },
        { Label = "110%", Value = 1.1 },
        { Label = "125%", Value = 1.25 },
        { Label = "140%", Value = 1.4 },
    }
    local currentContentScale = config.ContentScale or 1
    local menuContentRightInset = 0
    local function refreshMenuScrolls()
    end
    local function applyMenuContentLayout(scaleValue, animate)
        local safeScale = math.max(scaleValue or currentContentScale or 1, 0.01)
        local scaledInset = -math.floor((menuContentRightInset / safeScale) + 0.5)
        local targetSize = UDim2.new(1 / safeScale, scaledInset, 1 / safeScale, 0)

        if animate then
            Library:Animate(menuContent, "Open", {
                Size = targetSize,
            })
        else
            menuContent.Size = targetSize
        end
    end
    local function updateContentScaleHost(scaleValue, animate)
        applyMenuContentLayout(scaleValue, animate)
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
        updateContentScaleHost(option.Value, false)
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
    bindTheme(bottom, "BackgroundColor3", "Bottom")
    bindTheme(bottom, "BackgroundTransparency", "BottomTransparency")

    Instance.new("UICorner", bottom).CornerRadius = UDim.new(0, 4)

    -- Bottom top line
    local bottomLine = Instance.new("Frame", bottom)
    bottomLine.BackgroundColor3 = colors.Line
    bottomLine.BorderSizePixel = 0
    bottomLine.Size = UDim2.new(1, 0, 0, 1)
    bottomLine.ZIndex = 3
    bindTheme(bottomLine, "BackgroundColor3", "Line")

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
    bindTheme(gearBtn, "ImageColor3", "TextDim")

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
    bindTheme(settingsPanel, "BackgroundColor3", "Panel")
    bindTheme(settingsPanel, "BackgroundTransparency", "PanelTransparency")
    Instance.new("UICorner", settingsPanel).CornerRadius = UDim.new(0, 5)
    local spStroke = Instance.new("UIStroke", settingsPanel)
    spStroke.Color = colors.Line
    spStroke.Transparency = 0.3
    bindTheme(spStroke, "Color", "Line")

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
    bindTheme(spHeader, "TextColor3", "TextStrong")

    -- Separator
    local spSep = Instance.new("Frame", settingsPanel)
    spSep.Position = UDim2.new(0, 8, 0, 28)
    spSep.Size = UDim2.new(1, -16, 0, 1)
    spSep.BackgroundColor3 = colors.Line
    spSep.BorderSizePixel = 0
    spSep.ZIndex = 101
    bindTheme(spSep, "BackgroundColor3", "Line")

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
    bindTheme(asLabel, "TextColor3", "Text")

    local asChkFrame = Instance.new("Frame", autoSaveRow)
    asChkFrame.AnchorPoint = Vector2.new(1, 0.5)
    asChkFrame.Position = UDim2.new(1, 0, 0.5, 0)
    asChkFrame.Size = UDim2.new(0, 12, 0, 12)
    asChkFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    asChkFrame.BorderSizePixel = 0
    asChkFrame.ZIndex = 101
    bindTheme(asChkFrame, "BackgroundColor3", "Control")
    bindTheme(asChkFrame, "BackgroundTransparency", "ControlTransparency")
    Instance.new("UICorner", asChkFrame).CornerRadius = UDim.new(0, 3)
    local asChkStroke = Instance.new("UIStroke", asChkFrame)
    asChkStroke.Color = colors.Line
    asChkStroke.Transparency = 0.5
    bindTheme(asChkStroke, "Color", "Line")

    local asCheckIcon = Instance.new("ImageLabel", asChkFrame)
    asCheckIcon.BackgroundTransparency = 1
    asCheckIcon.AnchorPoint = Vector2.new(0.5, 0.5)
    asCheckIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
    asCheckIcon.Size = UDim2.new(0, 10, 0, 10)
    asCheckIcon.Image = "rbxassetid://122354904349171"
    asCheckIcon.ImageColor3 = colors.Main
    asCheckIcon.ImageTransparency = 1
    asCheckIcon.ZIndex = 102
    bindTheme(asCheckIcon, "ImageColor3", "Main")

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
    bindTheme(saveBtn, "BackgroundColor3", "Control")
    bindTheme(saveBtn, "BackgroundTransparency", "ControlTransparency")
    bindTheme(saveBtn, "TextColor3", "Text")

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
    bindTheme(loadBtn, "BackgroundColor3", "Control")
    bindTheme(loadBtn, "BackgroundTransparency", "ControlTransparency")
    bindTheme(loadBtn, "TextColor3", "Text")

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
        if win._openSettingsRoute then
            win._openSettingsRoute()
            return
        end
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
    bindTheme(searchBtn, "ImageColor3", "TextDim")

    searchBtn.MouseEnter:Connect(function()
        Library:Animate(searchBtn, "Hover", { ImageColor3 = colors.Main })
    end)
    searchBtn.MouseLeave:Connect(function()
        Library:Animate(searchBtn, "Hover", { ImageColor3 = colors.TextDim })
    end)

    function win:SetChatProvider()
        return false
    end
    win.RefreshChat = function()
    end
    win.SetChatRoom = function()
    end
    win._setChatOpen = nil

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
    bindTheme(searchPanel, "BackgroundColor3", "Panel")
    bindTheme(searchPanel, "BackgroundTransparency", "PanelTransparency")
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
    bindTouchScroll(resultsFrame, searchScrollState, {
        Axis = "Y",
        Priority = 30,
    })

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

    chatModule.attach({
        win = win,
        opts = opts,
        main = main,
        bottom = bottom,
        colors = colors,
        config = config,
        bindTheme = bindTheme,
        onThemeChanged = onThemeChanged,
        closeTransientPopups = closeTransientPopups,
        registerTransientPopup = registerTransientPopup,
        setPopupOpen = setPopupOpen,
        popupManager = popupManager,
        trackGlobal = trackGlobal,
        nextCleanupKey = nextCleanupKey,
        canUseUi = function()
            return win.Visible and keyGateUnlocked
        end,
    })

    -- ==============================
    -- DRAGGING / RESIZING
    -- ==============================
    local dragInput, dragStart, dragBounds, dragInputType, dragPending
    local resizeStart, resizeBounds, resizeInputType, resizeEndInputType
    local resizeDirection, hoverResizeDirection
    local resizeBorder = config.ResizeBorder or 8
    if isMobileClient then
        resizeBorder = math.max(resizeBorder, 18)
    end
    local dragThreshold = 3

    setResizeCursor = function()
    end

    local function getResizeDirection(position)
        if not win.Visible or not main.Visible then
            return nil
        end

        if keySystemActive and not keyGateUnlocked then
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

    local lockedWindowSize = UDim2.fromOffset(392, 208)
    local fullWindowSize = UDim2.fromOffset(initialWindowWidth, initialWindowHeight)
    local fullClipSize = UDim2.new(1, 0, 1, 0)

    local windowBounds = {
        left = math.floor(main.AbsolutePosition.X + 0.5),
        top = math.floor(main.AbsolutePosition.Y + 0.5),
        width = initialWindowWidth,
        height = initialWindowHeight,
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

    local function syncMobileRestoreButton()
        if mobileUi.RestoreBar then
            mobileUi.RestoreBar.Visible = startupReady and isMobileClient and not win.Visible
        end
    end

    local function syncFloatingPanels()
        for panel, state in pairs(win._floatingPanels) do
            panel.Visible = startupReady and win.Visible and keyGateUnlocked and state.Active or false
        end
    end

    local keybindManager = createKeybindManager({
        bindOutsideClose = popupManager.bindOutsideClose,
        bindTheme = bindTheme,
        clipFrame = clipFrame,
        closeTransientPopups = closeTransientPopups,
        colors = colors,
        config = config,
        getReservedKey = function()
            if typeof(guiKeybind) == "EnumItem" and guiKeybind.EnumType == Enum.KeyCode then
                return guiKeybind
            end
            if type(guiKeybind) == "string" then
                return Enum.KeyCode[guiKeybind]
            end
            return nil
        end,
        isRuntimeEnabled = function()
            return startupReady and keyGateUnlocked
        end,
        main = main,
        screenGui = sg,
        registerTransientPopup = registerTransientPopup,
        getWindowRect = function()
            return main.AbsolutePosition, main.AbsoluteSize
        end,
        setPopupOpen = setPopupOpen,
        syncFloatingPanels = syncFloatingPanels,
        trackGlobal = trackGlobal,
        win = win,
    })
    win._keybindManager = keybindManager

    local function smoothToggle()
        win.Visible = not win.Visible

        if not startupReady then
            syncMobileRestoreButton()
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

        syncMobileRestoreButton()
    end

    trackGlobal(UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if input.KeyCode == guiKeybind or (typeof(guiKeybind) == "string" and input.KeyCode.Name == guiKeybind) then
            smoothToggle()
        end
    end), "ToggleKeybind")

    if mobileUi.MinimizeButton then
        mobileUi.MinimizeButton.Activated:Connect(function()
            smoothToggle()
        end)
    end

    if mobileUi.RestoreBar then
        mobileUi.RestoreBar.Activated:Connect(function()
            smoothToggle()
        end)
    end

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

    win._updateGuiKeybindVisual = function(currentKey)
        if typeof(currentKey) == "EnumItem" then
            kbValueBtn.Text = currentKey.Name
        elseif typeof(currentKey) == "string" then
            kbValueBtn.Text = currentKey
        else
            kbValueBtn.Text = tostring(currentKey)
        end
    end

    win._setGuiKeybind = function(newKey, shouldSave)
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
        if type(win._updateGuiKeybindVisual) == "function" then
            win._updateGuiKeybindVisual(newKey)
        end

        if shouldSave then
            pcall(function() Library:SaveConfig() end)
        end

        return true
    end

    if type(win._updateGuiKeybindVisual) == "function" then
        win._updateGuiKeybindVisual(guiKeybind)
    end

    kbValueBtn.Activated:Connect(function()
        if kbListening then return end
        kbListening = true
        kbValueBtn.Text = "..."
        Library:Spring(kbStroke, "Smooth", { Color = colors.Main, Transparency = 0 })

        kbConn = trackGlobal(UserInputService.InputBegan:Connect(function(input, gpe)
            if input.UserInputType == Enum.UserInputType.Keyboard then
                -- Ignore modifier keys alone
                if input.KeyCode == Enum.KeyCode.Unknown then return end
                if type(win._setGuiKeybind) == "function" then
                    win._setGuiKeybind(input.KeyCode, true)
                end
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
            if type(win._setGuiKeybind) == "function" then
                win._setGuiKeybind(val, false)
            end
        end
    )

    Library:RegisterConfig("__uilib.settings.show_keybind_list", "setting",
        function()
            if keybindManager then
                return keybindManager:GetListEnabled()
            end
            return true
        end,
        function(val)
            if keybindManager then
                keybindManager:SetListEnabled(val == true, false)
            end
        end
    )

    Library:RegisterConfig("__uilib.settings.keybind_list_position", "setting",
        function()
            if keybindManager and type(keybindManager.GetListPosition) == "function" then
                return keybindManager:GetListPosition()
            end
            return { mode = "auto" }
        end,
        function(val)
            if keybindManager and type(keybindManager.SetListPosition) == "function" then
                keybindManager:SetListPosition(val, false)
            end
        end,
        {
            Aliases = { "__uilib.settings.keybind_panel_position" },
        }
    )

    win._setKeyChromeLocked = function(locked)
        if locked then
            closeTransientPopups()
            if keybindManager then
                keybindManager:CloseEditor()
            end
            settingsOpen = false
            searchOpen = false
            if type(win._setChatOpen) == "function" then
                win._setChatOpen(false)
            end
            uiScaleDropdownOpen = false
            settingsPanel.Visible = false
            searchPanel.Visible = false
            if uiScalePanel then
                uiScalePanel.Visible = false
            end
            main.AnchorPoint = Vector2.new(0.5, 0.5)
            main.Position = UDim2.new(0.5, 0, 0.5, 0)
            main.Size = lockedWindowSize
            main.BackgroundTransparency = 1
            dropShadow.Visible = false
        else
            main.AnchorPoint = Vector2.new(0.5, 0)
            main.BackgroundTransparency = 0
            dropShadow.Visible = true
            applyWindowBounds(windowBounds.left, windowBounds.top, windowBounds.width, windowBounds.height)
        end

        header.Visible = not locked
        menuBtnCont.Visible = not locked
        userProfile.Visible = not locked
        menuFrame.Visible = not locked
        bottom.Visible = not locked
        keyUi.Root.Visible = locked
    end

    keyUi.RunGetKeyAction = function()
        local handled = false

        if type(onGetKey) == "function" then
            local ok = pcall(onGetKey)
            handled = ok or handled
        end

        if type(keyLink) == "string" and keyLink ~= "" then
            local copied = false
            if type(setclipboard) == "function" then
                copied = pcall(setclipboard, keyLink)
            elseif type(toclipboard) == "function" then
                copied = pcall(toclipboard, keyLink)
            end

            if copied then
                keyUi.StatusLabel.Text = "Key link copied to clipboard."
                keyUi.StatusLabel.TextColor3 = colors.Main
            else
                keyUi.StatusLabel.Text = tostring(keyLink)
                keyUi.StatusLabel.TextColor3 = colors.TextDim
            end
            handled = true
        end

        if not handled then
            keyUi.StatusLabel.Text = "No key link configured."
            keyUi.StatusLabel.TextColor3 = Color3.fromRGB(255, 160, 160)
        end
    end

    win._bootstrapWindowContent = function()
        if keyContentBootstrapped or win._destroyed then
            return
        end

        keyContentBootstrapped = true

        pcall(function()
            Library:LoadTheme()
        end)

        win:_ensureSettingsMenu()

        if configName then
            pcall(function()
                Library:LoadConfig()
            end)
        end

        if win._destroyed then
            return
        end

        refreshMenuScrolls()
    end

    win._setKeyVerified = function(verified)
        keyGateUnlocked = verified == true
        win.KeyVerified = keyGateUnlocked
        win._setKeyChromeLocked(not keyGateUnlocked)

        if keyGateUnlocked then
            win._bootstrapWindowContent()
            keyUi.Input.Text = ""
            keyUi.StatusLabel.Text = ""
            keyUi.StatusLabel.TextColor3 = colors.TextDim
        end
    end

    local function setKeyStatus(text, color)
        keyUi.StatusLabel.Text = tostring(text or "")
        keyUi.StatusLabel.TextColor3 = typeof(color) == "Color3" and color or colors.TextDim
    end

    local function pulseKeyInputStroke(color)
        Library:Spring(keyUi.InputStroke, "Smooth", { Color = color, Transparency = 0.1 })
        task.delay(0.3, function()
            if keyUi.InputStroke.Parent then
                Library:Spring(keyUi.InputStroke, "Smooth", { Color = colors.Line, Transparency = 0.45 })
            end
        end)
    end

    local function describeKeyFailure(status)
        local code = trimText(type(status) == "table" and status.code or "")
        local message = type(status) == "table" and status.message or nil

        if code == "KEY_EMPTY" then
            return "Enter a key first.", Color3.fromRGB(255, 160, 160)
        end
        if code == "LUARMOR_SCRIPT_ID_MISSING" then
            return "LuarmorScriptId is missing.", Color3.fromRGB(255, 160, 160)
        end
        if code == "LUARMOR_LIBRARY_ERROR" or code == "LUARMOR_CHECK_FAILED" then
            return tostring(message or "Luarmor key check failed."), Color3.fromRGB(255, 160, 160)
        end
        if code == "KEY_HWID_LOCKED" then
            return "Key is locked to another HWID.", Color3.fromRGB(255, 188, 120)
        end
        if code == "KEY_EXPIRED" then
            return "Key expired. Get a new one and retry.", Color3.fromRGB(255, 188, 120)
        end
        if code == "KEY_INCORRECT" or code == "KEY_INVALID" then
            return "Invalid key.", Color3.fromRGB(255, 160, 160)
        end
        if type(message) == "string" and message ~= "" then
            return message, Color3.fromRGB(255, 160, 160)
        end
        return "Invalid key.", Color3.fromRGB(255, 160, 160)
    end

    local function setKeyValidationBusy(isBusy)
        keyValidationBusy = isBusy == true
        if keyValidationBusy then
            keyUi.SubmitButton.Text = keyValidationMode == "luarmor" and "Checking..." or keySubmitText
        else
            keyUi.SubmitButton.Text = keySubmitText
        end
    end

    keyUi.TryUnlockWindow = function()
        if keyValidationBusy then
            return false
        end

        local submitted = normalizeKeyInput(keyUi.Input.Text)
        if not keySystemActive then
            win._setKeyVerified(true)
            return true
        end

        if submitted == "" then
            setKeyStatus("Enter a key first.", Color3.fromRGB(255, 160, 160))
            pulseKeyInputStroke(Color3.fromRGB(200, 90, 90))
            return false
        end

        if keyValidationMode == "luarmor" then
            setKeyValidationBusy(true)
            setKeyStatus("Checking key...", colors.Main)
        end

        local accepted, status = validateSubmittedKey(submitted)
        setKeyValidationBusy(false)

        if not accepted then
            local failureText, failureColor = describeKeyFailure(status)
            setKeyStatus(failureText, failureColor)
            pulseKeyInputStroke(Color3.fromRGB(200, 90, 90))
            return false
        end

        if type(Library.WriteData) == "function" then
            Library:WriteData(keyStorageTag, {
                key = submitted,
                value = submitted,
                verified = true,
                mode = keyValidationMode,
                script_id = luarmorScriptId,
            })
        end

        win._setKeyVerified(true)
        return true
    end

    if keyValidationMode == "luarmor" and luarmorScriptId == "" then
        setKeyStatus("LuarmorScriptId is missing.", Color3.fromRGB(255, 160, 160))
    end

    keyUi.GetButton.MouseEnter:Connect(function()
        Library:Animate(keyUi.GetButton, "Hover", { BackgroundColor3 = Color3.fromRGB(42, 42, 42) })
    end)
    keyUi.GetButton.MouseLeave:Connect(function()
        Library:Animate(keyUi.GetButton, "Hover", { BackgroundColor3 = Color3.fromRGB(32, 32, 32) })
    end)
    keyUi.SubmitButton.MouseEnter:Connect(function()
        Library:Animate(keyUi.SubmitButton, "Hover", { BackgroundColor3 = Color3.fromRGB(60, 30, 38) })
    end)
    keyUi.SubmitButton.MouseLeave:Connect(function()
        Library:Animate(keyUi.SubmitButton, "Hover", { BackgroundColor3 = Color3.fromRGB(45, 25, 30) })
    end)
    keyUi.GetButton.Activated:Connect(keyUi.RunGetKeyAction)
    keyUi.SubmitButton.Activated:Connect(keyUi.TryUnlockWindow)
    keyUi.Input.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            keyUi.TryUnlockWindow()
        end
    end)

    win._setKeyChromeLocked(keySystemActive and not keyGateUnlocked)

    -- ==============================
    -- AddMenu (creates tab + page)
    -- ==============================
    function win:AddMenu(menuOpts)
        menuOpts = menuOpts or {}
        local menuName = menuOpts.Name or menuOpts.Title or "TAB"
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
        bindTheme(menuBtn, "BackgroundColor3", "TabBg")

        Instance.new("UICorner", menuBtn).CornerRadius = UDim.new(0, 3)

        local btnStroke = Instance.new("UIStroke", menuBtn)
        btnStroke.Transparency = 1
        bindTheme(btnStroke, "Color", "Line")

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
        bindTheme(menuLabel, "TextColor3", "TextDim")

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
            if isMobileClient then
                local col = Instance.new("ScrollingFrame", pageFrame)
                col.Name = "Column_" .. i
                col.BackgroundTransparency = 1
                col.BorderSizePixel = 0
                col.Position = UDim2.new(colWidth * (i - 1), 4, 0, 4)
                col.Size = UDim2.new(colWidth, -8, 1, -4)
                col.ZIndex = 3
                col.Active = true
                col.ClipsDescendants = true
                col.ScrollingEnabled = true
                col.ScrollBarThickness = 0
                col.ScrollBarImageTransparency = 1
                col.ScrollingDirection = Enum.ScrollingDirection.Y
                col.AutomaticCanvasSize = Enum.AutomaticSize.None
                col.CanvasSize = UDim2.new(0, 0, 0, 0)
                col.TopImage = ""
                col.MidImage = ""
                col.BottomImage = ""
                col.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
                col.AutomaticSize = Enum.AutomaticSize.None

                local colLayout = Instance.new("UIListLayout", col)
                colLayout.SortOrder = Enum.SortOrder.LayoutOrder
                colLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
                colLayout.Padding = UDim.new(0, 8)

                local colPad = Instance.new("UIPadding", col)
                colPad.PaddingTop = UDim.new(0, 4)
                colPad.PaddingBottom = UDim.new(0, 4)

                local function refreshScroll()
                    local canvasHeight = colLayout.AbsoluteContentSize.Y + 12
                    col.CanvasSize = UDim2.new(0, 0, 0, math.max(0, math.floor(canvasHeight + 0.5)))
                end

                trackGlobal(colLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(refreshScroll), nextCleanupKey("MobileColumnCanvas"))
                task.defer(refreshScroll)

                table.insert(menu._columnScrollers, refreshScroll)
                menu._columns[i] = col
            else
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
                    if popupManager.isMouseOverTransientPopup and popupManager.isMouseOverTransientPopup() then
                        return
                    end
                    local scrollStep = BASE_SCROLL_STEP / math.max(currentContentScale, 0.01)
                    scrollState:ScrollBy(-input.Position.Z * scrollStep)
                end)

                table.insert(menu._columnScrollers, refreshScroll)
                menu._columns[i] = inner -- sections parent to inner
            end
        end

        function menu:_refreshScroll()
            for _, refreshScroll in ipairs(self._columnScrollers) do
                refreshScroll()
            end
            if type(self._widePanels) == "table" then
                for _, panel in ipairs(self._widePanels) do
                    if panel and panel.RefreshLayout then
                        panel:RefreshLayout()
                    end
                end
            end
        end

        menu._btn = menuBtn
        menu._label = menuLabel
        menu._page = pageFrame
        menu._stroke = btnStroke
        menu._widePanels = {}

        -- Select/deselect
        local function selectMenu(selected)
            if selected then
                Library:Spring(menuBtn, "Smooth", { BackgroundTransparency = 0 })
                Library:Spring(btnStroke, "Smooth", { Transparency = 0.85 })
                Library:Spring(menuLabel, "Smooth", { TextColor3 = colors.TextStrong })
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
        -- AddWidePanel (full-width panel anchored below columns)
        -- ==============================
        function menu:AddWidePanel(panelOpts)
            panelOpts = panelOpts or {}

            local panelName = string.upper(tostring(panelOpts.Name or panelOpts.Title or "PANEL"))
            local panelHeight = math.max(80, tonumber(panelOpts.Height) or 220)
            local topPadding = math.max(0, tonumber(panelOpts.TopPadding) or 10)
            local sidePadding = math.max(0, tonumber(panelOpts.SidePadding) or 4)
            local headerInset = 10
            local titleOverlapPadding = 8
            local panel = {}
            local panelCleanup = Cleaner.new()

            local panelFrame = Instance.new("Frame", pageFrame)
            panelFrame.Name = "WidePanel_" .. panelName
            panelFrame.BackgroundColor3 = colors.Section
            panelFrame.BorderSizePixel = 0
            panelFrame.Position = UDim2.new(0, sidePadding, 0, 4 + titleOverlapPadding)
            panelFrame.Size = UDim2.new(1, -(sidePadding * 2), 0, panelHeight)
            panelFrame.ZIndex = 4
            panelFrame.ClipsDescendants = false
            bindTheme(panelFrame, "BackgroundColor3", "Section")
            bindTheme(panelFrame, "BackgroundTransparency", "SectionTransparency")
            Instance.new("UICorner", panelFrame).CornerRadius = UDim.new(0, 4)

            local panelTitle = Instance.new("TextLabel", panelFrame)
            panelTitle.Name = "PanelTitle"
            panelTitle.BackgroundTransparency = 1
            panelTitle.Position = UDim2.new(0, 8, 0, -6)
            panelTitle.Size = UDim2.new(1, -16, 0, 18)
            panelTitle.Font = config.Font
            panelTitle.Text = panelName
            panelTitle.TextColor3 = colors.Text
            panelTitle.TextSize = 10
            panelTitle.TextXAlignment = Enum.TextXAlignment.Left
            panelTitle.TextYAlignment = Enum.TextYAlignment.Center
            panelTitle.ZIndex = 7
            bindTheme(panelTitle, "TextColor3", "Text")

            local contentContainer = Instance.new("Frame", panelFrame)
            contentContainer.Name = "Content"
            contentContainer.BackgroundTransparency = 1
            contentContainer.BorderSizePixel = 0
            contentContainer.Position = UDim2.new(0, 0, 0, 0)
            contentContainer.Size = UDim2.new(1, 0, 1, 0)
            contentContainer.ZIndex = 4

            local panelPadding = Instance.new("UIPadding", contentContainer)
            panelPadding.PaddingTop = UDim.new(0, headerInset)
            panelPadding.PaddingBottom = UDim.new(0, 8)
            panelPadding.PaddingLeft = UDim.new(0, 10)
            panelPadding.PaddingRight = UDim.new(0, 10)

            panel.Frame = panelFrame
            panel.Container = contentContainer
            panel.Content = contentContainer
            panel.TitleLabel = panelTitle
            panel._cleanup = panelCleanup
            panel._menu = menu

            function panel:TrackConnection(conn, key)
                return self._cleanup:Add(conn, "Disconnect", key)
            end

            function panel:RefreshLayout()
                if not panelFrame.Parent or not pageFrame.Parent then
                    return
                end

                local bottom = 4
                for _, section in ipairs(menu.Sections) do
                    if section and section.Frame and section.Frame.Parent then
                        local relativeTop = section.Frame.AbsolutePosition.Y - pageFrame.AbsolutePosition.Y
                        bottom = math.max(bottom, relativeTop + section.Frame.AbsoluteSize.Y)
                    end
                end

                panelFrame.Position = UDim2.new(0, sidePadding, 0, math.floor(bottom + topPadding + titleOverlapPadding + 0.5))
                panelFrame.Size = UDim2.new(1, -(sidePadding * 2), 0, panelHeight)
            end

            function panel:Destroy()
                if self._destroyed then
                    return
                end
                self._destroyed = true
                self._cleanup:Cleanup()
                for index = #menu._widePanels, 1, -1 do
                    if menu._widePanels[index] == self then
                        table.remove(menu._widePanels, index)
                        break
                    end
                end
                if panelFrame.Parent then
                    panelFrame:Destroy()
                end
            end

            table.insert(menu._widePanels, panel)
            panel:TrackConnection(pageFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
                panel:RefreshLayout()
            end), nextCleanupKey("WidePanelAbsoluteSize"))
            task.defer(function()
                if panel.RefreshLayout then
                    panel:RefreshLayout()
                end
            end)

            return panel
        end

        -- ==============================
        -- AddSection (auto-height box in a column)
        -- ==============================
        function menu:AddSection(sectionOpts)
            sectionOpts = sectionOpts or {}
            local secName = sectionOpts.Name or sectionOpts.Title or "SECTION"
            local colNum = math.clamp(sectionOpts.Column or 1, 1, numColumns)

            local targetCol = menu._columns[colNum]
            local section = {}
            local sectionCleanup = Cleaner.new()

            -- Section container (The dark panel)
            local secFrame = Instance.new("Frame", targetCol)
            secFrame.Name = "SectionBox_" .. secName
            secFrame.BackgroundColor3 = colors.Section
            secFrame.BorderSizePixel = 0
            secFrame.Size = UDim2.new(1, 0, 0, 30)
            secFrame.AutomaticSize = Enum.AutomaticSize.Y
            secFrame.ClipsDescendants = false
            secFrame.ZIndex = 4
            bindTheme(secFrame, "BackgroundColor3", "Section")
            bindTheme(secFrame, "BackgroundTransparency", "SectionTransparency")

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
            bindTheme(secTitle, "TextColor3", "Text")

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
                fitLabel = controlBase.bindAdaptiveLabel,
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

            local function getLegacySectionConfigKey(controlName)
                return string.format("%s.%s", tostring(secName or "Section"), tostring(controlName or "Control"))
            end

            local function resolveSectionConfigKey(requestedKey, controlName)
                if requestedKey == false then
                    return nil, nil
                end
                if requestedKey ~= nil then
                    return requestedKey, nil
                end

                local legacyKey = getLegacySectionConfigKey(controlName)
                local scopedKey = string.format("%s.%s.%s", tostring(menuName or "Menu"), tostring(secName or "Section"), tostring(controlName or "Control"))
                if scopedKey ~= legacyKey then
                    return scopedKey, { legacyKey }
                end
                return legacyKey, nil
            end

            -- ==============================
            -- AddToggle (checkbox style)
            -- ==============================
            function section:AddToggle(toggleOpts)
                toggleOpts = toggleOpts or {}
                local tName = toggleOpts.Name or toggleOpts.Title or "Toggle"
                local tDefault = toggleOpts.Default or false
                local tCallback = toggleOpts.Callback or function() end
                local tSaveKey = toggleOpts.SaveKey
                local tConfigKey, tConfigAliases = resolveSectionConfigKey(tSaveKey, tName)

                local toggle = { Value = tDefault }

                local row = controlBase.createRow(contentContainer, "Toggle_" .. tName)
                local label = controlBase.createLabel(row, tName, {
                    Font = config.FontMedium,
                    Size = UDim2.new(1, -22, 1, 0),
                    TextColor3 = colors.Text,
                    TextSize = 12,
                    ThemeKey = "Text",
                })
                local checkFrame, checkStroke, checkIcon = controlBase.createCheckbox(row, colors, {
                    Name = "Check",
                    ImageTransparency = tDefault and 0 or 1,
                    ThemeBackgroundKey = "Control",
                    ThemeTransparencyKey = "ControlTransparency",
                    ThemeStrokeKey = "Line",
                    ThemeImageKey = "Main",
                })
                local clickBtn = controlBase.createOverlayButton(row)
                local checkBtn = controlBase.createOverlayButton(row, {
                    Name = "CheckButton",
                    Position = checkFrame.Position,
                    Size = checkFrame.Size,
                    ZIndex = checkFrame.ZIndex + 2,
                })
                checkBtn.AnchorPoint = checkFrame.AnchorPoint

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
                        Library:Spring(checkFrame, "Smooth", { BackgroundColor3 = colors.AccentSurface, BackgroundTransparency = colors.AccentTransparency })
                        Library:Spring(checkStroke, "Smooth", { Color = colors.Main, Transparency = 0.3 })
                        if subContainer then subContainer.Visible = true end
                    else
                        Library:Spring(checkIcon, "Smooth", { ImageTransparency = 1 })
                        Library:Spring(checkFrame, "Smooth", { BackgroundColor3 = colors.Control, BackgroundTransparency = colors.ControlTransparency })
                        Library:Spring(checkStroke, "Smooth", { Color = colors.Line, Transparency = 0.5 })
                        if subContainer then subContainer.Visible = false end
                    end
                end
                onThemeChanged(function()
                    updateVisual()
                end)

                local function setToggleValue(nextValue, shouldMarkDirty)
                    toggle.Value = nextValue and true or false
                    updateVisual()
                    if not callbacksSuppressed() then
                        pcall(tCallback, toggle.Value)
                    end
                    if shouldMarkDirty then
                        Library:_markDirty()
                    end
                end

                toggle = controlBase.attachControlLifecycle(section, toggle, {
                    clickTargets = { clickBtn, checkBtn },
                    getValue = function()
                        return toggle.Value
                    end,
                    onDestroy = function()
                        subContainer = nil
                    end,
                    refresh = updateVisual,
                    root = row,
                    saveKey = tConfigKey,
                    searchName = tName,
                    setValue = function(val)
                        setToggleValue(val == true, true)
                    end,
                    updateDisabled = function(disabled)
                        label.TextTransparency = disabled and 0.35 or 0
                        clickBtn.Active = not disabled
                        checkBtn.Active = not disabled
                    end,
                })

                local function handleToggleActivated()
                    if toggle.Disabled then
                        return
                    end

                    setToggleValue(not toggle.Value, true)
                end

                toggle:TrackConnection(clickBtn.Activated:Connect(handleToggleActivated), "ToggleClick")
                toggle:TrackConnection(checkBtn.Activated:Connect(handleToggleActivated), "ToggleCheckClick")

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
                toggle:TrackConnection(checkBtn.MouseEnter:Connect(function()
                    if toggle.Disabled then
                        return
                    end
                    Library:Spring(label, "Smooth", { TextColor3 = Color3.fromRGB(255, 255, 255) })
                end), "ToggleCheckHoverEnter")
                toggle:TrackConnection(checkBtn.MouseLeave:Connect(function()
                    Library:Spring(label, "Smooth", { TextColor3 = colors.Text })
                end), "ToggleCheckHoverLeave")
                controlBase.bindAdaptiveLabel(toggle, label, {
                    BaseTextSize = 12,
                    MinTextSize = 10,
                    WidthPadding = 2,
                })

                -- Init visual
                updateVisual()
                if keybindManager then
                    keybindManager:AttachToggle(toggle, {
                        ConfigKey = tConfigKey,
                        MenuName = menuName,
                        Name = tName,
                        SectionName = secName,
                        Targets = { clickBtn, checkBtn },
                    })
                end

                -- ==============================
                -- Toggle:AddColorPicker (inline)
                -- ==============================
                function toggle:AddColorPicker(cpOpts)
                    cpOpts = cpOpts or {}
                    local cpName = cpOpts.Name or "Color"
                    local cpDefault = cpOpts.Default or Color3.fromRGB(255, 255, 255)
                    local cpCallback = cpOpts.Callback or function() end
                    local cpSaveKey = cpOpts.SaveKey
                    local cpConfigKey, cpConfigAliases = resolveSectionConfigKey(cpSaveKey, tName .. "_" .. cpName)

                    local cpicker = { Value = cpDefault }
                    local hue, sat, val = cpDefault:ToHSV()

                    local colorBox, boxStroke = controlBase.createRightBox(row, {
                        BackgroundColor3 = cpDefault,
                        ClassName = "TextButton",
                        StrokeColor = colors.Line,
                        StrokeTransparency = 0.3,
                        RightOffset = -24,
                        Width = 18,
                        Height = 18,
                        ZIndex = 20,
                    })

                    clickBtn.Size = UDim2.new(1, -44, 1, 0)
                    label.Size = UDim2.new(1, -44, 1, 0)

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
                        if not callbacksSuppressed() then
                            pcall(cpCallback, c)
                        end
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
                        saveKey = cpConfigKey,
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

                    if cpConfigKey then
                        Library:RegisterConfig(cpConfigKey, "colorpicker",
                            function() return cpicker.Value end,
                            function(val) setColorValue(val, false) end,
                            { Aliases = cpConfigAliases }
                        )
                    end

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
                        configScope = string.format("%s.%s", tostring(secName or "Section"), tostring(tName or "Toggle")),
                        config = config,
                        ensureSubContainer = ensureSubContainer,
                        makeControl = function(control, opts)
                            return controlBase.attachControlLifecycle(section, control, opts)
                        end,
                        menuName = menuName,
                        nextCleanupKey = nextCleanupKey,
                        registerTransientPopup = registerTransientPopup,
                        secName = secName,
                        section = section,
                        trackGlobal = sectionTrackGlobal,
                        win = win,
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
                    local sStep = tonumber(sliderOpts.Step or sliderOpts.Increment)
                    local sPrecision = sliderOpts.Precision
                    if sPrecision == nil then
                        sPrecision = sliderOpts.Decimals
                    end
                    if sPrecision == nil then
                        sPrecision = sliderOpts.Decimal
                    end

                    local function countDecimals(value)
                        if type(value) ~= "number" then
                            return 0
                        end
                        local text = tostring(value)
                        if text:find("[eE]") then
                            text = string.format("%.10f", value):gsub("0+$", ""):gsub("%.$", "")
                        end
                        local decimals = text:match("%.(%d+)")
                        return decimals and #decimals or 0
                    end

                    local function inferPrecision()
                        if type(sPrecision) == "number" then
                            return math.clamp(math.floor(sPrecision + 0.5), 0, 6)
                        end
                        if sStep and sStep > 0 then
                            return math.clamp(countDecimals(sStep), 0, 6)
                        end
                        local inferred = math.max(countDecimals(sMin), countDecimals(sMax), countDecimals(sDefault))
                        if inferred > 0 then
                            return math.clamp(inferred, 0, 6)
                        end
                        if math.abs((sMax - sMin)) <= 1 then
                            return 2
                        end
                        return 0
                    end

                    local precision = inferPrecision()
                    if sStep and sStep <= 0 then
                        sStep = nil
                    end

                    local function quantizeValue(value)
                        local v = math.clamp(tonumber(value) or sMin, sMin, sMax)
                        if sStep then
                            v = sMin + math.floor(((v - sMin) / sStep) + 0.5) * sStep
                        end
                        if precision > 0 then
                            local m = 10 ^ precision
                            v = math.floor(v * m + 0.5) / m
                        else
                            v = math.floor(v + 0.5)
                        end
                        return math.clamp(v, sMin, sMax)
                    end

                    local function formatValue(value)
                        if precision > 0 then
                            return (string.format("%." .. precision .. "f", value):gsub("(%..-)0+$", "%1"):gsub("%.$", ""))
                        end
                        return tostring(math.floor(value + 0.5))
                    end

                    local slider = { Value = quantizeValue(sDefault) }

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
                    bindTheme(sLabel, "TextColor3", "TextDim")

                    local barBg = Instance.new("Frame", sRow)
                    barBg.AnchorPoint = Vector2.new(1, 0.5)
                    barBg.Position = UDim2.new(1, 0, 0.5, 0)
                    barBg.Size = UDim2.new(0.55, 0, 0, 14)
                    barBg.BackgroundColor3 = colors.ControlAlt
                    barBg.BorderSizePixel = 0
                    barBg.ClipsDescendants = true
                    barBg.ZIndex = 5
                    bindTheme(barBg, "BackgroundColor3", "ControlAlt")
                    bindTheme(barBg, "BackgroundTransparency", "ControlTransparency")
                    Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 3)

                    local fill = Instance.new("Frame", barBg)
                    fill.BackgroundColor3 = colors.Main
                    fill.BorderSizePixel = 0
                    local initialRange = (sMax - sMin)
                    local initialAlpha = (initialRange ~= 0) and ((slider.Value - sMin) / initialRange) or 0
                    fill.Size = UDim2.new(initialAlpha, 0, 1, 0)
                    fill.ZIndex = 6
                    bindTheme(fill, "BackgroundColor3", "Main")
                    bindTheme(fill, "BackgroundTransparency", "AccentTransparency")
                    Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 3)

                    local sValLabel = Instance.new("TextLabel", barBg)
                    sValLabel.BackgroundTransparency = 1
                    sValLabel.Size = UDim2.new(1, 0, 1, 0)
                    sValLabel.Font = config.Font
                    sValLabel.Text = formatValue(slider.Value) .. sSuffix
                    sValLabel.TextColor3 = colors.TextStrong
                    sValLabel.TextSize = 11
                    sValLabel.ZIndex = 7
                    bindTheme(sValLabel, "TextColor3", "TextStrong")

                    local dragging = false
                    local function updateSlider(inputX)
                        local bx, bw = barBg.AbsolutePosition.X, barBg.AbsoluteSize.X
                        local relX = math.clamp((inputX - bx) / bw, 0, 1)
                        local val = quantizeValue(sMin + (sMax - sMin) * relX)
                        slider.Value = val
                        local range = (sMax - sMin)
                        local alpha = (range ~= 0) and ((val - sMin) / range) or 0
                        Library:Spring(fill, "Responsive", { Size = UDim2.new(alpha, 0, 1, 0) })
                        sValLabel.Text = formatValue(val) .. sSuffix
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
                    controlBase.bindAdaptiveLabel(toggle, sLabel, {
                        BaseTextSize = 11,
                        MinTextSize = 9,
                        WidthPadding = 2,
                    })

                    return slider
                end

                -- Register for config save/load
                if tConfigKey then
                    Library:RegisterConfig(tConfigKey, "toggle",
                        function() return toggle.Value end,
                        function(val)
                            setToggleValue(val == true, false)
                        end,
                        { Aliases = tConfigAliases }
                    )
                end

                return toggle
            end

            -- ==============================
            -- AddSlider (draggable bar)
            -- ==============================
            function section:AddSlider(sliderOpts)
                sliderOpts = sliderOpts or {}
                local sName = sliderOpts.Name or sliderOpts.Title or "Slider"
                local sMin = sliderOpts.Min or 0
                local sMax = sliderOpts.Max or 100
                local sDefault = math.clamp(sliderOpts.Default or sMin, sMin, sMax)
                local sSuffix = sliderOpts.Suffix or "%"
                local sCallback = sliderOpts.Callback or function() end
                local sSaveKey = sliderOpts.SaveKey
                local sConfigKey, sConfigAliases = resolveSectionConfigKey(sSaveKey, sName)
                local sStep = tonumber(sliderOpts.Step or sliderOpts.Increment)
                local sPrecision = sliderOpts.Precision
                if sPrecision == nil then
                    sPrecision = sliderOpts.Decimals
                end
                if sPrecision == nil then
                    sPrecision = sliderOpts.Decimal
                end

                local function countDecimals(value)
                    if type(value) ~= "number" then
                        return 0
                    end
                    local text = tostring(value)
                    if text:find("[eE]") then
                        text = string.format("%.10f", value):gsub("0+$", ""):gsub("%.$", "")
                    end
                    local decimals = text:match("%.(%d+)")
                    return decimals and #decimals or 0
                end

                local function inferPrecision()
                    if type(sPrecision) == "number" then
                        return math.clamp(math.floor(sPrecision + 0.5), 0, 6)
                    end
                    if sStep and sStep > 0 then
                        return math.clamp(countDecimals(sStep), 0, 6)
                    end
                    local inferred = math.max(countDecimals(sMin), countDecimals(sMax), countDecimals(sDefault))
                    if inferred > 0 then
                        return math.clamp(inferred, 0, 6)
                    end
                    if math.abs((sMax - sMin)) <= 1 then
                        return 2
                    end
                    return 0
                end

                local precision = inferPrecision()
                if sStep and sStep <= 0 then
                    sStep = nil
                end

                local function quantizeValue(value)
                    local v = math.clamp(tonumber(value) or sMin, sMin, sMax)
                    if sStep then
                        v = sMin + math.floor(((v - sMin) / sStep) + 0.5) * sStep
                    end
                    if precision > 0 then
                        local m = 10 ^ precision
                        v = math.floor(v * m + 0.5) / m
                    else
                        v = math.floor(v + 0.5)
                    end
                    return math.clamp(v, sMin, sMax)
                end

                local function formatValue(value)
                    if precision > 0 then
                        return (string.format("%." .. precision .. "f", value):gsub("(%..-)0+$", "%1"):gsub("%.$", ""))
                    end
                    return tostring(math.floor(value + 0.5))
                end

                local slider = { Value = quantizeValue(sDefault) }

                local row = controlBase.createRow(contentContainer, "Slider_" .. sName)
                local label = controlBase.createLabel(row, sName, {
                    Font = config.FontMedium,
                    Size = UDim2.new(0.4, 0, 1, 0),
                    TextColor3 = colors.Text,
                    TextSize = 12,
                    ThemeKey = "Text",
                })

                -- Slider bar background (right side)
                local barBg = Instance.new("Frame", row)
                barBg.Name = "BarBg"
                barBg.AnchorPoint = Vector2.new(1, 0.5)
                barBg.Position = UDim2.new(1, 0, 0.5, 0)
                barBg.Size = UDim2.new(0.55, 0, 0, 16)
                barBg.BackgroundColor3 = colors.ControlAlt
                barBg.BorderSizePixel = 0
                barBg.ClipsDescendants = true
                barBg.ZIndex = 5
                bindTheme(barBg, "BackgroundColor3", "ControlAlt")
                bindTheme(barBg, "BackgroundTransparency", "ControlTransparency")

                Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 3)

                -- Fill bar (pink)
                local fill = Instance.new("Frame", barBg)
                fill.Name = "Fill"
                fill.BackgroundColor3 = colors.Main
                fill.BorderSizePixel = 0
                local initialRange = (sMax - sMin)
                local initialAlpha = (initialRange ~= 0) and ((slider.Value - sMin) / initialRange) or 0
                fill.Size = UDim2.new(initialAlpha, 0, 1, 0)
                fill.ZIndex = 6
                bindTheme(fill, "BackgroundColor3", "Main")
                bindTheme(fill, "BackgroundTransparency", "AccentTransparency")

                Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 3)

                -- Value text (inside bar, centered)
                local valLabel = Instance.new("TextLabel", barBg)
                valLabel.Name = "Value"
                valLabel.BackgroundTransparency = 1
                valLabel.Size = UDim2.new(1, 0, 1, 0)
                valLabel.Font = config.Font
                valLabel.Text = formatValue(slider.Value) .. sSuffix
                valLabel.TextColor3 = colors.TextStrong
                valLabel.TextSize = 12
                valLabel.ZIndex = 7
                bindTheme(valLabel, "TextColor3", "TextStrong")

                -- Drag interaction
                local dragging = false

                local function updateSlider(inputX)
                    local barAbsPos = barBg.AbsolutePosition.X
                    local barAbsSize = barBg.AbsoluteSize.X
                    local relX = math.clamp((inputX - barAbsPos) / barAbsSize, 0, 1)
                    local rawVal = sMin + (sMax - sMin) * relX
                    local val = quantizeValue(rawVal)
                    slider.Value = val
                    local range = (sMax - sMin)
                    local alpha = (range ~= 0) and ((val - sMin) / range) or 0
                    Library:Spring(fill, "Responsive", { Size = UDim2.new(alpha, 0, 1, 0) })
                    valLabel.Text = formatValue(val) .. sSuffix
                    if not callbacksSuppressed() then
                        pcall(sCallback, val)
                    end
                    Library:_markDirty()
                end

                local function setSliderValue(val, shouldMarkDirty)
                    val = quantizeValue(val)
                    local range = (sMax - sMin)
                    local relX = (range ~= 0) and ((val - sMin) / range) or 0
                    slider.Value = val
                    Library:Spring(fill, "Responsive", { Size = UDim2.new(relX, 0, 1, 0) })
                    valLabel.Text = formatValue(slider.Value) .. sSuffix
                    if not callbacksSuppressed() then
                        pcall(sCallback, slider.Value)
                    end
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
                    saveKey = sConfigKey,
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
                controlBase.bindAdaptiveLabel(slider, label, {
                    BaseTextSize = 12,
                    MinTextSize = 10,
                    WidthPadding = 2,
                })

                -- Register for config save/load
                if sConfigKey then
                    Library:RegisterConfig(sConfigKey, "slider",
                        function() return slider.Value end,
                        function(val)
                            setSliderValue(val, false)
                        end,
                        { Aliases = sConfigAliases }
                    )
                end

                return slider
            end

            -- ==============================
            -- AddMultiDropdown (multi-select)
            -- ==============================
            function section:AddMultiDropdown(dropOpts)
                return dropdownControls.addMultiDropdown(sectionDropdownBase, dropOpts)
            end

            function section:AddMultiDropdownToggle(opts)
                opts = opts or {}
                local mtName = opts.Name or opts.Title or "Multi Select Toggle"
                local mtOptions = opts.Options or opts.Items or { "Option 1", "Option 2" }
                local mtDefault = opts.Default or {}
                local mtEnabled = (opts.Enabled ~= nil and opts.Enabled)
                    or (opts.DefaultToggle ~= nil and opts.DefaultToggle)
                    or false
                local mtSaveKey = opts.SaveKey
                local mtToggleName = opts.ToggleName or (mtName .. " Enabled")
                local mtCallback = opts.Callback or function() end

                if type(mtSaveKey) == "string" and mtSaveKey ~= "" and type(Library._GetSetting) == "function" then
                    local saved = Library:_GetSetting(mtSaveKey, nil)
                    if type(saved) == "table" then
                        if saved.selections ~= nil then
                            mtDefault = saved.selections
                        elseif saved.selected ~= nil then
                            mtDefault = saved.selected
                        end
                        if saved.toggled ~= nil then
                            mtEnabled = saved.toggled and true or false
                        elseif saved.enabled ~= nil then
                            mtEnabled = saved.enabled and true or false
                        end
                    end
                end

                local selectedValues = {}
                local isEnabled = mtEnabled and true or false
                local control = {}
                local syncDepth = 0

                local function beginSync()
                    syncDepth += 1
                end

                local function finishSync()
                    if syncDepth > 0 then
                        syncDepth -= 1
                    end
                end

                local function isSyncing()
                    return syncDepth > 0
                end

                local function buildSelectionLookup(raw)
                    local lookup = {}
                    if type(raw) ~= "table" then
                        if raw ~= nil then
                            lookup[raw] = true
                        end
                        return lookup
                    end
                    if #raw > 0 then
                        for _, value in ipairs(raw) do
                            if value ~= nil then
                                lookup[value] = true
                            end
                        end
                        return lookup
                    end
                    for key, enabled in pairs(raw) do
                        if enabled then
                            lookup[key] = true
                        end
                    end
                    return lookup
                end

                local function selectionsEqual(left, right)
                    local leftLookup = buildSelectionLookup(left)
                    local rightLookup = buildSelectionLookup(right)
                    for key, enabled in pairs(leftLookup) do
                        if enabled ~= (rightLookup[key] and true or false) then
                            return false
                        end
                    end
                    for key, enabled in pairs(rightLookup) do
                        if enabled ~= (leftLookup[key] and true or false) then
                            return false
                        end
                    end
                    return true
                end

                local function persistState()
                    if type(mtSaveKey) == "string" and mtSaveKey ~= "" and type(Library.SetSaveKey) == "function" then
                        Library:SetSaveKey(mtSaveKey, {
                            selections = selectedValues,
                            toggled = isEnabled,
                            enabled = isEnabled,
                        })
                    end
                end

                local multi = section:AddMultiDropdown({
                    Name = mtName,
                    Options = mtOptions,
                    Default = mtDefault,
                    Callback = function(list, selectedMap)
                        selectedValues = list or {}
                        if isSyncing() then
                            return
                        end
                        persistState()
                        if not callbacksSuppressed() then
                            pcall(mtCallback, isEnabled, selectedValues, selectedMap)
                        end
                    end,
                })
                selectedValues = multi:Get() or {}

                local toggle = section:AddToggle({
                    Name = mtToggleName,
                    Default = isEnabled,
                    Callback = function(state)
                        isEnabled = state and true or false
                        if isSyncing() then
                            return
                        end
                        persistState()
                        if not callbacksSuppressed() then
                            pcall(mtCallback, isEnabled, selectedValues)
                        end
                    end,
                })

                control.Multi = multi
                control.Toggle = toggle

                function control:Get()
                    return {
                        selections = selectedValues,
                        toggled = isEnabled,
                        enabled = isEnabled,
                    }
                end

                function control:Set(value)
                    if type(value) ~= "table" then
                        return control
                    end
                    local nextSelections = nil
                    if value.selections ~= nil then
                        nextSelections = value.selections
                    elseif value.selected ~= nil then
                        nextSelections = value.selected
                    end
                    local nextEnabled = nil
                    if value.toggled ~= nil then
                        nextEnabled = value.toggled and true or false
                    elseif value.enabled ~= nil then
                        nextEnabled = value.enabled and true or false
                    end
                    if (nextSelections == nil or selectionsEqual(selectedValues, nextSelections))
                        and (nextEnabled == nil or isEnabled == nextEnabled) then
                        return control
                    end
                    beginSync()
                    if value.selections ~= nil then
                        multi:Set(value.selections)
                        selectedValues = multi:Get() or selectedValues
                    elseif value.selected ~= nil then
                        multi:Set(value.selected)
                        selectedValues = multi:Get() or selectedValues
                    end
                    if value.toggled ~= nil then
                        toggle:Set(value.toggled and true or false)
                        isEnabled = toggle:Get() and true or false
                    elseif value.enabled ~= nil then
                        toggle:Set(value.enabled and true or false)
                        isEnabled = toggle:Get() and true or false
                    end
                    finishSync()
                    return control
                end

                control.GetSelections = function()
                    return selectedValues
                end
                control.SetSelection = function(value)
                    if selectionsEqual(selectedValues, value) then
                        return control
                    end
                    beginSync()
                    multi:Set(value)
                    selectedValues = multi:Get() or selectedValues
                    finishSync()
                    return control
                end
                control.SetValues = control.SetSelection
                control.SetValue = control.SetSelection
                control.GetToggleState = function()
                    return isEnabled
                end
                control.SetToggleState = function(value)
                    local nextValue = value and true or false
                    if isEnabled == nextValue then
                        return control
                    end
                    beginSync()
                    toggle:Set(nextValue)
                    isEnabled = toggle:Get() and true or false
                    finishSync()
                    return control
                end
                control.GetState = control.GetToggleState
                control.SetState = control.SetToggleState

                if type(mtSaveKey) == "string" and mtSaveKey ~= "" then
                    Library._widgetRegistry = Library._widgetRegistry or {}
                    Library._widgetRegistry[mtSaveKey] = control
                end

                persistState()
                return control
            end

            -- ==============================
            -- AddSliderToggle (slider + checkbox)
            -- ==============================
            function section:AddSliderToggle(opts)
                opts = opts or {}
                local sName = opts.Name or opts.Title or "Slider"
                local sMin = opts.Min or 0
                local sMax = opts.Max or 100
                local sDefault = math.clamp(opts.Default or sMin, sMin, sMax)
                local sSuffix = opts.Suffix or "%"
                local sStep = tonumber(opts.Step or opts.Increment)
                local sPrecision = opts.Precision
                if sPrecision == nil then
                    sPrecision = opts.Decimals
                end
                if sPrecision == nil then
                    sPrecision = opts.Decimal
                end
                local sEnabled = opts.Enabled
                if sEnabled == nil then
                    if opts.DefaultToggle ~= nil then
                        sEnabled = opts.DefaultToggle
                    else
                        sEnabled = true
                    end
                end
                local sCallback = opts.Callback or opts.OnSliderChange or function() end
                local sToggleCallback = opts.OnToggle or opts.OnToggleChange or function() end
                local sSaveKey = opts.SaveKey
                local sConfigKey, sConfigAliases = resolveSectionConfigKey(sSaveKey, sName)

                local function countDecimals(value)
                    if type(value) ~= "number" then
                        return 0
                    end
                    local text = tostring(value)
                    if text:find("[eE]") then
                        text = string.format("%.10f", value):gsub("0+$", ""):gsub("%.$", "")
                    end
                    local decimals = text:match("%.(%d+)")
                    return decimals and #decimals or 0
                end

                local function inferPrecision()
                    if type(sPrecision) == "number" then
                        return math.clamp(math.floor(sPrecision + 0.5), 0, 6)
                    end
                    if sStep and sStep > 0 then
                        return math.clamp(countDecimals(sStep), 0, 6)
                    end
                    local inferred = math.max(countDecimals(sMin), countDecimals(sMax), countDecimals(sDefault))
                    if inferred > 0 then
                        return math.clamp(inferred, 0, 6)
                    end
                    if math.abs((sMax - sMin)) <= 1 then
                        return 2
                    end
                    return 0
                end

                local precision = inferPrecision()
                if sStep and sStep <= 0 then
                    sStep = nil
                end

                local function quantizeValue(value)
                    local v = math.clamp(tonumber(value) or sMin, sMin, sMax)
                    if sStep then
                        v = sMin + math.floor(((v - sMin) / sStep) + 0.5) * sStep
                    end
                    if precision > 0 then
                        local m = 10 ^ precision
                        v = math.floor(v * m + 0.5) / m
                    else
                        v = math.floor(v + 0.5)
                    end
                    return math.clamp(v, sMin, sMax)
                end

                local function formatValue(value)
                    if precision > 0 then
                        return (string.format("%." .. precision .. "f", value):gsub("(%..-)0+$", "%1"):gsub("%.$", ""))
                    end
                    return tostring(math.floor(value + 0.5))
                end

                local st = { Value = quantizeValue(sDefault), Enabled = sEnabled }

                local row = controlBase.createRow(contentContainer, "SliderToggle_" .. sName)
                local label = controlBase.createLabel(row, sName, {
                    Font = config.FontMedium,
                    Size = UDim2.new(0.3, 0, 1, 0),
                    TextColor3 = colors.Text,
                    TextSize = 12,
                })
                label.TextTruncate = Enum.TextTruncate.AtEnd
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

                local function layoutSliderToggle()
                    local rowWidth = row.AbsoluteSize.X
                    if rowWidth <= 0 then
                        return
                    end

                    local checkboxInset = 24
                    local labelGap = 8
                    local minLabelWidth = 72
                    local minBarWidth = 108
                    local textWidth = TextService:GetTextSize(
                        tostring(sName),
                        label.TextSize,
                        label.Font,
                        Vector2.new(1000, row.AbsoluteSize.Y > 0 and row.AbsoluteSize.Y or 22)
                    ).X + 8

                    local maxLabelWidth = math.max(minLabelWidth, rowWidth - checkboxInset - labelGap - minBarWidth)
                    local labelWidth = math.clamp(textWidth, minLabelWidth, maxLabelWidth)
                    local barWidth = math.max(minBarWidth, rowWidth - labelWidth - checkboxInset - labelGap)

                    label.Size = UDim2.new(0, labelWidth, 1, 0)
                    barBg.Size = UDim2.new(0, barWidth, 0, 16)
                end

                local fill = Instance.new("Frame", barBg)
                fill.BackgroundColor3 = colors.Main
                fill.BorderSizePixel = 0
                local initialRange = (sMax - sMin)
                local initialAlpha = (initialRange ~= 0) and ((st.Value - sMin) / initialRange) or 0
                fill.Size = UDim2.new(initialAlpha, 0, 1, 0)
                fill.ZIndex = 6
                Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 3)

                local valLabel = Instance.new("TextLabel", barBg)
                valLabel.BackgroundTransparency = 1
                valLabel.Size = UDim2.new(1, 0, 1, 0)
                valLabel.Font = config.Font
                valLabel.Text = formatValue(st.Value) .. sSuffix
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

                    if not callbacksSuppressed() then
                        pcall(sToggleCallback, st.Enabled)
                    end
                    if shouldMarkDirty then
                        Library:_markDirty()
                    end
                end

                local function setSliderValue(val, shouldMarkDirty)
                    st.Value = quantizeValue(val)
                    local range = (sMax - sMin)
                    local relX = (range ~= 0) and ((st.Value - sMin) / range) or 0
                    Library:Spring(fill, "Responsive", { Size = UDim2.new(relX, 0, 1, 0) })
                    valLabel.Text = formatValue(st.Value) .. sSuffix
                    if not callbacksSuppressed() then
                        pcall(sCallback, st.Value)
                    end
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
                    saveKey = sConfigKey,
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

                st.GetSliderValue = function()
                    return st.Value
                end
                st.SetSliderValue = function(value)
                    st:Set({ value = value })
                    return st
                end
                st.GetToggleState = function()
                    return st.Enabled and true or false
                end
                st.SetToggleState = function(value)
                    st:Set({ enabled = value and true or false })
                    return st
                end

                st:TrackConnection(row:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutSliderToggle), "SliderToggleLayout")
                task.defer(function()
                    if row.Parent then
                        layoutSliderToggle()
                    end
                end)
                controlBase.bindAdaptiveLabel(st, label, {
                    BaseTextSize = 12,
                    MinTextSize = 9,
                    WidthPadding = 2,
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
                if sConfigKey then
                    Library:RegisterConfig(sConfigKey, "slidertoggle",
                        function() return { value = st.Value, enabled = st.Enabled } end,
                        function(val)
                            if type(val) ~= "table" then return end
                            if val.value ~= nil then
                                setSliderValue(val.value, false)
                            end
                            if val.enabled ~= nil then
                                applyEnabled(val.enabled, false)
                            end
                        end,
                        { Aliases = sConfigAliases }
                    )
                end

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
                local bName = btnOpts.Name or btnOpts.Title or "Button"
                local bCallback = btnOpts.Callback or function() end

                local buttonControl = {}
                local row = controlBase.createRow(contentContainer, "Button_" .. bName)
                local label = controlBase.createLabel(row, bName, {
                    Font = config.FontMedium,
                    Size = UDim2.new(1, -24, 1, 0),
                    TextColor3 = colors.Text,
                    TextSize = 12,
                    ThemeKey = "Text",
                })

                -- Button box (right side)
                local btnBox, boxStroke = controlBase.createRightBox(row, {
                    ClassName = "TextButton",
                    StrokeColor = colors.Line,
                    StrokeTransparency = 0.5,
                    ThemeBackgroundKey = "Control",
                    ThemeTransparencyKey = "ControlTransparency",
                    ThemeStrokeKey = "Line",
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
                bindTheme(icon, "ImageColor3", "TextDim")

                local rowBtn = controlBase.createOverlayButton(row, {
                    Name = "ButtonRow",
                    ZIndex = 7,
                })
                btnBox.ZIndex = 8
                icon.ZIndex = 9

                local function flashButton()
                    Library:Spring(btnBox, "Smooth", { BackgroundColor3 = colors.Main, BackgroundTransparency = colors.AccentTransparency })
                    task.delay(0.2, function()
                        if btnBox.Parent then
                            Library:Spring(btnBox, "Smooth", { BackgroundColor3 = colors.Control, BackgroundTransparency = colors.ControlTransparency })
                        end
                    end)
                end

                buttonControl = controlBase.attachControlLifecycle(section, buttonControl, {
                    clickTargets = { btnBox, rowBtn },
                    root = row,
                    saveKey = btnOpts.SaveKey,
                    searchName = bName,
                    updateDisabled = function(disabled)
                        label.TextTransparency = disabled and 0.35 or 0
                        btnBox.Active = not disabled
                        rowBtn.Active = not disabled
                        icon.ImageTransparency = disabled and 0.4 or 0
                    end,
                })

                -- Hover
                local function onHoverEnter()
                    if buttonControl.Disabled then
                        return
                    end
                    Library:Spring(boxStroke, "Smooth", { Color = colors.Main, Transparency = 0.3 })
                    Library:Spring(icon, "Smooth", { ImageColor3 = colors.Main })
                    Library:Spring(label, "Smooth", { TextColor3 = colors.Main })
                end
                local function onHoverLeave()
                    Library:Spring(boxStroke, "Smooth", { Color = colors.Line, Transparency = 0.5 })
                    Library:Spring(icon, "Smooth", { ImageColor3 = colors.TextDim })
                    Library:Spring(label, "Smooth", { TextColor3 = colors.Text })
                end

                buttonControl:TrackConnection(btnBox.MouseEnter:Connect(onHoverEnter), "ButtonHoverEnter")
                buttonControl:TrackConnection(rowBtn.MouseEnter:Connect(onHoverEnter), "ButtonRowHoverEnter")
                buttonControl:TrackConnection(btnBox.MouseLeave:Connect(onHoverLeave), "ButtonHoverLeave")
                buttonControl:TrackConnection(rowBtn.MouseLeave:Connect(onHoverLeave), "ButtonRowHoverLeave")

                -- Click
                local function activateButton()
                    if buttonControl.Disabled then
                        return
                    end

                    flashButton()
                    pcall(bCallback)
                end

                buttonControl:TrackConnection(btnBox.Activated:Connect(activateButton), "ButtonActivated")
                buttonControl:TrackConnection(rowBtn.Activated:Connect(activateButton), "ButtonRowActivated")
                controlBase.bindAdaptiveLabel(buttonControl, label, {
                    BaseTextSize = 12,
                    MinTextSize = 10,
                    WidthPadding = 2,
                })

                function buttonControl:Fire()
                    flashButton()
                    return bCallback()
                end

                return buttonControl
            end

            function section:AddInputBox(inputOpts)
                inputOpts = inputOpts or {}
                local iName = inputOpts.Name or inputOpts.Title or "Input"
                local iCallback = inputOpts.Callback or function() end
                local iSaveKey = inputOpts.SaveKey
                local iConfigKey, iConfigAliases = resolveSectionConfigKey(iSaveKey, iName)

                local function normalizeInputText(value, fallbackText)
                    if value == nil then
                        return fallbackText or ""
                    end
                    local valueType = typeof(value)
                    if valueType == "string" then
                        return value
                    end
                    if valueType == "number" or valueType == "boolean" then
                        return tostring(value)
                    end
                    if valueType == "table" then
                        local candidate = value.Text
                        if candidate == nil then
                            candidate = value.text
                        end
                        if candidate == nil then
                            candidate = value.Value
                        end
                        if candidate == nil then
                            candidate = value.value
                        end
                        if candidate ~= nil then
                            return normalizeInputText(candidate, fallbackText)
                        end
                        return fallbackText or ""
                    end
                    return fallbackText or ""
                end

                local iDefault = normalizeInputText(inputOpts.Default, normalizeInputText(inputOpts.Placeholder, ""))

                local inputControl = { Value = iDefault }
                local row = controlBase.createRow(contentContainer, "Input_" .. iName)
                local label = controlBase.createLabel(row, iName, {
                    Font = config.FontMedium,
                    Size = UDim2.new(0.35, 0, 1, 0),
                    TextColor3 = colors.Text,
                    TextSize = 12,
                    ThemeKey = "Text",
                })

                local box = Instance.new("TextBox", row)
                box.AnchorPoint = Vector2.new(1, 0.5)
                box.Position = UDim2.new(1, 0, 0.5, 0)
                box.Size = UDim2.new(0.62, 0, 0, 18)
                box.BackgroundColor3 = colors.ControlAlt
                box.BorderSizePixel = 0
                box.TextXAlignment = Enum.TextXAlignment.Left
                box.Font = config.FontMedium
                box.TextSize = 11
                box.TextColor3 = colors.Text
                box.ClearTextOnFocus = inputOpts.ClearTextOnFocus == true
                box.PlaceholderText = tostring(inputOpts.Placeholder or "")
                box.Text = iDefault
                box.ZIndex = 6
                Instance.new("UICorner", box).CornerRadius = UDim.new(0, 3)
                bindTheme(box, "BackgroundColor3", "ControlAlt")
                bindTheme(box, "BackgroundTransparency", "ControlTransparency")
                bindTheme(box, "TextColor3", "Text")
                bindTheme(box, "PlaceholderColor3", "TextMuted")

                local function applyInputValue(rawValue, fireCallback, shouldMarkDirty)
                    local nextText = normalizeInputText(rawValue, "")
                    local changed = inputControl.Value ~= nextText or box.Text ~= nextText

                    inputControl.Value = nextText
                    if box.Text ~= nextText then
                        box.Text = nextText
                    end

                    if fireCallback and not callbacksSuppressed() then
                        pcall(iCallback, nextText)
                    end
                    if changed and shouldMarkDirty then
                        Library:_markDirty()
                    end

                    return changed
                end

                inputControl = controlBase.attachControlLifecycle(section, inputControl, {
                    clickTargets = { box },
                    getValue = function()
                        return inputControl.Value
                    end,
                    refresh = function()
                        applyInputValue(inputControl.Value, false, false)
                    end,
                    root = row,
                    saveKey = iConfigKey,
                    searchName = iName,
                    setValue = function(value)
                        applyInputValue(value, true, true)
                    end,
                    updateDisabled = function(disabled)
                        label.TextTransparency = disabled and 0.35 or 0
                        box.Active = not disabled
                        box.TextEditable = not disabled
                    end,
                })

                inputControl.Object = box
                inputControl.GetText = function()
                    return box.Text
                end
                inputControl.SetText = function(value)
                    inputControl:Set(value)
                    return inputControl
                end

                inputControl:TrackConnection(box.FocusLost:Connect(function()
                    if inputControl.Disabled then
                        return
                    end
                    applyInputValue(box.Text, true, true)
                end), "InputBoxFocusLost")
                controlBase.bindAdaptiveLabel(inputControl, label, {
                    BaseTextSize = 12,
                    MinTextSize = 10,
                    WidthPadding = 2,
                })

                if iConfigKey then
                    Library:RegisterConfig(iConfigKey, "input",
                        function()
                            return inputControl.Value
                        end,
                        function(value)
                            applyInputValue(value, false, false)
                        end,
                        { Aliases = iConfigAliases }
                    )
                end

                return inputControl
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
                local cpConfigKey, cpConfigAliases = resolveSectionConfigKey(cpSaveKey, cpName)

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
                    if not callbacksSuppressed() then
                        pcall(cpCallback, c)
                    end
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
                    saveKey = cpConfigKey,
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
                if cpConfigKey then
                    Library:RegisterConfig(cpConfigKey, "colorpicker",
                        function()
                            local c = cpicker.Value
                            return { R = math.floor(c.R * 255), G = math.floor(c.G * 255), B = math.floor(c.B * 255) }
                        end,
                        function(v)
                            setColorValue(v, false)
                        end,
                        { Aliases = cpConfigAliases }
                    )
                end
                controlBase.bindAdaptiveLabel(cpicker, label, {
                    BaseTextSize = 12,
                    MinTextSize = 10,
                    WidthPadding = 2,
                })

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
                controlBase.bindAdaptiveLabel(hitbox, label, {
                    BaseTextSize = 12,
                    MinTextSize = 10,
                    WidthPadding = 2,
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

    function win:_ensureSettingsMenu()
        if self._settingsMenu then
            return self._settingsMenu
        end

        local settingsMenu = self:AddMenu({
            Name = "SETTINGS",
            Columns = 2,
        })
        self._settingsMenu = settingsMenu

        local uiFunctionSection = settingsMenu:AddSection({
            Name = "UI FUNCTION SETTINGS",
            Column = 1,
        })
        local uiVisualColorSection = settingsMenu:AddSection({
            Name = "UI VISUAL COLORS",
            Column = 1,
        })
        local uiVisualTransparencySection = settingsMenu:AddSection({
            Name = "UI VISUAL TRANSPARENCY",
            Column = 2,
        })
        local uiVisualConfigSection = settingsMenu:AddSection({
            Name = "VISUAL SETTINGS CONFIG",
            Column = 2,
        })

        local uiScaleOptions = {}
        for _, option in ipairs(contentScaleOptions) do
            table.insert(uiScaleOptions, option.Label)
        end

        uiFunctionSection:AddToggle({
            Name = "Auto Save UI",
            Default = Library._autoSave,
            Callback = function(enabled)
                Library._autoSave = enabled and true or false
                pcall(function()
                    Library:SaveConfig()
                    Library:SaveTheme()
                end)
            end,
        })

        uiFunctionSection:AddToggle({
            Name = "Show Keybind List",
            Default = keybindManager and keybindManager:GetListEnabled() or true,
            SaveKey = false,
            Callback = function(enabled)
                if keybindManager then
                    keybindManager:SetListEnabled(enabled, true)
                end
            end,
        })

        uiFunctionSection:AddButton({
            Name = "Save UI Config",
            Callback = function()
                pcall(function()
                    Library:SaveConfig()
                    Library:SaveTheme()
                end)
            end,
        })

        uiFunctionSection:AddButton({
            Name = "Load UI Config",
            Callback = function()
                pcall(function()
                    Library:LoadTheme()
                    Library:LoadConfig()
                end)
            end,
        })

        uiFunctionSection:AddDropdown({
            Name = "Content Scale",
            Options = uiScaleOptions,
            Default = getContentScaleOption(currentContentScale).Label,
            Callback = function(selected)
                setContentScale(selected)
            end,
        })

        uiFunctionSection:AddDropdown({
            Name = "Toggle Key",
            Options = { "Insert", "RightShift", "LeftAlt", "RightAlt", "Home", "End" },
            Default = config.ToggleKey.Name,
            Callback = function(selected)
                local keyCode = Enum.KeyCode[selected]
                if keyCode then
                    config.ToggleKey = keyCode
                end
            end,
        })

        local colorThemeControls = {
            { Name = "Accent", Key = "Main" },
            { Name = "Window Background", Key = "Background" },
            { Name = "Top Bar", Key = "Header" },
            { Name = "Bottom Bar", Key = "Bottom" },
            { Name = "Section Background", Key = "Section" },
            { Name = "Panel Background", Key = "Panel" },
            { Name = "Control Background", Key = "Control" },
            { Name = "Slider Background", Key = "ControlAlt" },
            { Name = "Hover Background", Key = "ControlHover" },
            { Name = "Check Background", Key = "AccentSurface" },
            { Name = "Border / Line", Key = "Line" },
            { Name = "Main Text", Key = "Text" },
            { Name = "Dim Text", Key = "TextDim" },
            { Name = "Muted Text", Key = "TextMuted" },
            { Name = "Strong Text", Key = "TextStrong" },
            { Name = "Title Stroke", Key = "TitleStroke" },
        }

        for _, entry in ipairs(colorThemeControls) do
            uiVisualColorSection:AddColorPicker({
                Name = entry.Name,
                Default = Library:GetThemeValue(entry.Key),
                Callback = function(value)
                    Library:SetThemeValue(entry.Key, value)
                end,
            })
        end

        local transparencyThemeControls = {
            { Name = "Window Transparency", Key = "BackgroundTransparency", Default = Library:GetThemeValue("BackgroundTransparency") or 0 },
            { Name = "Top Bar Transparency", Key = "HeaderTransparency", Default = Library:GetThemeValue("HeaderTransparency") or 0 },
            { Name = "Bottom Bar Transparency", Key = "BottomTransparency", Default = Library:GetThemeValue("BottomTransparency") or 0 },
            { Name = "Section Transparency", Key = "SectionTransparency", Default = Library:GetThemeValue("SectionTransparency") or 0 },
            { Name = "Panel Transparency", Key = "PanelTransparency", Default = Library:GetThemeValue("PanelTransparency") or 0 },
            { Name = "Control Transparency", Key = "ControlTransparency", Default = Library:GetThemeValue("ControlTransparency") or 0 },
            { Name = "Accent Transparency", Key = "AccentTransparency", Default = Library:GetThemeValue("AccentTransparency") or 0 },
            { Name = "Shadow Transparency", Key = "ShadowTransparency", Default = Library:GetThemeValue("ShadowTransparency") or 0.75 },
        }

        for _, entry in ipairs(transparencyThemeControls) do
            uiVisualTransparencySection:AddSlider({
                Name = entry.Name,
                Min = 0,
                Max = 100,
                Default = math.floor((entry.Default or 0) * 100 + 0.5),
                Suffix = "%",
                Callback = function(value)
                    Library:SetThemeValue(entry.Key, value / 100)
                end,
            })
        end

        local function getPresetName(rawValue)
            local valueType = type(rawValue)
            if valueType == "table" then
                rawValue = rawValue.Name or rawValue.name or rawValue.label or rawValue.Label
                valueType = type(rawValue)
            end
            if valueType ~= "string" and valueType ~= "number" then
                return nil
            end

            local text = tostring(rawValue or ""):match("^%s*(.-)%s*$")
            if text == "" or text == "No Presets" then
                return nil
            end
            if text:sub(1, 6):lower() == "table:" then
                return nil
            end
            return text
        end

        local presetNameInput = uiVisualConfigSection:AddInputBox({
            Name = "Preset Name",
            Placeholder = "my_theme",
            Default = "",
            SaveKey = false,
        })

        local presetDropdown = uiVisualConfigSection:AddDropdown({
            Name = "Saved Presets",
            Options = { "No Presets" },
            Default = "No Presets",
            SaveKey = false,
            Callback = function(selected)
                local presetName = getPresetName(selected)
                if presetName then
                    presetNameInput:SetText(presetName)
                end
            end,
        })

        local presetStatusTone = "neutral"
        local presetStatusMessage = "Ready"

        local presetStatusRow = Instance.new("Frame", uiVisualConfigSection.Container)
        presetStatusRow.Name = "PresetStatus"
        presetStatusRow.BackgroundTransparency = 1
        presetStatusRow.BorderSizePixel = 0
        presetStatusRow.Size = UDim2.new(1, 0, 0, 18)
        presetStatusRow.ZIndex = 5

        local presetStatusLabel = Instance.new("TextLabel", presetStatusRow)
        presetStatusLabel.Name = "StatusLabel"
        presetStatusLabel.BackgroundTransparency = 1
        presetStatusLabel.BorderSizePixel = 0
        presetStatusLabel.Size = UDim2.new(1, 0, 1, 0)
        presetStatusLabel.Font = config.FontMedium
        presetStatusLabel.Text = ""
        presetStatusLabel.TextSize = 11
        presetStatusLabel.TextWrapped = false
        presetStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
        presetStatusLabel.TextYAlignment = Enum.TextYAlignment.Center
        presetStatusLabel.ZIndex = 5

        local function getPresetStatusColor()
            if presetStatusTone == "error" then
                return colors.Main
            end
            if presetStatusTone == "success" then
                return colors.Text
            end
            return colors.TextDim
        end

        local function applyPresetStatus()
            presetStatusLabel.Text = "Status: " .. tostring(presetStatusMessage or "Ready")
            presetStatusLabel.TextColor3 = getPresetStatusColor()
        end

        local function setPresetStatus(message, tone)
            presetStatusMessage = tostring(message or "Ready")
            presetStatusTone = tone or "neutral"
            applyPresetStatus()
        end

        onThemeChanged(function()
            applyPresetStatus()
        end)

        local function refreshPresetDropdown(selectedName)
            local presets = {}
            local seen = {}
            for _, value in ipairs(Library:ListThemePresets()) do
                local presetName = getPresetName(value)
                if presetName then
                    local key = presetName:lower()
                    if not seen[key] then
                        seen[key] = true
                        table.insert(presets, presetName)
                    end
                end
            end
            local hasPresets = #presets > 0
            if #presets == 0 then
                presets = { "No Presets" }
            end

            local targetValue = getPresetName(selectedName)
            if targetValue and not seen[targetValue:lower()] then
                table.insert(presets, 1, targetValue)
                hasPresets = true
            end
            if targetValue == nil then
                targetValue = presets[1]
            end

            presetDropdown:SetOptions(presets, targetValue)
            return hasPresets
        end

        uiVisualConfigSection:AddButton({
            Name = "Save Preset",
            Callback = function()
                local presetName = getPresetName(presetNameInput:GetText()) or getPresetName(presetDropdown:Get())
                if not presetName then
                    setPresetStatus("enter a preset name", "error")
                    return
                end

                local success, message = Library:SaveThemePreset(presetName)
                if success then
                    presetNameInput:SetText(presetName)
                    refreshPresetDropdown(presetName)
                    pcall(function()
                        Library:SaveConfig()
                    end)
                    setPresetStatus(message or ("saved preset: " .. presetName), "success")
                else
                    setPresetStatus(message or ("failed to save preset: " .. presetName), "error")
                end
            end,
        })

        uiVisualConfigSection:AddButton({
            Name = "Load Preset",
            Callback = function()
                local presetName = getPresetName(presetNameInput:GetText()) or getPresetName(presetDropdown:Get())
                if not presetName then
                    setPresetStatus("select a preset to load", "error")
                    return
                end

                local success, message = Library:LoadThemePreset(presetName)
                if success then
                    presetNameInput:SetText(presetName)
                    refreshPresetDropdown(presetName)
                    pcall(function()
                        Library:SaveConfig()
                    end)
                    setPresetStatus(message or ("loaded preset: " .. presetName), "success")
                else
                    setPresetStatus(message or ("failed to load preset: " .. presetName), "error")
                end
            end,
        })

        uiVisualConfigSection:AddButton({
            Name = "Reset to Default",
            Callback = function()
                Library:ResetThemeDefaults()
                presetNameInput:SetText("")
                refreshPresetDropdown()
                pcall(function()
                    Library:SaveConfig()
                end)
                setPresetStatus("reset theme to default", "success")
            end,
        })

        if refreshPresetDropdown() then
            setPresetStatus("preset manager ready", "neutral")
        else
            setPresetStatus("no presets saved yet", "neutral")
        end

        return settingsMenu
    end

    win._openSettingsRoute = function()
        local settingsMenuRef = win:_ensureSettingsMenu()
        if win.ActiveMenu and win.ActiveMenu ~= settingsMenuRef then
            win.ActiveMenu._select(false)
        end
        win.ActiveMenu = settingsMenuRef
        settingsMenuRef._select(true)
        setSettingsOpen(false)
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

        startupReady = true

        if win.Visible then
            main.Visible = true
            main.Size = fullWindowSize
            clipFrame.Size = fullClipSize
            updateResizeHover(UserInputService:GetMouseLocation())
        end

        if keyGateUnlocked then
            win._bootstrapWindowContent()
        else
            win._setKeyChromeLocked(true)
            task.defer(function()
                if keyUi.Input.Parent and main.Visible and win.Visible then
                    keyUi.Input:CaptureFocus()
                end
            end)
        end

        syncMobileRestoreButton()
        syncFloatingPanels()
    end)

    return win
end
end
