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

-- Checar se há obstaculos
function Killer:HasLineOfSight(targetRoot)
    local origin = self.Root.Position
    local direction = (targetRoot.Position - origin)

    local rayParams = RaycastParams.new()
    rayParams.FilterDescendantsInstances = {self.Model}
    rayParams.FilterType = Enum.RaycastFilterType.Exclude

    local result = workspace:Raycast(origin, direction, rayParams)
    if result then
        local hit = result.Instance
        local character = hit:FindFirstAncestorOfClass('Model')
        if character and Players:GetPlayerFromCharacter(character) then
            return true
        end
        return false
    end

    return true
end

-- FOV of the killer
function Killer:IsInFieldOfView(targetRoot)
    local Config = self.Config
    local toTarget = (targetRoot.Position - self.Root.Position).Unit
    local lookVector = self.Root.CFrame.lookVector

    local dot = toTarget:Dot(lookVector)
    local angle = math.deg(math.acos(dot))

    return angle < Config.FieldOfViewAngle
end



function Killer:FindNearestTarget()
    local maxDistance = self.Config.MaxChaseDistance
    local nearest = nil

    for _, player in pairs(Players:GetPlayers()) do
        local char = player.Character
        if char and char:FindFirstChild('HumanoidRootPart') then
            local targetRoot = char.HumanoidRootPart
            local dist = (self.Root.Position - targetRoot.Position).Magnitude

            if dist < maxDistance then
                if self:IsInFieldOfView(targetRoot) and self:HasLineOfSight(targetRoot) then
                    maxDistance = dist
                    nearest = player
                elseif dist < self.Config.DetectCloseDistance then
                    maxDistance = dist
                    nearest = player
                end
            end
        end
    end

    return nearest
end

-- function Killer:Chase()
--     local path = PathfindingService:CreatePath({
--         AgentHeight = 5,
--         AgentRadius = 2,
--         AgentCanJump = true,
--     })
    
--     while true do
--         local target = self:FindNearestTarget()
        
--         if target then
--             local targetRoot = target.Character and target.Character:FindFirstChild('HumanoidRootPart')
--             if targetRoot then
--                 local success, err = pcall(function()
--                     path:ComputeAsync(self.Root.Position, targetRoot.Position)
--                 end)
                
--                 if success and path.Status == Enum.PathStatus.Success then
--                     local waypoints = path:GetWaypoints()
                    
--                     for _, waypoint in pairs(waypoints) do
--                         if waypoint.Action == Enum.PathWaypointAction.Jump then
--                             self.Humanoid.Jump = true
--                         end
--                         self.Humanoid:MoveTo(waypoint.Position)
--                         self.Humanoid.MoveToFinished:Wait()
--                     end
--                 end
--             end
--         end
        
--         task.wait(0.5)
--     end
-- end

function Killer:MoveTo(position, interruptible)
    local path = PathfindingService:CreatePath({
        AgentHeight = 5,
        AgentRadius = 2,
        AgentCanJump = true,
        AgentCanClimb = true,
    })

    local success = pcall(function()
        path:ComputeAsync(self.Root.Position, position)
    end)

    if success and path.Status == Enum.PathStatus.Success then
        local waypoints = path:GetWaypoints()

        for _, waypoint in pairs(waypoints) do
            -- só interrompe se for patrulha E tiver alvo visível
            if interruptible then
                local target = self:FindNearestTarget()
                if target then
                    self.Humanoid:MoveTo(self.Root.Position)
                    return true -- sinaliza que foi interrompido
                end
            end

            if waypoint.Action == Enum.PathWaypointAction.Jump then
                self.Humanoid.Jump = true
            end

            self.Humanoid:MoveTo(waypoint.Position)

            local moved = self.Humanoid.MoveToFinished:Wait(1)
            if not moved then break end
        end
    end

    return false
end

-- Patrol System (Move around)
function Killer:Patrol()
    local Config = self.Config
    if not Config or #Config.PatrolPoints == 0 then return end

    local point = Config.PatrolPoints[self.PatrolIndex]
    self.Humanoid.WalkSpeed = Config.PatrolSpeed

    self:MoveTo(point, true) -- true para que ele seja interrompivel caso veja alguém

    self.PatrolIndex = (self.PatrolIndex % #Config.PatrolPoints) + 1
end

-- Attack system
function Killer:Attack(target)
    local char = target.Character
    if not char then return end

    local humanoid = char:FindFirstChild('Humanoid')
    local targetRoot = char:FindFirstChild('HumanoidRootPart')
    if not humanoid or not targetRoot then return end
    if humanoid.Health <= 0 then return end

    local dist = (self.Root.Position - targetRoot.Position).Magnitude

    if dist <= self.Config.AttackDistance then
        humanoid:TakeDamage(self.Config.AttackDamage)
        task.wait(self.Config.AttackCooldown)
    end
end

-- MainLoop
function Killer:Start()
    local Config = self.Config

    while true do
        local target = self:FindNearestTarget()

        if target then
            local char = target.Character
            local targetRoot = char and char:FindFirstChild('HumanoidRootPart')

            if targetRoot then
                self.Target = target
                self.LastKnownPosition = targetRoot.Position
                local dist = (self.Root.Position - targetRoot.Position).Magnitude

                if dist <= Config.AttackDistance then
                    -- Attack
                    self.State = States.Attack
                    self.Humanoid.WalkSpeed = 6 -- 0
                    if target and target.Character then
                        self:Attack(target)
                    end

                else
                    -- Follow Players
                    self.State = States.Chase
                    self.Humanoid.WalkSpeed = Config.ChaseSpeed
                    self:MoveTo(targetRoot.Position)
                end
            end

        elseif self.LastKnownPosition then
            -- Goto LastKnwonPosition
            self.State = States.Suspicious
            self.Humanoid.WalkSpeed = Config.PatrolSpeed
            self:MoveTo(self.LastKnownPosition)
            self.LastKnownPosition = nil

        else
            -- Patrol
            self.State = States.Patrol
            self:Patrol()
        end

        task.wait(0.1)
    end
end

function Killer:Spawn()
    local Config = self.Config

    self.Model:PivotTo(Config.BaseSpawnLocation)
end

return Killer