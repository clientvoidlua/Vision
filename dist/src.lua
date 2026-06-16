local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local ESP = {
    Enabled = true,
    Boxes = true,
    Names = true,
    Tracers = true,
    TeamMates = true,
    Players = true,
    TeamColor = true,
    FaceCamera = false,
    BoxShift = CFrame.new(0, -1.5, 0),
    BoxSize = Vector3.new(4, 6, 0),
    Color = Color3.fromRGB(255, 170, 0),
    Thickness = 2,
    AttachShift = 1,
    Objects = setmetatable({}, {__mode = "kv"}),
    Overrides = {},
    Highlighted = nil,
    HighlightColor = Color3.fromRGB(255, 255, 255),
    AutoRemove = true,
    MaxDistance = 1000,
    TargetFPS = 60
}

local PlatformMetrics = {
    IsMobile = table.find({Enum.Platform.Android, Enum.Platform.IOS}, UserInputService:GetPlatform()) ~= nil,
    PerformanceThrottling = false,
    LastFpsCheck = 0
}

if PlatformMetrics.IsMobile then
    ESP.MaxDistance = 400
    ESP.Thickness = 1
end

local function ApplyFontSettings(drawingTextInstance)
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
        end
    end
end

function ESP:GetBox(object)
    return self.Objects[object]
end

function ESP:AddObject(parent, options)
    local function NewListener(child)
        if options.Type and not child:IsA(options.Type) then return end
        if options.Name and child.Name ~= options.Name then return end
        if options.Validator and not options.Validator(child) then return end

        local boxOptions = table.clone(options)

        if type(options.PrimaryPart) == "string" then    
            boxOptions.PrimaryPart = child:WaitForChild(options.PrimaryPart)    
        elseif type(options.PrimaryPart) == "function" then    
            boxOptions.PrimaryPart = options.PrimaryPart(child)    
        end    

        if type(options.Color) == "function" then    
            boxOptions.Color = options.Color(child)    
        end    

        if options.CustomName then    
            if type(options.CustomName) == "function" then    
                boxOptions.Name = options.CustomName(child)    
            else    
                boxOptions.Name = options.CustomName    
            end    
        end    

        local box = ESP:Add(child, boxOptions)    
        if options.OnAdded then    
            task.spawn(options.OnAdded, box)    
        end
    end

    local connection = options.Recursive and parent.DescendantAdded or parent.ChildAdded
    local currentChildren = options.Recursive and parent:GetDescendants() or parent:GetChildren()

    connection:Connect(NewListener)
    for _, child in ipairs(currentChildren) do
        task.spawn(NewListener, child)
    end
end

local BoxBase = {}
BoxBase.__index = BoxBase

function BoxBase:Remove()
    ESP.Objects[self.Object] = nil
    for index, component in pairs(self.Components) do
        component.Visible = false
        component:Remove()
        self.Components[index] = nil
    end
end

function BoxBase:Update()
    if not self.PrimaryPart then
        return self:Remove()
    end

    local cameraCFrame = Camera.CFrame
    local distance = (cameraCFrame.Position - self.PrimaryPart.Position).Magnitude

    if distance > ESP.MaxDistance then
        for _, component in pairs(self.Components) do
            component.Visible = false
        end
        return
    end

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
        TagPos = shiftedCFrame * CFrame.new(0, size.Y / 2, 0),
        Torso = shiftedCFrame
    }

    local scaleFactor = math.clamp(1 / (distance * 0.015), 0.4, 1.1)

    if (ESP.Boxes or ESP.Box) and not PlatformMetrics.PerformanceThrottling then
        local topLeft, vis1 = Camera:WorldToViewportPoint(locations.TopLeft.Position)
        local topRight, vis2 = Camera:WorldToViewportPoint(locations.TopRight.Position)
        local bottomLeft, vis3 = Camera:WorldToViewportPoint(locations.BottomLeft.Position)
        local bottomRight, vis4 = Camera:WorldToViewportPoint(locations.BottomRight.Position)

        if self.Components.Quad then
            if vis1 or vis2 or vis3 or vis4 then
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
        end
    else
        if self.Components.Quad then
            self.Components.Quad.Visible = false
        end
    end

    if ESP.Names or ESP.Name then
        local tagPos, vis5 = Camera:WorldToViewportPoint(locations.TagPos.Position)

        if vis5 then
            self.Components.Name.Visible = true
            self.Components.Name.Position = Vector2.new(tagPos.X, tagPos.Y - (16 * scaleFactor))
            self.Components.Name.Text = self.Name
            self.Components.Name.Color = color
            self.Components.Name.Size = math.round(16 * scaleFactor)

            self.Components.Distance.Visible = true
            self.Components.Distance.Position = Vector2.new(tagPos.X, tagPos.Y - (16 * scaleFactor) + math.round(14 * scaleFactor))
            self.Components.Distance.Text = math.floor(distance) .. " studs"
            self.Components.Distance.Color = color
            self.Components.Distance.Size = math.round(12 * scaleFactor)
        else
            self.Components.Name.Visible = false
            self.Components.Distance.Visible = false
        end
    else
        self.Components.Name.Visible = false
        self.Components.Distance.Visible = false
    end

    if ESP.Tracers or ESP.Tracer then
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
end

function ESP:Add(object, options)
    if not object.Parent and not options.RenderInNil then
        return
    end

    local determinedPart = nil
    if object:IsA("Model") then
        determinedPart = object.PrimaryPart or object:FindFirstChild("HumanoidRootPart") or object:FindFirstChildWhichIsA("BasePart")
    elseif object:IsA("BasePart") then
        determinedPart = object
    end

    local box = setmetatable({
        Name = options.Name or object.Name,
        Type = "Box",
        Color = options.Color,
        Size = options.Size or self.BoxSize,
        Object = object,
        Player = options.Player or self:GetPlayerFromCharacter(object),
        PrimaryPart = options.PrimaryPart or determinedPart,
        Components = {},
        IsEnabled = options.IsEnabled,
        Temporary = options.Temporary,
        ColorDynamic = options.ColorDynamic,
        RenderInNil = options.RenderInNil
    }, BoxBase)

    local existingBox = self:GetBox(object)
    if existingBox then
        existingBox:Remove()
    end

    box.Components["Quad"] = CreateDrawing("Quad", {
        Thickness = self.Thickness,
        Transparency = 1,
        Filled = false,
        Visible = (self.Enabled and (self.Boxes or self.Box))
    })
    box.Components["Name"] = CreateDrawing("Text", {
        Text = box.Name,
        Color = box.Color or self.Color,
        Center = true,
        Outline = true,
        Size = 16,
        Visible = (self.Enabled and (self.Names or self.Name))
    })
    box.Components["Distance"] = CreateDrawing("Text", {
        Color = box.Color or self.Color,
        Center = true,
        Outline = true,
        Size = 12,
        Visible = (self.Enabled and (self.Names or self.Name))
    })
    box.Components["Tracer"] = CreateDrawing("Line", {
        Thickness = self.Thickness,
        Color = box.Color or self.Color,
        Transparency = 1,
        Visible = (self.Enabled and (self.Tracers or self.Tracer))
    })

    self.Objects[object] = box

    object.AncestryChanged:Connect(function(_, newParent)
        if newParent == nil and self.AutoRemove then
            box:Remove()
        end
    end)

    object:GetPropertyChangedSignal("Parent"):Connect(function()
        if object.Parent == nil and self.AutoRemove then
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
    local player = Players:GetPlayerFromCharacter(character)
    if not player then return end

    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then
        local attachmentConnection
        attachmentConnection = character.ChildAdded:Connect(function(child)
            if child.Name == "HumanoidRootPart" then
                attachmentConnection:Disconnect()
                ESP:Add(character, {
                    Name = player.Name,
                    Player = player,
                    PrimaryPart = child
                })
            end
        end)
    else
        ESP:Add(character, {
            Name = player.Name,
            Player = player,
            PrimaryPart = rootPart
        })
    end
end

local function HandlePlayer(player)
    player.CharacterAdded:Connect(HandleCharacter)
    if player.Character then
        task.spawn(HandleCharacter, player.Character)
    end
end

Players.PlayerAdded:Connect(HandlePlayer)
for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then
        HandlePlayer(player)
    end
end

RunService.RenderStepped:Connect(function(deltaTime)
    Camera = Workspace.CurrentCamera
    
    PlatformMetrics.LastFpsCheck = PlatformMetrics.LastFpsCheck + deltaTime
    if PlatformMetrics.LastFpsCheck >= 0.5 then
        local currentFps = 1 / deltaTime
        PlatformMetrics.LastFpsCheck = 0
        
        if currentFps < 45 then
            PlatformMetrics.PerformanceThrottling = true
            ESP.MaxDistance = math.max(250, ESP.MaxDistance - 50)
        elseif currentFps > 55 then
            PlatformMetrics.PerformanceThrottling = false
            local absoluteMax = PlatformMetrics.IsMobile and 400 or 1200
            ESP.MaxDistance = math.min(absoluteMax, ESP.MaxDistance + 25)
        end
    end

    if not ESP.Enabled then return end

    for _, box in pairs(ESP.Objects) do
        if box.Update then
            local success, err = pcall(box.Update, box)
            if not success then
                warn(err)
            end
        end
    end
end)

return ESP
