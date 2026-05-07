local PathfindingService = game:GetService('PathfindingService')
local Players = game:GetService('Players')
local RunService = game:GetService('RunService')

local AnimationController = require(script.AnimationController)

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
    self.LastAttackTime = 0

    self.Anim = AnimationController.new(self.Humanoid)
    self.Anim:Load(self.Config.Animations)

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
            if interruptible and self:FindNearestTarget() then
                self.Humanoid:MoveTo(self.Root.Position)
                return true
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

function Killer:StartChaseLoop()
    if self._chasing then return end
    self._chasing = true

    local waypoints = {}
    local waypointIndex = 1
    local lastTargetPos = nil

    -- Path compute em background
    task.spawn(function()
        local path = PathfindingService:CreatePath({
            AgentHeight = 5,
            AgentRadius = 2,
            AgentCanJump = true,
            AgentCanClimb = true,
            WaypointSpacing = 4,
        })

        while self._chasing do
            local target = self.Target
            local targetRoot = target and target.Character
                and target.Character:FindFirstChild('HumanoidRootPart')

            if targetRoot then
                -- Só recomputa se o target moveu mais de 4 studs
                local targetPos = targetRoot.Position
                if not lastTargetPos or (lastTargetPos - targetPos).Magnitude > 4 then
                    lastTargetPos = targetPos

                    pcall(function()
                        path:ComputeAsync(self.Root.Position, targetPos)
                    end)

                    if path.Status == Enum.PathStatus.Success then
                        local newWaypoints = path:GetWaypoints()
                        if #newWaypoints > 1 then
                            waypoints = newWaypoints
                            waypointIndex = 2
                        end
                    end
                end
            end

            task.wait(0.3)
        end
    end)

    -- Movimento no Heartbeat, sem nenhum yield
    local connection
    connection = RunService.Heartbeat:Connect(function()
        if not self._chasing then
            connection:Disconnect()
            return
        end

        local target = self.Target
        local targetRoot = target and target.Character
            and target.Character:FindFirstChild('HumanoidRootPart')

        if not targetRoot then return end

        -- Linha de visão direta: vai direto sem waypoints
        if self:HasLineOfSight(targetRoot) then
            self.Humanoid:MoveTo(targetRoot.Position)
            return
        end

        -- Sem linha de visão: segue waypoints
        local waypoint = waypoints[waypointIndex]
        if waypoint then
            if waypoint.Action == Enum.PathWaypointAction.Jump then
                self.Humanoid.Jump = true
            end

            self.Humanoid:MoveTo(waypoint.Position)

            if (self.Root.Position - waypoint.Position).Magnitude < 3 then
                waypointIndex = math.min(waypointIndex + 1, #waypoints)
            end
        end
    end)
end

function Killer:StopChase()
    self._chasing = false
end

function Killer:GetGravityPoint()
    local players = Players:GetPlayers()
    if #players == 0 then return end

    local sum = Vector3.new(0, 0, 0)
    local count = 0

    for _, player in pairs(players) do
        local char = player.Character
        if char and char:FindFirstChild('HumanoidRootPart') then
            sum = sum + char.HumanoidRootPart.Position
            count += 1
        end
    end

    if count == 0 then return nil end

    local centerOfMass = sum / count

    local nearestPos = nil
    local nearestDist = math.huge

    for _, player in pairs(players) do
        local char = player.Character

        if char and char:FindFirstChild('HumanoidRootPart') then
            local dist = (self.Root.Position - char.HumanoidRootPart.Position).Magnitude
            if dist < nearestDist then
                nearestDist = dist
                nearestPos = char.HumanoidRootPart.Position
            end
        end
    end

    local weights = self.Config.GravityWeights or { centerOfMass = 0.5, nearest = 0.5 }
    local gravityPoint = (centerOfMass * weights.centerOfMass) + (nearestPos * weights.nearest)

    return gravityPoint
end

-- Patrol System (Move around)
function Killer:Patrol()
    local Config = self.Config
    local gravityPoint = self:GetGravityPoint()

    -- Se não tem gravity point, wander pelo mapa normalmente
    local origin = gravityPoint or self.Root.Position
    local range = Config.PatrolWanderRange or 20

    -- Gera ponto aleatório ao redor do gravity point
    local randomOffset = Vector3.new(
        math.random(-range, range),
        0,
        math.random(-range, range)
    )

    local destination = origin + randomOffset

    -- Pausa ocasional para parecer natural
    if math.random(1, 4) == 1 then
        self.Humanoid.WalkSpeed = 0
        task.wait(math.random(1, 2))
    end

    self.Humanoid.WalkSpeed = Config.PatrolSpeed
    self:MoveTo(destination, true)
end

-- Attack system
function Killer:Attack(target)
    local char = target.Character
    if not char then return end

    local humanoid = char:FindFirstChildOfClass('Humanoid')
    local targetRoot = char:FindFirstChild('HumanoidRootPart')
    if not humanoid or not targetRoot then return end
    if humanoid.Health <= 0 then return end

    local dist = (self.Root.Position - targetRoot.Position).Magnitude
    if dist > self.Config.AttackDistance then return end

    -- Toca a animação
    local track = self.Anim.Tracks['Attack']
    if track then
        track:Play(0.1)

        -- Dano no meio da animação (ajusta o tempo conforme a anim)
        task.delay(track.Length * 0.4, function()
            if humanoid and humanoid.Parent then
                humanoid:TakeDamage(self.Config.AttackDamage)
            end
        end)
    else
        -- Sem animação, dano direto
        humanoid:TakeDamage(self.Config.AttackDamage)
    end
end

function Killer:UpdateAnimation()
    -- Velocity fisica, para funcionar para o servidor
    local velocity = self.Root.AssemblyLinearVelocity
    local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
    local moving = horizontalSpeed > 0.5

    -- Não interrompe animação de ataque enquanto ela toca
    local attackTrack = self.Anim.Tracks['Attack']
    if attackTrack and attackTrack.IsPlaying then return end

    if self.State == States.Chase then
        if moving then
            self.Anim:Play('Run')
        else
            self.Anim:Play('Idle')
        end

    elseif self.State == States.Patrol or self.State == States.Suspicious then
        if moving then
            self.Anim:Play('Walk')
        else
            self.Anim:Play('Idle')
        end

    else
        self.Anim:Play('Idle')
    end
end

function Killer:StartAnimationLoop()
    local lastAnim = nil
    local speedBuffer = 0 -- suaviza leituras de velocidade

    game:GetService('RunService').Heartbeat:Connect(function(dt)
        local attackTrack = self.Anim.Tracks['Attack']
        if attackTrack and attackTrack.IsPlaying then
            if lastAnim ~= 'Attack' then
                lastAnim = 'Attack'
            end
            return
        end

        local velocity = self.Root.AssemblyLinearVelocity
        local rawSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude

        -- suaviza a leitura de velocidade ao longo do tempo
        speedBuffer = speedBuffer + (rawSpeed - speedBuffer) * (dt * 10)

        local newAnim
        if speedBuffer > 12 then
            newAnim = 'Run'
        elseif speedBuffer > 1.5 then
            newAnim = 'Walk'
        else
            newAnim = 'Idle'
        end

        if newAnim ~= lastAnim then
            lastAnim = newAnim
            self.Anim:Play(newAnim)
        end
    end)
end

-- MainLoop
function Killer:Start()
    local Config = self.Config
    self:StartAnimationLoop()

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
                    -- Para o chase e ataca
                    self.State = States.Attack
                    self:StopChase()
                    self.Humanoid.WalkSpeed = 0

                    local now = tick()
                    if now - self.LastAttackTime >= Config.AttackCooldown then
                        self.LastAttackTime = now
                        self:Attack(target)
                    end
                else
                    -- Perseguição contínua
                    self.State = States.Chase
                    self.Humanoid.WalkSpeed = Config.ChaseSpeed
                    self:StartChaseLoop() -- só inicia se não estiver rodando
                end
            end

        elseif self.LastKnownPosition then
            self.State = States.Suspicious
            self:StopChase()
            self.Humanoid.WalkSpeed = Config.PatrolSpeed
            self:MoveTo(self.LastKnownPosition)
            self.LastKnownPosition = nil

        else
            self.State = States.Patrol
            self:StopChase()
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