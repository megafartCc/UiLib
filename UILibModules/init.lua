return function(moduleRequire)
    local Library = {}
    Library.__index = Library

    local context = moduleRequire("shared.lua")()

    moduleRequire("motion.lua")(Library, context)
    moduleRequire("config.lua")(Library, context)
    moduleRequire("window.lua")(Library, context)

    return Library
end
