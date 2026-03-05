return function(Library, context)
    local spr = context.spr

    Library.Fusion = context.Fusion
    Library.Janitor = context.Janitor

    Library.Motion = {
        Smooth      = { 1.0,  6  },
        Hover       = { 0.9,  8  },
        Press       = { 0.8,  11 },
        Select      = { 0.82, 9  },
        Open        = { 0.72, 8  },
        Close       = { 0.92, 8  },
        Snappy      = { 0.8,  8  },
        Bouncy      = { 0.5,  6  },
        Gentle      = { 1.0,  4  },
        Quick       = { 1.0,  12 },
        Drag        = { 1.0,  16 },
        Popup       = { 0.7,  7  },
        Responsive  = { 0.85, 14 },
    }

    Library.Springs = Library.Motion

    function Library:Stop(inst, prop)
        pcall(function()
            spr.stop(inst, prop)
        end)
    end

    function Library:Animate(inst, token, props)
        local p = self.Motion[token] or self.Motion.Smooth
        spr.target(inst, p[1], p[2], props)
    end

    function Library:Spring(inst, preset, props)
        self:Animate(inst, preset, props)
    end
end
