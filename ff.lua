local SETTINGS_FILE = 'eps1llon_forsaken3_settings.json'
local function loadRemoteUiLib()
    local baseUrl = "https://raw.githubusercontent.com/megafartCc/UiLib/main/UILibModules"
    local moduleCache = {}
    local cacheBust = "cb=" .. tostring(os.clock()):gsub("%.", "")
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
        local source = game:HttpGet(baseUrl .. "/" .. normalized .. "?" .. cacheBust)
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

task.spawn(function()
    local ok, err = pcall(function()
        local PANEL_URL = "https://panel-production-dd46.up.railway.app"
        local PANEL_SLUG = "forsaken"
        local PANEL_KEY = "DSD3213232sfdxzcvxcfhhjgfj"
        local cacheBust = tostring(os.clock()):gsub("%.", "")
        local sdk = loadstring(game:HttpGet("https://raw.githubusercontent.com/megafartCc/panel/refs/heads/main/sdk/panel_sdk.lua?cb=" .. cacheBust))()
        sdk.init(PANEL_URL, PANEL_SLUG, PANEL_KEY)
    end)
    if not ok then
        warn("[Forsaken] panel init failed:", err)
    end
end)

-------------VARIABLES------------

local Players = game:GetService("Players")
while not Players.LocalPlayer do
    task.wait()
end

local localplr = Players.LocalPlayer
local runs = game:GetService("RunService")
local uis = game:GetService("UserInputService")
local context = game:GetService("ContextActionService")
local tweens = game:GetService("TweenService")
local camera = workspace.CurrentCamera

local autoload = false

local moveonrepair = false
local noslow = false
local omnirun = false
local autoblock = false
local invisbool = false
local nofakenoli = false
local noacid = false

local gojo = {
    toggle = false,
    upsidefly = false
}
local infstamina = {
    toggle = false,
    lastcap = 100
}
local fakeblock = {
    toggle = false,
    anim = "Default"
}
local nofog = {
    toggle = false
}
local speedhack = {
    toggle = false,
    value = 1
}
local highjump = {
    toggle = false,
    value = 40
}
local infjump = {
    toggle = false,
    jumpforce = 50,
    cooldown = 0.2,
    lastjump = 0,
}
local fb = {
    toggle = false,
    real = {}
}
local autorepair = {
    toggle = false,
    delay = 5,
    hidden = false,
    closestgen = nil
}
local autopickup = {
    toggle = false,
    bloxy = false,
    medkit = false
}
local noclip = {
    toggle = false,
    inwall = false,
    nocliptime = 0,
    func = function() end
}
local esp = {
    globaltoggle = false,
    names = false,
    hp = false,
    highlight = false,
    textoutline = false,
    textsize = 14,
    chamsfill = 0.5,
    chamsline = 0,
    survivors = false,
    killers = false,
    lobby = false,
    gens = false,
    tools = false,
    teamcolor = false,
    textcolor = Color3.fromRGB(255,255,255),
    fillcolor = Color3.fromRGB(255,0,0),
    linecolor = Color3.fromRGB(255,255,255),
    table = {}
}

local animnames = {'Default', 'Milestone 4'}
local acidblocks = {}

local invisState = {
    invisblocked = false,
    noinvis = true,
}

-------------FUNCTIONS-------------

function searchplayer(model)
    for i,v in game.Players:GetPlayers() do
        if v.Character == model then
            return v
        end
    end
end

function Notify(tt, tx, dur)
    dur = dur or 4
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = tt,
        Text = tx,
        Duration = dur
    })
end

local function restartinvis(char)
    invisState.noinvis = true
    invisState.invisblocked = false

    local oldpos = char:GetPivot()

    task.wait(0.3)
    task.spawn(function()
        while runs.RenderStepped:Wait() do
            if invisState.invisblocked then break end
            char:PivotTo(char:GetPivot() * CFrame.new(0, 9e9^3,0))
        end
    end)
    task.wait(0.5)

    invisState.noinvis = false

    task.wait(1)
    char:PivotTo(oldpos)
end

local function fireprompt(prompt)
    prompt:InputHoldBegin()
    task.wait()
    prompt:InputHoldEnd()
end

function fakeBlock(act, state)
    if state ~= Enum.UserInputState.Begin then return end

    local BlockAIDs = {
        ["Default"] = "rbxassetid://" .. tostring(72722244508749),
        ["Milestone 4"] = "rbxassetid://" .. tostring(96959123077498)
    }
    if localplr.Character and localplr.Character.Name == 'Guest1337' and fakeblock then
        local animation = Instance.new("Animation")
        animation.AnimationId = BlockAIDs[fakeblock.anim]

        local anim = localplr.Character.Humanoid:LoadAnimation(animation)
        anim.Priority = Enum.AnimationPriority.Movement
        anim:Play()
    end
end

-------------GUI START--------------

local Window = Library:CreateWindow({
    Name = "UNKNOWN HUB",
    Expire = "never",
    ConfigName = "eps1llon_forsaken3",
    KeySystem = true,
    Key = "UnknownHub",
    GetKeyLink = "https://discord.com/invite/unknownhub",
})

-- / Pages
local playerPage = Window:AddMenu({ Name = 'PLAYER', Icon = 'rbxassetid://131503531968361', Columns = 2 })
local worldPage = Window:AddMenu({ Name = 'WORLD', Icon = 'rbxassetid://86586640293333', Columns = 2 })
local combatPage = Window:AddMenu({ Name = 'COMBAT', Icon = 'rbxassetid://133154037851337', Columns = 2 })
local visualPage = Window:AddMenu({ Name = 'VISUALS', Icon = 'rbxassetid://115724892413714', Columns = 2 })
local miscPage = Window:AddMenu({ Name = 'MISCELLANEOUS', Icon = 'rbxassetid://81683171903925', Columns = 2 })
local settingsPage = Window:AddMenu({ Name = 'SETTINGS', Icon = 'rbxassetid://135452049601292', Columns = 2 })

-- / Player Page Sections
local movementSection = playerPage:AddSection({ Name = 'Movement', Icon = 'rbxassetid://94367561105510', Column = 1 })

-- / World Page Sections
local generatorSection = worldPage:AddSection({ Name = 'Generators', Icon = 'rbxassetid://129850476577518', Column = 1 })
local pickupsSection = worldPage:AddSection({ Name = 'Pickups', Icon = 'rbxassetid://112316847300016', Column = 1 })
local environmentSection = worldPage:AddSection({ Name = 'Environment', Icon = 'rbxassetid://139777701329740', Column = 2 })

-- / Combat Page Sections
local blockingSection = combatPage:AddSection({ Name = 'Blocking', Icon = 'rbxassetid://86716534900228', Column = 1 })
local attacksection = combatPage:AddSection({ Name = 'Attacking', Icon = 'rbxassetid://86716534900228', Column = 2 })

-- / Visuals Page Sections
local espEntitiesSection = visualPage:AddSection({ Name = 'ESP Entities', Icon = 'rbxassetid://139777701329740', Column = 1 })
local espAppearanceSection = visualPage:AddSection({ Name = 'ESP Appearance', Icon = 'rbxassetid://139777701329740', Column = 2 })
local camerasection = visualPage:AddSection({ Name = 'Camera', Icon = 'rbxassetid://131994949129165', Column = 2 })

-- / Miscellaneous Page Sections
local miscSection = miscPage:AddSection({ Name = 'Exploits', Icon = 'rbxassetid://93815946105615', Column = 1 })

----------------------------------
-- / PLAYER PAGE
----------------------------------

movementSection:AddToggle({
    Name = 'SpeedHack',
    Default = false,
    SaveKey = 'speedtoggle',
    WaitForCallback = false,
    Callback = function(v)
        speedhack.toggle = v
        applyspeed()
    end
})
movementSection:AddSlider({
    Name = 'Speed Boost',
    Default = 1,
    Min = 0,
    Max = 5,
    Decimals = 1,
    SaveKey = 'speedboost',
    Callback = function(c)
        speedhack.value = c
    end
})
movementSection:AddToggle({
    Name = 'Inf Jump',
    Default = false,
    SaveKey = 'infjump',
    Callback = function(v)
        infjump.toggle = v
    end
})
movementSection:AddToggle({
    Name = 'Allow jump [risky]',
    Default = false,
    SaveKey = 'jumptoggle',
    Callback = function(v)
        highjump.toggle = v
        pcall(function()
            game.Players.LocalPlayer.Character.Humanoid.UseJumpPower = v
        end)

        while highjump.toggle and task.wait(5) do
            pcall(function()
                game.Players.LocalPlayer.Character.Humanoid.JumpPower = highjump.value
            end)
        end
    end
})
movementSection:AddSlider({
    Name = 'Jump height',
    Default = 40,
    Min = 10,
    Max = 50,
    Decimals = 1,
    SaveKey = 'jumpheight',
    Callback = function(c)
        highjump.value = c
        pcall(function()
            game.Players.LocalPlayer.Character.Humanoid.JumpPower = highjump.value
        end)
    end
})
movementSection:AddToggle({
    Name = 'Inf Stamina',
    Default = false,
    SaveKey = 'infstamina',
    Callback = function(v)
        infstamina.toggle = v

        if not v then
            local dd = require(game.ReplicatedStorage.Systems.Character.Game.Sprinting)
            dd.StaminaCap = infstamina.lastcap
            dd.Stamina = 100
        end
    end
})
movementSection:AddToggle({
    Name = 'Omni-Run',
    Default = false,
    SaveKey = 'omnirun',
    Callback = function(v)
        omnirun = v
    end
})
movementSection:AddToggle({
    Name = 'No Slowness',
    Default = false,
    SaveKey = 'noslow',
    Callback = function(v)
        noslow = v
    end
})
movementSection:AddToggle({
    Name = 'Gojo Edit',
    Default = false,
    SaveKey = 'gojotoggle',
    Callback = function(v)
        gojo.toggle = v
    end
})
movementSection:AddToggle({
    Name = 'Gojo Fly',
    Default = false,
    SaveKey = 'gojofly',
    Callback = function(v)
        gojo.upsidefly = v
    end
})

----------------------------------
-- / WORLD PAGE
----------------------------------

generatorSection:AddToggle({
    Name = 'Auto repair',
    Default = false,
    SaveKey = 'autorep',
    Callback = function(v)
        autorepair.toggle = v
    end
})
generatorSection:AddToggle({
    Name = 'Move on repair',
    Default = false,
    SaveKey = 'moveonrepair',
    Callback = function(v)
        moveonrepair = v
    end
})
generatorSection:AddSlider({
    Name = 'AutoRepair delay',
    Default = 5,
    Min = 1.6,
    Max = 10,
    Decimals = 1,
    SaveKey = 'repdelay',
    Callback = function(c)
        autorepair.delay = c
    end
})


pickupsSection:AddToggle({
    Name = 'Auto pickup',
    Default = false,
    SaveKey = 'autopickup',
    Callback = function(v)
        autopickup.toggle = v
    end
})
pickupsSection:AddToggle({
    Name = 'Pickup cola',
    Default = false,
    SaveKey = 'bloxypickup',
    Callback = function(v)
        autopickup.bloxy = v
    end
})
pickupsSection:AddToggle({
    Name = 'Pickup medkit',
    Default = false,
    SaveKey = 'medpickup',
    Callback = function(v)
        autopickup.medkit = v
    end
})


environmentSection:AddToggle({
    Name = 'Fullbright',
    Default = false,
    SaveKey = 'fullbright',
    WaitForCallback = false,
    Callback = function(v)
        fb.toggle = v
        local lig = game.Lighting
        if not fb.toggle then
            lig.Brightness = fb.real['Brightness']
            lig.OutdoorAmbient = fb.real['OutdoorAmbient']
            lig.Ambient = fb.real['Ambient']
            lig.ExposureCompensation = fb.real['ExposureCompensation']
        else
            while fb.toggle and task.wait(1) do
                lig.Brightness = 0
                lig.OutdoorAmbient = Color3.new(1,1,1)
                lig.Ambient = Color3.new(1,1,1)
                lig.ExposureCompensation = 1
            end
        end
    end
})
environmentSection:AddToggle({
    Name = 'No fog',
    Default = false,
    SaveKey = 'disablefog',
    WaitForCallback = false,
    Callback = function(v)
        nofog.toggle = v
        while nofog.toggle and task.wait(1) do
            game.Lighting.FogEnd = 100000
            for i,v in pairs(game.Lighting:GetDescendants()) do
                if v:IsA("Atmosphere") then
                    v.Density = 0
                end
            end
        end
    end
})
environmentSection:AddToggle({
    Name = 'No Fake Noli',
    Default = false,
    SaveKey = 'nofakenoli',
    Callback = function(v)
        nofakenoli = v
    end
})
environmentSection:AddToggle({
    Name = 'No Acid',
    Default = false,
    SaveKey = 'noacid',
    Callback = function(v)
        noacid = v
    end
})

----------------------------------
-- / COMBAT PAGE
----------------------------------

blockingSection:AddDropdown({
    Name = 'Fake block Animation',
    Items = animnames,
    Default = 1,
    SaveKey = 'fakeblockanimtype',
    Callback = function(value)
        fakeblock.anim = value
    end
})
blockingSection:AddToggle({
    Name = 'Fake Block [B]',
    Default = false,
    SaveKey = 'fakeblock',
    Callback = function(v)
        fakeblock.toggle = v
        if v then
            context:BindAction("FAKEBLOCKEZ", fakeBlock, true, Enum.KeyCode.B)
        else
            context:UnbindAction("FAKEBLOCKEZ")
        end
    end
})
blockingSection:AddToggle({
    Name = 'Auto Block',
    Default = false,
    SaveKey = 'autoblock',
    Callback = function(v)
        autoblock = v
    end
})

----------------------------------
-- / VISUALS PAGE
----------------------------------

espEntitiesSection:AddToggle({
    Name = 'Toggle ESP',
    Default = false,
    SaveKey = 'esp',
    Callback = function(v)
        esp.globaltoggle = v
    end
})
espEntitiesSection:AddToggle({
    Name = 'Show survivors',
    Default = false,
    SaveKey = 'espsurvs',
    Callback = function(v)
        esp.survivors = v
    end
})
espEntitiesSection:AddToggle({
    Name = 'Show spectators',
    Default = false,
    SaveKey = 'espspecs',
    Callback = function(v)
        esp.lobby = v
    end
})
espEntitiesSection:AddToggle({
    Name = 'Show killers',
    Default = false,
    SaveKey = 'espkillers',
    Callback = function(v)
        esp.killers = v
    end
})
espEntitiesSection:AddToggle({
    Name = 'Show generators',
    Default = false,
    SaveKey = 'espgens',
    Callback = function(v)
        esp.gens = v
    end
})
espEntitiesSection:AddToggle({
    Name = 'Show items',
    Default = false,
    SaveKey = 'espitems',
    Callback = function(v)
        esp.tools = v
    end
})


espAppearanceSection:AddToggle({
    Name = 'Name',
    Default = false,
    SaveKey = 'espnames',
    Callback = function(v)
        esp.names = v
    end
})
espAppearanceSection:AddToggle({
    Name = 'HP',
    Default = false,
    SaveKey = 'esphps',
    Callback = function(v)
        esp.hp = v
    end
})
espAppearanceSection:AddToggle({
    Name = 'Chams',
    Default = false,
    SaveKey = 'espchams',
    Callback = function(v)
        esp.highlight = v
    end
})
espAppearanceSection:AddToggle({
    Name = 'Text outline',
    Default = false,
    SaveKey = 'espoutline',
    Callback = function(v)
        esp.textoutline = v
    end
})
espAppearanceSection:AddToggle({
    Name = 'Teamcolors',
    Default = false,
    SaveKey = 'espteamcolors',
    Callback = function(v)
        esp.teamcolor = v
    end
})
espAppearanceSection:AddSlider({
    Name = 'Text Size',
    Default = 14,
    Min = 1,
    Max = 35,
    Decimals = 1,
    SaveKey = 'esptextsize',
    Callback = function(c)
        esp.textsize = c
    end
})
espAppearanceSection:AddSlider({
    Name = 'Chams Outline Transparency',
    Default = 0,
    Min = 0,
    Max = 1,
    Decimals = 2,
    SaveKey = 'espchamsoutlie',
    Callback = function(c)
        esp.chamsline = c
    end
})
espAppearanceSection:AddSlider({
    Name = 'Chams Fill Transparency',
    Default = 0.5,
    Min = 0,
    Max = 1,
    Decimals = 2,
    SaveKey = 'espchamsfill',
    Callback = function(c)
        esp.chamsfill = c
    end
})


camerasection:AddSlider({
    Name = 'Custom FOV',
    Default = 80,
    Min = 1,
    Max = 120,
    Decimals = 0,
    SaveKey = 'customfov',
    Callback = function(c)
        localplr.PlayerData.Settings.Game.FieldOfView.Value = c
    end
})

----------------------------------
-- / EXPLOITS PAGE
----------------------------------

miscSection:AddToggle({
    Name = 'Invisible',
    Default = false,
    SaveKey = 'invis',
    Callback = function(v)
        invisbool = v
        if not v then
            invisState.noinvis = true
            return
        end
        if localplr.Character and localplr.Character.Parent.Name ~= "Spectating" then
            restartinvis(localplr.Character)
        end
    end
})
miscSection:AddToggle({
    Name = 'Noclip',
    Default = false,
    SaveKey = 'noclip',
    WaitForCallback = false,
    Callback = function(v)
        noclip.toggle = v
        if v then
            task.spawn(noclip.func)
        end
    end
})

----------------------------------
-- / SETTINGS PAGE
----------------------------------

local configsection = settingsPage:AddSection({
    Name = 'Configuration',
    Icon = 'rbxassetid://86277109949371',
    Column = 1,
})
configsection:AddToggle({
    Name = 'Auto Reload',
    Default = false,
    SaveKey = 'autoreload',
    Callback = function(v)
        autoload = v
    end
})
--------SPEEDHACK---------

function applyspeed()
    local chr = localplr.Character
    local hum = chr and chr:FindFirstChildOfClass("Humanoid")
    while speedhack.toggle do
        if not hum or not chr or not chr.Parent then
            chr = localplr.Character
            hum = chr and chr:FindFirstChildOfClass("Humanoid")
            continue
        end

        local delta = runs.Heartbeat:Wait()
        if hum.MoveDirection.Magnitude > 0 then
            chr:TranslateBy(hum.MoveDirection * speedhack.value * delta * 10)
        end
    end
end

--------INFINITE JUMP--------
uis.JumpRequest:Connect(function()
    if not infjump.toggle then return end
    if tick() - infjump.lastjump < infjump.cooldown then return end

    local character = localplr.Character
    local rootPart = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not rootPart or not humanoid then return end
    if humanoid:GetState() == Enum.HumanoidStateType.Dead then return end

    infjump.lastjump = tick()

    local velocity = Instance.new("BodyVelocity")
    velocity.Name = "UnknownHubInfJumpVelocity"
    velocity.Velocity = Vector3.new(0, infjump.jumpforce, 0)
    velocity.MaxForce = Vector3.new(0, 9000, 0)
    velocity.P = 1250
    velocity.Parent = rootPart

    task.delay(0.1, function()
        if velocity and velocity.Parent then
            velocity:Destroy()
        end
    end)
end)

--------FULLBRIGHT-------
fb.real["Brightness"] = game.Lighting.Brightness
fb.real["OutdoorAmbient"] = game.Lighting.OutdoorAmbient
fb.real["Ambient"] = game.Lighting.Ambient
fb.real["ExposureCompensation"] = game.Lighting.ExposureCompensation

game.Lighting:GetPropertyChangedSignal("Brightness"):Connect(function()
    if fb.toggle then
        if game.Lighting.Brightness ~= 0 then
            fb.real["Brightness"] = game.Lighting.Brightness
            fb.real["OutdoorAmbient"] = game.Lighting.OutdoorAmbient
            fb.real["Ambient"] = game.Lighting.Ambient
            fb.real["ExposureCompensation"] = 0
        end
    else
        fb.real["Brightness"] = game.Lighting.Brightness
        fb.real["OutdoorAmbient"] = game.Lighting.OutdoorAmbient
        fb.real["Ambient"] = game.Lighting.Ambient
        fb.real["ExposureCompensation"] = game.Lighting.ExposureCompensation
    end
end)

--------ESP--------
function isonscreen(object)
    local _, bool = camera:WorldToScreenPoint(object.Position)
    return bool
end
function setupesp(obj, dtype, otype1)
    if not obj then return end

    local configs = {
        Name = { size = esp.textsize + 2 },
        HP = { size = esp.textsize },
        Highlight = {}
    }

    local dobj, tableinfo

    if dtype == "Highlight" then
        dobj = Instance.new("Highlight")
        dobj.Name = "ardour highlight"
        dobj.FillColor = esp.fillcolor
        dobj.OutlineColor = esp.linecolor
        dobj.FillTransparency = esp.chamsfill
        dobj.OutlineTransparency = esp.chamsline
        
        if obj.Parent:IsA("Model") then
            dobj.Parent = obj.Parent
        else
            dobj:Destroy()
            return
        end
        
        dobj.Enabled = esp.highlight
    elseif configs[dtype] then
        dobj = Drawing.new("Text")
        dobj.Font = Drawing.Fonts.Monospace
        dobj.Center = true
        dobj.Outline = esp.textoutline
        dobj.Size = configs[dtype].size
        dobj.Color = esp.textcolor
        dobj.OutlineColor = Color3.new(0, 0, 0)
        dobj.Visible = esp.globaltoggle
    end

    if not dobj then return end

    tableinfo = {
        primary = obj,
        type = dtype,
        otype = otype1,
        parent =  obj.Parent
    }

    local removing
    local function selfdestruct()
        if dtype == "Highlight" then
            dobj.Enabled = false
            dobj:Destroy()
        else
            dobj.Visible = false
            dobj:Remove()
        end
        if removing then
            removing:Disconnect()
            removing = nil
        end
    end

    if esp.table[dobj] then
        selfdestruct()
        return
    end

    esp.table[dobj] = tableinfo

    removing = obj.AncestryChanged:Connect(function(_, parent)
        if not parent or not obj:IsDescendantOf(workspace) then
            esp.table[dobj] = nil
            selfdestruct()
        end
    end)
end
function startesp(v, otype)
    if not v then return end

    for _, info in pairs(esp.table) do
        if info.primary == v and info.otype == otype then
            return
        end
    end

    task.spawn(function()
        setupesp(v, "Name", otype)
        setupesp(v, "HP", otype)
        setupesp(v, "Highlight", otype) 
    end)
end
function espinstancecheck(inst)
    if inst.Parent == nil then return end

    local plrmaybe = searchplayer(inst.Parent)
    if inst.Name == "HumanoidRootPart" and plrmaybe ~= nil and plrmaybe ~= localplr then
        startesp(inst, "Plr")
    elseif inst.Name == "Main" and inst.Parent and inst.Parent.Name == "Generator" then
        startesp(inst, "Gen")
    elseif inst.Name == "ItemRoot" and (inst.Parent.Parent.Name == "Ingame" or inst.Parent.Parent.Name == "Map" or inst.Parent.Parent == workspace) then
        startesp(inst, "Tool")
    end
end
for i,v in pairs(workspace:GetDescendants()) do
    espinstancecheck(v)
end
workspace.DescendantAdded:Connect(function(v)
    espinstancecheck(v)
end)
task.spawn(function()
    while wait(2) do
        for i,v in workspace.Players:GetDescendants() do
            local plrmb = searchplayer(v)
            if v:IsA("Model") and plrmb ~= nil and plrmb ~= localplr and not v:FindFirstChild("ardour highlight") then
                espinstancecheck(v.HumanoidRootPart)
            end
        end
    end
end)

function esp.remove(dobj, dtype)
    esp.table[dobj] = nil
    if dtype == "Highlight" then
        pcall(function()
            dobj.Enabled = false
            dobj:Destroy()
        end)
    else
        pcall(function()
            dobj.Visible = false
            dobj:Remove()
        end)
    end
end
function esp.setvisible(dobj, dtype, visible)
    pcall(function()
        if dtype == "Highlight" then
            dobj.Enabled = visible
        else
            dobj.Visible = visible
        end
    end)
end

runs.RenderStepped:Connect(function()
    if not localplr.Character or not localplr.Character:FindFirstChild("HumanoidRootPart") then
        return
    end

    for dobj, info in pairs(esp.table) do
        local dtype = info.type
        local otype = info.otype
        local obj = info.primary
        local parentmodel = info.parent

        if not obj or not obj.Parent or not obj.Parent.Parent then
            esp.remove(dobj, dtype)
            continue 
        end

        local team = obj.Parent.Parent and obj.Parent.Parent.Name
        local isKiller = team == "Killers"
        local isSurvivor = team == "Survivors"
        local isSpectating = team == "Spectating"
        local isGen = otype == "Gen"
        local isTool = otype == "Tool"

        if info.primary == nil or info.primary.Parent == nil then
            esp.remove(dobj, dtype)
            continue
        end
    
        local isHumanoid = (isGen or isTool) or obj.Parent:FindFirstChild("Humanoid")
        if not isHumanoid and not isGen then
            esp.remove(dobj, dtype)
            continue
        end
        
        if isTool and (dtype == "HP" or obj.Parent.Name == "Ingame") then
            esp.remove(dobj, dtype)
            continue
        end
    
        if not (esp.globaltoggle and isonscreen(obj) and isHumanoid) then
            esp.setvisible(dobj, dtype, false)
            continue
        end
        
        if (isKiller and not esp.killers) or 
            (isSurvivor and not esp.survivors) or 
            (isSpectating and not esp.lobby) or 
            (isGen and not esp.gens) or
            (isTool and not esp.tools) then
            esp.setvisible(dobj, dtype, false)
            continue
        end
    
        local headpos = camera:WorldToViewportPoint(obj.Position)
        local resultpos = Vector2.new(headpos.X, headpos.Y)
        
        local teamcolor
        if esp.teamcolor then
            if isGen then
                teamcolor = Color3.new(0, 0, 1)
            elseif isKiller then
                teamcolor = Color3.new(1, 0, 0)
            elseif isSurvivor then
                teamcolor = Color3.new(0, 1, 0)
            else
                teamcolor = Color3.new(1, 1, 1)
            end
        end

        pcall(function()
            if dtype == "Name" then
                if esp.names then
                    resultpos = resultpos - Vector2.new(0, 15)
                    dobj.Text = (isGen or isTool) and obj.Parent.Name or (not isSpectating and searchplayer(obj.Parent).Name .." ("..obj.Parent.Name..")" or obj.Parent.Name)
                    dobj.Position = resultpos
                    dobj.Size = esp.textsize + 2
                    dobj.Color = esp.textcolor
                    dobj.Outline = esp.textoutline
                    dobj.Visible = true
                else
                    dobj.Visible = false
                end
            elseif dtype == "HP" then
                resultpos = resultpos - Vector2.new(0, 30)
                local plrhp = isGen and "Progress : "..obj.Parent.Progress.Value or math.floor(obj.Parent.Humanoid.Health).."HP"
                dobj.Text = plrhp
                dobj.Position = resultpos
                dobj.Size = esp.textsize
                dobj.Color = esp.textcolor
                dobj.Visible = esp.hp
                dobj.Outline = esp.textoutline
            elseif dtype == "Highlight" then
                if esp.teamcolor then
                    dobj.FillColor = teamcolor
                    dobj.OutlineColor = teamcolor
                else
                    dobj.FillColor = esp.fillcolor
                    dobj.OutlineColor = esp.linecolor
                end
                dobj.FillTransparency = esp.chamsfill
                dobj.OutlineTransparency = esp.chamsline
                dobj.Enabled = esp.highlight
                dobj.Adornee = dobj.Parent
            end
        end)
    end
end)

--------AUTO REPAIR--------
task.spawn(function()
    while task.wait(autorepair.delay) do
        if not autorepair.closestgen or not autorepair.closestgen:FindFirstChild("Remotes") then
            continue
        end

        if autorepair.toggle then
            autorepair.closestgen.Remotes.RE:FireServer()
        end
    end
end)
task.spawn(function()
    while task.wait(0.5) do
        if localplr.Character == nil or not localplr.Character:FindFirstChild("HumanoidRootPart") then continue end
        if not autorepair.toggle then
            autorepair.closestgen = nil
            continue
        end

        local dist = 9e9
        local closest = nil
        for _, gen in workspace.Map.Ingame:GetDescendants() do
            if gen.Name == "Generator" and gen:FindFirstChild("Remotes") then
                local localdist = (localplr.Character.HumanoidRootPart.Position - gen.Main.Position).Magnitude or 9e9
                
                if localdist < dist then
                    dist = localdist
                    closest = gen
                end
            end
        end
        
        autorepair.closestgen = closest
    end
end)

----------NOCLIP----------
task.spawn(function()
    while wait(1) do
        if localplr.Character then
            local noclipdetector = localplr.Character:WaitForChild("NoclipDetector",2)
            if not noclipdetector then continue end
            noclipdetector:Destroy()
        end
    end
end)
task.spawn(function()
    while task.wait(0.1) do
        if noclip.nocliptime > 0 and noclip.inwall == false then
            noclip.nocliptime = math.clamp(noclip.nocliptime - 0.1, 0, 10)
        end
    end
end)
function noclip.func()
    local nclipparts = {}
    local hint = Instance.new("Hint")
    hint.Parent = game.ReplicatedStorage
    
    local function checknoclip()
        if not localplr.Character then return end

        noclip.inwall = false
        for _, part in pairs(workspace:GetPartsInPart(localplr.Character.HumanoidRootPart)) do
            if part.CanCollide == true and part ~= localplr.Character.HumanoidRootPart and not part:IsDescendantOf(localplr.Character) then
                noclip.inwall = true
            end
        end
        
        if noclip.inwall then
            noclip.nocliptime += 0.02
            hint.Text = "Noclip detect is possible at " .. math.floor(noclip.nocliptime) .. "s"
            hint.Parent = localplr.PlayerGui

            if noclip.nocliptime >= 2 then
                noclip.toggle = false
                hint.Text = "Noclip disabled - player inside object for too long"
                wait(1.5)
                hint.Parent = game.ReplicatedStorage
                return
            end
        else
            hint.Parent = game.ReplicatedStorage
        end
    end
    
    local function loop()
        if localplr.Character ~= nil then
            for _, child in pairs(localplr.Character:GetDescendants()) do
                if child:IsA("BasePart") and child.CanCollide == true then
                    child.CanCollide = false
                    table.insert(nclipparts, child)
                end
            end
        end
    end
    
    while noclip.toggle do
        loop()
        checknoclip()
        task.wait(0.01)
    end

    for _, child in ipairs(nclipparts) do
        if child and child.Parent then
            child.CanCollide = true
        end
    end

    hint:Destroy()
    noclip.nocliptime = 0
end

----INFINITE STAMINA----
task.spawn(function()
    local dd = require(game.ReplicatedStorage.Systems.Character.Game.Sprinting)
    while wait(0.5) do
        if infstamina.toggle then
            if dd.StaminaCap ~= 99999 then
                infstamina.lastcap = dd.StaminaCap
            end
            dd.Stamina = 99999
            dd.StaminaCap = 99999
        elseif dd.StaminaCap == 110 or dd.StaminaCap == 100 then
            infstamina.lastcap = dd.StaminaCap
        end
    end
end)

----NO SLOWNESS----
local function filterslow(v)
    if not noslow then return end
    if v.Name ~= "DirectionalMovement" and v.Name ~= "Sprinting" then
        v.Value = 1
        v.Changed:Connect(function()
            v.Value = 1
        end)
    end
end
if localplr.Character and localplr.Character:FindFirstChild("SpeedMultipliers") then
    localplr.Character.SpeedMultipliers.ChildAdded:Connect(function(v)
        filterslow(v)
    end)
    for _, child in ipairs(localplr.Character.SpeedMultipliers:GetChildren()) do
        filterslow(child)
    end
end
localplr.CharacterAdded:Connect(function(char)
    task.wait(0.5)
    char:WaitForChild("SpeedMultipliers")
    char.SpeedMultipliers.ChildAdded:Connect(function(v)
        filterslow(v)
    end)
    for _, child in ipairs(char.SpeedMultipliers:GetChildren()) do
        filterslow(child)
    end
end)

----OMNI RUN----
local function omnihandler(char)
    local speedMultipliers = char:WaitForChild("SpeedMultipliers")
    local dirmov = speedMultipliers:WaitForChild("DirectionalMovement")

    local humanoid = char:WaitForChild("Humanoid")
    local hrp = char:WaitForChild("HumanoidRootPart")

    local function apply()
        if not omnirun then return end
        if dirmov.Value ~= 1 then
            dirmov.Value = 1
        end
    end

    dirmov.Changed:Connect(apply)
    humanoid.Running:Connect(function()
        apply()
    end)
end

if localplr.Character then
    omnihandler(localplr.Character)
end
localplr.CharacterAdded:Connect(function(char)
    task.wait(0.5)
    omnihandler(char)
end)

----AUTO PICKUP----
task.spawn(function()
    while wait(0.05) do
        if not autopickup.toggle then continue end
        if not localplr.Character or not localplr.Character.Parent or localplr.Character.Parent.Name == "Spectating" then continue end

        local map = workspace.Map.Ingame:FindFirstChild('Map')
        if not map then continue end

        if autopickup.bloxy then
            for _, item in ipairs(map:GetChildren()) do
                if item:IsA('Tool') and item.Name == 'BloxyCola' and item:FindFirstChild('ItemRoot') and item.ItemRoot:FindFirstChildOfClass('ProximityPrompt') then
                    fireprompt(item.ItemRoot:FindFirstChildOfClass('ProximityPrompt'))
                end
            end
        end
        if autopickup.medkit then
            for _, item in ipairs(map:GetChildren()) do
                if item:IsA('Tool') and item.Name == 'Medkit' and item:FindFirstChild('ItemRoot') and item.ItemRoot:FindFirstChildOfClass('ProximityPrompt') then
                    fireprompt(item.ItemRoot:FindFirstChildOfClass('ProximityPrompt'))
                end
            end
        end
    end
end)

----AUTO BLOCK----
function doblock(killer)
    if not localplr.Character or not localplr.Character.Name == 'Guest1337' then return end
    local dist = (localplr.Character.HumanoidRootPart.CFrame.Position - killer.HumanoidRootPart.CFrame.Position).Magnitude
    if dist <= 7 then
        game.ReplicatedStorage.Modules.Network.RemoteEvent:FireServer("UseActorAbility", {'Block'})
    end
end
local attackanims = {
    "rbxassetid://18885909645",
    "rbxassetid://105458270463374",
    "rbxassetid://106538427162796",
    "rbxassetid://83829782357897",
    "rbxassetid://126830014841198"
}
task.spawn(function()
    while game:GetService("RunService").Heartbeat:Wait() do
        if not autoblock then continue end
    
        local killer = workspace.Players.Killers:FindFirstChildOfClass("Model")
        if not killer or not killer:FindFirstChild("Humanoid") then continue end
      
        for i,v in pairs(killer.Humanoid.Animator:GetPlayingAnimationTracks()) do
            if table.find(attackanims, v.Animation.AnimationId) ~= nil then
                doblock(killer)
            end
        end
    end
end)


----INVIS----
if localplr.Character then
    localplr.Character.HumanoidRootPart:GetPropertyChangedSignal("Anchored"):Connect(function()
        if localplr.Character.HumanoidRootPart.Anchored == false and invisbool then
            restartinvis(localplr.Character)
        end
    end)
end
localplr.CharacterAdded:Connect(function(char)
    if not invisbool then return end

    task.wait(1)
    if char.Parent.Name == "Spectating" then return end
    restartinvis(char)

    char.HumanoidRootPart:GetPropertyChangedSignal("Anchored"):Connect(function()
        if char.HumanoidRootPart.Anchored == false and invisbool then
            restartinvis(char)
        end
    end)
end)

----NO FAKE NOLI----
task.spawn(function()
    while wait(1) do
        if not nofakenoli then continue end
        if not workspace.Players.Killers:FindFirstChild("Noli") then continue end

        for i,v in workspace.Players.Killers:GetChildren() do
            if not game.Players:GetPlayerFromCharacter(v) then
                v:Destroy()
            end
        end
    end
end)

----NO ACID----
task.spawn(function()
    while wait(3) do
        if not noacid then
            for i,v in acidblocks do
                v:Destroy()
            end
            continue
        end
        for i,v in workspace.Map.Ingame:GetDescendants() do
            if v:IsA("Part") and v.Name == "Acid" and not acidblocks[v] then
                local replace = v:Clone()
                replace.Size += Vector3.new(0,1,0)
                acidblocks[v] = replace
            end
        end
    end
end)

----GOJO FUNCTIONS----
uis.InputBegan:Connect(function(input,gpe)
	if gpe then return end
	if not localplr.Character or not localplr.Character:FindFirstChild("Humanoid") then return end
    if not gojo.toggle then return end

	if input.KeyCode == Enum.KeyCode.Y then --gojo fly
        if not gojo.upsidefly then return end

        local anim = Instance.new("Animation")
        anim.AnimationId = 'rbxassetid://181526230'
        local track = localplr.Character.Humanoid.Animator:LoadAnimation(anim)
        track.Priority = Enum.AnimationPriority.Action4

		local killer = workspace.Players.Killers:FindFirstChildOfClass("Model")
		local oldjp = localplr.Character.Humanoid.JumpPower
		local oldjpenabled = localplr.Character.Humanoid.UseJumpPower

        localplr.Character.Humanoid.UseJumpPower = true
		localplr.Character.Humanoid.JumpPower = 50
		workspace.Gravity = 65
        localplr.Character.Humanoid:ChangeState("Jumping")
		task.wait(0.15)

		local bodyGyro = Instance.new("AlignOrientation")
		bodyGyro.Mode = Enum.OrientationAlignmentMode.OneAttachment
		bodyGyro.Attachment0 = localplr.Character.HumanoidRootPart:FindFirstChildOfClass("Attachment")
		bodyGyro.Responsiveness = 200
        bodyGyro.MaxTorque = 1000000000
		bodyGyro.Parent = localplr.Character.HumanoidRootPart

        local bodypos = Instance.new("AlignPosition")
        bodypos.Mode = Enum.PositionAlignmentMode.OneAttachment
        bodypos.Attachment0 = localplr.Character.HumanoidRootPart:FindFirstChildOfClass("Attachment")
        bodypos.Parent = localplr.Character.HumanoidRootPart
        bodypos.Responsiveness = 200
        bodypos.MaxForce = 1000000000
		
		local targetAngle = CFrame.Angles(math.rad(80), 0, 0)
        track:Play(0.1, 1, 1)
        bodypos.Enabled = true
        bodypos.Position = (localplr.Character.HumanoidRootPart.CFrame * targetAngle).Position
		bodyGyro.CFrame = localplr.Character.HumanoidRootPart.CFrame * targetAngle
        
		task.wait(0.2)

		local cf = localplr.Character.HumanoidRootPart.CFrame
		task.spawn(function()
			while task.wait() do
				if cf == nil then break end
				
				if killer and killer:FindFirstChild("HumanoidRootPart") then
					local targetpos = killer.HumanoidRootPart.Position
					local targetflat = Vector3.new(targetpos.X, cf.Y, targetpos.Z)
					local direction = (targetflat - cf.Position).Unit
					cf = CFrame.lookAt(cf.Position, cf.Position - direction) * CFrame.new(0,-0.0035,0)
                else
                    cf = cf * CFrame.new(0,-0.0035,0)
				end

                cf *= targetAngle
				
				--localplr.Character.HumanoidRootPart.CFrame = cf
                bodypos.Position = cf.Position
				bodyGyro.CFrame = cf
			end
		end)

		task.wait(1.5)
		cf = nil
		bodyGyro:Destroy()
        bodypos:Destroy()
        track:Stop()
		
		localplr.Character.HumanoidRootPart.AssemblyLinearVelocity = Vector3.zero
		wait()
        workspace.Gravity = 196.1999969482422
		localplr.Character.Humanoid:ChangeState("GettingUp")

		localplr.Character.Humanoid.UseJumpPower = oldjpenabled
		localplr.Character.Humanoid.JumpPower = oldjp
	end
end)


----REMOTE HOOK HANDLER----
ogcf = hookmetamethod(game, "__namecall", function(self, ...)
    local method = getnamecallmethod()
    local args = {...}
    if method == "FireServer" then
        if args[1] == "UpdCF" and invisState.noinvis == false and invisbool then -- INVIS (BLOCKER)
            invisState.invisblocked = true
            args[2] = { buffer.fromstring("{\"m\":null,\"t\";\"buffеr\",\"base64\";\"UriawwAAIkIfhXfC+Sb//1v9ASDGGDSFGGSDF\"}") }

            return ogcf(self, unpack(args))
        end
    end
    return ogcf(self, ...)
end)


----AUTO RELOAD----
local script_key = script_key or "YOUR_KEY_HERE"
game.Players.PlayerRemoving:Connect(function(plr)
    if plr ~= localplr then return end
    if not autoload then return end
 
    queue_on_teleport([[
        task.wait(5)
        local autoloading = ]] .. (autoload and "true" or "false") .. [[
        if not autoloading then return end
        script_key="]] .. script_key .. [[";
        loadstring(game:HttpGet("https://api.luarmor.net/files/v3/loaders/74106c5013c1ea04f6737962177d8e65.lua"))()
    ]])
end)

----LOAD CONFIG----





