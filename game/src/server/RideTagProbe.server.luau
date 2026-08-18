--!strict
-- F-4 acceptance probe: anything tagged "Ride" logs its attributes on spawn and
-- a line on despawn. In Studio it also self-spawns a throwaway tagged model so
-- the full attach → detach cycle shows in Output on Play. Replaced by the real
-- ride component in P-3.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Component = require(ReplicatedStorage.Shared.Component)

Component.bind("Ride", {
	onAttached = function(instance)
		local pairsList = {}
		for name, value in instance:GetAttributes() do
			table.insert(pairsList, ("%s=%s"):format(name, tostring(value)))
		end
		table.sort(pairsList)
		print(
			("[Component] Ride attached: %s {%s}"):format(
				instance:GetFullName(),
				table.concat(pairsList, ", ")
			)
		)
	end,
	onDetached = function(instance)
		print(("[Component] Ride detached: %s"):format(instance.Name))
	end,
})

if RunService:IsStudio() then
	task.delay(2, function()
		local testRide = Instance.new("Model")
		testRide.Name = "TestRide"
		testRide:SetAttribute("Cost", 500)
		testRide:SetAttribute("Capacity", 4)
		testRide:SetAttribute("Tier", 1)
		testRide:AddTag("Ride")
		testRide.Parent = workspace

		task.wait(3)
		testRide:Destroy()
	end)
end
