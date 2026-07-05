--!strict
--------------------------------------------------------------------------------
-- QuestController
-- StarterGui.MainHUD.QuestController (LocalScript)
--
-- One window, two session drivers:
--   * DAILY QUESTS — live progress bars from the DataChanged snapshot's
--     DailyQuests table, CLAIM buttons via Remotes.ClaimQuest. The open
--     button glows green whenever any completed quest is unclaimed.
--   * PLAYTIME CHESTS — a 5→60 minute reward track timed locally against
--     the session start and claimed via Remotes.ClaimPlaytime (the server
--     re-validates elapsed time, so the local clock is display-only).
--------------------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local screenGui = script.Parent :: ScreenGui

local FONT = Enum.Font.FredokaOne
local PANEL_COLOR = Color3.fromRGB(32, 34, 48)
local CARD_COLOR = Color3.fromRGB(46, 49, 70)
local ACCENT = Color3.fromRGB(90, 200, 120)
local GOLD = Color3.fromRGB(255, 210, 70)

local sessionStartClock = os.clock() -- local session timer for chest display

local latestData: any = nil
local claimedChests: { [number]: boolean } = {}

local function round(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function rewardText(entry: any): string
	local parts = {}
	if entry.Gold then table.insert(parts, entry.Gold .. " Gold") end
	if entry.Gems then table.insert(parts, entry.Gems .. " Gems") end
	if entry.EggRoll then table.insert(parts, "FREE " .. entry.EggRoll) end
	return table.concat(parts, " + ")
end

--------------------------------------------------------------------------------
-- WINDOW SHELL
--------------------------------------------------------------------------------
local window = Instance.new("Frame")
window.Name = "QuestWindow"
window.AnchorPoint = Vector2.new(0.5, 0.5)
window.Position = UDim2.fromScale(0.5, 0.5)
window.Size = UDim2.new(0, 560, 0, 460)
window.BackgroundColor3 = PANEL_COLOR
window.Visible = false
window.Parent = screenGui
round(window, 16)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(0.7, 0, 0, 40)
title.Position = UDim2.new(0.15, 0, 0, 8)
title.BackgroundTransparency = 1
title.Font = FONT
title.Text = "QUESTS & REWARDS"
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

local list = Instance.new("ScrollingFrame")
list.Size = UDim2.new(1, -24, 1, -64)
list.Position = UDim2.new(0, 12, 0, 52)
list.CanvasSize = UDim2.new(0, 0, 0, 0)
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.ScrollBarThickness = 6
list.BackgroundTransparency = 1
list.Parent = window

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 6)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = list

local function sectionHeader(text: string, order: number)
	local header = Instance.new("TextLabel")
	header.Size = UDim2.new(1, -8, 0, 30)
	header.BackgroundTransparency = 1
	header.Font = FONT
	header.Text = text
	header.TextColor3 = GOLD
	header.TextScaled = true
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.LayoutOrder = order
	header.Parent = list
end

--------------------------------------------------------------------------------
-- RENDER
--------------------------------------------------------------------------------
local openButton -- forward-declared for the glow refresh

local function rebuild()
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("Frame") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end

	local order = 0
	local anyClaimable = false

	-- SECTION 1: DAILY QUESTS -----------------------------------------------
	order += 1
	sectionHeader("DAILY QUESTS (reset at midnight UTC)", order)

	local quests = latestData and latestData.DailyQuests and latestData.DailyQuests.Quests or {}
	if #quests == 0 then
		order += 1
		local empty = Instance.new("TextLabel")
		empty.Size = UDim2.new(1, -8, 0, 28)
		empty.BackgroundTransparency = 1
		empty.Font = FONT
		empty.Text = "Loading today's quests..."
		empty.TextColor3 = Color3.fromRGB(180, 185, 205)
		empty.TextScaled = true
		empty.LayoutOrder = order
		empty.Parent = list
	end

	for questIndex, quest in ipairs(quests) do
		order += 1
		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, -8, 0, 64)
		card.BackgroundColor3 = quest.Claimed and Color3.fromRGB(38, 40, 52) or CARD_COLOR
		card.LayoutOrder = order
		card.Parent = list
		round(card, 10)

		local questLabel = Instance.new("TextLabel")
		questLabel.Size = UDim2.new(0.6, 0, 0, 24)
		questLabel.Position = UDim2.new(0, 12, 0, 6)
		questLabel.BackgroundTransparency = 1
		questLabel.Font = FONT
		questLabel.Text = tostring(quest.Text)
		questLabel.TextColor3 = quest.Claimed and Color3.fromRGB(130, 135, 150) or Color3.new(1, 1, 1)
		questLabel.TextScaled = true
		questLabel.TextXAlignment = Enum.TextXAlignment.Left
		questLabel.Parent = card

		local progressBack = Instance.new("Frame")
		progressBack.Size = UDim2.new(0.6, 0, 0, 12)
		progressBack.Position = UDim2.new(0, 12, 0, 36)
		progressBack.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
		progressBack.BorderSizePixel = 0
		progressBack.Parent = card
		round(progressBack, 6)

		local ratio = math.clamp((tonumber(quest.Progress) or 0) / math.max(tonumber(quest.Goal) or 1, 1), 0, 1)
		local progressFill = Instance.new("Frame")
		progressFill.Size = UDim2.fromScale(ratio, 1)
		progressFill.BackgroundColor3 = ratio >= 1 and ACCENT or GOLD
		progressFill.BorderSizePixel = 0
		progressFill.Parent = progressBack
		round(progressFill, 6)

		local progressText = Instance.new("TextLabel")
		progressText.Size = UDim2.new(0.6, 0, 0, 12)
		progressText.Position = UDim2.new(0, 12, 0, 49)
		progressText.BackgroundTransparency = 1
		progressText.Font = FONT
		progressText.Text = ("%d / %d  •  %s"):format(
			tonumber(quest.Progress) or 0, tonumber(quest.Goal) or 0, rewardText(quest))
		progressText.TextColor3 = Color3.fromRGB(180, 185, 205)
		progressText.TextScaled = true
		progressText.TextXAlignment = Enum.TextXAlignment.Left
		progressText.Parent = card

		local claim = Instance.new("TextButton")
		claim.Size = UDim2.new(0, 110, 0, 40)
		claim.Position = UDim2.new(1, -122, 0.5, -20)
		claim.Font = FONT
		claim.TextColor3 = Color3.new(1, 1, 1)
		claim.TextScaled = true
		claim.Parent = card
		round(claim, 8)

		if quest.Claimed then
			claim.Text = "DONE"
			claim.BackgroundColor3 = Color3.fromRGB(80, 84, 100)
			claim.AutoButtonColor = false
		elseif ratio >= 1 then
			claim.Text = "CLAIM"
			claim.BackgroundColor3 = ACCENT
			anyClaimable = true
			claim.MouseButton1Click:Connect(function()
				claim.Active = false
				Remotes.ClaimQuest:InvokeServer(questIndex)
				claim.Active = true
			end)
		else
			claim.Text = "..."
			claim.BackgroundColor3 = Color3.fromRGB(80, 84, 100)
			claim.AutoButtonColor = false
		end
	end

	-- SECTION 2: PLAYTIME CHESTS ----------------------------------------------
	order += 1
	sectionHeader("PLAYTIME CHESTS (this session)", order)

	local elapsedMinutes = (os.clock() - sessionStartClock) / 60
	for chestIndex, chest in ipairs(GameConfig.PlaytimeRewards) do
		order += 1
		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, -8, 0, 44)
		card.BackgroundColor3 = claimedChests[chestIndex] and Color3.fromRGB(38, 40, 52) or CARD_COLOR
		card.LayoutOrder = order
		card.Parent = list
		round(card, 10)

		local chestLabel = Instance.new("TextLabel")
		chestLabel.Size = UDim2.new(0.62, 0, 1, 0)
		chestLabel.Position = UDim2.new(0, 12, 0, 0)
		chestLabel.BackgroundTransparency = 1
		chestLabel.Font = FONT
		chestLabel.Text = ("%d min  •  %s"):format(chest.Minutes, rewardText(chest))
		chestLabel.TextColor3 = claimedChests[chestIndex]
			and Color3.fromRGB(130, 135, 150) or Color3.new(1, 1, 1)
		chestLabel.TextScaled = true
		chestLabel.TextXAlignment = Enum.TextXAlignment.Left
		chestLabel.Parent = card

		local claim = Instance.new("TextButton")
		claim.Size = UDim2.new(0, 110, 0, 32)
		claim.Position = UDim2.new(1, -122, 0.5, -16)
		claim.Font = FONT
		claim.TextColor3 = Color3.new(1, 1, 1)
		claim.TextScaled = true
		claim.Parent = card
		round(claim, 8)

		if claimedChests[chestIndex] then
			claim.Text = "DONE"
			claim.BackgroundColor3 = Color3.fromRGB(80, 84, 100)
			claim.AutoButtonColor = false
		elseif elapsedMinutes >= chest.Minutes then
			claim.Text = "CLAIM"
			claim.BackgroundColor3 = GOLD
			claim.TextColor3 = Color3.fromRGB(40, 30, 0)
			anyClaimable = true
			claim.MouseButton1Click:Connect(function()
				claim.Active = false
				local success = Remotes.ClaimPlaytime:InvokeServer(chestIndex)
				if success then
					claimedChests[chestIndex] = true
				end
				claim.Active = true
				rebuild()
			end)
		else
			local remaining = chest.Minutes - elapsedMinutes
			claim.Text = ("%dm"):format(math.ceil(remaining))
			claim.BackgroundColor3 = Color3.fromRGB(80, 84, 100)
			claim.AutoButtonColor = false
		end
	end

	-- Open-button glow when anything is claimable.
	if openButton then
		if anyClaimable then
			openButton.BackgroundColor3 = ACCENT
		else
			openButton.BackgroundColor3 = Color3.fromRGB(160, 110, 220)
		end
	end
end

--------------------------------------------------------------------------------
-- OPEN BUTTON + BINDINGS
--------------------------------------------------------------------------------
openButton = Instance.new("TextButton")
openButton.Size = UDim2.new(0, 110, 0, 44)
openButton.Position = UDim2.new(0, 12, 0, 452)
openButton.BackgroundColor3 = Color3.fromRGB(160, 110, 220)
openButton.Font = FONT
openButton.Text = "QUESTS"
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
		else
			rebuild() -- still refresh so the button glow stays current
			-- (rebuild on a hidden window is cheap: ~10 frames)
		end
	end
end)

task.spawn(function()
	local snapshot = Remotes.GetData:InvokeServer()
	if snapshot then
		latestData = snapshot
		rebuild()
	end
end)

-- Chest timers tick down while the window is open (and keep the glow honest).
task.spawn(function()
	while true do
		task.wait(15)
		rebuild()
	end
end)

print("[QuestController] Ready.")
