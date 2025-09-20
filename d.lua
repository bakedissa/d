--[[
    Ultimate Projectile Avoidance System
    This script hooks into the game's projectile system to provide perfect dodging
    Place this in your exploit's auto-execute folder or run it manually
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

-- Check if we're in a supported environment
if not ReplicatedStorage:FindFirstChild("enemyProjectiles") and not ReplicatedStorage:FindFirstChild("projectiles") then
    warn("Projectile folders not found. Script may not work correctly.")
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
                            -- Check for hitboxes
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
                            
                            -- Check for precast objects
                            local precast = item:FindFirstChild("precast")
                            if precast then
                                PrecastDatabase[enemyName][item.Name] = precast
                            end
                            
                            -- Check for movement scripts
                            local movementScript = findMovementScript(item)
                            if movementScript then
                                MovementPatterns[item.Name] = extractMovementData(movementScript)
                            end
                            
                            -- Recursively scan subfolders
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
                    -- Check for hitboxes
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
                    
                    -- Check for precast objects
                    local precast = item:FindFirstChild("precast")
                    if precast then
                        PrecastDatabase["General"][item.Name] = precast
                    end
                    
                    -- Check for movement scripts
                    local movementScript = findMovementScript(item)
                    if movementScript then
                        MovementPatterns[item.Name] = extractMovementData(movementScript)
                    end
                    
                    -- Recursively scan subfolders
                    scanGeneralFolder(item)
                end
            end
        end
        
        scanGeneralFolder(projectiles)
    end
    
    warn("Projectile database built:", #ProjectileDatabase, "enemies tracked")
end

-- ===== MOVEMENT PATTERN ANALYSIS =====
local function findMovementScript(object)
    -- Look for scripts that might control movement
    for _, child in ipairs(object:GetDescendants()) do
        if child:IsA("Script") or child:IsA("LocalScript") then
            if child.Name:lower():find("move") or child.Name:lower():find("control") then
                return child
            end
        end
    end
    return nil
end

local function extractMovementData(script)
    -- Try to extract movement data from script properties
    local speed = script:FindFirstChild("Speed") and script.Speed.Value or 50
    local behavior = script:FindFirstChild("Behavior") and script.Behavior.Value or "straight"
    local homing = script:FindFirstChild("Homing") ~= nil
    local arc = script:FindFirstChild("Arc") ~= nil
    
    return {
        speed = speed,
        behavior = behavior,
        homing = homing,
        arc = arc
    }
end

-- ===== PRECAST MONITORING =====
local function monitorPrecasts()
    for enemyName, precasts in pairs(PrecastDatabase) do
        for projectileName, precastObject in pairs(precasts) do
            -- Monitor when precast objects are cloned into workspace
            precastObject.ChildAdded:Connect(function(child)
                if child:IsA("BasePart") or child:IsA("Model") then
                    ActivePrecasts[child] = {
                        enemy = enemyName,
                        projectile = projectileName,
                        startTime = tick()
                    }
                    predictFromPrecast(child, enemyName, projectileName)
                end
            end)
        end
    end
end

local function predictFromPrecast(precastObject, enemyName, projectileName)
    -- Get the actual projectile template
    local projectileTemplate = PrecastDatabase[enemyName][projectileName].Parent
    
    if projectileTemplate and (projectileTemplate:FindFirstChild("hitBox") or projectileTemplate.PrimaryPart) then
        local hitBox = projectileTemplate:FindFirstChild("hitBox") or projectileTemplate.PrimaryPart
        local movementPattern = MovementPatterns[projectileName] or {speed = 50, behavior = "straight"}
        
        -- Analyze precast position/orientation
        local precastCFrame = getPrecastCFrame(precastObject)
        
        -- Predict final projectile trajectory
        local predictedTrajectory = calculateTrajectory(
            precastCFrame,
            movementPattern
        )
        
        -- Create danger zone visualization
        createDangerZone(predictedTrajectory, enemyName, projectileName, hitBox.Size)
        
        -- Set up auto-dodge
        setupAutoDodge(predictedTrajectory, projectileName, hitBox.Size)
    end
end

local function getPrecastCFrame(precastObject)
    if precastObject:IsA("BasePart") then
        return precastObject.CFrame
    elseif precastObject:IsA("Model") and precastObject.PrimaryPart then
        return precastObject.PrimaryPart.CFrame
    else
        -- Fallback to position only
        return CFrame.new(precastObject:GetPivot().Position)
    end
end

-- ===== PROJECTILE CAST HOOKING =====
local function hookProjectileCast()
    local success, projectileCastModule = pcall(function()
        return require(ReplicatedStorage:WaitForChild("ProjectileCast"))
    end)
    
    if not success then
        warn("ProjectileCast module not found or couldn't be required")
        return
    end
    
    -- Hook the new method
    local originalNew = projectileCastModule.new
    projectileCastModule.new = function(...)
        local projectileCast = originalNew(...)
        
        -- Extract information from the cast
        local castInfo = projectileCast.castInfo
        if castInfo and castInfo.projectile then
            local projectile = castInfo.projectile
            local projectileName = projectile.Name
            
            -- Track this projectile
            ActiveProjectiles[projectile] = {
                cast = projectileCast,
                info = castInfo,
                startTime = tick(),
                positions = {},
                velocities = {}
            }
            
            -- Monitor updates
            projectileCast.events.updated:Connect(function(updatedCastInfo, cframe)
                local currentTime = tick()
                local position = cframe.Position
                
                if ActiveProjectiles[projectile] then
                    table.insert(ActiveProjectiles[projectile].positions, {
                        time = currentTime,
                        position = position,
                        cframe = cframe
                    })
                    
                    -- Predict future path
                    predictFuturePath(projectile, position, cframe, castInfo.initialVelocity, castInfo.acceleration)
                end
            end)
            
            -- Clean up when stopped
            projectileCast.events.stopped:Connect(function()
                ActiveProjectiles[projectile] = nil
            end)
        end
        
        return projectileCast
    end
    
    warn("ProjectileCast hooked successfully")
end

-- ===== TRAJECTORY PREDICTION =====
local function calculateTrajectory(cframe, movementPattern)
    local direction = cframe.LookVector
    local speed = movementPattern.speed or 50
    local behavior = movementPattern.behavior or "straight"
    
    if behavior == "straight" then
        return {
            type = "linear",
            origin = cframe.Position,
            direction = direction,
            speed = speed,
            startTime = tick()
        }
    elseif behavior == "arc" then
        return {
            type = "parabolic",
            origin = cframe.Position,
            direction = direction,
            speed = speed,
            gravity = Vector3.new(0, -workspace.Gravity/196.2, 0), -- Approximate gravity
            startTime = tick()
        }
    elseif behavior == "homing" then
        return {
            type = "homing",
            origin = cframe.Position,
            direction = direction,
            speed = speed,
            startTime = tick(),
            target = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        }
    end
    
    return nil
end

local function predictFuturePath(projectile, currentPos, currentCframe, initialVel, acceleration)
    local projectileData = ActiveProjectiles[projectile]
    if not projectileData then return end
    
    -- Calculate current velocity
    local currentTime = tick() - projectileData.startTime
    local currentVel = initialVel + acceleration * currentTime
    
    -- Predict next positions
    local predictedPath = {}
    for t = 0.1, 2, 0.1 do
        local futurePos = currentPos + currentVel * t + 0.5 * acceleration * t * t
        local futureVel = currentVel + acceleration * t
        
        predictedPath[#predictedPath + 1] = {
            position = futurePos,
            time = tick() + t,
            velocity = futureVel
        }
    end
    
    -- Update danger zones
    updateDangerZones(projectile, predictedPath, projectileData.info.projectile)
end

-- ===== DANGER ZONE VISUALIZATION =====
local function createDangerZone(trajectory, enemyName, projectileName, hitBoxSize)
    if not trajectory then return end
    
    -- Create visual representation of danger zone
    local part = Instance.new("Part")
    part.Anchored = true
    part.CanCollide = false
    part.Transparency = 0.7
    part.Color = Color3.fromRGB(255, 0, 0)
    part.Material = Enum.Material.Neon
    part.Size = hitBoxSize or Vector3.new(5, 5, 5)
    
    if trajectory.type == "linear" then
        -- Create a long part showing the path
        local distance = trajectory.speed * 2 -- Show 2 seconds of travel
        part.Size = Vector3.new(2, 2, distance)
        part.CFrame = CFrame.new(trajectory.origin + trajectory.direction * distance/2, trajectory.origin + trajectory.direction * distance)
    elseif trajectory.type == "parabolic" then
        -- Create a curved path (simplified)
        part.CFrame = CFrame.new(trajectory.origin)
        part.Size = Vector3.new(10, 10, 10)
    elseif trajectory.type == "homing" then
        -- Create a sphere around player
        part.Shape = Enum.PartType.Ball
        part.Size = Vector3.new(8, 8, 8)
        part.CFrame = CFrame.new(trajectory.target and trajectory.target.Position or trajectory.origin)
    end
    
    part.Parent = Workspace
    
    -- Remove after a short time
    delay(2, function()
        if part then
            part:Destroy()
        end
    end)
end

local function updateDangerZones(projectile, predictedPath, projectileObject)
    -- This would update existing danger zones with new predictions
    -- Implementation depends on how you want to visualize multiple projectiles
end

-- ===== AUTO-DODGE SYSTEM =====
local function calculateSafeSpots(playerPos, trajectory, hitBoxSize)
    local safeSpots = {}
    
    if trajectory.type == "linear" then
        -- Find positions perpendicular to the trajectory
        local right = trajectory.direction:Cross(Vector3.new(0, 1, 0)).Unit
        local left = -right
        
        safeSpots = {
            playerPos + right * (hitBoxSize.X + 5),
            playerPos + left * (hitBoxSize.X + 5)
        }
    elseif trajectory.type == "parabolic" then
        -- For parabolic, just move away from the impact point
        local impactPoint = trajectory.origin + trajectory.direction * trajectory.speed * 1.5
        local awayDirection = (playerPos - impactPoint).Unit
        
        safeSpots = {
            playerPos + awayDirection * 10
        }
    elseif trajectory.type == "homing" then
        -- For homing, move perpendicular to the direction to target
        if trajectory.target then
            local toTarget = (trajectory.target.Position - playerPos).Unit
            local right = toTarget:Cross(Vector3.new(0, 1, 0)).Unit
            local left = -right
            
            safeSpots = {
                playerPos + right * 10,
                playerPos + left * 10
            }
        end
    end
    
    return safeSpots
end

local function isPositionSafe(position, safeSpots, threshold)
    threshold = threshold or 5
    for _, safeSpot in ipairs(safeSpots) do
        if (position - safeSpot).Magnitude < threshold then
            return true
        end
    end
    return false
end

local function findBestEscapeRoute(playerPos, safeSpots)
    -- Find the closest safe spot
    local bestSpot = nil
    local bestDistance = math.huge
    
    for _, spot in ipairs(safeSpots) do
        local distance = (playerPos - spot).Magnitude
        if distance < bestDistance then
            bestDistance = distance
            bestSpot = spot
        end
    end
    
    return (bestSpot - playerPos).Unit
end

local function executeDodge(direction)
    local character = LocalPlayer.Character
    if not character then return end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    
    if humanoid and humanoidRootPart then
        -- Use exploit methods to move character
        if setcharacter then
            setcharacter(humanoidRootPart.Position + direction * 10)
        elseif sethumanoid then
            sethumanoid("MoveDirection", direction)
        elseif setwalk then
            setwalk(direction * 10)
        else
            -- Fallback: use humanoid movement
            humanoid:MoveTo(humanoidRootPart.Position + direction * 10)
        end
    end
end

local function setupAutoDodge(trajectory, projectileName, hitBoxSize)
    local movementPattern = MovementPatterns[projectileName] or {speed = 50, behavior = "straight"}
    
    local connection
    connection = RunService.Heartbeat:Connect(function()
        local character = LocalPlayer.Character
        local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
        
        if not humanoidRootPart or not trajectory then
            connection:Disconnect()
            return
        end
        
        local playerPos = humanoidRootPart.Position
        local safeSpots = calculateSafeSpots(playerPos, trajectory, hitBoxSize)
        
        if not isPositionSafe(playerPos, safeSpots, hitBoxSize.X + 2) then
            local bestEscape = findBestEscapeRoute(playerPos, safeSpots)
            executeDodge(bestEscape)
            connection:Disconnect()  -- Stop dodging after one move
        end
    end)
end

-- ===== MAIN INITIALIZATION =====
local function initialize()
    warn("Initializing Ultimate Projectile Avoidance System...")
    
    -- Build projectile database
    buildProjectileDatabase()
    
    -- Hook into ProjectileCast system
    hookProjectileCast()
    
    -- Monitor precasts
    monitorPrecasts()
    
    -- Monitor workspace for active hitboxes
    Workspace.DescendantAdded:Connect(function(descendant)
        if descendant.Name == "hitBox" and descendant:IsA("BasePart") then
            -- Try to find which projectile this belongs to
            for enemyName, projectiles in pairs(ProjectileDatabase) do
                for _, projData in ipairs(projectiles) do
                    if projData.hitBox == descendant or descendant:IsDescendantOf(projData.object) then
                        warn("Hitbox spawned:", enemyName, "->", projData.name)
                        -- You could add tracking for these hitboxes too
                        break
                    end
                end
            end
        end
    end)
    
    warn("Ultimate Projectile Avoidance System initialized successfully!")
end

-- Start the system
initialize()

-- Auto-update when new projectiles are added
ReplicatedStorage.ChildAdded:Connect(function(child)
    if child.Name == "enemyProjectiles" or child.Name == "projectiles" then
        delay(1, function() buildProjectileDatabase() end)
    end
end)

-- Keep the script running
while true do
    -- Clean up old projectiles
    for projectile, data in pairs(ActiveProjectiles) do
        if not data.cast or not data.cast.stateInfo or not data.cast.stateInfo.active then
            ActiveProjectiles[projectile] = nil
        end
    end
    
    -- Clean up old precasts
    for precast, data in pairs(ActivePrecasts) do
        if tick() - data.startTime > 10 then  -- 10 second timeout
            ActivePrecasts[precast] = nil
        end
    end
    
    task.wait(5)
end
