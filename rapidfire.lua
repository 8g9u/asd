repeat task.wait() until game:IsLoaded()
pcall(function()
    loadstring(game:HttpGet("https://raw.githubusercontent.com/Pixeluted/adoniscries/main/Source.lua", true))()
end)
task.wait(0.35)

local cloneref = cloneref or function(...) return ... end
local Players = cloneref(game:GetService("Players"))
local UIS = cloneref(game:GetService("UserInputService"))
local RunService = cloneref(game:GetService("RunService"))

local LP = Players.LocalPlayer
local RATE = 0.01
local last = 0
local done = {}

local function isGun(t)
    if not t or not t:IsA("Tool") or not t:FindFirstChild("Handle") then return false end
    local n = string.lower(t.Name)
    if n:find("knife") or n:find("fist") or n:find("bat") or n:find("wallet") or n:find("phone") then
        return false
    end
    return n:find("revolver")
        or n:find("shotgun")
        or n:find("double")
        or n:find("tactical")
end

local function zeroCooldown(tool)
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
        if tool:GetAttribute("Cooldown") ~= nil then
            tool:SetAttribute("Cooldown", nil)
        end
        if tool:GetAttribute("ShootingCooldown") ~= nil then
            tool:SetAttribute("ShootingCooldown", 0)
        end
    end)
end

local function patchConnections(tool)
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

local function harden(tool)
    if not tool or done[tool] then return end
    if not isGun(tool) then return end
    zeroCooldown(tool)
    patchConnections(tool)
    done[tool] = true
    tool.DescendantAdded:Connect(function()
        zeroCooldown(tool)
    end)
end

local function scanTools()
    local char = LP.Character
    local bp = LP:FindFirstChild("Backpack")
    if char then
        for _, t in ipairs(char:GetChildren()) do
            if t:IsA("Tool") then harden(t) end
        end
    end
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") then harden(t) end
        end
    end
end

local function equipped()
    local char = LP.Character
    if not char then return nil end
    for _, t in ipairs(char:GetChildren()) do
        if t:IsA("Tool") and isGun(t) then return t end
    end
    return nil
end

local function hookChar(char)
    table.clear(done)
    task.wait(0.4)
    scanTools()
    char.ChildAdded:Connect(function(t)
        if t:IsA("Tool") then harden(t) end
    end)
end

if LP.Character then
    task.spawn(hookChar, LP.Character)
end
LP.CharacterAdded:Connect(hookChar)

if LP:FindFirstChild("Backpack") then
    LP.Backpack.ChildAdded:Connect(function(t)
        if t:IsA("Tool") then harden(t) end
    end)
end
LP.ChildAdded:Connect(function(c)
    if c.Name == "Backpack" then
        c.ChildAdded:Connect(function(t)
            if t:IsA("Tool") then harden(t) end
        end)
    end
end)

scanTools()

RunService.Heartbeat:Connect(function()
    scanTools()
    if not UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then return end
    if tick() - last < RATE then return end
    local tool = equipped()
    if not tool then return end
    harden(tool)
    zeroCooldown(tool)
    last = tick()
    pcall(function() tool:Activate() end)
end)