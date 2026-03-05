--[[
    UILib - Fatality-Style Roblox UI Library
    Bootstrap loader for the modular build.

    Usage:
        local Library = loadstring(readfile("build.lua"))()
        local Window = Library:CreateWindow({ Name = "FATALITY", Expire = "never" })
]]

local moduleCache = {}

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

local function fileExists(path)
    if typeof(isfile) == "function" then
        return isfile(path)
    end

    local ok = pcall(readfile, path)
    return ok
end

local function loadModule(path)
    local normalized = normalizePath(path)
    local cached = moduleCache[normalized]
    if cached ~= nil then
        return cached
    end

    local source = readfile(normalized)
    local chunk, err = loadstring(source, "@" .. normalized)
    if not chunk then
        error(string.format("UILib module load failed for %s: %s", normalized, tostring(err)))
    end

    local exported = chunk()
    moduleCache[normalized] = exported
    return exported
end

local function findEntryPath()
    local candidates = {
        "UILibModules/init.lua",
        "UILib/UILibModules/init.lua",
    }

    for _, candidate in ipairs(candidates) do
        local normalized = normalizePath(candidate)
        if fileExists(normalized) then
            return normalized
        end
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
