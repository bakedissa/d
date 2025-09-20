--!/usr/bin/env lua
-- Place this script in StarterPlayer > StarterPlayerScripts

--// Services
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

--// Player & Character Variables
local LocalPlayer = Players.LocalPlayer
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")

--// Modules
-- Using "PrecastHitbox" as confirmed.
local PrecastHitbox = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PrecastHitbox"))

--// Safety Check
if not PrecastHitbox then
	warn("DODGE SCRIPT ERROR: The 'PrecastHitbox' module failed to load. Please verify the path and name.")
	return
end

--// Configuration
local DODGE_DISTANCE = 25
local DODGE_DURATION = 0.2
local CHECK_POINTS = 16

--// State
local ActiveHitboxes = {}
local isDodging = false

--============================================================================--
--=                           HITBOX DETECTION LOGIC                         =--
--============================================================================--

local function isPointInRegion(point, region)
	local localPoint = region.CFrame:PointToObjectSpace(point)

	if region.Shape == "Cube" or region.Shape == "Triangle" then
		local size = region.Size
		return (math.abs(localPoint.X) <= size.X / 2)
			and (math.abs(localPoint.Y) <= size.Y / 2)
			and (math.abs(localPoint.Z) <= size.Z / 2)
	elseif region.Shape == "Circle" then
		local distanceOnXZ = math.sqrt(localPoint.X^2 + localPoint.Z^2)
		return distanceOnXZ <= region.Radius
	elseif region.Shape == "Ring" then
		-- CORRECTED LOGIC: Check for the area BETWEEN inner and outer radius
		local distanceOnXZ = math.sqrt(localPoint.X^2 + localPoint.Z^2)
		local outerRadius = region.Radius
		local innerRadius = region.Radius - region.Width
		return distanceOnXZ <= outerRadius and distanceOnXZ >= innerRadius
	end
	return false
end


--============================================================================--
--=                            DODGE CALCULATION                             =--
--============================================================================--

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

local function executeDodge()
	if isDodging then return end
	isDodging = true

	local targetCFrame
	local safePosition = findSafeSpot()

	if safePosition then
		targetCFrame = CFrame.new(safePosition) * (HumanoidRootPart.CFrame - HumanoidRootPart.CFrame.Position)
	else
		targetCFrame = HumanoidRootPart.CFrame + HumanoidRootPart.CFrame.LookVector * -15
	end
	
	local tweenInfo = TweenInfo.new(
		DODGE_DURATION,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)

	local dodgeTween = TweenService:Create(HumanoidRootPart, tweenInfo, {CFrame = targetCFrame})
	
	dodgeTween:Play()
	dodgeTween.Completed:Wait()

	isDodging = false
end

--============================================================================--
--=                 MODULE HIJACKING ("MONKEY-PATCHING")                     =--
--============================================================================--

local originalFuncs = {
	Cube = PrecastHitbox.Cube,
	Circle = PrecastHitbox.Circle,
	Ring = PrecastHitbox.Ring,
	Triangle = PrecastHitbox.Triangle,
}

local function addHitbox(data)
	-- DEBUG: Print the captured hitbox data to see if it's correct
	-- print("Adding new hitbox:", data)
	
	table.insert(ActiveHitboxes, data)
	if not isDodging then
		task.spawn(executeDodge)
	end
end

PrecastHitbox.Cube = function(cframe, size, delayUntilAttack, startTime, properties)
	print("✅ DODGE SCRIPT: Hijacked Cube function was called!")
	addHitbox({
		Shape = "Cube",
		CFrame = cframe,
		Size = size,
		Expiration = tick() + delayUntilAttack,
	})
	return originalFuncs.Cube(cframe, size, delayUntilAttack, startTime, properties)
end

PrecastHitbox.Circle = function(position, radius, delayUntilAttack, startTime, properties)
	print("✅ DODGE SCRIPT: Hijacked Circle function was called!")
	addHitbox({
		Shape = "Circle",
		CFrame = CFrame.new(position),
		Radius = radius,
		Expiration = tick() + delayUntilAttack,
	})
	return originalFuncs.Circle(position, radius, delayUntilAttack, startTime, properties)
end

PrecastHitbox.Ring = function(position, radius, width, delayUntilAttack, startTime, properties)
	print("✅ DODGE SCRIPT: Hijacked Ring function was called!")
	addHitbox({
		Shape = "Ring",
		CFrame = CFrame.new(position),
		Radius = radius,
		Width = width,
		Expiration = tick() + delayUntilAttack,
	})
	return originalFuncs.Ring(position, radius, width, delayUntilAttack, startTime, properties)
end

PrecastHitbox.Triangle = function(cframe, size, delayUntilAttack, startTime, properties)
	print("✅ DODGE SCRIPT: Hijacked Triangle function was called!")
	addHitbox({
		Shape = "Triangle",
		CFrame = cframe,
		Size = size,
		Expiration = tick() + delayUntilAttack,
	})
	return originalFuncs.Triangle(cframe, size, delayUntilAttack, startTime, properties)
end

--============================================================================--
--=                            MAIN UPDATE LOOP                              =--
--============================================================================--

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
