-- luau_scripter_demo.server.lua
-- Demonstrates a wide range of Luau/Roblox engineering concepts:
-- • Metatables and a manual class system
-- • CFrame and Vector3 math for movement
-- • Physics-based projectiles and raycast hit-detection
-- • Coroutine-style task scheduling
-- • Heartbeat simulation loops
-- • Event bus system for publish/subscribe patterns
-- • Lightweight optimization structures
-- • Procedural arena generation and simple AI behavior


---------------------------------------------------------
-- Service References
---------------------------------------------------------
local RunService = game:GetService("RunService")             -- Frame-stepped simulation.
local PhysicsService = game:GetService("PhysicsService")     -- Reserved for collision filtering.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")                     -- Handles timed cleanup.
local ReplicatedStorage = game:GetService("ReplicatedStorage")


---------------------------------------------------------
-- Global Constants
---------------------------------------------------------
local ARENA_NAME = "LuauScripterDemo_Arena"                  -- Container model for all demo content.
local ARENA_SIZE = Vector3.new(140, 12, 140)
local BOT_COUNT = 5
local PROJECTILE_SPEED = 120                                 -- Speed assigned to projectile BodyVelocity.
local TICK = 1/30                                            -- Reserved tick size (Heartbeat handles dt).
local DEBUG = true                                           -- Enables debug printing.


---------------------------------------------------------
-- Debug Print Helper
---------------------------------------------------------
local function dprint(...)
	if DEBUG then
		print("[LUAU-DEMO]", ...)
	end
end


---------------------------------------------------------
-- Math Utilities
---------------------------------------------------------
local function clamp(v, a, b)
	if v < a then return a end
	if v > b then return b end
	return v
end

local function lerp(a, b, t)
	return a + (b - a) * clamp(t, 0, 1)
end


---------------------------------------------------------
-- Mini Class System via Metatable & Inheritance
-- Provides:
-- • Class.new()
-- • Class:extend()
-- • Inherited methods via __index chain
---------------------------------------------------------
local Class = {}
Class.__index = Class

function Class.new()
	return setmetatable({}, Class)
end

function Class:extend()
	-- Creates a derived class by shallow-copying base methods.
	local cls = {}
	for k, v in pairs(self) do
		cls[k] = v
	end
	cls.__index = cls
	return setmetatable(cls, {__index = self})
end


---------------------------------------------------------
-- Arena Creation
-- Generates:
-- • a floor
-- • 4 surrounding walls
-- Ensures the arena exists only once.
---------------------------------------------------------
local function ensureArena()
	local arena = Workspace:FindFirstChild(ARENA_NAME)
	if arena then
		return arena
	end

	arena = Instance.new("Model")
	arena.Name = ARENA_NAME
	arena.Parent = Workspace

	-- Floor
	local floor = Instance.new("Part")
	floor.Name = "Floor"
	floor.Size = ARENA_SIZE
	floor.Anchored = true
	floor.Position = Vector3.new(0, 0, 0)
	floor.Parent = arena

	-- Boundary walls
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
-- VectorMover Class
-- Moves a Part toward a target position using dt-based motion.
-- Demonstrates:
-- • Class inheritance pattern
-- • Per-frame incremental movement
-- • Stop conditions
---------------------------------------------------------
local VectorMover = Class:extend()

function VectorMover:new(part)
	local obj = setmetatable({
		part = part,              -- Part being moved
		target = part.Position,   -- Target Vector3
		speed = 40,               -- Studs per second
		active = false
	}, VectorMover)
	return obj
end

function VectorMover:setTarget(pos)
	self.target = pos
	self.active = true
end

function VectorMover:step(dt)
	if not self.active then
		return
	end
	local dir = self.target - self.part.Position
	local dist = dir.Magnitude

	-- Stop when close enough
	if dist < 0.1 then
		self.active = false
		return
	end

	-- Move toward target at a capped distance per frame.
	local move = dir.Unit * math.min(self.speed * dt, dist)
	self.part.Position += move
end


---------------------------------------------------------
-- Bot Class
-- Simple autonomous agent:
-- • Holds its own Part
-- • Moves toward a target using CFrame look-at
---------------------------------------------------------
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
	if dir.Magnitude < 1 then
		return
	end

	-- Move toward target and orient the part to face it.
	self.part.CFrame = CFrame.new(
		self.part.Position + dir.Unit * self.speed * dt,
		self.target
	)
end


---------------------------------------------------------
-- Projectile System
-- Spawns dynamic projectiles with:
-- • BodyVelocity-based motion
-- • Raycast collision prediction (from lastPos → newPos)
-- • Impulse application to hit parts
-- • Auto cleanup through Debris
---------------------------------------------------------
local function fireProjectile(origin, direction)
	local proj = Instance.new("Part")
	proj.Size = Vector3.new(0.6, 0.6, 0.6)
	proj.Shape = Enum.PartType.Ball
	proj.Position = origin
	proj.Anchored = false
	proj.CanCollide = false
	proj.Parent = Workspace

	-- Apply velocity
	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
	bv.Velocity = direction.Unit * PROJECTILE_SPEED
	bv.Parent = proj

	local lastPos = proj.Position

	-- Coroutine-like projectile loop
	task.spawn(function()
		while proj.Parent do
			local nowPos = proj.Position

			-- Raycast between last and new position for reliable collision detection
			local rayParams = RaycastParams.new()
			rayParams.FilterType = Enum.RaycastFilterType.Blacklist
			rayParams.FilterDescendantsInstances = {proj}

			local result = Workspace:Raycast(lastPos, nowPos - lastPos, rayParams)
			if result then
				if result.Instance:IsA("BasePart") then
					-- Apply small impulse on impact
					result.Instance:ApplyImpulse(direction.Unit * 120)
				end
				proj:Destroy()
				return
			end

			lastPos = nowPos
			task.wait(0.03) -- Lightweight polling interval
		end
	end)

	-- Automatic cleanup safety
	Debris:AddItem(proj, 4)
end


---------------------------------------------------------
-- Moving Platform System
-- Creates multiple anchored platforms that oscillate
-- using a sin(time * speed) amplitude pattern.
---------------------------------------------------------
local movingPlatforms = {}

for i = 1, 6 do
	local plat = Instance.new("Part")
	plat.Size = Vector3.new(14, 1.5, 8)
	plat.Anchored = true
	plat.Position = Vector3.new(-50 + i * 18, 4 + i, 0)
	plat.Parent = arena

	-- Store platform motion properties
	movingPlatforms[#movingPlatforms + 1] = {
		part = plat,
		origin = plat.CFrame,
		speed = 0.8 + i * 0.1,
		amp = 10 + i * 2
	}
end


---------------------------------------------------------
-- Event Bus System
-- Lightweight pub/sub:
-- bus:on(event, callback)
-- bus:emit(event, ...)
-- Each event may contain multiple listeners.
---------------------------------------------------------
local EventBus = {}
EventBus.__index = EventBus

function EventBus.new()
	return setmetatable({
		listeners = {}
	}, EventBus)
end

function EventBus:on(eventName, fn)
	self.listeners[eventName] = self.listeners[eventName] or {}
	table.insert(self.listeners[eventName], fn)
end

function EventBus:emit(eventName, ...)
	local list = self.listeners[eventName]
	if not list then
		return
	end
	for _, fn in ipairs(list) do
		local ok, err = pcall(fn, ...)
		if not ok then
			warn("Event error:", err)
		end
	end
end

local bus = EventBus.new()


---------------------------------------------------------
-- Spawn Bots
-- Creates BOT_COUNT units inside the arena.
---------------------------------------------------------
local bots = {}

for i = 1, BOT_COUNT do
	local pos = Vector3.new(
		math.random(-40, 40),
		6,
		math.random(-40, 40)
	)
	local bot = Bot.new("DemoBot_" .. i, pos, arena)
	bots[#bots + 1] = bot
end


---------------------------------------------------------
-- Bot Target Randomizer
-- Every 3 seconds, each bot picks a new random target.
---------------------------------------------------------
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
-- Projectile Burst Task
-- Every 6 seconds, all bots fire a projectile in a random direction.
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
-- Heartbeat Simulation Loop
-- Handles:
-- • Platform oscillation
-- • Bot movement
-- Uses dt = currentTick - lastTick.
---------------------------------------------------------
local lastTick = tick()

RunService.Heartbeat:Connect(function()
	local now = tick()
	local dt = now - lastTick
	lastTick = now

	-- Animate oscillating platforms
	for _, plat in ipairs(movingPlatforms) do
		local t = tick() * plat.speed
		local y = math.sin(t) * plat.amp
		plat.part.CFrame = plat.origin * CFrame.new(0, y, 0)
	end

	-- Bot simulation
	for _, bot in ipairs(bots) do
		bot:step(dt)
	end
end)


---------------------------------------------------------
-- Player Events
---------------------------------------------------------
Players.PlayerAdded:Connect(function(player)
	dprint("Player joined:", player.Name)
end)


---------------------------------------------------------
-- Demonstration of EventBus Usage
---------------------------------------------------------
bus:on("ping", function(who)
	dprint("Ping received from", who)

	-- Spawn temporary debug marker
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
-- Script Initialization
---------------------------------------------------------
dprint("Extended Luau Scripter Demo Initialized")
