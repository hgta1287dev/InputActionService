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
local InputActionModule = require(script.InputAction)
local InputContextModule = require(script.InputContext)
local InputBindingModule = require(script.InputBinding)

--[[ Types ]]
export type InputAction = InputActionModule.InputAction
export type InputContext = InputContextModule.InputContext
export type InputBinding = InputBindingModule.InputBinding

type InputBindingType = InputBindingModule.InputBindingType
type InputBindingKey = InputBindingModule.InputBindingKey
type InputContextConfig = InputContextModule.InputContextConfig

export type InputActionService = typeof(setmetatable(
	{} :: {
		contexts: { [string]: InputContext },
		stackContexts: { string },
		buttons: { GuiButton },

		isEnabled: boolean,

		Destroying: RBXScriptSignal,
		EnabledChanged: RBXScriptSignal,
		ContextAdded: RBXScriptSignal,
		ContextRemoved: RBXScriptSignal,

		_connections: { [string]: RBXScriptConnection },
		_permanentConnections: { [string]: RBXScriptConnection },
		_events: {
			Destroying: BindableEvent,
			EnabledChanged: BindableEvent,
			ContextAdded: BindableEvent,
			ContextRemoved: BindableEvent,
		},
	},
	InputActionService
))

--[[ Public API ]]
--//Basic constructor
function InputActionService.new(): InputActionService
	local self: InputActionService = setmetatable({}, InputActionService) :: InputActionService

	self.contexts = {}
	self.stackContexts = {}
	self.buttons = {}

	self.isEnabled = false

	self._permanentConnections = {}
	self._connections = {}
	self._events = {
		EnabledChanged = Instance.new("BindableEvent"),
		Destroying = Instance.new("BindableEvent"),
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

	for _, conn in pairs(self._permanentConnections) do
		conn:Disconnect()
	end

	for _, event in pairs(self._events) do
		event:Destroy()
	end

	table.clear(self)
	setmetatable(self, nil)
end

--[[ Context Management ]]
function InputActionService:AddContext(name: string, config: InputContextConfig?): InputContext
	if self.contexts[name] then
		warn(string.format(ERRORS.CONTEXT_EXISTS, name))
		return self.contexts[name] :: InputContext
	end

	local context: InputContext = InputContextModule.new(config)
	self.contexts[name] = context

	self._events.ContextAdded:Fire(name, context)

	return context
end

function InputActionService:AddContexts(configs: {
	[string]: { priority: number? },
}): { [string]: InputContext }
	local result: { [string]: InputContext } = {}
	for name, config in pairs(configs) do
		result[name] = self:AddContext(name, config.priority)
	end
	return result
end

function InputActionService:RemoveContext(name: string)
	local context = self.contexts[name]
	if not context then
		warn(string.format(ERRORS.CONTEXT_MISSING, name))
		return
	end

	self.contexts[name] = nil

	local index = table.find(self.stackContexts, name)
	if index then
		table.remove(self.stackContexts, index)
	end

	self._events.ContextRemoved:Fire(name, context)
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

	local index = table.find(self.stackContexts, name)
	if index then
		table.remove(self.stackContexts, index)
	end

	table.insert(self.stackContexts, name)
end

function InputActionService:PopContext()
	table.remove(self.stackContexts)
end

function InputActionService:GetStack(): { string }
	return self.stackContexts
end

--//Input Button Management
function InputActionService:RegisterButton(button: GuiButton)
	if table.find(self.buttons, button) then
		return
	end
	table.insert(self.buttons, button)
	if self.isEnabled then
		self:_setupButtonConnection(button)
	end
end

function InputActionService:UnregisterButton(button: GuiButton)
	local index = table.find(self.buttons, button)
	if not index then
		return
	end

	self:_cleanupButtonConnection(button)
	table.remove(self.buttons, index)
end

--[[ Private Methods ]]
function InputActionService:_getContextsByPriority(): { string }
	local sortedStack = table.clone(self.stackContexts)
	table.sort(sortedStack, function(a, b)
		local contextA = self.contexts[a] :: InputContext?
		local contextB = self.contexts[b] :: InputContext?

		if not contextA or not contextB then
			return false
		end

		return contextA.priority > contextB.priority
	end)
	return sortedStack
end

function InputActionService:_cleanupUISConnections()
	if self._connections.InputBegan then
		self._connections.InputBegan:Disconnect()
	end

	if self._connections.InputEnded then
		self._connections.InputEnded:Disconnect()
	end
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

	for _, button in pairs(self.buttons) do
		self:_setupButtonConnection(button :: GuiButton)
	end
end

function InputActionService:_cleanupButtonConnection(button: GuiButton)
	if self._connections[button.Name .. BUTTON_EVENTSTATE.DOWN] then
		self._connections[button.Name .. BUTTON_EVENTSTATE.DOWN]:Disconnect()
		self._connections[button.Name .. BUTTON_EVENTSTATE.DOWN] = nil
	end

	if self._connections[button.Name .. BUTTON_EVENTSTATE.UP] then
		self._connections[button.Name .. BUTTON_EVENTSTATE.UP]:Disconnect()
		self._connections[button.Name .. BUTTON_EVENTSTATE.UP] = nil
	end

	if self._connections[button.Name .. BUTTON_EVENTSTATE.LEAVE] then
		self._connections[button.Name .. BUTTON_EVENTSTATE.LEAVE]:Disconnect()
		self._connections[button.Name .. BUTTON_EVENTSTATE.LEAVE] = nil
	end
end

function InputActionService:_setupButtonConnection(button: GuiButton)
	if self._connections[button.Name .. BUTTON_EVENTSTATE.DOWN] then
		return
	end

	self._connections[button.Name .. BUTTON_EVENTSTATE.DOWN] = button.MouseButton1Down:Connect(function()
		for _, contextName in ipairs(self:_getContextsByPriority()) do
			local context = self.contexts[contextName]
			if not context.isEnabled then
				continue
			end
			local shouldSink
			for _, action: any in pairs(context.actions) do
				if action:IsMatchingButton(button) and context.sink then
					shouldSink = true
				end
				action:PressButton(button)
			end
			if shouldSink then
				return
			end
		end
	end)

	self._connections[button.Name .. BUTTON_EVENTSTATE.UP] = button.MouseButton1Up:Connect(function()
		for _, contextName in pairs(self.stackContexts) do
			local context = self.contexts[contextName]
			if not context.isEnabled then
				continue
			end
			for _, action: any in pairs(context.actions) do
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
			for _, action: any in pairs(context.actions) do
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

			local shouldSink = false
			for _, action: any in pairs(context.actions) do
				if action:IsMatchingInput(input) and context.sink then
					shouldSink = true
				end
				action:PressInput(input)
			end
			if shouldSink then
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

			for _, action: any in pairs(context.actions) do
				action:ReleaseInput(input)
			end
		end
	end)
end

return InputActionService
