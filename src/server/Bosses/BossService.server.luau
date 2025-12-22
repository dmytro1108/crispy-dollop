local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

-- Library polygon (XZ)
local POLY = {
	Vector2.new(-39.05,  -74.314),
	Vector2.new(-18.076, -152.59),
	Vector2.new(-178.42, -195.554),
	Vector2.new(-199.851,-115.576),
}

local STATE_IDLE = "IDLE"
local STATE_CHASE = "CHASE"
local STATE_LOST = "LOST"

local state = STATE_IDLE
local currentTarget : Player? = nil
local wanderDestination : Vector3? = nil

local LOST_DURATION = 4 -- seconds
local lostStartTime = 0

local INTERACT_DISTANCE = 4 -- studs (very close)
local interactionCooldown = {} -- [Player] = lastTime
local INTERACT_COOLDOWN = 1.5 -- seconds

-- Click tracking
local REQUIRED_CLICKS = 12
local clickCount = {} :: {[Player]: number}

local Workspace = game:GetService("Workspace")

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Blacklist
rayParams.IgnoreWater = true

local Players = game:GetService("Players")

local root = boss:WaitForChild("HumanoidRootPart")

local touchDebounce = {}

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


local function pointInPolygonXZ(p, poly)
	local inside = false
	local j = #poly
	for i = 1, #poly do
		local xi, zi = poly[i].X, poly[i].Y
		local xj, zj = poly[j].X, poly[j].Y
		local intersect =
			((zi > p.Y) ~= (zj > p.Y)) and
			(p.X < (xj - xi) * (p.Y - zi) / ((zj - zi) ~= 0 and (zj - zi) or 1e-9) + xi)
		if intersect then inside = not inside end
		j = i
	end
	return inside
end

local function bounds(poly)
	local minX, maxX = math.huge, -math.huge
	local minZ, maxZ = math.huge, -math.huge
	for _, v in ipairs(poly) do
		minX = math.min(minX, v.X)
		maxX = math.max(maxX, v.X)
		minZ = math.min(minZ, v.Y)
		maxZ = math.max(maxZ, v.Y)
	end
	return minX, maxX, minZ, maxZ
end

local minX, maxX, minZ, maxZ = bounds(POLY)

local function randomPointInLibrary()
	for _ = 1, 80 do
		local x = minX + math.random() * (maxX - minX)
		local z = minZ + math.random() * (maxZ - minZ)
		local p2 = Vector2.new(x, z)
		if pointInPolygonXZ(p2, POLY) then
			-- keep Y as whatever your floor is; we are NOT clamping yet
			return Vector3.new(x, root.Position.Y, z)
		end
	end
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
task.spawn(function()
	while boss.Parent do
		if state == STATE_IDLE then
			-- IDLE: wander
			local dest = randomPointInLibrary()
			humanoid.WalkSpeed = 10
			humanoid:MoveTo(dest)

		elseif state == STATE_CHASE and currentTarget then
			-- CHASE: move toward target
			local char = currentTarget.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local hum = char and char:FindFirstChildOfClass("Humanoid")
		
			if not hrp or not hum or hum.Health <= 0 then
				-- target invalid → back to idle
				-- default walking speed
				humanoid.WalkSpeed = 10
				state = STATE_IDLE
				currentTarget = nil
				setAllOff()
			else
				-- if target leaves library → immediate disengage
				if not pointInPolygonXZ(
					Vector2.new(hrp.Position.X, hrp.Position.Z),
					POLY
				) then
					-- reset walking speed
					humanoid.WalkSpeed = 10
					-- lost them
					state = STATE_IDLE
					currentTarget = nil
					setAllOff()
				else
					-- adjust the speed of the boss while chasing
					if hrp and hasLineOfSight(root.Position, hrp) then
						humanoid.WalkSpeed = 24
						humanoid:MoveTo(hrp.Position)
						
					else
						-- lost sight, go to LOST state
						state = STATE_LOST
						wanderDestination = hrp.Position
						lostStartTime = os.clock()						
						humanoid.WalkSpeed = 10
						BossUI:FireClient(currentTarget, "LOST")
					end
				end
			end
		elseif state == STATE_LOST then -- go to the last place the player was seen
			local elapsed = os.clock() - lostStartTime
			-- NO destination, go back to idle.
			if not wanderDestination then
				state = STATE_IDLE
				humanoid.WalkSpeed = 10
				setAllOff()

			else
				-- re-acquire the player
				local hrp = nil
				if currentTarget and currentTarget.Character then
					hrp = currentTarget.Character:FindFirstChild("HumanoidRootPart")
				end

				-- switch back to CHASE.
				if hrp and hasLineOfSight(root.Position, hrp) then
					state = STATE_CHASE
					humanoid.WalkSpeed = 24
					BossUI:FireClient(currentTarget, "ON")
					humanoid:MoveTo(hrp.Position)

				else
					if elapsed < LOST_DURATION then
						-- remain LOST and walk toward wanderDestination
						humanoid.WalkSpeed = 10

						-- Optional: only tell the client LOST while we are lost
						-- (This can be spammy if called every loop, but it's simple and safe.)
						if currentTarget then
							BossUI:FireClient(currentTarget, "LOST")
						end

						humanoid:MoveTo(wanderDestination)

						-- reached last spot and did not find the player, IDLE
						local dist = (root.Position - wanderDestination).Magnitude
						if dist < 5 then
							wanderDestination = nil
							currentTarget = nil
							state = STATE_IDLE
							humanoid.WalkSpeed = 10
							setAllOff()
						end
					else
						-- give up, back to IDLE
						wanderDestination = nil
						currentTarget = nil
						state = STATE_IDLE
						humanoid.WalkSpeed = 10
						setAllOff()
					end
				end
			end
		end
		task.wait(WANDER_COOLDOWN)
	end
end)

-- count noisy tool clicks
NoisyToolClick.OnServerEvent:Connect(function(player)
	clickCount[player] = (clickCount[player] or 0) + 1
	print("Player", player.Name, "click count:", clickCount[player])
	if clickCount[player] >= REQUIRED_CLICKS then
		clickCount[player] = 0
		currentTarget = player
		state = STATE_CHASE

		-- UI: AWARE stays active during chase
		print("Player", player.Name, "has alerted the boss!")
		BossUI:FireClient(player, "ON")
	end
end)

