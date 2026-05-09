-- Killer.luau
--!strict

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimationController = require(script.AnimationController)

-- CORREÇÃO: função de tempo confiável
local function time() return os.clock() end

-- Estados
local States = {
	Idle = "Idle",
	Patrol = "Patrol",
	Suspicious = "Suspicious",
	Investigate = "Investigate",
	Stalk = "Stalk",
	Chase = "Chase",
	Attack = "Attack",
	Scream = "Scream",
}

local STATE_PRIORITY = {
	Idle = 0,
	Patrol = 1,
	Suspicious = 2,
	Investigate = 3,
	Stalk = 4,
	Chase = 5,
	Scream = 6,
	Attack = 7,
}

-- Killer class
local Killer = {}
Killer.__index = Killer

-------------------- constructor --------------------
function Killer.new(model)
	local self = setmetatable({}, Killer)

	self.Config = require(script.Config)
	self.Model = model
	self.Humanoid = model:FindFirstChild("Humanoid")
	self.Root = model:FindFirstChild("HumanoidRootPart")

	if self.Humanoid then
		self.Humanoid.AutoRotate = true
	end

	-- estado
	self.State = States.Idle
	self.Target = nil
	self.LastKnownPosition = nil

	-- velocidade suavizada
	self._currentSpeed = 0
	self._desiredSpeed = 0

	-- rotação suavizada
	self._desiredLookAt = nil

	-- chase / pathfinding
	self._chasePath = nil
	self._patrolPath = nil
	self._waypoints = {}
	self._wpIndex = 1
	self._lastPathTarget = nil
	self._pathComputing = false
	self._jumpWaypoints = {}

	-- attack
	self.LastAttackTime = 0

	-- scream
	self._screaming = false
	self._screamEndTime = 0
	self._lastScreamTime = 0

	-- target lock
	self._targetLockUntil = 0
	self._lostSightSince = nil
	self._lastVisiblePos = nil

	-- target memory
	self._targetMemory = {}

	-- hearing / noise
	self._lastHeardPos = nil
	self._lastHeardAt = 0
	self._lastHeardScore = 0
	self._noiseMemoryPos = nil
	self._noiseMemoryUntil = 0
	self._noiseMemoryScore = 0
	self._investigateNoiseUntil = 0

	-- search
	self._searchCenter = nil
	self._searchUntil = 0
	self._searchIndex = 1
	self._searchPoints = nil

	-- patrol
	self._lastPatrolStop = nil

	-- chase inertia
	self._lastChaseDir = nil

	-- debug
	self._debugTargetRoot = nil
	self._debugHasLOS = nil
	self._debugFolder = nil
	self._lastDebugPrint = 0

	-- stuck detection
	self._stuckCheckPos = nil
	self._stuckCheckTime = 0
	self._stuckAccum = 0

	-- connections
	self._connections = {}

	-- Raycast params
	self.RayParams = RaycastParams.new()
	self.RayParams.FilterDescendantsInstances = { self.Model }
	self.RayParams.FilterType = Enum.RaycastFilterType.Exclude

	-- Animações
	self.Anim = AnimationController.new(self.Humanoid)
	self.Anim:Load(self.Config.Animations)

	-- Paths reutilizáveis
	local agentCfg = self.Config.Agent
	local pathParams = {
		AgentHeight = agentCfg.Height,
		AgentRadius = agentCfg.Radius,
		AgentCanJump = agentCfg.CanJump,
		AgentCanClimb = agentCfg.CanClimb,
		WaypointSpacing = agentCfg.WaypointSpacing or 4,
		Costs = { Water = 20 },
	}
	self._chasePath = PathfindingService:CreatePath(pathParams)
	self._patrolPath = PathfindingService:CreatePath(pathParams)

	-- Evento global de ruídos
	local noiseEvent = ReplicatedStorage:FindFirstChild("RakeNoise")
	if not noiseEvent then
		noiseEvent = Instance.new("BindableEvent")
		noiseEvent.Name = "RakeNoise"
		noiseEvent.Parent = ReplicatedStorage
	end
	self._noiseEvent = noiseEvent
	self:_connect(noiseEvent.Event:Connect(function(pos, loudness)
		if typeof(pos) ~= "Vector3" then return end
		loudness = math.clamp(tonumber(loudness) or 1, 0.1, 10)
		self._lastHeardPos = pos
		self._lastHeardAt = time()
		self._lastHeardScore = loudness
	end))

	return self
end

-- Utility
function Killer:_connect(conn: RBXScriptConnection)
	table.insert(self._connections, conn)
end

function Killer:ProjectToGround(pos: Vector3): Vector3
	local rayOrigin = Vector3.new(pos.X, pos.Y + 80, pos.Z)
	local hit = workspace:Raycast(rayOrigin, Vector3.new(0, -250, 0), self.RayParams)
	if hit then
		return hit.Position
	end
	return Vector3.new(pos.X, self.Root.Position.Y, pos.Z)
end

function Killer:RememberNoise(pos: Vector3, score: number)
	local now = time()
	local ttl = self.Config.NoiseMemoryTime or 2.5
	local farEnough = self._noiseMemoryPos
		and (pos - self._noiseMemoryPos).Magnitude >= 6

	if not self._noiseMemoryPos
		or now >= self._noiseMemoryUntil
		or farEnough
		or score > (self._noiseMemoryScore or 0) + 0.08
	then
		self._noiseMemoryPos = self:ProjectToGround(pos)
		self._noiseMemoryUntil = now + ttl
		self._noiseMemoryScore = score
	end
end

function Killer:GetRememberedNoise(): (Vector3?, number)
	if self._noiseMemoryPos and time() < self._noiseMemoryUntil then
		return self._noiseMemoryPos, self._noiseMemoryScore or 0
	end
	return nil, 0
end

function Killer:HearNoisePosition(): (Vector3?, number)
	local h = self.Config.Hearing or {}
	local walkDist = h.WalkDistance or 18
	local runDist = h.RunDistance or 36
	local minNoise = h.MinNoise or 0.22
	local runNoise = h.RunNoise or 0.70
	local occMul = h.OccludedMultiplier or 0.15
	local occMaxFactor= h.OccludedMaxDistanceFactor or 0.6
	local eventMaxDist= h.EventMaxDistance or 50

	local bestPos: Vector3? = nil
	local bestScore = 0

	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		if not char then continue end
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not root or not hum or hum.Health <= 0 then continue end

		local noise = self:GetPlayerNoiseLevel(plr)
		if noise < minNoise then continue end

		local maxDist = if noise >= runNoise then runDist else walkDist
		local dist = (self.Root.Position - root.Position).Magnitude
		if dist > maxDist then continue end

		if not self:HasLineOfSight(root) then
			if dist > (maxDist * occMaxFactor) then continue end
			noise *= occMul
		end

		local score = noise * (1 - dist / maxDist)
		if score > bestScore then
			bestScore = score
			bestPos = root.Position
		end
	end

	if self._lastHeardPos and (time() - self._lastHeardAt) < 1.2 then
		local dist = (self.Root.Position - self._lastHeardPos).Magnitude
		if dist <= eventMaxDist then
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

function Killer:GetPlayerNoiseLevel(player: Player): number
	local char = player.Character
	if not char then return 0 end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 then return 0 end

	local v = root.AssemblyLinearVelocity
	local horiz = Vector3.new(v.X, 0, v.Z).Magnitude
	local cap = math.max(hum.WalkSpeed, 1)
	return math.clamp(horiz / cap, 0, 1)
end

function Killer:HasLineOfSight(targetRoot: BasePart): boolean
	local origin = self.Root.Position
	local direction = targetRoot.Position - origin

	local result = workspace:Raycast(origin, direction, self.RayParams)
	if result then
		local character = result.Instance:FindFirstAncestorOfClass("Model")
		if character and Players:GetPlayerFromCharacter(character) then
			return true
		end
		return false
	end
	return true
end

function Killer:IsInFieldOfView(targetRoot: BasePart): boolean
	local toTarget = (targetRoot.Position - self.Root.Position).Unit
	local look = self.Root.CFrame.LookVector
	local dot = math.clamp(toTarget:Dot(look), -1, 1)
	local angle = math.deg(math.acos(dot))
	return angle < self.Config.FieldOfViewAngle
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
		if dist >= maxDist then continue end
		if not self:HasLineOfSight(root) then continue end

		local closeEnough = dist <= (self.Config.DetectCloseDistance or 12) * 1.35
		if closeEnough or self:IsInFieldOfView(root) then
			maxDist = dist
			nearest = player
		end
	end

	return nearest
end

function Killer:IsValidTarget(player: Player?): boolean
	if not player then return false end
	local char = player.Character
	if not char then return false end
	local root = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	return root ~= nil and hum ~= nil and hum.Health > 0
end

function Killer:RememberTarget(player: Player, pos: Vector3)
	self._targetMemory[player.UserId] = {
		pos = pos,
		expiry = time() + 15,
		score = 1.0,
	}
end

function Killer:GetBestMemoryTarget(): Player?
	local best: Player? = nil
	local bestScore = 0
	local now = time()
	for userId, mem in pairs(self._targetMemory) do
		if now < mem.expiry and mem.score > bestScore then
			bestScore = mem.score
			best = Players:GetPlayerByUserId(userId)
		end
	end
	return best
end

function Killer:CleanMemory()
	local now = time()
	for userId, mem in pairs(self._targetMemory) do
		if now > mem.expiry then
			self._targetMemory[userId] = nil
		end
	end
end

function Killer:AddHorizontalJitter(pos: Vector3, radius: number): Vector3
	local a = math.random() * math.pi * 2
	local r = math.random() * radius
	return pos + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
end

function Killer:GetWallAvoidanceForce(): Vector3
	local wa = self.Config.WallAvoidance
	if not wa or not wa.Enabled then
		return Vector3.zero
	end

	local numRays = wa.RayCount or 5
	local spread = math.rad(wa.SpreadAngle or 90)
	local rayLen = wa.RayLength or 6
	local weight = wa.Weight or 4
	local force = Vector3.zero
	local look = self.Root.CFrame.LookVector

	for i = 1, numRays do
		local frac = (i - 1) / math.max(numRays - 1, 1)
		local angle = -spread / 2 + spread * frac
		local dir = (CFrame.fromAxisAngle(Vector3.yAxis, angle) * CFrame.new(Vector3.new(look.X, 0, look.Z).Unit * rayLen)).Position

		local hit = workspace:Raycast(self.Root.Position, dir, self.RayParams)
		if hit then
			local penetration = rayLen - hit.Distance
			local pushDir = (self.Root.Position - hit.Position)
			pushDir = Vector3.new(pushDir.X, 0, pushDir.Z)
			local mag = pushDir.Magnitude
			if mag > 0.001 then
				pushDir = pushDir.Unit
			end
			force += pushDir * (penetration / rayLen) * weight
		end
	end

	return force
end

function Killer:SmoothWaypoints(rawWaypoints: { PathWaypoint }): { Vector3 }
	if not self.Config.PathSmoothing or #rawWaypoints < 3 then
		local pts = {}
		for _, wp in ipairs(rawWaypoints) do
			table.insert(pts, wp.Position)
		end
		return pts
	end

	local positions = {}
	for _, wp in ipairs(rawWaypoints) do
		table.insert(positions, wp.Position)
	end

	local smoothed = { positions[1] }
	for i = 2, #positions - 1 do
		local p0 = positions[i - 1]
		local p1 = positions[i]
		local p2 = positions[i + 1]
		table.insert(smoothed, p0:Lerp(p1, 0.75))
		table.insert(smoothed, p1:Lerp(p2, 0.25))
	end
	table.insert(smoothed, positions[#positions])

	return smoothed
end

function Killer:ComputePathAsync(pathObj, from: Vector3, to: Vector3)
	if self._pathComputing then return end
	self._pathComputing = true
	self._lastPathTarget = to

	task.spawn(function()
		local ok = pcall(function()
			pathObj:ComputeAsync(from, to)
		end)

		if ok and pathObj.Status == Enum.PathStatus.Success then
			local raw = pathObj:GetWaypoints()
			self._jumpWaypoints = {}
			for i, wp in ipairs(raw) do
				if wp.Action == Enum.PathWaypointAction.Jump then
					self._jumpWaypoints[i] = true
				end
			end
			self._waypoints = self:SmoothWaypoints(raw)
			local bestIdx, bestDist = 1, math.huge
			for i = 2, #self._waypoints do
				local d = (self.Root.Position - self._waypoints[i]).Magnitude
				if d < bestDist then bestDist = d; bestIdx = i end
			end
			self._wpIndex = bestIdx
		else
			local gotPartial = false
			for _, frac in ipairs({ 0.8, 0.6, 0.4 }) do
				local partial = from:Lerp(to, frac)
				local ok2 = pcall(function()
					pathObj:ComputeAsync(from, partial)
				end)
				if ok2 and pathObj.Status == Enum.PathStatus.Success then
					local raw = pathObj:GetWaypoints()
					self._waypoints = self:SmoothWaypoints(raw)
					self._wpIndex = 2
					gotPartial = true
					break
				end
			end
			if not gotPartial then
				self._waypoints = {}
				self._wpIndex = 1
			end
		end

		self._pathComputing = false
	end)
end

function Killer:UpdateStuckDetection(dt: number): boolean
	local sd = self.Config.StuckDetection
	if not sd or not sd.Enabled then return false end

	self._stuckCheckTime += dt
	if self._stuckCheckTime >= (sd.CheckInterval or 0.5) then
		local pos = self.Root.Position
		if self._stuckCheckPos then
			local moved = (pos - self._stuckCheckPos).Magnitude
			if moved < (sd.MinMovement or 0.5) then
				self._stuckAccum += self._stuckCheckTime
			else
				self._stuckAccum = 0
			end
		end
		self._stuckCheckPos = pos
		self._stuckCheckTime = 0
	end

	return self._stuckAccum >= (sd.MaxStuckTime or 2.0)
end

function Killer:ResetStuck()
	self._stuckAccum = 0
	self._stuckCheckTime = 0
	self._stuckCheckPos = nil
end

function Killer:UpdateSpeed(dt: number)
	local cfg = self.Config
	local diff = self._desiredSpeed - self._currentSpeed
	local rate = if diff > 0 then (cfg.Acceleration or 14) else (cfg.Deceleration or 22)
	local step = math.sign(diff) * math.min(math.abs(diff), rate * dt)

	self._currentSpeed += step
	self.Humanoid.WalkSpeed = math.max(self._currentSpeed, 0)
end

function Killer:UpdateRotation(dt: number)
	if not self._desiredLookAt then return end

	local isStationary = self.State == States.Attack
		or self.State == States.Scream
		or self._currentSpeed < 0.5
	if not isStationary then return end

	local targetFlat = Vector3.new(
		self._desiredLookAt.X,
		self.Root.Position.Y,
		self._desiredLookAt.Z
	)

	local dist = (targetFlat - self.Root.Position).Magnitude
	if dist < 0.5 then return end

	local goalCF = CFrame.lookAt(self.Root.Position, targetFlat)
	local alpha = math.min((self.Config.TurnSpeed or 8) * dt, 1)
	self.Root.CFrame = self.Root.CFrame:Lerp(goalCF, alpha)
end

function Killer:UpdateAnimation(dt: number)
	if self.Anim:IsPlaying("Attack") then return end

	local velocity = self.Root.AssemblyLinearVelocity
	local rawSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude

	if not self._animSpeedSmooth then self._animSpeedSmooth = 0 end
	self._animSpeedSmooth += (rawSpeed - self._animSpeedSmooth) * math.min(dt * 12, 1)
	local s = self._animSpeedSmooth

	local anim
	if s > 12 then
		anim = "Run"
	elseif s > 1.5 then
		anim = "Walk"
	else
		anim = "Idle"
	end

	self.Anim:Play(anim)

	if anim == "Run" then
		local ps = s / (self.Config.ChaseSpeed or 20)
		self.Anim:AdjustSpeed("Run", math.clamp(ps, 0.8, 1.5))
	elseif anim == "Walk" then
		local ps = s / (self.Config.PatrolSpeed or 8)
		self.Anim:AdjustSpeed("Walk", math.clamp(ps, 0.8, 1.2))
	end
end

function Killer:BuildSearchPoints(center: Vector3, radius: number, count: number): { Vector3 }
	local points = {}
	for i = 1, count do
		local a = (i / count) * math.pi * 2
		local r = radius * (0.55 + 0.45 * math.random())
		table.insert(points, center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r))
	end
	table.insert(points, center)
	return points
end

function Killer:StartSearch(center: Vector3)
	self.State = States.Suspicious
	self._searchCenter = center
	self._searchUntil = time() + (self.Config.InvestigationTime or 10)
	self._searchIndex = 1
	self._searchPoints = self:BuildSearchPoints(
		center,
		(self.Config.HearingDistance or 25) * 0.55,
		6
	)
	self._waypoints = {}
	self._wpIndex = 1
end

function Killer:ClearSearch()
	self._searchCenter = nil
	self._searchPoints = nil
	self._searchIndex = 1
end

function Killer:GetGravityPoint(): Vector3?
	local players = Players:GetPlayers()
	if #players == 0 then return nil end

	local sum, count = Vector3.zero, 0
	local nearestPos: Vector3? = nil
	local nearestDist = math.huge

	for _, player in ipairs(players) do
		local char = player.Character
		if char and char:FindFirstChild("HumanoidRootPart") then
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

	if count == 0 or not nearestPos then return nil end

	local w = self.Config.GravityWeights
	return (sum / count) * w.centerOfMass + nearestPos * w.nearest
end

function Killer:PickPatrolTarget(): Vector3
	local cfg = self.Config
	local gp = self:GetGravityPoint()
	local origin = gp or self.Root.Position
	local range = cfg.PatrolWanderRange or 35

	for _ = 1, 6 do
		local x = origin.X + math.random(-range, range)
		local z = origin.Z + math.random(-range, range)
		local dest = self:ProjectToGround(Vector3.new(x, origin.Y, z))

		if self._lastPatrolStop and (dest - self._lastPatrolStop).Magnitude < 3 then
			range = math.max(8, range * 0.7)
			continue
		end

		return dest
	end

	return self.Root.Position + Vector3.new(math.random(-8, 8), 0, math.random(-8, 8))
end

function Killer:Attack(target: Player)
	local char = target.Character
	if not char then return end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local targetRoot = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not targetRoot or humanoid.Health <= 0 then return end

	local dist = (self.Root.Position - targetRoot.Position).Magnitude
	if dist > self.Config.AttackDistance then return end

	local track = self.Anim.Tracks["Attack"]
	if track then
		track:Play(0.1)
		task.delay(track.Length * 0.4, function()
			if humanoid and humanoid.Parent and targetRoot then
				local d = (self.Root.Position - targetRoot.Position).Magnitude
				if d <= self.Config.AttackDistance + 2 then
					humanoid:TakeDamage(self.Config.AttackDamage)
				end
			end
		end)
	else
		humanoid:TakeDamage(self.Config.AttackDamage)
	end
end

function Killer:DoScream(targetRoot: BasePart?)
	if self._screaming then return end
	self._screaming = true
	self._screamEndTime = time() + (self.Config.ScreamDuration or 2)

	self.State = States.Scream
	self._desiredSpeed = 0

	if targetRoot then
		self._desiredLookAt = targetRoot.Position
	end

	local track = self.Anim.Tracks["Scream"]
	if track then track:Play(0.1) end

	local screamSound = self.Model:FindFirstChild("ScreamSound", true)
	if screamSound and screamSound:IsA("Sound") then
		screamSound:Play()
	end
end

-- FOLLOW WAYPOINTS (com correção de backtracking)
function Killer:FollowWaypoints(dt: number, chaseMode: boolean?)
	local wps = self._waypoints
	if not wps or #wps == 0 then return end

	local cfg = self.Config
	local lookahead = cfg.WaypointLookahead or 2
	local arrival = cfg.WaypointArrivalDist or 3

	-- Avançar índice se já estiver perto o suficiente
	while self._wpIndex <= #wps do
		local d = (self.Root.Position - wps[self._wpIndex]).Magnitude
		if d < arrival then
			self._wpIndex += 1
		else
			break
		end
	end

	-- CORREÇÃO: Pular waypoints que estão atrás do NPC
	local forward = self.Root.CFrame.LookVector
	while self._wpIndex <= #wps do
		local toWP = wps[self._wpIndex] - self.Root.Position
		if toWP:Dot(forward) < -0.1 and self._wpIndex < #wps then
			self._wpIndex += 1
		else
			break
		end
	end

	if self._wpIndex > #wps then return end

	local lookIdx = math.min(self._wpIndex + lookahead, #wps)
	local target = wps[lookIdx]

	for i = self._wpIndex, lookIdx do
		if self._jumpWaypoints and self._jumpWaypoints[i] then
			self.Humanoid.Jump = true
			break
		end
	end

	local avoidance = self:GetWallAvoidanceForce()
	local finalTarget = target + avoidance

	self._desiredLookAt = finalTarget

	if chaseMode then
		local dir = (finalTarget - self.Root.Position)
		dir = Vector3.new(dir.X, 0, dir.Z)
		if dir.Magnitude > 0.01 then
			self.Humanoid:Move(dir.Unit)
		end
	else
		self.Humanoid:MoveTo(finalTarget)
	end
end

-- ============================================================================
-- MAIN LOOP
-- ============================================================================
function Killer:Start()
	local cfg = self.Config

	-- Limpeza de memória periódica
	task.spawn(function()
		while self.Model and self.Model.Parent do
			self:CleanMemory()
			task.wait(5)
		end
	end)

	local patrolPauseUntil = 0
	local patrolTarget: Vector3? = nil
	local needNewPatrol = true

	self:_connect(RunService.Heartbeat:Connect(function(dt)
		if not self.Root or not self.Root.Parent then return end
		if not self.Humanoid or self.Humanoid.Health <= 0 then return end

		self:DebugUpdate(self._debugTargetRoot, self._debugHasLOS)

		-- 0. Scream cooldown
		if self._screaming then
			if time() >= self._screamEndTime then
				self._screaming = false
			else
				self:UpdateSpeed(dt)
				self:UpdateRotation(dt)
				self:UpdateAnimation(dt)
				return
			end
		end

		-- 1. PERCEPÇÃO
		local visibleTarget = self:FindVisibleTarget()
		local noisePos: Vector3? = nil
		local noiseScore: number = 0

		if not visibleTarget then
			noisePos, noiseScore = self:HearNoisePosition()
			if noisePos and noiseScore > 0 then
				self:RememberNoise(noisePos, noiseScore)
			end
			noisePos, noiseScore = self:GetRememberedNoise()
		end

		local lockedTarget = self.Target
		local lockActive = lockedTarget
			and time() < self._targetLockUntil
			and self:IsValidTarget(lockedTarget)

		local target = visibleTarget or (lockActive and lockedTarget) or nil

		-- 2. DECISÃO (máquina de estados)
		if target then
			self.Target = target
			local char = target.Character
			local targetRoot = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not targetRoot then
				self.Target = nil
			else
				local dist = (self.Root.Position - targetRoot.Position).Magnitude

				if visibleTarget then
					self._targetLockUntil = time() + (cfg.TargetLockTime or 10)
					self.LastKnownPosition = targetRoot.Position
					self._lastVisiblePos = targetRoot.Position
					self._lostSightSince = nil
					self:RememberTarget(target, targetRoot.Position)
					self:ClearSearch()
					needNewPatrol = true
				else
					if not self._lostSightSince then
						self._lostSightSince = time()
					end
				end

				-- scream
				if visibleTarget and not self._screaming and self.State ~= States.Attack then
					local now = time()
					local cd = cfg.ScreamCooldown or 18
					if (now - self._lastScreamTime) >= cd
						and math.random() < (cfg.ScreamChance or 0)
					then
						self._lastScreamTime = now
						self:DoScream(targetRoot)
						self:UpdateSpeed(dt)
						self:UpdateRotation(dt)
						self:UpdateAnimation(dt)
						return
					end
				end

				-- desiste de chase quando perde visão por tempo suficiente
				if not visibleTarget and self._lostSightSince then
					local elapsed = time() - self._lostSightSince
					local giveUp = cfg.HideAfterLostTarget or 20

					if elapsed >= giveUp then
						self.Target = nil
						if self._lastVisiblePos then
							self:StartSearch(self._lastVisiblePos)
						end
						target = nil
					elseif elapsed >= 3.0 then
						if not self._searchCenter then
							local searchPos = self._lastVisiblePos or targetRoot.Position
							self:StartSearch(searchPos)
						end
					end
				end

				if target then
					if dist <= cfg.AttackDistance then
						---------- ATTACK ----------
						self.State = States.Attack
						self._desiredSpeed = 0
						self._desiredLookAt = targetRoot.Position

						local now = time() -- CORREÇÃO: usar time()
						if now - self.LastAttackTime >= cfg.AttackCooldown then
							self.LastAttackTime = now
							self:Attack(target)
						end

						self:UpdateSpeed(dt)
						self:UpdateRotation(dt)
						self:UpdateAnimation(dt)
						return

					else
						---------- CHASE ----------
						self.State = States.Chase
						self._desiredSpeed = cfg.ChaseSpeed

						local vel = targetRoot.AssemblyLinearVelocity
						local hVel = Vector3.new(vel.X, 0, vel.Z)
						local t = math.clamp(dist / math.max(cfg.ChaseSpeed, 1), 0.05, 0.9)
						local predicted = targetRoot.Position + hVel * t

						local hasLOS = self:HasLineOfSight(targetRoot)

						self._debugTargetRoot = targetRoot
						self._debugHasLOS = hasLOS

						-- CORREÇÃO: transição suave quando perde LOS recentemente
						local justLostLOS = not hasLOS
							and self._lostSightSince
							and (time() - self._lostSightSince) < 0.3

						if hasLOS or justLostLOS then
							-- Movimento direto (predição ou última posição visível)
							local moveTarget = hasLOS and predicted or (self._lastVisiblePos or predicted)
							local avoidance = self:GetWallAvoidanceForce()
							local desired = (moveTarget - self.Root.Position)
							local dir = Vector3.new(desired.X, 0, desired.Z)
							if dir.Magnitude > 0.01 then dir = dir.Unit end
							local finalDir = dir + avoidance * 0.3
							if finalDir.Magnitude > 0.01 then finalDir = finalDir.Unit end
							self.Humanoid:Move(finalDir)
							self._lastChaseDir = finalDir

							-- Pré‑computar path para fallback (só se tiver LOS)
							if hasLOS and (not self._lastPathTarget
								or (self._lastPathTarget - predicted).Magnitude > 10)
							then
								self:ComputePathAsync(self._chasePath, self.Root.Position, predicted)
							end
						else
							-- LOS perdido por mais de 0.3s → pathfinding
							local dest = self._lastVisiblePos or targetRoot.Position
							if not self._lastPathTarget or (self._lastPathTarget - dest).Magnitude > 8 then
								self:ComputePathAsync(self._chasePath, self.Root.Position, dest)
							end

							local wps = self._waypoints
							if wps and #wps > 0 and self._wpIndex <= #wps then
								self:FollowWaypoints(dt, true)
							else
								local inertia = self._lastChaseDir
								if inertia and inertia.Magnitude > 0.01 then
									self.Humanoid:Move(inertia.Unit)
								else
									local toCorner = (dest - self.Root.Position)
									toCorner = Vector3.new(toCorner.X, 0, toCorner.Z)
									if toCorner.Magnitude > 1 then
										self.Humanoid:Move(toCorner.Unit)
									end
								end
							end
						end

						if self:UpdateStuckDetection(dt) then
							self:ResetStuck()
							self._lastPathTarget = nil
						end

						self:UpdateSpeed(dt)
						self:UpdateRotation(dt)
						self:UpdateAnimation(dt)
						return
					end
				end
			end
		end

		-- Sem alvo → investigar / buscar / patrulhar
		self.Target = nil
		self._debugTargetRoot = nil
		self._debugHasLOS = nil

		-- INVESTIGATE NOISE
		if noisePos and noiseScore >= (cfg.NoiseInvestigateThreshold or 0.18) then
			local now = time()
			if now >= self._investigateNoiseUntil then
				self._investigateNoiseUntil = now + (cfg.NoiseInvestigateCooldown or 1.2)
				local jitterRadius = cfg.InvestigationJitterRadius or 6
				local dest = self:AddHorizontalJitter(noisePos, jitterRadius)
				dest = self:ProjectToGround(dest)

				self.State = States.Investigate
				self._desiredSpeed = cfg.CheckNoiseSpeed or 16
				self:ComputePathAsync(self._patrolPath, self.Root.Position, dest)
				self:ClearSearch()
				needNewPatrol = true
			end

			local wps = self._waypoints
			if wps and #wps > 0 and self._wpIndex <= #wps then
				self:FollowWaypoints(dt)
			elseif noisePos then
				self.Humanoid:MoveTo(noisePos)
			end

			if self:UpdateStuckDetection(dt) then
				self:ResetStuck()
				self:StartSearch(noisePos)
			end

			self:UpdateSpeed(dt)
			self:UpdateRotation(dt)
			self:UpdateAnimation(dt)
			return
		end

		-- SEARCH
		if self._searchCenter and time() < self._searchUntil then
			self.State = States.Suspicious
			self._desiredSpeed = cfg.InvestigationSpeed or cfg.PatrolSpeed

			local points = self._searchPoints
			if not points or #points == 0 then
				self._searchPoints = self:BuildSearchPoints(
					self._searchCenter,
					(cfg.HearingDistance or 25) * 0.55,
					6
				)
				points = self._searchPoints
			end

			local currentWps = self._waypoints
			local needNextPoint = (not currentWps
				or #currentWps == 0
				or self._wpIndex > #currentWps)
				and not self._pathComputing

			if needNextPoint then
				local p = points[self._searchIndex]
				self._searchIndex += 1
				if self._searchIndex > #points then
					self._searchIndex = 1
					self._searchPoints = self:BuildSearchPoints(
						self._searchCenter,
						(cfg.HearingDistance or 25) * 0.55,
						6
					)
				end
				self:ComputePathAsync(self._patrolPath, self.Root.Position, p)
			end

			local searchWps = self._waypoints
			if searchWps and #searchWps > 0 and self._wpIndex <= #searchWps then
				self:FollowWaypoints(dt)
			elseif points and points[self._searchIndex] then
				self.Humanoid:MoveTo(points[self._searchIndex])
			end

			if self:UpdateStuckDetection(dt) then
				self:ResetStuck()
				self._waypoints = {}
			end

			self:UpdateSpeed(dt)
			self:UpdateRotation(dt)
			self:UpdateAnimation(dt)
			return
		end

		if self._searchCenter then
			self:ClearSearch()
			needNewPatrol = true
		end

		if self.LastKnownPosition then
			self:StartSearch(self.LastKnownPosition)
			self.LastKnownPosition = nil
			self:UpdateSpeed(dt)
			self:UpdateRotation(dt)
			self:UpdateAnimation(dt)
			return
		end

		-- PATROL
		self.State = States.Patrol

		if time() < patrolPauseUntil then
			self._desiredSpeed = 0
			self:UpdateSpeed(dt)
			self:UpdateRotation(dt)
			self:UpdateAnimation(dt)
			return
		end

		if needNewPatrol then
			patrolTarget = self:PickPatrolTarget()
			needNewPatrol = false
			self:ComputePathAsync(self._patrolPath, self.Root.Position, patrolTarget)
			self:ResetStuck()

			if math.random(1, 5) == 1 then
				patrolPauseUntil = time() + math.random() * 2 + 1
			end
		end

		self._desiredSpeed = cfg.PatrolSpeed

		local wps = self._waypoints
		if (not wps or #wps == 0 or self._wpIndex > #wps) and not self._pathComputing then
			self._lastPatrolStop = self.Root.Position
			needNewPatrol = true
		end

		if (not wps or #wps == 0 or self._wpIndex > #wps) and patrolTarget then
			self.Humanoid:MoveTo(patrolTarget)
		else
			self:FollowWaypoints(dt)
		end

		if self:UpdateStuckDetection(dt) then
			self:ResetStuck()
			needNewPatrol = true
		end

		self:UpdateSpeed(dt)
		self:UpdateRotation(dt)
		self:UpdateAnimation(dt)
	end))
end

-- SPAWN / DESTROY
function Killer:Spawn()
	self.Model:PivotTo(self.Config.BaseSpawnLocation)

	for _, part in ipairs(self.Model:GetDescendants()) do
		if part:IsA("BasePart") then
			part:SetNetworkOwner(nil)
		end
	end

	self:Start()
end

function Killer:Destroy()
	for _, conn in ipairs(self._connections) do
		if conn.Connected then
			conn:Disconnect()
		end
	end
	self._connections = {}

	if self.Anim then
		self.Anim:Destroy()
	end

	self._waypoints = {}
	self._searchPoints = nil
	self._targetMemory = {}

	self:DebugClear()
end

-- DEBUG (inalterado, apenas com uso de time() corrigido)
local DEBUG_COLORS = {
	Idle = Color3.fromRGB(128, 128, 128),
	Patrol = Color3.fromRGB(0, 170, 255),
	Suspicious = Color3.fromRGB(255, 200, 0),
	Investigate = Color3.fromRGB(255, 140, 0),
	Stalk = Color3.fromRGB(180, 0, 255),
	Chase = Color3.fromRGB(255, 0, 0),
	Attack = Color3.fromRGB(200, 0, 0),
	Scream = Color3.fromRGB(255, 0, 128),
}

function Killer:_getDebugFolder(): Folder
	if self._debugFolder and self._debugFolder.Parent then
		return self._debugFolder
	end
	local folder = Instance.new("Folder")
	folder.Name = "RakeDebug_" .. (self.Model and self.Model.Name or "Unknown")
	folder.Parent = workspace
	self._debugFolder = folder
	return folder
end

function Killer:_createDebugSphere(pos: Vector3, color: Color3, size: number?, name: string?): BasePart
	local sphere = Instance.new("Part")
	sphere.Shape = Enum.PartType.Ball
	sphere.Size = Vector3.new(size or 1, size or 1, size or 1)
	sphere.Position = pos
	sphere.Anchored = true
	sphere.CanCollide = false
	sphere.CanQuery = false
	sphere.CanTouch = false
	sphere.Material = Enum.Material.Neon
	sphere.Color = color
	sphere.Transparency = 0.3
	sphere.Name = name or "DebugSphere"
	sphere.Parent = self:_getDebugFolder()
	return sphere
end

function Killer:_createDebugLine(from: Vector3, to: Vector3, color: Color3, thickness: number?, name: string?): BasePart
	local dist = (to - from).Magnitude
	if dist < 0.01 then return nil :: any end

	local line = Instance.new("Part")
	line.Size = Vector3.new(thickness or 0.15, thickness or 0.15, dist)
	line.CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -dist / 2)
	line.Anchored = true
	line.CanCollide = false
	line.CanQuery = false
	line.CanTouch = false
	line.Material = Enum.Material.Neon
	line.Color = color
	line.Transparency = 0.4
	line.Name = name or "DebugLine"
	line.Parent = self:_getDebugFolder()
	return line
end

function Killer:DebugClear()
	if self._debugFolder and self._debugFolder.Parent then
		self._debugFolder:Destroy()
	end
	self._debugFolder = nil
end

function Killer:DebugDrawPath()
	local dbg = self.Config.Debug
	if not dbg or not dbg.Enabled or not dbg.ShowPath then return end

	local folder = self:_getDebugFolder()
	for _, child in ipairs(folder:GetChildren()) do
		if child.Name == "WP" or child.Name == "PathLine" or child.Name == "WPCurrent" then
			child:Destroy()
		end
	end

	local wps = self._waypoints
	if not wps or #wps == 0 then return end

	local stateColor = DEBUG_COLORS[self.State] or Color3.fromRGB(255, 255, 255)

	for i, wp in ipairs(wps) do
		local isCurrent = (i == self._wpIndex)
		local size = if isCurrent then 1.8 else 0.8
		local color = if isCurrent then Color3.fromRGB(0, 255, 0) else stateColor
		local name = if isCurrent then "WPCurrent" else "WP"

		self:_createDebugSphere(wp + Vector3.new(0, 1, 0), color, size, name)

		if i > 1 then
			self:_createDebugLine(
				wps[i - 1] + Vector3.new(0, 1, 0),
				wp + Vector3.new(0, 1, 0),
				stateColor, 0.12, "PathLine"
			)
		end
	end

	if self._wpIndex <= #wps then
		self:_createDebugLine(
			self.Root.Position,
			wps[self._wpIndex] + Vector3.new(0, 1, 0),
			Color3.fromRGB(0, 255, 0), 0.2, "PathLine"
		)
	end
end

function Killer:DebugDrawLOS(targetRoot: BasePart?, hasLOS: boolean)
	local dbg = self.Config.Debug
	if not dbg or not dbg.Enabled or not dbg.ShowLOS then return end

	local folder = self:_getDebugFolder()
	for _, child in ipairs(folder:GetChildren()) do
		if child.Name == "LOSLine" or child.Name == "LOSHit" then
			child:Destroy()
		end
	end

	if not targetRoot then return end

	local color = if hasLOS
		then Color3.fromRGB(0, 255, 0)
		else Color3.fromRGB(255, 0, 0)

	self:_createDebugLine(
		self.Root.Position + Vector3.new(0, 2, 0),
		targetRoot.Position + Vector3.new(0, 2, 0),
		color, 0.1, "LOSLine"
	)
end

function Killer:DebugDrawAvoidance()
	local dbg = self.Config.Debug
	if not dbg or not dbg.Enabled or not dbg.ShowAvoidance then return end

	local folder = self:_getDebugFolder()
	for _, child in ipairs(folder:GetChildren()) do
		if child.Name == "AvoidRay" then
			child:Destroy()
		end
	end

	local waCfg = self.Config.WallAvoidance
	if not waCfg or not waCfg.Enabled then return end

	local rayCount = waCfg.RayCount or 5
	local spreadDeg = waCfg.SpreadAngle or 90
	local rayLen = waCfg.RayLength or 6

	local forward = self.Root.CFrame.LookVector
	local flatFwd = Vector3.new(forward.X, 0, forward.Z)
	if flatFwd.Magnitude < 0.01 then return end
	flatFwd = flatFwd.Unit

	local halfSpread = math.rad(spreadDeg / 2)
	local origin = self.Root.Position + Vector3.new(0, 1, 0)

	for i = 0, rayCount - 1 do
		local frac = if rayCount > 1 then i / (rayCount - 1) else 0.5
		local angle = -halfSpread + frac * halfSpread * 2

		local rotCF = CFrame.Angles(0, angle, 0)
		local dir3 = rotCF:VectorToWorldSpace(flatFwd)
		local rayDir = dir3 * rayLen

		local hit = workspace:Raycast(origin, rayDir, self.RayParams)
		local endPoint = if hit then hit.Position else (origin + rayDir)
		local color = if hit
			then Color3.fromRGB(255, 80, 80)
			else Color3.fromRGB(80, 255, 80)

		self:_createDebugLine(origin, endPoint, color, 0.08, "AvoidRay")
	end
end

function Killer:DebugPrint(targetRoot: BasePart?, hasLOS: boolean?)
	local dbg = self.Config.Debug
	if not dbg or not dbg.Enabled then return end

	local now = time()
	if not self._lastDebugPrint then self._lastDebugPrint = 0 end
	if (now - self._lastDebugPrint) < (dbg.PrintInterval or 0.5) then return end
	self._lastDebugPrint = now

	local wps = self._waypoints or {}
	local wpInfo = string.format("wp %d/%d", self._wpIndex or 0, #wps)
	local speedInfo = string.format("spd %.1f/%.1f", self._currentSpeed or 0, self._desiredSpeed or 0)

	local targetName = "none"
	local targetDist = "--"
	if self.Target then
		targetName = self.Target.Name or "?"
		if targetRoot then
			targetDist = string.format("%.1f", (self.Root.Position - targetRoot.Position).Magnitude)
		end
	end

	local losStr = "N/A"
	if hasLOS ~= nil then
		losStr = if hasLOS then "YES" else "NO"
	end

	local moveMode = "none"
	if self.State == "Chase" then
		if hasLOS then
			moveMode = "Move(dir) [LOS]"
		else
			if wps and #wps > 0 and (self._wpIndex or 1) <= #wps then
				moveMode = "Move(dir) [waypoints]"
			else
				moveMode = "Move(dir) [INERTIA]"
			end
		end
	elseif self.State == "Patrol" or self.State == "Investigate" or self.State == "Suspicious" then
		if wps and #wps > 0 and (self._wpIndex or 1) <= #wps then
			moveMode = "MoveTo [waypoints]"
		else
			moveMode = "MoveTo [fallback]"
		end
	elseif self.State == "Attack" or self.State == "Scream" then
		moveMode = "PARADO"
	end

	local computing = if self._pathComputing then "COMPUTING" else "idle"

	print(string.format(
		"[RAKE] State=%-12s | %s | LOS=%s | Target=%s dist=%s | %s | path=%s | stuck=%.1f",
		self.State or "?",
		speedInfo,
		losStr,
		targetName,
		targetDist,
		wpInfo,
		computing,
		self._stuckAccum or 0
	))
	print(string.format(
		" Move=%s | Pos=(%.0f, %.0f, %.0f) | LastVisible=%s | ChaseDir=%s",
		moveMode,
		self.Root.Position.X, self.Root.Position.Y, self.Root.Position.Z,
		if self._lastVisiblePos
			then string.format("(%.0f, %.0f, %.0f)", self._lastVisiblePos.X, self._lastVisiblePos.Y, self._lastVisiblePos.Z)
			else "none",
		if self._lastChaseDir
			then string.format("(%.2f, %.2f)", self._lastChaseDir.X, self._lastChaseDir.Z)
			else "none"
	))
end

function Killer:DebugUpdate(targetRoot: BasePart?, hasLOS: boolean?)
	local dbg = self.Config.Debug
	if not dbg or not dbg.Enabled then return end

	self:DebugDrawPath()
	self:DebugDrawLOS(targetRoot, hasLOS or false)
	self:DebugDrawAvoidance()
	self:DebugPrint(targetRoot, hasLOS)
end

return Killer