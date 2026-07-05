--!strict
--------------------------------------------------------------------------------
-- PetFollower
-- StarterPlayer.StarterPlayerScripts.PetFollower (LocalScript)
--
-- Renders every player's equipped pets as floating followers. The server
-- publishes each player's loadout as the "EquippedPetNames" Player attribute
-- (comma-separated, set by DataManager), so this runs with ZERO extra network
-- traffic per frame — all movement is computed locally:
--
--   * Pets hold formation slots in an arc behind their owner.
--   * Smooth spring-lag follow + idle bob + face-forward orientation.
--   * Designer meshes from ReplicatedStorage.PetMeshes[<Mesh name>] when
--     present, tier-colored glowing fallback primitives otherwise.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))

local ATTRIBUTE = "EquippedPetNames"
local FOLLOW_LERP = 8          -- higher = snappier follow
local ARC_RADIUS = 5           -- studs behind the owner
local ARC_SPREAD = math.rad(80)
local BOB_HEIGHT = 0.4
local BOB_SPEED = 3

local tierColors: { [string]: Color3 } = {}
for _, tierInfo in ipairs(GameConfig.PetTiers) do
	tierColors[tierInfo.Tier] = tierInfo.Color
end

local petMeshFolder = ReplicatedStorage:FindFirstChild("PetMeshes")

-- [Player] = { Models = {BasePart}, Names = {string} }
local followers: { [Player]: any } = {}

local container = Instance.new("Folder")
container.Name = "LocalPetFollowers"
container.Parent = workspace.CurrentCamera

--------------------------------------------------------------------------------
-- MODEL CONSTRUCTION
--------------------------------------------------------------------------------
local function buildPetModel(entry: string): BasePart
	-- Entry format: "PetName" or "PetName:Golden" / "PetName:Rainbow"
	local parts = string.split(entry, ":")
	local petName = parts[1]
	local variant = parts[2] or "Normal"
	local petConfig = GameConfig.Pets[petName]
	local template = petMeshFolder and petConfig and petMeshFolder:FindFirstChild(petConfig.Mesh)

	local part: BasePart
	if template and template:IsA("BasePart") then
		part = template:Clone() :: BasePart
	else
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Ball
		p.Material = Enum.Material.Neon
		p.Size = Vector3.new(1.6, 1.6, 1.6)
		p.Color = (petConfig and tierColors[petConfig.Tier]) or Color3.fromRGB(200, 200, 200)
		part = p
	end

	part.Name = "PetFollower_" .. petName
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false

	-- Fusion variants override the body color; Rainbow hue-cycles per frame.
	if variant == "Golden" then
		part.Color = GameConfig.Fusion.Variants.Golden.Color
		part.Material = Enum.Material.Neon
	elseif variant == "Rainbow" then
		part.Material = Enum.Material.Neon
		part:SetAttribute("RainbowPet", true)
	end

	-- Name tag with tier color.
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(5, 1)
	billboard.StudsOffset = Vector3.new(0, 1.6, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 60
	local tag = Instance.new("TextLabel")
	tag.Size = UDim2.fromScale(1, 1)
	tag.BackgroundTransparency = 1
	tag.Font = Enum.Font.FredokaOne
	tag.Text = if variant ~= "Normal" then (variant .. " " .. petName) else petName
	tag.TextScaled = true
	tag.TextColor3 = if variant == "Golden" then GameConfig.Fusion.Variants.Golden.Color
		else (petConfig and tierColors[petConfig.Tier]) or Color3.new(1, 1, 1)
	tag.TextStrokeTransparency = 0.4
	tag.Parent = billboard
	billboard.Parent = part

	-- Mythic pets get a permanent sparkle trail.
	if petConfig and petConfig.Tier == "Mythic" then
		local light = Instance.new("PointLight")
		light.Color = tierColors.Mythic
		light.Range = 8
		light.Brightness = 2
		light.Parent = part
	end

	part.Parent = container
	return part
end

--------------------------------------------------------------------------------
-- LOADOUT SYNC
--------------------------------------------------------------------------------
local function rebuildFor(player: Player)
	local state = followers[player]
	if state then
		for _, model in ipairs(state.Models) do
			model:Destroy()
		end
	end

	local csv = player:GetAttribute(ATTRIBUTE)
	if type(csv) ~= "string" or csv == "" then
		followers[player] = nil
		return
	end

	local names = string.split(csv, ",")
	local models = {}
	for _, entry in ipairs(names) do
		local petName = string.split(entry, ":")[1]
		if GameConfig.Pets[petName] then
			table.insert(models, buildPetModel(entry))
		end
	end
	followers[player] = { Models = models, Names = names }
end

local function watchPlayer(player: Player)
	rebuildFor(player)
	player:GetAttributeChangedSignal(ATTRIBUTE):Connect(function()
		rebuildFor(player)
	end)
end

Players.PlayerAdded:Connect(watchPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	watchPlayer(player)
end

Players.PlayerRemoving:Connect(function(player)
	local state = followers[player]
	if state then
		for _, model in ipairs(state.Models) do
			model:Destroy()
		end
		followers[player] = nil
	end
end)

--------------------------------------------------------------------------------
-- MOVEMENT
--------------------------------------------------------------------------------
RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	local alpha = math.clamp(FOLLOW_LERP * dt, 0, 1)
	local rainbowHue = (now * 0.5) % 1

	for player, state in pairs(followers) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			continue
		end

		local count = #state.Models
		for index, model in ipairs(state.Models) do
			-- Formation slot: arc centered directly behind the owner.
			local fraction = if count == 1 then 0.5 else (index - 1) / (count - 1)
			local angle = (fraction - 0.5) * ARC_SPREAD
			local offset = CFrame.Angles(0, angle, 0) * Vector3.new(0, 0, ARC_RADIUS)
			local slot = root.CFrame:PointToWorldSpace(offset)

			local bob = math.sin(now * BOB_SPEED + index * 1.3) * BOB_HEIGHT
			local goal = slot + Vector3.new(0, 1.5 + bob, 0)

			if model:GetAttribute("RainbowPet") then
				model.Color = Color3.fromHSV((rainbowHue + index * 0.15) % 1, 0.85, 1)
			end

			local newPosition = model.Position:Lerp(goal, alpha)
			local look = root.Position - newPosition
			local flatLook = Vector3.new(look.X, 0, look.Z)
			if flatLook.Magnitude > 0.05 then
				model.CFrame = CFrame.lookAt(newPosition, newPosition + flatLook.Unit)
			else
				model.CFrame = CFrame.new(newPosition)
			end
		end
	end
end)

print("[PetFollower] Ready.")
