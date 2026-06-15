local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Camera = Workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer

local ESP = {
    Enabled = false,
    Boxes = true,
    BoxShift = CFrame.new(0, -1.5, 0),
    BoxSize = Vector3.new(4, 6, 0),
    Color = Color3.fromRGB(255, 170, 0),
    FaceCamera = false,
    Names = true,
    TeamColor = true,
    Thickness = 2,
    AttachShift = 1,
    TeamMates = true,
    Players = true,
    Tracers = false,
    Highlighted = nil,
    HighlightColor = Color3.fromRGB(255, 255, 255),
    AutoRemove = true,
    
    Objects = setmetatable({}, {__mode = "kv"}),
    Overrides = {},
    
    CurrentFps = 60,
    UpdateBudget = 1,
    FrameCounter = 0,
    LastFpsCheck = os.clock(),
    IsLowEndPlatform = false
}

local WorldToViewportPoint = Camera.WorldToViewportPoint
local TableClone = table.clone
local TaskSpawn = task.spawn
local MathFloor = math.floor
local MathClamp = math.clamp
local Vector2New = Vector2.new

local function DetectPlatformPerformance()
    if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
        ESP.IsLowEndPlatform = true
        ESP.Tracers = false
        ESP.Thickness = 1
    end
end
DetectPlatformPerformance()

local function Draw(objectType, properties)
    local drawing = Drawing.new(objectType)
    properties = properties or {}
    for key, value in properties do
        drawing[key] = value
    end
    return drawing
end

function ESP:GetTeam(player)
    local override = self.Overrides.GetTeam
    if override then
        return override(player)
    end
    return player and player.Team
end

function ESP:IsTeamMate(player)
    local override = self.Overrides.IsTeamMate
    if override then
        return override(player)
    end
    return self:GetTeam(player) == self:GetTeam(LocalPlayer)
end

function ESP:GetColor(object)
    local override = self.Overrides.GetColor
    if override then
        return override(object)
    end
    local player = self:GetPlayerFromCharacter(object)
    if player and self.TeamColor and player.Team then
        return player.Team.TeamColor.Color
    end
    return self.Color
end

function ESP:GetPlayerFromCharacter(character)
    local override = self.Overrides.GetPlayerFromCharacter
    if override then
        return override(character)
    end
    return Players:GetPlayerFromCharacter(character)
end

function ESP:Toggle(state)
    self.Enabled = state
    if not state then
        for _, box in self.Objects do
            if box.Components then
                for _, component do
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

        local boxOptions = TableClone(options)
        
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

        local box = self:Add(child, boxOptions)
        if options.OnAdded then
            TaskSpawn(options.OnAdded, box)
        end
    end

    local connectionEvent = options.Recursive and parent.DescendantAdded or parent.ChildAdded
    local existingObjects = options.Recursive and parent:GetDescendants() or parent:GetChildren()

    connectionEvent:Connect(NewListener)
    for _, object in existingObjects do
        TaskSpawn(NewListener, object)
    end
end

local BoxBase = {}
BoxBase.__index = BoxBase

function BoxBase:Remove()
    ESP.Objects[self.Object] = nil
    if self.Connections then
        for _, connection in self.Connections do
            connection:Disconnect()
        end
    end
    for key, component in self.Components do
        component.Visible = false
        component:Remove()
        self.Components[key] = nil
    end
end

function BoxBase:Update()
    if not self.PrimaryPart or not self.PrimaryPart.Parent then
        return self:Remove()
    end

    local allow = true
    if ESP.Overrides.UpdateAllow and not ESP.Overrides.UpdateAllow(self) then
        allow = false
    end
    if self.Player and not ESP.TeamMates and ESP:IsTeamMate(self.Player) then
        allow = false
    end
    if self.Player and not ESP.Players then
        allow = false
    end
    if self.IsEnabled then
        if type(self.IsEnabled) == "string" and not ESP[self.IsEnabled] then
            allow = false
        elseif type(self.IsEnabled) == "function" and not self:IsEnabled() then
            allow = false
        end
    end
    if not self.RenderInNil and not Workspace:IsAncestorOf(self.PrimaryPart) then
        allow = false
    end

    if not allow then
        for _, component in self.Components do
            component.Visible = false
        end
        return
    end

    local color = ESP.Color
    if ESP.Highlighted == self.Object then
        color = ESP.HighlightColor
    else
        color = self.Color or (self.ColorDynamic and self:ColorDynamic()) or ESP:GetColor(self.Object)
    end

    local cameraCFrame = Camera.CFrame
    local objectCFrame = self.PrimaryPart.CFrame
    local distance = (cameraCFrame.Position - objectCFrame.Position).Magnitude
    
    local scaleFactor = 1 / (distance * 0.008)
    scaleFactor = MathClamp(scaleFactor, 0.4, 1.5)
    
    if ESP.IsLowEndPlatform then
        scaleFactor = scaleFactor * 0.8
    end

    if ESP.FaceCamera then
        objectCFrame = CFrame.new(objectCFrame.Position, cameraCFrame.Position)
    end

    local size = self.Size * scaleFactor
    local boxShift = ESP.BoxShift
    
    local topLeft = objectCFrame * boxShift * CFrame.new(size.X / 2, size.Y / 2, 0)
    local topRight = objectCFrame * boxShift * CFrame.new(-size.X / 2, size.Y / 2, 0)
    local bottomLeft = objectCFrame * boxShift * CFrame.new(size.X / 2, -size.Y / 2, 0)
    local bottomRight = objectCFrame * boxShift * CFrame.new(-size.X / 2, -size.Y / 2, 0)
    local tagPosition = objectCFrame * boxShift * CFrame.new(0, size.Y / 2, 0)
    local tracerPosition = objectCFrame * boxShift

    if ESP.Boxes and not ESP.IsLowEndPlatform then
        local screenTopLeft, vis1 = WorldToViewportPoint(Camera, topLeft.Position)
        local screenTopRight, vis2 = WorldToViewportPoint(Camera, topRight.Position)
        local screenBottomLeft, vis3 = WorldToViewportPoint(Camera, bottomLeft.Position)
        local screenBottomRight, vis4 = WorldToViewportPoint(Camera, bottomRight.Position)

        if self.Components.Quad then
            if vis1 or vis2 or vis3 or vis4 then
                self.Components.Quad.Visible = true
                self.Components.Quad.PointA = Vector2New(screenTopRight.X, screenTopRight.Y)
                self.Components.Quad.PointB = Vector2New(screenTopLeft.X, screenTopLeft.Y)
                self.Components.Quad.PointC = Vector2New(screenBottomLeft.X, screenBottomLeft.Y)
                self.Components.Quad.PointD = Vector2New(screenBottomRight.X, screenBottomRight.Y)
                self.Components.Quad.Color = color
                self.Components.Quad.Thickness = ESP.Thickness
            else
                self.Components.Quad.Visible = false
            end
        end
    elseif self.Components.Quad then
        self.Components.Quad.Visible = false
    end

    if ESP.Names then
        local screenTag, visName = WorldToViewportPoint(Camera, tagPosition.Position)
        if visName then
            local adjustedFontSize = MathClamp(MathFloor(16 * scaleFactor), 10, 22)
            
            self.Components.Name.Visible = true
            self.Components.Name.Position = Vector2New(screenTag.X, screenTag.Y - (adjustedFontSize + 2))
            self.Components.Name.Text = self.Name
            self.Components.Name.Color = color
            self.Components.Name.Size = adjustedFontSize
            
            self.Components.Distance.Visible = true
            self.Components.Distance.Position = Vector2New(screenTag.X, screenTag.Y - 2)
            self.Components.Distance.Text = MathFloor(distance) .. "m"
            self.Components.Distance.Color = color
            self.Components.Distance.Size = MathClamp(adjustedFontSize - 2, 8, 18)
        else
            self.Components.Name.Visible = false
            self.Components.Distance.Visible = false
        end
    else
        self.Components.Name.Visible = false
        self.Components.Distance.Visible = false
    end
    
    if ESP.Tracers and not ESP.IsLowEndPlatform then
        local screenTracer, visTracer = WorldToViewportPoint(Camera, tracerPosition.Position)
        if visTracer then
            self.Components.Tracer.Visible = true
            self.Components.Tracer.From = Vector2New(screenTracer.X, screenTracer.Y)
            self.Components.Tracer.To = Vector2New(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / ESP.AttachShift)
            self.Components.Tracer.Color = color
            self.Components.Tracer.Thickness = ESP.Thickness
        else
            self.Components.Tracer.Visible = false
        end
    elseif self.Components.Tracer then
        self.Components.Tracer.Visible = false
    end
end

function ESP:Add(object, options)
    if not object.Parent and not options.RenderInNil then
        warn(object, "has no parent")
        return nil
    end

    local box = setmetatable({
        Name = options.Name or object.Name,
        Type = "Box",
        Color = options.Color,
        Size = options.Size or self.BoxSize,
        Object = object,
        Player = options.Player or Players:GetPlayerFromCharacter(object),
        PrimaryPart = options.PrimaryPart or (object:IsA("Model") and (object.PrimaryPart or object:FindFirstChild("HumanoidRootPart") or object:FindFirstChildWhichIsA("BasePart"))) or (object:IsA("BasePart") and object),
        Components = {},
        Connections = {},
        IsEnabled = options.IsEnabled,
        Temporary = options.Temporary,
        ColorDynamic = options.ColorDynamic,
        RenderInNil = options.RenderInNil
    }, BoxBase)

    if self:GetBox(object) then
        self:GetBox(object):Remove()
    end

    box.Components["Quad"] = Draw("Quad", {
        Thickness = self.Thickness,
        Color = box.Color or self.Color,
        Transparency = 1,
        Filled = false,
        Visible = false
    })
    
    box.Components["Name"] = Draw("Text", {
        Text = box.Name,
        Color = box.Color or self.Color,
        Center = true,
        Outline = true,
        Size = 16,
        Font = 3,
        Visible = false
    })
    
    box.Components["Distance"] = Draw("Text", {
        Color = box.Color or self.Color,
        Center = true,
        Outline = true,
        Size = 14,
        Font = 3,
        Visible = false
    })
    
    box.Components["Tracer"] = Draw("Line", {
        Thickness = self.Thickness,
        Color = box.Color or self.Color,
        Transparency = 1,
        Visible = false
    })

    self.Objects[object] = box
    
    if self.AutoRemove then
        table.insert(box.Connections, object.AncestryChanged:Connect(function(_, parent)
            if parent == nil then
                box:Remove()
            end
        end))
        
        table.insert(box.Connections, object:GetPropertyChangedSignal("Parent"):Connect(function()
            if object.Parent == nil then
                box:Remove()
            end
        end))

        local humanoid = object:FindFirstChildOfClass("Humanoid")
        if humanoid then
            table.insert(box.Connections, humanoid.Died:Connect(function()
                box:Remove()
            end))
        end
    end

    return box
end

local function CharacterAdded(character)
    local player = Players:GetPlayerFromCharacter(character)
    if not player then return end
    
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then
        local connection
        connection = character.ChildAdded:Connect(function(child)
            if child.Name == "HumanoidRootPart" then
                connection:Disconnect()
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

local function PlayerAdded(player)
    player.CharacterAdded:Connect(CharacterAdded)
    if player.Character then
        TaskSpawn(CharacterAdded, player.Character)
    end
end

Players.PlayerAdded:Connect(PlayerAdded)
for _, player in Players:GetPlayers() do
    if player ~= LocalPlayer then
        PlayerAdded(player)
    end
end

local objectKeys = {}
local currentObjectIndex = 1

RunService.RenderStepped:Connect(function()
    Camera = Workspace.CurrentCamera
    if not ESP.Enabled then return end

    ESP.FrameCounter = ESP.FrameCounter + 1
    local now = os.clock()
    local timePassed = now - ESP.LastFpsCheck
    
    if timePassed >= 0.25 then
        ESP.CurrentFps = ESP.FrameCounter / timePassed
        ESP.FrameCounter = 0
        ESP.LastFpsCheck = now

        if ESP.CurrentFps < 35 then
            ESP.UpdateBudget = 4
            ESP.IsLowEndPlatform = true
        elseif ESP.CurrentFps < 45 then
            ESP.UpdateBudget = 3
        elseif ESP.CurrentFps < 55 then
            ESP.UpdateBudget = 2
        else
            ESP.UpdateBudget = 1
            DetectPlatformPerformance()
        end
    end

    table.clear(objectKeys)
    for object, _ in ESP.Objects do
        table.insert(objectKeys, object)
    end
    
    local totalObjects = #objectKeys
    if totalObjects == 0 then return end

    if ESP.UpdateBudget == 1 then
        for i = 1, totalObjects do
            local box = ESP.Objects[objectKeys[i]]
            if box and box.Update then
                box:Update()
            end
        end
    else
        for i = 1, totalObjects do
            local box = ESP.Objects[objectKeys[i]]
            if box then
                if (i % ESP.UpdateBudget) == (currentObjectIndex % ESP.UpdateBudget) then
                    box:Update()
                elseif not box.PrimaryPart or not box.PrimaryPart.Parent then
                    box:Remove()
                end
            end
        end
        currentObjectIndex = (currentObjectIndex % ESP.UpdateBudget) + 1
    end
end)

return ESP
