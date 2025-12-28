-- arc + input

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local ThrowBookRemote = ReplicatedStorage:WaitForChild("remote"):WaitForChild("ThrowBook")

local THROW_DISTANCE = 10.45        -- studs (fixed)
local MIN_HEIGHT = 4    
local MAX_HEIGHT = 10
local ARC_POINTS = 250           -- resolution of preview
local ARC_COLOR = Color3.fromRGB(0, 255, 90)
local ARC_THICKNESS = .1

local aiming = false
local arcParts = {}

local function hasBook()
    local char = player.Character
    if not char then return false end
    return char:FindFirstChild("old_book") ~= nil
end

local function getHeightScalar()
    local cam = workspace.CurrentCamera
    local y = math.clamp(cam.CFrame.LookVector.Y, -0.2, 0.8)
    return (y + 0.2) / 1.0
end

local function createArcPart()
    local part = Instance.new("Part")
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.CastShadow = false
    part.Size = Vector3.new(ARC_THICKNESS, ARC_THICKNESS, ARC_THICKNESS)
    part.Color = ARC_COLOR
    return part
end

local function showArc(targetPos)
    for _, part in ipairs(arcParts) do
        part:Destroy()
    end
    arcParts = {}
    local char = player.Character
    if not char then return end

    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local startPos = hrp.Position + Vector3.new(0, 2, 0)

    local heightScalar = getHeightScalar()
    local peakHeight = MIN_HEIGHT + (MAX_HEIGHT - MIN_HEIGHT) * heightScalar

    for i = 0, ARC_POINTS do
        local t = i / ARC_POINTS
        local height = math.sin(t * math.pi) * peakHeight
        local point = startPos:Lerp(targetPos, t) + Vector3.new(0, height, 0)

        local arcPart = createArcPart()
        arcPart.Position = point
        arcPart.Parent = workspace
        table.insert(arcParts, arcPart)
    end
end


local function hideArc()
    for _, part in ipairs(arcParts) do
        part:Destroy()
    end
    arcParts = {}
end

-- compute the arc 
local function computeThrowData()
    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local origin = hrp.Position + Vector3.new(0, 2, 0)

    local rawDir = mouse.UnitRay.Direction
    local flat = Vector3.new(rawDir.X, 0, rawDir.Z)
    if flat.Magnitude < 0.01 then
        flat = hrp.CFrame.LookVector * Vector3.new(1,0,1)
    end
    local flatDir = flat.Unit


    local heightScalar = getHeightScalar()

    return origin, flatDir, heightScalar
end


-- mouse input
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.UserInputType ~= Enum.UserInputType.MouseButton2 then return end
    if not hasBook() then return end

    aiming = true
end)


-- aiming loop
RunService.RenderStepped:Connect(function()
    if not aiming then return end

    local origin, dir, heightScalar = computeThrowData()
    if not origin then return end

    local targetPos = origin + dir * THROW_DISTANCE
    showArc(targetPos)
end)


-- release to throw
UserInputService.InputEnded:Connect(function(input, gp)
    if gp then return end
    if input.UserInputType ~= Enum.UserInputType.MouseButton2 then return end

    if not aiming then return end
    aiming = false
    hideArc()

    local origin, dir, heightScalar = computeThrowData()
    if not origin then return end

    ThrowBookRemote:FireServer(origin, dir, heightScalar)
end)
