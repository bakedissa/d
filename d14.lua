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
-- Corrected the casing from "PreCastHitbox" to "PrecastHitbox"
local PrecastHitbox = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PrecastHitbox"))

--// Safety Check
if not PrecastHitbox then
	warn("DODGE SCRIPT ERROR: The 'PrecastHitbox' module failed to load. Please verify the path in ReplicatedStorage.")
	return -- Stop the script to prevent further errors.
end

--// Configuration
local DODGE_DISTANCE = 25 
local DODGE_DURATION = 0.2 
local CHECK_POINTS = 16 

--// State
local ActiveHitboxes = {} 
local isDodging = false 

--============================================================================--
--=                          HITBOX DETECTION LOGIC                          =--
--============================================================================--

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
--=                      MODULE HIJACKING ("MONKEY-PATCHING")                =--
--============================================================================--

local originalFuncs = {
	Cube = PrecastHitbox.Cube,
	Circle = PrecastHitbox.Circle,
	Ring = PrecastHitbox.Ring,
	Triangle = PrecastHitbox.Triangle,
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

PrecastHitbox.Cube = function(cframe, size, delayUntilAttack, startTime, properties)
	addHitbox("Cube", cframe, size, nil, delayUntilAttack)
	return originalFuncs.Cube(cframe, size, delayUntilAttack, startTime, properties)
end

PrecastHitbox.Circle = function(position, radius, delayUntilAttack, startTime, properties)
	local cframe = CFrame.new(position)
	local size = Vector3.new(radius * 2, 20, radius * 2) 
	addHitbox("Circle", cframe, size, radius, delayUntilAttack)
	return originalFuncs.Circle(position, radius, delayUntilAttack, startTime, properties)
end

PrecastHitbox.Ring = function(position, radius, width, delayUntilAttack, startTime, properties)
	local cframe = CFrame.new(position)
	local size = Vector3.new(radius * 2, 20, radius * 2)
	addHitbox("Ring", cframe, size, radius, delayUntilAttack)
	return originalFuncs.Ring(position, radius, width, delayUntilAttack, startTime, properties)
end

PrecastHitbox.Triangle = function(cframe, size, delayUntilAttack, startTime, properties)
	addHitbox("Triangle", cframe, size, nil, delayUntilAttack)
	return originalFuncs.Triangle(cframe, size, delayUntilAttack, startTime, properties)
end

--============================================================================--
--=                             MAIN UPDATE LOOP                             =--
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
