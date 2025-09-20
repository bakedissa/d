-- Projectile Dodger (client)
-- Place as a LocalScript in StarterPlayer -> StarterPlayerScripts
-- Tweaks at the top.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local CHAR_CHECK_INTERVAL = 0.5

-- Config: tweak these
local THREAT_TIME_HORIZON = 1.2         -- seconds ahead to consider a threat
local MIN_THREAT_TIME = 0.05            -- ignore threats that would hit "now" (floating point)
local DODGE_FORCE_MAG = 1250            -- magnitude of dodge impulse
local DODGE_DURATION = 0.12             -- seconds to apply force
local MAX_PROJECTILE_AGE = 10           -- seconds before we stop tracking
local TRACKING_SMOOTH = 0.2             -- smoothing for velocity estimation
local CHECK_PROJECTILE_NAME_FOLDERS = { -- optional: names of ReplicatedStorage folders that contain templates
    "enemyProjectiles",
    "projectiles"
}

-- Helpers
local function isPotentialProjectileModel(model)
    if not model or not model:IsA("Model") then return false end
    -- Quick heuristics: has PrimaryPart OR a child named "Hitbox" OR has any BasePart and is not a standard character
    if model.PrimaryPart then return true end
    if model:FindFirstChild("Hitbox") and model.Hitbox:IsA("BasePart") then return true end
    for _, v in ipairs(model:GetChildren()) do
        if v:IsA("BasePart") then
            -- avoid tagging characters (look for Humanoid)
            if not model:FindFirstChildOfClass("Humanoid") then
                return true
            end
        end
    end
    -- optional: if the model name matches a template folder contents
    return false
end

local function getRepresentativePart(model)
    if not model then return nil end
    if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
        return model.PrimaryPart
    end
    local hit = model:FindFirstChild("Hitbox")
    if hit and hit:IsA("BasePart") then return hit end
    -- pick biggest part (by volume)
    local best, bestVol = nil, 0
    for _, p in ipairs(model:GetDescendants()) do
        if p:IsA("BasePart") then
            local vol = math.abs(p.Size.X * p.Size.Y * p.Size.Z)
            if vol > bestVol then
                best, bestVol = p, vol
            end
        end
    end
    return best
end

local function getBoundingRadiusForPart(part)
    if not part then return 1 end
    -- conservative: use half max dimension
    local s = part.Size
    return math.max(s.X, s.Y, s.Z) * 0.5
end

-- Projectile tracker
local tracked = {} -- model -> data

local function trackNewProjectile(model)
    if not model or not model.Parent then return end
    if tracked[model] then return end
    local rep = getRepresentativePart(model)
    if not rep then return end
    local now = tick()
    local data = {
        model = model;
        part = rep;
        createdAt = now;
        lastPos = rep.Position;
        velocity = Vector3.new(0,0,0);
        lastUpdate = now;
        hitRadius = getBoundingRadiusForPart(rep);
        threat = false;
        age = 0;
    }
    tracked[model] = data
end

-- Untrack cleaning
local function untrackProjectile(model)
    tracked[model] = nil
end

-- Optionally, seed tracking by scanning workspace initially
for _, obj in ipairs(workspace:GetDescendants()) do
    if obj:IsA("Model") and isPotentialProjectileModel(obj) then
        trackNewProjectile(obj)
    end
end

-- Also watch for new Models added to workspace
workspace.DescendantAdded:Connect(function(desc)
    if desc:IsA("Model") then
        if isPotentialProjectileModel(desc) then
            -- slight delay to let PrimaryPart be set if created in script
            task.delay(0.01, function()
                if desc.Parent then
                    trackNewProjectile(desc)
                end
            end)
        end
    elseif desc:IsA("BasePart") and desc.Parent and desc.Parent:IsA("Model") then
        -- sometimes only the part is added, track parent model
        local m = desc.Parent
        if isPotentialProjectileModel(m) then
            task.delay(0.01, function() if m.Parent then trackNewProjectile(m) end end)
        end
    end
end)

-- remove when models die
workspace.DescendantRemoving:Connect(function(desc)
    if desc:IsA("Model") then
        if tracked[desc] then untrackProjectile(desc) end
    elseif desc:IsA("BasePart") and desc.Parent and desc.Parent:IsA("Model") then
        local m = desc.Parent
        if tracked[m] then
            -- re-evaluate representative part
            local newRep = getRepresentativePart(m)
            if not newRep then untrackProjectile(m) else tracked[m].part = newRep end
        end
    end
end)

-- Utility: perpendicular dodge direction
local function getDodgeDirection(projVel, hitPoint, hrpPos)
    -- Try to dodge perpendicular to projectile direction, choose side that increases distance
    local forward = projVel.Unit
    if forward.Magnitude == 0 then
        -- if stationary, push away from hitpoint
        return (hrpPos - hitPoint).Unit
    end
    -- pick an arbitrary perpendicular: cross with world up then normalize
    local up = Vector3.new(0,1,0)
    local perp = forward:Cross(up)
    if perp.Magnitude < 0.1 then
        up = Vector3.new(1,0,0)
        perp = forward:Cross(up)
    end
    perp = perp.Unit
    -- decide left or right based on which increases lateral distance from predicted path
    local leftPos = hrpPos + perp * 4
    local rightPos = hrpPos - perp * 4
    local function distToPath(point)
        -- distance from point to infinite line defined by (hitPoint, forward)
        local w = point - hitPoint
        local proj = forward * (w:Dot(forward))
        local perpVec = w - proj
        return perpVec.Magnitude
    end
    if distToPath(leftPos) > distToPath(rightPos) then
        return perp
    else
        return -perp
    end
end

-- Apply a short dodge force to the player's HRP using VectorForce for physics based gentle push
local function PerformDodge(dodgeDirection)
    local char = player.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    -- ensure we don't stack forces
    if hrp:FindFirstChild("__projectile_dodge_force") then return end

    local rootMass = hrp:GetMass()
    local attachment = Instance.new("Attachment")
    attachment.Name = "__dodge_attach"
    attachment.Parent = hrp

    local vf = Instance.new("VectorForce")
    vf.Name = "__projectile_dodge_force"
    vf.Attachment0 = attachment
    vf.Force = dodgeDirection * DODGE_FORCE_MAG * rootMass
    vf.RelativeTo = Enum.ActuatorRelativeTo.World
    vf.ApplyAtCenterOfMass = true
    vf.Parent = hrp

    -- cleanup after duration
    task.delay(DODGE_DURATION, function()
        if vf and vf.Parent then vf:Destroy() end
        if attachment and attachment.Parent then attachment:Destroy() end
    end)
end

-- Main update loop: update projectile velocities, predict threats, perform dodge
local lastTick = tick()
RunService.RenderStepped:Connect(function(dt)
    local now = tick()
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local hrpPos = hrp.Position

    for model, data in pairs(tracked) do
        -- validate model still has part
        if not data.part or not data.part.Parent then
            local newRep = getRepresentativePart(model)
            if newRep then
                data.part = newRep
                data.hitRadius = getBoundingRadiusForPart(newRep)
            else
                tracked[model] = nil
                continue
            end
        end

        local pos = data.part.Position
        local t = now
        local dtLocal = math.max(1e-6, t - data.lastUpdate)

        -- velocity estimate (exponential smoothing)
        local instantVel = (pos - data.lastPos) / dtLocal
        data.velocity = data.velocity:Lerp(instantVel, math.clamp(dtLocal / (TRACKING_SMOOTH + dtLocal), 0, 1))
        data.lastPos = pos
        data.lastUpdate = t
        data.age = t - data.createdAt

        -- stop tracking if old
        if data.age > MAX_PROJECTILE_AGE then
            tracked[model] = nil
            continue
        end

        -- Predict relative motion: treat motion as linear with current velocity
        local rel = hrpPos - pos
        local v = data.velocity

        -- if velocity is near zero, try to detect if the projectile is static (like a zone)
        if v.Magnitude < 1e-3 then
            -- check distance to HRP now
            local distNow = rel.Magnitude
            if distNow <= data.hitRadius + 1.0 then
                -- treat as immediate threat -> dodge away
                local dodgeDir = (hrpPos - pos).Unit
                if dodgeDir.Magnitude > 0 then
                    PerformDodge(dodgeDir)
                end
            end
            continue
        end

        -- compute time of closest approach between point (hrp) and projectile path: minimize | pos + v*t - hrp |
        -- t* = v:Dot(hrpPos - pos) / v:Dot(v)
        local denom = v:Dot(v)
        if denom <= 1e-6 then
            -- fallback
            continue
        end
        local tClosest = v:Dot(hrpPos - pos) / denom
        -- clamp into future window
        if tClosest < 0 then tClosest = 0 end
        if tClosest > THREAT_TIME_HORIZON then
            -- We'll check limited future time points as well (optionally)
            -- Not a near-term threat
            data.threat = false
        else
            local closestPoint = pos + v * tClosest
            local distClosest = (closestPoint - hrpPos).Magnitude
            local collisionRadius = data.hitRadius + 2.0 -- buffer for player radius
            if distClosest <= collisionRadius and tClosest >= MIN_THREAT_TIME then
                -- Threat detected: compute dodge
                data.threat = true
                local dodgeDir = getDodgeDirection(v, closestPoint, hrpPos)
                -- Small safety: only dodge if dodgeDir valid
                if dodgeDir.Magnitude > 0 then
                    -- Optionally check if there's space (raycast) in dodge direction before dashing
                    PerformDodge(dodgeDir)
                end
            else
                data.threat = false
            end
        end
    end
end)

-- Periodic cleanup: remove dead tracked entries (models destroyed or parent nil)
spawn(function()
    while true do
        for m, v in pairs(tracked) do
            if not m.Parent or not m:IsDescendantOf(workspace) then
                tracked[m] = nil
            end
        end
        task.wait(1)
    end
end)

-- Debugging utility (optional): press R to print tracked projectiles (for development)
local UserInputService = game:GetService("UserInputService")
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.R then
        print("Tracked projectiles:")
        for m,d in pairs(tracked) do
            print(m:GetFullName(), "vel", d.velocity, "radius", d.hitRadius, "age", d.age)
        end
    end
end)

print("Projectile Dodger initialized")
