return {
    -- Posicionamento
    BaseSpawnLocation = CFrame.new(0, 0, 0),
    
    -- Detecção (mais sensível à noite/som)
    MaxChaseDistance = 60,
    DetectCloseDistance = 12, -- Mais agressivo de perto
    FieldOfViewAngle = 90, -- Campo de visão amplo
    HearingDistance = 25, -- Detecta passos correndo
    
    -- Velocidades (mais variadas)
    PatrolSpeed = 8,
    StalkSpeed = 12, -- Silencioso e assustador
    ChaseSpeed = 20, -- Sprint aterrorizante
    InvestigationSpeed = 8,
    
    -- Distâncias
    StalkDistance = 25,
    AttackDistance = 5,
    
    -- Combate
    AttackDamage = 35, -- Dano alto
    AttackCooldown = 1.8, -- Pequena janela de fuga
    
    -- Comportamento The Rake
    ScreamChance = 0.7, -- 70% chance de gritar ao detectar
    ScreamDuration = 2.0,
    HideAfterLostTarget = 8, -- Se esconde após X segundos
    InvestigationTime = 10, -- Tempo investigando
    
    -- Patrulha inteligente
    PatrolWanderRange = 35,
    GravityWeights = { centerOfMass = 0.3, nearest = 0.7 },
    
    -- Animações
    Animations = {
        Idle = 'rbxassetid://103397043187778',
        Walk = 'rbxassetid://106204575652395',
        Run = 'rbxassetid://113598626058813',
        Attack = 'rbxassetid://76074105029852',
        Scream = 'rbxassetid://76074105029852', -- mudar
        Stalk = 'rbxassetid://103397043187778', -- mudar
    }
}