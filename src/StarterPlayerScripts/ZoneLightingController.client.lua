--!strict
--------------------------------------------------------------------------------
-- ZoneLightingController
-- StarterPlayer.StarterPlayerScripts.ZoneLightingController (LocalScript)
--
-- Brings docs/MapSpecifications.md to life at runtime. Reads the per-zone
-- lighting sheets from GameConfig.ZoneAmbience and:
--   * Detects which zone the local player is standing in via the invisible
--     "ZoneRegion" part builders place inside each Workspace/Zones/Zone<N>
--     folder (point-in-box test, checked twice a second).
--   * Tweens every Lighting property to the zone's sheet over 1.5s so biome
--     transitions feel like walking into a different world, not a hard cut.
--   * Crossfades zone music (one looping Sound per zone, volume-tweened).
--
-- Falls back to Zone 1 ambience when no ZoneRegion contains the player, so
-- the game always has a defined look even before regions are placed.
--------------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))

local localPlayer = Players.LocalPlayer

local TRANSITION = TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local MUSIC_FADE = TweenInfo.new(2.0)
local MUSIC_VOLUME = 0.35
local CHECK_INTERVAL = 0.5

--------------------------------------------------------------------------------
-- MUSIC CHANNELS (one persistent looping Sound per zone)
--------------------------------------------------------------------------------
local musicChannels: { [number]: Sound } = {}
for zoneId, ambience in pairs(GameConfig.ZoneAmbience) do
	local sound = Instance.new("Sound")
	sound.Name = "ZoneMusic_" .. zoneId
	sound.SoundId = ambience.MusicId
	sound.Looped = true
	sound.Volume = 0
	sound.Parent = SoundService
	musicChannels[zoneId] = sound
end

--------------------------------------------------------------------------------
-- ZONE DETECTION
--------------------------------------------------------------------------------
local function pointInPart(point: Vector3, part: BasePart): boolean
	local localPoint = part.CFrame:PointToObjectSpace(point)
	local half = part.Size / 2
	return math.abs(localPoint.X) <= half.X
		and math.abs(localPoint.Y) <= half.Y
		and math.abs(localPoint.Z) <= half.Z
end

local function currentZone(): number
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return 1
	end
	local zonesFolder = Workspace:FindFirstChild("Zones")
	if not zonesFolder then
		return 1
	end
	for zoneId in pairs(GameConfig.ZoneAmbience) do
		local zoneFolder = zonesFolder:FindFirstChild("Zone" .. zoneId)
		local region = zoneFolder and zoneFolder:FindFirstChild("ZoneRegion")
		if region and region:IsA("BasePart") and pointInPart(root.Position, region) then
			return zoneId
		end
	end
	return 1
end

--------------------------------------------------------------------------------
-- APPLICATION
--------------------------------------------------------------------------------
local activeZone = 0

local function applyZone(zoneId: number)
	if zoneId == activeZone then
		return
	end
	activeZone = zoneId
	local ambience = GameConfig.ZoneAmbience[zoneId]
	if not ambience then
		return
	end

	TweenService:Create(Lighting, TRANSITION, {
		Ambient = ambience.Ambient,
		OutdoorAmbient = ambience.OutdoorAmbient,
		FogColor = ambience.FogColor,
		FogStart = ambience.FogStart,
		FogEnd = ambience.FogEnd,
		Brightness = ambience.Brightness,
		ColorShift_Top = ambience.ColorShift_Top,
		ClockTime = ambience.ClockTime,
	}):Play()

	for channelZone, sound in pairs(musicChannels) do
		if channelZone == zoneId then
			if not sound.IsPlaying then
				sound:Play()
			end
			TweenService:Create(sound, MUSIC_FADE, { Volume = MUSIC_VOLUME }):Play()
		else
			local fade = TweenService:Create(sound, MUSIC_FADE, { Volume = 0 })
			fade:Play()
			task.delay(MUSIC_FADE.Time, function()
				if sound.Volume <= 0.01 and activeZone ~= channelZone then
					sound:Stop()
				end
			end)
		end
	end

	local zoneConfig = GameConfig.Zones[zoneId]
	if zoneConfig then
		print("[ZoneLightingController] Entered " .. zoneConfig.Name)
	end
end

applyZone(1)
task.spawn(function()
	while true do
		task.wait(CHECK_INTERVAL)
		applyZone(currentZone())
	end
end)

print("[ZoneLightingController] Ready.")
