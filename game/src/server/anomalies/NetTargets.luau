--!strict
-- Capture-net target registry (A-3 refactor of the G-7 net). §9: the net is
-- the GENERIC humanoid-anomaly catch — zombie, spy in the act, exposed
-- aliens, revealed shapeshifter. Each anomaly module registers a probe; a
-- swing resolves the single nearest target across all of them. Also home of
-- the shared evaporation puff (§4 tone rule: instant comedic resolution).

export type Hit = {
	distance: number,
	resolve: () -> string, -- performs the catch; returns a tag for swing SFX
}

export type Probe = (position: Vector3) -> Hit?

local probes: { Probe } = {}

local NetTargets = {}

function NetTargets.register(probe: Probe)
	table.insert(probes, probe)
end

-- Nearest target within range across every registered anomaly, or nil
function NetTargets.swing(position: Vector3, range: number): string?
	local best: Hit? = nil
	for _, probe in probes do
		local hit = probe(position)
		if
			hit
			and hit.distance <= range
			and (not best or hit.distance < (best :: Hit).distance)
		then
			best = hit
		end
	end
	if best then
		return (best :: Hit).resolve()
	end
	return nil
end

-- §4 counter-item puff, shared by every anomaly resolution
function NetTargets.puffAt(position: Vector3, color: Color3?)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = CFrame.new(position + Vector3.new(0, 2, 0))
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color or Color3.fromRGB(220, 245, 210))
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.2),
		NumberSequenceKeypoint.new(1, 3),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Speed = NumberRange.new(3, 6)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Enabled = false
	emitter.Parent = anchor
	anchor.Parent = workspace
	emitter:Emit(30)
	task.delay(1.5, function()
		anchor:Destroy()
	end)
end

return NetTargets
