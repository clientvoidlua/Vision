local Vision = {}

Vision.config = {
	Player = true,
	LoadAssets = true,
}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local ActiveESPs = {}
local HeartbeatConnection = nil
local PlayerAddedConnection = nil
local PlayerRemovingConnection = nil
local MasterStorageGui = nil

local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local SCALE_FACTOR = isMobile and 1.3 or 1.0

local function generateStealthName()
	local length = math.random(10, 18)
	local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	local result = {}
	for i = 1, length do
		local rand = math.random(1, #chars)
		table.insert(result, string.sub(chars, rand, rand))
	end
	return table.concat(result)
end

local function createStealthInstance(className, parent)
	local obj = Instance.new(className)
	obj.Name = generateStealthName()
	if parent then
		obj.Parent = parent
	end
	return obj
end

local function getMasterStorage()
	if MasterStorageGui and MasterStorageGui.Parent then
		return MasterStorageGui
	end

	local targetParent = (gethui and gethui()) or LocalPlayer:WaitForChild("PlayerGui", 10)
	if not targetParent then return nil end

	for _, child in ipairs(targetParent:GetChildren()) do
		if child:GetAttribute("VisionStorage") == true then
			MasterStorageGui = child
			return MasterStorageGui
		end
	end

	local storage = createStealthInstance("ScreenGui", targetParent)
	storage:SetAttribute("VisionStorage", true)
	if storage:IsA("ScreenGui") then
		storage.ResetOnSpawn = false
		storage.DisplayOrder = 999
	end
	MasterStorageGui = storage
	return storage
end

local function locateValidTargetPart(character)
	if not character then return nil end

	local priorityList = {
		"HumanoidRootPart",
		"Torso",
		"LowerTorso",
		"Head",
		"UpperTorso"
	}

	for _, partName in ipairs(priorityList) do
		local found = character:FindFirstChild(partName)
		if found and found:IsA("BasePart") then
			return found
		end
	end

	if character.PrimaryPart then
		return character.PrimaryPart
	end

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("BasePart") then
			return child
		end
	end

	return nil
end

local function getUniversalHealth(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		return math.max(0, math.floor(humanoid.Health)), math.max(1, math.floor(humanoid.MaxHealth))
	end

	local customHealth = character:GetAttribute("Health") or character:GetAttribute("hp") or character:GetAttribute("HP")
	local customMaxHealth = character:GetAttribute("MaxHealth") or character:GetAttribute("maxHp") or 100

	if type(customHealth) == "number" then
		return math.floor(customHealth), math.floor(customMaxHealth)
	end

	return 100, 100
end

local function purgeDuplicates(player)
	if ActiveESPs[player] then
		if ActiveESPs[player].Billboard then
			pcall(function() ActiveESPs[player].Billboard:Destroy() end)
		end
		ActiveESPs[player] = nil
	end

	local storage = getMasterStorage()
	if storage then
		for _, child in ipairs(storage:GetChildren()) do
			if child:GetAttribute("TargetPlayer") == player.UserId then
				pcall(function() child:Destroy() end)
			end
		end
	end
end

local function createESP(player)
	if player == LocalPlayer then return end
	purgeDuplicates(player)

	local storage = getMasterStorage()
	if not storage then return end

	local billboard = createStealthInstance("BillboardGui", storage)
	billboard:SetAttribute("TargetPlayer", player.UserId)
	billboard.AlwaysOnTop = true
	billboard.ResetOnSpawn = false
	billboard.Size = UDim2.new(0, 500 * SCALE_FACTOR, 0, 20 * SCALE_FACTOR)
	billboard.StudsOffset = Vector3.new(0, 3.5, 0)
	billboard.Enabled = false

	local label = createStealthInstance("TextLabel", billboard)
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamSSm
	label.TextSize = 13 * SCALE_FACTOR
	label.TextColor3 = Color3.fromRGB(240, 240, 240)
	label.TextStrokeTransparency = 0.4
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.Text = ""

	ActiveESPs[player] = {
		Billboard = billboard,
		Label = label,
	}
end

local function removeESP(player)
	purgeDuplicates(player)
end

local function updateESP()
	if not Vision.config.Player then return end

	local localCharacter = LocalPlayer.Character
	local localTargetPart = locateValidTargetPart(localCharacter)

	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then
			pcall(function()
				local esp = ActiveESPs[player]
				local character = player.Character
				local targetPart = locateValidTargetPart(character)

				if targetPart then
					if not esp or not esp.Billboard or esp.Billboard.Parent == nil then
						createESP(player)
						esp = ActiveESPs[player]
					end

					if esp then
						if esp.Billboard.Adornee ~= targetPart then
							esp.Billboard.Adornee = targetPart
						end

						local distance = 0
						if localTargetPart then
							distance = math.floor((localTargetPart.Position - targetPart.Position).Magnitude)
						end

						local currentHealth, maxHealth = getUniversalHealth(character)

						esp.Label.Text = string.format(
							"@%s  |  Display: %s  |  Health: %d  |  Distance: %dm",
							player.Name,
							player.DisplayName,
							currentHealth,
							distance
						)

						if currentHealth > 0 then
							local healthPercent = currentHealth / maxHealth
							esp.Label.TextColor3 = Color3.fromHSV(healthPercent * 0.35, 1, 1)
						else
							esp.Label.TextColor3 = Color3.fromRGB(255, 30, 70)
						end

						esp.Billboard.Enabled = true
					end
				else
					if esp then
						esp.Billboard.Enabled = false
						esp.Billboard.Adornee = nil
					end
				end
			end)
		end
	end

	for player, _ in pairs(ActiveESPs) do
		if not player.Parent or not Players:FindFirstChild(player.Name) then
			removeESP(player)
		end
	end
end

function Vision:Run()
	if Vision.config.LoadAssets then
		task.wait(0.2)
	end

	for _, player in ipairs(Players:GetPlayers()) do
		createESP(player)
	end

	if PlayerAddedConnection then PlayerAddedConnection:Disconnect() end
	if PlayerRemovingConnection then PlayerRemovingConnection:Disconnect() end
	PlayerAddedConnection = Players.PlayerAdded:Connect(createESP)
	PlayerRemovingConnection = Players.PlayerRemoving:Connect(removeESP)

	if HeartbeatConnection then HeartbeatConnection:Disconnect() end
	HeartbeatConnection = RunService.Heartbeat:Connect(updateESP)
end

return Vision
