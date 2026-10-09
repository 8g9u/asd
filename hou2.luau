local Arvn = loadstring(game:HttpGet("https://raw.githubusercontent.com/koteqjjjj/arvn/main/arvn.lua"))()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local Mouse = LocalPlayer:GetMouse()

local Flags = Arvn.Flags
local Connections = {}
local ESPObjects = {}
local TracerObjects = {}
local Target = nil
local SilentCachedPart = nil
local SilentLastScan = 0
local NoclipConn, AntiAFKConn = nil, nil
local SpeedConn = nil
local SpeedBV = nil
local FOVCircle = nil
local SilentFOVCircle = nil
local Watermark = nil
local Spectating = false
local AntiStompDebounce = 0
local ESPLastHealthCheck = 0
local ESPNeedsRebuild = false
local RapidFireLast = 0
local RapidFireDone = {}
local RapidFireConns = {}
local AutoStompLast = {}
local MainRemote = nil
local FlyActive = false
local HitboxConn = nil
local TriggerBotLast = 0
local Whitelist = {}
local WL_GUI = nil
local WL_CONN = nil

local RageTargets        = {}
local RageTargetReady    = {}
local RageWaitingRespawn = {}
local RAGE_FIRE_RATE     = 0.05
local RageLastFire       = 0
local RageLastStomp      = {}
local RageLastStompAll   = 0
local RageSpectateConn   = nil
local MAX_RAGE_TARGETS   = 3
local FF_CLEAR_DELAY     = 0.12
local RageTPLast         = {}
local RageTPQueue        = nil

local SENTRY_Y           = 900
local SENTRY_RADIUS      = 150
local SENTRY_FIRE_RATE   = 0.02
local SENTRY_LOCK_TIME   = 15
local GUN_ORDER          = { "double", "db", "tactical", "revolver" }
local sentryTarget       = nil
local sentryLockUntil    = 0
local sentrySavedCF      = nil
local sentryLastFire     = 0
local sentryLastHp       = 100
local sentryVoided       = false
local sentryReturning    = false
local sentryGunIndex     = 1
local sentryAngle        = 0
local sentryCenter       = nil
local sentryNextChange   = 0

local SENTRY_BLOCK = {
    wallet = true, money = true, cash = true, phone = true,
    knife = true, fist = true, bat = true, bottle = true,
    food = true, drink = true, mask = true, box = true,
}

local HAS_DRAWING = pcall(function()
    if not Drawing then error("no drawing") end
    local t = Drawing.new("Square")
    t.Visible = false
    t:Remove()
end)

local HAS_QUAD = pcall(function()
    local q = Drawing.new("Quad")
    q.Visible = false
    q:Remove()
end)

local function NormalizeColor(v, fallback)
    fallback = fallback or Color3.new(1, 1, 1)
    if typeof(v) == "Color3" then return v end
    if type(v) == "table" then
        if v.Color and typeof(v.Color) == "Color3" then return v.Color end
        if v[1] and typeof(v[1]) == "Color3" then return v[1] end
        if v.color and typeof(v.color) == "Color3" then return v.color end
    end
    return fallback
end

local oldLighting = {
    Brightness = Lighting.Brightness,
    ClockTime = Lighting.ClockTime,
    Ambient = Lighting.Ambient,
    OutdoorAmbient = Lighting.OutdoorAmbient,
    FogEnd = Lighting.FogEnd,
    FogStart = Lighting.FogStart,
}

local function AddConn(c)
    table.insert(Connections, c)
    return c
end

local function SafeCall(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then warn("[houhou] " .. tostring(err)) end
    return ok, err
end

local function IsFinite(n)
    return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function IsFiniteVec2(v)
    return typeof(v) == "Vector2" and IsFinite(v.X) and IsFinite(v.Y)
end

local function GetHum()
    local c = LocalPlayer.Character
    return c and c:FindFirstChildOfClass("Humanoid") or nil
end

local function GetHRP()
    local c = LocalPlayer.Character
    return c and c:FindFirstChild("HumanoidRootPart") or nil
end

local function IsAlive(plr)
    local c = plr.Character
    if not c then return false end
    local h = c:FindFirstChildOfClass("Humanoid")
    return h and h.Health > 0
end

local function IsKO(plr)
    local c = plr and plr.Character
    if not c then return false, false end
    local be = c:FindFirstChild("BodyEffects")
    local isKO = false
    if be then
        local ko = be:FindFirstChild("K.O")
            or be:FindFirstChild("Knocked")
            or be:FindFirstChild("k.o")
            or be:FindFirstChild("KO")
        if ko and ko.Value == true then isKO = true end
    end
    local hum = c:FindFirstChildOfClass("Humanoid")
    local isDowned = hum and hum:GetState() == Enum.HumanoidStateType.Physics
    local isGrabbed = c:FindFirstChild("GRABBING_CONSTRAINT") ~= nil
    return (isKO or isDowned), isGrabbed
end

local function IsKnocked(plr)
    return (IsKO(plr))
end

local function HasTeam(plr)
    return plr.Team and LocalPlayer.Team and plr.Team == LocalPlayer.Team
end

local function IsWhitelisted(plr)
    if not plr then return false end
    return Whitelist[plr.UserId] == true or Whitelist[plr.Name] == true
end

local function HasForceField(plr)
    local c = plr and plr.Character
    if not c then return false end
    if c:FindFirstChildOfClass("ForceField") ~= nil then return true end
    local be = c:FindFirstChild("BodyEffects")
    if be then
        local ff = be:FindFirstChild("ForceField")
        if ff and (ff:IsA("BoolValue") and ff.Value or ff:IsA("ForceField")) then
            return true
        end
    end
    return false
end

local function GetTargetPart(plr, partName)
    local c = plr.Character
    if not c then return nil end
    if partName == "Closest" then
        local hrp = c:FindFirstChild("HumanoidRootPart")
        local head = c:FindFirstChild("Head")
        if head and hrp then
            local dH = (Camera.CFrame.Position - head.Position).Magnitude
            local dR = (Camera.CFrame.Position - hrp.Position).Magnitude
            return dH < dR and head or hrp
        end
        return head or hrp
    end
    if partName == "Head" then return c:FindFirstChild("Head") end
    return c:FindFirstChild(partName)
end

local function IsVisible(part)
    if not part then return false end
    local origin = Camera.CFrame.Position
    local dir = part.Position - origin
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {LocalPlayer.Character, Camera}
    local result = workspace:Raycast(origin, dir, params)
    if result then return result.Instance:IsDescendantOf(part.Parent) end
    return true
end

local function WorldToScreen(pos)
    if not Camera then return Vector2.new(0, 0), false end
    local ok, v2, onScreen = pcall(function() return Camera:WorldToViewportPoint(pos) end)
    if not ok or not v2 then return Vector2.new(0, 0), false end
    if not IsFinite(v2.X) or not IsFinite(v2.Y) or not IsFinite(v2.Z) then
        return Vector2.new(0, 0), false
    end
    return Vector2.new(v2.X, v2.Y), (onScreen and v2.Z > 0)
end

local function GetMousePos() return UserInputService:GetMouseLocation() end

local function PassesChecksForSticky(plr)
    if not plr then return false end
    if plr == LocalPlayer then return false end
    if not IsAlive(plr) then return false end
    if Flags.AimbotTeamCheck and HasTeam(plr) then return false end
    if Flags.AimbotKnockedCheck and IsKnocked(plr) then return false end
    if Flags.AimbotHealthCheck then
        local h = plr.Character:FindFirstChildOfClass("Humanoid")
        if h and h.Health < (Flags.AimbotMinHealth or 0) then return false end
    end
    return true
end

local function PassesChecks(plr)
    if not PassesChecksForSticky(plr) then return false end
    if Flags.AimbotWallCheck then
        local part = GetTargetPart(plr, Flags.AimbotHitPart or "Head")
        if not IsVisible(part) then return false end
    end
    return true
end

local function GetClosestToMouse()
    local mouse = GetMousePos()
    local fov = (Flags.AimbotUseFOV and Flags.AimbotFOV) or math.huge
    local closest, best = nil, fov
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and PassesChecks(plr) then
            local part = GetTargetPart(plr, Flags.AimbotHitPart or "Head")
            if part then
                local sp, onScreen = WorldToScreen(part.Position)
                if onScreen then
                    local d = (sp - mouse).Magnitude
                    if d < best then best = d closest = plr end
                end
            end
        end
    end
    return closest
end

local function GetClosestByDistance()
    local closest, best = nil, math.huge
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and PassesChecks(plr) then
            local part = GetTargetPart(plr, Flags.AimbotHitPart or "Head")
            if part then
                local d = (Camera.CFrame.Position - part.Position).Magnitude
                if d < best then best = d closest = plr end
            end
        end
    end
    return closest
end

local function GetClosestByFOV()
    local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    local fov = Flags.AimbotFOV or 120
    local closest, best = nil, fov
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and PassesChecks(plr) then
            local part = GetTargetPart(plr, Flags.AimbotHitPart or "Head")
            if part then
                local sp, onScreen = WorldToScreen(part.Position)
                if onScreen then
                    local d = (sp - center).Magnitude
                    if d < best then best = d closest = plr end
                end
            end
        end
    end
    return closest
end

local function GetAimbotTarget()
    local m = Flags.AimbotMethod or "Closest to Mouse"
    if m == "Closest Distance" then return GetClosestByDistance() end
    if m == "FOV" then return GetClosestByFOV() end
    return GetClosestToMouse()
end

local function ApplyAimbot()
    if not Flags.AimbotEnabled then
        Target = nil
        return
    end
    local mode = Flags.AimbotMode or "None"
    if mode == "None" then return end
    local shouldAim = (mode == "Always") or (mode == "OnKey" and UserInputService:IsKeyDown(Enum.KeyCode.V))
    if not shouldAim then return end

    if Target and (Target == LocalPlayer or not PassesChecksForSticky(Target)) then
        Target = nil
    end

    if not (Flags.AimbotStickyAim and Target) then
        Target = GetAimbotTarget()
        if Target == LocalPlayer then Target = nil end
    end

    if not Target or not IsAlive(Target) then return end

    local partName = Flags.AimbotHitPart or "Head"
    local part = Target.Character and Target.Character:FindFirstChild(partName)
    if not part then return end

    local aimPos = part.Position
    if Flags.AimbotPrediction then
        local vel = part.AssemblyLinearVelocity or Vector3.zero
        aimPos = aimPos + vel * (Flags.AimbotPredictionValue or 0.165)
    end

    if (Flags.AimbotType or "Camera") == "Camera" then
        local camPos = Camera.CFrame.Position
        local targetCF = CFrame.new(camPos, aimPos)
        if Flags.AimbotSmoothing and Flags.AimbotIndependentAxes then
            local cur = Camera.CFrame.LookVector
            local toTarget = (aimPos - camPos)
            if toTarget.Magnitude < 0.01 then return end
            local targetDir = toTarget.Unit
            local curYaw = math.atan2(cur.X, cur.Z)
            local curPitch = math.asin(math.clamp(cur.Y, -1, 1))
            local tgtYaw = math.atan2(targetDir.X, targetDir.Z)
            local tgtPitch = math.asin(math.clamp(targetDir.Y, -1, 1))
            local yawAlpha = math.clamp(1 / math.max(Flags.AimbotSmoothX or 15, 1), 0.05, 1)
            local pitchAlpha = math.clamp(1 / math.max(Flags.AimbotSmoothY or 15, 1), 0.05, 1)
            local yawDelta = tgtYaw - curYaw
            if yawDelta > math.pi then yawDelta = yawDelta - 2 * math.pi
            elseif yawDelta < -math.pi then yawDelta = yawDelta + 2 * math.pi end
            local newYaw = curYaw + yawDelta * yawAlpha
            local newPitch = curPitch + (tgtPitch - curPitch) * pitchAlpha
            local cosPitch = math.cos(newPitch)
            local look = Vector3.new(math.sin(newYaw) * cosPitch, math.sin(newPitch), math.cos(newYaw) * cosPitch)
            Camera.CFrame = CFrame.new(camPos, camPos + look)
        elseif Flags.AimbotSmoothing then
            local alpha = math.clamp(1 / math.max(Flags.AimbotSmoothness or 15, 1), 0.05, 1)
            Camera.CFrame = Camera.CFrame:Lerp(targetCF, alpha)
        else
            Camera.CFrame = targetCF
        end
    else
        if mousemoverel then
            local sp = WorldToScreen(aimPos)
            local m = GetMousePos()
            local delta = sp - m
            local multX = Flags.AimbotSmoothing and (1 / math.max(Flags.AimbotIndependentAxes and (Flags.AimbotSmoothX or 15) or (Flags.AimbotSmoothness or 15), 1)) or 1
            local multY = Flags.AimbotSmoothing and (1 / math.max(Flags.AimbotIndependentAxes and (Flags.AimbotSmoothY or 15) or (Flags.AimbotSmoothness or 15), 1)) or 1
            SafeCall(mousemoverel, delta.X * multX, delta.Y * multY)
        else
            Camera.CFrame = Camera.CFrame:Lerp(CFrame.new(Camera.CFrame.Position, aimPos), 0.2)
        end
    end
end

local function BuildFOVCircle()
    if not HAS_DRAWING then return end
    if FOVCircle then pcall(function() FOVCircle:Remove() end) end
    FOVCircle = Drawing.new("Circle")
    FOVCircle.Thickness = 2
    FOVCircle.NumSides = 64
    FOVCircle.Filled = false
    FOVCircle.Transparency = 1
    FOVCircle.Color = Color3.new(1, 1, 1)
    FOVCircle.Visible = false
end

local function UpdateFOVCircle()
    if not FOVCircle then return end
    if Flags.AimbotShowFOV then
        FOVCircle.Visible = true
        FOVCircle.Position = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
        FOVCircle.Radius = Flags.AimbotFOV or 120
        FOVCircle.Color = NormalizeColor(Flags.AimbotFOVColor, Color3.new(1, 1, 1))
        FOVCircle.Transparency = 1
        FOVCircle.Thickness = 2
    else
        FOVCircle.Visible = false
    end
end

local function BuildSilentFOVCircle()
    if not HAS_DRAWING then return end
    if SilentFOVCircle then pcall(function() SilentFOVCircle:Remove() end) end
    SilentFOVCircle = Drawing.new("Circle")
    SilentFOVCircle.Thickness = 2
    SilentFOVCircle.NumSides = 64
    SilentFOVCircle.Filled = false
    SilentFOVCircle.Transparency = 1
    SilentFOVCircle.Color = Color3.fromRGB(120, 180, 255)
    SilentFOVCircle.Visible = false
end

local function UpdateSilentFOVCircle()
    if not SilentFOVCircle then return end
    if Flags.SilentAimShowFOV then
        SilentFOVCircle.Visible = true
        SilentFOVCircle.Position = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
        SilentFOVCircle.Radius = Flags.SilentAimFOV or 150
        SilentFOVCircle.Color = NormalizeColor(Flags.SilentAimFOVColor, Color3.fromRGB(120, 180, 255))
        SilentFOVCircle.Transparency = 1
        SilentFOVCircle.Thickness = 2
    else
        SilentFOVCircle.Visible = false
    end
end

local function SilentScan()
    local now = tick()
    if now - SilentLastScan < 0.05 then return SilentCachedPart end
    SilentLastScan = now
    local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    local camPos = Camera.CFrame.Position
    local bestPart, bestScreen = nil, (Flags.SilentAimFOV or 150)
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local c = plr.Character
            if c then
                local skip = false
                if Flags.SilentAimTeamCheck and HasTeam(plr) then skip = true end
                if not skip and Flags.SilentAimKnockedCheck and IsKnocked(plr) then skip = true end
                if not skip then
                    local hum = c:FindFirstChildOfClass("Humanoid")
                    if hum and hum.Health > 0 then
                        local hrp = c:FindFirstChild("HumanoidRootPart")
                        local head = c:FindFirstChild("Head")
                        local part
                        local mode = Flags.SilentAimHitPart or "Head"
                        if mode == "Head" then part = head
                        elseif mode == "HumanoidRootPart" then part = hrp
                        else
                            if head and hrp then
                                part = (camPos - head.Position).Magnitude < (camPos - hrp.Position).Magnitude and head or hrp
                            else
                                part = head or hrp
                            end
                        end
                        if part and hrp and (hrp.Position - camPos).Magnitude <= 2500 then
                            local sp, onScreen = Camera:WorldToViewportPoint(part.Position)
                            if onScreen and sp.Z >= 0 then
                                local wallOk = true
                                if Flags.SilentAimWallCheck then
                                    if not IsVisible(part) then wallOk = false end
                                end
                                if wallOk then
                                    local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
                                    if d <= bestScreen then
                                        bestScreen = d
                                        bestPart = part
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    SilentCachedPart = bestPart
    return SilentCachedPart
end

local function InstallSilentHooks()
    if not (hookmetamethod and newcclosure and getnamecallmethod) then return false end
    local check = checkcaller or function() return false end
    pcall(function()
        local oldIndex
        oldIndex = hookmetamethod(game, "__index", newcclosure(function(self, key)
            if Flags.SilentAimEnabled and not check() and self == Mouse then
                local part = SilentCachedPart
                if part then
                    if key == "Hit" then return CFrame.new(part.Position) end
                    if key == "Target" then return part end
                end
            end
            return oldIndex(self, key)
        end))
    end)
    pcall(function()
        local oldNC
        oldNC = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
            if not Flags.SilentAimEnabled or check() then return oldNC(self, ...) end
            local method = getnamecallmethod()
            local part = SilentCachedPart
            if part and MainRemote and self == MainRemote and method == "FireServer" then
                local a = { ... }
                local hitPos = part.Position
                if a[1] == "UpdateMousePosI2" or a[1] == "UpdateMousePosI" or a[1] == "UpdateMousePos" then
                    a[2] = hitPos
                    return oldNC(self, table.unpack(a))
                end
                if a[1] == "ShootGun" then
                    if typeof(a[3]) == "Vector3" and typeof(a[4]) == "Vector3" then
                        a[4] = hitPos
                        a[5] = part
                        a[6] = Vector3.new(0, 1, 0)
                        return oldNC(self, table.unpack(a))
                    end
                    if typeof(a[3]) == "Vector3" then
                        a[5] = hitPos
                        a[6] = part
                        a[7] = Vector3.new(0, 1, 0)
                        return oldNC(self, table.unpack(a))
                    end
                elseif a[1] == "ShootingGunLetsGo" then
                    a[3] = hitPos
                    a[4] = { { Position = hitPos, Normal = Vector3.new(0, 1, 0), Instance = part } }
                    return oldNC(self, table.unpack(a))
                end
            end
            return oldNC(self, ...)
        end))
    end)
    return true
end

local ARC_SEGS = 20
local ARC_STRANDS = 3

local function GetScaledTextSize(baseSize, minSize, boxHeight)
    if not boxHeight or boxHeight <= 0 then return baseSize end
    local scale = math.clamp(boxHeight / 60, 0.85, 1.7)
    local result = math.floor(baseSize * scale)
    if result < minSize then result = minSize end
    return result
end

local function CreateESP(plr)
    if plr == LocalPlayer then return end
    if not plr.Character then return end
    if not IsAlive(plr) then return end
    if ESPObjects[plr] then RemoveESP(plr) end

    local char = plr.Character
    local obj = {}

    local hl = Instance.new("Highlight")
    hl.Name = "houhouHL"
    hl.FillTransparency = 1
    hl.OutlineTransparency = 1
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Adornee = char
    hl.Parent = char
    obj.highlight = hl

    if HAS_DRAWING then
        obj.box = Drawing.new("Square")
        obj.box.Thickness = 2
        obj.box.Filled = false
        obj.box.Transparency = 1
        obj.box.Color = Color3.new(1, 1, 1)
        obj.box.Visible = false

        obj.name = Drawing.new("Text")
        obj.name.Size = 16
        obj.name.Center = true
        obj.name.Outline = true
        obj.name.Color = Color3.new(1, 1, 1)
        obj.name.Visible = false

        if HAS_QUAD then
            obj.healthBar = Drawing.new("Quad")
            obj.healthBar.Filled = true
            obj.healthBar.Thickness = 0
            obj.healthBar.Transparency = 1
            obj.healthBar.Visible = false
        else
            obj.healthBar = Drawing.new("Square")
            obj.healthBar.Filled = true
            obj.healthBar.Thickness = 0
            obj.healthBar.Transparency = 1
            obj.healthBar.Visible = false
        end

        obj.distance = Drawing.new("Text")
        obj.distance.Size = 14
        obj.distance.Center = true
        obj.distance.Outline = true
        obj.distance.Color = Color3.new(1, 1, 1)
        obj.distance.Visible = false

        obj.toolTxt = Drawing.new("Text")
        obj.toolTxt.Size = 14
        obj.toolTxt.Center = true
        obj.toolTxt.Outline = true
        obj.toolTxt.Color = Color3.fromRGB(0, 255, 0)
        obj.toolTxt.Visible = false
    end

    local head = char:FindFirstChild("Head")
    if head then
        local bb = Instance.new("BillboardGui")
        bb.Name = "houhouBB"
        bb.Adornee = head
        bb.Size = UDim2.new(0, 220, 0, 64)
        bb.StudsOffset = Vector3.new(0, 2.5, 0)
        bb.AlwaysOnTop = true
        bb.LightInfluence = 0
        bb.Parent = char

        local nameLbl = Instance.new("TextLabel", bb)
        nameLbl.Name = "Name"
        nameLbl.Size = UDim2.new(1, 0, 0, 16)
        nameLbl.Position = UDim2.new(0, 0, 0, 0)
        nameLbl.BackgroundTransparency = 1
        nameLbl.TextColor3 = Color3.new(1, 1, 1)
        nameLbl.TextStrokeTransparency = 0
        nameLbl.Font = Enum.Font.GothamBold
        nameLbl.TextSize = 13
        nameLbl.Visible = false

        local distLbl = Instance.new("TextLabel", bb)
        distLbl.Name = "Dist"
        distLbl.Size = UDim2.new(1, 0, 0, 14)
        distLbl.Position = UDim2.new(0, 0, 0, 16)
        distLbl.BackgroundTransparency = 1
        distLbl.TextColor3 = Color3.fromRGB(255, 90, 90)
        distLbl.TextStrokeTransparency = 0
        distLbl.Font = Enum.Font.GothamBold
        distLbl.TextSize = 12
        distLbl.Visible = false

        local toolLbl = Instance.new("TextLabel", bb)
        toolLbl.Name = "Tool"
        toolLbl.Size = UDim2.new(1, 0, 0, 14)
        toolLbl.Position = UDim2.new(0, 0, 0, 30)
        toolLbl.BackgroundTransparency = 1
        toolLbl.TextColor3 = Color3.fromRGB(120, 255, 120)
        toolLbl.TextStrokeTransparency = 0
        toolLbl.Font = Enum.Font.Gotham
        toolLbl.TextSize = 12
        toolLbl.Visible = false

        local hpBg = Instance.new("Frame", bb)
        hpBg.Name = "HPBg"
        hpBg.Size = UDim2.new(0.7, 0, 0, 6)
        hpBg.Position = UDim2.new(0.15, 0, 0, 46)
        hpBg.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
        hpBg.BorderSizePixel = 0
        hpBg.Visible = false

        local hpFill = Instance.new("Frame", hpBg)
        hpFill.Name = "HPFill"
        hpFill.Size = UDim2.new(1, 0, 1, 0)
        hpFill.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
        hpFill.BorderSizePixel = 0

        obj.billboard = bb
        obj.nameLbl = nameLbl
        obj.distLbl = distLbl
        obj.toolLbl = toolLbl
        obj.hpBg = hpBg
        obj.hpFill = hpFill
    end

    ESPObjects[plr] = obj

    if HAS_DRAWING then
        local tracer = { lines = {} }
        local total = math.max(ARC_SEGS * ARC_STRANDS, 4)
        for i = 1, total do
            local l = Drawing.new("Line")
            l.Thickness = 1
            l.Transparency = 1
            l.Visible = false
            tracer.lines[i] = l
        end
        TracerObjects[plr] = tracer
    end
end

function RemoveESP(plr)
    local obj = ESPObjects[plr]
    if obj then
        if obj.box then pcall(function() obj.box:Remove() end) end
        if obj.name then pcall(function() obj.name:Remove() end) end
        if obj.healthBar then pcall(function() obj.healthBar:Remove() end) end
        if obj.distance then pcall(function() obj.distance:Remove() end) end
        if obj.toolTxt then pcall(function() obj.toolTxt:Remove() end) end
        if obj.highlight then pcall(function() obj.highlight:Destroy() end) end
        if obj.billboard then pcall(function() obj.billboard:Destroy() end) end
        ESPObjects[plr] = nil
    end
    local tr = TracerObjects[plr]
    if tr then
        if tr.lines then
            for _, l in ipairs(tr.lines) do pcall(function() l:Remove() end) end
        end
        TracerObjects[plr] = nil
    end
end

local function HideESP(obj)
    if not obj then return end
    if obj.box then obj.box.Visible = false end
    if obj.name then obj.name.Visible = false end
    if obj.healthBar then obj.healthBar.Visible = false end
    if obj.distance then obj.distance.Visible = false end
    if obj.toolTxt then obj.toolTxt.Visible = false end
    if obj.highlight then
        obj.highlight.FillTransparency = 1
        obj.highlight.OutlineTransparency = 1
    end
    if obj.nameLbl then obj.nameLbl.Visible = false end
    if obj.distLbl then obj.distLbl.Visible = false end
    if obj.toolLbl then obj.toolLbl.Visible = false end
    if obj.hpBg then obj.hpBg.Visible = false end
end

local function HideAllTracerLines(plr)
    local tr = TracerObjects[plr]
    if tr and tr.lines then
        for _, l in ipairs(tr.lines) do l.Visible = false end
    end
end

local function GetTracerOrigin()
    local originType = Flags.ESPTracerOrigin or "Bottom"
    if originType == "Cursor" then return GetMousePos()
    elseif originType == "Center" then return Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    else return Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y) end
end

local function DrawSpiderweb(tracer, origin, targetPos, color)
    local dir = targetPos - origin
    local len = dir.Magnitude
    if len < 1 then return end
    local n = Vector2.new(-dir.Y / len, dir.X / len)
    local spread = 8
    local strands = {
        {from = origin, to = targetPos},
        {from = origin + n * spread, to = targetPos},
        {from = origin - n * spread, to = targetPos},
    }
    for i, s in ipairs(strands) do
        local l = tracer.lines[i]
        if l then
            l.From = s.from
            l.To = s.to
            l.Color = color
            l.Thickness = 1.2
            l.Visible = true
        end
    end
end

local function DrawArc(tracer, origin, targetPos, color)
    local dir = targetPos - origin
    local dist = dir.Magnitude
    if dist < 1 then return end
    local n = Vector2.new(-dir.Y / dist, dir.X / dist)
    local mid = (origin + targetPos) / 2
    local control = mid + Vector2.new(0, dist * 0.35)
    local spread = 6
    local idx = 1
    for s = 1, ARC_STRANDS do
        local offset = (s - 2) * spread
        local offVec = n * offset
        local prev = origin + offVec
        for i = 1, ARC_SEGS do
            local t = i / ARC_SEGS
            local u = 1 - t
            local pt = Vector2.new(
                u*u*origin.X + 2*u*t*control.X + t*t*targetPos.X,
                u*u*origin.Y + 2*u*t*control.Y + t*t*targetPos.Y
            ) + offVec
            local line = tracer.lines[idx]
            if line then
                line.From = prev
                line.To = pt
                line.Color = color
                line.Thickness = 1
                line.Visible = true
            end
            prev = pt
            idx = idx + 1
            if idx > #tracer.lines then break end
        end
        if idx > #tracer.lines then break end
    end
end

local function UpdateTracers(plr, screenPos)
    local tracer = TracerObjects[plr]
    if not tracer or not tracer.lines then return end
    for _, l in ipairs(tracer.lines) do l.Visible = false end
    local tType = Flags.ESPTracerType or "Off"
    if tType == "Off" then return end
    if not IsFiniteVec2(screenPos) then return end
    local origin = GetTracerOrigin()
    local color = NormalizeColor(Flags.ESPTracerColor, Color3.new(1, 1, 1))
    if tType == "Straight" then
        local l = tracer.lines[1]
        if l then
            l.From = origin
            l.To = screenPos
            l.Color = color
            l.Thickness = 1
            l.Visible = true
        end
    elseif tType == "Spiderweb" then
        DrawSpiderweb(tracer, origin, screenPos, color)
    elseif tType == "Arc" then
        DrawArc(tracer, origin, screenPos, color)
    end
end

function ResetESP()
    if not Flags.ESPEnabled then return end
    for plr in pairs(ESPObjects) do pcall(RemoveESP, plr) end
    ESPObjects = {}
    TracerObjects = {}
    task.wait()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Character and IsAlive(plr) then
            pcall(CreateESP, plr)
        end
    end
    ESPNeedsRebuild = false
end

local function CheckESPHealth()
    if not Flags.ESPEnabled then return end
    local now = tick()
    if now - ESPLastHealthCheck < 8 then return end
    ESPLastHealthCheck = now
    for plr, obj in pairs(ESPObjects) do
        if not plr.Parent then ESPNeedsRebuild = true break end
        if not plr.Character or not IsAlive(plr) then ESPNeedsRebuild = true break end
        if obj.box then
            local ok = pcall(function()
                local _ = obj.box.Visible
                obj.box.Visible = obj.box.Visible
            end)
            if not ok then ESPNeedsRebuild = true break end
        end
    end
    if ESPNeedsRebuild then task.spawn(ResetESP) end
end

local function UpdateESP()
    if not Flags.ESPEnabled then
        if next(ESPObjects) then
            for plr in pairs(ESPObjects) do RemoveESP(plr) end
        end
        return
    end
    local snapshot = {}
    for _, plr in ipairs(Players:GetPlayers()) do table.insert(snapshot, plr) end

    for _, plr in ipairs(snapshot) do
        if plr ~= LocalPlayer then
            if not plr.Parent then
                RemoveESP(plr)
            elseif not plr.Character or not IsAlive(plr) then
                RemoveESP(plr)
            elseif Flags.ESPTeamCheck and HasTeam(plr) then
                if ESPObjects[plr] then HideESP(ESPObjects[plr]) end
                HideAllTracerLines(plr)
            else
                if not ESPObjects[plr] then pcall(CreateESP, plr) end
                local obj = ESPObjects[plr]
                if obj then
                    local char = plr.Character
                    if not char then
                        RemoveESP(plr)
                    else
                        local hrp = char:FindFirstChild("HumanoidRootPart")
                        local hum = char:FindFirstChildOfClass("Humanoid")
                        local head = char:FindFirstChild("Head")
                        if not hrp or not hum or not head then
                            RemoveESP(plr)
                        else
                            if obj.highlight and obj.highlight.Adornee ~= char then
                                obj.highlight.Adornee = char
                                obj.highlight.Parent = char
                            end
                            if obj.billboard and obj.billboard.Adornee ~= head then
                                obj.billboard.Adornee = head
                                obj.billboard.Parent = char
                            end

                            local dist = (Camera.CFrame.Position - hrp.Position).Magnitude
                            local maxDist = Flags.ESPMaxDistance or 500
                            local pos, onScreen = WorldToScreen(hrp.Position)
                            local tooFar = dist > maxDist
                            local offscreen = HAS_DRAWING and not onScreen

                            if tooFar or offscreen then
                                HideESP(obj)
                                HideAllTracerLines(plr)
                            else
                                local topPos = WorldToScreen(head.Position + Vector3.new(0, 1, 0))
                                local botPos = WorldToScreen(hrp.Position - Vector3.new(0, 3, 0))
                                local boxH = math.abs(botPos.Y - topPos.Y)
                                local boxW = boxH * 0.6
                                local boxTopY = topPos.Y
                                local hp = hum.Health
                                local maxHp = math.max(hum.MaxHealth, 1)
                                local pct = math.clamp(hp / maxHp, 0, 1)

                                if HAS_DRAWING and obj.box then
                                    if Flags.ESPBox and IsFinite(boxH) and boxH > 0 and boxH < 5000 then
                                        obj.box.Size = Vector2.new(boxW, boxH)
                                        obj.box.Position = Vector2.new(topPos.X - boxW / 2, boxTopY)
                                        obj.box.Color = Color3.fromRGB(255, 255, 255)
                                        obj.box.Visible = true
                                    else
                                        obj.box.Visible = false
                                    end
                                end

                                if obj.name then
                                    if Flags.ESPName and HAS_DRAWING then
                                        obj.name.Text = (Flags.ESPNameType == "Display") and plr.DisplayName or plr.Name
                                        obj.name.Size = GetScaledTextSize(16, 12, boxH)
                                        obj.name.Position = Vector2.new(pos.X, boxTopY - 18)
                                        obj.name.Visible = true
                                    else
                                        obj.name.Visible = false
                                    end
                                end

                                if obj.healthBar then
                                    if Flags.ESPHealth and HAS_DRAWING then
                                        local barW = math.max(2, math.floor(boxH * 0.08))
                                        local barOffset = math.max(3, math.floor(boxH * 0.08))
                                        local leftX = topPos.X - boxW / 2 - barOffset - barW
                                        local bottomY = boxTopY + boxH
                                        local topY = boxTopY + boxH * (1 - pct)
                                        if HAS_QUAD and obj.healthBar.PointA ~= nil then
                                            obj.healthBar.PointA = Vector2.new(leftX, topY)
                                            obj.healthBar.PointB = Vector2.new(leftX + barW, topY)
                                            obj.healthBar.PointC = Vector2.new(leftX + barW, bottomY)
                                            obj.healthBar.PointD = Vector2.new(leftX, bottomY)
                                        else
                                            obj.healthBar.Size = Vector2.new(barW, boxH * pct)
                                            obj.healthBar.Position = Vector2.new(leftX, topY)
                                        end
                                        obj.healthBar.Color = pct > 0.5 and Color3.fromRGB(0, 255, 0)
                                            or pct > 0.25 and Color3.fromRGB(255, 165, 0)
                                            or Color3.fromRGB(255, 0, 0)
                                        obj.healthBar.Visible = true
                                    else
                                        obj.healthBar.Visible = false
                                    end
                                end

                                if obj.distance then
                                    if Flags.ESPDistance and HAS_DRAWING then
                                        obj.distance.Text = string.format("[%d]", math.floor(dist))
                                        obj.distance.Size = GetScaledTextSize(14, 12, boxH)
                                        obj.distance.Position = Vector2.new(pos.X, boxTopY + boxH + 2)
                                        obj.distance.Visible = true
                                    else
                                        obj.distance.Visible = false
                                    end
                                end

                                if obj.toolTxt then
                                    if Flags.ESPTool and HAS_DRAWING then
                                        local tool = char:FindFirstChildOfClass("Tool")
                                        if tool then
                                            obj.toolTxt.Text = tool.Name
                                            obj.toolTxt.Size = GetScaledTextSize(14, 12, boxH)
                                            obj.toolTxt.Position = Vector2.new(pos.X, boxTopY + boxH + (Flags.ESPDistance and 18 or 2))
                                            obj.toolTxt.Visible = true
                                        else
                                            obj.toolTxt.Visible = false
                                        end
                                    else
                                        obj.toolTxt.Visible = false
                                    end
                                end

                                if obj.highlight then
                                    if Flags.ESPGlow then
                                        local c = NormalizeColor(Flags.ESPGlowColor, Color3.fromRGB(255, 255, 255))
                                        obj.highlight.FillColor = c
                                        obj.highlight.FillTransparency = 0.5
                                        obj.highlight.OutlineColor = c
                                        obj.highlight.OutlineTransparency = 0
                                    else
                                        obj.highlight.FillTransparency = 1
                                        obj.highlight.OutlineTransparency = 1
                                    end
                                end

                                if obj.billboard then
                                    obj.billboard.Enabled = true
                                    if obj.nameLbl then
                                        if Flags.ESPName then
                                            obj.nameLbl.Text = (Flags.ESPNameType == "Display") and plr.DisplayName or plr.Name
                                            obj.nameLbl.Visible = true
                                        else
                                            obj.nameLbl.Visible = false
                                        end
                                    end
                                    if obj.distLbl then
                                        if Flags.ESPDistance then
                                            obj.distLbl.Text = string.format("[%d]", math.floor(dist))
                                            obj.distLbl.Visible = true
                                        else
                                            obj.distLbl.Visible = false
                                        end
                                    end
                                    if obj.toolLbl then
                                        if Flags.ESPTool then
                                            local tool = char:FindFirstChildOfClass("Tool")
                                            if tool then
                                                obj.toolLbl.Text = tool.Name
                                                obj.toolLbl.Visible = true
                                            else
                                                obj.toolLbl.Visible = false
                                            end
                                        else
                                            obj.toolLbl.Visible = false
                                        end
                                    end
                                    if obj.hpBg then
                                        if Flags.ESPHealth then
                                            obj.hpBg.Visible = true
                                            obj.hpFill.Size = UDim2.new(pct, 0, 1, 0)
                                            obj.hpFill.BackgroundColor3 = pct > 0.5 and Color3.fromRGB(0, 255, 0)
                                                or pct > 0.25 and Color3.fromRGB(255, 165, 0)
                                                or Color3.fromRGB(255, 0, 0)
                                        else
                                            obj.hpBg.Visible = false
                                        end
                                    end
                                end

                                UpdateTracers(plr, pos)
                            end
                        end
                    end
                end
            end
        end
    end
end

local function StopSpeedLoop()
    if SpeedConn then SpeedConn:Disconnect() SpeedConn = nil end
    if SpeedBV then SpeedBV:Destroy() SpeedBV = nil end
end

local function applySpeed(on)
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    if on then
        local method = Flags.SpeedMethod or "Velocity"
        local val = Flags.SpeedValue or 16
        if method == "WalkSpeed" or method == "Hybrid" then
            hum.WalkSpeed = math.min(val, 500)
        end
        if method == "BodyVelocity" then
            local hrp = GetHRP()
            if hrp then
                if SpeedBV then SpeedBV:Destroy() end
                SpeedBV = Instance.new("BodyVelocity")
                SpeedBV.Name = "houhouSpeed"
                SpeedBV.MaxForce = Vector3.new(math.huge, 0, math.huge)
                SpeedBV.P = 1250
                SpeedBV.Velocity = Vector3.zero
                SpeedBV.Parent = hrp
            end
        end
    else
        if hum then hum.WalkSpeed = 16 end
        if SpeedBV then SpeedBV:Destroy() SpeedBV = nil end
    end
end

local function StartSpeedLoop()
    StopSpeedLoop()
    SpeedConn = RunService.RenderStepped:Connect(function(dt)
        if not Flags.SpeedEnabled then return end
        local hum = GetHum()
        local root = GetHRP()
        if not hum or not root then return end
        local speed = Flags.SpeedValue or 16
        local method = Flags.SpeedMethod or "Velocity"
        local dir = hum.MoveDirection
        if method == "Velocity" then
            if dir.Magnitude > 0 then
                root.AssemblyLinearVelocity = Vector3.new(dir.X * speed, root.AssemblyLinearVelocity.Y, dir.Z * speed)
            end
        elseif method == "WalkSpeed" then
            hum.WalkSpeed = math.min(speed, 500)
        elseif method == "Hybrid" then
            hum.WalkSpeed = math.min(speed, 500)
            if dir.Magnitude > 0 then
                root.AssemblyLinearVelocity = Vector3.new(dir.X * speed, root.AssemblyLinearVelocity.Y, dir.Z * speed)
            end
        elseif method == "CFrame" then
            if dir.Magnitude > 0 then
                root.CFrame = root.CFrame + dir.Unit * speed * dt
            end
        elseif method == "BodyVelocity" then
            if not SpeedBV or not SpeedBV.Parent then
                SpeedBV = Instance.new("BodyVelocity")
                SpeedBV.Name = "houhouSpeed"
                SpeedBV.MaxForce = Vector3.new(math.huge, 0, math.huge)
                SpeedBV.P = 1250
                SpeedBV.Parent = root
            end
            if dir.Magnitude > 0 then
                SpeedBV.Velocity = Vector3.new(dir.X * speed, 0, dir.Z * speed)
            else
                SpeedBV.Velocity = Vector3.zero
            end
        end
    end)
end

local FlyConn = nil
local flyVelocityMock = Vector3.new(0, 0.03, 0)

function StopFly()
    FlyActive = false
    if FlyConn then FlyConn:Disconnect() FlyConn = nil end
    local char = LocalPlayer.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end) end
    end
end

local function StartFly()
    if FlyConn then FlyConn:Disconnect() FlyConn = nil end
    FlyActive = true
    local char = LocalPlayer.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then pcall(function() hum:ChangeState(Enum.HumanoidStateType.Physics) end) end
    end
    FlyConn = RunService.RenderStepped:Connect(function()
        if not Flags.FlyEnabled then return end
        local char = LocalPlayer.Character
        if not char then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        local moveDir = Vector3.zero
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir = moveDir + Camera.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir = moveDir - Camera.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir = moveDir - Camera.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir = moveDir + Camera.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveDir = moveDir + Vector3.new(0, 1, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then moveDir = moveDir - Vector3.new(0, 1, 0) end
        local lookPos = hrp.Position + Camera.CFrame.LookVector
        local flatLookPos = Vector3.new(lookPos.X, hrp.Position.Y, lookPos.Z)
        local speed = Flags.FlySpeed or 5
        if moveDir.Magnitude > 0 then
            hrp.CFrame = CFrame.lookAt(hrp.Position, flatLookPos) + (moveDir.Unit * (speed / 5))
        else
            hrp.CFrame = CFrame.lookAt(hrp.Position, flatLookPos)
        end
        hrp.Velocity = flyVelocityMock
    end)
end

local function ApplyNoclip()
    if NoclipConn then NoclipConn:Disconnect() NoclipConn = nil end
    if not Flags.Noclip then return end
    NoclipConn = RunService.Stepped:Connect(function()
        local char = LocalPlayer.Character
        if char then
            for _, p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
            end
        end
    end)
end

local function ApplyAntiAFK()
    if AntiAFKConn then AntiAFKConn:Disconnect() AntiAFKConn = nil end
    if not Flags.AntiAFK then return end
    AntiAFKConn = LocalPlayer.Idled:Connect(function()
        local vu = game:GetService("VirtualUser")
        vu:CaptureController()
        vu:ClickButton2(Vector2.new())
    end)
end

local function ApplyAnchor()
    local hrp = GetHRP()
    if hrp then hrp.Anchored = Flags.Anchor end
end

local function RestoreHitboxes()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local char = plr.Character
            if char then
                local hrp = char:FindFirstChild("HumanoidRootPart")
                if hrp then
                    pcall(function()
                        hrp.Size = Vector3.new(2, 2, 1)
                        hrp.Transparency = 1
                        hrp.CanCollide = true
                    end)
                end
            end
        end
    end
end

local function ApplyHitbox()
    if HitboxConn then HitboxConn:Disconnect() HitboxConn = nil end
    if not Flags.HitboxEnabled then RestoreHitboxes() return end
    HitboxConn = RunService.Heartbeat:Connect(function()
        if not Flags.HitboxEnabled then return end
        local size = Flags.HitboxSize or 6
        local rawTrans = Flags.HitboxTransparency
        local trans
        if rawTrans == nil then trans = 0.5
        elseif rawTrans > 1 then trans = rawTrans / 100
        else trans = rawTrans end
        if trans < 0 then trans = 0 end
        if trans > 1 then trans = 1 end
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                local char = plr.Character
                if char then
                    local hrp = char:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        pcall(function()
                            hrp.Size = Vector3.new(size, size, size)
                            hrp.Transparency = trans
                            hrp.CanCollide = false
                        end)
                    end
                end
            end
        end
    end)
end

local function ApplyFullbright()
    if Flags.Fullbright then
        Lighting.Brightness = 2
        Lighting.ClockTime = 12
        Lighting.Ambient = Color3.new(1, 1, 1)
        Lighting.OutdoorAmbient = Color3.new(1, 1, 1)
    else
        Lighting.Brightness = oldLighting.Brightness
        Lighting.ClockTime = oldLighting.ClockTime
        Lighting.Ambient = oldLighting.Ambient
        Lighting.OutdoorAmbient = oldLighting.OutdoorAmbient
    end
end

local function ApplyNoFog()
    if Flags.NoFog then
        Lighting.FogEnd = 1e9
        Lighting.FogStart = 1e9
    else
        Lighting.FogEnd = oldLighting.FogEnd
        Lighting.FogStart = oldLighting.FogStart
    end
end

local function ApplyClockTime()
    if Flags.ClockTimeEnabled then
        Lighting.ClockTime = Flags.ClockTime or 12
    else
        Lighting.ClockTime = oldLighting.ClockTime
    end
end

local function ApplyAmbient()
    if Flags.AmbientEnabled then
        Lighting.Ambient = NormalizeColor(Flags.AmbientColor, Color3.new(0.5, 0.5, 0.5))
    else
        Lighting.Ambient = oldLighting.Ambient
    end
end

local function resolvePlayer(flagVal)
    if typeof(flagVal) == "Instance" and flagVal:IsA("Player") then return flagVal end
    if type(flagVal) == "string" then
        local direct = Players:FindFirstChild(flagVal)
        if direct then return direct end
        for _, p in ipairs(Players:GetPlayers()) do
            if p.Name == flagVal or p.DisplayName == flagVal then return p end
        end
    end
    return nil
end

local function GotoPlayer(plr)
    if not plr or not IsAlive(plr) then return end
    local my = GetHRP()
    local thrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
    if my and thrp then my.CFrame = thrp.CFrame + Vector3.new(0, 3, 0) end
end

local function Spectate(plr)
    if not plr or not IsAlive(plr) then return end
    Spectating = true
    local hum = plr.Character:FindFirstChildOfClass("Humanoid")
    if hum then Camera.CameraSubject = hum end
end

local function Unspectate()
    Spectating = false
    local hum = GetHum()
    if hum then Camera.CameraSubject = hum end
end

local function BuildWatermark()
    if not HAS_DRAWING then return end
    if Watermark then pcall(function() Watermark:Remove() end) end
    Watermark = Drawing.new("Text")
    Watermark.Size = 20
    Watermark.Outline = true
    Watermark.Color = Color3.new(1, 1, 1)
    Watermark.Position = Vector2.new(15, 15)
    Watermark.Visible = false
end

local function UpdateWatermark()
    if not Watermark then return end
    if not Flags.Watermark then Watermark.Visible = false return end
    Watermark.Visible = true
    local fps = 60
    pcall(function() fps = math.floor(1 / RunService.RenderStepped:Wait()) end)
    local ping = 0
    pcall(function() ping = math.floor(game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue()) end)
    Watermark.Text = string.format("houhou | %d fps | %d ms", fps, ping)
end

local function findMainRemote()
    local rs = ReplicatedStorage
    local possible = {
        rs:FindFirstChild("GameRemotes") and rs.GameRemotes:FindFirstChild("MainGameEvent"),
        rs:FindFirstChild("MainRemotes") and rs.MainRemotes:FindFirstChild("MainRemoteEvent"),
        rs:FindFirstChild("MainGameEvent", true),
        rs:FindFirstChild("MainRemoteEvent", true),
    }
    for _, rem in pairs(possible) do
        if rem and rem:IsA("RemoteEvent") then return rem end
    end
    for _, v in pairs(rs:GetDescendants()) do
        if v:IsA("RemoteEvent") then
            local n = v.Name:lower()
            if n:find("main") or n:find("game") then return v end
        end
    end
    return nil
end

local function DoAutoStomp()
    if not Flags.AutoStomp or not MainRemote then return end
    local now = tick()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local char = plr.Character
            if not char then
                AutoStompLast[plr] = nil
            else
                local isKO, isGrabbed = IsKO(plr)
                if isKO and not isGrabbed then
                    local last = AutoStompLast[plr]
                    if not last or now - last >= 0.4 then
                        AutoStompLast[plr] = now
                        pcall(function()
                            MainRemote:FireServer("Stomp")
                            MainRemote:FireServer("StompPlayer", char)
                            MainRemote:FireServer("Stomp", char)
                        end)
                    end
                else
                    AutoStompLast[plr] = nil
                end
            end
        end
    end
end

local function IsWeapon(t)
    if not t or not t:IsA("Tool") then return false end
    if not t:FindFirstChild("Handle") then return false end
    return true
end

local function ZeroCooldown(tool)
    if not tool then return end
    for _, v in ipairs(tool:GetDescendants()) do
        if v:IsA("NumberValue") or v:IsA("IntValue") then
            local n = string.lower(v.Name)
            if n:find("cool") or n:find("delay") or n:find("rate") or n:find("shoot") or n:find("debounce") then
                pcall(function() v.Value = 0 end)
            end
        end
        if v:IsA("BoolValue") then
            local n = string.lower(v.Name)
            if n:find("cool") or n:find("debounce") then
                pcall(function() v.Value = false end)
            end
        end
    end
    pcall(function()
        if tool:GetAttribute("Cooldown") ~= nil then tool:SetAttribute("Cooldown", nil) end
        if tool:GetAttribute("ShootingCooldown") ~= nil then tool:SetAttribute("ShootingCooldown", 0) end
    end)
end

local function PatchConnections(tool)
    if typeof(getconnections) ~= "function" then return end
    pcall(function()
        for _, conn in ipairs(getconnections(tool.Activated)) do
            local fn = conn.Function
            if fn and debug and debug.getupvalue and debug.setupvalue then
                local info = debug.getinfo(fn)
                local nups = (info and info.nups) or 0
                for i = 1, nups do
                    local val = debug.getupvalue(fn, i)
                    if type(val) == "number" and val > 0 and val < 1 then
                        debug.setupvalue(fn, i, 0)
                    end
                end
            end
        end
    end)
end

local function HardenTool(tool)
    if not tool or RapidFireDone[tool] then return end
    if not IsWeapon(tool) then return end
    ZeroCooldown(tool)
    PatchConnections(tool)
    RapidFireDone[tool] = true
    local conn = tool.DescendantAdded:Connect(function() ZeroCooldown(tool) end)
    table.insert(RapidFireConns, conn)
end

local function ScanRapidFireTools()
    local char = LocalPlayer.Character
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if char then
        for _, t in ipairs(char:GetChildren()) do
            if t:IsA("Tool") then HardenTool(t) end
        end
    end
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") then HardenTool(t) end
        end
    end
end

local function GetEquippedWeapon()
    local char = LocalPlayer.Character
    if not char then return nil end
    for _, t in ipairs(char:GetChildren()) do
        if t:IsA("Tool") and IsWeapon(t) then return t end
    end
    return nil
end

local function CleanupRapidFire()
    for _, c in ipairs(RapidFireConns) do pcall(function() c:Disconnect() end) end
    RapidFireConns = {}
    RapidFireDone = {}
end

local function UpdateRapidFire()
    if not Flags.RapidFire then return end
    ScanRapidFireTools()
    if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then return end
    if tick() - RapidFireLast < 0.015 then return end
    local tool = GetEquippedWeapon()
    if not tool then return end
    HardenTool(tool)
    ZeroCooldown(tool)
    RapidFireLast = tick()
    pcall(function() tool:Activate() end)
end

local function GetTargetUnderMouse()
    local target = Mouse.Target
    if not target then return nil end
    local model = target:FindFirstAncestorOfClass("Model")
    if not model then return nil end
    local plr = Players:GetPlayerFromCharacter(model)
    if not plr then return nil end
    if plr == LocalPlayer then return nil end
    if IsWhitelisted(plr) then return nil end
    if HasForceField(plr) then return nil end
    if Flags.TriggerTeamCheck and HasTeam(plr) then return nil end
    if Flags.TriggerKnockedCheck and IsKnocked(plr) then return nil end
    if not IsAlive(plr) then return nil end
    return plr, target
end

local function FireTriggerShot()
    if mouse1press and mouse1release then
        pcall(mouse1press)
        task.wait(0.01)
        pcall(mouse1release)
    elseif mouse1click then
        pcall(mouse1click)
    end
end

local function UpdateTriggerBot()
    if not Flags.TriggerEnabled then return end
    if not IsAlive(LocalPlayer) then return end
    local weapon = GetEquippedWeapon()
    if not weapon then return end
    local shouldFire = false
    local mode = Flags.TriggerMode or "Hold"
    if mode == "Always" then shouldFire = true
    elseif mode == "Hold" then shouldFire = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
    elseif mode == "OnKey" then
        local key = Flags.TriggerKey or "E"
        shouldFire = UserInputService:IsKeyDown(Enum.KeyCode[key:upper()] or Enum.KeyCode.E)
    end
    if not shouldFire then return end
    local plr = GetTargetUnderMouse()
    if not plr then return end
    local now = tick()
    local delay = (Flags.TriggerDelay or 100) / 1000
    if now - TriggerBotLast < delay then return end
    TriggerBotLast = now
    FireTriggerShot()
end

local function DestroyWhitelistGUI()
    if WL_CONN then pcall(function() WL_CONN:Disconnect() end) WL_CONN = nil end
    if WL_GUI then pcall(function() WL_GUI:Destroy() end) WL_GUI = nil end
end

local function BuildWhitelistGUI()
    DestroyWhitelistGUI()
    local parent
    pcall(function() parent = gethui() end)
    if not parent then parent = CoreGui end

    WL_GUI = Instance.new("ScreenGui")
    WL_GUI.Name = "houhou_whitelist"
    WL_GUI.ResetOnSpawn = false
    WL_GUI.IgnoreGuiInset = false
    WL_GUI.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    WL_GUI.Parent = parent

    local main = Instance.new("Frame")
    main.Size = UDim2.new(0, 320, 0, 400)
    main.Position = UDim2.new(0.5, -160, 0.5, -200)
    main.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
    main.BorderSizePixel = 0
    main.Active = true
    main.Draggable = true
    main.Parent = WL_GUI
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 8)

    local stroke = Instance.new("UIStroke", main)
    stroke.Color = Color3.fromRGB(60, 60, 80)
    stroke.Thickness = 1

    local title = Instance.new("TextLabel", main)
    title.Size = UDim2.new(1, -80, 0, 30)
    title.Position = UDim2.new(0, 10, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "Whitelist Manager"
    title.TextColor3 = Color3.fromRGB(220, 220, 240)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 14
    title.TextXAlignment = Enum.TextXAlignment.Left

    local closeBtn = Instance.new("TextButton", main)
    closeBtn.Size = UDim2.new(0, 25, 0, 25)
    closeBtn.Position = UDim2.new(1, -30, 0, 3)
    closeBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
    closeBtn.Text = "X"
    closeBtn.TextColor3 = Color3.fromRGB(220, 100, 100)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 14
    closeBtn.BorderSizePixel = 0
    closeBtn.Parent = main
    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 4)
    closeBtn.MouseButton1Click:Connect(function() DestroyWhitelistGUI() end)

    local refreshBtn = Instance.new("TextButton", main)
    refreshBtn.Size = UDim2.new(0, 25, 0, 25)
    refreshBtn.Position = UDim2.new(1, -60, 0, 3)
    refreshBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
    refreshBtn.Text = "R"
    refreshBtn.TextColor3 = Color3.fromRGB(120, 200, 255)
    refreshBtn.Font = Enum.Font.GothamBold
    refreshBtn.TextSize = 14
    refreshBtn.BorderSizePixel = 0
    refreshBtn.Parent = main
    Instance.new("UICorner", refreshBtn).CornerRadius = UDim.new(0, 4)

    local clearBtn = Instance.new("TextButton", main)
    clearBtn.Size = UDim2.new(0, 25, 0, 25)
    clearBtn.Position = UDim2.new(1, -90, 0, 3)
    clearBtn.BackgroundColor3 = Color3.fromRGB(60, 25, 25)
    clearBtn.Text = "C"
    clearBtn.TextColor3 = Color3.fromRGB(255, 120, 120)
    clearBtn.Font = Enum.Font.GothamBold
    clearBtn.TextSize = 14
    clearBtn.BorderSizePixel = 0
    clearBtn.Parent = main
    Instance.new("UICorner", clearBtn).CornerRadius = UDim.new(0, 4)
    clearBtn.MouseButton1Click:Connect(function()
        Whitelist = {}
        if Flags.RefreshWLList then Flags.RefreshWLList() end
    end)

    local scroll = Instance.new("ScrollingFrame", main)
    scroll.Size = UDim2.new(1, -20, 1, -50)
    scroll.Position = UDim2.new(0, 10, 0, 40)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 4
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.Parent = main

    local layout = Instance.new("UIListLayout", scroll)
    layout.Padding = UDim.new(0, 4)
    layout.SortOrder = Enum.SortOrder.LayoutOrder

    local function rebuild()
        for _, c in ipairs(scroll:GetChildren()) do
            if c:IsA("TextButton") then c:Destroy() end
        end
        local list = Players:GetPlayers()
        table.sort(list, function(a, b) return a.Name:lower() < b.Name:lower() end)
        for _, plr in ipairs(list) do
            if plr ~= LocalPlayer then
                local row = Instance.new("TextButton", scroll)
                row.Size = UDim2.new(1, -8, 0, 32)
                row.BackgroundColor3 = IsWhitelisted(plr) and Color3.fromRGB(30, 80, 40) or Color3.fromRGB(30, 30, 42)
                row.Text = ""
                row.BorderSizePixel = 0
                row.AutoButtonColor = false
                Instance.new("UICorner", row).CornerRadius = UDim.new(0, 5)
                local rowStroke = Instance.new("UIStroke", row)
                rowStroke.Color = IsWhitelisted(plr) and Color3.fromRGB(60, 180, 90) or Color3.fromRGB(50, 50, 70)
                rowStroke.Thickness = 1
                local name = Instance.new("TextLabel", row)
                name.Size = UDim2.new(1, -10, 1, 0)
                name.Position = UDim2.new(0, 8, 0, 0)
                name.BackgroundTransparency = 1
                name.Text = plr.DisplayName .. "  (@" .. plr.Name .. ")"
                name.TextColor3 = Color3.fromRGB(230, 230, 245)
                name.Font = Enum.Font.Gotham
                name.TextSize = 12
                name.TextXAlignment = Enum.TextXAlignment.Left
                local status = Instance.new("TextLabel", row)
                status.Size = UDim2.new(0, 60, 1, 0)
                status.Position = UDim2.new(1, -65, 0, 0)
                status.BackgroundTransparency = 1
                status.Text = IsWhitelisted(plr) and "WL ON" or "WL OFF"
                status.TextColor3 = IsWhitelisted(plr) and Color3.fromRGB(120, 255, 150) or Color3.fromRGB(160, 160, 180)
                status.Font = Enum.Font.GothamBold
                status.TextSize = 11
                status.TextXAlignment = Enum.TextXAlignment.Right
                row.MouseButton1Click:Connect(function()
                    if IsWhitelisted(plr) then
                        Whitelist[plr.UserId] = nil
                        Whitelist[plr.Name] = nil
                    else
                        Whitelist[plr.UserId] = true
                        Whitelist[plr.Name] = true
                    end
                    rebuild()
                end)
            end
        end
    end

    refreshBtn.MouseButton1Click:Connect(rebuild)
    rebuild()
    WL_CONN = Players.PlayerAdded:Connect(function() task.wait(0.5) rebuild() end)
end

Flags.RefreshWLList = function() BuildWhitelistGUI() end

local function RageIsFullyLoaded(plr)
    local c = plr and plr.Character
    if not c then return false end
    return c:FindFirstChild("Head") and c:FindFirstChild("HumanoidRootPart") and IsAlive(plr)
end

local function RageGetHead(plr)
    return plr and plr.Character and plr.Character:FindFirstChild("Head")
end

local function RageGetHRP(plr)
    return plr and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
end

local function RageFindGun()
    local c = LocalPlayer.Character
    if not c then return nil end
    for _, t in ipairs(c:GetChildren()) do
        if t:IsA("Tool") and t:FindFirstChild("Handle") then
            local n = t.Name:lower()
            if not n:find("knife") and not n:find("fist") and not n:find("bat") and not n:find("wallet") then
                return t
            end
        end
    end
    return nil
end

local function RageIsShotgun(tool)
    if not tool then return false end
    local n = tool.Name:lower()
    return n:find("shotgun") or n:find("double") or n:find("tactical") or tool:FindFirstChild("GunClientShotgun") ~= nil
end

local function RageFirstSelected()
    for plr, _ in pairs(RageTargets) do
        if plr and plr.Parent then return plr end
    end
    return nil
end

local function RageCanShoot(plr)
    if not plr or not plr.Parent or plr == LocalPlayer then return false end
    if not RageTargetReady[plr] then return false end
    if not RageIsFullyLoaded(plr) then return false end
    local knocked, grabbed = IsKO(plr)
    if knocked or grabbed then return false end
    if HasForceField(plr) then return false end
    return true
end

local function RageShootAt(head)
    if not MainRemote or not head or head.Name ~= "Head" then return false end
    local gun = RageFindGun()
    if not gun then return false end
    local handle = gun:FindFirstChild("Handle")
    if not handle then return false end
    local Ammo = gun:FindFirstChild("Ammo")
    if Ammo and Ammo.Value <= 0 then return false end
    local dmgObj = gun:FindFirstChild("Damage")
    local damage = dmgObj and dmgObj.Value
    if not damage then return false end
    local rangeObj = gun:FindFirstChild("Range")
    local range = rangeObj and rangeObj.Value or 250
    if range < 250 then range = 250 end
    local origin = handle.Position
    local pos = head.Position
    local normal = Vector3.new(0, 1, 0)
    pcall(function() MainRemote:FireServer("UpdateMousePosI2", pos) end)
    local ok = pcall(function()
        if RageIsShotgun(gun) then
            local pellets = {}
            for i = 1, 5 do
                table.insert(pellets, { AimPosition = pos, RawAimPosition = pos, Result1 = pos, Result2 = head, Result3 = normal, AimLockPart = head })
            end
            MainRemote:FireServer("ShootGun", handle, origin, pellets, nil, nil, nil, range, damage)
            MainRemote:FireServer("ShootGun", handle, origin, pellets, pos, head, normal, range, damage)
        else
            MainRemote:FireServer("ShootGun", handle, origin, nil, pos, head, normal, range, damage)
        end
    end)
    return ok
end

local function RageStartTPLock(plr)
    if RageTPQueue then return end
    if not plr or not plr.Parent then return end
    local hrp = RageGetHRP(plr)
    if not hrp then return end
    local myHRP = GetHRP()
    if not myHRP then return end
    local myPos = myHRP.Position
    local targetPos = hrp.Position
    local dir = Vector3.new(targetPos.X - myPos.X, 0, targetPos.Z - myPos.Z)
    if dir.Magnitude < 0.01 then dir = myHRP.CFrame.LookVector end
    local dirU = dir.Unit
    local finalPos = targetPos - dirU * 0.5

    RageTPQueue = {
        plr = plr,
        expires = tick() + 0.12,
        pos = finalPos,
        look = dirU,
        stomped = false,
    }
    local myHum = GetHum()
    if myHum then pcall(function() myHum:ChangeState(Enum.HumanoidStateType.Physics) end) end
end

local function RageTickTPLock()
    if not RageTPQueue then return end
    local lock = RageTPQueue
    local myHRP = GetHRP()
    if not myHRP then
        RageTPQueue = nil
        local myHum = GetHum()
        if myHum then pcall(function() myHum:ChangeState(Enum.HumanoidStateType.GettingUp) end) end
        return
    end
    if not lock.plr or not lock.plr.Parent or tick() > lock.expires then
        RageTPQueue = nil
        local myHum = GetHum()
        if myHum then pcall(function() myHum:ChangeState(Enum.HumanoidStateType.GettingUp) end) end
        return
    end
    pcall(function()
        myHRP.AssemblyLinearVelocity = Vector3.zero
        myHRP.AssemblyAngularVelocity = Vector3.zero
        myHRP.CFrame = CFrame.new(lock.pos, lock.pos + lock.look * 5)
    end)
    if not lock.stomped and MainRemote then
        lock.stomped = true
        local char = lock.plr.Character
        if char then
            pcall(function()
                MainRemote:FireServer("Stomp")
                MainRemote:FireServer("StompPlayer", char)
                MainRemote:FireServer("Stomp", char)
            end)
        end
    end
end

local function RageTryTP(plr)
    if not Flags.RageTPAuto then return end
    if RageTPQueue then return end
    local knocked = IsKO(plr)
    if not knocked then return end
    local now = tick()
    if RageTPLast[plr] and now - RageTPLast[plr] < 0.4 then return end
    RageTPLast[plr] = now
    RageStartTPLock(plr)
end

local function RageManualTP()
    local plr = RageFirstSelected()
    if not plr then return end
    local myHRP = GetHRP()
    local tHRP = RageGetHRP(plr)
    if myHRP and tHRP then
        pcall(function()
            myHRP.AssemblyLinearVelocity = Vector3.zero
            myHRP.CFrame = CFrame.new(tHRP.Position)
        end)
    end
end

local function RageTryStomp(plr)
    if not Flags.RageAutoStomp or not MainRemote then return end
    local knocked = IsKO(plr)
    if not knocked then return end
    local now = tick()
    if RageLastStomp[plr] and now - RageLastStomp[plr] < 0.6 then return end
    RageLastStomp[plr] = now
    pcall(function()
        MainRemote:FireServer("Stomp")
        MainRemote:FireServer("StompPlayer", plr.Character)
        MainRemote:FireServer("Stomp", plr.Character)
    end)
end

local function RageStompAllTick()
    if not Flags.RageStompAll or not MainRemote then return end
    local now = tick()
    if now - RageLastStompAll < 0.4 then return end
    RageLastStompAll = now
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            if IsKO(plr) then
                pcall(function()
                    MainRemote:FireServer("Stomp")
                    MainRemote:FireServer("StompPlayer", plr.Character)
                    MainRemote:FireServer("Stomp", plr.Character)
                end)
            end
        end
    end
end

local function RageSetSpectate(on)
    if RageSpectateConn then RageSpectateConn:Disconnect() RageSpectateConn = nil end
    if not on then
        local hum = GetHum()
        if hum then pcall(function() Camera.CameraSubject = hum end) end
        return
    end
    RageSpectateConn = RunService.RenderStepped:Connect(function()
        if not Flags.RageSpectate then return end
        local plr = RageFirstSelected()
        if not plr or not plr.Character then return end
        local hum = plr.Character:FindFirstChildOfClass("Humanoid")
        if hum then pcall(function() Camera.CameraSubject = hum end) end
    end)
end

local function SentryBlocked(name)
    local n = string.lower(name or "")
    for k in pairs(SENTRY_BLOCK) do
        if n:find(k, 1, true) then return true end
    end
    return false
end

local function IsSentryGun(name)
    if SentryBlocked(name) then return false end
    local n = string.lower(name or "")
    return n:find("revolver") or n:find("shotgun") or n:find("double") or n:find("tactical") or n:find("[")
end

local function SentryGunPriority(tool)
    local n = string.lower(tool.Name)
    for i, key in ipairs(GUN_ORDER) do
        if n:find(key, 1, true) then return i end
    end
    return 100
end

local function ListSentryGuns()
    local guns = {}
    local function scan(parent)
        if not parent then return end
        for _, t in ipairs(parent:GetChildren()) do
            if t:IsA("Tool") and t:FindFirstChild("Handle") and IsSentryGun(t.Name) then
                table.insert(guns, t)
            end
        end
    end
    scan(LocalPlayer.Character)
    scan(LocalPlayer:FindFirstChild("Backpack"))
    table.sort(guns, function(a, b) return SentryGunPriority(a) < SentryGunPriority(b) end)
    return guns
end

local function EquipSentryGun(tool)
    local char = LocalPlayer.Character
    if not char or not tool then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    if tool.Parent == char then return true end
    return pcall(function() hum:EquipTool(tool) end)
end

local function EquipNextSentryGun()
    local guns = ListSentryGuns()
    if #guns == 0 then return nil end
    if sentryGunIndex > #guns then sentryGunIndex = 1 end
    local tool = guns[sentryGunIndex]
    sentryGunIndex = sentryGunIndex + 1
    if sentryGunIndex > #guns then sentryGunIndex = 1 end
    EquipSentryGun(tool)
    return tool
end

local function GuessSentryAttacker()
    local myHRP = GetHRP()
    if not myHRP then return nil end
    local myPos = myHRP.Position
    local best, bestScore = nil, -math.huge
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local c = plr.Character
            if c then
                local hrp = c:FindFirstChild("HumanoidRootPart")
                local head = c:FindFirstChild("Head")
                local tool = c:FindFirstChildOfClass("Tool")
                local hum = c:FindFirstChildOfClass("Humanoid")
                if hrp and tool and hum and hum.Health > 0 then
                    local dirToMe = (myPos - hrp.Position)
                    local dist = dirToMe.Magnitude
                    if dist > 0.5 then
                        local look = head and head.CFrame.LookVector or hrp.CFrame.LookVector
                        local dot = look:Dot(dirToMe.Unit)
                        if dot > 0.5 then
                            local score = dot * 1000 - dist * 0.001
                            if score > bestScore then
                                bestScore = score
                                best = plr
                            end
                        end
                    end
                end
            end
        end
    end
    return best
end

local function ShootWithSentry(tool, head)
    if not MainRemote or not tool or not head then return end
    if head.Name ~= "Head" then return end
    if SentryBlocked(tool.Name) or not IsSentryGun(tool.Name) then return end
    local handle = tool:FindFirstChild("Handle")
    if not handle then return end
    if tool.Parent ~= LocalPlayer.Character then
        EquipSentryGun(tool)
        if tool.Parent ~= LocalPlayer.Character then return end
    end
    local Ammo = tool:FindFirstChild("Ammo")
    if Ammo and Ammo.Value <= 0 then return end
    local damage = (tool:FindFirstChild("Damage") and tool.Damage.Value) or 30
    local range = (tool:FindFirstChild("Range") and tool.Range.Value) or 250
    if range < 250 then range = 250 end
    local origin = handle.Position
    local pos = head.Position
    local normal = Vector3.new(0, 1, 0)
    pcall(function()
        if RageIsShotgun(tool) then
            local pellets = {}
            for i = 1, 5 do
                table.insert(pellets, { AimPosition = pos, RawAimPosition = pos, Result1 = pos, Result2 = head, Result3 = normal, AimLockPart = head })
            end
            MainRemote:FireServer("ShootGun", handle, origin, pellets, nil, nil, nil, range, damage)
        else
            MainRemote:FireServer("ShootGun", handle, origin, nil, pos, head, normal, range, damage)
        end
    end)
end

local function TpSentryHigh()
    local myHRP = GetHRP()
    if not myHRP then return end
    if not sentrySavedCF then sentrySavedCF = myHRP.CFrame end
    local p = myHRP.Position
    pcall(function()
        myHRP.AssemblyLinearVelocity = Vector3.zero
        myHRP.CFrame = CFrame.new(p.X, SENTRY_Y, p.Z)
    end)
    sentryVoided = true
end

local function SentryReturnHome()
    if sentryReturning then return end
    sentryReturning = true
    local myHRP = GetHRP()
    if myHRP and sentrySavedCF then
        pcall(function()
            myHRP.AssemblyLinearVelocity = Vector3.zero
            myHRP.CFrame = sentrySavedCF
        end)
    end
    sentryVoided = false
    sentryTarget = nil
    sentryCenter = nil
    task.delay(0.2, function()
        sentryReturning = false
        sentrySavedCF = nil
    end)
end

local function SentryOnDamaged()
    if not Flags.RageSentry then return end
    local atk = GuessSentryAttacker()
    if not atk then return end
    sentryTarget = atk
    sentryLockUntil = tick() + SENTRY_LOCK_TIME
    sentryGunIndex = 1
    if not sentryVoided then
        TpSentryHigh()
        task.defer(function()
            local guns = ListSentryGuns()
            if guns[1] then EquipSentryGun(guns[1]) end
        end)
    end
end

local function BindSentryHum(hum)
    if not hum then return end
    sentryLastHp = hum.Health
    AddConn(hum.HealthChanged:Connect(function(hp)
        if hp < sentryLastHp - 0.5 then SentryOnDamaged() end
        sentryLastHp = hp
    end))
end

local function SentryOnChar(char)
    task.wait(0.3)
    sentryVoided = false
    sentrySavedCF = nil
    sentryTarget = nil
    sentryCenter = nil
    local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5)
    BindSentryHum(hum)
end

if LocalPlayer.Character then SentryOnChar(LocalPlayer.Character) end
AddConn(LocalPlayer.CharacterAdded:Connect(SentryOnChar))

local function RageSyncTargets()
    local newList = {}
    for i = 1, MAX_RAGE_TARGETS do
        local v = Flags["RageTarget" .. i]
        if v then
            local plr = resolvePlayer(v)
            if plr and plr ~= LocalPlayer then newList[plr] = true end
        end
    end
    local toRemove = {}
    for plr in pairs(RageTargets) do
        if not newList[plr] then table.insert(toRemove, plr) end
    end
    for _, plr in ipairs(toRemove) do
        RageTargets[plr] = nil
        RageTargetReady[plr] = nil
        RageWaitingRespawn[plr] = nil
        RageTPLast[plr] = nil
    end
    for plr in pairs(newList) do
        if not RageTargets[plr] then
            RageTargets[plr] = true
            RageTargetReady[plr] = not HasForceField(plr)
        end
    end
end

local function PanicAll()
    Flags.AimbotEnabled = false
    Flags.SilentAimEnabled = false
    Flags.ESPEnabled = false
    Flags.SpeedEnabled = false
    Flags.FlyEnabled = false
    Flags.Noclip = false
    Flags.RapidFire = false
    Flags.AutoStomp = false
    Flags.HitboxEnabled = false
    Flags.TriggerEnabled = false
    Flags.RageAutoKill = false
    Flags.RageSentry = false
    Flags.RageTPAuto = false
    Flags.RageAutoStomp = false
    Flags.RageStompAll = false
    Flags.RageSpectate = false
    RageTargets = {}
    RageTargetReady = {}
    RageWaitingRespawn = {}
    RageTPLast = {}
    RageLastStomp = {}
    RageTPQueue = nil
    if sentryVoided then SentryReturnHome() end
    if RageSpectateConn then
        pcall(function() RageSpectateConn:Disconnect() end)
        RageSpectateConn = nil
    end
    Target = nil
    SilentCachedPart = nil
    applySpeed(false)
    StopSpeedLoop()
    StopFly()
    ApplyNoclip()
    ApplyHitbox()
    CleanupRapidFire()
    for plr in pairs(ESPObjects) do RemoveESP(plr) end
    AutoStompLast = {}
end

local Group
do
    local Window = Arvn:CreateWindow({
        Title = "houhou",
        Author = "nokoo",
        Version = "betaa",
        Folder = "houhou",
        Subtitle = "made by nokoo (rcy8 discord)",
        Theme = "Dark",
        Defaults = {},
    })
    Group = Window:Group("Main")
end

do
    local AimbotTab = Group:Tab({ Name = "Aimbot", Icon = "crosshair" })
    local AimbotSection = AimbotTab:Section({ Name = "Aimbot Settings", Side = "Left" })
    AimbotSection:Toggle({ Name = "Enabled", Flag = "AimbotEnabled", Default = false, Keybind = "V", Callback = function(v) Flags.AimbotEnabled = v end })
    AimbotSection:Segmented({ Name = "Mode", Flag = "AimbotMode", Values = {"None", "Always", "OnKey"}, Default = "None", Callback = function(v) Flags.AimbotMode = v end })
    AimbotSection:Dropdown({ Name = "Aimbot Type", Flag = "AimbotType", Values = {"Camera", "Mouse"}, Default = "Camera", Callback = function(v) Flags.AimbotType = v end })
    AimbotSection:Dropdown({ Name = "Hit Part", Flag = "AimbotHitPart", Values = {"Head", "HumanoidRootPart", "Closest"}, Default = "Head", Callback = function(v) Flags.AimbotHitPart = v end })
    AimbotSection:Dropdown({ Name = "Target Method", Flag = "AimbotMethod", Values = {"Closest to Mouse", "Closest Distance", "FOV"}, Default = "Closest to Mouse", Callback = function(v) Flags.AimbotMethod = v end })
    AimbotSection:Toggle({ Name = "Sticky Aim", Flag = "AimbotStickyAim", Default = false, Callback = function(v) Flags.AimbotStickyAim = v end })
    AimbotSection:Toggle({ Name = "Unlock on Death", Flag = "AimbotUnlockOnDeath", Default = true, Callback = function(v) Flags.AimbotUnlockOnDeath = v end })
    AimbotSection:Toggle({ Name = "Prediction", Flag = "AimbotPrediction", Default = false, Callback = function(v) Flags.AimbotPrediction = v end })
    AimbotSection:Slider({ Name = "Prediction Value", Flag = "AimbotPredictionValue", Min = 0, Max = 100, Default = 16, Callback = function(v) Flags.AimbotPredictionValue = v / 100 end })

    local FOVSection = AimbotTab:Section({ Name = "FOV Settings", Side = "Right" })
    FOVSection:Toggle({ Name = "Show FOV", Flag = "AimbotShowFOV", Default = true, Callback = function(v) Flags.AimbotShowFOV = v end })
    FOVSection:Slider({ Name = "FOV Radius", Flag = "AimbotFOV", Min = 10, Max = 500, Default = 120, Callback = function(v) Flags.AimbotFOV = v end })
    FOVSection:ColorPicker({ Name = "FOV Color", Flag = "AimbotFOVColor", Default = Color3.new(1, 1, 1), Callback = function(v) Flags.AimbotFOVColor = NormalizeColor(v, Color3.new(1, 1, 1)) end })
    FOVSection:Toggle({ Name = "Use FOV", Flag = "AimbotUseFOV", Default = true, Callback = function(v) Flags.AimbotUseFOV = v end })

    local SmoothSection = AimbotTab:Section("Aimbot Smoothing")
    SmoothSection:Toggle({ Name = "Enable Smoothing", Flag = "AimbotSmoothing", Default = true, Callback = function(v) Flags.AimbotSmoothing = v end })
    SmoothSection:Slider({ Name = "Smoothness", Flag = "AimbotSmoothness", Min = 1, Max = 30, Default = 15, Callback = function(v) Flags.AimbotSmoothness = v end })
    SmoothSection:Toggle({ Name = "Independent Axes", Flag = "AimbotIndependentAxes", Default = false, Callback = function(v) Flags.AimbotIndependentAxes = v end })
    SmoothSection:Slider({ Name = "Smooth X", Flag = "AimbotSmoothX", Min = 1, Max = 30, Default = 15, Callback = function(v) Flags.AimbotSmoothX = v end })
    SmoothSection:Slider({ Name = "Smooth Y", Flag = "AimbotSmoothY", Min = 1, Max = 30, Default = 15, Callback = function(v) Flags.AimbotSmoothY = v end })

    local CheckSection = AimbotTab:Section("Checks")
    CheckSection:Toggle({ Name = "Knocked Check", Flag = "AimbotKnockedCheck", Default = true, Callback = function(v) Flags.AimbotKnockedCheck = v end })
    CheckSection:Toggle({ Name = "Dead Check", Flag = "AimbotDeadCheck", Default = true, Callback = function(v) Flags.AimbotDeadCheck = v end })
    CheckSection:Toggle({ Name = "Wall Check", Flag = "AimbotWallCheck", Default = false, Callback = function(v) Flags.AimbotWallCheck = v end })
    CheckSection:Toggle({ Name = "Team Check", Flag = "AimbotTeamCheck", Default = true, Callback = function(v) Flags.AimbotTeamCheck = v end })
    CheckSection:Toggle({ Name = "Health Check", Flag = "AimbotHealthCheck", Default = false, Callback = function(v) Flags.AimbotHealthCheck = v end })
    CheckSection:Slider({ Name = "Min Health", Flag = "AimbotMinHealth", Min = 0, Max = 200, Default = 0, Callback = function(v) Flags.AimbotMinHealth = v end })
end

do
    local SilentTab = Group:Tab({ Name = "Silent Aim", Icon = "focus" })
    local SilentSection = SilentTab:Section("Silent Aim Settings")
    SilentSection:Toggle({ Name = "Enabled", Flag = "SilentAimEnabled", Default = false, Keybind = "P", Callback = function(v) Flags.SilentAimEnabled = v end })
    SilentSection:Dropdown({ Name = "Hit Part", Flag = "SilentAimHitPart", Values = {"Head", "HumanoidRootPart", "Closest"}, Default = "Head", Callback = function(v) Flags.SilentAimHitPart = v end })
    SilentSection:Slider({ Name = "FOV Radius", Flag = "SilentAimFOV", Min = 10, Max = 800, Default = 150, Callback = function(v) Flags.SilentAimFOV = v end })
    SilentSection:Toggle({ Name = "Show FOV Circle", Flag = "SilentAimShowFOV", Default = true, Callback = function(v) Flags.SilentAimShowFOV = v end })
    SilentSection:ColorPicker({ Name = "FOV Color", Flag = "SilentAimFOVColor", Default = Color3.fromRGB(120, 180, 255), Callback = function(v) Flags.SilentAimFOVColor = NormalizeColor(v, Color3.fromRGB(120, 180, 255)) end })
    SilentSection:Toggle({ Name = "Knocked Check", Flag = "SilentAimKnockedCheck", Default = true, Callback = function(v) Flags.SilentAimKnockedCheck = v end })
    SilentSection:Toggle({ Name = "Wall Check", Flag = "SilentAimWallCheck", Default = false, Callback = function(v) Flags.SilentAimWallCheck = v end })
    SilentSection:Toggle({ Name = "Team Check", Flag = "SilentAimTeamCheck", Default = true, Callback = function(v) Flags.SilentAimTeamCheck = v end })
end

do
    local TriggerTab = Group:Tab({ Name = "Trigger Bot", Icon = "zap" })
    local TriggerMainSection = TriggerTab:Section({ Name = "Trigger Bot", Side = "Left" })
    TriggerMainSection:Toggle({ Name = "Enabled", Flag = "TriggerEnabled", Default = false, Keybind = "E", Callback = function(v) Flags.TriggerEnabled = v end })
    TriggerMainSection:Segmented({ Name = "Trigger Mode", Flag = "TriggerMode", Values = {"Hold", "Always", "OnKey"}, Default = "Hold", Callback = function(v) Flags.TriggerMode = v end })
    TriggerMainSection:Slider({ Name = "Delay (ms)", Flag = "TriggerDelay", Min = 0, Max = 1000, Default = 100, Callback = function(v) Flags.TriggerDelay = v end })

    local TriggerCheckSection = TriggerTab:Section({ Name = "Checks", Side = "Right" })
    TriggerCheckSection:Toggle({ Name = "Team Check", Flag = "TriggerTeamCheck", Default = true, Callback = function(v) Flags.TriggerTeamCheck = v end })
    TriggerCheckSection:Toggle({ Name = "Knocked Check", Flag = "TriggerKnockedCheck", Default = true, Callback = function(v) Flags.TriggerKnockedCheck = v end })

    local WhitelistSection = TriggerTab:Section({ Name = "Whitelist", Side = "Right" })
    WhitelistSection:Button({ Name = "Open Whitelist Manager", Callback = function() task.defer(BuildWhitelistGUI) end })
    WhitelistSection:Button({
        Name = "List Whitelist",
        Callback = function()
            task.defer(function()
                local count = 0
                local names = {}
                for k, _ in pairs(Whitelist) do
                    count = count + 1
                    table.insert(names, tostring(k))
                end
                if count == 0 then
                    Arvn:Notify({ Title = "Whitelist", Content = "List is empty", Kind = "Info" })
                else
                    Arvn:Notify({ Title = "Whitelist (" .. count .. ")", Content = table.concat(names, ", "), Time = 6, Kind = "Info" })
                end
            end)
        end,
    })
    WhitelistSection:Button({
        Name = "Clear Whitelist",
        Callback = function()
            Whitelist = {}
            Arvn:Notify({ Title = "Whitelist", Content = "Cleared", Kind = "Warning" })
        end,
    })
end

do
    local RageTab = Group:Tab({ Name = "Rage", Icon = "crosshair" })
    local RageTargetsSec = RageTab:Section({ Name = "Targets", Side = "Left" })
    RageTargetsSec:Dropdown({ Name = "Target 1", Flag = "RageTarget1", Special = "Players", Callback = function(v) Flags.RageTarget1 = v end })
    RageTargetsSec:Dropdown({ Name = "Target 2", Flag = "RageTarget2", Special = "Players", Callback = function(v) Flags.RageTarget2 = v end })
    RageTargetsSec:Dropdown({ Name = "Target 3", Flag = "RageTarget3", Special = "Players", Callback = function(v) Flags.RageTarget3 = v end })
    RageTargetsSec:Button({
        Name = "Clear Targets",
        Callback = function()
            Flags.RageTarget1 = nil
            Flags.RageTarget2 = nil
            Flags.RageTarget3 = nil
            RageTargets = {}
            RageTargetReady = {}
            RageWaitingRespawn = {}
            RageTPQueue = nil
            Arvn:Notify({ Title = "Rage", Content = "Targets cleared", Kind = "Info" })
        end,
    })
    RageTargetsSec:Button({ Name = "TP Manual -> Target", Callback = function() task.defer(RageManualTP) end })

    local RageCombatSec = RageTab:Section({ Name = "Combat", Side = "Right" })
    RageCombatSec:Toggle({ Name = "Auto Kill", Flag = "RageAutoKill", Default = false, Keybind = "V", Callback = function(v) Flags.RageAutoKill = v end })
    RageCombatSec:Toggle({ Name = "Wait ForceField", Flag = "RageWaitFF", Default = true, Callback = function(v) Flags.RageWaitFF = v end })
    RageCombatSec:Toggle({ Name = "TP Auto KO", Flag = "RageTPAuto", Default = false, Callback = function(v) Flags.RageTPAuto = v end })
    RageCombatSec:Toggle({ Name = "Stomp Target", Flag = "RageAutoStomp", Default = false, Callback = function(v) Flags.RageAutoStomp = v end })
    RageCombatSec:Toggle({ Name = "Stomp All Knocked", Flag = "RageStompAll", Default = false, Callback = function(v) Flags.RageStompAll = v end })
    RageCombatSec:Toggle({ Name = "Spectate Target", Flag = "RageSpectate", Default = false, Callback = function(v) RageSetSpectate(v) end })

    local RageSentrySec = RageTab:Section({ Name = "Sentry", Side = "Left" })
    RageSentrySec:Toggle({
        Name = "Sentry Enabled",
        Flag = "RageSentry",
        Default = false,
        Callback = function(v)
            if not v and sentryVoided then SentryReturnHome() end
            if not v then
                sentryTarget = nil
                sentryCenter = nil
            end
        end,
    })

    local RageMiscSec = RageTab:Section({ Name = "Misc", Side = "Right" })
    RageMiscSec:Button({
        Name = "Sentry Return Home",
        Callback = function()
            if sentryVoided then SentryReturnHome() end
        end,
    })
end

do
    local ScriptsTab = Group:Tab({ Name = "Scripts", Icon = "file-code" })
    local ScriptsSection = ScriptsTab:Section({ Name = "Available Scripts", Side = "Left" })
    ScriptsSection:Button({
        Name = "Run Infinite Yield",
        Callback = function()
            task.spawn(function()
                local ok, err = pcall(function()
                    loadstring(game:HttpGet("https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source"))()
                end)
                if ok then
                    Arvn:Notify({ Title = "Scripts", Content = "Infinite Yield loaded", Kind = "Success" })
                else
                    Arvn:Notify({ Title = "Scripts", Content = "Failed: " .. tostring(err), Kind = "Error" })
                end
            end)
        end,
    })
end

do
    local VisualTab = Group:Tab({ Name = "Visuals / ESP", Icon = "eye" })
    local PlayersSection = VisualTab:Section({ Name = "Players", Side = "Left" })
    PlayersSection:Toggle({
        Name = "Master Enable",
        Flag = "ESPEnabled",
        Default = false,
        Keybind = "RightControl",
        Callback = function(v)
            Flags.ESPEnabled = v
            if not v then
                for plr in pairs(ESPObjects) do RemoveESP(plr) end
            else
                task.spawn(function()
                    task.wait(0.1)
                    ResetESP()
                end)
            end
        end,
    })
    PlayersSection:Toggle({ Name = "Box ESP", Flag = "ESPBox", Default = false, Callback = function(v) Flags.ESPBox = v end })
    PlayersSection:Toggle({ Name = "Name ESP", Flag = "ESPName", Default = false, Callback = function(v) Flags.ESPName = v end })
    PlayersSection:Dropdown({ Name = "Name Type", Flag = "ESPNameType", Values = {"Normal", "Display"}, Default = "Normal", Callback = function(v) Flags.ESPNameType = v end })
    PlayersSection:Toggle({ Name = "Health Bar", Flag = "ESPHealth", Default = false, Callback = function(v) Flags.ESPHealth = v end })
    PlayersSection:Toggle({ Name = "Distance", Flag = "ESPDistance", Default = false, Callback = function(v) Flags.ESPDistance = v end })
    PlayersSection:Toggle({ Name = "Tool Equip", Flag = "ESPTool", Default = false, Callback = function(v) Flags.ESPTool = v end })
    PlayersSection:Toggle({ Name = "Glow", Flag = "ESPGlow", Default = false, Callback = function(v) Flags.ESPGlow = v end })
    PlayersSection:ColorPicker({ Name = "Glow Color", Flag = "ESPGlowColor", Default = Color3.fromRGB(255, 255, 255), Callback = function(v) Flags.ESPGlowColor = NormalizeColor(v, Color3.fromRGB(255, 255, 255)) end })
    PlayersSection:Slider({ Name = "Max Distance", Flag = "ESPMaxDistance", Min = 10, Max = 5000, Default = 500, Callback = function(v) Flags.ESPMaxDistance = v end })
    PlayersSection:Toggle({ Name = "Team Check", Flag = "ESPTeamCheck", Default = true, Callback = function(v) Flags.ESPTeamCheck = v end })
    PlayersSection:Button({ Name = "Reset ESP", Callback = function() task.defer(ResetESP) end })

    local TracerSection = VisualTab:Section({ Name = "Tracers", Side = "Right" })
    TracerSection:Dropdown({ Name = "Type", Flag = "ESPTracerType", Values = {"Off", "Straight", "Spiderweb", "Arc"}, Default = "Off", Callback = function(v) Flags.ESPTracerType = v end })
    TracerSection:Dropdown({ Name = "Origin", Flag = "ESPTracerOrigin", Values = {"Cursor", "Bottom", "Center"}, Default = "Bottom", Callback = function(v) Flags.ESPTracerOrigin = v end })
    TracerSection:ColorPicker({ Name = "Color", Flag = "ESPTracerColor", Default = Color3.fromRGB(255, 255, 255), Callback = function(v) Flags.ESPTracerColor = NormalizeColor(v, Color3.fromRGB(255, 255, 255)) end })
    TracerSection:Toggle({ Name = "Tracers Glow", Flag = "ESPTracersGlow", Default = false, Callback = function(v) Flags.ESPTracersGlow = v end })
end

do
    local MoveTab = Group:Tab({ Name = "Movement", Icon = "person-standing" })
    local SpeedSection = MoveTab:Section("Speed")
    SpeedSection:Toggle({
        Name = "Speed Enabled",
        Flag = "SpeedEnabled",
        Default = false,
        Callback = function(v)
            Flags.SpeedEnabled = v
            if v then
                applySpeed(true)
                StartSpeedLoop()
            else
                applySpeed(false)
                StopSpeedLoop()
            end
        end,
    })
    SpeedSection:Dropdown({ Name = "Speed Method", Flag = "SpeedMethod", Values = {"Velocity", "WalkSpeed", "Hybrid", "CFrame", "BodyVelocity"}, Default = "Velocity", Callback = function(v)
        Flags.SpeedMethod = v
        if Flags.SpeedEnabled then
            applySpeed(false)
            applySpeed(true)
        end
    end })
    SpeedSection:Slider({ Name = "Speed Value", Flag = "SpeedValue", Min = 0, Max = 5000, Default = 16, Callback = function(v) Flags.SpeedValue = v end })

    local FlySection = MoveTab:Section("Fly")
    FlySection:Toggle({
        Name = "Fly (Safe)",
        Flag = "FlyEnabled",
        Default = false,
        Keybind = { Key = "LeftAlt", Mode = "Hold" },
        Callback = function(v)
            Flags.FlyEnabled = v
            if v then StartFly() else StopFly() end
        end,
    })
    FlySection:Slider({ Name = "Fly Speed", Flag = "FlySpeed", Min = 1, Max = 50, Default = 5, Callback = function(v) Flags.FlySpeed = v end })

    local MiscMoveSection = MoveTab:Section("Misc Movement")
    MiscMoveSection:Toggle({ Name = "Noclip", Flag = "Noclip", Default = false, Callback = function(v) Flags.Noclip = v ApplyNoclip() end })
    MiscMoveSection:Toggle({ Name = "Anchor", Flag = "Anchor", Default = false, Callback = function(v) Flags.Anchor = v ApplyAnchor() end })
end

do
    local WorldTab = Group:Tab({ Name = "World", Icon = "globe" })
    local WorldSection = WorldTab:Section("World Settings")
    WorldSection:Toggle({ Name = "Fullbright", Flag = "Fullbright", Default = false, Callback = function(v) Flags.Fullbright = v ApplyFullbright() end })
    WorldSection:Toggle({ Name = "No Fog", Flag = "NoFog", Default = false, Callback = function(v) Flags.NoFog = v ApplyNoFog() end })
    WorldSection:Toggle({ Name = "Clock Time Enabled", Flag = "ClockTimeEnabled", Default = false, Callback = function(v) Flags.ClockTimeEnabled = v ApplyClockTime() end })
    WorldSection:Slider({ Name = "Clock Time", Flag = "ClockTime", Min = 0, Max = 24, Default = 12, Callback = function(v) Flags.ClockTime = v ApplyClockTime() end })
    WorldSection:Toggle({ Name = "Ambient Enabled", Flag = "AmbientEnabled", Default = false, Callback = function(v) Flags.AmbientEnabled = v ApplyAmbient() end })
    WorldSection:ColorPicker({ Name = "Ambient Color", Flag = "AmbientColor", Default = Color3.new(0.5, 0.5, 0.5), Callback = function(v)
        Flags.AmbientColor = NormalizeColor(v, Color3.new(0.5, 0.5, 0.5))
        ApplyAmbient()
    end })
end

do
    local PlayersTab = Group:Tab({ Name = "Players", Icon = "users" })
    local PlayersListSection = PlayersTab:Section("Player List")
    PlayersListSection:PlayerList({
        Name = "Players",
        Flag = "PlayerListSelected",
        Callback = function(plr) Flags.SelectedPlayer = plr end,
    })

    local TargetSection = PlayersTab:Section("Target")
    TargetSection:Dropdown({ Name = "Select Player", Flag = "TargetPlayer", Special = "Players", Callback = function(v) Flags.TargetPlayer = v end })
    TargetSection:Button({
        Name = "Goto",
        Callback = function()
            task.defer(function()
                local plr = resolvePlayer(Arvn.Flags.TargetPlayer)
                if plr then GotoPlayer(plr) end
            end)
        end,
    })
    TargetSection:Button({
        Name = "Spectate",
        Callback = function()
            task.defer(function()
                local plr = resolvePlayer(Arvn.Flags.TargetPlayer)
                if plr then Spectate(plr) end
            end)
        end,
    })
    TargetSection:Button({ Name = "Unspectate", Callback = function() Unspectate() end })
    TargetSection:Button({
        Name = "Copy UserId",
        Callback = function()
            local plr = resolvePlayer(Arvn.Flags.TargetPlayer)
            if plr then
                local fn = setclipboard or toclipboard
                if fn then SafeCall(fn, tostring(plr.UserId)) end
            end
        end,
    })
    TargetSection:Button({
        Name = "Copy Username",
        Callback = function()
            local plr = resolvePlayer(Arvn.Flags.TargetPlayer)
            if plr then
                local fn = setclipboard or toclipboard
                if fn then SafeCall(fn, plr.Name) end
            end
        end,
    })
end

do
    local MiscTab = Group:Tab({ Name = "Misc", Icon = "wrench" })
    local MiscSection = MiscTab:Section("Miscellaneous")
    MiscSection:Toggle({ Name = "Anti AFK", Flag = "AntiAFK", Default = false, Callback = function(v) Flags.AntiAFK = v ApplyAntiAFK() end })
    MiscSection:Toggle({ Name = "Anti Stomp", Flag = "AntiStomp", Default = true, Callback = function(v) Flags.AntiStomp = v end })
    MiscSection:Toggle({ Name = "Watermark", Flag = "Watermark", Default = true, Callback = function(v) Flags.Watermark = v end })
    MiscSection:Toggle({ Name = "Auto Stomp", Flag = "AutoStomp", Default = false, Callback = function(v)
        Flags.AutoStomp = v
        if v then
            if not MainRemote then MainRemote = findMainRemote() end
        else
            AutoStompLast = {}
        end
    end })
    MiscSection:Toggle({ Name = "Rapid Fire", Flag = "RapidFire", Default = false, Callback = function(v)
        Flags.RapidFire = v
        if not v then CleanupRapidFire() else ScanRapidFireTools() end
    end })

    local HitboxSection = MiscTab:Section("Hitbox Expander")
    HitboxSection:Toggle({ Name = "Hitbox Expander", Flag = "HitboxEnabled", Default = false, Callback = function(v)
        Flags.HitboxEnabled = v
        ApplyHitbox()
    end })
    HitboxSection:Slider({ Name = "Hitbox Size", Flag = "HitboxSize", Min = 5, Max = 25, Default = 6, Callback = function(v) Flags.HitboxSize = v end })
    HitboxSection:Slider({ Name = "Transparency", Flag = "HitboxTransparency", Min = 0, Max = 100, Default = 50, Callback = function(v) Flags.HitboxTransparency = v end })

    MiscSection:Button({
        Name = "Respawn",
        Callback = function()
            SafeCall(function()
                local hum = GetHum()
                if hum then hum.Health = 0 end
            end)
        end,
    })
    MiscSection:Button({
        Name = "Rejoin",
        Callback = function()
            SafeCall(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
        end,
    })
    MiscSection:Button({
        Name = "Server Hop",
        Callback = function()
            task.spawn(function()
                local ok = SafeCall(function()
                    local raw = game:HttpGet("https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100")
                    local servers = HttpService:JSONDecode(raw)
                    if servers and servers.data and #servers.data > 0 then
                        TeleportService:TeleportToPlaceInstance(game.PlaceId, servers.data[1].id, LocalPlayer)
                    end
                end)
                if not ok then
                    Arvn:Notify({ Title = "houhou", Content = "Server hop unavailable", Kind = "Warning" })
                end
            end)
        end,
    })
    MiscSection:Button({
        Name = "Copy Job ID",
        Callback = function()
            local fn = setclipboard or toclipboard
            if fn then SafeCall(fn, game.JobId) end
        end,
    })
    MiscSection:Button({
        Name = "Copy Place ID",
        Callback = function()
            local fn = setclipboard or toclipboard
            if fn then SafeCall(fn, tostring(game.PlaceId)) end
        end,
    })
    MiscSection:Button({ Name = "Panic", Callback = function() task.defer(PanicAll) end })
end

do
    local SettingsTab = Group:Tab({ Name = "Settings", Icon = "settings" })
    local SettingsSection = SettingsTab:Section("Settings")
    SettingsSection:Button({
        Name = "Fix UI Quality",
        Callback = function()
            pcall(function()
                if WL_GUI then
                    WL_GUI.ResetOnSpawn = false
                    WL_GUI.IgnoreGuiInset = false
                end
            end)
            Arvn:Notify({ Title = "houhou", Content = "UI fix applied", Kind = "Success" })
        end,
    })
    SettingsSection:Button({
        Name = "Unload houhou",
        Callback = function()
            task.defer(function()
                PanicAll()
                DestroyWhitelistGUI()
                for _, c in ipairs(Connections) do pcall(function() c:Disconnect() end) end
                Connections = {}
                StopFly()
                StopSpeedLoop()
                if FOVCircle then pcall(function() FOVCircle:Remove() end) FOVCircle = nil end
                if SilentFOVCircle then pcall(function() SilentFOVCircle:Remove() end) SilentFOVCircle = nil end
                if Watermark then pcall(function() Watermark:Remove() end) Watermark = nil end
                for plr in pairs(ESPObjects) do RemoveESP(plr) end
                Lighting.Brightness = oldLighting.Brightness
                Lighting.ClockTime = oldLighting.ClockTime
                Lighting.Ambient = oldLighting.Ambient
                Lighting.OutdoorAmbient = oldLighting.OutdoorAmbient
                Lighting.FogEnd = oldLighting.FogEnd
                Lighting.FogStart = oldLighting.FogStart
                local hum = GetHum()
                if hum then hum.WalkSpeed = 16 end
                local hrp = GetHRP()
                if hrp then hrp.Anchored = false end
                Unspectate()
                if sentryVoided and sentrySavedCF then
                    local myHRP = GetHRP()
                    if myHRP then
                        pcall(function()
                            myHRP.AssemblyLinearVelocity = Vector3.zero
                            myHRP.CFrame = sentrySavedCF
                        end)
                    end
                end
                if RageSpectateConn then
                    pcall(function() RageSpectateConn:Disconnect() end)
                    RageSpectateConn = nil
                end
                if Arvn.Unload then pcall(function() Arvn:Unload() end) end
            end)
        end,
    })
end

AddConn(RunService.Heartbeat:Connect(function()
    pcall(ApplyAimbot)
    pcall(UpdateFOVCircle)
    pcall(UpdateSilentFOVCircle)
    pcall(UpdateESP)
    pcall(CheckESPHealth)
    pcall(UpdateRapidFire)
    pcall(UpdateTriggerBot)
    pcall(SilentScan)
    pcall(DoAutoStomp)

    RageSyncTargets()
    RageTickTPLock()

    do
        local toRemove = {}
        for plr, _ in pairs(RageTargets) do
            if not plr or not plr.Parent then
                table.insert(toRemove, plr)
            elseif not IsAlive(plr) or not RageIsFullyLoaded(plr) then
                RageWaitingRespawn[plr] = true
                RageTargetReady[plr] = false
            elseif HasForceField(plr) then
                RageWaitingRespawn[plr] = true
                RageTargetReady[plr] = false
            else
                if RageWaitingRespawn[plr] then
                    RageWaitingRespawn[plr] = false
                    RageTargetReady[plr] = false
                    local captured = plr
                    task.delay(FF_CLEAR_DELAY, function()
                        if RageTargets[captured]
                            and captured.Parent
                            and RageIsFullyLoaded(captured)
                            and IsAlive(captured)
                            and not HasForceField(captured)
                        then
                            RageTargetReady[captured] = true
                        end
                    end)
                elseif RageTargetReady[plr] == nil then
                    RageTargetReady[plr] = true
                end
            end
        end
        for _, plr in ipairs(toRemove) do
            RageTargets[plr] = nil
            RageTargetReady[plr] = nil
            RageWaitingRespawn[plr] = nil
        end
    end

    if Flags.RageAutoKill and tick() - RageLastFire >= RAGE_FIRE_RATE then
        local shot = false
        for plr, _ in pairs(RageTargets) do
            if plr and plr.Parent and plr ~= LocalPlayer then
                if RageCanShoot(plr) then
                    local head = RageGetHead(plr)
                    if head and RageShootAt(head) then shot = true end
                end
            end
        end
        if shot then RageLastFire = tick() end
    end

    for plr, _ in pairs(RageTargets) do
        if plr and plr.Parent and plr ~= LocalPlayer then
            if IsKO(plr) then
                RageTryTP(plr)
                RageTryStomp(plr)
            end
        end
    end

    RageStompAllTick()

    if Flags.RageSentry and sentryTarget then
        if not IsAlive(sentryTarget) or IsKO(sentryTarget) or tick() > sentryLockUntil then
            if sentryVoided then SentryReturnHome() else sentryTarget = nil end
        else
            if not HasForceField(sentryTarget) then
                local myHRP = GetHRP()
                if myHRP and sentryVoided then
                    if not sentryCenter then
                        sentryCenter = myHRP.Position
                        sentryNextChange = tick() + (0.25 + math.random() * 0.6)
                    end
                    if tick() >= sentryNextChange then
                        sentryAngle = sentryAngle + (math.random() * 2 - 1) * 2.2
                        sentryNextChange = tick() + (0.15 + math.random() * 0.5)
                    end
                    local speed = 4 + math.random() * 5
                    sentryAngle = sentryAngle + speed * (1 / 60)
                    local x = sentryCenter.X + math.cos(sentryAngle) * SENTRY_RADIUS
                    local z = sentryCenter.Z + math.sin(sentryAngle) * SENTRY_RADIUS
                    local y = SENTRY_Y + math.sin(sentryAngle * 0.9) * 30
                    pcall(function()
                        myHRP.AssemblyLinearVelocity = Vector3.zero
                        myHRP.CFrame = CFrame.new(x, y, z)
                    end)
                end
                if tick() - sentryLastFire >= SENTRY_FIRE_RATE then
                    sentryLastFire = tick()
                    local head = RageGetHead(sentryTarget)
                    if head then
                        local tool = EquipNextSentryGun()
                        if tool then ShootWithSentry(tool, head) end
                    end
                end
            end
        end
    end

    if Flags.AntiStomp and IsKnocked(LocalPlayer) then
        local now = tick()
        if now - AntiStompDebounce > 1.5 then
            AntiStompDebounce = now
            SafeCall(function()
                local hum = GetHum()
                if hum then hum.Health = 0 end
            end)
        end
    end
end))

task.spawn(function()
    BuildWatermark()
    while Watermark do
        local ok = pcall(UpdateWatermark)
        if not ok then break end
        task.wait(0.5)
    end
end)

AddConn(UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        PanicAll()
    end
end))

BuildFOVCircle()
BuildSilentFOVCircle()
InstallSilentHooks()
ApplyFullbright()
ApplyNoFog()
ApplyClockTime()
ApplyAmbient()
ApplyNoclip()
ApplyAntiAFK()

MainRemote = findMainRemote()

local function hookPlayerChar(plr)
    if plr == LocalPlayer then return end
    AddConn(plr.CharacterAdded:Connect(function()
        RemoveESP(plr)
        task.wait(0.4)
        if Flags.ESPEnabled then pcall(CreateESP, plr) end
    end))
end

for _, plr in ipairs(Players:GetPlayers()) do
    hookPlayerChar(plr)
end

AddConn(Players.PlayerAdded:Connect(function(plr) hookPlayerChar(plr) end))

AddConn(Players.PlayerRemoving:Connect(function(plr)
    RemoveESP(plr)
    TracerObjects[plr] = nil
    AutoStompLast[plr] = nil
    RageTargets[plr] = nil
    RageTargetReady[plr] = nil
    RageWaitingRespawn[plr] = nil
    RageTPLast[plr] = nil
    RageLastStomp[plr] = nil
end))

AddConn(LocalPlayer.CharacterAdded:Connect(function()
    Target = nil
    SilentCachedPart = nil
    RageTPQueue = nil
    task.wait(0.4)
    if Flags.SpeedEnabled then
        applySpeed(true)
        StartSpeedLoop()
    end
    if Flags.FlyEnabled then StartFly() end
    if Flags.Anchor then ApplyAnchor() end
    if Flags.RapidFire then ScanRapidFireTools() end
    if Flags.HitboxEnabled then ApplyHitbox() end
    if Flags.ESPEnabled then
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                if ESPObjects[plr] then RemoveESP(plr) end
                pcall(CreateESP, plr)
            end
        end
    end
end))

if LocalPlayer.Character then
    task.spawn(function()
        task.wait(0.5)
        if Flags.RapidFire then ScanRapidFireTools() end
    end)
end

AddConn(LocalPlayer.ChildAdded:Connect(function(c)
    if c.Name == "Backpack" then
        AddConn(c.ChildAdded:Connect(function(t)
            if t:IsA("Tool") and Flags.RapidFire then HardenTool(t) end
        end))
    end
end))

Arvn:Notify({ Title = "houhou", Content = "(rcy8 discord)", Kind = "uwu" })