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


gui.Enabled = false

local POLY = {
	Vector2.new(-39.05,  -74.314),
	Vector2.new(-18.076, -152.59),
	Vector2.new(-178.42, -195.554),
	Vector2.new(-199.851,-115.576),
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

local heldMoveKeys = {}
local isMoving = false
local movementNoise = 0 -- will be either 0 or 2

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
		if child:IsA("Tool") and child.Name == "noisy_horn" then
			hasNoisyTool = true
		end
	end)

	char.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") and child.Name == "noisy_horn" then
			hasNoisyTool = false
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

local function pointInPolyXZ(pos)
	local x, z = pos.X, pos.Z
	local inside = false
	local j = #POLY

	for i = 1, #POLY do
		local xi, zi = POLY[i].X, POLY[i].Y
		local xj, zj = POLY[j].X, POLY[j].Y

		if ((zi > z) ~= (zj > z))
			and (x < (xj - xi) * (z - zi) / (zj - zi) + xi) then
			inside = not inside
		end
		j = i
	end

	return inside
end

local function anyMoveKeyHeld() -- check if any movement key is held
	for _ in pairs(heldMoveKeys) do
		return true
	end
	return false
end


RunService.RenderStepped:Connect(function()
	if not insideLibrary then return end

	-- decide the floor
	local floor = isMoving and 2 or 0

	-- if we haven't clicked recently, snap to floor
	if loudnessLevel > floor then
		if tick() - lastClickTime >= 1 then
			loudnessLevel = floor
			render()
		end
	end
end)

RunService.RenderStepped:Connect(function()
	if not player.Character then return end
	local hrp = player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local inside = pointInPolyXZ(hrp.Position)
	setLibraryState(inside)
end)

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if not insideLibrary then return end

	-- CLICKING
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		-- with tool: normal stacking
		if hasNoisyTool then
			loudnessLevel = math.min(loudnessLevel + .8333, 12)
		else
			-- without tool: capped illusion
			loudnessLevel = math.min(2, math.max(loudnessLevel, 2))
		end

		lastClickTime = tick()
		render()
		return
	end

	-- MOVEMENT (no tool required)
	if MOVE_KEYS[input.KeyCode] then
		heldMoveKeys[input.KeyCode] = true

		if not isMoving then
			isMoving = true
			loudnessLevel = math.max(loudnessLevel, 2)
			movementNoise = tick()
			render()
		end
	end
end)


UserInputService.InputEnded:Connect(function(input, gp)
	if gp then return end

	if MOVE_KEYS[input.KeyCode] then
		heldMoveKeys[input.KeyCode] = nil
		isMoving = anyMoveKeyHeld()

		if not isMoving then
			loudnessLevel = 0
			render()
		end
	end
end)

