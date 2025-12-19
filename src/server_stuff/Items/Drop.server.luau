local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DropTool = ReplicatedStorage:WaitForChild("DropTool")

DropTool.OnServerEvent:Connect(function(player, tool)
	-- Validate instance
	if not tool or not tool:IsA("Tool") then return end

	-- Validate ownership
	if tool.Parent ~= player.Character and tool.Parent ~= player.Backpack then
		return
	end

	-- 🔒 SERVER decides to decrement ownership
	tool:Destroy()
end)
