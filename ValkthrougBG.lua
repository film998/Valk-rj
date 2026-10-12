--[[
	VALKTHROUG BG — Background Teleport + Auto Rejoin
	Runs by itself the moment it loads. The only UI is a small always-visible,
	drag-only panel showing that it's working.

	What it does
	  • Origin -> Destination teleport: every time you get within 5 studs of ORIGIN
	    you are moved to DESTINATION (with a short cooldown, so it never loops)
	  • Auto rejoin on kick / disconnect / internet drop (keeps retrying until it works)
	  • Scheduled rejoin every 60 minutes, with a live countdown on the panel

	Run with:  loadstring(game:HttpGet("YOUR_RAW_URL"))()
	To keep everything running after each rejoin, set CONFIG.ScriptUrl to the raw
	link of THIS file (it re-queues itself with queue_on_teleport).
]]

----------------------------------------------------------------------
-- 1. CONFIG
----------------------------------------------------------------------
local CONFIG = {
	-- Teleport route
	Origin = Vector3.new(558.30, 74.76, -315.47),
	Destination = Vector3.new(535.23, 70.57, -350.84),
	TriggerRadius = 5, -- studs
	TeleportCooldown = 1.5, -- seconds between teleports

	-- Auto rejoin
	ScriptUrl = "https://raw.githubusercontent.com/film998/Auto-rj/main/ValkthrougBG.lua", -- raw link to THIS file
	TrySameServerFirst = true, -- first 2 tries go back to the same server, then any server
	RetryDelay = 5, -- seconds before the 2nd attempt
	MaxDelay = 30, -- the delay doubles each try, up to this
	MaxAttempts = 0, -- 0 = keep trying forever
	ScheduledRejoin = true, -- also rejoin on a timer
	ScheduledRejoinMinutes = 60,

	-- UI
	StartPosition = Vector2.new(24, 90),
	UIRefreshInterval = 0.1,
}

----------------------------------------------------------------------
-- 2. SERVICES & GUARDS
----------------------------------------------------------------------
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local GuiService = game:GetService("GuiService")
local CoreGui = game:GetService("CoreGui")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Prevent running twice in one session
local env = (getgenv and getgenv()) or _G
if env.__ValkthrougBGLoaded then
	return
end
env.__ValkthrougBGLoaded = true

local GUI_NAME = "ValkthrougBGGui"
local old = playerGui:FindFirstChild(GUI_NAME)
if old then
	old:Destroy()
end

local function log(...)
	print("[ValkthrougBG]", ...)
end

-- Re-run this script automatically after every rejoin
if CONFIG.ScriptUrl ~= "" then
	local queueFn = queue_on_teleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)
	if queueFn then
		pcall(queueFn, string.format('loadstring(game:HttpGet("%s"))()', CONFIG.ScriptUrl))
	end
end

----------------------------------------------------------------------
-- 3. THEME & HELPERS
----------------------------------------------------------------------
local THEME = {
	Black = Color3.fromRGB(10, 6, 18),
	DeepPurple = Color3.fromRGB(38, 16, 74),
	Purple = Color3.fromRGB(124, 58, 237),
	SoftPurple = Color3.fromRGB(167, 119, 255),
	Gold = Color3.fromRGB(212, 175, 55),
	LightGold = Color3.fromRGB(255, 226, 125),
	White = Color3.fromRGB(255, 255, 255),
	Muted = Color3.fromRGB(176, 166, 200),
	Red = Color3.fromRGB(255, 95, 110),
}

local TI_FAST = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TI_MED = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TI_POP = TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local function tween(inst, info, props)
	local tw = TweenService:Create(inst, info, props)
	tw:Play()
	return tw
end

-- Tiny instance factory (Parent is assigned last for performance)
local function new(className, props, children)
	local inst = Instance.new(className)
	for key, value in pairs(props) do
		if key ~= "Parent" then
			inst[key] = value
		end
	end
	if children then
		for _, child in ipairs(children) do
			child.Parent = inst
		end
	end
	inst.Parent = props.Parent
	return inst
end

local function corner(radius)
	return new("UICorner", { CornerRadius = UDim.new(0, radius) })
end

local function stroke(color, thickness, transparency)
	return new("UIStroke", {
		Color = color,
		Thickness = thickness,
		Transparency = transparency,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

local function colorSeq(...)
	local colors = { ... }
	local points = {}
	for i, c in ipairs(colors) do
		points[i] = ColorSequenceKeypoint.new((i - 1) / (#colors - 1), c)
	end
	return ColorSequence.new(points)
end

local function formatVector(v)
	return string.format("%.2f, %.2f, %.2f", v.X, v.Y, v.Z)
end

----------------------------------------------------------------------
-- 4. BUILD THE UI (drag-only, always visible)
----------------------------------------------------------------------
local WIDTH = 300
local HEADER_H = 36
local BODY_H = 224
local FULL_H = HEADER_H + 1 + BODY_H
local SCALE = UserInputService.TouchEnabled and 0.92 or 1

local gui = new("ScreenGui", {
	Name = GUI_NAME,
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 999,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})

local anchor = new("Frame", {
	Name = "Anchor",
	Size = UDim2.fromOffset(0, 0),
	Position = UDim2.fromOffset(CONFIG.StartPosition.X, CONFIG.StartPosition.Y),
	BackgroundTransparency = 1,
	Parent = gui,
})

local uiScale = new("UIScale", { Scale = 0.6 }) -- pops up to SCALE on start
local strokeGradient = new("UIGradient", { Color = colorSeq(THEME.Gold, THEME.Purple, THEME.Gold) })
local mainStroke = new("UIStroke", {
	Color = THEME.White,
	Thickness = 1.5,
	Transparency = 0.2,
	ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, { strokeGradient })

local main = new("Frame", {
	Name = "Main",
	Size = UDim2.fromOffset(WIDTH, FULL_H),
	BackgroundColor3 = THEME.White, -- tinted by the gradient below
	BackgroundTransparency = 0.08,
	BorderSizePixel = 0,
	Active = true,
	ClipsDescendants = true,
	Parent = anchor,
}, {
	corner(14),
	mainStroke,
	uiScale,
	new("UIGradient", {
		Color = colorSeq(THEME.DeepPurple, THEME.Black, Color3.fromRGB(30, 12, 58)),
		Rotation = 125,
	}),
})

-- Glass sheen on the header
new("Frame", {
	Name = "Sheen",
	Size = UDim2.new(1, 0, 0, HEADER_H),
	BackgroundColor3 = THEME.White,
	BorderSizePixel = 0,
	Parent = main,
}, {
	corner(14),
	new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.86),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}),
})

-- Header: drag handle + title + LIVE pill
local header = new("Frame", {
	Name = "Header",
	Size = UDim2.new(1, 0, 0, HEADER_H),
	BackgroundTransparency = 1,
	Active = true,
	Parent = main,
})

new("Frame", {
	Name = "Diamond",
	Size = UDim2.fromOffset(8, 8),
	Position = UDim2.fromOffset(15, 14),
	Rotation = 45,
	BackgroundColor3 = THEME.Gold,
	BorderSizePixel = 0,
	Parent = header,
})

new("TextLabel", {
	Name = "Title",
	Size = UDim2.new(0, 150, 1, 0),
	Position = UDim2.fromOffset(32, 0),
	BackgroundTransparency = 1,
	Text = "VALKTHROUG",
	Font = Enum.Font.GothamBold,
	TextSize = 14,
	TextColor3 = THEME.White,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = header,
}, {
	new("UIGradient", { Color = colorSeq(THEME.LightGold, THEME.Gold), Rotation = 90 }),
})

local livePill = new("Frame", {
	Name = "Live",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -12, 0.5, 0),
	Size = UDim2.fromOffset(62, 20),
	BackgroundColor3 = THEME.Black,
	BackgroundTransparency = 0.3,
	BorderSizePixel = 0,
	Parent = header,
}, { corner(10), stroke(THEME.Gold, 1, 0.55) })

local liveDot = new("Frame", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 9, 0.5, 0),
	Size = UDim2.fromOffset(8, 8),
	BackgroundColor3 = THEME.Gold,
	BorderSizePixel = 0,
	Parent = livePill,
}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })

new("TextLabel", {
	Position = UDim2.fromOffset(22, 0),
	Size = UDim2.new(1, -26, 1, 0),
	BackgroundTransparency = 1,
	Text = "LIVE",
	Font = Enum.Font.GothamBold,
	TextSize = 10,
	TextColor3 = THEME.LightGold,
	Parent = livePill,
})

-- Divider
new("Frame", {
	Name = "Divider",
	Position = UDim2.new(0, 12, 0, HEADER_H),
	Size = UDim2.new(1, -24, 0, 1),
	BackgroundColor3 = THEME.White,
	BorderSizePixel = 0,
	Parent = main,
}, {
	new("UIGradient", {
		Color = colorSeq(THEME.Gold, THEME.SoftPurple, THEME.Gold),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}),
})

-- Body
local body = new("Frame", {
	Name = "Body",
	Position = UDim2.fromOffset(0, HEADER_H + 1),
	Size = UDim2.fromOffset(WIDTH, BODY_H),
	BackgroundTransparency = 1,
	Parent = main,
}, {
	new("UIPadding", {
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
	}),
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

local function card(order, height)
	return new("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = THEME.Black,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Parent = body,
	}, { corner(10), stroke(THEME.Purple, 1, 0.5) })
end

local function smallLabel(parent, props)
	local base = {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 10,
		TextColor3 = THEME.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = parent,
	}
	for k, v in pairs(props) do
		base[k] = v
	end
	return new("TextLabel", base)
end

-- Card 1: status + teleport counter
local statusCard = card(1, 30)

local statusDot = new("Frame", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 12, 0.5, 0),
	Size = UDim2.fromOffset(8, 8),
	BackgroundColor3 = THEME.Muted,
	BorderSizePixel = 0,
	Parent = statusCard,
}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })

local statusLabel = new("TextLabel", {
	Position = UDim2.fromOffset(26, 0),
	Size = UDim2.new(1, -130, 1, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	TextSize = 12,
	TextColor3 = THEME.White,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Text = "",
	Parent = statusCard,
})

local teleLabel = new("TextLabel", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -10, 0, 0),
	Size = UDim2.new(0, 100, 1, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 11,
	TextColor3 = THEME.LightGold,
	TextXAlignment = Enum.TextXAlignment.Right,
	Text = "Teleports: 0",
	Parent = statusCard,
})

-- Card 2: live position
local posCard = card(2, 46)
smallLabel(posCard, { Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 12), Text = "POSITION" })

local coordRow = new("Frame", {
	Position = UDim2.fromOffset(12, 22),
	Size = UDim2.new(1, -24, 0, 18),
	BackgroundTransparency = 1,
	Parent = posCard,
}, {
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

local function coordLabel(order)
	return new("TextLabel", {
		LayoutOrder = order,
		Size = UDim2.new(1 / 3, -3, 1, 0),
		BackgroundTransparency = 1,
		RichText = true,
		TextScaled = true,
		Font = Enum.Font.Code,
		TextColor3 = THEME.White,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
		Parent = coordRow,
	}, { new("UITextSizeConstraint", { MaxTextSize = 12, MinTextSize = 7 }) })
end
local xLabel, yLabel, zLabel = coordLabel(1), coordLabel(2), coordLabel(3)

-- Card 3: route (origin -> destination)
local routeCard = card(3, 54)
local function routeRow(y, tag, vector)
	smallLabel(routeCard, {
		Position = UDim2.fromOffset(12, y),
		Size = UDim2.fromOffset(52, 16),
		Text = tag,
		TextColor3 = THEME.Gold,
	})
	new("TextLabel", {
		Position = UDim2.fromOffset(64, y),
		Size = UDim2.new(1, -74, 0, 16),
		BackgroundTransparency = 1,
		Font = Enum.Font.Code,
		TextSize = 12,
		TextColor3 = THEME.White,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = formatVector(vector),
		Parent = routeCard,
	})
end
routeRow(8, "ORIGIN", CONFIG.Origin)
routeRow(30, "DEST", CONFIG.Destination)

-- Card 4: rejoin countdown + progress bar
local rejoinCard = card(4, 56)
smallLabel(rejoinCard, { Position = UDim2.fromOffset(12, 10), Size = UDim2.new(0, 120, 0, 14), Text = "NEXT REJOIN IN" })

local timeLabel = new("TextLabel", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 4),
	Size = UDim2.fromOffset(130, 26),
	BackgroundTransparency = 1,
	Font = Enum.Font.Code,
	TextSize = 20,
	TextColor3 = THEME.LightGold,
	TextXAlignment = Enum.TextXAlignment.Right,
	Text = "--:--",
	Parent = rejoinCard,
})

local barTrack = new("Frame", {
	Position = UDim2.fromOffset(12, 38),
	Size = UDim2.new(1, -24, 0, 6),
	BackgroundColor3 = THEME.Black,
	BackgroundTransparency = 0.2,
	BorderSizePixel = 0,
	Parent = rejoinCard,
}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })

local barFill = new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = THEME.White,
	BorderSizePixel = 0,
	Parent = barTrack,
}, {
	new("UICorner", { CornerRadius = UDim.new(1, 0) }),
	new("UIGradient", { Color = colorSeq(THEME.Gold, THEME.Purple) }),
})

----------------------------------------------------------------------
-- 5. STATE
----------------------------------------------------------------------
local rootPart = nil
local isRejoining = false
local teleportCount = 0
local lastTeleport = -math.huge
local statusText, statusLockUntil = nil, 0
local nextRejoinAt = os.time() + CONFIG.ScheduledRejoinMinutes * 60
local totalRejoinSeconds = CONFIG.ScheduledRejoinMinutes * 60
local connections = {} -- global connections we must release on destroy

local function track(conn)
	connections[#connections + 1] = conn
	return conn
end

-- Cached character root (no per-frame lookups)
local function bindCharacter(char)
	rootPart = char:FindFirstChild("HumanoidRootPart") or char:WaitForChild("HumanoidRootPart", 10)
end
local function getRoot()
	if rootPart and rootPart.Parent then
		return rootPart
	end
	return nil
end
track(player.CharacterAdded:Connect(bindCharacter))
track(player.CharacterRemoving:Connect(function()
	rootPart = nil
end))
if player.Character then
	task.spawn(bindCharacter, player.Character)
end

----------------------------------------------------------------------
-- 6. STATUS BAR
----------------------------------------------------------------------
local function renderStatus(text, color)
	if statusText ~= text then
		statusText = text
		statusLabel.Text = text
		tween(statusDot, TI_FAST, { BackgroundColor3 = color })
	end
end

local function flashStatus(text, color, seconds)
	statusLockUntil = os.clock() + (seconds or 2)
	renderStatus(text, color)
end

local function updateBaseStatus()
	if isRejoining then
		renderStatus("Rejoining...", THEME.Red)
	elseif os.clock() < statusLockUntil then
		return
	elseif not getRoot() then
		renderStatus("Waiting for character", THEME.Muted)
	else
		renderStatus("Armed • watching origin", THEME.Gold)
	end
end

----------------------------------------------------------------------
-- 7. AUTO REJOIN
----------------------------------------------------------------------
local function startRejoin(reason)
	if isRejoining then
		return
	end
	isRejoining = true
	log("Rejoining (" .. tostring(reason) .. ")")
	updateBaseStatus()

	task.spawn(function()
		local attempt, delay = 0, CONFIG.RetryDelay

		while CONFIG.MaxAttempts == 0 or attempt < CONFIG.MaxAttempts do
			attempt += 1
			local sameServer = CONFIG.TrySameServerFirst and attempt <= 2 and game.JobId ~= ""

			local ok, err = pcall(function()
				if sameServer then
					TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, player)
				else
					TeleportService:Teleport(game.PlaceId, player)
				end
			end)
			if not ok then
				log("Attempt " .. attempt .. " failed:", err)
			end

			-- If the teleport worked, the client closes. Still here = it failed, try again.
			task.wait(delay)
			delay = math.min(delay * 2, CONFIG.MaxDelay)
		end

		log("Gave up after " .. attempt .. " attempts")
		isRejoining = false
		nextRejoinAt = os.time() + totalRejoinSeconds
	end)
end

track(TeleportService.TeleportInitFailed:Connect(function(_, result, message)
	log("Teleport failed:", tostring(result), tostring(message))
end))

-- Detection 1: the disconnect / kick window
task.spawn(function()
	local ok, overlay = pcall(function()
		return CoreGui:WaitForChild("RobloxPromptGui", 30):WaitForChild("promptOverlay", 30)
	end)
	if not ok or not overlay then
		log("Could not read the error window, using backup detection only")
		return
	end

	track(overlay.ChildAdded:Connect(function(child)
		if child.Name == "ErrorPrompt" then
			startRejoin("error window")
		end
	end))

	if overlay:FindFirstChild("ErrorPrompt") then
		startRejoin("error window")
	end
end)

-- Detection 2 (backup): Roblox's own error message signal
pcall(function()
	track(GuiService.ErrorMessageChanged:Connect(function()
		local message = GuiService:GetErrorMessage()
		if message and message ~= "" then
			startRejoin(message)
		end
	end))
end)

----------------------------------------------------------------------
-- 8. TELEPORT
----------------------------------------------------------------------
local function doTeleport(root)
	lastTeleport = os.clock()
	teleportCount += 1

	root.CFrame = CFrame.new(CONFIG.Destination) * root.CFrame.Rotation -- keep facing direction
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero

	teleLabel.Text = "Teleports: " .. teleportCount
	flashStatus("Teleported!", THEME.LightGold)
end

----------------------------------------------------------------------
-- 9. DRAG (the only interaction), mouse + touch
----------------------------------------------------------------------
local function getVisualSize()
	return Vector2.new(WIDTH * SCALE, FULL_H * SCALE)
end

local function clampToScreen(pos, size)
	local screen = gui.AbsoluteSize
	return Vector2.new(
		math.clamp(pos.X, 0, math.max(0, screen.X - size.X)),
		math.clamp(pos.Y, 0, math.max(0, screen.Y - size.Y))
	)
end

local dragging, dragInput, dragStart, dragOrigin = false, nil, nil, nil
local moveConn, endConn = nil, nil

local function stopDrag()
	dragging = false
	dragInput = nil
	if moveConn then
		moveConn:Disconnect()
		moveConn = nil
	end
	if endConn then
		endConn:Disconnect()
		endConn = nil
	end
end

header.InputBegan:Connect(function(input)
	local kind = input.UserInputType
	if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then
		return
	end
	if dragging then
		return
	end

	dragging = true
	dragInput = input
	dragStart = input.Position
	dragOrigin = Vector2.new(anchor.Position.X.Offset, anchor.Position.Y.Offset)

	endConn = input.Changed:Connect(function()
		if input.UserInputState == Enum.UserInputState.End then
			stopDrag()
		end
	end)

	-- Only connected while a drag is active, so zero idle cost
	moveConn = UserInputService.InputChanged:Connect(function(changed)
		if changed.UserInputType == Enum.UserInputType.MouseMovement or changed == dragInput then
			local delta = changed.Position - dragStart
			local target = clampToScreen(dragOrigin + Vector2.new(delta.X, delta.Y), getVisualSize())
			anchor.Position = UDim2.fromOffset(target.X, target.Y)
		end
	end)
end)

gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	local current = Vector2.new(anchor.Position.X.Offset, anchor.Position.Y.Offset)
	local target = clampToScreen(current, getVisualSize())
	if target ~= current then
		tween(anchor, TI_MED, { Position = UDim2.fromOffset(target.X, target.Y) })
	end
end)

----------------------------------------------------------------------
-- 10. MAIN LOOP
----------------------------------------------------------------------
local cellCache = {}
local function setCell(label, axis, text)
	if cellCache[label] ~= text then
		cellCache[label] = text
		label.Text = string.format('<font color="#D4AF37">%s</font> %s', axis, text)
	end
end

local lastShownSecond = nil
local function refreshCountdown()
	if isRejoining then
		if timeLabel.Text ~= "..." then
			timeLabel.Text = "..."
		end
		return
	end
	if not CONFIG.ScheduledRejoin then
		if timeLabel.Text ~= "OFF" then
			timeLabel.Text = "OFF"
			barFill.Size = UDim2.fromScale(0, 1)
		end
		return
	end

	local remaining = math.max(0, nextRejoinAt - os.time())
	if remaining ~= lastShownSecond then
		lastShownSecond = remaining
		timeLabel.Text = string.format("%02d:%02d", math.floor(remaining / 60), remaining % 60)
		local fraction = totalRejoinSeconds > 0 and (remaining / totalRejoinSeconds) or 0
		tween(barFill, TweenInfo.new(1, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(fraction, 1) })
	end

	if remaining <= 0 then
		nextRejoinAt = os.time() + totalRejoinSeconds
		startRejoin("scheduled rejoin")
	end
end

local function refreshUI(root)
	if root then
		local p = root.Position
		setCell(xLabel, "X", string.format("%.1f", p.X))
		setCell(yLabel, "Y", string.format("%.1f", p.Y))
		setCell(zLabel, "Z", string.format("%.1f", p.Z))
	else
		setCell(xLabel, "X", "–")
		setCell(yLabel, "Y", "–")
		setCell(zLabel, "Z", "–")
	end
	updateBaseStatus()
	refreshCountdown()

	-- Keep the panel always on screen, even if something removes it
	if gui.Parent ~= playerGui then
		pcall(function()
			gui.Parent = playerGui
		end)
	end
end

local accumulator = 0
track(RunService.Heartbeat:Connect(function(dt)
	local root = getRoot()

	-- Teleport check runs every frame (a single distance compare)
	if root and not isRejoining then
		if (root.Position - CONFIG.Origin).Magnitude <= CONFIG.TriggerRadius then
			if os.clock() - lastTeleport >= CONFIG.TeleportCooldown then
				doTeleport(root)
			end
		end
	end

	accumulator += dt
	if accumulator >= CONFIG.UIRefreshInterval then
		accumulator = 0
		refreshUI(root)
	end
end))

----------------------------------------------------------------------
-- 11. START / CLEANUP
----------------------------------------------------------------------
-- Pulsing "LIVE" dot, so you can see at a glance that it's running
local livePulse = tween(liveDot, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
	BackgroundTransparency = 0.75,
})
local borderLoop = tween(strokeGradient, TweenInfo.new(10, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1), {
	Rotation = 360,
})

gui.Destroying:Connect(function()
	for _, conn in ipairs(connections) do
		conn:Disconnect()
	end
	stopDrag()
	livePulse:Cancel()
	borderLoop:Cancel()
	env.__ValkthrougBGLoaded = nil
end)

updateBaseStatus()
refreshCountdown()
gui.Parent = playerGui
tween(uiScale, TI_POP, { Scale = SCALE })
log("Loaded - running in the background")
