-- Movement.client.luau
-- Client-authoritative movement + baseline loudness

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

-- CONFIG
local WALK_SPEED = 16
local RUN_SPEED = 32
local CROUCH_SPEED = 8

local RUN_LOUDNESS = 6
local CROUCH_LOUDNESS = 0

-- STATE
local humanoid : Humanoid?
local isRunning = false
local isCrouching = false

-- Loudness exposed to UI / systems
-- (we will bind UI later)
local loudness = 0

-- Utility
local function getHumanoid()
	if humanoid and humanoid.Parent then return humanoid end
	local char = player.Character
	if not char then return nil end
	humanoid = char:FindFirstChildOfClass("Humanoid")
	return humanoid
end

-- APPLY MOVEMENT + BASE LOUDNESS
local function applyMovement()
	local hum = getHumanoid()
	if not hum then return end

	if isCrouching then
		hum.WalkSpeed = CROUCH_SPEED
		loudness = CROUCH_LOUDNESS
		return
	end

	if isRunning then
		hum.WalkSpeed = RUN_SPEED
		loudness = RUN_LOUDNESS
		return
	end

	-- Default walk
	hum.WalkSpeed = WALK_SPEED
	loudness = 0
end

-- INPUT HANDLING
UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end

	if input.KeyCode == Enum.KeyCode.LeftShift then
		isRunning = true
		isCrouching = false -- run overrides crouch
		applyMovement()
	end

	if input.KeyCode == Enum.KeyCode.C then
		isCrouching = true
		isRunning = false -- crouch overrides run
		applyMovement()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift then
		isRunning = false
		applyMovement()
	end

	if input.KeyCode == Enum.KeyCode.C then
		isCrouching = false
		applyMovement()
	end
end)

-- CHARACTER RESPAWN SAFETY
player.CharacterAdded:Connect(function()
	task.wait(0.1)
	applyMovement()
end)

-- PUBLIC API (for UI / clicking / items later)
-- DO NOT MODIFY LOUDNESS DIRECTLY — only add on top
_G.MovementState = {
	getBaselineLoudness = function()
		return loudness
	end,

	isRunning = function()
		return isRunning
	end,

	isCrouching = function()
		return isCrouching
	end
}
