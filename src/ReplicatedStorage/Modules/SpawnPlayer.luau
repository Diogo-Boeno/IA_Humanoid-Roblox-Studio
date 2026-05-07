local Players = game:GetService('Players')
local player = Players.LocalPlayer

local StartingPosition = Vector3.new(0, 0, 0)

local Spawn = {}

function Spawn.Start()
    local char = player.Character or player.CharacterAdded:Wait()
    print(char)

    char:PivotTo(CFrame.new(StartingPosition))
end

return Spawn