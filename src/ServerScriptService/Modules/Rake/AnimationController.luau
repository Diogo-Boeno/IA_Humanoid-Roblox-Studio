local AnimationController = {}
AnimationController.__index = AnimationController

function AnimationController.new(humanoid)
    local self = setmetatable({}, AnimationController)

    self.Humanoid = humanoid
    self.Animator = humanoid:FindFirstChildOfClass('Animator') or humanoid:WaitForChild('Animator')
    self.Tracks = {}
    self.Current = nil

    return self
end

-- Carrega todas as animações de uma vez
function AnimationController:Load(animations)
    for name, id in pairs(animations) do
        local anim = Instance.new('Animation')
        anim.AnimationId = id

        local track = self.Animator:LoadAnimation(anim)
        track.Priority = Enum.AnimationPriority.Action
        self.Tracks[name] = track
    end
end

-- Toca uma animação, para a anterior suavemente
function AnimationController:Play(name, fadeTime)
    fadeTime = fadeTime or 0.2
    if self.Current == name then return end

    -- debounce: não troca animação mais rápido que o fadeTime
    if self._switching then return end
    self._switching = true
    task.delay(fadeTime, function()
        self._switching = false
    end)

    if self.Current and self.Tracks[self.Current] then
        self.Tracks[self.Current]:Stop(fadeTime)
    end

    if self.Tracks[name] then
        self.Tracks[name]:Play(fadeTime)
        self.Current = name
    else
        warn('AnimationController: animação não encontrada ->', name)
    end
end

function AnimationController:Stop(name, fadeTime)
    fadeTime = fadeTime or 0.2
    if self.Tracks[name] then
        self.Tracks[name]:Stop(fadeTime)
        if self.Current == name then
            self.Current = nil
        end
    end
end

function AnimationController:StopAll(fadeTime)
    fadeTime = fadeTime or 0.2
    for name, track in pairs(self.Tracks) do
        track:Stop(fadeTime)
    end
    self.Current = nil
end

return AnimationController