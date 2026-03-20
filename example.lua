--[[
    UILib Full Example
    Execute this file directly (or via raw GitHub URL) to test all core controls.
]]

local UI_LIB_REF = "main"

local function loadRemoteUiLib(ref)
    local baseUrl = "https://raw.githubusercontent.com/megafartCc/UiLib/" .. tostring(ref or "main") .. "/UILibModules"
    local moduleCache = {}
    local cacheBust = "cb=" .. tostring(os.clock()):gsub("%.", "")

    local function normalizePath(path)
        local parts = {}
        local normalized = tostring(path or ""):gsub("\\", "/")
        for part in normalized:gmatch("[^/]+") do
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
        if moduleCache[normalized] ~= nil then
            return moduleCache[normalized]
        end

        local source = game:HttpGet(baseUrl .. "/" .. normalized .. "?" .. cacheBust)
        local chunk, err = loadstring(source)
        if not chunk then
            error(("UiLib load failed for %s: %s"):format(normalized, tostring(err)))
        end

        local exported = chunk()
        moduleCache[normalized] = exported
        return exported
    end

    local entryModule = loadRemoteModule("init.lua")
    return entryModule(function(relativePath)
        return loadRemoteModule(relativePath)
    end)
end

local Library = loadRemoteUiLib(UI_LIB_REF)

Library.Config.WindowWidth = 980
Library.Config.WindowHeight = 620
Library.Config.MinWindowWidth = 640
Library.Config.MinWindowHeight = 420

local Window = Library:CreateWindow({
    Name = "UNKNOWN HUB",
    Expire = "never",
    ConfigName = "uilib_example",
})

Library:Notify({
    Title = "UILib",
    Text = "example.lua loaded",
    Duration = 2.5,
})

local Automation = Window:AddMenu({ Name = "AUTOMATION", Columns = 3 })
local Visuals = Window:AddMenu({ Name = "VISUALS", Columns = 3 })
local Misc = Window:AddMenu({ Name = "MISC", Columns = 3 })

-- AUTOMATION
local Stealer = Automation:AddSection({ Name = "STEALER", Column = 1 })
local Filters = Automation:AddSection({ Name = "FILTERS", Column = 2 })
local Actions = Automation:AddSection({ Name = "ACTIONS", Column = 3 })

local autoSteal = Stealer:AddToggle({
    Name = "Auto Steal",
    Default = false,
    Callback = function(v)
        print("[example] Auto Steal:", v)
    end,
})

autoSteal:AddDropdown({
    Name = "Teleport Method",
    Options = { "Regular", "Bypass V2", "Pathfind" },
    Default = "Regular",
    Callback = function(v)
        print("[example] Teleport Method:", v)
    end,
})

autoSteal:AddSlider({
    Name = "Range",
    Min = 10,
    Max = 500,
    Default = 120,
    Suffix = " stud",
    Callback = function(v)
        print("[example] Range:", v)
    end,
})

autoSteal:AddColorPicker({
    Name = "Path Color",
    Default = Color3.fromRGB(80, 170, 255),
    SaveKey = "path_color",
    Callback = function(c)
        print("[example] Path Color:", c)
    end,
})

Stealer:AddSlider({
    Name = "Walk Speed",
    Min = 16,
    Max = 300,
    Default = 60,
    Suffix = "%",
    Callback = function(v)
        print("[example] Walk Speed:", v)
    end,
})

Filters:AddMultiDropdown({
    Name = "Rarity Filter",
    Options = { "Common", "Rare", "Epic", "Legendary", "Mythic", "Secret" },
    Default = { "Legendary", "Mythic", "Secret" },
    Callback = function(values)
        print("[example] Rarity Filter:", table.concat(values, ", "))
    end,
})

local hitboxMulti = Filters:AddMultiDropdown({
    Name = "Hitbox Parts",
    Options = { "Head", "Chest", "Stomach", "Left Arm", "Right Arm", "Left Leg", "Right Leg" },
    Default = { "Head", "Chest" },
    Callback = function(values)
        print("[example] Hitbox Parts:", table.concat(values, ", "))
    end,
})

Filters:AddHitboxPreview({
    Name = "Bone Preview",
    LinkedDropdown = hitboxMulti,
    Default = { "Head", "Chest" },
})

Filters:AddMultiDropdownToggle({
    Name = "Mutation Filter",
    Options = { "None", "Gold", "Rainbow", "Nuclear" },
    Default = { "Gold" },
    DefaultToggle = true,
    Callback = function(values, enabled)
        print("[example] Mutation Filter:", enabled, table.concat(values, ", "))
    end,
})

local modeOptions = { "Balanced", "Aggressive", "Safe", "Eco" }
local modeDropdown = Actions:AddDropdown({
    Name = "Strategy",
    Options = modeOptions,
    Default = "Balanced",
    Callback = function(v)
        print("[example] Strategy:", v)
    end,
})

Actions:AddButton({
    Name = "Rotate Strategy List",
    Callback = function()
        table.insert(modeOptions, table.remove(modeOptions, 1))
        modeDropdown:SetOptions(modeOptions, modeOptions[1])
        Library:Notify("Strategy List", "Options rotated", 1.75)
    end,
})

Actions:AddButton({
    Name = "Notify Test",
    Callback = function()
        Library:Notify({
            Title = "Notification Test",
            Text = "Top-right toast is working",
            Duration = 3,
        })
    end,
})

-- VISUALS
local EspSection = Visuals:AddSection({ Name = "PLAYER ESP", Column = 1 })
local RenderSection = Visuals:AddSection({ Name = "RENDER", Column = 2 })
local ThemeSection = Visuals:AddSection({ Name = "THEME", Column = 3 })

EspSection:AddDropdownToggle({
    Name = "Box ESP",
    Options = { "2D", "Corner", "Filled" },
    Default = "Corner",
    DefaultToggle = true,
    Callback = function(value, enabled)
        print("[example] Box ESP:", enabled, value)
    end,
})

EspSection:AddSliderToggle({
    Name = "Text Size",
    Min = 10,
    Max = 24,
    Default = 14,
    Suffix = " px",
    Enabled = true,
    Callback = function(value, enabled)
        print("[example] Text Size:", value, enabled)
    end,
})

EspSection:AddColorPicker({
    Name = "ESP Color",
    Default = Color3.fromRGB(245, 49, 116),
    SaveKey = "esp_color",
    Callback = function(c)
        print("[example] ESP Color:", c)
    end,
})

RenderSection:AddToggle({
    Name = "Fullbright",
    Default = false,
    Callback = function(v)
        print("[example] Fullbright:", v)
    end,
})

RenderSection:AddDropdown({
    Name = "Time Preset",
    Options = { "Morning", "Noon", "Evening", "Night" },
    Default = "Noon",
    Callback = function(v)
        print("[example] Time Preset:", v)
    end,
})

RenderSection:AddInputBox({
    Name = "Custom Skybox ID",
    Placeholder = "rbxassetid://...",
    Default = "",
    Callback = function(v)
        print("[example] Skybox ID:", v)
    end,
})

ThemeSection:AddColorPicker({
    Name = "Accent",
    Default = Color3.fromRGB(245, 49, 116),
    SaveKey = "accent",
    Callback = function(c)
        print("[example] Accent:", c)
    end,
})

ThemeSection:AddSlider({
    Name = "Panel Transparency",
    Min = 0,
    Max = 90,
    Default = 0,
    Suffix = "%",
    Callback = function(v)
        print("[example] Panel Transparency:", v)
    end,
})

-- MISC
local ConfigSection = Misc:AddSection({ Name = "CONFIG", Column = 1 })
local InputSection = Misc:AddSection({ Name = "INPUT", Column = 2 })
local StateSection = Misc:AddSection({ Name = "STATE", Column = 3 })

ConfigSection:AddInputBox({
    Name = "Profile Name",
    Placeholder = "example_profile",
    Default = "default",
    Callback = function(v)
        print("[example] Profile Name:", v)
    end,
})

ConfigSection:AddButton({
    Name = "Save Config",
    Callback = function()
        pcall(function()
            Library:SaveConfig()
        end)
        Library:Notify("Config", "Saved", 1.5)
    end,
})

ConfigSection:AddButton({
    Name = "Load Config",
    Callback = function()
        pcall(function()
            Library:LoadConfig()
        end)
        Library:Notify("Config", "Loaded", 1.5)
    end,
})

InputSection:AddToggle({
    Name = "Auto Click",
    Default = false,
    Callback = function(v)
        print("[example] Auto Click:", v)
    end,
})

InputSection:AddDropdown({
    Name = "Toggle Key",
    Options = { "Insert", "RightShift", "End", "Home" },
    Default = "Insert",
    Callback = function(v)
        print("[example] Toggle Key:", v)
    end,
})

InputSection:AddSliderToggle({
    Name = "Reaction Delay",
    Min = 0,
    Max = 400,
    Default = 120,
    Suffix = " ms",
    Enabled = true,
    Callback = function(value, enabled)
        print("[example] Reaction Delay:", value, enabled)
    end,
})

local runtimeEnabled = StateSection:AddToggle({
    Name = "Runtime Enabled",
    Default = true,
    Callback = function(v)
        print("[example] Runtime Enabled:", v)
    end,
})

StateSection:AddButton({
    Name = "Flip Runtime",
    Callback = function()
        runtimeEnabled:Set(not runtimeEnabled.Value)
    end,
})

StateSection:AddButton({
    Name = "Unload UI",
    Callback = function()
        pcall(function()
            Window:Destroy()
        end)
    end,
})

Library:Notify({
    Title = "UILib Example",
    Text = "All control types are mounted. Use tabs to test.",
    Duration = 4,
})
