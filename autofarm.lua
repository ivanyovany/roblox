--[[
CARRY SWAP SPY v1
Propósito: observar en silencio EXACTAMENTE qué objetos llegan al personaje
           después de un pickup / carry swap (muerte → respawn con carry).
           
No interfiere con nada. Solo lee y loggea.

INSTRUCCIONES:
1. Ejecutar este script.
2. Acercarte MANUALMENTE a un brainrot y recogerlo (o dejar que el autofarm lo haga).
3. Observar los logs. El bloque POST_SWAP_WINDOW es clave:
   muestra todo lo que aparece en tu personaje durante los 6 segundos post-respawn.
4. Copiar los logs con COPY y compartir.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")

local player = Players.LocalPlayer
local GUI_NAME = "CarrySwapSpy"
local VERSION = "spy-v1"
local MAX_LOGS = 80
local MAX_STORED = 1200
local POST_SWAP_WINDOW_SECONDS = 6.0  -- cuánto tiempo observar el personaje nuevo

-- ────────────────────────────────────────────────────────────────────────────
-- LIMPIEZA PREVIA
-- ────────────────────────────────────────────────────────────────────────────
if CoreGui:FindFirstChild(GUI_NAME) then
    CoreGui:FindFirstChild(GUI_NAME):Destroy()
end

local connections = {}
local storedLogs = {}
local uiLabels = {}
local closed = false

local function addConn(conn)
    table.insert(connections, conn)
    return conn
end

local function cleanup()
    closed = true
    for _, c in ipairs(connections) do
        pcall(function() c:Disconnect() end)
    end
    table.clear(connections)
    local gui = CoreGui:FindFirstChild(GUI_NAME)
    if gui then gui:Destroy() end
end

-- ────────────────────────────────────────────────────────────────────────────
-- UI
-- ────────────────────────────────────────────────────────────────────────────
local sg = Instance.new("ScreenGui")
sg.Name = GUI_NAME
sg.ResetOnSpawn = false
sg.Parent = CoreGui

local frame = Instance.new("Frame", sg)
frame.Size = UDim2.new(0, 480, 0, 370)
frame.Position = UDim2.new(0.5, -240, 0.03, 0)
frame.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
frame.BorderSizePixel = 1
frame.Active = true
frame.Draggable = true

local topBar = Instance.new("Frame", frame)
topBar.Size = UDim2.new(1, 0, 0, 28)
topBar.BackgroundColor3 = Color3.fromRGB(20, 80, 160)

local titleLbl = Instance.new("TextLabel", topBar)
titleLbl.Size = UDim2.new(1, -100, 1, 0)
titleLbl.Position = UDim2.new(0, 6, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text = "CARRY SWAP SPY | " .. VERSION
titleLbl.TextColor3 = Color3.new(1,1,1)
titleLbl.Font = Enum.Font.SourceSansBold
titleLbl.TextSize = 14
titleLbl.TextXAlignment = Enum.TextXAlignment.Left

local btnCopy = Instance.new("TextButton", topBar)
btnCopy.Size = UDim2.new(0, 60, 0, 22)
btnCopy.Position = UDim2.new(1, -130, 0, 3)
btnCopy.Text = "COPY"
btnCopy.BackgroundColor3 = Color3.fromRGB(55, 55, 55)
btnCopy.TextColor3 = Color3.new(1,1,1)
btnCopy.Font = Enum.Font.SourceSansBold

local btnClose = Instance.new("TextButton", topBar)
btnClose.Size = UDim2.new(0, 60, 0, 22)
btnClose.Position = UDim2.new(1, -65, 0, 3)
btnClose.Text = "CERRAR"
btnClose.BackgroundColor3 = Color3.fromRGB(120, 30, 30)
btnClose.TextColor3 = Color3.new(1,1,1)
btnClose.Font = Enum.Font.SourceSansBold

local statusLbl = Instance.new("TextLabel", frame)
statusLbl.Size = UDim2.new(1, -10, 0, 18)
statusLbl.Position = UDim2.new(0, 5, 0, 30)
statusLbl.BackgroundTransparency = 1
statusLbl.TextColor3 = Color3.fromRGB(180, 220, 255)
statusLbl.Font = Enum.Font.SourceSans
statusLbl.TextSize = 13
statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.Text = "Observando... Acércate a un brainrot y recógelo"

local logBox = Instance.new("ScrollingFrame", frame)
logBox.Size = UDim2.new(1, -10, 1, -52)
logBox.Position = UDim2.new(0, 5, 0, 50)
logBox.BackgroundColor3 = Color3.fromRGB(4, 4, 4)
logBox.ScrollBarThickness = 5

local listLayout = Instance.new("UIListLayout", logBox)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder

for i = 1, MAX_LOGS do
    local lbl = Instance.new("TextLabel", logBox)
    lbl.Size = UDim2.new(1, -4, 0, 13)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.Code
    lbl.TextSize = 11
    lbl.TextColor3 = Color3.new(1,1,1)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Text = ""
    lbl.LayoutOrder = i
    uiLabels[i] = lbl
end

-- ────────────────────────────────────────────────────────────────────────────
-- LOGGER
-- ────────────────────────────────────────────────────────────────────────────
local function pushLog(msg, color)
    local line = string.format("[%s] %s", os.date("%X"), msg)
    table.insert(storedLogs, line)
    while #storedLogs > MAX_STORED do
        table.remove(storedLogs, 1)
    end
    for i = 1, MAX_LOGS - 1 do
        uiLabels[i].Text = uiLabels[i+1].Text
        uiLabels[i].TextColor3 = uiLabels[i+1].TextColor3
    end
    uiLabels[MAX_LOGS].Text = line
    uiLabels[MAX_LOGS].TextColor3 = color or Color3.new(1,1,1)
    logBox.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 4)
    logBox.CanvasPosition = Vector2.new(0, math.max(0, listLayout.AbsoluteContentSize.Y))
end

local function L(tag, msg, color)
    pushLog(string.format("[%s] %s", tag, tostring(msg)), color)
end

local WHITE    = Color3.new(1, 1, 1)
local GREEN    = Color3.fromRGB(80, 255, 120)
local YELLOW   = Color3.fromRGB(255, 240, 80)
local ORANGE   = Color3.fromRGB(255, 160, 50)
local RED      = Color3.fromRGB(255, 80, 80)
local CYAN     = Color3.fromRGB(80, 220, 255)
local MAGENTA  = Color3.fromRGB(255, 120, 255)
local GRAY     = Color3.fromRGB(160, 160, 160)

-- ────────────────────────────────────────────────────────────────────────────
-- HELPERS DE INSTANCIA
-- ────────────────────────────────────────────────────────────────────────────
local function safePath(inst)
    if not inst then return "nil" end
    local ok, v = pcall(function() return inst:GetFullName() end)
    return (ok and v) or tostring(inst)
end

local function shortPath(inst, keep)
    local parts = string.split(safePath(inst), ".")
    local n = keep or 5
    if #parts <= n then return table.concat(parts, ".") end
    local out = {}
    for i = #parts - n + 1, #parts do table.insert(out, parts[i]) end
    return table.concat(out, ".")
end

local function isCarrySignal(inst)
    if not inst then return false end
    if inst:IsA("Tool") then return true end
    local lo = string.lower(inst.Name)
    if lo == "holdweld" or lo == "rightgrip" then return true end
    if lo:find("brainrot", 1, true) or lo:find("carry", 1, true)
    or lo:find("render", 1, true) or lo:find("hold", 1, true) then
        return true
    end
    if inst:IsA("Weld") or inst:IsA("WeldConstraint") or inst:IsA("Motor6D") then
        return true
    end
    return false
end

-- Vuelca toda la jerarquía relevante de una instancia
local function dumpHierarchy(root, tag, color)
    if not root then return end
    local function recurse(inst, depth)
        if depth > 6 then return end
        local lo = string.lower(inst.Name)
        local interesting = inst:IsA("Tool") or inst:IsA("Model") or inst:IsA("Folder")
            or inst:IsA("Weld") or inst:IsA("WeldConstraint") or inst:IsA("Motor6D")
            or inst:IsA("ProximityPrompt")
            or lo:find("brainrot",1,true) or lo:find("carry",1,true)
            or lo:find("hold",1,true) or lo:find("render",1,true)
            or lo:find("grip",1,true)
        if interesting then
            L(tag, string.rep(" ", depth*2) .. inst.ClassName .. " [" .. inst.Name .. "]", color)
        end
        for _, child in ipairs(inst:GetChildren()) do
            recurse(child, depth + 1)
        end
    end
    recurse(root, 0)
end

-- Snapshot resumido del personaje: tools + carry signals
local function snapshotCharacter(char, label)
    if not char then
        L("SNAP", label .. " | NO_CHAR", GRAY)
        return
    end
    local root = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    local tool = char:FindFirstChildOfClass("Tool")
    local hp = hum and string.format("%.0f", hum.Health) or "?"
    local anchored = root and tostring(root.Anchored) or "?"
    local y = root and string.format("%.2f", root.Position.Y) or "?"
    L("SNAP", string.format("%s | hp=%s y=%s anc=%s tool=%s", label, hp, y, anchored, tostring(tool and tool.Name or "none")), YELLOW)
    
    -- Carry signals en character root
    if root then
        local hw = root:FindFirstChild("HoldWeld")
        local rg = root:FindFirstChild("RightGrip", true)
        L("SNAP", string.format("  HoldWeld=%s  RightGrip=%s", tostring(hw ~= nil), tostring(rg ~= nil)), CYAN)
    end
    
    -- RenderedBrainrot
    local rb = char:FindFirstChild("RenderedBrainrot", true)
    if rb then
        L("SNAP", "  RenderedBrainrot FOUND: " .. shortPath(rb), GREEN)
    else
        L("SNAP", "  RenderedBrainrot: NOT FOUND", GRAY)
    end
    
    -- Tools en backpack
    local bp = player:FindFirstChildOfClass("Backpack")
    local toolCount = 0
    if bp then
        for _, c in ipairs(bp:GetChildren()) do
            if c:IsA("Tool") then toolCount += 1 end
        end
    end
    L("SNAP", string.format("  backpack_tools=%d  char_tools=%s", toolCount, tostring(tool and tool.Name or "0")), CYAN)
end

-- ────────────────────────────────────────────────────────────────────────────
-- VENTANA DE OBSERVACIÓN POST-RESPAWN
-- ────────────────────────────────────────────────────────────────────────────
local postRespawnWatcher = nil

local function startPostRespawnWindow(char)
    if postRespawnWatcher then
        task.cancel(postRespawnWatcher)
        postRespawnWatcher = nil
    end

    L("POST_SWAP", string.format("=== VENTANA %gs ABIERTA ===", POST_SWAP_WINDOW_SECONDS), MAGENTA)
    snapshotCharacter(char, "RESPAWN_BASELINE")
    dumpHierarchy(char, "CHAR_TREE", GRAY)

    local tempConns = {}
    local carryFound = false

    local function tempConn(event, fn)
        table.insert(tempConns, event:Connect(fn))
    end

    -- Tools / carry signals en character
    tempConn(char.ChildAdded, function(child)
        if closed then return end
        L("POST_CHAR+", child.ClassName .. " [" .. child.Name .. "]", GREEN)
        if isCarrySignal(child) then
            carryFound = true
            L("CARRY_SIGNAL!", "CHAR_CHILD: " .. child.ClassName .. " [" .. child.Name .. "]", MAGENTA)
        end
    end)

    tempConn(char.DescendantAdded, function(desc)
        if closed then return end
        if isCarrySignal(desc) then
            carryFound = true
            L("CARRY_SIGNAL!", "CHAR_DESC: " .. desc.ClassName .. " [" .. desc.Name .. "] @ " .. shortPath(desc.Parent, 3), MAGENTA)
        end
    end)

    -- Backpack
    local bp = player:FindFirstChildOfClass("Backpack")
    if bp then
        tempConn(bp.ChildAdded, function(child)
            if closed then return end
            L("POST_BP+", child.ClassName .. " [" .. child.Name .. "]", GREEN)
            if child:IsA("Tool") then
                carryFound = true
                L("CARRY_SIGNAL!", "BACKPACK_TOOL: " .. child.Name, MAGENTA)
            end
        end)
    end

    -- HumanoidRootPart para HoldWeld
    local root = char:FindFirstChild("HumanoidRootPart")
    if root then
        tempConn(root.ChildAdded, function(child)
            if closed then return end
            local lo = string.lower(child.Name)
            if lo == "holdweld" or lo == "rightgrip" or child:IsA("Weld") or child:IsA("WeldConstraint") then
                carryFound = true
                L("CARRY_SIGNAL!", "HRP_WELD: " .. child.ClassName .. " [" .. child.Name .. "]", MAGENTA)
            end
        end)
    end

    -- ActiveBrainrots: si el target desaparece → fue reclamado
    local activeBrainrots = workspace:FindFirstChild("ActiveBrainrots")
    if activeBrainrots then
        tempConn(activeBrainrots.ChildAdded, function(c)
            if closed then return end
            L("WORLD+", "ActiveBrainrots ChildAdded: " .. c.Name, CYAN)
        end)
        tempConn(activeBrainrots.ChildRemoved, function(c)
            if closed then return end
            L("WORLD-", "ActiveBrainrots ChildRemoved: " .. c.Name, ORANGE)
        end)
        tempConn(activeBrainrots.DescendantAdded, function(d)
            if closed then return end
            if d:IsA("ProximityPrompt") then
                L("PROMPT+", "NewPrompt in ActiveBrainrots: " .. shortPath(d, 5), CYAN)
            end
        end)
        tempConn(activeBrainrots.DescendantRemoving, function(d)
            if closed then return end
            if d:IsA("ProximityPrompt") or string.lower(d.Name):find("brainrot",1,true) then
                L("WORLD-", "ActiveBrainrots REMOVING: " .. d.ClassName .. "[" .. d.Name .. "]", ORANGE)
            end
        end)
    end

    postRespawnWatcher = task.spawn(function()
        local deadline = tick() + POST_SWAP_WINDOW_SECONDS
        local lastPoll = 0
        while tick() < deadline and not closed do
            if (tick() - lastPoll) >= 0.5 then
                lastPoll = tick()
                -- Poll carry state
                local hw = char and char:FindFirstChild("HumanoidRootPart") and
                           char.HumanoidRootPart:FindFirstChild("HoldWeld")
                local rb = char and char:FindFirstChild("RenderedBrainrot", true)
                local eq = char and char:FindFirstChildOfClass("Tool")
                if hw or rb or eq then
                    carryFound = true
                    L("POLL_CARRY", string.format("HW=%s RB=%s EQ=%s", tostring(hw~=nil), tostring(rb~=nil), tostring(eq and eq.Name or "n")), GREEN)
                end
            end
            RunService.Heartbeat:Wait()
        end

        -- Resultado final
        L("POST_SWAP", "=== VENTANA CERRADA ===", MAGENTA)
        snapshotCharacter(char, "POST_WINDOW_FINAL")
        if carryFound then
            L("RESULT", "✓ CARRY SIGNALS DETECTADOS → pickup confirmable", GREEN)
        else
            L("RESULT", "✗ SIN CARRY SIGNALS en " .. string.format("%.0f", POST_SWAP_WINDOW_SECONDS) .. "s → probable falso trigger o rechazo server", RED)
        end

        for _, c in ipairs(tempConns) do
            pcall(function() c:Disconnect() end)
        end
        postRespawnWatcher = nil
    end)
end

-- ────────────────────────────────────────────────────────────────────────────
-- MONITOREO DE PROMPTS CERCANOS
-- ────────────────────────────────────────────────────────────────────────────
local promptConnections = {}

local function clearPromptConns()
    for _, c in ipairs(promptConnections) do
        pcall(function() c:Disconnect() end)
    end
    table.clear(promptConnections)
end

local function watchPrompt(prompt)
    clearPromptConns()

    local function pc(event, fn)
        table.insert(promptConnections, event:Connect(fn))
    end

    pc(prompt.Triggered, function(who)
        if who ~= player then return end
        L("PROMPT", "TRIGGERED! " .. shortPath(prompt, 5), GREEN)
        statusLbl.Text = "Prompt TRIGGERED – esperando señales de carry..."
    end)

    pc(prompt.PromptHidden, function()
        L("PROMPT", "HIDDEN " .. shortPath(prompt, 4), YELLOW)
    end)

    pc(prompt:GetPropertyChangedSignal("Enabled"), function()
        L("PROMPT", "Enabled→" .. tostring(prompt.Enabled) .. " " .. shortPath(prompt, 4), YELLOW)
    end)

    pc(prompt.AncestryChanged, function(_, p)
        L("PROMPT", "ANCESTRY parent=" .. shortPath(p, 4), ORANGE)
    end)

    L("WATCHING", "Prompt: " .. shortPath(prompt, 6) ..
        string.format(" hold=%.2f max=%.0f enabled=%s", prompt.HoldDuration, prompt.MaxActivationDistance, tostring(prompt.Enabled)), CYAN)
end

-- Escanea workspace por prompts brainrot cercanos
local function findNearbyBrainrotPrompt()
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return nil, nil end

    local activeFolder = workspace:FindFirstChild("ActiveBrainrots")
    if not activeFolder then return nil, nil end

    local best, bestModel, bestDist = nil, nil, math.huge

    for _, rarityFolder in ipairs(activeFolder:GetChildren()) do
        for _, rot in ipairs(rarityFolder:GetChildren()) do
            local prompt = rot:FindFirstChild("TakePrompt", true)
            local rotRoot = rot:FindFirstChild("Root")
            if prompt and prompt.Enabled and rotRoot then
                local d = (root.Position - rotRoot.Position).Magnitude
                if d < bestDist then
                    bestDist = d
                    best = prompt
                    bestModel = rot
                end
            end
        end
    end

    return best, bestModel, bestDist
end

-- ────────────────────────────────────────────────────────────────────────────
-- LOOP PRINCIPAL DE OBSERVACIÓN
-- ────────────────────────────────────────────────────────────────────────────
addConn(player.CharacterAdded:Connect(function(char)
    if closed then return end
    L("FLOW", "=== CHARACTER ADDED ===", GREEN)
    statusLbl.Text = "CharacterAdded → ventana post-swap abierta"
    task.wait(0.15) -- dejar que el server replique
    startPostRespawnWindow(char)
end))

addConn(player.CharacterRemoving:Connect(function()
    if closed then return end
    L("FLOW", "=== CHARACTER REMOVING ===", RED)
    local char = player.Character
    if char then
        snapshotCharacter(char, "PRE_REMOVE")
    end
end))

-- Monitorea humanoid del personaje actual
local function hookCurrentCharacter(char)
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        addConn(hum.Died:Connect(function()
            if closed then return end
            L("FLOW", "HUMANOID_DIED – escuchando respawn", RED)
            statusLbl.Text = "Personaje murió → esperando CharacterAdded..."
        end))
    end
    snapshotCharacter(char, "INITIAL")
    dumpHierarchy(char, "INITIAL_TREE", GRAY)
end

-- Tick de polling para prompt cercano
addConn(RunService.Heartbeat:Connect(function()
    if closed then return end
    if (tick() % 1.2) < 0.033 then -- ~cada 1.2 segundos
        local prompt, model, dist = findNearbyBrainrotPrompt()
        if prompt then
            local info = string.format("dist=%.1f", dist or 999)
            statusLbl.Text = "Brainrot cercano: " .. (model and model.Name or "?") .. " | " .. info
            watchPrompt(prompt)
        end
    end
end))

-- ────────────────────────────────────────────────────────────────────────────
-- UI BOTONES
-- ────────────────────────────────────────────────────────────────────────────
btnClose.MouseButton1Click:Connect(function()
    cleanup()
end)

btnCopy.MouseButton1Click:Connect(function()
    local text = table.concat(storedLogs, "\n")
    local copied = false
    if type(setclipboard) == "function" then
        local ok = pcall(setclipboard, text)
        copied = ok
    elseif type(toclipboard) == "function" then
        local ok = pcall(toclipboard, text)
        copied = ok
    end
    L("UI", copied and "LOGS COPIADOS" or "PORTAPAPELES NO DISPONIBLE", copied and GREEN or ORANGE)
end)

-- ────────────────────────────────────────────────────────────────────────────
-- ARRANQUE
-- ────────────────────────────────────────────────────────────────────────────
hookCurrentCharacter(player.Character)

L("SPY", "Carry Swap Spy " .. VERSION .. " listo.", GREEN)
L("SPY", "Acércate a un brainrot y recógelo manualmente.", CYAN)
L("SPY", string.format("Ventana post-respawn: %.0fs | Polling prompts cercanos: activo", POST_SWAP_WINDOW_SECONDS), CYAN)
L("SPY", "─────────────────────────────────────────────────", GRAY)
