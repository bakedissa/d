-- AutoDodge.lua (LocalScript)
-- Places: StarterPlayer > StarterPlayerScripts
-- Behavior: watches workspace for enemy projectiles (cross-refs ReplicatedStorage.enemyProjectiles),
-- finds hitBox (prioritize) or preCast parts, treats their XZ footprint as unsafe (infinite Y),
-- finds nearest safe XZ spot on ground, tweens HumanoidRootPart there quickly. Warns if a projectile lacks both parts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local PhysicsService = game:GetService("PhysicsService")

local LOCAL_PLAYER = Players.LocalPlayer
local CHARACTER = LOCAL_PLAYER.Character or LOCAL_PLAYER.CharacterAdded:Wait()
local HRP = CHARACTER:WaitForChild("HumanoidRootPart")
local HUMANOID = CHARACTER:FindFirstChildOfClass("Humanoid")

local ENEMY_PROJECTILE_FOLDER = ReplicatedStorage:WaitForChild("enemyProjectiles", 5) -- will error if missing
if not ENEMY_PROJECTILE_FOLDER then
	error("ReplicatedStorage.enemyProjectiles not found")
end

-- Config
local CHECK_INTERVAL = 0.12 -- seconds between checks (about 8.3Hz)
local SAMPLE_RADII = {4, 7, 10, 15, 22} -- radii to sample for safe spots (studs)
local SAMPLE_ANGLE_STEP = 20 -- degrees between sample rays
local GROUND_CHECK_HEIGHT = 10 -- raycast down distance
local MAX_TWEEN_TIME = 0.35 -- how quickly we move
local MIN_SAFE_DISTANCE_FROM_HITBOX = 1 -- buffer to keep outside hitbox
local SAFETY_FLOOR_Y_OFFSET = 2 -- add small offset above ground so we land on floor, not inside

-- Util: case-insensitive name match helpers for parts
local HIT_NAMES = { "hitBox", "hitbox", "HitBox", "Hitbox", "Hit" }
local PRE_NAMES = { "preCast", "precast", "PreCast", "PreCast", "Pre" }

local function nameMatchesAny(name, list)
	for _, v in ipairs(list) do
		if name == v then return true end
	end
	-- fallback: substring match
	for _, v in ipairs(list) do
		if string.lower(name):find(string.lower(v)) then return true end
	end
	return false
end

-- Given a part or model, returns a footprint-check function that accepts a Vector3 position (world)
-- and returns true if that position (ignoring Y) is inside the footprint.
local function footprintFromInstance(inst)
	-- Instances might be Parts, Models, or Unions. We'll handle common cases.
	if not inst then
		return function() return false end
	end

	if inst:IsA("Model") then
		-- use bounding box
		local _, size = inst:GetBoundingBox()
		local cframe = inst:GetPrimaryPartCFrame and inst.PrimaryPart and inst.PrimaryPart.CFrame or inst:GetModelCFrame()
		if not cframe then
			cframe = inst:GetChildren()[1] and inst:GetChildren()[1].CFrame or CFrame.new(inst:GetModelCFrame().p)
		end
		local halfX, halfZ = size.X / 2, size.Z / 2
		local inv = cframe:Inverse()
		return function(worldPos)
			local p = inv:PointToObjectSpace(Vector3.new(worldPos.X, cframe.p.Y, worldPos.Z))
			return math.abs(p.X) <= (halfX + MIN_SAFE_DISTANCE_FROM_HITBOX) and math.abs(p.Z) <= (halfZ + MIN_SAFE_DISTANCE_FROM_HITBOX)
		end
	end

	if inst:IsA("BasePart") then
		local size = inst.Size
		local cf = inst.CFrame
		local shape = inst.Shape -- for Cylinder we handle as round in XZ
		local halfX, halfZ = size.X / 2, size.Z / 2
		local inv = cf:Inverse()
		if inst.Shape == Enum.PartType.Cylinder then
			-- Cylinder in Roblox: cylinder axis is Y by default (height = Y), radius from X/Z
			local radius = math.max(size.X, size.Z) / 2
			return function(worldPos)
				local p = inv:PointToObjectSpace(Vector3.new(worldPos.X, cf.p.Y, worldPos.Z))
				return (p.X * p.X + p.Z * p.Z) <= (radius + MIN_SAFE_DISTANCE_FROM_HITBOX)^2
			end
		else
			-- treat as oriented rectangle in XZ
			return function(worldPos)
				local p = inv:PointToObjectSpace(Vector3.new(worldPos.X, cf.p.Y, worldPos.Z))
				return math.abs(p.X) <= (halfX + MIN_SAFE_DISTANCE_FROM_HITBOX) and math.abs(p.Z) <= (halfZ + MIN_SAFE_DISTANCE_FROM_HITBOX)
			end
		end
	end

	-- Fallback: no footprint
	return function() return false end
end

-- Build list of active projectiles (those in workspace whose Name matches a child in ReplicatedStorage.enemyProjectiles)
local function isEnemyProjectileInstance(instance)
	-- if an instance name matches any name in ReplicatedStorage.enemyProjectiles
	local exists = ENEMY_PROJECTILE_FOLDER:FindFirstChild(instance.Name)
	return exists ~= nil
end

-- Given a projectile instance in workspace, find prioritized footprint function: hitBox prioritized over preCast.
-- Returns footprintFn, centerPos (Vector3), and a debug-friendly foundType string.
local function findProjectileFootprint(projectile)
	-- search children for hitBox or preCast (case-insensitive heuristics)
	local foundHit, foundPre
	for _, child in ipairs(projectile:GetDescendants()) do
		if child:IsA("BasePart") or child:IsA("Model") or child:IsA("UnionOperation") then
			if nameMatchesAny(child.Name, HIT_NAMES) then
				foundHit = child
				break
			elseif nameMatchesAny(child.Name, PRE_NAMES) then
				foundPre = foundPre or child
			end
		end
	end

	local chosen = foundHit or foundPre
	if not chosen then
		return nil, nil, nil
	end

	local center
	if chosen:IsA("BasePart") then
		center = chosen.Position
	elseif chosen:IsA("Model") then
		center = chosen:GetModelCFrame().p
	else
		center = chosen:IsA("Instance") and (chosen.Position or (chosen.PrimaryPart and chosen.PrimaryPart.Position) or projectile:GetModelCFrame().p) or projectile:GetModelCFrame().p
	end

	return footprintFromInstance(chosen), center, foundHit and "hitBox" or "preCast"
end

-- Check if a given world position (Vector3) is safe given all active footprints.
local function isPositionSafe(worldPos, footprints)
	for _, info in ipairs(footprints) do
		local fn = info.fn
		if fn and fn(worldPos) then
			return false
		end
	end
	return true
end

-- Ground snap: cast down from a high point and return CFrame on ground + offset
local function findGroundCFrameAt(xzPosition)
	local origin = Vector3.new(xzPosition.X, xzPosition.Y + GROUND_CHECK_HEIGHT, xzPosition.Z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Blacklist
	-- blacklist the character so we don't hit ourselves
	params.FilterDescendantsInstances = {CHARACTER}
	params.IgnoreWater = false
	local result = Workspace:Raycast(origin, Vector3.new(0, -GROUND_CHECK_HEIGHT - 5, 0), params)
	if result then
		local pos = result.Position + Vector3.new(0, SAFETY_FLOOR_Y_OFFSET, 0)
		-- produce HRP-oriented CFrame facing original look direction
		return CFrame.new(pos)
	end
	return nil
end

-- Build footprints for all current projectiles in workspace
local function gatherActiveFootprints()
	local footprints = {}
	for _, child in ipairs(Workspace:GetChildren()) do
		if isEnemyProjectileInstance(child) then
			local fn, center, foundType = findProjectileFootprint(child)
			if not fn then
				warn("[AutoDodge] Projectile found with no hitBox or preCast: ".. tostring(child.Name))
			else
				table.insert(footprints, {fn = fn, center = center, source = child, type = foundType})
			end
		end
	end
	return footprints
end

-- Candidate generation: sample around current HRP XZ at set radii and angles
local function generateCandidates(originPos)
	local candidates = {}
	for _, r in ipairs(SAMPLE_RADII) do
		for angle = 0, 360 - SAMPLE_ANGLE_STEP, SAMPLE_ANGLE_STEP do
			local rad = math.rad(angle)
			local x = originPos.X + math.cos(rad) * r
			local z = originPos.Z + math.sin(rad) * r
			table.insert(candidates, Vector3.new(x, originPos.Y, z))
		end
	end
	-- also add axis offsets (straight left/right/back/forward)
	for _, off in ipairs({Vector3.new(12,0,0), Vector3.new(-12,0,0), Vector3.new(0,0,12), Vector3.new(0,0,-12)}) do
		table.insert(candidates, originPos + off)
	end
	return candidates
end

-- Compute fallback opposite vector when no sampled candidate is safe
local function fallbackOppositeMove(originPos, footprints)
	-- compute weighted center of all footprint centers and go opposite direction
	local avgX, avgZ, count = 0, 0, 0
	for _, f in ipairs(footprints) do
		if f.center then
			avgX = avgX + f.center.X
			avgZ = avgZ + f.center.Z
			count = count + 1
		end
	end
	if count == 0 then
		return originPos + Vector3.new(0,0, -12)
	end
	avgX = avgX / count
	avgZ = avgZ / count
	local dir = Vector3.new(originPos.X - avgX, 0, originPos.Z - avgZ)
	if dir.Magnitude < 1 then
		dir = Vector3.new(0,0,-1)
	end
	dir = dir.Unit
	local target = originPos + dir * 14
	return target
end

-- Tween helper: cancel previous tween and create a new one to move HRP to a CFrame
local currentTween
local function tweenToCFrame(targetCFrame)
	if not HRP then return end
	if currentTween then
		pcall(function() currentTween:Cancel() end)
		currentTween = nil
	end
	local distance = (HRP.Position - targetCFrame.p).Magnitude
	local time = math.clamp(distance / 60, 0.07, MAX_TWEEN_TIME) -- ensure it's fast but not instant
	local tweenInfo = TweenInfo.new(time, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	currentTween = TweenService:Create(HRP, tweenInfo, {CFrame = targetCFrame})
	currentTween:Play()
end

-- Main logic loop: gather footprints, sample candidates, pick nearest safe, tween.
local lastTick = 0
local function mainStep(dt)
	lastTick = lastTick + dt
	if lastTick < CHECK_INTERVAL then return end
	lastTick = 0

	if not HRP or not HRP.Parent then
		CHARACTER = LOCAL_PLAYER.Character or LOCAL_PLAYER.CharacterAdded:Wait()
		HRP = CHARACTER:WaitForChild("HumanoidRootPart")
		HUMANOID = CHARACTER:FindFirstChildOfClass("Humanoid")
		return
	end

	local footprints = gatherActiveFootprints()
	if #footprints == 0 then
		-- no projectiles: nothing to do
		return
	end

	local origin = HRP.Position
	-- First: check if current position is already safe (maybe no overlap)
	if isPositionSafe(origin, footprints) then
		return
	end

	-- generate candidates
	local candidates = generateCandidates(origin)
	local best
	local bestDist = math.huge
	for _, cand in ipairs(candidates) do
		-- ground-check candidate
		local groundCFrame = findGroundCFrameAt(Vector3.new(cand.X, origin.Y, cand.Z))
		if groundCFrame then
			-- small vertical adjust so candidate uses ground position
			local testPos = groundCFrame.p
			-- check safety against footprints
			if isPositionSafe(testPos, footprints) then
				local dist = (testPos - origin).Magnitude
				if dist < bestDist then
					bestDist = dist
					best = groundCFrame
				end
			end
		end
	end

	-- fallback: opposite vector if no sampled candidate
	if not best then
		local fallbackXZ = fallbackOppositeMove(origin, footprints)
		local groundC = findGroundCFrameAt(Vector3.new(fallbackXZ.X, origin.Y, fallbackXZ.Z))
		if groundC and isPositionSafe(groundC.p, footprints) then
			best = groundC
		end
	end

	-- if we found a best CFrame, tween to it
	if best then
		tweenToCFrame(best)
	end
end

-- Connect run loop
local conn
conn = RunService.Heartbeat:Connect(function(dt)
	-- protect against studio pause or character removal
	pcall(function()
		mainStep(dt)
	end)
end)

-- Clean up on character respawn
LOCAL_PLAYER.CharacterAdded:Connect(function(char)
	CHARACTER = char
	HRP = CHARACTER:WaitForChild("HumanoidRootPart")
	HUMANOID = CHARACTER:WaitForChild("Humanoid")
end)

print("[AutoDodge] initialized - monitoring enemy projectiles")
