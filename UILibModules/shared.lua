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
        if typeof(gethui) == "function" then
            return gethui()
        end

        error("UILib requires gethui() for UI parenting")
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
