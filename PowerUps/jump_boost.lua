-- Jump Boost Power-Up Script

local powerUp = script.Parent  -- The part players touch to get the boost
local jumpBoostAmount = 100    -- How much to increase the jump power
local boostDuration = 10       -- How long the boost lasts (seconds)

local Players = game:GetService("Players")

powerUp.Touched:Connect(function(hit)
    local character = hit.Parent
    local player = Players:GetPlayerFromCharacter(character)

    if player then
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            -- Apply jump boost
            local originalJumpPower = humanoid.JumpPower
            humanoid.JumpPower = originalJumpPower + jumpBoostAmount

            -- Optional: Hide the power-up so it can't be reused immediately
            powerUp.Transparency = 1
            powerUp.CanCollide = false

            -- Wait for boost duration, then revert jump power
            wait(boostDuration)
            humanoid.JumpPower = originalJumpPower

            -- Restore the power-up after some cooldown
            wait(5)
            powerUp.Transparency = 0
            powerUp.CanCollide = true
        end
    end
end)
