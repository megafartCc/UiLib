--[[
    UILib - Custom Roblox Exploit UI Library
    Version: 0.1
    
    Spring-driven animations via spr (Fractality)
    No TweenService — everything is physics-based.
    
    Usage:
        local Library = loadstring(readfile("UILib/build.lua"))()
        local Window = Library:CreateWindow("My Hub")
]]

local Library = {}
Library.__index = Library

-- =====================================================
-- SERVICES
-- =====================================================
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")

-- =====================================================
-- SPRING LIBRARY (spr by Fractality)
-- =====================================================
local spr = loadstring(game:HttpGet("https://raw.githubusercontent.com/Fraktality/spr/master/spr.lua"))()

-- Spring presets (damping, frequency)
Library.Springs = {
    Smooth   = { 1,    6  },   -- critically damped, snappy
    Snappy   = { 0.8,  8  },   -- slight overshoot, fast
    Bouncy   = { 0.5,  6  },   -- visible bounce
    Gentle   = { 1,    4  },   -- slow smooth settle
    Quick    = { 1,    12 },   -- very fast, no overshoot
    Drag     = { 1,    16 },   -- instant-feel drag
    Popup    = { 0.7,  7  },   -- opening animations
}

-- Helper to fire spr.target with a preset
function Library:Spring(instance, preset, props)
    local p = self.Springs[preset] or self.Springs.Smooth
    spr.target(instance, p[1], p[2], props)
end

function Library:SpringCustom(instance, damping, freq, props)
    spr.target(instance, damping, freq, props)
end

function Library:StopSpring(instance, prop)
    spr.stop(instance, prop)
end

-- =====================================================
-- THEME
-- =====================================================
Library.Theme = {
    Background     = Color3.fromRGB(18, 18, 22),
    Surface        = Color3.fromRGB(25, 25, 32),
    SurfaceHover   = Color3.fromRGB(32, 32, 42),
    Border         = Color3.fromRGB(40, 40, 52),
    Accent         = Color3.fromRGB(88, 101, 242),
    AccentHover    = Color3.fromRGB(105, 117, 255),
    Text           = Color3.fromRGB(220, 221, 225),
    TextDim        = Color3.fromRGB(140, 142, 150),
    TextMuted      = Color3.fromRGB(90, 92, 100),
    Success        = Color3.fromRGB(67, 181, 129),
    Warning        = Color3.fromRGB(250, 168, 26),
    Error          = Color3.fromRGB(237, 66, 69),
    CornerRadius   = UDim.new(0, 8),
    WindowCorner   = UDim.new(0, 10),
}

Library.Config = {
    WindowWidth    = 550,
    WindowHeight   = 380,
    Font           = Enum.Font.GothamSemibold,
    FontLight      = Enum.Font.Gotham,
    ToggleKey      = Enum.KeyCode.RightControl,
}

-- =====================================================
-- UTILITY
-- =====================================================
local function getHiddenParent()
    local ok, ui = pcall(function()
        if typeof(gethui) == "function" then return gethui() end
        if typeof(get_hidden_gui) == "function" then return get_hidden_gui() end
        if typeof(gethiddenui) == "function" then return gethiddenui() end
    end)
    return (ok and ui) or CoreGui
end

local function protectGui(gui)
    if syn and typeof(syn.protect_gui) == "function" then
        pcall(syn.protect_gui, gui)
    elseif typeof(protect_gui) == "function" then
        pcall(protect_gui, gui)
    end
end

-- =====================================================
-- COMPONENT: WINDOW
-- =====================================================
function Library:CreateWindow(title)
    local theme = self.Theme
    local config = self.Config

    local win = {}
    win.Title = title or "UI Library"
    win.Visible = true
    win.Dragging = false
    win.Pages = {}

    -- ScreenGui
    local sg = Instance.new("ScreenGui")
    sg.Name = "UILib_" .. math.random(100000, 999999)
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    sg.ResetOnSpawn = false
    sg.DisplayOrder = 999
    protectGui(sg)
    sg.Parent = getHiddenParent()
    win.ScreenGui = sg

    -- ==============================
    -- DROP SHADOW
    -- ==============================
    local shadowFrame = Instance.new("Frame", sg)
    shadowFrame.Name = "Shadow"
    shadowFrame.Size = UDim2.fromOffset(config.WindowWidth + 24, config.WindowHeight + 24)
    shadowFrame.Position = UDim2.new(0.5, -math.floor((config.WindowWidth + 24) / 2), 0.5, -math.floor((config.WindowHeight + 24) / 2))
    shadowFrame.BackgroundTransparency = 1
    shadowFrame.ZIndex = 0

    local shadowImg = Instance.new("ImageLabel", shadowFrame)
    shadowImg.Size = UDim2.new(1, 0, 1, 0)
    shadowImg.BackgroundTransparency = 1
    shadowImg.Image = "rbxassetid://5554236805"
    shadowImg.ImageColor3 = Color3.fromRGB(0, 0, 0)
    shadowImg.ImageTransparency = 1 -- starts invisible
    shadowImg.ScaleType = Enum.ScaleType.Slice
    shadowImg.SliceCenter = Rect.new(23, 23, 277, 277)
    shadowImg.ZIndex = 0

    -- ==============================
    -- MAIN FRAME
    -- ==============================
    local main = Instance.new("Frame", sg)
    main.Name = "Window"
    main.Size = UDim2.fromOffset(config.WindowWidth, config.WindowHeight)
    main.Position = UDim2.new(0.5, -math.floor(config.WindowWidth / 2), 0.5, -math.floor(config.WindowHeight / 2))
    main.BackgroundColor3 = theme.Background
    main.BorderSizePixel = 0
    main.ClipsDescendants = true
    main.ZIndex = 1

    -- Start scaled down for open animation
    main.Size = UDim2.fromOffset(config.WindowWidth, 0)
    main.BackgroundTransparency = 0

    Instance.new("UICorner", main).CornerRadius = theme.WindowCorner

    local stroke = Instance.new("UIStroke", main)
    stroke.Color = theme.Border
    stroke.Transparency = 1 -- starts invisible
    stroke.Thickness = 1
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

    -- ==============================
    -- TITLE BAR
    -- ==============================
    local titleBar = Instance.new("Frame", main)
    titleBar.Name = "TitleBar"
    titleBar.Size = UDim2.new(1, 0, 0, 38)
    titleBar.BackgroundTransparency = 1
    titleBar.ZIndex = 5

    local titleText = Instance.new("TextLabel", titleBar)
    titleText.Size = UDim2.new(1, -30, 1, 0)
    titleText.Position = UDim2.fromOffset(14, 0)
    titleText.BackgroundTransparency = 1
    titleText.Text = win.Title
    titleText.TextColor3 = theme.Text
    titleText.TextSize = 14
    titleText.Font = config.Font
    titleText.TextXAlignment = Enum.TextXAlignment.Left
    titleText.TextTransparency = 1 -- starts invisible
    titleText.ZIndex = 5

    -- Separator
    local sep = Instance.new("Frame", main)
    sep.Size = UDim2.new(1, 0, 0, 1)
    sep.Position = UDim2.fromOffset(0, 38)
    sep.BackgroundColor3 = theme.Border
    sep.BackgroundTransparency = 1 -- starts invisible
    sep.BorderSizePixel = 0
    sep.ZIndex = 2

    -- ==============================
    -- CONTENT AREA
    -- ==============================
    local content = Instance.new("Frame", main)
    content.Name = "Content"
    content.Size = UDim2.new(1, 0, 1, -38)
    content.Position = UDim2.fromOffset(0, 38)
    content.BackgroundTransparency = 1
    content.ZIndex = 2
    win.Content = content

    -- ==============================
    -- DRAGGING (spring-based)
    -- ==============================
    local dragInput, dragStart, startPos

    titleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            win.Dragging = true
            dragStart = input.Position
            startPos = main.Position

            -- Stop any existing spring on position
            spr.stop(main, "Position")
            spr.stop(shadowFrame, "Position")

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    win.Dragging = false
                end
            end)
        end
    end)

    titleBar.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and win.Dragging then
            local delta = input.Position - dragStart
            local target = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
            -- Spring-based drag — feels liquid
            self:Spring(main, "Drag", { Position = target })
            self:Spring(shadowFrame, "Drag", {
                Position = UDim2.new(target.X.Scale, target.X.Offset - 12, target.Y.Scale, target.Y.Offset - 12)
            })
        end
    end)

    -- ==============================
    -- TOGGLE (Right Ctrl)
    -- ==============================
    UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if input.KeyCode == config.ToggleKey then
            win.Visible = not win.Visible
            if win.Visible then
                main.Visible = true
                shadowFrame.Visible = true
                -- Spring open
                self:Spring(main, "Popup", {
                    Size = UDim2.fromOffset(config.WindowWidth, config.WindowHeight)
                })
                self:Spring(shadowFrame, "Popup", {
                    Size = UDim2.fromOffset(config.WindowWidth + 24, config.WindowHeight + 24)
                })
                self:Spring(shadowImg, "Smooth", { ImageTransparency = 0.45 })
                self:Spring(titleText, "Smooth", { TextTransparency = 0 })
                self:Spring(sep, "Smooth", { BackgroundTransparency = 0.6 })
                self:Spring(stroke, "Smooth", { Transparency = 0.5 })
            else
                -- Spring close
                self:Spring(main, "Snappy", {
                    Size = UDim2.fromOffset(config.WindowWidth, 0)
                })
                self:Spring(shadowFrame, "Snappy", {
                    Size = UDim2.fromOffset(config.WindowWidth + 24, 0)
                })
                self:Spring(shadowImg, "Quick", { ImageTransparency = 1 })
                self:Spring(titleText, "Quick", { TextTransparency = 1 })
                self:Spring(sep, "Quick", { BackgroundTransparency = 1 })
                self:Spring(stroke, "Quick", { Transparency = 1 })
                task.delay(0.35, function()
                    if not win.Visible then
                        main.Visible = false
                        shadowFrame.Visible = false
                    end
                end)
            end
        end
    end)

    -- ==============================
    -- OPEN ANIMATION
    -- ==============================
    task.defer(function()
        -- Spring the window open from 0 height
        self:Spring(main, "Popup", {
            Size = UDim2.fromOffset(config.WindowWidth, config.WindowHeight)
        })
        self:Spring(shadowFrame, "Popup", {
            Size = UDim2.fromOffset(config.WindowWidth + 24, config.WindowHeight + 24)
        })
        self:Spring(shadowImg, "Gentle", { ImageTransparency = 0.45 })
        self:Spring(titleText, "Smooth", { TextTransparency = 0 })
        self:Spring(sep, "Smooth", { BackgroundTransparency = 0.6 })
        self:Spring(stroke, "Smooth", { Transparency = 0.5 })
    end)

    -- Store refs
    win._main = main
    win._shadow = shadowFrame
    win._shadowImg = shadowImg
    win._titleText = titleText
    win._sep = sep
    win._stroke = stroke
    win._library = self
    win._spr = spr

    return win
end

return Library
