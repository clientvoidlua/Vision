local Vision = {}

Vision.config = {
    Player = true,
    Object = true,
    Entity = true,
    LoadAssets = true,
}

local Players        = game:GetService("Players")
local RunService     = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer    = Players.LocalPlayer
local ActiveESPs     = {}
local HeartbeatConnection = nil
local MasterStorageGui    = nil

local isMobile            = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local SCALE_FACTOR        = isMobile and 1.3 or 1.0
local renderThrottleModulo = 1
local frameCounter        = 0
local lastFpsCheck        = os.clock()

local safeGetHui   = (gethui or function() return LocalPlayer:WaitForChild("PlayerGui", 10) end)
local safeCloneRef = (cloneref or function(obj) return obj end)

local function generateStealthName()
    local chars  = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local result = {}
    for i = 1, math.random(10, 18) do
        result[i] = string.sub(chars, math.random(1, #chars), math.random(1, #chars))
    end
    return table.concat(result)
end

local function createStealthInstance(className, parent)
    local obj  = Instance.new(className)
    obj.Name   = generateStealthName()
    if parent then obj.Parent = safeCloneRef(parent) end
    return safeCloneRef(obj)
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

    local storage            = createStealthInstance("ScreenGui", targetParent)
    storage.ResetOnSpawn     = false
    storage.DisplayOrder     = 999
    storage:SetAttribute("VisionStorage", true)
    MasterStorageGui = storage
    return storage
end

local function purgeDuplicates(player)
    if ActiveESPs[player] then
        for _, conn in ipairs(ActiveESPs[player].Connections or {}) do
            pcall(function() conn:Disconnect() end)
        end
        pcall(function() ActiveESPs[player].Billboard:Destroy() end)
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

local function createESP(player)
    if player == LocalPlayer then return end
    purgeDuplicates(player)

    local storage = getMasterStorage()
    if not storage then return end

    local billboard = createStealthInstance("BillboardGui", storage)
    billboard:SetAttribute("TargetPlayer", player.UserId)
    billboard.AlwaysOnTop    = true
    billboard.ResetOnSpawn   = false
    billboard.Enabled        = false
    billboard.Size           = UDim2.new(0, 420 * SCALE_FACTOR, 0, 22 * SCALE_FACTOR)
    billboard.StudsOffset    = Vector3.new(0, 4.5, 0)

    local espLabel = createStealthInstance("TextLabel", billboard)
    espLabel.Size                 = UDim2.new(1, 0, 1, 0)
    espLabel.BackgroundTransparency = 1
    espLabel.Font                 = Enum.Font.GothamSSm
    espLabel.TextSize             = 13 * SCALE_FACTOR
    espLabel.TextColor3           = Color3.fromRGB(240, 240, 240)
    espLabel.TextStrokeTransparency = 0.35
    espLabel.TextStrokeColor3     = Color3.new(0, 0, 0)
    espLabel.RichText             = true   -- enables <font color="…"> tags
    espLabel.TextXAlignment       = Enum.TextXAlignment.Center
    espLabel.TextYAlignment       = Enum.TextYAlignment.Center
    espLabel.Text                 = ""

    local connections = {}

    connections[#connections + 1] = player.CharacterAdded:Connect(function()
        task.wait(0.1)
        if ActiveESPs[player] then
            ActiveESPs[player].Billboard.Enabled = true
        end
    end)

    connections[#connections + 1] = player.CharacterRemoving:Connect(function()
        if ActiveESPs[player] then
            ActiveESPs[player].Billboard.Adornee = nil
            ActiveESPs[player].Billboard.Enabled = false
        end
    end)

    ActiveESPs[player] = {
        Billboard   = billboard,
        Label       = espLabel,
        Connections = connections,
    }
end

local function removeESP(player)
    purgeDuplicates(player)
end

local function locateValidTargetPart(character)
    if not character then return nil end
    for _, name in ipairs({ "HumanoidRootPart", "Torso", "LowerTorso", "Head", "UpperTorso" }) do
        local part = character:FindFirstChild(name)
        if part and part:IsA("BasePart") then return part end
    end
    return character.PrimaryPart or character:FindFirstChildWhichIsA("BasePart", true)
end

local function getUniversalHealth(character)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        return math.max(0, math.floor(humanoid.Health)),
               math.max(1, math.floor(humanoid.MaxHealth))
    end
    local hp    = character:GetAttribute("Health") or character:GetAttribute("hp") or character:GetAttribute("HP")
    local maxHp = character:GetAttribute("MaxHealth") or character:GetAttribute("maxHp") or 100
    if type(hp) == "number" then
        return math.floor(hp), math.floor(maxHp)
    end
    return 100, 100
end

local function healthColor(pct)
    if pct > 0.6 then
        return "rgb(0,220,80)"
    elseif pct > 0.3 then
        return "rgb(255,210,0)"
    else
        return "rgb(255,60,60)"
    end
end

local function updateESP(deltaTime)
    if not Vision.config.Player then return end

    frameCounter = frameCounter + 1
    if frameCounter % renderThrottleModulo ~= 0 then return end

    local now = os.clock()
    if now - lastFpsCheck >= 0.5 then
        local fps = 1 / math.max(deltaTime, 0.0001)
        if fps < 45 then
            renderThrottleModulo = math.min(4, renderThrottleModulo + 1)
        elseif fps > 55 then
            renderThrottleModulo = math.max(1, renderThrottleModulo - 1)
        end
        lastFpsCheck = now
    end

    local localRoot = locateValidTargetPart(LocalPlayer.Character)

    for player, esp in pairs(ActiveESPs) do
        local targetPart = locateValidTargetPart(player.Character)

        if targetPart then
            if esp.Billboard.Adornee ~= targetPart then
                esp.Billboard.Adornee = targetPart
            end

            local distance = localRoot
                and math.floor((localRoot.Position - targetPart.Position).Magnitude)
                or 0

            local hp, maxHp = getUniversalHealth(player.Character)
            local pct       = maxHp > 0 and (hp / maxHp) or 0
            local color     = healthColor(pct)

            esp.Label.Text = string.format(
                '@%s  |  Display: %s  |  Health: <font color="%s">%d</font>  |  Distance: %dm',
                player.Name,
                player.DisplayName,
                color,
                hp,
                distance
            )

            esp.Billboard.Enabled = true
        else
            esp.Billboard.Adornee = nil
            esp.Billboard.Enabled = false
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
