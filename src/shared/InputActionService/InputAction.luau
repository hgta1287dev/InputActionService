--!strict
local InputAction = {}
InputAction.__index = InputAction

--[[ Config ]]
local STATUS = {
	PRESSED = "Pressed",
	RELEASED = "Released",
}
local ERRORS = {
	BINDING_EXISTS = "Binding '%s' already exists",
	BINDING_MISSING = "Binding '%s' does not exist",
}

--[[ Modules ]]
local InputBinding = require(script.Parent.InputBinding)

--[[ Types ]]
export type InputBinding = InputBinding.InputBinding
export type InputAction = {
	isEnabled: boolean,
	isActivated: boolean,

	bindings: { [string]: InputBinding },
	activeBindings: { [string]: boolean },

	Pressed: RBXScriptSignal,
	Released: RBXScriptSignal,
	Activated: RBXScriptSignal,
	Deactivated: RBXScriptSignal,
	BindingAdded: RBXScriptSignal,
	BindingRemoved: RBXScriptSignal,

	_connections: { [string]: RBXScriptConnection },
	_events: {
		Pressed: BindableEvent,
		Released: BindableEvent,
		Activated: BindableEvent,
		Deactivated: BindableEvent,
		BindingAdded: BindableEvent,
		BindingRemoved: BindableEvent,
	},
} & typeof(InputAction)

--[[ Public API ]]
function InputAction.new(): InputAction
	local self = setmetatable({} :: InputAction, InputAction)

	self.isEnabled = false
	self.isActivated = false

	self.bindings = {}
	self.activeBindings = {}

	self._connections = {}
	self._events = {
		Pressed = Instance.new("BindableEvent"),
		Released = Instance.new("BindableEvent"),
		Activated = Instance.new("BindableEvent"),
		Deactivated = Instance.new("BindableEvent"),
		BindingAdded = Instance.new("BindableEvent"),
		BindingRemoved = Instance.new("BindableEvent"),
	}

	for _, event: BindableEvent in pairs(self._events) do
		(self :: any)[event.Name] = event.Event
	end

	return self
end

function InputAction:Enable()
	if self.isEnabled then
		return
	end

	self.isEnabled = true
	self:_setup()
end

function InputAction:Disable()
	if not self.isEnabled then
		return
	end

	self.isEnabled = false
	self:_cleanup()
end

function InputAction:Destroy()
	self:Disable()

	for _, event: BindableEvent in pairs(self._events) do
		event:Destroy()
	end

	table.clear(self)
	setmetatable(self, nil)
end

function InputAction:AddBinding(name: string, binding: InputBinding)
	if self.bindings[name] then
		warn(string.format(ERRORS.BINDING_EXISTS, name))
		return
	end

	self:_setBindingConnections(name, binding, true)

	self.bindings[name] = binding
	self._events.BindingAdded:Fire(name, binding)
end

function InputAction:RemoveBinding(name: string)
	local binding = self.bindings[name]
	if not binding then
		warn(string.format(ERRORS.BINDING_MISSING, name))
		return
	end

	self:_setBindingConnections(name, binding, false)

	self.bindings[name] = nil
	self._events.BindingRemoved:Fire(name, binding)
end

--[[ Private Methods ]]
function InputAction:_updateActive()
	local isActive = next(self.activeBindings) ~= nil

	if isActive == self.isActivated then
		return
	end

	self.isActivated = isActive

	if isActive then
		self._events.Activated:Fire()
	else
		self._events.Deactivated:Fire()
	end
end

function InputAction:_setBindingConnections(name: string, binding: InputBinding, active: boolean)
	if self._connections[name .. STATUS.PRESSED] then
		self._connections[name .. STATUS.PRESSED]:Disconnect()
		self._connections[name .. STATUS.PRESSED] = nil
	end

	if self._connections[name .. STATUS.RELEASED] then
		self._connections[name .. STATUS.RELEASED]:Disconnect()
		self._connections[name .. STATUS.RELEASED] = nil
	end

	if active then
		self._connections[name .. STATUS.PRESSED] = binding.Pressed:Connect(function()
			self._events.Pressed:Fire(binding.key)
			self.activeBindings[name] = true
			self:_updateActive()
		end)

		self._connections[name .. STATUS.RELEASED] = binding.Released:Connect(function()
			self._events.Released:Fire(binding.key)
			self.activeBindings[name] = nil
			self:_updateActive()
		end)
	else
		if not self.activeBindings[name] then
			return
		end
		self._events.Released:Fire(binding.key)
		self.activeBindings[name] = nil
		self:_updateActive()
	end
end

function InputAction:_setup()
	for name: string, binding: InputBinding in pairs(self.bindings) do
		self:_setBindingConnections(name, binding, true)
	end
end

function InputAction:_cleanup()
	for name: string, binding: InputBinding in pairs(self.bindings) do
		self:_setBindingConnections(name, binding, false)
	end

	for _, connection: RBXScriptConnection in pairs(self._connections) do
		connection:Disconnect()
	end

	self._connections = {}
end

return InputAction
