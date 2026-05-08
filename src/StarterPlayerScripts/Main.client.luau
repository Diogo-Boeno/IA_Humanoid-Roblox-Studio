local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild('Modules')

local Spawn = require(Modules:WaitForChild('SpawnPlayer'))

-- Spawna o player
Spawn.Start()
