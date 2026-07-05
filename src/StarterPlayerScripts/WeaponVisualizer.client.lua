--!strict
--------------------------------------------------------------------------------
-- WeaponVisualizer
-- StarterPlayer.StarterPlayerScripts.WeaponVisualizer (LocalScript)
--
-- Renders every player's equipped weapon in their right hand, driven by the
-- replicated "EquippedWeaponName" Player attribute (published by DataManager).
-- Like PetFollower, this is pure client-side presentation:
--
--   * Designer models from ReplicatedStorage.WeaponMeshes[<weapon key>] when
--     present; otherwise a procedurally-built neon blade whose length and
--     color scale with the weapon's zone tier, so progression is visible at
--     a glance even before art is imported.
--   * The LOCAL player's blade plays a quick slash tween on every landed hit
--     (Remotes.TargetDamaged), synced to the server-accepted swing.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local localPlayer = Players.LocalPlayer
local ATTRIBUTE = "EquippedWeaponName"

local weaponMeshFolder = ReplicatedStorage:FindFirstChild("WeaponMeshes")

local ZONE_BLADE_COLORS: { [number]: Color3 } = {
	[1] = Color3.fromRGB(150, 110, 70),   -- forest woods/iron
	[2] = Color3.fromRGB(255, 100, 40),   -- magma
	[3] = Color3.fromRGB(150, 200, 255),  -- crystal
	[4] = Color3.fromRGB(170, 60, 255),   -- cyber
}

-- [Player] = { Blade = BasePart, Weld = Weld, WeaponName = string }
local blades: { [Player]: any } = {}

--------------------------------------------------------------------------------
-- BLADE CONSTRUCTION
--------------------------------------------------------------------------------
local function rightHandOf(character: Model): BasePart?
	return (character:FindFirstChild("RightHand")
		or character:FindFirstChild("Right Arm")) :: BasePart?
end

local function buildBlade(weaponName: string): BasePart
	local template = weaponMeshFolder and weaponMeshFolder:FindFirstChild(weaponName)
	local blade: BasePart

	if template and template:IsA("BasePart") then
		blade = template:Clone() :: BasePart
	else
		local weaponConfig = GameConfig.Weapons[weaponName]
		local zone = weaponConfig and weaponConfig.Zone or 1
		local p = Instance.new("Part")
		p.Material = Enum.Material.Neon
		p.Color = ZONE_BLADE_COLORS[zone] or Color3.new(1, 1, 1)
		-- Blades get longer with zone tier: visible progression.
		p.Size = Vector3.new(0.25, 2.4 + zone * 0.5, 0.5)
		blade = p
	end

	blade.Name = "HeldWeapon_" .. weaponName
	blade.CanCollide = false
	blade.CanQuery = false
	blade.CanTouch = false
	blade.CastShadow = false
	blade.Anchored = false
	blade.Massless = true
	return blade
end

local function attachBlade(player: Player)
	local existing = blades[player]
	if existing then
		existing.Blade:Destroy()
		blades[player] = nil
	end

	local weaponName = player:GetAttribute(ATTRIBUTE)
	if type(weaponName) ~= "string" or not GameConfig.Weapons[weaponName] then
		return
	end
	local character = player.Character
	local hand = character and rightHandOf(character)
	if not hand then
		return
	end

	local blade = buildBlade(weaponName)
	local weld = Instance.new("Weld")
	weld.Part0 = hand
	weld.Part1 = blade
	-- Grip: blade extends up out of the fist.
	weld.C0 = CFrame.new(0, -blade.Size.Y / 2 - 0.4, 0) * CFrame.Angles(0, 0, math.rad(180))
	weld.Parent = blade
	blade.Parent = character

	blades[player] = { Blade = blade, Weld = weld, WeaponName = weaponName }
end

--------------------------------------------------------------------------------
-- PLAYER WATCHING
--------------------------------------------------------------------------------
local function watchPlayer(player: Player)
	player:GetAttributeChangedSignal(ATTRIBUTE):Connect(function()
		attachBlade(player)
	end)
	player.CharacterAdded:Connect(function(character)
		-- Wait for the hand to exist before welding.
		task.spawn(function()
			local deadline = os.clock() + 10
			while os.clock() < deadline and not rightHandOf(character) do
				task.wait(0.1)
			end
			attachBlade(player)
		end)
	end)
	if player.Character then
		attachBlade(player)
	end
end

Players.PlayerAdded:Connect(watchPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	watchPlayer(player)
end

Players.PlayerRemoving:Connect(function(player)
	local state = blades[player]
	if state then
		state.Blade:Destroy()
		blades[player] = nil
	end
end)

--------------------------------------------------------------------------------
-- LOCAL SLASH FEEDBACK (fires on every server-accepted hit)
--------------------------------------------------------------------------------
local slashing = false

Remotes.TargetDamaged.OnClientEvent:Connect(function()
	local state = blades[localPlayer]
	if not state or slashing or not state.Weld.Parent then
		return
	end
	slashing = true

	local restC0 = CFrame.new(0, -state.Blade.Size.Y / 2 - 0.4, 0) * CFrame.Angles(0, 0, math.rad(180))
	local swungC0 = restC0 * CFrame.Angles(math.rad(-110), 0, 0)

	local swing = TweenService:Create(state.Weld,
		TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = swungC0 })
	swing:Play()
	swing.Completed:Wait()
	local back = TweenService:Create(state.Weld,
		TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { C0 = restC0 })
	back:Play()
	back.Completed:Wait()
	slashing = false
end)

print("[WeaponVisualizer] Ready.")
