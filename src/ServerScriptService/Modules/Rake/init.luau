local PathfindingService = game:GetService('PathfindingService')
local Players = game:GetService('Players')

local Killer = {}
Killer.__index = Killer

local States = {
    Idle = 'Idle',
    Patrol = 'Patrol',
    Suspicious = 'Suspicious',
    Chase = 'Chase',
    Attack = 'Attack'
}

function Killer.new(model)
    local self = setmetatable({}, Killer)

    self.Config = require(script.Config)
    self.Model = model
    self.Humanoid = model:FindFirstChild('Humanoid')
    self.Root = model:FindFirstChild('HumanoidRootPart')
    self.Target = nil
    self.State = States.Idle
    self.LastKnownPosition = nil
    self.PatrolIndex = 1

    return self
end

function Killer:Spawn()
    local Config = self.Config

    self.Model:PivotTo(Config.BaseSpawnLocation)
end

function Killer:HasLineOfSight(targetRoot)
    local origin = self.Root.Position
    local direction = (targetRoot.Position - origin)

    local rayParams = RaycastParams.new()
    rayParams.FilterDescendantsInstances = {self.Model}
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
end

function Killer:FindNearestTarget()
    local maxDistance = self.Config.MaxChaseDistance
    local nearest = nil

    for _, player in pairs(Players:GetPlayers()) do
        local char = player.Character
        if char and char:FindFirstChild('HumanoidRootPart') then
            local dist = (self.Root.Position - char.HumanoidRootPart.Position).Magnitude
            if dist < maxDistance then
                maxDistance = dist
                nearest = player
            end
        end
    end

    return nearest
end

function Killer:Chase()
    local path = PathfindingService:CreatePath({
        AgentHeight = 5,
        AgentRadius = 2,
        AgentCanJump = true,
    })

    while true do
        local target = self:FindNearestTarget()

        if target then
            local targetRoot = target.Character and target.Character:FindFirstChild('HumanoidRootPart')
            if targetRoot then
                local success, err = pcall(function()
                    path:ComputeAsync(self.Root.Position, targetRoot.Position)
                end)

                if success and path.Status == Enum.PathStatus.Success then
                    local waypoints = path:GetWaypoints()

                    for _, waypoint in pairs(waypoints) do
                        if waypoint.Action == Enum.PathWaypointAction.Jump then
                            self.Humanoid.Jump = true
                        end
                        self.Humanoid:MoveTo(waypoint.Position)
                        self.Humanoid.MoveToFinished:Wait()
                    end
                end
            end
        end

        task.wait(0.5)
    end
end

return Killer