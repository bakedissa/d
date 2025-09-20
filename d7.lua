local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local root = nil
local safeDistance = 15 -- how far to teleport sideways

local function getRoot()
    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
        return LocalPlayer.Character.HumanoidRootPart
    end
    return nil
end

-- Teleport sideways relative to projectile
local function teleportDodge(projectile)
    root = getRoot()
    if not root or not projectile or not projectile:IsA("BasePart") then return end

    -- Direction of projectile travel
    local velocity = projectile.Velocity
    if velocity.Magnitude < 1 then return end

    local forwardDir = velocity.Unit
    local upDir = Vector3.new(0,1,0)

    -- Two possible sideways dodge directions
    local rightDir = forwardDir:Cross(upDir).Unit
    local leftDir = -rightDir

    -- Pick left or right randomly (could improve by checking free space)
    local dodgeDir = math.random(1,2) == 1 and leftDir or rightDir

    -- Teleport!
    root.CFrame = root.CFrame + dodgeDir * safeDistance
end

-- Watch projectiles
workspace.ChildAdded:Connect(function(child)
    if child.Name == "npcShurikenThrow" and child:IsA("BasePart") then
        -- Wait until projectile fully spawns
        task.wait(0.05)
        teleportDodge(child)
    end
end)
