--// Dodge System Debug Version
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local safeDistance = 20
local threats = {}

-- What to ignore
local ignoreParents = { "Characters", "Terrain", "Map" }

local function getRoot()
    local char = LocalPlayer.Character
    if char and char:FindFirstChild("HumanoidRootPart") then
        return char.HumanoidRootPart
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
        print("[DEBUG] Hazard detected:", part:GetFullName())
        return "Hazard"
    elseif part.Velocity.Magnitude > 5 then
        print("[DEBUG] Projectile detected:", part:GetFullName(), "Velocity:", part.Velocity)
        return "Projectile"
    else
        -- Debug low-speed object that doesn’t qualify
        print("[DEBUG] Ignored part:", part:GetFullName(), "Vel:", part.Velocity.Magnitude, "Anchored:", part.Anchored)
    end
    return nil
end

-- Track threats until removed
local function trackThreat(part, kind)
    print("[DEBUG] Tracking threat:", part:GetFullName(), "Type:", kind)
    table.insert(threats, {object = part, kind = kind})
    part.AncestryChanged:Connect(function(_, parent)
        if not parent then
            print("[DEBUG] Threat removed:", part:GetFullName())
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
        if t.object and t.object.Parent then
            if t.kind == "Projectile" then
                local dist = (t.object.Position - pos).Magnitude
                score += 1 / math.max(dist, 1)
            elseif t.kind == "Hazard" then
                local hazardDist = (t.object.Position - pos).Magnitude
                local hazardSize = t.object.Size.Magnitude / 2 + 3
                if hazardDist < hazardSize then
                    score += 9999
                end
            end
        end
    end
    return score
end

-- Smart dodge decision
local function smartDodge()
    local root = getRoot()
    if not root or #threats == 0 then return end

    print("[DEBUG] Evaluating dodge, threats:", #threats)

    local avgDir = Vector3.zero
    for _, t in ipairs(threats) do
        if t.kind == "Projectile" and t.object.Velocity.Magnitude > 1 then
            avgDir += t.object.Velocity.Unit
        end
    end
    if avgDir.Magnitude == 0 then avgDir = Vector3.new(0,0,-1) end
    avgDir = avgDir.Unit

    local rightDir = avgDir:Cross(Vector3.new(0,1,0)).Unit
    local leftDir = -rightDir

    local candidates = {
        root.Position + rightDir * safeDistance,
        root.Position + leftDir * safeDistance,
        root.Position - avgDir * safeDistance,
    }

    local bestPos = candidates[1]
    local bestScore = dangerScore(bestPos)
    for _, pos in ipairs(candidates) do
        local score = dangerScore(pos)
        print("[DEBUG] Candidate:", pos, "Score:", score)
        if score < bestScore then
            bestScore = score
            bestPos = pos
        end
    end

    print("[DEBUG] Best dodge position chosen:", bestPos, "Score:", bestScore)
    -- Uncomment to teleport when ready
    -- root.CFrame = CFrame.new(bestPos, root.Position + avgDir)
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

print("[DEBUG] Dodge system initialized")
