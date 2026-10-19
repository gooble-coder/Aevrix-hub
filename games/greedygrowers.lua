local LoadStarted = os.clock()

local function Loading(percent, text)
    print(string.format("[Gooble] [%d%%] %s", percent, text))
end

Loading(0, "Starting...")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

if not game:IsLoaded() then
    Loading(5, "Waiting for game...")
    game.Loaded:Wait()
end

Loading(10, "Game loaded")

local Player = Players.LocalPlayer
local Knit = require(
    ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Knit")
)

local Info = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Info")
local SeedConfig = require(Info:WaitForChild("SeedConfig"))
local CustomEnum = require(Info:WaitForChild("CustomEnum"))

Loading(20, "Core modules loaded")
Loading(25, "Waiting for Knit...")

Knit.OnStart():await()

Loading(30, "Knit ready")

local DataClient = Knit.GetController("DataClient")
local SeedService = Knit.GetService("SeedConveyorService")
local PlantService = Knit.GetService("PlantRoundService")
local PlotService = Knit.GetService("PlayerPlotService")
local SellService = Knit.GetService("SellStandService")

Loading(35, "Game services ready")

local S = {
    AutoFarm = false,
    AutoSell = true,
    CashReserve = 0,
    MinRarity = "COMMON",
    ScanDelay = 0.05
}

local RARITIES = {
    "COMMON","RARE","EPIC","LEGENDARY","MYTHIC","CELESTIAL",
    "SECRET","DIVINE","TRANSCENDENT","ANCIENT","ETHEREAL","GODLY"
}

local RANK = {}

for i, v in ipairs(RARITIES) do
    RANK[v] = i
end

local state = "IDLE"
local queued = false
local plot
local pending
local failed = {}
local cycle
local recover

local function call(fn)
    local luaOK, promiseOK, result = pcall(fn)

    if not luaOK or not promiseOK then
        return false, result
    end

    return true, result
end

local function money()
    local d = DataClient.currentData

    return d
        and d.Currency
        and d.Currency[CustomEnum.CURRENCIES.COINS]
        or 0
end

local function getPlot()
    if plot and plot.Parent then
        return plot
    end

    local field = workspace:FindFirstChild("BigField")
    local plots = field and field:FindFirstChild("PlayerPlots")

    if not plots then return end

    local ok, id = call(function()
        return PlotService:GetMyPlot():await()
    end)

    if ok and id then
        plot = plots:FindFirstChild(
            "PlayerPlot" .. tostring(id)
        )
    end

    return plot
end

local function findSeed(seedType)
    for _, container in ipairs({
        Player.Character,
        Player:FindFirstChildOfClass("Backpack")
    }) do
        if container then
            for _, tool in ipairs(container:GetChildren()) do
                if tool:IsA("Tool")
                    and tool:GetAttribute("IsSeed")
                    and tool:GetAttribute("SeedType") == seedType then

                    return tool
                end
            end
        end
    end
end

local function equip(tool)
    local char = Player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")

    if not tool or not hum then
        return false
    end

    if tool.Parent ~= char then
        hum:EquipTool(tool)
        task.wait(0.02)
    end

    return tool.Parent == char
end

local function bestSeed()
    local field = workspace:FindFirstChild("BigField")
    local conveyor = field and field:FindFirstChild("ConveyorSeeds")

    if not conveyor then return end

    local cash = math.max(
        0,
        money() - S.CashReserve
    )

    local min = RANK[S.MinRarity] or 1
    local best
    local free

    for _, holder in ipairs(conveyor:GetChildren()) do
        local seedType = holder:GetAttribute("SeedType")
        local id = holder:GetAttribute("SpawnId")
        local rarity = holder:GetAttribute("Rarity")
        local prompt = holder:FindFirstChildWhichIsA(
            "ProximityPrompt",
            true
        )

        if not seedType
            or not id
            or (failed[id] and os.clock() < failed[id])
            or not prompt
            or not prompt.Enabled
            or (RANK[rarity] or 0) < min then

            continue
        end

        local cfg = SeedConfig.GetSeed(seedType)

        if not cfg then
            continue
        end

        local cost = cfg.plantCost or 0

        local seed = {
            type = seedType,
            id = id,
            cost = cost
        }

        if cost == 0 then
            free = free or seed
        elseif cost <= cash
            and (not best or cost > best.cost) then

            best = seed
        end
    end

    return best or free
end

local function buy(seed)
    state = "BUYING"

    local ok, result = call(function()
        return SeedService:RequestPurchase(
            seed.id
        ):await()
    end)

    failed[seed.id] = os.clock() + 0.5

    if not ok or result == false then
        return false
    end

    pending = {
        type = seed.type,
        time = os.clock()
    }

    return true
end

local function plant()
    local seed = pending

    if not seed then
        return false
    end

    state = "PLANTING"

    local seedType = seed.type
    local tool = findSeed(seedType)
    local started = os.clock()

    while not tool
        and os.clock() - started < 0.75 do

        task.wait(0.015)

        if pending ~= seed then
            return false
        end

        tool = findSeed(seedType)
    end

    if not tool then
        if pending == seed
            and os.clock() - seed.time > 4 then

            pending = nil
        end

        return false
    end

    if not equip(tool) then
        return false
    end

    local p = getPlot()

    if not p then
        return false
    end

    local root = Player.Character
        and Player.Character:FindFirstChild(
            "HumanoidRootPart"
        )

    if not root then
        return false
    end

    root.CFrame = p:GetPivot()

    if pending ~= seed then
        return false
    end

    local ok, result = call(function()
        return PlantService:StartRound(
            seedType,
            "None"
        ):await()
    end)

    if not ok or result == false then
        return false
    end

    if pending == seed then
        pending = nil
    end

    state = "GROWING"

    return true
end

local function sell()
    if not S.AutoSell then
        return false
    end

    state = "SELLING"

    for _ = 1, 12 do
        if not S.AutoSell then
            state = "IDLE"
            return false
        end

        local ok, result = call(function()
            return SellService:SellAll():await()
        end)

        if ok and result ~= false then
            state = "IDLE"
            return true
        end

        task.wait(0.025)
    end

    state = "IDLE"

    return false
end

local function queue(delay)
    if queued or not S.AutoFarm then
        return
    end

    queued = true

    task.delay(delay or 0, function()
        queued = false
        cycle()
    end)
end

recover = function()
    if not S.AutoFarm then
        state = "CRASHED"
        return
    end

    if state == "RECOVERING" then
        return
    end

    state = "RECOVERING"

    task.spawn(function()
        for _ = 1, 40 do
            if not S.AutoFarm then
                state = "CRASHED"
                return
            end

            local ok, result = call(function()
                return PlantService:CollectDeadTree():await()
            end)

            if ok and result ~= false then
                if S.AutoSell then
                    sell()
                else
                    state = "IDLE"
                end

                queue()
                return
            end

            task.wait(0.025)
        end

        state = "IDLE"
        queue()
    end)
end

cycle = function()
    if not S.AutoFarm
        or state ~= "IDLE" then

        return
    end

    if pending then
        if not plant()
            and state == "PLANTING" then

            state = "IDLE"
            queue(0.03)
        end

        return
    end

    local seed = bestSeed()

    if not seed then
        return
    end

    if not buy(seed) then
        state = "IDLE"
        queue(0.03)
        return
    end

    state = "IDLE"
    queue()
end

PlantService.RoundStartedAll:Connect(function(userId)
    if userId ~= Player.UserId then
        return
    end

    pending = nil
    state = "GROWING"
end)

PlantService.CrashedAll:Connect(function(userId)
    if userId ~= Player.UserId
        or state == "RECOVERING"
        or state == "SELLING" then

        return
    end

    recover()
end)

PlantService.PlantStoppedAll:Connect(function(userId)
    if userId ~= Player.UserId
        or state == "RECOVERING"
        or state == "SELLING" then

        return
    end

    task.spawn(function()
        if S.AutoSell then
            sell()
        else
            state = "IDLE"
        end

        queue()
    end)
end)

PlantService.RoundResetAll:Connect(function(userId)
    if userId ~= Player.UserId
        or state == "RECOVERING"
        or state == "SELLING" then

        return
    end

    state = "IDLE"
    queue()
end)

SeedService.SeedSpawned:Connect(function()
    if S.AutoFarm
        and state == "IDLE"
        and not pending then

        queue(0.37)
    end
end)

Loading(40, "Automation ready")
Loading(45, "Waiting for player data...")

while not DataClient.currentData do
    task.wait(0.025)
end

Loading(50, "Player data ready")

task.spawn(function()
    getPlot()
end)

Loading(55, "Loading Fluent...")

local Library = loadstring(
    game:HttpGetAsync(
        "https://github.com/ActualMasterOogway/Fluent-Renewed/releases/latest/download/Fluent.luau"
    )
)()

Loading(75, "Fluent loaded")
Loading(80, "Loading InterfaceManager...")

local InterfaceManager = loadstring(
    game:HttpGetAsync(
        "https://raw.githubusercontent.com/ActualMasterOogway/Fluent-Renewed/master/Addons/InterfaceManager.luau"
    )
)()

Loading(90, "InterfaceManager loaded")
Loading(93, "Building UI...")

local Window = Library:CreateWindow{
    Title = "Gooble",
    SubTitle = "Auto Farm",
    TabWidth = 160,
    Size = UDim2.fromOffset(680, 460),
    Resize = true,
    MinSize = Vector2.new(520, 380),
    Acrylic = false,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.RightControl
}

local Tabs = {
    Main = Window:CreateTab{
        Title = "Main",
        Icon = "sprout"
    },

    Hotkeys = Window:CreateTab{
        Title = "Hotkeys",
        Icon = "keyboard"
    },

    Settings = Window:CreateTab{
        Title = "Settings",
        Icon = "settings"
    }
}

local Status = Tabs.Main:CreateParagraph(
    "Status",
    {
        Title = "Status",
        Content = "Auto Farm: OFF"
    }
)

local Farm = Tabs.Main:CreateToggle(
    "AutoFarm",
    {
        Title = "Auto Farm",
        Description = "Automatically buys, plants and recovers.",
        Default = false
    }
)

Farm:OnChanged(function(value)
    S.AutoFarm = value

    if not value then
        return
    end

    if state == "CRASHED" then
        recover()
    elseif state == "IDLE" then
        queue()
    end
end)

local AutoSell = Tabs.Main:CreateToggle(
    "AutoSell",
    {
        Title = "Auto Sell",
        Description = "Automatically sells after harvest or recovery.",
        Default = true
    }
)

AutoSell:OnChanged(function(value)
    S.AutoSell = value
end)

local Rarity = Tabs.Main:CreateDropdown(
    "Rarity",
    {
        Title = "Minimum Rarity",
        Description = "Ignore seeds below this rarity.",
        Values = RARITIES,
        Multi = false,
        Default = 1
    }
)

Rarity:SetValue(S.MinRarity)

Rarity:OnChanged(function(value)
    S.MinRarity = value

    if S.AutoFarm
        and state == "IDLE" then

        queue()
    end
end)

local Reserve = Tabs.Main:CreateInput(
    "Reserve",
    {
        Title = "Cash Reserve",
        Description = "Money that the bot will not spend.",
        Default = "0",
        Placeholder = "0",
        Numeric = true,
        Finished = true
    }
)

Reserve:OnChanged(function()
    S.CashReserve = math.max(
        0,
        tonumber(Reserve.Value) or 0
    )

    if S.AutoFarm
        and state == "IDLE" then

        queue()
    end
end)

Tabs.Hotkeys:CreateKeybind(
    "FarmKey",
    {
        Title = "Auto Farm Hotkey",
        Description = "Toggle Auto Farm",
        Default = "F6",
        Mode = "Hold",

        Callback = function(v)
            if v then
                Farm:SetValue(
                    not Farm.Value
                )
            end
        end
    }
)

Tabs.Hotkeys:CreateKeybind(
    "SellKey",
    {
        Title = "Auto Sell Hotkey",
        Description = "Toggle Auto Sell",
        Default = "F7",
        Mode = "Hold",

        Callback = function(v)
            if v then
                AutoSell:SetValue(
                    not AutoSell.Value
                )
            end
        end
    }
)

Tabs.Hotkeys:CreateParagraph(
    "HotkeyInfo",
    {
        Title = "UI Hotkey",
        Content = "RightControl = Minimize / Open UI"
    }
)

Loading(96, "Applying settings...")

pcall(function()
    InterfaceManager:SetLibrary(Library)
    InterfaceManager:SetFolder("Gooble")
    InterfaceManager:BuildInterfaceSection(
        Tabs.Settings
    )
end)

Window:SelectTab(1)

task.spawn(function()
    while not Library.Unloaded do
        task.wait(0.25)

        Status:SetValue(
            string.format(
                "State: %s\nCoins: %d\nAuto Farm: %s\nAuto Sell: %s\nMin Rarity: %s\nCash Reserve: %d",
                state,
                math.floor(money()),
                S.AutoFarm and "ON" or "OFF",
                S.AutoSell and "ON" or "OFF",
                S.MinRarity,
                S.CashReserve
            )
        )
    end
end)

task.spawn(function()
    while true do
        task.wait(S.ScanDelay)

        if S.AutoFarm
            and state == "IDLE" then

            queue()
        end
    end
end)

Loading(
    100,
    string.format(
        "Ready, Loaded in %.2fs",
        os.clock() - LoadStarted
    )
)
