--// Universal Dodge System: Projectiles + Hazards (Every Frame)
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local safeDistance = 20
local root
local threats = {}

-- What to ignore
local ignoreParents = { "Characters", "Terrain", "Map" }

local function getRoot()
    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
        return LocalPlayer.Character.HumanoidRootPart
    end
    return nil
end

-- Identify moving projectile vs hazard zone
local function classifyThreat(part)
    if not part:IsA("BasePart") then return nil end
    if LocalPlayer.Character and part:IsDescendantOf(LocalPlayer.Character) then return nil end
    
    for _, name in ipairs(ignoreParents) do
        if part.Parent and part.Parent.Name == name then
            return nil
        end
    end

    if part.Anchored then
        return "Hazard" -- static damaging zone
    elseif part.Velocity.Magnitude > 5 then
        return "Projectile" -- moving attack
    end
    return nil
end

-- Track threats until removed
local function trackThreat(part, kind)
    table.insert(threats, {object = part, kind = kind})
    part.AncestryChanged:Connect(function(_, parent)
        if not parent then
            for i, t in ipairs(threats) do
                if t.object == part then
                    table.remove(threats, i)
                    break
                end
            end
        end
    end)
end

-- Compute "danger score" of a position
local function dangerScore(pos)
    local score = 0
    for _, t in ipairs(threats) do
        if t.object:IsA("BasePart") then
            if t.kind == "Projectile" then
                local dist = (t.object.Position - pos).Magnitude
                score += 1 / math.max(dist, 1)
            elseif t.kind == "Hazard" then
                if (t.object.Position - pos).Magnitude < (t.object.Size.Magnitude / 2 + 3) then
                    score += 9999 -- huge penalty for teleporting into hazard
                end
            end
        end
    end
    return score
end

-- Smart dodge decision
local function smartDodge()
    root = getRoot()
    if not root or #threats == 0 then return end

    -- Average projectile direction (only moving ones)
    local avgDir = Vector3.zero
    for _, t in ipairs(threats) do
        if t.kind == "Projectile" and t.object.Velocity.Magnitude > 1 then
            avgDir += t.object.Velocity.Unit
        end
    end
    if avgDir.Magnitude == 0 then avgDir = Vector3.new(0,0,-1) end
    avgDir = avgDir.Unit

    local upDir = Vector3.new(0,1,0)
    local rightDir = avgDir:Cross(upDir).Unit
    local leftDir = -rightDir

    local candidates = {
        root.Position + rightDir * safeDistance,
        root.Position + leftDir * safeDistance,
        root.Position - avgDir * safeDistance,
        root.Position + rightDir * safeDistance * 2,
        root.Position + leftDir * safeDistance * 2,
    }

    -- Pick safest candidate
    local bestPos = candidates[1]
    local bestScore = dangerScore(candidates[1])
    for _, pos in ipairs(candidates) do
        local score = dangerScore(pos)
        if score < bestScore then
            bestScore = score
            bestPos = pos
        end
    end

    -- Teleport instantly
    root.CFrame = CFrame.new(bestPos, root.Position + avgDir)
end

-- Watch for new projectiles/hazards
Workspace.ChildAdded:Connect(function(child)
    local kind = classifyThreat(child)
    if kind then
        task.wait(0.05)
        trackThreat(child, kind)
    end
end)

-- Every frame reevaluation
RunService.Heartbeat:Connect(function()
    smartDodge()
end)
