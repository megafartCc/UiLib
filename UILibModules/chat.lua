return function(Library, context)
    local TextService = context.TextService
    local Client = context.Client

    local function trimChatText(text)
        local value = tostring(text or "")
        value = value:gsub("^%s+", ""):gsub("%s+$", "")
        return value
    end

    local function resolveTimeLabel(messageObj)
        local direct = messageObj.time_utc_minus3 or messageObj.time or messageObj.timestampLabel
        if type(direct) == "string" and direct ~= "" then
            return direct
        end

        local created = messageObj.created_at or messageObj.createdAt or messageObj.timestamp
        if type(created) == "string" and created ~= "" then
            local hh, mm, ss = string.match(created, "(%d%d):(%d%d):(%d%d)")
            if hh and mm and ss then
                return string.format("%02d:%02d:%02d", tonumber(hh) or 0, tonumber(mm) or 0, tonumber(ss) or 0)
            end
        end

        return os.date("!%H:%M:%S", os.time() - (3 * 60 * 60))
    end

    local function getMessageKey(messageId, userName, bodyText, timeText)
        if messageId and messageId > 0 then
            return "id:" .. tostring(messageId)
        end

        return table.concat({
            tostring(userName or ""),
            tostring(bodyText or ""),
            tostring(timeText or ""),
        }, "|")
    end

    local function getThemeColor(LibraryRef, key, fallback)
        if type(LibraryRef.GetThemeValue) == "function" then
            local value = LibraryRef:GetThemeValue(key)
            if typeof(value) == "Color3" then
                return value
            end
        end
        return fallback
    end

    local function callProviderFunction(provider, fn, ...)
        local okCall, a, b = pcall(fn, ...)
        if okCall then
            return true, a, b
        end

        local okMethod, c, d = pcall(fn, provider, ...)
        if okMethod then
            return true, c, d
        end

        return false, a
    end

    local function makeProviderResolver(chatOpts, opts)
        return function(rawProvider)
            if type(rawProvider) == "table" then
                return rawProvider
            end

            local envTable = nil
            if type(getgenv) == "function" then
                local okEnv, envResult = pcall(getgenv)
                if okEnv and type(envResult) == "table" then
                    envTable = envResult
                end
            end

            local panelSdk = chatOpts.PanelSDK or chatOpts.SDK or (type(envTable) == "table" and (envTable.PanelSDK or envTable.panelSdk))
            local panelUrl = chatOpts.PanelUrl or chatOpts.URL or chatOpts.Url or (type(envTable) == "table" and (envTable.PANEL_URL or envTable.PanelUrl))
            local panelSlug = chatOpts.ScriptSlug or chatOpts.Slug or (type(envTable) == "table" and (envTable.PANEL_SLUG or envTable.PanelSlug))
            local panelKey = chatOpts.PanelKey or chatOpts.Key or (type(envTable) == "table" and (envTable.PANEL_KEY or envTable.PanelKey))

            if type(panelSdk) == "table"
                and type(panelSdk.chatSend) == "function"
                and type(panelSdk.chatFeed) == "function"
                and type(panelUrl) == "string" and panelUrl ~= ""
                and type(panelSlug) == "string" and panelSlug ~= ""
                and type(panelKey) == "string" and panelKey ~= "" then
                return {
                    Send = function(text, room)
                        return panelSdk.chatSend(panelUrl, panelSlug, panelKey, text, {
                            room = room,
                        })
                    end,
                    Fetch = function(afterId, room, limit)
                        return panelSdk.chatFeed(panelUrl, panelSlug, panelKey, {
                            after_id = afterId,
                            room = room,
                            limit = limit,
                        })
                    end,
                }
            end

            return nil
        end
    end

    local function installNoopApi(win)
        function win:SetChatProvider()
            return false
        end

        win.RefreshChat = function()
        end

        win.SetChatRoom = function()
        end

        win._setChatOpen = nil
    end

    local function attachChat(args)
        local win = args.win
        local opts = args.opts or {}
        local main = args.main
        local bottom = args.bottom
        local colors = args.colors
        local config = args.config
        local bindTheme = args.bindTheme
        local onThemeChanged = args.onThemeChanged
        local closeTransientPopups = args.closeTransientPopups or function() end
        local registerTransientPopup = args.registerTransientPopup or function() end
        local setPopupOpen = args.setPopupOpen
        local popupManager = args.popupManager
        local trackGlobal = args.trackGlobal or function(conn)
            return conn
        end
        local nextCleanupKey = args.nextCleanupKey or function(prefix)
            return prefix or "ChatCleanup"
        end
        local canUseUi = args.canUseUi or function()
            return true
        end

        installNoopApi(win)

        if type(setPopupOpen) ~= "function" or not main or not bottom then
            return { Enabled = false }
        end

        local chatEnabled = (opts.ChatEnabled ~= false)
            and (type(opts.Chat) ~= "table" or opts.Chat.Enabled ~= false)
        if not chatEnabled then
            return { Enabled = false }
        end

        local chatOpts = type(opts.Chat) == "table" and opts.Chat or {}
        local chatRoom = tostring(chatOpts.Room or chatOpts.room or "global")
        local chatPollInterval = math.max(1, tonumber(chatOpts.PollInterval or chatOpts.pollInterval or 3) or 3)
        local chatFeedLimit = math.max(10, math.min(tonumber(chatOpts.Limit or chatOpts.limit or 60) or 60, 150))
        local chatMaxMessageLength = math.max(32, math.min(tonumber(chatOpts.MaxLength or chatOpts.maxLength or 240) or 240, 500))
        local chatPanelWidth = math.max(240, math.min(tonumber(chatOpts.Width or chatOpts.width or 312) or 312, 420))
        local chatStartsOpen = chatOpts.Open == true or chatOpts.DefaultOpen == true
        local chatOpen = false
        local chatPollBusy = false
        local chatLoopToken = 0
        local chatProvider = nil
        local chatSeen = {}
        local chatRows = {}
        local chatPanelRuntime = {
            LastId = 0,
            Reset = nil,
        }

        local resolveChatProvider = makeProviderResolver(chatOpts, opts)
        chatProvider = resolveChatProvider(chatOpts.Provider or opts.ChatProvider)

        local chatBtn = Instance.new("ImageButton", bottom)
        chatBtn.Name = "ChatBtn"
        chatBtn.AnchorPoint = Vector2.new(0.5, 0.5)
        chatBtn.Position = UDim2.new(0.5, 0, 0.5, 0)
        chatBtn.Size = UDim2.new(0, 16, 0, 16)
        chatBtn.BackgroundTransparency = 1
        chatBtn.BorderSizePixel = 0
        chatBtn.Image = "rbxassetid://104591132509810"
        chatBtn.ImageColor3 = colors.TextDim
        chatBtn.ZIndex = 4
        chatBtn.AutoButtonColor = false
        bindTheme(chatBtn, "ImageColor3", "TextDim")

        local CHAT_PANEL_GAP = 8
        local chatPanel = Instance.new("Frame", main)
        chatPanel.Name = "ChatPanel"
        chatPanel.AnchorPoint = Vector2.new(0, 0)
        chatPanel.Position = UDim2.new(1, CHAT_PANEL_GAP, 0, 0)
        chatPanel.Size = UDim2.new(0, 0, 1, 0)
        chatPanel.BackgroundColor3 = Color3.fromRGB(22, 22, 22)
        chatPanel.BorderSizePixel = 0
        chatPanel.ClipsDescendants = true
        chatPanel.Visible = false
        chatPanel.ZIndex = 12
        bindTheme(chatPanel, "BackgroundColor3", "Panel")
        bindTheme(chatPanel, "BackgroundTransparency", "PanelTransparency")
        Instance.new("UICorner", chatPanel).CornerRadius = UDim.new(0, 5)

        local chatStroke = Instance.new("UIStroke", chatPanel)
        chatStroke.Color = colors.Line
        chatStroke.Transparency = 0.3
        bindTheme(chatStroke, "Color", "Line")

        local chatHeader = Instance.new("TextLabel", chatPanel)
        chatHeader.BackgroundTransparency = 1
        chatHeader.Position = UDim2.new(0, 10, 0, 0)
        chatHeader.Size = UDim2.new(1, -20, 0, 28)
        chatHeader.Font = config.Font
        chatHeader.Text = "CHAT"
        chatHeader.TextColor3 = Color3.fromRGB(255, 255, 255)
        chatHeader.TextSize = 12
        chatHeader.TextXAlignment = Enum.TextXAlignment.Left
        chatHeader.ZIndex = 13
        bindTheme(chatHeader, "TextColor3", "TextStrong")

        local chatHeaderLine = Instance.new("Frame", chatPanel)
        chatHeaderLine.Position = UDim2.new(0, 8, 0, 28)
        chatHeaderLine.Size = UDim2.new(1, -16, 0, 1)
        chatHeaderLine.BorderSizePixel = 0
        chatHeaderLine.BackgroundColor3 = colors.Line
        chatHeaderLine.ZIndex = 13
        bindTheme(chatHeaderLine, "BackgroundColor3", "Line")

        local chatMessagesScroll = Instance.new("ScrollingFrame", chatPanel)
        chatMessagesScroll.Name = "MessagesScroll"
        chatMessagesScroll.Position = UDim2.new(0, 8, 0, 34)
        chatMessagesScroll.Size = UDim2.new(1, -16, 1, -78)
        chatMessagesScroll.BackgroundTransparency = 1
        chatMessagesScroll.BorderSizePixel = 0
        chatMessagesScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
        chatMessagesScroll.ScrollBarThickness = 3
        chatMessagesScroll.ScrollBarImageColor3 = getThemeColor(Library, "Line", colors.Line)
        chatMessagesScroll.ScrollingDirection = Enum.ScrollingDirection.Y
        chatMessagesScroll.AutomaticCanvasSize = Enum.AutomaticSize.None
        chatMessagesScroll.ZIndex = 13

        local chatMessagesInner = Instance.new("Frame", chatMessagesScroll)
        chatMessagesInner.BackgroundTransparency = 1
        chatMessagesInner.BorderSizePixel = 0
        chatMessagesInner.Size = UDim2.new(1, -2, 0, 0)
        chatMessagesInner.ZIndex = 13

        local chatMessagesLayout = Instance.new("UIListLayout", chatMessagesInner)
        chatMessagesLayout.Padding = UDim.new(0, 6)
        chatMessagesLayout.SortOrder = Enum.SortOrder.LayoutOrder

        local chatInputRow = Instance.new("Frame", chatPanel)
        chatInputRow.BackgroundTransparency = 1
        chatInputRow.Position = UDim2.new(0, 8, 1, -38)
        chatInputRow.Size = UDim2.new(1, -16, 0, 30)
        chatInputRow.ZIndex = 13

        local chatInputFrame = Instance.new("Frame", chatInputRow)
        chatInputFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
        chatInputFrame.BorderSizePixel = 0
        chatInputFrame.Size = UDim2.new(1, -34, 1, 0)
        chatInputFrame.ZIndex = 13
        bindTheme(chatInputFrame, "BackgroundColor3", "Control")
        bindTheme(chatInputFrame, "BackgroundTransparency", "ControlTransparency")
        Instance.new("UICorner", chatInputFrame).CornerRadius = UDim.new(0, 3)

        local chatInputStroke = Instance.new("UIStroke", chatInputFrame)
        chatInputStroke.Color = colors.Line
        chatInputStroke.Transparency = 0.45
        bindTheme(chatInputStroke, "Color", "Line")

        local chatInput = Instance.new("TextBox", chatInputFrame)
        chatInput.BackgroundTransparency = 1
        chatInput.BorderSizePixel = 0
        chatInput.Position = UDim2.new(0, 8, 0, 0)
        chatInput.Size = UDim2.new(1, -12, 1, 0)
        chatInput.Font = config.FontMedium
        chatInput.PlaceholderText = "Type text..."
        chatInput.PlaceholderColor3 = colors.TextDim
        chatInput.Text = ""
        chatInput.ClearTextOnFocus = false
        chatInput.TextColor3 = Color3.fromRGB(255, 255, 255)
        chatInput.TextSize = 12
        chatInput.TextXAlignment = Enum.TextXAlignment.Left
        chatInput.ZIndex = 14
        bindTheme(chatInput, "PlaceholderColor3", "TextDim")
        bindTheme(chatInput, "TextColor3", "Text")

        local chatSendBtn = Instance.new("ImageButton", chatInputRow)
        chatSendBtn.Name = "SendButton"
        chatSendBtn.AnchorPoint = Vector2.new(1, 0.5)
        chatSendBtn.Position = UDim2.new(1, -1, 0.5, 0)
        chatSendBtn.Size = UDim2.new(0, 22, 0, 22)
        chatSendBtn.BackgroundTransparency = 1
        chatSendBtn.BorderSizePixel = 0
        chatSendBtn.Image = "rbxassetid://109231405623946"
        chatSendBtn.ImageColor3 = colors.TextDim
        chatSendBtn.ZIndex = 14
        chatSendBtn.AutoButtonColor = false
        bindTheme(chatSendBtn, "ImageColor3", "TextDim")

        local function refreshChatButtonVisual()
            local targetColor = chatOpen and colors.Main or colors.TextDim
            Library:Animate(chatBtn, "Hover", { ImageColor3 = targetColor })
        end

        local function refreshChatCanvas()
            local contentHeight = chatMessagesLayout.AbsoluteContentSize.Y
            chatMessagesInner.Size = UDim2.new(1, -2, 0, contentHeight)
            chatMessagesScroll.CanvasSize = UDim2.new(0, 0, 0, math.max(0, contentHeight + 4))
        end

        local function scrollChatToBottom()
            refreshChatCanvas()
            local visibleHeight = chatMessagesScroll.AbsoluteSize.Y
            local contentHeight = chatMessagesLayout.AbsoluteContentSize.Y
            local target = math.max(0, contentHeight - visibleHeight + 4)
            chatMessagesScroll.CanvasPosition = Vector2.new(0, target)
        end

        local function addChatRow(userName, bodyText, timeText)
            local body = trimChatText(bodyText)
            if body == "" then
                return
            end

            local row = Instance.new("Frame", chatMessagesInner)
            row.BackgroundColor3 = Color3.fromRGB(26, 26, 26)
            row.BorderSizePixel = 0
            row.Size = UDim2.new(1, 0, 0, 38)
            row.ZIndex = 13
            bindTheme(row, "BackgroundColor3", "Control")
            bindTheme(row, "BackgroundTransparency", "ControlTransparency")
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 3)

            local rowPadding = Instance.new("UIPadding", row)
            rowPadding.PaddingLeft = UDim.new(0, 7)
            rowPadding.PaddingRight = UDim.new(0, 7)
            rowPadding.PaddingTop = UDim.new(0, 4)
            rowPadding.PaddingBottom = UDim.new(0, 5)

            local rowHeader = Instance.new("Frame", row)
            rowHeader.BackgroundTransparency = 1
            rowHeader.Size = UDim2.new(1, 0, 0, 12)
            rowHeader.ZIndex = 14

            local userLabel = Instance.new("TextLabel", rowHeader)
            userLabel.BackgroundTransparency = 1
            userLabel.Size = UDim2.new(0.66, 0, 1, 0)
            userLabel.Font = config.FontMedium
            userLabel.Text = tostring(userName or "unknown")
            userLabel.TextColor3 = colors.Main
            userLabel.TextSize = 11
            userLabel.TextXAlignment = Enum.TextXAlignment.Left
            userLabel.ZIndex = 14
            bindTheme(userLabel, "TextColor3", "Main")

            local timeLabel = Instance.new("TextLabel", rowHeader)
            timeLabel.BackgroundTransparency = 1
            timeLabel.AnchorPoint = Vector2.new(1, 0)
            timeLabel.Position = UDim2.new(1, 0, 0, 0)
            timeLabel.Size = UDim2.new(0.34, 0, 1, 0)
            timeLabel.Font = config.FontMedium
            timeLabel.Text = tostring(timeText or "")
            timeLabel.TextColor3 = colors.TextDim
            timeLabel.TextSize = 10
            timeLabel.TextXAlignment = Enum.TextXAlignment.Right
            timeLabel.ZIndex = 14
            bindTheme(timeLabel, "TextColor3", "TextDim")

            local messageLabel = Instance.new("TextLabel", row)
            messageLabel.BackgroundTransparency = 1
            messageLabel.Position = UDim2.new(0, 0, 0, 14)
            messageLabel.Size = UDim2.new(1, 0, 1, -14)
            messageLabel.Font = config.FontMedium
            messageLabel.Text = body
            messageLabel.TextColor3 = colors.Text
            messageLabel.TextSize = 12
            messageLabel.TextWrapped = true
            messageLabel.TextXAlignment = Enum.TextXAlignment.Left
            messageLabel.TextYAlignment = Enum.TextYAlignment.Top
            messageLabel.ZIndex = 14
            bindTheme(messageLabel, "TextColor3", "Text")

            local availableWidth = math.max(90, chatMessagesScroll.AbsoluteSize.X - 30)
            local textBounds = TextService:GetTextSize(body, 12, config.FontMedium, Vector2.new(availableWidth, 1000))
            row.Size = UDim2.new(1, 0, 0, math.max(34, textBounds.Y + 24))
            row.LayoutOrder = chatMessagesLayout.AbsoluteContentSize.Y + 1

            table.insert(chatRows, row)
            if #chatRows > 160 then
                local firstRow = table.remove(chatRows, 1)
                if firstRow and firstRow.Parent then
                    firstRow:Destroy()
                end
            end

            refreshChatCanvas()
        end

        chatPanelRuntime.Reset = function()
            chatPanelRuntime.LastId = 0
            chatSeen = {}
            chatRows = {}
            for _, child in ipairs(chatMessagesInner:GetChildren()) do
                if child:IsA("Frame") then
                    child:Destroy()
                end
            end
            refreshChatCanvas()
        end

        local function applyMessages(messageList)
            if type(messageList) ~= "table" then
                return
            end

            local added = false
            for _, entry in ipairs(messageList) do
                if type(entry) == "table" then
                    local messageId = tonumber(entry.id or entry.message_id)
                    local userName = entry.user or entry.name or entry.roblox_user
                    local bodyText = entry.message or entry.content or entry.text or entry.message_content
                    local timeText = resolveTimeLabel(entry)
                    local dedupeKey = getMessageKey(messageId, userName, bodyText, timeText)

                    if not chatSeen[dedupeKey] and type(bodyText) == "string" and trimChatText(bodyText) ~= "" then
                        chatSeen[dedupeKey] = true
                        addChatRow(userName, bodyText, timeText)
                        added = true
                    end

                    if messageId and messageId > (chatPanelRuntime.LastId or 0) then
                        chatPanelRuntime.LastId = messageId
                    end
                end
            end

            if added then
                scrollChatToBottom()
            end
        end

        local function callChatFetch()
            if chatPollBusy or not chatOpen or not canUseUi() then
                return
            end

            local provider = chatProvider
            local fetchFn = type(provider) == "table" and (provider.Fetch or provider.fetch or provider.Get or provider.get) or nil
            if type(fetchFn) ~= "function" then
                return
            end

            chatPollBusy = true
            task.spawn(function()
                local ok, success, response = callProviderFunction(provider, fetchFn, chatPanelRuntime.LastId or 0, chatRoom, chatFeedLimit)
                chatPollBusy = false
                if not ok or success == false then
                    return
                end

                local payload = response
                if type(payload) ~= "table" and type(success) == "table" then
                    payload = success
                end
                if type(payload) ~= "table" then
                    return
                end

                local rows = payload.messages or payload.data or payload.rows
                applyMessages(rows)
            end)
        end

        local function sendCurrentChatText()
            local messageText = trimChatText(chatInput.Text)
            if messageText == "" then
                return
            end

            if #messageText > chatMaxMessageLength then
                messageText = string.sub(messageText, 1, chatMaxMessageLength)
            end

            chatInput.Text = ""
            chatInput:ReleaseFocus()

            local provider = chatProvider
            local sendFn = type(provider) == "table" and (provider.Send or provider.send or provider.Post or provider.post) or nil
            if type(sendFn) ~= "function" then
                addChatRow(Client.Name, messageText, os.date("!%H:%M:%S", os.time() - (3 * 60 * 60)))
                scrollChatToBottom()
                return
            end

            task.spawn(function()
                local ok, success, response = callProviderFunction(provider, sendFn, messageText, chatRoom)
                if not ok or success == false then
                    return
                end

                local payload = response
                if type(payload) ~= "table" and type(success) == "table" then
                    payload = success
                end

                if type(payload) == "table" and type(payload.message) == "table" then
                    applyMessages({ payload.message })
                else
                    addChatRow(Client.Name, messageText, os.date("!%H:%M:%S", os.time() - (3 * 60 * 60)))
                    scrollChatToBottom()
                    callChatFetch()
                end
            end)
        end

        local chatPopupConfig = {
            ClosedSize = UDim2.new(0, 0, 1, 0),
            OpenSize = UDim2.new(0, chatPanelWidth, 1, 0),
            OpenToken = "Open",
            CloseToken = "Close",
            HideDelay = 0.2,
            OnOpen = function()
                chatInput:CaptureFocus()
                callChatFetch()
            end,
            OnClose = function()
                chatInput:ReleaseFocus()
            end,
        }

        local function setChatOpen(nextOpen)
            if chatOpen == nextOpen then
                return
            end
            if nextOpen and not canUseUi() then
                return
            end

            chatOpen = nextOpen
            if chatOpen then
                closeTransientPopups(chatPanel)
            end

            refreshChatButtonVisual()
            setPopupOpen(chatPanel, chatOpen, chatPopupConfig)
        end

        chatBtn.MouseEnter:Connect(function()
            Library:Animate(chatBtn, "Hover", { ImageColor3 = colors.Main })
        end)
        chatBtn.MouseLeave:Connect(function()
            local targetColor = chatOpen and colors.Main or colors.TextDim
            Library:Animate(chatBtn, "Hover", { ImageColor3 = targetColor })
        end)
        chatBtn.Activated:Connect(function()
            setChatOpen(not chatOpen)
        end)

        chatSendBtn.MouseEnter:Connect(function()
            Library:Animate(chatSendBtn, "Hover", { ImageColor3 = colors.Main })
        end)
        chatSendBtn.MouseLeave:Connect(function()
            Library:Animate(chatSendBtn, "Hover", { ImageColor3 = colors.TextDim })
        end)
        chatSendBtn.Activated:Connect(function()
            sendCurrentChatText()
        end)

        chatInput.FocusLost:Connect(function(enterPressed)
            if enterPressed then
                sendCurrentChatText()
            end
        end)

        registerTransientPopup(chatPanel, function()
            setChatOpen(false)
        end)

        if popupManager and type(popupManager.bindOutsideClose) == "function" then
            popupManager.bindOutsideClose({
                cleanupKey = nextCleanupKey("ChatOutsideClick"),
                close = function()
                    setChatOpen(false)
                end,
                isOpen = function()
                    return chatOpen
                end,
                targets = function()
                    return { chatPanel, chatBtn }
                end,
            })
        end

        trackGlobal(chatMessagesLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
            refreshChatCanvas()
        end), nextCleanupKey("ChatCanvasSize"))

        if type(onThemeChanged) == "function" then
            onThemeChanged(function()
                if win._destroyed then
                    return
                end
                local scrollColor = getThemeColor(Library, "Line", colors.Line)
                if typeof(scrollColor) == "Color3" then
                    chatMessagesScroll.ScrollBarImageColor3 = scrollColor
                end
                refreshChatButtonVisual()
            end)
        end

        chatLoopToken += 1
        local loopToken = chatLoopToken
        task.spawn(function()
            while not win._destroyed and loopToken == chatLoopToken do
                if chatOpen and canUseUi() then
                    callChatFetch()
                end
                task.wait(chatPollInterval)
            end
        end)

        function win:SetChatProvider(provider)
            chatProvider = resolveChatProvider(provider)
            chatPanelRuntime.LastId = 0
            if type(chatPanelRuntime.Reset) == "function" then
                chatPanelRuntime.Reset()
            end
            return chatProvider ~= nil
        end

        win.RefreshChat = function()
            callChatFetch()
        end

        win.SetChatRoom = function(_, roomName)
            chatRoom = tostring(roomName or "global")
            if type(chatPanelRuntime.Reset) == "function" then
                chatPanelRuntime.Reset()
            end
            callChatFetch()
        end

        win._setChatOpen = setChatOpen

        if chatStartsOpen then
            task.defer(function()
                if not win._destroyed and canUseUi() then
                    setChatOpen(true)
                end
            end)
        end

        return {
            Enabled = true,
            Button = chatBtn,
            Panel = chatPanel,
            SetOpen = setChatOpen,
        }
    end

    return {
        attach = attachChat,
    }
end
