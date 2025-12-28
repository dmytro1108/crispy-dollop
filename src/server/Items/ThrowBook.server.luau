-- validation + spawn + physics

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Debris = game:GetService("Debris")

local ThrowBookRemote = ReplicatedStorage:WaitForChild("remote"):WaitForChild("ThrowBook")

-- tuning (must conceptually match client)
local BASE_SPEED = 2
local MIN_HEIGHT = 4
local MAX_HEIGHT = 10

local FLIGHT_TIME = 0.2 -- seconds total
local THROW_DISTANCE = 20.45        -- studs (fixed)


local function findEquippedBook(character)
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") and child:GetAttribute("ID") == "old_book" then
			return child
		end
	end
end

local function spawnImpactEmitter(worldPosition)
	local effectsFolder = ServerStorage:FindFirstChild("Effects")
	if not effectsFolder then
		warn("Effects folder missing in ServerStorage")
		return
	end

	local template = effectsFolder:FindFirstChild("Part")
	if not template then
		warn("Emitter Part missing in ServerStorage.Effects")
		return
	end

	-- clone FIRST
	local emitterClone = template:Clone()

	-- parent FIRST (important)
	emitterClone.Parent = workspace

	-- position AFTER parenting
	emitterClone.CFrame = CFrame.new(worldPosition)

	-- FORCE emitters to fire
	for _, obj in ipairs(emitterClone:GetDescendants()) do
		if obj:IsA("ParticleEmitter") then
			-- safest one-shot method
			obj:Emit(50)
		end
	end

	-- cleanup
	Debris:AddItem(emitterClone, 2)
end

ThrowBookRemote.OnServerEvent:Connect(function(player, origin, direction, heightScalar)
	-- validate
	if typeof(origin) ~= "Vector3" then return end
	if typeof(direction) ~= "Vector3" then return end
	if typeof(heightScalar) ~= "number" then return end

	heightScalar = math.clamp(heightScalar, 0, 1)

	local character = player.Character
	if not character then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- consume tool
	local tool = findEquippedBook(character)
	if not tool then return end
	tool:Destroy()

	-- spawn projectile
	local projectile = ServerStorage.Items.old_book_projectile:Clone()
	projectile.Parent = workspace
	projectile.Anchored = true
	projectile.CanCollide = false
	projectile.CFrame = CFrame.new(origin)

	-- direction safety
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 0.01 then
		flat = hrp.CFrame.LookVector * Vector3.new(1,0,1)
	end
	flat = flat.Unit

	local targetPos = origin + flat * THROW_DISTANCE
	local peakHeight = MIN_HEIGHT + (MAX_HEIGHT - MIN_HEIGHT) * heightScalar

	-- raycast params (ignore player + projectile)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Blacklist
	rayParams.FilterDescendantsInstances = { character, projectile }

	-- move along arc deterministically
	task.spawn(function()
		local startTime = os.clock()

		while true do
			local t = (os.clock() - startTime) / FLIGHT_TIME
			if t >= 1 then break end

			local height = math.sin(t * math.pi) * peakHeight
			local pos =
				origin:Lerp(targetPos, t) +
				Vector3.new(0, height, 0)

			-- raycast DOWN to detect impact
			local result = workspace:Raycast(
				pos,
				Vector3.new(0, -3, 0),
				rayParams
			)

			if result then
				-- impact
				spawnImpactEmitter(result.Position)
				projectile:Destroy()
				return
			end

			projectile.Position = pos
			task.wait(0.03) -- fixed timestep (smooth + stable)
		end

		-- fallback impact at end of arc
		local result = workspace:Raycast(
			projectile.Position,
			Vector3.new(0, -10, 0),
			rayParams
		)

		if result then
			spawnImpactEmitter(result.Position)
		end

		projectile:Destroy()
	end)
end)




