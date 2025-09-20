--!/usr/bin/env lua
-- Place this script in StarterPlayer > StarterPlayerScripts

--// Services
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService") -- Added for smooth movement

--// Player & Character Variables
local LocalPlayer = Players.LocalPlayer
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")

--// Configuration
local DODGE_DISTANCE = 25 -- How far (in studs) to dash to find a safe spot.
local DODGE_DURATION = 0.2 -- How long the dodge tween should take (in seconds).
local CHECK_POINTS = 16 -- How many directions to check for a safe spot.

--// State
local ActiveHitboxes = {} -- Stores data about all current threats.
local isDodging = false -- A debounce to prevent dodging multiple times.

--============================================================================--
--=                          HITBOX DETECTION LOGIC                          =--
--============================================================================--

-- This function checks if a given 3D point is inside a specific hitbox shape.
-- (This section is unchanged)
local function isPointInRegion(point, region)
	if region.Shape == "Cube" or region.Shape == "Triangle" then
		local localPoint = region.CFrame:PointToObjectSpace(point)
		local size = region.Size
		return (math.abs(localPoint.X) <= size.X / 2)
			and (math.abs(localPoint.Y) <= size.Y / 2)
			and (math.abs(localPoint.Z) <= size.Z / 2)
	elseif region.Shape == "Circle" or region.Shape == "Ring" then
		local localPoint = region.CFrame:PointToObjectSpace(point)
		local distanceOnXZ = math.sqrt(localPoint.X^2 + localPoint.Z^2)
		return distanceOnXZ <= region.Radius
	end
	return false
end


--============================================================================--
--=                            DODGE CALCULATION                             =--
--============================================================================--

-- (This section is unchanged)
local function findSafeSpot()
	local myPos = HumanoidRootPart.Position
	
	for i = 1, CHECK_POINTS do
		local angle = (i / CHECK_POINTS) * (2 * math.pi)
		local offset = Vector3.new(math.cos(angle) * DODGE_DISTANCE, 0, math.sin(angle) * DODGE_DISTANCE)
		local checkPos = myPos + offset

		local isSafe = true
		for _, hitbox in pairs(ActiveHitboxes) do
			if isPointInRegion(checkPos, hitbox) then
				isSafe = false
				break
			end
		end

		if isSafe then
			return checkPos
		end
	end

	return nil
end

-- (This function has been UPDATED to use TweenService)
local function executeDodge()
	if isDodging then return end -- Debounce
	isDodging = true

	local targetCFrame
	local safePosition = findSafeSpot()

	if safePosition then
		-- Calculate a target CFrame that moves to the safe spot but keeps the character's current orientation.
		targetCFrame = CFrame.new(safePosition) * (HumanoidRootPart.CFrame - HumanoidRootPart.CFrame.Position)
	else
		-- Fallback: If no spot is perfectly safe, just tween backward as a last resort.
		targetCFrame = HumanoidRootPart.CFrame + HumanoidRootPart.CFrame.LookVector * -15
	end
	
	-- Define the properties of our tweening animation.
	local tweenInfo = TweenInfo.new(
		DODGE_DURATION,          -- Duration
		Enum.EasingStyle.Quad,   -- Easing Style
		Enum.EasingDirection.Out -- Easing Direction
	)

	-- Create the tween animation.
	local dodgeTween = TweenService:Create(HumanoidRootPart, tweenInfo, {CFrame = targetCFrame})
	
	dodgeTween:Play() -- Run the animation
	dodgeTween.Completed:Wait() -- Wait for the tween to finish before allowing another dodge.

	isDodging = false
end

--============================================================================--
--=                      MODULE HIJACKING ("MONKEY-PATCHING")                =--
--============================================================================--

-- (This section is unchanged)
local originalFuncs = {
	Cube = PreCastHitbox.Cube,
	Circle = PreCastHitbox.Circle,
	Ring = PreCastHitbox.Ring,
	Triangle = PreCastHitbox.Triangle,
}

local function addHitbox(shape, cframe, size, radius, duration)
	local hitboxData = {
		Shape = shape,
		CFrame = cframe,
		Size = size,
		Radius = radius,
		Expiration = tick() + duration,
	}
	table.insert(ActiveHitboxes, hitboxData)
	task.spawn(executeDodge)
end

PreCastHitbox.Cube = function(cframe, size, delayUntilAttack, startTime, properties)
	addHitbox("Cube", cframe, size, nil, delayUntilAttack)
	return originalFuncs.Cube(cframe, size, delayUntilAttack, startTime, properties)
end

PreCastHitbox.Circle = function(position, radius, delayUntilAttack, startTime, properties)
	local cframe = CFrame.new(position)
	local size = Vector3.new(radius * 2, 20, radius * 2) 
	addHitbox("Circle", cframe, size, radius, delayUntilAttack)
	return originalFuncs.Circle(position, radius, delayUntilAttack, startTime, properties)
end

PreCastHitbox.Ring = function(position, radius, width, delayUntilAttack, startTime, properties)
	local cframe = CFrame.new(position)
	local size = Vector3.new(radius * 2, 20, radius * 2)
	addHitbox("Ring", cframe, size, radius, delayUntilAttack)
	return originalFuncs.Ring(position, radius, width, delayUntilAttack, startTime, properties)
end

PreCastHitbox.Triangle = function(cframe, size, delayUntilAttack, startTime, properties)
	addHitbox("Triangle", cframe, size, nil, delayUntilAttack)
	return originalFuncs.Triangle(cframe, size, delayUntilAttack, startTime, properties)
end

--============================================================================--
--=                             MAIN UPDATE LOOP                             =--
--============================================================================--

-- (This section is unchanged)
RunService.Heartbeat:Connect(function()
	local currentTime = tick()
	for i = #ActiveHitboxes, 1, -1 do
		local hitbox = ActiveHitboxes[i]
		if currentTime > hitbox.Expiration then
			table.remove(ActiveHitboxes, i)
		end
	end
end)

print("✅ Smooth Dodge script loaded and active.")
