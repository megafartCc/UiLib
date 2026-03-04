--[[
    Window Component
    Dark draggable container with rounded corners and drop shadow
]]

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Window = {}
Window.__index = Window

function Window.new(library, title)
    local self = setmetatable({}, Window)
    self.Library = library
    self.Title = title or "UI Library"
    self.Pages = {}
    self.Visible = true
    self.Dragging = false
    self.DragStart = nil
    self.StartPos = nil

    local theme = library.Theme
    local config = library.Config

    -- ScreenGui
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "UILib_" .. tostring(math.random(100000, 999999))
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.ResetOnSpawn = false
    screenGui.DisplayOrder = 999
    library:_ProtectGui(screenGui)
    screenGui.Parent = library:_GetUIParent()
    self.ScreenGui = screenGui

    -- ==============================
    -- DROP SHADOW (layered for depth)
    -- ==============================
    local shadowHolder = Instance.new("Frame", screenGui)
    shadowHolder.Name = "ShadowHolder"
    shadowHolder.Size = UDim2.fromOffset(config.WindowWidth + 24, config.WindowHeight + 24)
    shadowHolder.Position = UDim2.new(0.5, -math.floor((config.WindowWidth + 24) / 2), 0.5, -math.floor((config.WindowHeight + 24) / 2))
    shadowHolder.BackgroundTransparency = 1
    shadowHolder.ZIndex = 0

    local shadow = Instance.new("ImageLabel", shadowHolder)
    shadow.Name = "Shadow"
    shadow.Size = UDim2.new(1, 0, 1, 0)
    shadow.BackgroundTransparency = 1
    shadow.Image = "rbxassetid://5554236805" -- soft shadow asset
    shadow.ImageColor3 = Color3.fromRGB(0, 0, 0)
    shadow.ImageTransparency = 0.5
    shadow.ScaleType = Enum.ScaleType.Slice
    shadow.SliceCenter = Rect.new(23, 23, 277, 277)
    shadow.ZIndex = 0
    self.ShadowHolder = shadowHolder

    -- ==============================
    -- MAIN WINDOW FRAME
    -- ==============================
    local mainFrame = Instance.new("Frame", screenGui)
    mainFrame.Name = "MainWindow"
    mainFrame.Size = UDim2.fromOffset(config.WindowWidth, config.WindowHeight)
    mainFrame.Position = UDim2.new(0.5, -math.floor(config.WindowWidth / 2), 0.5, -math.floor(config.WindowHeight / 2))
    mainFrame.BackgroundColor3 = theme.Background
    mainFrame.BorderSizePixel = 0
    mainFrame.ClipsDescendants = true
    mainFrame.ZIndex = 1
    self.MainFrame = mainFrame

    -- Rounded corners
    local corner = Instance.new("UICorner", mainFrame)
    corner.CornerRadius = theme.WindowCorner

    -- Subtle border stroke
    local stroke = Instance.new("UIStroke", mainFrame)
    stroke.Color = theme.Border
    stroke.Transparency = 0.6
    stroke.Thickness = 1
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

    -- ==============================
    -- TITLE BAR (drag zone)
    -- ==============================
    local titleBar = Instance.new("Frame", mainFrame)
    titleBar.Name = "TitleBar"
    titleBar.Size = UDim2.new(1, 0, 0, 36)
    titleBar.BackgroundTransparency = 1
    titleBar.ZIndex = 5

    local titleLabel = Instance.new("TextLabel", titleBar)
    titleLabel.Name = "TitleText"
    titleLabel.Size = UDim2.new(1, -20, 1, 0)
    titleLabel.Position = UDim2.fromOffset(14, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = self.Title
    titleLabel.TextColor3 = theme.Text
    titleLabel.TextSize = 14
    titleLabel.Font = config.Font
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.ZIndex = 5

    -- Title bar separator
    local sep = Instance.new("Frame", mainFrame)
    sep.Name = "TitleSep"
    sep.Size = UDim2.new(1, 0, 0, 1)
    sep.Position = UDim2.fromOffset(0, 36)
    sep.BackgroundColor3 = theme.Border
    sep.BackgroundTransparency = 0.7
    sep.BorderSizePixel = 0
    sep.ZIndex = 2

    -- ==============================
    -- CONTENT AREA (below title bar)
    -- ==============================
    local contentArea = Instance.new("Frame", mainFrame)
    contentArea.Name = "ContentArea"
    contentArea.Size = UDim2.new(1, 0, 1, -36)
    contentArea.Position = UDim2.fromOffset(0, 36)
    contentArea.BackgroundTransparency = 1
    contentArea.ZIndex = 2
    self.ContentArea = contentArea

    -- ==============================
    -- DRAGGING
    -- ==============================
    local dragInput = nil
    local dragStart = nil
    local startPos = nil

    titleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            self.Dragging = true
            dragStart = input.Position
            startPos = mainFrame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    self.Dragging = false
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
        if input == dragInput and self.Dragging then
            local delta = input.Position - dragStart
            local targetPos = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
            -- Smooth drag
            TweenService:Create(mainFrame, TweenInfo.new(config.DragSmoothing, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                Position = targetPos
            }):Play()
            -- Shadow follows
            TweenService:Create(shadowHolder, TweenInfo.new(config.DragSmoothing, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                Position = UDim2.new(
                    targetPos.X.Scale, targetPos.X.Offset - 12,
                    targetPos.Y.Scale, targetPos.Y.Offset - 12
                )
            }):Play()
        end
    end)

    -- ==============================
    -- TOGGLE VISIBILITY (Right Ctrl)
    -- ==============================
    UserInputService.InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.KeyCode == Enum.KeyCode.RightControl then
            self:Toggle()
        end
    end)

    -- Opening animation
    mainFrame.BackgroundTransparency = 1
    titleLabel.TextTransparency = 1
    sep.BackgroundTransparency = 1
    stroke.Transparency = 1
    shadow.ImageTransparency = 1

    task.defer(function()
        local tweenInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
        TweenService:Create(mainFrame, tweenInfo, { BackgroundTransparency = 0 }):Play()
        TweenService:Create(titleLabel, tweenInfo, { TextTransparency = 0 }):Play()
        TweenService:Create(sep, tweenInfo, { BackgroundTransparency = 0.7 }):Play()
        TweenService:Create(stroke, tweenInfo, { Transparency = 0.6 }):Play()
        TweenService:Create(shadow, tweenInfo, { ImageTransparency = 0.5 }):Play()
    end)

    return self
end

function Window:Toggle()
    self.Visible = not self.Visible
    local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

    if self.Visible then
        self.MainFrame.Visible = true
        self.ShadowHolder.Visible = true
        TweenService:Create(self.MainFrame, tweenInfo, { BackgroundTransparency = 0 }):Play()
        TweenService:Create(self.ShadowHolder, tweenInfo, { Size = UDim2.fromOffset(
            self.Library.Config.WindowWidth + 24, self.Library.Config.WindowHeight + 24
        )}):Play()
    else
        TweenService:Create(self.MainFrame, tweenInfo, { BackgroundTransparency = 1 }):Play()
        task.delay(0.3, function()
            if not self.Visible then
                self.MainFrame.Visible = false
                self.ShadowHolder.Visible = false
            end
        end)
    end
end

function Window:Destroy()
    if self.ScreenGui then
        self.ScreenGui:Destroy()
    end
end

return Window
