return function(Library, context)
    local TextService = context.TextService
    local HttpService = context.HttpService
    local Players = context.Players
    local Client = context.Client
    local TeleportService = game:GetService("TeleportService")

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

    local function getRequestFunction()
        local candidates = {
            request,
            http_request,
            httprequest,
            syn and syn.request,
            http and http.request,
            fluxus and fluxus.request,
        }
        for _, fn in ipairs(candidates) do
            if type(fn) == "function" then
                return fn
            end
        end
        return nil
    end

    local function decodeJson(body)
        if type(body) ~= "string" or body == "" then
            return nil
        end
        local okDecode, parsed = pcall(function()
            return HttpService:JSONDecode(body)
        end)
        if okDecode and type(parsed) == "table" then
            return parsed
        end
        return nil
    end

    local function fetchPresenceForUserId(userId)
        local uid = tonumber(userId)
        if not uid or uid <= 0 then
            return nil
        end

        local requestFn = getRequestFunction()
        if type(requestFn) ~= "function" then
            return nil
        end

        local body = nil
        local okBody = pcall(function()
            body = HttpService:JSONEncode({
                userIds = { uid },
            })
        end)
        if not okBody or type(body) ~= "string" then
            return nil
        end

        local requestVariants = {
            {
                Url = "https://presence.roblox.com/v1/presence/users",
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json",
                },
                Body = body,
            },
            {
                url = "https://presence.roblox.com/v1/presence/users",
                method = "POST",
                headers = {
                    ["Content-Type"] = "application/json",
                },
                body = body,
            },
        }

        local response = nil
        for _, options in ipairs(requestVariants) do
            local okRequest, result = pcall(requestFn, options)
            if okRequest and type(result) == "table" then
                response = result
                break
            end
        end
        if type(response) ~= "table" then
            return nil
        end

        local statusCode = tonumber(response.StatusCode or response.status) or 0
        if statusCode < 200 or statusCode >= 300 then
            return nil
        end

        local payload = decodeJson(response.Body or response.body)
        local users = payload and payload.userPresences
        if type(users) == "table" and type(users[1]) == "table" then
            return users[1]
        end

        return nil
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
                local function fetchSharedUsers(options)
                    if type(panelSdk.sharedUsers) ~= "function" then
                        return false, { error = "shared_users_unavailable" }
                    end

                    options = type(options) == "table" and options or {}
                    return panelSdk.sharedUsers(panelUrl, panelSlug, panelKey, {
                        jobid = tostring(options.jobid or game.JobId or ""),
                        includeSelf = options.includeSelf == true or options.include_self == true,
                    })
                end

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
                    SharedUsers = function(options)
                        return fetchSharedUsers(options)
                    end,
                    Profile = function(userName, userId)
                        local okPeers, peersResponse = fetchSharedUsers({
                            jobid = game.JobId or "",
                            includeSelf = true,
                        })
                        if not okPeers or type(peersResponse) ~= "table" then
                            return false, peersResponse
                        end

                        local candidates = peersResponse.users or peersResponse.peers or {}
                        local desiredId = tostring(userId or "")
                        local desiredName = string.lower(tostring(userName or ""))
                        for _, entry in ipairs(candidates) do
                            if type(entry) == "table" then
                                local entryId = tostring(entry.userid or "")
                                local entryName = string.lower(tostring(entry.user or entry.username or entry.name or ""))
                                if (desiredId ~= "" and entryId == desiredId)
                                    or (desiredName ~= "" and entryName == desiredName) then
                                    return true, {
                                        online = true,
                                        user = entry.user or entry.username or entry.name or userName,
                                        userid = entryId ~= "" and entryId or userId,
                                        placeid = tonumber(entry.placeid or entry.placeId or game.PlaceId) or game.PlaceId,
                                        jobid = tostring(entry.jobid or entry.gameId or game.JobId or ""),
                                        game = entry.game or entry.placeName or "This server",
                                    }
                                end
                            end
                        end

                        return false, { error = "user_not_found" }
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
        local presenceLoopToken = 0
        local presenceBusy = false
        local presenceInterval = math.max(3, tonumber(chatOpts.PresenceInterval or chatOpts.presenceInterval or 8) or 8)
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

        local presenceDot = Instance.new("Frame", bottom)
        presenceDot.Name = "ChatPresenceDot"
        presenceDot.AnchorPoint = Vector2.new(0.5, 0.5)
        presenceDot.Position = UDim2.new(0.5, 11, 0.5, -4)
        presenceDot.Size = UDim2.fromOffset(6, 6)
        presenceDot.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
        presenceDot.BorderSizePixel = 0
        presenceDot.ZIndex = 5
        Instance.new("UICorner", presenceDot).CornerRadius = UDim.new(1, 0)

        local presenceCountLabel = Instance.new("TextLabel", bottom)
        presenceCountLabel.Name = "ChatPresenceCount"
        presenceCountLabel.AnchorPoint = Vector2.new(0, 0.5)
        presenceCountLabel.Position = UDim2.new(0.5, 16, 0.5, 0)
        presenceCountLabel.Size = UDim2.fromOffset(18, 12)
        presenceCountLabel.BackgroundTransparency = 1
        presenceCountLabel.BorderSizePixel = 0
        presenceCountLabel.Font = config.FontMedium
        presenceCountLabel.Text = "0"
        presenceCountLabel.TextSize = 9
        presenceCountLabel.TextXAlignment = Enum.TextXAlignment.Left
        presenceCountLabel.TextColor3 = colors.TextDim
        presenceCountLabel.ZIndex = 5

        local lastPresenceCount = 0
        local lastSharedUsers = {}
        local function setPresenceVisual(rawCount)
            local count = math.max(0, tonumber(rawCount) or 0)
            lastPresenceCount = count
            presenceCountLabel.Text = tostring(count)
            if count > 0 then
                presenceDot.BackgroundColor3 = Color3.fromRGB(67, 217, 126)
                presenceCountLabel.TextColor3 = colors.Text
            else
                presenceDot.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
                presenceCountLabel.TextColor3 = colors.TextDim
            end
        end
        setPresenceVisual(0)

        local function extractSharedUsers(payload)
            if type(payload) ~= "table" then
                return {}
            end

            local list = payload.users or payload.peers
            if type(list) ~= "table" then
                return {}
            end

            local out = {}
            for _, entry in ipairs(list) do
                if type(entry) == "table" then
                    table.insert(out, entry)
                end
            end
            return out
        end

        local function countSharedUsersFromPayload(payload)
            local list = extractSharedUsers(payload)

            local localUserId = tostring(Client and Client.UserId or "")
            local localName = string.lower(tostring(Client and Client.Name or ""))
            local unique = {}

            for _, entry in ipairs(list) do
                local entryId = tostring(entry.userid or entry.userId or entry.user_id or "")
                local entryName = string.lower(tostring(entry.user or entry.username or entry.name or ""))
                if entryId ~= "" and entryId ~= localUserId then
                    unique["id:" .. entryId] = true
                elseif entryName ~= "" and entryName ~= localName then
                    unique["name:" .. entryName] = true
                end
            end

            local count = 0
            for _ in pairs(unique) do
                count += 1
            end
            return count
        end

        local refreshServerListPanel = function()
        end

        local function refreshSharedPresenceAsync()
            if presenceBusy or not canUseUi() then
                return
            end

            local provider = chatProvider
            local sharedFn = type(provider) == "table" and (provider.SharedUsers or provider.sharedUsers or provider.Peers or provider.peers) or nil
            if type(sharedFn) ~= "function" then
                setPresenceVisual(0)
                return
            end

            presenceBusy = true
            task.spawn(function()
                local okCall, okResult, response = callProviderFunction(provider, sharedFn, {
                    jobid = game.JobId or "",
                    includeSelf = false,
                })
                presenceBusy = false

                if not okCall or okResult == false then
                    setPresenceVisual(0)
                    lastSharedUsers = {}
                    refreshServerListPanel()
                    return
                end

                local payload = response
                if type(payload) ~= "table" and type(okResult) == "table" then
                    payload = okResult
                end

                lastSharedUsers = extractSharedUsers(payload)
                setPresenceVisual(countSharedUsersFromPayload(payload))
                refreshServerListPanel()
            end)
        end

        local userMetaByName = {}
        local activeProfileToken = 0
        local activeProfileData = nil
        local profileOpen = false
        local profileLastSource = nil
        local setProfileOpen

        local serverListOpen = false
        local serverListRows = {}
        local serverListWidth = math.max(190, math.min(chatPanelWidth - 16, 320))
        local serverListHeight = math.max(120, math.min(220, math.floor(main.AbsoluteSize.Y * 0.45)))

        local serverListBtn = Instance.new("TextButton", chatPanel)
        serverListBtn.Name = "ServerListButton"
        serverListBtn.AnchorPoint = Vector2.new(1, 0)
        serverListBtn.Position = UDim2.new(1, -8, 0, 7)
        serverListBtn.Size = UDim2.fromOffset(66, 16)
        serverListBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
        serverListBtn.BorderSizePixel = 0
        serverListBtn.Font = config.FontMedium
        serverListBtn.Text = "Servers"
        serverListBtn.TextColor3 = colors.TextDim
        serverListBtn.TextSize = 10
        serverListBtn.TextXAlignment = Enum.TextXAlignment.Center
        serverListBtn.ZIndex = 14
        serverListBtn.AutoButtonColor = false
        serverListBtn.Selectable = false
        bindTheme(serverListBtn, "BackgroundColor3", "Control")
        bindTheme(serverListBtn, "BackgroundTransparency", "ControlTransparency")
        bindTheme(serverListBtn, "TextColor3", "TextDim")
        Instance.new("UICorner", serverListBtn).CornerRadius = UDim.new(0, 3)

        local serverListPanel = Instance.new("Frame", chatPanel)
        serverListPanel.Name = "ServerListPanel"
        serverListPanel.AnchorPoint = Vector2.new(1, 0)
        serverListPanel.Position = UDim2.new(1, -8, 0, 26)
        serverListPanel.Size = UDim2.fromOffset(serverListWidth, 0)
        serverListPanel.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
        serverListPanel.BorderSizePixel = 0
        serverListPanel.Visible = false
        serverListPanel.ClipsDescendants = true
        serverListPanel.ZIndex = 130
        bindTheme(serverListPanel, "BackgroundColor3", "Panel")
        bindTheme(serverListPanel, "BackgroundTransparency", "PanelTransparency")
        Instance.new("UICorner", serverListPanel).CornerRadius = UDim.new(0, 4)
        local serverListStroke = Instance.new("UIStroke", serverListPanel)
        serverListStroke.Color = colors.Line
        serverListStroke.Transparency = 0.35
        bindTheme(serverListStroke, "Color", "Line")

        local serverListTitle = Instance.new("TextLabel", serverListPanel)
        serverListTitle.BackgroundTransparency = 1
        serverListTitle.Position = UDim2.new(0, 8, 0, 6)
        serverListTitle.Size = UDim2.new(1, -16, 0, 16)
        serverListTitle.Font = config.Font
        serverListTitle.Text = "SERVER LIST"
        serverListTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
        serverListTitle.TextSize = 11
        serverListTitle.TextXAlignment = Enum.TextXAlignment.Left
        serverListTitle.ZIndex = 131
        bindTheme(serverListTitle, "TextColor3", "TextStrong")

        local serverListScroll = Instance.new("ScrollingFrame", serverListPanel)
        serverListScroll.Name = "ServerListScroll"
        serverListScroll.Position = UDim2.new(0, 6, 0, 24)
        serverListScroll.Size = UDim2.new(1, -12, 1, -30)
        serverListScroll.BackgroundTransparency = 1
        serverListScroll.BorderSizePixel = 0
        serverListScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
        serverListScroll.ScrollBarThickness = 2
        serverListScroll.ScrollBarImageColor3 = getThemeColor(Library, "Line", colors.Line)
        serverListScroll.ZIndex = 131

        local serverListInner = Instance.new("Frame", serverListScroll)
        serverListInner.BackgroundTransparency = 1
        serverListInner.BorderSizePixel = 0
        serverListInner.Size = UDim2.new(1, -2, 0, 0)
        serverListInner.ZIndex = 131

        local serverListLayout = Instance.new("UIListLayout", serverListInner)
        serverListLayout.Padding = UDim.new(0, 4)
        serverListLayout.SortOrder = Enum.SortOrder.LayoutOrder

        local serverListPopupConfig = {
            ClosedSize = UDim2.fromOffset(serverListWidth, 0),
            OpenSize = UDim2.fromOffset(serverListWidth, serverListHeight),
            OpenToken = "Open",
            CloseToken = "Close",
            HideDelay = 0.18,
        }

        local function clearServerListRows()
            for _, row in ipairs(serverListRows) do
                if row and row.Parent then
                    row:Destroy()
                end
            end
            serverListRows = {}
        end

        local function refreshServerListCanvas()
            local contentHeight = serverListLayout.AbsoluteContentSize.Y
            serverListInner.Size = UDim2.new(1, -2, 0, contentHeight)
            serverListScroll.CanvasSize = UDim2.new(0, 0, 0, math.max(0, contentHeight + 2))
        end

        local function makeServerRow(entry, order)
            local row = Instance.new("Frame", serverListInner)
            row.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
            row.BorderSizePixel = 0
            row.Size = UDim2.new(1, 0, 0, 28)
            row.LayoutOrder = order
            row.ZIndex = 132
            bindTheme(row, "BackgroundColor3", "Control")
            bindTheme(row, "BackgroundTransparency", "ControlTransparency")
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 3)

            local name = tostring(entry.user or entry.username or entry.name or "unknown")
            local placeText = tostring(entry.game or entry.placeName or ("Place " .. tostring(entry.placeid or entry.placeId or "?")))
            local jobId = tostring(entry.jobid or entry.gameId or "")
            local placeId = tonumber(entry.placeid or entry.placeId or 0) or 0
            local joinable = placeId > 0 and jobId ~= "" and not (placeId == tonumber(game.PlaceId or 0) and jobId == tostring(game.JobId or ""))

            local nameLabel = Instance.new("TextLabel", row)
            nameLabel.BackgroundTransparency = 1
            nameLabel.Position = UDim2.new(0, 6, 0, 2)
            nameLabel.Size = UDim2.new(0.48, 0, 0, 11)
            nameLabel.Font = config.FontMedium
            nameLabel.Text = name
            nameLabel.TextColor3 = colors.Main
            nameLabel.TextSize = 10
            nameLabel.TextXAlignment = Enum.TextXAlignment.Left
            nameLabel.ZIndex = 133
            bindTheme(nameLabel, "TextColor3", "Main")

            local placeLabel = Instance.new("TextLabel", row)
            placeLabel.BackgroundTransparency = 1
            placeLabel.Position = UDim2.new(0, 6, 0, 13)
            placeLabel.Size = UDim2.new(0.52, 0, 0, 11)
            placeLabel.Font = config.FontMedium
            placeLabel.Text = placeText
            placeLabel.TextColor3 = colors.TextDim
            placeLabel.TextSize = 9
            placeLabel.TextXAlignment = Enum.TextXAlignment.Left
            placeLabel.ZIndex = 133
            bindTheme(placeLabel, "TextColor3", "TextDim")

            local joinBtn = Instance.new("TextButton", row)
            joinBtn.AnchorPoint = Vector2.new(1, 0.5)
            joinBtn.Position = UDim2.new(1, -6, 0.5, 0)
            joinBtn.Size = UDim2.fromOffset(48, 18)
            joinBtn.BackgroundColor3 = joinable and Color3.fromRGB(45, 25, 30) or Color3.fromRGB(35, 35, 35)
            joinBtn.BorderSizePixel = 0
            joinBtn.Font = config.FontMedium
            joinBtn.Text = joinable and "Join" or "-"
            joinBtn.TextColor3 = joinable and Color3.fromRGB(255, 255, 255) or colors.TextDim
            joinBtn.TextSize = 9
            joinBtn.AutoButtonColor = false
            joinBtn.Selectable = false
            joinBtn.Active = joinable
            joinBtn.ZIndex = 133
            Instance.new("UICorner", joinBtn).CornerRadius = UDim.new(0, 3)

            joinBtn.Activated:Connect(function()
                if not joinable then
                    return
                end
                pcall(function()
                    TeleportService:TeleportToPlaceInstance(placeId, jobId, Client)
                end)
            end)

            table.insert(serverListRows, row)
        end

        local function setServerListOpen(nextOpen)
            if serverListOpen == nextOpen then
                return
            end
            serverListOpen = nextOpen
            if serverListOpen then
                setProfileOpen(false)
                refreshServerListPanel()
            end
            setPopupOpen(serverListPanel, serverListOpen, serverListPopupConfig)
        end

        registerTransientPopup(serverListPanel, function()
            setServerListOpen(false)
        end)
        if popupManager and type(popupManager.bindOutsideClose) == "function" then
            popupManager.bindOutsideClose({
                cleanupKey = nextCleanupKey("ChatServerListOutsideClick"),
                close = function()
                    setServerListOpen(false)
                end,
                isOpen = function()
                    return serverListOpen
                end,
                targets = function()
                    return { serverListPanel, serverListBtn }
                end,
            })
        end

        serverListBtn.MouseEnter:Connect(function()
            Library:Animate(serverListBtn, "Hover", { BackgroundColor3 = Color3.fromRGB(50, 50, 50) })
        end)
        serverListBtn.MouseLeave:Connect(function()
            Library:Animate(serverListBtn, "Hover", { BackgroundColor3 = Color3.fromRGB(35, 35, 35) })
        end)
        serverListBtn.Activated:Connect(function()
            setServerListOpen(not serverListOpen)
        end)

        refreshServerListPanel = function()
            clearServerListRows()
            table.sort(lastSharedUsers, function(a, b)
                local nameA = string.lower(tostring(a.user or a.username or a.name or ""))
                local nameB = string.lower(tostring(b.user or b.username or b.name or ""))
                return nameA < nameB
            end)

            local count = 0
            local localId = tostring(Client and Client.UserId or "")
            local localName = string.lower(tostring(Client and Client.Name or ""))
            for _, entry in ipairs(lastSharedUsers) do
                local entryId = tostring(entry.userid or entry.userId or entry.user_id or "")
                local entryName = string.lower(tostring(entry.user or entry.username or entry.name or ""))
                if entryId ~= localId and entryName ~= localName then
                    count += 1
                    makeServerRow(entry, count)
                end
            end

            if count == 0 then
                local empty = Instance.new("TextLabel", serverListInner)
                empty.BackgroundTransparency = 1
                empty.Size = UDim2.new(1, 0, 0, 22)
                empty.Font = config.FontMedium
                empty.Text = "No users found"
                empty.TextColor3 = colors.TextDim
                empty.TextSize = 10
                empty.TextXAlignment = Enum.TextXAlignment.Center
                empty.ZIndex = 132
                bindTheme(empty, "TextColor3", "TextDim")
                table.insert(serverListRows, empty)
            end

            refreshServerListCanvas()
        end

        local profilePanel = Instance.new("Frame", chatPanel)
        profilePanel.Name = "ProfilePanel"
        local profilePanelWidth = math.max(170, math.min(chatPanelWidth - 24, 310))
        local profilePanelHeight = 128
        local profileLayout = {
            PadX = 10,
            HeaderY = 10,
            HeaderH = 14,
            LineY = 28,
            LineH = 1,
            NameY = 34,
            NameH = 16,
            StatusY = 54,
            StatusH = 14,
            GameY = 70,
            GameH = 14,
            FooterY = 94,
            FooterH = 24,
            ButtonGap = 6,
        }
        profilePanel.AnchorPoint = Vector2.new(0.5, 1)
        profilePanel.Position = UDim2.new(0.5, 0, 1, -8)
        profilePanel.Size = UDim2.fromOffset(profilePanelWidth, 0)
        profilePanel.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
        profilePanel.BorderSizePixel = 0
        profilePanel.Visible = false
        profilePanel.ClipsDescendants = true
        profilePanel.ZIndex = 130
        bindTheme(profilePanel, "BackgroundColor3", "Panel")
        bindTheme(profilePanel, "BackgroundTransparency", "PanelTransparency")
        Instance.new("UICorner", profilePanel).CornerRadius = UDim.new(0, 4)
        local profilePanelStroke = Instance.new("UIStroke", profilePanel)
        profilePanelStroke.Color = colors.Line
        profilePanelStroke.Transparency = 0.35
        bindTheme(profilePanelStroke, "Color", "Line")

        local profileTitle = Instance.new("TextLabel", profilePanel)
        profileTitle.BackgroundTransparency = 1
        profileTitle.Position = UDim2.new(0, profileLayout.PadX, 0, profileLayout.HeaderY)
        profileTitle.Size = UDim2.new(1, -(profileLayout.PadX * 2), 0, profileLayout.HeaderH)
        profileTitle.Font = config.Font
        profileTitle.Text = "USER PROFILE"
        profileTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
        profileTitle.TextSize = 11
        profileTitle.TextXAlignment = Enum.TextXAlignment.Left
        profileTitle.ZIndex = 131
        bindTheme(profileTitle, "TextColor3", "TextStrong")

        local profileHeaderLine = Instance.new("Frame", profilePanel)
        profileHeaderLine.BackgroundColor3 = colors.Line
        profileHeaderLine.BorderSizePixel = 0
        profileHeaderLine.Position = UDim2.new(0, profileLayout.PadX, 0, profileLayout.LineY)
        profileHeaderLine.Size = UDim2.new(1, -(profileLayout.PadX * 2), 0, profileLayout.LineH)
        profileHeaderLine.ZIndex = 131
        bindTheme(profileHeaderLine, "BackgroundColor3", "Line")

        local profileName = Instance.new("TextLabel", profilePanel)
        profileName.BackgroundTransparency = 1
        profileName.Position = UDim2.new(0, profileLayout.PadX, 0, profileLayout.NameY)
        profileName.Size = UDim2.new(1, -(profileLayout.PadX * 2), 0, profileLayout.NameH)
        profileName.Font = config.FontMedium
        profileName.Text = "-"
        profileName.TextColor3 = colors.Main
        profileName.TextSize = 12
        profileName.TextXAlignment = Enum.TextXAlignment.Left
        profileName.TextTruncate = Enum.TextTruncate.AtEnd
        profileName.ZIndex = 131
        bindTheme(profileName, "TextColor3", "Main")

        local profileStatus = Instance.new("TextLabel", profilePanel)
        profileStatus.BackgroundTransparency = 1
        profileStatus.Position = UDim2.new(0, profileLayout.PadX, 0, profileLayout.StatusY)
        profileStatus.Size = UDim2.new(1, -(profileLayout.PadX * 2), 0, profileLayout.StatusH)
        profileStatus.Font = config.FontMedium
        profileStatus.Text = "Status: unknown"
        profileStatus.TextColor3 = colors.TextDim
        profileStatus.TextSize = 10
        profileStatus.TextXAlignment = Enum.TextXAlignment.Left
        profileStatus.TextTruncate = Enum.TextTruncate.AtEnd
        profileStatus.ZIndex = 131
        bindTheme(profileStatus, "TextColor3", "TextDim")

        local profileGame = Instance.new("TextLabel", profilePanel)
        profileGame.BackgroundTransparency = 1
        profileGame.Position = UDim2.new(0, profileLayout.PadX, 0, profileLayout.GameY)
        profileGame.Size = UDim2.new(1, -(profileLayout.PadX * 2), 0, profileLayout.GameH)
        profileGame.Font = config.FontMedium
        profileGame.Text = "Game: unknown"
        profileGame.TextColor3 = colors.Text
        profileGame.TextSize = 10
        profileGame.TextXAlignment = Enum.TextXAlignment.Left
        profileGame.TextTruncate = Enum.TextTruncate.AtEnd
        profileGame.ZIndex = 131
        bindTheme(profileGame, "TextColor3", "Text")

        local profileFooter = Instance.new("Frame", profilePanel)
        profileFooter.BackgroundTransparency = 1
        profileFooter.Position = UDim2.new(0, profileLayout.PadX, 0, profileLayout.FooterY)
        profileFooter.Size = UDim2.new(1, -(profileLayout.PadX * 2), 0, profileLayout.FooterH)
        profileFooter.ZIndex = 131

        local profileJoinBtn = Instance.new("TextButton", profileFooter)
        profileJoinBtn.Size = UDim2.new(0.5, -(profileLayout.ButtonGap * 0.5), 1, 0)
        profileJoinBtn.BackgroundColor3 = Color3.fromRGB(45, 25, 30)
        profileJoinBtn.BorderSizePixel = 0
        profileJoinBtn.Font = config.FontMedium
        profileJoinBtn.Text = "Join Server"
        profileJoinBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        profileJoinBtn.TextSize = 10
        profileJoinBtn.AutoButtonColor = false
        profileJoinBtn.Selectable = false
        profileJoinBtn.ZIndex = 132
        bindTheme(profileJoinBtn, "TextColor3", "TextStrong")
        Instance.new("UICorner", profileJoinBtn).CornerRadius = UDim.new(0, 3)

        local profileCloseBtn = Instance.new("TextButton", profileFooter)
        profileCloseBtn.AnchorPoint = Vector2.new(1, 0)
        profileCloseBtn.Position = UDim2.new(1, 0, 0, 0)
        profileCloseBtn.Size = UDim2.new(0.5, -(profileLayout.ButtonGap * 0.5), 1, 0)
        profileCloseBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
        profileCloseBtn.BorderSizePixel = 0
        profileCloseBtn.Font = config.FontMedium
        profileCloseBtn.Text = "Close"
        profileCloseBtn.TextColor3 = colors.Text
        profileCloseBtn.TextSize = 10
        profileCloseBtn.AutoButtonColor = false
        profileCloseBtn.Selectable = false
        profileCloseBtn.ZIndex = 132
        bindTheme(profileCloseBtn, "BackgroundColor3", "Control")
        bindTheme(profileCloseBtn, "BackgroundTransparency", "ControlTransparency")
        bindTheme(profileCloseBtn, "TextColor3", "Text")
        Instance.new("UICorner", profileCloseBtn).CornerRadius = UDim.new(0, 3)

        local profilePopupConfig = {
            ClosedSize = UDim2.fromOffset(profilePanelWidth, 0),
            OpenSize = UDim2.fromOffset(profilePanelWidth, profilePanelHeight),
            OpenToken = "Open",
            CloseToken = "Close",
            HideDelay = 0.18,
        }

        local function updateProfileJoinVisual()
            local hasTarget = type(activeProfileData) == "table"
                and tonumber(activeProfileData.placeid or 0)
                and tonumber(activeProfileData.placeid or 0) > 0
                and type(activeProfileData.jobid) == "string"
                and activeProfileData.jobid ~= ""
                and not (
                    tonumber(activeProfileData.placeid or 0) == tonumber(game.PlaceId or 0)
                    and tostring(activeProfileData.jobid or "") == tostring(game.JobId or "")
                )

            if hasTarget then
                profileJoinBtn.Text = "Join Server"
                profileJoinBtn.TextTransparency = 0
                profileJoinBtn.Active = true
                return
            end

            profileJoinBtn.Text = "Join Unavailable"
            profileJoinBtn.TextTransparency = 0.35
            profileJoinBtn.Active = false
        end

        setProfileOpen = function(nextOpen)
            if profileOpen == nextOpen then
                return
            end
            profileOpen = nextOpen
            setPopupOpen(profilePanel, profileOpen, profilePopupConfig)
        end

        local function positionProfilePanelFromSource(sourceGui)
            local panelSize = chatPanel.AbsoluteSize
            local panelPos = chatPanel.AbsolutePosition
            local x = panelSize.X * 0.5
            local y = panelSize.Y - 8

            if sourceGui and sourceGui.Parent and sourceGui:IsDescendantOf(chatPanel) then
                local srcPos = sourceGui.AbsolutePosition
                local srcSize = sourceGui.AbsoluteSize
                x = (srcPos.X - panelPos.X) + (srcSize.X * 0.5)
                local desiredBottom = (srcPos.Y - panelPos.Y) - 4
                y = desiredBottom
            end

            x = math.clamp(x, profilePanelWidth * 0.5 + 6, panelSize.X - profilePanelWidth * 0.5 - 6)
            y = math.clamp(y, profilePanelHeight + 6, panelSize.Y - 6)
            profilePanel.Position = UDim2.fromOffset(math.floor(x + 0.5), math.floor(y + 0.5))
        end

        registerTransientPopup(profilePanel, function()
            setProfileOpen(false)
        end)

        if popupManager and type(popupManager.bindOutsideClose) == "function" then
            popupManager.bindOutsideClose({
                cleanupKey = nextCleanupKey("ChatProfileOutsideClick"),
                close = function()
                    setProfileOpen(false)
                end,
                isOpen = function()
                    return profileOpen
                end,
                targets = function()
                    return { profilePanel }
                end,
            })
        end

        profileCloseBtn.Activated:Connect(function()
            setProfileOpen(false)
        end)

        profileJoinBtn.MouseEnter:Connect(function()
            if profileJoinBtn.Active then
                Library:Animate(profileJoinBtn, "Hover", { BackgroundColor3 = Color3.fromRGB(60, 30, 38) })
            end
        end)
        profileJoinBtn.MouseLeave:Connect(function()
            Library:Animate(profileJoinBtn, "Hover", { BackgroundColor3 = Color3.fromRGB(45, 25, 30) })
        end)
        profileJoinBtn.Activated:Connect(function()
            if not profileJoinBtn.Active then
                return
            end
            if type(activeProfileData) ~= "table" then
                return
            end

            local placeId = tonumber(activeProfileData.placeid or 0)
            local jobId = tostring(activeProfileData.jobid or "")
            if not placeId or placeId <= 0 or jobId == "" then
                return
            end

            pcall(function()
                TeleportService:TeleportToPlaceInstance(placeId, jobId, Client)
            end)
        end)

        local function applyProfileData(profileData)
            local name = tostring(profileData.user or profileData.name or "unknown")
            local userIdText = tostring(profileData.userid or "")
            local statusText = tostring(profileData.status or "unknown")
            local gameText = tostring(profileData.game or profileData.lastLocation or "unknown")

            profileName.Text = userIdText ~= "" and string.format("%s (%s)", name, userIdText) or name
            profileStatus.Text = "Status: " .. statusText
            profileGame.Text = "Game: " .. gameText
            activeProfileData = profileData
            updateProfileJoinVisual()
        end

        local function resolveProfile(userName, userId)
            local resolved = {
                user = tostring(userName or "unknown"),
                userid = tostring(userId or ""),
                status = "unknown",
                game = "unknown",
                placeid = 0,
                jobid = "",
            }

            local livePlayer = Players:FindFirstChild(resolved.user)
            if livePlayer then
                resolved.userid = tostring(livePlayer.UserId or resolved.userid)
                resolved.status = "in this server"
                resolved.game = "Current Server"
                resolved.placeid = tonumber(game.PlaceId or 0) or 0
                resolved.jobid = tostring(game.JobId or "")
                return resolved
            end

            if (resolved.userid == "" or resolved.userid == "0") and resolved.user ~= "" then
                pcall(function()
                    resolved.userid = tostring(Players:GetUserIdFromNameAsync(resolved.user))
                end)
            end

            local provider = chatProvider
            local profileFn = type(provider) == "table" and (provider.Profile or provider.profile or provider.GetProfile or provider.getProfile) or nil
            if type(profileFn) == "function" then
                local okCall, okResult, response = callProviderFunction(provider, profileFn, resolved.user, resolved.userid)
                if okCall and okResult ~= false and type(response) == "table" then
                    resolved.status = tostring(response.status or (response.online and "online" or "unknown"))
                    resolved.game = tostring(response.game or response.placeName or resolved.game)
                    resolved.placeid = tonumber(response.placeid or response.placeId or resolved.placeid) or resolved.placeid
                    resolved.jobid = tostring(response.jobid or response.gameId or resolved.jobid or "")
                end
            end

            local presence = fetchPresenceForUserId(resolved.userid)
            if type(presence) == "table" then
                local presenceType = tonumber(presence.userPresenceType) or 0
                if presenceType == 2 then
                    resolved.status = "online"
                elseif presenceType == 1 then
                    resolved.status = "online (website)"
                else
                    resolved.status = "offline"
                end

                resolved.game = tostring(presence.lastLocation or resolved.game)
                resolved.placeid = tonumber(presence.placeId or presence.rootPlaceId or resolved.placeid) or resolved.placeid
                resolved.jobid = tostring(presence.gameId or resolved.jobid or "")
            end

            return resolved
        end

        local function openUserProfile(userName, userId, sourceGui)
            local normalizedName = string.lower(tostring(userName or ""))
            local cached = userMetaByName[normalizedName]
            local targetUserId = userId or (cached and cached.userid)

            activeProfileToken += 1
            local token = activeProfileToken

            applyProfileData({
                user = tostring(userName or "unknown"),
                userid = tostring(targetUserId or ""),
                status = "loading...",
                game = "loading...",
                placeid = 0,
                jobid = "",
            })
            profileLastSource = sourceGui
            positionProfilePanelFromSource(profileLastSource)
            setProfileOpen(true)

            task.spawn(function()
                local resolved = resolveProfile(userName, targetUserId)
                if token ~= activeProfileToken or win._destroyed then
                    return
                end
                applyProfileData(resolved)
            end)
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

        local function addChatRow(userName, bodyText, timeText, userId)
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

            local userButton = Instance.new("TextButton", rowHeader)
            userButton.BackgroundTransparency = 1
            userButton.BorderSizePixel = 0
            userButton.Size = UDim2.new(0.66, 0, 1, 0)
            userButton.Font = config.FontMedium
            userButton.Text = tostring(userName or "unknown")
            userButton.TextColor3 = colors.Main
            userButton.TextSize = 11
            userButton.TextXAlignment = Enum.TextXAlignment.Left
            userButton.ZIndex = 14
            userButton.AutoButtonColor = false
            userButton.Selectable = false
            bindTheme(userButton, "TextColor3", "Main")

            userButton.MouseEnter:Connect(function()
                Library:Animate(userButton, "Hover", { TextColor3 = Color3.fromRGB(255, 182, 201) })
            end)
            userButton.MouseLeave:Connect(function()
                Library:Animate(userButton, "Hover", { TextColor3 = colors.Main })
            end)
            userButton.Activated:Connect(function()
                openUserProfile(userName, userId, userButton)
            end)

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
            userMetaByName = {}
            lastSharedUsers = {}
            activeProfileData = nil
            setProfileOpen(false)
            setServerListOpen(false)
            setPresenceVisual(0)
            refreshServerListPanel()
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
                    local userId = entry.userid or entry.userId or entry.user_id or entry.roblox_userid
                    local bodyText = entry.message or entry.content or entry.text or entry.message_content
                    local timeText = resolveTimeLabel(entry)
                    local dedupeKey = getMessageKey(messageId, userName, bodyText, timeText)

                    local nameKey = string.lower(tostring(userName or ""))
                    if nameKey ~= "" then
                        userMetaByName[nameKey] = {
                            user = userName,
                            userid = tostring(userId or ""),
                        }
                    end

                    if not chatSeen[dedupeKey] and type(bodyText) == "string" and trimChatText(bodyText) ~= "" then
                        chatSeen[dedupeKey] = true
                        addChatRow(userName, bodyText, timeText, userId)
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
                refreshSharedPresenceAsync()
            else
                setProfileOpen(false)
                setServerListOpen(false)
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
                    serverListScroll.ScrollBarImageColor3 = scrollColor
                end
                refreshChatButtonVisual()
                setPresenceVisual(lastPresenceCount)
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

        presenceLoopToken += 1
        local presenceToken = presenceLoopToken
        task.spawn(function()
            while not win._destroyed and presenceToken == presenceLoopToken do
                if canUseUi() then
                    refreshSharedPresenceAsync()
                else
                    setPresenceVisual(0)
                end
                task.wait(presenceInterval)
            end
        end)

        function win:SetChatProvider(provider)
            chatProvider = resolveChatProvider(provider)
            chatPanelRuntime.LastId = 0
            if type(chatPanelRuntime.Reset) == "function" then
                chatPanelRuntime.Reset()
            end
            refreshSharedPresenceAsync()
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
