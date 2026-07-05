--!strict
--------------------------------------------------------------------------------
-- ShopController
-- StarterGui.MainHUD.ShopController (LocalScript)
--
-- Governs the entire store interface. The whole GUI is built in code so this
-- file is copy-paste complete — no manually authored ScreenGui required.
--
--   * Currency HUD (Gold / Gems / Rebirths) live-updated from DataChanged.
--   * ROBUX tab: Developer Products (100 Coins, 500 Coins, Mega Egg Roll) and
--     Gamepasses (2x Coins, VIP Luck, Auto-Hatch). Every button prompts the
--     purchase INSTANTLY via MarketplaceService.
--   * EGGS tab: in-game currency egg hatching through Remotes.HatchEgg.
--   * WEAPONS tab: buy/equip through Remotes.BuyWeapon / Remotes.EquipWeapon.
--   * Toast notifications from Remotes.NotifyText.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local localPlayer = Players.LocalPlayer
local screenGui = script.Parent :: ScreenGui

local FONT = Enum.Font.FredokaOne
local PANEL_COLOR = Color3.fromRGB(32, 34, 48)
local CARD_COLOR = Color3.fromRGB(46, 49, 70)
local ACCENT = Color3.fromRGB(90, 200, 120)
local ROBUX_GREEN = Color3.fromRGB(57, 218, 138)

local latestData: any = nil

--------------------------------------------------------------------------------
-- SMALL UI HELPERS
--------------------------------------------------------------------------------
local function round(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function label(parent: Instance, text: string, size: UDim2, position: UDim2, textSize: number?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = position
	l.Font = FONT
	l.Text = text
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextScaled = textSize == nil
	if textSize then
		l.TextSize = textSize
	end
	l.Parent = parent
	return l
end

local function button(parent: Instance, text: string, size: UDim2, position: UDim2, color: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Size = size
	b.Position = position
	b.BackgroundColor3 = color
	b.Font = FONT
	b.Text = text
	b.TextColor3 = Color3.new(1, 1, 1)
	b.TextScaled = true
	b.AutoButtonColor = true
	b.Parent = parent
	round(b, 10)
	return b
end

--------------------------------------------------------------------------------
-- CURRENCY HUD (top-left)
--------------------------------------------------------------------------------
local hudFrame = Instance.new("Frame")
hudFrame.Name = "CurrencyHUD"
hudFrame.AnchorPoint = Vector2.new(0, 0)
hudFrame.Position = UDim2.new(0, 12, 0, 12)
hudFrame.Size = UDim2.new(0, 220, 0, 118)
hudFrame.BackgroundColor3 = PANEL_COLOR
hudFrame.BackgroundTransparency = 0.15
hudFrame.Parent = screenGui
round(hudFrame, 12)

local goldLabel = label(hudFrame, "Gold: 0", UDim2.new(1, -16, 0, 30), UDim2.new(0, 8, 0, 6))
goldLabel.TextColor3 = Color3.fromRGB(255, 210, 70)
goldLabel.TextXAlignment = Enum.TextXAlignment.Left

local gemLabel = label(hudFrame, "Gems: 0", UDim2.new(1, -16, 0, 30), UDim2.new(0, 8, 0, 42))
gemLabel.TextColor3 = Color3.fromRGB(90, 220, 255)
gemLabel.TextXAlignment = Enum.TextXAlignment.Left

local rebirthLabel = label(hudFrame, "Rebirths: 0", UDim2.new(1, -16, 0, 30), UDim2.new(0, 8, 0, 78))
rebirthLabel.TextColor3 = Color3.fromRGB(255, 140, 220)
rebirthLabel.TextXAlignment = Enum.TextXAlignment.Left

local function abbreviate(n: number): string
	if n >= 1e12 then return string.format("%.2fT", n / 1e12) end
	if n >= 1e9 then return string.format("%.2fB", n / 1e9) end
	if n >= 1e6 then return string.format("%.2fM", n / 1e6) end
	if n >= 1e3 then return string.format("%.1fK", n / 1e3) end
	return tostring(math.floor(n))
end

--------------------------------------------------------------------------------
-- TOASTS
--------------------------------------------------------------------------------
local toastHolder = Instance.new("Frame")
toastHolder.Name = "Toasts"
toastHolder.AnchorPoint = Vector2.new(0.5, 0)
toastHolder.Position = UDim2.new(0.5, 0, 0, 20)
toastHolder.Size = UDim2.new(0, 420, 0, 200)
toastHolder.BackgroundTransparency = 1
toastHolder.Parent = screenGui

local toastLayout = Instance.new("UIListLayout")
toastLayout.Padding = UDim.new(0, 6)
toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
toastLayout.Parent = toastHolder

local function showToast(message: string, color: Color3?)
	local toast = Instance.new("TextLabel")
	toast.Size = UDim2.new(1, 0, 0, 34)
	toast.BackgroundColor3 = PANEL_COLOR
	toast.BackgroundTransparency = 0.1
	toast.Font = FONT
	toast.Text = message
	toast.TextColor3 = color or Color3.new(1, 1, 1)
	toast.TextScaled = true
	toast.Parent = toastHolder
	round(toast, 8)

	task.delay(2.5, function()
		local fade = TweenService:Create(toast, TweenInfo.new(0.4),
			{ BackgroundTransparency = 1, TextTransparency = 1 })
		fade:Play()
		fade.Completed:Wait()
		toast:Destroy()
	end)
end

Remotes.NotifyText.OnClientEvent:Connect(function(message: any, color: any)
	if type(message) == "string" then
		showToast(message, typeof(color) == "Color3" and color or nil)
	end
end)

--------------------------------------------------------------------------------
-- SHOP WINDOW SHELL
--------------------------------------------------------------------------------
local shopFrame = Instance.new("Frame")
shopFrame.Name = "ShopWindow"
shopFrame.AnchorPoint = Vector2.new(0.5, 0.5)
shopFrame.Position = UDim2.fromScale(0.5, 0.5)
shopFrame.Size = UDim2.new(0, 640, 0, 440)
shopFrame.BackgroundColor3 = PANEL_COLOR
shopFrame.Visible = false
shopFrame.Parent = screenGui
round(shopFrame, 16)

label(shopFrame, "NIGHTFALL SHOP", UDim2.new(0.6, 0, 0, 40), UDim2.new(0.2, 0, 0, 8))

local closeButton = button(shopFrame, "X", UDim2.new(0, 36, 0, 36),
	UDim2.new(1, -44, 0, 8), Color3.fromRGB(220, 80, 80))

local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, -24, 0, 40)
tabBar.Position = UDim2.new(0, 12, 0, 54)
tabBar.BackgroundTransparency = 1
tabBar.Parent = shopFrame

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 8)
tabLayout.Parent = tabBar

local pageHolder = Instance.new("Frame")
pageHolder.Size = UDim2.new(1, -24, 1, -110)
pageHolder.Position = UDim2.new(0, 12, 0, 100)
pageHolder.BackgroundTransparency = 1
pageHolder.Parent = shopFrame

local pages: { [string]: ScrollingFrame } = {}
local tabButtons: { [string]: TextButton } = {}

local function makePage(name: string): ScrollingFrame
	local page = Instance.new("ScrollingFrame")
	page.Name = name .. "Page"
	page.Size = UDim2.fromScale(1, 1)
	page.CanvasSize = UDim2.new(0, 0, 0, 0)
	page.AutomaticCanvasSize = Enum.AutomaticSize.Y
	page.ScrollBarThickness = 6
	page.BackgroundTransparency = 1
	page.Visible = false
	page.Parent = pageHolder

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = page
	return page
end

local function selectTab(name: string)
	for pageName, page in pairs(pages) do
		page.Visible = pageName == name
		tabButtons[pageName].BackgroundColor3 =
			if pageName == name then ACCENT else CARD_COLOR
	end
end

for _, tabName in ipairs({ "Robux", "Eggs", "Weapons" }) do
	pages[tabName] = makePage(tabName)
	local tab = button(tabBar, tabName:upper(), UDim2.new(0, 120, 1, 0), UDim2.new(), CARD_COLOR)
	tabButtons[tabName] = tab
	tab.MouseButton1Click:Connect(function()
		selectTab(tabName)
	end)
end

--------------------------------------------------------------------------------
-- CARD FACTORY
--------------------------------------------------------------------------------
local function makeCard(parent: Instance, order: number, title: string, subtitle: string): (Frame, TextButton)
	local card = Instance.new("Frame")
	card.Size = UDim2.new(1, -8, 0, 74)
	card.BackgroundColor3 = CARD_COLOR
	card.LayoutOrder = order
	card.Parent = parent
	round(card, 10)

	local titleLabel = label(card, title, UDim2.new(0.55, 0, 0, 32), UDim2.new(0, 12, 0, 8), 22)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left

	local subLabel = label(card, subtitle, UDim2.new(0.55, 0, 0, 24), UDim2.new(0, 12, 0, 40), 15)
	subLabel.TextXAlignment = Enum.TextXAlignment.Left
	subLabel.TextColor3 = Color3.fromRGB(180, 185, 205)
	subLabel.TextWrapped = true

	local buy = button(card, "BUY", UDim2.new(0, 130, 0, 44), UDim2.new(1, -144, 0.5, -22), ROBUX_GREEN)
	return card, buy
end

--------------------------------------------------------------------------------
-- ROBUX TAB — instant MarketplaceService prompts
--------------------------------------------------------------------------------
do
	local page = pages.Robux
	local order = 0

	-- Developer Products
	local productList = {
		GameConfig.DeveloperProducts.Coins100,
		GameConfig.DeveloperProducts.Coins500,
		GameConfig.DeveloperProducts.MegaEggRoll,
	}
	for _, product in ipairs(productList) do
		order += 1
		local _, buy = makeCard(page, order, product.Name,
			product.Grant.Gold and ("Instantly grants " .. product.Grant.Gold .. " Gold.")
				or "One premium roll on the Mega Egg — Rare or better guaranteed pool!")
		buy.Text = "R$ BUY"
		buy.MouseButton1Click:Connect(function()
			-- Instant prompt; grant happens server-side in ProcessReceipt.
			MarketplaceService:PromptProductPurchase(localPlayer, product.Id)
		end)
	end

	-- Gamepasses
	local passList = {
		GameConfig.Gamepasses.DoubleCoins,
		GameConfig.Gamepasses.VIPLuck,
		GameConfig.Gamepasses.AutoHatch,
	}
	for _, pass in ipairs(passList) do
		order += 1
		local card, buy = makeCard(page, order, pass.Name, pass.Description)
		buy.Text = "R$ PASS"

		local function refreshOwnedState()
			if latestData and latestData.OwnedGamepasses
				and latestData.OwnedGamepasses[tostring(pass.Id)] then
				buy.Text = "OWNED"
				buy.BackgroundColor3 = Color3.fromRGB(110, 115, 140)
			end
		end

		buy.MouseButton1Click:Connect(function()
			if buy.Text == "OWNED" then
				-- Auto-Hatch owned: the button becomes the on/off toggle.
				if pass == GameConfig.Gamepasses.AutoHatch then
					local enable = not (latestData and latestData.AutoHatchEnabled)
					Remotes.ToggleAutoHatch:FireServer(enable)
					showToast(enable and "Auto-Hatch ON" or "Auto-Hatch OFF", ACCENT)
				end
				return
			end
			MarketplaceService:PromptGamePassPurchase(localPlayer, pass.Id)
		end)

		Remotes.DataChanged.OnClientEvent:Connect(refreshOwnedState)
		task.defer(refreshOwnedState)
	end
end

--------------------------------------------------------------------------------
-- EGGS TAB
--------------------------------------------------------------------------------
do
	local page = pages.Eggs
	local order = 0
	local eggOrder = { "ForestEgg", "MagmaEgg", "CrystalEgg", "CyberEgg" }
	for _, eggName in ipairs(eggOrder) do
		local egg = GameConfig.Eggs[eggName]
		order += 1
		local zoneName = GameConfig.Zones[egg.Zone] and GameConfig.Zones[egg.Zone].Name or "?"
		local _, buy = makeCard(page, order, eggName,
			("Zone: %s  •  Cost: %s %s"):format(zoneName, abbreviate(egg.Cost), egg.Currency))
		buy.Text = "HATCH"
		buy.MouseButton1Click:Connect(function()
			buy.Active = false
			task.delay(0.5, function() buy.Active = true end)
			local reveal, err = Remotes.HatchEgg:InvokeServer(eggName)
			if not reveal and err then
				showToast(err, Color3.fromRGB(255, 90, 90))
			end
		end)
	end
end

--------------------------------------------------------------------------------
-- WEAPONS TAB
--------------------------------------------------------------------------------
do
	local page = pages.Weapons
	local weaponOrder = {
		"WoodenSword", "IronCleaver", "MysticBlade", "MagmaEdge", "ObsidianFang",
		"CrystalPike", "PrismSaber", "NeonKatana", "VoidReaver",
	}
	for index, weaponName in ipairs(weaponOrder) do
		local weapon = GameConfig.Weapons[weaponName]
		local _, buy = makeCard(page, index, weapon.DisplayName,
			("Damage: %s  •  Cost: %s Gold  •  Zone %d")
				:format(abbreviate(weapon.BaseDamage), abbreviate(weapon.Cost), weapon.Zone))

		local function refresh()
			if not latestData then return end
			if latestData.EquippedWeapon == weaponName then
				buy.Text = "EQUIPPED"
				buy.BackgroundColor3 = Color3.fromRGB(110, 115, 140)
			elseif latestData.OwnedWeapons and latestData.OwnedWeapons[weaponName] then
				buy.Text = "EQUIP"
				buy.BackgroundColor3 = ACCENT
			else
				buy.Text = "BUY"
				buy.BackgroundColor3 = ROBUX_GREEN
			end
		end

		buy.MouseButton1Click:Connect(function()
			if not latestData then return end
			local success, message
			if latestData.OwnedWeapons and latestData.OwnedWeapons[weaponName] then
				success, message = Remotes.EquipWeapon:InvokeServer(weaponName)
			else
				success, message = Remotes.BuyWeapon:InvokeServer(weaponName)
			end
			if message then
				showToast(message, success and ACCENT or Color3.fromRGB(255, 90, 90))
			end
		end)

		Remotes.DataChanged.OnClientEvent:Connect(refresh)
		task.defer(refresh)
	end
end

--------------------------------------------------------------------------------
-- OPEN / CLOSE + REBIRTH BUTTON
--------------------------------------------------------------------------------
local openShop = button(screenGui, "SHOP", UDim2.new(0, 110, 0, 44),
	UDim2.new(0, 12, 0, 140), ROBUX_GREEN)
openShop.MouseButton1Click:Connect(function()
	shopFrame.Visible = not shopFrame.Visible
	if shopFrame.Visible then
		selectTab("Robux")
	end
end)

closeButton.MouseButton1Click:Connect(function()
	shopFrame.Visible = false
end)

local rebirthButton = button(screenGui, "REBIRTH", UDim2.new(0, 110, 0, 44),
	UDim2.new(0, 12, 0, 192), Color3.fromRGB(255, 140, 220))
rebirthButton.MouseButton1Click:Connect(function()
	local success, message = Remotes.Rebirth:InvokeServer()
	if message then
		showToast(message, success and ACCENT or Color3.fromRGB(255, 90, 90))
	end
end)

--------------------------------------------------------------------------------
-- LIVE DATA BINDING
--------------------------------------------------------------------------------
local function applyData(data: any)
	if type(data) ~= "table" then return end
	latestData = data
	goldLabel.Text = "Gold: " .. abbreviate(data.Gold or 0)
	gemLabel.Text = "Gems: " .. abbreviate(data.Gems or 0)
	rebirthLabel.Text = "Rebirths: " .. tostring(data.Rebirths or 0)
end

Remotes.DataChanged.OnClientEvent:Connect(applyData)

-- Pull the initial snapshot (covers joining after the first DataChanged fired).
task.spawn(function()
	local snapshot = Remotes.GetData:InvokeServer()
	if snapshot then
		applyData(snapshot)
	end
end)

-- Hatch reveal toast (LootAnimator handles the 3D side).
Remotes.PetHatched.OnClientEvent:Connect(function(reveal: any)
	if type(reveal) == "table" then
		showToast(("Hatched %s (%s, +%d dmg)!"):format(
			tostring(reveal.PetName), tostring(reveal.Tier), tonumber(reveal.StatBonus) or 0),
			Color3.fromRGB(255, 170, 0))
	end
end)

print("[ShopController] Ready.")
