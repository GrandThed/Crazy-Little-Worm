--!strict
-- Tagged-component binder (F-4). Behavior binds to models via CollectionService
-- tag + Attributes: builders drop a model, tag it, set attributes — no per-ride
-- scripting. One Component.bind() call per tag, usually at server boot.
--
-- onAttached runs once per tagged instance (already-tagged and future) and may
-- return per-instance state; onDetached receives that state when the tag is
-- removed or the instance leaves the DataModel.

local CollectionService = game:GetService("CollectionService")

export type Handlers<State> = {
	onAttached: (instance: Instance) -> State,
	onDetached: ((instance: Instance, state: State) -> ())?,
}

export type Binder = {
	stop: (self: Binder) -> (),
}

local Component = {}

function Component.bind<State>(tag: string, handlers: Handlers<State>): Binder
	-- State is boxed so `nil` returned from onAttached still marks the instance as attached
	local attached: { [Instance]: { state: State } } = {}
	local connections: { RBXScriptConnection } = {}

	local function attach(instance: Instance)
		if attached[instance] then
			return
		end
		attached[instance] = { state = handlers.onAttached(instance) }
	end

	local function detach(instance: Instance)
		local box = attached[instance]
		if not box then
			return
		end
		attached[instance] = nil
		if handlers.onDetached then
			handlers.onDetached(instance, box.state)
		end
	end

	table.insert(connections, CollectionService:GetInstanceAddedSignal(tag):Connect(attach))
	table.insert(connections, CollectionService:GetInstanceRemovedSignal(tag):Connect(detach))

	for _, instance in CollectionService:GetTagged(tag) do
		attach(instance)
	end

	local binder = {} :: Binder
	function binder:stop()
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
		for instance in attached do
			detach(instance)
		end
	end

	return binder
end

return Component
