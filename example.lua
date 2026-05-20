--[[
    UILib mobile preview example.
    Execute this file directly to force the window into its mobile layout.
]]

local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/megafartCc/UiLib/main/build.lua"))()

Library.Config.WindowWidth = 620
Library.Config.WindowHeight = 540
Library.Config.MinWindowWidth = 520
Library.Config.MinWindowHeight = 420

local Window = Library:CreateWindow({
    Name = "UNKNOWN HUB",
    Expire = "never",
    ConfigName = "uilib_mobile_preview",
    ForceMobile = true,
})

Library:Notify({
    Title = "UILib",
    Text = "Mobile preview loaded",
    Duration = 2.5,
})

local Main = Window:AddMenu({ Name = "MAIN", Columns = 2 })
local Visuals = Window:AddMenu({ Name = "VISUALS", Columns = 2 })
local Settings = Window:AddMenu({ Name = "SETTINGS", Columns = 1 })

local Farm = Main:AddSection({ Name = "AUTO FARM", Column = 1 })
local Filters = Main:AddSection({ Name = "FILTERS", Column = 2 })
local Esp = Visuals:AddSection({ Name = "ESP", Column = 1 })
local Theme = Visuals:AddSection({ Name = "THEME", Column = 2 })
local Config = Settings:AddSection({ Name = "CONFIG", Column = 1 })

local farmToggle = Farm:AddToggle({
    Name = "Auto Farm",
    Default = false,
    Callback = function(value)
        print("[mobile preview] Auto Farm:", value)
    end,
})

farmToggle:AddDropdown({
    Name = "Farm Mode",
    Options = { "Closest", "Best Value", "Safe Path" },
    Default = "Closest",
    Callback = function(value)
        print("[mobile preview] Farm Mode:", value)
    end,
})

farmToggle:AddSlider({
    Name = "Range",
    Min = 25,
    Max = 500,
    Default = 150,
    Suffix = " studs",
    Callback = function(value)
        print("[mobile preview] Range:", value)
    end,
})

Filters:AddMultiDropdown({
    Name = "Targets",
    Options = { "Common", "Rare", "Epic", "Legendary", "Secret" },
    Default = { "Rare", "Epic" },
    Callback = function(selected)
        print("[mobile preview] Targets:", table.concat(selected, ", "))
    end,
})

Filters:AddDropdown({
    Name = "Minimum Rarity",
    Options = { "Any", "Rare", "Epic", "Legendary", "Secret" },
    Default = "Epic",
    Callback = function(value)
        print("[mobile preview] Minimum Rarity:", value)
    end,
})

Esp:AddToggle({
    Name = "Player ESP",
    Default = true,
    Callback = function(value)
        print("[mobile preview] Player ESP:", value)
    end,
})

Esp:AddToggle({
    Name = "Object ESP",
    Default = false,
    Callback = function(value)
        print("[mobile preview] Object ESP:", value)
    end,
})

Theme:AddColorPicker({
    Name = "Accent Color",
    Default = Color3.fromRGB(255, 70, 95),
    Callback = function(color)
        print("[mobile preview] Accent Color:", color)
    end,
})

Theme:AddSlider({
    Name = "Transparency",
    Min = 0,
    Max = 80,
    Default = 15,
    Suffix = "%",
    Callback = function(value)
        print("[mobile preview] Transparency:", value)
    end,
})

Config:AddButton({
    Name = "Print Mobile State",
    Callback = function()
        print("[mobile preview] ForceMobile is enabled")
    end,
})
