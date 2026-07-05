--!strict
--------------------------------------------------------------------------------
-- PetInventoryController
-- StarterGui.MainHUD.PetInventoryController (LocalScript)
--
-- The pet management window:
--   * Lists every owned pet sorted by StatBonus (best first) with tier colors,
--     equipped state, and one-click equip/unequip via Remotes.EquipPet.
--   * "EQUIP BEST" auto-equips the top pets by StatBonus in one click.
--   * Live team summary: equipped count and total +damage from pets.
--
-- Rebuilds from every DataChanged snapshot, so hatches, boss pet drops and
-- equips made elsewhere appear instantly.
--------------------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local screenGui = script.Parent :: ScreenGui

local FONT = Enum.Font.FredokaOne
local PANEL_COLOR = Color3.fromRGB(32, 34, 48)
local CARD_COLOR = Color3.fromRGB(46, 49, 70)
local ACCENT = Color3.fromRGB(90, 200, 120)
local MAX_EQUIPPED = GameConfig.Combat.MaxEquippedPets

local tierColors: { [string]: Color3 } = {}
local tierRank: { [string]: number } = {}
for rank, tierInfo in ipairs(GameConfig.PetTiers) do
	tierColors[tierInfo.Tier] = tierInfo.Color
	tierRank[tierInfo.Tier] = rank
end

local latestData: any = nil

local function round(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

--------------------------------------------------------------------------------
-- WINDOW SHELL
--------------------------------------------------------------------------------
local window = Instance.new("Frame")
window.Name = "PetWindow"
window.AnchorPoint = Vector2.new(0.5, 0.5)
window.Position = UDim2.fromScale(0.5, 0.5)
window.Size = UDim2.new(0, 560, 0, 430)
window.BackgroundColor3 = PANEL_COLOR
window.Visible = false
window.Parent = screenGui
round(window, 16)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(0.6, 0, 0, 40)
title.Position = UDim2.new(0.2, 0, 0, 8)
title.BackgroundTransparency = 1
title.Font = FONT
title.Text = "MY PETS"
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

local summary = Instance.new("TextLabel")
summary.Size = UDim2.new(1, -160, 0, 26)
summary.Position = UDim2.new(0, 12, 0, 52)
summary.BackgroundTransparency = 1
summary.Font = FONT
summary.Text = "Equipped 0/" .. MAX_EQUIPPED
summary.TextColor3 = Color3.fromRGB(180, 185, 205)
summary.TextScaled = true
summary.TextXAlignment = Enum.TextXAlignment.Left
summary.Parent = window

local equipBest = Instance.new("TextButton")
equipBest.Size = UDim2.new(0, 130, 0, 30)
equipBest.Position = UDim2.new(1, -142, 0, 50)
equipBest.BackgroundColor3 = ACCENT
equipBest.Font = FONT
equipBest.Text = "EQUIP BEST"
equipBest.TextColor3 = Color3.new(1, 1, 1)
equipBest.TextScaled = true
equipBest.Parent = window
round(equipBest, 8)

local list = Instance.new("ScrollingFrame")
list.Size = UDim2.new(1, -24, 1, -100)
list.Position = UDim2.new(0, 12, 0, 88)
list.CanvasSize = UDim2.new(0, 0, 0, 0)
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.ScrollBarThickness = 6
list.BackgroundTransparency = 1
list.Parent = window

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 6)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = list

--------------------------------------------------------------------------------
-- LIST RENDERING
--------------------------------------------------------------------------------
local function isEquipped(uuid: string): boolean
	if not latestData or not latestData.EquippedPets then
		return false
	end
	for _, equippedUuid in ipairs(latestData.EquippedPets) do
		if equippedUuid == uuid then
			return true
		end
	end
	return false
end

local function rebuild()
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	if not latestData or not latestData.OwnedPets then
		return
	end

	-- Sort: equipped first, then by StatBonus desc, then tier rank desc.
	local pets = table.clone(latestData.OwnedPets)
	table.sort(pets, function(a, b)
		local aEquipped, bEquipped = isEquipped(a.UUID), isEquipped(b.UUID)
		if aEquipped ~= bEquipped then
			return aEquipped
		end
		if a.StatBonus ~= b.StatBonus then
			return a.StatBonus > b.StatBonus
		end
		return tostring(a.PetName) < tostring(b.PetName)
	end)

	local equippedCount = 0
	local equippedBonus = 0

	for index, pet in ipairs(pets) do
		local petConfig = GameConfig.Pets[pet.PetName]
		local tier = petConfig and petConfig.Tier or "Common"
		local equipped = isEquipped(pet.UUID)
		if equipped then
			equippedCount += 1
			equippedBonus += pet.StatBonus
		end

		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, -8, 0, 52)
		card.BackgroundColor3 = equipped and Color3.fromRGB(56, 74, 60) or CARD_COLOR
		card.LayoutOrder = index
		card.Parent = list
		round(card, 8)

		local stripe = Instance.new("Frame")
		stripe.Size = UDim2.new(0, 6, 1, 0)
		stripe.BackgroundColor3 = tierColors[tier] or Color3.new(1, 1, 1)
		stripe.BorderSizePixel = 0
		stripe.Parent = card
		round(stripe, 3)

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(0.45, 0, 0, 26)
		nameLabel.Position = UDim2.new(0, 16, 0, 4)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = FONT
		nameLabel.Text = tostring(pet.PetName)
		nameLabel.TextColor3 = tierColors[tier] or Color3.new(1, 1, 1)
		nameLabel.TextScaled = true
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Parent = card

		local statText = Instance.new("TextLabel")
		statText.Size = UDim2.new(0.45, 0, 0, 18)
		statText.Position = UDim2.new(0, 16, 0, 30)
		statText.BackgroundTransparency = 1
		statText.Font = FONT
		statText.Text = ("%s  •  +%d dmg"):format(tier, pet.StatBonus)
		statText.TextColor3 = Color3.fromRGB(180, 185, 205)
		statText.TextScaled = true
		statText.TextXAlignment = Enum.TextXAlignment.Left
		statText.Parent = card

		local action = Instance.new("TextButton")
		action.Size = UDim2.new(0, 110, 0, 36)
		action.Position = UDim2.new(1, -122, 0.5, -18)
		action.BackgroundColor3 = equipped and Color3.fromRGB(200, 120, 60) or ACCENT
		action.Font = FONT
		action.Text = equipped and "UNEQUIP" or "EQUIP"
		action.TextColor3 = Color3.new(1, 1, 1)
		action.TextScaled = true
		action.Parent = card
		round(action, 8)

		action.MouseButton1Click:Connect(function()
			action.Active = false
			Remotes.EquipPet:InvokeServer(pet.UUID)
			action.Active = true
			-- DataChanged will rebuild the list.
		end)
	end

	summary.Text = ("Equipped %d/%d  •  +%d dmg from pets  •  %d owned")
		:format(equippedCount, MAX_EQUIPPED, equippedBonus, #pets)
end

equipBest.MouseButton1Click:Connect(function()
	if not latestData or not latestData.OwnedPets then
		return
	end
	equipBest.Active = false

	-- Unequip everything, then equip the top MAX_EQUIPPED by StatBonus.
	local current = latestData.EquippedPets or {}
	for _, uuid in ipairs(table.clone(current)) do
		Remotes.EquipPet:InvokeServer(uuid) -- toggle off
	end

	local pets = table.clone(latestData.OwnedPets)
	table.sort(pets, function(a, b)
		return a.StatBonus > b.StatBonus
	end)
	for i = 1, math.min(MAX_EQUIPPED, #pets) do
		Remotes.EquipPet:InvokeServer(pets[i].UUID)
	end
	equipBest.Active = true
end)

--------------------------------------------------------------------------------
-- OPEN BUTTON + DATA BINDING
--------------------------------------------------------------------------------
local openButton = Instance.new("TextButton")
openButton.Size = UDim2.new(0, 110, 0, 44)
openButton.Position = UDim2.new(0, 12, 0, 244)
openButton.BackgroundColor3 = Color3.fromRGB(120, 140, 255)
openButton.Font = FONT
openButton.Text = "PETS"
openButton.TextColor3 = Color3.new(1, 1, 1)
openButton.TextScaled = true
openButton.Parent = screenGui
round(openButton, 10)

openButton.MouseButton1Click:Connect(function()
	window.Visible = not window.Visible
	if window.Visible then
		rebuild()
	end
end)

closeButton.MouseButton1Click:Connect(function()
	window.Visible = false
end)

Remotes.DataChanged.OnClientEvent:Connect(function(data: any)
	if type(data) == "table" then
		latestData = data
		if window.Visible then
			rebuild()
		end
	end
end)

task.spawn(function()
	local snapshot = Remotes.GetData:InvokeServer()
	if snapshot then
		latestData = snapshot
	end
end)

print("[PetInventoryController] Ready.")
