--!strict
--------------------------------------------------------------------------------
-- FusionController
-- StarterGui.MainHUD.FusionController (LocalScript)
--
-- The fusion lab. Groups the player's pets by (name, variant) and lists every
-- possible fusion:
--   * 5x Normal <pet> + gems -> 1x Golden  (StatBonus x2.5)
--   * 5x Golden <pet> + gems -> 1x Rainbow (StatBonus x6.25)
-- Rows show live counts (3/5 etc.); the FUSE button only lights up when the
-- recipe is satisfied. The result plays through the HatchAnimator cutscene.
--
-- Opens from a FUSE button injected into the Pet window's header.
--------------------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

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

--------------------------------------------------------------------------------
-- WINDOW
--------------------------------------------------------------------------------
local window = Instance.new("Frame")
window.Name = "FusionWindow"
window.AnchorPoint = Vector2.new(0.5, 0.5)
window.Position = UDim2.fromScale(0.5, 0.5)
window.Size = UDim2.new(0, 560, 0, 420)
window.BackgroundColor3 = PANEL_COLOR
window.Visible = false
window.Parent = screenGui
round(window, 16)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(0.7, 0, 0, 40)
title.Position = UDim2.new(0.15, 0, 0, 8)
title.BackgroundTransparency = 1
title.Font = FONT
title.Text = "FUSION LAB"
title.TextColor3 = GameConfig.Fusion.Variants.Golden.Color
title.TextScaled = true
title.Parent = window

local subtitle = Instance.new("TextLabel")
subtitle.Size = UDim2.new(1, -24, 0, 22)
subtitle.Position = UDim2.new(0, 12, 0, 48)
subtitle.BackgroundTransparency = 1
subtitle.Font = FONT
subtitle.Text = ("Fuse %d identical pets + Gems into a stronger variant!")
	:format(GameConfig.Fusion.Required)
subtitle.TextColor3 = Color3.fromRGB(180, 185, 205)
subtitle.TextScaled = true
subtitle.Parent = window

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

local list = Instance.new("ScrollingFrame")
list.Size = UDim2.new(1, -24, 1, -86)
list.Position = UDim2.new(0, 12, 0, 74)
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
-- RECIPE LIST
--------------------------------------------------------------------------------
local function rebuild()
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	if not latestData or not latestData.OwnedPets then
		return
	end

	-- Count owned pets by "petName|variant".
	local counts: { [string]: number } = {}
	for _, pet in ipairs(latestData.OwnedPets) do
		local key = pet.PetName .. "|" .. (pet.Variant or "Normal")
		counts[key] = (counts[key] or 0) + 1
	end

	-- One row per possible recipe, sorted: ready first, then by progress.
	local rows = {}
	for petName, petConfig in pairs(GameConfig.Pets) do
		for variantName, variantConfig in pairs(GameConfig.Fusion.Variants) do
			local have = counts[petName .. "|" .. variantConfig.From] or 0
			if have > 0 then
				table.insert(rows, {
					PetName = petName,
					Tier = petConfig.Tier,
					Variant = variantName,
					VariantConfig = variantConfig,
					Have = have,
					Ready = have >= GameConfig.Fusion.Required,
					ResultStat = math.floor(petConfig.StatBonus * variantConfig.Multiplier),
				})
			end
		end
	end
	table.sort(rows, function(a, b)
		if a.Ready ~= b.Ready then
			return a.Ready
		end
		if a.Have ~= b.Have then
			return a.Have > b.Have
		end
		return a.PetName < b.PetName
	end)

	if #rows == 0 then
		local empty = Instance.new("Frame")
		empty.Size = UDim2.new(1, -8, 0, 44)
		empty.BackgroundColor3 = CARD_COLOR
		empty.Parent = list
		round(empty, 8)
		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.Font = FONT
		text.Text = "Hatch more pets to discover fusion recipes!"
		text.TextColor3 = Color3.fromRGB(180, 185, 205)
		text.TextScaled = true
		text.Parent = empty
		return
	end

	for order, row in ipairs(rows) do
		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, -8, 0, 56)
		card.BackgroundColor3 = CARD_COLOR
		card.LayoutOrder = order
		card.Parent = list
		round(card, 10)

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(0.55, 0, 0, 26)
		nameLabel.Position = UDim2.new(0, 12, 0, 4)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = FONT
		nameLabel.Text = ("%s -> %s %s"):format(row.PetName, row.Variant, row.PetName)
		nameLabel.TextColor3 = row.VariantConfig.Color
		nameLabel.TextScaled = true
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Parent = card

		local detail = Instance.new("TextLabel")
		detail.Size = UDim2.new(0.55, 0, 0, 20)
		detail.Position = UDim2.new(0, 12, 0, 32)
		detail.BackgroundTransparency = 1
		detail.Font = FONT
		detail.Text = ("%d/%d owned  •  %d Gems  •  result +%d dmg"):format(
			math.min(row.Have, GameConfig.Fusion.Required), GameConfig.Fusion.Required,
			row.VariantConfig.GemCost, row.ResultStat)
		detail.TextColor3 = Color3.fromRGB(180, 185, 205)
		detail.TextScaled = true
		detail.TextXAlignment = Enum.TextXAlignment.Left
		detail.Parent = card

		local fuse = Instance.new("TextButton")
		fuse.Size = UDim2.new(0, 110, 0, 40)
		fuse.Position = UDim2.new(1, -122, 0.5, -20)
		fuse.Font = FONT
		fuse.TextScaled = true
		fuse.Parent = card
		round(fuse, 8)

		if row.Ready then
			fuse.Text = "FUSE"
			fuse.BackgroundColor3 = ACCENT
			fuse.TextColor3 = Color3.new(1, 1, 1)
			fuse.MouseButton1Click:Connect(function()
				fuse.Active = false
				local _, err = Remotes.FusePets:InvokeServer(row.PetName, row.Variant)
				fuse.Active = true
				if type(err) == "string" then
					detail.Text = err
					detail.TextColor3 = Color3.fromRGB(255, 90, 90)
				end
				-- DataChanged rebuilds the list on success.
			end)
		else
			fuse.Text = ("%d/%d"):format(row.Have, GameConfig.Fusion.Required)
			fuse.BackgroundColor3 = Color3.fromRGB(80, 84, 100)
			fuse.TextColor3 = Color3.new(1, 1, 1)
			fuse.AutoButtonColor = false
		end
	end
end

--------------------------------------------------------------------------------
-- OPEN BUTTON (injected into the Pet window header) + BINDINGS
--------------------------------------------------------------------------------
task.spawn(function()
	local petWindow = screenGui:WaitForChild("PetWindow", 30)
	if not petWindow then
		return
	end
	local openButton = Instance.new("TextButton")
	openButton.Size = UDim2.new(0, 90, 0, 30)
	openButton.Position = UDim2.new(1, -240, 0, 50)
	openButton.BackgroundColor3 = GameConfig.Fusion.Variants.Golden.Color
	openButton.Font = FONT
	openButton.Text = "FUSE"
	openButton.TextColor3 = Color3.fromRGB(60, 40, 0)
	openButton.TextScaled = true
	openButton.Parent = petWindow
	round(openButton, 8)
	openButton.MouseButton1Click:Connect(function()
		window.Visible = not window.Visible
		if window.Visible then
			(petWindow :: Frame).Visible = false
			rebuild()
		end
	end)
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

print("[FusionController] Ready.")
