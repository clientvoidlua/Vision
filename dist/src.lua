local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

if _G.VisionESPInstance then
    pcall(function()
        _G.VisionESPInstance:Destroy()
    end)
end

local ESP = {
    Enabled = true,
    Boxes = true,
    Names = true,
    Tracers = true,
    Skeletons = true,
    HealthBars = true,
    TeamMates = true,
    Players = true,
    TeamColor = true,
    FaceCamera = false,
    BoxShift = CFrame.new(0, -1.5, 0),
    BoxSize = Vector3.new(4, 6, 0),
    Color = Color3.fromRGB(255, 170, 0),
    Thickness = 2,
    AttachShift = 1,
    Objects = {},
    Overrides = {},
    Highlighted = nil,
    HighlightColor = Color3.fromRGB(255, 255, 255),
    AutoRemove = true,
    MaxDistance = 1000,
    TargetFPS = 60
}

_G.VisionESPInstance = {
    Destroy = function()
        ESP.Enabled = false
        for _, box in pairs(ESP.Objects) do
            if box.Remove then
                pcall(box.Remove, box)
            end
        end
        table.clear(ESP.Objects)
    end
}

local PlatformMetrics = {
    IsMobile = table.find({Enum.Platform.Android, Enum.Platform.IOS}, UserInputService:GetPlatform()) ~= nil,
    CurrentTier = 3,
    LastFpsCheck = 0
}

if PlatformMetrics.IsMobile then
    ESP.MaxDistance = 400
    ESP.Thickness = 1
end

local function ApplyFontSettings(drawingTextInstance)
    pcall(function()
        drawingTextInstance.Font = 2
    end)
    pcall(function()
        drawingTextInstance.Font = "rbxasset://fonts/families/GothamSSm.json"
    end)
    pcall(function()
        drawingTextInstance.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json")
    end)
end

local function CreateDrawing(objectType, properties)
    local drawingElement = Drawing.new(objectType)
    if properties then
        for propertyName, propertyValue in pairs(properties) do
            if propertyName ~= "Font" and propertyName ~= "FontFace" then
                drawingElement[propertyName] = propertyValue
            end
        end
    end
    if objectType == "Text" then
        ApplyFontSettings(drawingElement)
    end
    return drawingElement
end

local function GetHealthColor(health, maxHealth)
    local percent = math.clamp(health / maxHealth, 0, 1)
    if percent >= 0.75 then
        return Color3.fromRGB(0, 255, 0)
    elseif percent >= 0.35 then
        return Color3.fromRGB(255, 255, 0)
    else
        return Color3.fromRGB(255, 0, 0)
    end
end

local function FindValidPrimaryPart(model)
    if not model then return nil end
    if model:IsA("BasePart") then return model end
    
    local standardParts = {"HumanoidRootPart", "Head", "Torso", "UpperTorso", "LowerTorso"}
    for _, partName in ipairs(standardParts) do
        local found = model:FindFirstChild(partName, true)
        if found and found:IsA("BasePart") then
            return found
        end
    end
    
    local biggestPart = nil
    local maxVolume = 0
    for _, desc in ipairs(model:GetDescendants()) do
        if desc:IsA("BasePart") then
            local volume = desc.Size.X * desc.Size.Y * desc.Size.Z
            if volume > maxVolume then
                maxVolume = volume
                biggestPart = desc
            end
        end
    end
    return biggestPart
end

function ESP:GetTeam(player)
    if self.Overrides.GetTeam then
        return self.Overrides.GetTeam(player)
    end
    return player and player.Team
end

function ESP:IsTeamMate(player)
    if self.Overrides.IsTeamMate then
        return self.Overrides.IsTeamMate(player)
    end
    return self:GetTeam(player) == self:GetTeam(LocalPlayer)
end

function ESP:GetColor(object)
    if self.Overrides.GetColor then
        return self.Overrides.GetColor(object)
    end
    local player = self:GetPlayerFromCharacter(object)
    if player and (self.TeamColor or self.TeamColor == nil) and player.Team then
        return player.Team.TeamColor.Color
    end
    return self.Color
end

function ESP:GetPlayerFromCharacter(character)
    if self.Overrides.GetPlayerFromCharacter then
        return self.Overrides.GetPlayerFromCharacter(character)
    end
    return Players:GetPlayerFromCharacter(character)
end

function ESP:Toggle(state)
    self.Enabled = state
    if not state then
        for _, box in pairs(self.Objects) do
            if box.Components then
                for _, component in pairs(box.Components) do
                    component.Visible = false
                end
            end
            if box.SkeletonLines then
                for _, line in pairs(box.SkeletonLines) do
                    line.Visible = false
                end
            end
        end
    end
end

function ESP:GetBox(object)
    return self.Objects[object]
end

local BoxBase = {}
BoxBase.__index = BoxBase

function BoxBase:Remove()
    ESP.Objects[self.Object] = nil
    if self.Components then
        for index, component in pairs(self.Components) do
            component.Visible = false
            pcall(function() component:Remove() end)
            self.Components[index] = nil
        end
    end
    if self.SkeletonLines then
        for index, line in pairs(self.SkeletonLines) do
            line.Visible = false
            pcall(function() line:Remove() end)
            self.SkeletonLines[index] = nil
        end
    end
end

function BoxBase:Update()
    if not self.PrimaryPart or not self.PrimaryPart.Parent then
        return self:Remove()
    end

    local cameraCFrame = Camera.CFrame
    local distance = (cameraCFrame.Position - self.PrimaryPart.Position).Magnitude

    if distance > ESP.MaxDistance or not ESP.Enabled then
        for _, component in pairs(self.Components) do
            component.Visible = false
        end
        for _, line in pairs(self.SkeletonLines) do
            line.Visible = false
        end
        return
    end

    local humanoid = self.Object:FindFirstChildOfClass("Humanoid")
    local currentHealth = humanoid and humanoid.Health or 100
    local maximumHealth = humanoid and humanoid.MaxHealth or 100
    local dynamicHealthColor = GetHealthColor(currentHealth, maximumHealth)

    local color = ESP.Color
    if ESP.Highlighted == self.Object then
        color = ESP.HighlightColor
    else
        color = self.Color or (self.ColorDynamic and self:ColorDynamic()) or ESP:GetColor(self.Object) or ESP.Color
    end

    local renderAllowed = true
    if ESP.Overrides.UpdateAllow and not ESP.Overrides.UpdateAllow(self) then
        renderAllowed = false
    end
    if self.Player and not (ESP.TeamMates or ESP.TeamMate) and ESP:IsTeamMate(self.Player) then
        renderAllowed = false
    end
    if self.Player and not (ESP.Players or ESP.Player) then
        renderAllowed = false
    end
    if type(self.IsEnabled) == "string" and not ESP[self.IsEnabled] then
        renderAllowed = false
    elseif type(self.IsEnabled) == "function" and not self:IsEnabled() then
        renderAllowed = false
    end
    if not Workspace:IsAncestorOf(self.PrimaryPart) and not self.RenderInNil then
        renderAllowed = false
    end

    if not renderAllowed then
        for _, component in pairs(self.Components) do
            component.Visible = false
        end
        for _, line in pairs(self.SkeletonLines) do
            line.Visible = false
        end
        return
    end

    local targetCFrame = self.PrimaryPart.CFrame
    if ESP.FaceCamera then
        targetCFrame = CFrame.new(targetCFrame.Position, cameraCFrame.Position)
    end

    local size = self.Size
    local shiftedCFrame = targetCFrame * ESP.BoxShift
    
    local locations = {
        TopLeft = shiftedCFrame * CFrame.new(size.X / 2, size.Y / 2, 0),
        TopRight = shiftedCFrame * CFrame.new(-size.X / 2, size.Y / 2, 0),
        BottomLeft = shiftedCFrame * CFrame.new(size.X / 2, -size.Y / 2, 0),
        BottomRight = shiftedCFrame * CFrame.new(-size.X / 2, -size.Y / 2, 0),
        Torso = shiftedCFrame
    }

    local headPart = self.Object:FindFirstChild("Head", true) or self.PrimaryPart
    local headPosition, headVisible = Camera:WorldToViewportPoint(headPart.Position + Vector3.new(0, 2.5, 0))

    if ESP.Names and headVisible then
        local username = self.Player and self.Player.Name or self.Object.Name
        local displayName = self.Player and self.Player.DisplayName or self.Object.Name
        
        self.Components.Name.Visible = true
        self.Components.Name.Position = Vector2.new(headPosition.X, headPosition.Y)
        self.Components.Name.Text = string.format("@%s | Display: %s | Health: %d | Distance: %dm", 
            username, displayName, math.round(currentHealth), math.round(distance)
        )
        self.Components.Name.Color = dynamicHealthColor
    else
        self.Components.Name.Visible = false
    end

    local topLeft, vis1 = Camera:WorldToViewportPoint(locations.TopLeft.Position)
    local topRight, vis2 = Camera:WorldToViewportPoint(locations.TopRight.Position)
    local bottomLeft, vis3 = Camera:WorldToViewportPoint(locations.BottomLeft.Position)
    local bottomRight, vis4 = Camera:WorldToViewportPoint(locations.BottomRight.Position)
    local boxVisible = vis1 or vis2 or vis3 or vis4

    if ESP.Boxes and boxVisible and PlatformMetrics.CurrentTier > 1 then
        self.Components.Quad.Visible = true
        self.Components.Quad.PointA = Vector2.new(topRight.X, topRight.Y)
        self.Components.Quad.PointB = Vector2.new(topLeft.X, topLeft.Y)
        self.Components.Quad.PointC = Vector2.new(bottomLeft.X, bottomLeft.Y)
        self.Components.Quad.PointD = Vector2.new(bottomRight.X, bottomRight.Y)
        self.Components.Quad.Color = color
        self.Components.Quad.Thickness = ESP.Thickness
    else
        self.Components.Quad.Visible = false
    end

    if ESP.HealthBars and boxVisible and PlatformMetrics.CurrentTier > 1 then
        local alignmentOffset = 6
        self.Components.HealthBarOutline.Visible = true
        self.Components.HealthBarOutline.From = Vector2.new(topLeft.X - alignmentOffset, topLeft.Y)
        self.Components.HealthBarOutline.To = Vector2.new(bottomLeft.X - alignmentOffset, bottomLeft.Y)
        self.Components.HealthBarOutline.Thickness = ESP.Thickness + 2

        local healthPercent = math.clamp(currentHealth / maximumHealth, 0, 1)
        local barHeightY = bottomLeft.Y - topLeft.Y
        local barProgressY = topLeft.Y + (barHeightY * (1 - healthPercent))

        self.Components.HealthBar.Visible = true
        self.Components.HealthBar.From = Vector2.new(topLeft.X - alignmentOffset, barProgressY)
        self.Components.HealthBar.To = Vector2.new(bottomLeft.X - alignmentOffset, bottomLeft.Y)
        self.Components.HealthBar.Color = dynamicHealthColor
        self.Components.HealthBar.Thickness = ESP.Thickness
    else
        self.Components.HealthBarOutline.Visible = false
        self.Components.HealthBar.Visible = false
    end

    if ESP.Tracers and boxVisible and PlatformMetrics.CurrentTier > 2 then
        local torsoPos, vis6 = Camera:WorldToViewportPoint(locations.Torso.Position)
        if vis6 then
            self.Components.Tracer.Visible = true
            self.Components.Tracer.From = Vector2.new(torsoPos.X, torsoPos.Y)
            self.Components.Tracer.To = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / ESP.AttachShift)
            self.Components.Tracer.Color = color
            self.Components.Tracer.Thickness = ESP.Thickness
        else
            self.Components.Tracer.Visible = false
        end
    else
        self.Components.Tracer.Visible = false
    end

    if ESP.Skeletons and PlatformMetrics.CurrentTier > 2 then
        local joints = {
            {"Head", "Torso"}, {"Torso", "Left Arm"}, {"Torso", "Right Arm"},
            {"Torso", "Left Leg"}, {"Torso", "Right Leg"}, {"Head", "UpperTorso"},
            {"UpperTorso", "LowerTorso"}, {"UpperTorso", "LeftUpperArm"}, {"LeftUpperArm", "LeftLowerArm"},
            {"LeftLowerArm", "LeftHand"}, {"UpperTorso", "RightUpperArm"}, {"RightUpperArm", "RightLowerArm"},
            {"RightLowerArm", "RightHand"}, {"LowerTorso", "LeftUpperLeg"}, {"LeftUpperLeg", "LeftLowerLeg"},
            {"LeftLowerLeg", "LeftFoot"}, {"LowerTorso", "RightUpperLeg"}, {"RightUpperLeg", "RightLowerLeg"},
            {"RightLowerLeg", "RightFoot"}
        }

        local lineIndex = 1
        for _, jointPair in ipairs(joints) do
            local partA = self.Object:FindFirstChild(jointPair[1], true)
            local partB = self.Object:FindFirstChild(jointPair[2], true)

            if partA and partB and partA:IsA("BasePart") and partB:IsA("BasePart") then
                local posA, visA = Camera:WorldToViewportPoint(partA.Position)
                local posB, visB = Camera:WorldToViewportPoint(partB.Position)

                if visA or visB then
                    local line = self.SkeletonLines[lineIndex]
                    if not line then
                        line = CreateDrawing("Line", {Thickness = 1.5, Transparency = 1})
                        self.SkeletonLines[lineIndex] = line
                    end
                    line.Visible = true
                    line.From = Vector2.new(posA.X, posA.Y)
                    line.To = Vector2.new(posB.X, posB.Y)
                    line.Color = color
                    lineIndex = lineIndex + 1
                end
            end
        end

        for i = lineIndex, #self.SkeletonLines do
            if self.SkeletonLines[i] then
                self.SkeletonLines[i].Visible = false
            end
        end
    else
        for _, line in pairs(self.SkeletonLines) do
            line.Visible = false
        end
    end
end

function ESP:Add(object, options)
    if not object.Parent and not options.RenderInNil then
        return
    end

    local determinedPart = FindValidPrimaryPart(object)
    if not determinedPart then return end

    local existingBox = self.Objects[object]
    if existingBox then
        pcall(existingBox.Remove, existingBox)
    end

    local box = setmetatable({
        Name = options.Name or object.Name,
        Type = "Box",
        Color = options.Color,
        Size = options.Size or self.BoxSize,
        Object = object,
        Player = options.Player or self:GetPlayerFromCharacter(object),
        PrimaryPart = determinedPart,
        Components = {},
        SkeletonLines = {},
        IsEnabled = options.IsEnabled,
        Temporary = options.Temporary,
        ColorDynamic = options.ColorDynamic,
        RenderInNil = options.RenderInNil
    }, BoxBase)

    box.Components["Quad"] = CreateDrawing("Quad", {Thickness = self.Thickness, Transparency = 1, Filled = false, Visible = false})
    box.Components["Name"] = CreateDrawing("Text", {Text = box.Name, Color = box.Color or self.Color, Center = true, Outline = true, Size = 13, Visible = false})
    box.Components["Tracer"] = CreateDrawing("Line", {Thickness = self.Thickness, Color = box.Color or self.Color, Transparency = 1, Visible = false})
    box.Components["HealthBarOutline"] = CreateDrawing("Line", {Thickness = self.Thickness + 2, Color = Color3.fromRGB(0, 0, 0), Transparency = 1, Visible = false})
    box.Components["HealthBar"] = CreateDrawing("Line", {Thickness = self.Thickness, Color = Color3.fromRGB(0, 255, 0), Transparency = 1, Visible = false})

    self.Objects[object] = box

    object.AncestryChanged:Connect(function(_, newParent)
        if newParent == nil and self.AutoRemove then
            box:Remove()
        end
    end)

    local humanoid = object:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.Died:Connect(function()
            if self.AutoRemove then
                box:Remove()
            end
        end)
    end

    return box
end

local function HandleCharacter(character)
    if not character then return end
    local player = Players:GetPlayerFromCharacter(character)
    if not player then return end

    if ESP.Objects[character] then
        pcall(ESP.Objects[character].Remove, ESP.Objects[character])
    end

    local rootPart = nil
    for i = 1, 30 do
        if not character.Parent then return end
        rootPart = FindValidPrimaryPart(character)
        if rootPart then break end
        task.wait(0.1)
    end

    if not rootPart then return end

    ESP:Add(character, {
        Name = player.Name,
        Player = player,
        PrimaryPart = rootPart
    })
end

local function HandlePlayer(player)
    if player == LocalPlayer then return end
    player.CharacterAdded:Connect(function(character)
        task.spawn(HandleCharacter, character)
    end)
    if player.Character then
        task.spawn(HandleCharacter, player.Character)
    end
end

Players.PlayerAdded:Connect(HandlePlayer)
Players.PlayerRemoving:Connect(function(player)
    for obj, box in pairs(ESP.Objects) do
        if box.Player == player then
            box:Remove()
        end
    end
end)

for _, player in ipairs(Players:GetPlayers()) do
    HandlePlayer(player)
end

RunService.RenderStepped:Connect(function(deltaTime)
    Camera = Workspace.CurrentCamera
    
    PlatformMetrics.LastFpsCheck = PlatformMetrics.LastFpsCheck + deltaTime
    if PlatformMetrics.LastFpsCheck >= 0.5 then
        local currentFps = 1 / deltaTime
        PlatformMetrics.LastFpsCheck = 0
        
        if currentFps < 35 then
            PlatformMetrics.CurrentTier = 1
            ESP.MaxDistance = 200
        elseif currentFps < 52 then
            PlatformMetrics.CurrentTier = 2
            ESP.MaxDistance = 500
        else
            PlatformMetrics.CurrentTier = 3
            local absoluteMax = PlatformMetrics.IsMobile and 400 or 1200
            ESP.MaxDistance = absoluteMax
        end
    end

    if not ESP.Enabled then return end

    for _, box in pairs(ESP.Objects) do
        if box.Update then
            local success, err = pcall(box.Update, box)
            if not success then
                warn("[Vision Engine Error]: " .. tostring(err))
            end
        end
    end
end)

return ESP
