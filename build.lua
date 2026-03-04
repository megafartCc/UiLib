--[[
    UILib - Custom Roblox Exploit UI Library
    Version: 0.2
    
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
    Smooth   = { 1,    6  },
    Snappy   = { 0.8,  8  },
    Bouncy   = { 0.5,  6  },
    Gentle   = { 1,    4  },
    Quick    = { 1,    12 },
    Drag     = { 1,    16 },
    Popup    = { 0.7,  7  },
}

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
    AccentGlow     = Color3.fromRGB(200, 80, 60),   -- orange-red ring like reference
    Text           = Color3.fromRGB(220, 221, 225),
    TextDim        = Color3.fromRGB(140, 142, 150),
    TextMuted      = Color3.fromRGB(90, 92, 100),
    Premium        = Color3.fromRGB(250, 168, 26),   -- gold for premium
    Success        = Color3.fromRGB(67, 181, 129),
    Warning        = Color3.fromRGB(250, 168, 26),
    Error          = Color3.fromRGB(237, 66, 69),
    CornerRadius   = UDim.new(0, 8),
    WindowCorner   = UDim.new(0, 10),
}

Library.Config = {
    WindowWidth    = 620,
    WindowHeight   = 480,
    TitleBarHeight = 60,
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

-- Get player avatar thumbnail URL
local function getAvatarUrl(userId)
    local ok, url = pcall(function()
        return Players:GetUserThumbnailAsync(
            userId,
            Enum.ThumbnailType.HeadShot,
            Enum.ThumbnailSize.Size100x100
        )
    end)
    return ok and url or ""
end

-- =====================================================
-- COMPONENT: WINDOW
-- =====================================================
function Library:CreateWindow(title)
    local theme = self.Theme
    local config = self.Config
    local lp = Players.LocalPlayer

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
    shadowImg.ImageTransparency = 1
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

    -- Start collapsed for open animation
    main.Size = UDim2.fromOffset(config.WindowWidth, 0)

    Instance.new("UICorner", main).CornerRadius = theme.WindowCorner

    local stroke = Instance.new("UIStroke", main)
    stroke.Color = theme.Border
    stroke.Transparency = 1
    stroke.Thickness = 1
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

    -- ==============================
    -- TITLE BAR (taller, has avatar)
    -- ==============================
    local titleBar = Instance.new("Frame", main)
    titleBar.Name = "TitleBar"
    titleBar.Size = UDim2.new(1, 0, 0, config.TitleBarHeight)
    titleBar.BackgroundTransparency = 1
    titleBar.ZIndex = 5

    -- Left side: Title text
    local titleText = Instance.new("TextLabel", titleBar)
    titleText.Name = "Title"
    titleText.Size = UDim2.new(0.5, 0, 0, 18)
    titleText.Position = UDim2.fromOffset(16, 12)
    titleText.BackgroundTransparency = 1
    titleText.Text = win.Title
    titleText.TextColor3 = theme.Text
    titleText.TextSize = 15
    titleText.Font = config.Font
    titleText.TextXAlignment = Enum.TextXAlignment.Left
    titleText.TextTransparency = 1
    titleText.ZIndex = 5

    -- Left side: "Premium" badge text below title
    local premiumText = Instance.new("TextLabel", titleBar)
    premiumText.Name = "Premium"
    premiumText.Size = UDim2.new(0.5, 0, 0, 14)
    premiumText.Position = UDim2.fromOffset(16, 33)
    premiumText.BackgroundTransparency = 1
    premiumText.Text = "Premium"
    premiumText.TextColor3 = theme.Premium
    premiumText.TextSize = 12
    premiumText.Font = config.Font
    premiumText.TextXAlignment = Enum.TextXAlignment.Left
    premiumText.TextTransparency = 1
    premiumText.ZIndex = 5

    -- ==============================
    -- RIGHT SIDE: Avatar + Username
    -- ==============================
    local avatarSize = 38
    local avatarRingSize = avatarSize + 4

    -- Avatar ring (accent-colored border)
    local avatarRing = Instance.new("Frame", titleBar)
    avatarRing.Name = "AvatarRing"
    avatarRing.Size = UDim2.fromOffset(avatarRingSize, avatarRingSize)
    avatarRing.Position = UDim2.new(1, -avatarRingSize - 14, 0.5, -math.floor(avatarRingSize / 2))
    avatarRing.BackgroundColor3 = theme.AccentGlow
    avatarRing.BorderSizePixel = 0
    avatarRing.ZIndex = 6
    avatarRing.BackgroundTransparency = 1

    Instance.new("UICorner", avatarRing).CornerRadius = UDim.new(1, 0) -- full circle

    -- Avatar image (inside ring)
    local avatarImg = Instance.new("ImageLabel", avatarRing)
    avatarImg.Name = "AvatarImage"
    avatarImg.Size = UDim2.fromOffset(avatarSize, avatarSize)
    avatarImg.Position = UDim2.fromOffset(2, 2) -- 2px padding = ring thickness
    avatarImg.BackgroundColor3 = theme.Surface
    avatarImg.BorderSizePixel = 0
    avatarImg.ZIndex = 7
    avatarImg.ImageTransparency = 1

    Instance.new("UICorner", avatarImg).CornerRadius = UDim.new(1, 0) -- full circle

    -- Load avatar async
    task.spawn(function()
        local url = getAvatarUrl(lp.UserId)
        if url and url ~= "" then
            avatarImg.Image = url
            -- Spring fade in
            self:Spring(avatarImg, "Smooth", { ImageTransparency = 0 })
        end
    end)

    -- Username text (to the left of avatar)
    local usernameText = Instance.new("TextLabel", titleBar)
    usernameText.Name = "Username"
    usernameText.Size = UDim2.new(0, 120, 0, 16)
    usernameText.Position = UDim2.new(1, -avatarRingSize - 14 - 8 - 120, 0.5, -8)
    usernameText.BackgroundTransparency = 1
    usernameText.Text = lp.DisplayName or lp.Name
    usernameText.TextColor3 = theme.TextDim
    usernameText.TextSize = 13
    usernameText.Font = config.FontLight
    usernameText.TextXAlignment = Enum.TextXAlignment.Right
    usernameText.TextTransparency = 1
    usernameText.ZIndex = 5

    -- Separator line below title bar
    local sep = Instance.new("Frame", main)
    sep.Name = "TitleSep"
    sep.Size = UDim2.new(1, 0, 0, 1)
    sep.Position = UDim2.fromOffset(0, config.TitleBarHeight)
    sep.BackgroundColor3 = theme.Border
    sep.BackgroundTransparency = 1
    sep.BorderSizePixel = 0
    sep.ZIndex = 2

    -- ==============================
    -- CONTENT AREA
    -- ==============================
    local content = Instance.new("Frame", main)
    content.Name = "Content"
    content.Size = UDim2.new(1, 0, 1, -config.TitleBarHeight)
    content.Position = UDim2.fromOffset(0, config.TitleBarHeight)
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
            self:Spring(main, "Drag", { Position = target })
            self:Spring(shadowFrame, "Drag", {
                Position = UDim2.new(target.X.Scale, target.X.Offset - 12, target.Y.Scale, target.Y.Offset - 12)
            })
        end
    end)

    -- ==============================
    -- TOGGLE (Right Ctrl)
    -- ==============================
    local function showAll()
        self:Spring(titleText, "Smooth", { TextTransparency = 0 })
        self:Spring(premiumText, "Smooth", { TextTransparency = 0 })
        self:Spring(usernameText, "Smooth", { TextTransparency = 0 })
        self:Spring(avatarRing, "Smooth", { BackgroundTransparency = 0 })
        self:Spring(sep, "Smooth", { BackgroundTransparency = 0.6 })
        self:Spring(stroke, "Smooth", { Transparency = 0.5 })
        self:Spring(shadowImg, "Gentle", { ImageTransparency = 0.45 })
    end

    local function hideAll()
        self:Spring(titleText, "Quick", { TextTransparency = 1 })
        self:Spring(premiumText, "Quick", { TextTransparency = 1 })
        self:Spring(usernameText, "Quick", { TextTransparency = 1 })
        self:Spring(avatarRing, "Quick", { BackgroundTransparency = 1 })
        self:Spring(sep, "Quick", { BackgroundTransparency = 1 })
        self:Spring(stroke, "Quick", { Transparency = 1 })
        self:Spring(shadowImg, "Quick", { ImageTransparency = 1 })
    end

    UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if input.KeyCode == config.ToggleKey then
            win.Visible = not win.Visible
            if win.Visible then
                main.Visible = true
                shadowFrame.Visible = true
                self:Spring(main, "Popup", {
                    Size = UDim2.fromOffset(config.WindowWidth, config.WindowHeight)
                })
                self:Spring(shadowFrame, "Popup", {
                    Size = UDim2.fromOffset(config.WindowWidth + 24, config.WindowHeight + 24)
                })
                showAll()
            else
                self:Spring(main, "Snappy", {
                    Size = UDim2.fromOffset(config.WindowWidth, 0)
                })
                self:Spring(shadowFrame, "Snappy", {
                    Size = UDim2.fromOffset(config.WindowWidth + 24, 0)
                })
                hideAll()
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
        self:Spring(main, "Popup", {
            Size = UDim2.fromOffset(config.WindowWidth, config.WindowHeight)
        })
        self:Spring(shadowFrame, "Popup", {
            Size = UDim2.fromOffset(config.WindowWidth + 24, config.WindowHeight + 24)
        })
        showAll()
    end)

    -- Store refs
    win._main = main
    win._shadow = shadowFrame
    win._library = self
    win._spr = spr

    return win
end

return Library
