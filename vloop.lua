local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")
local CoreGui    = game:GetService("CoreGui")

local player    = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local hrp       = character:WaitForChild("HumanoidRootPart")
local humanoid  = character:WaitForChild("Humanoid")

player.CharacterAdded:Connect(function(c)
    character = c
    hrp       = c:WaitForChild("HumanoidRootPart", 5)
    humanoid  = c:WaitForChild("Humanoid", 5)
end)

local cfg = {
    active       = false,
    speed        = 42000,
    height       = 8200,
    radius       = 1800,
    diveChance   = 0.42,
    diveDepth    = 58000,
    targetPlayer = 0.90,
    refresh      = 0.9,
    jitter       = 40,
    spread       = 0.55,
    orbitBias    = 0.35,
    stickiness   = 2.4,
    burstChance  = 0.18,
    burstPower   = 3.5,
}

local LIMITS = {
    speed        = { 1000, 300000 },
    height       = { -20000, 150000 },
    radius       = { 150, 25000 },
    diveChance   = { 0, 100 },
    diveDepth    = { 0, 250000 },
    targetPlayer = { 0, 100 },
    refresh      = { 0.15, 10 },
    jitter       = { 0, 3000 },
    spread       = { 0, 200 },
    orbitBias    = { 0, 100 },
    stickiness   = { 0, 1000 },
    burstChance  = { 0, 100 },
    burstPower   = { 0, 2000 },
}

local savedPos    = nil
local currentPos  = Vector3.zero
local targetPos   = Vector3.zero
local diveLeft    = 0
local lastRefresh = 0
local running     = false

local anchorPlayer = nil
local anchorSince  = 0
local orbitDir     = 1
local orbitPhase   = 0
local burstLeft    = 0
local burstVec     = Vector3.zero

pcall(function()
    if sethiddenproperty then
        sethiddenproperty(Workspace, "FallenPartsDestroyHeight", -999999999)
    else
        Workspace.FallenPartsDestroyHeight = -999999999
    end
end)

local function safeNum(v, fallback)
    if type(v) ~= "number" then return fallback end
    if v ~= v then return fallback end
    if v == math.huge or v == -math.huge then return fallback end
    return v
end

local function gauss(mean, dev)
    local u1 = math.random()
    local u2 = math.random()
    if u1 < 1e-9 then u1 = 1e-9 end
    return mean + math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2) * dev
end

local function pickPlayers()
    local list = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player then
            local c = p.Character
            if c then
                local h = c:FindFirstChild("HumanoidRootPart")
                local hum = c:FindFirstChildOfClass("Humanoid")
                if h and hum and hum.Health > 0 and h.Position.Magnitude < 1e7 then
                    table.insert(list, { plr = p, pos = h.Position })
                end
            end
        end
    end
    return list
end

local function weightedPick(list)
    if #list == 0 then return nil end
    local weights = {}
    local total = 0
    local myPos = hrp and hrp.Position or Vector3.zero
    for i, entry in ipairs(list) do
        local d = (entry.pos - myPos).Magnitude
        local w = 1 / (1 + d * 0.0008)
        if anchorPlayer == entry.plr then
            w = w * cfg.stickiness
        end
        weights[i] = w
        total = total + w
    end
    local r = math.random() * total
    local acc = 0
    for i, w in ipairs(weights) do
        acc = acc + w
        if r <= acc then return list[i] end
    end
    return list[#list]
end

local function pickCenter()
    local list = pickPlayers()
    if #list == 0 then
        anchorPlayer = nil
        return Vector3.zero
    end

    if math.random() < cfg.targetPlayer then
        local now = tick()
        if not anchorPlayer or (now - anchorSince) > cfg.stickiness then
            local pick = weightedPick(list)
            anchorPlayer = pick and pick.plr or nil
            anchorSince = now
        else
            local stillThere = false
            for _, e in ipairs(list) do
                if e.plr == anchorPlayer then stillThere = true; break end
            end
            if not stillThere then
                local pick = weightedPick(list)
                anchorPlayer = pick and pick.plr or nil
                anchorSince = now
            end
        end

        if anchorPlayer and anchorPlayer.Character then
            local h = anchorPlayer.Character:FindFirstChild("HumanoidRootPart")
            if h then return h.Position end
        end
    end
    return Vector3.zero
end

local function newTarget()
    local c = pickCenter()
    local spread = cfg.radius * cfg.spread

    orbitPhase = orbitPhase + (math.random() - 0.5) * 1.8
    if math.random() < 0.25 then orbitDir = -orbitDir end

    local ang = orbitPhase * orbitDir + math.random() * 0.4
    local rad = math.clamp(gauss(cfg.radius * 0.5, spread * 0.5), 150, cfg.radius)
    local dx = math.cos(ang) * rad + gauss(0, spread * 0.25)
    local dz = math.sin(ang) * rad + gauss(0, spread * 0.25)

    if anchorPlayer and cfg.orbitBias > 0 then
        local bias = cfg.orbitBias
        dx = dx * (1 - bias) + math.cos(ang) * rad * bias
        dz = dz * (1 - bias) + math.sin(ang) * rad * bias
    end

    local y = cfg.height + math.random(-cfg.jitter, cfg.jitter)

    if diveLeft <= 0 and math.random() < cfg.diveChance then
        diveLeft = math.random(2, 5)
    end
    if diveLeft > 0 then
        y = cfg.height - cfg.diveDepth + math.random(-300, 300)
        diveLeft = diveLeft - 1
    end

    if burstLeft <= 0 and math.random() < cfg.burstChance then
        burstLeft = math.random(2, 4)
        burstVec = Vector3.new(
            gauss(0, cfg.radius * 1.5),
            math.random(-cfg.jitter * 4, cfg.jitter * 4),
            gauss(0, cfg.radius * 1.5)
        ) * cfg.burstPower
    end

    local px, py, pz = c.X + dx, y, c.Z + dz
    if burstLeft > 0 then
        px = px + burstVec.X
        py = py + burstVec.Y
        pz = pz + burstVec.Z
        burstLeft = burstLeft - 1
    end

    if px ~= px or py ~= py or pz ~= pz then
        return Vector3.new(0, cfg.height, 0)
    end
    return Vector3.new(px, py, pz)
end

local parentGui = (gethui and gethui())
    or CoreGui:FindFirstChild("RobloxGui")
    or player:WaitForChild("PlayerGui")

if parentGui:FindFirstChild("VoidLoop") then
    parentGui.VoidLoop:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "VoidLoop"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = parentGui

local bg     = Color3.fromRGB(18, 18, 20)
local panel  = Color3.fromRGB(26, 26, 29)
local field  = Color3.fromRGB(14, 14, 16)
local line   = Color3.fromRGB(40, 40, 45)
local text   = Color3.fromRGB(215, 215, 220)
local dim    = Color3.fromRGB(105, 105, 112)
local red    = Color3.fromRGB(190, 60, 85)

local W = 230

local root = Instance.new("Frame")
root.Size = UDim2.new(0, W, 0, 200)
root.Position = UDim2.new(0, 60, 0, 140)
root.BackgroundColor3 = bg
root.BorderSizePixel = 0
root.Active = true
root.Draggable = true
root.Parent = gui
Instance.new("UICorner", root).CornerRadius = UDim.new(0, 3)

local stroke = Instance.new("UIStroke", root)
stroke.Color = line
stroke.Thickness = 1

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 24)
title.BackgroundColor3 = panel
title.BorderSizePixel = 0
title.Text = "  void loop"
title.TextColor3 = dim
title.Font = Enum.Font.Code
title.TextSize = 12
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = root
Instance.new("UICorner", title).CornerRadius = UDim.new(0, 3)

local close = Instance.new("TextButton")
close.Size = UDim2.new(0, 24, 0, 24)
close.Position = UDim2.new(1, -24, 0, 0)
close.BackgroundTransparency = 1
close.Text = "x"
close.TextColor3 = dim
close.Font = Enum.Font.Code
close.TextSize = 12
close.AutoButtonColor = false
close.Parent = root

local y = 34

local btn = Instance.new("TextButton")
btn.Size = UDim2.new(1, -20, 0, 26)
btn.Position = UDim2.new(0, 10, 0, y)
btn.BackgroundColor3 = panel
btn.BorderSizePixel = 0
btn.Text = "off"
btn.TextColor3 = text
btn.Font = Enum.Font.Code
btn.TextSize = 12
btn.AutoButtonColor = false
btn.Parent = root
Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 3)

local btnEdge = Instance.new("UIStroke", btn)
btnEdge.Color = line
btnEdge.Thickness = 1

y = y + 26 + 8

local function row(label, key, isPercent, isFloat)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, -20, 0, 22)
    f.Position = UDim2.new(0, 10, 0, y)
    f.BackgroundTransparency = 1
    f.Parent = root

    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, -70, 1, 0)
    l.BackgroundTransparency = 1
    l.Text = label
    l.TextColor3 = dim
    l.Font = Enum.Font.Code
    l.TextSize = 11
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = f

    local b = Instance.new("TextBox")
    b.Size = UDim2.new(0, 60, 0, 20)
    b.Position = UDim2.new(1, -60, 0.5, -10)
    b.BackgroundColor3 = field
    b.BorderSizePixel = 0
    b.TextColor3 = text
    b.Font = Enum.Font.Code
    b.TextSize = 11
    b.ClearTextOnFocus = false
    b.Text = isPercent and tostring(math.floor(cfg[key] * 100))
        or (isFloat and string.format("%.1f", cfg[key]))
        or tostring(cfg[key])
    b.Parent = f
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 2)

    local be = Instance.new("UIStroke", b)
    be.Color = line
    be.Thickness = 1

    local function cur()
        if isPercent then return tostring(math.floor(cfg[key] * 100)) end
        if isFloat then return string.format("%.1f", cfg[key]) end
        return tostring(cfg[key])
    end

    b.FocusLost:Connect(function()
        local raw = tonumber(b.Text)
        if not raw or raw ~= raw then
            b.Text = cur()
            return
        end
        local lo, hi = LIMITS[key][1], LIMITS[key][2]
        local v = math.clamp(raw, lo, hi)
        if isPercent then
            cfg[key] = v / 100
            b.Text = tostring(math.floor(v))
        elseif isFloat then
            cfg[key] = v
            b.Text = string.format("%.1f", v)
        else
            cfg[key] = math.floor(v)
            b.Text = tostring(cfg[key])
        end
        be.Color = red
        task.delay(0.3, function()
            if be and be.Parent then be.Color = line end
        end)
    end)

    y = y + 22 + 3
end

row("speed", "speed")
row("radius", "radius")
row("height", "height")
row("jitter", "jitter")
row("refresh", "refresh", false, true)
row("dive %", "diveChance", true)
row("dive depth", "diveDepth")
row("target p.", "targetPlayer", true)
row("spread", "spread", true)
row("orbit bias", "orbitBias", true)
row("stickiness", "stickiness", false, true)
row("burst %", "burstChance", true)
row("burst power", "burstPower", false, true)

root.Size = UDim2.new(0, W, 0, y + 12)

btn.MouseEnter:Connect(function() btn.BackgroundColor3 = Color3.fromRGB(32, 32, 36) end)
btn.MouseLeave:Connect(function() btn.BackgroundColor3 = panel end)
close.MouseEnter:Connect(function() close.TextColor3 = red end)
close.MouseLeave:Connect(function() close.TextColor3 = dim end)

local function stop()
    running = false
    if savedPos and hrp and hrp.Parent then
        pcall(function()
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
            hrp.CFrame = savedPos
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end)
    end
    if humanoid and humanoid.Parent then
        pcall(function()
            humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, true)
            humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
            humanoid.PlatformStand = false
        end)
    end
    btn.Text = "off"
    btn.TextColor3 = text
    btnEdge.Color = line
    stroke.Color = line
end

local function start()
    if not hrp or not hrp.Parent then return end
    savedPos     = hrp.CFrame
    currentPos   = hrp.Position
    diveLeft     = 0
    lastRefresh  = tick()
    anchorPlayer = nil
    anchorSince  = 0
    orbitDir     = math.random() < 0.5 and 1 or -1
    orbitPhase   = math.random() * math.pi * 2
    burstLeft    = 0
    burstVec     = Vector3.zero
    targetPos    = newTarget()
    running      = true

    if humanoid and humanoid.Parent then
        pcall(function()
            humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
            humanoid.PlatformStand = true
            humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
        end)
    end

    btn.Text = "on"
    btn.TextColor3 = red
    btnEdge.Color = red
    stroke.Color = red
end

btn.MouseButton1Click:Connect(function()
    cfg.active = not cfg.active
    if cfg.active then start() else stop() end
end)

close.MouseButton1Click:Connect(function()
    cfg.active = false
    running = false
    if savedPos and hrp and hrp.Parent then
        pcall(function()
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
            hrp.CFrame = savedPos
        end)
    end
    if humanoid and humanoid.Parent then
        pcall(function()
            humanoid.PlatformStand = false
            humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
        end)
    end
    gui:Destroy()
end)

local MIN_Y = -8000

RunService.Heartbeat:Connect(function(dt)
    if not running or not cfg.active then return end
    if not hrp or not hrp.Parent then return end
    if not character or not character.Parent then return end

    dt = safeNum(dt, 1 / 60)
    if dt <= 0 then dt = 1 / 60 end

    if humanoid and humanoid.Parent then
        pcall(function()
            if humanoid.Health < humanoid.MaxHealth then
                humanoid.Health = humanoid.MaxHealth
            end
            if humanoid:GetState() ~= Enum.HumanoidStateType.Freefall then
                humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
            end
            humanoid.PlatformStand = true
        end)
    end

    local pos = hrp.Position
    if pos.X ~= pos.X or pos.Y ~= pos.Y or pos.Z ~= pos.Z
        or math.abs(pos.X) > 1e7 or math.abs(pos.Z) > 1e7 then
        currentPos = Vector3.new(0, cfg.height, 0)
        targetPos  = currentPos
    end

    if targetPos.Y < MIN_Y then
        targetPos = Vector3.new(targetPos.X, MIN_Y, targetPos.Z)
    end
    if currentPos.Y < MIN_Y then
        currentPos = Vector3.new(currentPos.X, MIN_Y, currentPos.Z)
    end

    local dist = (currentPos - targetPos).Magnitude
    if dist ~= dist then dist = 0 end
    if dist < 40 or (tick() - lastRefresh) > cfg.refresh then
        targetPos = newTarget()
        if targetPos.Y < MIN_Y then
            targetPos = Vector3.new(targetPos.X, MIN_Y, targetPos.Z)
        end
        lastRefresh = tick()
    end

    local alpha = cfg.speed * dt / 100
    if alpha ~= alpha or alpha <= 0 then alpha = 0.1 end
    if alpha > 1 then alpha = 1 end
    currentPos = currentPos:Lerp(targetPos, alpha)

    if currentPos.Y < MIN_Y then
        currentPos = Vector3.new(currentPos.X, MIN_Y, currentPos.Z)
    end

    local ok, cf = pcall(function()
        local look = hrp.CFrame - hrp.CFrame.Position
        return CFrame.new(currentPos) * look
    end)
    if ok and cf then
        pcall(function() hrp.CFrame = cf end)
    end

    pcall(function()
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end)
end)