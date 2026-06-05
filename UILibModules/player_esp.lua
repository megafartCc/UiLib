return function(Library, context)
    local DEFAULT_ESP_URL = "https://raw.githubusercontent.com/megafartCc/SAB/main/espmodule.lua"

    local function themeColor(key, fallback)
        if type(Library.GetThemeValue) == "function" then
            local value = Library:GetThemeValue(key)
            if value ~= nil then
                return value
            end
        end
        return fallback
    end

    local function bindTheme(instance, propertyName, themeKey, transform)
        if type(Library.RegisterThemeBinding) == "function" then
            Library:RegisterThemeBinding(instance, propertyName, themeKey, transform)
        end
    end

    local function loadEspModule(sourceUrl)
        local okGame, isGameInstance = pcall(function()
            return typeof(game) == "Instance"
        end)
        if not okGame or not isGameInstance then
            return nil
        end
        if type(game.HttpGet) ~= "function" or type(loadstring) ~= "function" then
            return nil
        end

        local ok, result = pcall(function()
            return loadstring(game:HttpGet(sourceUrl or DEFAULT_ESP_URL))()
        end)
        if ok then
            return result
        end
        return nil
    end

    local function safeEspCall(esp, methodName, value)
        if esp and type(esp[methodName]) == "function" then
            pcall(esp[methodName], esp, value)
        end
    end

    local function createGuiEspModule(opts)
        opts = opts or {}

        local Players = context.Players or game:GetService("Players")
        local RunService = context.RunService or game:GetService("RunService")
        local LocalPlayer = context.Client or Players.LocalPlayer
        local C3 = Color3.fromRGB
        local V2 = Vector2.new

        local settings = {
            Box = false,
            Name = false,
            Health = false,
            Team = false,
            Tracers = false,
            Skeleton = false,
            HeldItem = false,
            MaxDistance = opts.MaxDistance or 1000,
        }

        local tracked = {}
        local renderConnection = nil
        local playerEspGui = nil

        local function getEspGui()
            local ok, parent = pcall(context.getHiddenParent)
            if not ok or not parent then
                return nil
            end

            if playerEspGui and playerEspGui.Parent == parent then
                return playerEspGui
            end

            local existing = parent:FindFirstChild("UnknownHubPlayerEsp")
            if existing and existing:IsA("ScreenGui") then
                playerEspGui = existing
                return playerEspGui
            end

            local gui = Instance.new("ScreenGui")
            gui.Name = "UnknownHubPlayerEsp"
            gui.IgnoreGuiInset = true
            gui.ResetOnSpawn = false
            gui.DisplayOrder = 100000
            gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
            gui.Parent = parent
            playerEspGui = gui
            return gui
        end

        local function destroyObject(object)
            if object then
                pcall(function()
                    object:Destroy()
                end)
            end
        end

        local function makeLabel(name, color, textSize, zIndex)
            local gui = getEspGui()
            if not gui then
                return nil
            end

            local label = Instance.new("TextLabel")
            label.Name = name
            label.AnchorPoint = Vector2.new(0.5, 0.5)
            label.BackgroundTransparency = 1
            label.BorderSizePixel = 0
            label.Font = Enum.Font.GothamBold
            label.TextColor3 = color
            label.TextSize = textSize
            label.TextStrokeColor3 = C3(0, 0, 0)
            label.TextStrokeTransparency = 0
            label.TextWrapped = false
            label.Visible = false
            label.ZIndex = zIndex or 120
            label.Size = UDim2.fromOffset(230, textSize + 8)
            label.Parent = gui
            return label
        end

        local function makeLine(name, color, thickness, zIndex)
            local gui = getEspGui()
            if not gui then
                return nil
            end

            local line = Instance.new("Frame")
            line.Name = name
            line.AnchorPoint = Vector2.new(0.5, 0.5)
            line.BackgroundColor3 = color
            line.BackgroundTransparency = 0.05
            line.BorderSizePixel = 0
            line.Size = UDim2.fromOffset(0, thickness or 1)
            line.Visible = false
            line.ZIndex = zIndex or 110
            line.Parent = gui
            return line
        end

        local function setVisible(object, visible)
            if object then
                object.Visible = visible == true
            end
        end

        local function hideList(list)
            for _, object in ipairs(list or {}) do
                setVisible(object, false)
            end
        end

        local function updateLine(line, fromPoint, toPoint, color, thickness)
            if not line or not fromPoint or not toPoint then
                setVisible(line, false)
                return
            end

            local delta = toPoint - fromPoint
            local length = delta.Magnitude
            if length < 1 then
                setVisible(line, false)
                return
            end

            line.BackgroundColor3 = color
            line.Size = UDim2.fromOffset(length, thickness or 1)
            line.Position = UDim2.fromOffset((fromPoint.X + toPoint.X) * 0.5, (fromPoint.Y + toPoint.Y) * 0.5)
            line.Rotation = math.deg((math.atan2 or math.atan)(delta.Y, delta.X))
            line.Visible = true
        end

        local function project(camera, position)
            local point, onScreen = camera:WorldToViewportPoint(position)
            if not onScreen or point.Z <= 0 then
                return nil
            end
            return V2(point.X, point.Y)
        end

        local function updateWorldLine(camera, line, fromPosition, toPosition, color, thickness)
            local fromPoint = fromPosition and project(camera, fromPosition)
            local toPoint = toPosition and project(camera, toPosition)
            updateLine(line, fromPoint, toPoint, color, thickness)
        end

        local function makePlayerData(player)
            if tracked[player] then
                return tracked[player]
            end

            local data = {
                box = {},
                skeleton = {},
            }

            for index = 1, 4 do
                data.box[index] = makeLine("PlayerBoxEspLine", C3(255, 255, 255), 1, 120)
            end

            data.tracer = makeLine("PlayerTracerEspLine", C3(255, 255, 255), 1, 110)
            data.healthBack = makeLine("PlayerHealthEspBack", C3(0, 0, 0), 3, 115)
            data.healthFill = makeLine("PlayerHealthEspFill", C3(0, 255, 0), 2, 125)
            data.name = makeLabel("PlayerNameEsp", C3(255, 255, 255), 14, 130)
            data.team = makeLabel("PlayerTeamEsp", C3(255, 255, 255), 13, 130)
            data.heldItem = makeLabel("PlayerHeldItemEsp", C3(255, 200, 0), 13, 130)

            if data.team then
                data.team.AnchorPoint = Vector2.new(0, 0.5)
                data.team.TextXAlignment = Enum.TextXAlignment.Left
                data.team.Size = UDim2.fromOffset(170, 20)
            end

            tracked[player] = data
            return data
        end

        local function removePlayerData(player)
            local data = tracked[player]
            if not data then
                return
            end

            for _, line in ipairs(data.box or {}) do
                destroyObject(line)
            end
            for _, line in ipairs(data.skeleton or {}) do
                destroyObject(line)
            end
            destroyObject(data.tracer)
            destroyObject(data.healthBack)
            destroyObject(data.healthFill)
            destroyObject(data.name)
            destroyObject(data.team)
            destroyObject(data.heldItem)
            tracked[player] = nil
        end

        local function hideData(data)
            if not data then
                return
            end

            hideList(data.box)
            hideList(data.skeleton)
            setVisible(data.tracer, false)
            setVisible(data.healthBack, false)
            setVisible(data.healthFill, false)
            setVisible(data.name, false)
            setVisible(data.team, false)
            setVisible(data.heldItem, false)
        end

        local r15SkeletonPairs = {
            { { "Head" }, { "UpperTorso" } },
            { { "UpperTorso" }, { "LowerTorso" } },
            { { "UpperTorso" }, { "LeftHand", "LeftLowerArm", "LeftUpperArm" } },
            { { "UpperTorso" }, { "RightHand", "RightLowerArm", "RightUpperArm" } },
            { { "LowerTorso" }, { "LeftFoot", "LeftLowerLeg", "LeftUpperLeg" } },
            { { "LowerTorso" }, { "RightFoot", "RightLowerLeg", "RightUpperLeg" } },
        }

        local r6SkeletonPairs = {
            { { "Head" }, { "Torso" } },
            { { "Torso" }, { "Left Arm" } },
            { { "Torso" }, { "Right Arm" } },
            { { "Torso" }, { "Left Leg" } },
            { { "Torso" }, { "Right Leg" } },
        }

        local function getSkeletonPairs(humanoid)
            if humanoid and humanoid.RigType == Enum.HumanoidRigType.R15 then
                return r15SkeletonPairs
            end
            return r6SkeletonPairs
        end

        local function findSkeletonPart(character, names)
            for _, name in ipairs(names or {}) do
                local part = character:FindFirstChild(name)
                if part and part:IsA("BasePart") then
                    return part
                end
            end
            return nil
        end

        local function updateSkeleton(camera, data, character, humanoid, color)
            local pairsList = getSkeletonPairs(humanoid)

            while #data.skeleton < #pairsList do
                table.insert(data.skeleton, makeLine("PlayerSkeletonEspLine", color, 2, 118))
            end

            for index, pair in ipairs(pairsList) do
                local line = data.skeleton[index]
                local fromPart = findSkeletonPart(character, pair[1])
                local toPart = findSkeletonPart(character, pair[2])
                if fromPart and toPart then
                    updateWorldLine(camera, line, fromPart.Position, toPart.Position, color, 2)
                else
                    setVisible(line, false)
                end
            end

            for index = #pairsList + 1, #data.skeleton do
                setVisible(data.skeleton[index], false)
            end
        end

        local function getRoot(character)
            return character and character:FindFirstChild("HumanoidRootPart")
        end

        local function isAlive(character)
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            return humanoid and humanoid.Health > 0, humanoid
        end

        local function getPlayerColor(player)
            if player.TeamColor then
                return player.TeamColor.Color
            end
            return C3(255, 255, 255)
        end

        local function anyEnabled()
            return settings.Box
                or settings.Name
                or settings.Health
                or settings.Team
                or settings.Tracers
                or settings.Skeleton
                or settings.HeldItem
        end

        local function render()
            local camera = workspace.CurrentCamera
            local localRoot = getRoot(LocalPlayer and LocalPlayer.Character)
            if not camera or not localRoot then
                for _, data in pairs(tracked) do
                    hideData(data)
                end
                return
            end

            local seen = {}
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer then
                    seen[player] = true
                    local data = makePlayerData(player)
                    local character = player.Character
                    local alive, humanoid = isAlive(character)
                    local root = getRoot(character)
                    if not alive or not root then
                        hideData(data)
                    else
                        local distance = (root.Position - localRoot.Position).Magnitude
                        if distance > settings.MaxDistance then
                            hideData(data)
                        else
                            local centerPoint = project(camera, root.Position)
                            local topPoint = project(camera, root.Position + Vector3.new(0, 3, 0))
                            local bottomPoint = project(camera, root.Position - Vector3.new(0, 3, 0))
                            if not centerPoint or not topPoint or not bottomPoint then
                                hideData(data)
                            else
                                local height = math.max(28, math.abs(bottomPoint.Y - topPoint.Y))
                                local width = math.max(14, height * 0.5)
                                local left = centerPoint.X - width * 0.5
                                local right = centerPoint.X + width * 0.5
                                local top = centerPoint.Y - height * 0.5
                                local bottom = centerPoint.Y + height * 0.5
                                local color = getPlayerColor(player)

                                if settings.Box then
                                    updateLine(data.box[1], V2(left, top), V2(right, top), color, 1)
                                    updateLine(data.box[2], V2(left, bottom), V2(right, bottom), color, 1)
                                    updateLine(data.box[3], V2(left, top), V2(left, bottom), color, 1)
                                    updateLine(data.box[4], V2(right, top), V2(right, bottom), color, 1)
                                else
                                    hideList(data.box)
                                end

                                if data.name then
                                    data.name.Text = player.DisplayName or player.Name
                                    data.name.TextColor3 = color
                                    data.name.Position = UDim2.fromOffset(centerPoint.X, top - 18)
                                    data.name.Visible = settings.Name
                                end

                                if data.team then
                                    data.team.Text = player.Team and player.Team.Name or "No Team"
                                    data.team.TextColor3 = color
                                    data.team.Position = UDim2.fromOffset(right + 8, top + 8)
                                    data.team.Visible = settings.Team
                                end

                                if settings.Health then
                                    local ratio = math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1)
                                    local x = left - 6
                                    updateLine(data.healthBack, V2(x, bottom), V2(x, top), C3(0, 0, 0), 3)
                                    updateLine(data.healthFill, V2(x, bottom), V2(x, bottom - ((bottom - top) * ratio)), C3(255, 0, 0):Lerp(C3(0, 255, 0), ratio), 2)
                                else
                                    setVisible(data.healthBack, false)
                                    setVisible(data.healthFill, false)
                                end

                                if settings.Tracers then
                                    updateLine(data.tracer, V2(camera.ViewportSize.X * 0.5, camera.ViewportSize.Y - 8), V2(centerPoint.X, bottom), color, 1)
                                else
                                    setVisible(data.tracer, false)
                                end

                                if settings.Skeleton then
                                    updateSkeleton(camera, data, character, humanoid, color)
                                else
                                    hideList(data.skeleton)
                                end

                                if data.heldItem then
                                    local tool = character:FindFirstChildWhichIsA("Tool")
                                    data.heldItem.Text = tool and tool.Name or ""
                                    data.heldItem.Position = UDim2.fromOffset(centerPoint.X, bottom + 10)
                                    data.heldItem.Visible = settings.HeldItem and tool ~= nil
                                end
                            end
                        end
                    end
                end
            end

            for player in pairs(tracked) do
                if not seen[player] or not player.Parent then
                    removePlayerData(player)
                end
            end
        end

        local function updateLoop()
            if anyEnabled() then
                if not renderConnection then
                    renderConnection = RunService.RenderStepped:Connect(function()
                        pcall(render)
                    end)
                end
                pcall(render)
            else
                if renderConnection then
                    renderConnection:Disconnect()
                    renderConnection = nil
                end
                for _, data in pairs(tracked) do
                    hideData(data)
                end
            end
        end

        local api = {}

        function api:Init()
            updateLoop()
        end

        function api:SetBoxEsp(value)
            settings.Box = value == true
            updateLoop()
        end

        function api:SetNameEsp(value)
            settings.Name = value == true
            updateLoop()
        end

        function api:SetHealthEsp(value)
            settings.Health = value == true
            updateLoop()
        end

        function api:SetTeamEsp(value)
            settings.Team = value == true
            updateLoop()
        end

        function api:SetTracers(value)
            settings.Tracers = value == true
            updateLoop()
        end

        function api:SetSkeletonEsp(value)
            settings.Skeleton = value == true
            updateLoop()
        end

        function api:SetHeldItemEsp(value)
            settings.HeldItem = value == true
            updateLoop()
        end

        function api:SetMaxDist(value)
            settings.MaxDistance = tonumber(value) or settings.MaxDistance
            updateLoop()
        end

        function api:Destroy()
            if renderConnection then
                renderConnection:Disconnect()
                renderConnection = nil
            end
            for player in pairs(tracked) do
                removePlayerData(player)
            end
        end

        return api
    end

    local function makePreview(menu, controlsSection, state, opts)
        opts = opts or {}

        local win = controlsSection and controlsSection._win
        local main = win and win._main
        if not main then
            return nil
        end

        local initialVisible = true
        if menu._page then
            initialVisible = menu._page.Visible == true
        end
        initialVisible = initialVisible and state.Preview == true

        local previewWidth = opts.PreviewWidth or 240
        local previewVerticalInset = opts.PreviewVerticalInset or 0

        local panel = Instance.new("Frame", main)
        panel.Name = "PlayerEspPreviewPanel"
        panel.AnchorPoint = Vector2.new(0, 0.5)
        panel.BackgroundColor3 = themeColor("Section", Color3.fromRGB(24, 24, 24))
        panel.BackgroundTransparency = themeColor("SectionTransparency", 0)
        panel.BorderSizePixel = 0
        panel.ClipsDescendants = true
        panel.Position = UDim2.new(1, opts.PreviewGap or 8, 0.5, 0)
        panel.Size = UDim2.new(0, previewWidth, 1, -previewVerticalInset)
        panel.Visible = initialVisible
        panel.ZIndex = 90
        bindTheme(panel, "BackgroundColor3", "Section")
        bindTheme(panel, "BackgroundTransparency", "SectionTransparency")
        Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 5)

        local panelStroke = Instance.new("UIStroke", panel)
        panelStroke.Color = themeColor("Line", Color3.fromRGB(60, 60, 60))
        panelStroke.Transparency = 0.8
        bindTheme(panelStroke, "Color", "Line")

        local title = Instance.new("TextLabel", panel)
        title.Name = "Title"
        title.BackgroundTransparency = 1
        title.BorderSizePixel = 0
        title.Position = UDim2.new(0, 10, 0, 10)
        title.Size = UDim2.new(1, -20, 0, 16)
        title.Font = Enum.Font.GothamBold
        title.Text = opts.PreviewName or "ESP PREVIEW"
        title.TextColor3 = themeColor("Text", Color3.fromRGB(235, 235, 235))
        title.TextSize = 10
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.ZIndex = 91
        bindTheme(title, "TextColor3", "Text")

        local sample = Instance.new("Frame", panel)
        sample.Name = "Box"
        sample.AnchorPoint = Vector2.new(0.5, 0.5)
        sample.BackgroundTransparency = 1
        sample.Position = UDim2.new(0.5, 0, 0.48, 0)
        sample.Size = UDim2.fromOffset(72, 150)
        sample.ZIndex = 91

        local boxStroke = Instance.new("UIStroke", sample)
        boxStroke.Color = themeColor("Line", Color3.fromRGB(60, 60, 60))
        boxStroke.Thickness = 1
        boxStroke.Transparency = 0.65

        local function makeText(name, parent, textSize, align)
            local label = Instance.new("TextLabel", parent)
            label.Name = name
            label.BackgroundTransparency = 1
            label.BorderSizePixel = 0
            label.Font = Enum.Font.GothamBold
            label.TextColor3 = themeColor("Text", Color3.fromRGB(235, 235, 235))
            label.TextSize = textSize or 11
            label.TextStrokeTransparency = 0.35
            label.TextXAlignment = align or Enum.TextXAlignment.Center
            label.TextYAlignment = Enum.TextYAlignment.Center
            label.ZIndex = 92
            bindTheme(label, "TextColor3", "Text")
            return label
        end

        local nameLabel = makeText("NameLabel", sample, 11)
        nameLabel.Text = opts.PreviewPlayerName or "PreviewPlayer"
        nameLabel.Position = UDim2.new(0, -70, 0, -24)
        nameLabel.Size = UDim2.new(1, 140, 0, 16)

        local teamLabel = makeText("TeamLabel", sample, 11, Enum.TextXAlignment.Left)
        teamLabel.Text = opts.PreviewTeamName or "No Team"
        teamLabel.Position = UDim2.new(1, 8, 0, 0)
        teamLabel.Size = UDim2.new(0, 74, 0, 15)

        local healthBack = Instance.new("Frame", sample)
        healthBack.Name = "HealthBack"
        healthBack.BackgroundColor3 = themeColor("Line", Color3.fromRGB(60, 60, 60))
        healthBack.BorderSizePixel = 0
        healthBack.Position = UDim2.new(0, -8, 0, 0)
        healthBack.Size = UDim2.new(0, 3, 1, 0)
        healthBack.ZIndex = 92
        bindTheme(healthBack, "BackgroundColor3", "Line")

        local healthFill = Instance.new("Frame", healthBack)
        healthFill.Name = "HealthFill"
        healthFill.AnchorPoint = Vector2.new(0, 1)
        healthFill.BackgroundColor3 = Color3.fromRGB(76, 255, 115)
        healthFill.BorderSizePixel = 0
        healthFill.Position = UDim2.new(0, 0, 1, 0)
        healthFill.Size = UDim2.new(1, 0, 0.82, 0)
        healthFill.ZIndex = 93

        local healthText = makeText("HealthText", sample, 10, Enum.TextXAlignment.Right)
        healthText.Text = opts.PreviewHealthText or "82 HP"
        healthText.Position = UDim2.new(0, -58, 0, 8)
        healthText.Size = UDim2.new(0, 46, 0, 14)

        local heldItemLabel = makeText("HeldItemLabel", sample, 11)
        heldItemLabel.Text = opts.PreviewHeldItem or "Knife"
        heldItemLabel.TextColor3 = themeColor("Main", Color3.fromRGB(245, 49, 116))
        heldItemLabel.Position = UDim2.new(0, -45, 1, 5)
        heldItemLabel.Size = UDim2.new(1, 90, 0, 16)
        bindTheme(heldItemLabel, "TextColor3", "Main")

        local tracerLine = Instance.new("Frame", panel)
        tracerLine.Name = "Tracer"
        tracerLine.AnchorPoint = Vector2.new(0.5, 0.5)
        tracerLine.BackgroundColor3 = themeColor("Main", Color3.fromRGB(245, 49, 116))
        tracerLine.BorderSizePixel = 0
        tracerLine.Size = UDim2.fromOffset(1, 1)
        tracerLine.ZIndex = 91
        bindTheme(tracerLine, "BackgroundColor3", "Main")

        local skeletonLines = {}
        local function makeLine(name)
            local line = Instance.new("Frame", sample)
            line.Name = name
            line.AnchorPoint = Vector2.new(0.5, 0.5)
            line.BackgroundColor3 = Color3.fromRGB(0, 255, 255)
            line.BorderSizePixel = 0
            line.Size = UDim2.fromOffset(1, 1)
            line.ZIndex = 92
            table.insert(skeletonLines, line)
            return line
        end

        local skeleton = {
            Shoulders = makeLine("SkeletonShoulders"),
            Neck = makeLine("SkeletonNeck"),
            Spine = makeLine("SkeletonSpine"),
            Hips = makeLine("SkeletonHips"),
            LeftArm = makeLine("SkeletonLeftArm"),
            RightArm = makeLine("SkeletonRightArm"),
            LeftLeg = makeLine("SkeletonLeftLeg"),
            RightLeg = makeLine("SkeletonRightLeg"),
        }

        local function snapPixel(value)
            return math.floor(value + 0.5)
        end

        local function setLine(line, x1, y1, x2, y2, thickness)
            x1 = snapPixel(x1)
            y1 = snapPixel(y1)
            x2 = snapPixel(x2)
            y2 = snapPixel(y2)

            local dx = x2 - x1
            local dy = y2 - y1
            local length = math.sqrt((dx * dx) + (dy * dy))
            local resolvedThickness = thickness
            if not resolvedThickness then
                resolvedThickness = (math.abs(dx) < 0.01 or math.abs(dy) < 0.01) and 2 or 1
            end

            line.Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2)
            line.Size = UDim2.fromOffset(math.max(1, length + 1), resolvedThickness)
            line.Rotation = math.deg((math.atan2 or math.atan)(dy, dx))
        end

        local function layoutPreview()
            local panelHeight = panel.AbsoluteSize.Y
            local panelWidth = panel.AbsoluteSize.X
            if panelHeight <= 0 or panelWidth <= 0 then
                return
            end

            local boxHeight = math.clamp(math.floor(panelHeight * 0.42), 120, math.max(120, panelHeight - 64))
            boxHeight = math.max(120, math.floor(boxHeight / 2) * 2)
            local boxWidth = math.clamp(math.floor(boxHeight * 0.48), 56, math.max(56, panelWidth - 46))
            boxWidth = math.max(56, math.floor(boxWidth / 2) * 2)
            sample.Size = UDim2.fromOffset(boxWidth, boxHeight)

            local boxCenterY = snapPixel(panelHeight * 0.48)
            local boxBottomY = boxCenterY + (boxHeight / 2)
            local boxCenterX = snapPixel(panelWidth / 2)
            sample.Position = UDim2.fromOffset(boxCenterX, boxCenterY)
            setLine(tracerLine, boxCenterX, panelHeight - 18, boxCenterX, boxBottomY, 1)

            local cx = snapPixel(boxWidth / 2)
            local headY = snapPixel(boxHeight * 0.23)
            local shoulderY = snapPixel(boxHeight * 0.35)
            local hipY = snapPixel(boxHeight * 0.61)
            local handY = snapPixel(boxHeight * 0.55)
            local footY = snapPixel(boxHeight * 0.91)

            local shoulderHalf = snapPixel(boxWidth * 0.30)
            local hipHalf = snapPixel(boxWidth * 0.17)
            local handHalf = snapPixel(boxWidth * 0.43)
            local footHalf = snapPixel(boxWidth * 0.28)

            setLine(skeleton.Shoulders, cx - shoulderHalf, shoulderY, cx + shoulderHalf, shoulderY)
            setLine(skeleton.Neck, cx, headY, cx, shoulderY)
            setLine(skeleton.Spine, cx, shoulderY, cx, hipY)
            setLine(skeleton.Hips, cx - hipHalf, hipY, cx + hipHalf, hipY)
            setLine(skeleton.LeftArm, cx - shoulderHalf, shoulderY, cx - handHalf, handY)
            setLine(skeleton.RightArm, cx + shoulderHalf, shoulderY, cx + handHalf, handY)
            setLine(skeleton.LeftLeg, cx - hipHalf, hipY, cx - footHalf, footY)
            setLine(skeleton.RightLeg, cx + hipHalf, hipY, cx + footHalf, footY)
        end

        local syncVisibility

        local function refreshPreview()
            syncVisibility()

            local activeColor = themeColor("Main", Color3.fromRGB(245, 49, 116))
            local inactiveColor = themeColor("Line", Color3.fromRGB(60, 60, 60))

            if state.Box then
                boxStroke.Color = activeColor
                boxStroke.Transparency = 0.05
            else
                boxStroke.Color = inactiveColor
                boxStroke.Transparency = 0.65
            end

            nameLabel.Visible = state.Name == true
            teamLabel.Visible = state.Team == true
            healthBack.Visible = state.Health == true
            healthText.Visible = state.Health == true
            tracerLine.Visible = state.Tracers == true
            heldItemLabel.Visible = state.HeldItem == true
            for _, line in ipairs(skeletonLines) do
                line.Visible = state.Skeleton == true
            end
        end

        syncVisibility = function()
            panel.Visible = state.Preview == true and (menu._page == nil or menu._page.Visible == true)
        end

        local function syncLayout()
            panel.Size = UDim2.new(0, previewWidth, 1, -previewVerticalInset)
            layoutPreview()
        end

        if controlsSection._cleanup and type(controlsSection._cleanup.Add) == "function" then
            controlsSection._cleanup:Add(panel, "Destroy", "PlayerEspPreviewPanel")
        end
        controlsSection:TrackConnection(panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutPreview), "PlayerEspPreviewLayout")
        controlsSection:TrackConnection(main:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncLayout), "PlayerEspPreviewWindowLayout")
        if menu._page then
            controlsSection:TrackConnection(menu._page:GetPropertyChangedSignal("Visible"):Connect(syncVisibility), "PlayerEspPreviewVisibility")
        end
        if type(Library.RegisterThemeCallback) == "function" then
            Library:RegisterThemeCallback(function()
                if panel.Parent then
                    refreshPreview()
                end
            end)
        end

        task.defer(syncLayout)
        task.defer(syncVisibility)
        task.defer(refreshPreview)

        return {
            Frame = panel,
            Box = sample,
            Refresh = refreshPreview,
            SetVisible = function(_, value)
                state.Preview = value == true
                syncVisibility()
            end,
        }
    end

    local function addPlayerEspSection(selfOrMenu, menuOrOpts, maybeOpts)
        local menu = selfOrMenu
        local opts = menuOrOpts

        if selfOrMenu == Library then
            menu = menuOrOpts
            opts = maybeOpts
        end

        opts = opts or {}
        if type(menu) ~= "table" or type(menu.AddSection) ~= "function" then
            error("AddPlayerESPSection requires a UiLib menu", 2)
        end

        local providedEsp = opts.ESP or opts.Esp or opts.Module
        local esp = nil
        if opts.UseProvidedEsp == true then
            esp = providedEsp
        elseif opts.LoadEsp == "external" or opts.UseExternalEsp == true then
            esp = providedEsp
            if not esp then
                esp = loadEspModule(opts.SourceUrl or opts.Url)
            end
        else
            esp = createGuiEspModule(opts)
        end

        if not esp and opts.LoadEsp ~= false then
            esp = loadEspModule(opts.SourceUrl or opts.Url)
        end
        if esp and type(esp.Init) == "function" then
            pcall(esp.Init, esp)
        end

        local section = opts.Section or menu:AddSection({
            Name = opts.Name or "PLAYER ESP",
            Column = opts.Column or 1,
        })

        local state = {
            Preview = opts.PreviewDefault ~= false,
            Box = opts.BoxDefault == true,
            Name = opts.NameDefault == true,
            Health = opts.HealthDefault == true,
            Team = opts.TeamDefault == true,
            Tracers = opts.TracersDefault == true,
            Skeleton = opts.SkeletonDefault == true,
            HeldItem = opts.HeldItemDefault == true,
            MaxDistance = opts.MaxDistance or 1000,
        }

        local api = {
            ESP = esp,
            Section = section,
            State = state,
            Controls = {},
        }

        local preview
        local function refreshPreview()
            if preview and preview.Refresh then
                preview.Refresh()
            end
        end

        local function notifyChange(key, value)
            local callback = opts["On" .. key .. "Changed"]
            if type(callback) == "function" then
                pcall(callback, value, api)
            end
            if type(opts.Callback) == "function" then
                pcall(opts.Callback, key, value, api)
            end
        end

        local function setToggle(key, methodName, value)
            state[key] = value and true or false
            safeEspCall(esp, methodName, state[key])
            refreshPreview()
            notifyChange(key, state[key])
        end

        local function addToggle(name, key, methodName, defaultValue)
            local control = section:AddToggle({
                Name = name,
                Default = defaultValue == true,
                Callback = function(value)
                    setToggle(key, methodName, value)
                end,
            })
            api.Controls[key] = control
            return control
        end

        if opts.Preview ~= false then
            api.Controls.Preview = section:AddToggle({
                Name = opts.PreviewToggleName or "ESP Preview",
                Default = state.Preview == true,
                Callback = function(value)
                    state.Preview = value == true
                    refreshPreview()
                    notifyChange("Preview", state.Preview)
                end,
            })
        end

        api.Controls.Box = addToggle("Box ESP", "Box", "SetBoxEsp", state.Box)

        if type(opts.AfterBox) == "function" then
            pcall(opts.AfterBox, section, api)
        end

        api.Controls.Name = addToggle("Name ESP", "Name", "SetNameEsp", state.Name)
        api.Controls.Health = addToggle("Health ESP", "Health", "SetHealthEsp", state.Health)
        api.Controls.Team = addToggle("Team ESP", "Team", "SetTeamEsp", state.Team)
        api.Controls.Tracers = addToggle("Tracers", "Tracers", "SetTracers", state.Tracers)
        api.Controls.Skeleton = addToggle("Skeleton ESP", "Skeleton", "SetSkeletonEsp", state.Skeleton)
        api.Controls.HeldItem = addToggle("Held Item ESP", "HeldItem", "SetHeldItemEsp", state.HeldItem)

        api.Controls.MaxDistance = section:AddSlider({
            Name = "Max Distance",
            Min = opts.MinDistance or 100,
            Max = opts.MaxDistanceLimit or 5000,
            Default = state.MaxDistance,
            Suffix = opts.DistanceSuffix or " studs",
            Callback = function(value)
                state.MaxDistance = value
                safeEspCall(esp, "SetMaxDist", value)
                notifyChange("MaxDistance", value)
            end,
        })

        if opts.Preview ~= false then
            preview = makePreview(menu, section, state, opts)
            api.Preview = preview
        end

        safeEspCall(esp, "SetBoxEsp", state.Box)
        safeEspCall(esp, "SetNameEsp", state.Name)
        safeEspCall(esp, "SetHealthEsp", state.Health)
        safeEspCall(esp, "SetTeamEsp", state.Team)
        safeEspCall(esp, "SetTracers", state.Tracers)
        safeEspCall(esp, "SetSkeletonEsp", state.Skeleton)
        safeEspCall(esp, "SetHeldItemEsp", state.HeldItem)
        safeEspCall(esp, "SetMaxDist", state.MaxDistance)
        refreshPreview()

        function api:SetEsp(nextEsp)
            esp = nextEsp
            self.ESP = nextEsp
            if esp and type(esp.Init) == "function" then
                pcall(esp.Init, esp)
            end
            safeEspCall(esp, "SetMaxDist", state.MaxDistance)
            return self
        end

        function api:GetState()
            local copy = {}
            for key, value in pairs(state) do
                copy[key] = value
            end
            return copy
        end

        function api:RefreshPreview()
            refreshPreview()
            return self
        end

        return api
    end

    Library.AddPlayerESPSection = addPlayerEspSection
    Library.CreatePlayerESPSection = addPlayerEspSection
end
