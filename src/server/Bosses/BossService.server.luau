-- ServerScriptService/BossService.server.lua
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")

-- Remotes
local RemotesFolder = ReplicatedStorage:WaitForChild("remote")
local NoisyToolClick = RemotesFolder:WaitForChild("NoisyToolClick")
local BossUI = RemotesFolder:WaitForChild("BossUI")

-- =========================
-- CONFIG
-- =========================
local REQUIRED_CLICKS = 12

local STATES = {
	Idle = "Idle",
	Chase = "Chase",
	Lost = "Lost",
}

-- Boss movement constraints
local FIXED_Y = 43.696
local WANDER_COOLDOWN = 2.5
local WANDER_RADIUS_JITTER = 2

local PATH_RECOMPUTE_COOLDOWN = 0.5
local WAYPOINT_REACH_DIST = 2.5

-- Optional: forbid boss from being blocked by tiny clutter (your "temporary working basic")
local BOSS_NONCOLLIDE = true

-- Library polygon (XZ only) - you gave 4 corners
local POLY = {
	Vector2.new(-39.05,  -74.314),
	Vector2.new(-18.076, -152.59),
	Vector2.new(-178.42, -195.554),
	Vector2.new(-199.851,-115.576),
}

-- Interior "hole" simplification: treat as a forbidden circle around the interior point
local INTERIOR_CENTER = Vector2.new(-105.301, -143.247)
local INTERIOR_RADIUS = 10 -- tweak as you like

-- Aggro range for “can see” checks (optional)
local AGGRO_RANGE = 250

-- =========================
-- UTIL: point in polygon (ray casting)
-- =========================
local function pointInPolygonXZ(point2, poly)
	local inside = false
	local j = #poly
	for i = 1, #poly do
		local xi, zi = poly[i].X, poly[i].Y
		local xj, zj = poly[j].X, poly[j].Y
		local intersect =
			((zi > point2.Y) ~= (zj > point2.Y)) and
			(point2.X < (xj - xi) * (point2.Y - zi) / ((zj - zi) ~= 0 and (zj - zi) or 1e-9) + xi)
		if intersect then
			inside = not inside
		end
		j = i
	end
	return inside
end

local function inLibraryXZ(pos3)
	local p = Vector2.new(pos3.X, pos3.Z)
	if not pointInPolygonXZ(p, POLY) then
		return false
	end
	-- reject interior circle
	if (p - INTERIOR_CENTER).Magnitude <= INTERIOR_RADIUS then
		return false
	end
	return true
end

local function getPolyBounds(poly)
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

local minX, maxX, minZ, maxZ = getPolyBounds(POLY)

local function randomWanderPoint()
	-- rejection sampling in bounding box
	for _ = 1, 60 do
		local x = math.random() * (maxX - minX) + minX
		local z = math.random() * (maxZ - minZ) + minZ
		local p3 = Vector3.new(x, FIXED_Y, z)
		if inLibraryXZ(p3) then
			return p3
		end
	end
	-- fallback: center-ish
	return Vector3.new((minX + maxX)/2, FIXED_Y, (minZ + maxZ)/2)
end

-- =========================
-- Boss spawn / references
-- =========================
local bossTemplate = ServerStorage:WaitForChild("Bosses"):WaitForChild("LibraryBoss")
local boss = bossTemplate:Clone()
boss.Name = "LibraryBoss"
boss.Parent = workspace

local humanoid = boss:FindFirstChildOfClass("Humanoid")
local root = boss:WaitForChild("HumanoidRootPart")
humanoid.RootPart = root

humanoid.AutoRotate = false

-- (optional) make boss not collide with world as your “basic” unblock
if BOSS_NONCOLLIDE then
	for _, d in ipairs(boss:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
		end
	end
end

-- lock yaw (no turning)
local lockedYaw = root.Orientation.Y

-- clamp Y + lock rotation continuously
RunService.Heartbeat:Connect(function()
	if not root.Parent then return end
	local pos = root.Position
	root.CFrame = CFrame.new(Vector3.new(pos.X, FIXED_Y, pos.Z)) * CFrame.Angles(0, math.rad(lockedYaw), 0)
end)

-- =========================
-- Target tracking
-- =========================
local clickCounts = {} :: {[Player]: number}
local currentTarget : Player? = nil
local lastSeenPos : Vector3? = nil

-- =========================
-- LOS check (simple raycast)
-- =========================
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function hasLineOfSightTo(player: Player)
	local char = player.Character
	if not char then return false end
	local targetRoot = char:FindFirstChild("HumanoidRootPart")
	local targetHum = char:FindFirstChildOfClass("Humanoid")
	if not targetRoot or not targetHum or targetHum.Health <= 0 then return false end

	local origin = root.Position
	local dir = targetRoot.Position - origin
	if dir.Magnitude > AGGRO_RANGE then return false end

	-- exclude boss + target character from ray
	rayParams.FilterDescendantsInstances = { boss, char }

	local result = workspace:Raycast(origin, dir, rayParams)
	-- If ray hits something before reaching the player, LOS is blocked
	return result == nil
end

local function isTargetValid(player: Player)
	local char = player.Character
	if not char then return false end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum or hum.Health <= 0 then return false end
	if not inLibraryXZ(hrp.Position) then
		return false
	end
	return true
end

-- =========================
-- Path movement
-- =========================
local agentParams = {
	AgentRadius = 2,
	AgentHeight = 6,
	AgentCanJump = true,
	AgentJumpHeight = 6, -- clears “table-ish” obstacles
	AgentMaxSlope = 30,
}

local activeWaypoints = nil
local waypointIndex = 1

local function computePathTo(dest: Vector3)
	local path = PathfindingService:CreatePath(agentParams)
	path:ComputeAsync(root.Position, dest)
	if path.Status ~= Enum.PathStatus.Success then
		return nil
	end
	return path:GetWaypoints()
end

local function moveAlongWaypoints(waypoints)
	if not waypoints or #waypoints == 0 then return true end

	local wp = waypoints[waypointIndex]
	if not wp then
		return true
	end

	if wp.Action == Enum.PathWaypointAction.Jump then
		humanoid.Jump = true
	end

	humanoid:MoveTo(Vector3.new(wp.Position.X, FIXED_Y, wp.Position.Z))

	local dist = (root.Position - Vector3.new(wp.Position.X, FIXED_Y, wp.Position.Z)).Magnitude
	if dist <= WAYPOINT_REACH_DIST then
		waypointIndex += 1
	end

	return waypointIndex > #waypoints
end

-- =========================
-- State machine
-- =========================
local state = STATES.Idle
local wanderTimer = 0
local lastPathCompute = 0

local function setState(newState, targetPlayer)
	if state == newState then return end
	state = newState

	if newState == STATES.Idle then
		currentTarget = nil
		lastSeenPos = nil
		activeWaypoints = nil
		waypointIndex = 1
		humanoid:MoveTo(root.Position)
		-- turn off UI for everyone (safe + simple)
		for _, plr in ipairs(Players:GetPlayers()) do
			BossUI:FireClient(plr, "OFF")
		end

	elseif newState == STATES.Chase then
		currentTarget = targetPlayer
		activeWaypoints = nil
		waypointIndex = 1
		lastPathCompute = 0

		-- UI: chased player sees CHASE
		for _, plr in ipairs(Players:GetPlayers()) do
			BossUI:FireClient(plr, "OFF")
		end
		if currentTarget then
			BossUI:FireClient(currentTarget, "CHASE")
		end

	elseif newState == STATES.Lost then
		activeWaypoints = nil
		waypointIndex = 1
		lastPathCompute = 0

		-- UI: previously chased player sees LOST blink
		if currentTarget then
			BossUI:FireClient(currentTarget, "LOST")
		end
	end
end

-- =========================
-- Click counting (SERVER)
-- =========================
local function resetClicks(player)
	clickCounts[player] = 0
end

Players.PlayerRemoving:Connect(function(p)
	clickCounts[p] = nil
	if currentTarget == p then
		setState(STATES.Idle)
	end
end)
NoisyToolClick.OnServerEvent:Connect(function(player, tool)
	-- Validate tool + equipped
	if not tool or not tool:IsA("Tool") then return end

	local char = player.Character
	if not char then return end
	if tool.Parent ~= char then
		-- not equipped => ignore
		return
	end

	-- Validate this is the noisy tool (name or attribute)
	-- You can tighten this by checking an attribute ID.
	if tool.Name ~= "noisy_horn" then return end

	-- If player is outside library, don't count (matches “if leave library they will not be chased”)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp or not inLibraryXZ(hrp.Position) then
		return
	end

	clickCounts[player] = (clickCounts[player] or 0) + 1

	if clickCounts[player] >= REQUIRED_CLICKS then
		-- “noisiest”: last player to reach 12 becomes target
		resetClicks(player)

		-- Engage chase immediately
		setState(STATES.Chase, player)
	end
end)

-- =========================
-- Main loop
-- =========================
task.spawn(function()
	local last = os.clock()
	while boss.Parent do
		local now = os.clock()
		local dt = now - last
		last = now

		if state == STATES.Idle then
			-- wander
			wanderTimer -= dt
			if wanderTimer <= 0 then
				wanderTimer = WANDER_COOLDOWN + math.random(-WANDER_RADIUS_JITTER, WANDER_RADIUS_JITTER)
				local dest = randomWanderPoint()
				humanoid:MoveTo(dest)
			end

		elseif state == STATES.Chase then
			if not currentTarget or not isTargetValid(currentTarget) then
				-- either dead, gone, or left library
				if currentTarget and currentTarget.Character and currentTarget.Character:FindFirstChild("HumanoidRootPart") then
					lastSeenPos = currentTarget.Character.HumanoidRootPart.Position
				else
					lastSeenPos = root.Position
				end
				setState(STATES.Lost)
			else
				local targetHrp = currentTarget.Character.HumanoidRootPart
				-- LOS gate: if blocked => Lost (but remember last seen)
				if not hasLineOfSightTo(currentTarget) then
					lastSeenPos = targetHrp.Position
					setState(STATES.Lost)
				else
					lastSeenPos = targetHrp.Position

					-- recompute path on cooldown
					if (now - lastPathCompute) >= PATH_RECOMPUTE_COOLDOWN or not activeWaypoints then
						lastPathCompute = now
						activeWaypoints = computePathTo(lastSeenPos)
						waypointIndex = 1
					end

					-- follow path (fallback: MoveTo direct)
					if activeWaypoints then
						local done = moveAlongWaypoints(activeWaypoints)
						if done then
							activeWaypoints = nil
						end
					else
						humanoid:MoveTo(Vector3.new(lastSeenPos.X, FIXED_Y, lastSeenPos.Z))
					end
				end
			end

		elseif state == STATES.Lost then
			-- re-acquire if target becomes visible again AND still in library
			if currentTarget and isTargetValid(currentTarget) and hasLineOfSightTo(currentTarget) then
				setState(STATES.Chase, currentTarget)
			else
				-- go to lastSeenPos, then Idle
				if not lastSeenPos then
					setState(STATES.Idle)
				else
					if (now - lastPathCompute) >= PATH_RECOMPUTE_COOLDOWN or not activeWaypoints then
						lastPathCompute = now
						activeWaypoints = computePathTo(lastSeenPos)
						waypointIndex = 1
					end

					local reached = false
					if activeWaypoints then
						reached = moveAlongWaypoints(activeWaypoints)
						if reached then
							activeWaypoints = nil
						end
					else
						humanoid:MoveTo(Vector3.new(lastSeenPos.X, FIXED_Y, lastSeenPos.Z))
						reached = (root.Position - Vector3.new(lastSeenPos.X, FIXED_Y, lastSeenPos.Z)).Magnitude <= 4
					end

					if reached then
						setState(STATES.Idle)
					end
				end
			end
		end

		task.wait(0.1)
	end
end)
