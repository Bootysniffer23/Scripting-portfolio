local Players = game:GetService("Players")

Players.PlayerAdded:Connect(function(player)
    player.Chatted:Connect(function(message)
        local lowerMsg = message:lower()

        if lowerMsg == "/dance" then
            local character = player.Character
            if character then
                local humanoid = character:FindFirstChildOfClass("Humanoid")
                if humanoid then
                    humanoid:LoadAnimation(script.DanceAnimation):Play()
                end
            end
        elseif lowerMsg == "/wave" then
            print(player.Name .. " waved!")
            -- Add wave animation or effect here
        end
    end)
end)
