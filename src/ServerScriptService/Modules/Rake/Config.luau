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
    PatrolPoints = {
        Vector3.new(0, 0, 0),
        Vector3.new(20, 0, 0),
        Vector3.new(20, 0, 20),
        Vector3.new(0, 0, 20),
    },
}

return Config