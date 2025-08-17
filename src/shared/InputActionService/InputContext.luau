--!strict
local InputContext = {}
InputContext.__index = InputContext

--[[ Config ]]
local ERRORS = {
	ACTION_EXISTS = "Action '%s' already exists in context '%s'",
	ACTION_MISSING = "Action '%s' does not exist in context '%s'",
}

--[[ Modules ]]
local InputAction = require(script.Parent.InputAction)

--[[ Types ]]
export type InputAction = InputAction.InputAction
export type InputContext = {
	priority: number,
	actions: { [string]: InputAction },
	ativeActions: { [string]: boolean },

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
} & typeof(InputContext)

--[[ Public API ]]
--// Basic constructor
function InputContext.new(priority: number?): InputContext
	local self = setmetatable({} :: InputContext, InputContext)

	self.priority = priority or 1
	self.isEnabled = false

	self._connections = {}
	self._events = {
		Destroying = Instance.new("BindableEvent"),
		ActionAdded = Instance.new("BindableEvent"),
		ActionRemoved = Instance.new("BindableEvent"),
		EnabledChanged = Instance.new("BindableEvent"),
		PriorityChanged = Instance.new("BindableEvent"),
	}

	for _, event: BindableEvent in pairs(self._events) do
		(self :: any)[event.Name] = event.Event
	end

	return self
end

function InputContext:Enable()
	if self.isEnabled then
		return
	end

	self.isEnabled = true
	self._events.EnabledChanged:Fire(self.isEnabled)
end

function InputContext:Disable(disableActions: boolean?)
	if not self.isEnabled then
		return
	end

	if disableActions ~= false then
		self:DisableAllActions()
	end

	self.isEnabled = false
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
		for _, action: InputAction in pairs(self.actions) do
			action:Destroy()
		end
	end

	table.clear(self)
	setmetatable(self, nil)
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
function InputContext:AddAction(name: string, action: InputAction)
	if self.actions[name] then
		error(string.format(ERRORS.ACTION_EXISTS, name))
	end

	self.actions[name] = action
	self._events.ActionAdded:Fire(name, action)

	return action
end

function InputContext:RemoveAction(name: string)
	local action = self.actions[name]
	if not action then
		error(string.format(ERRORS.ACTION_MISSING, name))
	end

	self.actions[name] = nil
	self._events.ActionRemoved:Fire(name, action)

	return action
end

return InputContext
