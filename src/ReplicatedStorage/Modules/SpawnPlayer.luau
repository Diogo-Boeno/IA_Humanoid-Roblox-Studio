local Players = game:GetService('Players')
local player = Players.LocalPlayer

local StartingPosition = Vector3.new(-40, 0, 0)

local Spawn = {}

function Spawn.Start()
    local char = player.Character or player.CharacterAdded:Wait()
    
    local rootPart = char:WaitForChild("HumanoidRootPart", 5)
    
    if rootPart then
        task.defer(function()
            char:PivotTo(CFrame.new(StartingPosition))
            print("Jogador teleportado para:", StartingPosition)
        end)
    else
        warn("HumanoidRootPart não carregou a tempo!")
    end
end

return Spawn