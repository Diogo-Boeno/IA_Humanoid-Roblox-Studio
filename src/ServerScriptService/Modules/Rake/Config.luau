return {
    -- Posicionamento
    BaseSpawnLocation = CFrame.new(0, 0, 0),
    
    -- Detecção (mais sensível à noite/som)
    MaxChaseDistance = 60,
    DetectCloseDistance = 12, -- Mais agressivo de perto
    FieldOfViewAngle = 90, -- Campo de visão amplo
    HearingDistance = 25, -- compat (legado). Use Hearing.* abaixo.
    Hearing = {
        -- Distâncias recomendadas (studs):
        -- andar normal detecta perto, correr detecta bem mais longe
        WalkDistance = 16, -- 18
        RunDistance = 32, -- 36

        -- Se quiser ajustar a classificação:
        -- abaixo disso ignora, acima disso considera "andar"
        MinNoise = 0.22,
        -- acima disso considera "corrida"
        RunNoise = 0.60,

        -- Ruído através de parede/estrutura (multiplicador + alcance efetivo)
        -- 0.15 estava fraco demais: atrás de parede o score não passava do threshold.
        OccludedMultiplier = 0.40, -- 0.35
        OccludedMaxDistanceFactor = 1.0, -- % do alcance quando não tem LOS (1.0 = ouve através de paredes na mesma distância)

        -- Ruídos de eventos (graveto, porta, etc.)
        -- Loudness (0.1..10) vira multiplicador de distância e score.
        EventMaxDistance = 50,
    },
    
    -- Velocidades (mais variadas)
    PatrolSpeed = 8,
    StalkSpeed = 12, -- Silencioso e assustador
    ChaseSpeed = 20, -- Sprint aterrorizante
    InvestigationSpeed = 8,
    CheckNoiseSpeed = 16,
    
    -- Distâncias
    StalkDistance = 25,
    AttackDistance = 5,
    
    -- Combate
    AttackDamage = 25, -- Dano
    AttackCooldown = 1.8, -- Pequena janela de fuga
    
    -- Comportamento The Rake
    ScreamChance = 0.7, -- 70% chance de gritar ao detectar
    ScreamDuration = 2.0,
    HideAfterLostTarget = 8, -- Se esconde após X segundos
    InvestigationTime = 10, -- Tempo investigando
    NoiseInvestigateThreshold = 0.18,
    NoiseInvestigateCooldown = 1.2,
    NoiseMemoryTime = 2.5,
    NoiseMoveInterruptThreshold = 0.12,
    
    -- Patrulha inteligente
    PatrolWanderRange = 35,
    GravityWeights = { centerOfMass = 0.3, nearest = 0.7 },
    
    -- Animações
    Animations = {
        Idle = 'rbxassetid://103397043187778',
        Walk = 'rbxassetid://106204575652395',
        Run = 'rbxassetid://113598626058813',
        Attack = 'rbxassetid://76074105029852',
        Scream = 'rbxassetid://114676740361584', -- of
        Stalk = 'rbxassetid://103397043187778', -- mudar
    }
}