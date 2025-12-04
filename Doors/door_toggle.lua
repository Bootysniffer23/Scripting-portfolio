local button = script.Parent.Button
local door = script.Parent.Door
local open = false

button.ClickDetector.MouseClick:Connect(function()
    if open then
        door.Position = door.Position - Vector3.new(0, 5, 0) -- Close door
        open = false
    else
        door.Position = door.Position + Vector3.new(0, 5, 0) -- Open door
        open = true
    end
end)
