local PathfindingService = game:GetService('PathfindingService')
local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
local SoundServices = game:GetService('SoundService')

local AnimationController = require(script.AnimationController)

local Killer = {}
Killer.__index = Killer

local States = {
    Idle = 'Idle',
    Patrol = 'Patrol',
    Suspicious = 'Suspicious',
    Stalk = 'Stalk',
    Chase = 'Chase',
    Attack = 'Attack',
    Scream = 'Scream'
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
    self.LastAttackTime = 0
    self.FirstDetect = true
    self._chasing = false
    self._chaseConn = nil

    self.RayParams = RaycastParams.new()
    self.RayParams.FilterDescendantsInstances = { self.Model }
    self.RayParams.FilterType = Enum.RaycastFilterType.Exclude

    self.Anim = AnimationController.new(self.Humanoid)
    self.Anim:Load(self.Config.Animations)

    return self
end

-- Checar se há obstáculos
function Killer:HasLineOfSight(targetRoot)
    local origin = self.Root.Position
    local direction = (targetRoot.Position - origin)

    -- local rayParams = RaycastParams.new()
    -- rayParams.FilterDescendantsInstances = {self.Model}
    -- rayParams.FilterType = Enum.RaycastFilterType.Exclude

    local result = workspace:Raycast(origin, direction, self.RayParams)
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

function Killer:FindTarget()
    local maxDist = self.Config.MaxChaseDistance
    local nearest = nil

    for _, player in ipairs(Players:GetPlayers()) do
        local char = player.Character
        if not char then continue end

        local root = char:FindFirstChild('HumanoidRootPart')
        local hum = char:FindFirstChildOfClass('Humanoid')
        if not root or not hum or hum.Health <= 0 then continue end

        local dist = (self.Root.Position - root.Position).Magnitude

        if dist < maxDist then
            local inFOV = self:IsInFieldOfView(root)
            local los = self:HasLineOfSight(root)
            local close = dist < self.Config.DetectCloseDistance

            if (inFOV and los) or close then
                maxDist = dist
                nearest = player
            end
        end
    end

    return nearest
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

-- Smooth Pathfinding
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

function Killer:StopChase()
    self._chasing = false
    if self._chaseConn then
        self._chaseConn:Disconnect()
        self._chaseConn = nil
    end
end

function Killer:StartChaseLoop()
    if self._chasing then return end
    self._chasing = true

    local path = PathfindingService:CreatePath({
        AgentHeight = 5,
        AgentRadius = 2,
        AgentCanJump = true,
        AgentCanClimb = true,
        WaypointSpacing = 3,
        Costs = {
            Water = 20,
        }
    })

    local waypoints = {}
    local wpIndex = 1
    local lastComputePos = nil
    local computing = false

    local function computePath(targetPos)
        if computing then return end
        computing = true

        task.spawn(function()
            pcall(function()
                path:ComputeAsync(self.Root.Position, targetPos)
            end)

            if path.Status == Enum.PathStatus.Success then
                local newWP = path:GetWaypoints()
                if #newWP > 1 then
                    -- encontra waypoint mais próximo para não parar
                    local best     = 2
                    local bestDist = math.huge
                    for i = 2, #newWP do
                        local d = (self.Root.Position - newWP[i].Position).Magnitude
                        if d < bestDist then
                            bestDist = d
                            best = i
                        end
                    end
                    waypoints = newWP
                    wpIndex = best
                end
            end

            computing = false
        end)
    end

    -- recomputa quando path bloqueia
    path.Blocked:Connect(function()
        local target = self.Target
        local tRoot  = target and target.Character and target.Character:FindFirstChild('HumanoidRootPart')
        if tRoot then
            lastComputePos = nil -- força recompute
        end
    end)

    -- movimento no Heartbeat = zero pausa
    self._chaseConn = RunService.Heartbeat:Connect(function()
        if not self._chasing then return end

        local target = self.Target
        local tRoot  = target and target.Character and target.Character:FindFirstChild('HumanoidRootPart')
        if not tRoot then return end

        local targetPos = tRoot.Position

        -- linha de visão direta: vai reto, sem waypoints
        if self:HasLineOfSight(tRoot) then
            self.Humanoid:MoveTo(targetPos)
            -- recomputa em background se mudou muito (para quando perder LOS)
            if not lastComputePos or (lastComputePos - targetPos).Magnitude > 6 then
                lastComputePos = targetPos
                computePath(targetPos)
            end
            return
        end

        -- sem LOS: segue waypoints
        if not lastComputePos or (lastComputePos - targetPos).Magnitude > 5 then
            lastComputePos = targetPos
            computePath(targetPos)
        end

        local wp = waypoints[wpIndex]
        if wp then
            if wp.Action == Enum.PathWaypointAction.Jump then
                self.Humanoid.Jump = true
            end
            self.Humanoid:MoveTo(wp.Position)

            if (self.Root.Position - wp.Position).Magnitude < 2.5 then
                wpIndex = math.min(wpIndex + 1, #waypoints)
            end
        end
    end)
end

function Killer:GetGravityPoint()
    local players = Players:GetPlayers()
    if #players == 0 then return end

    local sum, count = Vector3.new(), 0
    local nearestPos, nearestDist = nil, math.huge

    for _, player in pairs(players) do
        local char = player.Character
        if char and char:FindFirstChild('HumanoidRootPart') then
            local pos = char.HumanoidRootPart.Position
            local dist = (self.Root.Position - pos).Magnitude
            sum += pos
            count += 1
            if dist < nearestDist then
                nearestDist = dist
                nearestPos = pos
            end
        end
    end

    if count == 0 then return nil end

    local w = self.Config.GravityWeights
    return (sum / count) * w.centerOfMass + nearestPos * w.nearest
end

-- Patrol System (Move around)
function Killer:Patrol()
    local Config = self.Config
    local gravityPoint = self:GetGravityPoint()
    local origin = gravityPoint or self.Root.Position
    local range = Config.PatrolWanderRange or 20

    local dest = origin + Vector3.new(
        math.random(-range, range), 0,
        math.random(-range, range)
    )

    if math.random(1, 5) == 1 then
        self.Humanoid.WalkSpeed = 0
        task.wait(math.random(1, 3))
    end

    self.Humanoid.WalkSpeed = Config.PatrolSpeed
    self:BlockingMoveTo(dest, true)
end

function Killer:BlockingMoveTo(position, interruptible)
    local path = PathfindingService:CreatePath({
        AgentHeight = 5,
        AgentRadius = 2,
        AgentCanJump = true,
        AgentCanClimb = true,
    })

    pcall(function()
        path:ComputeAsync(self.Root.Position, position)
    end)

    if path.Status ~= Enum.PathStatus.Success then return end

    for _, wp in ipairs(path:GetWaypoints()) do
        if interruptible and self:FindTarget() then
            return true
        end

        if wp.Action == Enum.PathWaypointAction.Jump then
            self.Humanoid.Jump = true
        end

        self.Humanoid:MoveTo(wp.Position)
        self.Humanoid.MoveToFinished:Wait(2)
    end
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
        if humanoid and humanoid.Parent and targetRoot then
            local currentDist = (self.Root.Position - targetRoot.Position).Magnitude
            if currentDist <= self.Config.AttackDistance + 2 then -- pequena margem de erro
                humanoid:TakeDamage(self.Config.AttackDamage)
            end
        end
    end)
    else
        -- Sem animação, dano direto
        humanoid:TakeDamage(self.Config.AttackDamage)
    end
end

function Killer:StartAnimationLoop()
    local lastAnim = nil
    local speedSmooth = 0 -- suaviza Velocity Reading

    RunService.Heartbeat:Connect(function(dt)
        local attackTrack = self.Anim.Tracks['Attack']
        if attackTrack and attackTrack.IsPlaying then
                lastAnim = 'Attack'
            return
        end

        local velocity = self.Root.AssemblyLinearVelocity
        local rawSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
        -- speedSmooth = speedSmooth + (rawSpeed - speedSmooth) * math.min(dt * 12, 1) -- smoothening overTime

        local newAnim
        if rawSpeed > 12 then
            newAnim = 'Run'
        elseif rawSpeed > 1.5 then
            newAnim = 'Walk'
        else
            newAnim = 'Idle'
        end

        if newAnim ~= lastAnim then
            lastAnim = newAnim
            self.Anim:Play(newAnim)
        end

        if newAnim == 'Run' then
    -- Se a velocidade padrão é 16 e ele está a 18, a animação toca 1.12x mais rápido
            local playbackSpeed = rawSpeed / self.Config.ChaseSpeed
            self.Anim:AdjustSpeed('Run', math.clamp(playbackSpeed, 0.8, 1.5))
        elseif newAnim == 'Walk' then
            local playbackSpeed = rawSpeed / self.Config.PatrolSpeed
            self.Anim:AdjustSpeed('Walk', math.clamp(playbackSpeed, 0.8, 1.2))
        end
    end)
end

-- function Killer:UpdateAnimation()
--     -- Velocity fisica, para funcionar para o servidor
--     local velocity = self.Root.AssemblyLinearVelocity
--     local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
--     local moving = horizontalSpeed > 0.5

--     -- Não interrompe animação de ataque enquanto ela toca
--     local attackTrack = self.Anim.Tracks['Attack']
--     if attackTrack and attackTrack.IsPlaying then return end

--     if self.State == States.Chase then
--         if moving then
--             self.Anim:Play('Run')
--         else
--             self.Anim:Play('Idle')
--         end

--     elseif self.State == States.Patrol or self.State == States.Suspicious then
--         if moving then
--             self.Anim:Play('Walk')
--         else
--             self.Anim:Play('Idle')
--         end

--     else
--         self.Anim:Play('Idle')
--     end
-- end


-- MainLoop
function Killer:Start()
    local Config = self.Config
    self:StartAnimationLoop()

    while true do
        local target = self:FindNearestTarget()

        if target then
            self.Target = target
            local char = target.Character
            local targetRoot = char.HumanoidRootPart
            self.LastKnownPosition = targetRoot.Position
            
            local dist = (self.Root.Position - targetRoot.Position).Magnitude

            if dist <= Config.AttackDistance then
                -- ESTADO: ATAQUE
                self.State = States.Attack
                self:StopChase()
                self.Humanoid.WalkSpeed = 0
                
                -- Olhar para o alvo suavemente durante o ataque
                self.Root.CFrame = CFrame.lookAt(self.Root.Position, Vector3.new(targetRoot.Position.X, self.Root.Position.Y, targetRoot.Position.Z))

                local now = tick()
                if now - self.LastAttackTime >= Config.AttackCooldown then
                    self.LastAttackTime = now
                    self:Attack(target)
                end
            else
                -- ESTADO: CHASE
                self.State = States.Chase
                self.Humanoid.WalkSpeed = Config.ChaseSpeed
                self:StartChaseLoop() 
            end
        else
            -- PERDEU O ALVO
            self.Target = nil
            if self.LastKnownPosition then
                -- ESTADO: INVESTIGAR ÚLTIMA POSIÇÃO
                self.State = States.Suspicious
                self:StopChase()
                self.Humanoid.WalkSpeed = Config.PatrolSpeed
                
                local arrived = self:MoveTo(self.LastKnownPosition, true)
                if arrived or not self.Target then -- Se chegou ou achou outro no caminho
                    self.LastKnownPosition = nil
                end
            else
                -- ESTADO: PATROL
                self.State = States.Patrol
                self:StopChase()
                self:Patrol()
            end
        end

        task.wait(0.1)
    end
end

function Killer:Spawn()
    self.Model:PivotTo(self.Config.BaseSpawnLocation)
    for _, part in pairs(self.Model:GetDescendants()) do
        if part:IsA("BasePart") then
            part:SetNetworkOwner(nil) 
        end
    end
end

return Killer