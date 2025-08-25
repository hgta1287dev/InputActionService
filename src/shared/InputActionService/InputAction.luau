--!strict
local InputAction = {}
InputAction.__index = InputAction

--[[ Config ]]
local ERRORS = {
	BINDING_EXISTS = "Binding '%s' already exists",
	BINDING_MISSING = "Binding '%s' does not exist",
}

--[[ Modules ]]
local InputBinding = require(script.Parent.InputBinding)

--[[ Types ]]
export type InputBinding = InputBinding.InputBinding
export type InputBindingKey = InputBinding.InputBindingKey
export type InputBindingType = InputBinding.InputBindingType
export type BindingFromTypeConfig = {
	bindingType: InputBindingType,
	bindingKey: InputBindingKey,
}

export type InputAction = typeof(setmetatable(
	{} :: {
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
		EnabledChanged: RBXScriptSignal,
		Destroying: RBXScriptSignal,

		_events: {
			Pressed: BindableEvent,
			Released: BindableEvent,
			Activated: BindableEvent,
			Deactivated: BindableEvent,

			BindingAdded: BindableEvent,
			BindingRemoved: BindableEvent,
			EnabledChanged: BindableEvent,
			Destroying: BindableEvent,
		},
	},
	InputAction
))

--[[ Public API ]]
--// Basic constructor
function InputAction.new(bindings: { [string]: InputBinding }?): InputAction
	local self = setmetatable({}, InputAction) :: InputAction

	self.isEnabled = false
	self.isActivated = false

	self.bindings = bindings or {}
	self.activeBindings = {}

	self._events = {
		Pressed = Instance.new("BindableEvent"),
		Released = Instance.new("BindableEvent"),
		Activated = Instance.new("BindableEvent"),
		Deactivated = Instance.new("BindableEvent"),

		BindingAdded = Instance.new("BindableEvent"),
		BindingRemoved = Instance.new("BindableEvent"),
		EnabledChanged = Instance.new("BindableEvent"),
		Destroying = Instance.new("BindableEvent"),
	}

	for name, event: BindableEvent in pairs(self._events) do
		(self :: any)[name] = event.Event
	end

	--// Init
	self:Enable()

	return self
end

function InputAction:Enable()
	if self.isEnabled then
		return
	end

	self.isEnabled = true
	self._events.EnabledChanged:Fire(self.isEnabled)
end

function InputAction:Disable()
	if not self.isEnabled then
		return
	end

	self:ReleaseAll()
	self.isEnabled = false

	self._events.EnabledChanged:Fire(self.isEnabled)
end

function InputAction:Toggle(active: boolean?)
	local shouldEnabled = active ~= nil and active or not self.isEnabled
	if shouldEnabled then
		self:Enable()
	else
		self:Disable()
	end
end

function InputAction:Destroy(destroyBindings: boolean?)
	self._events.Destroying:Fire()

	self:Disable()

	if destroyBindings ~= false then
		for _, binding in pairs(self.bindings) do
			binding:Destroy()
		end
	end

	for _, event: BindableEvent in pairs(self._events) do
		event:Destroy()
	end

	table.clear(self)
	setmetatable(self, nil)
end

--// Binding management
function InputAction:AddBinding(name: string, bindingType: InputBindingType, bindingKey: InputBindingKey): InputBinding
	if self.bindings[name] then
		warn(string.format(ERRORS.BINDING_EXISTS, name))
		return self.bindings[name]
	end

	local binding = InputBinding.new(bindingType, bindingKey)

	self.bindings[name] = binding
	self._events.BindingAdded:Fire(name, binding)

	return binding
end

function InputAction:AddBindings(bindings: { [string]: { bindingType: InputBindingType, bindingKey: InputBindingKey } })
	for name, binding in pairs(bindings) do
		self:AddBinding(name, binding.bindingType, binding.bindingKey)
	end
end

function InputAction:GetBinding(name: string): InputBinding?
	return self.bindings[name]
end

function InputAction:RequireBinding(name: string): InputBinding
	local binding = self.bindings[name]
	if not binding then
		error(string.format(ERRORS.BINDING_MISSING, name), 2)
	end

	return binding
end

function InputAction:RemoveBinding(name: string, destroy: boolean?)
	local binding = self.bindings[name]
	if not binding then
		warn(string.format(ERRORS.BINDING_MISSING, name))
		return
	end

	if self.activeBindings[name] then
		self:Release(name)
	end

	if destroy ~= false then
		binding:Destroy()
	end

	self.bindings[name] = nil
	self._events.BindingRemoved:Fire(name, binding)
end

--// Action Activation
function InputAction:IsMatchingInput(input: InputObject): boolean
	for _, binding in pairs(self.bindings) do
		if binding:IsMatchingInput(input) then
			return true
		end
	end
	return false
end

function InputAction:PressInput(input: InputObject)
	if not self.isEnabled then
		return
	end

	for name, binding in pairs(self.bindings) do
		if binding:IsMatchingInput(input) then
			self:Press(name)
		end
	end
end

function InputAction:ReleaseInput(input: InputObject)
	if not self.isEnabled then
		return
	end

	for name, binding in pairs(self.bindings) do
		if binding:IsMatchingInput(input) then
			self:Release(name)
		end
	end
end

function InputAction:IsMatchingButton(button: GuiButton): boolean
	for _, binding: InputBinding in pairs(self.bindings) do
		if binding.type == "Button" and binding:IsMatchingButton(button) then
			return true
		end
	end
	return false
end

function InputAction:PressButton(button: GuiButton)
	if not self.isEnabled then
		return
	end

	for name, binding in pairs(self.bindings) do
		if binding:IsMatchingButton(button) then
			self:Press(name)
		end
	end
end

function InputAction:ReleaseButton(button: GuiButton)
	if not self.isEnabled then
		return
	end

	for name, binding in pairs(self.bindings) do
		if binding:IsMatchingButton(button) then
			self:Release(name)
		end
	end
end

function InputAction:Press(name: string)
	if not self.isEnabled then
		return
	end

	local binding = self.bindings[name]
	if not binding then
		warn(string.format(ERRORS.BINDING_MISSING, name))
		return
	end

	if self.activeBindings[name] then
		return
	end

	self.activeBindings[name] = true
	self._events.Pressed:Fire(name, binding)
	self:_updateActivation()
end

function InputAction:Release(name: string)
	if not self.isEnabled then
		return
	end

	local binding = self.bindings[name]
	if not binding then
		warn(string.format(ERRORS.BINDING_MISSING, name))
		return
	end

	if not self.activeBindings[name] then
		return
	end

	self.activeBindings[name] = nil
	self._events.Released:Fire(name, binding)
	self:_updateActivation()
end

function InputAction:ReleaseAll()
	local activeBindings = table.clone(self.activeBindings)
	if not next(activeBindings) then
		return
	end

	for name in pairs(activeBindings) do
		self:Release(name)
	end
end

--[[ Private Methods ]]
function InputAction:_updateActivation()
	local isActivated = self.isEnabled and next(self.activeBindings) ~= nil

	if isActivated == self.isActivated then
		return
	end

	if isActivated and not self.isActivated then
		self.isActivated = true
		self._events.Activated:Fire()
	elseif not isActivated and self.isActivated then
		self.isActivated = false
		self._events.Deactivated:Fire()
	end
end

return InputAction
