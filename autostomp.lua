local cloneref = cloneref or function(...) return ... end

local Services = {
    RunService        = cloneref(game:GetService("RunService")),
    Players           = cloneref(game:GetService("Players")),
    ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage")),
}

local LocalPlayer = Services.Players.LocalPlayer

local MainRemote = nil
local function findMainRemote()
    local rs = Services.ReplicatedStorage
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
            if n:find("main") or n:find("game") then
                return v
            end
        end
    end
    return nil
end

MainRemote = findMainRemote()
if MainRemote then
    print("Remote found:", MainRemote:GetFullName())
else
    warn("Remote not found")
end

local function isKnocked(plr)
    local char = plr and plr.Character
    if not char then return false end
    local be = char:FindFirstChild("BodyEffects")
    if not be then return false end
    local ko = be:FindFirstChild("K.O") or be:FindFirstChild("Knocked")
    return ko and ko.Value == true
end

local function fireStomp(plr)
    pcall(function()
        MainRemote:FireServer("Stomp")
        MainRemote:FireServer("StompPlayer", plr.Character)
        MainRemote:FireServer("Stomp", plr.Character)
    end)
end

local stomped = {}
local STOMP_DELAY = 0.35

Services.RunService.Heartbeat:Connect(function()
    if not MainRemote then return end
    local now = tick()
    for _, plr in ipairs(Services.Players:GetPlayers()) do
        if plr ~= LocalPlayer and isKnocked(plr) then
            local last = stomped[plr]
            if not last or now - last >= STOMP_DELAY then
                stomped[plr] = now
                fireStomp(plr)
            end
        else
            stomped[plr] = nil
        end
    end
end)