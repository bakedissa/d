--// Projectile + Hazard Detection + Dodge (Debug)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local RootPart

-- Libraries
local libraries = {
    ReplicatedStorage:WaitForChild("enemyProjectiles"),
    ReplicatedStorage:WaitForChild("projectiles")
}

-- Build projectile name set
local knownProjectiles = {}
for _, lib in ipairs(libraries) do
    for _, obj in ipairs(lib:GetChildren()) do
        knownProjectiles[obj.Name] = true
        print("[DEBUG] Registered projectile template:", obj.Name)
    end
end

-- Active threats
local threats = {}

-- Dodge settings
local dodgeDistance = 20 -- how far to teleport sideways
local dangerRadius = 15  -- how close a projectile must be to trigger dodge

local function getRoot()
    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
        return LocalPlayer.Character.HumanoidRootPart
    end
    return nil
end

local function teleportSideways(threat)
    RootPart = getRoot()
    if not RootPart then return end

    local dodgeDir
    if threat.kind == "Projectile" and threat.object:IsA("BasePart") then
        local vel = threat.object.Velocity
        if vel.Magnitude > 1 then
            local forward = vel.Unit
            local right = forward:Cross(Vector3.new(0,1,0)).Unit
            dodgeDir = (math.random(1,2) == 1) and right or -right
        end
    end

    if not dodgeDir then
        dodgeDir = Vector3.new(1,0,0) -- fallback dodge
    end

    print("[DEBUG] Dodging from:", threat.object:GetFullName())
    RootPart.CFrame = RootPart.CFrame + dodgeDir * dodgeDistance
end

local function classifyThreat(inst)
    if not inst:IsA("BasePart") and not inst:IsA("Model") then return nil end
    if LocalPlayer.Character and inst:IsDescendantOf(LocalPlayer.Character) then return nil end
    if knownProjectiles[inst.Name] then
        if inst:IsA("BasePart") and inst.Anchored then
            return "Hazard"
        else
            return "Projectile"
        end
    end
    return nil
end

local function trackThreat(inst, kind)
    table.insert(threats, {object = inst, kind = kind})
    inst.AncestryChanged:Connect(function(_, parent)
        if not parent then
            for i, t in ipairs(threats) do
                if t.object == inst then
                    table.remove(threats, i)
                    break
                end
            end
        end
    end)
end

-- Detect spawns
Workspace.DescendantAdded:Connect(function(inst)
    local kind = classifyThreat(inst)
    if kind then
        print("[DEBUG] Tracking:", inst:GetFullName(), "as", kind)
        trackThreat(inst, kind)
    end
end)

-- Initial scan
for _, inst in ipairs(Workspace:GetDescendants()) do
    local kind = classifyThreat(inst)
    if kind then trackThreat(inst, kind) end
end

-- Every frame check
RunService.Heartbeat:Connect(function()
    RootPart = getRoot()
    if not RootPart then return end

    for _, t in ipairs(threats) do
        if t.object and t.object.Parent then
            if t.kind == "Projectile" and t.object:IsA("BasePart") then
                local dist = (t.object.Position - RootPart.Position).Magnitude
                if dist < 50 then
                    print(string.format("[DEBUG] Projectile %s at %.1f studs", t.object.Name, dist))
                end
                if dist <= dangerRadius then
                    print("[DEBUG] Dodging projectile:", t.object.Name, "distance:", dist)
                    teleportSideways(t)
                end
            elseif t.kind == "Hazard" and t.object:IsA("BasePart") then
                local rel = RootPart.Position - t.object.Position
                if math.abs(rel.X) <= t.object.Size.X/2
                and math.abs(rel.Y) <= t.object.Size.Y/2
                and math.abs(rel.Z) <= t.object.Size.Z/2 then
                    print("[DEBUG] Standing on hazard:", t.object.Name)
                    teleportSideways(t)
                end
            end
        end
    end
end)

print("[DEBUG] Dodge system initialized (with debug checks)")
