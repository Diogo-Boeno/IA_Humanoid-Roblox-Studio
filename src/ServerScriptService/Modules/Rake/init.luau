local PathfindingService = game:GetService('PathfindingService')
local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
local SoundServices = game:GetService('SoundService')
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
    if self.Humanoid then
        self.Humanoid.AutoRotate = true
    end
    self.Target = nil
    self.State = States.Idle
    self.LastKnownPosition = nil
    self.LastAttackTime = 0
    self.FirstDetect = true
    self._chasing = false
    self._chaseConn = nil
    self._lastPatrolStop = nil
    self._screaming = false
    self._lastSeenTargetId = nil
    self._lastScreamTime = 0
    self._targetLockUntil = 0
    self._searchUntil = 0
    self._searchCenter = nil
    self._searchIndex = 1
    self._searchPoints = nil
    self._searching = false
    self._lostSightSince = nil
    self._lastVisiblePos = nil
    self._lastHeardPos = nil
    self._lastHeardAt = 0
    self._lastHeardScore = 0
    self._noiseMemoryPos = nil
    self._noiseMemoryUntil = 0
    self._investigateNoiseUntil = 0
    self._investigating = false
    self._investigatingPos = nil

    -- evento global para ruídos (ex: gravetos, portas, tiros)
    -- qualquer script pode fazer: ReplicatedStorage.RakeNoise:Fire(pos, loudness)
    local noiseEvent = ReplicatedStorage:FindFirstChild("RakeNoise")
    if not noiseEvent then
        noiseEvent = Instance.new("BindableEvent")
        noiseEvent.Name = "RakeNoise"
        noiseEvent.Parent = ReplicatedStorage
    end
    self._noiseEvent = noiseEvent
    self._noiseConn = noiseEvent.Event:Connect(function(pos, loudness)
        if typeof(pos) ~= "Vector3" then return end
        loudness = tonumber(loudness) or 1
        loudness = math.clamp(loudness, 0.1, 10)
        self._lastHeardPos = pos
        self._lastHeardAt = time()
        self._lastHeardScore = loudness
    end)

    self._patrolling = false
    self._patrolConn = nil

    -- reduz padrão determinístico do math.random ao reiniciar o servidor
    math.randomseed(math.floor(tick() * 1000000))

    self.RayParams = RaycastParams.new()
    self.RayParams.FilterDescendantsInstances = { self.Model }
    self.RayParams.FilterType = Enum.RaycastFilterType.Exclude

    self.Anim = AnimationController.new(self.Humanoid)
    self.Anim:Load(self.Config.Animations)

    return self
end

function Killer:ProjectToGround(pos: Vector3): Vector3
    local startY = (pos.Y + 80)
    local rayOrigin = Vector3.new(pos.X, startY, pos.Z)
    local rayDir = Vector3.new(0, -250, 0)
    local hit = workspace:Raycast(rayOrigin, rayDir, self.RayParams)
    if hit then
        return hit.Position
    end
    return Vector3.new(pos.X, self.Root.Position.Y, pos.Z)
end

function Killer:RememberNoise(pos: Vector3, score: number)
    -- trava um ponto de ruído por um tempo curto para evitar “seguir o player em tempo real”
    local now = time()
    local ttl = (self.Config.NoiseMemoryTime or 1.0)
    -- se não tem memória, se expirou, ou se o novo score é bem melhor, atualiza
    local farEnough = self._noiseMemoryPos and (pos - self._noiseMemoryPos).Magnitude >= 6 or false
    if not self._noiseMemoryPos
        or now >= (self._noiseMemoryUntil or 0)
        or farEnough
        or score > (self._noiseMemoryScore or 0) + 0.08
    then
        self._noiseMemoryPos = self:ProjectToGround(pos)
        self._noiseMemoryUntil = now + ttl
        self._noiseMemoryScore = score
    end
end

function Killer:GetRememberedNoise(): (Vector3?, number)
    if self._noiseMemoryPos and time() < (self._noiseMemoryUntil or 0) then
        return self._noiseMemoryPos, (self._noiseMemoryScore or 0)
    end
    return nil, 0
end

-- Retorna a melhor posição de ruído detectada por "audição" (a partir de players).
function Killer:HearNoisePosition(): (Vector3?, number)
	local cfg = self.Config
	local h = cfg.Hearing or {}
	local walkDist = h.WalkDistance or 18
	local runDist = h.RunDistance or 36
	local minNoise = h.MinNoise or 0.22
	local runNoise = h.RunNoise or 0.70
	local occMul = h.OccludedMultiplier or 0.15
	local occMaxFactor = h.OccludedMaxDistanceFactor or 0.6
	local eventMaxDist = h.EventMaxDistance or 50

	local bestPos: Vector3? = nil
	local bestScore = 0

	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		if not char then
			continue
		end
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not root then
			continue
		end

		local noise = self:GetPlayerNoiseLevel(plr)
		if noise < minNoise then
			continue
		end

		-- define alcance baseado em andar vs correr
		local maxDist = walkDist
		if noise >= runNoise then
			maxDist = runDist
		end

		local dist = (self.Root.Position - root.Position).Magnitude
		if dist > maxDist then
			continue
		end

		if not self:HasLineOfSight(root) then
			-- atrás de obstáculo: AINDA detecta (como você pediu), só fica menos “confiável”
			-- e pode reduzir o alcance efetivo se o OccludedMaxDistanceFactor < 1.
			if dist > (maxDist * occMaxFactor) then
				continue
			end
			noise *= occMul
		end

		local score = noise * (1 - dist / maxDist)
		if score > bestScore then
			bestScore = score
			bestPos = root.Position
		end
	end

	-- também considera ruídos explícitos (BindableEvent)
	if self._lastHeardPos and (time() - (self._lastHeardAt or 0)) < 1.2 then
		local dist = (self.Root.Position - self._lastHeardPos).Magnitude
		if dist <= eventMaxDist then
			-- loudness 0.1..10 → 0..1
			local loud01 = math.clamp((self._lastHeardScore or 1) / 10, 0.05, 1)
			local score = loud01 * (1 - dist / eventMaxDist)
			if score > bestScore then
				bestScore = score
				bestPos = self._lastHeardPos
			end
		end
	end

	return bestPos, bestScore
end

function Killer:InvestigateNoise(pos: Vector3)
    -- evita reiniciar a investigação a cada tick: só bloqueia enquanto está rodando
    if self._investigating then
        return
    end

    self._investigating = true
    local dest = self:ProjectToGround(pos)

    task.spawn(function()
        local ok, err = pcall(function()
            -- corre até o local do ruído e entra em busca ao redor
            self.State = States.Suspicious
            self:StopChase()
            self.Target = nil

            self.Humanoid.WalkSpeed = self.Config.CheckNoiseSpeed -- “vem correndo checar”
            -- Não interrompe por hearing aqui (senão ele se auto-interrompe e fica parado).
            self:BlockingMoveTo(dest, true, false)

            -- ao chegar (ou interromper por visão), vira busca na área
            self:StartSearch(dest)
        end)

        if not ok then
            warn("[Rake] InvestigateNoise failed:", err)
        end

        self._investigating = false
    end)
end

function Killer:IsValidTarget(player: Player?): boolean
    if not player then return false end
    local char = player.Character
    if not char then return false end
    local root = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not root or not hum or hum.Health <= 0 then
        return false
    end
    return true
end

function Killer:BuildSearchPoints(center: Vector3, radius: number, count: number): { Vector3 }
    local points = {}
    for i = 1, count do
        local a = (i / count) * math.pi * 2
        local r = radius * (0.55 + 0.45 * math.random())
        local p = center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
        table.insert(points, p)
    end
    -- adiciona 1 ponto no centro também (olhar ao redor)
    table.insert(points, center)
    return points
end

function Killer:StartSearch(center: Vector3)
    local cfg = self.Config
    self.State = States.Suspicious
    self:StopChase()
    self.Target = nil

    self._searchCenter = center
    self._searchUntil = time() + (cfg.InvestigationTime or 10)
    self._searchIndex = 1
    self._searchPoints = self:BuildSearchPoints(center, (cfg.HearingDistance or 25) * 0.55, 6)
end

function Killer:StartSearchLoop()
    if self._searching then return end
    self._searching = true

    task.spawn(function()
        while self._searching do
            if not self._searchCenter or time() >= (self._searchUntil or 0) then
                self._searching = false
                break
            end

            if self._investigating or self._screaming then
                task.wait(0.1)
                continue
            end

            local seen = self:FindVisibleTarget()
            if seen then
                -- se viu, encerra busca imediatamente
                self._searchCenter = nil
                self._searchPoints = nil
                self._searchIndex = 1
                self._searching = false
                break
            end

            local noisePos, noiseScore = self:HearNoisePosition()
            if noisePos and noiseScore > 0 then
                self:RememberNoise(noisePos, noiseScore)
            end
            noisePos, noiseScore = self:GetRememberedNoise()
            if noisePos and noiseScore >= (self.Config.NoiseInvestigateThreshold or 0.18) then
                -- ouviu algo forte durante a busca
                self._searchCenter = nil
                self._searchPoints = nil
                self._searchIndex = 1
                self._searching = false
                if not self._investigating then
                    self:InvestigateNoise(noisePos) -- self:InvestigateNoise(self:AddHorizontalJitter(noisePos, self.InvestigationJitterRadius or 6))
                end
                break
            end

            self:SearchStep()
            task.wait(0.1)
        end
    end)
end

function Killer:StopSearchLoop()
    self._searching = false
end

function Killer:SearchStep(): boolean
    -- retorna true quando terminou a busca
    if not self._searchCenter or time() >= (self._searchUntil or 0) then
        self._searchCenter = nil
        self._searchPoints = nil
        self._searchIndex = 1
        return true
    end

    local cfg = self.Config
    self.Humanoid.WalkSpeed = cfg.InvestigationSpeed or cfg.PatrolSpeed

    local points = self._searchPoints
    if not points or #points == 0 then
        self._searchPoints = self:BuildSearchPoints(self._searchCenter, (cfg.HearingDistance or 25) * 0.55, 6)
        points = self._searchPoints
    end

    local p = points[self._searchIndex]
    self._searchIndex += 1
    if self._searchIndex > #points then
        self._searchIndex = 1
        -- pequena variação de pontos a cada ciclo
        self._searchPoints = self:BuildSearchPoints(self._searchCenter, (cfg.HearingDistance or 25) * 0.55, 6)
    end

    self:BlockingMoveTo(p, true, false)
    task.wait(0.35 + math.random() * 0.45)
    return false
end

-- Checar obstaculos
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
    local lookVector = self.Root.CFrame.LookVector

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

function Killer:FindVisibleTarget(): Player?
    local maxDist = self.Config.MaxChaseDistance
    local nearest: Player? = nil

    for _, player in ipairs(Players:GetPlayers()) do
        local char = player.Character
        if not char then continue end

        local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not root or not hum or hum.Health <= 0 then continue end

        local dist = (self.Root.Position - root.Position).Magnitude
        if dist < maxDist then
            local los = self:HasLineOfSight(root)
            if not los then
                continue
            end

            local closeVisible = dist <= (self.Config.DetectCloseDistance or 12) * 1.35

            if closeVisible or self:IsInFieldOfView(root) then
                maxDist = dist
                nearest = player
            end
        end
    end

    return nearest
end

function Killer:GetPlayerNoiseLevel(player: Player): number
	local char = player.Character
	if not char then
		return 0
	end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 then
		return 0
	end
	local v = root.AssemblyLinearVelocity
	local horiz = Vector3.new(v.X, 0, v.Z).Magnitude
	local cap = math.max(hum.WalkSpeed, 1)
	-- sprint / corrida forte tende a ~1; arrastar devagar ~0.2
	return math.clamp(horiz / cap, 0, 1)
end

function Killer:AddHorizontalJitter(pos: Vector3, radius: number): Vector3
	local a = math.random() * math.pi * 2
	local r = math.random() * radius
	return pos + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
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
        Costs = { Water = 20 }
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
                    -- começa pelo waypoint mais perto do Rake (não recua)
                    local best, bestDist = 2, math.huge
                    for i = 2, #newWP do
                        local d = (self.Root.Position - newWP[i].Position).Magnitude
                        if d < bestDist then bestDist = d; best = i end
                    end
                    waypoints = newWP
                    wpIndex = best
                end
            end
            computing = false
        end)
    end

    path.Blocked:Connect(function()
        local tRoot = self.Target and self.Target.Character
            and self.Target.Character:FindFirstChild('HumanoidRootPart')
        if tRoot then lastComputePos = nil end
    end)

    self._chaseConn = RunService.Heartbeat:Connect(function(dt)
        if not self._chasing then return end

        local target = self.Target
        local tRoot = target and target.Character
            and target.Character:FindFirstChild('HumanoidRootPart') :: BasePart?
        if not tRoot then return end

        -- estima onde o player estará daqui a t segundos 
        local vel = tRoot.AssemblyLinearVelocity
        local horizVel = Vector3.new(vel.X, 0, vel.Z)
        local dist = (self.Root.Position - tRoot.Position).Magnitude
        local t = math.clamp(dist / math.max(self.Config.ChaseSpeed, 1), 0.05, 0.9)
        local predictedPos = tRoot.Position + horizVel * t

        -- LOS  vai ao ponto previsto; sem LOS → segue path 
        if self:HasLineOfSight(tRoot) then
            -- suaviza a direção com steering lerp
            local desired = (predictedPos - self.Root.Position)
            local moveTarget = self.Root.Position + desired.Unit * 6
            self.Humanoid:MoveTo(moveTarget)

            -- mantem path calculado para quando perder LOS
            if not lastComputePos or (lastComputePos - predictedPos).Magnitude > 5 then
                lastComputePos = predictedPos
                computePath(predictedPos)
            end
            return
        end

        -- recomputa path se o alvo se moveu bastante
        if not lastComputePos or (lastComputePos - predictedPos).Magnitude > 4 then
            lastComputePos = predictedPos
            computePath(predictedPos)
        end

        --  LOOKAHEAD
        local lookIdx = math.min(wpIndex + 2, #waypoints)
        local wp = waypoints[lookIdx]
        if wp then
            if wp.Action == Enum.PathWaypointAction.Jump then
                self.Humanoid.Jump = true
            end
            self.Humanoid:MoveTo(wp.Position)

            -- avança índice quando chega perto
            if (self.Root.Position - wp.Position).Magnitude < 3 then
                wpIndex = math.min(lookIdx + 1, #waypoints)
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

-- Patrol System
function Killer:Patrol()
    local Config = self.Config
    local gravityPoint = self:GetGravityPoint()
    local origin = gravityPoint or self.Root.Position
    local range = Config.PatrolWanderRange or 20

    if math.random(1, 5) == 1 then
        self.Humanoid.WalkSpeed = 0
        task.wait(math.random(1, 3))
    end

    self.Humanoid.WalkSpeed = Config.PatrolSpeed

    local function GetGroundAtXZ(x: number, z: number): Vector3
        local startY = (self.Root.Position.Y + 50)
        local rayOrigin = Vector3.new(x, startY, z)
        local rayDir = Vector3.new(0, -200, 0)

        local hit = workspace:Raycast(rayOrigin, rayDir, self.RayParams)
        if not hit then
            return Vector3.new(x, self.Root.Position.Y, z)
        end

        local character = hit.Instance and hit.Instance:FindFirstAncestorOfClass('Model')
        if character and Players:GetPlayerFromCharacter(character) then
            -- não apontar para "em cima" do player
            return Vector3.new(x, self.Root.Position.Y, z)
        end

        return hit.Position
    end

    local maxTries = 6
    local tries = 0
    local currentRange = range
    while tries < maxTries do
        tries += 1

        local x = origin.X + math.random(-currentRange, currentRange)
        local z = origin.Z + math.random(-currentRange, currentRange)
        local dest = GetGroundAtXZ(x, z)

        local attemptStartPos = self.Root.Position
        local interrupted, reached, stopPos = self:BlockingMoveTo(dest, true)
        if interrupted then
            return
        end

        if reached and stopPos then
            local moved = (stopPos - attemptStartPos).Magnitude
            local repeatedStop = self._lastPatrolStop and (stopPos - self._lastPatrolStop).Magnitude < 1.5
            if moved >= 1.5 and not repeatedStop then
                self._lastPatrolStop = stopPos
                return
            end
        end

        -- Se falhar muito reduz o alcance para achar pontos mais faceis
        currentRange = math.max(8, currentRange * 0.7)
    end
end

function Killer:StartPatrolLoop()
    if self._patrolling then return end
    self._patrolling = true

    task.spawn(function()
        while self._patrolling do
            -- para patrulha se entrar em investigação/chase/scream
            if self._investigating or self._screaming then
                task.wait(0.1)
                continue
            end

            local seen = self:FindVisibleTarget()
            if seen then
                self._patrolling = false
                break
            end

            -- se houver som alto
            local nPos, nScore = self:HearNoisePosition()
            if nPos and nScore >= (self.Config.NoiseInvestigateThreshold or 0.18) then
                self._patrolling = false
                break
            end

            self:Patrol()
            task.wait(0.1)
        end
    end)
end

function Killer:StopPatrolLoop()
    self._patrolling = false
end

function Killer:BlockingMoveTo(position, interruptible, interruptOnNoise)
    local path = PathfindingService:CreatePath({
        AgentHeight = 5,
        AgentRadius = 2,
        AgentCanJump = true,
        AgentCanClimb = true,
    })

    local ok = pcall(function()
        path:ComputeAsync(self.Root.Position, position)
    end)

    if not ok then
        return false, false, self.Root.Position
    end

    if path.Status ~= Enum.PathStatus.Success then
        return false, false, self.Root.Position
    end

    local lastPos = self.Root.Position

    for _, wp in ipairs(path:GetWaypoints()) do
        if interruptible then
            -- Se viu alguém de verdade breaka insta
            if self:FindVisibleTarget() then
                lastPos = self.Root.Position
                return true, false, lastPos
            end
            if interruptOnNoise ~= false then
                -- Se ouviu alguém perto
                local noisePos, noiseScore = self:HearNoisePosition()
                local threshold = (self.Config.NoiseMoveInterruptThreshold or 0.12)
                if noisePos and noiseScore >= threshold then
                    lastPos = self.Root.Position
                    return true, false, lastPos
                end
            end
        end

        if wp.Action == Enum.PathWaypointAction.Jump then
            self.Humanoid.Jump = true
        end

        local dist = (self.Root.Position - wp.Position).Magnitude
        local speed = math.max(self.Humanoid.WalkSpeed, self.Config.PatrolSpeed, 1)
        -- Tempo suficiente para chegar sem stuck
        local timeout = math.clamp(dist / speed + 0.6, 1, 3.5)

        self.Humanoid:MoveTo(wp.Position)

        local moved = self.Humanoid.MoveToFinished:Wait(timeout)
        if not moved then
            lastPos = self.Root.Position
            return false, false, lastPos
        end

        lastPos = self.Root.Position
    end

    return false, true, lastPos
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

    -- Toca a anim
    local track = self.Anim.Tracks['Attack']
    if track then
        track:Play(0.1)

        -- Dano no meio da anim
    task.delay(track.Length * 0.4, function()
        if humanoid and humanoid.Parent and targetRoot then
            local currentDist = (self.Root.Position - targetRoot.Position).Magnitude
            if currentDist <= self.Config.AttackDistance + 2 then -- pequena margem de erro
                humanoid:TakeDamage(self.Config.AttackDamage)
            end
        end
    end)
    else
        -- Sem anim
        humanoid:TakeDamage(self.Config.AttackDamage)
    end
end

function Killer:DoScream(targetRoot: BasePart?)
    if self._screaming then return end
    self._screaming = true

    self.State = States.Scream
    self:StopChase()
    self.Humanoid.WalkSpeed = 0

    if targetRoot then
        self.Root.CFrame = CFrame.lookAt(
            self.Root.Position,
            Vector3.new(targetRoot.Position.X, self.Root.Position.Y, targetRoot.Position.Z)
        )
    end

    local track = self.Anim.Tracks["Scream"]
    if track then
        track:Play(0.1)
    end

    local screamSound = self.Model:FindFirstChild("ScreamSound", true)
    if screamSound and screamSound:IsA("Sound") then
        screamSound:Play()
    end

    task.delay(self.Config.ScreamDuration or 2, function()
        self._screaming = false
    end)
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
        speedSmooth = speedSmooth + (rawSpeed - speedSmooth) * math.min(dt * 12, 1) -- smoothening overTime

        local newAnim
        if speedSmooth > 12 then
            newAnim = 'Run'
        elseif speedSmooth > 1.5 then
            newAnim = 'Walk'
        else
            newAnim = 'Idle'
        end

        if newAnim ~= lastAnim then
            lastAnim = newAnim
            self.Anim:Play(newAnim)
        end

        if newAnim == 'Run' then
            local playbackSpeed = speedSmooth / self.Config.ChaseSpeed
            self.Anim:AdjustSpeed('Run', math.clamp(playbackSpeed, 0.8, 1.5))
        elseif newAnim == 'Walk' then
            local playbackSpeed = speedSmooth / self.Config.PatrolSpeed
            self.Anim:AdjustSpeed('Walk', math.clamp(playbackSpeed, 0.8, 1.2))
        end
    end)
end

-- MainLoop
function Killer:Start()
    local Config = self.Config
    self:StartAnimationLoop()

    while true do
        if self._investigating then
            local seen = self:FindVisibleTarget()
            if seen then
                -- breaka a investigação para permitir chase normal
                self._investigating = false
            else
                task.wait(0.1)
                continue
            end
        end

        -- Se está em modo busca, NÃO fica “telepático” pegando nearest a cada tick.
        -- Só sai do modo busca se ver alguém ou ouvir alguém bem de perto.
        local searchingActive = (self._searchCenter and time() < (self._searchUntil or 0)) or false
        if searchingActive then
            -- busca roda em background, mas o cérebro continua reagindo (visão/ruído).
            self:StartSearchLoop()
        end

        -- Alvo visível (real) vs. apenas “travado”.
        local visibleTarget = self:FindVisibleTarget()
        local noisePos, noiseScore = nil, 0

        -- Target lock: só mantém se ainda estiver “perto” e (idealmente) visível com frequência.
        local lockedTarget = self.Target
        local lockActive = lockedTarget
            and time() < (self._targetLockUntil or 0)
            and self:IsValidTarget(lockedTarget)

        -- hearing só é considerado quando não há alvo visível
        if not visibleTarget then
            noisePos, noiseScore = self:HearNoisePosition()
            if noisePos and noiseScore > 0 then
                self:RememberNoise(noisePos, noiseScore)
            end
            noisePos, noiseScore = self:GetRememberedNoise()
        end

        -- alvo escolhido para agir
        local target = visibleTarget or (lockActive and lockedTarget) or nil

        if target then
            -- se viu de verdade, para loops de patrol/search/investigate competindo
            if visibleTarget then
                self:StopPatrolLoop()
                self:StopSearchLoop()
                self._investigating = false
            end
            -- Se não está visível e só foi “ouvido”, NÃO entra em chase: entra em busca.
            -- (nada aqui; ouvir sem ver é tratado no bloco "sem alvo" abaixo)

            self.Target = target
            if visibleTarget then
                self._targetLockUntil = time() + (Config.TargetLockTime or 3.5)
            end
            local char = target.Character
            local targetRoot = char.HumanoidRootPart
            -- atualiza memória apenas quando vê de verdade
            if visibleTarget then
                self.LastKnownPosition = targetRoot.Position
                self._lastVisiblePos = targetRoot.Position
                self._lostSightSince = nil
            else
                -- perdeu LOS: começa timer de “desistência”
                if not self._lostSightSince then
                    self._lostSightSince = time()
                end
            end

            local dist = (self.Root.Position - targetRoot.Position).Magnitude

            -- Scream quando "vê" o player (telegraph) para não pegar desprevenido.
            -- Regra: só por visão + cooldown (não precisa ser alvo novo).
            if visibleTarget and not self._screaming and self.State ~= States.Attack then
                self._lastSeenTargetId = target.UserId

                local now = time()
                local cooldown = Config.ScreamCooldown or 18
                local canScream = (now - (self._lastScreamTime or 0)) >= cooldown

                if canScream and math.random() < (Config.ScreamChance or 0) then
                    self._lastScreamTime = now
                    self:DoScream(targetRoot)
                end
            end

            -- enquanto grita, não faz chase/attack
            if self._screaming then
                task.wait(0.1)
                continue
            end

            -- Se ficou tempo demais sem ver o alvo, para de perseguir “telepaticamente” e entra em busca.
            if not visibleTarget and self._lostSightSince then
                local giveUp = Config.HideAfterLostTarget or 8
                if (time() - self._lostSightSince) >= giveUp then
                    self:StopChase()
                    self.Target = nil
                    if self._lastVisiblePos then
                        self:StartSearch(self._lastVisiblePos)
                        self._lastVisiblePos = nil
                    end
                    task.wait(0.1)
                    continue
                end
            end

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
                -- Só entra em CHASE se estiver visível de verdade.
                if visibleTarget then
                    self.State = States.Chase
                    self.Humanoid.WalkSpeed = Config.ChaseSpeed
                    self:StopPatrolLoop()
                    self:StopSearchLoop()
                    self:StopChase()
                    self:StartChaseLoop()
                else
                    -- sem visão: mantém suspeita/busca, não sprint infinito
                    self:StopChase()
                    -- Se está ouvindo algo, investiga correndo; senão, busca na última posição visível.
                    if noisePos and noiseScore >= (Config.NoiseInvestigateThreshold or 0.18) then
                        self:InvestigateNoise(noisePos) -- self:InvestigateNoise(self:AddHorizontalJitter(noisePos, self.InvestigationJitterRadius or 6))
                    elseif self._lastVisiblePos then
                        self:StartSearch(self._lastVisiblePos)
                        self._lastVisiblePos = nil
                    end
                end
            end
        else
            self.Target = nil

            -- Se ouviu um ruído alto e perto, corre pra checar
            if noisePos and noiseScore >= (Config.NoiseInvestigateThreshold or 0.18) then
                local now = time()
                if now >= (self._investigateNoiseUntil or 0) then
                    self._investigateNoiseUntil = now + (Config.NoiseInvestigateCooldown or 1.2)
                    if not self._investigating then
                        local investigatePos = self:AddHorizontalJitter(noisePos, self.InvestigationJitterRadius or 6)
                        self:InvestigateNoise(investigatePos)
                    end
                end

            elseif self.LastKnownPosition then
                -- ESTADO: BUSCA / SUSPEITA
                self:StartSearch(self.LastKnownPosition)
                self.LastKnownPosition = nil
            else
                -- ESTADO: PATROL
                self.State = States.Patrol
                self:StopChase()
                if not searchingActive then
                    self:StartPatrolLoop()
                end
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