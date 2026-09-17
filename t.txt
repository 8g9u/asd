repeat task.wait() until game:IsLoaded()

pcall(function()
    loadstring(game:HttpGet("https://raw.githubusercontent.com/Pixeluted/adoniscries/main/Source.lua", true))() --// this is a adonis bypass (may no work in some copies dh)
end)
task.wait(0.3)

if not (hookmetamethod and newcclosure and getnamecallmethod) then
    return warn("[SS] incomplete executor")
end

local cloneref = cloneref or function(...) return ... end
local Players = cloneref(game:GetService("Players"))
local Workspace = cloneref(game:GetService("Workspace"))
local UIS = cloneref(game:GetService("UserInputService"))
local RS = cloneref(game:GetService("ReplicatedStorage"))
local RunService = cloneref(game:GetService("RunService"))
local CoreGui = cloneref(game:GetService("CoreGui"))
local GuiService = cloneref(game:GetService("GuiService"))
local Debris = cloneref(game:GetService("Debris"))

local LP = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local Mouse = LP:GetMouse()

local ENABLED = true
local ESP_ON = true
local FOV = 150
local MAX_DIST = 10000
local ORIGIN_OFFSET = 3.5
local RANGE_MIN = 10000
local RANGE_MAX = 10000
local FORCE_HIT_DIST = 5800
local BEAM_LOCAL = false

local cachedPart = nil
local lastScan = 0

local function scan()
    local now = tick()
    if now - lastScan < 0.05 then return cachedPart end
    lastScan = now
    local m = UIS:GetMouseLocation()
    local best, bestD = nil, FOV
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == LP then continue end
        local c = plr.Character
        if not c then continue end
        local h = c:FindFirstChildOfClass("Humanoid")
        if not h or h.Health <= 0 then continue end
        local part = c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Head")
        if not part then continue end
        local sp = Camera:WorldToViewportPoint(part.Position)
        if sp.Z < 0 then continue end
        if (part.Position - Camera.CFrame.Position).Magnitude > MAX_DIST then continue end
        local d = (Vector2.new(sp.X, sp.Y) - m).Magnitude
        if d < bestD then bestD, best = d, part end
    end
    cachedPart = best
    return best
end

RunService.Heartbeat:Connect(function()
    if ENABLED then scan() end
end)

local function magicOrigin(part)
    local cam = Camera.CFrame.Position
    local toCam = cam - part.Position
    if toCam.Magnitude < 0.1 then
        return part.Position + Vector3.new(0, 1, 0)
    end
    return part.Position + toCam.Unit * ORIGIN_OFFSET
end

local function getMuzzle()
    local char = LP.Character
    if char then
        local tool = char:FindFirstChildOfClass("Tool")
        if tool and tool:FindFirstChild("Handle") then
            return tool.Handle.Position
        end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then return hrp.Position + Vector3.new(0, 1.2, 0) end
    end
    return Camera.CFrame.Position
end

local function midHit(origin, target, maxDist)
    local dir = target - origin
    if dir.Magnitude <= maxDist then return target end
    return origin + dir.Unit * maxDist
end

local function bulletTrail(fromPos, toPos, lifetime)
    local p0 = Instance.new("Part")
    p0.Anchored = true
    p0.CanCollide = false
    p0.Transparency = 1
    p0.Size = Vector3.new(0.05, 0.05, 0.05)
    p0.CFrame = CFrame.new(fromPos)
    p0.Parent = Workspace

    local p1 = Instance.new("Part")
    p1.Anchored = true
    p1.CanCollide = false
    p1.Transparency = 1
    p1.Size = Vector3.new(0.05, 0.05, 0.05)
    p1.CFrame = CFrame.new(toPos)
    p1.Parent = Workspace

    local a0 = Instance.new("Attachment", p0)
    local a1 = Instance.new("Attachment", p1)

    local beam = Instance.new("Beam")
    beam.Attachment0 = a0
    beam.Attachment1 = a1
    beam.Width0 = 0.2
    beam.Width1 = 0.05
    beam.FaceCamera = true
    beam.LightEmission = 1
    beam.LightInfluence = 0
    beam.Color = ColorSequence.new(Color3.fromRGB(160, 210, 255))
    beam.Transparency = NumberSequence.new(0.1, 0.7)
    beam.Parent = p0

    Debris:AddItem(p0, lifetime or 0.25)
    Debris:AddItem(p1, lifetime or 0.25)
end

local MainRemote = nil
do
    local gr = RS:FindFirstChild("GameRemotes")
    MainRemote = gr and gr:FindFirstChild("MainGameEvent")
    if not MainRemote then
        local mr = RS:FindFirstChild("MainRemotes")
        MainRemote = mr and mr:FindFirstChild("MainRemoteEvent")
    end
    if not MainRemote then
        MainRemote = RS:FindFirstChild("MainGameEvent", true)
            or RS:FindFirstChild("MainRemoteEvent", true)
    end
end

local check = checkcaller or function() return false end

local circle
if Drawing and Drawing.new then
    circle = Drawing.new("Circle")
    circle.Thickness = 1.5
    circle.NumSides = 64
    circle.Filled = false
    circle.Color = Color3.fromRGB(120, 180, 255)
    circle.Transparency = 0.25
end

RunService.RenderStepped:Connect(function()
    if not circle then return end
    if ENABLED then
        circle.Visible = true
        circle.Radius = FOV
        local inset = GuiService:GetGuiInset()
        circle.Position = Vector2.new(Mouse.X, Mouse.Y + inset.Y)
    else
        circle.Visible = false
    end
end)

pcall(function()
    local oldIndex
    oldIndex = hookmetamethod(game, "__index", newcclosure(function(self, key)
        if ENABLED and not check() and self == Mouse then
            local part = cachedPart
            if part then
                if key == "Hit" then return CFrame.new(part.Position) end
                if key == "Target" then return part end
            end
        end
        return oldIndex(self, key)
    end))
end)

local oldNC
oldNC = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
    if not ENABLED or check() then
        return oldNC(self, ...)
    end

    local method = getnamecallmethod()
    local part = cachedPart

    if part and (self == Workspace or (typeof(self) == "Instance" and self.ClassName == "Workspace")) then
        if method == "Raycast" then
            local a = { ... }
            if typeof(a[1]) == "Vector3" and typeof(a[2]) == "Vector3" then
                local dir = part.Position - a[1]
                if dir.Magnitude > 1 then
                    a[2] = dir.Unit * (dir.Magnitude + 20)
                end
                return oldNC(self, table.unpack(a))
            end
        elseif method == "FindPartOnRayWithIgnoreList"
            or method == "FindPartOnRay"
            or method == "FindPartOnRayWithWhitelist" then
            local a = { ... }
            if typeof(a[1]) == "Ray" then
                local dir = part.Position - a[1].Origin
                if dir.Magnitude > 1 then
                    a[1] = Ray.new(a[1].Origin, dir.Unit * (dir.Magnitude + 20))
                end
                return oldNC(self, table.unpack(a))
            end
        end
    end

    if part and MainRemote and self == MainRemote and method == "FireServer" then
        local a = { ... }
        if a[1] == "ShootGun" then
            local hitPos = part.Position
            local originReal = (typeof(a[3]) == "Vector3" and a[3]) or getMuzzle()

            local function clonarArgs(origin, hit, rng)
                local b = {}
                for i = 1, #a do b[i] = a[i] end
                b[3] = origin
                b[4] = nil
                b[5] = hit
                b[6] = part
                b[7] = Vector3.new(0, 1, 0)
                b[8] = rng or 10000
                return b
            end

            local distReal = (hitPos - originReal).Magnitude

            local fakeHit = midHit(originReal, hitPos, FORCE_HIT_DIST)

            oldNC(self, table.unpack(clonarArgs(originReal, fakeHit, 10000)))
            oldNC(self, table.unpack(clonarArgs(originReal, hitPos, 10000)))
            oldNC(self, table.unpack(clonarArgs(originReal, hitPos, 100)))
            oldNC(self, table.unpack(clonarArgs(originReal, hitPos, 9999)))

            if BEAM_LOCAL then
                task.defer(function()
                    bulletTrail(originReal, hitPos, 0.3)
                end)
            end

            local dmg = clonarArgs(magicOrigin(part), hitPos, 10000)
            return oldNC(self, table.unpack(dmg))

        elseif a[1] == "ShootingGunLetsGo" then
            local hitPos = part.Position
            a[3] = hitPos
            a[4] = {{ Position = hitPos, Normal = Vector3.new(0, 1, 0), Instance = part }}
            return oldNC(self, table.unpack(a))
        end
    end

    return oldNC(self, ...)
end))

local folder = Instance.new("Folder")
folder.Name = "SS_ESP"
pcall(function() folder.Parent = CoreGui end)
if not folder.Parent then folder.Parent = LP:WaitForChild("PlayerGui") end
local esp = {}

local function clearEsp(plr)
    if esp[plr] and esp[plr].bb then esp[plr].bb:Destroy() end
    esp[plr] = nil
end

local function ensureEsp(plr)
    if esp[plr] then return esp[plr] end
    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.fromOffset(170, 48)
    bb.AlwaysOnTop = true
    bb.StudsOffset = Vector3.new(0, 3.2, 0)
    bb.Parent = folder
    local function lab(y, size, bold)
        local t = Instance.new("TextLabel")
        t.Size = UDim2.new(1, 0, 0, size)
        t.Position = UDim2.fromOffset(0, y)
        t.BackgroundTransparency = 1
        t.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
        t.TextSize = size == 16 and 13 or 12
        t.TextStrokeTransparency = 0.4
        t.Parent = bb
        return t
    end
    esp[plr] = { bb = bb, name = lab(0, 16, true), hp = lab(16, 14, false), dist = lab(30, 14, false) }
    esp[plr].name.TextColor3 = Color3.fromRGB(220, 230, 255)
    esp[plr].dist.TextColor3 = Color3.fromRGB(160, 160, 175)
    return esp[plr]
end

RunService.RenderStepped:Connect(function()
    if not ESP_ON then
        for p in pairs(esp) do clearEsp(p) end
        return
    end
    local my = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == LP then continue end
        local c = plr.Character
        local head = c and (c:FindFirstChild("Head") or c:FindFirstChild("HumanoidRootPart"))
        local hum = c and c:FindFirstChildOfClass("Humanoid")
        if not head or not hum or hum.Health <= 0 then
            clearEsp(plr)
            continue
        end
        local e = ensureEsp(plr)
        e.bb.Adornee = head
        e.name.Text = plr.DisplayName .. " (@" .. plr.Name .. ")"
        local hp, mx = math.floor(hum.Health), math.floor(hum.MaxHealth)
        e.hp.Text = string.format("HP %d / %d", hp, mx)
        local pct = mx > 0 and hp / mx or 0
        e.hp.TextColor3 = pct > 0.5 and Color3.fromRGB(100, 220, 120)
            or pct > 0.25 and Color3.fromRGB(255, 190, 70)
            or Color3.fromRGB(255, 80, 90)
        e.dist.Text = my and string.format("%dm", math.floor((my.Position - head.Position).Magnitude)) or "—"
    end
end)

Players.PlayerRemoving:Connect(clearEsp)

UIS.InputBegan:Connect(function(i, g)
    if g then return end
    if i.KeyCode == Enum.KeyCode.V then
        ENABLED = not ENABLED
    end
end)
