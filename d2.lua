--[[
    Ultimate Projectile Avoidance System (Reordered / Fixed)
    This script hooks into the game's projectile system to provide perfect dodging.
    Place this in your exploit's auto-execute folder or run it manually.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- Initialize variables
local LocalPlayer = Players.LocalPlayer
local ProjectileDatabase = {}
local ActiveProjectiles = {}
local PrecastDatabase = {}
local ActivePrecasts = {}
local MovementPatterns = {}

-- ===== MOVEMENT PATTERN ANALYSIS =====
local function findMovementScript(object)
    for _, child in ipairs(object:GetDescendants()) do
        if child:IsA("Script") or child:IsA("LocalScript") then
            local name = child.Name:lower()
            if name:find("move") or name:find("control") then
                return child
            end
        end
    end
    return nil
end

local function extractMovementData(script)
    -- Defensive: script might not have the expected children
    local speed = 50
    local behavior = "straight"
    local homing = false
    local arc = false

    if script then
        if script:FindFirstChild("Speed") and script.Speed.Value then
            speed = script.Speed.Value
        end
        if script:FindFirstChild("Behavior") and script.Behavior.Value then
            behavior = script.Behavior.Value
        end
        homing = script:FindFirstChild("Homing") ~= nil
        arc = script:FindFirstChild("Arc") ~= nil
    end

    return {
        speed = speed,
        behavior = behavior,
        homing = homing,
        arc = arc
    }
end

-- ===== UTILITY HELPERS USED IN PREDICTION / DODGING =====
local function getPrecastCFrame(precastObject)
    if not precastObject then return CFrame.new() end
    if precastObject:IsA("BasePart") then
        return precastObject.CFrame
    elseif precastObject:IsA("Model") and precastObject.PrimaryPart then
        return precastObject.PrimaryPart.CFrame
    else
        -- Fallback: use pivot if available
        local success, pivot = pcall(function() return precastObject:GetPivot() end)
        if success and pivot then
            return CFrame.new(pivot.Position)
        end
        return CFrame.new()
    end
end

local function calculateTrajectory(cframe, movementPattern)
    if not cframe or not movementPattern then return nil end
    local direction = cframe.LookVector or Vector3.new(0,0,1)
    local speed = movementPattern.speed or 50
    local behavior = movementPattern.behavior or "straight"

    if behavior == "straight" then
        return {
            type = "linear",
            origin = cframe.Position,
            direction = direction.Unit,
            speed = speed,
            startTime = tick()
        }
    elseif behavior == "arc" or movementPattern.arc then
        return {
            type = "parabolic",
            origin = cframe.Position,
            direction = direction.Unit,
            speed = speed,
            gravity = Vector3.new(0, -Workspace.Gravity/196.2, 0), -- Approximate scaling
            startTime = tick()
        }
    elseif behavior == "homing" or movementPattern.homing then
        return {
            type = "homing",
            origin = cframe.Position,
            direction = direction.Unit,
            speed = speed,
            startTime = tick(),
            target = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        }
    end

    return nil
end

local function calculateSafeSpots(playerPos, trajectory, hitBoxSize)
    local safeSpots = {}

    if not trajectory or not playerPos then
        return safeSpots
    end

    if trajectory.type == "linear" then
        local right = trajectory.direction:Cross(Vector3.new(0, 1, 0))
        if right.Magnitude == 0 then
            right = Vector3.new(1, 0, 0)
        else
            right = right.Unit
        end
        local left = -right
        local offset = (hitBoxSize and hitBoxSize.X or 3) + 5

        table.insert(safeSpots, playerPos + right * offset)
        table.insert(safeSpots, playerPos + left * offset)

    elseif trajectory.type == "parabolic" then
        local impactPoint = trajectory.origin + trajectory.direction * (trajectory.speed * 1.5)
        local awayDirection = (playerPos - impactPoint)
        if awayDirection.Magnitude == 0 then
            awayDirection = Vector3.new(0, 0, 1)
        else
            awayDirection = awayDirection.Unit
        end
        table.insert(safeSpots, playerPos + awayDirection * 10)

    elseif trajectory.type == "homing" then
        if trajectory.target then
            local toTarget = (trajectory.target.Position - playerPos)
            if toTarget.Magnitude == 0 then
                toTarget = Vector3.new(0, 0, 1)
            else
                toTarget = toTarget.Unit
            end
            local right = toTarget:Cross(Vector3.new(0, 1, 0)).Unit
            local left = -right

            table.insert(safeSpots, playerPos + right * 10)
            table.insert(safeSpots, playerPos + left * 10)
        end
    end

    return safeSpots
end

local function isPositionSafe(position, safeSpots, threshold)
    threshold = threshold or 5
    if not position then return false end
    for _, safeSpot in ipairs(safeSpots) do
        if (position - safeSpot).Magnitude < threshold then
            return true
        end
    end
    return false
end

local function findBestEscapeRoute(playerPos, safeSpots)
    local bestSpot = nil
    local bestDistance = math.huge

    for _, spot in ipairs(safeSpots) do
        local distance = (playerPos - spot).Magnitude
        if distance < bestDistance then
            bestDistance = distance
            bestSpot = spot
        end
    end

    if not bestSpot then
        return Vector3.new(0,0,0)
    end

    local delta = (bestSpot - playerPos)
    if delta.Magnitude == 0 then
        return Vector3.new(0,0,0)
    end
    return delta.Unit
end

local function executeDodge(direction)
    if not direction or direction.Magnitude == 0 then return end
    local character = LocalPlayer and LocalPlayer.Character
    if not character then return end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")

    if humanoid and humanoidRootPart then
        -- Use available exploit movement helpers if present (kept as-is)
        if setcharacter then
            -- setcharacter usually teleports the character - keep existing behavior
            setcharacter(humanoidRootPart.Position + direction * 10)
        elseif sethumanoid then
            pcall(sethumanoid, "MoveDirection", direction)
        elseif setwalk then
            pcall(setwalk, direction * 10)
        else
            -- Best-effort fallback: MoveTo
            pcall(function()
                humanoid:MoveTo(humanoidRootPart.Position + direction * 10)
            end)
        end
    end
end

-- ===== DANGER ZONE VISUALIZATION =====
local function createDangerZone(trajectory, enemyName, projectileName, hitBoxSize)
    if not trajectory then return end
    local part = Instance.new("Part")
    part.Anchored = true
    part.CanCollide = false
    part.Transparency = 0.7
    part.Color = Color3.fromRGB(255, 0, 0)
    part.Material = Enum.Material.Neon
    part.Size = hitBoxSize or Vector3.new(5, 5, 5)

    if trajectory.type == "linear" then
        local distance = trajectory.speed * 2 -- visualize two seconds
        part.Size = Vector3.new(2, 2, math.max(1, distance))
        -- create CFrame pointing along direction; use mid-point
        part.CFrame = CFrame.new(trajectory.origin + trajectory.direction * (distance / 2), trajectory.origin + trajectory.direction * distance)
    elseif trajectory.type == "parabolic" then
        part.Size = Vector3.new(10, 10, 10)
        part.CFrame = CFrame.new(trajectory.origin)
    elseif trajectory.type == "homing" then
        part.Shape = Enum.PartType.Ball
        part.Size = Vector3.new(8, 8, 8)
        part.CFrame = CFrame.new((trajectory.target and trajectory.target.Position) or trajectory.origin)
    end

    part.Parent = Workspace

    delay(2, function()
        if part and part.Parent then
            pcall(function() part:Destroy() end)
        end
    end)
end

local function updateDangerZones(projectile, predictedPath, projectileObject)
    -- Placeholder: update existing visuals / pooling logic could go here
    -- For now, do nothing or extend for your visualization needs.
end

-- ===== FUTURE PATH PREDICTION =====
local function predictFuturePath(projectile, currentPos, currentCframe, initialVel, acceleration)
    local projectileData = ActiveProjectiles[projectile]
    if not projectileData then return end

    -- Defensive defaults
    initialVel = initialVel or Vector3.new(0,0,0)
    acceleration = acceleration or Vector3.new(0, Workspace.Gravity * -1, 0) * 0 -- default none

    local currentTime = tick() - projectileData.startTime
    local currentVel = initialVel + acceleration * currentTime

    local predictedPath = {}
    for t = 0.1, 2, 0.1 do
        local futurePos = currentPos + currentVel * t + 0.5 * acceleration * t * t
        local futureVel = currentVel + acceleration * t

        table.insert(predictedPath, {
            position = futurePos,
            time = tick() + t,
            velocity = futureVel
        })
    end

    updateDangerZones(projectile, predictedPath, projectileData.info and projectileData.info.projectile)
end

-- ===== PRECAST PREDICTION =====
local function predictFromPrecast(precastObject, enemyName, projectileName)
    if not (PrecastDatabase and PrecastDatabase[enemyName] and PrecastDatabase[enemyName][projectileName]) then
        return
    end

    local projectileTemplate = PrecastDatabase[enemyName][projectileName].Parent
    if not projectileTemplate then return end

    local hitBox = projectileTemplate:FindFirstChild("hitBox") or projectileTemplate.PrimaryPart
    local movementPattern = MovementPatterns[projectileName] or {speed = 50, behavior = "straight"}

    local precastCFrame = getPrecastCFrame(precastObject)
    local predictedTrajectory = calculateTrajectory(precastCFrame, movementPattern)

    createDangerZone(predictedTrajectory, enemyName, projectileName, (hitBox and hitBox.Size) or Vector3.new(3,3,3))
    setupAutoDodge(predictedTrajectory, projectileName, (hitBox and hitBox.Size) or Vector3.new(3,3,3))
end

local function monitorPrecasts()
    for enemyName, precasts in pairs(PrecastDatabase) do
        for projectileName, precastObject in pairs(precasts) do
            if precastObject and precastObject:IsA("Instance") then
                precastObject.ChildAdded:Connect(function(child)
                    if child:IsA("BasePart") or child:IsA("Model") then
                        ActivePrecasts[child] = {
                            enemy = enemyName,
                            projectile = projectileName,
                            startTime = tick()
                        }
                        pcall(predictFromPrecast, child, enemyName, projectileName)
                    end
                end)
            end
        end
    end
end

-- ===== AUTO-DODGE SYSTEM =====
local function setupAutoDodge(trajectory, projectileName, hitBoxSize)
    if not trajectory then return end

    local connection
    connection = RunService.Heartbeat:Connect(function()
        local character = LocalPlayer and LocalPlayer.Character
        local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")

        if not humanoidRootPart or not trajectory then
            if connection and connection.Disconnect then
                connection:Disconnect()
            end
            return
        end

        local playerPos = humanoidRootPart.Position
        local safeSpots = calculateSafeSpots(playerPos, trajectory, hitBoxSize)

        if not isPositionSafe(playerPos, safeSpots, (hitBoxSize and hitBoxSize.X) and (hitBoxSize.X + 2) or 5) then
            local bestEscape = findBestEscapeRoute(playerPos, safeSpots)
            if bestEscape and bestEscape.Magnitude > 0 then
                executeDodge(bestEscape)
            end
            if connection and connection.Disconnect then
                connection:Disconnect()
            end
        end
    end)
end

-- ===== PROJECTILE DATABASE BUILDING =====
local function buildProjectileDatabase()
    ProjectileDatabase = {}
    PrecastDatabase = {}
    MovementPatterns = {}

    -- Scan enemy projectiles folder
    local enemyProjectiles = ReplicatedStorage:FindFirstChild("enemyProjectiles")
    if enemyProjectiles then
        for _, enemyFolder in ipairs(enemyProjectiles:GetChildren()) do
            if enemyFolder:IsA("Folder") then
                ProjectileDatabase[enemyFolder.Name] = {}
                PrecastDatabase[enemyFolder.Name] = {}

                local function scanFolder(folder, enemyName)
                    for _, item in ipairs(folder:GetChildren()) do
                        if item:IsA("Model") or item:IsA("Folder") then
                            local hitBox = item:FindFirstChild("hitBox")
                            local primaryPart = item.PrimaryPart

                            if hitBox and hitBox:IsA("BasePart") then
                                table.insert(ProjectileDatabase[enemyName], {
                                    object = item,
                                    hitBox = hitBox,
                                    type = "direct",
                                    name = item.Name
                                })
                            elseif primaryPart and primaryPart:IsA("BasePart") then
                                table.insert(ProjectileDatabase[enemyName], {
                                    object = item,
                                    hitBox = primaryPart,
                                    type = "primary",
                                    name = item.Name
                                })
                            end

                            local precast = item:FindFirstChild("precast")
                            if precast then
                                PrecastDatabase[enemyName][item.Name] = precast
                            end

                            local movementScript = findMovementScript(item)
                            if movementScript then
                                MovementPatterns[item.Name] = extractMovementData(movementScript)
                            end

                            -- Recurse
                            scanFolder(item, enemyName)
                        end
                    end
                end

                scanFolder(enemyFolder, enemyFolder.Name)
            end
        end
    end

    -- Scan general projectiles folder
    local projectiles = ReplicatedStorage:FindFirstChild("projectiles")
    if projectiles then
        ProjectileDatabase["General"] = {}
        PrecastDatabase["General"] = {}

        local function scanGeneralFolder(folder)
            for _, item in ipairs(folder:GetChildren()) do
                if item:IsA("Model") or item:IsA("Folder") then
                    local hitBox = item:FindFirstChild("hitBox")
                    local primaryPart = item.PrimaryPart

                    if hitBox and hitBox:IsA("BasePart") then
                        table.insert(ProjectileDatabase["General"], {
                            object = item,
                            hitBox = hitBox,
                            type = "direct",
                            name = item.Name
                        })
                    elseif primaryPart and primaryPart:IsA("BasePart") then
                        table.insert(ProjectileDatabase["General"], {
                            object = item,
                            hitBox = primaryPart,
                            type = "primary",
                            name = item.Name
                        })
                    end

                    local precast = item:FindFirstChild("precast")
                    if precast then
                        PrecastDatabase["General"][item.Name] = precast
                    end

                    local movementScript = findMovementScript(item)
                    if movementScript then
                        MovementPatterns[item.Name] = extractMovementData(movementScript)
                    end

                    scanGeneralFolder(item)
                end
            end
        end

        scanGeneralFolder(projectiles)
    end

    warn("Projectile database built for " .. tostring(#ProjectileDatabase) .. " top-level entries")
end

-- ===== PROJECTILE CAST HOOKING =====
local function hookProjectileCast()
    local success, projectileCastModule = pcall(function()
        return require(ReplicatedStorage:WaitForChild("ProjectileCast"))
    end)

    if not success or not projectileCastModule then
        warn("ProjectileCast module not found or couldn't be required")
        return
    end

    local originalNew = projectileCastModule.new
    projectileCastModule.new = function(...)
        local projectileCast = originalNew(...)
        if not projectileCast then
            return projectileCast
        end

        local castInfo = projectileCast.castInfo
        if castInfo and castInfo.projectile then
            local projectile = castInfo.projectile
            local projectileName = projectile and projectile.Name or "Unknown"

            ActiveProjectiles[projectile] = {
                cast = projectileCast,
                info = castInfo,
                startTime = tick(),
                positions = {},
                velocities = {}
            }

            if projectileCast.events and projectileCast.events.updated then
                projectileCast.events.updated:Connect(function(updatedCastInfo, cframe)
                    local currentTime = tick()
                    local position = cframe and cframe.Position or (updatedCastInfo and updatedCastInfo.position) or Vector3.new(0,0,0)

                    if ActiveProjectiles[projectile] then
                        table.insert(ActiveProjectiles[projectile].positions, {
                            time = currentTime,
                            position = position,
                            cframe = cframe
                        })

                        pcall(predictFuturePath, projectile, position, cframe, castInfo.initialVelocity, castInfo.acceleration)
                    end
                end)
            end

            if projectileCast.events and projectileCast.events.stopped then
                projectileCast.events.stopped:Connect(function()
                    ActiveProjectiles[projectile] = nil
                end)
            end
        end

        return projectileCast
    end

    warn("ProjectileCast hooked successfully")
end

-- ===== INITIALIZATION & LISTENERS =====
local function initialize()
    warn("Initializing Ultimate Projectile Avoidance System...")

    buildProjectileDatabase()
    hookProjectileCast()
    monitorPrecasts()

    Workspace.DescendantAdded:Connect(function(descendant)
        if descendant and descendant.Name == "hitBox" and descendant:IsA("BasePart") then
            for enemyName, projectiles in pairs(ProjectileDatabase) do
                for _, projData in ipairs(projectiles) do
                    if projData and (projData.hitBox == descendant or descendant:IsDescendantOf(projData.object)) then
                        warn("Hitbox spawned:", enemyName, "->", projData.name)
                        break
                    end
                end
            end
        end
    end)

    warn("Ultimate Projectile Avoidance System initialized successfully!")
end

-- Auto-update when new projectile folders appear
ReplicatedStorage.ChildAdded:Connect(function(child)
    if child and (child.Name == "enemyProjectiles" or child.Name == "projectiles") then
        delay(1, function()
            pcall(buildProjectileDatabase)
        end)
    end
end)

-- Start the system
initialize()

-- ===== MAIN MAINTENANCE LOOP =====
coroutine.wrap(function()
    while true do
        -- Clean up inactive projectiles
        for projectile, data in pairs(ActiveProjectiles) do
            local ok, isActive = pcall(function()
                return data.cast and data.cast.stateInfo and data.cast.stateInfo.active
            end)
            if not ok or not isActive then
                ActiveProjectiles[projectile] = nil
            end
        end

        -- Clean up timed-out precasts
        for precast, data in pairs(ActivePrecasts) do
            if tick() - (data.startTime or 0) > 10 then
                ActivePrecasts[precast] = nil
            end
        end

        task.wait(5)
    end
end)()
