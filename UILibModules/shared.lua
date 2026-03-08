return function()
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

    local Fusion = loadstring(game:HttpGet("https://pst.rs.abhicracker.com/raw/96VnxLoJ.txt"))()
    local Janitor = loadstring(game:HttpGet("https://pst.rs.abhicracker.com/raw/FFP0rQvn.txt"))()
    local spr = loadstring(game:HttpGet("https://raw.githubusercontent.com/Fraktality/spr/master/spr.lua"))()

    local function getHiddenParent()
        local ok, ui = pcall(function()
            if typeof(gethui) == "function" then return gethui() end
            if typeof(get_hidden_gui) == "function" then return get_hidden_gui() end
            if typeof(gethiddenui) == "function" then return gethiddenui() end
        end)
        if ok and typeof(ui) == "Instance" then
            return ui
        end
        error("UILib requires gethui/get_hidden_gui/gethiddenui for UI parenting")
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
        Fusion = Fusion,
        Janitor = Janitor,
        FusionChildren = Fusion.Children,
        spr = spr,
        getHiddenParent = getHiddenParent,
        protectGui = protectGui,
        randomStr = randomStr,
    }
end
