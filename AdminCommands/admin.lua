local Admin = {}

local admins = {
    ["Player1"] = true,
    ["Player2"] = true
}

function Admin.IsAdmin(player)
    return admins[player.Name] == true
end

function Admin.HandleCommand(player, command)
    if not Admin.IsAdmin(player) then return end

    if command == "kick" then
        print(player.Name .. " used kick command!")
        -- Add kick logic here
    elseif command == "fly" then
        print(player.Name .. " used fly command!")
        -- Add fly logic here
    end
end

return Admin
