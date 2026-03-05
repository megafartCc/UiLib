--[[
    UILib Test Script (Fatality-style)
    Copy `build.lua` and the `UILibModules` folder into your executor workspace.
]]

local Library = loadstring(readfile("build.lua"))()

local Window = Library:CreateWindow({
    Name = "FATALITY",
    Expire = "never",
    ConfigName = "fatality_test",  -- Saves to workspace/Eps1lonScript/fatality_test.json
})

-- Create tabs
local Rage = Window:AddMenu({ Name = "RAGE", Columns = 3 })
local Legit = Window:AddMenu({ Name = "LEGIT", Columns = 3 })
local Visual = Window:AddMenu({ Name = "VISUAL", Columns = 3 })
local Misc = Window:AddMenu({ Name = "MISC", Columns = 3 })
local Skins = Window:AddMenu({ Name = "SKINS", Columns = 2 })
local Lua = Window:AddMenu({ Name = "LUA", Columns = 2 })

-- Add sections to Rage page
local Weapon  = Rage:AddSection({ Name = "WEAPON",  Column = 1 })
local Grenades = Rage:AddSection({ Name = "GRENADES", Column = 1 })
local Movement = Rage:AddSection({ Name = "MOVEMENT", Column = 2 })
local Extra    = Rage:AddSection({ Name = "EXTRA",    Column = 2 })
local General  = Rage:AddSection({ Name = "GENERAL",  Column = 3 })

-- Weapon section: toggle with chained sub-elements
local aimbot = Weapon:AddToggle({ Name = "Aimbot", Default = true })
aimbot:AddDropdown({ Name = "Target", Options = {"Head", "Body", "Nearest"}, Default = "Head" })
aimbot:AddSlider({ Name = "FOV", Default = 90, Min = 1, Max = 180, Suffix = "°" })

Weapon:AddToggle({ Name = "Silent aim" })
Weapon:AddToggle({ Name = "Autofire" })
local hitboxDD = Weapon:AddMultiDropdown({ Name = "Hitboxes", Options = {"Head", "Chest", "Stomach", "Left Arm", "Right Arm", "Left Leg", "Right Leg"}, Default = {"Head", "Chest"} })

-- Hitbox preview (interactive body part selector linked to the dropdown above)
Weapon:AddHitboxPreview({
    Name = "Aimbot bones preview",
    LinkedDropdown = hitboxDD,
    Default = {"Head", "Chest"},
})

-- SliderToggle example
Weapon:AddSliderToggle({ Name = "Min dmg", Default = 50, Min = 0, Max = 100, Suffix = "", Enabled = true })

-- Movement section
local bhop = Movement:AddToggle({ Name = "Bunny hop", Default = true })
bhop:AddDropdown({ Name = "Type", Options = {"Simple", "Strafe"}, Default = "Simple" })

Movement:AddToggle({ Name = "Jumpbug" })
Movement:AddToggle({ Name = "Edge jump" })

-- DropdownToggle example
Movement:AddDropdownToggle({ Name = "Autostrafer", Options = {"Off", "Easy strafe", "Directional"}, Default = "Easy strafe", Enabled = true })
Movement:AddSliderToggle({ Name = "Slowwalk", Default = 100, Min = 0, Max = 100, Suffix = "%", Enabled = false })

-- Extra section
Extra:AddDropdownToggle({ Name = "Quick stop", Options = {"Off", "Lethal", "Always"}, Default = "Lethal", Enabled = true })

-- General section
local aa = General:AddToggle({ Name = "Anti-aim" })
aa:AddDropdown({ Name = "Pitch", Options = {"None", "Down", "Up"}, Default = "Down" })
aa:AddDropdown({ Name = "Yaw", Options = {"None", "Backward", "Spin"}, Default = "Backward" })

General:AddToggle({ Name = "Desync" })
General:AddMultiDropdown({ Name = "Freestand", Options = {"Default", "Edge", "Moving"}, Default = {"Default"} })

-- Misc page
local Autobuy = Misc:AddSection({ Name = "AUTOBUY", Column = 1 })
local Settings = Misc:AddSection({ Name = "SETTINGS", Column = 2 })
local Menu = Misc:AddSection({ Name = "MENU", Column = 3 })

Autobuy:AddToggle({ Name = "Enable", Default = true })
Autobuy:AddDropdown({ Name = "Primary", Options = {"None", "Auto", "AWP", "Scout"}, Default = "None" })
Autobuy:AddDropdown({ Name = "Secondary", Options = {"None", "Deagle", "Five-Seven"}, Default = "None" })
Autobuy:AddMultiDropdown({ Name = "Extras", Options = {"Armor", "Kit", "Zeus", "Decoy", "Smoke"}, Default = {"Armor", "Kit"} })

Settings:AddToggle({ Name = "Auto-save" })
Settings:AddSliderToggle({ Name = "DPI Scale", Default = 100, Min = 50, Max = 200, Suffix = "%", Enabled = true })

Menu:AddDropdown({ Name = "Theme", Options = {"Dark", "Light", "Custom"}, Default = "Dark" })
Menu:AddToggle({ Name = "Bomb timer", Default = true })

-- Color picker examples
Menu:AddColorPicker({
    Name = "Accent Color",
    Default = Color3.fromRGB(245, 49, 116),
    SaveKey = "color_accent",
    Callback = function(color)
        print("Accent color:", color)
    end
})

Menu:AddColorPicker({
    Name = "ESP Color",
    Default = Color3.fromRGB(0, 255, 128),
    SaveKey = "color_esp",
    Callback = function(color)
        print("ESP color:", color)
    end
})

-- Button examples
Settings:AddButton({
    Name = "Reset Settings",
    Callback = function()
        print("Settings reset!")
    end
})

Settings:AddButton({
    Name = "Copy Config",
    Callback = function()
        print("Config copied!")
    end
})

-- Standalone dropdown example
Autobuy:AddDropdown({
    Name = "Grenade",
    Items = {"None", "Smoke", "Flash", "HE", "Molotov"},
    Default = "None",
    Callback = function(val)
        print("Grenade:", val)
    end
})

-- Visual section example
local VisualsCol = Visual:AddSection({ Name = "VISUALS", Column = 1 })
VisualsCol:AddToggle({ Name = "Chams", Default = false })
VisualsCol:AddToggle({ Name = "Glow", Default = false })
VisualsCol:AddColorPicker({ Name = "Glow Color", Default = Color3.fromRGB(0, 255, 255) })
