local Config = {
    BaseSpawnLocation = CFrame.new(0, 0, 0),

    -- Detecção
    MaxChaseDistance = 80,
    DetectCloseDistance = 10,  -- detecta sem linha de visão
    FieldOfViewAngle = 60,     -- graus (120 = campo de visão total)

    -- Movimento
    PatrolSpeed = 8,
    ChaseSpeed = 18,

    -- Ataque
    AttackDistance = 4,
    AttackDamage = 15,
    AttackCooldown = 1.5,

    -- Patrulha (adiciona os pontos que quiser)
    PatrolWanderRange = 20,

    GravityWeights = {
        centerOfMass = 0.5, -- push to group
        nearest = 0.5, -- push to nearest
    }
}

return Config