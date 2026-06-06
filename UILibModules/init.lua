return function(moduleRequire)
    local Library = {}

    local context = moduleRequire("shared.lua")(moduleRequire)

    moduleRequire("motion.lua")(Library, context)
    moduleRequire("config.lua")(Library, context)
    local Icons = moduleRequire("icons.lua")(Library, context)
    Library.Icons = Icons
    context.Icons = Icons
    moduleRequire("window.lua")(Library, context, moduleRequire)
    moduleRequire("player_esp.lua")(Library, context)

    return Library
end
