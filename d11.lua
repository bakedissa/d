--// Projectile + Hazard Detection
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

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

-- Classify part/model as hazard or projectile
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

-- Track threats and auto-remove when destroyed
local function trackThreat(inst, kind)
    print("[DEBUG] Tracking:", inst:GetFullName(), "as", kind)
    table.insert(threats, {object = inst, kind = kind})
    inst.AncestryChanged:Connect(function(_, parent)
        if not parent then
            for i, t in ipairs(threats) do
                if t.object == inst then
                    table.remove(threats, i)
                    print("[DEBUG] Removed:", inst:GetFullName())
                    break
                end
            end
        end
    end)
end

-- Detect when new descendants appear in Workspace
Workspace.DescendantAdded:Connect(function(inst)
    local kind = classifyThreat(inst)
    if kind then trackThreat(inst, kind) end
end)

-- Initial scan (in case projectiles already exist)
for _, inst in ipairs(Workspace:GetDescendants()) do
    local kind = classifyThreat(inst)
    if kind then trackThreat(inst, kind) end
end

-- Periodic summary
local lastSummary = 0
RunService.Heartbeat:Connect(function()
    if tick() - lastSummary >= 1 then
        lastSummary = tick()
        local projCount, hazardCount = 0, 0
        for _, t in ipairs(threats) do
            if t.object and t.object.Parent then
                if t.kind == "Projectile" then projCount += 1 end
                if t.kind == "Hazard" then hazardCount += 1 end
            end
        end
        if projCount + hazardCount > 0 then
            print(string.format("[DEBUG] Active threats → Projectiles: %d | Hazards: %d", projCount, hazardCount))
        end
    end
end)

print("[DEBUG] Dodge system initialized (monitoring ReplicatedStorage.enemyProjectiles & projectiles)")
