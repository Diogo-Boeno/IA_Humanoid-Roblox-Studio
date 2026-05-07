local UserInputService = game:GetService("UserInputService")
local player = game:GetService('Players').LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local animator = humanoid:WaitForChild("Animator")

local SPRINT_SPEED = 22
local WALK_SPEED = 16

local anim = Instance.new("Animation")
anim.AnimationId = "rbxassetid://113598626058813"

local track = animator:LoadAnimation(anim)
track.Priority = Enum.AnimationPriority.Action

UserInputService.InputBegan:Connect(function(input, processed)	
	if input.KeyCode == Enum.KeyCode.LeftShift then
		humanoid.WalkSpeed = SPRINT_SPEED
		if track then track:Play() end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift then
		humanoid.WalkSpeed = WALK_SPEED
		if track then track:Stop() end
	end
end)