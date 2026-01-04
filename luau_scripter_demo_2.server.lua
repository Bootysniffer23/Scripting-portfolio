-- luau_scripter_demo.server.lua
-- PURPOSE:
-- This script implements a self-contained Luau engineering sandbox designed
-- to demonstrate intermediate-to-advanced Roblox scripting concepts in a
-- single, cohesive environment.
--
-- The goal is not to build a full game, but to showcase architectural thinking,
-- system decoupling, physics interaction, and autonomous simulation behavior.
--
-- Core concepts demonstrated:
-- • Manual class systems via metatables
-- • Deterministic movement using CFrame math
-- • Physics-driven projectiles with raycast prediction
-- • Coroutine-style task scheduling
-- • Frame-stepped simulation loops
-- • Event-driven communication (publish/subscribe)
-- • Procedural environment construction
-- • Autonomous agent behavior


---------------------------------------------------------
-- SERVICE REFERENCES
---------------------------------------------------------
-- Services are cached locally to avoid repeated GetService calls,
-- which improves readability and prevents unnecessary service lookups.
local RunService = game:GetService("RunService")         -- Used for frame-based simulation.
local PhysicsService = game:GetService("PhysicsService") -- Reserved for collision-layer control.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")                 -- Automatic cleanup of temporary instances.
local ReplicatedStorage = game:GetService("ReplicatedStorage")


---------------------------------------------------------
-- GLOBAL CONSTANTS
---------------------------------------------------------
-- Constants are defined at the top to make system-wide tuning easier
-- and to avoid hidden magic numbers scattered throughout the script.
local ARENA_NAME = "LuauScripterDemo_Arena"
local ARENA_SIZE = Vector3.new(140, 12, 140)
local BOT_COUNT = 5

-- Projectile speed is intentionally high to require raycast-based
-- collision prediction instead of relying on Roblox's default physics.
local PROJECTILE_SPEED = 120

-- DEBUG flag allows noisy output to be disabled without removing prints.
local DEBUG = true


---------------------------------------------------------
-- DEBUG PRINT HELPER
---------------------------------------------------------
-- Centralized debug printing prevents clutter and makes it easy
-- to disable all debug output without editing multiple lines.
local function dprint(...)
	if DEBUG then
		print("[LUAU-DEMO]", ...)
	end
end


---------------------------------------------------------
-- MATH UTILITIES
---------------------------------------------------------
-- Utility math functions are defined explicitly to avoid relying
-- on hidden assumptions and to improve code readability.
local function clamp(v, a, b)
	if v < a then return a end
	if v > b then return b end
	return v
end

-- Linear interpolation helper used for smooth transitions.
local function lerp(a, b, t)
	return a + (b - a) * clamp(t, 0, 1)
end


---------------------------------------------------------
-- LIGHTWEIGHT CLASS SYSTEM (METATABLE-BASED)
---------------------------------------------------------
-- A manual class system is used instead of ModuleScripts to:
-- 1) Keep all logic inside a single script (per application rules)
-- 2) Explicitly demonstrate understanding of Lua metatables
-- 3) Allow inheritance-style behavior extension
--
-- This avoids global state while still enabling reusable behavior.
local Class = {}
Class.__index = Class

function Class.new()
	return setmetatable({}, Class)
end

function Class:extend()
	-- Creates a derived class by copying methods and chaining __index.
	local cls = {}
	for k, v in pairs(self) do
		cls[k] = v
	end
	cls.__index = cls
	return setmetatable(cls, { __index = self })
end


---------------------------------------------------------
-- ARENA CREATION (PROCEDURAL ENVIRONMENT)
---------------------------------------------------------
-- The arena is generated procedurally to demonstrate controlled
-- environment setup without relying on prebuilt assets.
-- This ensures the demo is reproducible and self-contained.
local function ensureArena()
	local arena = Workspace:FindFirstChild(ARENA_NAME)
	if arena then
		return arena
	end

	arena = Instance.new("Model")
	arena.Name = ARENA_NAME
	arena.Parent = Workspace

	-- Floor is anchored to provide a stable simulation surface.
	local floor = Instance.new("Part")
	floor.Name = "Floor"
	floor.Size = ARENA_SIZE
	floor.Anchored = true
	floor.Position = Vector3.new(0, 0, 0)
	floor.Parent = arena

	-- Walls constrain movement and ensure bots remain inside bounds,
	-- allowing predictable AI behavior for demonstration purposes.
	local wallThickness = 4
	local wallHeight = 14
	local half = ARENA_SIZE / 2

	local function makeWall(pos, size)
		local w = Instance.new("Part")
		w.Anchored = true
		w.Size = size
		w.Position = pos
		w.Parent = arena
	end

	makeWall(Vector3.new(half.X + 2, 7, 0), Vector3.new(wallThickness, wallHeight, ARENA_SIZE.Z))
	makeWall(Vector3.new(-half.X - 2, 7, 0), Vector3.new(wallThickness, wallHeight, ARENA_SIZE.Z))
	makeWall(Vector3.new(0, 7, half.Z + 2), Vector3.new(ARENA_SIZE.X, wallHeight, wallThickness))
	makeWall(Vector3.new(0, 7, -half.Z - 2), Vector3.new(ARENA_SIZE.X, wallHeight, wallThickness))

	return arena
end

local arena = ensureArena()


---------------------------------------------------------
-- VECTOR MOVER CLASS
---------------------------------------------------------
-- VectorMover encapsulates deterministic, frame-based movement logic.
-- This avoids physics forces, ensuring predictable motion regardless
-- of frame rate or physics solver variance.
local VectorMover = Class:extend()

function VectorMover:new(part)
	local obj = setmetatable({
		part = part,
		target = part.Position,
		speed = 40,
		active = false
	}, VectorMover)
	return obj
end

function VectorMover:setTarget(pos)
	self.target = pos
	self.active = true
end

function VectorMover:step(dt)
	if not self.active then return end

	local dir = self.target - self.part.Position
	local dist = dir.Magnitude

	-- Movement stops once the target is sufficiently reached,
	-- preventing jitter caused by overshooting.
	if dist < 0.1 then
		self.active = false
		return
	end

	local move = dir.Unit * math.min(self.speed * dt, dist)
	self.part.Position += move
end


---------------------------------------------------------
-- BOT CLASS (AUTONOMOUS AGENT)
---------------------------------------------------------
-- The Bot class represents a minimal autonomous agent.
-- It deliberately avoids Humanoids to keep behavior explicit
-- and fully controlled through math and CFrame logic.
local Bot = {}
Bot.__index = Bot

function Bot.new(name, spawnPos, parent)
	local p = Instance.new("Part")
	p.Size = Vector3.new(2, 2, 2)
	p.Anchored = false
	p.Position = spawnPos
	p.Name = name
	p.Parent = parent

	return setmetatable({
		part = p,
		target = spawnPos,
		speed = 28
	}, Bot)
end

function Bot:setTarget(pos)
	self.target = pos
end

function Bot:step(dt)
	local dir = self.target - self.part.Position
	if dir.Magnitude < 1 then return end

	-- CFrame-based movement is used to explicitly control
	-- orientation and forward motion in a single operation.
	self.part.CFrame = CFrame.new(
		self.part.Position + dir.Unit * self.speed * dt,
		self.target
	)
end


---------------------------------------------------------
-- PROJECTILE SYSTEM
---------------------------------------------------------
-- Projectiles use raycast-based collision prediction instead of
-- relying on Touched events, which can fail at high velocities.
-- This ensures reliable hit detection regardless of frame rate.
local function fireProjectile(origin, direction)
	local proj = Instance.new("Part")
	proj.Size = Vector3.new(0.6, 0.6, 0.6)
	proj.Shape = Enum.PartType.Ball
	proj.Position = origin
	proj.Anchored = false
	proj.CanCollide = false
	proj.Parent = Workspace

	-- BodyVelocity is used so Roblox physics handles motion
	-- while still allowing manual collision prediction.
	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
	bv.Velocity = direction.Unit * PROJECTILE_SPEED
	bv.Parent = proj

	local lastPos = proj.Position

	task.spawn(function()
		while proj.Parent do
			local nowPos = proj.Position

			-- Raycast between frames prevents tunneling issues.
			local rayParams = RaycastParams.new()
			rayParams.FilterType = Enum.RaycastFilterType.Blacklist
			rayParams.FilterDescendantsInstances = { proj }

			local result = Workspace:Raycast(lastPos, nowPos - lastPos, rayParams)
			if result then
				if result.Instance:IsA("BasePart") then
					-- Impulse demonstrates physics interaction on hit.
					result.Instance:ApplyImpulse(direction.Unit * 120)
				end
				proj:Destroy()
				return
			end

			lastPos = nowPos
			task.wait(0.03)
		end
	end)

	Debris:AddItem(proj, 4)
end


---------------------------------------------------------
-- MOVING PLATFORM SYSTEM
---------------------------------------------------------
-- Oscillating platforms demonstrate time-based motion
-- driven entirely by math instead of TweenService.
local movingPlatforms = {}

for i = 1, 6 do
	local plat = Instance.new("Part")
	plat.Size = Vector3.new(14, 1.5, 8)
	plat.Anchored = true
	plat.Position = Vector3.new(-50 + i * 18, 4 + i, 0)
	plat.Parent = arena

	movingPlatforms[#movingPlatforms + 1] = {
		part = plat,
		origin = plat.CFrame,
		speed = 0.8 + i * 0.1,
		amp = 10 + i * 2
	}
end


---------------------------------------------------------
-- EVENT BUS (PUBLISH / SUBSCRIBE)
---------------------------------------------------------
-- The EventBus decouples systems so they can communicate
-- without direct references, improving scalability.
local EventBus = {}
EventBus.__index = EventBus

function EventBus.new()
	return setmetatable({ listeners = {} }, EventBus)
end

function EventBus:on(eventName, fn)
	self.listeners[eventName] = self.listeners[eventName] or {}
	table.insert(self.listeners[eventName], fn)
end

function EventBus:emit(eventName, ...)
	local list = self.listeners[eventName]
	if not list then return end

	for _, fn in ipairs(list) do
		local ok, err = pcall(fn, ...)
		if not ok then
			warn("Event error:", err)
		end
	end
end

local bus = EventBus.new()


---------------------------------------------------------
-- BOT SPAWNING
---------------------------------------------------------
local bots = {}

for i = 1, BOT_COUNT do
	local pos = Vector3.new(
		math.random(-40, 40),
		6,
		math.random(-40, 40)
	)
	bots[#bots + 1] = Bot.new("DemoBot_" .. i, pos, arena)
end


---------------------------------------------------------
-- BOT TARGET RANDOMIZATION
---------------------------------------------------------
-- Bots periodically select new targets to simulate
-- autonomous roaming behavior.
task.spawn(function()
	while true do
		for _, bot in ipairs(bots) do
			bot:setTarget(Vector3.new(
				math.random(-50, 50),
				6,
				math.random(-50, 50)
			))
		end
		task.wait(3)
	end
end)


---------------------------------------------------------
-- PROJECTILE BURST TASK
---------------------------------------------------------
task.spawn(function()
	while true do
		for _, bot in ipairs(bots) do
			fireProjectile(
				bot.part.Position + Vector3.new(0, 4, 0),
				Vector3.new(math.random() - 0.5, 0.2, math.random() - 0.5)
			)
		end
		task.wait(6)
	end
end)


---------------------------------------------------------
-- HEARTBEAT SIMULATION LOOP
---------------------------------------------------------
local lastTick = tick()

RunService.Heartbeat:Connect(function()
	local now = tick()
	local dt = now - lastTick
	lastTick = now

	-- Animate platforms using sine-based oscillation.
	for _, plat in ipairs(movingPlatforms) do
		local t = tick() * plat.speed
		local y = math.sin(t) * plat.amp
		plat.part.CFrame = plat.origin * CFrame.new(0, y, 0)
	end

	-- Update all autonomous agents.
	for _, bot in ipairs(bots) do
		bot:step(dt)
	end
end)


---------------------------------------------------------
-- PLAYER EVENTS
---------------------------------------------------------
Players.PlayerAdded:Connect(function(player)
	dprint("Player joined:", player.Name)
end)


---------------------------------------------------------
-- EVENT BUS DEMONSTRATION
---------------------------------------------------------
bus:on("ping", function(who)
	dprint("Ping received from", who)

	local p = Instance.new("Part")
	p.Size = Vector3.new(1, 1, 1)
	p.Anchored = true
	p.Position = Vector3.new(
		math.random(-30, 30),
		8,
		math.random(-30, 30)
	)
	p.Parent = arena

	Debris:AddItem(p, 2)
end)


---------------------------------------------------------
-- INITIALIZATION
---------------------------------------------------------
dprint("Extended Luau Scripter Demo Initialized")
