local Cleaner = {}

local function runTask(task)
    if type(task) ~= "table" then
        return
    end

    local obj = task.obj
    local method = task.method

    if type(method) == "function" then
        pcall(method, obj)
        return
    end

    if type(method) == "string" and obj ~= nil then
        local fn = obj[method]
        if type(fn) == "function" then
            pcall(fn, obj)
            return
        end
    end

    if typeof(obj) == "RBXScriptConnection" then
        pcall(function()
            obj:Disconnect()
        end)
        return
    end

    if type(obj) == "function" then
        pcall(obj)
    end
end

function Cleaner.new()
    local cleaner = {
        _seed = 0,
        _tasks = {},
    }

    function cleaner:Add(taskObject, methodName, key)
        if taskObject == nil then
            return nil
        end

        local useKey = key
        if useKey == nil then
            self._seed += 1
            useKey = "__cleanup_" .. tostring(self._seed)
        end

        if self._tasks[useKey] ~= nil then
            self:Remove(useKey)
        end

        self._tasks[useKey] = {
            obj = taskObject,
            method = methodName,
        }

        return taskObject
    end

    function cleaner:Remove(key)
        local task = self._tasks[key]
        if task == nil then
            return
        end

        self._tasks[key] = nil
        runTask(task)
    end

    function cleaner:Cleanup()
        for key, task in pairs(self._tasks) do
            self._tasks[key] = nil
            runTask(task)
        end
    end

    return cleaner
end

return Cleaner
