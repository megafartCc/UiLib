RunService = game:GetService("RunService")
Players = game:GetService("Players")
Workspace = game:GetService("Workspace")
ReplicatedStorage = game:GetService("ReplicatedStorage")
TweenService = game:GetService("TweenService")
Lighting = game:GetService("Lighting")
CoreGui = gethui()
UserInputService = game:GetService("UserInputService")
VirtualUser = game:GetService("VirtualUser")
HttpService = game:GetService("HttpService")
LocalPlayer = Players.LocalPlayer
camera = Workspace.CurrentCamera
player = LocalPlayer
SETTINGS_FILE = "EpsilonHub_Config.json"

-- Backend sync config (edit these with your own server + keys)
BACKEND_URL = "https://beeswarmfrontend-production.up.railway.app"
BACKEND_API_KEY = "99fds8fdsjkxckkxuihdshufdsZXbccxn"
BACKEND_SYNC_ENABLED = true              -- enabled with your keys set
BACKEND_USER_KEY_FILE = "bee_user_key.txt"
-- Cloud config removed

function loadRemoteUiLib()
    local baseUrl = "https://raw.githubusercontent.com/megafartCc/UiLib/main/UILibModules"
    local moduleCache = {}

    local function normalizePath(path)
        local parts = {}
        for part in string.gmatch(string.gsub(path, "\\", "/"), "[^/]+") do
            if part == ".." then
                if #parts > 0 then
                    table.remove(parts)
                end
            elseif part ~= "." and part ~= "" then
                table.insert(parts, part)
            end
        end
        return table.concat(parts, "/")
    end

    local function loadRemoteModule(path)
        local normalized = normalizePath(path)
        local cached = moduleCache[normalized]
        if cached ~= nil then
            return cached
        end
        local source = game:HttpGet(baseUrl .. "/" .. normalized)
        local chunk, err = loadstring(source)
        if not chunk then
            error(string.format("UiLib load failed for %s: %s", normalized, tostring(err)))
        end
        local exported = chunk()
        moduleCache[normalized] = exported
        return exported
    end

    local entryModule = loadRemoteModule("init.lua")
    local function moduleRequire(relativePath)
        return loadRemoteModule(relativePath)
    end
    return entryModule(moduleRequire)
end

local Library = loadRemoteUiLib()
Library._widgetRegistry = Library._widgetRegistry or {}
Library._compatSettings = Library._compatSettings or {}
Library._compatSettingsFile = nil

function cloneValue(v)
    if type(v) ~= "table" then
        return v
    end
    local out = {}
    for k, x in pairs(v) do
        out[cloneValue(k)] = cloneValue(x)
    end
    return out
end

function Library:_flushCompatSettings()
    if not self._compatSettingsFile then return end
    if type(writefile) ~= "function" then return end
    local ok, encoded = pcall(function()
        return HttpService:JSONEncode(self._compatSettings)
    end)
    if ok and type(encoded) == "string" then
        pcall(writefile, self._compatSettingsFile, encoded)
    end
end

function Library:InitAutoSave(fileName)
    self._compatSettingsFile = type(fileName) == "string" and fileName or "EpsilonHub_Config.json"
    self._compatSettings = {}
    if type(isfile) == "function" and type(readfile) == "function" and isfile(self._compatSettingsFile) then
        local okRead, raw = pcall(readfile, self._compatSettingsFile)
        if okRead and type(raw) == "string" and raw ~= "" then
            local okDecode, decoded = pcall(function()
                return HttpService:JSONDecode(raw)
            end)
            if okDecode and type(decoded) == "table" then
                self._compatSettings = decoded
            end
        end
    end
    return self
end

function Library:_GetSetting(key, defaultValue)
    local value = self._compatSettings and self._compatSettings[key] or nil
    if value == nil then
        return defaultValue
    end
    return cloneValue(value)
end

function Library:GetSettings(key)
    return self:_GetSetting(key, nil)
end

function Library:SetSaveKey(key, value)
    if type(key) ~= "string" or key == "" then
        return
    end
    self._compatSettings[key] = cloneValue(value)
    self:_flushCompatSettings()

    local widget = self._widgetRegistry and self._widgetRegistry[key]
    if not widget then
        return
    end

    if type(value) == "table" then
        local sel = value.selections
        if sel == nil then sel = value.selection end
        if sel == nil then sel = value.item end
        if sel ~= nil and widget.SetSelection then
            pcall(widget.SetSelection, sel)
        end
        if value.value ~= nil then
            if widget.SetSliderValue then
                pcall(widget.SetSliderValue, value.value)
            elseif widget.SetValue then
                pcall(widget.SetValue, value.value)
            end
        end
        local tog = value.toggled
        if tog == nil then tog = value.enabled end
        if tog ~= nil then
            if widget.SetToggleState then
                pcall(widget.SetToggleState, tog)
            elseif widget.SetState then
                pcall(widget.SetState, tog)
            end
        end
    else
        if widget.SetState then
            pcall(widget.SetState, value)
        elseif widget.SetValue then
            pcall(widget.SetValue, value)
        elseif widget.SetSelection then
            pcall(widget.SetSelection, value)
        end
    end
end

Library:InitAutoSave(SETTINGS_FILE)

local NECTAR_TYPES = { "Comforting", "Motivating", "Satisfying", "Refreshing", "Invigorating" }
local currentNectarStates = {}
for _, name in ipairs(NECTAR_TYPES) do
    currentNectarStates[name] = 0
end
local nectarLastUpdate = 0
local NECTAR_UPDATE_INTERVAL = 5
local okClientStatCache, ClientStatCache = pcall(function()
    local module = ReplicatedStorage:FindFirstChild("ClientStatCache") or ReplicatedStorage:WaitForChild("ClientStatCache", 1)
    if not module then
        error("ClientStatCache missing")
    end
    return require(module)
end)

-- Inline Player ESP implementation (merged)
local localPlayer = LocalPlayer
local mouse = localPlayer:GetMouse()

local DrawingAvailable = (typeof(Drawing) == "table" or typeof(Drawing) == "userdata") and typeof(Drawing.new) == "function"
local canCancelTask = type(task) == "table" and type(task.cancel) == "function"

local theme = {
    panel = Color3.fromRGB(16, 18, 24),
    text = Color3.fromRGB(230, 235, 240),
    accent = Color3.fromRGB(64, 156, 255),
}

local espState = {
    boxes = false,
    health = false,
    tracer = false,
    teamCheck = false,
    teamColor = true,
    skeleton = false,
    names = false,
    hotbar = false,
}

local hotbarDisplay = {}
local trackedPlayers = {}

local autoDigEnabled = false
local autoDigThread = nil
local autoDigManualEnabled = false

local autoSprinklerEnabled = false
local autoActiveLoops = {}
local autoBuffLoop = { running = false, thread = nil }

function safeFire(remote, ...)
    if not remote then return end
    local args = { ... }
    pcall(function()
        remote:FireServer(table.unpack(args))
    end)
end

function playerActivesRemote()
    local events = ReplicatedStorage:FindFirstChild("Events") or ReplicatedStorage:WaitForChild("Events", 1)
    return events and events:FindFirstChild("PlayerActivesCommand")
end

function fireActive(name)
    local remote = playerActivesRemote()
    if not remote then return end
    safeFire(remote, { Name = tostring(name) })
end

function startLoop(loop)
    if loop.thread then return end
    loop.running = true
    loop.thread = task.spawn(function()
        while loop.running do
            loop.callback()
            task.wait(loop.interval)
        end
        loop.thread = nil
    end)
end

function stopLoop(loop)
    loop.running = false
    if loop.thread then
        if canCancelTask then
            pcall(function()
                task.cancel(loop.thread)
            end)
        end
        loop.thread = nil
    end
end

function startAutoDig()
    if autoDigThread then return end
    autoDigEnabled = true
    autoDigThread = task.spawn(function()
        local events = ReplicatedStorage:FindFirstChild("Events")
        while autoDigEnabled do
            local toolCollect = events and events:FindFirstChild("ToolCollect")
            if toolCollect then
                pcall(function()
                    toolCollect:FireServer()
                end)
            end
            task.wait(0.1)
        end
        autoDigThread = nil
    end)
end

function stopAutoDig()
    autoDigEnabled = false
    if autoDigThread then
        if canCancelTask then
            pcall(function()
                task.cancel(autoDigThread)
            end)
        end
        autoDigThread = nil
    end
end

function refreshAutoDig(isAutoFarmEnabled)
    local shouldRun = isAutoFarmEnabled or autoDigManualEnabled
    if shouldRun and not autoDigEnabled then
        startAutoDig()
    elseif not shouldRun and autoDigEnabled then
        stopAutoDig()
    end
end

function releaseBuffs()
    local names = { "Blue Extract", "Red Extract", "Oil", "Enzymes", "Glue", "Glitter", "Tropical Drink" }
    for _, name in ipairs(names) do
        fireActive(name)
        task.wait(0.1)
    end
end

function createDrawing(className, props)
    if not DrawingAvailable then return nil end
    local obj = Drawing.new(className)
    obj.Visible = false
    obj.Transparency = 1
    for k, v in pairs(props or {}) do
        obj[k] = v
    end
    return obj
end

function destroyDrawing(obj)
    if obj and obj.Remove then
        pcall(function() obj:Remove() end)
    end
end

function destroyBillboard(gui)
    if gui then
        pcall(function() gui:Destroy() end)
    end
end

function ensureHotbarBillboard(entry, adornee, size)
    if not adornee then
        destroyBillboard(entry.hotbarBillboard)
        entry.hotbarBillboard = nil
        entry.hotbarViewport = nil
        entry.hotbarCam = nil
        return
    end

    local gui = entry.hotbarBillboard
    if gui and gui.Parent == nil then
        gui = nil
    end
    if not gui then
        gui = Instance.new("BillboardGui")
        gui.Name = "EpsHotbar_" .. entry.player.Name
        gui.AlwaysOnTop = true
        gui.Size = UDim2.fromOffset(60, 60)
        gui.MaxDistance = 500
        gui.StudsOffset = Vector3.new(0, -3.5, 0)
        gui.Adornee = adornee
        gui.Parent = gethui()
        entry.hotbarBillboard = gui
    else
        gui.Adornee = adornee
    end

    gui.Size = UDim2.fromOffset(size, size)

    local frame = gui:FindFirstChild("Frame")
    if not frame then
        frame = Instance.new("Frame")
        frame.Name = "Frame"
        frame.Size = UDim2.fromScale(1, 1)
        frame.BackgroundColor3 = theme.panel
        frame.BackgroundTransparency = 0.35
        frame.BorderSizePixel = 0
        frame.Parent = gui
        Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)
    end

    local viewport = frame:FindFirstChild("Viewport")
    if not viewport then
        viewport = Instance.new("ViewportFrame")
        viewport.Name = "Viewport"
        viewport.BackgroundTransparency = 1
        viewport.Size = UDim2.fromScale(0.9, 0.9)
        viewport.Position = UDim2.fromScale(0.05, 0.05)
        viewport.Parent = frame
        local cam = Instance.new("Camera")
        cam.Name = "HotbarCam"
        cam.Parent = viewport
        viewport.CurrentCamera = cam
        entry.hotbarCam = cam
    elseif not entry.hotbarCam then
        local cam = Instance.new("Camera")
        cam.Name = "HotbarCam"
        cam.Parent = viewport
        viewport.CurrentCamera = cam
        entry.hotbarCam = cam
    end

    entry.hotbarViewport = viewport
end

function setHotbarPreview(entry, tool)
    if not entry.hotbarViewport or not entry.hotbarCam then return end
    for _, child in ipairs(entry.hotbarViewport:GetChildren()) do
        if child:IsA("Model") or child:IsA("BasePart") then
            child:Destroy()
        end
    end

    if not tool then return end

    local model = Instance.new("Model")
    model.Name = "Preview"
    model.Parent = entry.hotbarViewport

    local function copy(instance)
        for _, descendant in ipairs(instance:GetDescendants()) do
            if descendant:IsA("BasePart") then
                local clone = descendant:Clone()
                clone.Anchored = true
                clone.CanCollide = false
                clone.Parent = model
            end
        end
    end

    pcall(copy, tool)
    local handle = tool:FindFirstChild("Handle")
    if handle and #model:GetChildren() == 0 then
        local clone = handle:Clone()
        clone.Anchored = true
        clone.CanCollide = false
        clone.Parent = model
    end

    local cf, size = model:GetBoundingBox()
    local maxDim = math.max(size.X, size.Y, size.Z)
    local distance = (maxDim == 0 and 2) or (maxDim * 2.2)
    local cameraPos = (cf * CFrame.new(0, 0, distance)).Position
    entry.hotbarCam.CFrame = CFrame.new(cameraPos, cf.Position)
end

function createEntry(plr)
    if true then
        return
    end
    if plr == localPlayer then return end
    if trackedPlayers[plr] then return end

    local entry = {
        player = plr,
        draw = {
            box = createDrawing("Quad", { Color = Color3.fromRGB(255, 255, 255), Thickness = 1 }),
            boxOutline = createDrawing("Quad", { Color = Color3.fromRGB(0, 0, 0), Thickness = 2 }),
            tracer = createDrawing("Line", { Color = Color3.fromRGB(255, 255, 255), Thickness = 1 }),
            tracerOutline = createDrawing("Line", { Color = Color3.fromRGB(0, 0, 0), Thickness = 2 }),
            health = createDrawing("Line", { Thickness = 3 }),
            healthOutline = createDrawing("Line", { Color = Color3.fromRGB(0, 0, 0), Thickness = 5 }),
            name = createDrawing("Text", { Size = 14, Center = true, Outline = true, Color = theme.text }),
            hotbarText = createDrawing("Text", { Size = 12, Center = true, Outline = true, Color = theme.text }),
            team = createDrawing("Text", { Size = 12, Outline = true, Color = theme.accent }),
        },
        skeletonLines = {},
        skeletonConn = nil,
        lastTool = nil,
    }

    trackedPlayers[plr] = entry

    local function newLine()
        return createDrawing("Line", { Color = Color3.fromRGB(255, 255, 255), Thickness = 1 })
    end

    entry.skeletonLines = {
        HeadTorso = newLine(),
        TorsoLeftArm = newLine(),
        LeftArmLeftHand = newLine(),
        TorsoRightArm = newLine(),
        RightArmRightHand = newLine(),
        TorsoLeftLeg = newLine(),
        LeftLegLeftFoot = newLine(),
        TorsoRightLeg = newLine(),
        RightLegRightFoot = newLine(),
    }
end

function cleanupEntry(plr)
    local entry = trackedPlayers[plr]
    if not entry then return end
    if entry.skeletonConn then
        pcall(function() entry.skeletonConn:Disconnect() end)
    end
    for _, obj in pairs(entry.draw) do
        destroyDrawing(obj)
    end
    for _, obj in pairs(entry.skeletonLines) do
        destroyDrawing(obj)
    end
    destroyBillboard(entry.hotbarBillboard)
    trackedPlayers[plr] = nil
end

function drawSkeleton(entry, char)
    if not espState.skeleton then
        for _, line in pairs(entry.skeletonLines) do
            if line then line.Visible = false end
        end
        return
    end

    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then
        for _, line in pairs(entry.skeletonLines) do
            if line then line.Visible = false end
        end
        return
    end

    local points = {}
    local function project(partName)
        local part = char:FindFirstChild(partName)
        if not part then return end
        local pos, onScreen = camera:WorldToViewportPoint(part.Position)
        if onScreen then
            points[partName] = Vector2.new(pos.X, pos.Y)
        end
    end

    local names = { "Head", "UpperTorso", "LowerTorso", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }
    for _, name in ipairs(names) do
        project(name)
    end

    local function line(a, b, key)
        local lineObj = entry.skeletonLines[key]
        if not lineObj then return end
        if points[a] and points[b] then
            lineObj.From = points[a]
            lineObj.To = points[b]
            lineObj.Visible = true
        else
            lineObj.Visible = false
        end
    end

    if hum.RigType == Enum.HumanoidRigType.R6 then
        line("Head", "Torso", "HeadTorso")
        line("Torso", "Left Arm", "TorsoLeftArm")
        line("Left Arm", "Left Arm", "LeftArmLeftHand")
        line("Torso", "Right Arm", "TorsoRightArm")
        line("Right Arm", "Right Arm", "RightArmRightHand")
        line("Torso", "Left Leg", "TorsoLeftLeg")
        line("Left Leg", "Left Leg", "LeftLegLeftFoot")
        line("Torso", "Right Leg", "TorsoRightLeg")
        line("Right Leg", "Right Leg", "RightLegRightFoot")
    else
        line("Head", "UpperTorso", "HeadTorso")
        line("UpperTorso", "LeftUpperArm", "TorsoLeftArm")
        line("LeftUpperArm", "LeftLowerArm", "LeftArmLeftHand")
        line("UpperTorso", "RightUpperArm", "TorsoRightArm")
        line("RightUpperArm", "RightLowerArm", "RightArmRightHand")
        line("LowerTorso", "LeftUpperLeg", "TorsoLeftLeg")
        line("LeftUpperLeg", "LeftLowerLeg", "LeftLegLeftFoot")
        line("LowerTorso", "RightUpperLeg", "TorsoRightLeg")
        line("RightUpperLeg", "RightLowerLeg", "RightLegRightFoot")
    end
end

function updateEntry(entry)
    local plr = entry.player
    local char = plr.Character
    if not char then
        for _, obj in pairs(entry.draw) do if obj then obj.Visible = false end end
        drawSkeleton(entry, nil)
        destroyBillboard(entry.hotbarBillboard)
        return
    end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hum or hum.Health <= 0 or not hrp then
        for _, obj in pairs(entry.draw) do if obj then obj.Visible = false end end
        drawSkeleton(entry, nil)
        destroyBillboard(entry.hotbarBillboard)
        return
    end

    local head = char:FindFirstChild("Head")
    local rootPos = hrp.Position
    local topPos = rootPos + Vector3.new(0, 3, 0)
    local bottomPos = rootPos - Vector3.new(0, 3, 0)

    local root2d, onScreen = camera:WorldToViewportPoint(rootPos)
    if not onScreen then
        for _, obj in pairs(entry.draw) do if obj then obj.Visible = false end end
        drawSkeleton(entry, nil)
        destroyBillboard(entry.hotbarBillboard)
        return
    end

    local top2d = camera:WorldToViewportPoint(topPos)
    local bottom2d = camera:WorldToViewportPoint(bottomPos)
    local height = bottom2d.Y - top2d.Y
    local halfHeight = math.max(height / 2, 4)
    local halfWidth = math.max(halfHeight / 2, 3)
    local centerX, centerY = root2d.X, root2d.Y
    local yTop, yBottom = centerY - halfHeight, centerY + halfHeight

    -- Box
    if espState.boxes and entry.draw.box and entry.draw.boxOutline then
        local function setQuad(q)
            q.PointA = Vector2.new(centerX + halfWidth, yTop)
            q.PointB = Vector2.new(centerX - halfWidth, yTop)
            q.PointC = Vector2.new(centerX - halfWidth, yBottom)
            q.PointD = Vector2.new(centerX + halfWidth, yBottom)
            q.Visible = true
        end
        setQuad(entry.draw.boxOutline)
        setQuad(entry.draw.box)
    else
        if entry.draw.box then entry.draw.box.Visible = false end
        if entry.draw.boxOutline then entry.draw.boxOutline.Visible = false end
    end

    -- Tracer
    if espState.tracer and entry.draw.tracer and entry.draw.tracerOutline then
        local origin = Vector2.new(camera.ViewportSize.X * 0.5, camera.ViewportSize.Y)
        entry.draw.tracer.From = origin
        entry.draw.tracer.To = Vector2.new(centerX, yBottom)
        entry.draw.tracer.Visible = true
        entry.draw.tracerOutline.From = origin
        entry.draw.tracerOutline.To = Vector2.new(centerX, yBottom)
        entry.draw.tracerOutline.Visible = true
    else
        if entry.draw.tracer then entry.draw.tracer.Visible = false end
        if entry.draw.tracerOutline then entry.draw.tracerOutline.Visible = false end
    end

    -- Health
    if espState.health and entry.draw.health and entry.draw.healthOutline then
        local ratio = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
        local hbX = centerX - halfWidth - 5
        entry.draw.healthOutline.From = Vector2.new(hbX, yBottom)
        entry.draw.healthOutline.To = Vector2.new(hbX, yTop)
        entry.draw.healthOutline.Visible = true
        entry.draw.health.From = Vector2.new(hbX, yBottom)
        entry.draw.health.To = Vector2.new(hbX, yBottom - ((yBottom - yTop) * ratio))
        entry.draw.health.Color = Color3.fromRGB(255, 0, 0):Lerp(Color3.fromRGB(0, 255, 0), ratio)
        entry.draw.health.Visible = true
    else
        if entry.draw.health then entry.draw.health.Visible = false end
        if entry.draw.healthOutline then entry.draw.healthOutline.Visible = false end
    end

    -- Name
    if espState.names and entry.draw.name then
        entry.draw.name.Text = plr.DisplayName or plr.Name
        entry.draw.name.Position = Vector2.new(centerX, yTop - 12)
        entry.draw.name.Visible = true
    elseif entry.draw.name then
        entry.draw.name.Visible = false
    end

    -- Team label
    if espState.teamCheck and entry.draw.team then
        local label = plr.Team and (plr.Team.Name ~= "" and plr.Team.Name) or nil
        if label then
            entry.draw.team.Text = label
            entry.draw.team.Color = (espState.teamColor and plr.Team.TeamColor.Color) or theme.accent
            entry.draw.team.Position = Vector2.new(centerX + halfWidth + 5, yTop)
            entry.draw.team.Visible = true
        else
            entry.draw.team.Visible = false
        end
    elseif entry.draw.team then
        entry.draw.team.Visible = false
    end

    -- Hotbar text
    local tool = nil
    pcall(function()
        tool = char:FindFirstChildOfClass("Tool")
    end)
    if espState.hotbar and hotbarDisplay.Text and entry.draw.hotbarText then
        local text = tool and tool.Name or ""
        if text ~= "" then
            entry.draw.hotbarText.Text = text
            entry.draw.hotbarText.Position = Vector2.new(centerX, yBottom + 12)
            entry.draw.hotbarText.Visible = true
        else
            entry.draw.hotbarText.Visible = false
        end
    elseif entry.draw.hotbarText then
        entry.draw.hotbarText.Visible = false
    end

    if espState.hotbar and hotbarDisplay.Image and tool then
        ensureHotbarBillboard(entry, hrp, math.floor(math.clamp(halfWidth * 1.4, 32, 96)))
        if entry.hotbarBillboard and tool.Name ~= entry.lastTool then
            entry.lastTool = tool.Name
            setHotbarPreview(entry, tool)
        end
    else
        destroyBillboard(entry.hotbarBillboard)
        entry.hotbarBillboard = nil
        entry.hotbarViewport = nil
        entry.hotbarCam = nil
        entry.lastTool = nil
    end

    drawSkeleton(entry, char)
end

RunService.RenderStepped:Connect(function()
    for plr, entry in pairs(trackedPlayers) do
        if not Players:FindFirstChild(plr.Name) then
            cleanupEntry(plr)
        else
            updateEntry(entry)
        end
    end
end)

Players.PlayerAdded:Connect(createEntry)
Players.PlayerRemoving:Connect(cleanupEntry)
for _, plr in ipairs(Players:GetPlayers()) do
    createEntry(plr)
end

local SharedPlayerESP = nil
pcall(function()
    SharedPlayerESP = loadstring(game:HttpGet("https://raw.githubusercontent.com/megafartCc/SAB/main/espmodule.lua"))()
end)

function safePlayerESP(methodName, ...)
    if not SharedPlayerESP then
        return
    end
    local fn = SharedPlayerESP[methodName]
    if type(fn) ~= "function" then
        return
    end
    pcall(fn, SharedPlayerESP, ...)
end

local PlayerESP = {}
PlayerESP.refreshAutoDig = refreshAutoDig

function PlayerESP:Init()
    safePlayerESP("Init")
end

function PlayerESP:InitAutomation()
end

function PlayerESP:SetBoxEsp(v)
    safePlayerESP("SetBoxEsp", v and true or false)
end

function PlayerESP:SetHealthEsp(v)
    safePlayerESP("SetHealthEsp", v and true or false)
end

function PlayerESP:SetTracers(v)
    safePlayerESP("SetTracers", v and true or false)
end

function PlayerESP:SetTeamCheck(v)
    safePlayerESP("SetTeamEsp", v and true or false)
end

function PlayerESP:SetTeamColor(_)
end

function PlayerESP:SetSkeletonEsp(v)
    safePlayerESP("SetSkeletonEsp", v and true or false)
end

function PlayerESP:SetNameEsp(v)
    safePlayerESP("SetNameEsp", v and true or false)
end

function PlayerESP:SetHotbarEsp(v)
    safePlayerESP("SetHeldItemEsp", v and true or false)
end

function PlayerESP:SetHotbarDisplay(_)
end

function PlayerESP:SetAutoDigManual(state, isAutoFarmEnabled)
    autoDigManualEnabled = state and true or false
    refreshAutoDig(isAutoFarmEnabled)
end

function PlayerESP:SetAutoSprinkler(state)
    autoSprinklerEnabled = state and true or false
end

function PlayerESP:SetAutoActive(enabled, interval, activeName)
    if not activeName then return end
    autoActiveLoops[activeName] = autoActiveLoops[activeName] or { running = false, thread = nil, interval = interval or 60, callback = function() fireActive(activeName) end }
    local loop = autoActiveLoops[activeName]
    loop.interval = interval or loop.interval
    if enabled then
        startLoop(loop)
    else
        stopLoop(loop)
    end
end

function PlayerESP:SetAutoItemBuffs(enabled)
    autoBuffLoop.interval = 600
    autoBuffLoop.callback = releaseBuffs
    if enabled then
        startLoop(autoBuffLoop)
    else
        stopLoop(autoBuffLoop)
    end
end

function PlayerESP:FireActive(name)
    fireActive(name)
end


PlayerESP:Init()
PlayerESP:InitAutomation()

local BETTER_GRAPHICS_MODULE_URL = 'https://pastebin.com/raw/bVj0L3bk' -- !!! REPLACE THIS !!!
local BetterGraphicsModule = loadstring(game:HttpGet(BETTER_GRAPHICS_MODULE_URL))()
visualState = {
    fullbrightEnabled = false,
    fullbrightLightingSnapshot = nil,
    customTimeEnabled = false,
    customTimeValue = 12,
    customTimeSnapshot = nil,
    customTimeLoopToken = 0,
}

function getHivePhase()
    local hcRef = LocalPlayer:FindFirstChild("Honeycomb")
    local hive = hcRef and hcRef.Value
    local phaseValue = hive and hive:FindFirstChild("Phase")
    return phaseValue and phaseValue.Value or nil
end

function getHiveCircleCFrame()
    local hives = Workspace:FindFirstChild("HivePlatforms")
    if not hives then
        return nil
    end

    for _, platform in ipairs(hives:GetChildren()) do
        local pr = platform:FindFirstChild("PlayerRef")
        if pr and pr.Value == LocalPlayer then
            -- Prefer the visual circle if present
            local circle = platform:FindFirstChild("Circle") or platform:FindFirstChild("Circle2")
            if circle and circle:IsA("BasePart") then
                return circle.CFrame
            end
            -- Fallback to the hive platform like the standalone balloon watcher
            local plat = platform:FindFirstChild("Platform")
            if plat and plat:IsA("BasePart") then
                return plat.CFrame
            end
            if platform:IsA("BasePart") then
                return platform.CFrame
            end
        end
    end

    return nil
end

function getNearestHiveBalloonBody(hiveCF)
    if not hiveCF then
        return nil
    end

    local balloonsFolder = Workspace:FindFirstChild("Balloons")
    if not balloonsFolder then
        return nil
    end

    local hiveBalloons = balloonsFolder:FindFirstChild("HiveBalloons")
    if not hiveBalloons then
        return nil
    end

    -- Use a generous radius; HiveBalloons only contains hive balloons
    local NEAR = 25
    local origin = hiveCF.Position
    local nearest = nil
    local nearestDist = math.huge

    for _, inst in ipairs(hiveBalloons:GetDescendants()) do
        if inst:IsA("BasePart") and inst.Name == "BalloonBody" then
            local dist = (inst.Position - origin).Magnitude
            if dist <= NEAR and dist < nearestDist then
                nearest = inst
                nearestDist = dist
            end
        end
    end

    return nearest
end

function getBalloonBlessingValue(hiveCF)
    hiveCF = hiveCF or getHiveCircleCFrame()
    if not hiveCF then
        return nil
    end

    local body = getNearestHiveBalloonBody(hiveCF)
    if not body then
        return nil
    end

    -- Support both BalloonBody.Gui and BalloonBody.GuiAttach.Gui layouts
    local guiAttach = body:FindFirstChild("GuiAttach")
    local gui = nil
    if guiAttach then
        gui = guiAttach:FindFirstChild("Gui")
    end
    if not gui then
        gui = body:FindFirstChild("Gui")
    end
    if not gui then
        return nil
    end

    local blessingBar = gui:FindFirstChild("BlessingBar")
    local blessingLabel = blessingBar and blessingBar:FindFirstChild("TextLabel")
    local text = blessingLabel and blessingLabel.Text
    if not text then
        return nil
    end

    -- Debug: show raw label text to help diagnose parsing
    local num = text:match("(%d+%.?%d*)")
    local value = num and tonumber(num) or nil
    print(string.format("[BalloonHold] blessing label=\"%s\" parsed=%s", text, tostring(value)))
    return value
end

function hasBalloonAtHive(hiveCF)
    hiveCF = hiveCF or getHiveCircleCFrame()
    if not hiveCF then
        return false
    end
    return getNearestHiveBalloonBody(hiveCF) ~= nil
end

local lastMoveCommandPos = nil
local lastMoveCommandTime = 0
local hasTaskCancel = (type(task) == "table" or type(task) == "userdata") and type(task.cancel) == "function"

local TWEEN_DURATION_SCALE = 1.75 -- global slow-down for all tweens

function notify(title, text, duration)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = title or "Notice",
            Text = text or "",
            Duration = duration or 3,
        })
    end)
end

function resetTable(tbl)
    if type(tbl) ~= "table" then
        return
    end
    if table.clear then
        table.clear(tbl)
        return
    end
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

function resetMoveCommand()
    lastMoveCommandPos = nil
    lastMoveCommandTime = 0
end

function makeTweenInfo(duration, style, direction)
    local scaled = math.max(0, duration * TWEEN_DURATION_SCALE)
    return TweenInfo.new(scaled, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
end

function httpRequest(opts)
    -- force syn.request when available (executor native)
    if syn and syn.request then
        return syn.request(opts)
    end
    local fn = (http and http.request) or http_request or request
    if fn then
        return fn(opts)
    end
    if HttpService and HttpService.RequestAsync then
        local hsOpts = {
            Url = opts.Url,
            Method = opts.Method or "GET",
            Headers = opts.Headers or {},
            Body = opts.Body
        }
        local ok, res = pcall(function()
            return HttpService:RequestAsync(hsOpts)
        end)
        if ok then
            return res
        else
            return nil, res
        end
    end
    return nil, "no http request function available"
end

function generateUserKey()
    local raw = HttpService:GenerateGUID(false) .. "_" .. tostring(math.random(100000, 999999))
    return raw:gsub("%W", "")
end

function readUserKey()
    if typeof(isfile) == "function" and isfile(BACKEND_USER_KEY_FILE) then
        local ok, data = pcall(readfile, BACKEND_USER_KEY_FILE)
        if ok and type(data) == "string" and #data > 0 then
            return data
        end
    end
    return nil
end

function writeUserKey(key)
    if typeof(writefile) == "function" and key then
        pcall(writefile, BACKEND_USER_KEY_FILE, key)
    end
end

function setClipboard(text)
    if typeof(setclipboard) == "function" and text then
        pcall(setclipboard, text)
    end
end

function getHumanoid()
    local character = LocalPlayer.Character
    return character and character:FindFirstChildOfClass("Humanoid")
end

function getHRP()
    local character = LocalPlayer.Character
    return character and character:FindFirstChild("HumanoidRootPart")
end

function disableCharacterCollision()
    local character = LocalPlayer.Character
    if not character then return nil end
    local modified = {}
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") and part.CanCollide then
            part.CanCollide = false
            table.insert(modified, part)
        end
    end
    return modified
end

function restoreCharacterCollision(parts)
    if not parts or isNoclipEnabled then return end
    for _, part in ipairs(parts) do
        if part and part:IsA("BasePart") then
            part.CanCollide = true
        end
    end
end

function tweenToCFrame(cf, opts)
    opts = opts or {}
    local character = LocalPlayer.Character
    local hrp = getHRP()
    if not character or not hrp or typeof(cf) ~= "CFrame" then return end
    if not character.PrimaryPart then
        character.PrimaryPart = hrp
    end

    local distance = (hrp.Position - cf.Position).Magnitude
    -- Slightly slower tween; lower speed and allow a bit longer max duration
    local baseDuration = math.clamp(distance / (opts.speed or 90), 0.2, 2.0)
    local tweenInfo = makeTweenInfo(baseDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

    local collisionOverride = (not isNoclipEnabled) and disableCharacterCollision() or nil

    local ok, tween = pcall(function()
        return TweenService:Create(hrp, tweenInfo, { CFrame = cf })
    end)
    if not ok or not tween then
        pcall(function()
            hrp.CFrame = cf
        end)
        restoreCharacterCollision(collisionOverride)
        return
    end

    local function cleanupCollision()
        restoreCharacterCollision(collisionOverride)
    end

    tween:Play()
    if not opts.noYield then
        local _ = pcall(function()
            tween.Completed:Wait()
        end)
        cleanupCollision()
    else
        tween.Completed:Connect(cleanupCollision)
    end
end

function hardTeleportTo(cf)
    tweenToCFrame(cf)
end

function requestMoveTo(pos, bool)
    local character = LocalPlayer.Character
    local hrp = getHRP()
    if not character or not hrp or typeof(pos) ~= "Vector3" then return end
    character.Humanoid:MoveTo(pos)
end

function formatShort(num)
    num = tonumber(num) or 0
    local abs = math.abs(num)
    local suffix = ""
    local div = 1

    if abs >= 1e12 then
        suffix, div = "T", 1e12
    elseif abs >= 1e9 then
        suffix, div = "B", 1e9
    elseif abs >= 1e6 then
        suffix, div = "M", 1e6
    elseif abs >= 1e3 then
        suffix, div = "K", 1e3
    end
    local value = num / div
    local fmt
    if abs < 1e3 then
        fmt = string.format("%.0f", value)
    elseif abs >= 100 * div then
        fmt = string.format("%.0f", value)
    elseif abs >= 10 * div then
        fmt = string.format("%.1f", value)
    else
        fmt = string.format("%.2f", value)
    end
    return fmt .. suffix
end

function loadLifetimeStats() end
function saveLifetimeStats() end
loadLifetimeStats()

defaultWalkSpeed = 16
defaultJumpPower = 50
isSpeedEnabled = false
isJumpEnabled = false
isNoclipEnabled = false
isAutoFarmEnabled = false
isAutoDispenseEnabled = false
balloonBlessingHoldEnabled = false
balloonBlessingThreshold = 10
do
    local saved = Library and Library.autoSaveData and Library.autoSaveData["farm_balloon_blessing_hold"]
    if typeof(saved) == "table" then
        if typeof(saved.value) == "number" then
            balloonBlessingThreshold = math.max(0, saved.value)
        end
        if saved.toggled ~= nil then
            balloonBlessingHoldEnabled = saved.toggled and true or false
        end
    end
end
antiAfkEnabled = false
antiAfkConnection = nil
isAutoClaimHiveEnabled = false
currentSpeed = 100
currentJump = 150
selectedField = nil
isDispensing = false
selectedFieldName = nil
visitedTokens = {}
activeToken = nil
activeTokenIsLink = false
dupedTokenTarget = nil
dupedTokenTargetName = nil
dupedTokenTargetId = nil
dupedSeenTokens = {}
dupedTokenHoldUntil = 0
holdDupedTokensEnabled = false
dupedTokenSelectionList = {}
dupedTokenSelectionMap = {}
coconutTarget = nil
coconutHoldUntil = 0
coconutApproachTime = 0
starTarget = nil
starHoldUntil = 0
bubbleTarget = nil
fuzzyTarget = nil
preciseTarget = nil
precisePassCount = 0
preciseHoldUntil = 0
preciseVisitedMarks = {}
tokenMetadata = {}
candidateBuffer = {}
TOKEN_PASS_RADIUS = 4

-- Distance helper that ignores height (hovering duped tokens sit above the ground).
function planarDistance(a, b)
    local a2 = Vector2.new(a.X, a.Z)
    local b2 = Vector2.new(b.X, b.Z)
    return (a2 - b2).Magnitude
end

function dupedDebug(msg)
    print("[DupedToken][Debug] " .. tostring(msg))
end

-- FIX: Increased token ignore delay to break local loops
TOKEN_RECENT_DELAY = 1.0 
PRECISE_REVISIT_DELAY = 1.0
MAX_TOKEN_TRACK_DISTANCE = 220
activeTokenScore = 0
SCORE_RELOCK_THRESHOLD = 8
wanderTarget = nil
wanderExpireTime = 0
wanderDirection = Vector3.new(1, 0, 0)
lastWanderRotate = 0
WANDER_ROTATE_INTERVAL = 1.35
MIN_WANDER_DISTANCE = 18
wanderLastBase = nil
MOVE_COMMAND_EPS = 0.85
MOVE_COMMAND_RETRY = 0.35
statsGui = nil
statsLabel = nil
farmSessionStart = 0
farmStartPollen = 0
farmStartHoney = 0
statsLastUpdate = 0
isStatsPanelEnabled = false
isBuffAwareEnabled = false
ignoreTokensEnabled = false
ignoredTokenMap = {}
ignoreSelectionList = {}
stickersOnCooldown = false
STICKER_COOLDOWN_SECONDS = 86400
backendUserKey = nil
backendLastHoney = nil
backendLastPollen = nil
backendAccumHoney = 0
backendAccumPollen = 0
backendTokens = nil -- disabled
backendBuffs = nil  -- disabled
backendLastSend = 0
BACKEND_SEND_INTERVAL = 5
IGNORE_TOKEN_SAVE_KEY = "farm_ignore_tokens"
HOLD_DUPED_TOKEN_SAVE_KEY = "farm_duped_token_hold"
lastStuckCheckTime = 0
lastStuckCheckPosition = nil
stuckCounter = 0
MAX_PATH_SEGMENTS = 10
pathParts = {}
for i = 1, MAX_PATH_SEGMENTS do
    local part = Instance.new("Part")
    part.Name = "EpsPathLine_" .. i
    part.Anchored = true
    part.CanCollide = false
    part.Color = Color3.fromRGB(0, 255, 0)
    part.Material = Enum.Material.Neon
    part.Transparency = 1
    part.Size = Vector3.new(0.15, 0.15, 0.15)
    part.Locked = true
    part.Parent = Workspace
    pathParts[i] = part
end
fieldBoundsParts = {}
fieldBoundsEnabled = false
FIELD_WALL_HEIGHT = 35
FIELD_WALL_THICKNESS = 1.5
FIELD_WALL_MARGIN = 1
-- Performance Throttling Variables
currentBestCandidate = nil
lastTokenSearchTime = 0
TOKEN_SEARCH_INTERVAL = 0.2 -- Run expensive search only 5 times per second
DUPED_TOKEN_CHARGE_TIME = 1
DUPED_TOKEN_HOLD_BUFFER = 0.35
DUPED_TOKEN_RESELECT_DELAY = 1.5
COCONUT_STAND_TIME = 0.65
COCONUT_APPROACH_DELAY = 0.1
STAR_STAND_TIME = 0.6
standThroughPreciseBeeEnabled = false
pickUpBubblesEnabled = false
pickUpFuzzyEnabled = false
standUnderCoconutEnabled = false
standUnderFallingStarEnabled = false
autoMemoryMatchEnabled = false
memoryMatchThread = nil

function ensureFieldBounds()
    if #fieldBoundsParts > 0 then
        return
    end
    for i = 1, 4 do
        local wall = Instance.new("Part")
        wall.Name = "EpsFieldWall_" .. i
        wall.Anchored = true
        wall.CanCollide = true
        wall.Transparency = 1
        wall.Material = Enum.Material.ForceField
        wall.Locked = true
        wall.Parent = nil
        fieldBoundsParts[i] = wall
    end
end

function refreshFieldBounds()
    ensureFieldBounds()
    for _, wall in ipairs(fieldBoundsParts) do
        wall.Parent = nil
    end
    if not fieldBoundsEnabled or not selectedField then
        return
    end

    local size = selectedField.Size
    local cf = selectedField.CFrame
    local halfX = size.X / 2
    local halfZ = size.Z / 2
    local wallHeight = FIELD_WALL_HEIGHT
    local thickness = FIELD_WALL_THICKNESS
    local configs = {
        { Vector3.new(0, wallHeight / 2, halfZ - FIELD_WALL_MARGIN), Vector3.new(size.X, wallHeight, thickness) },
        { Vector3.new(0, wallHeight / 2, -halfZ + FIELD_WALL_MARGIN), Vector3.new(size.X, wallHeight, thickness) },
        { Vector3.new(halfX - FIELD_WALL_MARGIN, wallHeight / 2, 0), Vector3.new(thickness, wallHeight, size.Z) },
        { Vector3.new(-halfX + FIELD_WALL_MARGIN, wallHeight / 2, 0), Vector3.new(thickness, wallHeight, size.Z) },
    }
    for index, data in ipairs(configs) do
        local wall = fieldBoundsParts[index]
        wall.Size = data[2]
        wall.CFrame = cf * CFrame.new(data[1])
        wall.Parent = Workspace
    end
end

function cleanupTokenCaches(now)
    for token, expire in pairs(visitedTokens) do
        if not token.Parent or expire <= now then
            visitedTokens[token] = nil
        end
    end

    for token in pairs(tokenMetadata) do
        if not token.Parent then
            tokenMetadata[token] = nil
            if activeToken == token then
                activeToken = nil
                activeTokenScore = 0
            end
        end
    end

    for token, expire in pairs(dupedSeenTokens) do
        if not token or not token.Parent or expire <= now then
            dupedSeenTokens[token] = nil
        end
    end

    if dupedTokenTarget and not dupedTokenTarget.Parent then
        dupedTokenTarget = nil
        dupedTokenTargetName = nil
        dupedTokenTargetId = nil
        dupedTokenHoldUntil = 0
        -- give listener/main another shot next tick
    end
    if coconutTarget and not coconutTarget.Parent then
        coconutTarget = nil
        coconutHoldUntil = 0
        coconutApproachTime = 0
    end
    if starTarget and not starTarget.Parent then
        starTarget = nil
        starHoldUntil = 0
    end
    if bubbleTarget and not bubbleTarget.Parent then
        bubbleTarget = nil
    end
end


function isInField(position)
    if not selectedField then return false end
    local fieldPos = selectedField.Position
    local fieldSize = selectedField.Size
    local inX = math.abs(position.X - fieldPos.X) <= (fieldSize.X / 2)
    local inZ = math.abs(position.Z - fieldPos.Z) <= (fieldSize.Z / 2)
    return inX and inZ
end

function getRandomFieldSpot()
    if not selectedField then return nil end
    local size = selectedField.Size
    local pos = selectedField.Position
    local rx = math.random(-size.X / 2 * 0.9, size.X / 2 * 0.9)
    local rz = math.random(-size.Z / 2 * 0.9, size.Z / 2 * 0.9)
    return Vector3.new(pos.X + rx, pos.Y + 3, pos.Z + rz)
end

function chooseWanderSpot(origin, nowTime)
    local target = getRandomFieldSpot()
    if not target then return nil end

    if origin and (target - origin).Magnitude < MIN_WANDER_DISTANCE then
        local offset = Vector3.new(math.random(-25, 25), 0, math.random(-25, 25))
        target = origin + offset
    end
    
    if not isInField(target) then
        target = getRandomFieldSpot()
    end

    return target
end

function getTokenInfo(token)
    if not token then
        return nil
    end
    local info = tokenMetadata[token]
    if not info then
        info = {}
        tokenMetadata[token] = info
    end
    return info
end

function updateTokenTracking(token, position, now, infoready)
    local info
    if infoready then
        info = infoready
    else
        info = getTokenInfo(token)
        if not info then
            return nil
        end
    end
    info.LastPos = position
    info.LastSeen = now
    info.SpawnTime = info.SpawnTime or now
    return info
end

-- -------------------------------------------------------------------------------------
-- START: Modified Token Database and Priority Section
-- -------------------------------------------------------------------------------------

-- FARM_DATABASE: Kept for token name identification 
local FARM_DATABASE = {
["65867881"] = "Haste", ["1671281844"] = "Beamstorm", ["177997841"] = "Bear Morph / Glob",
["8083436978"] = "Inflate Balloons", ["1104415222"] = "Scratch", ["183390139"] = "Cog",
["4889322534"] = "Fuzz Bombs", ["5877939956"] = "Glitch / Map Corruption", ["1839454544"] = "Gummy Storm",
["2319083910"] = "Impale", ["4519549299"] = "Inferno", ["2000457501"] = "Inspire",
["3080529618"] = "Jelly Bean", ["1874564120"] = "Ability Token", ["4528379338"] = "Mark Surge",
["5877998606"] = "Mind Hack", ["4889470194"] = "Pollen Haze", ["1442725244"] = "Blue Bomb", ["1629547638"] = "Token Link",
["1629547638"] = "Token Link", ["3582501342"] = "Rain Call", ["8173555749"] = "Target Practice",
["8083943936"] = "Surprise Party", ["3582519526"] = "Tornado", ["4519523935"] = "Triangulate",
["1472256444"] = "Baby Love", ["2028574353"] = "Treat", ["4528414666"] = "Summon Frog",
["1472491940"] = "Bear Morph", ["1952740625"] = "Strawberry", ["1472135114"] = "Honey",
["2499514197"] = "Honey Mark", ["2499540966"] = "Pollen Mark", ["1952682401"] = "Sunflower Seed",
["1838129169"] = "Gumdrop", ["1753904608"] = "Tabby Love", ["1629649299"] = "Focus",
["1442863423"] = "Blue Boost", ["2028453802"] = "Blueberry", ["2652424740"] = "Festive Blessing",
["1442859163"] = "Red Boost", ["1952796032"] = "Pineapple",
}

local FARM_PRIORITY_ITEMS = { ["Token Link"] = true }
local TOKEN_PRIORITY_WEIGHT = {
    ["Token Link"] = 500, ["Token Link (Duped)"] = 550, ["Inspire"] = 70, ["Haste"] = 8,
    ["Baby Love"] = 55, ["Focus"] = 50, ["Melody"] = 50, ["Surprise Party"] = 50,
    ["Beamstorm"] = 45, ["Glitch"] = 45, ["Glitch / Map Corruption"] = 45, ["Mind Hack"] = 40,
    ["Mark Surge"] = 38, ["Bear Morph / Glob"] = 36, ["Bear Morph"] = 36, ["Pollen Mark"] = 35,
    ["Honey Mark"] = 34, ["Blue Boost"] = 32, ["Red Boost"] = 32, ["Pollen Haze"] = 32,
    ["Target Practice"] = 32, ["Gummy Storm"] = 32, ["Inferno"] = 32, ["Inflate Balloons"] = 30,
    ["Rain Call"] = 30, ["Triangulate"] = 29, ["Fuzz Bombs"] = 29, ["Summon Frog"] = 28,
    ["Festive Blessing"] = 28, ["Impale"] = 28, ["Cog"] = 26, ["Treat"] = 26,
    ["Blueberry"] = 18, ["Strawberry"] = 18, ["Pineapple"] = 17, ["Sunflower Seed"] = 17,
    ["Honey"] = 20, ["Gumdrop"] = 15, ["Jelly Bean"] = 15, ["Tabby Love"] = 45,
    ["Scratch"] = 33, ["Ability Token"] = 14, ["Rain Cloud"] = 30,
}

function getTokenPriorityScore(name)
    -- Default to 1 (lowest priority) if not found, ensuring age/distance/fade decides pickup.
    return TOKEN_PRIORITY_WEIGHT[name] or 1
end

local TOKEN_IGNORE_OPTIONS = {}
do
    local seen = {}
    for _, name in pairs(FARM_DATABASE) do
        if type(name) == "string" and not seen[name] then
            seen[name] = true
            table.insert(TOKEN_IGNORE_OPTIONS, name)
        end
    end
    table.sort(TOKEN_IGNORE_OPTIONS)
end

function setIgnoredTokens(selectionList)
    resetTable(ignoredTokenMap)
    if type(selectionList) ~= "table" then return end

    -- NOTE: The selection list is treated as a blacklist: selected tokens will be ignored.
    for _, name in ipairs(selectionList) do
        if type(name) == "string" then
            ignoredTokenMap[name] = true
        end
    end
end

function isTokenAllowed(name)
    if not ignoreTokensEnabled then
        return true
    end
    if not name then
        return true
    end
    -- If it's in the blacklist, skip it; otherwise allow.
    return not ignoredTokenMap[name]
end

function logIgnoreStatus()
    if not ignoreTokensEnabled then
        print("[IgnoreTokens] Disabled.")
        return
    end
    if #ignoreSelectionList == 0 then
        print("[IgnoreTokens] Enabled; blacklist empty (ignoring none).")
        return
    end
    print("[IgnoreTokens] Enabled; ignoring selected tokens: " .. table.concat(ignoreSelectionList, ", "))
end

function loadIgnoredTokenSettings()
    resetTable(ignoredTokenMap)
    resetTable(ignoreSelectionList)

    -- Primary (combined) save format from MultiSelectDropdownToggle
    local saved = Library:_GetSetting(IGNORE_TOKEN_SAVE_KEY, nil)
    if type(saved) == "table" then
        ignoreTokensEnabled = saved.toggled and true or false
        local sel = saved.selections
        if type(sel) == "table" then
            -- selections may be map or array; accept both
            if #sel > 0 then
                for _, name in ipairs(sel) do
                    if type(name) == "string" then
                        ignoredTokenMap[name] = true
                        table.insert(ignoreSelectionList, name)
                    end
                end
            else
                for name, flag in pairs(sel) do
                    if flag and type(name) == "string" then
                        ignoredTokenMap[name] = true
                        table.insert(ignoreSelectionList, name)
                    end
                end
            end
        end
        logIgnoreStatus()
        return
    end

    -- Fallback to legacy split keys if present
    local savedToggle = Library:_GetSetting("farm_ignore_tokens_toggle", false)
    local savedList = Library:_GetSetting("farm_ignore_tokens_list", nil)
    ignoreTokensEnabled = savedToggle and true or false
    if type(savedList) == "table" then
        for _, name in ipairs(savedList) do
            if type(name) == "string" then
                ignoredTokenMap[name] = true
                table.insert(ignoreSelectionList, name)
            end
        end
end
logIgnoreStatus()
end
loadIgnoredTokenSettings()

function setDupedTokenSelections(selectionList)
    resetTable(dupedTokenSelectionMap)
    resetTable(dupedTokenSelectionList)
    if type(selectionList) ~= "table" then
        return
    end
    if #selectionList > 0 then
        for _, name in ipairs(selectionList) do
            if type(name) == "string" and not dupedTokenSelectionMap[name] then
                dupedTokenSelectionMap[name] = true
                table.insert(dupedTokenSelectionList, name)
            end
        end
    else
        for name, flag in pairs(selectionList) do
            if flag and type(name) == "string" and not dupedTokenSelectionMap[name] then
                dupedTokenSelectionMap[name] = true
                table.insert(dupedTokenSelectionList, name)
            end
        end
    end
end

function logDupedHoldStatus()
    if not holdDupedTokensEnabled then
        print("[DupedTokens] Hold disabled.")
        return
    end
    if #dupedTokenSelectionList == 0 then
        print("[DupedTokens] Holding all duped tokens.")
        return
    end
    print("[DupedTokens] Holding duped tokens for: " .. table.concat(dupedTokenSelectionList, ", "))
end

function loadDupedTokenHoldSettings()
    setDupedTokenSelections({})
    local saved = Library:_GetSetting(HOLD_DUPED_TOKEN_SAVE_KEY, nil)
    if type(saved) == "table" then
        holdDupedTokensEnabled = saved.toggled and true or false
        local sel = saved.selections or saved.Selections
        if type(sel) == "table" then
            setDupedTokenSelections(sel)
        end
        logDupedHoldStatus()
        return
    end
    holdDupedTokensEnabled = false
    logDupedHoldStatus()
end
loadDupedTokenHoldSettings()

function isDupedTokenAllowed(tokenName)
    if not holdDupedTokensEnabled then
        return false
    end
    if next(dupedTokenSelectionMap) == nil then
        return true
    end
    if not tokenName then
        return false
    end
    return dupedTokenSelectionMap[tokenName] and true or false
end

function ensureBackendUserKey()
    if backendUserKey then
        return backendUserKey
    end
    backendUserKey = readUserKey()
    if not backendUserKey then
        local uid = tostring(LocalPlayer.UserId or "")
        if uid ~= "" then
            backendUserKey = "user-" .. uid
        else
            backendUserKey = generateUserKey()
        end
        writeUserKey(backendUserKey)
        notify("Backend", "Generated user key for stats sync.", 4)
    end
    return backendUserKey
end

function registerBackendKey(key)
    if not BACKEND_SYNC_ENABLED then return end
    if type(BACKEND_URL) ~= "string" or BACKEND_URL == "" then return end
    if type(BACKEND_API_KEY) ~= "string" or BACKEND_API_KEY == "replace-with-api-key" then return end
    if not key or key == "" then return end

    local payload = {
        honey = 1, -- tiny seed sample to register user
        pollen = 0,
        at = math.floor(os.time())
    }
    local body = HttpService:JSONEncode(payload)
    local headers = {
        ["Content-Type"] = "application/json",
        ["x-api-key"] = BACKEND_API_KEY,
        ["x-user-key"] = key,
    }
    local url = BACKEND_URL .. "/api/ingest"
    task.spawn(function()
        local ok, err = pcall(httpRequest, {
            Url = url,
            Method = "POST",
            Headers = headers,
            Body = body,
        })
        if not ok then
            warn("[Backend] Registration failed:", err)
        end
    end)
end

function createBackendKeyAndCopy()
    local key = ensureBackendUserKey()
    setClipboard(key)
    notify("Backend", "User key copied to clipboard.", 4)
    registerBackendKey(key)
end

function captureNectarStates()
    if not okClientStatCache or not ClientStatCache then
        return
    end
    local success, stats = pcall(function()
        return ClientStatCache:Get()
    end)
    if not success or not stats or type(stats.Modifiers) ~= "table" then
        return
    end
    local snapshot = {}
    for _, name in ipairs(NECTAR_TYPES) do
        snapshot[name] = 0
    end
    for _, buckets in pairs(stats.Modifiers) do
        if type(buckets) == "table" then
            for _, bucket in pairs(buckets) do
                if bucket and type(bucket.Mods) == "table" then
                    for _, mod in ipairs(bucket.Mods) do
                        if mod and type(mod.Src) == "string" then
                            local base = mod.Src:match("^(%w+)%s+Nectar$")
                            if base and snapshot[base] ~= nil then
                                snapshot[base] = 1
                            end
                        end
                    end
                end
            end
        end
    end
    currentNectarStates = snapshot
end

function sendBackendSample(
    honeyDelta,
    pollenDelta,
    forceSend,
    currentHoneyValue,
    currentBackpackValue,
    nectarSnapshot,
    currentCapacityValue,
    playerName
)
    if not BACKEND_SYNC_ENABLED then return end
    if type(BACKEND_URL) ~= "string" or BACKEND_URL == "" then return end
    if type(BACKEND_API_KEY) ~= "string" or BACKEND_API_KEY == "replace-with-api-key" then return end
    local hasMetrics = (honeyDelta or 0) > 0 or (pollenDelta or 0) > 0
    local hasNectar = nectarSnapshot ~= nil
    if (not forceSend) and not hasMetrics and not hasNectar then
        return
    end

    local sendHoney = honeyDelta or 0
    local sendPollen = pollenDelta or 0

    local key = ensureBackendUserKey()
    local payload = { at = math.floor(os.time()) }
    if honeyDelta ~= nil then payload.honey = honeyDelta end
    if pollenDelta ~= nil then payload.pollen = pollenDelta end

    if currentHoneyValue ~= nil then
        payload.currentHoney = currentHoneyValue
    end
    if currentBackpackValue ~= nil then
        payload.backpack = currentBackpackValue
    end
    if nectarSnapshot and type(nectarSnapshot) == "table" then
        payload.nectar = nectarSnapshot
    end
    if currentCapacityValue ~= nil then
        payload.backpackCapacity = currentCapacityValue
    end
    if playerName and playerName ~= "" then
        payload.username = tostring(playerName)
    end
    local playerId = LocalPlayer and LocalPlayer.UserId
    if playerId then
        payload.playerId = playerId
    end
    local body = HttpService:JSONEncode(payload)
    local url = BACKEND_URL .. "/api/ingest"
    local headers = {
        ["Content-Type"] = "application/json",
        ["x-api-key"] = BACKEND_API_KEY,
        ["x-user-key"] = key,
    }

    task.spawn(function()
        local function attempt()
            local ok, res = pcall(httpRequest, {
                Url = url,
                Method = "POST",
                Headers = headers,
                Body = body,
            })
            return ok, res
        end

        local ok, res = attempt()
        if not ok or (res and res.StatusCode and res.StatusCode >= 400) then
            -- retry once on failure to reduce dropped samples
            task.wait(1)
            ok, res = attempt()
        end

        if not ok or (res and res.StatusCode and res.StatusCode >= 400) then
            warn("[Backend] HTTP " .. tostring(res and res.StatusCode or "error") .. " while sending sample")
            -- Put the deltas back so they are retried on the next cycle
            backendAccumHoney = backendAccumHoney + sendHoney
            backendAccumPollen = backendAccumPollen + sendPollen
            return -- keep buffers so we can try again on next send
        end

        -- success: clear buffers
    end)
end

-- -------------------------------------------------------------------------------------
-- END: Modified Token Database and Priority Section
-- -------------------------------------------------------------------------------------

-- Simple buff-awareness helpers used by the token logic.
-- These do not read actual Buffs; they just use static assumptions.
function checkPlayerBuffs()
    return {
        BabyLove = 1, -- assume at least some Baby Love so it isn't over-prioritized
        Inspire = 0,
        Focus = 0,
    }
end

function getDynamicTokenBonus(tokenName, currentBuffs)
    local bonus = 0
    if not isBuffAwareEnabled then
        return 0
    end
    
    if tokenName == "Baby Love" and (currentBuffs.BabyLove or 0) < 1 then
        bonus = bonus + 400
    end
    if tokenName == "Inspire" and (currentBuffs.Inspire or 0) < 5 then
        bonus = bonus + 200
    end
    if (tokenName == "Focus" or tokenName == "Target Practice") and (currentBuffs.Focus or 0) < 5 then
        bonus = bonus + 150
    end
    
    return bonus
end

function getCleanID(str)
    return tonumber(string.match(tostring(str), "%d+"))
end

function extractDecalId(decal)
    if not decal then
        return nil
    end
    -- Some collectibles store the id in Texture, others in ColorMap.
    return getCleanID(decal.Texture or decal.ColorMap)
end

function getCollectibleTokenName(token)
    if not token or not token:IsA("BasePart") then
        return nil
    end

    -- Prefer explicit Front/Back decals when present.
    local front = token:FindFirstChild("FrontDecal")
    local back = token:FindFirstChild("BackDecal")
    local decal = (front and front:IsA("Decal")) and front
        or (back and back:IsA("Decal")) and back
        or token:FindFirstChildOfClass("Decal")

    local id = extractDecalId(decal)
    if not id then
        return nil
    end
    local name = FARM_DATABASE[tostring(id)]
    if name then
        return name
    end
    return string.format("Decal %s", tostring(id))
end

function describeDupedToken(inst)
    if not inst then
        return nil, nil
    end
    local front = inst:FindFirstChild("FrontDecal")
    local back = inst:FindFirstChild("BackDecal")
    local decal = (front and front:IsA("Decal")) and front
        or (back and back:IsA("Decal")) and back
        or inst:FindFirstChildOfClass("Decal")
    local decalId = extractDecalId(decal)
    local tokenName = decalId and FARM_DATABASE[tostring(decalId)] or getCollectibleTokenName(inst)
    if not tokenName then
        if decalId then
            tokenName = string.format("Decal %s", tostring(decalId))
        else
            tokenName = "Duped Token"
        end
    end
    return tokenName, decalId
end

function getDupedTokensFolder()
    local currentCamera = Workspace.CurrentCamera
    if currentCamera then
        local folder = currentCamera:FindFirstChild("DupedTokens")
        if folder then
            return folder
        end
    end
    local cameraChild = Workspace:FindFirstChild("Camera")
    if cameraChild then
        return cameraChild:FindFirstChild("DupedTokens")
    end
    return nil
end

function findDupedTokenTarget(rootPosition, now)
    if not holdDupedTokensEnabled or not rootPosition then
        return nil
    end
    local folder = getDupedTokensFolder()
    if not folder then
        return nil
    end
    local bestToken, bestName, bestId = nil, nil, nil
    local bestScore = -math.huge
    for _, inst in ipairs(folder:GetChildren()) do
        if inst:IsA("BasePart") and inst.Transparency < 0.995 then
            local expire = dupedSeenTokens[inst]
            if not expire or expire <= now then
                local dist = planarDistance(rootPosition, inst.Position)
                if dist <= MAX_TOKEN_TRACK_DISTANCE then
                    local tokenName, tokenId = describeDupedToken(inst)
                    if isDupedTokenAllowed(tokenName) then
                        local priority = getTokenPriorityScore(tokenName or "Unknown")
                        local score = priority - (dist / 6)
                        if score > bestScore then
                            bestScore = score
                            bestToken = inst
                            bestName = tokenName
                            bestId = tokenId
                        end
                    end
                end
            end
        end
    end
    return bestToken, bestName, bestId
end

-- Color/keyword helpers for warning discs to separate coconuts vs falling stars.
function isGreenish(color)
    return color and color.G >= 0.65 and color.G > color.R * 1.05 and color.G > color.B * 1.05
end

local DEBUG_HAZARD_LOG = true

function logHazard(tag, part)
    if not DEBUG_HAZARD_LOG then return end
    local size = part and part.Size
    local name = part and part.Name or "nil"
    if size then
        print(string.format("[Hazard] %s | %s | size=(%.2f, %.2f, %.2f)", tag, name, size.X, size.Y, size.Z))
    else
        print(string.format("[Hazard] %s | %s", tag, name))
    end
end

function isLikelyCoconut(part)
    if not (part and part:IsA("BasePart")) then return false end
    -- Strict warning-disk size check (approx 23.4, 0.4, 23.4)
    local lower = part.Name:lower()
    local isWarningDisk = lower:find("warning") or lower:find("disk") or part.Name == "WarningDisk"
    if not isWarningDisk then
        return false
    end
    local diameter = part.Size.X
    local target = 23.4
    local tolerance = 1.0
    return math.abs(diameter - target) <= tolerance
end

function findCoconutDropTarget(rootPosition)
    local best, bestDist = nil, math.huge
    local particles = Workspace:FindFirstChild("Particles")
    if not particles then
        return nil
    end
    for _, inst in ipairs(particles:GetDescendants()) do
        if inst:IsA("BasePart") and inst.Transparency < 0.99 and isLikelyCoconut(inst) then
            local dist = (rootPosition - inst.Position).Magnitude
            if dist < bestDist and dist < MAX_TOKEN_TRACK_DISTANCE then
                best = inst
                bestDist = dist
            end
        end
    end
    return best
end

function isStarWarningDisk(part)
    if not part or not part:IsA("BasePart") then return false end
    -- Strict warning-disk only.
    local lower = part.Name:lower()
    local isWarningDisk = lower:find("warning") or lower:find("disk") or part.Name == "WarningDisk"
    if not isWarningDisk then
        return false
    end
    -- Size check (approx 8, 0.4, 8)
    local diameter = part.Size.X
    local target = 8
    local tolerance = 1.0
    return math.abs(diameter - target) <= tolerance and part.Transparency < 0.99
end

function findFallingStarTarget(rootPosition)
    local particles = Workspace:FindFirstChild("Particles")
    if not particles then
        return nil
    end
    local best, bestDist = nil, math.huge
    for _, inst in ipairs(particles:GetDescendants()) do
        if inst:IsA("BasePart") and inst.Transparency < 0.99 then
            if isStarWarningDisk(inst) then
                local dist = (rootPosition - inst.Position).Magnitude
                if dist < bestDist and dist < MAX_TOKEN_TRACK_DISTANCE then
                    best = inst
                    bestDist = dist
                end
            end
        end
    end
    return best
end

function isPreciseCrosshair(part)
    if not part or not part:IsA("BasePart") then return false end
    local lower = part.Name:lower()
    local parentLower = (part.Parent and part.Parent.Name or ""):lower()
    if not (lower:find("crosshair") or parentLower:find("crosshair")) then
        return false
    end
    local function isColorClose(c, target, tol)
        tol = tol or 0.03
        return math.abs(c.R - target.R) <= tol and math.abs(c.G - target.G) <= tol and math.abs(c.B - target.B) <= tol
    end
    local preferredColor = Color3.fromRGB(119, 85, 255)
    local inactiveColor = Color3.fromRGB(144, 119, 87)
    -- Base inactive color is roughly 144,119,87; only chase once it turns greenish.
    local c = part.Color
    local isInactive = isColorClose(c, inactiveColor, 0.025)
    local isPreferred = isColorClose(c, preferredColor, 0.04)
    local isInactiveColorAllowed = isColorClose(c, inactiveColor, 0.04)
    local isGreenish = c.G > c.R and c.G > c.B
    return part.Transparency < 0.99 and (isPreferred or isInactiveColorAllowed or (not isInactive and isGreenish))
end

function findPreciseCrosshairTarget(rootPosition)
    local particles = Workspace:FindFirstChild("Particles")
    if not particles then
        return nil
    end
    for inst in pairs(preciseVisitedMarks) do
        if not inst or not inst.Parent then
            preciseVisitedMarks[inst] = nil
        end
    end
    local best, bestDist = nil, math.huge
    for _, inst in ipairs(particles:GetDescendants()) do
        if isPreciseCrosshair(inst) and not preciseVisitedMarks[inst] then
            local dist = (rootPosition - inst.Position).Magnitude
            if dist < MAX_TOKEN_TRACK_DISTANCE then
                local c = inst.Color
                local isPreferred = (math.abs(c.R - 119/255) <= 0.04 and math.abs(c.G - 85/255) <= 0.04 and math.abs(c.B - 255/255) <= 0.04)
                if best == nil then
                    best, bestDist = inst, dist
                else
                    local bestIsPreferred = false
                    if best and best:IsA("BasePart") then
                        local bc = best.Color
                        bestIsPreferred = (math.abs(bc.R - 119/255) <= 0.04 and math.abs(bc.G - 85/255) <= 0.04 and math.abs(bc.B - 255/255) <= 0.04)
                    end
                    if (isPreferred and not bestIsPreferred) or (isPreferred == bestIsPreferred and dist < bestDist) then
                        best, bestDist = inst, dist
                    end
                end
            end
        end
    end
    return best
end

function isBubble(part)
    if not (part and part:IsA("BasePart")) then return false end
    local lower = part.Name:lower()
    local parentLower = (part.Parent and part.Parent.Name or ""):lower()
    if not (lower:find("bubble") or parentLower:find("bubble")) then
        return false
    end
    local size = part.Size.X
    if size < 0.5 or size > 25 then
        return false
    end
    return part.Transparency < 0.99
end

function findBubbleTarget(rootPosition)
    local particles = Workspace:FindFirstChild("Particles")
    if not particles then
        return nil
    end
    local best, bestDist = nil, math.huge
    for _, inst in ipairs(particles:GetDescendants()) do
        if isBubble(inst) then
            local pos = inst.Position
            if isInField(pos) and math.abs(pos.Y - rootPosition.Y) < 5 then
                local dist = (rootPosition - pos).Magnitude
                if dist < bestDist and dist < MAX_TOKEN_TRACK_DISTANCE then
                    best = inst
                    bestDist = dist
                end
            end
        end
    end
    return best
end

function getDustBunnyRootPart(inst)
    local node = inst
    while node and node ~= Workspace do
        local name = (node.Name or ""):lower()
        if name:find("dustbunny") then
            if node:IsA("Model") then
                local root = node:FindFirstChild("Root")
                if root and root:IsA("BasePart") then
                    return root
                end
                local plane = node:FindFirstChild("Plane")
                if plane and plane:IsA("BasePart") then
                    return plane
                end
                for _, child in ipairs(node:GetChildren()) do
                    if child:IsA("BasePart") then
                        return child
                    end
                end
            elseif node:IsA("BasePart") then
                return node
            end
        end
        node = node.Parent
    end
    return nil
end

function findFuzzyTarget(rootPosition)
    local particles = Workspace:FindFirstChild("Particles")
    if not particles then
        return nil
    end
    local best, bestDist = nil, math.huge
    local seen = {}
    for _, inst in ipairs(particles:GetDescendants()) do
        local part = getDustBunnyRootPart(inst)
        if part and not seen[part] then
            seen[part] = true
            local pos = part.Position
            if isInField(pos) and part.Transparency < 1 and math.abs(pos.Y - rootPosition.Y) < 5 then
                local dist = (rootPosition - pos).Magnitude
                if dist < bestDist and dist < MAX_TOKEN_TRACK_DISTANCE then
                    best = part
                    bestDist = dist
                end
            end
        end
    end
    return best
end

function collectMemoryMatchSlots()
    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    if not gui then
        return {}
    end
    local slots = {}
    for _, inst in ipairs(gui:GetDescendants()) do
        if inst.Name == "MemoryMatchGuiSlot" then
            local btn = inst:FindFirstChild("ObjButton", true)
            local img = inst:FindFirstChild("ObjImage", true)
            local countLabel = nil
            if img then
                countLabel = img:FindFirstChild("TextLabel") or img:FindFirstChildWhichIsA("TextLabel")
            end
            table.insert(slots, {
                button = btn,
                image = img,
                countLabel = countLabel,
            })
        end
    end
    return slots
end

function clickMemoryButton(btn)
    if not btn then return end
    local clicked = false
    local ok = pcall(function()
        if typeof(btn.Activate) == "function" then
            btn:Activate()
            clicked = true
        end
    end)
    if not clicked then
        local okPos, absPos = pcall(function()
            return btn.AbsolutePosition
        end)
        local okSize, absSize = pcall(function()
            return btn.AbsoluteSize
        end)
        if okPos and okSize and absPos and absSize then
            local x = absPos.X + absSize.X / 2
            local y = absPos.Y + absSize.Y / 2
            local vim = game:GetService("VirtualInputManager")
            pcall(function()
                vim:SendMouseButtonEvent(x, y, 0, true, game, 0)
                vim:SendMouseButtonEvent(x, y, 0, false, game, 0)
            end)
        end
    end
end

function stopAutoMemoryMatch()
    autoMemoryMatchEnabled = false
    if memoryMatchThread then
        if hasTaskCancel then
            pcall(function()
                task.cancel(memoryMatchThread)
            end)
        end
        memoryMatchThread = nil
    end
end

function startAutoMemoryMatch()
    if memoryMatchThread then
        return
    end
    memoryMatchThread = task.spawn(function()
        local seen = {}
        local matched = {}
        while autoMemoryMatchEnabled do
            local slots = collectMemoryMatchSlots()
            if not slots or #slots == 0 then
                seen = {}
                matched = {}
                task.wait(0.5)
            else
                for idx, tile in ipairs(slots) do
                    if not autoMemoryMatchEnabled then
                        break
                    end
                    if not matched[idx] then
                        local img = tile.image
                        local btn = tile.button
                        if img and btn then
                            -- Flip hidden tiles
                            if img.ImageTransparency >= 0.95 then
                                clickMemoryButton(btn)
                                task.wait(0.4)
                            end
                            -- Only memorize when the image is revealed
                            if img.ImageTransparency < 0.1 then
                                local key = tostring(img.Image or "nil")
                                local countText = (tile.countLabel and tile.countLabel:IsA("TextLabel")) and tile.countLabel.Text or nil
                                if countText then
                                    key = key .. "|" .. countText
                                end
                                local mateIndex = seen[key]
                                if mateIndex and mateIndex ~= idx and not matched[mateIndex] then
                                    local mate = slots[mateIndex]
                                    if mate and mate.button then
                                        if mate.image and mate.image.ImageTransparency >= 0.95 then
                                            clickMemoryButton(mate.button)
                                            task.wait(0.4)
                                        end
                                        matched[idx] = true
                                        matched[mateIndex] = true
                                        task.wait(1.1)
                                    end
                                else
                                    seen[key] = idx
                                end
                            end
                        end
                    end
                    task.wait(0.05)
                end
                task.wait(0.2)
            end
        end
        memoryMatchThread = nil
    end)
end

function dispenseHoney()
    if isDispensing then return end
    isDispensing = true

    local char = LocalPlayer.Character
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    local rootPart = getHRP()
    local originalWalkSpeed = humanoid and humanoid.WalkSpeed or nil
    local originalJumpPower = humanoid and humanoid.JumpPower or nil
    local hivePosValue = LocalPlayer:FindFirstChild("SpawnPos") and LocalPlayer.SpawnPos.Value
    local remote = ReplicatedStorage:FindFirstChild("Events", true) and ReplicatedStorage.Events:FindFirstChild("PlayerHiveCommand")
    
    if char and hivePosValue and remote and rootPart then
        -- 1. Lock Player Movement and Reset Velocity
        if humanoid then
            -- Only set walk/jump speed to 0
            humanoid.WalkSpeed = 0
            humanoid.JumpPower = 0
        end
        
        -- Teleport to a fixed point slightly above the hive to drop correctly
        local targetCFrame = CFrame.new(hivePosValue.p + Vector3.new(0, 5, 0))
        hardTeleportTo(targetCFrame)
        
        -- Reset velocity to stop sliding
        rootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        rootPart.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
        
        task.wait(0.1) -- Stabilize
        
        -- 2. Dispense Logic
        remote:FireServer("ToggleHoneyMaking")
        task.wait(1)
        local pollen = LocalPlayer.CoreStats:FindFirstChild("Pollen")
        local lastPollen = pollen and pollen.Value or 0
        local lastChangeTime = tick()
        local startGraceUntil = tick() + 4 -- allow startup before we judge stalls
        local restartCount = 0
        local MAX_RESTARTS = 3
        local conversionStartedAt = tick()

        local hiveCircleCF = nil
        local holdForBalloon = false
        if balloonBlessingHoldEnabled and balloonBlessingThreshold and balloonBlessingThreshold > 0 then
            hiveCircleCF = getHiveCircleCFrame()
            local startBlessing = hiveCircleCF and getBalloonBlessingValue(hiveCircleCF) or nil
            print(string.format(
                "[BalloonHold] Convert start: threshold=%s current=%s",
                tostring(balloonBlessingThreshold),
                tostring(startBlessing)
            ))
            if startBlessing and startBlessing >= balloonBlessingThreshold then
                holdForBalloon = true
                print("[BalloonHold] Hold mode ENABLED at start of conversion")
            else
                print("[BalloonHold] Hold mode NOT enabled at start (threshold not met or no blessing)")
            end
        end

        local function restartConversion()
            restartCount += 1
            -- Nudge back onto the hive pad and try to re-start conversion
            hardTeleportTo(targetCFrame)
            rootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            rootPart.AssemblyAngularVelocity = Vector3.new(0, 0, 0)

            remote:FireServer("ToggleHoneyMaking") -- flip state once
            task.wait(0.5)

            -- If we're already in a working phase, don't flip again.
            local phase = getHivePhase()
            if phase ~= "Working" then
                local before = pollen and pollen.Value or 0
                task.wait(1.1)
                local after = pollen and pollen.Value or 0
                if after >= before - 1 then
                    remote:FireServer("ToggleHoneyMaking")
                    task.wait(0.4)
                end
            end

            lastChangeTime = tick()
            lastPollen = pollen and pollen.Value or 0
        end

        while isAutoFarmEnabled and pollen and (pollen.Value > 10 or (holdForBalloon and hasBalloonAtHive(hiveCircleCF))) do
            task.wait(0.6)
            local now = tick()
            local current = pollen.Value

            -- Re-evaluate balloon blessing hold every tick so we don't miss late-loaded GUI
            if balloonBlessingHoldEnabled and balloonBlessingThreshold and balloonBlessingThreshold > 0 then
                if not hiveCircleCF then
                    hiveCircleCF = getHiveCircleCFrame()
                end
                if hiveCircleCF and hasBalloonAtHive(hiveCircleCF) then
                    local blessingValue = getBalloonBlessingValue(hiveCircleCF)
                    if blessingValue and blessingValue >= balloonBlessingThreshold then
                        holdForBalloon = true
                        print(string.format(
                            "[BalloonHold] Hold mode ENABLED mid-conversion (threshold=%s current=%s)",
                            tostring(balloonBlessingThreshold),
                            tostring(blessingValue)
                        ))
                    end
                end
            end

            if current < lastPollen - 5 then
                lastPollen = current
                lastChangeTime = now
            elseif now - lastChangeTime > 9 and now > startGraceUntil then
                -- When balloon hold is active, do not spam restartConversion;
                -- only restart if we're not in hold mode yet.
                if restartCount < MAX_RESTARTS and not holdForBalloon then
                    restartConversion()
                else
                    if not holdForBalloon or not hasBalloonAtHive(hiveCircleCF) then
                        break
                    else
                        -- In hold mode with balloon present, just extend the timer
                        lastChangeTime = now
                    end
                end
            end

            if not holdForBalloon and now - conversionStartedAt > 120 then
                break
            end

            if holdForBalloon and not hasBalloonAtHive(hiveCircleCF) then
                break
            end
        end

        if isAutoFarmEnabled and pollen then
            task.wait(1)
        end
        remote:FireServer("ToggleHoneyMaking")
        task.wait(0.1)
        
        -- 3. Return to Field
        if isAutoFarmEnabled and selectedField then
            hardTeleportTo(selectedField.CFrame + Vector3.new(0, 5, 0))
            resetMoveCommand()
        end
    end
    
    -- 4. Restore Player State
    if humanoid then
        if originalWalkSpeed then
            humanoid.WalkSpeed = originalWalkSpeed
        end
        if originalJumpPower then
            humanoid.JumpPower = originalJumpPower
        end
    end
    isDispensing = false
end

local Window = Library:CreateWindow({
    Title = "Unknown Hub"
})

function getUIRoot()
    local ok, ui = pcall(function()
        if typeof(gethui) == "function" then
            return gethui()
        end
        if typeof(get_hidden_gui) == "function" then
            return get_hidden_gui()
        end
        if typeof(gethiddenui) == "function" then
            return gethiddenui()
        end
        return nil
    end)

    if ok and ui then
        return ui
    end
    return CoreGui
end

function protectGui(gui)
    if typeof(gui) ~= "Instance" then return end

    local ok, fn = pcall(function()
        return syn and syn.protect_gui
    end)
    if ok and typeof(fn) == "function" then
        pcall(fn, gui)
    elseif typeof(protect_gui) == "function" then
        pcall(protect_gui, gui)
    end
end

function destroyStatsPanel()
    if statsGui then
        statsGui:Destroy()
    end
    statsGui = nil
    statsLabel = nil
end

function createStatsPanel()
    destroyStatsPanel()

    local root = getUIRoot()
    local gui = Instance.new("ScreenGui")
    gui.Name = "Eps_StatsPanel"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    protectGui(gui)
    gui.Parent = root
    
    local frame = Instance.new("Frame")
    frame.Name = "StatsFrame"
    frame.Size = UDim2.fromOffset(250, 110)
    frame.Position = UDim2.new(1, -270, 1, -160)
    frame.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
    frame.BorderSizePixel = 0
    frame.Parent = gui
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = frame
    
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(255, 255, 255)
    stroke.Transparency = 1
    stroke.Thickness = 1
    stroke.Enabled = false
    stroke.Parent = frame
    
    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Parent = frame
    title.Size = UDim2.new(1, -16, 0, 18)
    title.Position = UDim2.fromOffset(8, 8)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBold
    title.TextSize = 14
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextColor3 = Color3.fromRGB(230, 235, 240)
    title.Text = "Auto Farm Stats"
    
    local line = Instance.new("Frame")
    line.Parent = frame
    line.Size = UDim2.new(1, -16, 0, 1)
    line.Position = UDim2.fromOffset(8, 28)
    line.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    line.BackgroundTransparency = 0.9
    line.BorderSizePixel = 0

    local body = Instance.new("TextLabel")
    body.Name = "Body"
    body.Parent = frame
    body.Size = UDim2.new(1, -16, 1, -38)
    body.Position = UDim2.fromOffset(8, 32)
    body.BackgroundTransparency = 1
    body.Font = Enum.Font.Gotham
    body.TextSize = 12
    body.TextXAlignment = Enum.TextXAlignment.Left
    body.TextYAlignment = Enum.TextYAlignment.Top
    body.TextColor3 = Color3.fromRGB(170, 176, 186)
    body.TextWrapped = true
    body.Text = "Waiting for Auto Farm..."
    
    local dragging = false
    local dragInput
    local dragStart
    local startPos
    
    local function update(input)
        if not dragging then return end
        local delta = input.Position - dragStart
        frame.Position = UDim2.new(
            frame.Position.X.Scale,
            startPos.X.Offset + delta.X,
            frame.Position.Y.Scale,
            startPos.Y.Offset + delta.Y
        )
    end
    
    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    
    frame.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
            update(input)
        end
    end)
    
    statsGui = gui
    statsLabel = body
    frame.BackgroundTransparency = 1
    title.TextTransparency = 1
    body.TextTransparency = 1
    line.BackgroundTransparency = 1
    local ti = makeTweenInfo(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    TweenService:Create(frame, ti, { BackgroundTransparency = 0 }):Play()
    TweenService:Create(title, ti, { TextTransparency = 0 }):Play()
    TweenService:Create(body, ti, { TextTransparency = 0 }):Play()
    TweenService:Create(line, ti, { BackgroundTransparency = 0.9 }):Play()
end

function setAntiAfk(state)
    antiAfkEnabled = state and true or false
    if antiAfkConnection then
        if antiAfkConnection.Disconnect then
            antiAfkConnection:Disconnect()
        end
        antiAfkConnection = nil
    end
    if antiAfkEnabled then
        antiAfkConnection = LocalPlayer.Idled:Connect(function()
            pcall(function()
                VirtualUser:Button2Down(Vector2.new(0, 0), camera.CFrame)
                task.wait(1)
                VirtualUser:Button2Up(Vector2.new(0, 0), camera.CFrame)
            end)
        end)
    end
end

function doAutoClaimHive()
    task.spawn(function()
        pcall(function()
            local Players = game:GetService("Players")
            local LocalPlayer = Players.LocalPlayer
            local Workspace = game:GetService("Workspace")

            local hivePlatforms = Workspace:FindFirstChild("HivePlatforms")
            local alreadyOwnsHive = false
            if hivePlatforms then
                for _, platform in ipairs(hivePlatforms:GetChildren()) do
                    local playerRef = platform:FindFirstChild("PlayerRef")
                    if playerRef and playerRef.Value == LocalPlayer then
                        alreadyOwnsHive = true
                        break
                    end
                end
            end
            
            if alreadyOwnsHive then
                notify("Auto Claim Hive", "You already own a hive.", 3)
                if uiObjects.autoClaimHiveToggle then
                    uiObjects.autoClaimHiveToggle:SetState(false)
                end
                isAutoClaimHiveEnabled = false
                return
            end
            
            local ReplicatedStorage = game:GetService("ReplicatedStorage")
            local TweenService = game:GetService("TweenService")

            local Character = LocalPlayer.Character
            if not Character or not isAutoClaimHiveEnabled then return end
            local RootPart = Character:FindFirstChild("HumanoidRootPart")
            if not RootPart then return end

            local Events = ReplicatedStorage:FindFirstChild("Events")
            if not Events then return end
            local ClaimHiveEvent = Events:FindFirstChild("ClaimHive")
            local BeeClientLoadedEvent = Events:FindFirstChild("BeeClientLoaded")
            if not ClaimHiveEvent or not BeeClientLoadedEvent then return end
            
            local function TweenTo(targetPos)
                local tween = TweenService:Create(RootPart, makeTweenInfo(1.5, Enum.EasingStyle.Quad), {CFrame = CFrame.new(targetPos)})
                tween:Play()
                tween.Completed:Wait()
            end
            
            local honeycombs = Workspace:FindFirstChild("Honeycombs")
            if not honeycombs then return end
            local claimedHive = false
            
            for _, hive in ipairs(honeycombs:GetChildren()) do
                if not isAutoClaimHiveEnabled then break end
                local owner = hive:FindFirstChild("Owner")
                local hiveID = hive:FindFirstChild("HiveID")
                local spawnPos = hive:FindFirstChild("SpawnPos")
                
                if owner and hiveID and spawnPos and owner.Value == nil then
                    TweenTo(spawnPos.Value.p + Vector3.new(0, 3, 0))

                    if not isAutoClaimHiveEnabled then break end
                    ClaimHiveEvent:FireServer(hiveID.Value)
                    task.wait(0.5)

                    BeeClientLoadedEvent:FireServer()

                    claimedHive = true
                    notify("Auto Claim Hive", "Successfully claimed a hive!", 3)
                    break
                end
            end
            
            if not claimedHive then
                notify("Auto Claim Hive", "No unowned hives found.", 3)
            end
            
            if uiObjects.autoClaimHiveToggle then
                uiObjects.autoClaimHiveToggle:SetState(false)
            end
            isAutoClaimHiveEnabled = false
        end)
    end)
end

local sproutEspEnabled = false
local sproutDrawingCache = {}
local SproutTextSize = 19
local SproutVerticalOffset = 10
sproutEspLastUpdate = 0
SPROUT_ESP_UPDATE_INTERVAL = 0.12

function isColorClose(colorA, colorB)
    local tolerance = 0.05
    return (
        math.abs(colorA.R - colorB.R) < tolerance
        and math.abs(colorA.G - colorB.G) < tolerance
        and math.abs(colorA.B - colorB.B) < tolerance
    )
end

RunService.RenderStepped:Connect(function()
    local hasDrawing = (typeof(Drawing) == "table" or typeof(Drawing) == "userdata") and typeof(Drawing.new) == "function"
    if not hasDrawing then
        for inst, drawing in pairs(sproutDrawingCache) do
            pcall(function()
                if drawing.Remove then
                    drawing:Remove()
                end
            end)
            sproutDrawingCache[inst] = nil
        end
        return
    end

    if not sproutEspEnabled then
        for _, drawing in pairs(sproutDrawingCache) do
            drawing.Visible = false
        end
        return
    end

    local nowClock = os.clock()
    if nowClock - sproutEspLastUpdate < SPROUT_ESP_UPDATE_INTERVAL then
        return
    end
    sproutEspLastUpdate = nowClock
    
    for inst, drawing in pairs(sproutDrawingCache) do
        if not inst or not inst.Parent then
            pcall(function()
                if drawing.Remove then
                    drawing:Remove()
                end
            end)
            sproutDrawingCache[inst] = nil
        else
            drawing.Visible = false
        end
    end
    
    local sproutsFolder = Workspace:FindFirstChild("Sprouts")
    if not sproutsFolder then
        return
    end
    
    local SproutColors = {
        ["Default Sprout"] = Color3.fromRGB(180, 190, 186),
        ["Diamond Sprout"] = Color3.fromRGB(103, 162, 201),
    }
    local SproutTextFont = Drawing.Fonts and (Drawing.Fonts.Plex or Drawing.Fonts.UI) or nil

    for _, sprout_item in ipairs(sproutsFolder:GetChildren()) do
        pcall(function()
            if sprout_item.Name ~= "Sprout" then
                return
            end
            local rootPart
            if sprout_item:IsA("Model") then
                rootPart = sprout_item.PrimaryPart
                if not rootPart then
                    rootPart = sprout_item:FindFirstChildWhichIsA("BasePart", true)
                end
            elseif sprout_item:IsA("BasePart") then
                rootPart = sprout_item
            end
            if not rootPart then
                return
            end
            
            local valueLabel
            for _, d in ipairs(sprout_item:GetDescendants()) do
                if d:IsA("TextLabel") then
                    valueLabel = d
                    break
                end
            end
            if not valueLabel then
                return
            end
            
            local displayText = ""
            local displayColor = Color3.fromRGB(255, 255, 255)
            local isSpecialType = false
            
            for name, color in pairs(SproutColors) do
                if isColorClose(valueLabel.TextColor3, color) then
                    displayText = name
                    displayColor = color
                    isSpecialType = true
                    break
                end
            end
            
            if not isSpecialType then
                local health = valueLabel.Text:match("([%d,]+)$")
                if health then
                    displayText = "Sprout (" .. health .. ")"
                else
                    displayText = "Sprout"
                end
            end
            
            if displayText ~= "" then
                local screenPos, onScreen = camera:WorldToViewportPoint(
                    rootPart.Position + Vector3.new(0, SproutVerticalOffset, 0)
                )
                if onScreen then
                    local drawing = sproutDrawingCache[sprout_item]
                    if not drawing then
                        drawing = Drawing.new("Text")
                        sproutDrawingCache[sprout_item] = drawing
                    end
                    drawing.Text = displayText
                    drawing.Color = displayColor
                    drawing.Size = SproutTextSize
                    if SproutTextFont then
                        drawing.Font = SproutTextFont
                    end
                    drawing.Center = true
                    drawing.Outline = true
                    drawing.Position = Vector2.new(screenPos.X, screenPos.Y)
                    drawing.Visible = true
                end
            end
        end)
    end
end)


local PlayerPage = Window:AddMenu({ Title = "PLAYER", Icon = "rbxassetid://110673269470793" })
local FarmingPage = Window:AddMenu({ Title = "FARMING", Icon = "rbxassetid://105067681602444" })
VisualsPage = Window:AddMenu({ Title = "VISUALS", Icon = "rbxassetid://102233250280118" })
local PlantersPage = Window:AddMenu({ Title = "PLANTERS", Icon = "rbxassetid://10912963464", Columns = 2 })
local TeleportPage = Window:AddMenu({ Title = "TELEPORT", Icon = "rbxassetid://119605181458611" })

local uiObjects = {}

local MovementSection = PlayerPage:AddSection({ Title = "Movement" })
uiObjects.speedControl = MovementSection:AddSliderToggle({
    Title = "Custom WalkSpeed",
    DefaultToggle = false,
    Min = 16, Max = 300, Default = 100,
    SaveKey = "player_speed_control",
    OnToggleChange = function(state)
        isSpeedEnabled = state
        if not state and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
            LocalPlayer.Character.Humanoid.WalkSpeed = defaultWalkSpeed
        end
    end,
    OnSliderChange = function(value) currentSpeed = value end
})
uiObjects.jumpControl = MovementSection:AddSliderToggle({
    Title = "Custom JumpPower",
    DefaultToggle = false,
    Min = 50, Max = 500, Default = 150,
    SaveKey = "player_jump_control",
    OnToggleChange = function(state)
        isJumpEnabled = state
        if not state and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
            LocalPlayer.Character.Humanoid.JumpPower = defaultJumpPower
        end
    end,
    OnSliderChange = function(value) currentJump = value end
})
uiObjects.noclipToggle = MovementSection:AddToggle({
    Title = "Enable Noclip",
    SaveKey = "player_noclip_enabled",
    Callback = function(state) isNoclipEnabled = state end
})

local AutoFarmSection = FarmingPage:AddSection({ Title = "Auto Farm", Icon = "rbxassetid://105067681602444" })

local fieldNames, fieldObjects = {}, {}
local flowerZones = Workspace:WaitForChild("FlowerZones")
for _, part in ipairs(flowerZones:GetChildren()) do
    if part:IsA("BasePart") then
        table.insert(fieldNames, part.Name)
        fieldObjects[part.Name] = part
    end
end
table.sort(fieldNames)

local fieldRoute = {}
local fieldRouteThread = nil
local fieldRouteEnabled = false
local fieldRouteSelectedField = fieldNames[1]
local fieldRouteStepDuration = 60

function clearList(t)
    for k in pairs(t) do
        t[k] = nil
    end
end

function findFirstBasePart(instance)
    if not instance then return nil end
    if instance:IsA("BasePart") then
        return instance
    end
    if instance:IsA("Model") and instance.PrimaryPart then
        return instance.PrimaryPart
    end
    for _, desc in ipairs(instance:GetDescendants()) do
        if desc:IsA("BasePart") then
            return desc
        end
    end
    return nil
end

function teleportCharacterToCFrame(targetCFrame, options)
    if typeof(targetCFrame) ~= "CFrame" then return end
    options = options or {}
    tweenToCFrame(targetCFrame, options)
end

local npcNames, npcTargets = {}, {}
local preferredNPCOrder = {
"Ant Challenge Info", "Black Bear", "Brown Bear", "Bubble Bee Man 2",
"Bucko Bee", "Dapper Bear", "Gummy Bear", "Honey Bee", "Mother Bear",
"Onett", "Panda Bear", "Polar Bear", "Riley Bee", "Robo Bear",
"Science Bear", "Spirit Bear", "Stick Bug", "Wind Shrine"
}

function refreshNPCList()
    clearList(npcNames)
    npcTargets = {}
    local folders = {}
    local npcFolder = Workspace:FindFirstChild("NPCs")
    if npcFolder then
        table.insert(folders, npcFolder)
    end
    local npcBeesFolder = Workspace:FindFirstChild("NPCBees")
    if npcBeesFolder then
        table.insert(folders, npcBeesFolder)
    end

    local registered = {}
    local function registerNPC(name, instance)
        if registered[name] then return end
        registered[name] = true
        local part = findFirstBasePart(instance)
        if part then
            npcTargets[name] = part
        end
        table.insert(npcNames, name)
    end
    
    for _, name in ipairs(preferredNPCOrder) do
        for _, folder in ipairs(folders) do
            local npc = folder and folder:FindFirstChild(name)
            if npc then
                registerNPC(name, npc)
                break
            end
        end
    end
    
    for _, folder in ipairs(folders) do
        for _, npc in ipairs(folder:GetChildren()) do
            if not registered[npc.Name] then
                registerNPC(npc.Name, npc)
            end
        end
    end
    
    if #npcNames == 0 then
        for _, name in ipairs(preferredNPCOrder) do
            table.insert(npcNames, name)
        end
    end
end
refreshNPCList()

local npcFolderRoot = Workspace:FindFirstChild("NPCs")
if npcFolderRoot then
    npcFolderRoot.ChildAdded:Connect(refreshNPCList)
    npcFolderRoot.ChildRemoved:Connect(refreshNPCList)
end
local npcBeesFolderRoot = Workspace:FindFirstChild("NPCBees")
if npcBeesFolderRoot then
    npcBeesFolderRoot.ChildAdded:Connect(refreshNPCList)
    npcBeesFolderRoot.ChildRemoved:Connect(refreshNPCList)
end

local playerDropdownItems = {}
function refreshPlayerDropdownItems()
    clearList(playerDropdownItems)
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            table.insert(playerDropdownItems, plr.Name)
        end
    end
    table.sort(playerDropdownItems)
end
refreshPlayerDropdownItems()

Players.PlayerAdded:Connect(refreshPlayerDropdownItems)
Players.PlayerRemoving:Connect(refreshPlayerDropdownItems)

local shopNames, shopTargets = {}, {}
local preferredShopOrder = {
"BadgeBearersGuild", "BasicShop", "BlueHQ", "CoconutShop", "DapperItemShop",
"DapperPlanterShop", "DiamondMaskShop", "EggDispenser", "GumdropDispenser",
"GummyBearShop", "JellyDispenser", "LavaShop", "MagicBeanDispenser",
"MasterRoomShop", "Mountaintop", "Petal Shop", "ProShop", "RedHQ",
"RoboBearChallenge", "Sticker-SeekerShop", "StingerShop", "TicketDispenser",
"TicketShop", "TreatShop"
}

function refreshShopList()
    clearList(shopNames)
    shopTargets = {}
    local shopsFolder = Workspace:FindFirstChild("Shops")
    if not shopsFolder then
        for _, name in ipairs(preferredShopOrder) do
            table.insert(shopNames, name)
        end
        return
    end

    local registered = {}
    local function registerShop(name, instance)
        if registered[name] then return end
        registered[name] = true
        local part = findFirstBasePart(instance)
        if part then
            shopTargets[name] = part
        end
        table.insert(shopNames, name)
    end
    
    for _, name in ipairs(preferredShopOrder) do
        local shop = shopsFolder:FindFirstChild(name)
        if shop then
            registerShop(name, shop)
        end
    end
    
    for _, shop in ipairs(shopsFolder:GetChildren()) do
        if not registered[shop.Name] then
            registerShop(shop.Name, shop)
        end
    end
end
refreshShopList()

local shopsFolderRoot = Workspace:FindFirstChild("Shops")
if shopsFolderRoot then
    shopsFolderRoot.ChildAdded:Connect(refreshShopList)
    shopsFolderRoot.ChildRemoved:Connect(refreshShopList)
end

function setBetterGraphics(state)
    if BetterGraphicsModule and BetterGraphicsModule.SetGraphics then
        BetterGraphicsModule:SetGraphics(state and true or false)
    end
end

function setFullbright(state)
    state = state and true or false
    if state == visualState.fullbrightEnabled then
        return
    end

    if state then
        visualState.fullbrightLightingSnapshot = {
            Brightness = Lighting.Brightness,
            Ambient = Lighting.Ambient,
            OutdoorAmbient = Lighting.OutdoorAmbient,
            GlobalShadows = Lighting.GlobalShadows,
            FogEnd = Lighting.FogEnd,
        }

        pcall(function() Lighting.Brightness = 2 end)
        pcall(function() Lighting.Ambient = Color3.fromRGB(255, 255, 255) end)
        pcall(function() Lighting.OutdoorAmbient = Color3.fromRGB(255, 255, 255) end)
        pcall(function() Lighting.GlobalShadows = false end)
        pcall(function() Lighting.FogEnd = 1e6 end)
        visualState.fullbrightEnabled = true
        return
    end

    if visualState.fullbrightLightingSnapshot then
        pcall(function() Lighting.Brightness = visualState.fullbrightLightingSnapshot.Brightness end)
        pcall(function() Lighting.Ambient = visualState.fullbrightLightingSnapshot.Ambient end)
        pcall(function() Lighting.OutdoorAmbient = visualState.fullbrightLightingSnapshot.OutdoorAmbient end)
        pcall(function() Lighting.GlobalShadows = visualState.fullbrightLightingSnapshot.GlobalShadows end)
        pcall(function() Lighting.FogEnd = visualState.fullbrightLightingSnapshot.FogEnd end)
    end
    visualState.fullbrightLightingSnapshot = nil
    visualState.fullbrightEnabled = false
end

function setCustomTimeValue(value)
    local numeric = tonumber(value)
    if not numeric then
        return
    end
    visualState.customTimeValue = math.clamp(numeric, 0, 24)
    if visualState.customTimeEnabled then
        pcall(function()
            Lighting.ClockTime = visualState.customTimeValue
        end)
    end
end

function setCustomTimeEnabled(state)
    state = state and true or false
    if state == visualState.customTimeEnabled then
        if state then
            pcall(function()
                Lighting.ClockTime = visualState.customTimeValue
            end)
        end
        return
    end

    visualState.customTimeEnabled = state
    visualState.customTimeLoopToken += 1
    local activeToken = visualState.customTimeLoopToken

    if visualState.customTimeEnabled then
        visualState.customTimeSnapshot = Lighting.ClockTime
        pcall(function()
            Lighting.ClockTime = visualState.customTimeValue
        end)
        task.spawn(function()
            while visualState.customTimeEnabled and visualState.customTimeLoopToken == activeToken do
                pcall(function()
                    Lighting.ClockTime = visualState.customTimeValue
                end)
                task.wait(1)
            end
        end)
        return
    end

    if visualState.customTimeSnapshot ~= nil then
        pcall(function()
            Lighting.ClockTime = visualState.customTimeSnapshot
        end)
    end
    visualState.customTimeSnapshot = nil
end

function setFieldSelection(fieldName)
    if not fieldName then return end
    local field = fieldObjects[fieldName]
    if not field then return end

    selectedField = field
    selectedFieldName = fieldName
    wanderTarget = nil
    wanderExpireTime = 0
    wanderLastBase = nil
    activeToken = nil
    activeTokenIsLink = false
    activeTokenScore = 0
    resetTable(visitedTokens)
    resetTable(tokenMetadata)
    refreshFieldBounds()
    resetMoveCommand()
    if isAutoFarmEnabled and selectedField and LocalPlayer.Character then
        teleportCharacterToCFrame(selectedField.CFrame + Vector3.new(0, 5, 0))
    end
    fieldRouteSelectedField = fieldName
end

function setAutoFarmEnabled(state)
    isAutoFarmEnabled = state and true or false
    wanderTarget = nil
    wanderExpireTime = 0
    
    if isAutoFarmEnabled and selectedField and LocalPlayer.Character then
        teleportCharacterToCFrame(selectedField.CFrame + Vector3.new(0, 5, 0))
        resetMoveCommand()
    else
        wanderTarget, activeToken, isDispensing = nil, nil, false
        activeTokenIsLink = false
        activeTokenScore = 0
        wanderExpireTime = 0
        wanderLastBase = nil
        resetTable(visitedTokens)
        resetTable(tokenMetadata)
        resetMoveCommand()
    end
    
    fieldBoundsEnabled = isAutoFarmEnabled and true or false
    refreshFieldBounds()
    
    if isAutoFarmEnabled then
        local coreStats = LocalPlayer:FindFirstChild("CoreStats")
        local pollen = coreStats and coreStats:FindFirstChild("Pollen")
        local honey = coreStats and coreStats:FindFirstChild("Honey")
        farmSessionStart = tick()
        farmStartPollen = pollen and pollen.Value or 0
        farmStartHoney = honey and honey.Value or 0
    else
        farmSessionStart = 0
    end
    refreshAutoDig(isAutoFarmEnabled)
end

function formatPercent(value)
    local numberValue = tonumber(value) or 0
    if numberValue < 0 then
        numberValue = 0
    end
    return string.format("%.1f%%", math.clamp(numberValue, 0, 1) * 100)
end

function normalizePlanterName(name)
    if type(name) ~= "string" then
        return nil
    end
    local cleaned = name:lower():gsub("%s+", ""):gsub("[^%w]", "")
    if cleaned == "" then
        return nil
    end
    return cleaned
end

function dropdownIndexForValue(list, value)
    if type(list) ~= "table" or #list == 0 then
        return 1
    end
    for index, item in ipairs(list) do
        if item == value then
            return index
        end
    end
    return 1
end

local PLANER_SLOT_COUNT = 3
local PLANER_CYCLE_COUNT = 4
local ANY_PLANTER_LABEL = "Any Planter"
local HARVEST_MODE_PERCENT = "percent"
local HARVEST_MODE_TIMER = "timer"
local harvestModeOptions = {
    { label = "Ready %", value = HARVEST_MODE_PERCENT },
    { label = "Timer (Hours)", value = HARVEST_MODE_TIMER }
}
local harvestModeLookup = {}
for index, option in ipairs(harvestModeOptions) do
    harvestModeLookup[option.value] = index
end
local PLANTER_VARIANTS = {
    { name = "Plastic Planter", typeKey = "PlasticPlanter" },
    { name = "Candy Planter", typeKey = "CandyPlanter" },
    { name = "Red Clay Planter", typeKey = "RedClayPlanter" },
    { name = "Blue Clay Planter", typeKey = "BlueClayPlanter" },
    { name = "Tacky Planter", typeKey = "TackyPlanter" },
    { name = "Pesticide Planter", typeKey = "PesticidePlanter" },
    { name = "Heat-Treated Planter", typeKey = "Heat-TreatedPlanter" },
    { name = "Hydroponic Planter", typeKey = "HydroponicPlanter" },
    { name = "Petal Planter", typeKey = "PetalPlanter" },
    { name = "Planter Of Plenty", typeKey = "PlentyPlanter" }
}
local planterDropdownItems = { ANY_PLANTER_LABEL }
for _, entry in ipairs(PLANTER_VARIANTS) do
    entry.normalized = normalizePlanterName(entry.name)
    table.insert(planterDropdownItems, entry.name)
end

local ANY_FIELD_VALUE = "Any Field"
local planterFieldOptions = { ANY_FIELD_VALUE }
for _, name in ipairs(fieldNames) do
    table.insert(planterFieldOptions, name)
end

local planterCycles = {}
local slotMatchesPlanter
function getCycleSlot(cycleIndex, slotIndex)
    planterCycles[cycleIndex] = planterCycles[cycleIndex] or {}
    if not planterCycles[cycleIndex][slotIndex] then
        planterCycles[cycleIndex][slotIndex] = {
            planter = ANY_PLANTER_LABEL,
            field = ANY_FIELD_VALUE,
            timer = false
        }
    end
    return planterCycles[cycleIndex][slotIndex]
end

function syncSlotMetadata(cycleIndex, slotIndex)
    local slot = getCycleSlot(cycleIndex, slotIndex)
    if slot.planter == ANY_PLANTER_LABEL or slot.planter == nil then
        slot.normalized = nil
    else
        slot.normalized = normalizePlanterName(slot.planter)
    end
end

function loadPlanterCycles()
    for cycleIndex = 1, PLANER_CYCLE_COUNT do
        for slotIndex = 1, PLANER_SLOT_COUNT do
            local slot = getCycleSlot(cycleIndex, slotIndex)
            local keyPrefix = ("planter_cycle_%d_slot_%d_"):format(cycleIndex, slotIndex)
            local slotPlanter = Library:_GetSetting(keyPrefix .. "planter", nil)
            local slotField = Library:_GetSetting(keyPrefix .. "field", nil)
            local slotTimer = Library:_GetSetting(keyPrefix .. "timer", nil)
            if cycleIndex == 1 then
                if slotPlanter == nil then
                    slotPlanter = Library:_GetSetting(("planter_slot_%d_planter"):format(slotIndex), nil)
                end
                if slotField == nil then
                    slotField = Library:_GetSetting(("planter_slot_%d_field"):format(slotIndex), nil)
                end
                if slotTimer == nil then
                    slotTimer = Library:_GetSetting(("planter_slot_%d_timer"):format(slotIndex), nil)
                end
            end
            slot.planter = slotPlanter or ANY_PLANTER_LABEL
            slot.field = slotField or ANY_FIELD_VALUE
            slot.timer = slotTimer and true or false
            syncSlotMetadata(cycleIndex, slotIndex)
        end
    end
end
loadPlanterCycles()

function updateSlotValue(cycleIndex, slotIndex, key, value)
    local slot = getCycleSlot(cycleIndex, slotIndex)
    slot[key] = value
    if key == "planter" then
        syncSlotMetadata(cycleIndex, slotIndex)
    end
end

local planterCycleLabels = {}
for cycleIndex = 1, PLANER_CYCLE_COUNT do
    planterCycleLabels[cycleIndex] = ("Cycle %d"):format(cycleIndex)
end

function cycleHasConfiguration(cycleIndex)
    local slots = planterCycles[cycleIndex]
    if not slots then
        return false
    end
    for slotIndex = 1, PLANER_SLOT_COUNT do
        local slot = slots[slotIndex]
        if slot and slot.planter ~= ANY_PLANTER_LABEL then
            if slot.field and slot.field ~= "" and slot.field ~= ANY_FIELD_VALUE then
                return true
            end
        end
    end
    return false
end

function clampCycleIndex(index)
    local numberIndex = tonumber(index) or 1
    numberIndex = math.clamp(math.floor(numberIndex + 0.5), 1, PLANER_CYCLE_COUNT)
    if cycleHasConfiguration(numberIndex) then
        return numberIndex
    end
    for offset = 1, PLANER_CYCLE_COUNT do
        local candidate = ((numberIndex - 1 + offset) % PLANER_CYCLE_COUNT) + 1
        if cycleHasConfiguration(candidate) then
            return candidate
        end
    end
    return 1
end

function nextCycleIndex(fromIndex)
    local start = clampCycleIndex(fromIndex or 1)
    for offset = 1, PLANER_CYCLE_COUNT do
        local candidate = ((start - 1 + offset) % PLANER_CYCLE_COUNT) + 1
        if cycleHasConfiguration(candidate) then
            return candidate
        end
    end
    return start
end

local planterCycleDropdownProgrammatic = false
local planterCycleNextIndex = clampCycleIndex(Library:_GetSetting("planter_cycle_next_index", 1) or 1)
local planterActiveCycleIndex = clampCycleIndex(Library:_GetSetting("planter_active_cycle_index", planterCycleNextIndex) or planterCycleNextIndex)

function syncPlanterCycleDropdown()
    local ctrl = uiObjects and uiObjects.planterCycleDropdown
    if not ctrl then
        return
    end
    planterCycleDropdownProgrammatic = true
    local ok = pcall(function()
        if ctrl.SetValue then
            ctrl:SetValue(planterCycleNextIndex)
        elseif ctrl.SetSelection then
            ctrl:SetSelection(planterCycleLabels[planterCycleNextIndex])
        elseif ctrl.SetSelected then
            ctrl:SetSelected(planterCycleLabels[planterCycleNextIndex])
        elseif ctrl.Set then
            ctrl:Set(planterCycleLabels[planterCycleNextIndex])
        end
    end)
    if not ok and ctrl.SetText then
        pcall(function()
            ctrl:SetText(planterCycleLabels[planterCycleNextIndex])
        end)
    end
    planterCycleDropdownProgrammatic = false
end

function setActivePlanterCycle(index)
    planterActiveCycleIndex = clampCycleIndex(index or planterCycleNextIndex or 1)
    Library:SetSaveKey("planter_active_cycle_index", planterActiveCycleIndex)
end

function setNextPlanterCycle(index)
    planterCycleNextIndex = clampCycleIndex(index or 1)
    Library:SetSaveKey("planter_cycle_next_index", planterCycleNextIndex)
    syncPlanterCycleDropdown()
end

function countCycleMatches(cycleIndex, planterList)
    local slots = planterCycles[cycleIndex]
    if not slots or type(planterList) ~= "table" then
        return 0
    end
    local used = {}
    local matches = 0
    for slotIndex = 1, PLANER_SLOT_COUNT do
        local slot = slots[slotIndex]
        if slot and slot.planter ~= ANY_PLANTER_LABEL then
            for _, planter in ipairs(planterList) do
                if not used[planter] and slotMatchesPlanter(slot, planter) then
                    used[planter] = true
                    matches += 1
                    break
                end
            end
        end
    end
    return matches
end

function updateDetectedPlanterCycle(planterList)
    if type(planterList) ~= "table" or #planterList == 0 then
        return nil, 0
    end
    local bestCycle, bestScore = nil, 0
    for cycleIndex = 1, PLANER_CYCLE_COUNT do
        local score = countCycleMatches(cycleIndex, planterList)
        if score > bestScore then
            bestScore = score
            bestCycle = cycleIndex
        end
    end
    if bestCycle then
        setActivePlanterCycle(bestCycle)
        if bestScore > 0 and planterCycleNextIndex == bestCycle and not autoplaceActive then
            setNextPlanterCycle(nextCycleIndex(bestCycle))
        end
    end
    return bestCycle, bestScore
end

function logPlanterAuto(message, ...)
    local text
    if select('#', ...) > 0 then
        local ok, formatted = pcall(string.format, message, ...)
        text = ok and formatted or message
    else
        text = tostring(message)
    end
    print("[Planter Auto] " .. text)
end

function getPlanterCollectRemote()
    local events = ReplicatedStorage:FindFirstChild("Events")
    if not events then
        return nil
    end
    return events:FindFirstChild("PlanterModelCollect")
end

local planterAutoCollectEnabled = Library:_GetSetting("planter_auto_collect_enabled", false) and true or false
local planterCollectThreshold = tonumber(Library:_GetSetting("planter_collect_threshold", 95)) or 95
local planterHarvestWindow = tonumber(Library:_GetSetting("planter_collect_window", 15)) or 15
local planterHarvestMode = Library:_GetSetting("planter_harvest_mode", HARVEST_MODE_PERCENT)
if not harvestModeLookup[planterHarvestMode] then
    planterHarvestMode = HARVEST_MODE_PERCENT
end
local planterHarvestAfterHours = tonumber(Library:_GetSetting("planter_collect_after_hours", 6)) or 6
local planterAutoPlaceEnabled = Library:_GetSetting("planter_auto_place_enabled", false) and true or false
local planterPlaceDelaySeconds = tonumber(Library:_GetSetting("planter_place_delay", 8)) or 8
local autoplaceActive = false
local autoplaceThread = nil
local autoplaceToggleProgrammatic = false
local planterSeenTimes = {}

local planterTypesModule = nil
do
    local planterTypesScript = ReplicatedStorage:FindFirstChild("PlanterTypes")
    if planterTypesScript and planterTypesScript:IsA("ModuleScript") then
        local ok, mod = pcall(require, planterTypesScript)
        if ok and type(mod) == "table" then
            planterTypesModule = mod
        end
    end
end

function getPlanterDisplayName(typeName)
    if planterTypesModule and type(planterTypesModule.Get) == "function" and type(typeName) == "string" then
        local ok, record = pcall(planterTypesModule.Get, typeName)
        if ok and type(record) == "table" and record.DisplayName then
            return record.DisplayName
        end
    end
    return typeName or "Planter"
end

local planterZoneCache = nil
function rebuildPlanterZones()
    planterZoneCache = {}
    local folder = Workspace:FindFirstChild("FlowerZones")
    if not folder then
        return planterZoneCache
    end
    for _, zone in ipairs(folder:GetChildren()) do
        if zone:IsA("Model") then
            local ok, cf, size = pcall(zone.GetBoundingBox, zone)
            if ok and cf and size then
                table.insert(planterZoneCache, { cf = cf, size = size, name = zone.Name })
            end
        elseif zone:IsA("BasePart") then
            table.insert(planterZoneCache, { cf = zone.CFrame, size = zone.Size, name = zone.Name })
        end
    end
    return planterZoneCache
end

function pointInsideZone(zone, pos)
    if not zone or not pos then
        return false
    end
    local ok, relative = pcall(function()
        return zone.cf:PointToObjectSpace(pos)
    end)
    if not ok or typeof(relative) ~= "Vector3" then
        return false
    end
    return math.abs(relative.X) <= zone.size.X * 0.5
        and math.abs(relative.Y) <= zone.size.Y * 0.5
        and math.abs(relative.Z) <= zone.size.Z * 0.5
end

function nearestZoneName(pos)
    if typeof(pos) ~= "Vector3" then
        return nil
    end
    local zones = planterZoneCache or rebuildPlanterZones()
    if #zones == 0 then
        return nil
    end
    local bestName, bestDistance = nil, math.huge
    for _, zone in ipairs(zones) do
        if pointInsideZone(zone, pos) then
            return zone.name
        end
        local ok, relative = pcall(function()
            return zone.cf:PointToObjectSpace(pos)
        end)
        if ok and typeof(relative) == "Vector3" then
            local dx = math.max(math.abs(relative.X) - zone.size.X * 0.5, 0)
            local dy = math.max(math.abs(relative.Y) - zone.size.Y * 0.5, 0)
            local dz = math.max(math.abs(relative.Z) - zone.size.Z * 0.5, 0)
            local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
            if distance < bestDistance then
                bestDistance = distance
                bestName = zone.name
            end
        end
    end
    return bestName
end

function fetchLocalPlanterTables()
    local moduleScript = ReplicatedStorage:FindFirstChild("LocalPlanters")
    if not moduleScript or not moduleScript:IsA("ModuleScript") then
        return nil
    end
    local okModule, moduleTable = pcall(require, moduleScript)
    if not okModule or type(moduleTable) ~= "table" then
        return nil
    end
    local debugLib = debug
    if not debugLib or type(debugLib.getupvalue) ~= "function" then
        return nil
    end
    local okList, myPlanters = pcall(debugLib.getupvalue, moduleTable.CheckForNearbyHarvestablePlanters, 1)
    local okMap, planterMap = pcall(debugLib.getupvalue, moduleTable.PromptCollect, 1)
    if not okList or type(myPlanters) ~= "table" then
        myPlanters = {}
    end
    if not okMap or type(planterMap) ~= "table" then
        planterMap = {}
    end
    return moduleTable, myPlanters, planterMap
end

function collectMyPlanters()
    local moduleTable, myPlanters = fetchLocalPlanterTables()
    if not moduleTable or not myPlanters then
        return nil, nil
    end
    local now = os.clock()
    local seenThisCycle = {}
    local collection = {}
    for _, entry in ipairs(myPlanters) do
        if entry.Active and entry.IsMine then
            local display = getPlanterDisplayName(entry.Type)
            local position = entry.Pos
            if typeof(position) ~= "Vector3" and entry.BulbPart then
                position = entry.BulbPart.Position
            end
            local resolvedField = position and nearestZoneName(position) or nil
            local actorId = entry.ActorID
            if actorId then
                planterSeenTimes[actorId] = planterSeenTimes[actorId] or now
                seenThisCycle[actorId] = true
            end
            table.insert(collection, {
                actorId = entry.ActorID,
                rawName = entry.Type,
                typeKey = entry.Type,
                displayName = display,
                normalized = normalizePlanterName(display),
                growth = entry.GrowthPercent or 0,
                position = position,
                zone = resolvedField,
                glittered = entry.Glittered and true or false,
                puff = entry.Puffshroom and true or false,
                plantedAt = actorId and planterSeenTimes[actorId] or now
            })
        end
    end
    for actorId in pairs(planterSeenTimes) do
        if not seenThisCycle[actorId] then
            planterSeenTimes[actorId] = nil
        end
    end
    table.sort(collection, function(a, b)
        return (a.growth or 0) > (b.growth or 0)
    end)
    logPlanterAuto("Detected %d owned planter(s)", #collection)
    updateDetectedPlanterCycle(collection)
    return moduleTable, collection
end

function callPlanterPlantRemote(slot)
    if not slot or type(slot.planter) ~= "string" or slot.planter == "" then
        return false, "Invalid planter selection"
    end
    local remote = playerActivesRemote()
    if not remote then
        logPlanterAuto("PlayerActives remote missing; cannot place %s", slot.planter)
        return false, "PlayerActives remote missing"
    end
    logPlanterAuto("Firing PlayerActivesCommand for %s", slot.planter)
    local ok, err = pcall(function()
        remote:FireServer({ Name = slot.planter })
    end)
    if not ok then
        return false, err
    end
    return true
end

function computeFieldPlantCFrame(fieldName)
    if not fieldName or fieldName == "" then
        return nil
    end
    local fieldPart = fieldObjects[fieldName]
    if not fieldPart or not fieldPart.CFrame then
        return nil
    end
    local yOffset = 0.75
    if fieldPart.Size then
        yOffset = fieldPart.Size.Y * 0.5 + 0.75
    end
    return fieldPart.CFrame + Vector3.new(0, yOffset, 0)
end


function isPlanterInField(planter, fieldName)
    if not fieldName or fieldName == "" or fieldName == ANY_FIELD_VALUE then
        return true
    end
    if planter.zone == fieldName then
        return true
    end
    local fieldPart = fieldObjects[fieldName]
    if not fieldPart or typeof(planter.position) ~= "Vector3" then
        return false
    end
    local relative = fieldPart.CFrame:PointToObjectSpace(planter.position)
    local size = fieldPart.Size
    if not size then
        return false
    end
    return math.abs(relative.X) <= size.X * 0.5
        and math.abs(relative.Y) <= size.Y * 0.5
        and math.abs(relative.Z) <= size.Z * 0.5
end

slotMatchesPlanter = function(slot, planter)
    if not slot or not planter then
        return false
    end
    if slot.planter ~= ANY_PLANTER_LABEL then
        if not slot.normalized or not planter.normalized or slot.normalized ~= planter.normalized then
            return false
        end
    end
    return isPlanterInField(planter, slot.field)
end

function slotNeedsPlanter(cycleIndex, slotIndex, planterList)
    local slot = getCycleSlot(cycleIndex, slotIndex)
    if not slot or slot.planter == ANY_PLANTER_LABEL then
        return false, "slot not configured"
    end
    if not slot.field or slot.field == "" or slot.field == ANY_FIELD_VALUE then
        return false, "field missing"
    end
    if type(planterList) == "table" then
        for _, planter in ipairs(planterList) do
            if slotMatchesPlanter(slot, planter) then
                return false, "already planted"
            end
        end
    end
    return true
end

function findCycleSlotForPlanter(planter)
    if not planter then
        return nil, nil
    end
    for cycleIndex = 1, PLANER_CYCLE_COUNT do
        for slotIndex = 1, PLANER_SLOT_COUNT do
            if slotMatchesPlanter(getCycleSlot(cycleIndex, slotIndex), planter) then
                return cycleIndex, slotIndex
            end
        end
    end
    return nil, nil
end

function finalizeAutoPlace(message, returnCFrame, finishedCycle)
    if message then
        logPlanterAuto(message)
    end
    autoplaceActive = false
    autoplaceThread = nil
    if planterAutoPlaceEnabled then
        planterAutoPlaceEnabled = false
        if uiObjects and uiObjects.planterAutoPlaceToggle and uiObjects.planterAutoPlaceToggle.SetState then
            autoplaceToggleProgrammatic = true
            pcall(function()
                uiObjects.planterAutoPlaceToggle:SetState(false)
            end)
            autoplaceToggleProgrammatic = false
        end
    end
    if finishedCycle then
        setActivePlanterCycle(finishedCycle)
        setNextPlanterCycle(nextCycleIndex(finishedCycle))
    end
    if returnCFrame and isAutoFarmEnabled then
        teleportCharacterToCFrame(returnCFrame)
    end
end

function runAutoPlaceOnce()
    if autoplaceThread then
        logPlanterAuto("Auto place already running.")
        return
    end
    autoplaceActive = true
    local resumeCFrame = (isAutoFarmEnabled and selectedField and selectedField.CFrame + Vector3.new(0, 5, 0)) or nil
    autoplaceThread = task.spawn(function()
        local _, planterList = collectMyPlanters()
        planterList = planterList or {}
        local targetCycle = clampCycleIndex(planterCycleNextIndex)
        logPlanterAuto("Auto place targeting cycle %d", targetCycle)
        local missing = {}
        for slotIndex = 1, PLANER_SLOT_COUNT do
            local needs, reason = slotNeedsPlanter(targetCycle, slotIndex, planterList)
            if needs then
                table.insert(missing, slotIndex)
            else
                logPlanterAuto("Slot %d idle: %s", slotIndex, reason or "already satisfied")
            end
        end
        if #missing == 0 then
            finalizeAutoPlace("Auto place: all slots satisfied.", resumeCFrame, targetCycle)
            return
        end
        local placementsMade = 0
        for _, slotIndex in ipairs(missing) do
            if not autoplaceActive then
                break
            end
            local slot = getCycleSlot(targetCycle, slotIndex)
            if slot then
                logPlanterAuto("Auto place: cycle %d slot %d -> %s at %s", targetCycle, slotIndex, slot.planter or "?", slot.field or "?")
                local targetCFrame = computeFieldPlantCFrame(slot.field)
                if not targetCFrame then
                    logPlanterAuto("Field %s missing for slot %d", tostring(slot.field), slotIndex)
                else
                    teleportCharacterToCFrame(targetCFrame + Vector3.new(0, 6, 0))
                    task.wait(0.35)
                    if callPlanterPlantRemote(slot) then
                        logPlanterAuto("Placement requested for cycle %d slot %d (%s)", targetCycle, slotIndex, slot.planter or "?")
                        placementsMade += 1
                        task.wait(math.max(1, planterPlaceDelaySeconds))
                        _, planterList = collectMyPlanters()
                        planterList = planterList or {}
                    else
                        logPlanterAuto("Placement failed for slot %d", slotIndex)
                    end
                end
            end
        end
        finalizeAutoPlace("Auto place run complete.", resumeCFrame, targetCycle)
    end)
end

function cancelAutoPlace()
    if autoplaceActive then
        logPlanterAuto("Auto place cancelled.")
    end
    autoplaceActive = false
end

local PLANTER_LOOT_RADIUS = 45
function collectPlanterLoot(centerPosition, duration)
    local goalPos = centerPosition
    if typeof(goalPos) ~= "Vector3" then
        local hrp = getHRP()
        goalPos = hrp and hrp.Position or nil
    end
    local folder = Workspace:FindFirstChild("Collectibles")
    local deadline = os.clock() + duration
    while os.clock() < deadline do
        local bestToken, bestDistance
        if folder and goalPos then
            for _, token in ipairs(folder:GetChildren()) do
                if token:IsA("BasePart") and token.Parent then
                    local dist = (token.Position - goalPos).Magnitude
                    if dist <= PLANTER_LOOT_RADIUS and (not bestDistance or dist < bestDistance) then
                        bestToken = token
                        bestDistance = dist
                    end
                end
            end
        end
        if bestToken and bestToken.CFrame then
            teleportCharacterToCFrame(bestToken.CFrame + Vector3.new(0, 3, 0))
            task.wait(0.2)
        else
            task.wait(0.25)
        end
    end
end

function formatShortDuration(seconds)
    local total = math.max(0, math.floor((tonumber(seconds) or 0) + 0.5))
    local hours = math.floor(total / 3600)
    local minutes = math.floor((total % 3600) / 60)
    local secs = total % 60
    local parts = {}
    if hours > 0 then
        table.insert(parts, string.format("%dh", hours))
    end
    if minutes > 0 or hours > 0 then
        table.insert(parts, string.format("%dm", minutes))
    end
    if hours == 0 then
        table.insert(parts, string.format("%ds", secs))
    end
    if #parts == 0 then
        return "0s"
    end
    return table.concat(parts, " ")
end

function buildPlanterTimerText(planter, nowClock)
    if planterHarvestMode ~= HARVEST_MODE_TIMER then
        return nil
    end
    if not planter or not planter.plantedAt then
        return nil
    end
    local plantedAt = tonumber(planter.plantedAt)
    if not plantedAt then
        return nil
    end
    local harvestAfterSeconds = math.max(1, math.floor(planterHarvestAfterHours + 0.5)) * 3600
    local elapsed = math.max(0, nowClock - plantedAt)
    local remaining = harvestAfterSeconds - elapsed
    if remaining <= 0 then
        return "Ready (timer)"
    end
    return string.format("ETA %s", formatShortDuration(remaining))
end

function resumeAutoFarmFromPlanter(alreadyTeleported)
    if autoplaceActive and autoplaceThread == nil then
        autoplaceActive = false
    end
    if isAutoFarmEnabled and selectedField then
        if not alreadyTeleported then
            teleportCharacterToCFrame(selectedField.CFrame + Vector3.new(0, 5, 0))
        end
        resetMoveCommand()
    end
end

function describePlanterRecord(planter, timerText)
    if not planter then
        return "No planters detected"
    end
    local percentText = formatPercent(planter.growth or 0)
    local locationText = planter.zone or "Unknown Field"
    local parts = { planter.displayName or "Planter", percentText, locationText }
    if timerText and timerText ~= "" then
        table.insert(parts, timerText)
    end
    return table.concat(parts, " | ")
end

local planterStatusText = "Waiting for planter info..."
local uiPlanterStatusBox = nil
local planterHarvestCooldowns = {}
local planterHarvestInProgress = false
local lastPlanterSnapshot = {}

function harvestPlanter(moduleTable, planterRecord, slotIndex)
    if not moduleTable or not planterRecord then
        return
    end
    if planterHarvestInProgress then
        return
    end
    logPlanterAuto("Collect request for slot %s (%s)", slotIndex or "?", planterRecord.displayName or "Planter")
    planterHarvestInProgress = true
    if planterRecord.actorId then
        planterHarvestCooldowns[planterRecord.actorId] = os.clock() + planterHarvestWindow
    end
    local returnCFrame = nil
    if isAutoFarmEnabled and selectedField then
        returnCFrame = selectedField.CFrame + Vector3.new(0, 5, 0)
    end
    local heightOffset = Vector3.new(0, 6, 0)
    local centerPosition = planterRecord.position
    if planterRecord.position then
        teleportCharacterToCFrame(CFrame.new(planterRecord.position + heightOffset))
    elseif planterRecord.zone and fieldObjects[planterRecord.zone] then
        teleportCharacterToCFrame(fieldObjects[planterRecord.zone].CFrame + heightOffset)
        centerPosition = fieldObjects[planterRecord.zone].Position
    end
    local collectRemote = getPlanterCollectRemote()
    local okCollect, collectResult
    if collectRemote then
        okCollect, collectResult = pcall(function()
            if collectRemote:IsA("RemoteEvent") then
                collectRemote:FireServer(planterRecord.actorId)
            else
                collectRemote:InvokeServer(planterRecord.actorId)
            end
        end)
    else
        okCollect, collectResult = pcall(moduleTable.PromptCollect, planterRecord.actorId)
    end
    if okCollect then
        logPlanterAuto("Collect succeeded for %s", planterRecord.displayName or planterRecord.actorId or "?")
        notify("Planter Auto Collect", string.format("Collected %s%s", planterRecord.displayName or "Planter", planterRecord.zone and (" at " .. planterRecord.zone) or ""), 4)
    else
        warn("[Planter Auto] Failed to collect planter:", collectResult)
        logPlanterAuto("Collect failed: %s", tostring(collectResult))
    end
    local holdSeconds = 25
    logPlanterAuto("Holding at planter for %.1f seconds to gather drops", holdSeconds)
    task.wait(holdSeconds)
    logPlanterAuto("Collect hold finished")
    planterHarvestInProgress = false
    if planterRecord.actorId then
        planterSeenTimes[planterRecord.actorId] = nil
    end
    if returnCFrame then
        teleportCharacterToCFrame(returnCFrame)
    end
    resumeAutoFarmFromPlanter(returnCFrame ~= nil)
end

function refreshPlanterStatus(planterList)
    if not uiPlanterStatusBox then
        return
    end
    if not planterList or #planterList == 0 then
        planterStatusText = "No planters detected"
    else
        local lines = {}
        local nowClock = os.clock()
        for index, planter in ipairs(planterList) do
            local slotName = "Unassigned"
            local cycleIndex, slotIndex = findCycleSlotForPlanter(planter)
            if cycleIndex and slotIndex then
                slotName = ("Cycle %d Slot %d"):format(cycleIndex, slotIndex)
            end
            local timerText = buildPlanterTimerText(planter, nowClock)
            table.insert(lines, string.format("%d) %s [%s]", index, describePlanterRecord(planter, timerText), slotName))
        end
        planterStatusText = table.concat(lines, "\n")
    end
    if uiPlanterStatusBox.SetText then
        uiPlanterStatusBox.SetText(planterStatusText)
    end
end

function processPlanterAutomation()
    local moduleTable, planterList = collectMyPlanters()
    lastPlanterSnapshot = planterList or {}
    logPlanterAuto("Automation tick: %d planter(s) tracked", planterList and #planterList or 0)
    refreshPlanterStatus(planterList)
    if not planterAutoCollectEnabled or planterHarvestInProgress then
        return
    end
    if not moduleTable or not planterList then
        return
    end
    local useTimerMode = planterHarvestMode == HARVEST_MODE_TIMER
    local threshold = math.clamp(planterCollectThreshold, 10, 100) * 0.01
    local harvestAfterSeconds = math.max(1, math.floor(planterHarvestAfterHours + 0.5)) * 3600
    local nowClock = os.clock()
    for _, planter in ipairs(planterList) do
        local actorId = planter.actorId
        local expiry = actorId and planterHarvestCooldowns[actorId] or nil
        local isCoolingDown = expiry and os.clock() < expiry
        if not isCoolingDown then
            local plantedAt = actorId and planterSeenTimes[actorId] or planter.plantedAt
            local meetsTimer = false
            if useTimerMode and plantedAt then
                meetsTimer = (nowClock - plantedAt) >= harvestAfterSeconds
            end
            local meetsThreshold = planter.growth and planter.growth >= threshold
            local shouldCollect
            if useTimerMode then
                shouldCollect = meetsTimer
                if not shouldCollect and not plantedAt then
                    shouldCollect = meetsThreshold
                end
            else
                shouldCollect = meetsThreshold
            end
            if shouldCollect then
                local matchedSlot = false
                local cycleIndex, slotIndex = findCycleSlotForPlanter(planter)
                if cycleIndex and slotIndex then
                    matchedSlot = true
                    local slotLabel = string.format("C%d-S%d", cycleIndex, slotIndex)
                    task.spawn(function()
                        harvestPlanter(moduleTable, planter, slotLabel)
                    end)
                    return
                end
                if not matchedSlot then
                    task.spawn(function()
                        harvestPlanter(moduleTable, planter, nil)
                    end)
                    return
                end
            end
        end
    end
end

task.spawn(function()
    while true do
        local ok, err = pcall(processPlanterAutomation)
        if not ok then
            warn("[Planter Auto] monitor error:", err)
        end
        task.wait(5)
    end
end)

function getFirstSelection(list)
    if type(list) ~= "table" then return nil end
    return list[1]
end

function collectAllStickers()
    if stickersOnCooldown then
        notify("Find Stickers", "You already collected stickers. Please wait before trying again.", 4)
        return
    end

    local folder = Workspace:FindFirstChild("HiddenStickers")
    if not folder then
        notify("Find Stickers", "HiddenStickers folder not found.", 4)
        return
    end

    local collected = 0
    for _, inst in ipairs(folder:GetDescendants()) do
        if inst:IsA("ClickDetector") then
            collected += 1
            task.spawn(function()
                pcall(function() fireclickdetector(inst) end)
            end)
        end
    end

    notify("Find Stickers", string.format("Triggered %d stickers.", collected), 5)
    stickersOnCooldown = true
    task.delay(5, function()
        notify("Find Stickers", "Daily sticker limit may apply. If it fails, wait until tomorrow.", 6)
    end)
    task.delay(STICKER_COOLDOWN_SECONDS, function()
        stickersOnCooldown = false
        notify("Find Stickers", "Sticker cooldown finished. You can try again.", 4)
    end)
end

local PROMO_CODES = {
    "Octobersmas", "15MMembers", "38217", "BeesBuzz123", "ClubBean",
    "Bopmaster", "Connoisseur", "Crawlers", "Nectar", "Roof", "Wax"
}

function redeemAllCodes()
    local events = ReplicatedStorage:FindFirstChild("Events")
    local promoEvent = events and events:FindFirstChild("PromoCodeEvent")
    if not promoEvent then
        notify("Redeem Codes", "PromoCodeEvent not found.", 4)
        return
    end

    for _, code in ipairs(PROMO_CODES) do
        pcall(function()
            promoEvent:FireServer(code)
        end)
        task.wait(1)
    end

    notify("Redeem Codes", "Attempted to redeem all codes.", 5)
end

uiObjects.farmFieldDropdown = AutoFarmSection:AddDropdownToggle({
    Title = "Auto Farm (Field + Enable)",
    Items = fieldNames,
    DefaultToggle = false,
    SaveKey = "farm_field_toggle_select",
    Searchable = true,
    Callback = function(selectedFieldName, enabled)
        if selectedFieldName then
            setFieldSelection(selectedFieldName)
        end
        setAutoFarmEnabled(enabled and true or false)
    end
})

do
    local saved = Library:GetSettings("farm_field_toggle_select")
    local savedSelection
    local savedToggle = false
    if type(saved) == "table" then
        if type(saved.selection) == "string" then
            savedSelection = saved.selection
        elseif type(saved.item) == "string" then
            savedSelection = saved.item
        elseif type(saved.selections) == "table" then
            if #saved.selections > 0 then
                savedSelection = saved.selections[1]
            else
                for name, flag in pairs(saved.selections) do
                    if flag and type(name) == "string" then
                        savedSelection = name
                        break
                    end
                end
            end
        end
        if saved.toggled ~= nil then
            savedToggle = saved.toggled and true or false
        end
    elseif type(saved) == "string" then
        savedSelection = saved
    end
    if savedSelection then
        pcall(function() setFieldSelection(savedSelection) end)
    end
    if savedToggle then
        pcall(function() setAutoFarmEnabled(true) end)
    end
end

AutoFarmSection:AddMultiDropdownToggle({
    Title = "Ignore Tokens",
    Items = TOKEN_IGNORE_OPTIONS,
    DefaultToggle = ignoreTokensEnabled,
    SaveKey = IGNORE_TOKEN_SAVE_KEY,
    Searchable = true,
    Callback = function(isEnabled, selections)
        ignoreTokensEnabled = isEnabled and true or false
        ignoreSelectionList = selections or {}
        if ignoreTokensEnabled then
            setIgnoredTokens(ignoreSelectionList)
        else
            resetTable(ignoredTokenMap)
        end
        logIgnoreStatus()
    end
})

AutoFarmSection:AddMultiDropdownToggle({
    Title = "Hold Duped Tokens",
    Items = TOKEN_IGNORE_OPTIONS,
    DefaultToggle = holdDupedTokensEnabled,
    SaveKey = HOLD_DUPED_TOKEN_SAVE_KEY,
    Searchable = true,
    HelpText = "Select which Duped ability tokens to stand under. Leave the list empty to target all duped tokens.",
    Callback = function(isEnabled, selections)
        holdDupedTokensEnabled = isEnabled and true or false
        setDupedTokenSelections(selections or {})
        if not holdDupedTokensEnabled then
            dupedTokenTarget = nil
            dupedTokenTargetName = nil
            dupedTokenTargetId = nil
            dupedTokenHoldUntil = 0
        end
        logDupedHoldStatus()
    end
})

AutoFarmSection:AddToggle({
    Title = "Stand Under Falling Star",
    Default = false,
    SaveKey = "farm_stand_under_star",
    Callback = function(state)
        standUnderFallingStarEnabled = state and true or false
        if not standUnderFallingStarEnabled then
            starTarget = nil
            starHoldUntil = 0
        end
    end
})

AutoFarmSection:AddToggle({
    Title = "Stand Under Falling Coconut",
    Default = false,
    SaveKey = "farm_stand_under_coconut",
    Callback = function(state)
        standUnderCoconutEnabled = state and true or false
        if not standUnderCoconutEnabled then
            coconutTarget = nil
            coconutHoldUntil = 0
            coconutApproachTime = 0
        end
    end
})

AutoFarmSection:AddToggle({
    Title = "Walk Through Precise Marks",
    Default = false,
    SaveKey = "farm_precise_marks",
    HelpText = "Follows Precise Bee crosshair markers and walks through them.",
    Callback = function(state)
        standThroughPreciseBeeEnabled = state and true or false
        if not standThroughPreciseBeeEnabled then
            preciseTarget = nil
        end
    end
})

AutoFarmSection:AddToggle({
    Title = "Pick Up Bubbles",
    Default = false,
    SaveKey = "farm_pickup_bubbles",
    HelpText = "Treat field bubbles as tokens and path through them (lower priority than stars/coconuts).",
    Callback = function(state)
        pickUpBubblesEnabled = state and true or false
        if not pickUpBubblesEnabled then
            bubbleTarget = nil
        end
    end
})

AutoFarmSection:AddToggle({
    Title = "Pick Up Fuzzy Particles",
    Default = false,
    SaveKey = "farm_pickup_fuzzy",
    HelpText = "Walks to DustBunnyInstance fuzzy particles (Fuzzy Bee spawns) when no tokens are available.",
    Callback = function(state)
        pickUpFuzzyEnabled = state and true or false
        if not pickUpFuzzyEnabled then
            fuzzyTarget = nil
        end
    end
})

AutoFarmSection:AddToggle({
    Title = "Auto Dispense Honey",
    Default = true,
    SaveKey = "farm_auto_dispense",
    Callback = function(state)
        isAutoDispenseEnabled = state and true or false
    end
})

AutoFarmSection:AddSliderToggle({
    Title = "Balloon Blessing Hold (x)",
    DefaultToggle = false,
    Min = 0,
    Max = 50,
    Default = balloonBlessingThreshold,
    SaveKey = "farm_balloon_blessing_hold",
    HelpText = "If enabled and your Balloon Blessing is at or above this value when conversion starts, Auto Dispense will keep converting until your hive balloon disappears.",
    OnToggleChange = function(state)
        balloonBlessingHoldEnabled = state and true or false
    end,
    OnSliderChange = function(value)
        local numberValue = tonumber(value)
        if numberValue then
            balloonBlessingThreshold = math.max(0, numberValue)
        end
    end
})

AutoFarmSection:AddToggle({
    Title = "Stats Panel",
    Default = false,
    SaveKey = "farm_stats_panel",
    Callback = function(state)
        isStatsPanelEnabled = state
        if state then
            createStatsPanel()
        else
            destroyStatsPanel()
        end
    end
})

AutoFarmSection:AddToggle({
    Title = "Buff-Aware Farming",
    Default = true, -- Turning this ON by default since the dynamic scoring is now implemented
    SaveKey = "farm_buff_aware_enabled",
    HelpText = "Dynamically prioritizes tokens for missing/low multiplier buffs (e.g. Inspire, Baby Love).",
    Callback = function(state)
        isBuffAwareEnabled = state
        if state then
            notify("Buff-Aware Farming", "Dynamic scoring enabled for critical buffs (Inspire, Baby Love, Focus).", 5)
        end
    end
})

function rebuildFieldRouteLabel()
    return
end

function stopFieldRoute()
    fieldRouteEnabled = false
    if fieldRouteThread then
        if hasTaskCancel then
            pcall(function()
                task.cancel(fieldRouteThread)
            end)
        end
        fieldRouteThread = nil
    end
end

function startFieldRoute()
    if fieldRouteThread or #fieldRoute == 0 then
        if uiObjects.fieldRouteToggle and uiObjects.fieldRouteToggle.SetState then
            local success, err = pcall(function()
                uiObjects.fieldRouteToggle:SetState(false)
            end)
            if not success then
                warn("Error in startFieldRoute: " .. tostring(err))
            end
        end
        return
    end

    fieldRouteEnabled = true
    fieldRouteThread = task.spawn(function()
        local index = 1
        while fieldRouteEnabled and #fieldRoute > 0 do
            local step = fieldRoute[index]
            if not step then
                index = 1
                step = fieldRoute[index]
            end
            local farmSelectedField = step.Field
            
            setFieldSelection(farmSelectedField)
            
            local fieldPart = fieldObjects[step.Field]
            if fieldPart and LocalPlayer.Character and LocalPlayer.Character.PrimaryPart then
                pcall(function()
                    teleportCharacterToCFrame(fieldPart.CFrame + Vector3.new(0, 5, 0))
                end)
            end
            
            local elapsed = 0
            local duration = math.max(5, math.floor(step.Duration or fieldRouteStepDuration))
            
            while fieldRouteEnabled and elapsed < duration do
                task.wait(1)
                elapsed = elapsed + 1
            end
            
            index = index + 1
            if index > #fieldRoute then
                index = 1
            end
        end
        
        fieldRouteThread = nil
        fieldRouteEnabled = false
        if uiObjects.fieldRouteToggle and uiObjects.fieldRouteToggle.SetState then
            pcall(function()
                uiObjects.fieldRouteToggle:SetState(false)
            end)
        end
    end)
end

function removeLastRouteStep()
    if #fieldRoute > 0 then
        fieldRoute[#fieldRoute] = nil
        rebuildFieldRouteLabel()
    end
end

function clearFieldRoute()
    for i = #fieldRoute, 1, -1 do
        fieldRoute[i] = nil
    end
    rebuildFieldRouteLabel()
end

local FieldRouteSection = FarmingPage:AddSection({
    Title = "Field Route Manager",
    Icon = "rbxassetid://110882457725395",
    HelpText = "Queue fields and automatically cycle between them.",
    Column = 2
})

uiObjects.fieldRouteDropdown = FieldRouteSection:AddDropdown({
    Title = "Field Step",
    Items = fieldNames,
    Default = 1,
    Searchable = true,
    Callback = function(name)
        fieldRouteSelectedField = name
    end
})

uiObjects.fieldRouteDuration = FieldRouteSection:AddSlider({
    Title = "Step Duration (seconds)",
    Min = 10,
    Max = 600,
    Default = fieldRouteStepDuration,
    Decimals = 0,
    Callback = function(value)
        local numberValue = tonumber(value)
        if numberValue then
            fieldRouteStepDuration = math.max(10, math.floor(numberValue))
        end
    end
})

FieldRouteSection:AddButton({
    Title = "Add Step",
    Callback = function()
        local fieldName = fieldRouteSelectedField or fieldNames[1]
        if not fieldName then
            notify("Field Route", "No field selected.", 3)
            return
        end
        table.insert(fieldRoute, {
            Field = fieldName,
            Duration = math.max(5, math.floor(fieldRouteStepDuration)),
        })
        rebuildFieldRouteLabel()
    end
})

FieldRouteSection:AddButton({
    Title = "Remove Last Step",
    Callback = function()
        removeLastRouteStep()
    end
})

FieldRouteSection:AddButton({
    Title = "Clear Route",
    Callback = function()
        clearFieldRoute()
    end
})

uiObjects.fieldRouteToggle = FieldRouteSection:AddToggle({
    Title = "Enable Route Loop",
    Default = false,
    Callback = function(state)
        if state then
            if #fieldRoute == 0 then
                notify("Field Route", "Add at least one step before enabling.", 4)
                uiObjects.fieldRouteToggle:SetState(false)
                return
            end
            startFieldRoute()
        else
            stopFieldRoute()
        end
    end
})

local PlanterAutomationSection = PlantersPage:AddSection({
    Title = "Planter Configuration",
    Icon = "rbxassetid://7830488573",
    HelpText = "Configure up to three planter slots and enable automatic harvesting.",
    Column = 1
})

uiObjects.planterAutoToggle = PlanterAutomationSection:AddToggle({
    Title = "Auto Collect Planters",
    Default = planterAutoCollectEnabled,
    SaveKey = "planter_auto_collect_enabled",
    Callback = function(state)
        planterAutoCollectEnabled = state and true or false
    end
})

uiObjects.planterAutoPlaceToggle = PlanterAutomationSection:AddToggle({
    Title = "Auto Place Planters",
    Default = planterAutoPlaceEnabled,
    SaveKey = "planter_auto_place_enabled",
    Callback = function(state)
        if autoplaceToggleProgrammatic then
            return
        end
        planterAutoPlaceEnabled = state and true or false
        if planterAutoPlaceEnabled then
            runAutoPlaceOnce()
        else
            cancelAutoPlace()
        end
    end
})

uiObjects.planterCycleDropdown = PlanterAutomationSection:AddDropdown({
    Title = "Next Cycle (Auto Place)",
    Items = planterCycleLabels,
    Default = planterCycleNextIndex,
    SaveKey = "planter_cycle_next_index",
    Callback = function(value, index)
        if planterCycleDropdownProgrammatic then
            return
        end
        local newIndex = index
        if type(newIndex) ~= "number" then
            newIndex = table.find(planterCycleLabels, value) or planterCycleNextIndex
        end
        setNextPlanterCycle(newIndex)
    end
})
syncPlanterCycleDropdown()

uiObjects.planterThreshold = PlanterAutomationSection:AddSlider({
    Title = "Collect Threshold (%)",
    Min = 10,
    Max = 100,
    Default = math.clamp(planterCollectThreshold, 10, 100),
    SaveKey = "planter_collect_threshold",
    Callback = function(value)
        local numberValue = tonumber(value)
        if numberValue then
            planterCollectThreshold = math.clamp(math.floor(numberValue + 0.5), 10, 100)
        end
    end
})

local harvestModeLabels = {}
for _, option in ipairs(harvestModeOptions) do
    table.insert(harvestModeLabels, option.label)
end
uiObjects.planterHarvestMode = PlanterAutomationSection:AddDropdown({
    Title = "Harvest Mode",
    Items = harvestModeLabels,
    Default = harvestModeLookup[planterHarvestMode] or 1,
    SaveKey = "planter_harvest_mode",
    Callback = function(value, index)
        local newIndex = index
        if type(newIndex) ~= "number" then
            newIndex = table.find(harvestModeLabels, value) or harvestModeLookup[planterHarvestMode] or 1
        end
        local option = harvestModeOptions[newIndex]
        planterHarvestMode = option and option.value or HARVEST_MODE_PERCENT
    end
})

uiObjects.planterHarvestAfterHours = PlanterAutomationSection:AddSlider({
    Title = "Harvest After (hours)",
    Min = 1,
    Max = 12,
    Default = math.clamp(math.floor(planterHarvestAfterHours + 0.5), 1, 12),
    SaveKey = "planter_collect_after_hours",
    Callback = function(value)
        local numberValue = tonumber(value)
        if numberValue then
            planterHarvestAfterHours = math.clamp(math.floor(numberValue + 0.5), 1, 12)
        end
    end
})

uiObjects.planterHarvestDelay = PlanterAutomationSection:AddSlider({
    Title = "Stay On Field (seconds)",
    Min = 5,
    Max = 60,
    Default = math.clamp(planterHarvestWindow, 5, 60),
    SaveKey = "planter_collect_window",
    Callback = function(value)
        local numberValue = tonumber(value)
        if numberValue then
            planterHarvestWindow = math.max(5, math.floor(numberValue + 0.5))
        end
    end
})

uiObjects.planterReplantDelay = PlanterAutomationSection:AddSlider({
    Title = "Replant Delay (seconds)",
    Min = 3,
    Max = 30,
    Default = math.clamp(planterPlaceDelaySeconds, 3, 30),
    SaveKey = "planter_place_delay",
    Callback = function(value)
        local numberValue = tonumber(value)
        if numberValue then
            planterPlaceDelaySeconds = math.max(3, math.floor(numberValue + 0.5))
        end
    end
})

uiPlanterStatusBox = PlanterAutomationSection:AddInputBox({
    Title = "Active Planters",
    Placeholder = "No planters detected"
})
uiPlanterStatusBox.Object.TextEditable = false
uiPlanterStatusBox.Object.ClearTextOnFocus = false
uiPlanterStatusBox.SetText(planterStatusText)

PlanterAutomationSection:AddButton({
    Title = "Refresh Snapshot",
    Callback = function()
        local _, planters = collectMyPlanters()
        refreshPlanterStatus(planters)
    end
})

local PlanterCycleSections = {}
for cycleIndex = 1, PLANER_CYCLE_COUNT do
    PlanterCycleSections[cycleIndex] = PlantersPage:AddSection({
        Title = string.format("Cycle %d Planters", cycleIndex),
        Icon = "rbxassetid://7704357727",
        HelpText = "Configure planter + field pairs planted during this cycle.",
        Column = 2
    })

    for slotIndex = 1, PLANER_SLOT_COUNT do
        local slot = getCycleSlot(cycleIndex, slotIndex)
        PlanterCycleSections[cycleIndex]:AddDropdown({
            Title = string.format("Slot %d Planter", slotIndex),
            Items = planterDropdownItems,
            Default = dropdownIndexForValue(planterDropdownItems, slot.planter),
            SaveKey = ("planter_cycle_%d_slot_%d_planter"):format(cycleIndex, slotIndex),
            Searchable = true,
            Callback = function(value)
                updateSlotValue(cycleIndex, slotIndex, "planter", value)
            end
        })

        PlanterCycleSections[cycleIndex]:AddDropdown({
            Title = string.format("Slot %d Field", slotIndex),
            Items = planterFieldOptions,
            Default = dropdownIndexForValue(planterFieldOptions, slot.field),
            SaveKey = ("planter_cycle_%d_slot_%d_field"):format(cycleIndex, slotIndex),
            Searchable = true,
            Callback = function(value)
                updateSlotValue(cycleIndex, slotIndex, "field", value or ANY_FIELD_VALUE)
            end
        })

        PlanterCycleSections[cycleIndex]:AddToggle({
            Title = string.format("Slot %d Timed Harvest", slotIndex),
            Default = slot.timer,
            SaveKey = ("planter_cycle_%d_slot_%d_timer"):format(cycleIndex, slotIndex),
            Callback = function(state)
                updateSlotValue(cycleIndex, slotIndex, "timer", state and true or false)
            end
        })

        PlanterCycleSections[cycleIndex]:AddButton({
            Title = string.format("Teleport To Slot %d Field", slotIndex),
            Callback = function()
                local slotData = getCycleSlot(cycleIndex, slotIndex)
                local fieldName = slotData.field
                if not fieldName or fieldName == "" or fieldName == ANY_FIELD_VALUE then
                    notify("Planter Slot", "Select a specific field before teleporting.", 4)
                    return
                end
                local fieldPart = fieldObjects[fieldName]
                if not fieldPart then
                    notify("Planter Slot", "Field part missing: " .. tostring(fieldName), 4)
                    return
                end
                teleportCharacterToCFrame(fieldPart.CFrame + Vector3.new(0, 5, 0))
            end
        })
    end
end

function getNpcTarget(name)
    local target = npcTargets[name]
    if target and target.Parent then
        return target
    end
    local folders = { Workspace:FindFirstChild("NPCs"), Workspace:FindFirstChild("NPCBees") }
    for _, folder in ipairs(folders) do
        local npc = folder and folder:FindFirstChild(name)
        if npc then
            local part = findFirstBasePart(npc)
            if part then
                npcTargets[name] = part
                return part
            end
        end
    end
    return nil
end

function getShopTarget(name)
    local target = shopTargets[name]
    if target and target.Parent then
        return target
    end
    local shopsFolder = Workspace:FindFirstChild("Shops")
    if not shopsFolder then
        return nil
    end
    local shop = shopsFolder:FindFirstChild(name)
    if not shop then
        return nil
    end
    local part = findFirstBasePart(shop)
    if part then
        shopTargets[name] = part
    end
    return part
end

local TeleportSection = TeleportPage:AddSection({ Title = "Teleports", Icon = "rbxassetid://6634488405" })

TeleportSection:AddDropdown({
    Title = "Teleport To Field",
    Items = fieldNames,
    Searchable = true,
    -- SaveKey removed to prevent saving
    Callback = function(name)
        local field = fieldObjects[name]
        if field then
            teleportCharacterToCFrame(field.CFrame + Vector3.new(0, 5, 0))
        end
    end
})

TeleportSection:AddDropdown({
    Title = "Teleport To NPC",
    Items = npcNames,
    Searchable = true,
    -- SaveKey removed to prevent saving
    Callback = function(name)
        local target = getNpcTarget(name)
        if target then
            teleportCharacterToCFrame(CFrame.new(target.Position + Vector3.new(0, 5, 0)))
        end
    end
})

TeleportSection:AddDropdown({
    Title = "Teleport To Player",
    Items = playerDropdownItems,
    Searchable = true,
    -- SaveKey removed to prevent saving
    Callback = function(name)
        local targetPlayer = Players:FindFirstChild(name)
        local character = targetPlayer and targetPlayer.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if root then
            teleportCharacterToCFrame(root.CFrame + Vector3.new(0, 5, 0))
        end
    end
})

TeleportSection:AddDropdown({
    Title = "Teleport To Shop",
    Items = shopNames,
    Searchable = true,
    -- SaveKey removed to prevent saving
    Callback = function(name)
        local target = getShopTarget(name)
        if target then
            teleportCharacterToCFrame(target.CFrame + Vector3.new(0, 5, 0))
        end
    end
})

local ExtraSection = FarmingPage:AddSection({
    Title = "Extra Automation",
    Icon = "rbxassetid://132944044601566",
    HelpText = "Miscellaneous automation like item buffs and gumdrops.",
    Column = 3,
})

ExtraSection:AddToggle({
    Title = "Auto Item Buffs",
    Default = false,
    SaveKey = "helper_auto_item_buffs",
    Callback = function(enabled)
        PlayerESP:SetAutoItemBuffs(enabled)
    end
})

uiObjects.autoDig = ExtraSection:AddToggle({
    Title = "Auto Dig",
    Default = false,
    SaveKey = "auto_dig_enabled",
    HelpText = "Toggle allows manual digging when Auto Farm is off.",
    Callback = function(enabled)
        PlayerESP:SetAutoDigManual(enabled, isAutoFarmEnabled)
    end
})

function createActiveToggle(title, saveKey, interval, activeName)
    ExtraSection:AddToggle({
        Title = title,
        Default = false,
        SaveKey = saveKey,
        Callback = function(enabled)
            PlayerESP:SetAutoActive(enabled, interval, activeName)
        end
    })
end

createActiveToggle("Auto Gumdrops", "helper_auto_gumdrops", 2, "Gumdrops")
createActiveToggle("Auto Glitter", "helper_auto_glitter", 920, "Glitter")
createActiveToggle("Auto Coconut", "helper_auto_coconut", 11, "Coconut")
createActiveToggle("Auto Stinger", "helper_auto_stinger", 30, "Stinger")
createActiveToggle("Auto Magic Bean", "helper_auto_magic_bean", 0.3, "Magic Bean")

uiObjects.autoSprinkler = ExtraSection:AddToggle({
    Title = "Auto Sprinkler",
    Default = false,
    SaveKey = "auto_sprinkler_enabled",
    Callback = function(enabled)
        PlayerESP:SetAutoSprinkler(enabled)
    end,
})

uiObjects.autoMemoryMatch = ExtraSection:AddToggle({
    Title = "Auto Memory Match",
    Default = false,
    SaveKey = "helper_auto_memory_match",
    HelpText = "Automatically flips and matches tiles in Memory Match when the game UI is open.",
    Callback = function(enabled)
        autoMemoryMatchEnabled = enabled and true or false
        if autoMemoryMatchEnabled then
            startAutoMemoryMatch()
        else
            stopAutoMemoryMatch()
        end
    end
})

local espSection = VisualsPage:AddSection({
    Title = "Player ESP",
    Icon = "rbxassetid://132944044601566",
    HelpText = "Visual assistance features.",
})

uiObjects.boxEspToggle = espSection:AddToggle({
    Title = "Box ESP",
    Default = false,
    SaveKey = "box_esp_enabled",
    Callback = function(v)
        PlayerESP:SetBoxEsp(v)
    end,
})

uiObjects.healthEspToggle = espSection:AddToggle({
    Title = "Health ESP",
    Default = false,
    SaveKey = "health_esp_enabled",
    Callback = function(value)
        PlayerESP:SetHealthEsp(value)
    end,
})

uiObjects.tracersToggle = espSection:AddToggle({
    Title = "Tracers",
    Default = false,
    SaveKey = "tracers_enabled",
    Callback = function(value)
        PlayerESP:SetTracers(value)
    end,
})

uiObjects.teamCheckToggle = espSection:AddToggle({
    Title = "Team Check",
    Default = false,
    SaveKey = "team_check_enabled",
    Callback = function(value)
        PlayerESP:SetTeamCheck(value)
    end,
})

uiObjects.teamColorToggle = espSection:AddToggle({
    Title = "Team Color",
    Default = true,
    SaveKey = "team_color_enabled",
    Callback = function(value)
        PlayerESP:SetTeamColor(value)
    end,
})

uiObjects.skeletonEspToggle = espSection:AddToggle({
    Title = "Skeleton ESP",
    Default = false,
    SaveKey = "skeleton_esp_enabled",
    Callback = function(value)
        PlayerESP:SetSkeletonEsp(value)
    end,
})

uiObjects.nameEspToggle = espSection:AddToggle({
    Title = "Name ESP",
    Default = false,
    SaveKey = "name_esp_enabled",
    Callback = function(value)
        PlayerESP:SetNameEsp(value)
    end,
})

uiObjects.hotbarEspToggle = espSection:AddToggle({
    Title = "Hotbar ESP",
    Default = false,
    SaveKey = "hotbar_esp_enabled",
    Callback = function(value)
        PlayerESP:SetHotbarEsp(value)
        if value then
            local ctrl = uiObjects.hotbarDisplay
            if ctrl and ctrl.SetState then
                pcall(function()
                    if ctrl.SetSelected then
                        ctrl:SetSelected("Text", true)
                    end
                    if ctrl.Select then
                        ctrl:Select("Text", true)
                    end
                    if ctrl.SetValues then
                        ctrl:SetValues({ "Text" })
                    end
                    if ctrl.Set then
                        ctrl:Set({ "Text" })
                    end
                end)
            end
        end
    end,
})

uiObjects.hotbarDisplay = espSection:AddMultiDropdown({
    Title = "Hotbar Display",
    Items = { "Image", "Text" },
    SaveKey = "hotbar_display_types",
    Callback = function(list)
        PlayerESP:SetHotbarDisplay(list)
    end,
})

local gameEspSection = VisualsPage:AddSection({
    Title = "Game ESP",
    Icon = "rbxassetid://132944044601566",
    HelpText = "World and game ESP.",
})

uiObjects.sproutEspToggle = gameEspSection:AddToggle({
    Title = "Sprout ESP",
    Default = false,
    SaveKey = "sprout_esp_enabled",
    Callback = function(v)
        sproutEspEnabled = v and true or false
    end,
})

local monsterSpawnerEspEnabled = false
uiObjects.monsterSpawnerEspToggle = gameEspSection:AddToggle({
    Title = "Monsters Spawners ESP",
    Default = false,
    SaveKey = "monster_spawner_esp_enabled",
    Callback = function(v)
        monsterSpawnerEspEnabled = v and true or false
    end,
})

worldVisualsSection = VisualsPage:AddSection({
    Title = "World Visuals",
    Icon = "rbxassetid://4483345998",
    HelpText = "Visual tweaks that only affect your local client.",
    Column = 2,
})

worldVisualsSection:AddToggle({
    Title = "Better Graphics",
    Default = false,
    SaveKey = "misc_better_graphics",
    Callback = function(state)
        setBetterGraphics(state)
    end
})

worldVisualsSection:AddToggle({
    Title = "Fullbright",
    Default = false,
    SaveKey = "visual_fullbright",
    Callback = function(state)
        setFullbright(state)
    end,
})

worldVisualsSection:AddToggle({
    Title = "Custom Time",
    Default = false,
    SaveKey = "visual_custom_time_enabled",
    Callback = function(state)
        setCustomTimeEnabled(state)
    end,
})

worldVisualsSection:AddSlider({
    Title = "Time Of Day",
    Min = 0,
    Max = 24,
    Default = visualState.customTimeValue,
    Decimals = 1,
    SaveKey = "visual_custom_time_value",
    Callback = function(value)
        setCustomTimeValue(value)
    end,
})

RewardsSection = PlayerPage:AddSection({
    Title = "Rewards & Codes",
    Icon = "rbxassetid://4483345998",
    HelpText = "One-click sticker collection, promo codes, and masks.",
    Column = 2,
})

RewardsSection:AddButton({
    Title = "Find All Stickers",
    Callback = function()
        collectAllStickers()
    end
})

RewardsSection:AddButton({
    Title = "Redeem All Codes",
    Callback = function()
        redeemAllCodes()
    end
})

MASK_OPTIONS = {
    "Gummy Mask",
    "Demon Mask",
    "Diamond Mask",
    "Bubble Mask",
    "Fire Mask",
    "Honey Mask"
}

function equipMask(maskName)
    if type(maskName) ~= "string" then return end
    local events = ReplicatedStorage:FindFirstChild("Events")
    local packageEvent = events and events:FindFirstChild("ItemPackageEvent")
    if not packageEvent then
        notify("Equip Mask", "ItemPackageEvent not found.", 4)
        return
    end

    local payload = {
        Mute = true,
        Type = maskName,
        Category = "Accessory"
    }
    pcall(function()
        packageEvent:InvokeServer("Equip", payload)
    end)
    notify("Equip Mask", "Attempted to equip " .. maskName .. ".", 3)
end

RewardsSection:AddDropdown({
    Title = "Equip Mask",
    Items = MASK_OPTIONS,
    Default = 1,
    SaveKey = "misc_mask_selection",
    Callback = function(choice)
        equipMask(choice)
    end
})

UtilitySection = PlayerPage:AddSection({
    Title = "Utility",
    Icon = "rbxassetid://133154037851337",
    HelpText = "Quality-of-life helpers that keep the session active.",
    Column = 2,
})

UtilitySection:AddToggle({
    Title = "Anti AFK",
    Default = false,
    SaveKey = "misc_anti_afk",
    Callback = function(state)
        setAntiAfk(state)
    end
})

uiObjects.autoClaimHiveToggle = UtilitySection:AddToggle({
    Title = "Auto Claim Hive",
    Default = false,
    SaveKey = "misc_auto_claim_hive",
    Callback = function(state)
        isAutoClaimHiveEnabled = state
        if state then
            doAutoClaimHive()
        end
    end
})

UtilitySection:AddButton({
    Title = "Create & Copy Backend Key",
    Callback = function()
        createBackendKeyAndCopy()
    end
})

-- Define the actual cutoff distance based on estimated token/player size (in studs)
-- Player HRP Radius (~1 stud) + Token Avg Radius (~1 stud) + 0.5 stud buffer for guaranteed overlap
TOKEN_PICKUP_CUTOFF = 2.5 

-- -------------------------------------------------------------------------------------
-- Remote control sync (website <-> in-game UI) over HTTP (no websocket)
-- -------------------------------------------------------------------------------------
REMOTE_POLL_INTERVAL = 5
REMOTE_PUSH_FAILS = 0
REMOTE_BACKOFF_UNTIL = 0
remoteErrorCount = 0
remoteErrorCooldownUntil = 0
lastStateJson = nil

remoteControlSchema = {
    windowTitle = "Unknown Hub",
    pages = {
        {
            title = "PLAYER",
            sections = {
                {
                    title = "Movement",
                    controls = {
                        { key = "player_speed_control", title = "Custom WalkSpeed", type = "sliderToggle", defaultValue = currentSpeed, min = 16, max = 300 },
                        { key = "player_jump_control", title = "Custom JumpPower", type = "sliderToggle", defaultValue = currentJump, min = 50, max = 500 },
                        { key = "player_noclip_enabled", title = "Enable Noclip", type = "toggle" },
                    }
                }
            }
        },
        {
            title = "FARMING",
            sections = {
                {
                    title = "Auto Farm",
                    controls = {
                        { key = "farm_field_toggle_select", title = "Auto Farm (Field + Enable)", type = "dropdownToggle", options = fieldNames },
                        { key = IGNORE_TOKEN_SAVE_KEY, title = "Ignore Tokens", type = "multiSelectToggle", options = TOKEN_IGNORE_OPTIONS },
                        { key = "farm_stand_under_star", title = "Stand Under Falling Star", type = "toggle" },
                        { key = "farm_stand_under_coconut", title = "Stand Under Falling Coconut", type = "toggle" },
                        { key = "farm_precise_marks", title = "Walk Through Precise Marks", type = "toggle" },
                        { key = "farm_pickup_bubbles", title = "Pick Up Bubbles", type = "toggle" },
                        { key = "farm_auto_dispense", title = "Auto Dispense Honey", type = "toggle" },
                        { key = "farm_stats_panel", title = "Stats Panel", type = "toggle" },
                        { key = "farm_buff_aware_enabled", title = "Buff-Aware Farming", type = "toggle" },
                    }
                }
            }
        },
        {
            title = "VISUALS",
            sections = {
                {
                    title = "Automation",
                    controls = {
                        { key = "helper_auto_item_buffs", title = "Auto Item Buffs", type = "toggle" },
                        { key = "auto_dig_enabled", title = "Auto Dig", type = "toggle" },
                        { key = "helper_auto_gumdrops", title = "Auto Gumdrops", type = "toggle" },
                        { key = "helper_auto_glitter", title = "Auto Glitter", type = "toggle" },
                        { key = "helper_auto_coconut", title = "Auto Coconut", type = "toggle" },
                        { key = "helper_auto_stinger", title = "Auto Stinger", type = "toggle" },
                        { key = "helper_auto_magic_bean", title = "Auto Magic Bean", type = "toggle" },
                        { key = "auto_sprinkler_enabled", title = "Auto Sprinkler", type = "toggle" },
                        { key = "helper_auto_memory_match", title = "Auto Memory Match", type = "toggle" },
                    }
                }
            }
        }
    }
}

remoteControlLookup = {}
for _, page in ipairs(remoteControlSchema.pages) do
    for _, section in ipairs(page.sections) do
        for _, ctrl in ipairs(section.controls) do
            remoteControlLookup[ctrl.key] = ctrl
        end
    end
end

function normalizeSelectionList(raw)
    local list = {}
    if type(raw) ~= "table" then
        if raw ~= nil then
            table.insert(list, raw)
        end
        return list
    end
    if #raw > 0 then
        for _, v in ipairs(raw) do
            if v ~= nil then
                table.insert(list, v)
            end
        end
        return list
    end
    for name, flag in pairs(raw) do
        if flag then
            table.insert(list, name)
        end
    end
    return list
end

function getRemoteControlState(ctrl)
    if not ctrl or not ctrl.key then return nil end
    local widget = Library._widgetRegistry and Library._widgetRegistry[ctrl.key]
    local state = Library:GetSettings(ctrl.key) or Library:_GetSetting(ctrl.key, nil)
    if ctrl.type == "multiSelectToggle" then
        local toggled = false
        local selections = {}
        if type(state) == "table" then
            if state.toggled ~= nil then
                toggled = state.toggled and true or false
            end
            selections = normalizeSelectionList(state.selections or state.selected or state)
        elseif widget and widget.GetSelections then
            selections = widget.GetSelections()
            if widget.GetToggleState then
                toggled = widget:GetToggleState() and true or false
            end
        end
        return { toggled = toggled, selections = selections }
    elseif ctrl.type == "sliderToggle" then
        local value = ctrl.defaultValue or 0
        local toggled = false
        if type(state) == "table" then
            if state.value ~= nil then
                value = tonumber(state.value) or value
            end
            if state.toggled ~= nil then
                toggled = state.toggled and true or false
            end
        elseif type(state) == "number" then
            value = state
        elseif widget and widget.GetSliderValue then
            value = widget:GetSliderValue()
            if widget.GetToggleState then toggled = widget:GetToggleState() and true or false end
        end
        return { value = value, toggled = toggled }
    elseif ctrl.type == "dropdownToggle" then
        local selection = nil
        local toggled = false
        if type(state) == "table" then
            if state.selection ~= nil then
                selection = state.selection
            elseif state.item ~= nil then
                selection = state.item
            end
            if state.toggled ~= nil then
                toggled = state.toggled and true or false
            end
        elseif type(state) == "string" then
            selection = state
        end
        if widget then
            if widget.GetSelection then
                local ok, sel = pcall(function() return widget:GetSelection() end)
                if ok and sel ~= nil then selection = sel end
            end
            if widget.GetToggleState then
                local ok, tog = pcall(function() return widget:GetToggleState() end)
                if ok and tog ~= nil then toggled = tog and true or false end
            end
        end
        return { selection = selection, toggled = toggled }
    elseif ctrl.type == "toggle" then
        if state ~= nil then
            return state and true or false
        end
        if widget and widget.GetState then
            local ok, val = pcall(function() return widget:GetState() end)
            if ok then return val and true or false end
        end
        return false
    end
    return state
end

function cloneRemoteSchemaWithState()
    local snapshot = { windowTitle = remoteControlSchema.windowTitle, pages = {} }
    for _, page in ipairs(remoteControlSchema.pages) do
        local pageCopy = { title = page.title, sections = {} }
        for _, section in ipairs(page.sections) do
            local secCopy = { title = section.title, controls = {} }
            for _, ctrl in ipairs(section.controls) do
                local ctrlCopy = {
                    key = ctrl.key,
                    title = ctrl.title,
                    type = ctrl.type,
                    options = ctrl.options
                }
                local st = getRemoteControlState(ctrl)
                if st ~= nil then
                    ctrlCopy.state = st
                end
                table.insert(secCopy.controls, ctrlCopy)
            end
            table.insert(pageCopy.sections, secCopy)
        end
        table.insert(snapshot.pages, pageCopy)
    end
    return snapshot
end

function parseBoolean(value)
    if value == nil then
        return nil
    end
    local valType = typeof(value)
    if valType == "boolean" then
        return value
    end
    if valType == "number" then
        return value ~= 0
    end
    if valType == "string" then
        local lowered = string.lower(value)
        if lowered == "true" or lowered == "1" or lowered == "yes" or lowered == "on" then
            return true
        end
        if lowered == "false" or lowered == "0" or lowered == "no" or lowered == "off" then
            return false
        end
        return lowered ~= "" and lowered ~= "nil"
    end
    return value ~= nil
end

local backendReady
local sendRemoteState

backendReady = function()
    return BACKEND_SYNC_ENABLED
        and type(BACKEND_URL) == "string"
        and BACKEND_URL ~= ""
        and type(BACKEND_API_KEY) == "string"
        and BACKEND_API_KEY ~= "replace-with-api-key"
end

sendRemoteState = function(force)
    if not backendReady() then return end
    if tick() < REMOTE_BACKOFF_UNTIL then return end
    local key = ensureBackendUserKey()
    local statePayload = cloneRemoteSchemaWithState()
    local stateJson = HttpService:JSONEncode(statePayload)
    if (not force) and lastStateJson and lastStateJson == stateJson then
        return
    end
    local payload = {
        at = math.floor(os.time()),
        state = statePayload,
    }
    local body = HttpService:JSONEncode(payload)
    local headers = {
        ["Content-Type"] = "application/json",
        ["x-api-key"] = BACKEND_API_KEY,
        ["x-user-key"] = key,
    }
    task.spawn(function()
        local ok, res = pcall(httpRequest, {
            Url = BACKEND_URL .. "/api/controls/state",
            Method = "POST",
            Headers = headers,
            Body = body,
        })
        if not ok then
            remoteErrorCount += 1
            REMOTE_PUSH_FAILS += 1
            if tick() > remoteErrorCooldownUntil then
                warn("[RemoteControl] Failed to push state:", res)
                remoteErrorCooldownUntil = tick() + 10
            end
            if REMOTE_PUSH_FAILS >= 3 then
                REMOTE_BACKOFF_UNTIL = tick() + 15
                warn("[RemoteControl] Backing off 15s after repeated push failures.")
            end
        elseif res and res.StatusCode and res.StatusCode >= 400 then
            remoteErrorCount += 1
            REMOTE_PUSH_FAILS += 1
            if tick() > remoteErrorCooldownUntil then
                warn("[RemoteControl] HTTP " .. tostring(res.StatusCode) .. " pushing state")
                remoteErrorCooldownUntil = tick() + 10
            end
            if REMOTE_PUSH_FAILS >= 3 then
                REMOTE_BACKOFF_UNTIL = tick() + 15
                warn("[RemoteControl] Backing off 15s after HTTP errors.")
            end
        else
            remoteErrorCount = 0
            REMOTE_PUSH_FAILS = 0
            REMOTE_BACKOFF_UNTIL = 0
            lastStateJson = stateJson
        end
    end)
end

function applyRemoteCommand(cmd)
    if type(cmd) ~= "table" then return end
    local key = cmd.key or cmd.saveKey
    if not key then return end
    local ctrl = remoteControlLookup[key]
    if not ctrl then return end
    local payload = nil
    if cmd ~= nil then
        if cmd.value ~= nil then
            payload = cmd.value
        elseif cmd.state ~= nil then
            payload = cmd.state
        else
            payload = cmd
        end
    end

    local function safeSet(saveKey, value)
        local ok, err = pcall(function()
            Library:SetSaveKey(saveKey, value)
            local widget = Library._widgetRegistry and Library._widgetRegistry[saveKey]
            if widget then
                -- Force widget state in case SetSaveKey skipped visuals/callbacks
                if type(value) == "table" then
                    if widget.SetSelection then
                        if value.selections then
                            widget.SetSelection(value.selections)
                        elseif value.selection ~= nil then
                            widget.SetSelection(value.selection)
                        elseif value.item ~= nil then
                            widget.SetSelection(value.item)
                        end
                    end
                    if widget.SetSliderValue and value.value ~= nil then
                        widget.SetSliderValue(value.value)
                    end
                    if widget.SetToggleState and value.toggled ~= nil then
                        widget.SetToggleState(value.toggled)
                    end
                end
                if widget.SetState and type(value) ~= "table" then
                    widget.SetState(value)
                end
                -- Nudge widget callbacks in case SetSaveKey didn't fire them
                if typeof(widget.Call) == "function" then
                    widget.Call(value)
                elseif widget.SetState then
                    widget.SetState(value)
                    if typeof(widget.Call) == "function" then widget.Call(value) end
                elseif widget.SetSliderValue and widget.SetToggleState and type(value) == "table" then
                    if value.value ~= nil then widget.SetSliderValue(value.value) end
                    if value.toggled ~= nil then widget.SetToggleState(value.toggled) end
                    if typeof(widget.Call) == "function" then widget.Call(value.value, value.toggled) end
                elseif widget.SetSelection and widget.SetToggleState and type(value) == "table" then
                    local setArg = value.selections or value.selection or value.item
                    if setArg ~= nil then
                        widget.SetSelection(setArg)
                    end
                    if value.toggled ~= nil then widget.SetToggleState(value.toggled) end
                    if typeof(widget.Call) == "function" then widget.Call(setArg, value.toggled) end
                end
            end
        end)
        if not ok then
            warn("[RemoteControl] Failed to apply key", saveKey, "err:", err)
        end
    end

    if ctrl.type == "toggle" then
        local boolValue = nil
        if type(payload) == "table" then
            boolValue = parseBoolean(payload.enabled)
            if boolValue == nil then boolValue = parseBoolean(payload.state) end
            if boolValue == nil then boolValue = parseBoolean(payload.value) end
            if boolValue == nil then boolValue = parseBoolean(payload.toggled) end
        else
            boolValue = parseBoolean(payload)
        end
        if boolValue == nil then
            boolValue = false
        end
        safeSet(key, boolValue)
        warn(string.format("[RemoteControl] Applied toggle %s -> %s", key, tostring(boolValue)))
    elseif ctrl.type == "sliderToggle" then
        local value = 0
        local toggled = nil
        if type(payload) == "table" then
            if payload.value ~= nil then value = tonumber(payload.value) or 0 end
            toggled = parseBoolean(payload.toggled)
        elseif type(payload) == "number" then
            value = payload
        end
        safeSet(key, { value = value, toggled = toggled })
        warn(string.format("[RemoteControl] Applied sliderToggle %s -> value=%s, toggled=%s", key, tostring(value), tostring(toggled)))
    elseif ctrl.type == "dropdownToggle" then
        local selection = nil
        local toggled = nil
        if type(payload) == "table" then
            if type(payload.selection) == "string" then
                selection = payload.selection
            elseif type(payload.item) == "string" then
                selection = payload.item
            elseif type(payload.value) == "string" then
                selection = payload.value
            end
            toggled = parseBoolean(payload.toggled)
        elseif type(payload) == "string" then
            selection = payload
        end
        safeSet(key, { selection = selection, toggled = toggled })
        warn(string.format("[RemoteControl] Applied dropdownToggle %s -> selection=%s, toggled=%s", key, tostring(selection), tostring(toggled)))
    elseif ctrl.type == "multiSelectToggle" then
        local selections = {}
        local toggled = nil
        if type(payload) == "table" then
            local rawSel = payload.selections or payload.selected or payload.selection or payload
            if type(rawSel) == "table" then
                if #rawSel > 0 then
                    for _, name in ipairs(rawSel) do
                        if name ~= nil then selections[name] = true end
                    end
                else
                    selections = rawSel
                end
            elseif type(rawSel) == "string" then
                selections[rawSel] = true
            end
            toggled = parseBoolean(payload.toggled)
        elseif type(payload) == "string" then
            selections[payload] = true
        end
        if toggled == nil then
            toggled = next(selections) ~= nil
        end
        safeSet(key, { selections = selections, toggled = toggled })
        warn(string.format("[RemoteControl] Applied multiSelect %s -> %d selections, toggled=%s", key, (function(t) local c=0 for _,v in pairs(t) do if v then c=c+1 end end return c end)(selections), tostring(toggled)))
    end
    -- Immediately push updated state so the website reflects changes without waiting
    task.delay(0.15, function() sendRemoteState(true) end)
end

function pullRemoteCommands()
    if not backendReady() then return end
    local key = ensureBackendUserKey()
    local headers = {
        ["x-api-key"] = BACKEND_API_KEY,
        ["x-user-key"] = key,
    }
    local url = BACKEND_URL .. "/api/controls/commands"
    task.spawn(function()
        local ok, res = pcall(httpRequest, {
            Url = url,
            Method = "GET",
            Headers = headers,
        })
        if not ok then
            warn("[RemoteControl] Failed to fetch commands:", res)
            return
        end
        if not res or not res.Body then return end
        local decoded = nil
        local success, err = pcall(function()
            decoded = HttpService:JSONDecode(res.Body)
        end)
        if not success or type(decoded) ~= "table" then return end
        if type(decoded.commands) == "table" then
            for _, cmd in ipairs(decoded.commands) do
                applyRemoteCommand(cmd)
            end
        end
    end)
end

task.spawn(function()
    while true do
        local ok, err = pcall(function()
            sendRemoteState()
            pullRemoteCommands()
        end)
        if not ok then
            warn("[RemoteControl] Loop error:", err)
        end
        task.wait(REMOTE_POLL_INTERVAL)
    end
end)

-- dY"Ã…Â¥ Optimized RunService.Stepped Loop
-- Ã°Å¸â€Â¥ Optimized RunService.Stepped Loop
RunService.Stepped:Connect(function()
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("Humanoid") then return end
    local humanoid = char.Humanoid
    local rootPart = char.HumanoidRootPart

    local now = tick()
    
    -- Speed/Jump/Noclip Logic
    if isSpeedEnabled and not isDispensing then humanoid.WalkSpeed = currentSpeed end
    if isJumpEnabled and not isDispensing then humanoid.JumpPower = currentJump end
    
    if isNoclipEnabled then
        humanoid:ChangeState(Enum.HumanoidStateType.Running)
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.CanCollide then part.CanCollide = false end
        end
    end
    
    local coreStats = LocalPlayer:FindFirstChild("CoreStats")
    local pollen = coreStats and coreStats:FindFirstChild("Pollen")
    local capacity = coreStats and coreStats:FindFirstChild("Capacity")
    
    -- Stats Update 
    if coreStats and farmSessionStart > 0 and now - statsLastUpdate > 0.5 then
        statsLastUpdate = now
        local currentHoney = coreStats:FindFirstChild("Honey") and coreStats.Honey.Value or 0
        local currentPollen = pollen and pollen.Value or 0
        local elapsed = math.max(now - farmSessionStart, 1)
        local pollenGained = currentPollen - farmStartPollen
        local honeyGained = currentHoney - farmStartHoney
        local pollenPerMin = (pollenGained / elapsed) * 60
        local honeyPerHour = (honeyGained / elapsed) * 3600
        local capValue = capacity and capacity.Value or 0
        local percent = (capValue > 0) and (currentPollen / capValue * 100) or 0
        local minutes = math.floor(elapsed / 60)
        local seconds = math.floor(elapsed % 60)

        if isStatsPanelEnabled and statsLabel then
            local statsText = string.format(
                "Session: %02d:%02d\nPollen: %s / %s (%.1f%%%%)\nPollen Gain: %s (%s/min)\nHoney Gain: %s (%s/hr)",
                minutes, seconds,
                formatShort(currentPollen), formatShort(capValue), percent,
                formatShort(pollenGained), formatShort(pollenPerMin),
                formatShort(honeyGained), formatShort(honeyPerHour)
            )
            statsLabel.Text = statsText
        end

        -- Backend sync (accumulate deltas and send every BACKEND_SEND_INTERVAL)
        if BACKEND_SYNC_ENABLED then
            backendLastHoney = backendLastHoney or currentHoney
            backendLastPollen = backendLastPollen or currentPollen

            local rawHoneyDelta = currentHoney - backendLastHoney
            local rawPollenDelta = currentPollen - backendLastPollen
            local honeyDelta = math.max(0, rawHoneyDelta)
            local pollenDelta = math.max(0, rawPollenDelta)
            backendAccumHoney = backendAccumHoney + honeyDelta
            backendAccumPollen = backendAccumPollen + pollenDelta

            backendLastHoney = currentHoney
            backendLastPollen = currentPollen

            if now - backendLastSend >= BACKEND_SEND_INTERVAL then
                local playerLabel = LocalPlayer and LocalPlayer.Name or "Player"
                sendBackendSample(
                    backendAccumHoney,
                    backendAccumPollen,
                    true,
                    currentHoney,
                    currentPollen,
                    currentNectarStates,
                    capValue,
                    playerLabel
                )
                backendAccumHoney = 0
                backendAccumPollen = 0
                backendLastSend = now
            end
        end

        if now - nectarLastUpdate >= NECTAR_UPDATE_INTERVAL then
            nectarLastUpdate = now
            captureNectarStates()
        end
    end

    -- Hide path parts and skip movement logic when Auto Farm is off or we are dispensing,
    -- but keep stats/backend updates running above.
    if not isAutoFarmEnabled or isDispensing or planterHarvestInProgress or autoplaceActive then
        for i = 1, #pathParts do
            pathParts[i].Transparency = 1
        end
        return
    end

    if isAutoDispenseEnabled and not planterHarvestInProgress and pollen and capacity and pollen.Value >= capacity.Value then
        print(string.format(
            "[BalloonHold] Auto-dispense trigger: pollen=%s capacity=%s threshold=%s holdToggle=%s",
            tostring(pollen.Value),
            tostring(capacity.Value),
            tostring(balloonBlessingThreshold),
            tostring(balloonBlessingHoldEnabled)
        ))
        task.spawn(dispenseHoney)
        return
    end
    
    if not selectedField then return end

    -- Auto-Teleport back to field if outside
    if not isInField(rootPart.Position) then
        if not char.PrimaryPart then
            char.PrimaryPart = rootPart
        end
        teleportCharacterToCFrame(selectedField.CFrame + Vector3.new(0, 5, 0), { noYield = true })
    end
    
    cleanupTokenCaches(now)

    -- Simplified Movement Function
    local function requestMoveTo(targetPos)
        if not targetPos then return end
        humanoid:MoveTo(targetPos)
    end

    -- New, simplified token finding function
    local function findBestToken()
        local collectibles = Workspace:FindFirstChild("Collectibles")
        if not collectibles then return nil end

        local bestToken = nil
        local bestScore = -math.huge

        for _, token in ipairs(collectibles:GetChildren()) do
            if token:IsA("BasePart") then
                local front = token:FindFirstChild("FrontDecal")
                local back = token:FindFirstChild("BackDecal")
                local anyDecal = (front and front:IsA("Decal")) or (back and back:IsA("Decal")) or token:FindFirstChildOfClass("Decal")
                local recentlyVisited = visitedTokens[token] and visitedTokens[token] > now

                if not recentlyVisited and anyDecal and token.Transparency < 0.9 then
                    local tokenPos = token.Position
                    -- Add a height check to ignore tokens in trees or far below the field
                    if isInField(tokenPos) and math.abs(tokenPos.Y - rootPart.Position.Y) < 5 then
                        local dist = (rootPart.Position - tokenPos).Magnitude
                        if dist < MAX_TOKEN_TRACK_DISTANCE then
                            local name = getCollectibleTokenName(token)
                            local allowed = isTokenAllowed(name)

                            if allowed then
                                local priority = TOKEN_PRIORITY_WEIGHT[name] or 1
                                
                                -- Add a large bonus for tokens that are about to expire (high transparency)
                                local transparency_bonus = (token.Transparency ^ 2) * 150
                                
                                -- New score: priority and transparency bonus weighted against distance
                                local score = priority + transparency_bonus - (dist / 4)

                                if score > bestScore then
                                    bestScore = score
                                    bestToken = token
                                end
                            end
                        end
                    end
                end
            end
        end
        return bestToken
    end

    -- --- New State Machine Logic ---
    local currentTargetPosition = nil

    -- State 1: Check if current token is valid
    if activeToken and (not activeToken.Parent or activeToken.Transparency > 0.95) then
        visitedTokens[activeToken] = now + TOKEN_RECENT_DELAY
        local name = getCollectibleTokenName(activeToken)
        if name then
    -- token logging disabled
end
        activeToken = nil
        wanderTarget = nil -- Force find a new wander spot
    end

    -- Priority 0: Duped tokens (Digital Bee ability duplicates)
    if holdDupedTokensEnabled then
        if dupedTokenTarget and not isDupedTokenAllowed(dupedTokenTargetName) then
            dupedTokenTarget = nil
            dupedTokenTargetName = nil
            dupedTokenTargetId = nil
            dupedTokenHoldUntil = 0
        end
        if not dupedTokenTarget then
            local newTarget, tokenName, tokenId = findDupedTokenTarget(rootPart.Position, now)
            if newTarget then
                dupedTokenTarget = newTarget
                dupedTokenTargetName = tokenName
                dupedTokenTargetId = tokenId
                dupedTokenHoldUntil = 0
            end
        end
        if dupedTokenTarget and dupedTokenTarget.Parent then
            local tokenPos = dupedTokenTarget.Position
            local movePos = Vector3.new(tokenPos.X, rootPart.Position.Y, tokenPos.Z)
            currentTargetPosition = movePos
            requestMoveTo(movePos)
            local planarDist = planarDistance(tokenPos, rootPart.Position)
            if planarDist <= TOKEN_PASS_RADIUS then
                if dupedTokenHoldUntil == 0 then
                    dupedTokenHoldUntil = now + DUPED_TOKEN_CHARGE_TIME + DUPED_TOKEN_HOLD_BUFFER
                elseif now >= dupedTokenHoldUntil then
                    dupedSeenTokens[dupedTokenTarget] = now + DUPED_TOKEN_RESELECT_DELAY
                    dupedTokenTarget = nil
                    dupedTokenTargetName = nil
                    dupedTokenTargetId = nil
                    dupedTokenHoldUntil = 0
                end
            else
                dupedTokenHoldUntil = 0
            end
        elseif dupedTokenTarget then
            dupedTokenTarget = nil
            dupedTokenTargetName = nil
            dupedTokenTargetId = nil
            dupedTokenHoldUntil = 0
        end
    else
        if dupedTokenTarget then
            dupedTokenTarget = nil
            dupedTokenTargetName = nil
            dupedTokenTargetId = nil
        end
        dupedTokenHoldUntil = 0
    end

    -- Priority 1: Falling stars (warning disk -> star) -> stand briefly
    if starTarget and (not starTarget.Parent or not isStarWarningDisk(starTarget)) then
        starTarget = nil
        starHoldUntil = 0
    end
    if not dupedTokenTarget and standUnderFallingStarEnabled then
        local newStar = findFallingStarTarget(rootPart.Position)
        if newStar and newStar ~= starTarget then
            logHazard("StarDisk->Target", newStar)
        end
        starTarget = newStar or starTarget
        if starTarget then
            local starPos = starTarget.Position
            currentTargetPosition = starPos
            requestMoveTo(starPos)
            local dist = (rootPart.Position - starPos).Magnitude
            if dist < TOKEN_PASS_RADIUS then
                if starHoldUntil == 0 then
                    starHoldUntil = now + STAR_STAND_TIME
                elseif now >= starHoldUntil then
                    starTarget = nil
                    starHoldUntil = 0
                end
            end
        end
    elseif not standUnderFallingStarEnabled then
        starTarget = nil
        starHoldUntil = 0
    end

    -- Priority 2: Falling coconuts (green circles) -> short delay then stand briefly
    if not dupedTokenTarget and not starTarget and standUnderCoconutEnabled then
        local newTarget = findCoconutDropTarget(rootPart.Position)
        if newTarget and newTarget ~= coconutTarget then
            logHazard("CoconutDisk->Target", newTarget)
            coconutApproachTime = now + COCONUT_APPROACH_DELAY
            coconutHoldUntil = 0
            coconutTarget = newTarget
        end
        if coconutTarget then
            local cocPos = coconutTarget.Position
            currentTargetPosition = (now >= coconutApproachTime) and cocPos or currentTargetPosition
            if now >= coconutApproachTime then
                requestMoveTo(cocPos)
            end
            local dist = (rootPart.Position - cocPos).Magnitude
            if dist < TOKEN_PASS_RADIUS then
                if coconutHoldUntil == 0 then
                    coconutHoldUntil = now + COCONUT_STAND_TIME
                elseif now >= coconutHoldUntil then
                    coconutTarget = nil
                    coconutHoldUntil = 0
                    coconutApproachTime = 0
                end
            end
        end
    elseif not standUnderCoconutEnabled then
        coconutTarget = nil
        coconutHoldUntil = 0
        coconutApproachTime = 0
    end

    -- Priority 3: Precise Bee crosshair markers -> walk through them
    if not dupedTokenTarget and not starTarget and not coconutTarget and standThroughPreciseBeeEnabled then
        local newPrecise = findPreciseCrosshairTarget(rootPart.Position)
        if newPrecise and newPrecise ~= preciseTarget then
            logHazard("PreciseMark->Target", newPrecise)
        end
        preciseTarget = newPrecise or preciseTarget
        if preciseTarget then
            local markPos = preciseTarget.Position
            currentTargetPosition = markPos
            requestMoveTo(markPos)
            local dist = (rootPart.Position - markPos).Magnitude
            if dist < TOKEN_PASS_RADIUS then
                if preciseHoldUntil == 0 then
                    precisePassCount = precisePassCount + 1
                    preciseVisitedMarks[preciseTarget] = true -- prevent reselect while handling
                    if precisePassCount % 3 == 0 then
                        preciseHoldUntil = now + 1.5
                    else
                        preciseTarget = nil
                    end
                elseif now >= preciseHoldUntil then
                    preciseHoldUntil = 0
                    preciseTarget = nil
                end
            end
        end
    elseif not standThroughPreciseBeeEnabled then
        preciseTarget = nil
        preciseHoldUntil = 0
    end

    if dupedTokenTarget then
        -- handled above; skip other logic
    elseif starTarget then
        -- handled above; skip other logic
    elseif coconutTarget then
        -- handled above; skip other logic
    elseif preciseTarget then
        -- handled above; skip other logic
    else
        -- State 2: If we have a valid token, move to it
        if activeToken then
            local tokenPos = activeToken.Position
            local tokenName = getCollectibleTokenName(activeToken)
            local dist = (rootPart.Position - tokenPos).Magnitude

            if dist < TOKEN_PASS_RADIUS then
                visitedTokens[activeToken] = now + TOKEN_RECENT_DELAY
                if tokenName then
                    -- token logging disabled
                end
                activeToken = nil
                wanderTarget = nil
            else
                -- Move to the token
                currentTargetPosition = tokenPos
                requestMoveTo(tokenPos)
            end

        -- State 3: If no active token, find a new one or wander
        else
            if now - lastTokenSearchTime >= TOKEN_SEARCH_INTERVAL then
                lastTokenSearchTime = now
                currentBestCandidate = findBestToken()
            end

            local bestToken = currentBestCandidate
            if bestToken and (not bestToken.Parent or bestToken.Transparency > 0.95) then
                currentBestCandidate = nil
                bestToken = nil
            end
            if bestToken then
                activeToken = bestToken
                currentBestCandidate = nil
            elseif pickUpBubblesEnabled or pickUpFuzzyEnabled then
                -- Low-priority passes (only if no regular token was found)
                if pickUpBubblesEnabled then
                    if bubbleTarget and (not bubbleTarget.Parent or not isBubble(bubbleTarget) or not isInField(bubbleTarget.Position)) then
                        bubbleTarget = nil
                    end
                    local newBubble = findBubbleTarget(rootPart.Position)
                    if newBubble and newBubble ~= bubbleTarget then
                        logHazard("Bubble->Target", newBubble)
                    end
                    bubbleTarget = newBubble or bubbleTarget
                else
                    bubbleTarget = nil
                end

                if pickUpFuzzyEnabled then
                    if fuzzyTarget and (not fuzzyTarget.Parent or not fuzzyTarget:IsA("BasePart") or not isInField(fuzzyTarget.Position)) then
                        fuzzyTarget = nil
                    end
                    local newFuzzy = findFuzzyTarget(rootPart.Position)
                    if newFuzzy and newFuzzy ~= fuzzyTarget then
                        logHazard("Fuzzy->Target", newFuzzy)
                    end
                    fuzzyTarget = newFuzzy or fuzzyTarget
                else
                    fuzzyTarget = nil
                end

                local secondaryTarget = bubbleTarget or fuzzyTarget
                if secondaryTarget then
                    local targetPos = secondaryTarget.Position
                    currentTargetPosition = targetPos
                    requestMoveTo(targetPos)
                    local dist = (rootPart.Position - targetPos).Magnitude
                    if dist < TOKEN_PASS_RADIUS then
                        if secondaryTarget == bubbleTarget then
                            bubbleTarget = nil
                        end
                        if secondaryTarget == fuzzyTarget then
                            fuzzyTarget = nil
                        end
                    end
                else
                    if not wanderTarget or (rootPart.Position - wanderTarget).Magnitude < 10 or now > wanderExpireTime then
                        wanderTarget = chooseWanderSpot(rootPart.Position, now)
                        if wanderTarget then
                            wanderExpireTime = now + math.random(2, 5)
                        end
                    end
                    currentTargetPosition = wanderTarget
                    requestMoveTo(wanderTarget)
                end
            else
                -- Wander if no tokens found
                if not wanderTarget or (rootPart.Position - wanderTarget).Magnitude < 10 or now > wanderExpireTime then
                    wanderTarget = chooseWanderSpot(rootPart.Position, now)
                    if wanderTarget then
                        wanderExpireTime = now + math.random(2, 5) 
                    end
                end
                currentTargetPosition = wanderTarget
                requestMoveTo(wanderTarget)
            end
        end
    end

    -- Path Visualization
    for i = 1, #pathParts do
        pathParts[i].Transparency = 1
    end
    if currentTargetPosition then
        local startPos = rootPart.Position
        local endPos = currentTargetPosition
        local direction = endPos - startPos
        local distance = direction.Magnitude
        local part = pathParts[1]
        
        if distance > 1 then
            part.Transparency = 0.25
            part.Size = Vector3.new(0.15, 0.15, distance)
            part.CFrame = CFrame.new(startPos, endPos) * CFrame.new(0, 0, -distance / 2)
        end
    end
end)

-- // --- Monster Spawner ESP + World Info Overlay --- //
local monsterEspScreenGui = Instance.new("ScreenGui")
monsterEspScreenGui.Name = "MonsterESP_Container"
monsterEspScreenGui.ResetOnSpawn = false
monsterEspScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function()
    monsterEspScreenGui.Parent = gethui()
end)
local monsterGuiCache = {}
local MONSTER_ESP_TEXT_SIZE = 16
local MONSTER_ESP_VERTICAL_OFFSET = 15
local MONSTER_ESP_READY_COLOR = Color3.fromRGB(0, 255, 127)
local MONSTER_ESP_TIMER_COLOR = Color3.fromRGB(255, 255, 255)
monsterEspLastUpdate = 0
MONSTER_ESP_UPDATE_INTERVAL = 0.2

RunService.RenderStepped:Connect(function()
    if not monsterSpawnerEspEnabled then
        if monsterEspScreenGui.Enabled then monsterEspScreenGui.Enabled = false end
        return
    end
    if not monsterEspScreenGui.Enabled then monsterEspScreenGui.Enabled = true end

    local nowClock = os.clock()
    if nowClock - monsterEspLastUpdate < MONSTER_ESP_UPDATE_INTERVAL then
        return
    end
    monsterEspLastUpdate = nowClock

    local char = LocalPlayer.Character
    local rootPart = char and char:FindFirstChild("HumanoidRootPart")

    local monsterSpawnersFolder = Workspace:FindFirstChild("MonsterSpawners")
    if monsterSpawnersFolder then
        for _, spawnerModel in ipairs(monsterSpawnersFolder:GetDescendants()) do
            pcall(function()
                if not (spawnerModel:IsA("Model") or spawnerModel:IsA("BasePart")) then return end

                local timerLabel = spawnerModel:FindFirstChild("TimerLabel", true)
                if timerLabel and timerLabel:IsA("TextLabel") then
                    local timerGui = timerLabel.Parent
                    if timerGui and timerGui.Name == "TimerGui" and timerGui:IsA("BillboardGui") then
                        local anchorPart = timerGui.Parent
                        if anchorPart and anchorPart:IsA("Attachment") then

                            local timerText = timerLabel.Text
                            local displayText, displayColor

                            if timerText == "1:00" then
                                displayText = string.format("%s [READY]", spawnerModel.Name)
                                displayColor = MONSTER_ESP_READY_COLOR
                            else
                                displayText = string.format("%s [%s]", spawnerModel.Name, timerText)
                                displayColor = MONSTER_ESP_TIMER_COLOR
                            end

                            local billboardGui = monsterGuiCache[spawnerModel]
                            if not billboardGui then
                                billboardGui = Instance.new("BillboardGui")
                                billboardGui.Name = "SpawnerLabel"
                                billboardGui.AlwaysOnTop = true
                                billboardGui.Size = UDim2.new(0, 300, 0, 50)
                                billboardGui.StudsOffset = Vector3.new(0, MONSTER_ESP_VERTICAL_OFFSET, 0)
                                billboardGui.Adornee = anchorPart

                                local textLabel = Instance.new("TextLabel")
                                textLabel.Name = "InfoText"
                                textLabel.BackgroundTransparency = 1
                                textLabel.Size = UDim2.new(1, 0, 1, 0)
                                textLabel.Font = Enum.Font.SourceSans
                                textLabel.TextSize = MONSTER_ESP_TEXT_SIZE
                                textLabel.TextStrokeTransparency = 0.5

                                textLabel.Parent = billboardGui
                                billboardGui.Parent = monsterEspScreenGui

                                monsterGuiCache[spawnerModel] = billboardGui
                            end

                            local textLabel = billboardGui:FindFirstChild("InfoText")
                            if textLabel then
                                textLabel.Text = displayText
                                textLabel.TextColor3 = displayColor
                            end
                        end
                    end
                end
            end)
        end
    end

end)

function onCharacterAdded(character)
    local humanoid = character:WaitForChild("Humanoid")
    defaultWalkSpeed, defaultJumpPower = humanoid.WalkSpeed, humanoid.JumpPower
end

LocalPlayer.CharacterAdded:Connect(onCharacterAdded)
if LocalPlayer.Character then onCharacterAdded(LocalPlayer.Character) end
