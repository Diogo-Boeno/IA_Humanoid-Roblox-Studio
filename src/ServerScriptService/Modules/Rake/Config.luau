return {
    BaseSpawnLocation = CFrame.new(0, 0, 0),

    -- Detecção
    MaxChaseDistance = 80,
    DetectCloseDistance = 8,
    FieldOfViewAngle = 70,

    -- Velocidades
    PatrolSpeed = 7,
    StalkSpeed = 12,   -- velocidade ao stalkar
    ChaseSpeed = 18,

    -- Stalk 
    StalkDistance = 10,   -- distância que começa a stalkar (BASE = 20)

    -- Ataque
    AttackDistance = 4,
    AttackDamage = 25,
    AttackCooldown = 1.2,

    -- Scream ao detectar
    ScreamDuration = 1.5,

    -- Patrulha
    PatrolWanderRange = 25,
    GravityWeights = { centerOfMass = 0.5, nearest = 0.5 },

    -- Animações
    Animations = {
        Idle = 'rbxassetid://103397043187778',
        Walk = 'rbxassetid://106204575652395',
        Run = 'rbxassetid://113598626058813',
        Attack = 'rbxassetid://76074105029852',
    },
}