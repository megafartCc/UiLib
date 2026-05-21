return function(moduleRequire)
    local Library = {}

    local context = moduleRequire("shared.lua")(moduleRequire)

    moduleRequire("motion.lua")(Library, context)
    moduleRequire("config.lua")(Library, context)
    moduleRequire("window.lua")(Library, context, moduleRequire)
    moduleRequire("player_esp.lua")(Library, context)

    return Library
end
