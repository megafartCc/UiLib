return function(moduleRequire)
    local SharedEnv = typeof(getgenv) == "function" and getgenv() or _G
    local SharedState = SharedEnv.__FatalityUILibState
    if type(SharedState) ~= "table" then
        SharedState = {}
        SharedEnv.__FatalityUILibState = SharedState
    end

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
        local ok, ui = pcall(function()
            if typeof(gethui) == "function" then
                return gethui()
            end
        end)
        if ok and typeof(ui) == "Instance" then
            return ui
        end
        error("UILib requires gethui() for UI parenting")
    end

    local function protectGui(gui)
        if syn and typeof(syn.protect_gui) == "function" then
            pcall(syn.protect_gui, gui)
        elseif typeof(protect_gui) == "function" then
            pcall(protect_gui, gui)
        end
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
        SharedEnv = SharedEnv,
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
