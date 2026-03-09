local function valueKind(value)
    local t = typeof(value)
    if t == "number" then
        return "number"
    end
    if t == "Color3" then
        return "Color3"
    end
    if t == "UDim2" then
        return "UDim2"
    end
    if t == "Vector2" then
        return "Vector2"
    end
    if t == "UDim" then
        return "UDim"
    end
    return nil
end

local function flattenValue(kind, value)
    if kind == "number" then
        return { value }
    end
    if kind == "Color3" then
        return { value.R, value.G, value.B }
    end
    if kind == "UDim2" then
        return { value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset }
    end
    if kind == "Vector2" then
        return { value.X, value.Y }
    end
    if kind == "UDim" then
        return { value.Scale, value.Offset }
    end
    return nil
end

local function rebuildValue(kind, packed)
    if kind == "number" then
        return packed[1]
    end
    if kind == "Color3" then
        return Color3.new(packed[1], packed[2], packed[3])
    end
    if kind == "UDim2" then
        return UDim2.new(packed[1], packed[2], packed[3], packed[4])
    end
    if kind == "Vector2" then
        return Vector2.new(packed[1], packed[2])
    end
    if kind == "UDim" then
        return UDim.new(packed[1], packed[2])
    end
    return nil
end

local function epsilonForKind(kind)
    if kind == "number" then
        return 0.001
    end
    if kind == "Color3" then
        return 0.002
    end
    if kind == "UDim2" then
        return 0.1
    end
    if kind == "Vector2" then
        return 0.1
    end
    if kind == "UDim" then
        return 0.1
    end
    return 0.001
end

local function isFinished(current, target, epsilon)
    for i = 1, #current do
        if math.abs(target[i] - current[i]) > epsilon then
            return false
        end
    end
    return true
end

local function stepToward(current, target, alpha)
    local out = table.create(#current)
    for i = 1, #current do
        out[i] = current[i] + ((target[i] - current[i]) * alpha)
    end
    return out
end

return function(RunService)
    local animator = {
        _tracks = {},
        _conn = nil,
    }

    local function stopLoopIfIdle()
        if next(animator._tracks) ~= nil then
            return
        end
        if animator._conn then
            animator._conn:Disconnect()
            animator._conn = nil
        end
    end

    local function removeTrack(inst, prop)
        local instanceTracks = animator._tracks[inst]
        if not instanceTracks then
            return
        end

        instanceTracks[prop] = nil
        if next(instanceTracks) == nil then
            animator._tracks[inst] = nil
        end
    end

    local function step(dt)
        for inst, props in pairs(animator._tracks) do
            for prop, track in pairs(props) do
                local alpha = 1 - math.exp(-(track.speed * dt))
                local current = stepToward(track.current, track.target, alpha)
                local done = isFinished(current, track.target, track.epsilon)

                if done then
                    current = track.target
                end

                local value = rebuildValue(track.kind, current)
                local ok = pcall(function()
                    inst[prop] = value
                end)

                if not ok or done then
                    removeTrack(inst, prop)
                else
                    track.current = current
                end
            end
        end

        stopLoopIfIdle()
    end

    local function ensureLoop()
        if animator._conn ~= nil then
            return
        end

        animator._conn = RunService.RenderStepped:Connect(step)
    end

    function animator:setTarget(inst, prop, targetValue, speed)
        if typeof(inst) ~= "Instance" or type(prop) ~= "string" then
            return
        end

        local kind = valueKind(targetValue)
        if kind == nil then
            pcall(function()
                inst[prop] = targetValue
            end)
            return
        end

        local currentValue
        local okRead = pcall(function()
            currentValue = inst[prop]
        end)
        if not okRead then
            return
        end

        local currentKind = valueKind(currentValue)
        if currentKind ~= kind then
            currentValue = targetValue
        end

        local currentFlat = flattenValue(kind, currentValue)
        local targetFlat = flattenValue(kind, targetValue)
        if currentFlat == nil or targetFlat == nil then
            pcall(function()
                inst[prop] = targetValue
            end)
            return
        end

        local instanceTracks = self._tracks[inst]
        if not instanceTracks then
            instanceTracks = {}
            self._tracks[inst] = instanceTracks
        end

        instanceTracks[prop] = {
            kind = kind,
            current = currentFlat,
            target = targetFlat,
            epsilon = epsilonForKind(kind),
            speed = math.max(1, tonumber(speed) or 8),
        }

        ensureLoop()
    end

    function animator:stop(inst, prop)
        if typeof(inst) ~= "Instance" then
            return
        end

        if prop == nil then
            self._tracks[inst] = nil
            stopLoopIfIdle()
            return
        end

        removeTrack(inst, prop)
        stopLoopIfIdle()
    end

    function animator:cleanup()
        self._tracks = {}
        if self._conn then
            self._conn:Disconnect()
            self._conn = nil
        end
    end

    return animator
end
