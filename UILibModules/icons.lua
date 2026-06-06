return function(Library, context)
    local Icons = {}
    local registry = {}

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

        if string.match(text, "^rbxassetid://")
            or string.match(text, "^rbxthumb://")
            or string.match(text, "^rbxasset://")
            or string.match(text, "^http://")
            or string.match(text, "^https://")
            or string.match(text, "^data:image/") then
            return text
        end

        return nil
    end

    function Icons:Normalize(name)
        return normalizeName(name)
    end

    function Icons:Register(name, image)
        local key = normalizeName(name)
        local resolved = normalizeImage(image)
        if key == "" or not resolved then
            return false
        end

        registry[key] = resolved
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

        if type(icon) == "string" then
            return registry[normalizeName(icon)]
        end

        return nil
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
