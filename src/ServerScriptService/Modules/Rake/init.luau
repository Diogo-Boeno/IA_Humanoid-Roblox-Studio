local PathFindingService = game:GetService('PathfindingService')
local Players = game:GetService('Players')

local Killer = {}
Killer.__index = Killer

function Killer.new(model)
    local self = setmetatable({}, Killer)

    self.Config = require(script.Config)
    self.Model = model
    self.Humanoid = model:FindFirstChild('Humanoid')
    self.Root = model:FindFirstChild('HumanoidRootPart')
    self.Target = nil
    self.IsChasing = false

    return self
end

function Killer:Spawn()
    local Config = self.Config

    self.Model:PivotTo(Config.BaseSpawnLocation)
end

function Killer:FindNearestTarget()
    local Config = self.Config
    local maxDistance = Config.MaxChaseDistance

    for _, player in pairs(Players:GetPlayers()) do
        local char = player.Character
        if char and char:FindFirstChild('HumanoidRootPart') then
            local dist = (self.Root.Position - char.HumanoidRootPart.Position).Magnitude
            if dist < maxDistance then
                print('Damage')
            end
        end
    end
end



return Killer