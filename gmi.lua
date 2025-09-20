--[[
    Client-Side Projectile Evasion Script
    
    Description:
    This script automatically moves the player's character to avoid projectiles.
    It works by:
    1. Identifying projectiles in the workspace by cross-referencing with a list in ReplicatedStorage.
    2. Finding the 'hitBox' or 'preCast' part within each projectile.
    3. Treating these parts as infinitely tall danger zones.
    4. Searching for the closest safe spot on a 2D (X, Z) plane around the player.
    5. Tweening the character's HumanoidRootPart to that safe spot.
    
    Location: StarterPlayerScripts
]]

--// Services
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

--// Configuration
local MAX_SEARCH_RADIUS = 40 -- How far out the script will look for a safe spot (in studs).
local SEARCH_INCREMENT = 5   -- The step size for each search ring (in studs).
local SEARCH_DENSITY = 16    -- How many points to check in each search ring. Higher is more accurate but less performant.
local TWEEN_DURATION = 0.25  -- How fast the character moves to the safe spot (in seconds).

--// Player & Character Variables
local localPlayer = Players.LocalPlayer
local character = localPlayer.Character or localPlayer.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local hrp = character:WaitForChild("HumanoidRootPart")

--// Module & Asset References
local enemyProjectilesFolder = ReplicatedStorage:WaitForChild("enemyProjectiles")

--// Runtime Variables
local projectileNames = {} -- A set for fast lookup of valid projectile names.
local activeTween = nil    -- To track the current movement tween.

--// Populate the projectile name set for efficient checking.
for _, projectileObject in ipairs(enemyProjectilesFolder:GetChildren()) do
	projectileNames[projectileObject.Name] = true
end
print("Projectile Dodge System Initialized.")

---
-- @function getDangerZones
-- @description Scans the workspace for active projectiles and returns their hitBox/preCast parts.
-- @returns {table} An array of all danger zone parts currently in the workspace.
---
local function getDangerZones()
	local dangerZones = {}
	for _, instance in ipairs(Workspace:GetChildren()) do
		-- Check if the instance is a known projectile.
		if projectileNames[instance.Name] then
			-- Prioritize hitBox over preCast as requested.
			local dangerPart = instance:FindFirstChild("hitBox") or instance:FindFirstChild("preCast")
			
			if dangerPart and dangerPart:IsA("BasePart") then
				table.insert(dangerZones, dangerPart)
			else
				-- Warn if a known projectile is found without a valid danger part.
				warn("Dodge Script: Could not find a 'hitBox' or 'preCast' Part in projectile: " .. instance.Name)
			end
		end
	end
	return dangerZones
end

---
-- @function isPositionSafe
-- @description Checks if a given 3D position is inside any of the danger zones on a 2D plane (X, Z).
-- @param position {Vector3} The world position to check.
-- @param dangerZones {table} An array of danger zone parts.
-- @returns {boolean} True if the position is safe, false otherwise.
---
local function isPositionSafe(position, dangerZones)
	for _, zone in ipairs(dangerZones) do
		-- Convert the world position to the zone's local object space.
		local localPos = zone.CFrame:PointToObjectSpace(position)
		
		-- Check if the position is within the zone's X and Z bounds. The Y-axis is ignored.
		if math.abs(localPos.X) <= zone.Size.X / 2 and math.abs(localPos.Z) <= zone.Size.Z / 2 then
			return false -- Position is inside this zone, so it's not safe.
		end
	end
	return true -- Position is outside all danger zones.
end

---
-- @function findSafestSpot
-- @description Searches for the closest safe position around the character.
-- @param dangerZones {table} An array of danger zone parts.
-- @returns {Vector3 | nil} The closest safe Vector3 position, or nil if none is found or needed.
---
local function findSafestSpot(dangerZones)
	-- If the player is already safe, no need to move.
	if isPositionSafe(hrp.Position, dangerZones) then
		return nil
	end
	
	-- Search in expanding rings to find the *closest* safe spot first.
	for radius = SEARCH_INCREMENT, MAX_SEARCH_RADIUS, SEARCH_INCREMENT do
		for i = 1, SEARCH_DENSITY do
			local angle = (i / SEARCH_DENSITY) * 2 * math.pi
			local offset = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
			local candidatePos = hrp.Position + offset
			
			-- The first safe spot found in the expanding search will be the closest.
			if isPositionSafe(candidatePos, dangerZones) then
				return candidatePos
			end
		end
	end
	
	-- No safe spot found within the search radius.
	return nil
end

---
-- @function moveTo
-- @description Tweens the HumanoidRootPart to a target position smoothly.
-- @param targetPosition {Vector3} The destination to move to.
---
local function moveTo(targetPosition)
	-- Cancel any ongoing movement tween to avoid conflicts.
	if activeTween then
		activeTween:Cancel()
		activeTween = nil
	end
	
	local tweenInfo = TweenInfo.new(
		TWEEN_DURATION,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)
	
	-- Ensure the Y-position remains the same to prevent floating or clipping.
	local goal = { Position = Vector3.new(targetPosition.X, hrp.Position.Y, targetPosition.Z) }
	
	activeTween = TweenService:Create(hrp, tweenInfo, goal)
	activeTween:Play()
end

--// Main Loop
RunService.Heartbeat:Connect(function()
	-- Ensure the character and HRP are still valid.
	if not (character and character.Parent and hrp and humanoid and humanoid.Health > 0) then
		return
	end
	
	-- 1. Identify all current threats.
	local dangerZones = getDangerZones()
	
	-- Optimization: If there are no projectiles on screen, do nothing.
	if #dangerZones == 0 then
		return
	end

	-- 2. Find the best place to move to.
	local safeSpot = findSafestSpot(dangerZones)
	
	-- 3. If a safe spot was found, move the character there.
	if safeSpot then
		moveTo(safeSpot)
	end
end)
