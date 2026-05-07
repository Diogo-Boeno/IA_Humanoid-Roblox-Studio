local Players = game:GetService('Players')
local player = Players.LocalPlayer

local StartingPosition = Vector3.new(-40, 0, 0)

local Spawn = {}

function Spawn.Start()
    local char = player.Character or player.CharacterAdded:Wait(0.01)
    print(char)

    char:PivotTo(CFrame.new(StartingPosition))
end

return Spawn