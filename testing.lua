--[[
    UILib Test Script
    Run this in your executor to test the basic window box.
    
    Expected: Dark box with rounded corners, drop shadow,
    spring-based open animation, smooth dragging, Right Ctrl to toggle.
]]

local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/megafartCc/UiLib/main/build.lua"))()
local Window = Library:CreateWindow("UILib Test Window")
