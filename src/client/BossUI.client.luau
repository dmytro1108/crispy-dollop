-- StarterPlayerScripts/BossUI.client.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local RunService = game:GetService("RunService")
local fading = false
-- Your GUI references (these must exist in PlayerGui at runtime)
local gui = player:WaitForChild("PlayerGui"):WaitForChild("Eye")
local picChase = gui:WaitForChild("Chase")
local picLost  = gui:WaitForChild("Lost")

-- HARD DEFAULT OFF (client owns this)
picChase.Visible = false
picLost.Visible = false

print("Eye GUI found?", gui ~= nil)

local BossUI = ReplicatedStorage:WaitForChild("remote"):WaitForChild("BossUI")

local function apply(mode)
	if mode == "OFF" then -- no chase
		picChase.Visible = false
		picLost.Visible = false
	elseif mode == "ON" then -- chase
		picLost.Visible = false
		picChase.Visible = true
	elseif mode == "LOST" then -- lost target
		picChase.Visible = false
		picLost.Visible = true -- make sure this picture has a fade in fade out effect
		if not fading then
			fading = true
			picLost.ImageTransparency = 1
			local alpha = 1
			-- fade in
			while alpha > 0 do
				alpha = alpha - 0.02
				picLost.ImageTransparency = alpha
				RunService.Heartbeat:Wait()
			end
			-- hold
			task.wait(2)
			-- fade out
			while alpha < 1 do
				alpha = alpha + 0.02
				picLost.ImageTransparency = alpha
				RunService.Heartbeat:Wait()
			end
			picLost.Visible = false
			fading = false
		end
	end
end

BossUI.OnClientEvent:Connect(apply)
