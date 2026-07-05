--!strict
--------------------------------------------------------------------------------
-- VFXController
-- StarterPlayer.StarterPlayerScripts.VFXController (LocalScript)
--
-- Combat juice, driven by Remotes.TargetDamaged (fired by CoreEngine on every
-- accepted swing):
--   * Floating damage numbers that pop, drift upward and fade.
--   * Hit sparks at the impact point.
--   * Death burst (bigger emission + camera-shake pulse) when a target dies.
--
-- Everything is camera-parented and client-local: zero replication cost.
--------------------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local camera = Workspace.CurrentCamera
local rng = Random.new()

local KIND_COLORS: { [string]: Color3 } = {
	Node = Color3.fromRGB(255, 235, 130),
	Enemy = Color3.fromRGB(255, 120, 90),
	Boss = Color3.fromRGB(255, 70, 160),
}

--------------------------------------------------------------------------------
-- DAMAGE NUMBERS
--------------------------------------------------------------------------------
local function abbreviate(n: number): string
	if n >= 1e9 then return string.format("%.1fB", n / 1e9) end
	if n >= 1e6 then return string.format("%.1fM", n / 1e6) end
	if n >= 1e3 then return string.format("%.1fK", n / 1e3) end
	return tostring(math.floor(n))
end

local function spawnDamageNumber(position: Vector3, damage: number, color: Color3, isKill: boolean)
	local anchor = Instance.new("Part")
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Position = position + Vector3.new(
		rng:NextNumber(-1.5, 1.5), rng:NextNumber(1, 2.5), rng:NextNumber(-1.5, 1.5))
	anchor.Parent = camera

	local billboard = Instance.new("BillboardGui")
	billboard.Size = isKill and UDim2.fromScale(8, 2.4) or UDim2.fromScale(5, 1.6)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 140
	billboard.Parent = anchor

	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.Text = (isKill and "-" or "-") .. abbreviate(damage) .. (isKill and " 💥" or "")
	text.TextColor3 = isKill and Color3.fromRGB(255, 60, 60) or color
	text.TextStrokeTransparency = 0.2
	text.TextScaled = true
	text.Parent = billboard

	-- Pop in, drift up, fade out.
	text.TextTransparency = 1
	TweenService:Create(text, TweenInfo.new(0.08), { TextTransparency = 0 }):Play()
	TweenService:Create(anchor, TweenInfo.new(0.85, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = anchor.Position + Vector3.new(0, 4, 0) }):Play()
	task.delay(0.55, function()
		TweenService:Create(text, TweenInfo.new(0.3), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
	Debris:AddItem(anchor, 1)
end

--------------------------------------------------------------------------------
-- PARTICLES
--------------------------------------------------------------------------------
local function spawnSparks(position: Vector3, color: Color3, big: boolean)
	local anchor = Instance.new("Part")
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Position = position
	anchor.Parent = camera

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, big and 0.9 or 0.45),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(0.25, big and 0.8 or 0.5)
	emitter.Speed = NumberRange.new(big and 14 or 7, big and 26 or 13)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.Parent = anchor
	emitter:Emit(big and 40 or 12)

	Debris:AddItem(anchor, 1.2)
end

--------------------------------------------------------------------------------
-- KILL CAMERA PULSE
--------------------------------------------------------------------------------
local shaking = false
local function killPulse()
	if shaking then
		return
	end
	shaking = true
	local original = camera.FieldOfView
	TweenService:Create(camera, TweenInfo.new(0.06), { FieldOfView = original + 3 }):Play()
	task.delay(0.07, function()
		TweenService:Create(camera, TweenInfo.new(0.18, Enum.EasingStyle.Back),
			{ FieldOfView = original }):Play()
		task.delay(0.2, function()
			shaking = false
		end)
	end)
end

--------------------------------------------------------------------------------
-- EVENT ENTRY POINT
-- Payload: { Position = Vector3, Damage = number, Kind = string, Died = bool }
--------------------------------------------------------------------------------
Remotes.TargetDamaged.OnClientEvent:Connect(function(payload: any)
	if typeof(payload) ~= "table" or typeof(payload.Position) ~= "Vector3" then
		return
	end
	local damage = tonumber(payload.Damage) or 0
	local color = KIND_COLORS[payload.Kind] or Color3.new(1, 1, 1)
	local died = payload.Died == true

	spawnDamageNumber(payload.Position, damage, color, died)
	spawnSparks(payload.Position, color, died)
	if died then
		killPulse()
	end
end)

print("[VFXController] Ready.")
