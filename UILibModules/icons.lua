return function(Library, context)
    local Icons = {}
    local registry = {}
    local remoteCache = {}

    local LUCIDE_48PX_BASE = "https://raw.githubusercontent.com/latte-soft/lucide-roblox/master/icons/compiled/48px/"
    local CUSTOM_ASSET_FOLDER = "UnknownHubUiLib"

    local function normalizeName(value)
        local text = tostring(value or "")
        text = text:gsub("(%u)(%u%l)", "%1-%2")
        text = text:gsub("(%l)(%u)", "%1-%2")
        text = text:gsub("[_%s]+", "-")
        text = text:gsub("[^%w%-]+", "")
        text = text:gsub("%-+", "-")
        text = text:gsub("^%-", ""):gsub("%-$", "")
        return string.lower(text)
    end

    local function isRemoteUrl(value)
        return type(value) == "string" and (string.match(value, "^http://") or string.match(value, "^https://")) ~= nil
    end

    local function isRobloxImage(value)
        return type(value) == "string"
            and (string.match(value, "^rbxassetid://")
                or string.match(value, "^rbxthumb://")
                or string.match(value, "^rbxasset://")) ~= nil
    end

    local function getExtension(url)
        local lowered = string.lower(tostring(url or ""))
        local ext = string.match(lowered, "%.([%w]+)%?") or string.match(lowered, "%.([%w]+)$")
        if ext == "jpg" or ext == "jpeg" or ext == "png" or ext == "webp" then
            return ext
        end
        return "png"
    end

    local function hashText(text)
        local hash = 0
        for index = 1, #text do
            hash = (hash * 31 + string.byte(text, index)) % 1000000007
        end
        return tostring(hash)
    end

    local function ensureFolder(path)
        if type(isfolder) == "function" then
            local ok, exists = pcall(isfolder, path)
            if ok and exists then
                return true
            end
        end

        if type(makefolder) == "function" then
            local ok = pcall(makefolder, path)
            return ok
        end

        return false
    end

    local function fileExists(path)
        if type(isfile) ~= "function" then
            return false
        end

        local ok, exists = pcall(isfile, path)
        return ok and exists == true
    end

    local function getRequestFunction()
        if type(request) == "function" then
            return request
        end
        if type(http_request) == "function" then
            return http_request
        end
        if type(syn) == "table" and type(syn.request) == "function" then
            return syn.request
        end
        return nil
    end

    local function downloadUrl(url)
        local requestFunction = getRequestFunction()
        if requestFunction then
            local ok, response = pcall(requestFunction, {
                Url = url,
                Method = "GET",
            })
            if ok and type(response) == "table" then
                local status = tonumber(response.StatusCode or response.Status or response.status)
                local body = response.Body or response.body
                if (not status or (status >= 200 and status < 300)) and type(body) == "string" and body ~= "" then
                    return body
                end
            end
        end

        if typeof(game) == "Instance" and type(game.HttpGet) == "function" then
            local ok, body = pcall(function()
                return game:HttpGet(url)
            end)
            if ok and type(body) == "string" and body ~= "" then
                return body
            end
        end

        return nil
    end

    local function isPngBytes(body)
        return type(body) == "string" and string.sub(body, 1, 8) == string.char(137, 80, 78, 71, 13, 10, 26, 10)
    end

    local function cacheRemoteImage(url)
        if remoteCache[url] then
            return remoteCache[url]
        end

        if type(getcustomasset) ~= "function" or type(writefile) ~= "function" then
            return nil
        end

        if not ensureFolder(CUSTOM_ASSET_FOLDER) then
            return nil
        end

        local extension = getExtension(url)
        local path = CUSTOM_ASSET_FOLDER .. "/icon_" .. hashText(url) .. "." .. extension

        if not fileExists(path) then
            local body = downloadUrl(url)
            if not body then
                return nil
            end
            if extension == "png" and not isPngBytes(body) then
                return nil
            end

            local ok = pcall(writefile, path, body)
            if not ok then
                return nil
            end
        end

        local ok, asset = pcall(getcustomasset, path)
        if ok and type(asset) == "string" and asset ~= "" then
            remoteCache[url] = asset
            return asset
        end

        return nil
    end

    local function normalizeImage(value)
        if type(value) == "number" then
            return "rbxassetid://" .. tostring(value)
        end

        if type(value) ~= "string" then
            return nil
        end

        local text = tostring(value)
        if text == "" then
            return nil
        end

        if string.match(text, "^%d+$") then
            return "rbxassetid://" .. text
        end

        if isRobloxImage(text) then
            return text
        end

        if isRemoteUrl(text) then
            return cacheRemoteImage(text) or text
        end

        return nil
    end

    function Icons:Normalize(name)
        return normalizeName(name)
    end

    function Icons:Register(name, image)
        local key = normalizeName(name)
        if key == "" then
            return false
        end

        if type(image) ~= "string" and type(image) ~= "number" then
            return false
        end

        registry[key] = image
        return true
    end

    function Icons:RegisterMany(iconMap)
        if type(iconMap) ~= "table" then
            return 0
        end

        local count = 0
        for name, image in pairs(iconMap) do
            if self:Register(name, image) then
                count += 1
            end
        end
        return count
    end

    function Icons:Resolve(icon)
        if type(icon) == "table" then
            icon = icon.Image or icon.Icon or icon.Url or icon.URL or icon.Uri or icon.URI or icon.Asset or icon.AssetId or icon.Id
        end

        local direct = normalizeImage(icon)
        if direct then
            return direct
        end

        if type(icon) ~= "string" or string.match(icon, "^data:image/") then
            return nil
        end

        local key = normalizeName(icon)
        if key == "" or #key > 80 then
            return nil
        end

        local registered = registry[key]
        if registered ~= nil then
            return normalizeImage(registered)
        end

        return cacheRemoteImage(LUCIDE_48PX_BASE .. key .. ".png")
    end

    function Icons:Apply(imageLabel, icon, opts)
        opts = opts or {}
        if not imageLabel then
            return false
        end

        local image = self:Resolve(icon)
        if not image then
            imageLabel.Visible = opts.VisibleWhenMissing == true
            return false
        end

        imageLabel.Image = image
        imageLabel.Visible = opts.Visible ~= false

        if opts.ImageColor3 then
            imageLabel.ImageColor3 = opts.ImageColor3
        end
        if opts.ImageTransparency ~= nil then
            imageLabel.ImageTransparency = opts.ImageTransparency
        end
        if opts.ScaleType then
            imageLabel.ScaleType = opts.ScaleType
        end

        if opts.ThemeImageKey and Library.RegisterThemeBinding then
            Library:RegisterThemeBinding(imageLabel, "ImageColor3", opts.ThemeImageKey)
        end

        return true
    end

    return Icons
end
