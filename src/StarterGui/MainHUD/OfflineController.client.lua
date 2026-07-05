--!strict
--------------------------------------------------------------------------------
-- OfflineController
-- StarterGui.MainHUD.OfflineController (LocalScript)
--
-- The welcome-back popup. When OfflineEarningsManager reports offline gold,
-- shows what was earned (already granted — no claim risk) and offers the
-- contextual "DOUBLE IT" developer product. This converts because the player
-- is looking at the exact number they'd be doubling.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local localPlayer = Players.LocalPlayer
local screenGui = script.Parent :: ScreenGui

local FONT = Enum.Font.FredokaOne
local PANEL_COLOR = Color3.fromRGB(32, 34, 48)
local GOLD = Color3.fromRGB(255, 210, 70)
local ROBUX_GREEN = Color3.fromRGB(57, 218, 138)

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
-- POPUP
--------------------------------------------------------------------------------
local popup = Instance.new("Frame")
popup.Name = "OfflinePopup"
popup.AnchorPoint = Vector2.new(0.5, 0.5)
popup.Position = UDim2.fromScale(0.5, 0.42)
popup.Size = UDim2.new(0, 420, 0, 240)
popup.BackgroundColor3 = PANEL_COLOR
popup.Visible = false
popup.ZIndex = 40
popup.Parent = screenGui
round(popup, 16)

local header = Instance.new("TextLabel")
header.Size = UDim2.new(1, -24, 0, 40)
header.Position = UDim2.new(0, 12, 0, 10)
header.BackgroundTransparency = 1
header.Font = FONT
header.Text = "WELCOME BACK!"
header.TextColor3 = Color3.new(1, 1, 1)
header.TextScaled = true
header.ZIndex = 41
header.Parent = popup

local amountLabel = Instance.new("TextLabel")
amountLabel.Size = UDim2.new(1, -24, 0, 52)
amountLabel.Position = UDim2.new(0, 12, 0, 54)
amountLabel.BackgroundTransparency = 1
amountLabel.Font = FONT
amountLabel.Text = ""
amountLabel.TextColor3 = GOLD
amountLabel.TextScaled = true
amountLabel.ZIndex = 41
amountLabel.Parent = popup

local detailLabel = Instance.new("TextLabel")
detailLabel.Size = UDim2.new(1, -24, 0, 24)
detailLabel.Position = UDim2.new(0, 12, 0, 106)
detailLabel.BackgroundTransparency = 1
detailLabel.Font = FONT
detailLabel.Text = ""
detailLabel.TextColor3 = Color3.fromRGB(180, 185, 205)
detailLabel.TextScaled = true
detailLabel.ZIndex = 41
detailLabel.Parent = popup

local doubleButton = Instance.new("TextButton")
doubleButton.Size = UDim2.new(0.56, 0, 0, 48)
doubleButton.Position = UDim2.new(0.04, 0, 1, -60)
doubleButton.BackgroundColor3 = ROBUX_GREEN
doubleButton.Font = FONT
doubleButton.Text = "DOUBLE IT!  R$"
doubleButton.TextColor3 = Color3.new(1, 1, 1)
doubleButton.TextScaled = true
doubleButton.ZIndex = 41
doubleButton.Parent = popup
round(doubleButton, 10)

local dismissButton = Instance.new("TextButton")
dismissButton.Size = UDim2.new(0.32, 0, 0, 48)
dismissButton.Position = UDim2.new(0.64, 0, 1, -60)
dismissButton.BackgroundColor3 = Color3.fromRGB(80, 84, 100)
dismissButton.Font = FONT
dismissButton.Text = "THANKS"
dismissButton.TextColor3 = Color3.new(1, 1, 1)
dismissButton.TextScaled = true
dismissButton.ZIndex = 41
dismissButton.Parent = popup
round(dismissButton, 10)

local activeProductId: number? = nil

Remotes.OfflineReport.OnClientEvent:Connect(function(report: any)
	if type(report) ~= "table" or type(report.Amount) ~= "number" then
		return
	end
	activeProductId = tonumber(report.ProductId)

	local hours = math.floor((report.AwayMinutes or 0) / 60)
	local minutes = (report.AwayMinutes or 0) % 60

	amountLabel.Text = "+" .. abbreviate(report.Amount) .. " Gold"
	detailLabel.Text = ("Earned while you were away %dh %dm — already added!")
		:format(hours, minutes)
	doubleButton.Text = ("DOUBLE IT (+%s)  R$"):format(abbreviate(report.Amount))

	popup.Size = UDim2.new(0, 0, 0, 0)
	popup.Visible = true
	TweenService:Create(popup,
		TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.new(0, 420, 0, 240) }):Play()
end)

doubleButton.MouseButton1Click:Connect(function()
	if activeProductId then
		MarketplaceService:PromptProductPurchase(localPlayer, activeProductId)
	end
	popup.Visible = false
end)

dismissButton.MouseButton1Click:Connect(function()
	popup.Visible = false
end)

print("[OfflineController] Ready.")
