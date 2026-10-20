local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local VIM = game:GetService("VirtualInputManager")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui")

local C = {
Enabled = true,
PerfectCastTime = 0.578,
CastCompensation = 0.002,
AfterCastDelay = 0.20,
ShakeDelay = 0.012,
ShakeClickHold = 0.007,
ReelTick = 0.002,
DeadZone = 2.5,
PredictionTime = 0.065,
VelocitySmoothing = 0.32,
StrongRight = 55,
StrongLeft = -55,
ResetDelay = 2,
MaxShake = 25,
MaxReel = 35,
Debug = false
}

local state = "CAST"
local stateStart = os.clock()
local held = false
local lastFishX, lastBarX, lastTime
local fishVel, barVel = 0, 0

local function setState(s)
state = s
stateStart = os.clock()
if s ~= "REEL" then
lastFishX, lastBarX, lastTime = nil, nil, nil
fishVel, barVel = 0, 0
end
end

local function centerX(o)
return o.AbsolutePosition.X + o.AbsoluteSize.X / 2
end

local function screenCenter()
local cam = workspace.CurrentCamera
if not cam then return 500, 500 end
return cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2
end

local function mouse(v, x, y)
if held == v then return end
held = v
VIM:SendMouseButtonEvent(x or 0, y or 0, 0, v, game, 0)
end

local function release(x, y)
held = false
VIM:SendMouseButtonEvent(x or 0, y or 0, 0, false, game, 0)
end

local function getShake()
local s = gui:FindFirstChild("shakeui")
local z = s and s:FindFirstChild("safezone")
local b = z and z:FindFirstChild("default")
if b and b:IsA("GuiObject") and b.Visible and b.AbsoluteSize.X > 2 and b.AbsoluteSize.Y > 2 then return b end
end

local function getReel()
local r = gui:FindFirstChild("reel")
local c = r and r:FindFirstChild("bar")
if not c then return end
local f = c:FindFirstChild("fish")
local b = c:FindFirstChild("playerbar")
if f and b and f:IsA("GuiObject") and b:IsA("GuiObject") and f.Visible and b.Visible then return f, b, c end
end

local function cast()
local x, y = screenCenter()
print("[FISH BOT] Casting")
mouse(true, x, y)

local start = os.clock()
local target = C.PerfectCastTime - C.CastCompensation

while true do
	RunService.Heartbeat:Wait()
	if os.clock() - start >= target then break end
end

mouse(false, x, y)

if C.Debug then
	print(string.format("[CAST] %.6f", os.clock() - start))
end

task.wait(C.AfterCastDelay)
setState("SHAKE")
end

local function shake()
if getReel() then
setState("REEL")
return
end

local b = getShake()
if b then
	local p, s = b.AbsolutePosition, b.AbsoluteSize
	local x, y = p.X + s.X / 2, p.Y + s.Y / 2
	VIM:SendMouseMoveEvent(x, y, game)
	task.wait(0.002)
	VIM:SendMouseButtonEvent(x, y, 0, true, game, 0)
	task.wait(C.ShakeClickHold)
	VIM:SendMouseButtonEvent(x, y, 0, false, game, 0)
	task.wait(C.ShakeDelay)
else
	task.wait(0.004)
end

if os.clock() - stateStart > C.MaxShake then setState("RESET") end
end

local function reel()
local fish, bar, container = getReel()
if not fish then
release()
setState("RESET")
return
end

local now = os.clock()
local fx, bx = centerX(fish), centerX(bar)

if lastFishX and lastBarX and lastTime then
	local dt = now - lastTime
	if dt > 0 then
		local newFishVel = (fx - lastFishX) / dt
		local newBarVel = (bx - lastBarX) / dt
		fishVel += (newFishVel - fishVel) *C.VelocitySmoothing
		barVel += (newBarVel - barVel)* C.VelocitySmoothing
	end
end

lastFishX, lastBarX, lastTime = fx, bx, now

local predictedFish = fx + fishVel *C.PredictionTime
local predictedBar = bx + barVel* C.PredictionTime
local error = predictedFish - predictedBar
local relativeVelocity = fishVel - barVel
local control = error + relativeVelocity * 0.035

local x = container.AbsolutePosition.X + container.AbsoluteSize.X / 2
local y = container.AbsolutePosition.Y + container.AbsoluteSize.Y / 2

if control > C.StrongRight then
	mouse(true, x, y)
elseif control < C.StrongLeft then
	mouse(false, x, y)
elseif control > C.DeadZone then
	mouse(true, x, y)
elseif control < -C.DeadZone then
	mouse(false, x, y)
elseif held and barVel > fishVel + 35 then
	mouse(false, x, y)
elseif not held and barVel < fishVel - 35 then
	mouse(true, x, y)
end

if C.Debug then
	print(string.format("F %.1f B %.1f FV %.1f BV %.1f E %.1f C %.1f H %s", fx, bx, fishVel, barVel, error, control, tostring(held)))
end

if os.clock() - stateStart > C.MaxReel then
	release(x, y)
	setState("RESET")
	return
end

task.wait(C.ReelTick)
end

local function reset()
release()
task.wait(C.ResetDelay)
setState("CAST")
end

task.spawn(function()
task.wait(2)
print("[FISH BOT] Started")

while C.Enabled do
	if state == "CAST" then cast()
	elseif state == "SHAKE" then shake()
	elseif state == "REEL" then reel()
	elseif state == "RESET" then reset()
	end
	task.wait()
end

release()
end)
