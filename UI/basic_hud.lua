local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local ScreenGui = Instance.new("ScreenGui", playerGui)
local TextLabel = Instance.new("TextLabel", ScreenGui)

TextLabel.Size = UDim2.new(0, 200, 0, 50)
TextLabel.Position = UDim2.new(0, 10, 0, 10)
TextLabel.Text = "Health: 100"
TextLabel.TextColor3 = Color3.new(1, 0, 0)
