return function(moduleRequire)
    local SharedState = {
        AutoSaveLoopStarted = false,
    }

    local UserInputService = game:GetService("UserInputService")
    local RunService = game:GetService("RunService")
    local Players = game:GetService("Players")
    local HttpService = game:GetService("HttpService")
    local TextService = game:GetService("TextService")
    local Client = Players.LocalPlayer

    local Cleaner = moduleRequire("cleanup.lua")
    local createAnimator = moduleRequire("animator.lua")
    local Animator = createAnimator(RunService)

    local function getHiddenParent()
        if type(gethui) == "function" then
            local okHui, hui = pcall(gethui)
            if okHui and hui then
                return hui
            end
        end

        if Client then
            local okPlayerGui, playerGui = pcall(function()
                return Client:FindFirstChildOfClass("PlayerGui") or Client:WaitForChild("PlayerGui", 5)
            end)
            if okPlayerGui and playerGui then
                return playerGui
            end
        end

        local okCoreGui, coreGui = pcall(function()
            return game:GetService("CoreGui")
        end)
        if okCoreGui and coreGui then
            return coreGui
        end

        error("UILib could not resolve a UI parent")
    end

    local function protectGui(gui)
        return gui
    end

    local function randomStr(len)
        len = len or 12
        local s = ""
        local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
        for i = 1, len do
            local r = math.random(1, #chars)
            s = s .. string.sub(chars, r, r)
        end
        return s
    end

    return {
        SharedState = SharedState,
        UserInputService = UserInputService,
        RunService = RunService,
        Players = Players,
        HttpService = HttpService,
        TextService = TextService,
        Client = Client,
        Cleaner = Cleaner,
        Animator = Animator,
        getHiddenParent = getHiddenParent,
        protectGui = protectGui,
        randomStr = randomStr,
    }
end
