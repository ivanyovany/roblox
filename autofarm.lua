-- ==========================================================
-- SPY SCANNER OPTIMIZADO: GUI ARRASTRABLE + BUFFER CERO LAGg
-- ==========================================================

local CoreGui = game:GetService("CoreGui")
local State = rawget(_G, "__SpyScannerState") or {}
State.logBuffer = State.logBuffer or {}
State.maxLogs = 300
State.isLogging = true
_G.__SpyScannerState = State

-- 1. CONFIGURACIÓN DEL BUFFER (CERO LAG)
local maxLogs = State.maxLogs -- Límite de eventos antes de pausar para no dar lag

local function addLog(titulo, detalles)
    if not State.isLogging or #State.logBuffer >= maxLogs then return end

    local logString = "[" .. os.date("%H:%M:%S") .. "] 🕵️ " .. titulo .. "\n"
    for k, v in pairs(detalles) do
        logString = logString .. "  ↳ " .. tostring(k) .. ": " .. tostring(v) .. "\n"
    end
    logString = logString .. "-----------------------------------\n"

    table.insert(State.logBuffer, logString)

    -- Actualizar contador en la UI
    if State.UpdateLogCount then State.UpdateLogCount(#State.logBuffer) end
end

State.addLog = addLog

-- 2. CREACIÓN DE LA UI MINIMALISTA Y ARRASTRABLE
local guiParent = CoreGui
local hasGuiParent, executorGui = pcall(function()
    return gethui and gethui()
end)
if hasGuiParent and executorGui then
    guiParent = executorGui
end

local existingGui = guiParent:FindFirstChild("SpyScannerGUI") or CoreGui:FindFirstChild("SpyScannerGUI")
if existingGui then
    existingGui:Destroy()
end

local SpyGui = Instance.new("ScreenGui")
SpyGui.Name = "SpyScannerGUI"
SpyGui.Parent = guiParent
State.Gui = SpyGui

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 220, 0, 110)
MainFrame.Position = UDim2.new(0.5, -110, 0.8, 0)
MainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
MainFrame.BorderSizePixel = 2
MainFrame.BorderColor3 = Color3.fromRGB(0, 255, 150)
MainFrame.Active = true
MainFrame.Draggable = true -- Permite moverlo libremente
MainFrame.Parent = SpyGui

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 25)
Title.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
Title.TextColor3 = Color3.fromRGB(0, 255, 150)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 12
Title.Text = "🕵️ SPY SCANNER"
Title.Parent = MainFrame

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, 0, 0, 25)
StatusLabel.Position = UDim2.new(0, 0, 0, 30)
StatusLabel.BackgroundTransparency = 1
StatusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.TextSize = 12
StatusLabel.Text = "Logs capturados: 0/" .. maxLogs
StatusLabel.Parent = MainFrame

local CopyBtn = Instance.new("TextButton")
CopyBtn.Size = UDim2.new(0.45, 0, 0, 30)
CopyBtn.Position = UDim2.new(0.03, 0, 0, 65)
CopyBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
CopyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CopyBtn.Font = Enum.Font.GothamBold
CopyBtn.TextSize = 11
CopyBtn.Text = "📝 COPIAR"
CopyBtn.Parent = MainFrame

local ClearBtn = Instance.new("TextButton")
ClearBtn.Size = UDim2.new(0.45, 0, 0, 30)
ClearBtn.Position = UDim2.new(0.52, 0, 0, 65)
ClearBtn.BackgroundColor3 = Color3.fromRGB(120, 40, 40)
ClearBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ClearBtn.Font = Enum.Font.GothamBold
ClearBtn.TextSize = 11
ClearBtn.Text = "🗑️ LIMPIAR"
ClearBtn.Parent = MainFrame

-- Función para actualizar el texto del contador
State.UpdateLogCount = function(count)
    if count >= maxLogs then
        StatusLabel.Text = "⚠️ LÍMITE ALCANZADO: " .. count
        StatusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
    else
        StatusLabel.Text = "Logs capturados: " .. count .. "/" .. maxLogs
        StatusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    end
end

State.UpdateLogCount(#State.logBuffer)

-- Lógica de Botones
CopyBtn.MouseButton1Click:Connect(function()
    if #State.logBuffer > 0 then
        local fullText = table.concat(State.logBuffer, "\n")
        local success = pcall(function()
            if setclipboard then setclipboard(fullText)
            elseif toclipboard then toclipboard(fullText) end
        end)
        if success then
            CopyBtn.Text = "¡COPIADO!"
            task.wait(1)
            CopyBtn.Text = "📝 COPIAR"
        end
    end
end)

ClearBtn.MouseButton1Click:Connect(function()
    if table.clear then
        table.clear(State.logBuffer)
    else
        State.logBuffer = {}
    end
    State.isLogging = true
    State.UpdateLogCount(0)
    ClearBtn.Text = "¡LIMPIO!"
    task.wait(1)
    ClearBtn.Text = "🗑️ LIMPIAR"
end)

-- 3. HOOKS (LOS ESPÍAS)
if not State.HooksInstalled then
    if fireproximityprompt then
        local old_fire
        old_fire = hookfunction(fireproximityprompt, function(prompt, amount, skip)
            if State.addLog then
                State.addLog("fireproximityprompt", {
                    ["Prompt"] = prompt:GetFullName(),
                    ["ActionText"] = prompt.ActionText,
                })
            end
            return old_fire(prompt, amount, skip)
        end)
    end

    local mt = getrawmetatable(game)
    local old_newindex = mt.__newindex
    setreadonly(mt, false)

    mt.__newindex = newcclosure(function(obj, prop, val)
        if typeof(obj) == "Instance" and obj:IsA("ProximityPrompt") then
            if prop == "HoldDuration" or prop == "MaxActivationDistance" or prop == "RequiresLineOfSight" then
                if State.addLog then
                    State.addLog("Propiedad Alterada", {
                        ["Prompt"] = obj:GetFullName(),
                        ["Propiedad"] = prop,
                        ["Nuevo Valor"] = tostring(val)
                    })
                end
            end
        end
        return old_newindex(obj, prop, val)
    end)
    setreadonly(mt, true)

    State.HooksInstalled = true
end
