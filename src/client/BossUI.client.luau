-- StarterPlayerScripts/BossUI.client.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local bossUIRemote = ReplicatedStorage:WaitForChild("remote"):WaitForChild("BossUI")

-- TODO: replace these with your actual GUI references
local gui = game.Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("BossGui")
local picChase = gui:WaitForChild("Caught") -- first picture
local picLost  = gui:WaitForChild("Searching")  -- second picture

local blinkTween

local function stopBlink()
	if blinkTween then
		blinkTween:Cancel()
		blinkTween = nil
	end
end

local function startBlink()
	stopBlink()
	picLost.Visible = true
	picLost.ImageTransparency = 0.2

	-- simple blink loop by toggling transparency
	task.spawn(function()
		while picLost.Visible do
			picLost.ImageTransparency = 0.2
			task.wait(0.25)
			picLost.ImageTransparency = 0.9
			task.wait(0.25)
		end
	end)
end

bossUIRemote.OnClientEvent:Connect(function(mode)
	-- mode = "CHASE" | "LOST" | "OFF"
	if mode == "CHASE" then
		stopBlink()
		picLost.Visible = false
		picChase.Visible = true
		picChase.ImageTransparency = 0
	elseif mode == "LOST" then
		picChase.Visible = false
		startBlink()
	elseif mode == "OFF" then
		stopBlink()
		picChase.Visible = false
		picLost.Visible = false
	end
end)
