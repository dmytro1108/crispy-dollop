local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RunService = game:GetService("RunService")

local Remotes = ReplicatedStorage:WaitForChild("remote")
local BossUI = Remotes:WaitForChild("BossUI")
local NoisyToolClick = Remotes:WaitForChild("NoisyToolClick")

-- Grab the existing rig you placed in Workspace
local boss = workspace:WaitForChild("Librarian")
boss.Name = "LibraryBoss"

local humanoid = boss:FindFirstChildOfClass("Humanoid")
local root = boss:FindFirstChild("HumanoidRootPart")

-- Ensure server owns movement (helps stability)
pcall(function()
	root:SetNetworkOwner(nil)
end)

-- Library RECT
local RECT = {
	minX = -140.5,
	maxX = -25.8,
	minZ = -35.1,
	maxZ = 29,
}

local STATE_IDLE = "IDLE"
local STATE_CHASE = "CHASE"
local STATE_LOST = "LOST"

local state = STATE_IDLE
local currentTarget : Player? = nil
local wanderDestination : Vector3? = nil

local LOST_DURATION = 4 -- seconds
local lostStartTime = 0

-- Click tracking
local REQUIRED_CLICKS = 12
local clickCount = {} :: {[Player]: number}
local lastClickTime = {} :: {[Player]: number}

local Workspace = game:GetService("Workspace")

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Blacklist
rayParams.IgnoreWater = true

local Players = game:GetService("Players")

local root = boss:WaitForChild("HumanoidRootPart")

local touchDebounce = {}

local AVOID_DISTANCE = 2
local AVOID_ANGLE = 30 -- degrees left/right

root.Touched:Connect(function(hit)
	local character = hit.Parent
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local player = Players:GetPlayerFromCharacter(character)
	if not player then return end

	-- Only interact while chasing
	if state ~= STATE_CHASE then return end

	-- Debounce
	if touchDebounce[player] then return end
	touchDebounce[player] = true

	-- === EJECT PLAYER UPWARD ===

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp then
		-- Base upward velocity (normal jump ≈ 50)
		local baseUpwardVelocity = 50

		-- Exponential-style boost (×10)
		local launchVelocity = baseUpwardVelocity * 10

		-- Apply vertical velocity ONLY
		hrp.AssemblyLinearVelocity = Vector3.new(
			hrp.AssemblyLinearVelocity.X,
			launchVelocity,
			hrp.AssemblyLinearVelocity.Z
		)

		print("[BOSS INTERACTION] Player launched upward:", player.Name)
	end

	-- Reset debounce after short delay
	task.delay(1.5, function()
		touchDebounce[player] = nil
	end)
end)

local function hasLineOfSight(fromPos: Vector3, targetHRP: BasePart)
	if not targetHRP then
		return false
	end

	-- Raise ray to "eye level"
	local from = fromPos + Vector3.new(0, 4, 0)
	local to = targetHRP.Position + Vector3.new(0, 4, 0)

	-- Ignore boss + target character
	rayParams.FilterDescendantsInstances = {
		boss,
		targetHRP.Parent
	}

	local direction = to - from
	local result = Workspace:Raycast(from, direction, rayParams)

	-- If nothing blocks the ray, we can see the target
	if not result then
		return true
	end

	-- If we directly hit the target character, LOS is valid
	return result.Instance:IsDescendantOf(targetHRP.Parent)
end

local function pointInRectXZ(pos)
	return pos.X >= RECT.minX
		and pos.X <= RECT.maxX
		and pos.Z >= RECT.minZ
		and pos.Z <= RECT.maxZ
end

local function randomPointInLibrary()
	for _ = 1, 80 do
		local x = RECT.minX + math.random() * (RECT.maxX - RECT.minX)
		local z = RECT.minZ + math.random() * (RECT.maxZ - RECT.minZ)

		if pointInRectXZ(Vector3.new(x, 0, z)) then
			return Vector3.new(x, root.Position.Y, z)
		end
	end

	-- fallback (should rarely happen)
	return root.Position
end

-- Force UI OFF for everyone (and for late joiners)
local function setAllOff()
	for _, plr in ipairs(Players:GetPlayers()) do
		BossUI:FireClient(plr, "OFF")
	end
end

Players.PlayerAdded:Connect(function(plr)
	task.wait(0.2)
	BossUI:FireClient(plr, "OFF")
end)

setAllOff()

-- IDLE wander loop
local WANDER_COOLDOWN = 0.5

-- idle or chase or lost 
-- idle or chase or lost 
task.spawn(function()
	while boss.Parent do
		if state == STATE_IDLE then
			-- IDLE: wander
			local dest = randomPointInLibrary()
			humanoid.WalkSpeed = 10
			humanoid:MoveTo(dest)

		elseif state == STATE_CHASE and currentTarget then
			-- CHASE: move toward target (simple, alive, responsive)
			local char = currentTarget.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local hum = char and char:FindFirstChildOfClass("Humanoid")

			-- invalid target → back to idle
			if not hrp or not hum or hum.Health <= 0 then
				state = STATE_IDLE
				currentTarget = nil
				humanoid.WalkSpeed = 10
				setAllOff()

			-- target left library → disengage
			elseif not pointInRectXZ(hrp.Position) then
				state = STATE_IDLE
				currentTarget = nil
				humanoid.WalkSpeed = 10
				setAllOff()

			-- lost LOS → LOST
			elseif not hasLineOfSight(root.Position, hrp) then
				state = STATE_LOST
				wanderDestination = hrp.Position
				lostStartTime = os.clock()
				humanoid.WalkSpeed = 10
				BossUI:FireClient(currentTarget, "LOST")

			else
				-- ACTIVE CHASE (this is the reintegrated part)
				humanoid.WalkSpeed = 24
				humanoid:MoveTo(hrp.Position)
			end

		elseif state == STATE_LOST then
			local elapsed = os.clock() - lostStartTime

			if not wanderDestination then
				state = STATE_IDLE
				humanoid.WalkSpeed = 10
				setAllOff()

			else
				local hrp = nil
				if currentTarget and currentTarget.Character then
					hrp = currentTarget.Character:FindFirstChild("HumanoidRootPart")
				end

				-- re-acquire target
				if hrp and hasLineOfSight(root.Position, hrp) then
					state = STATE_CHASE
					humanoid.WalkSpeed = 24
					BossUI:FireClient(currentTarget, "ON")
					humanoid:MoveTo(hrp.Position)

				elseif elapsed < LOST_DURATION then
					humanoid.WalkSpeed = 10
					if currentTarget then
						BossUI:FireClient(currentTarget, "LOST")
					end
					humanoid:MoveTo(wanderDestination)

					local dist = (root.Position - wanderDestination).Magnitude
					if dist < 5 then
						wanderDestination = nil
						currentTarget = nil
						state = STATE_IDLE
						humanoid.WalkSpeed = 10
						setAllOff()
					end
				else
					wanderDestination = nil
					currentTarget = nil
					state = STATE_IDLE
					humanoid.WalkSpeed = 10
					setAllOff()
				end
			end
		end

		task.wait(WANDER_COOLDOWN)
	end
end)

-- count noisy tool clicks
NoisyToolClick.OnServerEvent:Connect(function(player)
	local now = os.clock()
	clickCount[player] = (clickCount[player] or 0) + 1
	
	-- reset count if too much time has passed since last click
	if lastClickTime[player] then
		if now - lastClickTime[player] > 0.8 then
			clickCount[player] = 1
			print("Player", player.Name, "click count reset due to timeout.")
		end
	end

	lastClickTime[player] = now

	print("Player", player.Name, "click count:", clickCount[player])

	if clickCount[player] >= REQUIRED_CLICKS then
		clickCount[player] = 0
		lastClickTime[player] = nil
		currentTarget = player
		state = STATE_CHASE

		-- UI: AWARE stays active during chase
		print("Player", player.Name, "has alerted the boss!")
		BossUI:FireClient(player, "ON")
	end
end)
