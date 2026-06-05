return function(Library, context)
    local DEFAULT_ESP_URL = "https://raw.githubusercontent.com/megafartCc/SAB/main/espmodule.lua"

    local function themeColor(key, fallback)
        if type(Library.GetThemeValue) == "function" then
            local value = Library:GetThemeValue(key)
            if value ~= nil then
                return value
            end
        end
        return fallback
    end

    local function bindTheme(instance, propertyName, themeKey, transform)
        if type(Library.RegisterThemeBinding) == "function" then
            Library:RegisterThemeBinding(instance, propertyName, themeKey, transform)
        end
    end

    local function loadEspModule(sourceUrl)
        local okGame, isGameInstance = pcall(function()
            return typeof(game) == "Instance"
        end)
        if not okGame or not isGameInstance then
            return nil
        end
        if type(game.HttpGet) ~= "function" or type(loadstring) ~= "function" then
            return nil
        end

        local ok, result = pcall(function()
            return loadstring(game:HttpGet(sourceUrl or DEFAULT_ESP_URL))()
        end)
        if ok then
            return result
        end
        return nil
    end

    local function safeEspCall(esp, methodName, value)
        if esp and type(esp[methodName]) == "function" then
            pcall(esp[methodName], esp, value)
        end
    end

    local function createGuiEspModule(opts)
        opts = opts or {}

        local Players = context.Players or game:GetService("Players")
        local RunService = context.RunService or game:GetService("RunService")
        local TextService = context.TextService or game:GetService("TextService")
        local LocalPlayer = context.Client or Players.LocalPlayer
        local C3 = Color3.fromRGB
        local V2 = Vector2.new
        local WHITE = C3(255, 255, 255)

        local settings = {
            Box = false,
            Name = false,
            Health = false,
            Team = false,
            Tracers = false,
            Skeleton = false,
            HeldItem = false,
            MaxDistance = opts.MaxDistance or 1000,
        }

        local tracked = {}
        local textMeasureCache = {}
        local renderConnection = nil
        local playerEspGui = nil
        local playerEspGuiReset = false
        local linePoints = {}
        local noSmoothLines = {}
        local LINE_SMOOTH_ALPHA = 0.58
        local LINE_RESET_DISTANCE = 90
        local BOUNDS_SMOOTH_ALPHA = 0.62
        local BOUNDS_RESET_DISTANCE = 90

        local function getEspGui()
            local ok, parent = pcall(context.getHiddenParent)
            if not ok or not parent then
                return nil
            end

            if not playerEspGuiReset then
                playerEspGuiReset = true
                local staleGui = parent:FindFirstChild("UnknownHubPlayerEsp")
                if staleGui then
                    pcall(function()
                        staleGui:Destroy()
                    end)
                end
            end

            if playerEspGui and playerEspGui.Parent == parent then
                return playerEspGui
            end

            local existing = parent:FindFirstChild("UnknownHubPlayerEsp")
            if existing and existing:IsA("ScreenGui") then
                playerEspGui = existing
                return playerEspGui
            end

            local gui = Instance.new("ScreenGui")
            gui.Name = "UnknownHubPlayerEsp"
            gui.IgnoreGuiInset = true
            gui.ResetOnSpawn = false
            gui.DisplayOrder = 100000
            gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
            gui.Parent = parent
            playerEspGui = gui
            return gui
        end

        local function destroyObject(object)
            if object then
                pcall(function()
                    linePoints[object] = nil
                    noSmoothLines[object] = nil
                    object:Destroy()
                end)
            end
        end

        local function makeLabel(name, color, textSize, zIndex)
            local gui = getEspGui()
            if not gui then
                return nil
            end

            local label = Instance.new("TextLabel")
            label.Name = name
            label.AnchorPoint = Vector2.new(0.5, 0.5)
            label.BackgroundTransparency = 1
            label.BorderSizePixel = 0
            label.Font = Enum.Font.GothamBold
            label.TextColor3 = color
            label.TextSize = textSize
            label.TextStrokeColor3 = C3(0, 0, 0)
            label.TextStrokeTransparency = 0.35
            label.TextWrapped = false
            label.TextTruncate = Enum.TextTruncate.AtEnd
            label.Visible = false
            label.ZIndex = zIndex or 120
            label.Size = UDim2.fromOffset(230, textSize + 8)
            label.Parent = gui
            return label
        end

        local function makeLine(name, color, thickness, zIndex)
            local gui = getEspGui()
            if not gui then
                return nil
            end

            local line = Instance.new("Frame")
            line.Name = name
            line.AnchorPoint = Vector2.new(0.5, 0.5)
            line.BackgroundColor3 = color
            line.BackgroundTransparency = 0.05
            line.BorderSizePixel = 0
            line.Size = UDim2.fromOffset(0, thickness or 1)
            line.Visible = false
            line.ZIndex = zIndex or 110
            line.Parent = gui
            return line
        end

        local function setVisible(object, visible)
            if object then
                if visible ~= true then
                    linePoints[object] = nil
                end
                object.Visible = visible == true
            end
        end

        local function hideList(list)
            for _, object in ipairs(list or {}) do
                setVisible(object, false)
            end
        end

        local function snap(value)
            return math.floor((tonumber(value) or 0) + 0.5)
        end

        local function snapPoint(point)
            if not point then
                return nil
            end
            return V2(point.X, point.Y)
        end

        local function smoothPoint(previous, current)
            if not previous then
                return current
            end
            if (current - previous).Magnitude > LINE_RESET_DISTANCE then
                return current
            end
            return previous + ((current - previous) * LINE_SMOOTH_ALPHA)
        end

        local function updateLine(line, fromPoint, toPoint, color, thickness)
            if not line or not fromPoint or not toPoint then
                if line then
                    linePoints[line] = nil
                end
                setVisible(line, false)
                return
            end

            fromPoint = snapPoint(fromPoint)
            toPoint = snapPoint(toPoint)
            if not noSmoothLines[line] then
                local state = linePoints[line] or {}
                fromPoint = smoothPoint(state.From, fromPoint)
                toPoint = smoothPoint(state.To, toPoint)
                linePoints[line] = {
                    From = fromPoint,
                    To = toPoint,
                }
            end

            local delta = toPoint - fromPoint
            local length = delta.Magnitude
            if length < 1 then
                linePoints[line] = nil
                setVisible(line, false)
                return
            end

            line.BackgroundColor3 = color
            line.Size = UDim2.fromOffset(length, thickness or 1)
            line.Position = UDim2.fromOffset((fromPoint.X + toPoint.X) * 0.5, (fromPoint.Y + toPoint.Y) * 0.5)
            line.Rotation = math.deg((math.atan2 or math.atan)(delta.Y, delta.X))
            line.Visible = true
        end

        local function measureTextWidth(text, textSize, font)
            local key = tostring(font) .. "\0" .. tostring(textSize) .. "\0" .. tostring(text or "")
            local cached = textMeasureCache[key]
            if cached then
                return cached
            end

            local ok, size = pcall(function()
                return TextService:GetTextSize(text, textSize, font, Vector2.new(1000, textSize + 8))
            end)
            if ok and size then
                textMeasureCache[key] = size.X
                return size.X
            end
            local fallback = #tostring(text or "") * textSize * 0.55
            textMeasureCache[key] = fallback
            return fallback
        end

        local function updateNameLabel(label, text, centerX, top, boxWidth)
            if not label then
                return
            end
            if not settings.Name then
                label.Visible = false
                return
            end

            local resolvedBoxWidth = tonumber(boxWidth) or 0
            local maxWidth = math.max(96, math.min(440, snap(resolvedBoxWidth + 56)))
            local textSize = 12
            if resolvedBoxWidth >= 90 then
                textSize = 13
            end
            if resolvedBoxWidth >= 150 then
                textSize = 14
            end
            if resolvedBoxWidth >= 240 then
                textSize = 15
            end

            while textSize > 10 and measureTextWidth(text, textSize, label.Font) > maxWidth do
                textSize -= 1
            end

            local labelHeight = textSize + 6
            label.Text = text
            label.TextSize = textSize
            label.TextColor3 = WHITE
            label.Size = UDim2.fromOffset(maxWidth, labelHeight)
            label.Position = UDim2.fromOffset(centerX, top - (labelHeight * 0.5) - 4)
            label.Visible = true
        end

        local function project(camera, position)
            local point, onScreen = camera:WorldToViewportPoint(position)
            if not onScreen or point.Z <= 0 then
                return nil
            end
            return V2(point.X, point.Y)
        end

        local function updateWorldLine(camera, line, fromPosition, toPosition, color, thickness)
            local fromPoint = fromPosition and project(camera, fromPosition)
            local toPoint = toPosition and project(camera, toPosition)
            updateLine(line, fromPoint, toPoint, color, thickness)
        end

        local function makePlayerData(player)
            if tracked[player] then
                return tracked[player]
            end

            local data = {
                box = {},
                skeleton = {},
                bounds = nil,
            }

            for index = 1, 4 do
                data.box[index] = makeLine("PlayerBoxEspLine", WHITE, 1, 120)
            end

            data.tracer = makeLine("PlayerTracerEspLine", WHITE, 1, 110)
            data.healthBack = makeLine("PlayerHealthEspBack", C3(0, 0, 0), 3, 115)
            data.healthFill = makeLine("PlayerHealthEspFill", C3(0, 255, 0), 2, 125)
            data.name = makeLabel("PlayerNameEsp", WHITE, 11, 130)
            data.team = makeLabel("PlayerTeamEsp", WHITE, 12, 130)
            data.heldItem = makeLabel("PlayerHeldItemEsp", C3(255, 200, 0), 13, 130)

            if data.team then
                data.team.AnchorPoint = Vector2.new(0, 0.5)
                data.team.TextXAlignment = Enum.TextXAlignment.Left
                data.team.Size = UDim2.fromOffset(170, 20)
            end

            tracked[player] = data
            return data
        end

        local function removePlayerData(player)
            local data = tracked[player]
            if not data then
                return
            end

            for _, line in ipairs(data.box or {}) do
                destroyObject(line)
            end
            for _, line in ipairs(data.skeleton or {}) do
                destroyObject(line)
            end
            destroyObject(data.tracer)
            destroyObject(data.healthBack)
            destroyObject(data.healthFill)
            destroyObject(data.name)
            destroyObject(data.team)
            destroyObject(data.heldItem)
            tracked[player] = nil
        end

        local function hideData(data)
            if not data then
                return
            end

            hideList(data.box)
            hideList(data.skeleton)
            data.bounds = nil
            setVisible(data.tracer, false)
            setVisible(data.healthBack, false)
            setVisible(data.healthFill, false)
            setVisible(data.name, false)
            setVisible(data.team, false)
            setVisible(data.heldItem, false)
        end

        local r6LowerBodyParts = {
            "Left Leg",
            "Right Leg",
        }

        local r15LowerBodyParts = {
            "LeftFoot",
            "RightFoot",
            "LeftLowerLeg",
            "RightLowerLeg",
            "LeftUpperLeg",
            "RightUpperLeg",
        }

        local bodyBoundsPartNames = {
            Head = true,
            Torso = true,
            ["Left Arm"] = true,
            ["Right Arm"] = true,
            ["Left Leg"] = true,
            ["Right Leg"] = true,
            UpperTorso = true,
            LowerTorso = true,
            LeftUpperArm = true,
            LeftLowerArm = true,
            LeftHand = true,
            RightUpperArm = true,
            RightLowerArm = true,
            RightHand = true,
            LeftUpperLeg = true,
            LeftLowerLeg = true,
            LeftFoot = true,
            RightUpperLeg = true,
            RightLowerLeg = true,
            RightFoot = true,
        }

        local function getPart(character, name)
            local part = character and character:FindFirstChild(name)
            if part and part:IsA("BasePart") then
                return part
            end
            return nil
        end

        local function pointFromPart(part, offset)
            if not part then
                return nil
            end
            return part.CFrame:PointToWorldSpace(offset)
        end

        local function partEnd(part, yScale)
            if not part or not part.Parent then
                return nil
            end
            return pointFromPart(part, Vector3.new(0, part.Size.Y * yScale, 0))
        end

        local function midpoint(a, b, fallback)
            if a and b then
                return (a + b) * 0.5
            end
            return fallback
        end

        local function collectJointPositions(character, jointNames)
            local wanted = {}
            local found = {}
            for _, jointName in ipairs(jointNames) do
                wanted[jointName] = true
            end

            for _, inst in ipairs(character:GetDescendants()) do
                if wanted[inst.Name] and inst:IsA("Motor6D") then
                    if inst.Part0 and inst.Part0.Parent then
                        found[inst.Name] = inst.Part0.CFrame:PointToWorldSpace(inst.C0.Position)
                    elseif inst.Part1 and inst.Part1.Parent then
                        found[inst.Name] = inst.Part1.CFrame:PointToWorldSpace(inst.C1.Position)
                    end
                end
            end

            return found
        end

        local function getR6SkeletonSegments(character)
            local head = getPart(character, "Head")
            local torso = getPart(character, "Torso")
            local leftArm = getPart(character, "Left Arm")
            local rightArm = getPart(character, "Right Arm")
            local leftLeg = getPart(character, "Left Leg")
            local rightLeg = getPart(character, "Right Leg")

            if not head or not torso then
                return {}
            end

            local torsoSize = torso.Size
            local joints = collectJointPositions(character, {
                "Neck",
                "Left Shoulder",
                "Right Shoulder",
                "Left Hip",
                "Right Hip",
            })

            local neck = joints.Neck or partEnd(torso, 0.5)
            local leftShoulder = joints["Left Shoulder"] or pointFromPart(torso, Vector3.new(-torsoSize.X * 0.5, torsoSize.Y * 0.35, 0))
            local rightShoulder = joints["Right Shoulder"] or pointFromPart(torso, Vector3.new(torsoSize.X * 0.5, torsoSize.Y * 0.35, 0))
            local leftHip = joints["Left Hip"] or pointFromPart(torso, Vector3.new(-torsoSize.X * 0.25, -torsoSize.Y * 0.5, 0))
            local rightHip = joints["Right Hip"] or pointFromPart(torso, Vector3.new(torsoSize.X * 0.25, -torsoSize.Y * 0.5, 0))
            local pelvis = midpoint(leftHip, rightHip, partEnd(torso, -0.5))
            local shoulderCenter = midpoint(leftShoulder, rightShoulder, neck)
            local leftArmTop = partEnd(leftArm, 0.5) or leftShoulder
            local leftArmBottom = partEnd(leftArm, -0.5) or leftShoulder
            local rightArmTop = partEnd(rightArm, 0.5) or rightShoulder
            local rightArmBottom = partEnd(rightArm, -0.5) or rightShoulder
            local leftLegTop = partEnd(leftLeg, 0.5) or leftHip
            local leftLegBottom = partEnd(leftLeg, -0.5) or leftHip
            local rightLegTop = partEnd(rightLeg, 0.5) or rightHip
            local rightLegBottom = partEnd(rightLeg, -0.5) or rightHip

            return {
                { head.Position, neck },
                { neck, shoulderCenter },
                { shoulderCenter, pelvis },
                { leftShoulder, rightShoulder },
                { leftShoulder, leftArmTop },
                { leftArmTop, leftArmBottom },
                { rightShoulder, rightArmTop },
                { rightArmTop, rightArmBottom },
                { leftLegTop, rightLegTop },
                { pelvis, leftLegTop },
                { leftLegTop, leftLegBottom },
                { pelvis, rightLegTop },
                { rightLegTop, rightLegBottom },
            }
        end

        local function getR15SkeletonSegments(character)
            local head = getPart(character, "Head")
            local upperTorso = getPart(character, "UpperTorso")
            local lowerTorso = getPart(character, "LowerTorso")
            local leftUpperArm = getPart(character, "LeftUpperArm")
            local leftLowerArm = getPart(character, "LeftLowerArm")
            local leftHand = getPart(character, "LeftHand")
            local rightUpperArm = getPart(character, "RightUpperArm")
            local rightLowerArm = getPart(character, "RightLowerArm")
            local rightHand = getPart(character, "RightHand")
            local leftUpperLeg = getPart(character, "LeftUpperLeg")
            local leftLowerLeg = getPart(character, "LeftLowerLeg")
            local leftFoot = getPart(character, "LeftFoot")
            local rightUpperLeg = getPart(character, "RightUpperLeg")
            local rightLowerLeg = getPart(character, "RightLowerLeg")
            local rightFoot = getPart(character, "RightFoot")

            if not head or not upperTorso or not lowerTorso then
                return {}
            end

            local joints = collectJointPositions(character, {
                "Neck",
                "Waist",
                "LeftShoulder",
                "LeftElbow",
                "LeftWrist",
                "RightShoulder",
                "RightElbow",
                "RightWrist",
                "LeftHip",
                "LeftKnee",
                "LeftAnkle",
                "RightHip",
                "RightKnee",
                "RightAnkle",
            })

            local neck = joints.Neck or partEnd(upperTorso, 0.5)
            local waist = joints.Waist or midpoint(upperTorso.Position, lowerTorso.Position, partEnd(lowerTorso, 0.5))
            local leftShoulder = joints.LeftShoulder or (leftUpperArm and midpoint(upperTorso.Position, leftUpperArm.Position, leftUpperArm.Position))
            local rightShoulder = joints.RightShoulder or (rightUpperArm and midpoint(upperTorso.Position, rightUpperArm.Position, rightUpperArm.Position))
            local leftElbow = joints.LeftElbow or (leftUpperArm and leftLowerArm and midpoint(leftUpperArm.Position, leftLowerArm.Position, leftLowerArm.Position))
            local rightElbow = joints.RightElbow or (rightUpperArm and rightLowerArm and midpoint(rightUpperArm.Position, rightLowerArm.Position, rightLowerArm.Position))
            local leftWrist = joints.LeftWrist or (leftLowerArm and leftHand and midpoint(leftLowerArm.Position, leftHand.Position, leftHand.Position))
            local rightWrist = joints.RightWrist or (rightLowerArm and rightHand and midpoint(rightLowerArm.Position, rightHand.Position, rightHand.Position))
            local leftHip = joints.LeftHip or (leftUpperLeg and midpoint(lowerTorso.Position, leftUpperLeg.Position, leftUpperLeg.Position))
            local rightHip = joints.RightHip or (rightUpperLeg and midpoint(lowerTorso.Position, rightUpperLeg.Position, rightUpperLeg.Position))
            local leftKnee = joints.LeftKnee or (leftUpperLeg and leftLowerLeg and midpoint(leftUpperLeg.Position, leftLowerLeg.Position, leftLowerLeg.Position))
            local rightKnee = joints.RightKnee or (rightUpperLeg and rightLowerLeg and midpoint(rightUpperLeg.Position, rightLowerLeg.Position, rightLowerLeg.Position))
            local leftAnkle = joints.LeftAnkle or (leftLowerLeg and leftFoot and midpoint(leftLowerLeg.Position, leftFoot.Position, leftFoot.Position))
            local rightAnkle = joints.RightAnkle or (rightLowerLeg and rightFoot and midpoint(rightLowerLeg.Position, rightFoot.Position, rightFoot.Position))
            local shoulderCenter = midpoint(leftShoulder, rightShoulder, neck)
            local hipCenter = midpoint(leftHip, rightHip, lowerTorso.Position)
            local upperTorsoTop = partEnd(upperTorso, 0.5) or neck
            local upperTorsoBottom = partEnd(upperTorso, -0.5) or waist
            local lowerTorsoTop = partEnd(lowerTorso, 0.5) or waist
            local lowerTorsoBottom = partEnd(lowerTorso, -0.5) or hipCenter
            local leftUpperArmTop = partEnd(leftUpperArm, 0.5) or leftShoulder
            local leftUpperArmBottom = partEnd(leftUpperArm, -0.5) or leftElbow
            local leftLowerArmTop = partEnd(leftLowerArm, 0.5) or leftElbow
            local leftLowerArmBottom = partEnd(leftLowerArm, -0.5) or leftWrist
            local rightUpperArmTop = partEnd(rightUpperArm, 0.5) or rightShoulder
            local rightUpperArmBottom = partEnd(rightUpperArm, -0.5) or rightElbow
            local rightLowerArmTop = partEnd(rightLowerArm, 0.5) or rightElbow
            local rightLowerArmBottom = partEnd(rightLowerArm, -0.5) or rightWrist
            local leftUpperLegTop = partEnd(leftUpperLeg, 0.5) or leftHip
            local leftUpperLegBottom = partEnd(leftUpperLeg, -0.5) or leftKnee
            local leftLowerLegTop = partEnd(leftLowerLeg, 0.5) or leftKnee
            local leftLowerLegBottom = partEnd(leftLowerLeg, -0.5) or leftAnkle
            local rightUpperLegTop = partEnd(rightUpperLeg, 0.5) or rightHip
            local rightUpperLegBottom = partEnd(rightUpperLeg, -0.5) or rightKnee
            local rightLowerLegTop = partEnd(rightLowerLeg, 0.5) or rightKnee
            local rightLowerLegBottom = partEnd(rightLowerLeg, -0.5) or rightAnkle

            return {
                { head.Position, neck },
                { neck, upperTorsoTop },
                { upperTorsoTop, upperTorsoBottom },
                { upperTorsoBottom, lowerTorsoTop },
                { lowerTorsoTop, lowerTorsoBottom },
                { leftShoulder, rightShoulder },
                { shoulderCenter, leftShoulder },
                { leftShoulder, leftUpperArmTop },
                { leftUpperArmTop, leftUpperArmBottom },
                { leftUpperArmBottom, leftLowerArmTop },
                { leftLowerArmTop, leftLowerArmBottom },
                { leftLowerArmBottom, leftHand and leftHand.Position },
                { shoulderCenter, rightShoulder },
                { rightShoulder, rightUpperArmTop },
                { rightUpperArmTop, rightUpperArmBottom },
                { rightUpperArmBottom, rightLowerArmTop },
                { rightLowerArmTop, rightLowerArmBottom },
                { rightLowerArmBottom, rightHand and rightHand.Position },
                { leftHip, rightHip },
                { hipCenter, leftHip },
                { leftHip, leftUpperLegTop },
                { leftUpperLegTop, leftUpperLegBottom },
                { leftUpperLegBottom, leftLowerLegTop },
                { leftLowerLegTop, leftLowerLegBottom },
                { leftLowerLegBottom, leftFoot and leftFoot.Position },
                { hipCenter, rightHip },
                { rightHip, rightUpperLegTop },
                { rightUpperLegTop, rightUpperLegBottom },
                { rightUpperLegBottom, rightLowerLegTop },
                { rightLowerLegTop, rightLowerLegBottom },
                { rightLowerLegBottom, rightFoot and rightFoot.Position },
            }
        end

        local function getSkeletonSegments(character, humanoid)
            if humanoid and humanoid.RigType == Enum.HumanoidRigType.R15 then
                return getR15SkeletonSegments(character)
            end
            return getR6SkeletonSegments(character)
        end

        local function addScreenSegment(segments, fromPoint, toPoint)
            if fromPoint and toPoint then
                table.insert(segments, { fromPoint, toPoint })
            end
        end

        local function bezierPoint(a, b, c, t)
            local inv = 1 - t
            return (a * inv * inv) + (b * 2 * inv * t) + (c * t * t)
        end

        local function addCurveSegments(segments, fromPoint, controlPoint, toPoint, steps)
            steps = steps or 5
            local previous = fromPoint
            for index = 1, steps do
                local current = bezierPoint(fromPoint, controlPoint, toPoint, index / steps)
                addScreenSegment(segments, previous, current)
                previous = current
            end
        end

        local function getStyledSkeletonSegments(camera, character, humanoid, bounds)
            if not camera or not character or not bounds then
                return {}
            end

            local left = bounds.Left
            local right = bounds.Right
            local top = bounds.Top
            local bottom = bounds.Bottom
            local width = right - left
            local height = bottom - top
            if width <= 0 or height <= 0 then
                return {}
            end

            local cx = bounds.CenterX
            local fallback = {
                Head = V2(cx, top + (height * 0.18)),
                Neck = V2(cx, top + (height * 0.29)),
                Waist = V2(cx, top + (height * 0.55)),
                HipCenter = V2(cx, top + (height * 0.66)),
                LeftShoulder = V2(cx - (width * 0.22), top + (height * 0.31)),
                RightShoulder = V2(cx + (width * 0.22), top + (height * 0.31)),
                LeftHip = V2(cx - (width * 0.12), top + (height * 0.66)),
                RightHip = V2(cx + (width * 0.12), top + (height * 0.66)),
                LeftElbow = V2(cx - (width * 0.34), top + (height * 0.47)),
                RightElbow = V2(cx + (width * 0.34), top + (height * 0.47)),
                LeftHand = V2(cx - (width * 0.31), top + (height * 0.66)),
                RightHand = V2(cx + (width * 0.31), top + (height * 0.66)),
                LeftKnee = V2(cx - (width * 0.10), top + (height * 0.82)),
                RightKnee = V2(cx + (width * 0.10), top + (height * 0.82)),
                LeftFoot = V2(cx - (width * 0.13), bottom - (height * 0.05)),
                RightFoot = V2(cx + (width * 0.13), bottom - (height * 0.05)),
            }

            local function screen(position, fallbackPoint)
                return project(camera, position) or fallbackPoint
            end

            local isR15 = humanoid and humanoid.RigType == Enum.HumanoidRigType.R15
            local head = getPart(character, "Head")
            local torso = getPart(character, "Torso")
            local upperTorso = getPart(character, "UpperTorso")
            local lowerTorso = getPart(character, "LowerTorso")
            local headPoint = screen(head and head.Position, fallback.Head)
            local neck
            local waist
            local hipCenter
            local leftShoulder
            local rightShoulder
            local leftHip
            local rightHip
            local leftElbow
            local rightElbow
            local leftHand
            local rightHand
            local leftKnee
            local rightKnee
            local leftFoot
            local rightFoot

            if isR15 then
                local joints = collectJointPositions(character, {
                    "Neck",
                    "Waist",
                    "LeftShoulder",
                    "RightShoulder",
                    "LeftElbow",
                    "RightElbow",
                    "LeftWrist",
                    "RightWrist",
                    "LeftHip",
                    "RightHip",
                    "LeftKnee",
                    "RightKnee",
                    "LeftAnkle",
                    "RightAnkle",
                })
                local leftUpperArm = getPart(character, "LeftUpperArm")
                local rightUpperArm = getPart(character, "RightUpperArm")
                local leftLowerArm = getPart(character, "LeftLowerArm")
                local rightLowerArm = getPart(character, "RightLowerArm")
                local leftHandPart = getPart(character, "LeftHand")
                local rightHandPart = getPart(character, "RightHand")
                local leftUpperLeg = getPart(character, "LeftUpperLeg")
                local rightUpperLeg = getPart(character, "RightUpperLeg")
                local leftLowerLeg = getPart(character, "LeftLowerLeg")
                local rightLowerLeg = getPart(character, "RightLowerLeg")
                local leftFootPart = getPart(character, "LeftFoot")
                local rightFootPart = getPart(character, "RightFoot")

                neck = screen(joints.Neck or partEnd(upperTorso, 0.5), fallback.Neck)
                waist = screen(joints.Waist or (upperTorso and lowerTorso and midpoint(upperTorso.Position, lowerTorso.Position, lowerTorso.Position)), fallback.Waist)
                leftShoulder = screen(joints.LeftShoulder or (upperTorso and leftUpperArm and midpoint(upperTorso.Position, leftUpperArm.Position, leftUpperArm.Position)), fallback.LeftShoulder)
                rightShoulder = screen(joints.RightShoulder or (upperTorso and rightUpperArm and midpoint(upperTorso.Position, rightUpperArm.Position, rightUpperArm.Position)), fallback.RightShoulder)
                leftHip = screen(joints.LeftHip or (lowerTorso and leftUpperLeg and midpoint(lowerTorso.Position, leftUpperLeg.Position, leftUpperLeg.Position)), fallback.LeftHip)
                rightHip = screen(joints.RightHip or (lowerTorso and rightUpperLeg and midpoint(lowerTorso.Position, rightUpperLeg.Position, rightUpperLeg.Position)), fallback.RightHip)
                hipCenter = midpoint(leftHip, rightHip, fallback.HipCenter)
                leftElbow = screen(joints.LeftElbow or (leftUpperArm and leftLowerArm and midpoint(leftUpperArm.Position, leftLowerArm.Position, leftLowerArm.Position)), fallback.LeftElbow)
                rightElbow = screen(joints.RightElbow or (rightUpperArm and rightLowerArm and midpoint(rightUpperArm.Position, rightLowerArm.Position, rightLowerArm.Position)), fallback.RightElbow)
                leftHand = screen((leftHandPart and leftHandPart.Position) or joints.LeftWrist, fallback.LeftHand)
                rightHand = screen((rightHandPart and rightHandPart.Position) or joints.RightWrist, fallback.RightHand)
                leftKnee = screen(joints.LeftKnee or (leftUpperLeg and leftLowerLeg and midpoint(leftUpperLeg.Position, leftLowerLeg.Position, leftLowerLeg.Position)), fallback.LeftKnee)
                rightKnee = screen(joints.RightKnee or (rightUpperLeg and rightLowerLeg and midpoint(rightUpperLeg.Position, rightLowerLeg.Position, rightLowerLeg.Position)), fallback.RightKnee)
                leftFoot = screen((leftFootPart and leftFootPart.Position) or joints.LeftAnkle, fallback.LeftFoot)
                rightFoot = screen((rightFootPart and rightFootPart.Position) or joints.RightAnkle, fallback.RightFoot)
            else
                local joints = collectJointPositions(character, {
                    "Neck",
                    "Left Shoulder",
                    "Right Shoulder",
                    "Left Hip",
                    "Right Hip",
                })
                local leftArm = getPart(character, "Left Arm")
                local rightArm = getPart(character, "Right Arm")
                local leftLeg = getPart(character, "Left Leg")
                local rightLeg = getPart(character, "Right Leg")

                neck = screen(joints.Neck or partEnd(torso, 0.5), fallback.Neck)
                waist = screen(torso and torso.Position, fallback.Waist)
                leftShoulder = screen(joints["Left Shoulder"] or (torso and pointFromPart(torso, Vector3.new(-torso.Size.X * 0.5, torso.Size.Y * 0.35, 0))), fallback.LeftShoulder)
                rightShoulder = screen(joints["Right Shoulder"] or (torso and pointFromPart(torso, Vector3.new(torso.Size.X * 0.5, torso.Size.Y * 0.35, 0))), fallback.RightShoulder)
                leftHip = screen(joints["Left Hip"] or (torso and pointFromPart(torso, Vector3.new(-torso.Size.X * 0.25, -torso.Size.Y * 0.5, 0))), fallback.LeftHip)
                rightHip = screen(joints["Right Hip"] or (torso and pointFromPart(torso, Vector3.new(torso.Size.X * 0.25, -torso.Size.Y * 0.5, 0))), fallback.RightHip)
                hipCenter = midpoint(leftHip, rightHip, fallback.HipCenter)
                leftElbow = screen(leftArm and leftArm.Position, fallback.LeftElbow)
                rightElbow = screen(rightArm and rightArm.Position, fallback.RightElbow)
                leftHand = screen(partEnd(leftArm, -0.5), fallback.LeftHand)
                rightHand = screen(partEnd(rightArm, -0.5), fallback.RightHand)
                leftKnee = screen(leftLeg and leftLeg.Position, fallback.LeftKnee)
                rightKnee = screen(rightLeg and rightLeg.Position, fallback.RightKnee)
                leftFoot = screen(partEnd(leftLeg, -0.5), fallback.LeftFoot)
                rightFoot = screen(partEnd(rightLeg, -0.5), fallback.RightFoot)
            end

            local shoulderControl = V2((leftShoulder.X + rightShoulder.X) * 0.5, math.min(leftShoulder.Y, rightShoulder.Y, neck.Y) - (height * 0.018))
            local hipControl = V2((leftHip.X + rightHip.X) * 0.5, math.min(leftHip.Y, rightHip.Y, hipCenter.Y) - (height * 0.01))
            local shoulderJoin = bezierPoint(leftShoulder, shoulderControl, rightShoulder, 0.5)
            local hipJoin = bezierPoint(leftHip, hipControl, rightHip, 0.5)

            local segments = {}
            addScreenSegment(segments, headPoint, neck)
            addCurveSegments(segments, leftShoulder, shoulderControl, rightShoulder, 7)
            addScreenSegment(segments, neck, shoulderJoin)
            addScreenSegment(segments, shoulderJoin, waist)
            addScreenSegment(segments, waist, hipJoin)
            addCurveSegments(segments, leftHip, hipControl, rightHip, 5)
            addCurveSegments(segments, leftShoulder, leftElbow, leftHand, 6)
            addCurveSegments(segments, rightShoulder, rightElbow, rightHand, 6)
            addCurveSegments(segments, leftHip, leftKnee, leftFoot, 5)
            addCurveSegments(segments, rightHip, rightKnee, rightFoot, 5)
            return segments
        end

        local function updateSkeleton(camera, data, character, humanoid, bounds)
            local segments = getStyledSkeletonSegments(camera, character, humanoid, bounds)

            while #data.skeleton < #segments do
                local line = makeLine("PlayerSkeletonEspLine", WHITE, 1, 118)
                if line then
                    noSmoothLines[line] = true
                end
                table.insert(data.skeleton, line)
            end

            for index, segment in ipairs(segments) do
                local line = data.skeleton[index]
                if segment and segment[1] and segment[2] then
                    updateLine(line, segment[1], segment[2], WHITE, 1)
                else
                    setVisible(line, false)
                end
            end

            for index = #segments + 1, #data.skeleton do
                setVisible(data.skeleton[index], false)
            end
        end

        local function getRoot(character)
            return character and character:FindFirstChild("HumanoidRootPart")
        end

        local function getViewportBodyPoint(camera, worldPosition)
            if not worldPosition then
                return nil
            end

            local point = camera:WorldToViewportPoint(worldPosition)
            if point.Z <= 0 then
                return nil
            end
            return V2(point.X, point.Y)
        end

        local function getLowestBodyPoint(character, names)
            local lowestPoint = nil
            local lowestY = nil

            for _, name in ipairs(names) do
                local part = getPart(character, name)
                if part then
                    local point = pointFromPart(part, Vector3.new(0, -part.Size.Y * 0.55, 0))
                    if not lowestY or point.Y < lowestY then
                        lowestPoint = point
                        lowestY = point.Y
                    end
                end
            end

            return lowestPoint
        end

        local function includeBoundsPoint(bounds, point)
            if not point then
                return
            end

            if not bounds.Left or point.X < bounds.Left then
                bounds.Left = point.X
            end
            if not bounds.Right or point.X > bounds.Right then
                bounds.Right = point.X
            end
            if not bounds.Top or point.Y < bounds.Top then
                bounds.Top = point.Y
            end
            if not bounds.Bottom or point.Y > bounds.Bottom then
                bounds.Bottom = point.Y
            end
            bounds.Count += 1
        end

        local function includePartBounds(camera, bounds, part)
            if not part or not part.Parent then
                return
            end

            local half = part.Size * 0.5
            for x = -1, 1, 2 do
                for y = -1, 1, 2 do
                    for z = -1, 1, 2 do
                        local world = part.CFrame:PointToWorldSpace(Vector3.new(half.X * x, half.Y * y, half.Z * z))
                        local viewportPoint = camera:WorldToViewportPoint(world)
                        if viewportPoint.Z > 0 then
                            includeBoundsPoint(bounds, V2(viewportPoint.X, viewportPoint.Y))
                        end
                    end
                end
            end
        end

        local function smoothNumber(previous, current, alpha)
            if previous == nil then
                return current
            end
            return previous + ((current - previous) * alpha)
        end

        local function smoothBounds(data, bounds)
            if not data or not bounds then
                return bounds
            end

            local previous = data.bounds
            if not previous then
                data.bounds = bounds
                return bounds
            end

            local dx = math.abs((bounds.CenterX or 0) - (previous.CenterX or 0))
            local dy = math.abs((bounds.CenterY or 0) - (previous.CenterY or 0))
            if dx > BOUNDS_RESET_DISTANCE or dy > BOUNDS_RESET_DISTANCE then
                data.bounds = bounds
                return bounds
            end

            local nextBounds = {
                Left = smoothNumber(previous.Left, bounds.Left, BOUNDS_SMOOTH_ALPHA),
                Right = smoothNumber(previous.Right, bounds.Right, BOUNDS_SMOOTH_ALPHA),
                Top = smoothNumber(previous.Top, bounds.Top, BOUNDS_SMOOTH_ALPHA),
                Bottom = smoothNumber(previous.Bottom, bounds.Bottom, BOUNDS_SMOOTH_ALPHA),
                CenterX = smoothNumber(previous.CenterX, bounds.CenterX, BOUNDS_SMOOTH_ALPHA),
                CenterY = smoothNumber(previous.CenterY, bounds.CenterY, BOUNDS_SMOOTH_ALPHA),
            }
            data.bounds = nextBounds
            return nextBounds
        end

        local function getCharacterScreenBounds(camera, character, humanoid)
            local root = getRoot(character)
            if not camera or not root then
                return nil
            end

            local bounds = {
                Count = 0,
            }
            for _, inst in ipairs(character:GetChildren()) do
                if bodyBoundsPartNames[inst.Name] and inst:IsA("BasePart") then
                    includePartBounds(camera, bounds, inst)
                end
            end

            if bounds.Count <= 0 then
                return nil
            end

            local viewportSize = camera.ViewportSize
            local paddingX = math.clamp((bounds.Right - bounds.Left) * 0.04, 2, 8)
            local paddingY = math.clamp((bounds.Bottom - bounds.Top) * 0.025, 2, 8)
            local left = math.clamp(bounds.Left - paddingX, -viewportSize.X * 0.25, viewportSize.X * 1.25)
            local right = math.clamp(bounds.Right + paddingX, -viewportSize.X * 0.25, viewportSize.X * 1.25)
            local top = math.clamp(bounds.Top - paddingY, -viewportSize.Y * 0.25, viewportSize.Y * 1.25)
            local bottom = math.clamp(bounds.Bottom + paddingY, -viewportSize.Y * 0.25, viewportSize.Y * 1.25)

            if right - left < 8 or bottom - top < 12 then
                return nil
            end

            return {
                Left = left,
                Right = right,
                Top = top,
                Bottom = bottom,
                CenterX = (left + right) * 0.5,
                CenterY = (top + bottom) * 0.5,
            }
        end

        local function isAlive(character)
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            return humanoid and humanoid.Health > 0, humanoid
        end

        local function getPlayerColor(player)
            if player.TeamColor then
                return player.TeamColor.Color
            end
            return C3(255, 255, 255)
        end

        local function anyEnabled()
            return settings.Box
                or settings.Name
                or settings.Health
                or settings.Team
                or settings.Tracers
                or settings.Skeleton
                or settings.HeldItem
        end

        local function render()
            local camera = workspace.CurrentCamera
            local localRoot = getRoot(LocalPlayer and LocalPlayer.Character)
            if not camera or not localRoot then
                for _, data in pairs(tracked) do
                    hideData(data)
                end
                return
            end

            local seen = {}
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer then
                    seen[player] = true
                    local data = makePlayerData(player)
                    local character = player.Character
                    local alive, humanoid = isAlive(character)
                    local root = getRoot(character)
                    if not alive or not root then
                        hideData(data)
                    else
                        local distance = (root.Position - localRoot.Position).Magnitude
                        if distance > settings.MaxDistance then
                            hideData(data)
                        else
                            local bounds = getCharacterScreenBounds(camera, character, humanoid)
                            if not bounds then
                                hideData(data)
                            else
                                bounds = smoothBounds(data, bounds)
                                local left = bounds.Left
                                local right = bounds.Right
                                local top = bounds.Top
                                local bottom = bounds.Bottom
                                local color = WHITE
                                local boxWidth = right - left

                                if settings.Box then
                                    updateLine(data.box[1], V2(left, top), V2(right, top), WHITE, 1)
                                    updateLine(data.box[2], V2(left, bottom), V2(right, bottom), WHITE, 1)
                                    updateLine(data.box[3], V2(left, top), V2(left, bottom), WHITE, 1)
                                    updateLine(data.box[4], V2(right, top), V2(right, bottom), WHITE, 1)
                                else
                                    hideList(data.box)
                                end

                                updateNameLabel(data.name, player.DisplayName or player.Name, bounds.CenterX, top, boxWidth)

                                if data.team then
                                    data.team.Text = player.Team and player.Team.Name or "No Team"
                                    data.team.TextColor3 = WHITE
                                    data.team.Position = UDim2.fromOffset(right + 8, top + 8)
                                    data.team.Visible = settings.Team
                                end

                                if settings.Health then
                                    local ratio = math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1)
                                    local x = left - 6
                                    updateLine(data.healthBack, V2(x, bottom), V2(x, top), C3(0, 0, 0), 3)
                                    updateLine(data.healthFill, V2(x, bottom), V2(x, bottom - ((bottom - top) * ratio)), C3(255, 0, 0):Lerp(C3(0, 255, 0), ratio), 2)
                                else
                                    setVisible(data.healthBack, false)
                                    setVisible(data.healthFill, false)
                                end

                                if settings.Tracers then
                                    updateLine(data.tracer, V2(camera.ViewportSize.X * 0.5, camera.ViewportSize.Y - 8), V2(bounds.CenterX, bottom), color, 1)
                                else
                                    setVisible(data.tracer, false)
                                end

                                if settings.Skeleton then
                                    updateSkeleton(camera, data, character, humanoid, bounds)
                                else
                                    hideList(data.skeleton)
                                end

                                if data.heldItem then
                                    local tool = character:FindFirstChildWhichIsA("Tool")
                                    data.heldItem.Text = tool and tool.Name or ""
                                    data.heldItem.Position = UDim2.fromOffset(bounds.CenterX, bottom + 10)
                                    data.heldItem.Visible = settings.HeldItem and tool ~= nil
                                end
                            end
                        end
                    end
                end
            end

            for player in pairs(tracked) do
                if not seen[player] or not player.Parent then
                    removePlayerData(player)
                end
            end
        end

        local function updateLoop()
            if anyEnabled() then
                if not renderConnection then
                    renderConnection = RunService.RenderStepped:Connect(function()
                        pcall(render)
                    end)
                end
                pcall(render)
            else
                if renderConnection then
                    renderConnection:Disconnect()
                    renderConnection = nil
                end
                for _, data in pairs(tracked) do
                    hideData(data)
                end
            end
        end

        local api = {}

        function api:Init()
            updateLoop()
        end

        function api:SetBoxEsp(value)
            settings.Box = value == true
            updateLoop()
        end

        function api:SetNameEsp(value)
            settings.Name = value == true
            updateLoop()
        end

        function api:SetHealthEsp(value)
            settings.Health = value == true
            updateLoop()
        end

        function api:SetTeamEsp(value)
            settings.Team = value == true
            updateLoop()
        end

        function api:SetTracers(value)
            settings.Tracers = value == true
            updateLoop()
        end

        function api:SetSkeletonEsp(value)
            settings.Skeleton = value == true
            updateLoop()
        end

        function api:SetHeldItemEsp(value)
            settings.HeldItem = value == true
            updateLoop()
        end

        function api:SetMaxDist(value)
            settings.MaxDistance = tonumber(value) or settings.MaxDistance
            updateLoop()
        end

        function api:Destroy()
            if renderConnection then
                renderConnection:Disconnect()
                renderConnection = nil
            end
            for player in pairs(tracked) do
                removePlayerData(player)
            end
        end

        return api
    end

    local function makePreview(menu, controlsSection, state, opts)
        opts = opts or {}

        local win = controlsSection and controlsSection._win
        local main = win and win._main
        if not main then
            return nil
        end

        local initialVisible = true
        if menu._page then
            initialVisible = menu._page.Visible == true
        end
        initialVisible = initialVisible and state.Preview == true

        local previewWidth = opts.PreviewWidth or 240
        local previewVerticalInset = opts.PreviewVerticalInset or 0

        local panel = Instance.new("Frame", main)
        panel.Name = "PlayerEspPreviewPanel"
        panel.AnchorPoint = Vector2.new(0, 0.5)
        panel.BackgroundColor3 = themeColor("Section", Color3.fromRGB(24, 24, 24))
        panel.BackgroundTransparency = themeColor("SectionTransparency", 0)
        panel.BorderSizePixel = 0
        panel.ClipsDescendants = true
        panel.Position = UDim2.new(1, opts.PreviewGap or 8, 0.5, 0)
        panel.Size = UDim2.new(0, previewWidth, 1, -previewVerticalInset)
        panel.Visible = initialVisible
        panel.ZIndex = 90
        bindTheme(panel, "BackgroundColor3", "Section")
        bindTheme(panel, "BackgroundTransparency", "SectionTransparency")
        Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 5)

        local panelStroke = Instance.new("UIStroke", panel)
        panelStroke.Color = themeColor("Line", Color3.fromRGB(60, 60, 60))
        panelStroke.Transparency = 0.8
        bindTheme(panelStroke, "Color", "Line")

        local title = Instance.new("TextLabel", panel)
        title.Name = "Title"
        title.BackgroundTransparency = 1
        title.BorderSizePixel = 0
        title.Position = UDim2.new(0, 10, 0, 10)
        title.Size = UDim2.new(1, -20, 0, 16)
        title.Font = Enum.Font.GothamBold
        title.Text = opts.PreviewName or "ESP PREVIEW"
        title.TextColor3 = themeColor("Text", Color3.fromRGB(235, 235, 235))
        title.TextSize = 10
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.ZIndex = 91
        bindTheme(title, "TextColor3", "Text")

        local sample = Instance.new("Frame", panel)
        sample.Name = "Box"
        sample.AnchorPoint = Vector2.new(0.5, 0.5)
        sample.BackgroundTransparency = 1
        sample.Position = UDim2.new(0.5, 0, 0.48, 0)
        sample.Size = UDim2.fromOffset(72, 150)
        sample.ZIndex = 91

        local boxStroke = Instance.new("UIStroke", sample)
        boxStroke.Color = themeColor("Line", Color3.fromRGB(60, 60, 60))
        boxStroke.Thickness = 1
        boxStroke.Transparency = 0.65

        local function makeText(name, parent, textSize, align)
            local label = Instance.new("TextLabel", parent)
            label.Name = name
            label.BackgroundTransparency = 1
            label.BorderSizePixel = 0
            label.Font = Enum.Font.GothamBold
            label.TextColor3 = themeColor("Text", Color3.fromRGB(235, 235, 235))
            label.TextSize = textSize or 11
            label.TextStrokeTransparency = 0.35
            label.TextXAlignment = align or Enum.TextXAlignment.Center
            label.TextYAlignment = Enum.TextYAlignment.Center
            label.ZIndex = 92
            bindTheme(label, "TextColor3", "Text")
            return label
        end

        local nameLabel = makeText("NameLabel", sample, 11)
        nameLabel.Text = opts.PreviewPlayerName or "PreviewPlayer"
        nameLabel.Position = UDim2.new(0, -70, 0, -24)
        nameLabel.Size = UDim2.new(1, 140, 0, 16)

        local teamLabel = makeText("TeamLabel", sample, 11, Enum.TextXAlignment.Left)
        teamLabel.Text = opts.PreviewTeamName or "No Team"
        teamLabel.Position = UDim2.new(1, 8, 0, 0)
        teamLabel.Size = UDim2.new(0, 74, 0, 15)

        local healthBack = Instance.new("Frame", sample)
        healthBack.Name = "HealthBack"
        healthBack.BackgroundColor3 = themeColor("Line", Color3.fromRGB(60, 60, 60))
        healthBack.BorderSizePixel = 0
        healthBack.Position = UDim2.new(0, -8, 0, 0)
        healthBack.Size = UDim2.new(0, 3, 1, 0)
        healthBack.ZIndex = 92
        bindTheme(healthBack, "BackgroundColor3", "Line")

        local healthFill = Instance.new("Frame", healthBack)
        healthFill.Name = "HealthFill"
        healthFill.AnchorPoint = Vector2.new(0, 1)
        healthFill.BackgroundColor3 = Color3.fromRGB(76, 255, 115)
        healthFill.BorderSizePixel = 0
        healthFill.Position = UDim2.new(0, 0, 1, 0)
        healthFill.Size = UDim2.new(1, 0, 0.82, 0)
        healthFill.ZIndex = 93

        local healthText = makeText("HealthText", sample, 10, Enum.TextXAlignment.Right)
        healthText.Text = opts.PreviewHealthText or "82 HP"
        healthText.Position = UDim2.new(0, -58, 0, 8)
        healthText.Size = UDim2.new(0, 46, 0, 14)

        local heldItemLabel = makeText("HeldItemLabel", sample, 11)
        heldItemLabel.Text = opts.PreviewHeldItem or "Knife"
        heldItemLabel.TextColor3 = themeColor("Main", Color3.fromRGB(245, 49, 116))
        heldItemLabel.Position = UDim2.new(0, -45, 1, 5)
        heldItemLabel.Size = UDim2.new(1, 90, 0, 16)
        bindTheme(heldItemLabel, "TextColor3", "Main")

        local tracerLine = Instance.new("Frame", panel)
        tracerLine.Name = "Tracer"
        tracerLine.AnchorPoint = Vector2.new(0.5, 0.5)
        tracerLine.BackgroundColor3 = themeColor("Main", Color3.fromRGB(245, 49, 116))
        tracerLine.BorderSizePixel = 0
        tracerLine.Size = UDim2.fromOffset(1, 1)
        tracerLine.ZIndex = 91
        bindTheme(tracerLine, "BackgroundColor3", "Main")

        local skeletonLines = {}
        local function makeLine(name)
            local line = Instance.new("Frame", sample)
            line.Name = name
            line.AnchorPoint = Vector2.new(0.5, 0.5)
            line.BackgroundColor3 = Color3.fromRGB(0, 255, 255)
            line.BorderSizePixel = 0
            line.Size = UDim2.fromOffset(1, 1)
            line.ZIndex = 92
            table.insert(skeletonLines, line)
            return line
        end

        local skeleton = {
            Shoulders = makeLine("SkeletonShoulders"),
            Neck = makeLine("SkeletonNeck"),
            Spine = makeLine("SkeletonSpine"),
            Hips = makeLine("SkeletonHips"),
            LeftArm = makeLine("SkeletonLeftArm"),
            RightArm = makeLine("SkeletonRightArm"),
            LeftLeg = makeLine("SkeletonLeftLeg"),
            RightLeg = makeLine("SkeletonRightLeg"),
        }

        local function snapPixel(value)
            return math.floor(value + 0.5)
        end

        local function setLine(line, x1, y1, x2, y2, thickness)
            x1 = snapPixel(x1)
            y1 = snapPixel(y1)
            x2 = snapPixel(x2)
            y2 = snapPixel(y2)

            local dx = x2 - x1
            local dy = y2 - y1
            local length = math.sqrt((dx * dx) + (dy * dy))
            local resolvedThickness = thickness or 1

            line.Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2)
            line.Size = UDim2.fromOffset(math.max(1, length + 1), resolvedThickness)
            line.Rotation = math.deg((math.atan2 or math.atan)(dy, dx))
        end

        local function layoutPreview()
            local panelHeight = panel.AbsoluteSize.Y
            local panelWidth = panel.AbsoluteSize.X
            if panelHeight <= 0 or panelWidth <= 0 then
                return
            end

            local boxHeight = math.clamp(math.floor(panelHeight * 0.42), 120, math.max(120, panelHeight - 64))
            boxHeight = math.max(120, math.floor(boxHeight / 2) * 2)
            local boxWidth = math.clamp(math.floor(boxHeight * 0.48), 56, math.max(56, panelWidth - 46))
            boxWidth = math.max(56, math.floor(boxWidth / 2) * 2)
            sample.Size = UDim2.fromOffset(boxWidth, boxHeight)

            local boxCenterY = snapPixel(panelHeight * 0.48)
            local boxBottomY = boxCenterY + (boxHeight / 2)
            local boxCenterX = snapPixel(panelWidth / 2)
            sample.Position = UDim2.fromOffset(boxCenterX, boxCenterY)
            setLine(tracerLine, boxCenterX, panelHeight - 18, boxCenterX, boxBottomY, 1)

            local cx = snapPixel(boxWidth / 2)
            local headY = snapPixel(boxHeight * 0.23)
            local shoulderY = snapPixel(boxHeight * 0.35)
            local hipY = snapPixel(boxHeight * 0.61)
            local handY = snapPixel(boxHeight * 0.55)
            local footY = snapPixel(boxHeight * 0.91)

            local shoulderHalf = snapPixel(boxWidth * 0.30)
            local hipHalf = snapPixel(boxWidth * 0.17)
            local handHalf = snapPixel(boxWidth * 0.43)
            local footHalf = snapPixel(boxWidth * 0.28)

            setLine(skeleton.Shoulders, cx - shoulderHalf, shoulderY, cx + shoulderHalf, shoulderY)
            setLine(skeleton.Neck, cx, headY, cx, shoulderY)
            setLine(skeleton.Spine, cx, shoulderY, cx, hipY)
            setLine(skeleton.Hips, cx - hipHalf, hipY, cx + hipHalf, hipY)
            setLine(skeleton.LeftArm, cx - shoulderHalf, shoulderY, cx - handHalf, handY)
            setLine(skeleton.RightArm, cx + shoulderHalf, shoulderY, cx + handHalf, handY)
            setLine(skeleton.LeftLeg, cx - hipHalf, hipY, cx - footHalf, footY)
            setLine(skeleton.RightLeg, cx + hipHalf, hipY, cx + footHalf, footY)
        end

        local syncVisibility

        local function refreshPreview()
            syncVisibility()

            local activeColor = themeColor("Main", Color3.fromRGB(245, 49, 116))
            local inactiveColor = themeColor("Line", Color3.fromRGB(60, 60, 60))

            if state.Box then
                boxStroke.Color = activeColor
                boxStroke.Transparency = 0.05
            else
                boxStroke.Color = inactiveColor
                boxStroke.Transparency = 0.65
            end

            nameLabel.Visible = state.Name == true
            teamLabel.Visible = state.Team == true
            healthBack.Visible = state.Health == true
            healthText.Visible = state.Health == true
            tracerLine.Visible = state.Tracers == true
            heldItemLabel.Visible = state.HeldItem == true
            for _, line in ipairs(skeletonLines) do
                line.Visible = state.Skeleton == true
            end
        end

        syncVisibility = function()
            panel.Visible = state.Preview == true and (menu._page == nil or menu._page.Visible == true)
        end

        local function syncLayout()
            panel.Size = UDim2.new(0, previewWidth, 1, -previewVerticalInset)
            layoutPreview()
        end

        if controlsSection._cleanup and type(controlsSection._cleanup.Add) == "function" then
            controlsSection._cleanup:Add(panel, "Destroy", "PlayerEspPreviewPanel")
        end
        controlsSection:TrackConnection(panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutPreview), "PlayerEspPreviewLayout")
        controlsSection:TrackConnection(main:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncLayout), "PlayerEspPreviewWindowLayout")
        if menu._page then
            controlsSection:TrackConnection(menu._page:GetPropertyChangedSignal("Visible"):Connect(syncVisibility), "PlayerEspPreviewVisibility")
        end
        if type(Library.RegisterThemeCallback) == "function" then
            Library:RegisterThemeCallback(function()
                if panel.Parent then
                    refreshPreview()
                end
            end)
        end

        task.defer(syncLayout)
        task.defer(syncVisibility)
        task.defer(refreshPreview)

        return {
            Frame = panel,
            Box = sample,
            Refresh = refreshPreview,
            SetVisible = function(_, value)
                state.Preview = value == true
                syncVisibility()
            end,
        }
    end

    local function addPlayerEspSection(selfOrMenu, menuOrOpts, maybeOpts)
        local menu = selfOrMenu
        local opts = menuOrOpts

        if selfOrMenu == Library then
            menu = menuOrOpts
            opts = maybeOpts
        end

        opts = opts or {}
        if type(menu) ~= "table" or type(menu.AddSection) ~= "function" then
            error("AddPlayerESPSection requires a UiLib menu", 2)
        end

        local providedEsp = opts.ESP or opts.Esp or opts.Module
        local esp = nil
        if opts.UseProvidedEsp == true then
            esp = providedEsp
        elseif opts.LoadEsp == "external" or opts.UseExternalEsp == true then
            esp = providedEsp
            if not esp then
                esp = loadEspModule(opts.SourceUrl or opts.Url)
            end
        else
            esp = createGuiEspModule(opts)
        end

        if not esp and opts.LoadEsp ~= false then
            esp = loadEspModule(opts.SourceUrl or opts.Url)
        end
        if esp and type(esp.Init) == "function" then
            pcall(esp.Init, esp)
        end

        local section = opts.Section or menu:AddSection({
            Name = opts.Name or "PLAYER ESP",
            Column = opts.Column or 1,
        })

        local state = {
            Preview = opts.PreviewDefault ~= false,
            Box = opts.BoxDefault == true,
            Name = opts.NameDefault == true,
            Health = opts.HealthDefault == true,
            Team = opts.TeamDefault == true,
            Tracers = opts.TracersDefault == true,
            Skeleton = opts.SkeletonDefault == true,
            HeldItem = opts.HeldItemDefault == true,
            MaxDistance = opts.MaxDistance or 1000,
        }

        local api = {
            ESP = esp,
            Section = section,
            State = state,
            Controls = {},
        }

        local preview
        local function refreshPreview()
            if preview and preview.Refresh then
                preview.Refresh()
            end
        end

        local function notifyChange(key, value)
            local callback = opts["On" .. key .. "Changed"]
            if type(callback) == "function" then
                pcall(callback, value, api)
            end
            if type(opts.Callback) == "function" then
                pcall(opts.Callback, key, value, api)
            end
        end

        local function setToggle(key, methodName, value)
            state[key] = value and true or false
            safeEspCall(esp, methodName, state[key])
            refreshPreview()
            notifyChange(key, state[key])
        end

        local function addToggle(name, key, methodName, defaultValue)
            local control = section:AddToggle({
                Name = name,
                Default = defaultValue == true,
                Callback = function(value)
                    setToggle(key, methodName, value)
                end,
            })
            api.Controls[key] = control
            return control
        end

        if opts.Preview ~= false then
            api.Controls.Preview = section:AddToggle({
                Name = opts.PreviewToggleName or "ESP Preview",
                Default = state.Preview == true,
                Callback = function(value)
                    state.Preview = value == true
                    refreshPreview()
                    notifyChange("Preview", state.Preview)
                end,
            })
        end

        api.Controls.Box = addToggle("Box ESP", "Box", "SetBoxEsp", state.Box)

        if type(opts.AfterBox) == "function" then
            pcall(opts.AfterBox, section, api)
        end

        api.Controls.Name = addToggle("Name ESP", "Name", "SetNameEsp", state.Name)
        api.Controls.Health = addToggle("Health ESP", "Health", "SetHealthEsp", state.Health)
        api.Controls.Team = addToggle("Team ESP", "Team", "SetTeamEsp", state.Team)
        api.Controls.Tracers = addToggle("Tracers", "Tracers", "SetTracers", state.Tracers)
        api.Controls.Skeleton = addToggle("Skeleton ESP", "Skeleton", "SetSkeletonEsp", state.Skeleton)
        api.Controls.HeldItem = addToggle("Held Item ESP", "HeldItem", "SetHeldItemEsp", state.HeldItem)

        api.Controls.MaxDistance = section:AddSlider({
            Name = "Max Distance",
            Min = opts.MinDistance or 100,
            Max = opts.MaxDistanceLimit or 5000,
            Default = state.MaxDistance,
            Suffix = opts.DistanceSuffix or " studs",
            Callback = function(value)
                state.MaxDistance = value
                safeEspCall(esp, "SetMaxDist", value)
                notifyChange("MaxDistance", value)
            end,
        })

        if opts.Preview ~= false then
            preview = makePreview(menu, section, state, opts)
            api.Preview = preview
        end

        safeEspCall(esp, "SetBoxEsp", state.Box)
        safeEspCall(esp, "SetNameEsp", state.Name)
        safeEspCall(esp, "SetHealthEsp", state.Health)
        safeEspCall(esp, "SetTeamEsp", state.Team)
        safeEspCall(esp, "SetTracers", state.Tracers)
        safeEspCall(esp, "SetSkeletonEsp", state.Skeleton)
        safeEspCall(esp, "SetHeldItemEsp", state.HeldItem)
        safeEspCall(esp, "SetMaxDist", state.MaxDistance)
        refreshPreview()

        function api:SetEsp(nextEsp)
            esp = nextEsp
            self.ESP = nextEsp
            if esp and type(esp.Init) == "function" then
                pcall(esp.Init, esp)
            end
            safeEspCall(esp, "SetMaxDist", state.MaxDistance)
            return self
        end

        function api:GetState()
            local copy = {}
            for key, value in pairs(state) do
                copy[key] = value
            end
            return copy
        end

        function api:RefreshPreview()
            refreshPreview()
            return self
        end

        return api
    end

    Library.AddPlayerESPSection = addPlayerEspSection
    Library.CreatePlayerESPSection = addPlayerEspSection
end
