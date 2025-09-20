--[[ 
    Projectile Inspector & Visualizer (Safe / Educational)
    - Scans ReplicatedStorage enemyProjectiles and projectiles.
    - Builds databases of projectile templates, precasts, and movement patterns.
    - Monitors precast activations and workspace hitBox parts.
    - Visualizes predicted trajectories (visual only).
    - DOES NOT move or control the player, and DOES NOT hook ProjectileCast.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

local ProjectileDatabase = {}   -- { [enemyName] = { {object=Model, hitBox=BasePart, name=string, type="direct"/"primary"} , ... } }
local PrecastDatabase = {}     -- { [enemyName] = { [projectileName] = precastInstance, ... } }
local MovementPatterns = {}    -- { [projectileName] = { speed=..., behavior=..., homing=bool, arc=bool } }

-- ===== Movement script helpers =====
local function findMovementScript(object)
    for _, child in ipairs(object:GetDescendants()) do
        if child:IsA("Script") or child:IsA("LocalScript") then
            local lname = child.Name:lower()
            if lname:find("move") or lname:find("control") or lname:find("projectile") then
                return child
            end
        end
    end
    return nil
end

local function extractMovementData(script)
    if not script then
        return { speed = 50, behavior = "straight", homing = false, arc = false }
    end

    local ok, speed = pcall(function() return script:FindFirstChild("Speed") and script.Speed.Value end)
    local ok2, behavior = pcall(function() return script:FindFirstChild("Behavior") and script.Behavior.Value end)
    local homing = script:FindFirstChild("Homing") ~= nil
    local arc = script:FindFirstChild("Arc") ~= nil

    return {
        speed = (type(speed) == "number" and speed) or 50,
        behavior = (type(behavior) == "string" and behavior) or "straight",
        homing = homing,
        arc = arc
    }
end

-- ===== Precast / precast CFrame helpers =====
local function safeGetPivotCFrame(instance)
    if not instance then return CFrame.new() end
    if instance:IsA("BasePart") then
        return instance.CFrame
    elseif instance:IsA("Model") then
        if instance.PrimaryPart then
            return instance.PrimaryPart.CFrame
        else
            local success, pivot = pcall(function() return instance:GetPivot() end)
            if success and pivot then
                return CFrame.new(pivot.Position)
            end
        end
    end
    -- fallback: try to use Position property if present
    local pos = instance:FindFirstChild("Position") or instance:FindFirstChildWhichIsA and instance:FindFirstChildWhichIsA("Vector3Value")
    return CFrame.new(0,0,0)
end

-- ===== Trajectory calc & visualization (visual only) =====
local function calculateTrajectory(cframe, movementPattern)
    if not cframe or not movementPattern then return nil end
    local dir = cframe.LookVector or Vector3.new(0,0,1)
    local speed = movementPattern.speed or 50
    local behavior = movementPattern.behavior or "straight"

    if behavior == "straight" then
        return {
            type = "linear",
            origin = cframe.Position,
            direction = dir.Unit,
            speed = speed,
            startTime = tick()
        }
    elseif behavior == "arc" or movementPattern.arc then
        return {
            type = "parabolic",
            origin = cframe.Position,
            direction = dir.Unit,
            speed = speed,
            gravity = Vector3.new(0, Workspace.Gravity * -1, 0),
            startTime = tick()
        }
    elseif behavior == "homing" or movementPattern.homing then
        return {
            type = "homing",
            origin = cframe.Position,
            direction = dir.Unit,
            speed = speed,
            startTime = tick(),
            -- visualization-only target: player's HRP if present
            target = (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")) or nil
        }
    end

    return nil
end

local function createDangerZoneVisual(trajectory, hitBoxSize)
    if not trajectory then return end

    local part = Instance.new("Part")
    part.Anchored = true
    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = false
    part.Material = Enum.Material.Neon
    part.Transparency = 0.6
    part.Color = Color3.fromRGB(255, 80, 80)
    part.Name = "InspectorDangerZone"
    part.Size = hitBoxSize or Vector3.new(3,3,3)

    if trajectory.type == "linear" then
        -- length based on speed (visual ~2s)
        local distance = math.max(2, trajectory.speed * 2)
        part.Size = Vector3.new(2, 2, math.clamp(distance, 2, 200))
        -- orient along direction: use lookAt target to ensure rotation
        local mid = trajectory.origin + trajectory.direction * (distance / 2)
        part.CFrame = CFrame.new(mid, trajectory.origin + trajectory.direction * distance)
    elseif trajectory.type == "parabolic" then
        part.Size = Vector3.new(6,6,6)
        part.CFrame = CFrame.new(trajectory.origin)
    elseif trajectory.type == "homing" then
        part.Shape = Enum.PartType.Ball
        part.Size = Vector3.new(8,8,8)
        local pos = trajectory.target and trajectory.target.Position or trajectory.origin
        part.CFrame = CFrame.new(pos)
    end

    part.Parent = Workspace

    -- fade out & remove after 2.2 seconds
    spawn(function()
        local TweenService = game:GetService("TweenService")
        local info = TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
        task.wait(1.8)
        pcall(function()
            TweenService:Create(part, info, {Transparency = 1}):Play()
        end)
        task.wait(0.4)
        pcall(function() part:Destroy() end)
    end)
end

-- ===== Database building (fixed for Folders vs Models) =====
local function buildProjectileDatabase()
    ProjectileDatabase = {}
    PrecastDatabase = {}
    MovementPatterns = {}

    local function scanFolderRoot(folder, ownerKey)
        if not folder then return end

        for _, child in ipairs(folder:GetChildren()) do
            if child:IsA("Folder") then
                -- Keep a structure for the folder name
                if ownerKey then
                    -- nested folder inside enemy folder - recurse
                    scanFolderRoot(child, ownerKey)
                else
                    -- top-level folder (e.g., enemy name)
                    scanFolderRoot(child, child.Name)
                end
            elseif child:IsA("Model") then
                local enemyName = ownerKey or "Unknown"
                ProjectileDatabase[enemyName] = ProjectileDatabase[enemyName] or {}
                PrecastDatabase[enemyName] = PrecastDatabase[enemyName] or {}

                local hitBox = child:FindFirstChild("hitBox")
                local primaryPart = child.PrimaryPart -- safe because child:IsA("Model")

                if hitBox and hitBox:IsA("BasePart") then
                    table.insert(ProjectileDatabase[enemyName], {
                        object = child,
                        hitBox = hitBox,
                        type = "direct",
                        name = child.Name
                    })
                elseif primaryPart and primaryPart:IsA("BasePart") then
                    table.insert(ProjectileDatabase[enemyName], {
                        object = child,
                        hitBox = primaryPart,
                        type = "primary",
                        name = child.Name
                    })
                end

                local precast = child:FindFirstChild("precast")
                if precast then
                    PrecastDatabase[enemyName][child.Name] = precast
                end

                local movementScript = findMovementScript(child)
                if movementScript then
                    MovementPatterns[child.Name] = extractMovementData(movementScript)
                end

                -- Also recurse children to find nested Models (e.g., line entries inside a folder)
                for _, nested in ipairs(child:GetChildren()) do
                    if nested:IsA("Folder") then
                        scanFolderRoot(nested, enemyName)
                    elseif nested:IsA("Model") then
                        -- we will pick it up on next loop iteration because it's a direct child of folder if present
                    end
                end
            else
                -- Not a Model or Folder (Accessory, Part, etc.) — ignore, continue
            end
        end
    end

    -- Scan enemyProjectiles if present
    local enemyProjectiles = ReplicatedStorage:FindFirstChild("enemyProjectiles")
    if enemyProjectiles and enemyProjectiles:IsA("Folder") then
        for _, enemyFolder in ipairs(enemyProjectiles:GetChildren()) do
            if enemyFolder:IsA("Folder") or enemyFolder:IsA("Model") then
                scanFolderRoot(enemyFolder, enemyFolder.Name)
            end
        end
    end

    -- Scan general projectiles
    local projectiles = ReplicatedStorage:FindFirstChild("projectiles")
    if projectiles and projectiles:IsA("Folder") then
        scanFolderRoot(projectiles, "General")
    end

    -- Also include top-level children that are Models directly under enemyProjectiles / projectiles
    warn("ProjectileDatabase built. Enemy groups:", (function()
        local count = 0
        for k in pairs(ProjectileDatabase) do count = count + 1 end
        return count
    end)())
end

-- ===== Monitor precasts (visual-only) =====
local ActivePrecasts = {}

local function getPrecastCFrame(precastObject)
    if not precastObject then return CFrame.new() end
    if precastObject:IsA("BasePart") then
        return precastObject.CFrame
    elseif precastObject:IsA("Model") then
        if precastObject.PrimaryPart then
            return precastObject.PrimaryPart.CFrame
        else
            local success, pivot = pcall(function() return precastObject:GetPivot() end)
            if success and pivot then
                return CFrame.new(pivot.Position)
            end
        end
    end
    return CFrame.new()
end

local function predictFromPrecast(precastInstance, enemyName, projectileName)
    -- Visual-only prediction & debug logging
    local template = PrecastDatabase[enemyName] and PrecastDatabase[enemyName][projectileName]
    if not template then return end

    local projectileTemplate = template.Parent -- usually parent is the projectile model
    if not projectileTemplate then return end

    local hitBox = projectileTemplate:FindFirstChild("hitBox") or projectileTemplate.PrimaryPart
    local movementPattern = MovementPatterns[projectileName] or { speed = 50, behavior = "straight" }

    local precastCFrame = getPrecastCFrame(precastInstance)
    local predictedTrajectory = calculateTrajectory(precastCFrame, movementPattern)

    -- create visual
    createDangerZoneVisual(predictedTrajectory, (hitBox and hitBox.Size) or Vector3.new(3,3,3))

    -- log to output for inspection
    warn("[Inspector] Precast detected:", enemyName, "->", projectileName, "movement:", movementPattern.behavior, movementPattern.speed)
end

local function monitorPrecasts()
    for enemyName, precasts in pairs(PrecastDatabase) do
        for projectileName, precastObject in pairs(precasts) do
            if precastObject and precastObject:IsA("Instance") then
                -- some precast objects are templates; monitor ChildAdded on templates being cloned into workspace
                precastObject.ChildAdded:Connect(function(child)
                    if child and (child:IsA("BasePart") or child:IsA("Model")) then
                        ActivePrecasts[child] = { enemy = enemyName, projectile = projectileName, startTime = tick() }
                        pcall(predictFromPrecast, child, enemyName, projectileName)
                    end
                end)
            end
        end
    end
end

-- ===== Monitor workspace for actual hitBox parts being spawned =====
local function monitorActiveHitboxes()
    Workspace.DescendantAdded:Connect(function(descendant)
        if not descendant then return end
        if descendant.Name == "hitBox" and descendant:IsA("BasePart") then
            -- attempt to identify its template by walking up the ancestry
            local ancestor = descendant.Parent
            while ancestor and ancestor ~= Workspace do
                for enemyName, projList in pairs(ProjectileDatabase) do
                    for _, projData in ipairs(projList) do
                        if projData.object and projData.object.Name == ancestor.Name then
                            warn("[Inspector] Hitbox spawned:", enemyName, "->", projData.name)
                            -- Visualize a marker on the spawned hitbox
                            local marker = Instance.new("Part")
                            marker.Name = "InspectorMarker"
                            marker.Anchored = true
                            marker.CanCollide = false
                            marker.CanTouch = false
                            marker.CanQuery = false
                            marker.Size = descendant.Size * 1.05
                            marker.Transparency = 0.7
                            marker.Material = Enum.Material.Neon
                            marker.Color = Color3.fromRGB(255, 150, 0)
                            marker.CFrame = descendant.CFrame
                            marker.Parent = Workspace
                            delay(1.6, function() pcall(function() marker:Destroy() end) end)
                            return
                        end
                    end
                end
                ancestor = ancestor.Parent
            end
        end
    end)
end

-- ===== Public small inspect functions =====
local function printSummary()
    print("----------- Projectile Inspector Summary -----------")
    for enemyName, list in pairs(ProjectileDatabase) do
        print("Enemy group:", enemyName, "- projectile count:", #list)
        for i, v in ipairs(list) do
            local hbSize = (v.hitBox and tostring(v.hitBox.Size)) or "nil"
            print(("  [%d] %s  hitBoxSize=%s  type=%s"):format(i, v.name or "<unnamed>", hbSize, v.type or "unknown"))
        end
    end

    print("Precast groups:")
    for enemyName, precs in pairs(PrecastDatabase) do
        for projName, p in pairs(precs) do
            print("  Precast:", enemyName, "->", projName, " (template parent)", tostring(p.Parent and p.Parent.Name or "<no parent>"))
        end
    end

    print("Movement patterns known:")
    for name, pat in pairs(MovementPatterns) do
        print("  ", name, pat.behavior, pat.speed, "homing=", tostring(pat.homing))
    end
    print("----------------------------------------------------")
end

-- ===== Initialization =====
local function initialize()
    warn("Projectile Inspector initializing... (safe mode)")
    buildProjectileDatabase()
    monitorPrecasts()
    monitorActiveHitboxes()
    warn("Projectile Inspector ready. Use printSummary() to log collected info.")
end

-- Auto-refresh database when folders added/changed
ReplicatedStorage.ChildAdded:Connect(function(child)
    if not child then return end
    if child.Name == "enemyProjectiles" or child.Name == "projectiles" then
        -- small delay so game can finish populating
        delay(0.8, function()
            pcall(buildProjectileDatabase)
        end)
    end
end)

-- Run initialization
initialize()

-- Expose debug function to global for user convenience
_G.ProjectileInspectorPrintSummary = printSummary
