--!strict
--------------------------------------------------------------------------------
-- LeaderboardController
-- StarterGui.MainHUD.LeaderboardController (LocalScript)
--
-- Global top-10 window (Richest Players / Most Rebirths) fed by the server's
-- cached OrderedDataStore snapshots via Remotes.GetLeaderboard. Refreshes
-- when opened and every 60s while open.
--------------------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local screenGui = script.Parent :: ScreenGui

local FONT = Enum.Font.FredokaOne
local PANEL_COLOR = Color3.fromRGB(32, 34, 48)
local CARD_COLOR = Color3.fromRGB(46, 49, 70)
local ACCENT = Color3.fromRGB(90, 200, 120)

local MEDALS = { "🥇", "🥈", "🥉" }

local function round(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function abbreviate(n: number): string
	if n >= 1e12 then return string.format("%.2fT", n / 1e12) end
	if n >= 1e9 then return string.format("%.2fB", n / 1e9) end
	if n >= 1e6 then return string.format("%.2fM", n / 1e6) end
	if n >= 1e3 then return string.format("%.1fK", n / 1e3) end
	return tostring(math.floor(n))
end

--------------------------------------------------------------------------------
-- WINDOW
--------------------------------------------------------------------------------
local window = Instance.new("Frame")
window.Name = "LeaderboardWindow"
window.AnchorPoint = Vector2.new(0.5, 0.5)
window.Position = UDim2.fromScale(0.5, 0.5)
window.Size = UDim2.new(0, 460, 0, 440)
window.BackgroundColor3 = PANEL_COLOR
window.Visible = false
window.Parent = screenGui
round(window, 16)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(0.7, 0, 0, 40)
title.Position = UDim2.new(0.15, 0, 0, 8)
title.BackgroundTransparency = 1
title.Font = FONT
title.Text = "LEADERBOARDS"
title.TextColor3 = Color3.new(1, 1, 1)
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

local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, -24, 0, 36)
tabBar.Position = UDim2.new(0, 12, 0, 52)
tabBar.BackgroundTransparency = 1
tabBar.Parent = window

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 8)
tabLayout.Parent = tabBar

local list = Instance.new("ScrollingFrame")
list.Size = UDim2.new(1, -24, 1, -110)
list.Position = UDim2.new(0, 12, 0, 96)
list.CanvasSize = UDim2.new(0, 0, 0, 0)
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.ScrollBarThickness = 6
list.BackgroundTransparency = 1
list.Parent = window

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 5)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = list

local boardCache: any = nil
local activeBoard = GameConfig.Leaderboards.Boards[1].Key
local tabButtons: { [string]: TextButton } = {}

local function renderBoard()
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for key, tab in pairs(tabButtons) do
		tab.BackgroundColor3 = if key == activeBoard then ACCENT else CARD_COLOR
	end

	local board = boardCache and boardCache[activeBoard]
	local entries = board and board.Entries or {}

	if #entries == 0 then
		local empty = Instance.new("Frame")
		empty.Size = UDim2.new(1, -8, 0, 40)
		empty.BackgroundColor3 = CARD_COLOR
		empty.Parent = list
		round(empty, 8)
		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.Font = FONT
		text.Text = "No entries yet — be the first!"
		text.TextColor3 = Color3.fromRGB(180, 185, 205)
		text.TextScaled = true
		text.Parent = empty
		return
	end

	for rank, entry in ipairs(entries) do
		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, -8, 0, 36)
		card.BackgroundColor3 = CARD_COLOR
		card.LayoutOrder = rank
		card.Parent = list
		round(card, 8)

		local rankLabel = Instance.new("TextLabel")
		rankLabel.Size = UDim2.new(0, 50, 1, 0)
		rankLabel.Position = UDim2.new(0, 8, 0, 0)
		rankLabel.BackgroundTransparency = 1
		rankLabel.Font = FONT
		rankLabel.Text = MEDALS[rank] or ("#" .. rank)
		rankLabel.TextColor3 = Color3.new(1, 1, 1)
		rankLabel.TextScaled = true
		rankLabel.TextXAlignment = Enum.TextXAlignment.Left
		rankLabel.Parent = card

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(1, -190, 1, 0)
		nameLabel.Position = UDim2.new(0, 62, 0, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = FONT
		nameLabel.Text = tostring(entry.Name)
		nameLabel.TextColor3 = Color3.new(1, 1, 1)
		nameLabel.TextScaled = true
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Parent = card

		local valueLabel = Instance.new("TextLabel")
		valueLabel.Size = UDim2.new(0, 110, 1, 0)
		valueLabel.Position = UDim2.new(1, -118, 0, 0)
		valueLabel.BackgroundTransparency = 1
		valueLabel.Font = FONT
		valueLabel.Text = abbreviate(tonumber(entry.Value) or 0)
		valueLabel.TextColor3 = Color3.fromRGB(255, 210, 70)
		valueLabel.TextScaled = true
		valueLabel.TextXAlignment = Enum.TextXAlignment.Right
		valueLabel.Parent = card
	end
end

for _, board in ipairs(GameConfig.Leaderboards.Boards) do
	local tab = Instance.new("TextButton")
	tab.Size = UDim2.new(0, 160, 1, 0)
	tab.BackgroundColor3 = CARD_COLOR
	tab.Font = FONT
	tab.Text = board.Title:upper()
	tab.TextColor3 = Color3.new(1, 1, 1)
	tab.TextScaled = true
	tab.Parent = tabBar
	round(tab, 8)
	tabButtons[board.Key] = tab
	tab.MouseButton1Click:Connect(function()
		activeBoard = board.Key
		renderBoard()
	end)
end

local function refresh()
	task.spawn(function()
		local result = Remotes.GetLeaderboard:InvokeServer()
		if type(result) == "table" then
			boardCache = result
			renderBoard()
		end
	end)
end

--------------------------------------------------------------------------------
-- OPEN BUTTON
--------------------------------------------------------------------------------
local openButton = Instance.new("TextButton")
openButton.Size = UDim2.new(0, 110, 0, 44)
openButton.Position = UDim2.new(0, 12, 0, 348)
openButton.BackgroundColor3 = Color3.fromRGB(200, 160, 60)
openButton.Font = FONT
openButton.Text = "TOP 10"
openButton.TextColor3 = Color3.new(1, 1, 1)
openButton.TextScaled = true
openButton.Parent = screenGui
round(openButton, 10)

openButton.MouseButton1Click:Connect(function()
	window.Visible = not window.Visible
	if window.Visible then
		refresh()
	end
end)
closeButton.MouseButton1Click:Connect(function()
	window.Visible = false
end)

task.spawn(function()
	while true do
		task.wait(60)
		if window.Visible then
			refresh()
		end
	end
end)

print("[LeaderboardController] Ready.")
