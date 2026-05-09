local AnimationController = {}
AnimationController.__index = AnimationController

local PRIORITIES = {
	Idle   = Enum.AnimationPriority.Idle,
	Walk   = Enum.AnimationPriority.Movement,
	Run    = Enum.AnimationPriority.Movement,
	Stalk  = Enum.AnimationPriority.Movement,
	Attack = Enum.AnimationPriority.Action,
	Scream = Enum.AnimationPriority.Action,
}

function AnimationController.new(humanoid)
	local self = setmetatable({}, AnimationController)
	self.Humanoid = humanoid
	self.Animator = humanoid:FindFirstChildOfClass("Animator")
		or humanoid:WaitForChild("Animator")
	self.Tracks  = {}
	self.Current = nil
	self._loaded = false
	return self
end

function AnimationController:Load(animations)
	if self._loaded then return end
	self._loaded = true

	for name, id in pairs(animations) do
		local anim = Instance.new("Animation")
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
		warn("[AnimController] Animation not found:", name)
		return
	end

	fadeTime = fadeTime or 0.2

	if self.Current and self.Tracks[self.Current] then
		self.Tracks[self.Current]:Stop(fadeTime)
	end

	track:Play(fadeTime)
	self.Current = name
end

function AnimationController:Stop(fadeTime)
	fadeTime = fadeTime or 0.2
	if self.Current and self.Tracks[self.Current] then
		self.Tracks[self.Current]:Stop(fadeTime)
	end
	self.Current = nil
end

function AnimationController:IsPlaying(name): boolean
	local track = self.Tracks[name]
	return track ~= nil and track.IsPlaying
end

function AnimationController:AdjustSpeed(name, speed)
	local track = self.Tracks[name]
	if track then
		track:AdjustSpeed(speed)
	end
end

function AnimationController:Destroy()
	for _, track in pairs(self.Tracks) do
		track:Stop(0)
		track:Destroy()
	end
	self.Tracks  = {}
	self.Current = nil
end

return AnimationController
