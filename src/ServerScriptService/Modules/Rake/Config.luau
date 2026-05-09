return {
	-- Posicionamento
	BaseSpawnLocation = CFrame.new(0, 0, 0),

	-- Detecção
	MaxChaseDistance = 60,
	DetectCloseDistance = 12,
	FieldOfViewAngle = 90,
	HearingDistance = 25, -- legado / fallback

	Hearing = {
		WalkDistance = 16,
		RunDistance = 32,
		MinNoise = 0.22,
		RunNoise = 0.60,
		OccludedMultiplier= 0.40,
		OccludedMaxDistanceFactor = 1.0,
		EventMaxDistance  = 50,
	},

	-- Velocidades‑alvo (o NPC interpola até elas, nunca snap)
	PatrolSpeed= 8,
	StalkSpeed = 12,
	ChaseSpeed = 20,
	InvestigationSpeed  = 8,
	CheckNoiseSpeed= 16,

	-- Aceleração / desaceleração (studs/s²)
	Acceleration = 14,  -- acelerando (patrol → chase)
	Deceleration = 22,  -- freando  (chase → parado)

	-- Rotação suave
	TurnSpeed= 8,-- rad/s (quanto maior, mais rápido vira)

	-- Distâncias
	StalkDistance  = 25,
	AttackDistance = 5,

	-- Combate
	AttackDamage  = 25,
	AttackCooldown = 1.8,

	-- Comportamento The Rake
	ScreamChance = 0.7,
	ScreamDuration  = 2.0,
	ScreamCooldown  = 18,
	HideAfterLostTarget= 20,
	InvestigationTime= 10,
	NoiseInvestigateThreshold = 0.18,
	NoiseInvestigateCooldown = 1.2,
	NoiseMemoryTime = 2.5,
	NoiseMoveInterruptThreshold = 0.12,
	TargetLockTime  = 10,
	InvestigationJitterRadius = 6,

	-- Patrulha inteligente
	PatrolWanderRange = 35,
	GravityWeights= { centerOfMass = 0.3, nearest = 0.7 },

	-- Wall Avoidance (raycasts laterais)
	WallAvoidance = {
		Enabled= true,
		RayCount = 5, -- quantidade de raios em leque
		SpreadAngle = 90, -- graus totais (metade pra cada lado)
		RayLength= 6, -- studs de alcance de cada raio
		Weight = 4, -- força de repulsão
	},

	-- Pathfinding (agente)
	Agent = {
		Height = 5,
		Radius = 3, -- ajustar ao tamanho real do modelo
		CanJump= true,
		CanClimb = true,
		WaypointSpacing = 3,
	},
	PathSmoothing= true, -- Chaikin corner‑cutting nos waypoints

	-- Stuck detection
	StuckDetection = {
		Enabled = true,
		CheckInterval = 0.5, -- segundos entre checks
		MinMovement  = 0.5, -- studs mínimos no intervalo
		MaxStuckTime = 2.0, -- tempo parado antes de considerar stuck
	},

	-- Waypoint lookahead (evita stop‑go)
	WaypointLookahead= 2,-- quantos waypoints à frente mirar
	WaypointArrivalDist = 3,-- studs para considerar "chegou" no waypoint

	-- Animações
	Animations = {
		Idle  = "rbxassetid://103397043187778",
		Walk  = "rbxassetid://106204575652395",
		Run= "rbxassetid://113598626058813",
		Attack = "rbxassetid://76074105029852",
		Scream = "rbxassetid://114676740361584",
		Stalk = "rbxassetid://103397043187778",  -- TODO: substituir por animação própria
	},

	-- Debug (desligar tudo em produção)
	Debug = {
		Enabled = true,  -- master switch
		PrintInterval = 0.5,-- imprime estado a cada N segundos
		ShowPath= true,  -- mostra waypoints como esferas 3D
		ShowLOS = true,  -- mostra linha de visão
		ShowAvoidance = true,  -- mostra raycasts de wall avoidance
	},
}
