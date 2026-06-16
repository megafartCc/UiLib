--[[
    UILib - Fatality-Style Roblox UI Library
    Bootstrap loader for the modular build.

    Usage:
        local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/megafartCc/UiLib/main/build.lua"))()
        local Window = Library:CreateWindow({ Name = "FATALITY", Expire = "never" })
]]

local moduleCache = {}
local okRobloxInstance, RobloxInstance = pcall(function()
    return Instance
end)
if not okRobloxInstance then
    RobloxInstance = nil
end
local safeModuleEnvironment = nil
local remoteModuleBases = {
    "https://raw.githubusercontent.com/megafartCc/UiLib/main/UILibModules/",
    "https://raw.githubusercontent.com/megafartCc/UiLib/refs/heads/main/UILibModules/",
    "https://cdn.jsdelivr.net/gh/megafartCc/UiLib@main/UILibModules/",
}
local remoteCacheTag = tostring(os.time())

local function normalizePath(path)
    path = string.gsub(path, "\\", "/")

    local prefix = ""
    if string.match(path, "^%a:/") then
        prefix = string.sub(path, 1, 2)
        path = string.sub(path, 3)
    end

    local parts = {}
    for part in string.gmatch(path, "[^/]+") do
        if part == ".." then
            if #parts > 0 then
                table.remove(parts)
            end
        elseif part ~= "." and part ~= "" then
            table.insert(parts, part)
        end
    end

    local normalized = table.concat(parts, "/")
    if prefix ~= "" then
        return prefix .. "/" .. normalized
    end
    return normalized
end

local function dirname(path)
    local normalized = normalizePath(path)
    return string.match(normalized, "^(.*)/[^/]+$") or ""
end

local function resolvePath(baseDir, relativePath)
    if string.match(relativePath, "^%a:[/\\]") then
        return normalizePath(relativePath)
    end

    if string.sub(relativePath, 1, 1) == "/" then
        return normalizePath(relativePath)
    end

    if baseDir == "" then
        return normalizePath(relativePath)
    end

    return normalizePath(baseDir .. "/" .. relativePath)
end

local function canHttpGet()
    local ok, result = pcall(function()
        return game ~= nil and type(game.HttpGet) == "function"
    end)
    return ok and result == true
end

local function remoteModulePath(path)
    local normalized = normalizePath(path)
    normalized = string.gsub(normalized, "^UILibModules/", "")
    normalized = string.gsub(normalized, "^UILib/UILibModules/", "")
    return normalized
end

local function withCacheTag(url)
    local separator = string.find(url, "?", 1, true) and "&" or "?"
    return url .. separator .. "v=" .. remoteCacheTag
end

local function setParentSafe(object, parent)
    if parent == nil then
        return
    end

    local ok = pcall(function()
        object.Parent = parent
    end)
    if ok then
        return
    end

    task.defer(function()
        pcall(function()
            if object and parent then
                object.Parent = parent
            end
        end)
    end)
end

local function safeInstanceNew(className, parent)
    local object = (RobloxInstance or Instance).new(className)
    setParentSafe(object, parent)
    return object
end

local function shouldRetryWithoutSafeEnvironment(err)
    local text = string.lower(tostring(err or ""))
    return string.find(text, "lacking capability", 1, true) ~= nil
        or string.find(text, "cannot access 'instance'", 1, true) ~= nil
        or string.find(text, "current thread cannot access", 1, true) ~= nil
end

local function getSafeModuleEnvironment()
    if safeModuleEnvironment then
        return safeModuleEnvironment
    end

    local baseEnvironment = _G
    if type(getfenv) == "function" then
        local okEnv, env = pcall(getfenv, 0)
        if okEnv and type(env) == "table" then
            baseEnvironment = env
        end
    end

    safeModuleEnvironment = setmetatable({
        Instance = {
            new = safeInstanceNew,
        },
    }, {
        __index = baseEnvironment,
    })

    return safeModuleEnvironment
end

local function compileModuleChunk(source, normalized)
    local chunk, err = loadstring(source, "@" .. normalized)
    if not chunk then
        error(string.format("UILib module load failed for %s: %s", normalized, tostring(err)))
    end
    return chunk
end

local function runModuleChunk(source, normalized, useSafeEnvironment)
    local chunk = compileModuleChunk(source, normalized)
    if useSafeEnvironment and type(setfenv) == "function" then
        setfenv(chunk, getSafeModuleEnvironment())
    end
    return chunk()
end

local function previewText(value)
    local preview = tostring(value or "")
    preview = string.gsub(preview, "%s+", " ")
    if #preview > 140 then
        preview = string.sub(preview, 1, 140) .. "..."
    end
    return preview
end

local function validateModuleSource(source, path, url)
    if type(source) ~= "string" or source == "" then
        return nil, "empty response from " .. tostring(url)
    end

    local first = string.match(source, "^%s*(.)")
    local prefix = string.lower(string.sub(source, 1, 240))
    if first == "<" or string.find(prefix, "<!doctype", 1, true) or string.find(prefix, "<html", 1, true) then
        return nil, "HTML response for " .. tostring(path) .. " from " .. tostring(url) .. ": " .. previewText(source)
    end

    if string.match(source, "^%s*%d+%s*:") then
        return nil, "HTTP error body for " .. tostring(path) .. " from " .. tostring(url) .. ": " .. previewText(source)
    end

    return source
end

local function fetchModuleSource(baseUrl, modulePath, normalized)
    local url = withCacheTag(baseUrl .. modulePath)
    local ok, source = pcall(function()
        return game:HttpGet(url)
    end)

    if not ok then
        return nil, "request failed for " .. tostring(normalized) .. " from " .. tostring(url) .. ": " .. tostring(source)
    end

    return validateModuleSource(source, normalized, url)
end

local function readModuleSource(path)
    local normalized = normalizePath(path)
    if canHttpGet() then
        local modulePath = remoteModulePath(normalized)
        local errors = {}

        for _, baseUrl in ipairs(remoteModuleBases) do
            local source, err = fetchModuleSource(baseUrl, modulePath, normalized)
            if source then
                return source
            end

            table.insert(errors, err)
            if type(task) == "table" and type(task.wait) == "function" then
                task.wait(0.15)
            end
        end

        error("UILib module source download failed for " .. tostring(normalized) .. ": " .. table.concat(errors, " | "))
    end
    error("UILib module source not found: " .. tostring(normalized))
end

local function loadModule(path)
    local normalized = normalizePath(path)
    local cached = moduleCache[normalized]
    if cached ~= nil then
        return cached
    end

    local source = readModuleSource(normalized)
    local okRun, exported = pcall(runModuleChunk, source, normalized, true)
    if not okRun and shouldRetryWithoutSafeEnvironment(exported) then
        okRun, exported = pcall(runModuleChunk, source, normalized, false)
    end
    if not okRun then
        error(tostring(exported))
    end

    moduleCache[normalized] = exported
    return exported
end

local function findEntryPath()
    if canHttpGet() then
        return "UILibModules/init.lua"
    end

    error("UILib bootstrap could not find UILibModules/init.lua")
end

local entryPath = findEntryPath()
local entryDir = dirname(entryPath)
local entryModule = loadModule(entryPath)

local function moduleRequire(relativePath)
    return loadModule(resolvePath(entryDir, relativePath))
end

return entryModule(moduleRequire)
