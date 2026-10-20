local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local Fluent = loadstring(game:HttpGetAsync("https://github.com/ActualMasterOogway/Fluent-Renewed/releases/latest/download/Fluent.luau"))()
local InterfaceManager = loadstring(game:HttpGetAsync("https://raw.githubusercontent.com/ActualMasterOogway/Fluent-Renewed/master/Addons/InterfaceManager.luau"))()
local SaveManager = loadstring(game:HttpGetAsync("https://raw.githubusercontent.com/ActualMasterOogway/Fluent-Renewed/master/Addons/SaveManager.luau"))()

local Window, Options

local Player = Players.LocalPlayer
local Character = Player.Character or Player.CharacterAdded:Wait()
local HRP = Character:WaitForChild("HumanoidRootPart")

local SETTINGS = {
    Enabled = false,
    ParryThreshold = 0.40,
    CooldownTime = 0.35,
    TargetAttribute = "target",
    BallFolder = workspace:WaitForChild("Balls")
}

local State = {
    CurrentBall = nil,
    IsOnCooldown = false,
    LastParryTick = 0
}

local function Notify(title, text)
    if Window then
        Fluent:Notify({
            Title = title,
            Content = text,
            Duration = 3
        })
    else
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = 2
        })
    end
end

local function TriggerParry()
    local PlayerGui = Player:FindFirstChild("PlayerGui")
    local Hotbar = PlayerGui and PlayerGui:FindFirstChild("Hotbar")
    local BlockButton = Hotbar and Hotbar:FindFirstChild("Block")

    if not BlockButton then return end

    local eventTypes = {"Activated", "MouseButton1Down", "MouseButton1Click"}

    for _, eventName in ipairs(eventTypes) do
        local connections = getconnections(BlockButton[eventName])
        if #connections > 0 then
            for i = 1, #connections do
                connections[i]:Fire()
            end
            return 
        end
    end
end

local function GetTargetBall()
    local children = SETTINGS.BallFolder:GetChildren()
    for i = 1, #children do
        local ball = children[i]
        if ball:GetAttribute("realBall") and ball:GetAttribute(SETTINGS.TargetAttribute) == Player.Name then
            return ball
        end
    end
    return nil
end

local function ToggleParry()
    SETTINGS.Enabled = not SETTINGS.Enabled
    if Options and Options.EnableParry then
        Options.EnableParry:SetValue(SETTINGS.Enabled)
    else
        Notify("Auto Parry", "Status: " .. (SETTINGS.Enabled and "ENABLED" or "DISABLED"))
    end
end

Window = Fluent:CreateWindow({
    Title = "Aevrix Hub " .. Fluent.Version,
    SubTitle = "Auto-Parry",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 420),
    Acrylic = false,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tabs = {
    Main = Window:CreateTab({ Title = "Main", Icon = "sword" }),
    Settings = Window:CreateTab({ Title = "Settings", Icon = "settings" })
}

Options = Fluent.Options

Tabs.Main:CreateToggle("EnableParry", {
    Title = "Enable Auto Parry",
    Description = "Master switch for the parry engine",
    Default = false
})

Options.EnableParry:OnChanged(function(Value)
    SETTINGS.Enabled = Value
    Notify("Auto Parry", "Status: " .. (Value and "ENABLED" or "DISABLED"))
end)

Tabs.Main:CreateSlider("ParryThreshold", {
    Title = "Parry Threshold",
    Description = "Time before impact to trigger parry",
    Default = 0.40,
    Min = 0.1,
    Max = 1.0,
    Rounding = 2,
    Callback = function(Value)
        SETTINGS.ParryThreshold = Value
    end
})

Tabs.Main:CreateSlider("CooldownTime", {
    Title = "Cooldown",
    Description = "Minimum seconds between parry attempts",
    Default = 0.35,
    Min = 0.1,
    Max = 1.0,
    Rounding = 2,
    Callback = function(Value)
        SETTINGS.CooldownTime = Value
    end
})

Tabs.Main:CreateKeybind("ToggleKeybind", {
    Title = "Toggle Auto Parry",
    Mode = "Toggle",
    Default = "K",
    Callback = function()
        ToggleParry()
    end
})

InterfaceManager:SetLibrary(Fluent)
InterfaceManager:SetFolder("Aevrix Hub")
InterfaceManager:BuildInterfaceSection(Tabs.Settings)

SaveManager:SetLibrary(Fluent)
SaveManager:SetFolder("Aevrix Hub")
SaveManager:BuildConfigSection(Tabs.Settings)
SaveManager:LoadAutoloadConfig()

Window:SelectTab(1)

RunService.Heartbeat:Connect(function()
    if not SETTINGS.Enabled or State.IsOnCooldown then return end

    local Ball = State.CurrentBall or GetTargetBall()
    if not Ball then 
        State.CurrentBall = nil
        return 
    end

    local rootPart = Character and Character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return end

    local Velocity = Ball.zoomies.VectorVelocity.Magnitude
    local Distance = (rootPart.Position - Ball.Position).Magnitude

    if Velocity <= 0 or Distance <= 0 then return end

    local toPlayer = (rootPart.Position - Ball.Position).Unit
    local isApproaching = toPlayer:Dot(Ball.zoomies.VectorVelocity.Unit) > 0
    if not isApproaching then return end

    local TimeToImpact = Distance / Velocity

    if TimeToImpact <= SETTINGS.ParryThreshold then
        State.IsOnCooldown = true
        State.LastParryTick = tick()

        TriggerParry()

        task.delay(SETTINGS.CooldownTime, function()
            State.IsOnCooldown = false
        end)
    end
end)

Player.CharacterAdded:Connect(function(newChar)
    Character = newChar
    HRP = newChar:WaitForChild("HumanoidRootPart")
end)

