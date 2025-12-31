-- This localScript contains the LoudnessMeter UI logic
-- logic is responsible for:
-- 1. UI visibility
-- 2. Loudness meter UI
-- 3. Door open/close logic
-- 4. Walking noise logic
-- 5. Noisy tool logic
-- 6. Clicking logic
-- 7. Boss UI logic
-- 8. Boss walk animation logic
-- 9. Boss attack animation logic

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DoorUsed = ReplicatedStorage:WaitForChild("DoorUsed")

local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local gui = script.Parent
local container = gui:WaitForChild("LoudnessContainer")

local LoudnessDeterminism = ReplicatedStorage:WaitForChild("remote"):WaitForChild("NoisyToolClick")

-- Collect frames in order
local frames = {}
for i = 1, 12 do
	frames[i] = container:WaitForChild(i)
end

local loudnessLevel = 0
local insideLibrary = false
local hasNoisyTool = false
local lastClickTime = 0

local walkingNoise = 0
local heldMoveKeys = {}
local isMoving = false
local movementNoise = 0 -- will be either 0 or 2

local hasOldBook = false
local bookRightHeld = false

local runHeld = false
local crouchHeld = false


gui.Enabled = false

local RECT = {
	minX = -151.491,
	maxX = -14.491,
	minZ = -215.476,
	maxZ = -78.476,
}

local COLORS = {
	
	[12] = Color3.fromRGB(255, 0, 0), -- bottom 2 red
	[11] = Color3.fromRGB(255, 0, 0),
	
	[10] = Color3.fromRGB(255, 165, 0),-- next 6 orange
	[9] = Color3.fromRGB(255, 165, 0),
	[8] = Color3.fromRGB(255, 165, 0),
	[7] = Color3.fromRGB(255, 165, 0),
	
	[6] = Color3.fromRGB(255, 255, 0), -- top 2 yellow
	[5] = Color3.fromRGB(255, 255, 0),

	[4]  = Color3.fromRGB(0, 255, 0),  -- next 4 green
	[3] = Color3.fromRGB(0, 255, 0),
	[2] = Color3.fromRGB(0, 255, 0),
	[1] = Color3.fromRGB(0, 255, 0),
}

-- normal color
local OFF_COLOR = Color3.fromRGB(54, 54, 54)

local MOVE_KEYS = {
	[Enum.KeyCode.W] = true,
	[Enum.KeyCode.A] = true,
	[Enum.KeyCode.S] = true,
	[Enum.KeyCode.D] = true,
	[Enum.KeyCode.Space] = true,
}
local RUN_KEY = Enum.KeyCode.LeftShift
local CROUCH_KEY = Enum.KeyCode.C

local function render()
	for i = 1, 12 do
		if i <= loudnessLevel then
			frames[i].BackgroundColor3 = COLORS[i]
		else
			frames[i].BackgroundColor3 = OFF_COLOR
		end
	end
end

local function onCharacterAdded(char)
	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			if child.Name == "noisy_horn" then
				hasNoisyTool = true
			elseif child.Name == "old_book" then
				hasOldBook = true
			end
		end
	end)

	char.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			if child.Name == "noisy_horn" then
				hasNoisyTool = false
			elseif child.Name == "old_book" then
				hasOldBook = false
				bookRightHeld = false -- safety reset if unequipped mid-hold
			end
		end
	end)
end

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)

-- fade in fade out
local function fadeGui(targetAlpha)
	gui.Enabled = true
	for _, frame in ipairs(frames) do
		TweenService:Create(
			frame,
			TweenInfo.new(0.35),
			{BackgroundTransparency = targetAlpha}
		):Play()
	end
end

local function fadeIn()
	fadeGui(0)
end

local function fadeOut()
	fadeGui(1)
	task.delay(0.35, function()
		gui.Enabled = false
	end)
end

local function setLibraryState(inside)
	if inside == insideLibrary then return end

	insideLibrary = inside
	loudnessLevel = 0
	walkingNoise = 0
	render()

	if inside then
		fadeIn()
	else
		fadeOut()
	end
end

local function pointInRectXZ(pos)
	return pos.X >= RECT.minX
		and pos.X <= RECT.maxX
		and pos.Z >= RECT.minZ
		and pos.Z <= RECT.maxZ
end


local function anyMoveKeyHeld() -- check if any movement key is held
	for _ in pairs(heldMoveKeys) do
		return true
	end
	return false
end

local function resolveMovementFloor()
	-- crouch always wins silence
	if crouchHeld then
		return 0
	end

	-- run overrides walking
	if runHeld then
		return 6
	end

	-- walking noise
	if anyMoveKeyHeld() then
		return 2
	end

	return 0
end


RunService.RenderStepped:Connect(function()
	if not insideLibrary then return end

	-- decide the floor
	local floor = resolveMovementFloor()

	-- if we haven't clicked recently, snap to floor
	if loudnessLevel > floor then
		if tick() - lastClickTime >= 1 then
			loudnessLevel = floor
			print("floor", loudnessLevel)
			render()
		end
	end
end)

RunService.RenderStepped:Connect(function()
	if not player.Character then return end
	local hrp = player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local inside = pointInRectXZ(hrp.Position)
	setLibraryState(inside)
end)

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if not insideLibrary then return end

	-- CLICKING
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		-- with tool: normal stacking
		if hasNoisyTool then
			loudnessLevel = math.min(loudnessLevel + 1, 12)
		end
		lastClickTime = tick()
		render()
		return
	end

	-- MOVEMENT (no tool required)
	if MOVE_KEYS[input.KeyCode] and not crouchHeld then
		heldMoveKeys[input.KeyCode] = true

		if not isMoving then
			isMoving = true

			-- 🔑 reassert run baseline if shift is already held
			if runHeld then
				loudnessLevel = math.max(loudnessLevel, 6)
			else
				loudnessLevel = math.max(loudnessLevel, 2)
			end

			movementNoise = tick()
			render()
		end
	end

	
	-- OLD_BOOK: Right mouse hold begins
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		if hasOldBook then
			bookRightHeld = true
		end
		return
	end
	
	-- RUN
	if input.KeyCode == RUN_KEY then
		runHeld = true
		
		-- must be actual movement
		if not anyMoveKeyHeld() then
			loudnessLevel = 0 -- reset comepletely
			render()
			return
		end
		
		-- snap UI to run floor
		loudnessLevel = math.max(loudnessLevel, 6)
		render()

		-- let server-side timeout clear first (~1s)
		task.delay(1.2, function()
			-- still running AND still moving
			if not runHeld or not anyMoveKeyHeld() then return end

			-- fire exactly enough to reach 6 (not more)
			for _ = 1, 6 do
				LoudnessDeterminism:FireServer()
			end
		end)

		return
	end

	-- CROUCH
	if input.KeyCode == CROUCH_KEY then
		crouchHeld = true
		loudnessLevel = 0
		render()
		return
	end

end)


UserInputService.InputEnded:Connect(function(input, gp)
	if gp then return end

	if MOVE_KEYS[input.KeyCode] then
		heldMoveKeys[input.KeyCode] = nil
		isMoving = anyMoveKeyHeld()

		if not isMoving then
			loudnessLevel = resolveMovementFloor()
			render()
		end

	end
	
	-- OLD_BOOK: Right mouse released -> snap to max
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		if hasOldBook and bookRightHeld and insideLibrary then
			bookRightHeld = false
			loudnessLevel = 12
			lastClickTime = tick()
			render()
			
			-- for loop 12 times to fire server
			for count = 0, 12,1 do
				LoudnessDeterminism:FireServer()
			end
		else
			bookRightHeld = false
		end
		return
	end
	
	-- RUN RELEASE
	if input.KeyCode == RUN_KEY then
		runHeld = false
		loudnessLevel = resolveMovementFloor()
		render()
		return
	end

	-- CROUCH RELEASE
	if input.KeyCode == CROUCH_KEY then
		crouchHeld = false

		-- 🔑 reassert run baseline if shift is already held
		if runHeld then
			loudnessLevel = math.max(loudnessLevel, 6)
		else
			loudnessLevel = math.max(loudnessLevel, 2)
		end

		movementNoise = tick()
		render()
		return
	end

end)

