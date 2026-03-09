return function(Library, context)
    local animator = context.Animator
    Library.Cleaner = context.Cleaner

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
        animator:stop(inst, prop)
    end

    function Library:Animate(inst, token, props)
        local p = self.Motion[token] or self.Motion.Smooth
        local speed = math.max(1, (p[2] or 8) / math.max(0.2, p[1] or 1))
        for prop, value in pairs(props or {}) do
            animator:setTarget(inst, prop, value, speed)
        end
    end

    function Library:Spring(inst, preset, props)
        self:Animate(inst, preset, props)
    end
end
