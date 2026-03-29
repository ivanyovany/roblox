if not game:IsLoaded() then
	game.Loaded:Wait()
end

local scriptVersion = "stpatric-v2-test"

print("--- INICIANDO OSAKA " .. scriptVersion .. " (ST PATRIC DEDICADO) ---")

local Players = game:GetService("Players")
local TS = game:GetService("TweenService")
local RS = game:GetService("RunService")

local LP = Players.LocalPlayer

local watchMode = false
local autoPilot = false
local isReturning = false
local isGrabbing = false
local returnLocked = false
local scriptClosed = false
local towerPriorityMode = false
local eventShieldMode = false
local isRespawning = false

local farmSpeed = 700
local firstTripSpeed = 700
local startupStabilizeTime = 0.45
local safeDepth = -6.5
local depositRise = 0.08
local returnAt = 6
local returnApproachDepth = -8.5
local returnSettleDepth = -4.0
local returnHoverDepth = -1.6
local returnGoalTolerance = 1.75
local returnWallOffset = 9
local returnPeekTime = 0.10
local returnDamageThreshold = 10
local depositPeekAttempts = 3
local depositRetryCooldown = 0.75
local depositSettleTime = 0.16
local depositSafeConfirmAttempt = 2
local towerMinLevel = 110
local shieldSinkOffset = -2.35
local shieldDamageThreshold = 6
local shieldRetreatStep = 0.35
local shieldRetreatMax = 3.8
local shieldEmergencyStep = 0.8
local shieldAutoHeal = true
local shieldRecoverStep = 0.08
local shieldRecoverInterval = 0.30
local shieldRecoverDelayAfterHit = 0.80
local shieldExitStabilizeTime = 0.18
local stPatricSubmitCooldown = 0.60
local stPatricLastSubmitAttempt = 0
local stPatricPromptHeightOffset = -24
local stPatricNearFullMargin = 1
local stPatricPostTriggerDelay = 0.12
local stPatricSubmitCheckInterval = 0.06
local stPatricRequiredDrainChecks = 1
local stPatricConfirmedDrainWindow = 1.6
local stPatricUnconfirmedDrainWindow = 1.4
local stPatricRepromptDelay = 0.35
local stPatricHoldSnapDistance = 3.5
local stPatricImmediateRepromptDelay = 0.18
local stPatricConfirmTimeout = 5.2
local stPatricAssumeSubmitDelay = 0.45

local invCount = 0
local basePos = nil
local travelBaseY = nil
local sessionGrabCount = 0

local blacklist = {}
local grabAttempts = 0
local currentTarget = nil

local targetCache = {}
local lastScan = 0
local scanInterval = 0.35
local waveCleanupInterval = 1.0
local nextWaveCleanup = 0
local forceRescan = false
local lastDepositAttempt = 0
local lastBrainrotSpawnLog = 0
local pendingBrainrotSpawnCount = 0
local pendingBrainrotSpawnSample = nil
local brainrotSpawnLogWindow = 1.25
local logEnabled = true
local maxStoredLogs = 250
local storedLogs = {}
local lastScanSummary = ""
local lastSelectionSummary = ""
local lastScanHint = ""
local startupReleaseTime = 0
local firstTripPending = false
local activeRunToken = 0

local flyValue = Instance.new("CFrameValue")

local diedConn = nil
local charAddedConn = nil
local brainrotAddedConn = nil
local steppedConn = nil
local mainLoopThread = nil
local mainButton = nil
local towerButton = nil
local shieldButton = nil
local copyLogsButton = nil
local resetLogsButton = nil
local shieldCFrame = nil
local shieldBaseCFrame = nil
local shieldRetreatOffset = 0
local shieldLastHealth = nil
local shieldLastDamageTime = 0
local shieldLastRecoverTime = 0
local characterPartStateBackup = {}
local collisionModeLabel = "NORMAL"
local baselineToolCounts = {}
local farmToolTrackingReliable = false
local stPatricSubmitPromptCache = nil
local getCharacter
local getHumanoid
local getRoot

local filtros = {
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

local rarityPriority = {
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

local rarityAliases = {
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

local filterOrder = {
	"Infinite",
	"Celestial",
	"Divine",
	"Secret",
	"Cosmic",
	"Mythic",
	"Legendary",
	"Epic",
	"Rare",
	"Uncommon",
	"Common",
}

local function resolveRarityName(name)
	return rarityAliases[name] or name
end

local stPatricKeywords = {
	"st",
	"patric",
	"patrick",
	"saint",
	"clover",
	"rainbow",
	"gold",
	"pot",
	"cauld",
	"olla",
	"submit",
	"deliver",
	"build",
	"brainrot",
	"yes",
}

local function containsKeyword(text)
	if type(text) ~= "string" or text == "" then
		return false, nil
	end

	local lowered = string.lower(text)
	for _, keyword in ipairs(stPatricKeywords) do
		if lowered:find(keyword, 1, true) then
			return true, keyword
		end
	end

	return false, nil
end

local function safeName(instance)
	if not instance then
		return ""
	end

	local name = ""
	pcall(function()
		name = instance.Name
	end)
	return name or ""
end

local function safeText(instance)
	if not instance then
		return ""
	end

	local text = ""
	pcall(function()
		text = instance.Text
	end)
	return text or ""
end

local function safeParent(instance)
	if not instance then
		return nil
	end

	local parent = nil
	pcall(function()
		parent = instance.Parent
	end)
	return parent
end

local function safeIsA(instance, className)
	if not instance then
		return false
	end

	local result = false
	pcall(function()
		result = instance:IsA(className)
	end)
	return result
end

local function safeIsDescendantOf(instance, ancestor)
	if not instance or not ancestor then
		return false
	end

	local result = false
	pcall(function()
		result = instance:IsDescendantOf(ancestor)
	end)
	return result
end

local function safeInstancePath(instance)
	if not instance then
		return "nil"
	end

	local ok, fullName = pcall(function()
		return instance:GetFullName()
	end)
	if ok and fullName and fullName ~= "" then
		return fullName
	end

	return safeName(instance)
end

local function safeGuiVisible(instance)
	if not instance then
		return false
	end

	local current = instance
	while current do
		if safeIsA(current, "ScreenGui") then
			local enabled = true
			pcall(function()
				enabled = current.Enabled
			end)
			if not enabled then
				return false
			end
		elseif safeIsA(current, "GuiObject") then
			local visible = true
			pcall(function()
				visible = current.Visible
			end)
			if not visible then
				return false
			end
		end
		current = safeParent(current)
	end

	return true
end

local function safeGuiArea(instance)
	if not instance or not safeIsA(instance, "GuiObject") then
		return 0
	end

	local area = 0
	pcall(function()
		area = instance.AbsoluteSize.X * instance.AbsoluteSize.Y
	end)
	return area
end

local function getGuiTextMatchScore(text)
	if type(text) ~= "string" or text == "" then
		return 0
	end

	local lowered = string.lower(text)
	if lowered == "yes" or lowered == "yes!" then
		return 14
	end
	if lowered == "confirm" or lowered == "confirm!" then
		return 8
	end
	if lowered == "ok" or lowered == "okay" then
		return 4
	end
	if lowered:find("yes", 1, true) then
		return 10
	end
	if lowered:find("confirm", 1, true) then
		return 6
	end
	return 0
end

local function getStPatricDialogContextScore(root)
	if not root then
		return 0
	end

	local score = 0
	for _, descendant in ipairs(root:GetDescendants()) do
		if safeIsA(descendant, "TextLabel") or safeIsA(descendant, "TextButton") then
			local content = string.lower(safeText(descendant))
			if content:find("submit brainrots", 1, true) then
				score = score + 8
			elseif content:find("build the rainbow", 1, true) then
				score = score + 7
			elseif content:find("brainrot", 1, true) then
				score = score + 4
			elseif content:find("gone forever", 1, true) then
				score = score + 4
			elseif content:find("rainbow", 1, true) or content:find("gold", 1, true) then
				score = score + 3
			end
		end
	end

	return score
end

local scoreYesButton

local function getStPatricYesDebugCandidates(limit)
	local playerGui = LP:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return "sin PlayerGui"
	end

	local candidates = {}
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if safeIsA(descendant, "GuiButton") and scoreYesButton then
			local text = safeText(descendant)
			local name = safeName(descendant)
			local path = safeInstancePath(descendant)
			local visible = safeGuiVisible(descendant)
			local strictScore = scoreYesButton(descendant)
			local looseScore = getGuiTextMatchScore(text)
				+ math.max(0, getGuiTextMatchScore(name) - 2)
				+ math.max(0, getGuiTextMatchScore(path) - 4)

			if strictScore > 0 or looseScore > 0 then
				table.insert(candidates, {
					button = descendant,
					strictScore = strictScore,
					looseScore = looseScore,
					visible = visible,
					area = safeGuiArea(descendant),
					text = text,
					name = name,
					path = path,
				})
			end
		end
	end

	table.sort(candidates, function(a, b)
		if a.strictScore ~= b.strictScore then
			return a.strictScore > b.strictScore
		end
		if a.looseScore ~= b.looseScore then
			return a.looseScore > b.looseScore
		end
		if a.visible ~= b.visible then
			return a.visible
		end
		if a.area ~= b.area then
			return a.area > b.area
		end
		return a.path < b.path
	end)

	if #candidates == 0 then
		return "sin candidatos GuiButton"
	end

	local parts = {}
	for i = 1, math.min(limit or 3, #candidates) do
		local entry = candidates[i]
		table.insert(
			parts,
			string.format(
				"#%d strict=%d loose=%d visible=%s area=%d text=%s name=%s path=%s",
				i,
				entry.strictScore,
				entry.looseScore,
				tostring(entry.visible),
				entry.area,
				tostring(entry.text),
				tostring(entry.name),
				tostring(entry.path)
			)
		)
	end

	return table.concat(parts, " || ")
end

local function getVisibleStPatricDialog()
	local playerGui = LP:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return false, nil, 0
	end

	local bestPath = nil
	local bestScore = 0
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if safeIsA(descendant, "GuiObject") and safeGuiVisible(descendant) then
			local score = getStPatricDialogContextScore(descendant)
			if score > bestScore then
				bestScore = score
				bestPath = safeInstancePath(descendant)
			end
		end
	end

	return bestScore >= 8, bestPath, bestScore
end

local function safePromptData(prompt)
	local data = {
		actionText = "",
		objectText = "",
		enabled = false,
		holdDuration = 0,
		maxActivationDistance = 0,
	}

	if not prompt then
		return data
	end

	pcall(function()
		data.actionText = prompt.ActionText or ""
	end)
	pcall(function()
		data.objectText = prompt.ObjectText or ""
	end)
	pcall(function()
		data.enabled = prompt.Enabled
	end)
	pcall(function()
		data.holdDuration = prompt.HoldDuration or 0
	end)
	pcall(function()
		data.maxActivationDistance = prompt.MaxActivationDistance or 0
	end)

	return data
end

local function updateCopyLogsButtonState()
	if scriptClosed or not copyLogsButton then
		return
	end

	copyLogsButton.Text = "COPIAR LOGS (" .. tostring(#storedLogs) .. ")"
end

local function appendStoredLog(message)
	table.insert(storedLogs, message)
	if #storedLogs > maxStoredLogs then
		table.remove(storedLogs, 1)
	end
	updateCopyLogsButtonState()
end

local function debugLog(eventName, details)
	if not logEnabled then
		return
	end

	local message = string.format("[OSAKA][%.3f][%s]", os.clock(), tostring(eventName))
	if details and details ~= "" then
		message = message .. " " .. tostring(details)
	end

	appendStoredLog(message)
	print(message)
end

debugLog("BOOT", "version=" .. scriptVersion)

local function getStoredLogDump()
	if #storedLogs == 0 then
		return "[OSAKA] no hay logs capturados todavia"
	end

	return table.concat(storedLogs, "\n")
end

local function copyLogsToClipboard(status)
	local payload = getStoredLogDump()
	local copyFns = {setclipboard, toclipboard}
	local copied = false
	local copyError = nil

	for _, copyFn in ipairs(copyFns) do
		if type(copyFn) == "function" then
			local ok, err = pcall(copyFn, payload)
			if ok then
				copied = true
				break
			end
			copyError = err
		end
	end

	if not copied and type(Clipboard) == "table" and type(Clipboard.set) == "function" then
		local ok, err = pcall(function()
			Clipboard.set(payload)
		end)
		copied = ok
		copyError = ok and copyError or err
	end

	if status then
		status.Text = copied and ("LOGS COPIADOS: " .. tostring(#storedLogs)) or "NO SE PUDO COPIAR LOGS"
	end

	debugLog(copied and "LOG_COPY_OK" or "LOG_COPY_FAIL", copied and ("entries=" .. tostring(#storedLogs)) or tostring(copyError or "sin API de clipboard"))
	return copied
end

local function clearStoredLogs(status)
	storedLogs = {}
	lastScanSummary = ""
	lastSelectionSummary = ""
	updateCopyLogsButtonState()
	if status then
		status.Text = "LOGS REINICIADOS"
	end
end

local function copyLogsAndReset(status)
	if copyLogsToClipboard(status) then
		clearStoredLogs(status)
		if status then
			status.Text = "LOGS COPIADOS Y REINICIADOS"
		end
		debugLog("LOG_RESET_OK", "buffer reiniciado tras copia")
		return true
	end
	return false
end

local function debugOnce(eventName, details, key)
	if key ~= nil then
		if key == lastSelectionSummary and eventName == "TARGET_LOCK" then
			return
		end
		if key == lastScanSummary and eventName == "SCAN" then
			return
		end
	end

	if eventName == "TARGET_LOCK" then
		lastSelectionSummary = key or ""
	elseif eventName == "SCAN" then
		lastScanSummary = key or ""
	end

	debugLog(eventName, details)
end

local function invalidateRunToken(reason)
	activeRunToken = activeRunToken + 1
	debugLog("RUN_TOKEN", "invalidate=" .. tostring(activeRunToken) .. " reason=" .. tostring(reason or "n/a"))
	return activeRunToken
end

local function armStartupStabilization(reason)
	startupReleaseTime = os.clock() + startupStabilizeTime
	firstTripPending = true
	debugLog("STABILIZE", (reason or "inicio") .. " hasta=" .. string.format("%.3f", startupReleaseTime))
end

local function isOperationValid(runToken)
	if scriptClosed then
		return false
	end
	if runToken ~= nil and runToken ~= activeRunToken then
		return false
	end
	local humanoid = getHumanoid()
	local root = getRoot()
	if not humanoid or not root then
		return false
	end
	return humanoid.Health > 0
end

function getCharacter()
	return LP.Character or LP.CharacterAdded:Wait()
end

function getHumanoid()
	local character = LP.Character
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

function getRoot()
	local character = LP.Character
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart")
end

local function getOwnedToolCounts()
	local counts = {}
	local backpack = LP:FindFirstChildOfClass("Backpack")
	local character = LP.Character

	local function collect(container)
		if not container then
			return
		end

		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") then
				counts[child.Name] = (counts[child.Name] or 0) + 1
			end
		end
	end

	collect(backpack)
	collect(character)

	return counts
end

local function captureBaselineTools()
	baselineToolCounts = getOwnedToolCounts()
	farmToolTrackingReliable = false
	debugLog("BASELINE", "herramientas base capturadas")
end

local function getFarmToolCount()
	local total = 0
	local currentCounts = getOwnedToolCounts()

	for name, count in pairs(currentCounts) do
		local baselineCount = baselineToolCounts[name] or 0
		if count > baselineCount then
			total = total + (count - baselineCount)
		end
	end

	if total > 0 then
		farmToolTrackingReliable = true
	end

	return total
end

local function getEquippedToolCount()
	local total = 0
	local character = LP.Character
	if not character then
		return 0
	end

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then
			total = total + 1
		end
	end

	return total
end

local function syncInventoryCountFromTools()
	local detectedCount = getFarmToolCount()
	if detectedCount > returnAt then
		farmToolTrackingReliable = false
		debugLog("TOOL_SYNC_SKIP", "detected=" .. tostring(detectedCount) .. " limite=" .. tostring(returnAt))
		if invCount <= 0 then
			returnLocked = false
		end
		return 0
	end
	if detectedCount > 0 then
		invCount = math.max(invCount, detectedCount)
	end
	if invCount <= 0 then
		returnLocked = false
	end
	return detectedCount
end

local function getEffectiveCarryCount()
	return math.max(invCount, syncInventoryCountFromTools())
end

local function forceUnequipFarmTools(humanoid)
	if not humanoid then
		return false
	end

	local beforeCount = getEquippedToolCount()
	if beforeCount <= 0 then
		return true
	end

	debugLog("UNEQUIP", "intentando soltar tools extra=" .. tostring(beforeCount))

	pcall(function()
		humanoid:UnequipTools()
	end)

	local deadline = os.clock() + 0.45
	while os.clock() < deadline do
		if getEquippedToolCount() < beforeCount then
			debugLog("UNEQUIP", "ok")
			return true
		end
		task.wait(0.05)
	end

	local result = getEquippedToolCount() < beforeCount
	debugLog("UNEQUIP", result and "ok tardio" or "sin cambios")
	return result
end

local function getCompactStateLabel()
	if scriptClosed then
		return "CLOSED"
	end
	if eventShieldMode then
		return "SHIELD"
	end
	if isReturning or returnLocked then
		return "RETURN"
	end
	if isGrabbing then
		return "GRAB"
	end
	if autoPilot and currentTarget then
		return "GO"
	end
	if watchMode then
		return "STP"
	end
	return "OFF"
end

local function logHealthState(tag, humanoid, previousHealth)
	if not humanoid then
		debugLog("HEALTH_TRACE", tostring(tag) .. " hp=nil")
		return previousHealth
	end

	local currentHealth = humanoid.Health
	local deltaText = ""
	if type(previousHealth) == "number" then
		deltaText = string.format(" delta=%.2f", currentHealth - previousHealth)
	end
	debugLog("HEALTH_TRACE", string.format("%s hp=%.2f%s", tostring(tag), currentHealth, deltaText))
	return currentHealth
end

local function updateTowerButtonState()
	if scriptClosed or not towerButton then
		return
	end
	towerButton.Text = towerPriorityMode and ("LVL " .. tostring(towerMinLevel) .. "+") or "LVL ANY"
	towerButton.BackgroundColor3 = towerPriorityMode and Color3.fromRGB(210, 145, 55) or Color3.fromRGB(35, 40, 45)
	towerButton.TextColor3 = Color3.new(1, 1, 1)
end

local function updateShieldButtonState()
	if scriptClosed or not shieldButton then
		return
	end
	shieldButton.Text = eventShieldMode and "SHIELD ON" or "SHIELD OFF"
	shieldButton.BackgroundColor3 = eventShieldMode and Color3.fromRGB(70, 130, 200) or Color3.fromRGB(35, 40, 45)
	shieldButton.TextColor3 = Color3.new(1, 1, 1)
end

local function updateButtonState(btn)
	if scriptClosed then
		return
	end
	btn.Text = "STP | " .. getCompactStateLabel() .. " | " .. collisionModeLabel
	btn.BackgroundColor3 = watchMode and Color3.fromRGB(0, 200, 100) or Color3.fromRGB(180, 50, 50)
end

local function resetRunState()
	invCount = 0
	grabAttempts = 0
	currentTarget = nil
	blacklist = {}
	targetCache = {}
	lastScan = 0
	forceRescan = true
	isReturning = false
	isGrabbing = false
	returnLocked = false
end

local function resetSessionProgress()
	sessionGrabCount = 0
	debugLog("SESSION_RESET", "contador reiniciado")
end

local function enforceCharacterNoCollision(character)
	if not character then
		return
	end
	collisionModeLabel = "NO-COLLIDE"

	for _, v in ipairs(character:GetDescendants()) do
		if v:IsA("BasePart") then
			if not characterPartStateBackup[v] then
				characterPartStateBackup[v] = {
					canCollide = v.CanCollide,
					canTouch = v.CanTouch,
				}
			end
			v.CanCollide = false
			v.CanTouch = false
		end
	end
	if mainButton then
		updateButtonState(mainButton)
	end
end

local function restoreCharacterCollisionState()
	collisionModeLabel = "NORMAL"
	for part, state in pairs(characterPartStateBackup) do
		if part and part.Parent then
			part.CanCollide = state.canCollide
			part.CanTouch = state.canTouch
		end
		characterPartStateBackup[part] = nil
	end
	if mainButton then
		updateButtonState(mainButton)
	end
end

local function updateShieldCFrame()
	if shieldBaseCFrame then
		local basePos = shieldBaseCFrame.Position
		local rotation = shieldBaseCFrame - basePos
		shieldCFrame = CFrame.new(basePos + Vector3.new(0, shieldRetreatOffset, 0)) * rotation
	else
		shieldCFrame = nil
	end
end

local function configureShieldHumanoid(humanoid, enabled)
	if not humanoid then
		return
	end

	pcall(function()
		humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, not enabled)
	end)
	pcall(function()
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, not enabled)
	end)
	pcall(function()
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Physics, not enabled)
	end)
	pcall(function()
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, not enabled)
	end)
	pcall(function()
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, not enabled)
	end)

	humanoid.PlatformStand = enabled
end

local function restoreFromShield()
	local character = LP.Character
	local root = getRoot()
	local humanoid = getHumanoid()
	if not root then
		return
	end

	root.Anchored = true
	if shieldBaseCFrame and character then
		pcall(function()
			character:PivotTo(shieldBaseCFrame)
		end)
	else
		root.CFrame = CFrame.new(root.Position + Vector3.new(0, math.abs(shieldSinkOffset), 0))
	end
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero

	if humanoid then
		humanoid.PlatformStand = true
	end

	task.delay(shieldExitStabilizeTime, function()
		if scriptClosed then
			return
		end
		local delayedRoot = getRoot()
		local delayedHumanoid = getHumanoid()
		if delayedRoot then
			delayedRoot.AssemblyLinearVelocity = Vector3.zero
			delayedRoot.AssemblyAngularVelocity = Vector3.zero
			delayedRoot.Anchored = false
		end
		if delayedHumanoid then
			delayedHumanoid.PlatformStand = false
			pcall(function()
				delayedHumanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
			end)
			pcall(function()
				delayedHumanoid:ChangeState(Enum.HumanoidStateType.Running)
			end)
		end
	end)
end

local function setEventShieldMode(enabled, status)
	local root = getRoot()
	local humanoid = getHumanoid()

	eventShieldMode = enabled
	if enabled then
		watchMode = false
		autoPilot = false
		isReturning = false
		isGrabbing = false
		returnLocked = false
		currentTarget = nil
		if root then
			shieldBaseCFrame = root.CFrame
			shieldRetreatOffset = shieldSinkOffset
			shieldLastDamageTime = os.clock()
			shieldLastRecoverTime = 0
			updateShieldCFrame()
			if shieldCFrame and root.Parent then
				pcall(function()
					root.Parent:PivotTo(shieldCFrame)
				end)
			end
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			root.Anchored = true
		end
		if humanoid then
			shieldLastHealth = humanoid.Health
			configureShieldHumanoid(humanoid, true)
		end
		if status then
			status.Text = "SHIELD ACTIVO"
		end
	else
		local previousShieldBase = shieldBaseCFrame
		shieldBaseCFrame = nil
		shieldCFrame = nil
		shieldRetreatOffset = 0
		shieldLastHealth = nil
		shieldLastDamageTime = 0
		shieldLastRecoverTime = 0
		shieldBaseCFrame = previousShieldBase
		restoreFromShield()
		shieldBaseCFrame = nil
		restoreCharacterCollisionState()
		if humanoid then
			configureShieldHumanoid(humanoid, false)
		end
		if status then
			status.Text = "SHIELD OFF"
		end
	end

	if mainButton then
		updateButtonState(mainButton)
	end
	updateShieldButtonState()
end

local function removeFromCache(target)
	for i = #targetCache, 1, -1 do
		if targetCache[i] == target then
			table.remove(targetCache, i)
		end
	end
end

local function getTargetRarity(target)
	local node = target
	while node and node ~= workspace do
		local resolved = resolveRarityName(node.Name)
		if rarityPriority[resolved] then
			return resolved
		end
		node = node.Parent
	end
	return "Common"
end

local function getTargetPriority(target)
	return rarityPriority[getTargetRarity(target)] or 0
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

	for _, attributeName in ipairs({"Level", "Lvl", "level", "lvl"}) do
		local ok, value = pcall(function()
			return target:GetAttribute(attributeName)
		end)
		if ok then
			local parsed = parseLevelValue(value)
			if parsed then
				return parsed
			end
		end
	end

	for _, descendant in ipairs(target:GetDescendants()) do
		local loweredName = string.lower(descendant.Name)
		if loweredName == "level" or loweredName == "lvl" then
			if descendant:IsA("IntValue") or descendant:IsA("NumberValue") then
				return descendant.Value
			elseif descendant:IsA("StringValue") then
				local parsed = parseLevelValue(descendant.Value)
				if parsed then
					return parsed
				end
			end
		end

		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
			local parsed = parseLevelValue(descendant.Text)
			if parsed then
				return parsed
			end
		end
	end

	return 0
end

local function getTowerPriority(target)
	local level = getTargetLevel(target)
	if level >= towerMinLevel then
		return 2, level
	end
	return 1, level
end

local function findPrompt(target)
	if not target then
		return nil
	end

	local prompt = target:FindFirstChildWhichIsA("ProximityPrompt", true)
	if prompt then
		return prompt
	end

	if target.Parent then
		return target.Parent:FindFirstChildWhichIsA("ProximityPrompt", true)
	end

	return nil
end

local function isBrainrotCandidate(target)
	if not target or not target:IsA("Model") then
		return false
	end

	local loweredName = string.lower(target.Name)
	if loweredName == "renderedbrainrot" or loweredName:find("brainrot", 1, true) then
		return true
	end

	local parent = target.Parent
	if parent then
		local loweredParentName = string.lower(parent.Name)
		if loweredParentName == "renderedbrainrot" or loweredParentName:find("brainrot", 1, true) then
			return true
		end
	end

	return false
end

local function getInvalidTargetReason(target)
	if not target then
		return "nil"
	end

	if blacklist[target] then
		return "blacklist"
	end

	if not target:IsDescendantOf(workspace) then
		return "not_in_workspace"
	end

	if not target:IsA("Model") then
		return "not_model"
	end

	if not findPrompt(target) then
		return "no_prompt"
	end

	return nil
end

local function isValidTarget(target)
	return getInvalidTargetReason(target) == nil
end

local function getTargetPosition(target)
	local ok, pivot = pcall(function()
		return target:GetPivot()
	end)

	if ok and pivot then
		return pivot.Position
	end

	if not ok then
		debugLog("TARGET_ERROR", "GetPivot fallo para " .. tostring(target and target:GetFullName() or "nil"))
	end

	return nil
end

local function isPreferredLiveTarget(target)
	if not target or not target:IsDescendantOf(workspace) then
		return false
	end

	local brainrots = workspace:FindFirstChild("ActiveBrainrots")
	if brainrots then
		return target:IsDescendantOf(brainrots)
	end

	return true
end

local function engageAutopilot(reason, status)
	local humanoid = getHumanoid()
	local root = getRoot()
	if not humanoid or not root then
		debugLog("AUTOPILOT_FAIL", "sin humanoid o root")
		return false
	end

	if not autoPilot then
		flyValue.Value = root.CFrame
	end

	autoPilot = true
	humanoid.PlatformStand = true

	if reason then
		status.Text = reason
	end
	debugLog("AUTOPILOT_ON", reason or "sin motivo")
	if mainButton then
		updateButtonState(mainButton)
	end

	return true
end

local function appendTargetIfValid(container, target)
	if not target then
		return
	end

	local invalidReason = getInvalidTargetReason(target)
	if invalidReason then
		return
	end

	for _, existing in ipairs(container) do
		if existing == target then
			return
		end
	end

	table.insert(container, target)
end

local function noteScanReason(reasonCounts, reason)
	if not reason then
		return
	end

	reasonCounts[reason] = (reasonCounts[reason] or 0) + 1
end

local function formatReasonCounts(reasonCounts)
	local orderedReasons = {"no_prompt", "blacklist", "not_in_workspace", "not_model", "nil"}
	local parts = {}
	local seen = {}

	for _, reason in ipairs(orderedReasons) do
		if reasonCounts[reason] then
			table.insert(parts, reason .. "=" .. tostring(reasonCounts[reason]))
			seen[reason] = true
		end
	end

	for reason, count in pairs(reasonCounts) do
		if not seen[reason] then
			table.insert(parts, reason .. "=" .. tostring(count))
		end
	end

	return #parts > 0 and table.concat(parts, ",") or "none"
end

local function getEnabledFiltersSummary()
	local enabled = {}

	for _, rarityName in ipairs(filterOrder) do
		if filtros[rarityName] then
			table.insert(enabled, rarityName)
		end
	end

	return #enabled > 0 and table.concat(enabled, ",") or "none"
end

local function getDisabledRarityHint(disabledWithCandidates)
	local available = {}

	for _, rarityName in ipairs(filterOrder) do
		if disabledWithCandidates[rarityName] then
			table.insert(available, rarityName)
		end
	end

	if #available == 0 then
		return ""
	end

	if #available > 4 then
		return table.concat(available, ",", 1, 4) .. ",..."
	end

	return table.concat(available, ",")
end

local function collectTargetsFromContainer(container, results, scanStats)
	if not container then
		return
	end

	for _, descendant in ipairs(container:GetDescendants()) do
		if isBrainrotCandidate(descendant) then
			if scanStats then
				scanStats.candidates = scanStats.candidates + 1
			end
			local rarityName = getTargetRarity(descendant)
			if filtros[rarityName] then
				local invalidReason = getInvalidTargetReason(descendant)
				if not invalidReason then
					appendTargetIfValid(results, descendant)
				elseif scanStats then
					noteScanReason(scanStats.invalidReasons, invalidReason)
				end
			elseif scanStats then
				scanStats.filteredOut = scanStats.filteredOut + 1
			end
		end
	end
end

local function releaseAutopilot(reason, status)
	local root = getRoot()
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end

	autoPilot = false
	if not eventShieldMode then
		restoreCharacterCollisionState()
	end

	local humanoid = getHumanoid()
	if humanoid then
		humanoid.PlatformStand = false
	end

	if reason then
		status.Text = reason
	end
	debugLog("AUTOPILOT_OFF", reason or "sin motivo")

	if mainButton then
		updateButtonState(mainButton)
	end
end

local function refreshTargets(force)
	local now = os.clock()
	local scanStats = {
		folders = 0,
		candidates = 0,
		filteredOut = 0,
		disabledWithCandidates = {},
		invalidReasons = {},
		usedFallback = false,
	}

	if forceRescan then
		force = true
		forceRescan = false
	end

	if not force and (now - lastScan) < scanInterval then
		return targetCache, #targetCache
	end

	lastScan = now
	targetCache = {}

	local brainrots = workspace:FindFirstChild("ActiveBrainrots")
	if not brainrots then
		scanStats.usedFallback = true
		collectTargetsFromContainer(workspace, targetCache, scanStats)
		if #targetCache > 0 then
			debugLog("SCAN_FALLBACK", "usando workspace completo, targets=" .. tostring(#targetCache))
		end
		debugOnce(
			"SCAN",
			string.format(
				"ActiveBrainrots no existe targets=%d candidates=%d invalid=%s filters=%s",
				#targetCache,
				scanStats.candidates,
				formatReasonCounts(scanStats.invalidReasons),
				getEnabledFiltersSummary()
			),
			"missing:" .. tostring(#targetCache) .. ":" .. formatReasonCounts(scanStats.invalidReasons) .. ":" .. getEnabledFiltersSummary()
		)
		return targetCache, #targetCache
	end

	for _, rarityFolder in ipairs(brainrots:GetChildren()) do
		scanStats.folders = scanStats.folders + 1
		local resolvedFolderName = resolveRarityName(rarityFolder.Name)
		if filtros[resolvedFolderName] then
			for _, descendant in ipairs(rarityFolder:GetDescendants()) do
				if isBrainrotCandidate(descendant) then
					scanStats.candidates = scanStats.candidates + 1
					local invalidReason = getInvalidTargetReason(descendant)
					if not invalidReason then
						table.insert(targetCache, descendant)
					else
						noteScanReason(scanStats.invalidReasons, invalidReason)
					end
				end
			end
		else
			scanStats.filteredOut = scanStats.filteredOut + 1
			if rarityFolder:FindFirstChild("RenderedBrainrot", true) then
				scanStats.disabledWithCandidates[resolvedFolderName] = true
			end
		end
	end

	if #targetCache == 0 then
		scanStats.usedFallback = true
		collectTargetsFromContainer(workspace, targetCache, scanStats)
		if #targetCache > 0 then
			debugLog("SCAN_FALLBACK", "ActiveBrainrots vacio, usando workspace completo targets=" .. tostring(#targetCache))
		end
	end

	table.sort(targetCache, function(a, b)
		if towerPriorityMode then
			local ta, la = getTowerPriority(a)
			local tb, lb = getTowerPriority(b)

			if ta ~= tb then
				return ta > tb
			end

			if la ~= lb then
				return la > lb
			end
		end

		local pa = getTargetPriority(a)
		local pb = getTargetPriority(b)

		if pa ~= pb then
			return pa > pb
		end

		local root = getRoot()
		if not root then
			return false
		end

		local posa = getTargetPosition(a)
		local posb = getTargetPosition(b)
		if not posa then
			return false
		end
		if not posb then
			return true
		end

		return (root.Position - posa).Magnitude < (root.Position - posb).Magnitude
	end)

	local topTarget = targetCache[1]
	if #targetCache == 0 then
		local disabledHint = getDisabledRarityHint(scanStats.disabledWithCandidates)
		if disabledHint ~= "" then
			lastScanHint = "SIN TARGETS. ACTIVA: " .. disabledHint
		else
			lastScanHint = "SIN TARGETS DISPONIBLES"
		end
	else
		lastScanHint = ""
	end
	local summary = table.concat({
		tostring(#targetCache),
		tostring(topTarget and getTargetRarity(topTarget) or "none"),
		tostring(scanStats.candidates),
		formatReasonCounts(scanStats.invalidReasons),
		getEnabledFiltersSummary(),
		tostring(scanStats.usedFallback),
	}, ":")
	debugOnce(
		"SCAN",
		string.format(
			"targets=%d top=%s tower=%s folders=%d candidates=%d filtered=%d invalid=%s fallback=%s filters=%s",
			#targetCache,
			topTarget and getTargetRarity(topTarget) or "none",
			tostring(towerPriorityMode),
			scanStats.folders,
			scanStats.candidates,
			scanStats.filteredOut,
			formatReasonCounts(scanStats.invalidReasons),
			tostring(scanStats.usedFallback),
			getEnabledFiltersSummary()
		),
		summary
	)

	return targetCache, #targetCache
end

local function hasHighPriorityTarget()
	refreshTargets(false)
	for _, target in ipairs(targetCache) do
		local rarityName = getTargetRarity(target)
		if rarityName == "Infinite"
			or rarityName == "Divine"
			or rarityName == "Celestial"
		then
			return true, target
		end
	end
	return false, nil
end

local function getClosestTarget()
	local cache, availableCount = refreshTargets(false)

	if currentTarget and isValidTarget(currentTarget) and isPreferredLiveTarget(currentTarget) then
		local currentPriority = getTargetPriority(currentTarget)
		for _, candidate in ipairs(cache) do
			if candidate ~= currentTarget and isValidTarget(candidate) and isPreferredLiveTarget(candidate) then
				local candidatePriority = getTargetPriority(candidate)
				if candidatePriority > currentPriority then
					currentTarget = candidate
					debugOnce(
						"TARGET_LOCK",
						"upgrade -> " .. getTargetRarity(currentTarget) .. " | " .. currentTarget:GetFullName(),
						currentTarget:GetFullName()
					)
					return currentTarget, availableCount
				end
				break
			end
		end
		return currentTarget, availableCount
	end

	currentTarget = nil
	for _, candidate in ipairs(cache) do
		if isValidTarget(candidate) and isPreferredLiveTarget(candidate) then
			currentTarget = candidate
			break
		end
	end
	if currentTarget then
		debugOnce(
			"TARGET_LOCK",
			"pick -> " .. getTargetRarity(currentTarget) .. " | " .. currentTarget:GetFullName(),
			currentTarget:GetFullName()
		)
	end
	return currentTarget, availableCount
end

local function tweenTo(goal, runToken)
	local startPos = flyValue.Value.Position
	local distance = (startPos - goal.Position).Magnitude
	if distance <= 0.5 then
		flyValue.Value = goal
		return true
	end

	local speed = firstTripPending and firstTripSpeed or farmSpeed
	local duration = math.clamp(distance / speed, 0.05, 3)
	debugLog("TRAVEL_TWEEN", string.format("distance=%.2f speed=%.2f duration=%.2f", distance, speed, duration))
	local tween = TS:Create(flyValue, TweenInfo.new(duration, Enum.EasingStyle.Linear), {Value = goal})
	local finished = false
	local state = nil
	local conn
	conn = tween.Completed:Connect(function(playbackState)
		finished = true
		state = playbackState
	end)
	tween:Play()

	local deadline = os.clock() + duration + 0.4
	while not finished and os.clock() < deadline do
		if runToken ~= nil and not isOperationValid(runToken) then
			pcall(function()
				tween:Cancel()
			end)
			debugLog("TRAVEL_ABORT", "operacion invalidada")
			return false
		end
		task.wait()
	end

	if conn then
		conn:Disconnect()
	end

	if not finished then
		pcall(function()
			tween:Cancel()
		end)
		flyValue.Value = goal
		return false
	end

	return state == Enum.PlaybackState.Completed
		or state == Enum.PlaybackState.Cancelled
		or state == nil
end

local function resolveTravelY(targetPos, forcedY, respectBaseClamp)
	local fallenLimit = workspace.FallenPartsDestroyHeight or -500
	local minSafeY = fallenLimit + 25
	local referenceY = travelBaseY or (basePos and basePos.Y) or targetPos.Y
	local safeY = forcedY or (referenceY + safeDepth)
	safeY = math.max(safeY, minSafeY)

	if respectBaseClamp and travelBaseY then
		safeY = math.max(safeY, travelBaseY - 18)
	elseif respectBaseClamp and basePos then
		safeY = math.max(safeY, basePos.Y - 18)
	end

	return safeY
end

local function ghostTravel(targetPos, forcedY, respectBaseClamp, runToken)
	local root = getRoot()
	if not root then
		debugLog("TRAVEL_FAIL", "sin root para viajar")
		return false
	end

	local safeY = resolveTravelY(targetPos, forcedY, respectBaseClamp ~= false)
	debugLog(
		"TRAVEL_PATH",
		string.format("from=(%.2f, %.2f, %.2f) to=(%.2f, %.2f, %.2f) safeY=%.2f", root.Position.X, root.Position.Y, root.Position.Z, targetPos.X, targetPos.Y, targetPos.Z, safeY)
	)

	debugLog("TRAVEL_STAGE", "pre-rise")
	local startPos = flyValue.Value.Position
	flyValue.Value = CFrame.new(startPos.X, safeY, startPos.Z)
	task.wait(0.03)
	debugLog("TRAVEL_STAGE", "post-rise")
	if runToken ~= nil and not isOperationValid(runToken) then
		debugLog("TRAVEL_ABORT", "invalidada antes de tween")
		return false
	end

	local goal = CFrame.new(targetPos.X, safeY, targetPos.Z)
	debugLog("TRAVEL_STAGE", "pre-tween")
	local reached = tweenTo(goal, runToken)
	debugLog("TRAVEL_STAGE", "post-tween")
	local updatedRoot = getRoot()
	local remainingDistance = updatedRoot and (updatedRoot.Position - goal.Position).Magnitude or -1
	debugLog("TRAVEL_RESULT", string.format("ok=%s remaining=%.2f", tostring(reached), remainingDistance))
	return reached
end

local function ghostReturnTravel(targetPos, runToken)
	local root = getRoot()
	if not root or not basePos then
		return false
	end

	local cruiseY = math.max(basePos.Y + safeDepth, root.Position.Y - 1.5)
	cruiseY = resolveTravelY(targetPos, cruiseY, false)
	return ghostTravel(targetPos, cruiseY, false, runToken)
end

local function emergencyRecover(status)
	local root = getRoot()
	if not root then
		return
	end
	local fallback = basePos and Vector3.new(basePos.X, math.max(basePos.Y - 1, root.Position.Y), basePos.Z)
		or Vector3.new(root.Position.X, root.Position.Y, root.Position.Z)
	ghostTravel(fallback)
	status.Text = "RECUPERANDO RUTA..."
end

local function getGoalDistance(goal)
	local root = getRoot()
	if not root then
		return math.huge
	end
	return (root.Position - goal.Position).Magnitude
end

local function snapCharacterTo(goal)
	local character = LP.Character
	local root = getRoot()
	if not root then
		return false
	end

	flyValue.Value = goal
	pcall(function()
		if character then
			character:PivotTo(goal)
		else
			root.CFrame = goal
		end
	end)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	return true
end

local function approachStPatricPrompt(promptPos, runToken)
	if not promptPos then
		return false
	end

	local root = getRoot()
	if root and (root.Position - promptPos).Magnitude > 10 then
		ghostTravel(promptPos, nil, nil, runToken)
	end

	if runToken ~= nil and not isOperationValid(runToken) then
		debugLog("STP_POT_APPROACH_ABORT", "operacion invalidada antes de ajuste final")
		return false
	end

	local finalY = math.max(resolveTravelY(promptPos, nil, true), promptPos.Y + stPatricPromptHeightOffset)
	local finalGoal = CFrame.new(promptPos.X, finalY, promptPos.Z)
	local reached = tweenTo(finalGoal, runToken)
	if not reached or getGoalDistance(finalGoal) > 4 then
		snapCharacterTo(finalGoal)
	end

	local updatedRoot = getRoot()
	local remaining = updatedRoot and (updatedRoot.Position - finalGoal.Position).Magnitude or -1
	debugLog("STP_POT_APPROACH", string.format("promptY=%.2f finalY=%.2f remaining=%.2f", promptPos.Y, finalY, remaining))
	return true
end

local function descendAfterStPatricSubmit(runToken)
	local root = getRoot()
	if not root then
		return false
	end

	local safeY = resolveTravelY(root.Position, nil, true)
	local descendGoal = CFrame.new(root.Position.X, safeY, root.Position.Z)
	local reached = tweenTo(descendGoal, runToken)
	if not reached or getGoalDistance(descendGoal) > 3 then
		snapCharacterTo(descendGoal)
	end

	debugLog("STP_EXIT_POT", string.format("fromY=%.2f toY=%.2f", root.Position.Y, safeY))
	return true
end

local function finalizeStPatricSubmitSuccess(status, runToken, carryCount, toolsBefore, toolsNow, dialogScore, dialogPath, eventName)
	captureBaselineTools()
	invCount = 0
	grabAttempts = 0
	currentTarget = nil
	blacklist = {}
	returnLocked = false
	isReturning = false
	refreshTargets(true)
	status.Text = "STP: ENTREGA OK"
	debugLog(eventName or "STP_SUBMIT_OK", "carry_before=" .. tostring(carryCount) .. " tools_before=" .. tostring(toolsBefore) .. " tools_now=" .. tostring(toolsNow) .. " dialog_score=" .. tostring(dialogScore) .. " dialog_path=" .. tostring(dialogPath or "none"))
	descendAfterStPatricSubmit(runToken)
	releaseAutopilot("STP: BUSCANDO BRAINROTS...", status)
	return true
end

local function getReturnTunnelY()
	if not basePos then
		return nil
	end
	return basePos.Y + returnApproachDepth
end

local function getReturnWallWaypoint()
	if not basePos then
		return nil
	end

	local root = getRoot()
	if not root then
		return Vector3.new(basePos.X + returnWallOffset, getReturnTunnelY() or basePos.Y, basePos.Z)
	end

	local delta = root.Position - basePos
	local tunnelY = getReturnTunnelY() or basePos.Y
	if math.abs(delta.X) >= math.abs(delta.Z) then
		local direction = delta.X >= 0 and 1 or -1
		return Vector3.new(basePos.X + (direction * returnWallOffset), tunnelY, basePos.Z)
	end

	local direction = delta.Z >= 0 and 1 or -1
	return Vector3.new(basePos.X, tunnelY, basePos.Z + (direction * returnWallOffset))
end

local function moveReturnStage(goal, status, recoveryText, runToken)
	local reached = tweenTo(goal, runToken)
	if reached and getGoalDistance(goal) <= returnGoalTolerance then
		return true
	end

	if recoveryText and status then
		status.Text = recoveryText
		debugLog("RETURN_RECOVER", recoveryText)
	end

	snapCharacterTo(goal)
	task.wait(0.05)
	return getGoalDistance(goal) <= returnGoalTolerance + 1
end

local function moveReturnTunnel(targetPos, status, recoveryText, runToken)
	local tunnelY = getReturnTunnelY()
	if not tunnelY then
		return false
	end

	local reached = ghostTravel(targetPos, tunnelY, false, runToken)
	local goal = CFrame.new(targetPos.X, tunnelY, targetPos.Z)
	if reached and getGoalDistance(goal) <= returnGoalTolerance + 0.5 then
		return true
	end

	if recoveryText and status then
		status.Text = recoveryText
		debugLog("RETURN_RECOVER", recoveryText)
	end

	return moveReturnStage(goal, status, nil, runToken)
end

local function grabItem(target, runToken)
	if runToken ~= nil and not isOperationValid(runToken) then
		debugLog("GRAB_ABORT", "operacion invalidada antes de iniciar")
		return false
	end
	local carryCount = getEffectiveCarryCount()
	if carryCount >= returnAt then
		returnLocked = true
		debugLog("GRAB_ABORT", "limite alcanzado carry=" .. tostring(carryCount) .. "/" .. tostring(returnAt))
		return false
	end
	if not isValidTarget(target) then
		debugLog("GRAB_SKIP", "target invalido")
		return false
	end

	isGrabbing = true
	if mainButton then
		updateButtonState(mainButton)
	end
	local humanoid = getHumanoid()
	local root = getRoot()
	local healthBefore = humanoid and humanoid.Health or 100
	local farmToolsBefore = getFarmToolCount()
	debugLog(
		"GRAB_START",
		string.format(
			"target=%s rarity=%s dist=%.2f inv=%d tools=%d",
			target.Name,
			getTargetRarity(target),
			(root and getTargetPosition(target)) and (root.Position - getTargetPosition(target)).Magnitude or -1,
			invCount,
			farmToolsBefore
		)
	)
	local prompt = findPrompt(target)
	if not prompt then
		debugLog("GRAB_FAIL", "sin prompt")
		isGrabbing = false
		if mainButton then
			updateButtonState(mainButton)
		end
		return false
	end
	local activeBrainrots = workspace:FindFirstChild("ActiveBrainrots")

	local function isClaimConfirmed()
		if target and activeBrainrots and not target:IsDescendantOf(activeBrainrots) then
			return true, "target salio de ActiveBrainrots"
		end
		if prompt and prompt.Parent then
			if target and not prompt:IsDescendantOf(target) then
				return true, "prompt movido fuera del target"
			end
			if activeBrainrots and not prompt:IsDescendantOf(activeBrainrots) then
				return true, "prompt salio de ActiveBrainrots"
			end
		end
		return false, nil
	end

	local triggered = false
	pcall(function()
		prompt.RequiresLineOfSight = false
		prompt.MaxActivationDistance = 100
		prompt.HoldDuration = 0
	end)
	debugLog(
		"GRAB_PROMPT",
		string.format(
			"path=%s action=%s object=%s max=%.1f hold=%.2f enabled=%s",
			prompt:GetFullName(),
			tostring(prompt.ActionText),
			tostring(prompt.ObjectText),
			prompt.MaxActivationDistance,
			prompt.HoldDuration,
			tostring(prompt.Enabled)
		)
	)

	task.wait(0.15)

	for attempt = 1, 4 do
		if runToken ~= nil and not isOperationValid(runToken) then
			debugLog("GRAB_ABORT", "operacion invalidada durante trigger")
			isGrabbing = false
			if mainButton then
				updateButtonState(mainButton)
			end
			return false
		end
		local claimedBeforeFire, claimedBeforeFireReason = isClaimConfirmed()
		if claimedBeforeFire then
			debugLog("GRAB_OK", claimedBeforeFireReason)
			isGrabbing = false
			if mainButton then
				updateButtonState(mainButton)
			end
			return true
		end
		if not isValidTarget(target) then
			debugLog("GRAB_OK", "target desaparecio antes de terminar")
			isGrabbing = false
			if mainButton then
				updateButtonState(mainButton)
			end
			return true
		end

		local fireOk, fireErr = pcall(function()
			fireproximityprompt(prompt)
		end)
		triggered = fireOk or triggered
		if attempt == 1 or not fireOk or fireErr then
			debugLog(
				"GRAB_TRIGGER",
				"prompt=" .. prompt:GetFullName() .. " ok=" .. tostring(fireOk) .. (fireErr and (" err=" .. tostring(fireErr)) or "") .. " attempt=" .. tostring(attempt)
			)
		end

		local claimed, claimedReason = isClaimConfirmed()
		if claimed then
			debugLog("GRAB_OK", claimedReason)
			isGrabbing = false
			if mainButton then
				updateButtonState(mainButton)
			end
			return true
		end

		if humanoid and humanoid.Health > 0 and humanoid.Health < healthBefore - 20 then
			debugLog("GRAB_FAIL", "daño alto durante agarre")
			isGrabbing = false
			if mainButton then
				updateButtonState(mainButton)
			end
			return false
		end

		task.wait(0.08)
	end

	local deadline = os.clock() + 0.75
	while os.clock() < deadline do
		if runToken ~= nil and not isOperationValid(runToken) then
			debugLog("GRAB_ABORT", "operacion invalidada esperando confirmacion")
			isGrabbing = false
			if mainButton then
				updateButtonState(mainButton)
			end
			return false
		end
		local farmToolCount = getFarmToolCount()
		local claimed, claimedReason = isClaimConfirmed()
		if claimed then
			debugLog("GRAB_OK", claimedReason)
			isGrabbing = false
			if mainButton then
				updateButtonState(mainButton)
			end
			return true
		end
		if farmToolCount > farmToolsBefore then
			debugLog("GRAB_OK", "tool detectada nueva=" .. tostring(farmToolCount))
			isGrabbing = false
			if mainButton then
				updateButtonState(mainButton)
			end
			return true
		end
		if not target:IsDescendantOf(workspace) then
			debugLog("GRAB_OK", "target removido de workspace")
			isGrabbing = false
			if mainButton then
				updateButtonState(mainButton)
			end
			return true
		end
		if not findPrompt(target) then
			debugLog("GRAB_OK", "prompt ya no existe")
			isGrabbing = false
			if mainButton then
				updateButtonState(mainButton)
			end
			return true
		end
		task.wait(0.05)
	end

	isGrabbing = false
	if mainButton then
		updateButtonState(mainButton)
	end
	debugLog("GRAB_FAIL", triggered and "trigger sin confirmacion" or "no trigger")
	return false
end

local function stopFarm(reason, btn, status, keepWatching)
	invalidateRunToken(reason or "stopFarm")
	autoPilot = false
	isReturning = false
	isGrabbing = false
	returnLocked = false

	local humanoid = getHumanoid()
	if humanoid then
		humanoid.PlatformStand = false
	end

	if not keepWatching then
		watchMode = false
		resetSessionProgress()
		updateButtonState(btn)
	end

	status.Text = reason or (keepWatching and "VIGILANDO LIBRE..." or "ESTADO: ESPERANDO")
	resetRunState()
	updateButtonState(btn)
end

local function returnToBase(status, reasonText, runToken)
	if runToken ~= nil and not isOperationValid(runToken) then
		debugLog("RETURN_ABORT", "operacion invalidada antes de iniciar")
		return false
	end
	if not basePos then
		debugLog("RETURN_SKIP", "sin basePos")
		return false
	end

	lastDepositAttempt = os.clock()

	isReturning = true
	if mainButton then
		updateButtonState(mainButton)
	end
	if not engageAutopilot(reasonText, status) then
		debugLog("RETURN_FAIL", "no pudo activar autopilot")
		isReturning = false
		if mainButton then
			updateButtonState(mainButton)
		end
		return false
	end

	local returnPos = Vector3.new(basePos.X, basePos.Y, basePos.Z)
	debugLog(
		"RETURN_START",
		string.format("inv=%d tools=%d base=(%.2f, %.2f, %.2f)", invCount, syncInventoryCountFromTools(), basePos.X, basePos.Y, basePos.Z)
	)
	local reached = ghostReturnTravel(returnPos, runToken)
	if not reached then
		debugLog("RETURN_ROUTE", "fallo ruta principal, usando recover")
		if runToken ~= nil and not isOperationValid(runToken) then
			debugLog("RETURN_ABORT", "operacion invalidada tras ruta principal")
			isReturning = false
			return false
		end
		emergencyRecover(status)
		if runToken ~= nil and not isOperationValid(runToken) then
			debugLog("RETURN_ABORT", "operacion invalidada durante recover")
			isReturning = false
			return false
		end
		ghostReturnTravel(returnPos, runToken)
	end
	if runToken ~= nil and not isOperationValid(runToken) then
		debugLog("RETURN_ABORT", "operacion invalidada despues del retorno")
		isReturning = false
		return false
	end

	local root = getRoot()
	local humanoid = getHumanoid()
	if not root or not humanoid then
		debugLog("RETURN_FAIL", "sin root o humanoid al volver")
		isReturning = false
		return false
	end
	local trackedHealth = logHealthState("return_start", humanoid)

	local wallWaypoint = getReturnWallWaypoint()
	local tunnelStage = CFrame.new(basePos.X, basePos.Y + returnApproachDepth, basePos.Z)
	local stageOne = CFrame.new(basePos.X, basePos.Y + returnSettleDepth, basePos.Z)
	local stageTwo = CFrame.new(basePos.X, basePos.Y + returnHoverDepth, basePos.Z)

	if wallWaypoint then
		debugLog("RETURN_STAGE", "wallWaypoint")
		moveReturnTunnel(wallWaypoint, status, "PEGANDOSE A LA PARED...", runToken)
		if runToken ~= nil and not isOperationValid(runToken) then
			debugLog("RETURN_ABORT", "operacion invalidada en wallWaypoint")
			isReturning = false
			return false
		end
		trackedHealth = logHealthState("after_wallWaypoint", humanoid, trackedHealth)
	end

	debugLog("RETURN_STAGE", "tunnelStage")
	moveReturnStage(tunnelStage, status, "ENTRANDO POR ABAJO...", runToken)
	if runToken ~= nil and not isOperationValid(runToken) then
		debugLog("RETURN_ABORT", "operacion invalidada en tunnelStage")
		isReturning = false
		return false
	end
	trackedHealth = logHealthState("after_tunnelStage", humanoid, trackedHealth)
	task.wait(0.08)
	debugLog("RETURN_STAGE", "stageOne")
	moveReturnStage(stageOne, status, "BAJANDO AL RETORNO...", runToken)
	if runToken ~= nil and not isOperationValid(runToken) then
		debugLog("RETURN_ABORT", "operacion invalidada en stageOne")
		isReturning = false
		return false
	end
	trackedHealth = logHealthState("after_stageOne", humanoid, trackedHealth)
	task.wait(0.08)
	debugLog("RETURN_STAGE", "stageTwo")
	moveReturnStage(stageTwo, status, "LLEGANDO A HOME...", runToken)
	if runToken ~= nil and not isOperationValid(runToken) then
		debugLog("RETURN_ABORT", "operacion invalidada en stageTwo")
		isReturning = false
		return false
	end
	trackedHealth = logHealthState("after_stageTwo", humanoid, trackedHealth)
	task.wait(0.08)

	status.Text = "DESCARGANDO EN HOME..."
	local unequipped = forceUnequipFarmTools(humanoid)
	if runToken ~= nil and not isOperationValid(runToken) then
		debugLog("RETURN_ABORT", "operacion invalidada al desequipar")
		isReturning = false
		return false
	end
	trackedHealth = logHealthState("after_unequip", humanoid, trackedHealth)
	task.wait(0.12)
	captureBaselineTools()
	invCount = 0
	sessionGrabCount = 0
	grabAttempts = 0
	currentTarget = nil
	blacklist = {}
	refreshTargets(true)
	returnLocked = false
	status.Text = "HOME OK"
	debugLog("RETURN_OK", "home reached unequip=" .. tostring(unequipped) .. " tools=" .. tostring(getFarmToolCount()))

	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	releaseAutopilot("VIGILANDO LIBRE...", status)
	isReturning = false
	if mainButton then
		updateButtonState(mainButton)
	end
	debugLog("RETURN_END", "returnLocked=" .. tostring(returnLocked) .. " inv=" .. tostring(invCount))
	return true
end

local function getStPatricTargets()
	local results = {}
	local brainrots = workspace:FindFirstChild("ActiveBrainrots")
	local containers = brainrots and {brainrots} or {workspace}

	for _, container in ipairs(containers) do
		for _, descendant in ipairs(container:GetDescendants()) do
			if isBrainrotCandidate(descendant) and isValidTarget(descendant) and isPreferredLiveTarget(descendant) then
				appendTargetIfValid(results, descendant)
			end
		end
	end

	local carryCount = getEffectiveCarryCount()
	local preferClosest = carryCount >= math.max(1, returnAt - stPatricNearFullMargin)

	table.sort(results, function(a, b)
		local root = getRoot()
		if not root then
			local pa = getTargetPriority(a)
			local pb = getTargetPriority(b)
			if pa ~= pb then
				return pa > pb
			end
			return safeInstancePath(a) < safeInstancePath(b)
		end

		local posa = getTargetPosition(a)
		local posb = getTargetPosition(b)
		if not posa then
			return false
		end
		if not posb then
			return true
		end

		if preferClosest then
			local distA = (root.Position - posa).Magnitude
			local distB = (root.Position - posb).Magnitude
			if math.abs(distA - distB) > 12 then
				return distA < distB
			end
		end

		local pa = getTargetPriority(a)
		local pb = getTargetPriority(b)

		if pa ~= pb then
			return pa > pb
		end

		return (root.Position - posa).Magnitude < (root.Position - posb).Magnitude
	end)

	return results
end

local function getStPatricTarget()
	local targets = getStPatricTargets()
	local target = targets[1]
	if target and currentTarget ~= target then
		debugOnce(
			"STP_TARGET",
			"pick -> " .. getTargetRarity(target) .. " | " .. safeInstancePath(target),
			safeInstancePath(target)
		)
	end
	return target, #targets
end

local function getWorldPositionFromInstance(instance)
	if not instance then
		return nil
	end

	if safeIsA(instance, "Attachment") then
		local position = nil
		pcall(function()
			position = instance.WorldPosition
		end)
		return position
	end

	if safeIsA(instance, "BasePart") then
		local position = nil
		pcall(function()
			position = instance.Position
		end)
		return position
	end

	if safeIsA(instance, "Model") then
		local ok, pivot = pcall(function()
			return instance:GetPivot()
		end)
		if ok and pivot then
			return pivot.Position
		end
	end

	local parent = safeParent(instance)
	return parent and parent ~= instance and getWorldPositionFromInstance(parent) or nil
end

local function scoreStPatricPrompt(prompt)
	if not prompt or not safeIsA(prompt, "ProximityPrompt") then
		return 0
	end

	local activeBrainrots = workspace:FindFirstChild("ActiveBrainrots")
	if activeBrainrots and safeIsDescendantOf(prompt, activeBrainrots) then
		return 0
	end

	local promptData = safePromptData(prompt)
	local parent = safeParent(prompt)
	local texts = {
		safeName(prompt),
		safeInstancePath(prompt),
		promptData.actionText,
		promptData.objectText,
		safeName(parent),
		safeInstancePath(parent),
	}
	local score = 0

	for _, text in ipairs(texts) do
		local matched, keyword = containsKeyword(text)
		if matched then
			score = score + 2
			if keyword == "submit" or keyword == "deliver" or keyword == "build" then
				score = score + 4
			elseif keyword == "pot" or keyword == "cauld" or keyword == "gold" or keyword == "rainbow" then
				score = score + 3
			end
		end
	end

	return score
end

local function findStPatricSubmitPrompt()
	if stPatricSubmitPromptCache
		and safeIsA(stPatricSubmitPromptCache, "ProximityPrompt")
		and safeIsDescendantOf(stPatricSubmitPromptCache, workspace)
	then
		local cachedScore = scoreStPatricPrompt(stPatricSubmitPromptCache)
		if cachedScore > 0 then
			debugLog("STP_POT", "prompt=" .. safeInstancePath(stPatricSubmitPromptCache) .. " score=" .. tostring(cachedScore) .. " cached=true")
			return stPatricSubmitPromptCache, cachedScore
		end
	end

	local bestPrompt = nil
	local bestScore = 0

	for _, descendant in ipairs(workspace:GetDescendants()) do
		if safeIsA(descendant, "ProximityPrompt") then
			local score = scoreStPatricPrompt(descendant)
			if score > bestScore then
				bestScore = score
				bestPrompt = descendant
			end
		end
	end

	if bestPrompt then
		stPatricSubmitPromptCache = bestPrompt
		debugLog("STP_POT", "prompt=" .. safeInstancePath(bestPrompt) .. " score=" .. tostring(bestScore))
	else
		stPatricSubmitPromptCache = nil
		debugLog("STP_POT", "sin prompt de olla")
	end

	return bestPrompt, bestScore
end

scoreYesButton = function(button)
	if not button or not safeIsA(button, "GuiButton") then
		return 0
	end

	if not safeGuiVisible(button) then
		return 0
	end

	local score = 0
	local text = safeText(button)
	local name = safeName(button)
	local path = safeInstancePath(button)

	score = score + getGuiTextMatchScore(text)
	score = score + math.max(0, getGuiTextMatchScore(name) - 2)
	score = score + math.max(0, getGuiTextMatchScore(path) - 4)

	if score <= 0 then
		return 0
	end

	if safeGuiArea(button) >= 1200 then
		score = score + 2
	end

	local parent = safeParent(button)
	for _ = 1, 4 do
		if not parent then
			break
		end
		score = score + getStPatricDialogContextScore(parent)
		parent = safeParent(parent)
	end

	if score < 12 then
		return 0
	end

	return score
end

local function scoreFallbackYesButton(button)
	if not button or not safeIsA(button, "GuiButton") then
		return 0
	end

	local text = safeText(button)
	local name = safeName(button)
	local path = string.lower(safeInstancePath(button))
	local score = 0

	score = score + getGuiTextMatchScore(text)
	score = score + math.max(0, getGuiTextMatchScore(name) - 2)
	score = score + math.max(0, getGuiTextMatchScore(path) - 4)

	if path:find("choicegui%.choice%.choices%.yes") then
		score = score + 12
	elseif path:find("choicegui") and path:find("yes") then
		score = score + 8
	end

	if safeGuiArea(button) >= 1200 then
		score = score + 1
	end

	return score
end

local function getRankedStPatricYesButtons(limit)
	local playerGui = LP:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return {}
	end

	local ranked = {}
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if safeIsA(descendant, "GuiButton") then
			local score = scoreYesButton(descendant)
			if score > 0 then
				table.insert(ranked, {
					button = descendant,
					score = score,
					area = safeGuiArea(descendant),
					path = safeInstancePath(descendant),
				})
			end
		end
	end

	table.sort(ranked, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		if a.area ~= b.area then
			return a.area > b.area
		end
		return a.path < b.path
	end)

	if limit and #ranked > limit then
		for i = #ranked, limit + 1, -1 do
			table.remove(ranked, i)
		end
	end

	if #ranked == 0 then
		for _, descendant in ipairs(playerGui:GetDescendants()) do
			if safeIsA(descendant, "GuiButton") then
				local score = scoreFallbackYesButton(descendant)
				if score > 0 then
					table.insert(ranked, {
						button = descendant,
						score = score,
						area = safeGuiArea(descendant),
						path = safeInstancePath(descendant),
					})
				end
			end
		end

		table.sort(ranked, function(a, b)
			if a.score ~= b.score then
				return a.score > b.score
			end
			if a.area ~= b.area then
				return a.area > b.area
			end
			return a.path < b.path
		end)

		if limit and #ranked > limit then
			for i = #ranked, limit + 1, -1 do
				table.remove(ranked, i)
			end
		end
	end

	return ranked
end

local function findStPatricYesButton()
	local ranked = getRankedStPatricYesButtons(1)
	if #ranked == 0 then
		return nil, 0
	end
	return ranked[1].button, ranked[1].score
end

local function activateStPatricYesButton(button)
	if not button then
		return false
	end

	pcall(function()
		button.Active = true
	end)
	pcall(function()
		button.Interactable = true
	end)

	local activated = pcall(function()
		button:Activate()
	end)

	if type(firesignal) == "function" then
		local signalOk = pcall(function()
			firesignal(button.MouseButton1Click)
		end)
		activated = activated or signalOk

		signalOk = pcall(function()
			firesignal(button.Activated, nil, 1)
		end)
		activated = activated or signalOk
	end

	return activated
end

local function confirmStPatricDialog(status)
	local deadline = os.clock() + stPatricConfirmTimeout
	local dialogSeen = false
	while os.clock() < deadline do
		if scriptClosed then
			return false, dialogSeen
		end

		local rankedButtons = getRankedStPatricYesButtons(3)
		local dialogVisible = getVisibleStPatricDialog()
		dialogSeen = dialogSeen or dialogVisible
		for _, entry in ipairs(rankedButtons) do
			local yesButton = entry.button
			local ok = activateStPatricYesButton(yesButton)
			debugLog("STP_CONFIRM", "button=" .. safeInstancePath(yesButton) .. " score=" .. tostring(entry.score) .. " ok=" .. tostring(ok))
			if status then
				status.Text = ok and "STP: CONFIRMANDO..." or "STP: YES DETECTADO"
			end
			if ok then
				return true, dialogSeen
			end
		end

		task.wait(0.05)
	end

	debugLog("STP_CONFIRM_FAIL", "yes button no detectado")
	debugLog("STP_CONFIRM_CANDIDATES", getStPatricYesDebugCandidates(5))
	return false, dialogSeen
end

local function submitStPatricLoad(status, runToken)
	if runToken ~= nil and not isOperationValid(runToken) then
		debugLog("STP_SUBMIT_ABORT", "operacion invalidada antes de entregar")
		return false
	end
	if os.clock() - stPatricLastSubmitAttempt < stPatricSubmitCooldown then
		releaseAutopilot("STP: ESPERANDO OLLA...", status)
		return false
	end

	local carryCount = getEffectiveCarryCount()
	if carryCount <= 0 then
		returnLocked = false
		isReturning = false
		currentTarget = nil
		debugLog("STP_RETURN_CLEAR", "sin carry al intentar entregar")
		return false
	end

	stPatricLastSubmitAttempt = os.clock()
	isReturning = true
	returnLocked = true
	if mainButton then
		updateButtonState(mainButton)
	end

	if not engageAutopilot("STP: LLEVANDO A OLLA...", status) then
		isReturning = false
		return false
	end

	local prompt, promptScore = findStPatricSubmitPrompt()
	if not prompt or promptScore <= 0 then
		releaseAutopilot("STP: OLLA NO ENCONTRADA", status)
		isReturning = false
		return false
	end

	local promptPos = getWorldPositionFromInstance(prompt)
	if promptPos then
		if not approachStPatricPrompt(promptPos, runToken) then
			releaseAutopilot("STP: NO SE PUDO ACERCAR A OLLA", status)
			isReturning = false
			return false
		end
	end

	pcall(function()
		prompt.RequiresLineOfSight = false
		prompt.MaxActivationDistance = 100
		prompt.HoldDuration = 0
	end)

	local toolsBefore = getFarmToolCount()
	local successfulConfirms = 0
	for attempt = 1, 3 do
		if runToken ~= nil and not isOperationValid(runToken) then
			debugLog("STP_SUBMIT_ABORT", "operacion invalidada durante entrega")
			isReturning = false
			return false
		end

		local fireOk, fireErr = pcall(function()
			fireproximityprompt(prompt)
		end)
		debugLog("STP_SUBMIT_TRIGGER", "prompt=" .. safeInstancePath(prompt) .. " ok=" .. tostring(fireOk) .. (fireErr and (" err=" .. tostring(fireErr)) or "") .. " attempt=" .. tostring(attempt))

		task.wait(stPatricPostTriggerDelay)
		local confirmOk, dialogSeen = confirmStPatricDialog(status)
		if confirmOk then
			successfulConfirms = successfulConfirms + 1
		end
		if not confirmOk and not dialogSeen then
			task.wait(stPatricImmediateRepromptDelay)
			local reopenOk, reopenErr = pcall(function()
				fireproximityprompt(prompt)
			end)
			debugLog("STP_SUBMIT_REOPEN", "prompt=" .. safeInstancePath(prompt) .. " ok=" .. tostring(reopenOk) .. (reopenErr and (" err=" .. tostring(reopenErr)) or "") .. " attempt=" .. tostring(attempt))
			task.wait(stPatricPostTriggerDelay)
			local retryConfirmOk, retryDialogSeen = confirmStPatricDialog(status)
			confirmOk = confirmOk or retryConfirmOk
			dialogSeen = dialogSeen or retryDialogSeen
			if retryConfirmOk then
				successfulConfirms = successfulConfirms + 1
			end
		end
		local drainedConfirmations = 0
		local repromptDone = false
		local repromptAt = os.clock() + (confirmOk and 0.25 or stPatricRepromptDelay)
		local assumeSuccessAt = math.huge
		local confirmSuccessAt = confirmOk and (os.clock() + 0.35) or math.huge

		local deadline = os.clock() + (confirmOk and stPatricConfirmedDrainWindow or stPatricUnconfirmedDrainWindow)
		while os.clock() < deadline do
			if runToken ~= nil and not isOperationValid(runToken) then
				debugLog("STP_SUBMIT_ABORT", "operacion invalidada esperando confirmacion de entrega")
				isReturning = false
				return false
			end
			if isRespawning then
				debugLog("STP_SUBMIT_ABORT", "respawn detectado durante confirmacion de entrega")
				isReturning = false
				return false
			end
			if promptPos then
				local holdY = math.max(resolveTravelY(promptPos, nil, true), promptPos.Y + stPatricPromptHeightOffset)
				local holdGoal = CFrame.new(promptPos.X, holdY, promptPos.Z)
				if getGoalDistance(holdGoal) > stPatricHoldSnapDistance then
					snapCharacterTo(holdGoal)
				end
			end
			local toolsNow = getFarmToolCount()
			local carryNow = getEffectiveCarryCount()
			local dialogVisible, dialogPath, dialogScore = getVisibleStPatricDialog()
			local carryDrained = toolsNow < toolsBefore or carryNow <= 0
			local promptData = safePromptData(prompt)
			if confirmOk and not carryDrained and not dialogVisible and not repromptDone and os.clock() >= repromptAt then
				local retryOk, retryErr = pcall(function()
					fireproximityprompt(prompt)
				end)
				debugLog("STP_SUBMIT_RETRY", "prompt=" .. safeInstancePath(prompt) .. " ok=" .. tostring(retryOk) .. (retryErr and (" err=" .. tostring(retryErr)) or ""))
				repromptDone = true
				assumeSuccessAt = os.clock() + stPatricAssumeSubmitDelay
			end
			if carryDrained and not dialogVisible then
				drainedConfirmations = drainedConfirmations + 1
			else
				drainedConfirmations = 0
			end
			if drainedConfirmations >= stPatricRequiredDrainChecks and (confirmOk or dialogSeen or not promptData.enabled) then
				return finalizeStPatricSubmitSuccess(status, runToken, carryCount, toolsBefore, toolsNow, dialogScore, dialogPath, "STP_SUBMIT_OK")
			end
			if confirmOk and (not dialogVisible or successfulConfirms >= 2) and os.clock() >= confirmSuccessAt then
				return finalizeStPatricSubmitSuccess(status, runToken, carryCount, toolsBefore, toolsNow, dialogScore, dialogPath, "STP_SUBMIT_CONFIRM_OK")
			end
			if confirmOk and repromptDone and not dialogVisible and os.clock() >= assumeSuccessAt then
				return finalizeStPatricSubmitSuccess(status, runToken, carryCount, toolsBefore, toolsNow, dialogScore, dialogPath, "STP_SUBMIT_ASSUME_OK")
			end
			task.wait(stPatricSubmitCheckInterval)
		end
	end

	if successfulConfirms >= 2 then
		return finalizeStPatricSubmitSuccess(status, runToken, carryCount, toolsBefore, getFarmToolCount(), 0, "repeat-confirm", "STP_SUBMIT_MULTI_CONFIRM")
	end

	debugLog("STP_SUBMIT_FAIL", "sin confirmacion de entrega")
	if getEffectiveCarryCount() <= 0 then
		return finalizeStPatricSubmitSuccess(status, runToken, carryCount, toolsBefore, getFarmToolCount(), 0, "none", "STP_SUBMIT_FAIL_CLEAR")
	end
	isReturning = false
	releaseAutopilot("STP: ENTREGA FALLIDA", status)
	return false
end

local function bindBrainrotWatcher()
	if brainrotAddedConn then
		brainrotAddedConn:Disconnect()
		brainrotAddedConn = nil
	end

	local brainrots = workspace:FindFirstChild("ActiveBrainrots")
	if not brainrots then
		return
	end

	brainrotAddedConn = brainrots.DescendantAdded:Connect(function(desc)
		if desc.Name == "RenderedBrainrot" and desc:IsA("Model") then
			forceRescan = true
			pendingBrainrotSpawnCount = pendingBrainrotSpawnCount + 1
			pendingBrainrotSpawnSample = pendingBrainrotSpawnSample or desc:GetFullName()

			local now = os.clock()
			if now - lastBrainrotSpawnLog >= brainrotSpawnLogWindow then
				if pendingBrainrotSpawnCount >= 2 then
					debugLog(
						"BRAINROT_SPAWN",
						string.format("batch=%d sample=%s", pendingBrainrotSpawnCount, tostring(pendingBrainrotSpawnSample or desc:GetFullName()))
					)
				end
				lastBrainrotSpawnLog = now
				pendingBrainrotSpawnCount = 0
				pendingBrainrotSpawnSample = nil
			end
		end
	end)
end

local guiParent = pcall(function()
	return gethui()
end) and gethui() or game:GetService("CoreGui")

local oldGui = guiParent:FindFirstChild("OsakaV79Fix")
if oldGui then
	oldGui:Destroy()
end

local sg = Instance.new("ScreenGui")
sg.Name = "OsakaV79Fix"
sg.ResetOnSpawn = false
sg.Parent = guiParent

local frame = Instance.new("Frame", sg)
frame.Size = UDim2.new(0, 172, 0, 38)
frame.Position = UDim2.new(0.05, 0, 0.3, 0)
frame.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
frame.Active = true
frame.Draggable = true
Instance.new("UICorner", frame)

local expanded = false
local filtersExpanded = false

local towerBtn = Instance.new("TextButton", sg)
towerBtn.Size = UDim2.new(0, 84, 0, 24)
towerBtn.Position = UDim2.new(0.05, 0, 0.3, -28)
towerBtn.BackgroundColor3 = Color3.fromRGB(35, 40, 45)
towerBtn.Font = Enum.Font.GothamBold
towerBtn.TextSize = 11
towerBtn.BorderSizePixel = 0
Instance.new("UICorner", towerBtn)
towerBtn.Visible = false
towerButton = towerBtn

local shieldBtn = Instance.new("TextButton", sg)
shieldBtn.Size = UDim2.new(0, 84, 0, 24)
shieldBtn.Position = UDim2.new(0.05, 88, 0.3, -28)
shieldBtn.BackgroundColor3 = Color3.fromRGB(35, 40, 45)
shieldBtn.Font = Enum.Font.GothamBold
shieldBtn.TextSize = 11
shieldBtn.BorderSizePixel = 0
Instance.new("UICorner", shieldBtn)
shieldBtn.Visible = false
shieldButton = shieldBtn

local btn = Instance.new("TextButton", frame)
btn.Size = UDim2.new(1, -74, 0, 32)
btn.Position = UDim2.new(0, 6, 0, 3)
btn.TextColor3 = Color3.new(1, 1, 1)
btn.Font = Enum.Font.GothamBold
btn.TextSize = 13
Instance.new("UICorner", btn)
mainButton = btn

local expandBtn = Instance.new("TextButton", frame)
expandBtn.Size = UDim2.new(0, 30, 0, 32)
expandBtn.Position = UDim2.new(1, -68, 0, 3)
expandBtn.Text = "+"
expandBtn.TextColor3 = Color3.new(1, 1, 1)
expandBtn.BackgroundColor3 = Color3.fromRGB(35, 40, 45)
expandBtn.Font = Enum.Font.GothamBold
expandBtn.TextSize = 18
Instance.new("UICorner", expandBtn)

local closeBtn = Instance.new("TextButton", frame)
closeBtn.Size = UDim2.new(0, 30, 0, 32)
closeBtn.Position = UDim2.new(1, -36, 0, 3)
closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.new(1, 1, 1)
closeBtn.BackgroundColor3 = Color3.fromRGB(120, 45, 45)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 14
Instance.new("UICorner", closeBtn)

local panel = Instance.new("Frame", frame)
panel.Position = UDim2.new(0, 6, 0, 40)
panel.Size = UDim2.new(1, -12, 0, 140)
panel.BackgroundTransparency = 1
panel.Visible = false

local status = Instance.new("TextLabel", panel)
status.Size = UDim2.new(1, 0, 0, 20)
status.Position = UDim2.new(0, 0, 0, 0)
status.Text = "ST PATRIC: ESPERANDO"
status.TextColor3 = Color3.new(1, 1, 1)
status.BackgroundTransparency = 1
status.Font = Enum.Font.Gotham
status.TextSize = 12
status.TextXAlignment = Enum.TextXAlignment.Left

local limitLabel = Instance.new("TextLabel", panel)
limitLabel.Size = UDim2.new(1, 0, 0, 18)
limitLabel.Position = UDim2.new(0, 0, 0, 24)
limitLabel.Text = "LIMITE"
limitLabel.TextColor3 = Color3.new(0.8, 0.8, 0.8)
limitLabel.BackgroundTransparency = 1
limitLabel.Font = Enum.Font.Gotham
limitLabel.TextSize = 11
limitLabel.TextXAlignment = Enum.TextXAlignment.Left

local limitRow = Instance.new("Frame", panel)
limitRow.Size = UDim2.new(1, 0, 0, 28)
limitRow.Position = UDim2.new(0, 0, 0, 46)
limitRow.BackgroundTransparency = 1

local limitMinus = Instance.new("TextButton", limitRow)
limitMinus.Size = UDim2.new(0, 28, 0, 28)
limitMinus.Position = UDim2.new(0, 0, 0, 0)
limitMinus.Text = "-"
limitMinus.TextColor3 = Color3.new(1, 1, 1)
limitMinus.BackgroundColor3 = Color3.fromRGB(35, 40, 45)
limitMinus.Font = Enum.Font.GothamBold
limitMinus.TextSize = 16
Instance.new("UICorner", limitMinus)

local limitValue = Instance.new("TextLabel", limitRow)
limitValue.Size = UDim2.new(1, -64, 0, 28)
limitValue.Position = UDim2.new(0, 32, 0, 0)
limitValue.Text = tostring(returnAt)
limitValue.TextColor3 = Color3.new(1, 1, 1)
limitValue.BackgroundColor3 = Color3.fromRGB(22, 24, 28)
limitValue.Font = Enum.Font.GothamBold
limitValue.TextSize = 13
Instance.new("UICorner", limitValue)

local limitPlus = Instance.new("TextButton", limitRow)
limitPlus.Size = UDim2.new(0, 28, 0, 28)
limitPlus.Position = UDim2.new(1, -28, 0, 0)
limitPlus.Text = "+"
limitPlus.TextColor3 = Color3.new(1, 1, 1)
limitPlus.BackgroundColor3 = Color3.fromRGB(35, 40, 45)
limitPlus.Font = Enum.Font.GothamBold
limitPlus.TextSize = 16
Instance.new("UICorner", limitPlus)

local filtersBtn = Instance.new("TextButton", panel)
filtersBtn.Size = UDim2.new(1, 0, 0, 28)
filtersBtn.Position = UDim2.new(0, 0, 0, 80)
filtersBtn.Text = "FILTROS ▾"
filtersBtn.TextColor3 = Color3.new(1, 1, 1)
filtersBtn.BackgroundColor3 = Color3.fromRGB(35, 40, 45)
filtersBtn.Font = Enum.Font.GothamBold
filtersBtn.TextSize = 12
Instance.new("UICorner", filtersBtn)
filtersBtn.Visible = false

local copyLogsBtn = Instance.new("TextButton", panel)
copyLogsBtn.Size = UDim2.new(0.5, -2, 0, 24)
copyLogsBtn.Position = UDim2.new(0, 0, 0, 114)
copyLogsBtn.TextColor3 = Color3.new(1, 1, 1)
copyLogsBtn.BackgroundColor3 = Color3.fromRGB(65, 90, 140)
copyLogsBtn.Font = Enum.Font.GothamBold
copyLogsBtn.TextSize = 11
copyLogsBtn.BorderSizePixel = 0
Instance.new("UICorner", copyLogsBtn)
copyLogsButton = copyLogsBtn

local resetLogsBtn = Instance.new("TextButton", panel)
resetLogsBtn.Size = UDim2.new(0.5, -2, 0, 24)
resetLogsBtn.Position = UDim2.new(0.5, 2, 0, 114)
resetLogsBtn.Text = "COPIAR + NUEVOS 250"
resetLogsBtn.TextColor3 = Color3.new(1, 1, 1)
resetLogsBtn.BackgroundColor3 = Color3.fromRGB(110, 75, 45)
resetLogsBtn.Font = Enum.Font.GothamBold
resetLogsBtn.TextSize = 11
resetLogsBtn.BorderSizePixel = 0
Instance.new("UICorner", resetLogsBtn)
resetLogsButton = resetLogsBtn

local scroll = Instance.new("ScrollingFrame", frame)
scroll.Size = UDim2.new(1, -12, 0, 146)
scroll.Position = UDim2.new(0, 6, 0, 184)
scroll.BackgroundTransparency = 1
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.ScrollBarThickness = 4
scroll.Visible = false

local listLayout = Instance.new("UIListLayout", scroll)
listLayout.Padding = UDim.new(0, 4)

local function disconnectConnection(conn)
	if conn then
		conn:Disconnect()
	end
	return nil
end

local function shutdownScript()
	if scriptClosed then
		return
	end

	logEnabled = false
	scriptClosed = true
	isRespawning = false
	watchMode = false
	autoPilot = false
	isReturning = false
	isGrabbing = false
	returnLocked = false
	eventShieldMode = false
	forceRescan = false
	currentTarget = nil
	blacklist = {}
	targetCache = {}
	storedLogs = {}
	lastScanSummary = ""
	lastSelectionSummary = ""
	lastScanHint = ""
	startupReleaseTime = 0
	firstTripPending = false
	shieldCFrame = nil
	shieldBaseCFrame = nil
	shieldRetreatOffset = 0
	shieldLastHealth = nil
	shieldLastDamageTime = 0
	shieldLastRecoverTime = 0
	lastBrainrotSpawnLog = 0
	pendingBrainrotSpawnCount = 0
	pendingBrainrotSpawnSample = nil
	activeRunToken = activeRunToken + 1

	local humanoid = getHumanoid()
	local root = getRoot()
	restoreCharacterCollisionState()
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		root.Anchored = false
	end
	if humanoid then
		humanoid.PlatformStand = false
	end

	diedConn = disconnectConnection(diedConn)
	charAddedConn = disconnectConnection(charAddedConn)
	brainrotAddedConn = disconnectConnection(brainrotAddedConn)
	steppedConn = disconnectConnection(steppedConn)

	if mainLoopThread then
		pcall(function()
			task.cancel(mainLoopThread)
		end)
		mainLoopThread = nil
	end

	mainButton = nil
	towerButton = nil
	shieldButton = nil
	copyLogsButton = nil
	resetLogsButton = nil

	if sg then
		sg:Destroy()
		sg = nil
	end
end

local function applyLayout()
	if scriptClosed then
		return
	end
	panel.Visible = expanded
	scroll.Visible = expanded and filtersExpanded
	expandBtn.Text = expanded and "−" or "+"
	filtersBtn.Text = filtersExpanded and "FILTROS ▴" or "FILTROS ▾"

	if not expanded then
		frame.Size = UDim2.new(0, 172, 0, 38)
	elseif filtersExpanded then
		frame.Size = UDim2.new(0, 172, 0, 336)
	else
		frame.Size = UDim2.new(0, 172, 0, 184)
	end

	scroll.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 8)
end

local function updateReturnLimit(delta)
	if scriptClosed then
		return
	end
	limitValue.Text = tostring(returnAt)
end

limitMinus.MouseButton1Click:Connect(function()
	updateReturnLimit(-1)
end)

limitPlus.MouseButton1Click:Connect(function()
	updateReturnLimit(1)
end)

expandBtn.MouseButton1Click:Connect(function()
	if scriptClosed then
		return
	end
	expanded = not expanded
	if not expanded then
		filtersExpanded = false
	end
	applyLayout()
end)

filtersBtn.MouseButton1Click:Connect(function()
	if scriptClosed then
		return
	end
	filtersExpanded = not filtersExpanded
	applyLayout()
end)

closeBtn.MouseButton1Click:Connect(function()
	shutdownScript()
end)

towerBtn.MouseButton1Click:Connect(function()
	if scriptClosed then
		return
	end
	status.Text = "ST PATRIC DEDICADO"
end)

shieldBtn.MouseButton1Click:Connect(function()
	if scriptClosed then
		return
	end
	status.Text = "ST PATRIC DEDICADO"
end)

copyLogsBtn.MouseButton1Click:Connect(function()
	if scriptClosed then
		return
	end
	copyLogsToClipboard(status)
	updateCopyLogsButtonState()
end)

resetLogsBtn.MouseButton1Click:Connect(function()
	if scriptClosed then
		return
	end
	copyLogsAndReset(status)
end)

for _, name in ipairs(filterOrder) do
	local filterButton = Instance.new("TextButton", scroll)
	filterButton.Size = UDim2.new(1, 0, 0, 24)
	filterButton.Text = name
	filterButton.BackgroundColor3 = filtros[name] and Color3.fromRGB(0, 200, 100) or Color3.fromRGB(35, 40, 45)
	filterButton.TextColor3 = Color3.new(0.9, 0.9, 0.9)
	filterButton.Font = Enum.Font.Gotham
	filterButton.TextSize = 12
	Instance.new("UICorner", filterButton)

	filterButton.MouseButton1Click:Connect(function()
		if scriptClosed then
			return
		end
		filtros[name] = not filtros[name]
		filterButton.BackgroundColor3 = filtros[name] and Color3.fromRGB(0, 200, 100) or Color3.fromRGB(35, 40, 45)
		refreshTargets(true)
	end)
	end

listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(applyLayout)
applyLayout()
updateReturnLimit()
updateTowerButtonState()
updateShieldButtonState()
updateCopyLogsButtonState()

steppedConn = RS.Stepped:Connect(function()
	if scriptClosed then
		return
	end

	local now = os.clock()

	if now >= nextWaveCleanup then
		nextWaveCleanup = now + waveCleanupInterval
		for _, v in ipairs(workspace:GetDescendants()) do
			local lowered = string.lower(v.Name)
			if lowered:find("tsunami") or lowered:find("wave") or lowered:find("water") or lowered:find("acid") then
				if v:IsA("BasePart") then
					v.Transparency = 0
					v.LocalTransparencyModifier = 0
					v.CanCollide = false
					v.CanTouch = false
				elseif v:IsA("Decal") or v:IsA("Texture") then
					v.Transparency = 0
				elseif v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Beam") then
					v.Enabled = true
				end
			end
		end
	end

	if not autoPilot and not eventShieldMode then
		restoreCharacterCollisionState()
		return
	end

	local character = LP.Character
	local root = getRoot()
	local humanoid = getHumanoid()
	if not character or not root then
		return
	end

	if eventShieldMode and shieldCFrame then
		if humanoid then
			if shieldLastHealth and humanoid.Health > 0 and humanoid.Health < shieldLastHealth then
				local damageTaken = shieldLastHealth - humanoid.Health
				local retreatAmount = damageTaken >= shieldDamageThreshold and shieldEmergencyStep or shieldRetreatStep
				shieldRetreatOffset = math.max(shieldRetreatOffset - retreatAmount, -shieldRetreatMax)
				shieldLastDamageTime = now
				updateShieldCFrame()
				if shieldAutoHeal then
					pcall(function()
						humanoid.Health = humanoid.MaxHealth
					end)
				end
			elseif now - shieldLastDamageTime >= shieldRecoverDelayAfterHit
				and now - shieldLastRecoverTime >= shieldRecoverInterval
			then
				shieldRetreatOffset = math.min(shieldRetreatOffset + shieldRecoverStep, shieldSinkOffset)
				shieldLastRecoverTime = now
				updateShieldCFrame()
			end
			shieldLastHealth = humanoid.Health
			configureShieldHumanoid(humanoid, true)
		end
		pcall(function()
			character:PivotTo(shieldCFrame)
		end)
	else
		root.CFrame = flyValue.Value
	end
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero

	enforceCharacterNoCollision(character)
end)

local function bindCharacter(btnRef, statusRef)
	if diedConn then
		diedConn:Disconnect()
		diedConn = nil
	end

	local character = getCharacter()
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
	if humanoid then
		diedConn = humanoid.Died:Connect(function()
			if scriptClosed then
				return
			end
			isRespawning = true
			debugLog("DEATH", "personaje murio, watchMode=" .. tostring(watchMode))
			stopFarm("RESPAWN DETECTADO - REARMANDO...", btnRef, statusRef, true)
		end)
	end
end

bindCharacter(btn, status)
bindBrainrotWatcher()

if charAddedConn then
	charAddedConn:Disconnect()
end

charAddedConn = LP.CharacterAdded:Connect(function()
	if scriptClosed then
		return
	end
	debugLog("CHARACTER_ADDED", "nuevo character detectado")
	task.wait(0.75)
	if scriptClosed then
		return
	end
	bindCharacter(btn, status)
	if watchMode then
		local root = getRoot()
		if root then
			invalidateRunToken("characterAdded")
			resetRunState()
			if not basePos then
				basePos = root.Position
			end
			if travelBaseY == nil then
				travelBaseY = root.Position.Y
			end
			flyValue.Value = root.CFrame
			captureBaselineTools()
			armStartupStabilization("respawn")
			isRespawning = false
			releaseAutopilot("STP: BUSCANDO BRAINROTS...", status)
			refreshTargets(true)
		end
	end
end)

btn.MouseButton1Click:Connect(function()
	if scriptClosed then
		return
	end

	local character = getCharacter()
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
		status.Text = "PERSONAJE INVALIDO"
		return
	end

	updateReturnLimit()
	if watchMode and (autoPilot or isReturning or isGrabbing) then
		debugLog(
			"WATCH_OFF_BLOCKED",
			string.format(
				"state=%s autoPilot=%s returning=%s grabbing=%s target=%s",
				getCompactStateLabel(),
				tostring(autoPilot),
				tostring(isReturning),
				tostring(isGrabbing),
				currentTarget and currentTarget:GetFullName() or "nil"
			)
		)
		status.Text = "BLOQUEADO: AUTOFARM EN CURSO"
		updateButtonState(btn)
		return
	end
	watchMode = not watchMode
	updateButtonState(btn)

	if watchMode then
		if eventShieldMode then
			setEventShieldMode(false, status)
		end
		resetSessionProgress()
		invalidateRunToken("watchOn")
		debugLog("STP_ON", string.format("base=(%.2f, %.2f, %.2f)", root.Position.X, root.Position.Y, root.Position.Z))
		basePos = root.Position
		travelBaseY = root.Position.Y
		flyValue.Value = root.CFrame
		root.Anchored = false
		captureBaselineTools()
		armStartupStabilization("watchOn")
		resetRunState()
		bindBrainrotWatcher()
		refreshTargets(true)
		status.Text = "STP: BUSCANDO BRAINROTS..."
		releaseAutopilot("STP: BUSCANDO BRAINROTS...", status)
	else
		invalidateRunToken("watchOff")
		debugLog("STP_OFF", "script en espera")
		releaseAutopilot("ST PATRIC: ESPERANDO", status)
		resetRunState()
	end
end)

mainLoopThread = task.spawn(function()
	while task.wait(0.08) do
		local ok, err = xpcall(function()
			if scriptClosed then
				return "break"
			end

			if eventShieldMode then
				return
			end

			if not watchMode then
				return
			end

			if isRespawning then
				releaseAutopilot("RESPAWN DETECTADO - REARMANDO...", status)
				return
			end

			local runToken = activeRunToken

			if startupReleaseTime > 0 and os.clock() < startupReleaseTime then
				releaseAutopilot("ESTABILIZANDO...", status)
				return
			end

			updateReturnLimit()
			local carryCount = getEffectiveCarryCount()

			if returnLocked and carryCount <= 0 then
				returnLocked = false
				isReturning = false
				currentTarget = nil
				debugLog("STP_RETURN_CLEAR", "carry agotado, liberando retorno")
				releaseAutopilot("STP: BUSCANDO BRAINROTS...", status)
				return
			end

			local humanoid = getHumanoid()
			local root = getRoot()
			if not humanoid or not root or humanoid.Health <= 0 then
				return
			end

			if returnLocked or carryCount >= returnAt then
				returnLocked = true
				if isReturning then
					status.Text = "STP: LLEVANDO A OLLA..."
					return
				end
				debugLog("STP_RETURN", "returnLocked=" .. tostring(returnLocked) .. " inv=" .. tostring(invCount) .. " carry=" .. tostring(carryCount))
				if os.clock() - stPatricLastSubmitAttempt < stPatricSubmitCooldown then
					releaseAutopilot("STP: ESPERANDO OLLA...", status)
					return
				end
				submitStPatricLoad(status, runToken)
				return
			end

			local target, availableCount = getStPatricTarget()
			if not target then
				debugLog("STP_NO_TARGET", "inv=" .. tostring(invCount) .. " returnLocked=" .. tostring(returnLocked))
				if (invCount > 0 or returnLocked) and not isReturning and not isGrabbing then
					returnLocked = invCount > 0 or returnLocked
					submitStPatricLoad(status, runToken)
				else
					currentTarget = nil
					releaseAutopilot("STP: BUSCANDO BRAINROTS...", status)
				end
				return
			end

			local targetPos = getTargetPosition(target)
			if not targetPos then
				debugLog("TARGET_DROP", "sin posicion -> " .. tostring(target and target:GetFullName() or "nil"))
				blacklist[target] = true
				currentTarget = nil
				removeFromCache(target)
				return
			end

			if not engageAutopilot("OBJETIVOS: " .. tostring(availableCount) .. " | " .. tostring(carryCount) .. "/" .. tostring(returnAt), status) then
				return
			end

			local dist = (root.Position - targetPos).Magnitude
			if dist > 8 then
				debugLog("STP_TRAVEL", string.format("target=%s rarity=%s dist=%.2f", target:GetFullName(), getTargetRarity(target), dist))
				status.Text = "VIAJANDO A " .. getTargetRarity(target)
				local reached = ghostTravel(targetPos, nil, nil, runToken)
				if not reached then
					debugLog("TRAVEL_RECOVER", "fallo viaje principal")
					emergencyRecover(status)
					return
				end
			end

			root = getRoot()
			targetPos = getTargetPosition(target)
			local postTravelDistance = math.huge
			if root and targetPos then
				postTravelDistance = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(targetPos.X, 0, targetPos.Z)).Magnitude
			end
			if postTravelDistance > 10 then
				debugLog("GRAB_ABORT", string.format("demasiado lejos tras viaje horizontal=%.2f", postTravelDistance))
				currentTarget = nil
				return
			end

			if not isValidTarget(target) then
				debugLog("TARGET_DROP", "target invalido tras viaje -> " .. tostring(target and target:GetFullName() or "nil"))
				currentTarget = nil
				removeFromCache(target)
				return
			end

			local success = grabItem(target, runToken)
			if success then
				firstTripPending = false
				invCount = invCount + 1
				sessionGrabCount = sessionGrabCount + 1
				local syncedCount = syncInventoryCountFromTools()
				if syncedCount > 0 then
					invCount = math.max(invCount, syncedCount)
				end
				debugLog("STP_GRAB_OK", "inv=" .. tostring(invCount) .. " total=" .. tostring(sessionGrabCount) .. " tools=" .. tostring(getFarmToolCount()))
				if invCount >= returnAt then
					returnLocked = true
				end
				grabAttempts = 0
				blacklist[target] = true
				currentTarget = nil
				removeFromCache(target)
				refreshTargets(true)
				status.Text = "STP: " .. tostring(invCount) .. "/" .. tostring(returnAt)

				if returnLocked or invCount >= returnAt then
					debugLog("STP_TRIGGER", "limite alcanzado")
					submitStPatricLoad(status, runToken)
				else
					task.wait(0.12)
				end
			else
				local carryAfterFail = getEffectiveCarryCount()
				if returnLocked or carryAfterFail >= returnAt then
					returnLocked = true
					grabAttempts = 0
					currentTarget = nil
					debugLog("STP_RETURN", "grab cancelado por limite carry=" .. tostring(carryAfterFail) .. "/" .. tostring(returnAt))
					if not isReturning then
						submitStPatricLoad(status, runToken)
					end
					return
				end

				local currentHumanoid = getHumanoid()
				if currentHumanoid then
					logHealthState("grab_fail", currentHumanoid)
				end
				grabAttempts = grabAttempts + 1
				debugLog("STP_GRAB_FAIL", "fail intento=" .. tostring(grabAttempts))
				status.Text = "STP FAIL " .. tostring(grabAttempts) .. "/3"
				if grabAttempts >= 3 then
					blacklist[target] = true
					currentTarget = nil
					grabAttempts = 0
					removeFromCache(target)
					refreshTargets(true)
					status.Text = "IGNORADO"
					task.wait(0.1)
				end
			end
		end, debug.traceback)

		if not ok then
			debugLog("MAIN_LOOP_ERROR", tostring(err))
			releaseAutopilot("ERROR EN MAIN LOOP", status)
		end

		if ok and err == "break" then
			break
		end
	end
end)
