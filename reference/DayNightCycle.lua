--!strict
--------------------------------------------------------------------------------
-- DayNightCycle
-- Reference module for a survival-horror day/night atmosphere system.
--
-- Usage: place as a ModuleScript (ReplicatedStorage recommended), then from a
-- thin LocalScript in StarterPlayerScripts:
--
--   local DayNightCycle = require(path.to.DayNightCycle)
--   DayNightCycle.Start()
--   DayNightCycle.PhaseChanged:Connect(function(isNight)
--       print(isNight and "Night has fallen..." or "Dawn breaks.")
--   end)
--
-- Pure client-side ATMOSPHERE/VISUAL cycle -- Lighting is a client-rendered
-- service, so nothing here is server-authoritative. If night should also
-- affect GAMEPLAY (monster spawn rates, stamina drain, etc.), have the server
-- set the Workspace attribute named by SERVER_CLOCK_ATTRIBUTE (a number 0-24)
-- once per second or so; every client will sync its visuals to that same
-- authoritative hour instead of running an independent local clock, so every
-- player's screen goes dark at the same real moment.
--
-- Assumes Lighting.Technology = Enum.Technology.Future is already set per the
-- manual Lighting checklist (Technology is a one-time global switch, not
-- something you animate frame to frame).
--------------------------------------------------------------------------------

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DayNightCycle = {}

-- ============================================================================
-- CONFIG
-- ============================================================================

-- Real-world seconds for one full 24h in-game day. 1200s = 20 real minutes.
local FULL_CYCLE_SECONDS = 1200

-- If this Workspace attribute exists (a number 0-24, set by the server), the
-- cycle SYNCS to it instead of running its own clock. Set to "" to disable.
local SERVER_CLOCK_ATTRIBUTE = "ServerTimeOfDay"

-- Night window used for the IsNight flag / PhaseChanged event.
local NIGHT_START_HOUR = 20
local NIGHT_END_HOUR = 6

-- Keyframes across a 24h cycle: hour -> full preset table. Values interpolate
-- piecewise-linearly between the two nearest keyframes every frame.
local KEYFRAMES = {
	[0] = { -- MIDNIGHT: peak horror
		Ambient = Color3.fromRGB(8, 10, 14),
		OutdoorAmbient = Color3.fromRGB(10, 12, 16),
		Brightness = 0.5,
		EnvironmentDiffuseScale = 0.25,
		EnvironmentSpecularScale = 0.2,
		Atmosphere = {
			Density = 0.42, Offset = 0.15,
			Color = Color3.fromRGB(90, 100, 110),
			Decay = Color3.fromRGB(20, 22, 28),
			Glare = 0.1, Haze = 2.4,
		},
		ColorCorrection = {
			Brightness = -0.08, Contrast = 0.22, Saturation = -0.55,
			TintColor = Color3.fromRGB(190, 210, 220),
		},
		Bloom = { Intensity = 0.35, Size = 26, Threshold = 1.6 },
		FogColor = Color3.fromRGB(12, 14, 18),
		FogStart = 6, FogEnd = 75,
	},
	[6] = { -- DAWN: fragile relief
		Ambient = Color3.fromRGB(55, 45, 40),
		OutdoorAmbient = Color3.fromRGB(80, 65, 55),
		Brightness = 1.4,
		EnvironmentDiffuseScale = 0.5,
		EnvironmentSpecularScale = 0.4,
		Atmosphere = {
			Density = 0.32, Offset = 0.22,
			Color = Color3.fromRGB(180, 140, 110),
			Decay = Color3.fromRGB(60, 50, 55),
			Glare = 0.3, Haze = 1.7,
		},
		ColorCorrection = {
			Brightness = -0.02, Contrast = 0.14, Saturation = -0.35,
			TintColor = Color3.fromRGB(230, 210, 195),
		},
		Bloom = { Intensity = 0.55, Size = 28, Threshold = 1.4 },
		FogColor = Color3.fromRGB(70, 60, 58),
		FogStart = 15, FogEnd = 160,
	},
	[12] = { -- NOON: least oppressive, still overcast/eerie
		Ambient = Color3.fromRGB(70, 80, 70),
		OutdoorAmbient = Color3.fromRGB(120, 130, 120),
		Brightness = 2.0,
		EnvironmentDiffuseScale = 0.65,
		EnvironmentSpecularScale = 0.45,
		Atmosphere = {
			Density = 0.28, Offset = 0.25,
			Color = Color3.fromRGB(165, 175, 160),
			Decay = Color3.fromRGB(80, 85, 75),
			Glare = 0.25, Haze = 1.3,
		},
		ColorCorrection = {
			Brightness = 0.0, Contrast = 0.1, Saturation = -0.25,
			TintColor = Color3.fromRGB(220, 225, 215),
		},
		Bloom = { Intensity = 0.4, Size = 24, Threshold = 1.5 },
		FogColor = Color3.fromRGB(120, 128, 118),
		FogStart = 20, FogEnd = 260,
	},
	[18] = { -- DUSK: dread building
		Ambient = Color3.fromRGB(45, 30, 30),
		OutdoorAmbient = Color3.fromRGB(70, 45, 40),
		Brightness = 1.1,
		EnvironmentDiffuseScale = 0.4,
		EnvironmentSpecularScale = 0.3,
		Atmosphere = {
			Density = 0.36, Offset = 0.18,
			Color = Color3.fromRGB(150, 90, 70),
			Decay = Color3.fromRGB(40, 25, 25),
			Glare = 0.2, Haze = 1.9,
		},
		ColorCorrection = {
			Brightness = -0.05, Contrast = 0.18, Saturation = -0.45,
			TintColor = Color3.fromRGB(215, 190, 175),
		},
		Bloom = { Intensity = 0.5, Size = 30, Threshold = 1.35 },
		FogColor = Color3.fromRGB(50, 35, 32),
		FogStart = 10, FogEnd = 110,
	},
}
KEYFRAMES[24] = KEYFRAMES[0] -- 18 -> 24 lerps back into midnight

local ORDERED_HOURS = { 0, 6, 12, 18, 24 }

-- ============================================================================
-- LIGHTING CHILD INSTANCES (get-or-create so this works on a bare Lighting)
-- ============================================================================
local function getOrCreate(className: string, parent: Instance): Instance
	local existing = parent:FindFirstChildOfClass(className)
	if existing then
		return existing
	end
	local instance = Instance.new(className)
	instance.Parent = parent
	return instance
end

local atmosphere = getOrCreate("Atmosphere", Lighting) :: Atmosphere
local colorCorrection = getOrCreate("ColorCorrectionEffect", Lighting) :: ColorCorrectionEffect
local bloom = getOrCreate("BloomEffect", Lighting) :: BloomEffect

-- ============================================================================
-- INTERPOLATION
-- ============================================================================
local function lerpValue(a: any, b: any, alpha: number): any
	if typeof(a) == "number" then
		return a + (b - a) * alpha
	elseif typeof(a) == "Color3" then
		return a:Lerp(b, alpha)
	elseif typeof(a) == "table" then
		local result = {}
		for key, value in pairs(a) do
			result[key] = lerpValue(value, b[key], alpha)
		end
		return result
	end
	return a
end

local function boundingHours(hour: number): (number, number)
	for i = 1, #ORDERED_HOURS - 1 do
		local lower, upper = ORDERED_HOURS[i], ORDERED_HOURS[i + 1]
		if hour >= lower and hour <= upper then
			return lower, upper
		end
	end
	return 18, 24
end

local function applyPreset(preset: any)
	Lighting.Ambient = preset.Ambient
	Lighting.OutdoorAmbient = preset.OutdoorAmbient
	Lighting.Brightness = preset.Brightness
	Lighting.EnvironmentDiffuseScale = preset.EnvironmentDiffuseScale
	Lighting.EnvironmentSpecularScale = preset.EnvironmentSpecularScale
	Lighting.FogColor = preset.FogColor
	Lighting.FogStart = preset.FogStart
	Lighting.FogEnd = preset.FogEnd

	atmosphere.Density = preset.Atmosphere.Density
	atmosphere.Offset = preset.Atmosphere.Offset
	atmosphere.Color = preset.Atmosphere.Color
	atmosphere.Decay = preset.Atmosphere.Decay
	atmosphere.Glare = preset.Atmosphere.Glare
	atmosphere.Haze = preset.Atmosphere.Haze

	colorCorrection.Brightness = preset.ColorCorrection.Brightness
	colorCorrection.Contrast = preset.ColorCorrection.Contrast
	colorCorrection.Saturation = preset.ColorCorrection.Saturation
	colorCorrection.TintColor = preset.ColorCorrection.TintColor

	bloom.Intensity = preset.Bloom.Intensity
	bloom.Size = preset.Bloom.Size
	bloom.Threshold = preset.Bloom.Threshold
end

-- ============================================================================
-- PUBLIC STATE
-- ============================================================================
local phaseChangedEvent = Instance.new("BindableEvent")
DayNightCycle.PhaseChanged = phaseChangedEvent.Event -- :Connect(function(isNight: boolean) end)
DayNightCycle.IsNight = false

local localClock = 12 -- start at noon
local started = false

function DayNightCycle.GetTimeOfDay(): number
	return Lighting.ClockTime
end

function DayNightCycle.Start()
	if started then
		return
	end
	started = true

	RunService.Heartbeat:Connect(function(dt: number)
		local hour: number
		local serverHour = SERVER_CLOCK_ATTRIBUTE ~= ""
			and Workspace:GetAttribute(SERVER_CLOCK_ATTRIBUTE)
		if typeof(serverHour) == "number" then
			hour = serverHour
		else
			localClock = (localClock + dt * (24 / FULL_CYCLE_SECONDS)) % 24
			hour = localClock
		end

		Lighting.ClockTime = hour

		local lower, upper = boundingHours(hour)
		local span = upper - lower
		local alpha = if span == 0 then 0 else (hour - lower) / span
		applyPreset(lerpValue(KEYFRAMES[lower], KEYFRAMES[upper], alpha))

		local nightNow = hour >= NIGHT_START_HOUR or hour < NIGHT_END_HOUR
		if nightNow ~= DayNightCycle.IsNight then
			DayNightCycle.IsNight = nightNow
			phaseChangedEvent:Fire(nightNow)
		end
	end)
end

return DayNightCycle
