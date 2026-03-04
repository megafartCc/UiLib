--[[
    UILib - Custom Roblox Exploit UI Library
    Modular, scalable, dark-themed
]]

local Library = {}
Library.__index = Library

-- Services
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")

-- Config
Library.Theme = {
    Background = Color3.fromRGB(18, 18, 22),
    Surface = Color3.fromRGB(25, 25, 32),
    SurfaceHover = Color3.fromRGB(32, 32, 42),
    Border = Color3.fromRGB(40, 40, 52),
    Accent = Color3.fromRGB(88, 101, 242),    -- Discord-ish blue/purple
    AccentHover = Color3.fromRGB(105, 117, 255),
    Text = Color3.fromRGB(220, 221, 225),
    TextDim = Color3.fromRGB(140, 142, 150),
    TextMuted = Color3.fromRGB(90, 92, 100),
    Success = Color3.fromRGB(67, 181, 129),
    Warning = Color3.fromRGB(250, 168, 26),
    Error = Color3.fromRGB(237, 66, 69),
    Shadow = Color3.fromRGB(0, 0, 0),
    CornerRadius = UDim.new(0, 8),
    WindowCorner = UDim.new(0, 10),
}

Library.Config = {
    WindowWidth = 550,
    WindowHeight = 380,
    MinWindowWidth = 400,
    MinWindowHeight = 280,
    AnimationSpeed = 0.25,
    DragSmoothing = 0.12,
    Font = Enum.Font.GothamSemibold,
    FontLight = Enum.Font.Gotham,
    FontMono = Enum.Font.Code,
}

-- Hidden UI parent
function Library:_GetUIParent()
    local ok, ui = pcall(function()
        if typeof(gethui) == "function" then return gethui() end
        if typeof(get_hidden_gui) == "function" then return get_hidden_gui() end
        if typeof(gethiddenui) == "function" then return gethiddenui() end
        return nil
    end)
    if ok and ui then return ui end
    return CoreGui
end

-- Protect GUI from detection
function Library:_ProtectGui(gui)
    if typeof(gui) ~= "Instance" then return end
    if syn and typeof(syn.protect_gui) == "function" then
        pcall(syn.protect_gui, gui)
    elseif typeof(protect_gui) == "function" then
        pcall(protect_gui, gui)
    end
end

-- Create the main window
function Library:CreateWindow(title)
    local Window = require(script.Components.Window)
    return Window.new(self, title)
end

return Library
