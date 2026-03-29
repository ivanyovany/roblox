--[[
BRAINROT FARMER V236 - ATTRIBUTE TARGETING + HARD PICKUP CONFIRM
Arquitectura: FSM Estricta, DEAD terminal, recovery estable y BURST sellado seguro
st patric copy 3
CAMBIOS V236:
1. Nuevo modo auto por atributos si no se selecciona mutacion manual.
2. Prioridad de target por rareza, luego nivel, luego distancia.
3. Se endurece la confirmacion de pickup con HoldWeld, RenderedBrainrot y RightGrip.
4. Los eventos transitorios del burst ya no confirman pickup con ruido generico.
5. Se mantiene compatibilidad total con el filtro manual por mutacion.

CAMBIOS V235:
1. DEAD es terminal y solo se libera con CharacterAdded estable.
2. Se separa salud minima de arranque y salud minima de recuperacion.
3. El burst usa hold real cuando el prompt lo requiere.
4. Despues del trigger real se libera el character para dejar pasar el carry del servidor.
5. Se confirma pickup por HoldWeld, RenderedBrainrot en character y reparent al jugador.
6. NUEVO: Carry Swap Auto Resume - si la entidad falla DESPUES del trigger, el juego
   esta haciendo un swap de personaje (mecanica carry). En ese caso NO se detiene el
   script en CharacterRemoving, y el farming reanuda automaticamente tras el respawn.
]]

local Players = game:GetService("Players")
local RS = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")

local player = Players.LocalPlayer
local scriptName = "IvanForensicsV236"

local function resolveGuiParent()
    local ok, guiParent = pcall(function()
        return gethui and gethui()
    end)
    if ok and guiParent then
        return guiParent
    end
    return CoreGui
end

local GuiParent = resolveGuiParent()

local function destroyExistingGui()
    local primaryGui = GuiParent and GuiParent:FindFirstChild(scriptName)
    if primaryGui then
        primaryGui:Destroy()
    end

    if GuiParent ~= CoreGui then
        local fallbackGui = CoreGui:FindFirstChild(scriptName)
        if fallbackGui then
            fallbackGui:Destroy()
        end
    end
end

local function copyToClipboard(text)
    if type(setclipboard) == "function" then
        local ok = pcall(setclipboard, text)
        if ok then
            return true
        end
    end

    if type(toclipboard) == "function" then
        local ok = pcall(toclipboard, text)
        if ok then
            return true
        end
    end

    return false
end

if _G.IvanFarmer_Cleanup then _G.IvanFarmer_Cleanup() end
destroyExistingGui()

-- ==============================================================================
-- 1. ESTRUCTURAS BÁSICAS Y UTILIDADES
-- ==============================================================================
local MAX_LOGS = 60
local Connections = {}
local Threads = {}

local Logger = nil

local function reportProtectedError(context, err)
    local message = tostring(err)
    local trace = debug.traceback(message, 2)
    local lines = {}

    for line in string.gmatch(trace, "[^\r\n]+") do
        table.insert(lines, line)
    end

    if Logger then
        Logger.LastErrorLines = lines
        Logger:Log("[SCRIPT_ERROR] " .. tostring(context) .. ": " .. message, Color3.new(1, 0.2, 0.2))
        for index, line in ipairs(lines) do
            if index > 1 then
                Logger:Log("[STACK] " .. tostring(line), Color3.new(1, 0.5, 0.5))
            end
        end
    end

    return message
end

local function connectProtected(event, callback, context)
    return event:Connect(function(...)
        xpcall(callback, function(err)
            return reportProtectedError(context or "EVENT_CALLBACK", err)
        end, ...)
    end)
end

local function safeConnect(event, callback, context)
    local conn = connectProtected(event, callback, context)
    table.insert(Connections, conn)
    return conn
end

local function trackConnection(conn)
    table.insert(Connections, conn)
    return conn
end

local function safeSpawn(context, callback)
    return task.spawn(function()
        xpcall(callback, function(err)
            return reportProtectedError(context or "TASK", err)
        end)
    end)
end

local Config = {
    Activo = false, 
    Mutacion = nil, 
    MinTargetLevel = 0,
    Y_Transito = -3.00, 
    Y_Cobro = -4.00,
    BurstTransitDepth = -6.50,
    Distancia = 3.0, 
    Velocidad = 400, 
    Home = nil,
    HomeSafetyMargin = 2.0,
    StableVyEpsilon = 1.5,
    StablePosEpsilon = 0.35,
    ReleaseStableFrames = 8,
    HomeStableFrames = 6,
    RespawnStableFrames = 12,
    RespawnGuardSeconds = 1.75,
    EmergencyGuardSeconds = 2.25,
    MinStartHealth = 50.0,
    MinRecoverHealth = 1.0,
    BurstMode = "TRANSIT_PLUS_COBRO",
    BurstProbeFree = false,
    BurstFireEvery = 0.10,
    BurstHoldPadding = 0.25,
    AutoReleaseRetryEvery = 0.40,
    BurstConfirmFrames = 3,
    BurstPostTriggerGrace = 0.05,
    BurstCarrySwapAutoResume = true,
    BurstUseStPatricGrab = true,
    BurstStPatricMaxDistance = 100,
    BurstStPatricHeightOffset = -24,
    BurstFallbackFireInHold = false,
    BurstSpoofHoldDuration = false,
    BurstSpoofHoldValue = 0.0,
    BurstCarryConfirmWindow = 2.50,  -- ampliado: espera que server replique reparent
    BurstPromptMaxDistance = 0,
    BurstRapidAttempts = 4,
    BurstHoldAttempts = 2,
    BurstRapidAttemptDelay = 0.08,
    BurstPerAttemptResolveWindow = 0.12,
    BurstPostFireConfirmWindow = 6.50,  -- ampliado: da tiempo al server para procesar tras trigger  -- ampliado: dar tiempo al servidor para adjuntar RenderedBrainrot
    BurstPromptSetupDelay = 0.15,
    BurstClaimSettleWindow = 6.00,
    BurstAllowWorldOnlyConfirm = false,
    CarrySwapResumeConfirmWindow = 4.00,
    CarryClearHomeWindow = 3.00,
    CarryClearPoll = 0.05,
    ReturnApproachDepth = -8.50,
    ReturnSettleDepth = -4.00,
    ReturnHoverDepth = -1.60,
    ReturnStageDelay = 0.08,
    ReturnHoverFree = true,
    ReturnTouchWindow = true,
    ReturnForceUnequip = true,
    ReturnUnequipEvery = 0.20,
    ReturnAt = 2,
    ReturnWhenNoTargets = true,
    PostPickupFieldWindow = 2.00,   -- ampliado: tiempo para detectar RenderedBrainrot en personaje
    PostPickupFieldPoll = 0.05,
    BurstHoldExtra = 0.12,
    BurstPromptRootOffset = 2.80,
    BurstPromptVerticalOffset = -0.90,
    BurstPostTriggerRelease = false,   -- OFF: no liberar personaje después del trigger (evita caída mortal)
    BurstPostFireResolveWindow = 0.80,  -- ampliar ventana de detección de carry attach
    BurstFreeInteractDelay = 0.06,
    BurstReSnapDistance = 2.5,
    BurstHoverHoldEnabled = false,      -- OFF: mantener personaje anclado en lugar de física libre
    BurstHoverMaxVelocity = 60,
    BurstHoverResponsiveness = 28,
    BurstHoverMaxForce = 1000000,
    TargetRetryCooldown = 2.75,
    TargetSuccessCooldown = 1.50,
    BurstSoftResetReasons = {
        NO_PROMPT = true,
        PROMPT_NOT_CONFIRMED = true,
        TRIGGER_WITHOUT_PICKUP_CONFIRM = true,
        TARGET_VANISHED_PRE_CONFIRM = true,
        CLAIM_WITHOUT_CARRY_CONFIRM = true,
        CLAIM_SETTLE_LOST = true
    }
}

local RarityAliases = {
    ["Common"] = "Common",
    ["Uncommon"] = "Uncommon",
    ["Rare"] = "Rare",
    ["Epic"] = "Epic",
    ["Legendary"] = "Legendary",
    ["Mythic"] = "Mythic",
    ["Mythical"] = "Mythic",
    ["Mythicals"] = "Mythic",
    ["Cosmic"] = "Cosmic",
    ["Secret"] = "Secret",
    ["Divine"] = "Divine",
    ["Celestial"] = "Celestial",
    ["Celestials"] = "Celestial",
    ["Infinite"] = "Infinite",
    ["Infinity"] = "Infinite",
    ["Infiniti"] = "Infinite",
    ["Infinitis"] = "Infinite",
    ["Infinites"] = "Infinite",
}

local RarityPriority = {
    ["Infinite"] = 100,
    ["Celestial"] = 95,
    ["Divine"] = 90,
    ["Secret"] = 70,
    ["Cosmic"] = 60,
    ["Mythic"] = 50,
    ["Legendary"] = 40,
    ["Epic"] = 30,
    ["Rare"] = 20,
    ["Uncommon"] = 10,
    ["Common"] = 1,
}

local AllowedTargetRarities = {
    ["Common"] = true,
    ["Uncommon"] = true,
    ["Rare"] = true,
    ["Epic"] = true,
    ["Legendary"] = true,
    ["Mythic"] = true,
    ["Cosmic"] = true,
    ["Secret"] = true,
    ["Divine"] = true,
    ["Celestial"] = true,
    ["Infinite"] = true,
}

local function resolveRarityName(name)
    return RarityAliases[name] or name
end

local function getActiveTargetMode()
    if Config.Mutacion and Config.Mutacion ~= "" then
        return "MUTATION"
    end
    return "ATTRIBUTES"
end

local function getTargetModeSummary()
    if getActiveTargetMode() == "MUTATION" then
        return "mutacion=" .. tostring(Config.Mutacion)
    end
    return string.format("atributos rareza>nivel>dist minLvl=%d", Config.MinTargetLevel or 0)
end

local function tryGetAttribute(instance, attributeName)
    if not instance or not attributeName then
        return nil
    end

    local ok, value = pcall(function()
        return instance:GetAttribute(attributeName)
    end)
    if ok then
        return value
    end
    return nil
end

local function getAttributeFromChain(instance, attributeNames)
    local cursor = instance

    while cursor and cursor ~= game do
        for _, attributeName in ipairs(attributeNames) do
            local value = tryGetAttribute(cursor, attributeName)
            if value ~= nil then
                return value, attributeName, cursor
            end
        end
        cursor = cursor.Parent
    end

    return nil, nil, nil
end

local function parseLevelValue(value)
    if type(value) == "number" then
        return value
    end
    if type(value) == "string" then
        return tonumber(string.match(value, "%d+"))
    end
    return nil
end

local function getTargetLevel(target)
    if not target then
        return 0
    end

    local levelValue = getAttributeFromChain(target, {"Level", "Lvl", "level", "lvl"})
    local parsedLevel = parseLevelValue(levelValue)
    if parsedLevel then
        return parsedLevel
    end

    for _, descendant in ipairs(target:GetDescendants()) do
        local loweredName = string.lower(descendant.Name)
        if loweredName == "level" or loweredName == "lvl" then
            if descendant:IsA("IntValue") or descendant:IsA("NumberValue") then
                return descendant.Value
            elseif descendant:IsA("StringValue") then
                local parsedValue = parseLevelValue(descendant.Value)
                if parsedValue then
                    return parsedValue
                end
            end
        end

        if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
            local parsedText = parseLevelValue(descendant.Text)
            if parsedText then
                return parsedText
            end
        end
    end

    return 0
end

local function getTargetMutation(target)
    local mutationValue = getAttributeFromChain(target, {"Mutation", "mutation"})
    if type(mutationValue) == "string" and mutationValue ~= "" and mutationValue ~= "None" then
        return mutationValue
    end
    return nil
end

local function getTargetRarity(target)
    if not target then
        return "Common"
    end

    local rarityValue = getAttributeFromChain(target, {"Rarity", "RarityName", "Tier", "tier", "Category", "category"})
    if type(rarityValue) == "string" then
        local resolved = resolveRarityName(rarityValue)
        if RarityPriority[resolved] then
            return resolved
        end
    end

    local node = target
    while node and node ~= workspace do
        local resolved = resolveRarityName(node.Name)
        if RarityPriority[resolved] then
            return resolved
        end
        node = node.Parent
    end

    return "Common"
end

local function evaluateTargetCandidate(targetModel, targetRoot, prompt, hrp)
    if not targetModel or not targetRoot or not prompt or not hrp then
        return nil
    end

    local dx = hrp.Position.X - targetRoot.Position.X
    local dz = hrp.Position.Z - targetRoot.Position.Z
    local distanceXZ = math.sqrt(dx * dx + dz * dz)
    local rarityName = getTargetRarity(targetModel)
    local targetLevel = getTargetLevel(targetModel)
    local targetMutation = getTargetMutation(targetModel)

    if getActiveTargetMode() == "MUTATION" then
        if targetMutation ~= Config.Mutacion then
            return nil
        end

        return {
            score = -distanceXZ,
            distance = distanceXZ,
            rarity = rarityName,
            level = targetLevel,
            mutation = targetMutation,
            mode = "MUTATION",
        }
    end

    if not AllowedTargetRarities[rarityName] then
        return nil
    end

    if targetLevel < (Config.MinTargetLevel or 0) then
        return nil
    end

    return {
        score = ((RarityPriority[rarityName] or 0) * 100000) + (targetLevel * 100) - distanceXZ,
        distance = distanceXZ,
        rarity = rarityName,
        level = targetLevel,
        mutation = targetMutation,
        mode = "ATTRIBUTES",
    }
end

-- ==============================================================================
-- 2. CAPA UI & LOGGER (Ring Buffer)
-- ==============================================================================
local UI = { LogLabels = {}, ButtonPool = {}, Minimized = false }
Logger = {
    Buffer = table.create(400, ""), LogIndex = 1,
    Snapshots = table.create(30), SnapIndex = 1,
    LastErrorLines = nil
}

local sg = Instance.new("ScreenGui"); sg.Name = scriptName; sg.ResetOnSpawn = false; sg.Parent = GuiParent
local main = Instance.new("Frame", sg); main.Name = "Main"; main.Size = UDim2.new(0, 260, 0, 315); main.Position = UDim2.new(0.5, -130, 0.28, 0); main.BackgroundColor3 = Color3.fromRGB(15, 15, 15); main.BorderSizePixel = 1; main.ClipsDescendants = true
main.Active = true

local topBar = Instance.new("Frame", main); topBar.Name = "TopBar"; topBar.Size = UDim2.new(1, 0, 0, 30); topBar.BackgroundColor3 = Color3.fromRGB(0, 160, 80)
topBar.Active = true

local title = Instance.new("TextLabel", topBar); title.Size = UDim2.new(1, -34, 1, 0); title.Position = UDim2.new(0, 6, 0, 0); title.BackgroundTransparency = 1; title.Text = "V235 - CARRY SWAP AUTO RESUME"; title.TextColor3 = Color3.new(1,1,1); title.Font = Enum.Font.SourceSansBold; title.TextSize = 14; title.TextXAlignment = Enum.TextXAlignment.Left
local btnToggle = Instance.new("TextButton", topBar); btnToggle.Size = UDim2.new(0, 28, 0, 22); btnToggle.Position = UDim2.new(1, -31, 0, 4); btnToggle.Text = "−"; btnToggle.BackgroundColor3 = Color3.fromRGB(40, 40, 40); btnToggle.TextColor3 = Color3.new(1,1,1)

local logBox = Instance.new("ScrollingFrame", main); logBox.Name = "LogBox"; logBox.Size = UDim2.new(0.9, 0, 0, 130); logBox.Position = UDim2.new(0.05, 0, 0, 128); logBox.BackgroundColor3 = Color3.fromRGB(5, 5, 5); logBox.ScrollBarThickness = 4
local logLayout = Instance.new("UIListLayout", logBox); logLayout.SortOrder = Enum.SortOrder.LayoutOrder; logLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom

local mutScroll = Instance.new("ScrollingFrame", main); mutScroll.Size = UDim2.new(0.9, 0, 0, 82); mutScroll.Position = UDim2.new(0.05, 0, 0, 38); mutScroll.BackgroundColor3 = Color3.fromRGB(20, 20, 20); mutScroll.ScrollBarThickness = 4
local mutLayout = Instance.new("UIListLayout", mutScroll); mutLayout.Padding = UDim.new(0, 2)

local footer = Instance.new("Frame", main); footer.Size = UDim2.new(1, 0, 0, 50); footer.Position = UDim2.new(0, 0, 1, -50); footer.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
local btnAction = Instance.new("TextButton", footer); btnAction.Size = UDim2.new(0.55, 0, 0, 36); btnAction.Position = UDim2.new(0.05, 0, 0, 7); btnAction.Text = "INICIAR"; btnAction.BackgroundColor3 = Color3.fromRGB(0, 150, 50); btnAction.TextColor3 = Color3.new(1,1,1); btnAction.Font = Enum.Font.SourceSansBold
local btnCopy = Instance.new("TextButton", footer); btnCopy.Size = UDim2.new(0.3, 0, 0, 36); btnCopy.Position = UDim2.new(0.65, 0, 0, 7); btnCopy.Text = "COPY"; btnCopy.BackgroundColor3 = Color3.fromRGB(60, 60, 60); btnCopy.TextColor3 = Color3.new(1,1,1); btnCopy.Font = Enum.Font.SourceSansBold

local function refreshTitle()
    local modeLabel = getActiveTargetMode() == "MUTATION"
        and ("MUT " .. tostring(Config.Mutacion))
        or "ATR AUTO"
    title.Text = "V236 - " .. modeLabel
end

for i = 1, MAX_LOGS do
    local lbl = Instance.new("TextLabel", logBox)
    lbl.Size = UDim2.new(1, 0, 0, 14); lbl.BackgroundTransparency = 1; lbl.Text = ""
    lbl.TextColor3 = Color3.new(1,1,1); lbl.TextSize = 9; lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.LayoutOrder = i
    UI.LogLabels[i] = lbl
end

function Logger:Log(msg, color)
    local line = "["..os.date("%X").."] "..msg
    self.Buffer[self.LogIndex] = line
    self.LogIndex = (self.LogIndex % 400) + 1
    
    for i = 1, MAX_LOGS - 1 do
        UI.LogLabels[i].Text = UI.LogLabels[i+1].Text; UI.LogLabels[i].TextColor3 = UI.LogLabels[i+1].TextColor3
    end
    UI.LogLabels[MAX_LOGS].Text = line; UI.LogLabels[MAX_LOGS].TextColor3 = color or Color3.new(1,1,1)
    
    logBox.CanvasSize = UDim2.new(0, 0, 0, logLayout.AbsoluteContentSize.Y)
    logBox.CanvasPosition = Vector2.new(0, 99999)
end

function Logger:Dump(reason)
    self:Log("!!! BLACKBOX DUMP: " .. reason, Color3.new(1, 0.3, 0.3))
    for i = 1, 30 do
        local index = (self.SnapIndex + i - 2) % 30 + 1
        local s = self.Snapshots[index]
        if s then
            local stateA = s.anchored and "ANC" or "FREE"
            self:Log(string.format("-- T-%.2fs | HP:%.0f | Y:%.1f | Vy:%.1f | Ph:%s | DXZ:%.1f | %s",
                tick() - s.t, s.hp, s.y, s.vy, s.phase, s.distXZ, stateA), Color3.new(0.8, 0.8, 0.8))
        end
    end
end

function Logger:BuildCopyPayload()
    local cleanBuffer = {}

    if self.LastErrorLines and #self.LastErrorLines > 0 then
        table.insert(cleanBuffer, "===== LAST_SCRIPT_ERROR =====")
        for _, line in ipairs(self.LastErrorLines) do
            table.insert(cleanBuffer, line)
        end
        table.insert(cleanBuffer, "===== LOG_BUFFER =====")
    end

    for i = 0, 399 do
        local idx = ((self.LogIndex + i - 1) % 400) + 1
        local line = self.Buffer[idx]
        if line and line ~= "" then
            table.insert(cleanBuffer, line)
        end
    end

    return table.concat(cleanBuffer, "\n")
end

-- ==============================================================================
-- 3. CAPA DE MOTOR FÍSICO Y GHOST MODE
-- ==============================================================================
local Motor = { GhostCache = {} }
local TargetCooldowns = setmetatable({}, { __mode = "k" })
local FSM = {
    Phase = "IDLE",
    StateID = 0,
    Session = 0,
    SessionCarryCount = 0,
    TargetRoot = nil,
    TargetPrompt = nil,
    EmergencyTicks = 0,
    LastEmergencyAt = 0,
    LastRespawnAt = 0,
    DeadLatch = false,
    PostTriggerRemovalExpected = false,
    PendingCarrySwap = nil,
    LastStartBlockLogAt = 0,
    LastStabilityPos = nil,
    PendingSafeRelease = false,
    PendingSafeReleaseReason = nil,
    LastReleaseAttemptAt = 0
}

local function GetPromptWorldPosition(prompt, fallback)
    if not prompt then return fallback end

    local parent = prompt.Parent
    if parent then
        if parent:IsA("Attachment") then
            return parent.WorldPosition
        end
        if parent:IsA("BasePart") then
            return parent.Position
        end
        if parent:IsA("Model") and parent.PrimaryPart then
            return parent.PrimaryPart.Position
        end
    end

    return fallback
end

local function FindTargetPrompt(targetModel, targetRoot, promptHint)
    if promptHint and promptHint:IsA("ProximityPrompt") and promptHint:IsDescendantOf(workspace) then
        return promptHint
    end

    local searchRoots = {}
    if targetModel then
        table.insert(searchRoots, targetModel)
    end
    if targetRoot then
        table.insert(searchRoots, targetRoot)
    end
    if targetRoot and targetRoot.Parent and targetRoot.Parent ~= targetModel then
        table.insert(searchRoots, targetRoot.Parent)
    end

    for _, searchRoot in ipairs(searchRoots) do
        if searchRoot then
            local namedPrompt = searchRoot:FindFirstChild("TakePrompt", true)
            if namedPrompt and namedPrompt:IsA("ProximityPrompt") and namedPrompt:IsDescendantOf(workspace) then
                return namedPrompt
            end

            local anyPrompt = searchRoot:FindFirstChildWhichIsA("ProximityPrompt", true)
            if anyPrompt and anyPrompt:IsDescendantOf(workspace) then
                return anyPrompt
            end
        end
    end

    return nil
end

local function GetBurstPickupCFrame(targetRoot, prompt)
    local promptPos = GetPromptWorldPosition(prompt, targetRoot and targetRoot.Position or nil)
    local fallenLimit = workspace.FallenPartsDestroyHeight or -500
    local minSafeY = fallenLimit + 25
    local burstY

    if Config.BurstUseStPatricGrab then
        local baseY = Config.Home and Config.Home.Position.Y
        local safeTravelY = (baseY or promptPos.Y) + (Config.BurstTransitDepth or -6.50)
        local promptOffsetY = promptPos.Y + (Config.BurstStPatricHeightOffset or -24)
        burstY = math.max(safeTravelY, promptOffsetY, minSafeY)
    else
        local desiredY = promptPos.Y + (Config.BurstPromptVerticalOffset or -0.90)

        -- Mantenernos cerca del prompt real para que validen distancia en servidor.
        burstY = math.max(desiredY, minSafeY)
    end

    local burstPos = Vector3.new(promptPos.X, burstY, promptPos.Z)
    local burstLook = Vector3.new(targetRoot.Position.X, burstY, targetRoot.Position.Z)
    if (burstLook - burstPos).Magnitude < 0.01 then
        burstLook = burstPos + Vector3.new(1, 0, 0)
    end

    return CFrame.lookAt(burstPos, burstLook), promptPos
end

local function GetRoutineSafeY()
    return Config.Y_Transito + 1.25
end

function FSM:GetValidEntity()
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not char or not hrp or not hum or hum.Health <= 0 then return nil end
    return char, hrp, hum
end

function FSM:ClearTargets()
    self.TargetRoot = nil
    self.TargetPrompt = nil
end

function FSM:GetTargetCooldownRemaining(targetRoot, prompt)
    local now = tick()
    local rootUntil = (targetRoot and TargetCooldowns[targetRoot]) or 0
    local promptUntil = (prompt and TargetCooldowns[prompt]) or 0
    local expiresAt = math.max(rootUntil, promptUntil)
    if expiresAt > now then
        return expiresAt - now
    end
    return 0
end

function FSM:IsTargetCoolingDown(targetRoot, prompt)
    return self:GetTargetCooldownRemaining(targetRoot, prompt) > 0
end

function FSM:MarkTargetCooldown(targetRoot, prompt, seconds, reason)
    local cooldown = math.max(seconds or 0, 0)
    if cooldown <= 0 then return end

    local expiresAt = tick() + cooldown
    if targetRoot then
        TargetCooldowns[targetRoot] = math.max(TargetCooldowns[targetRoot] or 0, expiresAt)
    end
    if prompt then
        TargetCooldowns[prompt] = math.max(TargetCooldowns[prompt] or 0, expiresAt)
    end

    Logger:Log(string.format("[TARGET_COOLDOWN] %.2fs (%s)", cooldown, tostring(reason or "n/a")), Color3.new(1, 0.7, 0))
end

local function GetOwnedToolCounts()
    local total = 0
    local totalByName = {}
    local backpackByName = {}
    local characterByName = {}
    local backpack = player:FindFirstChildOfClass("Backpack")
    local character = player.Character

    local function collect(container, bucket)
        if not container then return end
        for _, child in ipairs(container:GetChildren()) do
            if child:IsA("Tool") then
                total += 1
                bucket[child.Name] = (bucket[child.Name] or 0) + 1
                totalByName[child.Name] = (totalByName[child.Name] or 0) + 1
            end
        end
    end

    collect(backpack, backpackByName)
    collect(character, characterByName)

    return {
        total = total,
        totalByName = totalByName,
        backpackByName = backpackByName,
        characterByName = characterByName,
    }
end

local function GetOwnedToolTotal()
    return GetOwnedToolCounts().total
end

local function GetPositiveToolDelta(beforeMap, afterMap)
    local delta = 0
    local names = {}

    for name, afterCount in pairs(afterMap or {}) do
        local beforeCount = (beforeMap and beforeMap[name]) or 0
        if afterCount > beforeCount then
            local diff = afterCount - beforeCount
            delta += diff
            table.insert(names, string.format("%s(+%d)", name, diff))
        end
    end

    table.sort(names)
    return delta, table.concat(names, ", ")
end

local function GetChildSignatureCounts(container)
    local counts = {}
    if not container then return counts end

    for _, child in ipairs(container:GetChildren()) do
        local key = string.format("%s|%s", child.ClassName, child.Name
