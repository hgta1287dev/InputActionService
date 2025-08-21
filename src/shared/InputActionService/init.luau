--!strict
local InputActionService = {}
InputActionService.__index = InputActionService

--[[ Config ]]
local BUTTON_EVENTSTATE = {
	LEAVE = "Leave",
	DOWN = "Down",
	UP = "Up",
}
local ERRORS = {
	ACTION_EXISTS = "Action '%s' already exists",
	ACTION_MISSING = "Action '%s' does not exist",
	CONTEXT_EXISTS = "Context '%s' already exists",
	CONTEXT_MISSING = "Context '%s' does not exist",
}

--[[ Services ]]
local UIS = game:GetService("UserInputService")

--[[ Modules ]]
local InputAction = require(script.InputAction)
local InputContext = require(script.InputContext)
local InputBinding = require(script.InputBinding)

--[[ Types ]]
export type InputAction = InputAction.InputAction
export type InputContext = InputContext.InputContext
export type InputBinding = InputBinding.InputBinding

export type InputActionService = {
	contexts: { [string]: InputContext },
	stackContexts: { string },
	buttonBindings: { [string]: InputBinding },

	isEnabled: boolean,

	Destroying: RBXScriptSignal,
	EnabledChanged: RBXScriptSignal,

	ActionAdded: RBXScriptSignal,
	ActionRemoved: RBXScriptSignal,

	ContextAdded: RBXScriptSignal,
	ContextRemoved: RBXScriptSignal,

	_connections: { [string]: RBXScriptConnection },
	_events: {
		Destroying: BindableEvent,
		EnabledChanged: BindableEvent,

		ActionAdded: BindableEvent,
		ActionRemoved: BindableEvent,

		ContextAdded: BindableEvent,
		ContextRemoved: BindableEvent,
	},
} & typeof(setmetatable({} :: InputActionService, InputActionService))

--[[ Public API ]]
--//Basic constructor
function InputActionService.new(): InputActionService
	local self = setmetatable({} :: InputActionService, InputActionService)

	self.contexts = {}
	self.stackContexts = {}
	self.buttonBindings = {}

	self.isEnabled = false

	self._connections = {}
	self._events = {
		EnabledChanged = Instance.new("BindableEvent"),
		Destroying = Instance.new("BindableEvent"),
		ActionAdded = Instance.new("BindableEvent"),
		ActionRemoved = Instance.new("BindableEvent"),
		ContextAdded = Instance.new("BindableEvent"),
		ContextRemoved = Instance.new("BindableEvent"),
	}

	for name, event: BindableEvent in pairs(self._events) do
		(self :: any)[name] = event.Event
	end

	--// Init
	self:Enable()

	return self
end

function InputActionService:Enable()
	if self.isEnabled then
		return
	end

	self.isEnabled = true
	self:_setup()
	self._events.EnabledChanged:Fire(self.isEnabled)
end

function InputActionService:Disable()
	if not self.isEnabled then
		return
	end

	self.isEnabled = false

	for _, context in pairs(self.contexts) do
		context:Disable()
	end

	self:_cleanup()
	self._events.EnabledChanged:Fire(self.isEnabled)
end

function InputActionService:Destroy()
	self._events.Destroying:Fire()
	self:Disable()

	for _, event in pairs(self._events) do
		event:Destroy()
	end

	table.clear(self)
	setmetatable(self, nil)
end

--[[ Context Management ]]
function InputActionService:AddContext(name: string): InputContext
	if self.contexts[name] then
		warn(string.format(ERRORS.CONTEXT_EXISTS, name))
		return self.contexts[name]
	end

	local context = InputContext.new()
	self.contexts[name] = context

	table.insert(self.stackContexts, name)
	self:_updateStackContexts()

	self._events.ContextAdded:Fire(context)

	return context
end

function InputActionService:AddContexts(contexts: { string }): { [string]: InputContext }
	local result: { [string]: InputContext } = {}
	for name, context in pairs(contexts) do
		result[name] = self:AddContext(name, context)
	end
	return result
end

function InputActionService:RemoveContext(name: string)
	if not self.contexts[name] then
		warn(string.format(ERRORS.CONTEXT_MISSING, name))
	end

	self.contexts[name] = nil

	local index = table.find(self.stackContexts, name)
	if index then
		table.remove(self.stackContexts, index)
	end
	self:_updateStackContexts()

	self._events.ContextRemoved:Fire(name)
end

function InputActionService:RemoveContexts(names: { string })
	for _, name in pairs(names) do
		self:RemoveContext(name)
	end
end

function InputActionService:GetContext(name: string): InputContext?
	return self.contexts[name]
end

function InputActionService:RequireContext(name: string): InputContext
	local context = self.contexts[name]
	if not context then
		error(string.format(ERRORS.CONTEXT_MISSING, name), 2)
	end

	return context
end

--//Stack Management
function InputActionService:PushContext(name: string)
	if not self.contexts[name] then
		warn(string.format(ERRORS.CONTEXT_MISSING, name))
	end

	if table.find(self.stackContexts, name) then
		return
	end

	table.insert(self.stackContexts, name)
	self:_updateStackContexts()
end

function InputActionService:PopContext(name: string)
	if not self.contexts[name] then
		warn(string.format(ERRORS.CONTEXT_MISSING, name))
	end

	local index = table.find(self.stackContexts, name)
	if not index then
		return
	end

	table.remove(self.stackContexts, index)
	self:_updateStackContexts()
end

function InputActionService:ClearStack()
	self.stackContexts = {}
	self:_updateStackContexts()
end

function InputActionService:GetStack(): { string }
	return self.stackContexts
end

--[[ Private Methods ]]
function InputActionService:_updateStackContexts()
	table.sort(self.stackContexts, function(a, b)
		return self.contexts[a].priority < self.contexts[b].priority
	end)
end

function InputActionService:_cleanupUISConnections()
	if not self._connections.InputBegan then
		return
	end

	self._connections.InputBegan:Disconnect()
	self._connections.InputBegan = nil

	self._connections.InputEnded:Disconnect()
	self._connections.InputEnded = nil
end

function InputActionService:_cleanup()
	for _, connection in pairs(self._connections) do
		connection:Disconnect()
	end
	self._connections = {}

	for _, context in pairs(self.contexts) do
		context:Disable()
	end
end

function InputActionService:_setup()
	self:_setupUISConnections()

	for _, button in pairs(self.buttonBindings) do
		self:_setupButtonConnection(button)
	end
end

function InputActionService:_setupButtonConnection(button: GuiButton)
	if self._connections[button.Name .. BUTTON_EVENTSTATE.DOWN] then
		return
	end

	self._connections[button.Name .. BUTTON_EVENTSTATE.DOWN] = button.MouseButton1Down:Connect(function()
		for _, contextName in pairs(self.stackContexts) do
			local context = self.contexts[contextName]
			if not context.isEnabled then
				continue
			end
			local activated = false
			for _, action in pairs(context.actions) do
				if not activated and action:IsMatchingButton(button) then
					activated = true
				end
				action:PressButton(button)
			end
		end
	end)

	self._connections[button.Name .. BUTTON_EVENTSTATE.UP] = button.MouseButton1Up:Connect(function()
		for _, contextName in pairs(self.stackContexts) do
			local context = self.contexts[contextName]
			if not context.isEnabled then
				continue
			end
			for _, action in pairs(context.actions) do
				action:ReleaseButton(button)
			end
		end
	end)

	self._connections[button.Name .. BUTTON_EVENTSTATE.LEAVE] = button.MouseLeave:Connect(function()
		for _, contextName in pairs(self.stackContexts) do
			local context = self.contexts[contextName]
			if not context.isEnabled then
				continue
			end
			for _, action in pairs(context.actions) do
				action:ReleaseButton(button)
			end
		end
	end)
end

function InputActionService:_setupUISConnections()
	if self._connections.InputBegan then
		return
	end

	self._connections.InputBegan = UIS.InputBegan:Connect(function(input, gpe)
		if not self.isEnabled or gpe then
			return
		end

		for _, contextName in ipairs(self.stackContexts) do
			local context = self.contexts[contextName]
			if not context.isEnabled then
				continue
			end

			local activated = false
			for _, action in pairs(context.actions) do
				if not activated and action:IsMatchingInput(input) then
					activated = true
				end
				action:PressInput(input)
			end
			if activated then
				return
			end
		end
	end)

	self._connections.InputEnded = UIS.InputEnded:Connect(function(input)
		if not self.isEnabled then
			return
		end

		for _, contextName in ipairs(self.stackContexts) do
			local context = self.contexts[contextName]
			if not context.isEnabled then
				continue
			end

			for _, action in pairs(context.actions) do
				action:ReleaseInput(input)
			end
		end
	end)
end

return InputActionService.new()
