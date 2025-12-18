
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DoorUsed = ReplicatedStorage:WaitForChild("DoorUsed") -- BindableEvent


-- Hardcoded spawn positions
local SPAWN_POSITIONS = {
	Library_Main = Vector3.new(11.4, 0.5, -10),
	Library_basement = Vector3.new(11.4, -79.274, -5.6),
}

----------------------------------------------------
-- Move player to a hardcoded spawn
----------------------------------------------------
local function movePlayerToPosition(player, position)
	if not position then
		warn("No spawn position provided")
		return
	end

	local character = player.Character
	if not character then return end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then return end

	humanoidRootPart.CFrame = CFrame.new(position)
end

----------------------------------------------------
-- Handle door interaction
----------------------------------------------------
local function onDoorActivated(player, doorModel)
	-- Read attributes from the door
	local targetMap = doorModel:GetAttribute("Send")
	local doorType = doorModel:GetAttribute("Type")

	if not targetMap or not doorType then
		warn("Door missing attributes:", doorModel.Name)
		return
	end

	print("Door activated")
	print(" Type:", doorType)
	print(" Sending player to:", targetMap)

	------------------------------------------------
	-- Resolve spawn position
	------------------------------------------------
	local spawnPosition = SPAWN_POSITIONS[targetMap]
	if not spawnPosition then
		warn("No spawn defined for map:", targetMap)
		return
	end

	------------------------------------------------
	-- Transition (map loading stub)
	------------------------------------------------
	print("Transitioning to map:", targetMap)

	-- Real map loading would happen here

	------------------------------------------------
	-- Move player
	------------------------------------------------
	movePlayerToPosition(player, spawnPosition)
end

DoorUsed.Event:Connect(function(player, doorModel)
	onDoorActivated(player, doorModel)
end)




