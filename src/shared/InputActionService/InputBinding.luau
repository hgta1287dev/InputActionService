--!strict
local InputBinding = {}
InputBinding.__index = InputBinding

--[[ Services ]]
local UIS = game:GetService("UserInputService")

--[[ Types ]]
export type InputBindingType = "Keyboard" | "Mouse" | "Gamepad" | "Button"
export type InputBindingKey = Enum.KeyCode | Enum.UserInputType | GuiButton
export type InputBinding = {
	type: InputBindingType,
	key: InputBindingKey,

	isEnabled: boolean,
	isPressed: boolean,

	Pressed: RBXScriptSignal,
	Released: RBXScriptSignal,
	KeyChanged: RBXScriptSignal,
	Destroying: RBXScriptSignal,

	_connections: { [string]: RBXScriptConnection },
	_events: {
		Pressed: BindableEvent,
		Released: BindableEvent,
		KeyChanged: BindableEvent,
		Destroying: BindableEvent,
	},
} & typeof(InputBinding)

--[[ Helpers ]]
local function isValidKey(bindingType: InputBindingType, key: InputBindingKey): boolean
	if bindingType == "Button" then
		return typeof(key) == "Instance" and key:IsA("GuiButton")
	elseif bindingType == "Keyboard" then
		return typeof(key) == "EnumItem" and key.EnumType == Enum.KeyCode
	elseif bindingType == "Gamepad" then
		return typeof(key) == "EnumItem" and key.EnumType == Enum.KeyCode
	elseif bindingType == "Mouse" then
		return typeof(key) == "EnumItem"
			and key.EnumType == Enum.UserInputType
			and (
				key == Enum.UserInputType.MouseButton1
				or key == Enum.UserInputType.MouseButton2
				or key == Enum.UserInputType.MouseMovement
			)
	end

	return false
end

--[[ Pulic API ]]
function InputBinding.new(bindingType: InputBindingType, key: InputBindingKey): InputBinding
	if not isValidKey(bindingType, key) then
		error(string.format("Invalid key for binding type '%s': %s", bindingType, tostring(key)))
	end

	local self = setmetatable({} :: InputBinding, InputBinding)
	self.type = bindingType
	self.key = key

	self.isEnabled = false
	self.isPressed = false

	self._connections = {}
	self._events = {
		Pressed = Instance.new("BindableEvent"),
		Released = Instance.new("BindableEvent"),
		KeyChanged = Instance.new("BindableEvent"),
		Destroying = Instance.new("BindableEvent"),
	}

	for _, event in pairs(self._events) do
		(self :: any)[event.Name] = event.Event
	end

	self:Enable()

	return self
end

function InputBinding:Toggle(active: boolean?)
	local shouldEnabled = active ~= nil and active or not self.isEnabled
	if shouldEnabled then
		self:Enable()
	else
		self:Disable()
	end
end

function InputBinding:Enable()
	if self.isEnabled then
		return
	end

	self.isEnabled = true
	self:_setup()
end

function InputBinding:Disable()
	if not self.isEnabled then
		return
	end

	self.isEnabled = false
	self:cleanup()
end

function InputBinding:Destroy()
	self._events.Destroying:Fire()
	self:Disable()
	for _, event in pairs(self._events) do
		event:Destroy()
	end
	table.clear(self._events)
	setmetatable(self, nil)
end

function InputBinding:ChangeKey(newKey: InputBindingKey)
	if self.key == newKey then
		return
	end

	self.key = newKey
	self._events.KeyChanged:Fire(newKey)

	if self.isEnabled then
		self:cleanup()
		self:_setup()
	end
end

--[[ Private Methods ]]
function InputBinding:cleanup()
	for _, connection in pairs(self._connections) do
		connection:Disconnect()
	end
	self._connections = {}

	self.isEnabled = false
	self.isPressed = false
end

function InputBinding:_setup()
	local bindingType: InputBindingType = self.type
	if bindingType == "Keyboard" or self.type == "Gamepad" then
		self._connections.InputBegan = UIS.InputBegan:Connect(function(input, gpe)
			if not self.isEnabled or gpe or input.UserInputType ~= self.key then
				return
			end

			self.isPressed = true
			self._events.Pressed:Fire()
		end)

		self._connections.InputEnded = UIS.InputEnded:Connect(function(input)
			if input.UserInputType ~= self.key then
				return
			end

			self.isPressed = false
			self._events.Released:Fire()

			return
		end)
	elseif bindingType == "Mouse" then
		self._connections.InputBegan = UIS.InputBegan:Connect(function(input, gpe)
			if not self.isEnabled or gpe or input.UserInputType ~= self.key then
				return
			end

			self.isPressed = true
			self._events.Pressed:Fire()
		end)

		self._connections.InputEnded = UIS.InputEnded:Connect(function(input)
			if input.UserInputType ~= self.key then
				return
			end

			self.isPressed = false
			self._events.Released:Fire()
		end)
	elseif bindingType == "Button" then
		if not self.key or typeof(self.key) ~= "Instance" or not self.key:IsA("GuiButton") then
			error("Mobile input binding requires a GuiButton key")
		end

		local button: GuiButton = self.key
		local pressed = false

		self._connections.MouseButton1Down = button.MouseButton1Down:Connect(function()
			if not self.isEnabled or pressed then
				return
			end

			pressed = true

			self.isPressed = true
			self._events.Pressed:Fire()
		end)

		self._connections.MouseButton1Up = button.MouseButton1Up:Connect(function()
			if not self.isEnabled or not pressed then
				return
			end

			pressed = false

			self.isPressed = false
			self._events.Released:Fire()
		end)

		self._connections.MouseLeave = button.MouseLeave:Connect(function()
			if not self.isEnabled or not pressed then
				return
			end

			pressed = false

			self.isPressed = false
			self._events.Released:Fire()
		end)
	end
end

return InputBinding
