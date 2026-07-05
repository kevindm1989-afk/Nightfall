--!strict
--------------------------------------------------------------------------------
-- LootAnimator
-- StarterPlayer.StarterPlayerScripts.LootAnimator (LocalScript)
--
-- Listens to ReplicatedStorage.Remotes.LootDropped (fired by CoreEngine when a
-- node, enemy or boss breaks) and renders purely-cosmetic 3D loot pickups:
--
--   1. Burst: items scatter outward from the break point with a random impulse.
--   2. Hover: a short bobbing pause so the drop reads visually.
--   3. Vacuum: each item flies into the player's HumanoidRootPart along a
--      smooth cubic Bezier curve, re-targeted every frame so it always lands
--      on the moving character, then pops with a scale-down + sound.
--
-- All parts are client-side only (created locally, never replicated), so 20
-- players breaking nodes costs the server nothing.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local localPlayer = Players.LocalPlayer

--------------------------------------------------------------------------------
-- TUNING
--------------------------------------------------------------------------------
local BURST_RADIUS = 6          -- studs of horizontal scatter on break
local BURST_HEIGHT = 4          -- how high items pop on break
local BURST_TIME = 0.35         -- seconds for the scatter arc
local HOVER_TIME = 0.45         -- seconds of bobbing before vacuum
local VACUUM_TIME_MIN = 0.45    -- seconds along the Bezier (randomized per item)
local VACUUM_TIME_MAX = 0.75
local MAX_LIVE_ITEMS = 60       -- hard cap on simultaneously animating items
local ITEM_SIZE = Vector3.new(1.2, 1.2, 1.2)

local COLLECT_SOUND_ID = "rbxassetid://402143943"   -- coin chime
local RARE_SOUND_ID = "rbxassetid://12222084"       -- sparkle sting

local TYPE_COLORS: { [string]: Color3 } = {
	Gold = Color3.fromRGB(255, 200, 40),
	Gems = Color3.fromRGB(90, 220, 255),
	Weapon = Color3.fromRGB(200, 200, 210),
	Egg = Color3.fromRGB(250, 240, 200),
	Pet = Color3.fromRGB(255, 130, 220),
}

local rng = Random.new()
local liveItemCount = 0

-- Optional designer-made loot meshes live in ReplicatedStorage.LootMeshes,
-- named by loot item (e.g. "Gold_Small"). Missing meshes fall back to a
-- glowing primitive so the system works before art is imported.
local lootMeshFolder = ReplicatedStorage:FindFirstChild("LootMeshes")

--------------------------------------------------------------------------------
-- BEZIER MATH
-- Cubic Bezier: B(t) = (1-t)^3 P0 + 3(1-t)^2 t P1 + 3(1-t) t^2 P2 + t^3 P3
--------------------------------------------------------------------------------
local function cubicBezier(t: number, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3): Vector3
	local u = 1 - t
	return (u * u * u) * p0
		+ (3 * u * u * t) * p1
		+ (3 * u * t * t) * p2
		+ (t * t * t) * p3
end

local function easeInOutQuad(t: number): number
	if t < 0.5 then
		return 2 * t * t
	end
	return 1 - ((-2 * t + 2) ^ 2) / 2
end

--------------------------------------------------------------------------------
-- ITEM CONSTRUCTION
--------------------------------------------------------------------------------
local function buildLootPart(drop: any): BasePart
	local template = lootMeshFolder and lootMeshFolder:FindFirstChild(drop.Item)
	local part: BasePart

	if template and template:IsA("BasePart") then
		part = template:Clone() :: BasePart
	else
		local p = Instance.new("Part")
		p.Shape = if drop.Type == "Gold" then Enum.PartType.Cylinder else Enum.PartType.Ball
		p.Material = Enum.Material.Neon
		p.Color = TYPE_COLORS[drop.Type] or Color3.fromRGB(255, 255, 255)
		part = p
	end

	part.Size = ITEM_SIZE
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Name = "Loot_" .. tostring(drop.Item)

	local sparkle = Instance.new("PointLight")
	sparkle.Color = TYPE_COLORS[drop.Type] or Color3.new(1, 1, 1)
	sparkle.Range = 6
	sparkle.Brightness = 1.4
	sparkle.Parent = part

	return part
end

local function playCollectSound(drop: any, atPart: BasePart)
	local sound = Instance.new("Sound")
	sound.SoundId = (drop.Type == "Pet" or drop.Type == "Weapon") and RARE_SOUND_ID or COLLECT_SOUND_ID
	sound.Volume = 0.5
	sound.PlaybackSpeed = rng:NextNumber(0.95, 1.1)
	sound.Parent = atPart
	sound:Play()
	Debris:AddItem(sound, 3)
end

--------------------------------------------------------------------------------
-- PER-ITEM ANIMATION PIPELINE
--------------------------------------------------------------------------------
local function animateItem(drop: any, origin: Vector3, delaySeconds: number)
	if liveItemCount >= MAX_LIVE_ITEMS then
		return
	end
	liveItemCount += 1

	task.delay(delaySeconds, function()
		local part = buildLootPart(drop)
		part.Position = origin
		part.Parent = workspace.CurrentCamera -- camera container = never replicated

		-- Phase 1: burst outward along a small parabola.
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = rng:NextNumber(BURST_RADIUS * 0.4, BURST_RADIUS)
		local landing = origin + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		local apex = origin:Lerp(landing, 0.5) + Vector3.new(0, BURST_HEIGHT, 0)

		local elapsed = 0
		while elapsed < BURST_TIME do
			local dt = RunService.RenderStepped:Wait()
			elapsed += dt
			local t = math.clamp(elapsed / BURST_TIME, 0, 1)
			-- Quadratic arc expressed as a degenerate cubic (P1 = P2 = apex).
			part.Position = cubicBezier(t, origin, apex, apex, landing)
			part.CFrame = CFrame.new(part.Position) * CFrame.Angles(0, t * math.pi * 2, 0)
		end

		-- Phase 2: hover bob.
		elapsed = 0
		while elapsed < HOVER_TIME do
			local dt = RunService.RenderStepped:Wait()
			elapsed += dt
			local bob = math.sin(elapsed * 8) * 0.25
			part.CFrame = CFrame.new(landing + Vector3.new(0, 0.5 + bob, 0))
				* CFrame.Angles(0, elapsed * 3, 0)
		end

		-- Phase 3: vacuum into the character along a cubic Bezier that
		-- re-reads the HumanoidRootPart position every frame.
		local vacuumTime = rng:NextNumber(VACUUM_TIME_MIN, VACUUM_TIME_MAX)
		local start = part.Position
		local sideSwing = Vector3.new(
			rng:NextNumber(-4, 4),
			rng:NextNumber(2, 6),
			rng:NextNumber(-4, 4))

		elapsed = 0
		while elapsed < vacuumTime do
			local dt = RunService.RenderStepped:Wait()
			elapsed += dt

			local character = localPlayer.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not root then
				break
			end

			local target = root.Position
			local t = easeInOutQuad(math.clamp(elapsed / vacuumTime, 0, 1))
			local control1 = start + sideSwing
			local control2 = target + Vector3.new(0, 3, 0)

			part.Position = cubicBezier(t, start, control1, control2, target)
			part.Size = ITEM_SIZE * (1 - 0.5 * t)
			part.CFrame = CFrame.new(part.Position) * CFrame.Angles(t * 4, t * 6, 0)
		end

		-- Pop + sound at the character.
		playCollectSound(drop, part)
		local pop = TweenService:Create(part,
			TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.In),
			{ Size = Vector3.new(0.05, 0.05, 0.05), Transparency = 1 })
		pop:Play()
		pop.Completed:Wait()
		part:Destroy()
		liveItemCount -= 1
	end)
end

--------------------------------------------------------------------------------
-- EVENT ENTRY POINT
-- Payload: { Origin = Vector3, Drops = { {Item, Type, Amount?}, ... } }
--------------------------------------------------------------------------------
Remotes.LootDropped.OnClientEvent:Connect(function(payload: any)
	if typeof(payload) ~= "table" or typeof(payload.Origin) ~= "Vector3" then
		return
	end
	local drops = payload.Drops
	if typeof(drops) ~= "table" then
		return
	end

	for index, drop in ipairs(drops) do
		if typeof(drop) == "table" and drop.Item ~= nil and drop.Type ~= nil then
			-- Gold bursts render multiple coins for juice; other types render one.
			local visualCount = 1
			if drop.Type == "Gold" then
				visualCount = math.clamp(math.floor((drop.Amount or 1) / 25) + 3, 3, 8)
			end
			for i = 1, visualCount do
				animateItem(drop, payload.Origin, (index - 1) * 0.05 + (i - 1) * 0.04)
			end
		end
	end
end)

print("[LootAnimator] Ready.")
