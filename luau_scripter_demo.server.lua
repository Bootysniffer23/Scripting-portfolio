
-- luau_scripter_demo.server.lua
-- Single-file Luau demo: intermediate systems, CFrame math, physics, metatables, coroutines, events
-- Place this Script inside ServerScriptService in Roblox Studio.
-- Author: Bootysniffer23
-- Purpose: Demonstrate Luau skills for application — gameplay systems, optimization patterns, and clear comments.

local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local ARENA_NAME = "LuauScripterDemo_Arena"
local ARENA_SIZE = Vector3.new(120, 12, 120)
local PLATFORM_COUNT = 6
local BOT_COUNT = 4
local PROJECTILE_SPEED = 120
local TICK = 1/30

local DEBUG = true
local function dprint(...)
	if DEBUG then
		print("[DEMOSYS]", ...)
	end
end

local Class = {}
Class.__index = Class

function Class.new()
	local self = setmetatable({}, Class)
	return self
end

function Class:extend()
	local cls = {}
	for k,v in pairs(self) do
		cls[k] = v
	end
	cls.__index = cls
	return setmetatable(cls, {__index = self})
end

local VectorMover = Class:extend()
function VectorMover:new(part)
	local obj = setmetatable({
		_part = part,
		_target = part.Position,
		_speed = 32,
		_active = false,
	}, VectorMover)
	return obj
end

function VectorMover:setTarget(pos)
	self._target = pos
	self._active = true
end

function VectorMover:step(dt)
	if not self._active then return end
	local p = self._part.Position
	local dir = (self._target - p)
	local dist = dir.Magnitude
	if dist < 0.1 then
		self._active = false
		return
	end
	local move = dir.Unit * math.min(self._speed * dt, dist)
	self._part.Position = p + move
end

local function ensureArena()
	local arena = Workspace:FindFirstChild(ARENA_NAME)
	if arena then return arena end

	arena = Instance.new("Model")
	arena.Name = ARENA_NAME
	arena.Parent = Workspace

	local floor = Instance.new("Part")
	floor.Size = ARENA_SIZE
	floor.Anchored = true
	floor.Position = Vector3.new(0, 0, 0)
	floor.Parent = arena

	return arena
end

local arena = ensureArena()

local Bot = {}
Bot.__index = Bot

function Bot.new(name, pos, parent)
	local part = Instance.new("Part")
	part.Size = Vector3.new(2,2,2)
	part.Position = pos
	part.Anchored = false
	part.Name = name
	part.Parent = parent

	return setmetatable({
		part = part,
		target = pos,
		speed = 26
	}, Bot)
end

function Bot:setTarget(pos)
	self.target = pos
end

function Bot:step(dt)
	local dir = self.target - self.part.Position
	if dir.Magnitude < 1 then return end
	self.part.CFrame = CFrame.new(self.part.Position + dir.Unit * self.speed * dt, self.target)
end

local bots = {}
for i = 1, BOT_COUNT do
	local pos = Vector3.new(math.random(-30,30), 6, math.random(-30,30))
	local b = Bot.new("DemoBot_"..i, pos, arena)
	bots[#bots+1] = b
end

local function fireProjectile(origin, direction)
	local proj = Instance.new("Part")
	proj.Shape = Enum.PartType.Ball
	proj.Size = Vector3.new(0.6,0.6,0.6)
	proj.Position = origin
	proj.Anchored = false
	proj.CanCollide = false
	proj.Parent = Workspace

	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(1e5,1e5,1e5)
	bv.Velocity = direction.Unit * PROJECTILE_SPEED
	bv.Parent = proj

	Debris:AddItem(proj, 4)
end

task.spawn(function()
	while true do
		for _, bot in ipairs(bots) do
			bot:setTarget(Vector3.new(math.random(-40,40), 6, math.random(-40,40)))
		end
		task.wait(3)
	end
end)

task.spawn(function()
	while true do
		for _, bot in ipairs(bots) do
			fireProjectile(bot.part.Position + Vector3.new(0,3,0), Vector3.new(math.random(),0,math.random()))
		end
		task.wait(6)
	end
end)

local last = tick()
RunService.Heartbeat:Connect(function()
	local now = tick()
	local dt = now - last
	last = now
	for _, bot in ipairs(bots) do
		bot:step(dt)
	end
end)

Players.PlayerAdded:Connect(function(player)
	dprint("Player joined:", player.Name)
end)

dprint("Luau Scripter demo fully initialized.")
