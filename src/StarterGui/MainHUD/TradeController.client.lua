--!strict
--------------------------------------------------------------------------------
-- TradeController
-- StarterGui.MainHUD.TradeController (LocalScript)
--
-- Client half of the secure trade flow (server truth lives in TradeManager):
--   * Player list -> send a trade request.
--   * Incoming request banner with ACCEPT / DECLINE (30s TTL server-side).
--   * Live trade window: click your pets to add/remove them from your offer
--     (max 6), watch the partner's offer update, CONFIRM, then the 3-second
--     countdown. Any change flips both sides back to unconfirmed — the UI just
--     renders whatever TradeUpdated says; it never assumes.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local localPlayer = Players.LocalPlayer
local screenGui = script.Parent :: ScreenGui

local FONT = Enum.Font.FredokaOne
local PANEL_COLOR = Color3.fromRGB(32, 34, 48)
local CARD_COLOR = Color3.fromRGB(46, 49, 70)
local ACCENT = Color3.fromRGB(90, 200, 120)
local WARN = Color3.fromRGB(255, 160, 90)

local MAX_PER_SIDE = GameConfig.Trading.MaxPetsPerSide

local latestData: any = nil
local myOffer: { string } = {} -- UUIDs I intend to offer (server re-validates)
local inTrade = false

local tierColors: { [string]: Color3 } = {}
for _, tierInfo in ipairs(GameConfig.PetTiers) do
	tierColors[tierInfo.Tier] = tierInfo.Color
end

local function round(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function petLabelText(pet: any): string
	local variant = pet.Variant or "Normal"
	local prefix = if variant ~= "Normal" then (variant .. " ") else ""
	return ("%s%s (+%d)"):format(prefix, tostring(pet.PetName), tonumber(pet.StatBonus) or 0)
end

local function petLabelColor(pet: any): Color3
	local variant = pet.Variant or "Normal"
	local variantConfig = GameConfig.Fusion.Variants[variant]
	if variantConfig then
		return variantConfig.Color
	end
	local petConfig = GameConfig.Pets[pet.PetName]
	return (petConfig and tierColors[petConfig.Tier]) or Color3.new(1, 1, 1)
end

--------------------------------------------------------------------------------
-- WINDOW SHELL
--------------------------------------------------------------------------------
local window = Instance.new("Frame")
window.Name = "TradeWindow"
window.AnchorPoint = Vector2.new(0.5, 0.5)
window.Position = UDim2.fromScale(0.5, 0.5)
window.Size = UDim2.new(0, 680, 0, 480)
window.BackgroundColor3 = PANEL_COLOR
window.Visible = false
window.Parent = screenGui
round(window, 16)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(0.7, 0, 0, 36)
title.Position = UDim2.new(0.15, 0, 0, 8)
title.BackgroundTransparency = 1
title.Font = FONT
title.Text = "TRADING"
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

-- PAGE 1: player list ---------------------------------------------------------
local playerListPage = Instance.new("ScrollingFrame")
playerListPage.Size = UDim2.new(1, -24, 1, -60)
playerListPage.Position = UDim2.new(0, 12, 0, 48)
playerListPage.CanvasSize = UDim2.new(0, 0, 0, 0)
playerListPage.AutomaticCanvasSize = Enum.AutomaticSize.Y
playerListPage.ScrollBarThickness = 6
playerListPage.BackgroundTransparency = 1
playerListPage.Parent = window

local playerListLayout = Instance.new("UIListLayout")
playerListLayout.Padding = UDim.new(0, 6)
playerListLayout.Parent = playerListPage

-- PAGE 2: active trade --------------------------------------------------------
local tradePage = Instance.new("Frame")
tradePage.Size = UDim2.new(1, -24, 1, -60)
tradePage.Position = UDim2.new(0, 12, 0, 48)
tradePage.BackgroundTransparency = 1
tradePage.Visible = false
tradePage.Parent = window

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, 0, 0, 26)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = FONT
statusLabel.Text = ""
statusLabel.TextColor3 = WARN
statusLabel.TextScaled = true
statusLabel.Parent = tradePage

local function makeColumn(xScale: number, headerText: string): (TextLabel, ScrollingFrame)
	local header = Instance.new("TextLabel")
	header.Size = UDim2.new(0.48, 0, 0, 24)
	header.Position = UDim2.new(xScale, 0, 0, 30)
	header.BackgroundTransparency = 1
	header.Font = FONT
	header.Text = headerText
	header.TextColor3 = Color3.new(1, 1, 1)
	header.TextScaled = true
	header.Parent = tradePage

	local column = Instance.new("ScrollingFrame")
	column.Size = UDim2.new(0.48, 0, 0, 150)
	column.Position = UDim2.new(xScale, 0, 0, 58)
	column.BackgroundColor3 = Color3.fromRGB(25, 26, 36)
	column.CanvasSize = UDim2.new(0, 0, 0, 0)
	column.AutomaticCanvasSize = Enum.AutomaticSize.Y
	column.ScrollBarThickness = 4
	column.Parent = tradePage
	round(column, 8)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.Parent = column
	return header, column
end

local yourHeader, yourOfferColumn = makeColumn(0, "YOUR OFFER (0/6)")
local theirHeader, theirOfferColumn = makeColumn(0.52, "THEIR OFFER")

local inventoryHeader = Instance.new("TextLabel")
inventoryHeader.Size = UDim2.new(1, 0, 0, 22)
inventoryHeader.Position = UDim2.new(0, 0, 0, 214)
inventoryHeader.BackgroundTransparency = 1
inventoryHeader.Font = FONT
inventoryHeader.Text = "YOUR PETS (click to add/remove)"
inventoryHeader.TextColor3 = Color3.fromRGB(180, 185, 205)
inventoryHeader.TextScaled = true
inventoryHeader.Parent = tradePage

local inventoryGrid = Instance.new("ScrollingFrame")
inventoryGrid.Size = UDim2.new(1, 0, 0, 120)
inventoryGrid.Position = UDim2.new(0, 0, 0, 240)
inventoryGrid.BackgroundColor3 = Color3.fromRGB(25, 26, 36)
inventoryGrid.CanvasSize = UDim2.new(0, 0, 0, 0)
inventoryGrid.AutomaticCanvasSize = Enum.AutomaticSize.Y
inventoryGrid.ScrollBarThickness = 4
inventoryGrid.Parent = tradePage
round(inventoryGrid, 8)

local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.new(0, 150, 0, 30)
gridLayout.CellPadding = UDim2.new(0, 4, 0, 4)
gridLayout.Parent = inventoryGrid

local confirmButton = Instance.new("TextButton")
confirmButton.Size = UDim2.new(0.48, 0, 0, 44)
confirmButton.Position = UDim2.new(0, 0, 1, -48)
confirmButton.BackgroundColor3 = ACCENT
confirmButton.Font = FONT
confirmButton.Text = "CONFIRM"
confirmButton.TextColor3 = Color3.new(1, 1, 1)
confirmButton.TextScaled = true
confirmButton.Parent = tradePage
round(confirmButton, 10)

local cancelButton = Instance.new("TextButton")
cancelButton.Size = UDim2.new(0.48, 0, 0, 44)
cancelButton.Position = UDim2.new(0.52, 0, 1, -48)
cancelButton.BackgroundColor3 = Color3.fromRGB(220, 80, 80)
cancelButton.Font = FONT
cancelButton.Text = "CANCEL TRADE"
cancelButton.TextColor3 = Color3.new(1, 1, 1)
cancelButton.TextScaled = true
cancelButton.Parent = tradePage
round(cancelButton, 10)

--------------------------------------------------------------------------------
-- INCOMING REQUEST BANNER
--------------------------------------------------------------------------------
local requestBanner = Instance.new("Frame")
requestBanner.AnchorPoint = Vector2.new(0.5, 0)
requestBanner.Position = UDim2.new(0.5, 0, 0, 64)
requestBanner.Size = UDim2.new(0, 380, 0, 74)
requestBanner.BackgroundColor3 = PANEL_COLOR
requestBanner.Visible = false
requestBanner.Parent = screenGui
round(requestBanner, 12)

local requestText = Instance.new("TextLabel")
requestText.Size = UDim2.new(1, -16, 0, 30)
requestText.Position = UDim2.new(0, 8, 0, 6)
requestText.BackgroundTransparency = 1
requestText.Font = FONT
requestText.Text = ""
requestText.TextColor3 = Color3.new(1, 1, 1)
requestText.TextScaled = true
requestText.Parent = requestBanner

local acceptButton = Instance.new("TextButton")
acceptButton.Size = UDim2.new(0.44, 0, 0, 30)
acceptButton.Position = UDim2.new(0.04, 0, 0, 38)
acceptButton.BackgroundColor3 = ACCENT
acceptButton.Font = FONT
acceptButton.Text = "ACCEPT"
acceptButton.TextColor3 = Color3.new(1, 1, 1)
acceptButton.TextScaled = true
acceptButton.Parent = requestBanner
round(acceptButton, 8)

local declineButton = Instance.new("TextButton")
declineButton.Size = UDim2.new(0.44, 0, 0, 30)
declineButton.Position = UDim2.new(0.52, 0, 0, 38)
declineButton.BackgroundColor3 = Color3.fromRGB(220, 80, 80)
declineButton.Font = FONT
declineButton.Text = "DECLINE"
declineButton.TextColor3 = Color3.new(1, 1, 1)
declineButton.TextScaled = true
declineButton.Parent = requestBanner
round(declineButton, 8)

local pendingRequesterId: number? = nil

Remotes.TradeRequested.OnClientEvent:Connect(function(requesterName: any, requesterUserId: any)
	if type(requesterName) ~= "string" or type(requesterUserId) ~= "number" then
		return
	end
	pendingRequesterId = requesterUserId
	requestText.Text = requesterName .. " wants to trade!"
	requestBanner.Visible = true
	task.delay(30, function()
		if pendingRequesterId == requesterUserId then
			pendingRequesterId = nil
			requestBanner.Visible = false
		end
	end)
end)

acceptButton.MouseButton1Click:Connect(function()
	if pendingRequesterId then
		Remotes.TradeRespond:InvokeServer(pendingRequesterId, true)
		pendingRequesterId = nil
		requestBanner.Visible = false
	end
end)

declineButton.MouseButton1Click:Connect(function()
	if pendingRequesterId then
		Remotes.TradeRespond:InvokeServer(pendingRequesterId, false)
		pendingRequesterId = nil
		requestBanner.Visible = false
	end
end)

--------------------------------------------------------------------------------
-- PLAYER LIST PAGE
--------------------------------------------------------------------------------
local function rebuildPlayerList()
	for _, child in ipairs(playerListPage:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local others = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= localPlayer then
			table.insert(others, player)
		end
	end

	if #others == 0 then
		local empty = Instance.new("Frame")
		empty.Size = UDim2.new(1, -8, 0, 44)
		empty.BackgroundColor3 = CARD_COLOR
		empty.Parent = playerListPage
		round(empty, 8)
		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.Font = FONT
		text.Text = "No other players in this server yet."
		text.TextColor3 = Color3.fromRGB(180, 185, 205)
		text.TextScaled = true
		text.Parent = empty
		return
	end

	for _, player in ipairs(others) do
		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, -8, 0, 44)
		card.BackgroundColor3 = CARD_COLOR
		card.Parent = playerListPage
		round(card, 8)

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(0.6, 0, 1, 0)
		nameLabel.Position = UDim2.new(0, 12, 0, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = FONT
		nameLabel.Text = player.Name
		nameLabel.TextColor3 = Color3.new(1, 1, 1)
		nameLabel.TextScaled = true
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Parent = card

		local trade = Instance.new("TextButton")
		trade.Size = UDim2.new(0, 110, 0, 32)
		trade.Position = UDim2.new(1, -122, 0.5, -16)
		trade.BackgroundColor3 = ACCENT
		trade.Font = FONT
		trade.Text = "TRADE"
		trade.TextColor3 = Color3.new(1, 1, 1)
		trade.TextScaled = true
		trade.Parent = card
		round(trade, 8)

		trade.MouseButton1Click:Connect(function()
			trade.Active = false
			local _, message = Remotes.TradeRequest:InvokeServer(player.UserId)
			trade.Text = "SENT!"
			task.delay(2, function()
				if trade.Parent then
					trade.Text = "TRADE"
					trade.Active = true
				end
			end)
			if type(message) == "string" then
				statusLabel.Text = message
			end
		end)
	end
end

--------------------------------------------------------------------------------
-- TRADE PAGE RENDERING (pure function of the server's TradeUpdated state)
--------------------------------------------------------------------------------
local function fillOfferColumn(column: ScrollingFrame, offer: { any })
	for _, child in ipairs(column:GetChildren()) do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	for _, pet in ipairs(offer) do
		local entry = Instance.new("TextLabel")
		entry.Size = UDim2.new(1, -8, 0, 24)
		entry.BackgroundTransparency = 1
		entry.Font = FONT
		entry.Text = petLabelText(pet)
		entry.TextColor3 = petLabelColor(pet)
		entry.TextScaled = true
		entry.TextXAlignment = Enum.TextXAlignment.Left
		entry.Parent = column
	end
end

local function rebuildInventoryGrid()
	for _, child in ipairs(inventoryGrid:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	if not latestData or not latestData.OwnedPets then
		return
	end

	local offered: { [string]: boolean } = {}
	for _, uuid in ipairs(myOffer) do
		offered[uuid] = true
	end

	local pets = table.clone(latestData.OwnedPets)
	table.sort(pets, function(a, b)
		return a.StatBonus > b.StatBonus
	end)

	for _, pet in ipairs(pets) do
		local cell = Instance.new("TextButton")
		cell.BackgroundColor3 = offered[pet.UUID] and ACCENT or CARD_COLOR
		cell.Font = FONT
		cell.Text = petLabelText(pet)
		cell.TextColor3 = petLabelColor(pet)
		cell.TextScaled = true
		cell.Parent = inventoryGrid
		round(cell, 6)

		cell.MouseButton1Click:Connect(function()
			if offered[pet.UUID] then
				for index, uuid in ipairs(myOffer) do
					if uuid == pet.UUID then
						table.remove(myOffer, index)
						break
					end
				end
			else
				if #myOffer >= MAX_PER_SIDE then
					statusLabel.Text = ("Max %d pets per side."):format(MAX_PER_SIDE)
					return
				end
				table.insert(myOffer, pet.UUID)
			end
			Remotes.TradeSetOffer:InvokeServer(myOffer)
			-- TradeUpdated re-renders everything.
		end)
	end
end

Remotes.TradeUpdated.OnClientEvent:Connect(function(state: any)
	if state == nil then
		-- Trade ended (completed or cancelled).
		inTrade = false
		myOffer = {}
		tradePage.Visible = false
		playerListPage.Visible = true
		rebuildPlayerList()
		return
	end
	if type(state) ~= "table" then
		return
	end

	inTrade = true
	window.Visible = true
	playerListPage.Visible = false
	tradePage.Visible = true

	title.Text = "TRADING WITH " .. string.upper(tostring(state.Partner))
	yourHeader.Text = ("YOUR OFFER (%d/%d)%s"):format(
		#state.YourOffer, MAX_PER_SIDE, state.YouConfirmed and "  ✓" or "")
	theirHeader.Text = ("THEIR OFFER (%d)%s"):format(
		#state.TheirOffer, state.TheyConfirmed and "  ✓" or "")
	fillOfferColumn(yourOfferColumn, state.YourOffer)
	fillOfferColumn(theirOfferColumn, state.TheirOffer)

	-- Keep the local offer mirror in sync with the server's validated version.
	myOffer = {}
	for _, pet in ipairs(state.YourOffer) do
		table.insert(myOffer, pet.UUID)
	end
	rebuildInventoryGrid()

	if state.Countdown then
		statusLabel.Text = ("BOTH CONFIRMED — trading in %d seconds..."):format(state.Countdown)
		confirmButton.Text = "LOCKED"
		confirmButton.BackgroundColor3 = Color3.fromRGB(80, 84, 100)
	elseif state.YouConfirmed then
		statusLabel.Text = "Waiting for " .. tostring(state.Partner) .. " to confirm..."
		confirmButton.Text = "CONFIRMED ✓"
		confirmButton.BackgroundColor3 = Color3.fromRGB(80, 84, 100)
	else
		statusLabel.Text = "Add pets, then confirm. Changing anything resets confirmations."
		confirmButton.Text = "CONFIRM"
		confirmButton.BackgroundColor3 = ACCENT
	end
end)

confirmButton.MouseButton1Click:Connect(function()
	if inTrade then
		Remotes.TradeConfirm:InvokeServer()
	end
end)

cancelButton.MouseButton1Click:Connect(function()
	if inTrade then
		Remotes.TradeCancel:InvokeServer()
	end
end)

--------------------------------------------------------------------------------
-- OPEN BUTTON (right side) + BINDINGS
--------------------------------------------------------------------------------
local openButton = Instance.new("TextButton")
openButton.AnchorPoint = Vector2.new(1, 0)
openButton.Size = UDim2.new(0, 110, 0, 44)
openButton.Position = UDim2.new(1, -12, 0, 140)
openButton.BackgroundColor3 = Color3.fromRGB(90, 160, 220)
openButton.Font = FONT
openButton.Text = "TRADE"
openButton.TextColor3 = Color3.new(1, 1, 1)
openButton.TextScaled = true
openButton.Parent = screenGui
round(openButton, 10)

openButton.MouseButton1Click:Connect(function()
	window.Visible = not window.Visible
	if window.Visible and not inTrade then
		playerListPage.Visible = true
		tradePage.Visible = false
		title.Text = "TRADING"
		rebuildPlayerList()
	end
end)

closeButton.MouseButton1Click:Connect(function()
	if inTrade then
		Remotes.TradeCancel:InvokeServer()
	end
	window.Visible = false
end)

Players.PlayerAdded:Connect(function()
	if window.Visible and not inTrade then
		rebuildPlayerList()
	end
end)
Players.PlayerRemoving:Connect(function()
	if window.Visible and not inTrade then
		task.defer(rebuildPlayerList)
	end
end)

Remotes.DataChanged.OnClientEvent:Connect(function(data: any)
	if type(data) == "table" then
		latestData = data
		if inTrade then
			rebuildInventoryGrid()
		end
	end
end)

task.spawn(function()
	local snapshot = Remotes.GetData:InvokeServer()
	if snapshot then
		latestData = snapshot
	end
end)

print("[TradeController] Ready.")
