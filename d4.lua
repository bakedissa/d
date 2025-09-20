--[[ 
    Ultimate Auto-Dodge Script
    Dodges ALL projectiles using ProjectileCast + projectile folders
    Teleports player sideways out of attack path
]]

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local LP = Players.LocalPlayer

local ActiveProjectiles = {}

-- === UTILITIES ===
local function getHRP()
    local char = LP.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function safeTeleport(newPos)
    local hrp = getHRP()
    if not hrp then return end
    
    -- Exploit-provided function preferred if available
    if setcharacter then
        setcharacter(newPos)
    elseif setpos then
        setpos(newPos)
    else
        hrp.CFrame = CFrame.new(newPos)
    end
end

local function perpendicularDodge(projectilePos, velocity, hrpPos, distance)
    distance = distance or 15
    local dir = velocity.Unit
    local side = dir:Cross(Vector3.new(0,1,0)).Unit
    local dodgeRight = hrpPos + side * distance
    local dodgeLeft = hrpPos - side * distance

    -- Pick side farther from projectile
    if (projectilePos - dodgeRight).Magnitude > (projectilePos - dodgeLeft).Magnitude then
        return dodgeRight
    else
        return dodgeLeft
    end
end

-- === DODGE CHECK ===
local function checkAndDodge(projData)
    local hrp = getHRP()
    if not hrp then return end

    local projPos = projData.Position
    local vel = projData.Velocity
    if not vel or vel.Magnitude == 0 then return end

    -- Predict line of travel
    local toPlayer = (hrp.Position - projPos)
    local travelDir = vel.Unit
    local dot = toPlayer.Unit:Dot(travelDir)

    -- If dot ~ 1, projectile is heading at player
    if dot > 0.85 then
        local newPos = perpendicularDodge(projPos, vel, hrp.Position)
        safeTeleport(newPos)
    end
end

-- === HOOK PROJECTILECAST ===
local function hookProjectileCast()
    local success, ProjectileCast = pcall(function()
        return require(RS:WaitForChild("ProjectileCast"))
    end)
    if not success then
        warn("ProjectileCast not found.")
        return
    end

    local oldNew = ProjectileCast.new
    ProjectileCast.new = function(origin, dir, speed, config, callbacks)
        local cast = oldNew(origin, dir, speed, config, callbacks)

        cast.events.updated:Connect(function(info, cframe)
            ActiveProjectiles[cast] = {
                Position = cframe.Position,
                Velocity = info.initialVelocity,
                Start = tick()
            }
            checkAndDodge(ActiveProjectiles[cast])
        end)

        cast.events.stopped:Connect(function()
            ActiveProjectiles[cast] = nil
        end)

        return cast
    end
    warn("ProjectileCast hooked.")
end

-- === WATCH PROJECTILE FOLDERS TOO ===
local function watchProjectileFolders()
    local function track(desc)
        if desc:IsA("BasePart") and desc.Name:lower():find("hitbox") then
            RunService.Heartbeat:Once(function()
                if desc:IsDescendantOf(Workspace) then
                    local vel = desc.AssemblyLinearVelocity
                    ActiveProjectiles[desc] = {
                        Position = desc.Position,
                        Velocity = vel,
                        Start = tick()
                    }
                end
            end)
        end
    end

    for _, folderName in ipairs({"enemyProjectiles","projectiles"}) do
        local folder = RS:FindFirstChild(folderName)
        if folder then
            folder.DescendantAdded:Connect(track)
        end
    end
end

-- === INIT ===
hookProjectileCast()
watchProjectileFolders()
warn("Auto-Dodge System Loaded")
