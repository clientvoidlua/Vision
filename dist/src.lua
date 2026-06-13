local Vision = {}

Vision.config = {
    Player = true,
    LoadAssets = true,
}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local ActiveESPs = {}
local HeartbeatConnection = nil
local MasterStorageGui = nil

local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local SCALE_FACTOR = isMobile and 1.3 or 1.0 
local renderThrottleModulo = 1
local frameCounter = 0
local lastFpsCheck = os.clock()

local safeGetHui = (gethui or function() 
    return LocalPlayer:WaitForChild("PlayerGui", 10) 
end)
local safeCloneRef = (cloneref or function(obj) 
    return obj 
end)

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
        obj.Parent = safeCloneRef(parent)
    end
    return safeCloneRef(obj)
end

local function purgeDuplicates(player)
    if ActiveESPs[player] then
        if ActiveESPs[player].Container then
            pcall(function() ActiveESPs[player].Container:Destroy() end)
        end
        ActiveESPs[player] = nil
    end

    local storage = MasterStorageGui
    if storage then
        for _, child in ipairs(storage:GetChildren()) do
            if child:GetAttribute("TargetPlayer") == player.UserId then
                pcall(function() child:Destroy() end)
            end
        end
    end
end

local function getMasterStorage()
    if MasterStorageGui and MasterStorageGui.Parent then
        return MasterStorageGui
    end
    
    local targetParent = safeGetHui()
    if not targetParent then return nil end
    
    for _, child in ipairs(targetParent:GetChildren()) do
        if child:GetAttribute("VisionStorage") == true then
            MasterStorageGui = safeCloneRef(child)
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
    
    local fallbackPart = character:FindFirstChildWhichIsA("BasePart", true)
    return fallbackPart
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

local function createESP(player)
    if player == LocalPlayer then return end
    purgeDuplicates(player)

    local storage = getMasterStorage()
    if not storage then return end

    local container = createStealthInstance("Folder", storage)
    container:SetAttribute("TargetPlayer", player.UserId)

    local billboard = createStealthInstance("BillboardGui", container)
    billboard.AlwaysOnTop = true
    billboard.ResetOnSpawn = false
    billboard.Size = UDim2.new(0, 200 * SCALE_FACTOR, 0, 100 * SCALE_FACTOR)
    billboard.ExtentsOffset = Vector3.new(0, 3.5, 0)

    local layout = createStealthInstance("UIListLayout", billboard)
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 2)

    local function createLabel(order, color)
        local label = createStealthInstance("TextLabel", billboard)
        label.Size = UDim2.new(1, 0, 0, 14 * SCALE_FACTOR)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.GothamSSm
        label.TextSize = 13 * SCALE_FACTOR
        label.TextColor3 = color
        label.TextStrokeTransparency = 0.4
        label.TextStrokeColor3 = Color3.new(0, 0, 0)
        label.LayoutOrder = order
        return label
    end

    local usernameLabel = createLabel(1, Color3.fromRGB(240, 240, 240))
    local displayNameLabel = createLabel(2, Color3.fromRGB(180, 180, 180))
    local healthLabel = createLabel(3, Color3.fromRGB(0, 255, 120))
    local distanceLabel = createLabel(4, Color3.fromRGB(200, 200, 200))

    ActiveESPs[player] = {
        Container = container,
        Billboard = billboard,
        Username = usernameLabel,
        DisplayName = displayNameLabel,
        Health = healthLabel,
        Distance = distanceLabel,
        Connections = {}
    }

    local charAdded = player.CharacterAdded:Connect(function()
        task.wait(0.1)
        if ActiveESPs[player] then ActiveESPs[player].Container.Enabled = true end
    end)
    
    local charRemoving = player.CharacterRemoving:Connect(function()
        if ActiveESPs[player] then
            ActiveESPs[player].Billboard.Adornee = nil
            ActiveESPs[player].Container.Enabled = false
        end
    end)

    table.insert(ActiveESPs[player].Connections, charAdded)
    table.insert(ActiveESPs[player].Connections, charRemoving)
end

local function removeESP(player)
    purgeDuplicates(player)
end

local function updateESP(deltaTime)
    if not Vision.config.Player then return end
    
    frameCounter = frameCounter + 1
    if frameCounter % renderThrottleModulo ~= 0 then return end
    
    local currentCheckTime = os.clock()
    local timePassed = currentCheckTime - lastFpsCheck
    if timePassed >= 0.5 then
        local currentFps = 1 / deltaTime
        
        if currentFps < 45 then
            renderThrottleModulo = math.min(4, renderThrottleModulo + 1)
        elseif currentFps > 55 then
            renderThrottleModulo = math.max(1, renderThrottleModulo - 1)
        end
        lastFpsCheck = currentCheckTime
    end
    
    local localCharacter = LocalPlayer.Character
    local localTargetPart = locateValidTargetPart(localCharacter)

    for player, esp in pairs(ActiveESPs) do
        local character = player.Character
        local targetPart = locateValidTargetPart(character)
        
        if targetPart then
            if esp.Billboard.Adornee ~= targetPart then
                esp.Billboard.Adornee = targetPart
            end
            
            local distance = 0
            if localTargetPart then
                distance = math.floor((localTargetPart.Position - targetPart.Position).Magnitude)
            end

            local currentHealth, maxHealth = getUniversalHealth(character)
            
            esp.Username.Text = "@" .. player.Name
            esp.DisplayName.Text = "[" .. player.DisplayName .. "]"
            esp.Health.Text = currentHealth .. " HP"
            esp.Distance.Text = distance .. "m"

            if currentHealth > 0 then
                local healthPercent = currentHealth / maxHealth
                esp.Health.TextColor3 = Color3.fromHSV(healthPercent * 0.35, 1, 1)
            else
                esp.Health.TextColor3 = Color3.fromRGB(255, 30, 70)
            end
            
            esp.Container.Enabled = true
        else
            esp.Container.Enabled = false
            if character then
                task.spawn(function()
                    local retryPart = locateValidTargetPart(character)
                    if retryPart then
                        esp.Billboard.Adornee = retryPart
                        esp.Container.Enabled = true
                    end
                end)
            end
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
    
    Players.PlayerAdded:Connect(createESP)
    Players.PlayerRemoving:Connect(removeESP)

    if HeartbeatConnection then HeartbeatConnection:Disconnect() end
    HeartbeatConnection = RunService.Heartbeat:Connect(updateESP)
end

return Vision
