--!strict
--------------------------------------------------------------------------------
-- CombatController
-- StarterPlayer.StarterPlayerScripts.CombatController (LocalScript)
--
-- Client input half of the CoreEngine loop:
--   * Click / tap a resource node  -> Remotes.NodeHit:FireServer(model)
--   * Click / tap an enemy or boss -> Remotes.CombatSwing:FireServer(model)
--   * Hold to auto-swing at the hovered target on the server cooldown.
--   * Draws floating world-space health bars from the CurrentHealth /
--     MaxHealth attributes CoreEngine stamps on every target model.
--
-- The server re-validates distance and cooldown, so nothing here is trusted.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local localPlayer = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local SWING_INTERVAL = GameConfig.Combat.SwingCooldown
local MAX_HIT_DISTANCE = GameConfig.Combat.MaxHitDistance

local holding = false
local lastLocalSwing = 0

--------------------------------------------------------------------------------
-- TARGET RESOLUTION
--------------------------------------------------------------------------------
-- Walks up from a hit BasePart to the registered target Model (a child of a
-- Zones/ZoneN/{Nodes,Enemies,Boss} folder).
local function resolveTarget(hitPart: BasePart?): (Model?, string?)
	if not hitPart then
		return nil, nil
	end
	local node: Instance? = hitPart
	while node and node ~= Workspace do
		if node:IsA("Model") then
			local parent = node.Parent
			local grandparent = parent and parent.Parent
			if parent and grandparent and grandparent.Parent
				and grandparent.Parent.Name == "Zones" then
				if parent.Name == "Nodes" then
					return node, "Node"
				elseif parent.Name == "Enemies" then
					return node, "Enemy"
				elseif parent.Name == "Boss" then
					return node, "Boss"
				end
			end
		end
		node = node.Parent
	end
	return nil, nil
end

local function targetUnderCursor(): (Model?, string?)
	local mouseLocation = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { localPlayer.Character or Instance.new("Folder") }
	local result = Workspace:Raycast(ray.Origin, ray.Direction * 500, params)
	if result then
		return resolveTarget(result.Instance)
	end
	return nil, nil
end

--------------------------------------------------------------------------------
-- SWINGING
--------------------------------------------------------------------------------
local function trySwing()
	local now = os.clock()
	if now - lastLocalSwing < SWING_INTERVAL then
		return
	end

	local model, kind = targetUnderCursor()
	if not model or not kind then
		return
	end

	-- Client-side pre-check to avoid spamming remotes at unreachable targets.
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local primary = model.PrimaryPart
	if not root or not primary then
		return
	end
	if (root.Position - primary.Position).Magnitude > MAX_HIT_DISTANCE then
		return
	end
	if (model:GetAttribute("CurrentHealth") or 0) <= 0 then
		return
	end

	lastLocalSwing = now
	if kind == "Node" then
		Remotes.NodeHit:FireServer(model)
	else
		Remotes.CombatSwing:FireServer(model)
	end

	-- Local swing feedback: play the character's tool animation if present.
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		local swingAnim = ReplicatedStorage:FindFirstChild("SwingAnimation")
		if animator and swingAnim and swingAnim:IsA("Animation") then
			animator:LoadAnimation(swingAnim):Play()
		end
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		holding = true
		trySwing()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		holding = false
	end
end)

RunService.Heartbeat:Connect(function()
	if holding then
		trySwing()
	end
end)

--------------------------------------------------------------------------------
-- WORLD-SPACE HEALTH BARS
--------------------------------------------------------------------------------
local healthBars: { [Model]: BillboardGui } = {}

local function buildHealthBar(model: Model): BillboardGui
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HealthBar"
	billboard.Size = UDim2.fromScale(6, 0.8)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 120

	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 0.45)
	back.Position = UDim2.fromScale(0, 0.55)
	back.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
	back.BorderSizePixel = 0
	back.Parent = billboard
	local backCorner = Instance.new("UICorner")
	backCorner.CornerRadius = UDim.new(0.5, 0)
	backCorner.Parent = back

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(90, 220, 90)
	fill.BorderSizePixel = 0
	fill.Parent = back
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.5, 0)
	fillCorner.Parent = fill

	local label = Instance.new("TextLabel")
	label.Name = "NameLabel"
	label.Size = UDim2.fromScale(1, 0.5)
	label.BackgroundTransparency = 1
	label.Text = model.Name
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.Parent = billboard

	billboard.Adornee = model.PrimaryPart
	billboard.Parent = model
	return billboard
end

task.spawn(function()
	while true do
		task.wait(0.1)
		local zonesFolder = Workspace:FindFirstChild("Zones")
		if zonesFolder then
			for _, zoneFolder in ipairs(zonesFolder:GetChildren()) do
				for _, groupName in ipairs({ "Nodes", "Enemies", "Boss" }) do
					local group = zoneFolder:FindFirstChild(groupName)
					if group then
						for _, model in ipairs(group:GetChildren()) do
							if model:IsA("Model") and model.PrimaryPart then
								local maxHealth = model:GetAttribute("MaxHealth")
								if maxHealth and maxHealth > 0 then
									local bar = healthBars[model]
									if not bar or not bar.Parent then
										bar = buildHealthBar(model)
										healthBars[model] = bar
									end
									local current = model:GetAttribute("CurrentHealth") or 0
									local ratio = math.clamp(current / maxHealth, 0, 1)
									local back = bar:FindFirstChildOfClass("Frame")
									local fillFrame = back and back:FindFirstChild("Fill")
									if fillFrame then
										(fillFrame :: Frame).Size = UDim2.fromScale(ratio, 1);
										(fillFrame :: Frame).BackgroundColor3 = Color3.fromHSV(0.33 * ratio, 0.8, 0.9)
									end
									bar.Enabled = current > 0
								end
							end
						end
					end
				end
			end
		end
	end
end)

print("[CombatController] Ready.")
