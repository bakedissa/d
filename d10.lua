--// Dodge System Debug Scan
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local safeDistance = 20
local threats = {}

local function getRoot()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart") or nil
end

-- Classify
local function classifyThreat(part)
    if not part:IsA("BasePart") then return nil end
    if LocalPlayer.Character and part:IsDescendantOf(LocalPlayer.Character) then return nil end

    -- DEBUG: log every part we see
    print("[DEBUG] New part seen:", part:GetFullName(), "Anchored:", part.Anchored, "Vel:", part.Velocity)

    if part.Anchored then
        return "Hazard"
    elseif part.Velocity.Magnitude > 1 then
        return "Projectile"
    end
    return nil
end

-- Track until removed
local function trackThreat(part, kind)
    print("[DEBUG] Tracking:", part:GetFullName(), "as", kind)
    table.insert(threats, {object = part, kind = kind})
    part.AncestryChanged:Connect(function(_, parent)
        if not parent then
            print("[DEBUG] Removed:", part:GetFullName())
            for i, t in ipairs(threats) do
                if t.object == part then
                    table.remove(threats, i)
                    break
                end
            end
        end
    end)
end

-- Scan existing parts
for _, desc in ipairs(Workspace:GetDescendants()) do
    local kind = classifyThreat(desc)
    if kind then trackThreat(desc, kind) end
end

-- Listen for new ones anywhere
Workspace.DescendantAdded:Connect(function(desc)
    local kind = classifyThreat(desc)
    if kind then trackThreat(desc, kind) end
end)

-- Just print threats list for now
RunService.Heartbeat:Connect(function()
    if #threats > 0 then
        print("[DEBUG] Active threats:", #threats)
        for _, t in ipairs(threats) do
            if t.object and t.object.Parent then
                print("   •", t.kind, t.object:GetFullName())
            end
        end
    end
end)

print("[DEBUG] Dodge system initialized (scanning all descendants)")
