-- features_module.lua
local Features = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

--// Connection storage
Features.Connections = {}

function Features:Disconnect(flag)
    if self.Connections[flag] then
        self.Connections[flag]:Disconnect()
        self.Connections[flag] = nil
    end
end

function Features:Connect(flag, func)
    self:Disconnect(flag)
    self.Connections[flag] = RunService.Heartbeat:Connect(func)
end

--// PLAYER ESP SYSTEM (Tab 4)
Features.ESPConfig = {
    auto_track = true,
    box = { enabled = false, type = "normal", fill = Color3.new(1,1,1), outline = Color3.new(0,0,0) },
    healthbar = { enabled = false, fill = Color3.new(0,1,0), outline = Color3.new(0,0,0), width = 2, offset = 3, dynamic_color = true },
    friendmarker = { enabled = false, fill = Color3.new(0.2,0.6,1), size_offset = 4, offset = 4 },
    dsyncmarker = { enabled = false, fill = Color3.new(1,1,0), size_offset = 4, offset = 4 },
    macromarker = { enabled = false, fill = Color3.new(0,1,0), size_offset = 4, offset = 4 },
    name = { enabled = false, fill = Color3.new(1,1,1), size = 13 },
    distance = { enabled = false, fill = Color3.new(1,1,1), size = 13 },
    state = { enabled = false, fill = Color3.new(1,1,1), size = 12, offset = 3 },
    tracer = { enabled = false, fill = Color3.new(1,1,1), outline = Color3.new(0,0,0), from = "mouse" },
}
Features.ESPNameMode = "Real Name"
Features.ESPMode = "Static"

-- Embedded ESP Library (adapted for APEX UI)
local esplib = Features.ESPConfig
local espinstances = {}
local espfunctions = {}

local run_service = game:GetService("RunService")
local players = game:GetService("Players")
local user_input_service = game:GetService("UserInputService")
local camera = workspace.CurrentCamera
local localPlayer = players.LocalPlayer

local friendCache = {}
local charSizes = {}
local detectData = {}

local function isFriend(player)
    if not player then return false end
    local uid = player.UserId
    if friendCache[uid] == nil then
        local ok, res = pcall(function()
            return localPlayer:IsFriendsWith(uid)
        end)
        friendCache[uid] = ok and res or false
    end
    return friendCache[uid]
end

local function detectAnomalies(instance, humanoid, hrp)
    local player = players:GetPlayerFromCharacter(instance)
    if not player or player == localPlayer then return false, false end
    local now = tick()
    local data = detectData[player] or {
        history = {}, lastPos = nil, lastTime = nil, lastDir = nil,
        macroEnd = 0, dsyncEnd = 0, freezeTime = nil,
    }
    local currentPos = hrp.Position
    local currentDir = hrp.CFrame.LookVector
    table.insert(data.history, 1, {pos = currentPos, time = now, dir = currentDir})
    if #data.history > 12 then table.remove(data.history) end
    if data.lastPos and data.lastTime then
        local dt = now - data.lastTime
        if dt > 0.001 and dt < 0.4 then
            local delta = currentPos - data.lastPos
            local horizontal = Vector3.new(delta.X, 0, delta.Z)
            local horizontalDist = horizontal.Magnitude
            local verticalDist = math.abs(delta.Y)
            local hSpeed = horizontalDist / dt
            if hSpeed > 35 and horizontalDist > 4 then
                data.macroEnd = now + 0.3
            end
            if horizontalDist > 20 and verticalDist < 12 then
                data.dsyncEnd = now + 0.5
            elseif data.freezeTime and (now - data.freezeTime) > 0.25 and horizontalDist > 6 then
                data.dsyncEnd = now + 0.5
                data.freezeTime = nil
            elseif #data.history >= 5 then
                local pNow  = data.history[1].pos
                local pMid  = data.history[3].pos
                local pOld  = data.history[6] and data.history[6].pos or pMid
                local d1 = Vector3.new(pNow.X - pMid.X, 0, pNow.Z - pMid.Z).Magnitude
                local d2 = Vector3.new(pMid.X - pOld.X, 0, pMid.Z - pOld.Z).Magnitude
                if d1 > 4 and d2 > 4 then
                    local returnDist = Vector3.new(pNow.X - pOld.X, 0, pNow.Z - pOld.Z).Magnitude
                    if returnDist < math.max(d1, d2) * 0.4 then
                        data.dsyncEnd = now + 0.4
                    end
                end
            end
            if data.lastDir then
                local dot = data.lastDir:Dot(currentDir)
                local angle = math.acos(math.clamp(dot, -1, 1))
                local angularSpeed = angle / dt
                if angularSpeed > 10 then
                    data.dsyncEnd = now + 0.3
                end
            end
            if humanoid.MoveDirection.Magnitude < 0.05 and hSpeed > 30 then
                data.dsyncEnd = now + 0.4
            end
            if horizontalDist < 0.2 and verticalDist < 0.4 then
                if not data.freezeTime then data.freezeTime = now end
            else
                data.freezeTime = nil
            end
        end
    end
    data.lastPos = currentPos
    data.lastTime = now
    data.lastDir = currentDir
    detectData[player] = data
    return now < (data.dsyncEnd or 0), now < (data.macroEnd or 0)
end

local function getCharSize(instance)
    if Features.ESPMode == "Static" and charSizes[instance] then
        return charSizes[instance]
    end
    local hrp = instance:FindFirstChild("HumanoidRootPart")
    local head = instance:FindFirstChild("Head")
    local torso = instance:FindFirstChild("UpperTorso") or instance:FindFirstChild("Torso")
    local height = 5
    local width = 3.5
    if head and hrp then
        height = math.abs(head.Position.Y - hrp.Position.Y) * 2.4
    end
    if torso then
        width = math.max(torso.Size.X, torso.Size.Z) * 2.0
    end
    height = math.clamp(height, 4, 10)
    width = math.clamp(width, 2.5, 7)
    local size = Vector3.new(width, height, width)
    if Features.ESPMode == "Static" then
        charSizes[instance] = size
    end
    return size
end

local function get_static_box(instance)
    local ref = instance:FindFirstChild("HumanoidRootPart") or instance:FindFirstChild("Head") or instance:FindFirstChildWhichIsA("BasePart")
    if not ref then return nil, nil, false end
    local center = ref.Position
    local size = getCharSize(instance)
    local half = size / 2
    local min, max = Vector2.new(math.huge, math.huge), Vector2.new(-math.huge, -math.huge)
    local anyVisible = false
    for _, offset in ipairs({
        Vector3.new( half.X,  half.Y,  half.Z), Vector3.new(-half.X,  half.Y,  half.Z),
        Vector3.new( half.X, -half.Y,  half.Z), Vector3.new(-half.X, -half.Y,  half.Z),
        Vector3.new( half.X,  half.Y, -half.Z), Vector3.new(-half.X,  half.Y, -half.Z),
        Vector3.new( half.X, -half.Y, -half.Z), Vector3.new(-half.X, -half.Y, -half.Z),
    }) do
        local pos, visible = camera:WorldToViewportPoint(center + offset)
        if visible then
            local v2 = Vector2.new(pos.X, pos.Y)
            min = min:Min(v2)
            max = max:Max(v2)
            anyVisible = true
        end
    end
    if not anyVisible then return nil, nil, false end
    return min, max, true
end

function espfunctions.add_box(instance)
    if not instance or espinstances[instance] and espinstances[instance].box then return end
    local box = {}
    local outline = Drawing.new("Square")
    outline.Thickness = 3; outline.Filled = false; outline.Transparency = 1; outline.Visible = false
    local fill = Drawing.new("Square")
    fill.Thickness = 1; fill.Filled = false; fill.Transparency = 1; fill.Visible = false
    box.outline = outline; box.fill = fill
    box.corner_fill = {}; box.corner_outline = {}
    for i = 1, 8 do
        local o = Drawing.new("Line")
        o.Thickness = 3; o.Transparency = 1; o.Visible = false
        local f = Drawing.new("Line")
        f.Thickness = 1; f.Transparency = 1; f.Visible = false
        table.insert(box.corner_fill, f)
        table.insert(box.corner_outline, o)
    end
    espinstances[instance] = espinstances[instance] or {}
    espinstances[instance].box = box
end

function espfunctions.add_healthbar(instance)
    if not instance or espinstances[instance] and espinstances[instance].healthbar then return end
    local outline = Drawing.new("Square")
    outline.Thickness = 1; outline.Filled = true; outline.Transparency = 1
    local fill = Drawing.new("Square")
    fill.Filled = true; fill.Transparency = 1
    espinstances[instance] = espinstances[instance] or {}
    espinstances[instance].healthbar = { outline = outline, fill = fill }
end

function espfunctions.add_friendmarker(instance)
    if not instance or espinstances[instance] and espinstances[instance].friendmarker then return end
    local text = Drawing.new("Text")
    text.Center = false; text.Outline = true; text.Font = 1; text.Transparency = 1; text.Text = "F"
    espinstances[instance] = espinstances[instance] or {}
    espinstances[instance].friendmarker = text
end

function espfunctions.add_dsyncmarker(instance)
    if not instance or espinstances[instance] and espinstances[instance].dsyncmarker then return end
    local text = Drawing.new("Text")
    text.Center = false; text.Outline = true; text.Font = 1; text.Transparency = 1; text.Text = "DSYNC"
    espinstances[instance] = espinstances[instance] or {}
    espinstances[instance].dsyncmarker = text
end

function espfunctions.add_macromarker(instance)
    if not instance or espinstances[instance] and espinstances[instance].macromarker then return end
    local text = Drawing.new("Text")
    text.Center = false; text.Outline = true; text.Font = 1; text.Transparency = 1; text.Text = "MACRO"
    espinstances[instance] = espinstances[instance] or {}
    espinstances[instance].macromarker = text
end

function espfunctions.add_name(instance)
    if not instance or espinstances[instance] and espinstances[instance].name then return end
    local text = Drawing.new("Text")
    text.Center = true; text.Outline = true; text.Font = 1; text.Transparency = 1
    espinstances[instance] = espinstances[instance] or {}
    espinstances[instance].name = text
end

function espfunctions.add_distance(instance)
    if not instance or espinstances[instance] and espinstances[instance].distance then return end
    local text = Drawing.new("Text")
    text.Center = true; text.Outline = true; text.Font = 1; text.Transparency = 1
    espinstances[instance] = espinstances[instance] or {}
    espinstances[instance].distance = text
end

function espfunctions.add_state(instance)
    if not instance or espinstances[instance] and espinstances[instance].state then return end
    local text = Drawing.new("Text")
    text.Center = true; text.Outline = true; text.Font = 1; text.Transparency = 1
    espinstances[instance] = espinstances[instance] or {}
    espinstances[instance].state = text
end

function espfunctions.add_tracer(instance)
    if not instance or espinstances[instance] and espinstances[instance].tracer then return end
    local outline = Drawing.new("Line")
    outline.Thickness = 3; outline.Transparency = 1
    local fill = Drawing.new("Line")
    fill.Thickness = 1; fill.Transparency = 1
    espinstances[instance] = espinstances[instance] or {}
    espinstances[instance].tracer = { outline = outline, fill = fill }
end

run_service.RenderStepped:Connect(function()
    local toRemove = {}
    for instance, data in pairs(espinstances) do
        if not instance or not instance.Parent then
            if data.box then
                data.box.outline:Remove(); data.box.fill:Remove()
                for _, line in ipairs(data.box.corner_fill) do line:Remove() end
                for _, line in ipairs(data.box.corner_outline) do line:Remove() end
            end
            if data.healthbar then data.healthbar.outline:Remove(); data.healthbar.fill:Remove() end
            if data.friendmarker then data.friendmarker:Remove() end
            if data.dsyncmarker then data.dsyncmarker:Remove() end
            if data.macromarker then data.macromarker:Remove() end
            if data.name then data.name:Remove() end
            if data.distance then data.distance:Remove() end
            if data.state then data.state:Remove() end
            if data.tracer then data.tracer.outline:Remove(); data.tracer.fill:Remove() end
            table.insert(toRemove, instance)
        else
            local min, max, onscreen = get_static_box(instance)
            local humanoid = instance:FindFirstChildOfClass("Humanoid")
            local hrp = instance:FindFirstChild("HumanoidRootPart")
            local dsyncDetected, macroDetected = false, false
            if humanoid and hrp then
                dsyncDetected, macroDetected = detectAnomalies(instance, humanoid, hrp)
            end
            local markerSize = (esplib.name.size or 13) + 4
            local rightX = (max and max.X or 0) + (esplib.friendmarker.offset or 4)
            local lineH = markerSize + 2
            local rightY = (min and min.Y or 0)

            if data.box then
                local box = data.box
                if esplib.box.enabled and onscreen and min and max then
                    local x, y = min.X, min.Y
                    local w, h = (max - min).X, (max - min).Y
                    local len = math.min(w, h) * 0.25
                    if esplib.box.type == "normal" then
                        box.outline.Position = min; box.outline.Size = max - min; box.outline.Color = esplib.box.outline; box.outline.Visible = true
                        box.fill.Position = min; box.fill.Size = max - min; box.fill.Color = esplib.box.fill; box.fill.Visible = true
                        for _, line in ipairs(box.corner_fill) do line.Visible = false end
                        for _, line in ipairs(box.corner_outline) do line.Visible = false end
                    elseif esplib.box.type == "corner" then
                        local fill_lines = box.corner_fill
                        local outline_lines = box.corner_outline
                        local corners = {
                            { Vector2.new(x, y), Vector2.new(x + len, y) },
                            { Vector2.new(x, y), Vector2.new(x, y + len) },
                            { Vector2.new(x + w - len, y), Vector2.new(x + w, y) },
                            { Vector2.new(x + w, y), Vector2.new(x + w, y + len) },
                            { Vector2.new(x, y + h), Vector2.new(x + len, y + h) },
                            { Vector2.new(x, y + h - len), Vector2.new(x, y + h) },
                            { Vector2.new(x + w - len, y + h), Vector2.new(x + w, y + h) },
                            { Vector2.new(x + w, y + h - len), Vector2.new(x + w, y + h) },
                        }
                        for i = 1, 8 do
                            local from, to = corners[i][1], corners[i][2]
                            local dir = (to - from).Unit
                            local o = outline_lines[i]
                            o.From = from - dir; o.To = to + dir; o.Color = esplib.box.outline; o.Visible = true
                            local f = fill_lines[i]
                            f.From = from; f.To = to; f.Color = esplib.box.fill; f.Visible = true
                        end
                        box.outline.Visible = false; box.fill.Visible = false
                    end
                else
                    box.outline.Visible = false; box.fill.Visible = false
                    for _, line in ipairs(box.corner_fill) do line.Visible = false end
                    for _, line in ipairs(box.corner_outline) do line.Visible = false end
                end
            end

            if data.healthbar then
                local outline, fill = data.healthbar.outline, data.healthbar.fill
                if not esplib.healthbar.enabled or not onscreen or not min or not max then
                    outline.Visible = false; fill.Visible = false
                else
                    if humanoid and humanoid.MaxHealth > 0 then
                        local height = max.Y - min.Y
                        local barW = esplib.healthbar.width or 2
                        local barOff = esplib.healthbar.offset or 3
                        local x = min.X - barOff - barW
                        local ratio = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
                        local fillH = height * ratio
                        outline.Color = esplib.healthbar.outline
                        outline.Position = Vector2.new(x, min.Y)
                        outline.Size = Vector2.new(barW, height)
                        outline.Visible = true
                        if esplib.healthbar.dynamic_color then
                            fill.Color = Color3.new(1, 0, 0):Lerp(Color3.new(0, 1, 0), ratio)
                        else
                            fill.Color = esplib.healthbar.fill
                        end
                        fill.Position = Vector2.new(x, max.Y - fillH)
                        fill.Size = Vector2.new(barW, fillH)
                        fill.Visible = true
                    else
                        outline.Visible = false; fill.Visible = false
                    end
                end
            end

            if data.friendmarker then
                local text = data.friendmarker
                if not esplib.friendmarker.enabled or not onscreen or not min then
                    text.Visible = false
                else
                    local player = players:GetPlayerFromCharacter(instance)
                    if player and isFriend(player) then
                        text.Size = markerSize; text.Color = esplib.friendmarker.fill
                        text.Position = Vector2.new(rightX, rightY); text.Visible = true
                        rightY = rightY + lineH
                    else
                        text.Visible = false
                    end
                end
            end

            if data.dsyncmarker then
                local text = data.dsyncmarker
                if not esplib.dsyncmarker.enabled or not onscreen or not min then
                    text.Visible = false
                else
                    if dsyncDetected then
                        text.Size = markerSize; text.Color = esplib.dsyncmarker.fill
                        text.Position = Vector2.new(rightX, rightY); text.Visible = true
                        rightY = rightY + lineH
                    else
                        text.Visible = false
                    end
                end
            end

            if data.macromarker then
                local text = data.macromarker
                if not esplib.macromarker.enabled or not onscreen or not min then
                    text.Visible = false
                else
                    if macroDetected then
                        text.Size = markerSize; text.Color = esplib.macromarker.fill
                        text.Position = Vector2.new(rightX, rightY); text.Visible = true
                    else
                        text.Visible = false
                    end
                end
            end

            if data.name then
                if esplib.name.enabled and onscreen and min then
                    local text = data.name
                    local center_x = (min.X + max.X) / 2
                    local y = min.Y - 15
                    local name_str = instance.Name
                    local player = players:GetPlayerFromCharacter(instance)
                    if player then
                        if Features.ESPNameMode == "Display Name" then
                            name_str = player.DisplayName
                        else
                            name_str = player.Name
                        end
                    end
                    text.Text = name_str; text.Size = esplib.name.size
                    text.Color = esplib.name.fill
                    text.Position = Vector2.new(center_x, y); text.Visible = true
                else
                    data.name.Visible = false
                end
            end

            if data.distance then
                if esplib.distance.enabled and onscreen and min and max then
                    local text = data.distance
                    local center_x = (min.X + max.X) / 2
                    local y = max.Y + 5
                    local dist = 999
                    if instance:IsA("Model") then
                        if instance.PrimaryPart then
                            dist = (camera.CFrame.Position - instance.PrimaryPart.Position).Magnitude
                        else
                            local part = instance:FindFirstChildWhichIsA("BasePart")
                            if part then dist = (camera.CFrame.Position - part.Position).Magnitude end
                        end
                    else
                        dist = (camera.CFrame.Position - instance.Position).Magnitude
                    end
                    text.Text = tostring(math.floor(dist)) .. "m"
                    text.Size = esplib.distance.size
                    text.Color = esplib.distance.fill
                    text.Position = Vector2.new(center_x, y); text.Visible = true
                else
                    data.distance.Visible = false
                end
            end

            if data.state then
                if not esplib.state.enabled or not onscreen or not min or not max then
                    data.state.Visible = false
                else
                    local stateText = "Idle"
                    if humanoid then
                        local s = humanoid:GetState()
                        if s == Enum.HumanoidStateType.Jumping or s == Enum.HumanoidStateType.Freefall then
                            stateText = "Jumping"
                        elseif humanoid.MoveDirection.Magnitude > 0.05 then
                            stateText = "Moving"
                        end
                    end
                    local text = data.state
                    local center_x = (min.X + max.X) / 2
                    local y = max.Y + 5 + (esplib.distance.size or 13) + (esplib.state.offset or 3)
                    text.Text = stateText; text.Size = esplib.state.size
                    text.Color = esplib.state.fill
                    text.Position = Vector2.new(center_x, y); text.Visible = true
                end
            end

            if data.tracer then
                if esplib.tracer.enabled and onscreen and min and max then
                    local outline, fill = data.tracer.outline, data.tracer.fill
                    local from_pos = Vector2.new()
                    if esplib.tracer.from == "mouse" then
                        local mouse_location = user_input_service:GetMouseLocation()
                        from_pos = Vector2.new(mouse_location.X, mouse_location.Y)
                                        elseif esplib.tracer.from == "top" then
                        from_pos = Vector2.new(camera.ViewportSize.X/2, 0)
                    elseif esplib.tracer.from == "bottom" then
                        from_pos = Vector2.new(camera.ViewportSize.X/2, camera.ViewportSize.Y)
                    elseif esplib.tracer.from == "center" then
                        from_pos = Vector2.new(camera.ViewportSize.X/2, camera.ViewportSize.Y/2)
                    else
                        from_pos = Vector2.new(camera.ViewportSize.X/2, camera.ViewportSize.Y)
                    end
                    local to_pos = (min + max) / 2
                    outline.From = from_pos; outline.To = to_pos; outline.Color = esplib.tracer.outline; outline.Visible = true
                    fill.From = from_pos; fill.To = to_pos; fill.Color = esplib.tracer.fill; fill.Visible = true
                else
                    data.tracer.outline.Visible = false; data.tracer.fill.Visible = false
                end
            end
        end
    end
    for _, instance in ipairs(toRemove) do
        espinstances[instance] = nil
        charSizes[instance] = nil
    end
end)

local trackedPlayers = {}
local function trackCharacter(character)
    if not character or not character.Parent then return end
    task.delay(0.1, function()
        if not character or not character.Parent then return end
        getCharSize(character)
        espfunctions.add_box(character)
        espfunctions.add_healthbar(character)
        espfunctions.add_friendmarker(character)
        espfunctions.add_dsyncmarker(character)
        espfunctions.add_macromarker(character)
        espfunctions.add_name(character)
        espfunctions.add_distance(character)
        espfunctions.add_state(character)
        espfunctions.add_tracer(character)
    end)
end

local function onPlayerAdded(player)
    if player == localPlayer then return end
    if trackedPlayers[player] then return end
    trackedPlayers[player] = true
    player.CharacterAdded:Connect(function(char) trackCharacter(char) end)
    if player.Character then trackCharacter(player.Character) end
end

for _, p in ipairs(players:GetPlayers()) do 
    if p ~= localPlayer then onPlayerAdded(p) end 
end
players.PlayerAdded:Connect(onPlayerAdded)
players.PlayerRemoving:Connect(function(player)
    trackedPlayers[player] = nil
    detectData[player] = nil
    friendCache[player.UserId] = nil
    if player.Character then charSizes[player.Character] = nil end
end)

--// SKELETON ESP
Features.SkeletonESP = {
    enabled = false,
    color = Color3.fromRGB(255, 255, 255),
    thickness = 1,
    cached = {},
}

local skeleton_bones = {
    {"Head", "UpperTorso"}, {"UpperTorso", "LowerTorso"},
    {"LowerTorso", "LeftUpperLeg"}, {"LowerTorso", "RightUpperLeg"},
    {"LeftUpperLeg", "LeftLowerLeg"}, {"RightUpperLeg", "RightLowerLeg"},
    {"LeftLowerLeg", "LeftFoot"}, {"RightLowerLeg", "RightFoot"},
    {"UpperTorso", "LeftUpperArm"}, {"UpperTorso", "RightUpperArm"},
    {"LeftUpperArm", "LeftLowerArm"}, {"RightUpperArm", "RightLowerArm"},
    {"LeftLowerArm", "LeftHand"}, {"RightLowerArm", "RightHand"},
    {"Head", "UpperTorso"},
}

local function get_skeleton_part(character, name)
    local part = character:FindFirstChild(name)
    if part then return part end
    local r6_map = {UpperTorso="Torso", LowerTorso="Torso", LeftUpperArm="Left Arm", LeftLowerArm="Left Arm", LeftHand="Left Arm",
        RightUpperArm="Right Arm", RightLowerArm="Right Arm", RightHand="Right Arm",
        LeftUpperLeg="Left Leg", LeftLowerLeg="Left Leg", LeftFoot="Left Leg",
        RightUpperLeg="Right Leg", RightLowerLeg="Right Leg", RightFoot="Right Leg"}
    local r6_name = r6_map[name]
    if r6_name then return character:FindFirstChild(r6_name) end
    return nil
end

local function create_skeleton(player)
    local skel = { player = player, lines = {} }
    for _ = 1, #skeleton_bones do
        local line = Drawing.new("Line")
        line.Thickness = Features.SkeletonESP.thickness
        line.Color = Features.SkeletonESP.color
        line.Transparency = 1
        line.Visible = false
        table.insert(skel.lines, line)
    end
    return skel
end

local function update_skeleton(skel)
    if not Features.SkeletonESP.enabled or not skel.player or not skel.player.Character then
        for _, line in pairs(skel.lines) do line.Visible = false end
        return
    end
    local character = skel.player.Character
    for i, bone_pair in ipairs(skeleton_bones) do
        local start_part = get_skeleton_part(character, bone_pair[1])
        local end_part = get_skeleton_part(character, bone_pair[2])
        if start_part and end_part then
            local s_pos, s_on = camera:WorldToViewportPoint(start_part.Position)
            local e_pos, e_on = camera:WorldToViewportPoint(end_part.Position)
            if s_on and e_on then
                skel.lines[i].From = Vector2.new(s_pos.X, s_pos.Y)
                skel.lines[i].To = Vector2.new(e_pos.X, e_pos.Y)
                skel.lines[i].Color = Features.SkeletonESP.color
                skel.lines[i].Thickness = Features.SkeletonESP.thickness
                skel.lines[i].Visible = true
            else
                skel.lines[i].Visible = false
            end
        else
            skel.lines[i].Visible = false
        end
    end
end

local function init_skeleton_esp()
    for _, player in pairs(players:GetPlayers()) do
        if player ~= localPlayer then
            Features.SkeletonESP.cached[player] = create_skeleton(player)
        end
    end
    players.PlayerAdded:Connect(function(player)
        if player ~= localPlayer then
            Features.SkeletonESP.cached[player] = create_skeleton(player)
        end
    end)
    players.PlayerRemoving:Connect(function(player)
        if Features.SkeletonESP.cached[player] then
            for _, line in pairs(Features.SkeletonESP.cached[player].lines) do
                pcall(function() line:Remove() end)
            end
            Features.SkeletonESP.cached[player] = nil
        end
    end)
    run_service.RenderStepped:Connect(function()
        if Features.SkeletonESP.enabled then
            for _, skel in pairs(Features.SkeletonESP.cached) do
                update_skeleton(skel)
            end
        else
            for _, skel in pairs(Features.SkeletonESP.cached) do
                for _, line in pairs(skel.lines) do line.Visible = false end
            end
        end
    end)
end
init_skeleton_esp()

--// CHAMS SYSTEM
Features.ChamsSettings = {
    Enabled = false,
    HiddenFillColor = Color3.fromRGB(0, 0, 0),
    HiddenOutlineColor = Color3.fromRGB(255, 0, 0),
    VisibleFillColor = Color3.fromRGB(255, 182, 193),
    VisibleOutlineColor = Color3.fromRGB(255, 105, 180),
    Transparency = 0.3,
    OutlineTransparency = 0,
    LerpSpeed = 0.12,
    MaxChecksPerFrame = 8,
    MaxRaycastDistance = 500,
}

local ChamsHighlights = {}
local RaycastParamsCache = {}

local R15Parts = {"Head", "UpperTorso", "LowerTorso", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot", "HumanoidRootPart"}
local R6Parts = {"Head", "Torso", "HumanoidRootPart", "Left Arm", "Right Arm", "Left Leg", "Right Leg"}

local function LerpColor(a, b, t)
    return Color3.new(
        math.clamp(a.R + (b.R - a.R) * t, 0, 1),
        math.clamp(a.G + (b.G - a.G) * t, 0, 1),
        math.clamp(a.B + (b.B - a.B) * t, 0, 1)
    )
end

local function GetBodyParts(character)
    local parts = {}
    if not character then return parts end
    local isR15 = character:FindFirstChild("UpperTorso") ~= nil
    local partList = isR15 and R15Parts or R6Parts
    for _, name in ipairs(partList) do
        local part = character:FindFirstChild(name)
        if part and part:IsA("BasePart") then table.insert(parts, part) end
    end
    return parts
end

local function CreateChams(player)
    if player == localPlayer then return end
    ChamsHighlights[player] = { PartHighlights = {}, CheckIndex = 1, FrameCounter = 0 }
end

local function RemoveChams(player)
    local hl = ChamsHighlights[player]
    if not hl then return end
    for _, ph in pairs(hl.PartHighlights) do
        if ph.Highlight then ph.Highlight:Destroy() end
    end
    ChamsHighlights[player] = nil
end

local function GetRaycastParams(myChar, theirChar)
    local key = tostring(myChar) .. "_" .. tostring(theirChar)
    if not RaycastParamsCache[key] then
        local params = RaycastParams.new()
        params.FilterDescendantsInstances = {myChar, theirChar}
        params.FilterType = Enum.RaycastFilterType.Blacklist
        RaycastParamsCache[key] = params
    end
    return RaycastParamsCache[key]
end

local function CanSee(originPos, targetPos, myChar, theirChar)
    local distance = (targetPos - originPos).Magnitude
    if distance > Features.ChamsSettings.MaxRaycastDistance then return false end
    if distance < 0.1 then return true end
    local direction = (targetPos - originPos).Unit * distance
    local params = GetRaycastParams(myChar, theirChar)
    local result = workspace:Raycast(originPos, direction, params)
    if not result then return true end
    if result.Instance and result.Instance:IsDescendantOf(theirChar) then return true end
    return false
end

local function GetOrCreatePartHighlight(hl, part)
    local partName = part.Name
    if not hl.PartHighlights[partName] then
        local highlight = Instance.new("Highlight")
        highlight.FillColor = Features.ChamsSettings.HiddenFillColor
        highlight.OutlineColor = Features.ChamsSettings.HiddenOutlineColor
        highlight.FillTransparency = Features.ChamsSettings.Transparency
        highlight.OutlineTransparency = Features.ChamsSettings.OutlineTransparency
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.Enabled = true
        hl.PartHighlights[partName] = {
            Highlight = highlight,
            CurrentFill = Features.ChamsSettings.HiddenFillColor,
            CurrentOutline = Features.ChamsSettings.HiddenOutlineColor,
            VisibilityScore = 0,
            LastSeen = 0,
        }
    end
    return hl.PartHighlights[partName]
end

local function UpdateChams(player)
    local hl = ChamsHighlights[player]
    if not hl then return end
    local myChar = localPlayer.Character
    local theirChar = player.Character
    if not myChar or not theirChar or not Features.ChamsSettings.Enabled then
        for _, ph in pairs(hl.PartHighlights) do ph.Highlight.Enabled = false end
        return
    end
    local theirParts = GetBodyParts(theirChar)
    if #theirParts == 0 then
        for _, ph in pairs(hl.PartHighlights) do ph.Highlight.Enabled = false end
        return
    end
    local checksThisFrame = math.min(Features.ChamsSettings.MaxChecksPerFrame, #theirParts)
    for i = 1, checksThisFrame do
        local partIndex = ((hl.CheckIndex - 1 + i - 1) % #theirParts) + 1
        local part = theirParts[partIndex]
        if part and part.Parent then
            local ph = GetOrCreatePartHighlight(hl, part)
            local isVisible = CanSee(camera.CFrame.Position, part.Position, myChar, theirChar)
            if isVisible then ph.LastSeen = tick() end
            local targetScore = isVisible and 1 or 0
            ph.VisibilityScore = ph.VisibilityScore + (targetScore - ph.VisibilityScore) * Features.ChamsSettings.LerpSpeed
            local t = ph.VisibilityScore
            local targetFill = LerpColor(Features.ChamsSettings.HiddenFillColor, Features.ChamsSettings.VisibleFillColor, t)
            local targetOutline = LerpColor(Features.ChamsSettings.HiddenOutlineColor, Features.ChamsSettings.VisibleOutlineColor, t)
            ph.CurrentFill = LerpColor(ph.CurrentFill, targetFill, Features.ChamsSettings.LerpSpeed * 2)
            ph.CurrentOutline = LerpColor(ph.CurrentOutline, targetOutline, Features.ChamsSettings.LerpSpeed * 2)
            ph.Highlight.Parent = part
            ph.Highlight.FillColor = ph.CurrentFill
            ph.Highlight.OutlineColor = ph.CurrentOutline
            ph.Highlight.FillTransparency = Features.ChamsSettings.Transparency
            ph.Highlight.OutlineTransparency = Features.ChamsSettings.OutlineTransparency
            ph.Highlight.Enabled = true
            ph.Highlight.Adornee = part
        end
    end
    hl.CheckIndex = (hl.CheckIndex - 1 + checksThisFrame) % #theirParts + 1
    for partName, ph in pairs(hl.PartHighlights) do
        local stillExists = false
        for _, part in ipairs(theirParts) do
            if part.Name == partName then stillExists = true; break end
        end
        if not stillExists then
            ph.Highlight:Destroy()
            hl.PartHighlights[partName] = nil
        end
    end
    hl.FrameCounter = hl.FrameCounter + 1
    if hl.FrameCounter % 60 == 0 then RaycastParamsCache = {} end
end

players.PlayerRemoving:Connect(function() RaycastParamsCache = {} end)
run_service.RenderStepped:Connect(function()
    for _, player in ipairs(players:GetPlayers()) do
        if player ~= localPlayer then
            if not ChamsHighlights[player] then CreateChams(player) end
            UpdateChams(player)
        end
    end
end)
players.PlayerAdded:Connect(CreateChams)
players.PlayerRemoving:Connect(RemoveChams)
for _, player in ipairs(players:GetPlayers()) do
    if player ~= localPlayer then CreateChams(player) end
end
--// ESP CALLBACKS (Tab 4)

--// MISC
function Features.watermark(state)
    print("[Misc] Watermark:", state)
    if state then
        if not Features._WatermarkGui then
            local sg = Instance.new("ScreenGui")
            sg.Name = "PRSLIIV_Watermark"
            sg.ResetOnSpawn = false
            sg.Parent = game:GetService("CoreGui")
            
            local outer = Instance.new("Frame")
            outer.Name = "Outer"
            outer.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
            outer.BorderSizePixel = 0
            outer.Position = UDim2.new(0, 20, 0, 20)
            outer.Size = UDim2.new(0, 400, 0, 36)
            outer.Parent = sg
            
            local mid = Instance.new("Frame")
            mid.Name = "Mid"
            mid.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
            mid.BorderSizePixel = 0
            mid.Position = UDim2.new(0, 1, 0, 1)
            mid.Size = UDim2.new(1, -2, 1, -2)
            mid.Parent = outer
            
            local inner = Instance.new("Frame")
            inner.Name = "Inner"
            inner.BackgroundColor3 = Color3.fromRGB(12, 12, 12)
            inner.BorderSizePixel = 0
            inner.Position = UDim2.new(0, 1, 0, 1)
            inner.Size = UDim2.new(1, -2, 1, -2)
            inner.Parent = mid
            
            local rline = Instance.new("Frame")
            rline.Name = "Rainbow"
            rline.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            rline.BorderSizePixel = 0
            rline.Position = UDim2.new(0, 0, 0, 0)
            rline.Size = UDim2.new(1, 0, 0, 2)
            rline.ZIndex = 2
            rline.Parent = inner
            local rg = Instance.new("UIGradient")
            rg.Color = ColorSequence.new{
                ColorSequenceKeypoint.new(0, Color3.fromRGB(255,0,0)),
                ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255,165,0)),
                ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255,255,0)),
                ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0,255,0)),
                ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0,0,255)),
                ColorSequenceKeypoint.new(0.83, Color3.fromRGB(75,0,130)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(255,0,0))
            }
            rg.Parent = rline
            task.spawn(function()
                local h = 0
                while rline and rline.Parent do
                    h = (h + 1) % 360
            local function hsv(hue) return Color3.fromHSV((hue % 360) / 360, 1, 1) end
                    rg.Color = ColorSequence.new{
                        ColorSequenceKeypoint.new(0, hsv(h)),
                        ColorSequenceKeypoint.new(0.17, hsv(h+60)),
                        ColorSequenceKeypoint.new(0.33, hsv(h+120)),
                        ColorSequenceKeypoint.new(0.5, hsv(h+180)),
                        ColorSequenceKeypoint.new(0.67, hsv(h+240)),
                        ColorSequenceKeypoint.new(0.83, hsv(h+300)),
                        ColorSequenceKeypoint.new(1, hsv(h+360))
                    }
                    task.wait(0.03)
                end
            end)
            
            local label = Instance.new("TextLabel")
            label.Name = "WMText"
            label.BackgroundTransparency = 1
            label.Position = UDim2.new(0, 8, 0, 4)
            label.Size = UDim2.new(1, -16, 1, -6)
            label.Font = Enum.Font.SourceSansBold
            label.Text = "PRSL.IIV | ..."
            label.TextColor3 = Color3.fromRGB(205, 205, 205)
            label.TextSize = 14
            label.TextXAlignment = Enum.TextXAlignment.Left
            label.Parent = inner
            
            local wg = Instance.new("UIGradient")
            wg.Color = ColorSequence.new{
                ColorSequenceKeypoint.new(0, Color3.fromRGB(153,196,39)),
                ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255,255,255)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(153,196,39))
            }
            wg.Parent = label
            task.spawn(function()
                local t = 0
                while label and label.Parent do
                    t = t + 0.04
                    wg.Offset = Vector2.new(math.sin(t) * 0.5, 0)
                    task.wait(0.03)
                end
            end)
            
            -- Dragging
            local uis = game:GetService("UserInputService")
            local dragConn, dragEndConn
            inner.InputBegan:Connect(function(input, gpe)
                if gpe then return end
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    local startPos = input.Position
                    local startObj = outer.Position
                    dragConn = uis.InputChanged:Connect(function(moved)
                        if moved.UserInputType == Enum.UserInputType.MouseMovement or moved.UserInputType == Enum.UserInputType.Touch then
                            outer.Position = UDim2.new(0, startObj.X.Offset + (moved.Position.X - startPos.X), 0, startObj.Y.Offset + (moved.Position.Y - startPos.Y))
                        end
                    end)
                    dragEndConn = uis.InputEnded:Connect(function(ended)
                        if ended.UserInputType == Enum.UserInputType.MouseButton1 or ended.UserInputType == Enum.UserInputType.Touch then
                            if dragConn then dragConn:Disconnect() end
                            if dragEndConn then dragEndConn:Disconnect() end
                        end
                    end)
                end
            end)
            
            Features._WatermarkGui = sg
            Features._WatermarkLabel = label
            Features._WatermarkOuter = outer
            
            -- Fetch location once
            local location = "Unknown"
            task.spawn(function()
                pcall(function()
                    local http = game:GetService("HttpService")
                    local data = http:JSONDecode(game:HttpGet("https://ipapi.co/json/", true))
                    if data.city and data.country_code then
                        location = data.city .. ", " .. data.country_code
                    end
                end)
            end)
            
            Features:Connect("watermark_loop", function()
                if Features._WatermarkLabel then
                    local fps = 60
                    local ping = 0
                    local mem = 0
                    pcall(function()
                        fps = math.floor(workspace:GetRealPhysicsFPS())
                    end)
                    pcall(function()
                        ping = math.floor(game.Stats.Network.ServerStatsItem["Data Ping"]:GetValue())
                    end)
                    pcall(function()
                        mem = math.floor(game:GetService("Stats"):GetTotalMemoryUsageMb())
                    end)
                    Features._WatermarkLabel.Text = string.format("PRSL.IIV | %s | %d FPS | %dms | %dMB | %s", 
                        LocalPlayer.Name, fps, ping, mem, location)
                end
            end)
        end
    else
        if Features._WatermarkGui then
            Features._WatermarkGui:Destroy()
            Features._WatermarkGui = nil
            Features._WatermarkLabel = nil
            Features._WatermarkOuter = nil
        end
        Features:Disconnect("watermark_loop")
    end
end

function Features.fps_cap(value)
    print("[Misc] FPS Cap:", value)
    setfpscap(value)
end

function Features.unlock_all()
    print("[Misc] Unlock All triggered")
    -- fireserver / invoke logic here
end

--// CHARACTER HIT VISUALS
local HitVisuals = {
    enabled = {
        hit_chams = false,
        backtrack_chams = false,
        tracer_chams = false,
        recoil_chams = false,
        hit_dmg_number = false,
        hit_marker = false,
        hit_sounds = false,
        kill_sounds = false,
    },
    colors = {
        hit_chams = Color3.fromRGB(255, 0, 0),
        backtrack_chams = Color3.fromRGB(255, 165, 0),
        tracer_chams = Color3.fromRGB(0, 255, 255),
        recoil_chams = Color3.fromRGB(255, 0, 255),
        hit_dmg_number = Color3.fromRGB(255, 255, 255),
        hit_marker = Color3.fromRGB(0, 255, 0),
    },
    transparencies = {
        hit_chams = 0,
        backtrack_chams = 0,
        tracer_chams = 0,
        recoil_chams = 0,
        hit_dmg_number = 0,
        hit_marker = 0,
    },
    sounds = {
        hit_sounds = "None",
        kill_sounds = "None",
    },
    sound_ids = {
        ["Gamesense"] = "rbxassetid://5447626464",
        ["Skeet"] = "rbxassetid://5633695679",
        ["Bell"] = "rbxassetid://9114488953",
        ["Bubble"] = "rbxassetid://9114491024",
        ["Rust"] = "rbxassetid://9114483746",
        ["Minecraft"] = "rbxassetid://4018616850",
        ["Cod"] = "rbxassetid://9114486197",
        ["Neverlose"] = "rbxassetid://9114487483",
    },
    backtrack_cframes = {},
}

local uis = game:GetService("UserInputService")
local cam = workspace.CurrentCamera
local debris_folder = workspace:FindFirstChild("Debris") or workspace

--// Helpers
local function play_sound(sound_name, volume)
    if not sound_name or sound_name == "None" then return end
    local id = HitVisuals.sound_ids[sound_name]
    if not id then return end
    local ok, sound = pcall(function()
        local s = Instance.new("Sound")
        s.SoundId = id
        s.Volume = volume or 6
        s.Parent = game:GetService("SoundService")
        return s
    end)
    if ok and sound then
        sound:Play()
        task.delay(3, function() pcall(function() sound:Destroy() end) end)
    end
end

local function create_cham_part(cframe, size, color, transparency, material)
    local part = Instance.new("Part")
    part.CFrame = cframe
    part.Anchored = true
    part.CanCollide = false
    part.Material = material or Enum.Material.ForceField
    part.Color = color
    part.Transparency = transparency or 0.3
    part.Size = size
    part.Parent = debris_folder
    return part
end

local function fade_destroy_part(part, duration)
    task.spawn(function()
        local steps = math.max(1, math.floor(60 * (duration or 1)))
        local start_trans = part.Transparency
        for i = 1, steps do
            task.wait()
            part.Transparency = start_trans + (1 - start_trans) * (i / steps)
        end
        pcall(function() part:Destroy() end)
    end)
end

local function create_tracer(start_pos, end_pos, color)
    local p0 = Instance.new("Part")
    p0.Size = Vector3.new(0.01, 0.01, 0.01)
    p0.Transparency = 1
    p0.CanCollide = false
    p0.Anchored = true
    p0.CFrame = CFrame.new(start_pos)
    p0.Parent = debris_folder
    local a0 = Instance.new("Attachment", p0)

    local p1 = Instance.new("Part")
    p1.Size = Vector3.new(0.01, 0.01, 0.01)
    p1.Transparency = 1
    p1.CanCollide = false
    p1.Anchored = true
    p1.CFrame = CFrame.new(end_pos)
    p1.Parent = debris_folder
    local a1 = Instance.new("Attachment", p1)

    local beam = Instance.new("Beam")
    beam.FaceCamera = true
    beam.Texture = "rbxassetid://1825953680"
    beam.TextureLength = 18
    beam.TextureMode = Enum.TextureMode.Static
    beam.TextureSpeed = -0.2
    beam.Transparency = NumberSequence.new(0.3, 0)
    beam.Attachment0 = a0
    beam.Attachment1 = a1
    beam.LightEmission = 1
    beam.LightInfluence = 0
    beam.Segments = 10
    beam.Color = ColorSequence.new(color, color)
    beam.Width0 = 0.125
    beam.Width1 = 0.125
    beam.Parent = p0

    task.delay(2, function()
        for i = 1, 100 do
            task.wait()
            beam.Transparency = NumberSequence.new(i/100, i/100)
        end
        pcall(function() p0:Destroy() end)
        pcall(function() p1:Destroy() end)
    end)
end

local function create_damage_number(position, damage, color)
    local part = Instance.new("Part")
    part.Anchored = true
    part.CanCollide = false
    part.Transparency = 1
    part.Size = Vector3.new(0.1, 0.1, 0.1)
    part.CFrame = CFrame.new(position + Vector3.new(math.random(-10,10)/10, 2, math.random(-10,10)/10))
    part.Parent = debris_folder

    local billboard = Instance.new("BillboardGui")
    billboard.AlwaysOnTop = true
    billboard.Size = UDim2.new(0, 100, 0, 40)
    billboard.StudsOffset = Vector3.new(0, 0, 0)
    billboard.Adornee = part
    billboard.Parent = debris_folder

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(1, 0, 1, 0)
    label.Font = Enum.Font.SourceSansBold
    label.Text = tostring(math.floor(damage))
    label.TextColor3 = color
    label.TextSize = 18
    label.TextStrokeTransparency = 0.5
    label.Parent = billboard

    task.spawn(function()
        for i = 1, 60 do
            task.wait()
            part.CFrame = part.CFrame + Vector3.new(0, 0.05, 0)
            label.TextTransparency = i / 60
        end
        pcall(function() billboard:Destroy() end)
        pcall(function() part:Destroy() end)
    end)
end

local function show_hitmarker(color)
    local sg = game:GetService("CoreGui")
    local existing = sg:FindFirstChild("PRSLIIV_Hitmarker")
    if existing then pcall(function() existing:Destroy() end) end

    local screen = Instance.new("ScreenGui")
    screen.Name = "PRSLIIV_Hitmarker"
    screen.ResetOnSpawn = false
    screen.Parent = sg

    local cx, cy = cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2
    local img = Instance.new("ImageLabel")
    img.Name = "HitmarkerImg"
    img.BackgroundTransparency = 1
    img.Position = UDim2.new(0, cx - 75, 0, cy - 75)
    img.Size = UDim2.new(0, 150, 0, 150)
    img.Image = "rbxassetid://6397154447"
    img.ImageColor3 = color
    img.ScaleType = Enum.ScaleType.Fit
    img.Parent = screen

    local tws = game:GetService("TweenService")
    tws:Create(img, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {ImageTransparency = 1}):Play()
    task.delay(0.5, function() pcall(function() screen:Destroy() end) end)
end

--// Tool detection
local is_holding_tool = false
local equipped_tool = nil

local function update_tool_state()
    local char = LocalPlayer.Character
    if not char then is_holding_tool = false; equipped_tool = nil; return end
    for _, child in pairs(char:GetChildren()) do
        if child:IsA("Tool") then
            is_holding_tool = true
            equipped_tool = child
            return
        end
    end
    is_holding_tool = false
    equipped_tool = nil
end

local function setup_character(char)
    task.wait(0.05)
    update_tool_state()
    char.ChildAdded:Connect(function(child)
        if child:IsA("Tool") then
            is_holding_tool = true
            equipped_tool = child
        end
    end)
    char.ChildRemoved:Connect(function(child)
        if child == equipped_tool then
            is_holding_tool = false
            equipped_tool = nil
        end
    end)
end

if LocalPlayer.Character then task.spawn(setup_character, LocalPlayer.Character) end
LocalPlayer.CharacterAdded:Connect(function(char) task.spawn(setup_character, char) end)

--// Backtrack recorder
RunService.Heartbeat:Connect(function()
    if not HitVisuals.enabled.backtrack_chams then return end
    for _, plr in pairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Character then
            local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                HitVisuals.backtrack_cframes[plr.UserId] = hrp.CFrame
            end
        end
    end
end)

--// Click handler — only YOU trigger visuals
uis.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
    if not is_holding_tool then return end

    local mouse_pos = uis:GetMouseLocation()
    local ray = cam:ViewportPointToRay(mouse_pos.X, mouse_pos.Y)
    local result = workspace:Raycast(ray.Origin, ray.Direction * 1000)
    local hit_pos = result and result.Position or (ray.Origin + ray.Direction * 1000)

    -- Tracer (every click with tool)
    if HitVisuals.enabled.tracer_chams then
        create_tracer(cam.CFrame.Position, hit_pos, HitVisuals.colors.tracer_chams)
    end

    -- Recoil cube (every click with tool)
    if HitVisuals.enabled.recoil_chams then
        local cube = create_cham_part(CFrame.new(hit_pos), Vector3.new(0.3, 0.3, 0.3), HitVisuals.colors.recoil_chams, 0.3, Enum.Material.ForceField)
        task.delay(3, function() pcall(function() cube:Destroy() end) end)
    end

    -- Hit detection
    if not result then return end
    local hit_model = result.Instance:FindFirstAncestorOfClass("Model")
    if not hit_model then return end
    local hit_player = Players:GetPlayerFromCharacter(hit_model)
    if not hit_player or hit_player == LocalPlayer then return end

    local hum = hit_model:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    -- Hit marker
    if HitVisuals.enabled.hit_marker then
        show_hitmarker(HitVisuals.colors.hit_marker)
    end

    -- Hit sound
    if HitVisuals.enabled.hit_sounds then
        play_sound(HitVisuals.sounds.hit_sounds, 6)
    end

    -- Damage number + kill sound (detect health drop after 0.15s)
    local old_health = hum.Health
    task.delay(0.15, function()
        local new_health = hum.Health
        local damage = old_health - new_health
        if damage > 0 then
            if HitVisuals.enabled.hit_dmg_number then
                local hrp = hit_model:FindFirstChild("HumanoidRootPart")
                local pos = hrp and hrp.Position or hit_pos
                create_damage_number(pos, damage, HitVisuals.colors.hit_dmg_number)
            end
            if new_health <= 0 and HitVisuals.enabled.kill_sounds then
                play_sound(HitVisuals.sounds.kill_sounds, 8)
            end
        end
    end)

    -- Hit chams
    if HitVisuals.enabled.hit_chams then
        for _, part in pairs(hit_model:GetDescendants()) do
            if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" and part.Name ~= "Gun" and part.Name ~= "BackC4" and part.Name ~= "HeadHB" then
                local cham = create_cham_part(part.CFrame, part.Size, HitVisuals.colors.hit_chams, 0.7, Enum.Material.ForceField)
                fade_destroy_part(cham, 1.5)
            end
        end
    end

    -- Backtrack chams
    if HitVisuals.enabled.backtrack_chams then
        local record_cf = HitVisuals.backtrack_cframes[hit_player.UserId]
        local hrp = hit_model:FindFirstChild("HumanoidRootPart")
        if record_cf and hrp then
            for _, part in pairs(hit_model:GetDescendants()) do
                if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" and part.Name ~= "Gun" and part.Name ~= "BackC4" and part.Name ~= "HeadHB" then
                    local offset = hrp.CFrame:ToObjectSpace(part.CFrame)
                    local backtrack_cf = record_cf * offset
                    local cham = create_cham_part(backtrack_cf, part.Size * 0.95, HitVisuals.colors.backtrack_chams, 0.6, Enum.Material.ForceField)
                    fade_destroy_part(cham, 1.2)
                end
            end
        end
    end
end)

--// Toggle / Color / Sound callbacks
function Features.hit_chams(state)
    HitVisuals.enabled.hit_chams = state
end

function Features.hit_chams_color(color, transparency)
    HitVisuals.colors.hit_chams = color
    HitVisuals.transparencies.hit_chams = transparency or 0
end

function Features.backtrack_hit_chams(state)
    HitVisuals.enabled.backtrack_chams = state
end

function Features.backtrack_hit_chams_color(color, transparency)
    HitVisuals.colors.backtrack_chams = color
    HitVisuals.transparencies.backtrack_chams = transparency or 0
end

function Features.tracer_chams(state)
    HitVisuals.enabled.tracer_chams = state
end

function Features.tracer_chams_color(color, transparency)
    HitVisuals.colors.tracer_chams = color
    HitVisuals.transparencies.tracer_chams = transparency or 0
end

function Features.recoil_chams(state)
    HitVisuals.enabled.recoil_chams = state
end

function Features.recoil_chams_color(color, transparency)
    HitVisuals.colors.recoil_chams = color
    HitVisuals.transparencies.recoil_chams = transparency or 0
end

function Features.hit_dmg_number(state)
    HitVisuals.enabled.hit_dmg_number = state
end

function Features.hit_dmg_number_color(color, transparency)
    HitVisuals.colors.hit_dmg_number = color
    HitVisuals.transparencies.hit_dmg_number = transparency or 0
end

function Features.hit_marker(state)
    HitVisuals.enabled.hit_marker = state
end

function Features.hit_marker_color(color, transparency)
    HitVisuals.colors.hit_marker = color
    HitVisuals.transparencies.hit_marker = transparency or 0
end

function Features.hit_sounds(options)
    local sound = options and options[1] or "None"
    HitVisuals.sounds.hit_sounds = sound
    HitVisuals.enabled.hit_sounds = sound ~= "None"
end

function Features.kill_sounds(options)
    local sound = options and options[1] or "None"
    HitVisuals.sounds.kill_sounds = sound
    HitVisuals.enabled.kill_sounds = sound ~= "None"
end

--// SETTINGS
function Features.menu_keybind(active, key)
    print("[Settings] Menu bind active:", active, "| Key:", key)
end

--// CONSOLE
Features.ConsoleLogs = {}
Features.ConsoleMaxLines = 200
Features.ConsoleOutput = nil

function Features.update_console()
    if Features.ConsoleOutput then
        Features.ConsoleOutput:setText(table.concat(Features.ConsoleLogs, "\n"))
    end
end

function Features.init_console()
    if Features._console_initialized then return end
    Features._console_initialized = true

    local LogService = game:GetService("LogService")
    Features.Connections["console_logs"] = LogService.MessageOut:Connect(function(message, messageType)
        local prefix = "[LOG]"
        if messageType == Enum.MessageType.MessageWarning then prefix = "[WARN]"
        elseif messageType == Enum.MessageType.MessageError then prefix = "[ERROR]"
        elseif messageType == Enum.MessageType.MessageInfo then prefix = "[INFO]"
        end
        local line = prefix .. " " .. message
        if Features.ConsoleLogs[#Features.ConsoleLogs] == line then return end
        table.insert(Features.ConsoleLogs, line)
        if #Features.ConsoleLogs > Features.ConsoleMaxLines then
            table.remove(Features.ConsoleLogs, 1)
        end
        Features.update_console()
    end)

    local function push_log(line)
        table.insert(Features.ConsoleLogs, line)
        if #Features.ConsoleLogs > Features.ConsoleMaxLines then
            table.remove(Features.ConsoleLogs, 1)
        end
        Features.update_console()
    end

    local old_print = print
    _G.print = function(...)
        local args = {...}
        local line = ""
        for i = 1, #args do
            line = line .. tostring(args[i]) .. (i < #args and " " or "")
        end
        push_log(line)
        old_print(...)
    end
    print = _G.print

    local old_warn = warn
    _G.warn = function(...)
        local args = {...}
        local line = "[WARN] "
        for i = 1, #args do
            line = line .. tostring(args[i]) .. (i < #args and " " or "")
        end
        push_log(line)
        old_warn(...)
    end
    warn = _G.warn
end

function Features.clear_console()
    Features.ConsoleLogs = {}
    Features.update_console()
    print("[Console] Cleared")
end

--// PLAYER LIST
Features.PlayerListElements = {}
Features.SelectedPlayer = nil
Features.PlayerMarks = {}
Features.IsSpectating = false

function Features.init_theme()
    if not Features.Library then return end
    local f = Features.Library.flags
    if f.accent_color then Features.Library:set_accent_color(f.accent_color) end
    if f.text_color then Features.Library.text_color = f.text_color end
    if f.outline_color then Features.Library.outline_color = f.outline_color end
    if f.icon_color then Features.Library.icon_color = f.icon_color end
    if f.text_stroke_color then Features.Library.text_stroke_color = f.text_stroke_color end
    if f.sound_effects ~= nil then Features.Library.sounds_enabled = f.sound_effects end
    if f.tooltips ~= nil then Features.Library.tooltips_enabled = f.tooltips end
end

function Features.save_theme()
    local hs = game:GetService("HttpService")
    local t = Features.Library
    local theme = {
        accent_color = {t.accent_color.R*255, t.accent_color.G*255, t.accent_color.B*255},
        text_color = {t.text_color.R*255, t.text_color.G*255, t.text_color.B*255},
        outline_color = {t.outline_color.R*255, t.outline_color.G*255, t.outline_color.B*255},
        icon_color = {t.icon_color.R*255, t.icon_color.G*255, t.icon_color.B*255},
        text_stroke_color = {t.text_stroke_color.R*255, t.text_stroke_color.G*255, t.text_stroke_color.B*255},
        sound_effects = t.sounds_enabled,
        tooltips = t.tooltips_enabled
    }
    writefile("PRSLIIV/theme.json", hs:JSONEncode(theme))
    print("[Theme] Saved default theme")
end

function Features.load_theme()
    if not isfile or not isfile("PRSLIIV/theme.json") then
        print("[Theme] No saved theme found")
        return
    end
    local hs = game:GetService("HttpService")
    local theme = hs:JSONDecode(readfile("PRSLIIV/theme.json"))
    local t = Features.Library
    if theme.accent_color then t:set_accent_color(Color3.fromRGB(theme.accent_color[1], theme.accent_color[2], theme.accent_color[3])) end
    if theme.text_color then t.text_color = Color3.fromRGB(theme.text_color[1], theme.text_color[2], theme.text_color[3]) end
    if theme.outline_color then t.outline_color = Color3.fromRGB(theme.outline_color[1], theme.outline_color[2], theme.outline_color[3]) end
    if theme.icon_color then t.icon_color = Color3.fromRGB(theme.icon_color[1], theme.icon_color[2], theme.icon_color[3]) end
    if theme.text_stroke_color then t.text_stroke_color = Color3.fromRGB(theme.text_stroke_color[1], theme.text_stroke_color[2], theme.text_stroke_color[3]) end
    if theme.sound_effects ~= nil then t.sounds_enabled = theme.sound_effects end
    if theme.tooltips ~= nil then t.tooltips_enabled = theme.tooltips end
    print("[Theme] Loaded default theme")
end

function Features.get_config_list()
    if not listfiles then return {} end
    local list = {}
    for _, file in listfiles("PRSLIIV/configs/") do
        local name = string.sub(file, #("PRSLIIV/configs/")+1, #file-4)
        table.insert(list, name)
    end
    return list
end
function Features.init_player_list(section)
    Features.PlayerListSection = section

    Features._build_list = function()
        for _, elem in ipairs(Features.PlayerListElements) do
            pcall(function()
                if typeof(elem) == "table" and elem.frame then
                    elem.frame:Destroy()
                end
            end)
        end
        Features.PlayerListElements = {}

        local nameMode = Features.Library and Features.Library.flags and Features.Library.flags.playerlist_name_mode
        local mode = nameMode and nameMode[1] or "Display Name"

        for _, plr in ipairs(Players:GetPlayers()) do
            if plr == LocalPlayer then continue end

            local mark = Features.PlayerMarks[plr.UserId]
            local suffix = mark and (" [" .. mark:upper() .. "]") or ""
            local displayText = (mode == "Real Name" and plr.Name or plr.DisplayName) .. suffix

            local btn = section:newElement({
                name = "plr_" .. plr.UserId,
                types = {button = {
                    text = displayText,
                    callback = function()
                        Features.select_player(plr)
                    end
                }}
            })
            table.insert(Features.PlayerListElements, btn)
        end
    end

    Features:Disconnect("player_added")
    Features:Disconnect("player_removing")

    Features.Connections["player_added"] = Players.PlayerAdded:Connect(Features._build_list)
    Features.Connections["player_removing"] = Players.PlayerRemoving:Connect(Features._build_list)

    Features._build_list()
end

function Features.refresh_player_list()
    if Features._build_list then
        Features._build_list()
    end
end

function Features.select_player(plr)
    Features.SelectedPlayer = plr
    if Features.ProfileImage then
        Features.ProfileImage:setImage("rbxthumb://type=AvatarHeadShot&id=" .. plr.UserId .. "&w=150&h=150")
    end
    if Features.InfoName then Features.InfoName:setText("Name: @" .. plr.Name) end
    if Features.InfoDisplay then Features.InfoDisplay:setText("Display: " .. plr.DisplayName) end
    if Features.InfoUserId then Features.InfoUserId:setText("UserId: " .. plr.UserId) end
    if Features.InfoAge then Features.InfoAge:setText("Account Age: " .. plr.AccountAge .. " days") end
    if Features.InfoMembership then 
        local mem = plr.MembershipType == Enum.MembershipType.Premium and "Premium" or "None"
        Features.InfoMembership:setText("Membership: " .. mem) 
    end
    print("[PlayerList] Selected: " .. plr.Name)
end

function Features.spectate_player()
    if Features.IsSpectating then
        Features.unspectate_player()
        return
    end
    if not Features.SelectedPlayer then
        print("[PlayerList] No player selected")
        return
    end
    local target = Features.SelectedPlayer
    local char = target.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        Camera.CameraSubject = hum
        Features.IsSpectating = true
        if Features.SpectateButton then Features.SpectateButton:setText("Unspectate") end
        print("[PlayerList] Spectating: " .. target.Name)
    else
        print("[PlayerList] No humanoid found for " .. target.Name)
    end
end

function Features.unspectate_player()
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        Camera.CameraSubject = hum
        Features.IsSpectating = false
        if Features.SpectateButton then Features.SpectateButton:setText("Spectate") end
        print("[PlayerList] Unspectated")
    else
        print("[PlayerList] Local humanoid not found")
    end
end
function Features.teleport_to_player()
    if not Features.SelectedPlayer then
        print("[PlayerList] No player selected")
        return
    end
    local target = Features.SelectedPlayer
    local tChar = target.Character
    local lChar = LocalPlayer.Character
    local tHRP = tChar and tChar:FindFirstChild("HumanoidRootPart")
    local lHRP = lChar and lChar:FindFirstChild("HumanoidRootPart")
    if tHRP and lHRP then
        lHRP.CFrame = tHRP.CFrame
        print("[PlayerList] Teleported to: " .. target.Name)
    else
        print("[PlayerList] Cannot teleport - missing HumanoidRootPart")
    end
end

function Features.fling_player()
    if not Features.SelectedPlayer then
        print("[PlayerList] No player selected")
        return
    end
    local target = Features.SelectedPlayer
    local tChar = target.Character
    local lChar = LocalPlayer.Character
    local tHRP = tChar and tChar:FindFirstChild("HumanoidRootPart")
    local lHRP = lChar and lChar:FindFirstChild("HumanoidRootPart")
    if tHRP and lHRP then
        local bv = Instance.new("BodyVelocity")
        bv.MaxForce = Vector3.new(500000, 500000, 500000)
        bv.Velocity = Vector3.new(0, 0, 0)
        bv.Parent = lHRP
        for i = 1, 25 do
            lHRP.CFrame = tHRP.CFrame * CFrame.new(0, 0, -1.5)
            task.wait()
        end
        bv:Destroy()
        print("[PlayerList] Flung: " .. target.Name)
    else
        print("[PlayerList] Cannot fling - missing HumanoidRootPart")
    end
end

function Features.set_player_priority(mark_type)
    if not Features.SelectedPlayer then
        print("[PlayerList] No player selected")
        return
    end
    local target = Features.SelectedPlayer
    Features.PlayerMarks[target.UserId] = mark_type
    print("[PlayerList] Marked " .. target.Name .. " as " .. mark_type:upper())
    if Features._build_list then
        Features._build_list()
    end
end

--// WORLD VISUALS
Features.OriginalLighting = {}
Features.WorldEffects = {}

function Features.init_world_visuals()
    local Lighting = game:GetService("Lighting")
    Features.OriginalLighting = {
        GlobalShadows = Lighting.GlobalShadows,
        Brightness = Lighting.Brightness,
        ClockTime = Lighting.ClockTime,
        FogStart = Lighting.FogStart,
        FogEnd = Lighting.FogEnd,
        Ambient = Lighting.Ambient,
        OutdoorAmbient = Lighting.OutdoorAmbient,
        ExposureCompensation = Lighting.ExposureCompensation,
    }
    local bloom = Lighting:FindFirstChild("PRSLIIV_Bloom")
    if not bloom then
        bloom = Instance.new("BloomEffect")
        bloom.Name = "PRSLIIV_Bloom"
        bloom.Enabled = false
        bloom.Parent = Lighting
    end
    Features.WorldEffects.Bloom = bloom
    local blur = Lighting:FindFirstChild("PRSLIIV_Blur")
    if not blur then
        blur = Instance.new("BlurEffect")
        blur.Name = "PRSLIIV_Blur"
        blur.Enabled = false
        blur.Parent = Lighting
    end
    Features.WorldEffects.Blur = blur
    local cc = Lighting:FindFirstChild("PRSLIIV_ColorCorrection")
    if not cc then
        cc = Instance.new("ColorCorrectionEffect")
        cc.Name = "PRSLIIV_ColorCorrection"
        cc.Enabled = false
        cc.Parent = Lighting
    end
    Features.WorldEffects.ColorCorrection = cc
end

function Features.full_bright(state)
    local Lighting = game:GetService("Lighting")
    if state then
        Lighting.GlobalShadows = false
        Lighting.Brightness = 10
    else
        Lighting.GlobalShadows = Features.OriginalLighting.GlobalShadows
        Lighting.Brightness = Features.OriginalLighting.Brightness
    end
end

function Features.no_fog(state)
    local Lighting = game:GetService("Lighting")
    if state then
        Lighting.FogStart = 0
        Lighting.FogEnd = 100000
    else
        Lighting.FogStart = Features.OriginalLighting.FogStart
        Lighting.FogEnd = Features.OriginalLighting.FogEnd
    end
end

function Features.time_of_day(value)
    if not (Features.Library and Features.Library.flags.time_force_loop) then
        game:GetService("Lighting").ClockTime = value
    end
end

function Features.time_force_loop(state)
    if state then
        Features:Connect("time_loop", function()
            local Lighting = game:GetService("Lighting")
            Lighting.ClockTime = (Lighting.ClockTime + 0.05) % 24
        end)
    else
        Features:Disconnect("time_loop")
        local v = Features.Library and Features.Library.flags.time_of_day
        if v then
            game:GetService("Lighting").ClockTime = v
        end
    end
end

function Features.brightness(value)
    game:GetService("Lighting").Brightness = value
end

function Features.exposure_comp(value)
    game:GetService("Lighting").ExposureCompensation = value
end

function Features.custom_ambient(state)
    local Lighting = game:GetService("Lighting")
    if state then
        local color = Features.Library.flags.ambient_color or Color3.fromRGB(127,127,127)
        Lighting.Ambient = color
        Lighting.OutdoorAmbient = color
    else
        Lighting.Ambient = Features.OriginalLighting.Ambient
        Lighting.OutdoorAmbient = Features.OriginalLighting.OutdoorAmbient
    end
end

function Features.ambient_color(color, transparency)
    if Features.Library and Features.Library.flags.custom_ambient then
        local Lighting = game:GetService("Lighting")
        Lighting.Ambient = color
        Lighting.OutdoorAmbient = color
    end
end

function Features.bloom(state)
    Features.WorldEffects.Bloom.Enabled = state
end

function Features.bloom_intensity(value)
    Features.WorldEffects.Bloom.Intensity = value
end

function Features.bloom_size(value)
    Features.WorldEffects.Bloom.Size = value
end

function Features.bloom_threshold(value)
    Features.WorldEffects.Bloom.Threshold = value
end

function Features.blur(state)
    Features.WorldEffects.Blur.Enabled = state
end

function Features.blur_size(value)
    Features.WorldEffects.Blur.Size = value
end

function Features.color_correction(state)
    Features.WorldEffects.ColorCorrection.Enabled = state
end

function Features.saturation(value)
    Features.WorldEffects.ColorCorrection.Saturation = value
end

function Features.contrast(value)
    Features.WorldEffects.ColorCorrection.Contrast = value
end

function Features.tint_color(color, transparency)
    Features.WorldEffects.ColorCorrection.TintColor = color
end

--// SELF VISUALS
Features.SelfESP = {
    BoxOutline = Drawing.new("Square"),
    BoxFill = Drawing.new("Square"),
    HealthbarOutline = Drawing.new("Square"),
    HealthbarFill = Drawing.new("Square"),
    TracerOutline = Drawing.new("Line"),
    TracerFill = Drawing.new("Line"),
    NameText = Drawing.new("Text"),
    StateText = Drawing.new("Text"),
    DistText = Drawing.new("Text"),
}

do
    local s = Features.SelfESP
    s.BoxOutline.Thickness = 3; s.BoxOutline.Filled = false; s.BoxOutline.Transparency = 1; s.BoxOutline.Visible = false
    s.BoxFill.Thickness = 1; s.BoxFill.Filled = false; s.BoxFill.Transparency = 1; s.BoxFill.Visible = false
    s.HealthbarOutline.Filled = true; s.HealthbarOutline.Transparency = 1; s.HealthbarOutline.Visible = false
    s.HealthbarFill.Filled = true; s.HealthbarFill.Transparency = 1; s.HealthbarFill.Visible = false
    s.TracerOutline.Thickness = 3; s.TracerOutline.Transparency = 1; s.TracerOutline.Visible = false
    s.TracerFill.Thickness = 1; s.TracerFill.Transparency = 1; s.TracerFill.Visible = false
    s.NameText.Center = true; s.NameText.Outline = true; s.NameText.Font = 1; s.NameText.Transparency = 1; s.NameText.Visible = false
    s.StateText.Center = true; s.StateText.Outline = true; s.StateText.Font = 1; s.StateText.Transparency = 1; s.StateText.Visible = false
    s.DistText.Center = true; s.DistText.Outline = true; s.DistText.Font = 1; s.DistText.Transparency = 1; s.DistText.Visible = false
end

function Features.update_self_esp()
    local s = Features.SelfESP
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local head = char and char:FindFirstChild("Head")
    local cam = workspace.CurrentCamera
    
    if not char or not hrp or not hum or not head then
        for _, d in pairs(s) do if typeof(d) == "Drawing" then d.Visible = false end end
        return
    end
    
    local pos, onscreen = cam:WorldToViewportPoint(hrp.Position)
    if not onscreen then
        for _, d in pairs(s) do if typeof(d) == "Drawing" then d.Visible = false end end
        return
    end
    
    local height = math.abs(head.Position.Y - hrp.Position.Y) * 2.6
    local top = cam:WorldToViewportPoint(hrp.Position + Vector3.new(0, height*0.5, 0))
    local bottom = cam:WorldToViewportPoint(hrp.Position - Vector3.new(0, height*0.5, 0))
    local screenH = math.abs(top.Y - bottom.Y)
    local screenW = screenH * 0.6
    local min = Vector2.new(pos.X - screenW/2, pos.Y - screenH/2)
    local max = Vector2.new(pos.X + screenW/2, pos.Y + screenH/2)
    
    local flags = Features.Library and Features.Library.flags or {}
    
    if flags.self_esp_box then
        local color = flags.self_esp_box_color or Color3.new(1,1,1)
        s.BoxOutline.Position = min; s.BoxOutline.Size = max-min; s.BoxOutline.Color = Color3.new(0,0,0); s.BoxOutline.Visible = true
        s.BoxFill.Position = min; s.BoxFill.Size = max-min; s.BoxFill.Color = color; s.BoxFill.Visible = true
    else
        s.BoxOutline.Visible = false; s.BoxFill.Visible = false
    end
    
    if flags.self_esp_health and hum.MaxHealth > 0 then
        local ratio = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
        local barW = 3
        local barOff = 3
        local x = min.X - barOff - barW
        local hpH = (max.Y - min.Y) * ratio
        local color = flags.self_esp_health_color or Color3.new(0,1,0)
        s.HealthbarOutline.Position = Vector2.new(x, min.Y); s.HealthbarOutline.Size = Vector2.new(barW, max.Y-min.Y); s.HealthbarOutline.Color = Color3.new(0,0,0); s.HealthbarOutline.Visible = true
        s.HealthbarFill.Position = Vector2.new(x, max.Y - hpH); s.HealthbarFill.Size = Vector2.new(barW, hpH); s.HealthbarFill.Color = color; s.HealthbarFill.Visible = true
    else
        s.HealthbarOutline.Visible = false; s.HealthbarFill.Visible = false
    end
    
    if flags.self_esp_tracer then
        local from = Vector2.new(cam.ViewportSize.X/2, cam.ViewportSize.Y)
        local to = (min + max)/2
        local color = flags.self_esp_tracer_color or Color3.new(1,1,1)
        s.TracerOutline.From = from; s.TracerOutline.To = to; s.TracerOutline.Color = Color3.new(0,0,0); s.TracerOutline.Visible = true
        s.TracerFill.From = from; s.TracerFill.To = to; s.TracerFill.Color = color; s.TracerFill.Visible = true
    else
        s.TracerOutline.Visible = false; s.TracerFill.Visible = false
    end
    
    if flags.self_esp_name then
        local color = flags.self_esp_name_color or Color3.new(1,1,1)
        s.NameText.Text = LocalPlayer.Name
        s.NameText.Size = 13
        s.NameText.Color = color
        s.NameText.Position = Vector2.new((min.X+max.X)/2, min.Y - 15)
        s.NameText.Visible = true
    else
        s.NameText.Visible = false
    end
    
    if flags.self_esp_state then
        local stateText = "Idle"
        local st = hum:GetState()
        if st == Enum.HumanoidStateType.Jumping or st == Enum.HumanoidStateType.Freefall then
            stateText = "Jumping"
        elseif hum.MoveDirection.Magnitude > 0.05 then
            stateText = "Moving"
        end
        local color = flags.self_esp_state_color or Color3.new(1,1,1)
        s.StateText.Text = stateText
        s.StateText.Size = 12
        s.StateText.Color = color
        s.StateText.Position = Vector2.new((min.X+max.X)/2, max.Y + 5 + 13 + 3)
        s.StateText.Visible = true
    else
        s.StateText.Visible = false
    end
    
    if flags.self_esp_dist then
        local dist = (cam.CFrame.Position - hrp.Position).Magnitude
        local color = flags.self_esp_dist_color or Color3.new(1,1,1)
        s.DistText.Text = tostring(math.floor(dist)) .. "m"
        s.DistText.Size = 13
        s.DistText.Color = color
        s.DistText.Position = Vector2.new((min.X+max.X)/2, max.Y + 5)
        s.DistText.Visible = true
    else
        s.DistText.Visible = false
    end
end

function Features.self_esp(state)
    if state then
        Features:Connect("self_esp_loop", function()
            Features.update_self_esp()
        end)
    else
        Features:Disconnect("self_esp_loop")
        for _, d in pairs(Features.SelfESP) do
            if typeof(d) == "Drawing" then
                d.Visible = false
            end
        end
    end
end

function Features.movement_trail(state)
    local char = LocalPlayer.Character
    if state then
        local function addTrail(character)
            local hrp = character:FindFirstChild("HumanoidRootPart")
            if not hrp then return end
            for _, v in pairs(hrp:GetChildren()) do
                if v.Name == "PRSLIIV_Trail" or v.Name == "PRSLIIV_TrailAtt0" or v.Name == "PRSLIIV_TrailAtt1" then
                    v:Destroy()
                end
            end
            local att0 = Instance.new("Attachment", hrp); att0.Name = "PRSLIIV_TrailAtt0"; att0.Position = Vector3.new(0, -2, 0)
            local att1 = Instance.new("Attachment", hrp); att1.Name = "PRSLIIV_TrailAtt1"; att1.Position = Vector3.new(0, 2, 0)
            local trail = Instance.new("Trail", hrp); trail.Name = "PRSLIIV_Trail"; trail.Attachment0 = att0; trail.Attachment1 = att1
            trail.Lifetime = 0.5; trail.WidthScale = NumberSequence.new(0.2)
            local color = Features.Library.flags.trail_color or Color3.fromRGB(255,255,255)
            trail.Color = ColorSequence.new(color)
        end
        if char then addTrail(char) end
        Features.Connections["trail_char"] = LocalPlayer.CharacterAdded:Connect(function(newChar)
            task.wait(0.1)
            if Features.Library and Features.Library.flags.movement_trail then
                addTrail(newChar)
            end
        end)
    else
        Features:Disconnect("trail_char")
        if char then
            for _, v in pairs(char:GetDescendants()) do
                if v.Name == "PRSLIIV_Trail" or v.Name == "PRSLIIV_TrailAtt0" or v.Name == "PRSLIIV_TrailAtt1" then
                    v:Destroy()
                end
            end
        end
    end
end

function Features.trail_color(color, transparency)
    local char = LocalPlayer.Character
    if not char then return end
    for _, v in pairs(char:GetDescendants()) do
        if v.Name == "PRSLIIV_Trail" and v:IsA("Trail") then
            v.Color = ColorSequence.new(color)
        end
    end
end

--// PARTICLE AURA (embedded)
local ParticleAura = {}
ParticleAura.Enabled = false
ParticleAura.Color = Color3.fromRGB(133, 220, 255)
ParticleAura.SelectedAura = "Angel"
local particle_auras = {}
local particles = {}
local aura_connection = nil
local char_connection = nil
local R15_TO_R6 = {
    ["UpperTorso"] = "Torso", ["LowerTorso"] = "Torso",
    ["LeftUpperArm"] = "Left Arm", ["LeftLowerArm"] = "Left Arm", ["LeftHand"] = "Left Arm",
    ["RightUpperArm"] = "Right Arm", ["RightLowerArm"] = "Right Arm", ["RightHand"] = "Right Arm",
    ["LeftUpperLeg"] = "Left Leg", ["LeftLowerLeg"] = "Left Leg", ["LeftFoot"] = "Left Leg",
    ["RightUpperLeg"] = "Right Leg", ["RightLowerLeg"] = "Right Leg", ["RightFoot"] = "Right Leg",
}
local function IsR6(character)
    for _, child in pairs(character:GetChildren()) do
        if child.Name == "Torso" and child:IsA("BasePart") then return true end
    end
    return false
end
local function FindCharPart(character, name, r6)
    if r6 then
        local mapped = R15_TO_R6[name] or name
        for _, child in pairs(character:GetChildren()) do
            if child.Name == mapped and child:IsA("BasePart") then return child end
        end
    else
        for _, child in pairs(character:GetChildren()) do
            if child.Name == name and child:IsA("BasePart") then return child end
        end
    end
    return nil
end
local function LoadAuras()
    local assets = {
        ["Starlight"] = "rbxassetid://134645216613107",
        ["Heavenly"] = "rbxassetid://139300897520961",
        ["Ribbon"] = "rbxassetid://132069507632161",
        ["Sakura"] = "rbxassetid://81755778619404",
        ["Angel"] = "rbxassetid://97658130917593",
        ["Wind"] = "rbxassetid://80694081850877",
        ["Flow"] = "rbxassetid://119913533725648",
        ["Star"] = "rbxassetid://73754563740680",
        ["Spike"] = "rbxassetid://74417067882526",
        ["Super Saiyan"] = "rbxassetid://16699750981",
        ["Head"] = "rbxassetid://17069712982",
        -- Thunder removed
    }
    for name, id in pairs(assets) do
        pcall(function()
            particle_auras[name] = game:GetObjects(id)[1]
        end)
    end
end
local function ApplyColorToModel(model, color)
    if not model then return end
    local colorSeq = ColorSequence.new(color)
    pcall(function()
        for _, desc in pairs(model:GetDescendants()) do
            pcall(function()
                if desc.ClassName == "PointLight" then
                    desc.Color = color
                elseif desc.ClassName == "ParticleEmitter" or desc.ClassName == "Beam" or desc.ClassName == "Trail" then
                    desc.Color = colorSeq
                end
            end)
        end
    end)
end
local function ClearParticles()
    for i = #particles, 1, -1 do
        pcall(function() particles[i]:Destroy() end)
        particles[i] = nil
    end
    particles = {}
end
local function ApplyAura()
    ClearParticles()
    local character = LocalPlayer and LocalPlayer.Character
    if not character then return end
    local hrp = nil
    pcall(function()
        for _, child in pairs(character:GetChildren()) do
            if child.Name == "HumanoidRootPart" then hrp = child; break end
        end
    end)
    if not hrp then return end
    local auraModel = particle_auras[ParticleAura.SelectedAura]
    if not auraModel then return end
    local r6 = IsR6(character)
    pcall(function()
        local cloned = auraModel:Clone()
        local children = cloned:GetChildren()
        for _, part in pairs(children) do
            local localPart = FindCharPart(character, part.Name, r6)
            if localPart then
                for _, child in pairs(part:GetChildren()) do
                    pcall(function()
                        child.Name = "\0\0"
                        child.Parent = localPart
                        table.insert(particles, child)
                    end)
                end
            end
            pcall(function() part:Destroy() end)
        end
        pcall(function() cloned:Destroy() end)
    end)
end
function ParticleAura:SetColor(color)
    self.Color = color
    local colorSeq = ColorSequence.new(color)
    for name, model in pairs(particle_auras) do
        if model and typeof(model) ~= "string" then
            ApplyColorToModel(model, color)
        end
    end
    for _, part in pairs(particles) do
        pcall(function()
            if part.ClassName == "PointLight" then
                part.Color = color
            elseif part.ClassName == "ParticleEmitter" or part.ClassName == "Beam" or part.ClassName == "Trail" then
                part.Color = colorSeq
            end
            for _, desc in pairs(part:GetDescendants()) do
                pcall(function()
                    if desc.ClassName == "PointLight" then
                        desc.Color = color
                    elseif desc.ClassName == "ParticleEmitter" or desc.ClassName == "Beam" or desc.ClassName == "Trail" then
                        desc.Color = colorSeq
                    end
                end)
            end
        end)
    end
end
function ParticleAura:SetAura(name)
    self.SelectedAura = name
    if self.Enabled then
        ApplyAura()
    end
end
function ParticleAura:Toggle(enabled)
    self.Enabled = enabled
    ClearParticles()
    if char_connection then
        pcall(function() char_connection:Disconnect() end)
        char_connection = nil
    end
    if enabled then
        ApplyAura()
        char_connection = LocalPlayer.CharacterAdded:Connect(function()
            task.wait(0.5)
            if self.Enabled then
                ApplyAura()
            end
        end)
    end
end
function ParticleAura:GetAuraNames()
    local names = {}
    for name, _ in pairs(particle_auras) do
        table.insert(names, name)
    end
    return names
end
LoadAuras()
pcall(function()
    ParticleAura:SetColor(ParticleAura.Color)
end)

function Features.particle_aura(state)
    if state then
        local auraName = Features.Library.flags.particle_aura_type and Features.Library.flags.particle_aura_type[1] or "Angel"
        ParticleAura:SetAura(auraName)
        ParticleAura:SetColor(Features.Library.flags.particle_aura_color or Color3.fromRGB(133, 220, 255))
        ParticleAura:Toggle(true)
    else
        ParticleAura:Toggle(false)
    end
end

function Features.particle_aura_type(options)
    local name = options and options[1] or "Angel"
    ParticleAura:SetAura(name)
end

function Features.particle_aura_color(color, transparency)
    ParticleAura:SetColor(color)
end

-- Init world visuals
Features.init_world_visuals()

--// CFRAME SYSTEM (Tab 3)
Features.CFrameConfig = {
    enabled = false,
    method = "Velocity", -- "Velocity" or "Bunny Hop"
    multiplier = 0.5,
    bhopMaxSpeed = 20.0,
    bhopGain = 0.05,
    active = false,
    currentBhopMultiplier = 0.0,
    hasJumpedThisAirtime = false,
}

function Features.cframe_enabled(state)
    Features.CFrameConfig.enabled = state
    if not state then
        Features.CFrameConfig.active = false
        Features.CFrameConfig.currentBhopMultiplier = 0.0
        Features.CFrameConfig.hasJumpedThisAirtime = false
    end
end

function Features.cframe_method(options)
    local method = options and options[1] or "Velocity"
    Features.CFrameConfig.method = method
    Features.CFrameConfig.currentBhopMultiplier = 0.0
    Features.CFrameConfig.hasJumpedThisAirtime = false
    if Features.CFrameConfig.enabled then
        Features.CFrameConfig.active = false
    end
end

function Features.cframe_multiplier(value)
    Features.CFrameConfig.multiplier = value
end

function Features.cframe_bhop_max(value)
    Features.CFrameConfig.bhopMaxSpeed = value
end

function Features.cframe_bhop_gain(value)
    Features.CFrameConfig.bhopGain = value / 100
end

function Features.cframe_toggle_keybind(active)
    if not Features.CFrameConfig.enabled then return end
    if Features.CFrameConfig.method == "Velocity" then
        Features.CFrameConfig.active = active
    end
end

-- CFrame Heartbeat
local cframeConnection = RunService.Heartbeat:Connect(function()
    if not Features.CFrameConfig.enabled then return end
    
    local lp = Players.LocalPlayer
    if lp.Character and lp.Character:FindFirstChild("Humanoid") and lp.Character:FindFirstChild("HumanoidRootPart") then
        local humanoid = lp.Character.Humanoid
        local hrp = lp.Character.HumanoidRootPart
        local UIS = game:GetService("UserInputService")
        local cfg = Features.CFrameConfig
        
        if cfg.method == "Velocity" and cfg.active then
            if humanoid.MoveDirection.Magnitude > 0 then
                hrp.CFrame = hrp.CFrame + (humanoid.MoveDirection * cfg.multiplier)
            end
            
        elseif cfg.method == "Bunny Hop" then
            if UIS:IsKeyDown(Enum.KeyCode.Space) then
                if humanoid.FloorMaterial ~= Enum.Material.Air then
                    humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                    
                    if not cfg.hasJumpedThisAirtime then
                        cfg.currentBhopMultiplier = math.min(cfg.currentBhopMultiplier + cfg.bhopGain, cfg.bhopMaxSpeed)
                        cfg.hasJumpedThisAirtime = true
                    end
                end
                
                if humanoid.FloorMaterial == Enum.Material.Air then
                    cfg.hasJumpedThisAirtime = false
                end
                
                if humanoid.MoveDirection.Magnitude > 0 and cfg.currentBhopMultiplier > 0 then
                    hrp.CFrame = hrp.CFrame + (humanoid.MoveDirection * cfg.currentBhopMultiplier)
                end
            else
                if humanoid.FloorMaterial ~= Enum.Material.Air then
                    cfg.currentBhopMultiplier = 0.0
                    cfg.hasJumpedThisAirtime = false
                end
            end
        end
    end
end)

-- CFrame Guns FIX
function Features.cframe_guns_fix()
    local lp = Players.LocalPlayer
    if lp.Character then
        for _, v in pairs(lp.Character:GetChildren()) do
            if v:IsA("Script") and v.Name ~= "Health" and v.Name ~= "Sound" and v:FindFirstChild("LocalScript") then
                v:Destroy()
            end
        end
    end
    lp.CharacterAdded:Connect(function(char)
        char:WaitForChild("Humanoid")
        char.ChildAdded:Connect(function(child)
            if child:IsA("Script") then 
                task.wait(0.1)
                if child:FindFirstChild("LocalScript") then
                    child.LocalScript:FireServer()
                end
            end
        end)
    end)
end

local function ensureAllTracked()
    for _, plr in pairs(players:GetPlayers()) do
        if plr ~= localPlayer and plr.Character then
            trackCharacter(plr.Character)
        end
    end
end

function Features.esp_box(state)
    Features.ESPConfig.box.enabled = state
    if state then ensureAllTracked() end
end

function Features.esp_box_color(color, transparency)
    Features.ESPConfig.box.fill = color
    Features.ESPConfig.box.outline = Color3.new(0,0,0)
end

function Features.esp_box_type(options)
    local t = options and options[1] or "Normal"
    Features.ESPConfig.box.type = t:lower()
end

function Features.esp_box_fill(state)
    for _, data in pairs(espinstances) do
        if data.box then
            data.box.fill.Filled = state
        end
    end
end

function Features.esp_box_fill_color(color, transparency)
    for _, data in pairs(espinstances) do
        if data.box then
            data.box.fill.Color = color
        end
    end
end

function Features.esp_healthbar(state)
    Features.ESPConfig.healthbar.enabled = state
    if state then ensureAllTracked() end
end

function Features.esp_healthbar_color(color, transparency)
    Features.ESPConfig.healthbar.fill = color
end

function Features.esp_healthbar_dynamic(state)
    Features.ESPConfig.healthbar.dynamic_color = state
end

function Features.esp_name(state)
    Features.ESPConfig.name.enabled = state
    if state then ensureAllTracked() end
end

function Features.esp_name_color(color, transparency)
    Features.ESPConfig.name.fill = color
end

function Features.esp_name_mode(options)
    Features.ESPNameMode = options and options[1] or "Real Name"
end

function Features.esp_distance(state)
    Features.ESPConfig.distance.enabled = state
    if state then ensureAllTracked() end
end

function Features.esp_distance_color(color, transparency)
    Features.ESPConfig.distance.fill = color
end

function Features.esp_state(state)
    Features.ESPConfig.state.enabled = state
    if state then ensureAllTracked() end
end

function Features.esp_state_color(color, transparency)
    Features.ESPConfig.state.fill = color
end

function Features.esp_tracer(state)
    Features.ESPConfig.tracer.enabled = state
    if state then ensureAllTracked() end
end

function Features.esp_tracer_color(color, transparency)
    Features.ESPConfig.tracer.fill = color
end

function Features.esp_tracer_from(options)
    Features.ESPConfig.tracer.from = (options and options[1] or "Mouse"):lower()
end

function Features.esp_friend_marker(state)
    Features.ESPConfig.friendmarker.enabled = state
    if state then ensureAllTracked() end
end

function Features.esp_friend_marker_color(color, transparency)
    Features.ESPConfig.friendmarker.fill = color
end

function Features.esp_dsync_marker(state)
    Features.ESPConfig.dsyncmarker.enabled = state
    if state then ensureAllTracked() end
end

function Features.esp_dsync_marker_color(color, transparency)
    Features.ESPConfig.dsyncmarker.fill = color
end

function Features.esp_macro_marker(state)
    Features.ESPConfig.macromarker.enabled = state
    if state then ensureAllTracked() end
end

function Features.esp_macro_marker_color(color, transparency)
    Features.ESPConfig.macromarker.fill = color
end

function Features.esp_skeleton(state)
    Features.SkeletonESP.enabled = state
end

function Features.esp_skeleton_color(color, transparency)
    Features.SkeletonESP.color = color
end

function Features.esp_mode(options)
    Features.ESPMode = options and options[1] or "Static"
    if Features.ESPMode == "Dynamic" then
        charSizes = {}
    end
end

function Features.esp_chams(state)
    Features.ChamsSettings.Enabled = state
end

function Features.esp_chams_vis_fill(color, transparency)
    Features.ChamsSettings.VisibleFillColor = color
end

function Features.esp_chams_vis_outline(color, transparency)
    Features.ChamsSettings.VisibleOutlineColor = color
end

function Features.esp_chams_hid_fill(color, transparency)
    Features.ChamsSettings.HiddenFillColor = color
end

function Features.esp_chams_hid_outline(color, transparency)
    Features.ChamsSettings.HiddenOutlineColor = color
end

function Features.esp_chams_transparency(value)
    Features.ChamsSettings.Transparency = value
end

--// =========================================================
--// CAMLOCK & TRIGGERBOT SYSTEM (Tab 2)
--// =========================================================

Features.CamlockConfig = {
    enabled = false,
    smoothness = 0.5,
    prediction = 0,
    targetingMode = "Players",
    hitpart = {"Head", "Upper Torso"},
    rigType = "R15",
    closestPart = false,
    closestPoint = false,
    priorityOnly = false,
    friendlyLock = false,
    maxDistance = 500,
    visibleCheck = false,
    visibleInterval = 0.1,
    relockDelay = 0.1,
    visibilityMethod = "Camera",
    shootOnSight = false,
    shootMode = "Auto",
    shootCPS = 10,
    fov = 500,
}

Features.CamlockJumpDelay = {
    enabled = false,
    delayMs = 300,
    smoothness = 0.3,
    followAfterDelay = true,
}

Features.CamlockPerlin = {
    enabled = false,
    intensity = 1.0,
    frequency = 0.5,
    xIntensity = 1.0,
    yIntensity = 1.0,
    onlyWhenMoving = true,
    minSmoothness = 0.1,
}

Features.TriggerbotConfig = {
    enabled = false,
    targetingMode = "Players",
    priorityOnly = false,
    friendlyLock = false,
    teamCheck = false,
    checkTeammates = true,
    checkHealth = true,
    notify = true,
}

-- State
local CamlockState = {
    target = nil,
    targetPart = nil,
    pendingTarget = nil,
    pendingPart = nil,
    pendingTime = 0,
    lastVisCheck = 0,
    isPending = false,
    jumpJumped = false,
    jumpDelaying = false,
    jumpCatchup = false,
    jumpStartTime = 0,
    jumpGroundY = nil,
    catchupStartTime = 0,
    catchupStartY = 0,
    camConn = nil,
    perlinConn = nil,
    shootHeld = false,
    lastClick = 0,
}

local TriggerbotState = {
    clickState = true,
}

-- Perlin Noise
local PerlinNoise = {}
do
    local function fade(t) return t * t * t * (t * (t * 6 - 15) + 10) end
    local function lerp(a, b, t) return a + t * (b - a) end
    local function grad(hash, x, y, z)
        local h = hash % 16
        local u = h < 8 and x or y
        local v = h < 4 and y or (h == 12 or h == 14) and x or z
        return ((h % 2) == 0 and u or -u) + ((h % 4) == 0 and v or -v)
    end
    local p = {}
    for i = 0, 255 do p[i] = i end
    for i = 255, 1, -1 do
        local j = math.random(0, i)
        p[i], p[j] = p[j], p[i]
    end
    for i = 0, 255 do p[i + 256] = p[i] end
    function PerlinNoise.noise(x, y, z)
        local X = math.floor(x) % 255
        local Y = math.floor(y) % 255
        local Z = math.floor(z) % 255
        x, y, z = x - math.floor(x), y - math.floor(y), z - math.floor(z)
        local u, v, w = fade(x), fade(y), fade(z)
        local a = p[X] + Y
        local aa, ab = p[a] + Z, p[a + 1] + Z
        local b = p[X + 1] + Y
        local ba, bb = p[b] + Z, p[b + 1] + Z
        return lerp(
            lerp(lerp(grad(p[aa], x, y, z), grad(p[ba], x - 1, y, z), u),
                 lerp(grad(p[ab], x, y - 1, z), grad(p[bb], x - 1, y - 1, z), u), v),
            lerp(lerp(grad(p[aa + 1], x, y, z - 1), grad(p[ba + 1], x - 1, y, z - 1), u),
                 lerp(grad(p[ab + 1], x, y - 1, z - 1), grad(p[bb + 1], x - 1, y - 1, z - 1), u), v),
            w)
    end
end

local perlinState = { time = math.random(0, 1000), lastX = 0, lastY = 0 }

-- Helpers
local function getPriority(char)
    if not char then return "Neutral" end
    local plr = Players:GetPlayerFromCharacter(char)
    if not plr then return "Neutral" end
    local data = _G.PlayerTags and _G.PlayerTags[plr.Name]
    return data or "Neutral"
end

local function isValidForMode(char, priorityOnly, friendlyLock)
    if not char then return false end
    local plr = Players:GetPlayerFromCharacter(char)
    if not plr then return true end
    local p = getPriority(char)
    if priorityOnly and p ~= "Priority" then return false end
    if not friendlyLock and p == "Friendly" then return false end
    return true
end

local function getTargets(mode, priorityOnly, friendlyLock)
    local targets = {}
    if mode == "Players" or mode == "Hybrid" then
        for _, v in pairs(Players:GetPlayers()) do
            if v ~= LocalPlayer and v.Character and v.Character.Parent then
                if isValidForMode(v.Character, priorityOnly, friendlyLock) then
                    table.insert(targets, v.Character)
                end
            end
        end
    end
    if mode == "NPCs" or mode == "Hybrid" then
        for _, obj in pairs(workspace:GetDescendants()) do
            if obj:IsA("Model") and obj:FindFirstChildOfClass("Humanoid") then
                if not Players:GetPlayerFromCharacter(obj) and obj ~= LocalPlayer.Character then
                    table.insert(targets, obj)
                end
            end
        end
    end
    return targets
end

local function isValidChar(char, mode)
    if not char or char == LocalPlayer.Character or not char.Parent then return false end
    local plr = Players:GetPlayerFromCharacter(char)
    if mode == "Players" and not plr then return false end
    if mode == "NPCs" and plr then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum and (hum.Health <= 0 or hum:GetState() == Enum.HumanoidStateType.Dead) then return false end
    return char:FindFirstChild("HumanoidRootPart") ~= nil
end

local function getFallbackPart(char)
    for _, name in ipairs({"Head", "UpperTorso", "LowerTorso", "HumanoidRootPart"}) do
        local p = char:FindFirstChild(name)
        if p and p:IsA("BasePart") then return p end
    end
    return nil
end

local R15_DISPLAY_MAP = {
    ["Head"] = "Head", ["Neck"] = "Neck", ["Upper Torso"] = "UpperTorso",
    ["Lower Torso"] = "LowerTorso", ["Root"] = "HumanoidRootPart",
    ["Left Upper Arm"] = "LeftUpperArm", ["Left Lower Arm"] = "LeftLowerArm", ["Left Hand"] = "LeftHand",
    ["Right Upper Arm"] = "RightUpperArm", ["Right Lower Arm"] = "RightLowerArm", ["Right Hand"] = "RightHand",
    ["Left Upper Leg"] = "LeftUpperLeg", ["Left Lower Leg"] = "LeftLowerLeg", ["Left Foot"] = "LeftFoot",
    ["Right Upper Leg"] = "RightUpperLeg", ["Right Lower Leg"] = "RightLowerLeg", ["Right Foot"] = "RightFoot"
}

local R6_DISPLAY_MAP = {
    ["Head"] = "Head", ["Torso"] = "Torso", ["HumanoidRootPart"] = "HumanoidRootPart",
    ["Left Arm"] = "Left Arm", ["Right Arm"] = "Right Arm",
    ["Left Leg"] = "Left Leg", ["Right Leg"] = "Right Leg"
}

local function displayToInternal(name, rigType)
    if rigType == "R6" then return R6_DISPLAY_MAP[name] or name end
    return R15_DISPLAY_MAP[name] or name
end

local function getHitpartOptions(rigType)
    if rigType == "R6" then
        return {"Head", "Torso", "HumanoidRootPart", "Left Arm", "Right Arm", "Left Leg", "Right Leg"}
    end
    return {"Head", "Neck", "Upper Torso", "Lower Torso", "Root",
        "Left Upper Arm", "Left Lower Arm", "Left Hand",
        "Right Upper Arm", "Right Lower Arm", "Right Hand",
        "Left Upper Leg", "Left Lower Leg", "Left Foot",
        "Right Upper Leg", "Right Lower Leg", "Right Foot"}
end

local function getAimPart(char)
    local cfg = Features.CamlockConfig
    if cfg.closestPart then
        local mousePos = game:GetService("UserInputService"):GetMouseLocation()
        local best, bestDist = nil, math.huge
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                local sp, on = Camera:WorldToViewportPoint(part.Position)
                if on then
                    local d = (Vector2.new(sp.X, sp.Y) - mousePos).Magnitude
                    if d < bestDist then bestDist, best = d, part end
                end
            end
        end
        if best then return best end
    end
    local selected = cfg.hitpart
    if type(selected) ~= "table" then selected = {selected} end
    for _, display in ipairs(selected) do
        local name = displayToInternal(display, cfg.rigType)
        local p = char:FindFirstChild(name)
        if not p and cfg.rigType == "R15" then
            local fallback = {UpperTorso="Torso", LowerTorso="Torso", LeftUpperArm="Left Arm", LeftLowerArm="Left Arm",
                LeftHand="Left Arm", RightUpperArm="Right Arm", RightLowerArm="Right Arm", RightHand="Right Arm",
                LeftUpperLeg="Left Leg", LeftLowerLeg="Left Leg", LeftFoot="Left Leg",
                RightUpperLeg="Right Leg", RightLowerLeg="Right Leg", RightFoot="Right Leg"}
            p = char:FindFirstChild(fallback[name] or "")
        end
        if p and p:IsA("BasePart") then return p end
    end
    return getFallbackPart(char)
end

local function generateMultipoints(part)
    local points, size, cf = {}, part.Size / 2, part.CFrame
    local gridSize, step = 3, 1
    local faces = {Vector3.new(1,0,0), Vector3.new(-1,0,0), Vector3.new(0,1,0), Vector3.new(0,-1,0), Vector3.new(0,0,1), Vector3.new(0,0,-1)}
    for _, n in ipairs(faces) do
        local t1, t2
        if math.abs(n.X) > 0.999 then t1, t2 = Vector3.new(0,1,0), Vector3.new(0,0,1)
        elseif math.abs(n.Y) > 0.999 then t1, t2 = Vector3.new(1,0,0), Vector3.new(0,0,1)
        else t1, t2 = Vector3.new(1,0,0), Vector3.new(0,1,0) end
        for i = 0, gridSize - 1 do
            for j = 0, gridSize - 1 do
                local u, v = -1 + i * step, -1 + j * step
                table.insert(points, cf:PointToWorldSpace(n * size + t1 * (u * size.X) + t2 * (v * size.Y)))
            end
        end
    end
    table.insert(points, cf:PointToWorldSpace(Vector3.zero))
    local corners = {Vector3.new(-1,-1,-1), Vector3.new(1,-1,-1), Vector3.new(-1,1,-1), Vector3.new(1,1,-1),
        Vector3.new(-1,-1,1), Vector3.new(1,-1,1), Vector3.new(-1,1,1), Vector3.new(1,1,1)}
    for _, c in ipairs(corners) do table.insert(points, cf:PointToWorldSpace(c * size)) end
    return points
end

local function getClosestPoint(char, rigType)
    if not char then return nil end
    local center = Camera.ViewportSize / 2
    local origin = Camera.CFrame.Position
    local best = {pos = nil, part = nil, dist = math.huge}
    local parts = {}
    if rigType == "R6" then
        parts = {"Head", "Torso", "HumanoidRootPart", "Left Arm", "Right Arm", "Left Leg", "Right Leg"}
    else
        parts = {"Head", "Neck", "Upper Torso", "Lower Torso", "HumanoidRootPart",
            "Left Upper Arm", "Left Lower Arm", "Left Hand",
            "Right Upper Arm", "Right Lower Arm", "Right Hand",
            "Left Upper Leg", "Left Lower Leg", "Left Foot",
            "Right Upper Leg", "Right Lower Leg", "Right Foot"}
    end
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    rp.IgnoreWater = true
    rp.FilterDescendantsInstances = {LocalPlayer.Character}
    for _, display in ipairs(parts) do
        local name = displayToInternal(display, rigType)
        local part = char:FindFirstChild(name)
        if not part and rigType == "R15" then
            local fb = {UpperTorso="Torso", LowerTorso="Torso", LeftUpperArm="Left Arm", LeftLowerArm="Left Arm", LeftHand="Left Arm",
                RightUpperArm="Right Arm", RightLowerArm="Right Arm", RightHand="Right Arm",
                LeftUpperLeg="Left Leg", LeftLowerLeg="Left Leg", LeftFoot="Left Leg",
                RightUpperLeg="Right Leg", RightLowerLeg="Right Leg", RightFoot="Right Leg"}
            part = char:FindFirstChild(fb[name] or "")
        end
        if part and part:IsA("BasePart") then
            for _, wp in ipairs(generateMultipoints(part)) do
                local sp, on = Camera:WorldToViewportPoint(wp)
                if on then
                    local sd = (Vector2.new(sp.X, sp.Y) - center).Magnitude
                    local dir = wp - origin
                    local res = workspace:Raycast(origin, dir, rp)
                    local vis = not res or (res.Instance and res.Instance:IsDescendantOf(char))
                    if vis and sd < best.dist then best = {pos = wp, part = part, dist = sd} end
                end
            end
        end
    end
    return best.pos
end

local function isPartVisible(part, method)
    local char = LocalPlayer.Character
    if not (char and part) then return false end
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    rp.IgnoreWater = true
    local origin, dir
    if method == "Camera" then
        origin = Camera.CFrame.Position
        dir = part.Position - origin
        rp.FilterDescendantsInstances = {char}
    elseif method == "LocalPlayer" then
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return true end
        origin = hrp.Position
        dir = part.Position - origin
        rp.FilterDescendantsInstances = {char}
    elseif method == "Tool" then
        local tool = char:FindFirstChildOfClass("Tool")
        if not tool then
            origin = Camera.CFrame.Position
            dir = part.Position - origin
            rp.FilterDescendantsInstances = {char}
        else
            local handle = tool:FindFirstChild("Handle")
            if not handle then
                origin = Camera.CFrame.Position
                dir = part.Position - origin
                rp.FilterDescendantsInstances = {char}
            else
                origin = handle.Position
                dir = part.Position - origin
                rp.FilterDescendantsInstances = {char, tool}
            end
        end
    else
        return true
    end
    local res = workspace:Raycast(origin, dir, rp)
    return not res or (res.Instance and res.Instance:IsDescendantOf(part.Parent))
end

local function updateVisibilityCheck()
    local cfg = Features.CamlockConfig
    if not cfg.visibleCheck then
        CamlockState.pendingTarget = nil
        CamlockState.pendingPart = nil
        CamlockState.isPending = false
        return
    end
    local now = tick()
    if now - CamlockState.lastVisCheck < cfg.visibleInterval then return end
    CamlockState.lastVisCheck = now
    local target, part = CamlockState.target, CamlockState.targetPart
    if target and part then
        if not isPartVisible(part, cfg.visibilityMethod) then
            CamlockState.pendingTarget, CamlockState.pendingPart = target, part
            CamlockState.target, CamlockState.targetPart = nil, nil
            CamlockState.isPending = true
            CamlockState.pendingTime = now
        else
            CamlockState.pendingTarget, CamlockState.pendingPart = nil, nil
            CamlockState.isPending = false
        end
    elseif CamlockState.pendingTarget and CamlockState.pendingPart then
        if isPartVisible(CamlockState.pendingPart, cfg.visibilityMethod) then
            if now - CamlockState.pendingTime >= cfg.relockDelay then
                CamlockState.target, CamlockState.targetPart = CamlockState.pendingTarget, CamlockState.pendingPart
                CamlockState.pendingTarget, CamlockState.pendingPart = nil, nil
                CamlockState.isPending = false
            end
        else
            CamlockState.pendingTime = now
        end
    end
end

local function applyPerlin(targetCF, currentCF, smoothness)
    local p = Features.CamlockPerlin
    if not p.enabled or smoothness < p.minSmoothness then return targetCF end
    perlinState.time = perlinState.time + (1/60) * p.frequency
    local nx = PerlinNoise.noise(perlinState.time, 0, 0) * 0.5
    local ny = PerlinNoise.noise(0, perlinState.time + 100, 0) * 0.5
    local offX = nx * p.intensity * p.xIntensity * smoothness
    local offY = ny * p.intensity * p.yIntensity * smoothness
    perlinState.lastX = perlinState.lastX + (offX - perlinState.lastX) * 0.3
    perlinState.lastY = perlinState.lastY + (offY - perlinState.lastY) * 0.3
    local look = targetCF.LookVector
    local right = targetCF.RightVector
    local up = targetCF.UpVector
    local rot = look + right * (perlinState.lastX * 0.02) + up * (perlinState.lastY * 0.02)
    return CFrame.new(targetCF.Position, targetCF.Position + rot.Unit)
end

local function getTargetUnderMouse(mode)
    local mousePos = game:GetService("UserInputService"):GetMouseLocation()
    local closestDist, closestChar = Features.CamlockConfig.fov, nil
    local targets = getTargets(mode, Features.CamlockConfig.priorityOnly, Features.CamlockConfig.friendlyLock)
    for _, char in ipairs(targets) do
        if not isValidChar(char, mode) then continue end
        local part = getAimPart(char)
        if part then
            local sp, on = Camera:WorldToViewportPoint(part.Position)
            if on then
                local d = (Vector2.new(sp.X, sp.Y) - mousePos).Magnitude
                if d < closestDist then closestDist, closestChar = d, char end
            end
        end
    end
    return closestChar
end

local function canShoot(char)
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    local cfg = Features.TriggerbotConfig
    if cfg.checkHealth and hum.Health < 1 then return false end
    if cfg.teamCheck then
        local tplr = Players:GetPlayerFromCharacter(char)
        if tplr and LocalPlayer.Team and tplr.Team then
            if cfg.checkTeammates and LocalPlayer.Team == tplr.Team then return false end
        end
    end
    return true
end

local function sosClick()
    mouse1press()
    task.delay(0.015, mouse1release)
end

local function isVisibleForSOS(part, origin)
    local char = LocalPlayer.Character
    if not (char and part) then return false end
    local bush = workspace:FindFirstChild("Bush")
    local ignore = workspace:FindFirstChild("Ignored")
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    rp.IgnoreWater = true
    rp.FilterDescendantsInstances = {char, bush, ignore}
    local res = workspace:Raycast(origin, part.Position - origin, rp)
    return not res or (res.Instance and res.Instance:IsDescendantOf(part.Parent))
end

local function checkAndShoot()
    local cfg = Features.CamlockConfig
    if not (cfg.shootOnSight and cfg.enabled and CamlockState.target) then return false end
    if not isValidChar(CamlockState.target, cfg.targetingMode) then
        CamlockState.target, CamlockState.targetPart = nil, nil
        return false
    end
    local origin = Camera.CFrame.Position
    local part = CamlockState.targetPart or getAimPart(CamlockState.target)
    if not part then return false end
    if not isVisibleForSOS(part, origin) then return false end
    CamlockState.targetPart = part
    local hum = CamlockState.target:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    if cfg.shootMode == "Hold" then
        if not CamlockState.shootHeld then
            mouse1press()
            CamlockState.shootHeld = true
        end
        return true
    end
    local interval = 1 / cfg.shootCPS
    local now = tick()
    if now - CamlockState.lastClick >= interval then
        CamlockState.lastClick = now
        sosClick()
        return true
    end
    return false
end

-- Core camlock loop
local function startCamlockLoop()
    if CamlockState.camConn then CamlockState.camConn:Disconnect() end
    if CamlockState.perlinConn then CamlockState.perlinConn:Disconnect() end
    CamlockState.camConn, CamlockState.perlinConn = nil, nil
    if not Features.CamlockConfig.enabled then return end

    -- Reset jump state
    CamlockState.jumpJumped = false
    CamlockState.jumpDelaying = false
    CamlockState.jumpCatchup = false
    CamlockState.jumpGroundY = nil

    local function runCamlock(dt)
        local cfg = Features.CamlockConfig
        if cfg.visibleCheck then updateVisibilityCheck() end
        if not cfg.enabled or not CamlockState.target then return end
        if not isValidChar(CamlockState.target, cfg.targetingMode) then
            CamlockState.target, CamlockState.targetPart = nil, nil
            return
        end

        local targetPos = nil
        local char = CamlockState.target
        local hum = char:FindFirstChildOfClass("Humanoid")
        local root = char:FindFirstChild("HumanoidRootPart")

        -- Get target position
        if cfg.closestPoint then
            targetPos = getClosestPoint(char, cfg.rigType)
        else
            local part = getAimPart(char)
            if part then targetPos = part.Position end
        end
        if not targetPos then
            local fb = getFallbackPart(char)
            if fb then targetPos = fb.Position else return end
        end

        -- Jump delay logic
        local state = hum and hum:GetState() or Enum.HumanoidStateType.Running
        local isJumping = state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall
        local isGrounded = state == Enum.HumanoidStateType.Running or state == Enum.HumanoidStateType.Landed
            or state == Enum.HumanoidStateType.GettingUp or state == Enum.HumanoidStateType.RunningNoPhysics
            or state == Enum.HumanoidStateType.Seated

        if isGrounded then CamlockState.jumpGroundY = targetPos.Y end
        if isJumping and not CamlockState.jumpJumped and CamlockState.jumpGroundY then
            CamlockState.jumpJumped = true
            CamlockState.jumpStartTime = tick()
            CamlockState.jumpDelaying = true
            CamlockState.jumpCatchup = false
        end
        if isGrounded and CamlockState.jumpJumped then
            CamlockState.jumpJumped = false
            CamlockState.jumpDelaying = false
            CamlockState.jumpCatchup = false
            CamlockState.jumpGroundY = targetPos.Y
        end
        if hum and hum.Health <= 0 then
            CamlockState.jumpJumped = false
            CamlockState.jumpDelaying = false
            CamlockState.jumpCatchup = false
            CamlockState.jumpGroundY = nil
        end

        local jd = Features.CamlockJumpDelay
        if jd.enabled and CamlockState.jumpDelaying then
            local elapsed = (tick() - CamlockState.jumpStartTime) * 1000
            if elapsed < jd.delayMs then
                targetPos = Vector3.new(targetPos.X, CamlockState.jumpGroundY, targetPos.Z)
            else
                if not CamlockState.jumpCatchup then
                    CamlockState.jumpCatchup = true
                    CamlockState.catchupStartTime = tick()
                    CamlockState.catchupStartY = CamlockState.jumpGroundY
                end
                if jd.followAfterDelay then
                    local t = math.clamp((tick() - CamlockState.catchupStartTime) / math.max(0.1, jd.smoothness * 0.5), 0, 1)
                    local eased = 1 - math.pow(1 - t, 3)
                    targetPos = Vector3.new(targetPos.X, CamlockState.catchupStartY + (targetPos.Y - CamlockState.catchupStartY) * eased, targetPos.Z)
                    if t >= 1 then CamlockState.jumpDelaying = false; CamlockState.jumpCatchup = false end
                else
                    CamlockState.jumpDelaying = false
                    targetPos = Vector3.new(targetPos.X, CamlockState.jumpGroundY, targetPos.Z)
                end
            end
        end

        -- Prediction
        if cfg.prediction > 0 and root then
            targetPos = targetPos + root.AssemblyLinearVelocity * cfg.prediction
        end

        -- Distance check
        local myPos = Camera.CFrame.Position
        if (targetPos - myPos).Magnitude > cfg.maxDistance then return end

        -- Smooth aim
        local lookAt = CFrame.new(myPos, targetPos)
        local currentCF = Camera.CFrame
        local lerpFactor = 1 - math.exp(-(0.01 + cfg.smoothness * 0.49) * 60 * dt)
        local newCF = currentCF:Lerp(lookAt, lerpFactor)

        -- Perlin noise
        if Features.CamlockPerlin.enabled then
            newCF = applyPerlin(newCF, currentCF, cfg.smoothness)
        end

        Camera.CFrame = newCF
    end

    if Features.CamlockPerlin.enabled then
        CamlockState.perlinConn = RunService.RenderStepped:Connect(runCamlock)
    else
        CamlockState.camConn = RunService.RenderStepped:Connect(runCamlock)
    end
end

-- Triggerbot loop
local function startTriggerbotLoop()
    RunService.RenderStepped:Connect(function()
        local cfg = Features.TriggerbotConfig
        if not cfg.enabled then
            if not TriggerbotState.clickState then
                mouse1release()
                TriggerbotState.clickState = true
            end
            return
        end
        local mousePos = game:GetService("UserInputService"):GetMouseLocation()
        local ray = Camera:ScreenPointToRay(mousePos.X, mousePos.Y, 0, 0)
        local rp = RaycastParams.new()
        rp.FilterType = Enum.RaycastFilterType.Exclude
        rp.FilterDescendantsInstances = {LocalPlayer.Character}
        local res = workspace:Raycast(ray.Origin, ray.Direction * 500, rp)
        local targetChar = nil
        if res and res.Instance then
            local cur = res.Instance
            while cur and cur ~= workspace do
                if cur:IsA("Model") and cur:FindFirstChildOfClass("Humanoid") then
                    if isValidChar(cur, cfg.targetingMode) and isValidForMode(cur, cfg.priorityOnly, cfg.friendlyLock) then
                        targetChar = cur
                    end
                    break
                end
                cur = cur.Parent
            end
        end
        if targetChar and targetChar.Name ~= LocalPlayer.Name and canShoot(targetChar) then
            mouse1press()
            TriggerbotState.clickState = false
        elseif not TriggerbotState.clickState then
            mouse1release()
            TriggerbotState.clickState = true
        end
    end)
end

-- SOS loop
RunService.RenderStepped:Connect(function()
    if Features.CamlockConfig.shootOnSight and Features.CamlockConfig.enabled then
        checkAndShoot()
    elseif CamlockState.shootHeld then
        mouse1release()
        CamlockState.shootHeld = false
    end
end)

task.spawn(function()
    while true do
        task.wait(1)
        if CamlockState.shootHeld then
            mouse1release()
            CamlockState.shootHeld = false
        end
    end
end)

-- Start triggerbot loop once
startTriggerbotLoop()

--// FEATURES BRIDGE FUNCTIONS (Tab 2)

function Features.camlock_enabled(state)
    Features.CamlockConfig.enabled = state
    if state then
        startCamlockLoop()
    else
        if CamlockState.camConn then CamlockState.camConn:Disconnect() end
        if CamlockState.perlinConn then CamlockState.perlinConn:Disconnect() end
        CamlockState.camConn, CamlockState.perlinConn = nil, nil
        CamlockState.target, CamlockState.targetPart = nil, nil
        if CamlockState.shootHeld then
            mouse1release()
            CamlockState.shootHeld = false
        end
    end
end

function Features.camlock_toggle(active)
    if not Features.CamlockConfig.enabled then return end
    if CamlockState.target then
        CamlockState.target, CamlockState.targetPart = nil, nil
    else
        local t = getTargetUnderMouse(Features.CamlockConfig.targetingMode)
        if t then
            CamlockState.target = t
            CamlockState.targetPart = getAimPart(t)
        end
    end
end

function Features.camlock_targeting_mode(options)
    Features.CamlockConfig.targetingMode = options and options[1] or "Players"
end

function Features.camlock_smoothness(value)
    Features.CamlockConfig.smoothness = value
end

function Features.camlock_prediction(value)
    Features.CamlockConfig.prediction = value
end

function Features.camlock_rig_type(options)
    Features.CamlockConfig.rigType = options and options[1] or "R15"
end

function Features.camlock_hitpart(options)
    Features.CamlockConfig.hitpart = options or {"Head"}
end

function Features.camlock_closest_part(state)
    Features.CamlockConfig.closestPart = state
end

function Features.camlock_closest_point(state)
    Features.CamlockConfig.closestPoint = state
end

function Features.camlock_priority_only(state)
    Features.CamlockConfig.priorityOnly = state
end

function Features.camlock_friendly_lock(state)
    Features.CamlockConfig.friendlyLock = state
end

function Features.camlock_max_distance(value)
    Features.CamlockConfig.maxDistance = value
end

function Features.camlock_visible_check(state)
    Features.CamlockConfig.visibleCheck = state
    if not state then
        CamlockState.pendingTarget, CamlockState.pendingPart = nil, nil
        CamlockState.isPending = false
    end
end

function Features.camlock_visible_interval(value)
    Features.CamlockConfig.visibleInterval = value
end

function Features.camlock_relock_delay(value)
    Features.CamlockConfig.relockDelay = value
end

function Features.camlock_visibility_method(options)
    Features.CamlockConfig.visibilityMethod = options and options[1] or "Camera"
end

function Features.camlock_jump_delay_enabled(state)
    Features.CamlockJumpDelay.enabled = state
    if not state then
        CamlockState.jumpDelaying = false
        CamlockState.jumpJumped = false
        CamlockState.jumpCatchup = false
    end
end

function Features.camlock_jump_delay_ms(value)
    Features.CamlockJumpDelay.delayMs = value
end

function Features.camlock_jump_smoothness(value)
    Features.CamlockJumpDelay.smoothness = value
end

function Features.camlock_jump_follow(state)
    Features.CamlockJumpDelay.followAfterDelay = state
end

function Features.camlock_shoot_on_sight(state)
    Features.CamlockConfig.shootOnSight = state
    if not state and CamlockState.shootHeld then
        mouse1release()
        CamlockState.shootHeld = false
    end
end

function Features.camlock_shoot_mode(options)
    Features.CamlockConfig.shootMode = options and options[1] or "Auto"
end

function Features.camlock_shoot_cps(value)
    Features.CamlockConfig.shootCPS = value
end

function Features.camlock_fov(value)
    Features.CamlockConfig.fov = value
end

-- Perlin
function Features.camlock_perlin_enabled(state)
    Features.CamlockPerlin.enabled = state
    if Features.CamlockConfig.enabled then
        startCamlockLoop()
    end
end

function Features.camlock_perlin_intensity(value)
    Features.CamlockPerlin.intensity = value
end

function Features.camlock_perlin_frequency(value)
    Features.CamlockPerlin.frequency = value
end

function Features.camlock_perlin_x(value)
    Features.CamlockPerlin.xIntensity = value
end

function Features.camlock_perlin_y(value)
    Features.CamlockPerlin.yIntensity = value
end

function Features.camlock_perlin_only_moving(state)
    Features.CamlockPerlin.onlyWhenMoving = state
end

function Features.camlock_perlin_min_smoothness(value)
    Features.CamlockPerlin.minSmoothness = value
end

-- Triggerbot
function Features.triggerbot_enabled(state)
    Features.TriggerbotConfig.enabled = state
end

function Features.triggerbot_toggle(active)
    Features.TriggerbotConfig.enabled = not Features.TriggerbotConfig.enabled
end

function Features.triggerbot_targeting_mode(options)
    Features.TriggerbotConfig.targetingMode = options and options[1] or "Players"
end

function Features.triggerbot_priority_only(state)
    Features.TriggerbotConfig.priorityOnly = state
end

function Features.triggerbot_friendly_lock(state)
    Features.TriggerbotConfig.friendlyLock = state
end

function Features.triggerbot_team_check(state)
    Features.TriggerbotConfig.teamCheck = state
end

function Features.triggerbot_check_teammates(state)
    Features.TriggerbotConfig.checkTeammates = state
end

function Features.triggerbot_check_health(state)
    Features.TriggerbotConfig.checkHealth = state
end

function Features.triggerbot_notify(state)
    Features.TriggerbotConfig.notify = state
end

-- Expose helper for UI
function Features.get_hitpart_options(rigType)
    return getHitpartOptions(rigType or "R15")
end

return Features
