--!strict
local InputBinding = {}
InputBinding.__index = InputBinding

--[[ Config ]]
local ERRORS = {
	INVALID_KEY = "Invalid key for binding type '%s': %s",
}

--[[ Types ]]
export type InputBindingType = "Keyboard" | "Mouse" | "Gamepad" | "Button"
export type InputBindingKey = Enum.KeyCode | Enum.UserInputType | GuiButton
export type InputBinding = typeof(setmetatable(
	{} :: {
		type: InputBindingType,
		key: InputBindingKey,

		isEnabled: boolean,

		KeyChanged: RBXScriptSignal,
		Destroying: RBXScriptSignal,
		EnabledChanged: RBXScriptSignal,

		_events: {
			KeyChanged: BindableEvent,
			Destroying: BindableEvent,
			EnabledChanged: BindableEvent,
		},
	},
	InputBinding
))

--[[ Helpers ]]
local function isValidKey(bindingType: InputBindingType, bindingKey: InputBindingKey): boolean
	if bindingType == "Button" then
		return typeof(bindingKey) == "Instance" and bindingKey:IsA("GuiButton")
	else
		if typeof(bindingKey) ~= "EnumItem" then
			return false
		end

		if bindingKey.EnumType == Enum.KeyCode then
			return bindingType == "Keyboard" or bindingType == "Gamepad"
		elseif bindingKey.EnumType == Enum.UserInputType then
			return bindingType == "Mouse"
				and (
					bindingKey == Enum.UserInputType.MouseButton1
					or bindingKey == Enum.UserInputType.MouseButton2
					or bindingKey == Enum.UserInputType.MouseButton3
				)
		end
	end

	return false
end

--[[ Pulic API ]]
function InputBinding.new(bindingType: InputBindingType, bindingKey: InputBindingKey): InputBinding
	if not isValidKey(bindingType, bindingKey) then
		error(string.format(ERRORS.INVALID_KEY, bindingType, tostring(bindingKey)))
	end

	local self = setmetatable({}, InputBinding) :: InputBinding
	self.isEnabled = false
	self.type = bindingType
	self.key = bindingKey

	self._events = {
		KeyChanged = Instance.new("BindableEvent"),
		Destroying = Instance.new("BindableEvent"),
		EnabledChanged = Instance.new("BindableEvent"),
	}

	for name, event: BindableEvent in pairs(self._events) do
		(self :: any)[name] = event.Event
	end

	--// Init
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
	self._events.EnabledChanged:Fire(self.isEnabled)
end

function InputBinding:Disable()
	if not self.isEnabled then
		return
	end

	self.isEnabled = false
	self._events.EnabledChanged:Fire(self.isEnabled)
end

function InputBinding:Destroy()
	self._events.Destroying:Fire()

	for _, event in pairs(self._events) do
		event:Destroy()
	end

	table.clear(self)
	setmetatable(self, nil)
end

function InputBinding:ChangeKey(newType: InputBindingType, newKey: InputBindingKey)
	if self.key == newKey then
		return
	end

	if not isValidKey(newType, newKey) then
		error(string.format(ERRORS.INVALID_KEY, newType, tostring(newKey)))
	end

	self.type = newType
	self.key = newKey
	self._events.KeyChanged:Fire(newKey)
end

function InputBinding:IsMatchingButton(button: GuiButton): boolean
	if self.isEnabled == false then
		return false
	end
	if self.type ~= "Button" then
		return false
	end

	return (self.key :: Instance) == button
end

function InputBinding:IsMatchingInput(input: InputObject): boolean
	if self.isEnabled == false then
		return false
	end
	return (self.type == "Keyboard" and input.KeyCode == self.key)
		or (self.type == "Gamepad" and input.KeyCode == self.key)
		or (self.type == "Mouse" and input.UserInputType == self.key)
end

return InputBinding
