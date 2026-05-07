local AnimationController = {}
AnimationController.__index = AnimationController

local PRIORITIES = {
    Idle = Enum.AnimationPriority.Idle,
    Walk = Enum.AnimationPriority.Movement,
    Run = Enum.AnimationPriority.Movement,
    Attack = Enum.AnimationPriority.Action,
    Scream = Enum.AnimationPriority.Action,
}

function AnimationController.new(humanoid)
    local self = setmetatable({}, AnimationController)
    self.Humanoid = humanoid
    self.Animator = humanoid:FindFirstChildOfClass('Animator') or humanoid:WaitForChild('Animator')
    self.Tracks = {}
    self.Current = nil
    return self
end

function AnimationController:Load(animations)
    for name, id in pairs(animations) do
        local anim = Instance.new('Animation')
        anim.AnimationId = id
        
        local track = self.Animator:LoadAnimation(anim)
        track.Priority = PRIORITIES[name] or Enum.AnimationPriority.Action
        self.Tracks[name] = track
    end
end

function AnimationController:Play(name, fadeTime)
    if self.Current == name then return end
    
    local track = self.Tracks[name]
    if not track then 
        warn("Animação não encontrada:", name)
        return 
    end

    fadeTime = fadeTime or 0.2

    if self.Current and self.Tracks[self.Current] then
        self.Tracks[self.Current]:Stop(fadeTime)
    end

    track:Play(fadeTime)
    self.Current = name
end

function AnimationController:AdjustSpeed(name, speed)
    if self.Tracks[name] then
        self.Tracks[name]:AdjustSpeed(speed)
    end
end

return AnimationController