--!strict
--------------------------------------------------------------------------------
-- HatchAnimator
-- StarterGui.MainHUD.HatchAnimator (LocalScript)
--
-- Full-screen hatch reveal, queued so auto-hatch spam never overlaps:
--   1. Dim backdrop slides in.
--   2. Egg wobbles with growing violence, then "cracks" (scale punch + flash).
--   3. The pet bursts out: tier-colored glow, name, tier and +damage stat.
--   4. Auto-dismisses (fast for Common, lingers for Mythic) or click to skip.
--
-- Listens to Remotes.PetHatched fired by PetSystem for every hatch source
-- (shop eggs, boss egg drops, Mega Egg Roll, daily streak Royal hatch).
--------------------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local screenGui = script.Parent :: ScreenGui

local tierColors: { [string]: Color3 } = {}
for _, tierInfo in ipairs(GameConfig.PetTiers) do
	tierColors[tierInfo.Tier] = tierInfo.Color
end

local TIER_LINGER: { [string]: number } = {
	Common = 0.9, Uncommon = 1.1, Rare = 1.6, Epic = 2.2, Mythic = 3.2,
}

--------------------------------------------------------------------------------
-- STATIC UI (built once, reused per reveal)
--------------------------------------------------------------------------------
local backdrop = Instance.new("TextButton") -- button so any click skips
backdrop.Name = "HatchBackdrop"
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = Color3.fromRGB(10, 10, 18)
backdrop.BackgroundTransparency = 1
backdrop.Text = ""
backdrop.AutoButtonColor = false
backdrop.Visible = false
backdrop.ZIndex = 50
backdrop.Parent = screenGui

local eggLabel = Instance.new("TextLabel")
eggLabel.AnchorPoint = Vector2.new(0.5, 0.5)
eggLabel.Position = UDim2.fromScale(0.5, 0.45)
eggLabel.Size = UDim2.fromOffset(160, 160)
eggLabel.BackgroundTransparency = 1
eggLabel.Font = Enum.Font.FredokaOne
eggLabel.Text = "🥚"
eggLabel.TextScaled = true
eggLabel.ZIndex = 51
eggLabel.Parent = backdrop

local glow = Instance.new("Frame")
glow.AnchorPoint = Vector2.new(0.5, 0.5)
glow.Position = UDim2.fromScale(0.5, 0.45)
glow.Size = UDim2.fromOffset(0, 0)
glow.BackgroundColor3 = Color3.new(1, 1, 1)
glow.BackgroundTransparency = 0.35
glow.ZIndex = 50
glow.Parent = backdrop
local glowCorner = Instance.new("UICorner")
glowCorner.CornerRadius = UDim.new(1, 0)
glowCorner.Parent = glow

local petIcon = Instance.new("TextLabel")
petIcon.AnchorPoint = Vector2.new(0.5, 0.5)
petIcon.Position = UDim2.fromScale(0.5, 0.42)
petIcon.Size = UDim2.fromOffset(150, 150)
petIcon.BackgroundTransparency = 1
petIcon.Font = Enum.Font.FredokaOne
petIcon.Text = "🐾"
petIcon.TextScaled = true
petIcon.Visible = false
petIcon.ZIndex = 52
petIcon.Parent = backdrop

local nameLabel = Instance.new("TextLabel")
nameLabel.AnchorPoint = Vector2.new(0.5, 0.5)
nameLabel.Position = UDim2.fromScale(0.5, 0.62)
nameLabel.Size = UDim2.new(0.6, 0, 0, 54)
nameLabel.BackgroundTransparency = 1
nameLabel.Font = Enum.Font.FredokaOne
nameLabel.Text = ""
nameLabel.TextScaled = true
nameLabel.TextStrokeTransparency = 0.3
nameLabel.Visible = false
nameLabel.ZIndex = 52
nameLabel.Parent = backdrop

local statLabel = Instance.new("TextLabel")
statLabel.AnchorPoint = Vector2.new(0.5, 0.5)
statLabel.Position = UDim2.fromScale(0.5, 0.70)
statLabel.Size = UDim2.new(0.5, 0, 0, 34)
statLabel.BackgroundTransparency = 1
statLabel.Font = Enum.Font.FredokaOne
statLabel.Text = ""
statLabel.TextColor3 = Color3.fromRGB(220, 225, 240)
statLabel.TextScaled = true
statLabel.Visible = false
statLabel.ZIndex = 52
statLabel.Parent = backdrop

--------------------------------------------------------------------------------
-- REVEAL SEQUENCE
--------------------------------------------------------------------------------
local queue: { any } = {}
local playing = false
local skipRequested = false

backdrop.MouseButton1Click:Connect(function()
	skipRequested = true
end)

local function interruptibleWait(duration: number)
	local deadline = os.clock() + duration
	while os.clock() < deadline and not skipRequested do
		task.wait(0.03)
	end
end

local function playReveal(reveal: any)
	skipRequested = false
	local tier = tostring(reveal.Tier)
	local color = tierColors[tier] or Color3.new(1, 1, 1)

	backdrop.Visible = true
	eggLabel.Visible = true
	eggLabel.Rotation = 0
	eggLabel.Size = UDim2.fromOffset(160, 160)
	petIcon.Visible = false
	nameLabel.Visible = false
	statLabel.Visible = false
	glow.Size = UDim2.fromOffset(0, 0)

	TweenService:Create(backdrop, TweenInfo.new(0.25), { BackgroundTransparency = 0.35 }):Play()

	-- Wobble: 3 escalating shakes (skippable).
	for round = 1, 3 do
		if skipRequested then break end
		local strength = 8 * round
		for _, rotation in ipairs({ -strength, strength, -strength / 2, strength / 2, 0 }) do
			if skipRequested then break end
			local tween = TweenService:Create(eggLabel,
				TweenInfo.new(0.05, Enum.EasingStyle.Quad), { Rotation = rotation })
			tween:Play()
			tween.Completed:Wait()
		end
		interruptibleWait(0.12)
	end

	-- Crack: white flash ring + egg pops away.
	glow.BackgroundColor3 = color
	TweenService:Create(glow, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(420, 420),
		BackgroundTransparency = 1,
	}):Play()
	TweenService:Create(eggLabel, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Size = UDim2.fromOffset(0, 0),
	}):Play()
	task.wait(0.15)
	eggLabel.Visible = false

	-- Pet bursts in.
	petIcon.TextColor3 = color
	petIcon.Size = UDim2.fromOffset(0, 0)
	petIcon.Visible = true
	TweenService:Create(petIcon, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(150, 150),
	}):Play()

	nameLabel.Text = tostring(reveal.PetName)
	nameLabel.TextColor3 = color
	nameLabel.Visible = true
	statLabel.Text = ("%s  •  +%d Damage"):format(tier:upper(), tonumber(reveal.StatBonus) or 0)
	statLabel.Visible = true

	interruptibleWait(TIER_LINGER[tier] or 1.2)

	TweenService:Create(backdrop, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
	task.wait(0.25)
	backdrop.Visible = false
end

task.spawn(function()
	while true do
		if #queue > 0 and not playing then
			playing = true
			local reveal = table.remove(queue, 1)
			local ok, err = pcall(playReveal, reveal)
			if not ok then
				warn("[HatchAnimator] " .. tostring(err))
				backdrop.Visible = false
			end
			playing = false
		else
			task.wait(0.05)
		end
	end
end)

Remotes.PetHatched.OnClientEvent:Connect(function(reveal: any)
	if type(reveal) == "table" and reveal.PetName then
		-- Auto-hatch can outpace the animation; keep the queue shallow so the
		-- player is never watching stale reveals.
		if #queue < 3 then
			table.insert(queue, reveal)
		end
	end
end)

print("[HatchAnimator] Ready.")
