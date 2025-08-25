--!strict
local InputContext = {}
InputContext.__index = InputContext

--[[ Config ]]
local ERRORS = {
	ACTION_EXISTS = "Action '%s' already exists in context",
	ACTION_MISSING = "Action '%s' does not exist in context",
}

--[[ Modules ]]
local InputAction = require(script.Parent.InputAction)
local InputBinding = require(script.Parent.InputBinding)

--[[ Types ]]
export type InputAction = InputAction.InputAction
export type InputBinding = InputBinding.InputBinding
export type InputBindingType = InputBinding.InputBindingType
export type InputBindingKey = InputBinding.InputBindingKey
export type InputBindingConfig = {
	bindingType: InputBindingType,
	bindingKey: InputBindingKey,
}
export type InputContext = typeof(setmetatable(
	{} :: {
		priority: number,
		actions: { [string]: InputAction },

		isEnabled: boolean,

		Destroying: RBXScriptSignal,
		ActionAdded: RBXScriptSignal,
		ActionRemoved: RBXScriptSignal,
		EnabledChanged: RBXScriptSignal,
		PriorityChanged: RBXScriptSignal,

		_connections: { [string]: RBXScriptConnection },
		_events: {
			Destroying: BindableEvent,
			ActionAdded: BindableEvent,
			ActionRemoved: BindableEvent,
			EnabledChanged: BindableEvent,
			PriorityChanged: BindableEvent,
		},
	},
	InputContext
))

--[[ Public API ]]
--// Basic constructor
function InputContext.new(priority: number?, actions: { [string]: InputAction }?): InputContext
	local self = setmetatable({}, InputContext) :: InputContext

	self.priority = priority or 0
	self.isEnabled = false

	self.actions = actions or {}

	self._connections = {}
	self._events = {
		Destroying = Instance.new("BindableEvent"),
		ActionAdded = Instance.new("BindableEvent"),
		ActionRemoved = Instance.new("BindableEvent"),
		EnabledChanged = Instance.new("BindableEvent"),
		PriorityChanged = Instance.new("BindableEvent"),
	}

	for name, event: BindableEvent in pairs(self._events) do
		(self :: any)[name] = event.Event
	end

	--// Init
	self:Enable()

	return self
end

function InputContext:Enable()
	if self.isEnabled then
		return
	end

	self.isEnabled = true
	self._events.EnabledChanged:Fire(self.isEnabled)
end

function InputContext:Disable()
	if not self.isEnabled then
		return
	end

	self.isEnabled = false
	self:ReleaseAll()
	self._events.EnabledChanged:Fire(self.isEnabled)
end

function InputContext:Toggle(active: boolean?)
	local shouldEnabled = active ~= nil and active or not self.isEnabled
	if shouldEnabled then
		self:Enable()
	else
		self:Disable()
	end
end

function InputContext:Destroy(destroyActions: boolean?)
	self._events.Destroying:Fire()
	self:Disable()

	for _, event in pairs(self._events) do
		event:Destroy()
	end

	if destroyActions ~= false then
		for _, action in pairs(self.actions) do
			action:Destroy()
		end
	end

	table.clear(self)
	setmetatable(self, nil)
end

--// Action management
function InputContext:DisableAllActions()
	for _, action in pairs(self.actions) do
		action:Disable()
	end
end

function InputContext:ReleaseAll()
	for _, action in pairs(self.actions) do
		action:ReleaseAll()
	end
end

--// Priority management
function InputContext:SetPriority(priority: number)
	if self.priority == priority then
		return
	end

	self.priority = priority
	self._events.PriorityChanged:Fire(priority)
end

--// Action management
function InputContext:AddAction(name: string, bindingConfigs: { [string]: InputBindingConfig }): InputAction
	if self.actions[name] then
		warn(string.format(ERRORS.ACTION_EXISTS, name))
		return self.actions[name]
	end

	local action = InputAction.new()
	action:AddBindings(bindingConfigs)

	self.actions[name] = action
	self._events.ActionAdded:Fire(name, action)

	return action
end

function InputContext:AddActions(actionConfigs: {
	[string]: {
		[string]: InputBindingConfig,
	},
}): { [string]: InputAction }
	local results: { [string]: InputAction } = {}
	for name, actionConfig in pairs(actionConfigs) do
		results[name] = self:AddAction(name, actionConfig)
	end
	return results
end

function InputContext:RemoveAction(name: string): InputAction?
	local action = self.actions[name]
	if not action then
		warn(string.format(ERRORS.ACTION_MISSING, name))
		return
	end

	self.actions[name] = nil
	self._events.ActionRemoved:Fire(name, action)

	return action
end

function InputContext:GetAction(name: string): InputAction?
	return self.actions[name]
end

function InputContext:RequireAction(name: string): InputAction
	local action = self.actions[name]
	if not action then
		error(string.format(ERRORS.ACTION_MISSING, name), 2)
	end

	return action
end

return InputContext
