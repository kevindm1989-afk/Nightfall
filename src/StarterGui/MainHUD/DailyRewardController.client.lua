--!strict
--------------------------------------------------------------------------------
-- DailyRewardController
-- StarterGui.MainHUD.DailyRewardController (LocalScript)
--
-- The 7-day streak calendar UI:
--   * Shows all 7 days with their rewards; past days dimmed, today pulsing.
--   * Claim button invokes Remotes.ClaimDaily and shows the payout.
--   * The open button glows gold whenever a claim is available — the single
--     most effective "come back tomorrow" hook in the HUD.
--------------------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local screenGui = script.Parent :: ScreenGui

local FONT = Enum.Font.FredokaOne
local PANEL_COLOR = Color3.fromRGB(32, 34, 48)
local CARD_COLOR = Color3.fromRGB(46, 49, 70)
local GOLD = Color3.fromRGB(255, 210, 70)

local latestData: any = nil

local function round(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function rewardText(reward: any): string
	local parts = {}
	if reward.Gold then
		table.insert(parts, reward.Gold .. " Gold")
	end
	if reward.Gems then
		table.insert(parts, reward.Gems .. " Gems")
	end
	if reward.EggRoll then
		table.insert(parts, "FREE " .. reward.EggRoll .. "!")
	end
	return table.concat(parts, " + ")
end

--------------------------------------------------------------------------------
-- WINDOW
--------------------------------------------------------------------------------
local window = Instance.new("Frame")
window.Name = "DailyWindow"
window.AnchorPoint = Vector2.new(0.5, 0.5)
window.Position = UDim2.fromScale(0.5, 0.5)
window.Size = UDim2.new(0, 480, 0, 420)
window.BackgroundColor3 = PANEL_COLOR
window.Visible = false
window.Parent = screenGui
round(window, 16)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(0.7, 0, 0, 40)
title.Position = UDim2.new(0.15, 0, 0, 8)
title.BackgroundTransparency = 1
title.Font = FONT
title.Text = "DAILY STREAK"
title.TextColor3 = GOLD
title.TextScaled = true
title.Parent = window

local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.new(0, 36, 0, 36)
closeButton.Position = UDim2.new(1, -44, 0, 8)
closeButton.BackgroundColor3 = Color3.fromRGB(220, 80, 80)
closeButton.Font = FONT
closeButton.Text = "X"
closeButton.TextColor3 = Color3.new(1, 1, 1)
closeButton.TextScaled = true
closeButton.Parent = window
round(closeButton, 10)

local dayCards: { [number]: Frame } = {}
local listFrame = Instance.new("Frame")
listFrame.Size = UDim2.new(1, -24, 1, -130)
listFrame.Position = UDim2.new(0, 12, 0, 56)
listFrame.BackgroundTransparency = 1
listFrame.Parent = window

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 5)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = listFrame

for day = 1, #GameConfig.DailyRewards do
	local card = Instance.new("Frame")
	card.Size = UDim2.new(1, 0, 0, 34)
	card.BackgroundColor3 = CARD_COLOR
	card.LayoutOrder = day
	card.Parent = listFrame
	round(card, 8)

	local dayLabel = Instance.new("TextLabel")
	dayLabel.Size = UDim2.new(0, 80, 1, 0)
	dayLabel.Position = UDim2.new(0, 10, 0, 0)
	dayLabel.BackgroundTransparency = 1
	dayLabel.Font = FONT
	dayLabel.Text = "Day " .. day
	dayLabel.TextColor3 = Color3.new(1, 1, 1)
	dayLabel.TextScaled = true
	dayLabel.TextXAlignment = Enum.TextXAlignment.Left
	dayLabel.Parent = card

	local reward = Instance.new("TextLabel")
	reward.Size = UDim2.new(1, -110, 1, 0)
	reward.Position = UDim2.new(0, 100, 0, 0)
	reward.BackgroundTransparency = 1
	reward.Font = FONT
	reward.Text = rewardText(GameConfig.DailyRewards[day])
	reward.TextColor3 = Color3.fromRGB(180, 185, 205)
	reward.TextScaled = true
	reward.TextXAlignment = Enum.TextXAlignment.Right
	reward.Parent = card

	dayCards[day] = card
end

local claimButton = Instance.new("TextButton")
claimButton.Size = UDim2.new(1, -24, 0, 48)
claimButton.Position = UDim2.new(0, 12, 1, -60)
claimButton.BackgroundColor3 = GOLD
claimButton.Font = FONT
claimButton.Text = "CLAIM"
claimButton.TextColor3 = Color3.fromRGB(40, 30, 0)
claimButton.TextScaled = true
claimButton.Parent = window
round(claimButton, 10)

--------------------------------------------------------------------------------
-- OPEN BUTTON (glows when claimable)
--------------------------------------------------------------------------------
local openButton = Instance.new("TextButton")
openButton.Size = UDim2.new(0, 110, 0, 44)
openButton.Position = UDim2.new(0, 12, 0, 296)
openButton.BackgroundColor3 = CARD_COLOR
openButton.Font = FONT
openButton.Text = "DAILY"
openButton.TextColor3 = Color3.new(1, 1, 1)
openButton.TextScaled = true
openButton.Parent = screenGui
round(openButton, 10)

local function claimable(): boolean
	if not latestData then
		return false
	end
	local last = tonumber(latestData.LastDailyClaim) or 0
	return last == 0 or (os.time() - last) >= GameConfig.DailyRewardCooldown
end

local function refresh()
	local streak = latestData and tonumber(latestData.DailyStreak) or 0
	local nextDay = (streak % #GameConfig.DailyRewards) + 1
	for day, card in pairs(dayCards) do
		if claimable() and day == nextDay then
			card.BackgroundColor3 = Color3.fromRGB(90, 78, 30) -- today: gold tint
		elseif day <= streak then
			card.BackgroundColor3 = Color3.fromRGB(40, 56, 44) -- claimed
		else
			card.BackgroundColor3 = CARD_COLOR
		end
	end
	if claimable() then
		claimButton.Text = "CLAIM DAY " .. nextDay
		claimButton.AutoButtonColor = true
		openButton.BackgroundColor3 = GOLD
		openButton.TextColor3 = Color3.fromRGB(40, 30, 0)
	else
		claimButton.Text = "COME BACK LATER"
		openButton.BackgroundColor3 = CARD_COLOR
		openButton.TextColor3 = Color3.new(1, 1, 1)
	end
end

claimButton.MouseButton1Click:Connect(function()
	claimButton.Active = false
	local success, payload = Remotes.ClaimDaily:InvokeServer()
	claimButton.Active = true
	if success and type(payload) == "table" then
		local pulse = TweenService:Create(claimButton, TweenInfo.new(0.15,
			Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, true),
			{ Size = UDim2.new(1, -12, 0, 54) })
		pulse:Play()
	elseif type(payload) == "string" then
		claimButton.Text = payload
	end
	refresh()
end)

openButton.MouseButton1Click:Connect(function()
	window.Visible = not window.Visible
	refresh()
end)
closeButton.MouseButton1Click:Connect(function()
	window.Visible = false
end)

Remotes.DataChanged.OnClientEvent:Connect(function(data: any)
	if type(data) == "table" then
		latestData = data
		refresh()
	end
end)

task.spawn(function()
	local snapshot = Remotes.GetData:InvokeServer()
	if snapshot then
		latestData = snapshot
		refresh()
	end
end)

-- Keep the glow honest as the cooldown expires while playing.
task.spawn(function()
	while true do
		task.wait(30)
		refresh()
	end
end)

print("[DailyRewardController] Ready.")
