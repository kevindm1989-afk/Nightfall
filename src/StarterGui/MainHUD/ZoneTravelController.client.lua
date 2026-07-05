--!strict
--------------------------------------------------------------------------------
-- ZoneTravelController
-- StarterGui.MainHUD.ZoneTravelController (LocalScript)
--
-- The zone map: lists all 4 biomes with their unlock costs.
--   * Locked zone  -> UNLOCK button invokes Remotes.UnlockZone (server checks
--     order + Gold). A "not enough Gold" failure opens the Robux shop tab —
--     the zone walls are the strongest coin-pack conversion points in the game.
--   * Unlocked zone -> TRAVEL button teleports the character to the zone's
--     "ZoneSpawn" part (Workspace/Zones/Zone<N>/ZoneSpawn).
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local localPlayer = Players.LocalPlayer
local screenGui = script.Parent :: ScreenGui

local FONT = Enum.Font.FredokaOne
local PANEL_COLOR = Color3.fromRGB(32, 34, 48)
local CARD_COLOR = Color3.fromRGB(46, 49, 70)
local ACCENT = Color3.fromRGB(90, 200, 120)

local latestData: any = nil

local function round(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function abbreviate(n: number): string
	if n >= 1e9 then return string.format("%.2fB", n / 1e9) end
	if n >= 1e6 then return string.format("%.2fM", n / 1e6) end
	if n >= 1e3 then return string.format("%.1fK", n / 1e3) end
	return tostring(math.floor(n))
end

--------------------------------------------------------------------------------
-- WINDOW
--------------------------------------------------------------------------------
local window = Instance.new("Frame")
window.Name = "ZoneWindow"
window.AnchorPoint = Vector2.new(0.5, 0.5)
window.Position = UDim2.fromScale(0.5, 0.5)
window.Size = UDim2.new(0, 500, 0, 360)
window.BackgroundColor3 = PANEL_COLOR
window.Visible = false
window.Parent = screenGui
round(window, 16)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(0.7, 0, 0, 40)
title.Position = UDim2.new(0.15, 0, 0, 8)
title.BackgroundTransparency = 1
title.Font = FONT
title.Text = "WORLD MAP"
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

local list = Instance.new("Frame")
list.Size = UDim2.new(1, -24, 1, -64)
list.Position = UDim2.new(0, 12, 0, 52)
list.BackgroundTransparency = 1
list.Parent = window

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 8)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = list

--------------------------------------------------------------------------------
-- ZONE CARDS
--------------------------------------------------------------------------------
local zoneButtons: { [number]: TextButton } = {}

local function travelTo(zoneId: number)
	local zonesFolder = Workspace:FindFirstChild("Zones")
	local zoneFolder = zonesFolder and zonesFolder:FindFirstChild("Zone" .. zoneId)
	local spawnPart = zoneFolder and zoneFolder:FindFirstChild("ZoneSpawn")
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if spawnPart and spawnPart:IsA("BasePart") and root then
		root.CFrame = spawnPart.CFrame + Vector3.new(0, 4, 0)
		window.Visible = false
	end
end

local function refresh()
	for zoneId, actionButton in pairs(zoneButtons) do
		local unlocked = latestData and latestData.UnlockedZones
			and latestData.UnlockedZones[zoneId] -- number keys survive as-is in
			or latestData and latestData.UnlockedZones
			and latestData.UnlockedZones[tostring(zoneId)] -- ...or as strings post-JSON
		if unlocked then
			actionButton.Text = "TRAVEL"
			actionButton.BackgroundColor3 = ACCENT
		else
			actionButton.Text = "UNLOCK " .. abbreviate(GameConfig.Zones[zoneId].UnlockCost)
			actionButton.BackgroundColor3 = Color3.fromRGB(200, 160, 60)
		end
	end
end

for zoneId = 1, 4 do
	local zoneConfig = GameConfig.Zones[zoneId]

	local card = Instance.new("Frame")
	card.Size = UDim2.new(1, 0, 0, 60)
	card.BackgroundColor3 = CARD_COLOR
	card.LayoutOrder = zoneId
	card.Parent = list
	round(card, 10)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(0.5, 0, 0, 28)
	nameLabel.Position = UDim2.new(0, 12, 0, 6)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = FONT
	nameLabel.Text = ("Zone %d — %s"):format(zoneId, zoneConfig.Name)
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextScaled = true
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Parent = card

	local bossLabel = Instance.new("TextLabel")
	bossLabel.Size = UDim2.new(0.5, 0, 0, 20)
	bossLabel.Position = UDim2.new(0, 12, 0, 34)
	bossLabel.BackgroundTransparency = 1
	bossLabel.Font = FONT
	bossLabel.Text = "Boss: " .. zoneConfig.Boss
	bossLabel.TextColor3 = Color3.fromRGB(180, 185, 205)
	bossLabel.TextScaled = true
	bossLabel.TextXAlignment = Enum.TextXAlignment.Left
	bossLabel.Parent = card

	local action = Instance.new("TextButton")
	action.Size = UDim2.new(0, 150, 0, 40)
	action.Position = UDim2.new(1, -162, 0.5, -20)
	action.BackgroundColor3 = ACCENT
	action.Font = FONT
	action.Text = "TRAVEL"
	action.TextColor3 = Color3.new(1, 1, 1)
	action.TextScaled = true
	action.Parent = card
	round(action, 8)
	zoneButtons[zoneId] = action

	action.MouseButton1Click:Connect(function()
		local unlocked = latestData and latestData.UnlockedZones
			and (latestData.UnlockedZones[zoneId] or latestData.UnlockedZones[tostring(zoneId)])
		if unlocked then
			travelTo(zoneId)
			return
		end
		local success, message = Remotes.UnlockZone:InvokeServer(zoneId)
		if success then
			refresh()
			travelTo(zoneId)
		elseif type(message) == "string" then
			bossLabel.Text = message
			bossLabel.TextColor3 = Color3.fromRGB(255, 90, 90)
			task.delay(2.5, function()
				bossLabel.Text = "Boss: " .. zoneConfig.Boss
				bossLabel.TextColor3 = Color3.fromRGB(180, 185, 205)
			end)
			-- Upsell: the zone paywall is the highest-value conversion moment.
			if string.find(message, "Not enough") then
				local shop = screenGui:FindFirstChild("ShopWindow")
				if shop and shop:IsA("Frame") then
					shop.Visible = true
				end
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- OPEN BUTTON + DATA BINDING
--------------------------------------------------------------------------------
local openButton = Instance.new("TextButton")
openButton.Size = UDim2.new(0, 110, 0, 44)
openButton.Position = UDim2.new(0, 12, 0, 400)
openButton.BackgroundColor3 = Color3.fromRGB(70, 170, 200)
openButton.Font = FONT
openButton.Text = "ZONES"
openButton.TextColor3 = Color3.new(1, 1, 1)
openButton.TextScaled = true
openButton.Parent = screenGui
round(openButton, 10)

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

print("[ZoneTravelController] Ready.")
