-- Fisch script migrated to native UiLib API (no legacy adapter).
-- Uses AddMenu/AddSection/AddToggle/AddSlider/AddDropdown directly.

local function loadRemoteUiLib()
    local baseUrl = 'https://raw.githubusercontent.com/megafartCc/UiLib/main/UILibModules'
    local moduleCache = {}

    local function normalizePath(path)
        local parts = {}
        for part in string.gmatch(string.gsub(path, '\\', '/'), '[^/]+') do
            if part == '..' then
                if #parts > 0 then
                    table.remove(parts)
                end
            elseif part ~= '.' and part ~= '' then
                table.insert(parts, part)
            end
        end
        return table.concat(parts, '/')
    end

    local function loadRemoteModule(path)
        local normalized = normalizePath(path)
        local cached = moduleCache[normalized]
        if cached ~= nil then
            return cached
        end
        local source = game:HttpGet(baseUrl .. '/' .. normalized)
        local chunk, err = loadstring(source)
        if not chunk then
            error(string.format('UiLib load failed for %s: %s', normalized, tostring(err)))
        end
        local exported = chunk()
        moduleCache[normalized] = exported
        return exported
    end

    local entryModule = loadRemoteModule('init.lua')
    local function moduleRequire(relativePath)
        return loadRemoteModule(relativePath)
    end
    return entryModule(moduleRequire)
end

local Library = loadRemoteUiLib()
local Players = game:GetService('Players')
local TeleportService = game:GetService('TeleportService')
local HttpService = game:GetService('HttpService')
local RunService = game:GetService('RunService')
local localplr = Players.LocalPlayer
local SETTINGS_CONFIG = 'eps1llon_fisch_settings'

if type(Library.Notify) ~= 'function' then
    function Library:Notify(opts)
        opts = opts or {}
        local title = tostring(opts.Title or opts.title or 'Notice')
        local text = tostring(opts.Text or opts.text or '')
        local duration = tonumber(opts.Duration or opts.duration or 3) or 3
        pcall(function()
            game:GetService('StarterGui'):SetCore('SendNotification', {
                Title = title,
                Text = text,
                Duration = duration,
            })
        end)
        print(string.format('[Notify] %s | %s', title, text))
    end
end

local lighting = game:GetService('Lighting')
local originalAmbient = lighting.Ambient
local originalOutdoorAmbient = lighting.OutdoorAmbient
local originalBrightness = lighting.Brightness
local originalGlobalShadows = lighting.GlobalShadows
local originalFogEnd = lighting.FogEnd
local originalClockTime = lighting.ClockTime

-- Internal state flags which will be updated via UI callbacks.
local isWalkSpeedLocked = false
local currentWalkSpeed = 16
local autoselling = false
local radar = false
local jesus = false
local waterplatforms = Instance.new('Folder', workspace)
waterplatforms.Name = 'WaterPlatforms'
local isAntiStaffEnabled = false
local customWorldTimeEnabled = false
local customWorldTimeValue = 14

local fpsBoostEnabled = false
local fpsBoostConnections = {}
local originalProperties = {
    lighting = {},
    terrain = {},
    parts = setmetatable({}, { __mode = 'k' }),
    effects = setmetatable({}, { __mode = 'k' }),
}

-- Base defaults used before config load.
local settings = {
    walkSpeed = 16,
    jesus = false,
    lockWalkSpeed = false,
    jumpPower = 50,
    infOxygen = false,
    stableTemp = false,
    radar = false,
    fullBright = false,
    fpsBoost = false,
    autoSell = false,
    playerZone = 'Safe Zone',
    fishingZone = 'The Docks',
    webhookUrl = '',
    antiStaff = false,
    customWorldTime = 14,
    customWorldTimeEnabled = false,
}

local targetList = {
    'https://www.roblox.com/users/155853515/profile',
    'https://www.roblox.com/users/3497011635/profile',
    'https://www.roblox.com/users/2694547161/profile',
    'https://www.roblox.com/users/130278226/profile',
    'https://www.roblox.com/users/725269614/profile',
    'https://www.roblox.com/users/3647331140/profile',
    'https://www.roblox.com/users/3325762586/profile',
    'https://www.roblox.com/users/1907905676/profile',
    'https://www.roblox.com/users/5287738230/profile',
    'https://www.roblox.com/users/1055857769/profile',
    'https://www.roblox.com/users/8060615849/profile',
    'https://www.roblox.com/users/95398820/profile',
    'https://www.roblox.com/users/2291652094/profile',
    'https://www.roblox.com/users/14107450/profile',
    'https://www.roblox.com/users/60226364/profile',
    'https://www.roblox.com/users/8055169764/profile',
    'https://www.roblox.com/users/8109217058/profile',
    'https://www.roblox.com/users/1201661392/profile',
    'https://www.roblox.com/users/1411462370/profile',
    'https://www.roblox.com/users/1306774965/profile',
    'https://www.roblox.com/users/139050865/profile',
    'https://www.roblox.com/users/402818270/profile',
    'https://www.roblox.com/users/162424510/profile',
    'https://www.roblox.com/users/90135034/profile',
    'https://www.roblox.com/users/298106898/profile',
    'https://www.roblox.com/users/1861488663/profile',
    'https://www.roblox.com/users/1073847038/profile',
    'https://www.roblox.com/users/28225333/profile',
    'https://www.roblox.com/users/1217510625/profile',
    'https://www.roblox.com/users/2512557413/profile',
    'https://www.roblox.com/users/498794415/profile',
    'https://www.roblox.com/users/4092667115/profile',
    'https://www.roblox.com/users/113781265/profile',
    'https://www.roblox.com/users/136024227/profile',
    'https://www.roblox.com/users/4946842593/profile',
    'https://www.roblox.com/users/135002869/profile',
    'https://www.roblox.com/users/4078993443/profile',
    'https://www.roblox.com/users/7207625280/profile',
    'https://www.roblox.com/users/120944129/profile',
    'https://www.roblox.com/users/18659509/profile',
    'https://www.roblox.com/users/44504376/profile',
    'https://www.roblox.com/users/8292780047/profile',
    'https://www.roblox.com/users/4656808630/profile',
    'https://www.roblox.com/users/1170217288/profile',
    'https://www.roblox.com/users/296986122/profile',
    'https://www.roblox.com/users/909635/profile',
    'https://www.roblox.com/users/89659291/profile',
    'https://www.roblox.com/users/8219405134/profile',
    'https://www.roblox.com/users/7554542185/profile',
    'https://www.roblox.com/users/1300222786/profile',
    'https://www.roblox.com/users/129332660/profile',
    'https://www.roblox.com/users/250083132/profile',
    'https://www.roblox.com/users/7930656926/profile',
    'https://www.roblox.com/users/7930492944/profile',
    'https://www.roblox.com/users/198270268/profile',
    'https://www.roblox.com/users/3607413291/profile',
    'https://www.roblox.com/users/7685118272/profile',
    'https://www.roblox.com/users/2678001507/profile',
    'https://www.roblox.com/users/1881196856/profile',
    'https://www.roblox.com/users/207355228/profile',
    'https://www.roblox.com/users/182959121/profile',
    'https://www.roblox.com/users/2541090675/profile',
}

local actionDelay = 0.3
local maxHopAttempts = 4
local hopAttemptDelay = 1.0
local resetDebounceAfter = 10
local reactedRecently = false
local targetIds = {}

local function extractUserId(s)
    if not s then
        return nil
    end
    local id = s:match('/users/(%d+)[^%d]?')
        or s:match('/users/(%d+)$')
        or s:match('^(%d+)$')
    return id and tonumber(id) or nil
end

for _, entry in ipairs(targetList) do
    local id = extractUserId(entry)
    if id then
        targetIds[id] = true
    end
end

local function tryServerHop()
    for attempt = 1, maxHopAttempts do
        local ok, err = pcall(function()
            TeleportService:Teleport(game.PlaceId, localplr)
        end)
        if ok then
            return true
        end
        warn(('Serverhop attempt %d failed: %s'):format(attempt, tostring(err)))
        task.wait(hopAttemptDelay)
    end
    return false
end

local function reactToTarget(plr)
    if reactedRecently or plr == localplr then
        return
    end
    reactedRecently = true
    Library:Notify({
        Title = 'TARGET DETECTED',
        Text = 'PLAYER DETECTED: ' .. plr.Name:upper(),
        Duration = 6,
        Type = 'Error',
    })
    task.wait(actionDelay)
    Library:Notify({
        Title = 'SERVER HOP INITIATED',
        Text = 'ATTEMPTING TO FIND A NEW SERVER...',
        Duration = 6,
        Type = 'Info',
    })
    if not tryServerHop() then
        warn('All serverhop attempts failed.')
        Library:Notify({
            Title = 'SERVER HOP FAILED',
            Text = 'COULD NOT FIND A NEW SERVER.',
            Duration = 8,
            Type = 'Error',
        })
    end
    task.delay(resetDebounceAfter, function()
        reactedRecently = false
    end)
end

local function checkPlayer(plr)
    return targetIds[plr.UserId] == true
end

local function onPlayerAdded(plr)
    if not isAntiStaffEnabled then
        return
    end
    if checkPlayer(plr) then
        reactToTarget(plr)
    end
end

local function checkCurrentPlayers()
    if not isAntiStaffEnabled then
        return
    end
    for _, plr in ipairs(Players:GetPlayers()) do
        if checkPlayer(plr) then
            reactToTarget(plr)
            break
        end
    end
end

Players.PlayerAdded:Connect(onPlayerAdded)

local function isAnyGui(obj)
    return obj:IsDescendantOf(localplr:WaitForChild('PlayerGui'))
        or obj:IsDescendantOf(gethui())
end

local function isWorldGui(obj)
    return obj:IsA('BillboardGui') or obj:IsA('SurfaceGui') or obj:IsA('AdGui')
end

local function isUIPreserved(obj)
    return isAnyGui(obj) or isWorldGui(obj)
end

local function applyFpsBoost(enable)
    local Terrain = workspace:FindFirstChildOfClass('Terrain')
    local Lighting = game:GetService('Lighting')
    for _, conn in ipairs(fpsBoostConnections) do
        conn:Disconnect()
    end
    fpsBoostConnections = {}
    if enable then
        originalProperties.lighting = {
            GlobalShadows = Lighting.GlobalShadows,
            FogEnd = Lighting.FogEnd,
            EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale,
            EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale,
            Atmosphere = Lighting:FindFirstChildOfClass('Atmosphere'),
            Effects = {},
        }
        for _, eff in ipairs(Lighting:GetChildren()) do
            if eff:IsA('PostEffect') then
                originalProperties.lighting.Effects[eff] = eff.Enabled
            end
        end
        if Terrain then
            originalProperties.terrain = {
                WaterWaveSize = Terrain.WaterWaveSize,
                WaterWaveSpeed = Terrain.WaterWaveSpeed,
            }
        end
        for _, d in ipairs(workspace:GetDescendants()) do
            if not isUIPreserved(d) then
                if d:IsA('BasePart') then
                    originalProperties.parts[d] = {
                        Material = d.Material,
                        Reflectance = d.Reflectance,
                        SurfaceAppearance = d:FindFirstChildOfClass('SurfaceAppearance')
                            and d:FindFirstChildOfClass('SurfaceAppearance'):Clone(),
                    }
                elseif d:IsA('ParticleEmitter') or d:IsA('Trail') or d:IsA('Beam') then
                    originalProperties.effects[d] = d.Enabled
                end
            end
        end
        if Terrain then
            Terrain.WaterWaveSize = 0
            Terrain.WaterWaveSpeed = 0
        end
        for eff, _ in pairs(originalProperties.lighting.Effects) do
            eff.Enabled = false
        end
        Lighting.GlobalShadows = false
        Lighting.FogEnd = 1e10
        Lighting.EnvironmentSpecularScale = 0
        Lighting.EnvironmentDiffuseScale = 0
        if originalProperties.lighting.Atmosphere then
            originalProperties.lighting.Atmosphere.Parent = nil
        end
        local function optimizePart(obj)
            if isUIPreserved(obj) then
                return
            end
            if obj:IsA('BasePart') then
                obj.Material = Enum.Material.SmoothPlastic
                obj.Reflectance = 0
                if obj:FindFirstChildOfClass('SurfaceAppearance') then
                    obj:FindFirstChildOfClass('SurfaceAppearance'):Destroy()
                end
            end
        end
        local function disableEffect(obj)
            if isUIPreserved(obj) then
                return
            end
            if obj:IsA('ParticleEmitter') or obj:IsA('Trail') or obj:IsA('Beam') then
                obj.Enabled = false
            end
        end
        for d, _ in pairs(originalProperties.parts) do
            if d and d.Parent then
                optimizePart(d)
            end
        end
        for d, _ in pairs(originalProperties.effects) do
            if d and d.Parent then
                disableEffect(d)
            end
        end
        table.insert(fpsBoostConnections, workspace.DescendantAdded:Connect(optimizePart))
        table.insert(fpsBoostConnections, workspace.DescendantAdded:Connect(disableEffect))
    else
        if originalProperties.lighting.GlobalShadows ~= nil then
            Lighting.GlobalShadows = originalProperties.lighting.GlobalShadows
            Lighting.FogEnd = originalProperties.lighting.FogEnd
            Lighting.EnvironmentSpecularScale = originalProperties.lighting.EnvironmentSpecularScale
            Lighting.EnvironmentDiffuseScale = originalProperties.lighting.EnvironmentDiffuseScale
            if originalProperties.lighting.Atmosphere then
                originalProperties.lighting.Atmosphere.Parent = Lighting
            end
            for eff, wasEnabled in pairs(originalProperties.lighting.Effects) do
                if eff and eff.Parent then
                    eff.Enabled = wasEnabled
                end
            end
        end
        if Terrain and originalProperties.terrain.WaterWaveSize ~= nil then
            Terrain.WaterWaveSize = originalProperties.terrain.WaterWaveSize
            Terrain.WaterWaveSpeed = originalProperties.terrain.WaterWaveSpeed
        end
        for part, props in pairs(originalProperties.parts) do
            if part and part.Parent then
                part.Material = props.Material
                part.Reflectance = props.Reflectance
                if part:FindFirstChildOfClass('SurfaceAppearance') then
                    part:FindFirstChildOfClass('SurfaceAppearance'):Destroy()
                end
                if props.SurfaceAppearance then
                    props.SurfaceAppearance.Parent = part
                end
            end
        end
        for effect, wasEnabled in pairs(originalProperties.effects) do
            if effect and effect.Parent then
                effect.Enabled = wasEnabled
            end
        end
        originalProperties = {
            lighting = {},
            terrain = {},
            parts = setmetatable({}, { __mode = 'k' }),
            effects = setmetatable({}, { __mode = 'k' }),
        }
    end
end

local function setupBillboard(billboard)
    if billboard:IsA('BillboardGui') then
        billboard.AlwaysOnTop = true
        billboard.MaxDistance = 1111110
        billboard.Size = UDim2.new(billboard.Size.X.Scale, 70, billboard.Size.Y.Scale, 50)
        billboard.ClipsDescendants = false
    end
end

local function updateAllRadarTags()
    for _, tag in pairs(game:GetService('CollectionService'):GetTagged('radarTag')) do
        if tag:IsA('BillboardGui') or tag:IsA('SurfaceGui') then
            setupBillboard(tag)
            tag.Enabled = radar
            if tag:FindFirstChild('abundanceName') and tag:FindFirstChild('abundanceName').Text == 'Ancient Depth Serpent' then
                tag.Enabled = false
            end
        end
    end
    for _, tag in pairs(game:GetService('CollectionService'):GetTagged('radarTagWithTimer')) do
        if tag:IsA('BillboardGui') or tag:IsA('SurfaceGui') then
            setupBillboard(tag)
            tag.Enabled = radar
        end
    end
end

-- Player ESP module copied from sabnew.lua.
local ESP
pcall(function()
    ESP = loadstring(game:HttpGet('https://raw.githubusercontent.com/megafartCc/SAB/main/espmodule.lua'))()
    pcall(ESP.Init, ESP)
end)

local function safeESP(fn, value)
    if ESP then
        pcall(fn, ESP, value)
    end
end

local function applyCustomWorldTime()
    if customWorldTimeEnabled then
        lighting.ClockTime = customWorldTimeValue
    end
end

-- Define UI window and menus (native UiLib API).
local window = Library:CreateWindow({
    Name = 'UNKNOWN HUB',
    Expire = 'Premium',
    ConfigName = SETTINGS_CONFIG,
})
Library._autoSave = true

local configMenu = window:AddMenu({ Name = 'PLAYER', Columns = 2 })
local fishingMenu = window:AddMenu({ Name = 'FISHING', Columns = 2 })
local visualsMenu = window:AddMenu({ Name = 'VISUALS', Columns = 2 })
local shopMenu = window:AddMenu({ Name = 'SHOP', Columns = 2 })
local teleportMenu = window:AddMenu({ Name = 'TELEPORTS', Columns = 2 })
local miscMenu = window:AddMenu({ Name = 'MISCELLANEOUS', Columns = 2 })

-- Sections
local playerConfigSection = configMenu:AddSection({ Name = 'CHARACTER', Column = 1 })
local playerMiscSection = configMenu:AddSection({ Name = 'PLAYER MISC', Column = 2 })
local fishingPlaceholderSection = fishingMenu:AddSection({ Name = 'FISHING AUTOMATION', Column = 1 })
local playerEspSection = visualsMenu:AddSection({ Name = 'PLAYER ESP', Column = 1 })
local worldVisualsSection = visualsMenu:AddSection({ Name = 'WORLD VISUALS', Column = 2 })
local sellsection = shopMenu:AddSection({ Name = 'SELL', Column = 1 })
local teleportsection = teleportMenu:AddSection({ Name = 'TELEPORTS', Column = 1 })
local serverHopSection = miscMenu:AddSection({ Name = 'ANTI STAFF', Column = 1 })
local webhookSection = miscMenu:AddSection({ Name = 'WEBHOOKS', Column = 2 })

local function addTextInput(section, opts)
    opts = opts or {}
    local name = tostring(opts.Name or 'Input')
    local defaultValue = tostring(opts.Default or '')
    local placeholder = tostring(opts.Placeholder or '')
    local callback = opts.Callback or function() end
    local saveKey = opts.SaveKey
    local value = defaultValue

    local row = Instance.new('Frame')
    row.BackgroundTransparency = 1
    row.BorderSizePixel = 0
    row.Size = UDim2.new(1, 0, 0, 22)
    row.Parent = section.Container

    local label = Instance.new('TextLabel')
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(0.35, 0, 1, 0)
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Font = Enum.Font.Gotham
    label.TextSize = 12
    label.TextColor3 = Color3.fromRGB(220, 220, 220)
    label.Text = name
    label.Parent = row

    local box = Instance.new('TextBox')
    box.AnchorPoint = Vector2.new(1, 0.5)
    box.Position = UDim2.new(1, 0, 0.5, 0)
    box.Size = UDim2.new(0.62, 0, 0, 18)
    box.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    box.BorderSizePixel = 0
    box.TextXAlignment = Enum.TextXAlignment.Left
    box.Font = Enum.Font.Gotham
    box.TextSize = 11
    box.TextColor3 = Color3.fromRGB(235, 235, 235)
    box.ClearTextOnFocus = false
    box.PlaceholderText = placeholder
    box.Text = defaultValue
    box.Parent = row

    local corner = Instance.new('UICorner')
    corner.CornerRadius = UDim.new(0, 3)
    corner.Parent = box

    local function applyText(newValue, fireCallback, markDirty)
        value = tostring(newValue or '')
        box.Text = value
        if fireCallback then
            pcall(callback, value)
        end
        if markDirty then
            Library:_markDirty()
        end
    end

    box.FocusLost:Connect(function()
        applyText(box.Text, true, true)
    end)

    local api = { Object = box }
    function api:Get()
        return value
    end
    function api:Set(newValue)
        applyText(newValue, true, true)
        return api
    end
    function api:GetText()
        return value
    end
    function api:SetText(newValue)
        return api:Set(newValue)
    end

    if saveKey then
        Library:RegisterConfig(saveKey, 'textbox',
            function()
                return value
            end,
            function(loadedValue)
                applyText(loadedValue, true, false)
            end
        )
    end

    return api
end

local wsSlider = playerConfigSection:AddSlider({
    Name = 'WalkSpeed',
    Min = 16,
    Max = 200,
    Default = settings.walkSpeed,
    Suffix = '',
    Callback = function(value)
        currentWalkSpeed = value
        if not isWalkSpeedLocked and localplr.Character and localplr.Character:FindFirstChildOfClass('Humanoid') then
            localplr.Character.Humanoid.WalkSpeed = value
        end
    end,
})

local jesusToggle = playerConfigSection:AddToggle({
    Name = 'Jesus',
    Default = settings.jesus,
    Callback = function(v)
        jesus = v
        if not v then
            for _, child in pairs(waterplatforms:GetChildren()) do
                child:Destroy()
            end
        end
    end,
})

local lockWSToggle = playerConfigSection:AddToggle({
    Name = 'Lock WalkSpeed',
    Default = settings.lockWalkSpeed,
    Callback = function(value)
        isWalkSpeedLocked = value
        if not isWalkSpeedLocked and localplr.Character and localplr.Character:FindFirstChildOfClass('Humanoid') then
            localplr.Character.Humanoid.WalkSpeed = currentWalkSpeed
        end
    end,
})

local jumpPowerSlider = playerConfigSection:AddSlider({
    Name = 'Jump Power',
    Min = 50,
    Max = 250,
    Default = settings.jumpPower,
    Suffix = '',
    Callback = function(value)
        if localplr.Character and localplr.Character:FindFirstChildOfClass('Humanoid') then
            localplr.Character.Humanoid.JumpPower = value
        end
    end,
})

local infOxygenToggle = playerMiscSection:AddToggle({
    Name = 'Inf Oxygen',
    Default = settings.infOxygen,
    Callback = function(value)
        local resources = localplr.Character and localplr.Character:FindFirstChild('Resources')
        if resources then
            resources.oxygen.Enabled = not value
            resources['oxygen(peaks)'].Enabled = not value
            if value then
                for _, v in ipairs(localplr.Character.Head:GetChildren()) do
                    pcall(function()
                        if v.Name == 'ui' and v.bg.Bar.BackgroundColor3 == resources.oxygen.ui.bg.Bar.BackgroundColor3 then
                            v:Destroy()
                        end
                    end)
                end
            end
        end
    end,
})

local stableTempToggle = playerMiscSection:AddToggle({
    Name = 'Stable Temperature',
    Default = settings.stableTemp,
    Callback = function(value)
        local resources = localplr.Character and localplr.Character:FindFirstChild('Resources')
        if resources then
            resources.temperature.Enabled = not value
            resources['temperature(heat)'].Enabled = not value
            if value then
                for _, v in ipairs(localplr.Character.Head:GetChildren()) do
                    pcall(function()
                        if v.Name == 'ui' and v.bg.Bar.BackgroundColor3 == resources.temperature.ui.bg.Bar.BackgroundColor3 then
                            v:Destroy()
                        end
                    end)
                end
            end
        end
    end,
})

fishingPlaceholderSection:AddButton({
    Name = 'COMING SOON',
    Callback = function()
        Library:Notify({
            Title = 'FISHING',
            Text = 'Fishing automation is temporarily disabled.',
            Duration = 3,
        })
    end,
})

playerEspSection:AddToggle({
    Name = 'Box ESP',
    Default = false,
    Callback = function(state)
        safeESP(ESP.SetBoxEsp, state)
    end,
})
playerEspSection:AddToggle({
    Name = 'Name ESP',
    Default = false,
    Callback = function(state)
        safeESP(ESP.SetNameEsp, state)
    end,
})
playerEspSection:AddToggle({
    Name = 'Health ESP',
    Default = false,
    Callback = function(state)
        safeESP(ESP.SetHealthEsp, state)
    end,
})
playerEspSection:AddToggle({
    Name = 'Team ESP',
    Default = false,
    Callback = function(state)
        safeESP(ESP.SetTeamEsp, state)
    end,
})
playerEspSection:AddToggle({
    Name = 'Tracers',
    Default = false,
    Callback = function(state)
        safeESP(ESP.SetTracers, state)
    end,
})
playerEspSection:AddToggle({
    Name = 'Skeleton ESP',
    Default = true,
    Callback = function(state)
        safeESP(ESP.SetSkeletonEsp, state)
    end,
})
playerEspSection:AddToggle({
    Name = 'Held Item ESP',
    Default = false,
    Callback = function(state)
        safeESP(ESP.SetHeldItemEsp, state)
    end,
})

local radarToggle = worldVisualsSection:AddToggle({
    Name = 'Radar',
    Default = settings.radar,
    Callback = function(value)
        radar = value
        updateAllRadarTags()
    end,
})

local fullBrightToggle = worldVisualsSection:AddToggle({
    Name = 'Full Bright',
    Default = settings.fullBright,
    Callback = function(value)
        if value then
            lighting.Ambient, lighting.OutdoorAmbient, lighting.Brightness, lighting.GlobalShadows, lighting.FogEnd =
                Color3.fromRGB(255, 255, 255),
                Color3.fromRGB(255, 255, 255),
                2,
                false,
                100000
        else
            lighting.Ambient, lighting.OutdoorAmbient, lighting.Brightness, lighting.GlobalShadows, lighting.FogEnd =
                originalAmbient,
                originalOutdoorAmbient,
                originalBrightness,
                originalGlobalShadows,
                originalFogEnd
        end
    end,
})

local fpsBoostToggle = worldVisualsSection:AddToggle({
    Name = 'FPS Boost',
    Default = settings.fpsBoost,
    Callback = function(value)
        fpsBoostEnabled = value
        applyFpsBoost(value)
    end,
})

local customWorldTimeToggle = worldVisualsSection:AddToggle({
    Name = 'Custom World Time',
    Default = settings.customWorldTimeEnabled,
    Callback = function(value)
        customWorldTimeEnabled = value and true or false
        if not customWorldTimeEnabled then
            lighting.ClockTime = originalClockTime
        else
            applyCustomWorldTime()
        end
    end,
})

local customWorldTimeSlider = worldVisualsSection:AddSlider({
    Name = 'World Time',
    Min = 0,
    Max = 24,
    Default = settings.customWorldTime,
    Suffix = 'h',
    Callback = function(value)
        customWorldTimeValue = value
        applyCustomWorldTime()
    end,
})

local autoSellToggle = sellsection:AddToggle({
    Name = 'Auto Sell All',
    Default = settings.autoSell,
    Callback = function(v)
        autoselling = v
    end,
})

local pzones, wzones = {}, {}
for _, v in workspace.zones.player:GetChildren() do
    table.insert(pzones, v.Name)
end
for _, v in workspace.zones.fishing:GetChildren() do
    table.insert(wzones, v.Name)
end

local playerZoneDropdown = teleportsection:AddDropdown({
    Name = 'Player Zone TP',
    Options = pzones,
    Default = table.find(pzones, settings.playerZone) or 1,
    SaveKey = 'playerZone',
    Callback = function(item)
        if workspace.zones.player:FindFirstChild(item) then
            localplr.Character:PivotTo(workspace.zones.player[item].CFrame)
        end
    end,
})

local fishingZoneDropdown = teleportsection:AddDropdown({
    Name = 'Fishing Zone TP',
    Options = wzones,
    Default = table.find(wzones, settings.fishingZone) or 1,
    SaveKey = 'fishingZone',
    Callback = function(item)
        if workspace.zones.fishing:FindFirstChild(item) then
            localplr.Character:PivotTo(workspace.zones.fishing[item].CFrame)
        end
    end,
})

local antiStaffToggle = serverHopSection:AddToggle({
    Name = 'Anti Staff',
    Default = settings.antiStaff,
    Callback = function(v)
        isAntiStaffEnabled = v
        Library:Notify({
            Title = 'ANTI STAFF',
            Text = 'STATUS: ' .. (v and 'ENABLED' or 'DISABLED'),
            Duration = 4,
            Type = 'Info',
        })
        if v then
            checkCurrentPlayers()
        end
    end,
})

local webhookInput = addTextInput(webhookSection, {
    Name = 'Webhook Catch',
    Default = settings.webhookUrl,
    Placeholder = 'Enter Webhook URL',
    SaveKey = 'webhookUrl',
})

-- Load saved values after all controls are registered.
Library:LoadConfig()

-- Background tasks
task.spawn(function()
    while task.wait() do
        if localplr.Character and localplr.Character:FindFirstChildOfClass('Humanoid') then
            if isWalkSpeedLocked then
                localplr.Character.Humanoid.WalkSpeed = currentWalkSpeed
            end
            if autoselling then
                pcall(function()
                    game.ReplicatedStorage.events.SellAll:InvokeServer()
                end)
            end
        end
    end
end)

task.spawn(function()
    while RunService.Heartbeat:Wait() do
        applyCustomWorldTime()
        if jesus and localplr.Character and localplr.Character:FindFirstChild('HumanoidRootPart') then
            local params = RaycastParams.new()
            params.FilterDescendantsInstances = { workspace.zones }
            local hrp = localplr.Character.HumanoidRootPart
            local hitPart = workspace:Raycast(
                hrp.Position,
                Vector3.new(0, -5, 0) + hrp.CFrame.LookVector * 5,
                params
            )
            if hitPart and hitPart.Material == Enum.Material.Water then
                local clone = Instance.new('Part', waterplatforms)
                clone.Position = hitPart.Position
                clone.Anchored = true
                clone.CanCollide = true
                clone.CanQuery = false
                clone.Size = Vector3.new(15, 0.2, 15)
                clone.Transparency = 1
            end
        end
    end
end)
