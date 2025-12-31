local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local RunService = game:GetService("RunService")

local Remotes = ReplicatedStorage:WaitForChild("remote")
local BossUI = Remotes:WaitForChild("BossUI")
local NoisyToolClick = Remotes:WaitForChild("NoisyToolClick")

-- Grab the existing rig you placed in Workspace
local boss = workspace:WaitForChild("Librarian")
boss.Name = "LibraryBoss"

local humanoid = boss:FindFirstChildOfClass("Humanoid")
local root = boss:FindFirstChild("HumanoidRootPart")

local BossController = {}
BossController.__index = BossController

-- Ensure server owns movement (helps stability)
pcall(function()
	root:SetNetworkOwner(nil)
end)


-- -151.491, 7, -78.476
-- -14.491, 7, -78.476
-- -14.491, 7, -215.476
-- -150.491, 7, -215.476
-- Library RECT
local RECT = {
	minX = -151.491,
	maxX = -14.491,
	minZ = -215.476,
	maxZ = -78.476,
}

local STATE_IDLE = "IDLE"
local STATE_CHASE = "CHASE"
local STATE_LOST = "LOST"

local state = STATE_IDLE

local currentTarget : Player? = nil
local wanderDestination : Vector3? = nil

local LOST_DURATION = 1 -- seconds
local lostStartTime = 0
local WANDER_RADIUS = 25
local WANDER_COOLDOWN = 4
local CHASE_REPATH_INTERVAL = 0.5


-- Click tracking
local REQUIRED_CLICKS = 12
local clickCount = {} :: {[Player]: number}
local lastClickTime = {} :: {[Player]: number}

local Workspace = game:GetService("Workspace")

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Blacklist
rayParams.IgnoreWater = true

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

local function pointInRectXZ(pos)
	return pos.X >= RECT.minX
		and pos.X <= RECT.maxX
		and pos.Z >= RECT.minZ
		and pos.Z <= RECT.maxZ
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

function BossController.new(boss)
	local self = setmetatable({}, BossController)

	self.Model = boss
	self.Humanoid = boss:FindFirstChildOfClass("Humanoid")
	self.RootPart = boss:FindFirstChild("HumanoidRootPart")

	self.State = STATE_IDLE
	self.Target = nil

	self.HomePosition = self.RootPart.Position
	self.wanderTimer = 0
	self.moving = false

	self.lastPathTime = 0
	self.lostTimer = 0

	self.Path = PathfindingService:CreatePath({
		AgentRadius = 2,
		AgentHeight = 5,
		AgentCanJump = true,
		WaypointSpacing = 4,
	})

	self.waypoints = nil
	self.waypointIndex = 1

	return self
end

function BossController:SetState(newState, target)
	if self.State == newState then return end

	self.State = newState
	self.Target = target or nil

	if newState == STATE_IDLE then
		self.moving = false
		self.Target = nil
	elseif newState == STATE_CHASE then
		self.lastPathTime = 0
		self.moving = false -- 🔴 REQUIRED

	elseif newState == STATE_LOST then
		self.lostTimer = LOST_DURATION
	end
end

function BossController:ComputePath(destination)
	local success = pcall(function()
		self.Path:ComputeAsync(self.RootPart.Position, destination)
	end)

	if not success or self.Path.Status ~= Enum.PathStatus.Success then
		return false
	end

	self.waypoints = self.Path:GetWaypoints()
	self.waypointIndex = 1
	return true
end

function BossController:FollowPath()
	if not self.waypoints or #self.waypoints == 0 then
		self.moving = false
		return
	end

	self.moving = true

	self.Humanoid:MoveTo(self.waypoints[self.waypointIndex].Position)

	self.Humanoid.MoveToFinished:Once(function(reached)
		if not reached then
			self.moving = false
			return
		end

		self.waypointIndex += 1

		if self.waypointIndex > #self.waypoints then
			self.moving = false
			return
		end

		self:FollowPath()
	end)
end

function BossController:MoveTo(destination, force)
    if self.moving and not force then return end
	if self:ComputePath(destination) then
		self:FollowPath()
	end
end

local controller = BossController.new(boss)
local lastTick = os.clock()
local idleFrozen = false

function BossController:Stop()
	self.moving = false
	self.waypoints = nil
	self.waypointIndex = 1

	-- HARD cancel humanoid movement
	self.Humanoid:MoveTo(self.RootPart.Position)
end
-- --------------------------------------------
-- IDLE LOGIC
-- --------------------------------------------
local IDLE_SPAWNS = {
	Vector3.new(-28.098, 0.5, -149.533),
	Vector3.new(-43.15, 0.5, -127.417),
	Vector3.new(-28.098, 0.5, -149.533),
	Vector3.new(-44.078, 0.5, -88.37),
	Vector3.new(-82.578, 0.5, -177.001),
	Vector3.new(-113.155, 0.5, -194.846),
	Vector3.new(-140.491, 0.5, -206.338),
	Vector3.new(-141.895, 0.5, -162.576),
	Vector3.new(-105.832, 0.5, -146.227),
	Vector3.new(-90.975, 0.5, -115.447),
	Vector3.new(-141.895, 0.5, -112.508),
	Vector3.new(-82.074, 0.5, -88.37),
	Vector3.new(-44.078, 0.5, -190.806),
}
local idleTick = 0
local idleDespawned = false
local idleSpawnIndex = 1

-- how many IDLE loops before toggle
local IDLE_TOGGLE_TICKS = 1  -- adjust later, this WILL work

local function setBossVisible(visible)
	for _, d in ipairs(boss:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Transparency = visible and 0 or 1
			d.CanCollide = visible
		end
	end
end

local function teleportBoss(pos)
	root.CFrame = CFrame.new(pos)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
end

local function applyIdleSpawnState(despawn)
	if despawn then
		setBossVisible(false)
	else
		idleSpawnIndex += 1
		if idleSpawnIndex > #IDLE_SPAWNS then
			idleSpawnIndex = 1
		end

		teleportBoss(IDLE_SPAWNS[idleSpawnIndex])
		setBossVisible(true)
		controller:Stop()
	end
end

function BossController:UpdateIdle(dt)
	-- Wander timer
	self.wanderTimer -= dt
	if self.wanderTimer > 0 then return end
	if self.moving then return end

	self.wanderTimer = WANDER_COOLDOWN

	local randomPos = self.HomePosition + Vector3.new(
		math.random(-WANDER_RADIUS, WANDER_RADIUS),
		0,
		math.random(-WANDER_RADIUS, WANDER_RADIUS)
	)

	self:MoveTo(randomPos)
end
-- --------------------------------------------
function BossController:UpdateChase(dt)
	if not self.Target then
		self:SetState(STATE_IDLE)
		return
	end

	local targetRoot = self.Target:FindFirstChild("HumanoidRootPart")
	if not targetRoot then
		self:SetState(STATE_IDLE)
		return
	end

	-- Throttle path recompute
	self.lastPathTime -= dt
	if self.lastPathTime <= 0 then
		self.lastPathTime = CHASE_REPATH_INTERVAL
		self:MoveTo(targetRoot.Position, true) -- force repath
	end
end

function BossController:UpdateLost(dt)
	self.lostTimer -= dt

	if self.lostTimer <= 0 then
		self:SetState(STATE_IDLE)
		return
	end

	if self.moving then return end

	-- Just stand and "listen" during lost, or re-walk last location if you want
end

-- idle or chase or lost 
task.spawn(function()
	while boss.Parent do
		local now = os.clock()
		local dt = now - lastTick
		lastTick = now

		if state == STATE_IDLE and not idleFrozen then
			-- IDLE: wander
			
			idleTick += 1

			-- 🔴 VISION CHECK FIRST
			for _, player in ipairs(Players:GetPlayers()) do
				local char = player.Character
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				local hum = char and char:FindFirstChildOfClass("Humanoid")

				if hrp and hum and hum.Health > 0 then
					if hasLineOfSight(root.Position, hrp) then
						-- exit idle completely
						idleFrozen = true
						idleDespawned = false
						setBossVisible(true)

						currentTarget = player
						controller:Stop()
						controller.Target = char

						state = STATE_CHASE
						controller.lastPathTime = 0
						BossUI:FireClient(player, "ON")
						break
					end
				end
			end

			-- ✅ ONLY RUN IF STILL IDLE
			if state == STATE_IDLE then
				-- despawn / respawn
				if idleTick % IDLE_TOGGLE_TICKS == 0 then
					idleDespawned = not idleDespawned
					applyIdleSpawnState(idleDespawned)
				end

				-- wandering
				if not idleDespawned then
					humanoid.WalkSpeed = 6
					controller:UpdateIdle(dt)
				end
			end
		elseif state == STATE_CHASE and currentTarget then
			-- CHASE: move toward target (simple, alive, responsive)
			controller.Target = currentTarget.Character

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

			-- LOST
			elseif not hasLineOfSight(root.Position, hrp) then
				state = STATE_LOST
				wanderDestination = hrp.Position
				lostStartTime = os.clock()
				humanoid.WalkSpeed = 10
				BossUI:FireClient(currentTarget, "LOST")

			else
				-- ACTIVE CHASE
				humanoid.WalkSpeed = 36
				controller.Target = currentTarget.Character
				controller:UpdateChase(dt)
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
					controller.Target = currentTarget.Character
					controller:UpdateChase(dt)

				elseif elapsed < LOST_DURATION then
					humanoid.WalkSpeed = 10
					if currentTarget then
						BossUI:FireClient(currentTarget, "LOST")
					end

					controller.lostTimer = LOST_DURATION
					controller:UpdateLost(dt)

					local dist = (root.Position - wanderDestination).Magnitude
					if dist < 5 then
						wanderDestination = nil
						currentTarget = nil
						state = STATE_IDLE
						humanoid.WalkSpeed = 10
						setAllOff()
					end
					-- give up after timeout
				else
					wanderDestination = nil
					currentTarget = nil
					state = STATE_IDLE
					idleFrozen = false
					humanoid.WalkSpeed = 10
					setAllOff()
				end
			end
		end

		task.wait(.01)
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
