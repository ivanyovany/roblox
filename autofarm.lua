--[[
BRAINROT FARMER V236 - ATTRIBUTE TARGETING + HARD PICKUP CONFIRM
Arquitectura: FSM Estricta, DEAD terminal, recovery estable y BURST sellado seguro

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
    BurstFallbackFireInHold = false,
    BurstSpoofHoldDuration = true,
    BurstSpoofHoldValue = 0.0,
    BurstCarryConfirmWindow = 2.50,  -- ampliado: espera que server replique reparent
    BurstPromptMaxDistance = 100,
    BurstRapidAttempts = 4,
    BurstHoldAttempts = 2,
    BurstRapidAttemptDelay = 0.08,
    BurstPostFireConfirmWindow = 4.50,  -- ampliado: da tiempo al server para procesar tras trigger  -- ampliado: dar tiempo al servidor para adjuntar RenderedBrainrot
    BurstPromptSetupDelay = 0.15,
    BurstClaimSettleWindow = 5.00,
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

local function GetBurstPickupCFrame(targetRoot, prompt)
    local promptPos = GetPromptWorldPosition(prompt, targetRoot and targetRoot.Position or nil)
    local fallenLimit = workspace.FallenPartsDestroyHeight or -500
    local minSafeY = fallenLimit + 25
    local referenceY = (Config.Home and Config.Home.Position.Y) or promptPos.Y
    local transitDepthY = math.max(referenceY + (Config.BurstTransitDepth or 0), minSafeY)
    local offsetY = promptPos.Y + (Config.BurstPromptRootOffset or 0)

    -- El script que si funciona no se posiciona sobre el prompt; mantiene el HRP a profundidad de transito.
    local burstY = math.min(offsetY, transitDepthY)

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
        local key = string.format("%s|%s", child.ClassName, child.Name)
        counts[key] = (counts[key] or 0) + 1
    end

    return counts
end

local function GetSignatureDelta(beforeMap, afterMap)
    local names = {}

    for key, afterCount in pairs(afterMap or {}) do
        local beforeCount = (beforeMap and beforeMap[key]) or 0
        if afterCount > beforeCount then
            local diff = afterCount - beforeCount
            table.insert(names, string.format("%s(+%d)", key, diff))
        end
    end

    table.sort(names)
    return #names > 0, table.concat(names, ", ")
end

local function IsCarryRelevantDescendant(instance)
    if not instance then return false end
    if instance:IsA("Tool") then
        return true
    end

    local loweredName = string.lower(instance.Name)
    if loweredName == "holdweld" or loweredName == "rightgrip" then
        return true
    end

    if loweredName == "renderedbrainrot" or loweredName:find("brainrot", 1, true) or loweredName:find("carry", 1, true) then
        return true
    end

    if instance:IsA("Weld") or instance:IsA("WeldConstraint") then
        return loweredName == "holdweld" or loweredName == "rightgrip" or loweredName:find("brainrot", 1, true) or loweredName:find("carry", 1, true)
    end

    if instance:IsA("Model") then
        return loweredName == "renderedbrainrot" or loweredName:find("brainrot", 1, true) or loweredName:find("carry", 1, true)
    end

    return false
end

local function GetRelevantDescendantSignatureCounts(container)
    local counts = {}
    if not container then return counts end

    for _, descendant in ipairs(container:GetDescendants()) do
        if IsCarryRelevantDescendant(descendant) then
            local key = string.format("%s|%s", descendant.ClassName, descendant.Name)
            counts[key] = (counts[key] or 0) + 1
        end
    end

    return counts
end

local function FormatSignalCounts(signalMap, limit)
    local items = {}
    for key, count in pairs(signalMap or {}) do
        if count > 1 then
            table.insert(items, string.format("%s(x%d)", key, count))
        else
            table.insert(items, key)
        end
    end

    table.sort(items)
    if limit and #items > limit then
        while #items > limit do
            table.remove(items)
        end
    end
    return table.concat(items, ", ")
end

local function GetEquippedTool(character)
    if not character then return nil end
    return character:FindFirstChildOfClass("Tool")
end

local function LooksLikeGuid(text)
    if type(text) ~= "string" then
        return false
    end

    return string.match(text, "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil
end

local function GetHomeStageCFrame(homeCF, yOffset)
    if not homeCF then
        return nil
    end

    local stagePos = homeCF.Position + Vector3.new(0, yOffset or 0, 0)
    local flatLook = Vector3.new(homeCF.LookVector.X, 0, homeCF.LookVector.Z)
    if flatLook.Magnitude < 0.01 then
        flatLook = Vector3.new(0, 0, -1)
    else
        flatLook = flatLook.Unit
    end

    return CFrame.lookAt(stagePos, stagePos + flatLook)
end

local function ForceUnequipTools(humanoid)
    if not humanoid then
        return false
    end

    local equippedBefore = GetEquippedTool(player.Character)
    pcall(function()
        humanoid:UnequipTools()
    end)

    if not equippedBefore then
        return true
    end

    local deadline = tick() + 0.35
    while tick() < deadline do
        if not GetEquippedTool(player.Character) then
            return true
        end
        task.wait(0.05)
    end

    return GetEquippedTool(player.Character) == nil
end

local function TryUnequipEquippedTool(humanoid, reasonTag)
    local liveChar = player.Character
    local equippedTool = GetEquippedTool(liveChar)
    if not humanoid or not equippedTool then
        return false, nil
    end

    local toolName = tostring(equippedTool.Name)
    local unequipped = ForceUnequipTools(humanoid)
    if unequipped then
        Logger:Log("[UNEQUIP_OK] " .. tostring(reasonTag or "n/a") .. ": " .. toolName, Color3.new(0, 1, 0))
        return true, toolName
    end

    return false, toolName
end

local function GetLiveCarryState()
    local liveChar = player.Character
    if not liveChar then
        return false, nil
    end

    local liveRoot = liveChar:FindFirstChild("HumanoidRootPart")
    if liveRoot then
        local holdWeld = liveRoot:FindFirstChild("HoldWeld")
        if holdWeld and holdWeld:IsA("Weld") then
            return true, "HOLD_WELD"
        end
    end

    local rendered = liveChar:FindFirstChild("RenderedBrainrot") or liveChar:FindFirstChild("RenderedBrainrot", true)
    if rendered and rendered:IsA("Model") then
        return true, "RENDERED_BRAINROT"
    end

    local rightGrip = liveChar:FindFirstChild("RightGrip", true)
    local equippedTool = GetEquippedTool(liveChar)
    if rightGrip and rightGrip:IsA("Weld") and equippedTool then
        if LooksLikeGuid(equippedTool.Name) then
            return false, "EQUIPPED_UUID_TOOL:" .. tostring(equippedTool.Name)
        end
        return true, "RIGHT_GRIP:" .. tostring(equippedTool.Name)
    end

    return false, nil
end

function FSM:HasPendingCarrySwap()
    return self.PendingCarrySwap ~= nil
end

function FSM:MarkCarrySwapPending(payload)
    local pending = self.PendingCarrySwap or {}
    pending.toolSnapshotBefore = (payload and payload.toolSnapshotBefore) or pending.toolSnapshotBefore
    pending.characterChildrenBefore = (payload and payload.characterChildrenBefore) or pending.characterChildrenBefore
    pending.characterDescendantsBefore = (payload and payload.characterDescendantsBefore) or pending.characterDescendantsBefore
    pending.targetRoot = (payload and payload.targetRoot) or pending.targetRoot
    pending.targetModel = (payload and payload.targetModel) or pending.targetModel
    pending.prompt = (payload and payload.prompt) or pending.prompt
    pending.claimReason = (payload and payload.claimReason) or pending.claimReason
    pending.lossReason = (payload and payload.lossReason) or pending.lossReason
    pending.markedAt = tick()

    self.PendingCarrySwap = pending
    self.PostTriggerRemovalExpected = true
end

function FSM:ClearPendingCarrySwap()
    self.PendingCarrySwap = nil
end

function FSM:WaitForCarrySwapResolution()
    local pending = self.PendingCarrySwap
    if not pending or not pending.toolSnapshotBefore then
        return false, "NO_PENDING_SWAP"
    end

    local function getSwapWorldClaimConfirmation()
        local activeFolder = workspace:FindFirstChild("ActiveBrainrots")

        if pending.targetRoot then
            if activeFolder and not pending.targetRoot:IsDescendantOf(activeFolder) then
                return true, "SWAP_CLAIM_WORLD_OK: target salio de ActiveBrainrots"
            end
            if not pending.targetRoot:IsDescendantOf(workspace) then
                return true, "SWAP_TARGET_REMOVED_OK"
            end
        end

        if pending.prompt then
            if not pending.prompt:IsDescendantOf(workspace) then
                return true, "SWAP_PROMPT_MISSING_OK"
            end
            if pending.targetModel and not pending.prompt:IsDescendantOf(pending.targetModel) then
                return true, "SWAP_PROMPT_REPARENT_OK"
            end
            if activeFolder and not pending.prompt:IsDescendantOf(activeFolder) then
                return true, "SWAP_PROMPT_FOLDER_EXIT_OK"
            end
        end

        return false, nil
    end

    local function getSwapDirectCarryConfirmation(liveChar)
        if not liveChar then return false, nil end

        local liveRoot = liveChar:FindFirstChild("HumanoidRootPart")
        if liveRoot then
            local holdWeld = liveRoot:FindFirstChild("HoldWeld")
            if holdWeld and holdWeld:IsA("Weld") then
                return true, "SWAP_HOLD_WELD_OK"
            end
        end

        local rendered = liveChar:FindFirstChild("RenderedBrainrot") or liveChar:FindFirstChild("RenderedBrainrot", true)
        if rendered and rendered:IsA("Model") then
            return true, "SWAP_RENDERED_OK"
        end

        local rightGrip = liveChar:FindFirstChild("RightGrip", true)
        local equippedTool = GetEquippedTool(liveChar)
        if rightGrip and rightGrip:IsA("Weld") and equippedTool then
            return true, "SWAP_RIGHT_GRIP_OK: " .. tostring(equippedTool.Name)
        end

        if pending.targetRoot and pending.targetRoot:IsDescendantOf(liveChar) then
            return true, "SWAP_TARGET_ON_CHAR_OK"
        end

        if pending.targetModel and pending.targetModel.Parent == liveChar then
            return true, "SWAP_TARGET_MODEL_PARENT_CHAR_OK"
        end

        if pending.targetModel and pending.targetModel:IsDescendantOf(liveChar) then
            return true, "SWAP_TARGET_MODEL_ON_CHAR_OK"
        end

        if pending.prompt and pending.prompt:IsDescendantOf(liveChar) then
            if pending.prompt.Enabled == false then
                return true, "SWAP_PROMPT_ON_CHAR_DISABLED_OK"
            end
            return true, "SWAP_PROMPT_ON_CHAR_OK"
        end

        return false, nil
    end

    local deadline = tick() + Config.CarrySwapResumeConfirmWindow
    while tick() < deadline do
        local worldOk, worldReason = getSwapWorldClaimConfirmation()
        if worldOk then
            return true, worldReason
        end

        local liveChar, _, _ = self:GetValidEntity()
        if liveChar then
            local directOk, directReason = getSwapDirectCarryConfirmation(liveChar)
            if directOk then
                return true, directReason
            end

            local toolSnapshotNow = GetOwnedToolCounts()
            local equippedDelta, equippedNames = GetPositiveToolDelta(pending.toolSnapshotBefore.characterByName, toolSnapshotNow.characterByName)
            if equippedDelta > 0 then
                return true, "SWAP_TOOL_EQUIPPED_OK: " .. tostring(equippedNames ~= "" and equippedNames or equippedDelta)
            end

            local totalDelta, totalNames = GetPositiveToolDelta(pending.toolSnapshotBefore.totalByName, toolSnapshotNow.totalByName)
            if totalDelta > 0 then
                return true, "SWAP_TOOL_DELTA_OK: " .. tostring(totalNames ~= "" and totalNames or totalDelta)
            end

            local equippedTool = GetEquippedTool(liveChar)
            local rightGrip = liveChar:FindFirstChild("RightGrip", true)
            if equippedTool and rightGrip and rightGrip:IsA("Weld") then
                local beforeCount = (pending.toolSnapshotBefore.totalByName and pending.toolSnapshotBefore.totalByName[equippedTool.Name]) or 0
                local afterCount = (toolSnapshotNow.totalByName and toolSnapshotNow.totalByName[equippedTool.Name]) or 0
                if afterCount > beforeCount then
                    return true, "SWAP_RIGHT_GRIP_OK: " .. tostring(equippedTool.Name)
                end
            end

            local hasDescDelta, descDeltaNames = GetSignatureDelta(pending.characterDescendantsBefore, GetRelevantDescendantSignatureCounts(liveChar))
            if hasDescDelta then
                return true, "SWAP_CHAR_DESC_OK: " .. tostring(descDeltaNames)
            end

            local hasChildDelta, childDeltaNames = GetSignatureDelta(pending.characterChildrenBefore, GetChildSignatureCounts(liveChar))
            if hasChildDelta then
                return true, "SWAP_CHAR_ATTACH_OK: " .. tostring(childDeltaNames)
            end
        end

        task.wait(0.10)
    end

    return false, "SWAP_NO_TOOL_CONFIRM"
end

function FSM:RequestSafeRelease(reason)
    if self.DeadLatch or self.Phase == "DEAD" then
        return
    end

    self.PendingSafeRelease = true
    self.PendingSafeReleaseReason = reason or "Deferred Release"
end

function FSM:IsHomeCFrameSafe(homeCF)
    return homeCF and homeCF.Position.Y > (Config.Y_Transito + Config.HomeSafetyMargin)
end

function FSM:CheckStabilitySample(hrp, hum, previousPos, opts)
    opts = opts or {}

    if not hrp or not hrp.Parent or not hum or hum.Health <= 0 then
        return false, "NO_ENTITY", previousPos
    end

    local minY = opts.minY or (Config.Y_Transito + 1.0)
    local minHealth = opts.minHealth or Config.MinRecoverHealth
    local requireAnchored = opts.requireAnchored == true
    local vy = math.abs(hrp.AssemblyLinearVelocity.Y)
    local pos = hrp.Position
    local delta = previousPos and (pos - previousPos).Magnitude or 0

    if requireAnchored and not hrp.Anchored then
        return false, "NOT_ANCHORED", pos
    end
    if pos.Y <= minY then
        return false, "LOW_Y", pos
    end
    if hum.Health < minHealth then
        return false, "LOW_HP", pos
    end
    if vy > Config.StableVyEpsilon then
        return false, "HIGH_VY", pos
    end
    if previousPos and delta > Config.StablePosEpsilon then
        return false, "POS_DRIFT", pos
    end

    return true, "STABLE", pos
end

function FSM:WaitForStableWindow(requiredFrames, opts)
    local stableFrames = 0
    local missingFrames = 0
    local previousPos = nil
    local maxFrames = (opts and opts.maxFrames) or math.max(requiredFrames * 5, requiredFrames + 8)
    local allowMissingEntityFrames = (opts and opts.allowMissingEntityFrames) or 0
    local lastReason = "INIT"

    for _ = 1, maxFrames do
        local _, hrp, hum = self:GetValidEntity()
        if not hrp or not hum then
            stableFrames = 0
            missingFrames += 1
            lastReason = "NO_ENTITY"
            if missingFrames > allowMissingEntityFrames then
                return false, "NO_ENTITY"
            end
            RS.Heartbeat:Wait()
            continue
        end

        missingFrames = 0

        local ok, reason, nextPos = self:CheckStabilitySample(hrp, hum, previousPos, opts)
        previousPos = nextPos
        if ok then
            stableFrames += 1
            if stableFrames >= requiredFrames then
                return true, "STABLE"
            end
        else
            stableFrames = 0
            lastReason = reason
        end

        RS.Heartbeat:Wait()
    end

    return false, lastReason
end

function FSM:IsRoutineBlocked()
    local now = tick()

    if self.DeadLatch or self.Phase == "DEAD" then
        return true, "DEAD_LATCH"
    end
    if (now - (self.LastRespawnAt or 0)) < Config.RespawnGuardSeconds then
        return true, "RESPAWN_GUARD"
    end
    if (now - (self.LastEmergencyAt or 0)) < Config.EmergencyGuardSeconds then
        return true, "EMERGENCY_GUARD"
    end

    local _, hrp, hum = self:GetValidEntity()
    if not hrp or not hum then
        return true, "NO_ENTITY"
    end

    local equippedTool = GetEquippedTool(player.Character)
    if equippedTool then
        local clearedTool = TryUnequipEquippedTool(hum, "START")
        if clearedTool then
            equippedTool = GetEquippedTool(player.Character)
        end
    end

    local carryActive, carryReason = GetLiveCarryState()
    if carryActive then
        return true, "CARRY_ACTIVE_" .. tostring(carryReason)
    end
    if equippedTool then
        if LooksLikeGuid(equippedTool.Name) then
            return false, "UUID_TOOL_IGNORED"
        end
        return true, "TOOL_EQUIPPED_" .. tostring(equippedTool.Name)
    end
    if hum.Health < Config.MinStartHealth then
        return true, "LOW_HP_START"
    end

    local stable, reason = self:CheckStabilitySample(hrp, hum, nil, {
        minY = Config.Y_Transito + 1.0,
        minHealth = Config.MinStartHealth,
        requireAnchored = true
    })
    if not stable then
        return true, reason
    end

    return false, "READY"
end

function FSM:GetSessionCarryCount()
    return math.max(self.SessionCarryCount or 0, 0)
end

function FSM:HasStoredSessionCarry()
    return self:GetSessionCarryCount() > 0
end

function FSM:ResetSessionCarry(reason)
    local previous = self:GetSessionCarryCount()
    self.SessionCarryCount = 0

    if previous > 0 and reason then
        Logger:Log(string.format("[SESSION_CARRY_RESET] %s prev=%d", tostring(reason), previous), Color3.new(0, 1, 1))
    end
end

function FSM:RecordSessionPickup(reason)
    self.SessionCarryCount = self:GetSessionCarryCount() + 1
    Logger:Log(string.format("[SESSION_CARRY] %d/%d (%s)", self.SessionCarryCount, math.max(Config.ReturnAt or 1, 1), tostring(reason or "pickup")), Color3.new(0, 1, 1))
    return self.SessionCarryCount
end

function FSM:HandleBurstSoftReset(reason)
    local liveChar, liveRoot, liveHum = self:GetValidEntity()
    if liveChar and liveRoot then
        if liveHum and liveHum.Health < Config.MinStartHealth and self:IsHomeCFrameSafe(Config.Home) then
            self:RecoverToSafeHome(liveRoot, liveChar)
            Logger:Log(string.format("[BURST_SOFT_RECOVER_HOME] hp=%.1f", liveHum.Health), Color3.new(1, 0.8, 0))
        else
            local flatLook = Vector3.new(liveRoot.CFrame.LookVector.X, 0, liveRoot.CFrame.LookVector.Z)
            if flatLook.Magnitude < 0.01 then
                flatLook = Vector3.new(0, 0, -1)
            else
                flatLook = flatLook.Unit
            end

            local resetPos = Vector3.new(liveRoot.Position.X, math.max(liveRoot.Position.Y, GetRoutineSafeY()), liveRoot.Position.Z)
            local resetCF = CFrame.lookAt(resetPos, resetPos + flatLook)
            Motor:TeleportCharacter(liveChar, liveRoot, resetCF, true)
            Logger:Log(string.format("[BURST_LOCAL_RESET] y=%.2f", resetPos.Y), Color3.new(1, 0.8, 0))
        end
    end

    Logger:Log("[BURST_SOFT_RESET] " .. tostring(reason), Color3.new(1, 0.6, 0))
    self:TransitionTo("IDLE", "Burst Soft Reset")
end

function FSM:WaitForFieldPickupStow()
    local deadline = tick() + math.max(Config.PostPickupFieldWindow or 0, 0)
    local lastUnequipAt = 0

    while tick() < deadline do
        local liveChar, liveRoot, liveHum = self:GetValidEntity()
        if not liveChar or not liveRoot or not liveHum then
            return false, "NO_ENTITY"
        end

        Motor:SealCharacter(liveRoot)
        local flatLook = Vector3.new(liveRoot.CFrame.LookVector.X, 0, liveRoot.CFrame.LookVector.Z)
        if flatLook.Magnitude < 0.01 then
            flatLook = Vector3.new(0, 0, -1)
        else
            flatLook = flatLook.Unit
        end
        local safeY = math.max(liveRoot.Position.Y, GetRoutineSafeY())
        if math.abs(liveRoot.Position.Y - safeY) > 0.05 then
            local safePos = Vector3.new(liveRoot.Position.X, safeY, liveRoot.Position.Z)
            pcall(function()
                liveChar:PivotTo(CFrame.lookAt(safePos, safePos + flatLook))
            end)
        end
        Motor:StopMotion(liveRoot)

        local carryActive, carryReason = GetLiveCarryState()
        local equippedTool = GetEquippedTool(liveChar)
        if (carryActive or equippedTool) and (tick() - lastUnequipAt) >= (Config.ReturnUnequipEvery or 0.20) then
            lastUnequipAt = tick()
            ForceUnequipTools(liveHum)
            carryActive, carryReason = GetLiveCarryState()
            equippedTool = GetEquippedTool(liveChar)
        end

        if not carryActive then
            if equippedTool and LooksLikeGuid(equippedTool.Name) then
                ForceUnequipTools(liveHum)
                equippedTool = GetEquippedTool(liveChar)
            end

            if not equippedTool then
                return true, "FIELD_STOW_CLEAR"
            end

            if equippedTool and LooksLikeGuid(equippedTool.Name) then
                return true, "FIELD_STOW_UUID"
            end
        end

        task.wait(Config.PostPickupFieldPoll or 0.05)
    end

    local carryActive, carryReason = GetLiveCarryState()
    if not carryActive then
        local _, _, liveHum = self:GetValidEntity()
        if liveHum then
            ForceUnequipTools(liveHum)
        end

        local equippedTool = GetEquippedTool(player.Character)
        if not equippedTool or LooksLikeGuid(equippedTool.Name) then
            return true, "FIELD_STOW_LATE"
        end
    end

    return false, carryReason or "FIELD_STOW_TIMEOUT"
end

function FSM:RunHomeReturn(targetRoot, prompt, transitionReason, cooldownReason)
    self:TransitionTo("RETURN", transitionReason or "Safe Extract")

    local _, hrpAfter = self:GetValidEntity()
    if not hrpAfter then
        if self.Phase == "RETURN" then self:TransitionTo("EMERGENCY", "POST_RETURN_NO_ENTITY") end
        return false, "NO_ENTITY"
    end
    if not self:IsHomeCFrameSafe(Config.Home) then
        if self.Phase == "RETURN" then self:TransitionTo("EMERGENCY", "HOME_INVALID") end
        return false, "HOME_INVALID"
    end

    local clearedCarry, carryClearReason = self:ExecuteHomeUnloadSequence()
    if not clearedCarry and (carryClearReason == "HOME_INVALID" or carryClearReason == "NO_ENTITY") then
        if self.Phase == "RETURN" then self:TransitionTo("EMERGENCY", carryClearReason) end
        return false, carryClearReason
    end
    if clearedCarry then
        Logger:Log("[RETURN_CLEAR] carry descargado", Color3.new(0, 1, 0))
        local _, _, clearHum = self:GetValidEntity()
        if clearHum then
            TryUnequipEquippedTool(clearHum, cooldownReason or "RETURN_CLEAR")
        end
        self:ResetSessionCarry(cooldownReason or "RETURN_CLEAR")
    else
        Logger:Log("[RETURN_CLEAR_PENDING] " .. tostring(carryClearReason), Color3.new(1, 0.8, 0))
    end
    self:MarkTargetCooldown(targetRoot, prompt, Config.TargetSuccessCooldown, clearedCarry and (cooldownReason or "SUCCESS_SETTLE") or ("SUCCESS_PENDING_" .. tostring(carryClearReason)))

    self:TransitionTo("IDLE", clearedCarry and "Farm Success" or "Return Pending")
    local _, safeRoot = self:GetValidEntity()
    if safeRoot then
        Motor:SealCharacter(safeRoot)
    end
    if not Config.Activo then
        self:ReleaseCharacterIfSafe(clearedCarry and "Farm Success" or "Return Pending")
    elseif not clearedCarry then
        Logger:Log("[CYCLE_BLOCKED] esperando descarga home", Color3.new(1, 0.8, 0))
    else
        Logger:Log("[CYCLE_READY_SEALED]", Color3.new(0, 1, 0))
    end

    return clearedCarry, carryClearReason
end

function FSM:WaitForCarryClearWindow(hoverCFrame)
    local carryActive, carryReason = GetLiveCarryState()
    if not carryActive then
        return true, "CLEAR"
    end

    local deadline = tick() + math.max(Config.CarryClearHomeWindow or 0, 0)
    local lastUnequipAt = 0
    local touchWindowArmed = false

    while tick() < deadline do
        local liveChar, liveRoot, liveHum = self:GetValidEntity()
        if not liveChar or not liveRoot or not liveHum then
            return false, "NO_ENTITY"
        end

        if hoverCFrame then
            if Config.ReturnTouchWindow then
                Motor:SetGhostTouchWindow(true)
                touchWindowArmed = true
            end

            if Config.ReturnHoverFree then
                if liveRoot.Anchored then
                    Motor:ReleaseCharacter(liveRoot)
                end
                pcall(function()
                    liveChar:PivotTo(hoverCFrame)
                end)
                Motor:StopMotion(liveRoot)
            else
                Motor:TeleportCharacter(liveChar, liveRoot, hoverCFrame, true)
            end

            if Config.ReturnForceUnequip and (tick() - lastUnequipAt) >= (Config.ReturnUnequipEvery or 0.20) then
                lastUnequipAt = tick()
                ForceUnequipTools(liveHum)
            end
        end

        carryActive, carryReason = GetLiveCarryState()
        if not carryActive then
            if touchWindowArmed then
                Motor:SetGhostTouchWindow(false)
            end
            local _, endRoot = self:GetValidEntity()
            if endRoot then
                Motor:SealCharacter(endRoot)
            end
            return true, "CLEAR"
        end
        task.wait(Config.CarryClearPoll or 0.05)
    end

    if touchWindowArmed then
        Motor:SetGhostTouchWindow(false)
    end
    local endChar, endRoot = self:GetValidEntity()
    if endChar and endRoot and hoverCFrame then
        pcall(function()
            endChar:PivotTo(hoverCFrame)
        end)
        Motor:StopMotion(endRoot)
        Motor:SealCharacter(endRoot)
    end

    return false, carryReason or "CARRY_STILL_ACTIVE"
end

function FSM:ExecuteHomeUnloadSequence()
    if not self:IsHomeCFrameSafe(Config.Home) then
        return false, "HOME_INVALID"
    end

    local tunnelStage = GetHomeStageCFrame(Config.Home, Config.ReturnApproachDepth)
    local settleStage = GetHomeStageCFrame(Config.Home, Config.ReturnSettleDepth)
    local hoverStage = GetHomeStageCFrame(Config.Home, Config.ReturnHoverDepth)
    local stageDelay = math.max(Config.ReturnStageDelay or 0, 0)
    local stages = {
        { name = "TUNNEL", cframe = tunnelStage, anchored = true },
        { name = "SETTLE", cframe = settleStage, anchored = true },
        { name = "HOVER", cframe = hoverStage, anchored = not Config.ReturnHoverFree },
    }

    Logger:Log("[RETURN_MODE] HOME_UNLOAD_STAGES", Color3.new(0, 1, 1))

    for _, stage in ipairs(stages) do
        local liveChar, liveRoot = self:GetValidEntity()
        if not liveChar or not liveRoot then
            return false, "NO_ENTITY"
        end

        if stage.name == "HOVER" and Config.ReturnTouchWindow then
            Motor:SetGhostTouchWindow(true)
            Logger:Log("[RETURN_TOUCH_WINDOW] canTouch=ON", Color3.new(0, 1, 1))
        end

        Motor:TeleportCharacter(liveChar, liveRoot, stage.cframe, stage.anchored)
        Logger:Log(string.format("[RETURN_STAGE] %s y=%.2f anchored=%s", stage.name, stage.cframe.Position.Y, tostring(stage.anchored)), Color3.new(0, 1, 1))

        if stageDelay > 0 then
            task.wait(stageDelay)
        end
    end

    return self:WaitForCarryClearWindow(hoverStage)
end

function Motor:StopMotion(hrp)
    if not hrp then return end
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero
end

function Motor:SetAnchored(hrp, anchored)
    if not hrp then return end
    self:StopMotion(hrp)
    hrp.Anchored = anchored and true or false
    if anchored then
        self:StopMotion(hrp)
    end
end

function Motor:SealCharacter(hrp)
    self:SetAnchored(hrp, true)
end

function Motor:ReleaseCharacter(hrp)
    self:SetAnchored(hrp, false)
end

function Motor:TeleportCharacter(char, hrp, targetCFrame, anchoredAfter)
    if not char or not hrp or not targetCFrame then return false end
    self:SealCharacter(hrp)
    char:PivotTo(targetCFrame)
    RS.Heartbeat:Wait()
    self:StopMotion(hrp)
    hrp.Anchored = anchoredAfter ~= false
    return true
end

function Motor:GetBurstHoverRig(hrp)
    if not hrp then
        return nil, nil
    end

    return hrp:FindFirstChild("IvanBurstHoverAttachment"), hrp:FindFirstChild("IvanBurstHoverAlign")
end

function Motor:DestroyBurstHoverRig(hrp)
    local attachment, align = self:GetBurstHoverRig(hrp)
    if align then
        align:Destroy()
    end
    if attachment then
        attachment:Destroy()
    end
end

function Motor:EnsureBurstHoverRig(hrp)
    if not hrp then
        return nil, nil
    end

    local attachment, align = self:GetBurstHoverRig(hrp)
    if not attachment then
        attachment = Instance.new("Attachment")
        attachment.Name = "IvanBurstHoverAttachment"
        attachment.Parent = hrp
    end
    if not align then
        align = Instance.new("AlignPosition")
        align.Name = "IvanBurstHoverAlign"
        align.Mode = Enum.PositionAlignmentMode.OneAttachment
        align.Attachment0 = attachment
        align.ApplyAtCenterOfMass = true
        align.RigidityEnabled = false
        align.MaxVelocity = Config.BurstHoverMaxVelocity
        align.Responsiveness = Config.BurstHoverResponsiveness
        align.MaxForce = Config.BurstHoverMaxForce
        align.Parent = hrp
    end

    return attachment, align
end

function Motor:SetGhostMode(enable)
    local char = FSM:GetValidEntity()
    if not char then return end
    if enable then
        table.clear(self.GhostCache)
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.CanCollide then
                self.GhostCache[part] = { CanCollide = part.CanCollide, CanTouch = part.CanTouch }
                part.CanCollide = false; part.CanTouch = false
            end
        end
    else
        for part, props in pairs(self.GhostCache) do
            if part and part.Parent then
                part.CanCollide = props.CanCollide; part.CanTouch = props.CanTouch
            end
        end
        table.clear(self.GhostCache)
    end
end

function Motor:SetGhostTouchWindow(enabled)
    for part, _ in pairs(self.GhostCache) do
        if part and part.Parent then
            part.CanCollide = false
            part.CanTouch = enabled and true or false
        end
    end
end

-- ==============================================================================
-- 4. FUNCIONES DE RECUPERACIÓN Y SEGURIDAD (LAS QUE PEDISTE)
-- ==============================================================================
function FSM:ReleaseCharacterIfSafe(context)
    local char, hrp, hum = self:GetValidEntity()
    if not hrp then return false, "NO_ENTITY" end

    if self.Phase ~= "IDLE" then
        Logger:Log("[RELEASE_BLOCKED] Phase=" .. self.Phase, Color3.new(1, 0.5, 0))
        return false, "PHASE_" .. self.Phase
    end

    if self.DeadLatch then
        Logger:Log("[RELEASE_BLOCKED] DEAD_LATCH", Color3.new(1, 0.3, 0.3))
        return false, "DEAD_LATCH"
    end

    if (tick() - (self.LastRespawnAt or 0)) < Config.RespawnGuardSeconds then
        Logger:Log("[RELEASE_BLOCKED] RESPAWN_GUARD", Color3.new(1, 0.5, 0))
        return false, "RESPAWN_GUARD"
    end

    if (tick() - (self.LastEmergencyAt or 0)) < Config.EmergencyGuardSeconds then
        Logger:Log("[RELEASE_BLOCKED] EMERGENCY_GUARD", Color3.new(1, 0.5, 0))
        return false, "EMERGENCY_GUARD"
    end

    local ok, reason = self:WaitForStableWindow(Config.ReleaseStableFrames, {
        minY = Config.Y_Transito + 1.0,
        minHealth = Config.MinRecoverHealth,
        requireAnchored = true,
        maxFrames = 48
    })

    if ok then
        Motor:ReleaseCharacter(hrp)
        self.PendingSafeRelease = false
        self.PendingSafeReleaseReason = nil
        Logger:Log("[RELEASE_OK] " .. tostring(context), Color3.new(0, 1, 0))
        return true, "OK"
    else
        Motor:SealCharacter(hrp)
        Logger:Log("[RELEASE_BLOCKED] " .. tostring(reason), Color3.new(1, 0.5, 0))
        return false, reason
    end
end

function FSM:SaveHomeIfSafe(hrp)
    local ok, reason = self:WaitForStableWindow(Config.HomeStableFrames, {
        minY = Config.Y_Transito + Config.HomeSafetyMargin,
        minHealth = Config.MinRecoverHealth,
        requireAnchored = true,
        maxFrames = 36
    })

    if ok then
        Config.Home = hrp.CFrame
        Logger:Log("Home Fijado: Y=" .. string.format("%.1f", Config.Home.Y), Color3.new(0, 1, 0))
    else
        Logger:Log("[HOME_REJECTED] " .. tostring(reason), Color3.new(1, 0.5, 0))
    end
end

function FSM:RecoverToSafeHome(hrp, char)
    Motor:SealCharacter(hrp)
    if self:IsHomeCFrameSafe(Config.Home) then
        Motor:TeleportCharacter(char, hrp, Config.Home + Vector3.new(0, 3, 0), true)
        Logger:Log("[RECOVERY] Teleport a Home Seguro", Color3.new(0, 1, 1))
    else
        Motor:TeleportCharacter(char, hrp, hrp.CFrame + Vector3.new(0, math.abs(hrp.Position.Y) + 15, 0), true)
        Logger:Log("[RECOVERY_FALLBACK] Teleport hacia arriba", Color3.new(1, 0.5, 0))
    end
end

function FSM:StopSafely()
    if self.DeadLatch or self.Phase == "DEAD" then
        Logger:Log("[STOP_BLOCKED] DEAD terminal hasta respawn estable", Color3.new(1, 0.3, 0.3))
        return
    end

    local char, hrp, hum = self:GetValidEntity()
    if hrp then
        if hrp.Position.Y <= (Config.Y_Transito + 1.0) then
            Logger:Log("[STOP] Subterráneo detectado. Rescatando...", Color3.new(1, 0.5, 0))
            self:RecoverToSafeHome(hrp, char)
        else
            Motor:SealCharacter(hrp)
        end
    end
    self:TransitionTo("IDLE", "Manual Stop")
    if hum and hum.Health >= Config.MinStartHealth then
        local released = self:ReleaseCharacterIfSafe("Manual Stop")
        if not released then
            self:RequestSafeRelease("Manual Stop Deferred")
        end
    else
        self:RequestSafeRelease("Manual Stop Low HP")
        Logger:Log("[STOP_SEALED_LOW_HP]", Color3.new(1, 0.5, 0))
    end
end

function FSM:TransitionTo(newPhase, reason, extraCFrame)
    if self.Phase == newPhase then return end

    if self.Phase == "DEAD" and newPhase ~= "DEAD" and reason ~= "CharacterAdded Stable" and reason ~= "Cleanup" then
        Logger:Log("[FSM_BLOCKED] DEAD terminal -> " .. newPhase, Color3.new(1, 0.3, 0.3))
        return
    end

    Logger:Log(string.format("[FSM] %s -> %s (%s)", self.Phase, newPhase, reason or "Auto"), Color3.fromRGB(150, 150, 250))
    
    self.Phase = newPhase
    self.StateID = self.StateID + 1 
    self.LastStabilityPos = nil
    
    if newPhase == "IDLE" or newPhase == "EMERGENCY" or newPhase == "DEAD" then
        Motor:SetGhostMode(false)
    end
    
    if newPhase == "IDLE" then 
        self:ClearTargets()
        self.EmergencyTicks = 0
        if not Config.Activo and not self.DeadLatch then
            self:RequestSafeRelease(reason or "IDLE")
        end
    elseif newPhase == "FLASH_EXIT" then
        local char, hrp = self:GetValidEntity()
        if hrp and extraCFrame then
            Motor:TeleportCharacter(char, hrp, extraCFrame, true)
        end
    elseif newPhase == "EMERGENCY" then
        self:ClearTargets()
        self.EmergencyTicks = 0
        self.LastEmergencyAt = tick()
        local char, hrp = self:GetValidEntity()
        if hrp then
            self:RecoverToSafeHome(hrp, char)
            Logger:Log("[TELEMETRY] EMERGENCY Latch Activo", Color3.new(1, 0, 0))
        end
    elseif newPhase == "RETURN" then
        self:ClearTargets()
    elseif newPhase == "DEAD" then
        self:ClearTargets()
        self.DeadLatch = true
        self.EmergencyTicks = 0
    end 
end

-- ==============================================================================
-- 5. LÓGICA DE VIAJE Y BURST
-- ==============================================================================
function Motor:Travel(targetCF, expectedToken)
    local char, hrp = FSM:GetValidEntity()
    if not hrp then return false, "NO_ENTITY" end

    Motor:SealCharacter(hrp)
    
    local startCF = hrp.CFrame 
    local dist = (Vector2.new(startCF.X, startCF.Z) - Vector2.new(targetCF.X, targetCF.Z)).Magnitude 
    local duration = math.max(dist / Config.Velocidad, 0.1) 
    local startTime = tick() 
    local status = "PENDING" 
    
    local conn
    conn = RS.RenderStepped:Connect(function() 
        if not Config.Activo then
            status = "ABORTED_MANUAL"
            return
        end
        if FSM.StateID ~= expectedToken then
            status = "STATE_OVERRIDDEN"
            return
        end
        if not FSM:GetValidEntity() then
            status = "NO_ENTITY"
            return
        end
        local elapsed = tick() - startTime 
        local alpha = math.clamp(elapsed / duration, 0, 1) 
        hrp.CFrame = startCF:Lerp(targetCF, alpha) 
        Motor:StopMotion(hrp)
        if alpha >= 1 then status = "OK" end 
    end) 
    
    local timeout = duration + 2
    while status == "PENDING" and (tick() - startTime) < timeout do RS.Heartbeat:Wait() end 
    if conn then conn:Disconnect() end 
    if status == "PENDING" then status = "TIMEOUT" end
    
    return status == "OK", status 
end

function Motor:ExecuteBurst(targetRoot, prompt, cCobro, burstToken)
    local char, hrp, hum = FSM:GetValidEntity()
    if not hrp then return false, "NO_ENTITY" end
    if not prompt or not prompt:IsDescendantOf(workspace) then return false, "NO_PROMPT" end

    local tempConnections = {}
    local triggeredObserved = false
    local interactionObserved = false
    local promptHiddenObserved = false
    local promptHiddenObservedAt = 0
    local promptHiddenAfterInteractionAt = 0
    local postTriggerMicroReleaseDone = false
    local claimObservedAt = 0
    local lastConfirmRefireAt = 0
    local lastBurstPoseMode = nil
    local lastInteractionAt = 0
    local triggeredObservedAt = 0
    local hoverHoldLogged = false
    local targetContainer = targetRoot and targetRoot.Parent or nil
    local targetModel = targetContainer and targetContainer:IsA("Model") and targetContainer or nil
    local activeBrainrots = workspace:FindFirstChild("ActiveBrainrots")
    local toolSnapshotBefore = GetOwnedToolCounts()
    local characterChildrenBefore = GetChildSignatureCounts(char)
    local characterDescendantsBefore = GetRelevantDescendantSignatureCounts(char)
    local burstSignals = {
        claimSeen = false,
        claimReason = nil,
        charAdded = {},
        charRemoved = {},
        descAdded = {},
        descRemoved = {},
        toolAdded = {},
        toolRemoved = {},
    }
    local promptPropsBefore = {
        RequiresLineOfSight = prompt.RequiresLineOfSight,
        MaxActivationDistance = prompt.MaxActivationDistance,
        HoldDuration = prompt.HoldDuration,
    }
    local burstHumanoidPropsBefore = hum and {
        PlatformStand = hum.PlatformStand,
        AutoRotate = hum.AutoRotate,
    } or nil
    local observeLook = Vector3.new(cCobro.LookVector.X, 0, cCobro.LookVector.Z)
    if observeLook.Magnitude < 0.01 then
        observeLook = Vector3.new(1, 0, 0)
    else
        observeLook = observeLook.Unit
    end
    local observePos = Vector3.new(cCobro.Position.X, math.max(cCobro.Position.Y, GetRoutineSafeY()), cCobro.Position.Z)
    local burstObserveCF = CFrame.lookAt(observePos, observePos + observeLook)
    local probableObservedAt = 0
    local probableReason = nil
    local promptEventSlack = 0.10

    local function classifyBurstCarrySignal(instance)
        if not instance then
            return nil
        end

        if instance:IsA("Weld") and instance.Name == "HoldWeld" then
            return "HOLD_WELD"
        end

        if instance:IsA("Weld") and instance.Name == "RightGrip" then
            return "RIGHT_GRIP"
        end

        if instance:IsA("Model") and instance.Name == "RenderedBrainrot" then
            return "RENDERED_BRAINROT"
        end

        if instance:IsA("Tool") then
            return "TOOL:" .. instance.Name
        end

        if targetModel and (instance == targetModel or instance:IsDescendantOf(targetModel)) then
            return "TARGET_ATTACH"
        end

        if targetRoot and instance == targetRoot then
            return "TARGET_ROOT"
        end

        return nil
    end

    local function noteSignal(bucket, instance)
        if not bucket or not instance then return end
        local signal = classifyBurstCarrySignal(instance)
        if not signal then return end
        bucket[signal] = (bucket[signal] or 0) + 1
    end

    local function isRelevantCarryEvent(instance)
        return classifyBurstCarrySignal(instance) ~= nil
    end

    local function hasSignal(bucket, signalName)
        return (bucket and bucket[signalName] or 0) > 0
    end

    local function hasPromptHiddenAfterInteraction()
        return promptHiddenAfterInteractionAt > 0
    end

    local function getInstancePath(instance)
        if not instance then return "nil" end
        local ok, fullName = pcall(function()
            return instance:GetFullName()
        end)
        if ok and fullName and fullName ~= "" then
            return fullName
        end
        local parentName = instance.Parent and instance.Parent.Name or "nil"
        return string.format("%s:%s parent=%s", instance.ClassName, instance.Name, parentName)
    end

    local function restorePromptProps()
        if not prompt or not prompt:IsDescendantOf(workspace) then return end
        pcall(function()
            prompt.RequiresLineOfSight = promptPropsBefore.RequiresLineOfSight
            prompt.MaxActivationDistance = promptPropsBefore.MaxActivationDistance
            prompt.HoldDuration = promptPropsBefore.HoldDuration
        end)
    end

    local function applyBurstHumanoidLock(liveHum)
        if not liveHum then return end
        pcall(function()
            liveHum.PlatformStand = true
            liveHum.AutoRotate = true
        end)
    end

    local function restoreBurstHumanoid(liveHum)
        if not liveHum or not burstHumanoidPropsBefore then return end
        pcall(function()
            liveHum.PlatformStand = burstHumanoidPropsBefore.PlatformStand
            liveHum.AutoRotate = burstHumanoidPropsBefore.AutoRotate
        end)
    end

    local function canOwnWorldClaim()
        return interactionObserved or triggeredObserved
    end

    local function noteClaim(reason)
        if not burstSignals.claimSeen then
            claimObservedAt = tick()
        end

        burstSignals.claimSeen = true
        burstSignals.claimReason = burstSignals.claimReason or reason
    end

    local function noteProbable(reason)
        if not reason then
            return
        end

        if probableObservedAt <= 0 then
            probableObservedAt = tick()
            probableReason = reason
            Logger:Log("[TELEMETRY] PICKUP_PROBABLE: " .. tostring(reason), Color3.new(1, 1, 0))
        elseif not probableReason then
            probableReason = reason
        end
    end

    local function getProbablePickupSignal()
        if burstSignals.claimSeen then
            return true, burstSignals.claimReason or "WORLD_CLAIM_PROBABLE"
        end

        if hasSignal(burstSignals.descAdded, "HOLD_WELD") then
            return true, "EVENT_HOLD_WELD"
        end

        if hasSignal(burstSignals.charAdded, "RENDERED_BRAINROT") or hasSignal(burstSignals.descAdded, "RENDERED_BRAINROT") then
            return true, "EVENT_RENDERED_BRAINROT"
        end

        if hasSignal(burstSignals.charAdded, "TARGET_ATTACH") or hasSignal(burstSignals.descAdded, "TARGET_ATTACH") or hasSignal(burstSignals.descAdded, "TARGET_ROOT") then
            return true, "EVENT_TARGET_ATTACH"
        end

        if hasSignal(burstSignals.descAdded, "RIGHT_GRIP") then
            return true, "EVENT_RIGHT_GRIP"
        end

        if hasPromptHiddenAfterInteraction() and (triggeredObserved or interactionObserved) then
            return true, "PROMPT_HIDDEN_AFTER_TRIGGER"
        end

        return false, nil
    end

    local function hasCarryEvidence()
        return burstSignals.claimSeen
            or hasSignal(burstSignals.descAdded, "HOLD_WELD")
            or hasSignal(burstSignals.charAdded, "RENDERED_BRAINROT")
            or hasSignal(burstSignals.descAdded, "RENDERED_BRAINROT")
            or hasSignal(burstSignals.charAdded, "TARGET_ATTACH")
            or hasSignal(burstSignals.descAdded, "TARGET_ATTACH")
            or hasSignal(burstSignals.descAdded, "TARGET_ROOT")
    end

    local function hasCarrySwapEvidence()
        local recentTriggerWindow = math.max(
            Config.BurstCarryConfirmWindow or 0,
            Config.BurstPostFireConfirmWindow or 0,
            Config.BurstPostFireResolveWindow or 0,
            0.25
        )
        local recentTriggerObserved = triggeredObservedAt > 0 and (tick() - triggeredObservedAt) <= (recentTriggerWindow + 0.15)

        return hasCarryEvidence()
            or recentTriggerObserved
            or triggeredObserved
            or hasPromptHiddenAfterInteraction()
            or (probableObservedAt > 0 and probableReason ~= nil and probableReason ~= "PROMPT_HIDDEN_AFTER_TRIGGER")
    end

    local function isCarrySwapLikely(lossReason)
        if not Config.BurstCarrySwapAutoResume then
            return false
        end

        local lossText = tostring(lossReason or "")
        local swapLoss = lossText == "HUM_DEAD"
            or lossText == "CHAR_NIL"
            or lossText == "HRP_NIL"
            or lossText == "HUM_NIL"

        if hasCarryEvidence() then
            return triggeredObserved or hasPromptHiddenAfterInteraction() or interactionObserved or probableObservedAt > 0
        end

        if swapLoss and hasCarrySwapEvidence() then
            return true
        end

        return false
    end

    local function markCarrySwapPending(stage, lossReason)
        if not isCarrySwapLikely(lossReason) then
            return false
        end

        FSM:MarkCarrySwapPending({
            toolSnapshotBefore = toolSnapshotBefore,
            characterChildrenBefore = characterChildrenBefore,
            characterDescendantsBefore = characterDescendantsBefore,
            targetRoot = targetRoot,
            targetModel = targetModel,
            prompt = prompt,
            claimReason = burstSignals.claimReason or (triggeredObserved and "POST_TRIGGER_SWAP_SUSPECT" or nil),
            lossReason = lossReason,
        })
        FSM:MarkTargetCooldown(targetRoot, prompt, Config.TargetRetryCooldown, "CARRY_SWAP_" .. string.upper(tostring(stage or "pending")))
        Logger:Log("[CARRY_SWAP] Pending " .. tostring(stage) .. ": " .. tostring(lossReason) .. " | " .. tostring(burstSignals.claimReason or "sin_claim"), Color3.new(1, 1, 0))
        return true
    end

    local function disconnectTempConnections()
        for _, conn in ipairs(tempConnections) do
            pcall(function() conn:Disconnect() end)
        end
        table.clear(tempConnections)
    end

    local function getEntityLossReason()
        local liveChar = player.Character
        if not liveChar then
            return "CHAR_NIL"
        end

        local liveRoot = liveChar:FindFirstChild("HumanoidRootPart")
        if not liveRoot then
            return "HRP_NIL"
        end

        local liveHum = liveChar:FindFirstChildOfClass("Humanoid")
        if not liveHum then
            return "HUM_NIL"
        end

        if liveHum.Health <= 0 then
            return "HUM_DEAD"
        end

        return string.format("UNSPECIFIED hp=%.1f anchored=%s y=%.2f", liveHum.Health, tostring(liveRoot.Anchored), liveRoot.Position.Y)
    end

    local function getCarryConfirmation()
        local toolSnapshotNow = GetOwnedToolCounts()
        local equippedDelta, equippedNames = GetPositiveToolDelta(toolSnapshotBefore.characterByName, toolSnapshotNow.characterByName)
        if equippedDelta > 0 then
            return true, "TOOL_EQUIPPED_OK: " .. tostring(equippedNames ~= "" and equippedNames or equippedDelta)
        end

        local totalDelta, totalNames = GetPositiveToolDelta(toolSnapshotBefore.totalByName, toolSnapshotNow.totalByName)
        if totalDelta > 0 then
            return true, "TOOL_DELTA_OK: " .. tostring(totalNames ~= "" and totalNames or totalDelta)
        end

        return false, nil
    end

    local function getDirectCarryStateConfirmation()
        local liveChar = player.Character
        if not liveChar then return false, nil end

        local targetAttachedToChar = (targetRoot and targetRoot:IsDescendantOf(liveChar))
            or (targetModel and targetModel:IsDescendantOf(liveChar))
            or (prompt and prompt:IsDescendantOf(liveChar))
        local carryLinkedToCurrentTarget = burstSignals.claimSeen or targetAttachedToChar

        local liveRoot = liveChar:FindFirstChild("HumanoidRootPart")
        if liveRoot then
            local holdWeld = liveRoot:FindFirstChild("HoldWeld")
            if holdWeld and holdWeld:IsA("Weld") and carryLinkedToCurrentTarget then
                return true, "HOLD_WELD_OK"
            end
        end

        -- RenderedBrainrot en personaje: señal directa de carry para este juego.
        -- Solo necesita triggeredObserved (no carryLinkedToCurrentTarget) porque el
        -- servidor reparentea el modelo aquí mismo después del trigger.
        local rendered = liveChar:FindFirstChild("RenderedBrainrot") or liveChar:FindFirstChild("RenderedBrainrot", true)
        if rendered and rendered:IsA("Model") then
            if carryLinkedToCurrentTarget or triggeredObserved then
                return true, "CHAR_RENDERED_OK"
            end
        end

        local rightGrip = liveChar:FindFirstChild("RightGrip", true)
        local equippedTool = liveChar:FindFirstChildOfClass("Tool")
        if rightGrip and rightGrip:IsA("Weld") and equippedTool and carryLinkedToCurrentTarget then
            return true, "RIGHT_GRIP_OK: " .. tostring(equippedTool.Name)
        end

        if targetRoot and targetRoot:IsDescendantOf(liveChar) then
            return true, "TARGET_ON_CHAR_OK"
        end

        if targetModel and targetModel.Parent == liveChar then
            return true, "TARGET_MODEL_PARENT_CHAR_OK"
        end

        if targetModel and targetModel:IsDescendantOf(liveChar) then
            return true, "TARGET_MODEL_ON_CHAR_OK"
        end

        if prompt and prompt:IsDescendantOf(liveChar) then
            if prompt.Enabled == false then
                return true, "PROMPT_ON_CHAR_DISABLED_OK"
            end
            return true, "PROMPT_ON_CHAR_OK"
        end

        return false, nil
    end

    local function getTransientCarryConfirmation()
        if hasSignal(burstSignals.descAdded, "HOLD_WELD") then
            return true, "HOLD_WELD_EVENT_OK"
        end

        if hasSignal(burstSignals.descAdded, "HOLD_WELD") and (
            hasSignal(burstSignals.charAdded, "RENDERED_BRAINROT")
            or hasSignal(burstSignals.descAdded, "RENDERED_BRAINROT")
            or hasSignal(burstSignals.charAdded, "TARGET_ATTACH")
            or hasSignal(burstSignals.descAdded, "TARGET_ATTACH")
        ) then
            return true, "HOLD_WELD_ATTACH_EVENT_OK"
        end

        if hasSignal(burstSignals.charAdded, "RENDERED_BRAINROT") or hasSignal(burstSignals.descAdded, "RENDERED_BRAINROT") then
            return true, "RENDERED_EVENT_OK"
        end

        if hasSignal(burstSignals.charAdded, "TARGET_ATTACH") or hasSignal(burstSignals.descAdded, "TARGET_ATTACH") or hasSignal(burstSignals.descAdded, "TARGET_ROOT") then
            return true, "TARGET_ATTACH_EVENT_OK"
        end

        if hasSignal(burstSignals.descAdded, "RIGHT_GRIP") then
            local toolEventText = FormatSignalCounts(burstSignals.toolAdded, 4)
            if toolEventText ~= "" then
                return true, "RIGHT_GRIP_TOOL_EVENT_OK: " .. toolEventText
            end
        end

        if hasPromptHiddenAfterInteraction() and burstSignals.claimSeen then
            if hasSignal(burstSignals.descRemoved, "HOLD_WELD") or hasSignal(burstSignals.descRemoved, "RENDERED_BRAINROT") then
                return true, "PROMPT_HIDDEN_ATTACH_OK"
            end
        end

        return false, nil
    end

    local function getCharacterAttachConfirmation()
        local liveChar = player.Character
        local directOk, directReason = getDirectCarryStateConfirmation()
        if directOk then
            return true, directReason
        end

        local hasDescDelta, descDeltaNames = GetSignatureDelta(characterDescendantsBefore, GetRelevantDescendantSignatureCounts(liveChar))
        if hasDescDelta then
            return true, "CHAR_DESC_OK: " .. tostring(descDeltaNames)
        end

        local hasDelta, deltaNames = GetSignatureDelta(characterChildrenBefore, GetChildSignatureCounts(liveChar))
        if hasDelta then
            return true, "CHAR_ATTACH_OK: " .. tostring(deltaNames)
        end
        return false, nil
    end

    local function getWorldClaimConfirmation()
        if not canOwnWorldClaim() then
            return false, nil
        end

        local activeFolder = workspace:FindFirstChild("ActiveBrainrots") or activeBrainrots
        if targetRoot and activeFolder and not targetRoot:IsDescendantOf(activeFolder) then
            noteClaim("CLAIM_WORLD_OK: target salio de ActiveBrainrots")
            return true, "CLAIM_WORLD_OK: target salio de ActiveBrainrots"
        end
        if targetRoot and not targetRoot:IsDescendantOf(workspace) then
            noteClaim("TARGET_REMOVED_OK: target removido de workspace")
            return true, "TARGET_REMOVED_OK: target removido de workspace"
        end
        if prompt then
            if not prompt:IsDescendantOf(workspace) then
                noteClaim("PROMPT_MISSING_OK: prompt removido de workspace")
                return true, "PROMPT_MISSING_OK: prompt removido de workspace"
            end
            if targetContainer and not prompt:IsDescendantOf(targetContainer) then
                noteClaim("PROMPT_REPARENT_OK: prompt movido fuera del target")
                return true, "PROMPT_REPARENT_OK: prompt movido fuera del target"
            end
            if activeFolder and not prompt:IsDescendantOf(activeFolder) then
                noteClaim("PROMPT_FOLDER_EXIT_OK: prompt salio de ActiveBrainrots")
                return true, "PROMPT_FOLDER_EXIT_OK: prompt salio de ActiveBrainrots"
            end
        end
        return false, nil
    end

    local function hasStableWorldClaimState()
        local activeFolder = workspace:FindFirstChild("ActiveBrainrots") or activeBrainrots
        local targetGone = false
        local promptGone = false

        if targetRoot then
            targetGone = (activeFolder and not targetRoot:IsDescendantOf(activeFolder))
                or not targetRoot:IsDescendantOf(workspace)
        end

        if prompt then
            promptGone = not prompt:IsDescendantOf(workspace)
                or (targetContainer and not prompt:IsDescendantOf(targetContainer))
                or (activeFolder and not prompt:IsDescendantOf(activeFolder))
        else
            promptGone = true
        end

        return targetGone or promptGone, targetGone, promptGone
    end

    local function finishBurst(ok, reason)
        local _, finishRoot, finishHum = FSM:GetValidEntity()
        if finishRoot then
            Motor:DestroyBurstHoverRig(finishRoot)
        end
        restoreBurstHumanoid(finishHum)
        if finishRoot then
            Motor:SealCharacter(finishRoot)
        end
        restorePromptProps()
        disconnectTempConnections()
        return ok, reason
    end

    local function applyBurstPoseMode(liveChar, liveRoot, mode)
        if not liveChar or not liveRoot then
            return
        end

        local liveHum = liveChar:FindFirstChildOfClass("Humanoid")
        local targetCF = mode == "INTERACT" and cCobro or burstObserveCF
        local isHoverObserve = mode == "OBSERVE" and Config.BurstHoverHoldEnabled

        if mode ~= lastBurstPoseMode and lastBurstPoseMode == "OBSERVE" then
            Motor:DestroyBurstHoverRig(liveRoot)
        end

        if mode == "RELEASE" then
            applyBurstHumanoidLock(liveHum)
            Motor:DestroyBurstHoverRig(liveRoot)
            if liveRoot.Anchored then
                Motor:ReleaseCharacter(liveRoot)
            end
        elseif isHoverObserve then
            restoreBurstHumanoid(liveHum)
            if liveHum then
                pcall(function()
                    liveHum.PlatformStand = false
                    liveHum.AutoRotate = true
                end)
            end
            if liveRoot.Anchored then
                Motor:ReleaseCharacter(liveRoot)
            end
            local _, align = Motor:EnsureBurstHoverRig(liveRoot)
            if align then
                align.Position = targetCF.Position
            end
            if not hoverHoldLogged then
                hoverHoldLogged = true
                Logger:Log("[TELEMETRY] BURST_HOVER_HOLD", Color3.new(0, 1, 1))
            end
        else
            Motor:DestroyBurstHoverRig(liveRoot)
            restoreBurstHumanoid(liveHum)
            Motor:SealCharacter(liveRoot)
        end

        liveRoot.CanCollide = false
        liveRoot.CanTouch = mode == "OBSERVE" or mode == "RELEASE"
        if mode == "INTERACT" or mode == "RELEASE" then
            pcall(function()
                liveChar:PivotTo(targetCF)
            end)
        elseif (liveRoot.Position - targetCF.Position).Magnitude > math.max(Config.BurstReSnapDistance or 0, 0.25) then
            pcall(function()
                liveChar:PivotTo(targetCF)
            end)
        end
        Motor:StopMotion(liveRoot)
        lastBurstPoseMode = mode
    end

    local function runPostTriggerMicroRelease(reason)
        if postTriggerMicroReleaseDone or not Config.BurstPostTriggerRelease then
            return true, nil
        end

        local releaseDuration = math.max(Config.BurstPostTriggerGrace or 0, 0)
        postTriggerMicroReleaseDone = true

        if releaseDuration <= 0 then
            return true, nil
        end

        Logger:Log("[TELEMETRY] BURST_MICRO_RELEASE: " .. tostring(reason), Color3.new(0, 1, 1))

        local deadline = tick() + releaseDuration
        while tick() < deadline do
            if not Config.Activo then
                return false, "BURST_ABORT_MANUAL"
            end
            if FSM.StateID ~= burstToken then
                return false, "STATE_OVERRIDDEN"
            end

            local liveChar, liveRoot, liveHum = FSM:GetValidEntity()
            if not liveChar or not liveRoot or not liveHum then
                return false, getEntityLossReason()
            end

            applyBurstPoseMode(liveChar, liveRoot, "RELEASE")
            RS.Heartbeat:Wait()
        end

        local endChar, endRoot, endHum = FSM:GetValidEntity()
        if not endChar or not endRoot or not endHum then
            return false, getEntityLossReason()
        end

        applyBurstPoseMode(endChar, endRoot, "OBSERVE")
        Logger:Log("[TELEMETRY] BURST_MICRO_RESEAL", Color3.new(1, 1, 0))
        return true, nil
    end

    local function maintainBurstPose(liveChar, liveRoot, allowFree)
        if not liveChar or not liveRoot then return end
        applyBurstPoseMode(liveChar, liveRoot, allowFree and "OBSERVE" or "INTERACT")
    end

    local function sustainBurstPose(seconds, allowFree)
        local duration = math.max(seconds or 0, 0)
        if duration <= 0 then
            return true, nil
        end

        local deadline = tick() + duration
        while tick() < deadline do
            if not Config.Activo then
                return false, "BURST_ABORT_MANUAL"
            end
            if FSM.StateID ~= burstToken then
                return false, "STATE_OVERRIDDEN"
            end

            local liveChar, liveRoot, liveHum = FSM:GetValidEntity()
            if not liveChar or not liveRoot or not liveHum then
                return false, getEntityLossReason()
            end

            maintainBurstPose(liveChar, liveRoot, allowFree)
            RS.Heartbeat:Wait()
        end

        return true, nil
    end

    local waitForClaimSettle

    local function waitForPostFireResolution(reason)
        local baseWindow = math.max(Config.BurstPostFireResolveWindow or 0, 0)
        local deadline = tick() + baseWindow
        local extendedDeadline = deadline
        if deadline <= tick() then
            return false, nil
        end

        Logger:Log("[TELEMETRY] POST_FIRE_RESOLVE: " .. tostring(reason), Color3.new(0, 1, 1))

        while tick() < extendedDeadline do
            if not Config.Activo then return false, "BURST_ABORT_MANUAL" end
            if FSM.StateID ~= burstToken then return false, "STATE_OVERRIDDEN" end

            local liveChar, liveRoot, liveHum = FSM:GetValidEntity()
            if not liveChar or not liveRoot or not liveHum then
                local lossReason = getEntityLossReason()
                Logger:Log("[TELEMETRY] ENTITY_LOST_POST_FIRE_WAIT: " .. tostring(lossReason), Color3.new(1, 0, 0))
                if markCarrySwapPending("post_fire_wait", lossReason) then
                    return false, "CARRY_SWAP_PENDING"
                end
                return false, "NO_ENTITY"
            end

            applyBurstPoseMode(liveChar, liveRoot, "OBSERVE")

            local carryConfirmed, carryReason = getCarryConfirmation()
            if carryConfirmed then
                Logger:Log("[TELEMETRY] PICKUP_CONFIRMED: " .. tostring(carryReason), Color3.new(0, 1, 0))
                return true, carryReason
            end

            local attachConfirmed, attachReason = getCharacterAttachConfirmation()
            if attachConfirmed then
                Logger:Log("[TELEMETRY] PICKUP_CONFIRMED: " .. tostring(attachReason), Color3.new(0, 1, 0))
                return true, attachReason
            end

            local claimed, claimedReason = getWorldClaimConfirmation()
            if claimed then
                Logger:Log("[TELEMETRY] POST_FIRE_RESOLVE: " .. tostring(claimedReason), Color3.new(0, 1, 1))
                return waitForClaimSettle(claimedReason)
            end

            local probableOk, observedReason = getProbablePickupSignal()
            if probableOk then
                local isNewProbable = probableObservedAt <= 0
                noteProbable(observedReason)
                if isNewProbable then
                    extendedDeadline = math.max(extendedDeadline, tick() + math.max(Config.BurstCarryConfirmWindow or 0, baseWindow))
                end
            end

            RS.Heartbeat:Wait()
        end

        local endChar, endRoot, endHum = FSM:GetValidEntity()
        if endChar and endRoot and endHum then
            applyBurstPoseMode(endChar, endRoot, "OBSERVE")
        end

        return false, nil
    end

    waitForClaimSettle = function(claimReason)
        Logger:Log("[TELEMETRY] CLAIM_SEEN_SETTLING: " .. tostring(claimReason), Color3.new(0, 1, 1))
        local releaseOk, releaseReason = runPostTriggerMicroRelease(claimReason)
        if not releaseOk then
            Logger:Log("[TELEMETRY] ENTITY_LOST_CLAIM_RELEASE: " .. tostring(releaseReason), Color3.new(1, 0, 0))
            if markCarrySwapPending("claim_release", releaseReason) then
                return false, "CARRY_SWAP_PENDING"
            end
            if releaseReason == "BURST_ABORT_MANUAL" or releaseReason == "STATE_OVERRIDDEN" then
                return false, releaseReason
            end
            return false, "NO_ENTITY"
        end

        local deadline = tick() + Config.BurstClaimSettleWindow

        while tick() < deadline do
            if not Config.Activo then return false, "BURST_ABORT_MANUAL" end
            if FSM.StateID ~= burstToken then return false, "STATE_OVERRIDDEN" end

            local charS, hrpS, humS = FSM:GetValidEntity()
            if not hrpS or not charS or not humS then
                local lossReason = getEntityLossReason()
                Logger:Log("[TELEMETRY] ENTITY_LOST_SETTLE: " .. lossReason, Color3.new(1, 0, 0))
                if markCarrySwapPending("settle", lossReason) then
                    return false, "CARRY_SWAP_PENDING"
                end
                return false, "NO_ENTITY"
            end

            local lastHP = humS:GetAttribute("LastHP") or humS.Health
            if humS.Health < lastHP then return false, "HP_DROPPED_IN_BURST" end

            maintainBurstPose(charS, hrpS, true)

            local carryConfirmed, carryReason = getCarryConfirmation()
            if carryConfirmed then
                Logger:Log("[TELEMETRY] PICKUP_CONFIRMED: " .. tostring(carryReason), Color3.new(0, 1, 0))
                return true, carryReason
            end

            local attachConfirmed, attachReason = getCharacterAttachConfirmation()
            if attachConfirmed then
                Logger:Log("[TELEMETRY] PICKUP_CONFIRMED: " .. tostring(attachReason), Color3.new(0, 1, 0))
                return true, attachReason
            end

            local claimedStillThere, _ = getWorldClaimConfirmation()
            if not claimedStillThere then
                Logger:Log("[TELEMETRY] CLAIM_SETTLE_LOST", Color3.new(1, 0.5, 0))
                return false, "CLAIM_SETTLE_LOST"
            end

            local probableOk, observedReason = getProbablePickupSignal()
            if probableOk then
                noteProbable(observedReason)
            end

            local stableWorldClaim, targetGone, promptGone = hasStableWorldClaimState()
            if stableWorldClaim and claimObservedAt > 0 and (tick() - claimObservedAt) >= (Config.BurstCarryConfirmWindow or 0) then
                local worldReason = string.format(
                    "CLAIM_WORLD_STABLE_OK: %s targetGone=%s promptGone=%s",
                    tostring(burstSignals.claimReason or claimReason),
                    tostring(targetGone),
                    tostring(promptGone)
                )
                Logger:Log("[TELEMETRY] PICKUP_CONFIRMED: " .. worldReason, Color3.new(0, 1, 0))
                return true, worldReason
            end

            RS.Heartbeat:Wait()
        end

        Logger:Log("[TELEMETRY] CLAIM_SETTLE_NO_ATTACH", Color3.new(1, 0.5, 0))
        return false, "CLAIM_WITHOUT_CARRY_CONFIRM"
    end

    if prompt then
        table.insert(tempConnections, prompt.AncestryChanged:Connect(function()
            local activeFolder = workspace:FindFirstChild("ActiveBrainrots") or activeBrainrots
            if not prompt:IsDescendantOf(workspace) then
                if canOwnWorldClaim() then
                    noteClaim("PROMPT_ANCESTRY_MISSING_OK")
                end
                Logger:Log("[TELEMETRY] PROMPT_ANCESTRY_MISSING: " .. getInstancePath(prompt), Color3.new(0, 1, 1))
            elseif targetContainer and not prompt:IsDescendantOf(targetContainer) then
                if canOwnWorldClaim() then
                    noteClaim("PROMPT_ANCESTRY_REPARENT_OK")
                end
                Logger:Log("[TELEMETRY] PROMPT_ANCESTRY_REPARENT: " .. getInstancePath(prompt), Color3.new(0, 1, 1))
            elseif activeFolder and not prompt:IsDescendantOf(activeFolder) then
                if canOwnWorldClaim() then
                    noteClaim("PROMPT_ANCESTRY_FOLDER_EXIT_OK")
                end
                Logger:Log("[TELEMETRY] PROMPT_ANCESTRY_FOLDER_EXIT: " .. getInstancePath(prompt), Color3.new(0, 1, 1))
            end
        end))
        table.insert(tempConnections, prompt.PromptHidden:Connect(function()
            promptHiddenObserved = true
            promptHiddenObservedAt = tick()
            if lastInteractionAt > 0 and promptHiddenObservedAt + promptEventSlack >= lastInteractionAt then
                promptHiddenAfterInteractionAt = promptHiddenObservedAt
            end
            Logger:Log("[TELEMETRY] PROMPT_HIDDEN", Color3.new(1, 1, 0))
        end))
        table.insert(tempConnections, prompt.PromptButtonHoldBegan:Connect(function(playerWhoTriggered)
            if playerWhoTriggered == player then
                Logger:Log("[TELEMETRY] PROMPT_HOLD_BEGAN", Color3.new(1, 1, 0))
            end
        end))
        table.insert(tempConnections, prompt.PromptButtonHoldEnded:Connect(function(playerWhoTriggered)
            if playerWhoTriggered == player then
                Logger:Log("[TELEMETRY] PROMPT_HOLD_ENDED", Color3.new(1, 0.7, 0))
            end
        end))
        table.insert(tempConnections, prompt.Triggered:Connect(function(playerWhoTriggered)
            if playerWhoTriggered == player then
                triggeredObserved = true
                triggeredObservedAt = tick()
                if promptHiddenObservedAt > 0 and lastInteractionAt > 0 and promptHiddenObservedAt + promptEventSlack >= lastInteractionAt then
                    promptHiddenAfterInteractionAt = math.max(promptHiddenAfterInteractionAt, promptHiddenObservedAt)
                end
                Logger:Log("[TELEMETRY] PROMPT_TRIGGERED", Color3.new(0, 1, 0))
            end
        end))
        table.insert(tempConnections, prompt.TriggerEnded:Connect(function(playerWhoTriggered)
            if playerWhoTriggered == player then
                Logger:Log("[TELEMETRY] PROMPT_TRIGGER_ENDED", Color3.new(0.7, 1, 0.2))
            end
        end))
    end

    if char then
        if targetRoot then
            table.insert(tempConnections, targetRoot.AncestryChanged:Connect(function()
                local activeFolder = workspace:FindFirstChild("ActiveBrainrots") or activeBrainrots
                if not targetRoot:IsDescendantOf(workspace) then
                    if canOwnWorldClaim() then
                        noteClaim("TARGET_ANCESTRY_REMOVED_OK")
                    end
                    Logger:Log("[TELEMETRY] TARGET_ANCESTRY_REMOVED: " .. getInstancePath(targetRoot), Color3.new(0, 1, 1))
                elseif activeFolder and not targetRoot:IsDescendantOf(activeFolder) then
                    if canOwnWorldClaim() then
                        noteClaim("TARGET_ANCESTRY_FOLDER_EXIT_OK")
                    end
                    Logger:Log("[TELEMETRY] TARGET_ANCESTRY_FOLDER_EXIT: " .. getInstancePath(targetRoot), Color3.new(0, 1, 1))
                end
            end))
        end
        table.insert(tempConnections, char.ChildAdded:Connect(function(child)
            if isRelevantCarryEvent(child) then
                noteSignal(burstSignals.charAdded, child)
            end
        end))
        table.insert(tempConnections, char.ChildRemoved:Connect(function(child)
            if isRelevantCarryEvent(child) then
                noteSignal(burstSignals.charRemoved, child)
            end
        end))
        table.insert(tempConnections, char.DescendantAdded:Connect(function(descendant)
            if isRelevantCarryEvent(descendant) then
                noteSignal(burstSignals.descAdded, descendant)
            end
        end))
        table.insert(tempConnections, char.DescendantRemoving:Connect(function(descendant)
            if isRelevantCarryEvent(descendant) then
                noteSignal(burstSignals.descRemoved, descendant)
            end
        end))
    end

    local backpack = player:FindFirstChildOfClass("Backpack")
    if backpack then
        table.insert(tempConnections, backpack.ChildAdded:Connect(function(child)
            if child:IsA("Tool") then
                noteSignal(burstSignals.toolAdded, child)
            end
        end))
        table.insert(tempConnections, backpack.ChildRemoved:Connect(function(child)
            if child:IsA("Tool") then
                noteSignal(burstSignals.toolRemoved, child)
            end
        end))
    end

    Motor:SealCharacter(hrp)
    Motor:TeleportCharacter(char, hrp, cCobro, true)
    Logger:Log("[TELEMETRY] PRE_BURST", Color3.new(1, 1, 0))
    
    Motor:SealCharacter(hrp)
    Motor:TeleportCharacter(char, hrp, cCobro, true)
    Logger:Log("[TELEMETRY] POST_PROBE", Color3.new(1, 1, 0))
    if Config.BurstProbeFree then
        Motor:ReleaseCharacter(hrp)
        RS.Heartbeat:Wait()
        Motor:SealCharacter(hrp)
        Motor:TeleportCharacter(char, hrp, cCobro, true)
        Logger:Log("[TELEMETRY] PROBE_FREE", Color3.new(1, 1, 0))
    end
    
    -- [EXPLICACIÓN DEL FALLO LÓGICO DE BURST ANTERIOR]
    -- El burst disparaba sin comprobar si estábamos dentro de MaxActivationDistance 3D.
    -- Con esta telemetría pura sabrás exactamente por qué falla.
    local spoofedHoldDuration = promptPropsBefore.HoldDuration
    pcall(function()
        prompt.RequiresLineOfSight = false
        if (Config.BurstPromptMaxDistance or 0) > 0 then
            prompt.MaxActivationDistance = math.max(prompt.MaxActivationDistance, Config.BurstPromptMaxDistance)
        end
        if Config.BurstSpoofHoldDuration and prompt.HoldDuration > Config.BurstSpoofHoldValue then
            prompt.HoldDuration = Config.BurstSpoofHoldValue
            spoofedHoldDuration = prompt.HoldDuration
        end
    end)

    local maxDist = prompt and prompt.MaxActivationDistance or 0
    local hDur = prompt and prompt.HoldDuration or 0
    local pPos = GetPromptWorldPosition(prompt, targetRoot.Position)
    local burstY = cCobro.Position.Y
    local d3D = (hrp.Position - pPos).Magnitude
    local dXZ = math.sqrt((hrp.Position.X - pPos.X)^2 + (hrp.Position.Z - pPos.Z)^2)

    Logger:Log(string.format("[BURST_INFO] 3D:%.1f|XZ:%.1f|Y:%.1f|PromptY:%.1f|BurstY:%.1f", d3D, dXZ, hrp.Position.Y, pPos.Y, burstY), Color3.new(0, 1, 1))
    Logger:Log(string.format("[BURST_INFO] Hold:%.1fs|MaxD:%.1f|Anc:%s", hDur, maxDist, tostring(hrp.Anchored)), Color3.new(0, 1, 1))
    if Config.BurstSpoofHoldDuration and (promptPropsBefore.HoldDuration or 0) > hDur then
        Logger:Log(string.format("[BURST_INFO] HoldSpoof:%.2f->%.2f", promptPropsBefore.HoldDuration or 0, hDur), Color3.new(0, 1, 1))
    end
    Logger:Log("[BURST_MODE] SEALED_MICRO_RELEASE_CONFIRM", Color3.new(0, 1, 1))

    do
        local sustainOk, sustainReason = sustainBurstPose(Config.BurstPromptSetupDelay, false)
        if not sustainOk then
            if sustainReason == "BURST_ABORT_MANUAL" or sustainReason == "STATE_OVERRIDDEN" then
                return finishBurst(false, sustainReason)
            end
            Logger:Log("[TELEMETRY] ENTITY_LOST_SETUP: " .. tostring(sustainReason), Color3.new(1, 0, 0))
            return finishBurst(false, "NO_ENTITY")
        end
    end

    local function checkPositiveConfirmation(logPrefix)
        local carryConfirmed, carryReason = getCarryConfirmation()
        if carryConfirmed then
            Logger:Log("[TELEMETRY] " .. tostring(carryReason), Color3.new(0, 1, 0))
            return true, carryReason
        end

        local attachConfirmed, attachReason = getCharacterAttachConfirmation()
        if attachConfirmed then
            Logger:Log("[TELEMETRY] " .. tostring(attachReason), Color3.new(0, 1, 0))
            return true, attachReason
        end

        local claimed, claimedReason = getWorldClaimConfirmation()
        if claimed then
            Logger:Log("[TELEMETRY] " .. tostring(logPrefix) .. ": " .. tostring(claimedReason), Color3.new(0, 1, 1))
            return waitForClaimSettle(claimedReason)
        end

        local probableOk, observedReason = getProbablePickupSignal()
        if probableOk then
            noteProbable(observedReason)
        end

        return false, nil
    end

    local function performPromptInteraction(liveChar, liveRoot, livePrompt)
        if not livePrompt then return false, "NO_PROMPT" end

        if fireproximityprompt then
            local ok, err = pcall(function()
                fireproximityprompt(livePrompt)
            end)
            if ok then
                return true, "FIRE_PROMPT"
            end

            if (livePrompt.HoldDuration or 0) <= 0 and not Config.BurstFallbackFireInHold then
                return false, err
            end
        end

        local holdDuration = livePrompt.HoldDuration or 0
        if holdDuration > 0 then
            local ok, err = pcall(function()
                livePrompt:InputHoldBegin()
                task.wait(holdDuration + Config.BurstHoldExtra)
                livePrompt:InputHoldEnd()
            end)
            return ok, ok and "INPUT_HOLD" or err
        end

        return false, "NO_INTERACT_IMPL"
    end

    local totalAttempts = ((prompt.HoldDuration or 0) > 0) and Config.BurstHoldAttempts or Config.BurstRapidAttempts

    for attempt = 1, totalAttempts do
        if not Config.Activo then return finishBurst(false, "BURST_ABORT_MANUAL") end
        if FSM.StateID ~= burstToken then return finishBurst(false, "STATE_OVERRIDDEN") end

        local charB, hrpB, humB = FSM:GetValidEntity()
        if not hrpB or not charB or not humB then
            local lossReason = getEntityLossReason()
            Logger:Log("[TELEMETRY] ENTITY_LOST_PRE_FIRE: " .. lossReason, Color3.new(1, 0, 0))
            if markCarrySwapPending("pre_fire", lossReason) then
                return finishBurst(false, "CARRY_SWAP_PENDING")
            end
            return finishBurst(false, "NO_ENTITY")
        end

        local lastHP = humB:GetAttribute("LastHP") or humB.Health
        if humB.Health < lastHP then return finishBurst(false, "HP_DROPPED_IN_BURST") end

        maintainBurstPose(charB, hrpB, false)

        local earlyOk, earlyReason = checkPositiveConfirmation("CLAIM_PRE_FIRE")
        if earlyOk then
            Logger:Log("[TELEMETRY] PICKUP_CONFIRMED: " .. tostring(earlyReason), Color3.new(0, 1, 0))
            return finishBurst(true, earlyReason)
        elseif earlyReason == "CLAIM_WITHOUT_CARRY_CONFIRM" or earlyReason == "CLAIM_SETTLE_LOST" then
            return finishBurst(false, earlyReason)
        end

        if not targetRoot or not targetRoot:IsDescendantOf(workspace) then
            Logger:Log("[TELEMETRY] TARGET_VANISHED_PRE_CONFIRM", Color3.new(1, 0.5, 0))
            return finishBurst(false, "TARGET_VANISHED_PRE_CONFIRM")
        end

        if not prompt or not prompt:IsDescendantOf(workspace) or not prompt.Enabled then
            Logger:Log("[TELEMETRY] NO_PROMPT_PRE_FIRE", Color3.new(1, 0.5, 0))
            return finishBurst(false, "NO_PROMPT")
        end

        maintainBurstPose(charB, hrpB, false)

        interactionObserved = true
        lastInteractionAt = tick()
        local fireOk, fireErr = performPromptInteraction(charB, hrpB, prompt)

        if fireOk then
            Logger:Log("[TELEMETRY] GRAB_FIRE attempt=" .. tostring(attempt) .. " mode=" .. tostring(fireErr), Color3.new(1, 1, 0))

            local resolveOk, resolveReason = waitForPostFireResolution("POST_FIRE:" .. tostring(fireErr))
            if resolveOk then
                Logger:Log("[TELEMETRY] PICKUP_CONFIRMED: " .. tostring(resolveReason), Color3.new(0, 1, 0))
                return finishBurst(true, resolveReason)
            elseif resolveReason == "CARRY_SWAP_PENDING" then
                return finishBurst(false, resolveReason)
            elseif resolveReason == "CLAIM_WITHOUT_CARRY_CONFIRM" or resolveReason == "CLAIM_SETTLE_LOST" then
                return finishBurst(false, resolveReason)
            elseif resolveReason == "BURST_ABORT_MANUAL" or resolveReason == "STATE_OVERRIDDEN" then
                return finishBurst(false, resolveReason)
            elseif resolveReason == "NO_ENTITY" then
                return finishBurst(false, resolveReason)
            end
        elseif attempt == 1 or fireErr then
            Logger:Log("[TELEMETRY] GRAB_FIRE_FAIL attempt=" .. tostring(attempt) .. " err=" .. tostring(fireErr), Color3.new(1, 0.5, 0))
        end

        local postOk, postReason = checkPositiveConfirmation("CLAIM_POST_FIRE")
        if postOk then
            Logger:Log("[TELEMETRY] PICKUP_CONFIRMED: " .. tostring(postReason), Color3.new(0, 1, 0))
            return finishBurst(true, postReason)
        elseif postReason == "CARRY_SWAP_PENDING" then
            return finishBurst(false, postReason)
        elseif postReason == "CLAIM_WITHOUT_CARRY_CONFIRM" or postReason == "CLAIM_SETTLE_LOST" then
            return finishBurst(false, postReason)
        end

        if burstSignals.claimSeen then
            Logger:Log("[TELEMETRY] CLAIM_SEEN_WAIT_SETTLE", Color3.new(1, 1, 0))
            break
        end

        if hasPromptHiddenAfterInteraction() or probableObservedAt > 0 then
            Logger:Log("[TELEMETRY] POST_TRIGGER_OBSERVE_ONLY attempt=" .. tostring(attempt), Color3.new(1, 1, 0))
            break
        end

        do
            local sustainOk, sustainReason = sustainBurstPose(Config.BurstRapidAttemptDelay, false)
            if not sustainOk then
                if sustainReason == "BURST_ABORT_MANUAL" or sustainReason == "STATE_OVERRIDDEN" then
                    return finishBurst(false, sustainReason)
                end
                Logger:Log("[TELEMETRY] ENTITY_LOST_INTER_ATTEMPT: " .. tostring(sustainReason), Color3.new(1, 0, 0))
                if markCarrySwapPending("inter_attempt", sustainReason) then
                    return finishBurst(false, "CARRY_SWAP_PENDING")
                end
                return finishBurst(false, "NO_ENTITY")
            end
        end
    end

    local confirmDeadline = tick() + Config.BurstPostFireConfirmWindow
    while tick() < confirmDeadline do
        if not Config.Activo then return finishBurst(false, "BURST_ABORT_MANUAL") end
        if FSM.StateID ~= burstToken then return finishBurst(false, "STATE_OVERRIDDEN") end

        local charB, hrpB, humB = FSM:GetValidEntity()
        if not hrpB or not charB or not humB then
            local lossReason = getEntityLossReason()
            Logger:Log("[TELEMETRY] ENTITY_LOST_CONFIRM: " .. lossReason, Color3.new(1, 0, 0))
            if markCarrySwapPending("confirm", lossReason) then
                return finishBurst(false, "CARRY_SWAP_PENDING")
            end
            return finishBurst(false, "NO_ENTITY")
        end

        local lastHP = humB:GetAttribute("LastHP") or humB.Health
        if humB.Health < lastHP then return finishBurst(false, "HP_DROPPED_IN_BURST") end

        maintainBurstPose(charB, hrpB, triggeredObserved or hasPromptHiddenAfterInteraction() or probableObservedAt > 0 or burstSignals.claimSeen)

        local confirmOk, confirmReason = checkPositiveConfirmation("CONFIRM_WINDOW")
        if confirmOk then
            Logger:Log("[TELEMETRY] PICKUP_CONFIRMED: " .. tostring(confirmReason), Color3.new(0, 1, 0))
            return finishBurst(true, confirmReason)
        elseif confirmReason == "CARRY_SWAP_PENDING" then
            return finishBurst(false, confirmReason)
        elseif confirmReason == "CLAIM_WITHOUT_CARRY_CONFIRM" or confirmReason == "CLAIM_SETTLE_LOST" then
            return finishBurst(false, confirmReason)
        end

        if targetRoot and not targetRoot:IsDescendantOf(workspace) then
            Logger:Log("[TELEMETRY] TARGET_VANISHED_PRE_CONFIRM", Color3.new(1, 0.5, 0))
            return finishBurst(false, "TARGET_VANISHED_PRE_CONFIRM")
        end

        if not prompt or not prompt:IsDescendantOf(workspace) then
            Logger:Log("[TELEMETRY] NO_PROMPT_CONFIRM", Color3.new(1, 0.5, 0))
            return finishBurst(false, "NO_PROMPT")
        end

        if not interactionObserved and not burstSignals.claimSeen and not triggeredObserved and not hasPromptHiddenAfterInteraction() and probableObservedAt <= 0 and prompt.Enabled and (tick() - lastConfirmRefireAt) >= Config.BurstFireEvery then
            lastConfirmRefireAt = tick()
            maintainBurstPose(charB, hrpB, false)
            interactionObserved = true
            lastInteractionAt = tick()

            local refireOk, refireMode = performPromptInteraction(charB, hrpB, prompt)
            if refireOk then
                Logger:Log("[TELEMETRY] GRAB_REFIRE mode=" .. tostring(refireMode), Color3.new(1, 1, 0))
            end
        end

        -- Triggered pero sin claim aun: el server puede haber rechazado el primer fire.
        -- Reintenta una vez despues de 2s para darle otra oportunidad.
        if triggeredObserved and not burstSignals.claimSeen and not hasPromptHiddenAfterInteraction()
            and probableObservedAt <= 0
            and prompt and prompt:IsDescendantOf(workspace) and prompt.Enabled
            and lastInteractionAt > 0 and (tick() - lastInteractionAt) >= 2.0 then
            lastInteractionAt = tick()
            lastConfirmRefireAt = tick()
            maintainBurstPose(charB, hrpB, false)
            local retryOk, retryMode = performPromptInteraction(charB, hrpB, prompt)
            if retryOk then
                Logger:Log("[TELEMETRY] GRAB_TRIGGER_RETRY mode=" .. tostring(retryMode), Color3.new(1, 0.7, 0))
            end
        end

        RS.Heartbeat:Wait()
    end

    Logger:Log("[TELEMETRY] GRAB_FAIL_NO_CONFIRM", Color3.new(1, 0.5, 0))
    if triggeredObserved then
        Logger:Log("[TELEMETRY] TRIGGER_WITHOUT_PICKUP_CONFIRM", Color3.new(1, 0.5, 0))
        return finishBurst(false, "TRIGGER_WITHOUT_PICKUP_CONFIRM")
    end
    return finishBurst(false, "PROMPT_NOT_CONFIRMED")
end

-- ==============================================================================
-- 6. SECUENCIA NÚCLEO (L-SHAPE ROUTING)
-- ==============================================================================
local function FarmRoutine(targetRoot, prompt)
    if FSM.Phase ~= "IDLE" then return end
    if not targetRoot or not targetRoot:IsDescendantOf(workspace) or not prompt or not prompt:IsDescendantOf(workspace) or not prompt.Enabled then return end
    
    local char, hrp = FSM:GetValidEntity()
    if not hrp or not Config.Home then return end
    if FSM:IsTargetCoolingDown(targetRoot, prompt) then return end

    local blocked, reason = FSM:IsRoutineBlocked()
    if blocked then
        if (tick() - (FSM.LastStartBlockLogAt or 0)) > 1.0 then
            Logger:Log("[START_BLOCKED] " .. tostring(reason), Color3.new(1, 0.5, 0))
            FSM.LastStartBlockLogAt = tick()
        end
        return
    end

    FSM.TargetRoot = targetRoot 
    FSM.TargetPrompt = prompt 
    Motor:SetGhostMode(true) 
    
    local diff = (hrp.Position - targetRoot.Position) 
    local dirXZ = Vector3.new(diff.X, 0, diff.Z) 
    dirXZ = dirXZ.Magnitude < 0.01 and Vector3.new(1,0,0) or dirXZ.Unit 
    local spotXZ = targetRoot.Position + (dirXZ * Config.Distancia) 
    local cCobro, promptPos = GetBurstPickupCFrame(targetRoot, prompt)
    
    local posHRP = hrp.Position 
    local cDropLocal = CFrame.lookAt(Vector3.new(posHRP.X, Config.Y_Transito, posHRP.Z), Vector3.new(spotXZ.X, Config.Y_Transito, spotXZ.Z)) 
    local cTrans = CFrame.lookAt(Vector3.new(spotXZ.X, Config.Y_Transito, spotXZ.Z), Vector3.new(targetRoot.Position.X, Config.Y_Transito, targetRoot.Position.Z)) 
    
    FSM:TransitionTo("TRANSIT_DROP", "Bajar")
    local okD, errD = Motor:Travel(cDropLocal, FSM.StateID) 
    if not okD then if FSM.Phase == "TRANSIT_DROP" then FSM:TransitionTo("EMERGENCY", errD) end; return end 
    
    FSM:TransitionTo("TRANSIT_HORIZONTAL", "Acercar")
    local okT, errT = Motor:Travel(cTrans, FSM.StateID) 
    if not okT then if FSM.Phase == "TRANSIT_HORIZONTAL" then FSM:TransitionTo("EMERGENCY", errT) end; return end 
    
    FSM:TransitionTo("BURST", "Interact") 
    local okB, errB = Motor:ExecuteBurst(targetRoot, prompt, cCobro, FSM.StateID) 
    if not okB then 
        if FSM.Phase == "BURST" then
            if errB == "CARRY_SWAP_PENDING" then
                Logger:Log("[CARRY_SWAP] pickup aceptado, esperando respawn para volver a base", Color3.new(1, 1, 0))
                FSM:TransitionTo("DEAD", "Carry Swap Pending")
            elseif errB == "NO_PROMPT" or errB == "PROMPT_NOT_CONFIRMED" or errB == "TRIGGER_WITHOUT_PICKUP_CONFIRM" or errB == "CLAIM_WITHOUT_CARRY_CONFIRM" or errB == "CLAIM_SETTLE_LOST" or errB == "TARGET_VANISHED_PRE_CONFIRM" then
                FSM:MarkTargetCooldown(targetRoot, prompt, Config.TargetRetryCooldown, errB)
                FSM:HandleBurstSoftReset(errB)
            else
                FSM:TransitionTo("EMERGENCY", errB)
            end
        end 
        return
    end 

    local fieldStowOk, fieldStowReason = FSM:WaitForFieldPickupStow()
    local shouldReturnHome = not fieldStowOk
    if fieldStowOk then
        local carryCountNow = FSM:RecordSessionPickup(fieldStowReason)
        if carryCountNow >= math.max(Config.ReturnAt or 1, 1) then
            shouldReturnHome = true
            Logger:Log(string.format("[RETURN_TRIGGER] THRESHOLD %d/%d", carryCountNow, math.max(Config.ReturnAt or 1, 1)), Color3.new(0, 1, 1))
        else
            Logger:Log(string.format("[FIELD_STOW_OK] %s carry=%d/%d", tostring(fieldStowReason), carryCountNow, math.max(Config.ReturnAt or 1, 1)), Color3.new(0, 1, 0))
        end
    else
        Logger:Log("[FIELD_STOW_PENDING] " .. tostring(fieldStowReason), Color3.new(1, 0.8, 0))
        Logger:Log("[RETURN_TRIGGER] HARD_CARRY_PENDING", Color3.new(1, 1, 0))
    end

    if shouldReturnHome then
        FSM:RunHomeReturn(targetRoot, prompt, fieldStowOk and "Threshold Return" or "Hard Carry Return", fieldStowOk and "SUCCESS_THRESHOLD" or "SUCCESS_HARD_CARRY")
        return
    end

    FSM:MarkTargetCooldown(targetRoot, prompt, Config.TargetSuccessCooldown, "SUCCESS_STORED")
    FSM:TransitionTo("IDLE", "Pickup Stored")
    local _, safeRoot = FSM:GetValidEntity()
    if safeRoot then
        Motor:SealCharacter(safeRoot)
    end
    if not Config.Activo then
        FSM:ReleaseCharacterIfSafe("Pickup Stored")
    else
        Logger:Log("[CYCLE_READY_STORED]", Color3.new(0, 1, 0))
    end
end

-- ==============================================================================
-- 7. EVENTOS Y CONTROL DE FLUJO
-- ==============================================================================
table.insert(Threads, safeSpawn("Heartbeat Monitor", function()
    while RS.Heartbeat:Wait() do
        local char, hrp, hum = FSM:GetValidEntity()
        if hrp and hum then
            if not Config.Activo and FSM.Phase == "IDLE" and FSM.PendingSafeRelease and not FSM.DeadLatch then
                local now = tick()
                if (now - (FSM.LastReleaseAttemptAt or 0)) >= Config.AutoReleaseRetryEvery then
                    FSM.LastReleaseAttemptAt = now
                    local released = FSM:ReleaseCharacterIfSafe(FSM.PendingSafeReleaseReason or "Deferred Release")
                    if not released then
                        Motor:SealCharacter(hrp)
                    end
                end
            end

            if Config.Activo then
                if FSM.Phase == "EMERGENCY" then
                    Motor:SealCharacter(hrp)
                    if FSM:IsHomeCFrameSafe(Config.Home) then
                        if hrp.Position.Y < (Config.Y_Transito + 0.5) then
                            Motor:TeleportCharacter(char, hrp, Config.Home + Vector3.new(0, 3, 0), true)
                            FSM.EmergencyTicks = 0
                        else
                            local stable, reason, nextPos = FSM:CheckStabilitySample(hrp, hum, FSM.LastStabilityPos, {
                                minY = Config.Y_Transito + 1.0,
                                minHealth = Config.MinRecoverHealth,
                                requireAnchored = true
                            })
                            FSM.LastStabilityPos = nextPos
                            FSM.EmergencyTicks = stable and ((FSM.EmergencyTicks or 0) + 1) or 0
                            if FSM.EmergencyTicks > Config.ReleaseStableFrames then
                                Logger:Log("[RECOVERY] Saliendo de EMERGENCY con ventana estable", Color3.new(0, 1, 0))
                                FSM:TransitionTo("IDLE", "Auto Recovery Stable")
                            elseif not stable and reason == "LOW_HP" then
                                if ((FSM.LastStartBlockLogAt or 0) + 1.0) < tick() then
                                    Logger:Log("[RECOVERY_BLOCKED] LOW_HP_RECOVER", Color3.new(1, 0.5, 0))
                                    FSM.LastStartBlockLogAt = tick()
                                end
                            end
                        end
                    else
                        FSM.EmergencyTicks = 0
                    end
                end

                local distXZ = -1
                local dist3D = -1
                if FSM.TargetRoot and FSM.TargetRoot.Parent then 
                    local pPos = FSM.TargetRoot.Position
                    dist3D = (hrp.Position - pPos).Magnitude
                    distXZ = math.sqrt((hrp.Position.X - pPos.X)^2 + (hrp.Position.Z - pPos.Z)^2)
                end
                
                Logger.Snapshots[Logger.SnapIndex] = { 
                    t = tick(), hp = hum.Health, y = hrp.Position.Y, vy = hrp.AssemblyLinearVelocity.Y, 
                    phase = FSM.Phase, distXZ = distXZ, dist3D = dist3D, anchored = hrp.Anchored 
                }
                Logger.SnapIndex = (Logger.SnapIndex % 30) + 1
                
                local currentHP = hum.Health 
                local lastHP = hum:GetAttribute("LastHP") or currentHP 
                if currentHP < lastHP and FSM.Phase ~= "IDLE" and FSM.Phase ~= "EMERGENCY" then 
                    Logger:Log("[TELEMETRY] HP_CHANGE: " .. tostring(lastHP) .. " -> " .. tostring(currentHP), Color3.new(1, 0, 0))
                    if currentHP <= Config.MinRecoverHealth then
                        Logger:Dump("CRITICAL_DAMAGE") 
                        FSM:TransitionTo("EMERGENCY", "Critical Damage Abort") 
                    end
                end 
                hum:SetAttribute("LastHP", currentHP) 

                if hrp.AssemblyLinearVelocity.Y < -40.0 and FSM.Phase ~= "IDLE" and FSM.Phase ~= "EMERGENCY" and FSM.Phase ~= "DEAD" then
                    Logger:Dump("FALLING_DETECTED")
                    FSM:TransitionTo("EMERGENCY", "Physics Fall Abort")
                end
            end
        end 
    end 
end))

table.insert(Threads, safeSpawn("Target Picker", function()
    while task.wait(0.2) do
        if Config.Activo and FSM.Phase == "IDLE" and not FSM:HasPendingCarrySwap() then
            local char, hrp = FSM:GetValidEntity()
            if hrp then
                local folder = workspace:FindFirstChild("ActiveBrainrots")
                if folder then
                    local bestRoot, bestPrompt, bestCandidate = nil, nil, nil
                    for _, rarityFolder in pairs(folder:GetChildren()) do 
                        for _, rot in pairs(rarityFolder:GetChildren()) do
                            local tr = rot:FindFirstChild("Root")
                            local pr = rot:FindFirstChild("TakePrompt", true)
                            if tr and pr and pr.Enabled and (not FSM:IsTargetCoolingDown(tr, pr)) then
                                local candidate = evaluateTargetCandidate(rot, tr, pr, hrp)
                                if candidate then
                                    local shouldTake = not bestCandidate
                                        or candidate.score > bestCandidate.score
                                        or (candidate.score == bestCandidate.score and candidate.distance < bestCandidate.distance)
                                    if shouldTake then
                                        bestCandidate = candidate
                                        bestRoot = tr
                                        bestPrompt = pr
                                    end
                                end
                            end
                        end 
                    end
                    if bestRoot and bestPrompt then
                        FarmRoutine(bestRoot, bestPrompt)
                    elseif Config.ReturnWhenNoTargets and FSM:HasStoredSessionCarry() then
                        Logger:Log(string.format("[RETURN_TRIGGER] SIN_TARGETS carry=%d/%d", FSM:GetSessionCarryCount(), math.max(Config.ReturnAt or 1, 1)), Color3.new(0, 1, 1))
                        FSM:RunHomeReturn(nil, nil, "No Targets Return", "RETURN_NO_TARGETS")
                    end
                end
            end
        end
    end
end))

local lastMutsCache = ""
table.insert(Threads, safeSpawn("Mutation Scanner", function()
    while task.wait(1.5) do
        if Config.Activo then continue end
        local folder = workspace:FindFirstChild("ActiveBrainrots"); if not folder then continue end
        local currentMuts = {}; 
        for _, r in pairs(folder:GetChildren()) do 
            for _, rot in pairs(r:GetChildren()) do 
                local m = getTargetMutation(rot)
                if m and m ~= "None" then currentMuts[m] = true end 
            end 
        end
        local keys = {}; for k in pairs(currentMuts) do table.insert(keys, k) end; table.sort(keys); 
        local cacheString = table.concat(keys, "|")
        if cacheString == lastMutsCache then continue end; lastMutsCache = cacheString

        if not UI.ButtonPool[1] then
            local autoButton = Instance.new("TextButton", mutScroll)
            autoButton.Size = UDim2.new(1,-10,0,25)
            autoButton.TextColor3 = Color3.new(1,1,1)
            UI.ButtonPool[1] = {btn = autoButton, conn = nil}
        end

        local autoButtonData = UI.ButtonPool[1]
        autoButtonData.btn.Visible = true
        autoButtonData.btn.Text = "AUTO ATRIBUTOS"
        autoButtonData.btn.BackgroundColor3 = (getActiveTargetMode() == "ATTRIBUTES") and Color3.fromRGB(0,120,200) or Color3.fromRGB(45,45,45)
        if autoButtonData.conn then autoButtonData.conn:Disconnect() end
        autoButtonData.conn = connectProtected(autoButtonData.btn.MouseButton1Click, function()
            Config.Mutacion = nil
            lastMutsCache = ""
            refreshTitle()
            Logger:Log("[TARGET_MODE] " .. getTargetModeSummary(), Color3.new(0, 1, 1))
        end, "Auto Target Mode Button")

        for i, m in ipairs(keys) do 
            local poolIndex = i + 1
            if not UI.ButtonPool[poolIndex] then 
                local b = Instance.new("TextButton", mutScroll); b.Size = UDim2.new(1,-10,0,25); b.TextColor3 = Color3.new(1,1,1) 
                UI.ButtonPool[poolIndex] = {btn = b, conn = nil} 
            end 
            local bData = UI.ButtonPool[poolIndex] 
            bData.btn.Visible = true; bData.btn.Text = m; bData.btn.BackgroundColor3 = (Config.Mutacion == m) and Color3.fromRGB(0,120,200) or Color3.fromRGB(45,45,45) 
            if bData.conn then bData.conn:Disconnect() end 
            bData.conn = connectProtected(bData.btn.MouseButton1Click, function()
                Config.Mutacion = m
                lastMutsCache = ""
                refreshTitle()
                Logger:Log("[TARGET_MODE] " .. getTargetModeSummary(), Color3.new(0, 1, 1))
            end, "Mutation Button") 
        end 
        for i = #keys + 2, #UI.ButtonPool do UI.ButtonPool[i].btn.Visible = false end
    end 
end))

-- ==============================================================================
-- 8. UI DRAG & CONTROLES
-- ==============================================================================
local dragging, dragStart, startPos = false, nil, nil

safeConnect(topBar.InputBegan, function(input) 
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then 
        dragging = true 
        dragStart = input.Position 
        startPos = main.Position 
    end 
end, "TopBar InputBegan")

safeConnect(UIS.InputChanged, function(input) 
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then 
        local delta = input.Position - dragStart 
        main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y) 
    end 
end, "UIS InputChanged")

safeConnect(UIS.InputEnded, function(input) 
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then 
        dragging = false 
    end 
end, "UIS InputEnded")

safeConnect(btnCopy.MouseButton1Click, function()
    if copyToClipboard(Logger:BuildCopyPayload()) then
        Logger:Log("LOGS COPIADOS", Color3.new(0,1,0))
    else
        Logger:Log("PORTAPAPELES NO DISPONIBLE", Color3.new(1,0.5,0))
    end
end, "Copy Button")

safeConnect(btnToggle.MouseButton1Click, function()
    UI.Minimized = not UI.Minimized
    local newH = UI.Minimized and 30 or 315
    main.Size = UDim2.new(0, 260, 0, newH)
    btnToggle.Text = UI.Minimized and "+" or "−"
    logBox.Visible = not UI.Minimized
    mutScroll.Visible = not UI.Minimized
    footer.Visible = not UI.Minimized
end, "Toggle Button")

safeConnect(btnAction.MouseButton1Click, function()
    local char, hrp, hum = FSM:GetValidEntity()

    if not Config.Activo then
        if FSM.DeadLatch or FSM.Phase == "DEAD" then
            Logger:Log("[START_BLOCKED] DEAD terminal. Esperando CharacterAdded estable.", Color3.new(1, 0.3, 0.3))
            return
        end
        if not hrp or not hum then
            Logger:Log("[START_BLOCKED] NO_ENTITY", Color3.new(1, 0.5, 0))
            return
        end
        if hum.Health < Config.MinStartHealth then
            Logger:Log("[START_BLOCKED] LOW_HP_START", Color3.new(1, 0.5, 0))
            return
        end

        Motor:SealCharacter(hrp)
        FSM:SaveHomeIfSafe(hrp)
        if not FSM:IsHomeCFrameSafe(Config.Home) then
            Logger:Log("[START_BLOCKED] HOME_INVALID", Color3.new(1, 0.5, 0))
            return
        end

        FSM:ResetSessionCarry("START_SESSION")

        Config.Activo = true
        btnAction.Text = "DETENER"
        btnAction.BackgroundColor3 = Color3.fromRGB(200, 0, 0)

        if hrp then
            Motor:SealCharacter(hrp)
        end
        refreshTitle()
        Logger:Log("[TARGET_MODE] " .. getTargetModeSummary(), Color3.new(0, 1, 1))
        Logger:Log("[START_READY_SEALED]", Color3.new(0, 1, 0))
    else
        Config.Activo = false
        btnAction.Text = "INICIAR"
        btnAction.BackgroundColor3 = Color3.fromRGB(0, 150, 50)
        FSM:StopSafely()
    end
end, "Action Button")

safeConnect(player.CharacterRemoving, function(char)
    Logger:Dump("CHARACTER_REMOVING")
    local isCarrySwap = FSM.PostTriggerRemovalExpected
    FSM.PostTriggerRemovalExpected = false
    FSM:TransitionTo("DEAD", "CharRemoving")
    FSM.LastStabilityPos = nil
    FSM.Session += 1
    if isCarrySwap and Config.BurstCarrySwapAutoResume then
        Logger:Log("[CARRY_SWAP] CharRemoving post-trigger: mantener Activo para reanudar", Color3.new(0, 1, 1))
    else
        Config.Activo = false
        btnAction.Text = "INICIAR"; btnAction.BackgroundColor3 = Color3.fromRGB(0, 150, 50)
    end
end, "CharacterRemoving")

safeConnect(player.CharacterAdded, function(char)
    FSM.LastRespawnAt = tick()
    FSM.LastStabilityPos = nil
    FSM:ClearTargets()
    Logger:Log("[RESPAWN] CharacterAdded detectado", Color3.new(0, 1, 1))

    safeSpawn("CharacterAdded Resume", function()
        task.wait(0.4)
        local respawnStamp = FSM.LastRespawnAt
        local ok, reason = FSM:WaitForStableWindow(Config.RespawnStableFrames, {
            minY = Config.Y_Transito + 1.0,
            minHealth = Config.MinRecoverHealth,
            requireAnchored = false,
            maxFrames = 90,
            allowMissingEntityFrames = 45
        })
        if FSM.LastRespawnAt ~= respawnStamp then return end

        local _, respawnRoot = FSM:GetValidEntity()
        if ok and respawnRoot then
            Motor:SealCharacter(respawnRoot)
            FSM.DeadLatch = false
            if FSM.Phase == "DEAD" then
                FSM:TransitionTo("IDLE", "CharacterAdded Stable")
            end

            if FSM:HasPendingCarrySwap() then
                Logger:Log("[CARRY_SWAP] Verificando pickup tras respawn", Color3.new(0, 1, 1))
                local pending = FSM.PendingCarrySwap
                local swapOk, swapReason = FSM:WaitForCarrySwapResolution()
                if swapOk then
                    Logger:Log("[CARRY_SWAP] PICKUP_CONFIRMADO: " .. tostring(swapReason), Color3.new(0, 1, 0))
                    local returnChar, returnRoot = FSM:GetValidEntity()
                    if returnRoot and FSM:IsHomeCFrameSafe(Config.Home) then
                        FSM:TransitionTo("RETURN", "Carry Swap Resume")
                        local clearedCarry, carryClearReason = FSM:ExecuteHomeUnloadSequence()
                        if not clearedCarry and (carryClearReason == "HOME_INVALID" or carryClearReason == "NO_ENTITY") then
                            Logger:Log("[CARRY_SWAP] RETURN_FAIL: " .. tostring(carryClearReason), Color3.new(1, 0.5, 0))
                            FSM:ClearPendingCarrySwap()
                            FSM:TransitionTo("EMERGENCY", carryClearReason)
                            return
                        end
                        if clearedCarry then
                            Logger:Log("[RETURN_CLEAR] carry descargado", Color3.new(0, 1, 0))
                            local _, _, clearHum = FSM:GetValidEntity()
                            if clearHum then
                                TryUnequipEquippedTool(clearHum, "CARRY_SWAP_CLEAR")
                            end
                        else
                            Logger:Log("[RETURN_CLEAR_PENDING] " .. tostring(carryClearReason), Color3.new(1, 0.8, 0))
                        end
                        FSM:MarkTargetCooldown(pending and pending.targetRoot, pending and pending.prompt, Config.TargetSuccessCooldown, "CARRY_SWAP_SUCCESS")
                        FSM:ClearPendingCarrySwap()
                        FSM:TransitionTo("IDLE", clearedCarry and "Carry Swap Success" or "Carry Swap Pending Clear")
                        if not Config.Activo then
                            FSM:RequestSafeRelease(clearedCarry and "Carry Swap Success" or "Carry Swap Pending Clear")
                        elseif not clearedCarry then
                            Logger:Log("[CYCLE_BLOCKED] esperando descarga home", Color3.new(1, 0.8, 0))
                        else
                            Logger:Log("[CYCLE_READY_SEALED]", Color3.new(0, 1, 0))
                        end
                    else
                        Logger:Log("[CARRY_SWAP] HOME_INVALID_POST_RESPAWN", Color3.new(1, 0.5, 0))
                        FSM:ClearPendingCarrySwap()
                    end
                else
                    Logger:Log("[CARRY_SWAP] Sin confirmacion tras respawn: " .. tostring(swapReason), Color3.new(1, 0.5, 0))
                    FSM:ClearPendingCarrySwap()
                end
            end

            if not Config.Activo then
                FSM:RequestSafeRelease("Respawn Stable")
            end
            Logger:Log("[RESPAWN_READY] Character estable", Color3.new(0, 1, 0))
        else
            Logger:Log("[RESPAWN_UNSTABLE] " .. tostring(reason), Color3.new(1, 0.5, 0))
        end
    end)
end, "CharacterAdded")

_G.IvanFarmer_Cleanup = function()
    Config.Activo = false; FSM.Session += 1
    for _, conn in ipairs(Connections) do pcall(function() conn:Disconnect() end) end
    table.clear(Connections)
    for _, th in ipairs(Threads) do pcall(function() task.cancel(th) end) end
    table.clear(Threads)
    FSM:TransitionTo("IDLE", "Cleanup") 
    destroyExistingGui()
end

refreshTitle()
Logger:Log("V236 Attribute Targeting Ready.", Color3.new(0, 1, 0.4))
Logger:Log("[TARGET_MODE] " .. getTargetModeSummary(), Color3.new(0, 1, 1))
Logger:Log(string.format("[CONFIG] PromptRootOff=%.2f | Dist=%.1f | StartHP=%.0f | RecoverHP=%.0f | Burst=%s | PromptMax=%.0f | HoldSpoof=%s | Attempts=%d | RetryCD=%.2f | ReturnAt=%d", Config.BurstPromptRootOffset, Config.Distancia, Config.MinStartHealth, Config.MinRecoverHealth, Config.BurstMode, Config.BurstPromptMaxDistance, tostring(Config.BurstSpoofHoldDuration), Config.BurstRapidAttempts, Config.TargetRetryCooldown, math.max(Config.ReturnAt or 1, 1)), Color3.new(0, 1, 1))
