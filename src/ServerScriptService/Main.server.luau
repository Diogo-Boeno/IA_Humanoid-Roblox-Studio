local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ReplicatedStorage:WaitForChild('Modules')
local ServerModules = ServerScriptService:WaitForChild('Modules')

local Model = workspace:FindFirstChild('The_Rake')

local Rake = require(ServerModules:WaitForChild('Rake'))

local killer = Rake.new(Model)
killer:Spawn()

task.spawn(function()
    killer:Chase()
end)

local Configs = require(Modules)