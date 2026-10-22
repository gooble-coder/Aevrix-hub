if not game:IsLoaded() then game.Loaded:Wait() end
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local Environment = (getgenv and getgenv()) or _G
if Environment.AevrixMM2 and type(Environment.AevrixMM2.Stop) == "function" then pcall(Environment.AevrixMM2.Stop) end
local CurrentRoundClient = require(
    ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CurrentRoundClient")
)
local GameplayRemotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Gameplay")
local Fluent = loadstring(game:HttpGetAsync(
    "https://github.com/ActualMasterOogway/Fluent-Renewed/releases/latest/download/Fluent.luau"
))()
local InterfaceManager = loadstring(game:HttpGetAsync(
    "https://raw.githubusercontent.com/ActualMasterOogway/Fluent-Renewed/master/Addons/InterfaceManager.luau"
))()
local Settings = {
    ESPEnabled = false, -- one toggle: Murderer red, Sheriff/Hero blue, other active players green
    GunESP = false,
    AutoGunTP = false,
    FarmEnabled = false,
    MurderKillAll = false,
    SheriffAuto = false,
    KnifeAimbot = false, -- same shared first-person aim tracking as Gun Aimbot; ignores wall obstruction
    GunAimbot = false, -- supports first-person aim tracking and targets behind walls
    FlySpeed = 30, -- default studs per second; adjustable in the Farm tab
    PlayerWalkSpeed = 16, -- set from the current Humanoid below; inert until adjusted
    PlayerJumpHeight = 7.2, -- set from the current Humanoid below; inert until adjusted
    ClickTP = false, -- Ctrl + world click by default; rebindable below
    SpinFling = false, -- physics spin fling is disabled at startup
    SpinFlingSpeed = 130, -- angular speed in radians/second
    SpinTarget = "None (Manual)", -- player dropdown, no auto approach by default
    FarmPriority = "Coins First", -- can be changed live with the Fluent dropdown
    AutoCraft = false,
    AutoBattlePassBuy = false, -- disabled on startup; spends earned event currency only
    AutoBattlePassClaim = false, -- disabled on startup; free unlocked tiers only
    AutoSalvage = false, -- only duplicate, non-event, non-equipped weapons
    CraftMode = "Standard",
    CraftGoal = 10, -- maximum automatic craft requests per activation
    SalvageRarity = "Common",
    KeepCopies = 1,
}
local StartingHumanoid = LocalPlayer.Character
    and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
if StartingHumanoid then
    Settings.PlayerWalkSpeed = StartingHumanoid.WalkSpeed
    Settings.PlayerJumpHeight = StartingHumanoid.JumpHeight
end
local Running = true
local Connections = {}
local PlayerConnections = {}
local Highlights = {}
local GunMarks = {}
local CoinRecords = {}
local CoinCooldowns = setmetatable({}, { __mode = "k" })
local FullCurrencies = {}
local ActiveCurrencies = {} -- currencies announced for this round via CoinsStarted
local Red = Color3.fromRGB(255, 65, 75)
local Blue = Color3.fromRGB(65, 155, 255)
local Green = Color3.fromRGB(75, 225, 115)
local Gold = Color3.fromRGB(255, 203, 57)
local FarmToggle
local TeleportedDrops = setmetatable({}, { __mode = "k" })
local PendingGunTPs = setmetatable({}, { __mode = "k" })
local GUN_TP_DELAY = 3 -- seconds between detecting a gun drop and teleporting
local tryAutoGunTeleport
local refreshAutoGunTeleport
local getCombatMode
-- ============================== ROLE ESP ==============================
local function removeHighlight(player)
    local highlight = Highlights[player]
    if highlight then
        Highlights[player] = nil
        highlight:Destroy()
    end
end
local function refreshPlayer(player)
    if not Running or player == LocalPlayer then return end
    local info = (CurrentRoundClient.PlayerData or {})[player.Name]
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not Settings.ESPEnabled
        or type(info) ~= "table"
        or info.Dead == true
        or not character
        or not character.Parent
        or not humanoid
        or humanoid.Health <= 0 then
        removeHighlight(player)
        return
    end
    local color
    if info.Role == "Murderer" then
        color = Red
    elseif info.Role == "Sheriff" or info.Role == "Hero" then
        color = Blue
    elseif type(info.Role) == "string" and info.Role ~= "" then
        color = Green
    end
    if not color then
        removeHighlight(player)
        return
    end
    local highlight = Highlights[player]
    if highlight and (highlight.Parent ~= character or highlight.Adornee ~= character) then
        removeHighlight(player)
        highlight = nil
    end
    if not highlight then
        highlight = Instance.new("Highlight")
        highlight.Name = "AEVRIX_RoleESP"
        highlight.Adornee = character
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.FillTransparency = 0.55
        highlight.OutlineTransparency = 0
        highlight.Parent = character
        Highlights[player] = highlight
    end
    highlight.FillColor = color
    highlight.OutlineColor = color
    highlight.Enabled = true
end
local function refreshAll()
    if not Running then return end
    for _, player in ipairs(Players:GetPlayers()) do
        refreshPlayer(player)
    end
end
local function disconnectPlayer(player)
    removeHighlight(player)
    local record = PlayerConnections[player]
    if not record then return end
    for _, connection in pairs(record) do
        if typeof(connection) == "RBXScriptConnection" then connection:Disconnect() end
    end
    PlayerConnections[player] = nil
end
local function watchPlayer(player)
    if player == LocalPlayer or PlayerConnections[player] then return end
    local record = {}
    PlayerConnections[player] = record
    local function characterAdded(character)
        removeHighlight(player)
        if record.died then
            record.died:Disconnect()
            record.died = nil
        end
        task.spawn(function()
            local humanoid = character:FindFirstChildOfClass("Humanoid")
                or character:WaitForChild("Humanoid", 8)
            if not Running or player.Character ~= character then return end
            if humanoid then
                record.died = humanoid.Died:Connect(function()
                    removeHighlight(player)
                end)
            end
            refreshAll()
        end)
    end
    record.added = player.CharacterAdded:Connect(characterAdded)
    record.removing = player.CharacterRemoving:Connect(function()
        removeHighlight(player)
    end)
    if player.Character then characterAdded(player.Character) end
end
-- =========================== DROPPED GUN ESP =========================
local DropNames = {
    gundrop = true,
    droppedgun = true,
    gun_drop = true,
}
local function isDropObject(item)
    if not item or not (item:IsA("BasePart") or item:IsA("Model")) then return false end
    if not DropNames[string.lower(item.Name)] then return false end
    if not item:IsDescendantOf(Workspace) then return false end
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character and item:IsDescendantOf(player.Character) then return false end
    end
    return true
end
local function dropPart(item)
    if item:IsA("BasePart") then return item end
    return item:FindFirstChildWhichIsA("BasePart", true)
end
local function removeGunMark(item)
    local mark = GunMarks[item]
    if not mark then return end
    GunMarks[item] = nil
    if mark.Highlight then mark.Highlight:Destroy() end
    if mark.Billboard then mark.Billboard:Destroy() end
end
local function clearGunMarks()
    for item in pairs(GunMarks) do
        removeGunMark(item)
    end
end
local function addGunMark(item)
    if not Running or not Settings.GunESP or GunMarks[item]
        or not isDropObject(item) then
        return
    end
    local part = dropPart(item)
    if not part then return end
    local mark = {}
    GunMarks[item] = mark
    local highlight = Instance.new("Highlight")
    highlight.Name = "AEVRIX_DroppedGunESP"
    highlight.Adornee = item
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillColor = Gold
    highlight.OutlineColor = Gold
    highlight.FillTransparency = 0.35
    highlight.OutlineTransparency = 0
    highlight.Parent = item
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "AEVRIX_DroppedGunLabel"
    billboard.Adornee = part
    billboard.Size = UDim2.fromOffset(150, 36)
    billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.7, 0)
    billboard.AlwaysOnTop = true
    billboard.ResetOnSpawn = false
    local label = Instance.new("TextLabel")
    label.Name = "Label"
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Text = "DROPPED GUN"
    label.Font = Enum.Font.GothamBold
    label.TextSize = 15
    label.TextColor3 = Gold
    label.TextStrokeColor3 = Color3.fromRGB(10, 10, 15)
    label.TextStrokeTransparency = 0.15
    label.Parent = billboard
    billboard.Parent = part
    mark.Highlight = highlight
    mark.Billboard = billboard
end
local function findGunDropAncestor(item)
    local current = item
    while current and current ~= Workspace do
        if (current:IsA("BasePart") or current:IsA("Model"))
            and DropNames[string.lower(current.Name)] then
            return current
        end
        current = current.Parent
    end
    return nil
end
local function refreshGunESP()
    if not Running or not Settings.GunESP then
        clearGunMarks()
        return
    end
    for _, item in ipairs(Workspace:GetDescendants()) do
        if isDropObject(item) then addGunMark(item) end
    end
    for item in pairs(GunMarks) do
        if not isDropObject(item) then removeGunMark(item) end
    end
end
table.insert(Connections, Workspace.DescendantAdded:Connect(function(item)
    if not Running or not (Settings.GunESP or Settings.AutoGunTP) then return end
    local gun = findGunDropAncestor(item)
    if not gun then return end
    if Settings.GunESP then addGunMark(gun) end
    if Settings.AutoGunTP and tryAutoGunTeleport then tryAutoGunTeleport(gun) end
end))
table.insert(Connections, Workspace.DescendantRemoving:Connect(function(item)
    if GunMarks[item] then removeGunMark(item) end
    if TeleportedDrops[item] then TeleportedDrops[item] = nil end
    PendingGunTPs[item] = nil
end))
-- ======================== COIN / CANDY DETECTION =======================
local function getCoinContainer(coin)
    local ancestor = coin.Parent
    while ancestor and ancestor ~= Workspace do
        if ancestor.Name == "CoinContainer" then return ancestor end
        ancestor = ancestor.Parent
    end
    return nil
end
local function isEligibleCoin(coin)
    if not coin or not coin:IsA("BasePart")
        or coin.Name ~= "Coin_Server"
        or not coin:IsDescendantOf(Workspace)
        or not getCoinContainer(coin) then
        return false
    end
    local currency = coin:GetAttribute("CoinID")
    if type(currency) ~= "string" or currency == "" or FullCurrencies[currency] then return false end
    if coin:GetAttribute("Collected") == true
        or coin:GetAttribute("RoundEnd") == true then
        return false
    end
    local visual = coin:FindFirstChild("CoinVisual")
    if visual and (visual:GetAttribute("Collected") == true
        or visual:GetAttribute("Delete") == true) then
        return false
    end
    return true
end
local TargetCoin
local TargetNearSince
local TargetBestDistance = math.huge
local TargetProgressAt = 0
local Flight
local LastTargetSearch = 0
local function clearTarget()
    TargetCoin = nil
    TargetNearSince = nil
    TargetBestDistance = math.huge
    TargetProgressAt = 0
end
local function untrackCoin(coin)
    if TargetCoin == coin then clearTarget() end
    local record = CoinRecords[coin]
    if not record then return end
    CoinRecords[coin] = nil
    for _, connection in ipairs(record) do
        connection:Disconnect()
    end
end
local function trackCoin(coin)
    if not coin or not coin:IsA("BasePart")
        or coin.Name ~= "Coin_Server" or CoinRecords[coin] then
        return
    end
    local record = {}
    CoinRecords[coin] = record
    table.insert(record, coin:GetAttributeChangedSignal("Collected"):Connect(function()
        if TargetCoin == coin and not isEligibleCoin(coin) then clearTarget() end
    end))
    table.insert(record, coin:GetAttributeChangedSignal("CoinID"):Connect(function()
        if TargetCoin == coin and not isEligibleCoin(coin) then clearTarget() end
    end))
    table.insert(record, coin.AncestryChanged:Connect(function()
        if not coin:IsDescendantOf(Workspace) then untrackCoin(coin) end
    end))
end
for _, item in ipairs(Workspace:GetDescendants()) do
    if item:IsA("BasePart") and item.Name == "Coin_Server" then trackCoin(item) end
end
table.insert(Connections, Workspace.DescendantAdded:Connect(function(item)
    if item:IsA("BasePart") and item.Name == "Coin_Server" then trackCoin(item) end
end))
table.insert(Connections, Workspace.DescendantRemoving:Connect(function(item)
    if CoinRecords[item] then untrackCoin(item) end
end))
table.insert(Connections, CollectionService:GetInstanceAddedSignal("CoinVisual"):Connect(function(item)
    local parent = item.Parent
    if parent and parent:IsA("BasePart") and parent.Name == "Coin_Server" then trackCoin(parent) end
end))
local function selectNearestCoin(root)
    local currentTime = time()
    if currentTime - LastTargetSearch < 0.2 then return nil end
    LastTargetSearch = currentTime
    local closest, bestDistance
    bestDistance = math.huge
    for coin in pairs(CoinRecords) do
        if isEligibleCoin(coin) and (CoinCooldowns[coin] or 0) <= currentTime then
            local distance = (coin.Position - root.Position).Magnitude
            if distance < bestDistance then
                closest = coin
                bestDistance = distance
            end
        end
    end
    return closest
end
local function allCurrencyBagsFull()
    if next(FullCurrencies) == nil then return false end
    local foundCurrency = false
    for currencyID in pairs(ActiveCurrencies) do
        foundCurrency = true
        if not FullCurrencies[currencyID] then return false end
    end
    if foundCurrency then return true end
    for coin in pairs(CoinRecords) do
        if coin:IsDescendantOf(Workspace) then
            local currencyID = coin:GetAttribute("CoinID")
            if type(currencyID) == "string" and currencyID ~= "" then
                foundCurrency = true
                if not FullCurrencies[currencyID] then return false end
            end
        end
    end
    return foundCurrency or next(FullCurrencies) ~= nil
end
-- =========================== PHYSICAL FLIGHT ==========================
local function releaseFlight()
    if not Flight then return end
    local old = Flight
    Flight = nil
    if old.Velocity then old.Velocity:Destroy() end
    if old.Gyro then old.Gyro:Destroy() end
    for _, conn in ipairs(old.CollisionConnections) do conn:Disconnect() end
    for part, originallyCollidable in pairs(old.OriginalCollisions) do
        if part.Parent then part.CanCollide = originallyCollidable end
    end
    if old.Humanoid and old.Humanoid.Parent then
        old.Humanoid.PlatformStand = old.OriginalPlatformStand
        old.Humanoid.AutoRotate = old.OriginalAutoRotate
    end
end
local function watchFlightCollisions(flight)
    local function trackPart(part)
        if not part:IsA("BasePart") or flight.OriginalCollisions[part] ~= nil then return end
        flight.OriginalCollisions[part] = part.CanCollide
        table.insert(flight.CollisionConnections, part:GetPropertyChangedSignal("CanCollide"):Connect(function()
            if Flight == flight and part.CanCollide then part.CanCollide = false end
        end))
        part.CanCollide = false
    end
    for _, part in ipairs(flight.Character:GetDescendants()) do trackPart(part) end
    table.insert(flight.CollisionConnections, flight.Character.DescendantAdded:Connect(trackPart))
end
local function createFlight(character, humanoid, root, forCombat)
    if Flight and Flight.Character == character and Flight.Root == root
        and Flight.IsCombat == (forCombat == true)
        and Flight.Velocity and Flight.Velocity.Parent == root then
        return Flight
    end
    releaseFlight()
    local velocity = Instance.new("BodyVelocity")
    velocity.Name = "AEVRIX_CoinFlightVelocity"
    velocity.MaxForce = Vector3.new(1e8, 1e8, 1e8)
    velocity.P = 15000
    velocity.Velocity = Vector3.zero
    velocity.Parent = root
    local gyro = Instance.new("BodyGyro")
    gyro.Name = "AEVRIX_CoinFlightGyro"
    gyro.MaxTorque = Vector3.new(1e8, 1e8, 1e8)
    gyro.P = 30000
    gyro.D = 1200
    gyro.CFrame = root.CFrame
    gyro.Parent = root
    Flight = {
        Character = character,
        Humanoid = humanoid,
        Root = root,
        IsCombat = forCombat == true,
        Velocity = velocity,
        Gyro = gyro,
        OriginalPlatformStand = humanoid.PlatformStand,
        OriginalAutoRotate = humanoid.AutoRotate,
        OriginalCollisions = {}, CollisionConnections = {},
    }
    watchFlightCollisions(Flight)
    humanoid.AutoRotate = false
    humanoid.PlatformStand = forCombat ~= true
    return Flight
end
local function canFarmNow()
    local character = LocalPlayer.Character
    if not character or not character.Parent then return nil, "Waiting for character" end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root or humanoid.Health <= 0 then return nil, "Waiting to respawn" end
    local data = (CurrentRoundClient.PlayerData or {})[LocalPlayer.Name]
    if type(data) ~= "table" or data.Dead == true or not data.Role then return nil, "Waiting for an active round" end
    return { Character = character, Humanoid = humanoid, Root = root }, nil
end
local function setFarmEnabled(enabled)
    Settings.FarmEnabled = enabled == true
    clearTarget()
    LastTargetSearch = 0
    if not Settings.FarmEnabled then releaseFlight() end
end
-- ======================== AUTO TP TO DROPPED GUN =======================
local function performAutoGunTeleport(gun)
    if not Running or not Settings.AutoGunTP
        or (getCombatMode and getCombatMode() ~= nil)
        or not isDropObject(gun) or TeleportedDrops[gun] then
        return false
    end
    local part = dropPart(gun)
    if not part or not part:IsDescendantOf(Workspace) then return false end
    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root or not humanoid or humanoid.Health <= 0 then return false end
    local data = (CurrentRoundClient.PlayerData or {})[LocalPlayer.Name]
    if type(data) == "table" and data.Dead == true then return false end
    TeleportedDrops[gun] = true
    if Settings.FarmEnabled then
        setFarmEnabled(false)
        if FarmToggle and type(FarmToggle.SetValue) == "function" then pcall(function() FarmToggle:SetValue(false) end) end
    else
        releaseFlight()
    end
    local targetPosition = part.Position + Vector3.new(0, 2.5, 0)
    root.CFrame = CFrame.new(targetPosition) * root.CFrame.Rotation
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    return true
end
tryAutoGunTeleport = function(gun)
    if not Running or not Settings.AutoGunTP
        or (getCombatMode and getCombatMode() ~= nil)
        or not isDropObject(gun) or TeleportedDrops[gun]
        or PendingGunTPs[gun] then
        return false
    end
    local part = dropPart(gun)
    if not part or not part:IsDescendantOf(Workspace) then return false end
    local ticket = {}
    PendingGunTPs[gun] = ticket
    task.delay(GUN_TP_DELAY, function()
        if PendingGunTPs[gun] ~= ticket then return end
        PendingGunTPs[gun] = nil
        performAutoGunTeleport(gun)
    end)
    return true
end
refreshAutoGunTeleport = function()
    if not Running or not Settings.AutoGunTP then return end
    for _, item in ipairs(Workspace:GetDescendants()) do
        if isDropObject(item) and tryAutoGunTeleport(item) then return end
    end
end
table.insert(Connections, LocalPlayer.CharacterAdded:Connect(function()
    if not Settings.AutoGunTP then return end
    task.delay(0.6, function()
        if Running and Settings.AutoGunTP then refreshAutoGunTeleport() end
    end)
end))
-- ========================= AUTOMATIC COMBAT =========================
local CombatTarget
local CombatMode
local CombatTargetSince = 0
local CombatLastAttack = -math.huge
local CombatLastEquip = 0
local CombatNextScan = 0
local CombatNextTeleport = 0
local CombatReadyToAttackAt = 0
local CombatCooldowns = setmetatable({}, { __mode = "k" })
local CombatAimTarget
local KNIFE_ATTACK_GAP = 0.24
local GUN_ATTACK_GAP = 1.3
getCombatMode = function()
    local playerData = CurrentRoundClient.PlayerData or {}
    local me = playerData[LocalPlayer.Name]
    if type(me) ~= "table" or me.Dead == true then return nil end
    local mode
    if Settings.MurderKillAll and me.Role == "Murderer" then
        mode = "Knife"
    elseif Settings.SheriffAuto and (me.Role == "Sheriff" or me.Role == "Hero") then
        mode = "Gun"
    else
        return nil
    end
    if Settings.FarmEnabled and Settings.FarmPriority == "Coins First"
        and not allCurrencyBagsFull() then
        return nil
    end
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local entry = playerData[player.Name]
            local character = player.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            local root = character and character:FindFirstChild("HumanoidRootPart")
            if type(entry) == "table" and entry.Dead ~= true and root
                and humanoid and humanoid.Health > 0
                and ((mode == "Gun" and entry.Role == "Murderer")
                    or (mode == "Knife" and entry.Role and entry.Role ~= "Murderer")) then
                return mode
            end
        end
    end
    return nil
end
local function clearCombatTarget()
    CombatTarget = nil
    CombatTargetSince = 0
    CombatAimTarget = nil
    CombatNextTeleport = 0
    CombatReadyToAttackAt = 0
    CombatNextScan = 0
end
local function livingTarget(player, mode)
    if not player or player == LocalPlayer then return nil end
    local entry = (CurrentRoundClient.PlayerData or {})[player.Name]
    if type(entry) ~= "table" or entry.Dead == true then return nil end
    if mode == "Gun" and entry.Role ~= "Murderer" then return nil end
    if mode == "Knife" and (entry.Role == "Murderer" or not entry.Role) then return nil end
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root or not humanoid or humanoid.Health <= 0 then return nil end
    return root, character
end
local function nearestCombatTarget(myRoot, mode)
    local closest, shortest = nil, math.huge
    local now = time()
    for _, player in ipairs(Players:GetPlayers()) do
        local root = livingTarget(player, mode)
        if root and (CombatCooldowns[player] or 0) <= now then
            local dist = (root.Position - myRoot.Position).Magnitude
            if dist < shortest then
                shortest = dist
                closest = player
            end
        end
    end
    return closest
end
local function matchingWeapon(tool, mode)
    if not tool or not tool:IsA("Tool") then return false end
    if mode == "Knife" then
        return tool:HasTag("Weapon_Knife") or tool.Name == "Knife"
            or (tool:FindFirstChild("Stab") and tool:FindFirstChild("KnifeClient")) ~= nil
    end
    return tool:HasTag("Weapon_Gun") or tool.Name == "Gun"
        or tool:FindFirstChild("IsGun") ~= nil
end
local function equippedWeapon(avatar, mode)
    for _, child in ipairs(avatar.Character:GetChildren()) do
        if matchingWeapon(child, mode) then return child end
    end
    local now = time()
    if now - CombatLastEquip < 0.12 then return nil end
    CombatLastEquip = now
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
        or LocalPlayer:FindFirstChild("Backpack")
    if not backpack then return nil end
    for _, child in ipairs(backpack:GetChildren()) do
        if matchingWeapon(child, mode) then
            avatar.Humanoid:EquipTool(child)
            return nil
        end
    end
    return nil
end
local function weaponHasLineOfSight(from, to, myCharacter, theirCharacter)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { myCharacter, theirCharacter }
    return Workspace:Raycast(from, to - from, params) == nil
end
local function targetAimPosition(character, root)
    local head = character:FindFirstChild("Head")
    return (head and head:IsA("BasePart")) and head.Position
        or (root.Position + Vector3.new(0, 1.25, 0))
end
local function teleportNearTarget(avatar, targetRoot, targetCharacter, mode)
    local origin = targetRoot.Position
    local relative = avatar.Root.Position - origin
    local planar = Vector3.new(relative.X, 0, relative.Z)
    if planar.Magnitude < 0.05 then
        planar = -Vector3.new(targetRoot.CFrame.LookVector.X, 0,
            targetRoot.CFrame.LookVector.Z)
    end
    local forward = planar.Magnitude > 0.05 and planar.Unit or Vector3.new(1, 0, 0)
    local side = Vector3.new(-forward.Z, 0, forward.X)
    local aim = targetAimPosition(targetCharacter, targetRoot)
    local radius = mode == "Knife" and 2.05 or 9.5
    local overlap = OverlapParams.new()
    overlap.FilterType = Enum.RaycastFilterType.Exclude
    overlap.FilterDescendantsInstances = { avatar.Character, targetCharacter }
    overlap.MaxParts = 35
    local angles = {0, math.pi / 4, -math.pi / 4, math.pi / 2,
        -math.pi / 2, 3 * math.pi / 4, -3 * math.pi / 4, math.pi}
    for _, angle in ipairs(angles) do
        local direction = forward * math.cos(angle) + side * math.sin(angle)
        local candidate = origin + direction * radius
        candidate += Vector3.new(0, 0.15, 0)
        local blocked = false
        for _, part in ipairs(Workspace:GetPartBoundsInBox(
            CFrame.new(candidate), Vector3.new(2.5, 3.4, 2.5), overlap
        )) do
            if part.CanCollide then
                blocked = true
                break
            end
        end
        if not blocked and (mode ~= "Gun" or weaponHasLineOfSight(
            candidate + Vector3.new(0, 1.0, 0), aim,
            avatar.Character, targetCharacter
        )) then
            avatar.Root.CFrame = CFrame.lookAt(candidate,
                Vector3.new(origin.X, candidate.Y, origin.Z))
            avatar.Root.AssemblyLinearVelocity = Vector3.zero
            avatar.Root.AssemblyAngularVelocity = Vector3.zero
            return true
        end
    end
    return false
end
-- ======================= FIRST-PERSON CAMERA AIM ======================
local function cameraUsesCenter(camera)
    if LocalPlayer.CameraMode == Enum.CameraMode.LockFirstPerson
        or UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
        return true
    end
    local playerScripts = LocalPlayer:FindFirstChild("PlayerScripts")
    local mouseLock = playerScripts and playerScripts:FindFirstChild("MouseLock")
    if mouseLock and mouseLock:GetAttribute("Enabled") == true then return true end
    local character = LocalPlayer.Character
    local head = character and character:FindFirstChild("Head")
    return head ~= nil
        and (camera.CFrame.Position - head.Position).Magnitude < 1.35
end
local function weaponCrosshair(camera)
    local center = camera.ViewportSize * 0.5
    if cameraUsesCenter(camera) or not UserInputService.MouseEnabled then return center, true end
    return UserInputService:GetMouseLocation(), false
end
local function aimAtTarget(character, mode)
    local camera = Workspace.CurrentCamera
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not camera or not root or not root:IsA("BasePart") then return end
    local aimPoint = root.Position + Vector3.new(0, 1.25, 0)
    local cameraPosition = camera.CFrame.Position
    if (aimPoint - cameraPosition).Magnitude < 0.5 then return end
    local desired = CFrame.lookAt(cameraPosition, aimPoint)
    local cursor, usesCenter = weaponCrosshair(camera)
    if not usesCenter then
        local size = camera.ViewportSize
        if size.X > 0 and size.Y > 0 then
            local dx = (cursor.X / size.X - 0.5) * 2
            local dy = (cursor.Y / size.Y - 0.5) * 2
            local halfTan = math.tan(math.rad(camera.FieldOfView) * 0.5)
            local yaw = math.atan(dx * halfTan * size.X / size.Y)
            local pitch = math.atan(dy * halfTan)
            desired = desired * CFrame.Angles(pitch, yaw, 0)
        end
    end
    camera.CFrame = desired
end
-- ======================= MANUAL WEAPON AIMBOTS =======================
local ManualAimTarget
local ManualAimMode
local ManualAimNextScan = 0
local THIRD_PERSON_AIM_RADIUS = 390
local function clearManualAim()
    ManualAimTarget = nil
    ManualAimMode = nil
    ManualAimNextScan = 0
end
local function manualAimContext()
    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local info = (CurrentRoundClient.PlayerData or {})[LocalPlayer.Name]
    if not character or not root or not humanoid or humanoid.Health <= 0
        or type(info) ~= "table" or info.Dead == true then
        return nil
    end
    local mode
    if info.Role == "Murderer" and Settings.KnifeAimbot then
        mode = "Knife"
    elseif (info.Role == "Sheriff" or info.Role == "Hero") and Settings.GunAimbot then
        mode = "Gun"
    else
        return nil
    end
    for _, child in ipairs(character:GetChildren()) do
        if matchingWeapon(child, mode) then return mode, character end
    end
    return nil
end
local function aimCandidate(player, mode, camera)
    local root, character = livingTarget(player, mode)
    if not root then return nil end
    local point = root.Position + Vector3.new(0, 1.25, 0)
    local offset = point - camera.CFrame.Position
    local worldDistance = offset.Magnitude
    if worldDistance < 0.5 then return nil end
    local projected, onScreen = camera:WorldToViewportPoint(point)
    local cursor, centerLocked = weaponCrosshair(camera)
    local dx = projected.X - cursor.X
    local dy = projected.Y - cursor.Y
    local screenDistance = math.sqrt(dx * dx + dy * dy)
    local radius = if centerLocked then camera.ViewportSize.Magnitude * 0.55
        else THIRD_PERSON_AIM_RADIUS
    if onScreen and projected.Z > 0 and screenDistance <= radius then return character, screenDistance, true end
    if centerLocked then
        local alignment = math.clamp(camera.CFrame.LookVector:Dot(offset.Unit), -1, 1)
        local angularDistance = math.acos(alignment) / math.pi
        local fallbackScore = camera.ViewportSize.Magnitude
            * (0.85 + angularDistance) + worldDistance * 0.05
        return character, fallbackScore, false
    end
    return nil
end
local function findManualAimTarget(mode, camera)
    local best, bestScore, bestOnScreen
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local character, score, onScreen = aimCandidate(player, mode, camera)
            if character then
                score *= (player == ManualAimTarget and 0.68 or 1)
                if bestScore == nil
                    or (onScreen and not bestOnScreen)
                    or (onScreen == bestOnScreen and score < bestScore) then
                    best, bestScore, bestOnScreen = player, score, onScreen
                end
            end
        end
    end
    return best
end
local AimRenderBound = false
local function renderCombatAim()
    if not Running then return end
    if not CombatAimTarget and not Settings.KnifeAimbot and not Settings.GunAimbot then return end
    if CombatAimTarget and CombatMode == "Gun" then
        aimAtTarget(CombatAimTarget, "Gun")
        return
    end
    local mode = manualAimContext()
    if not mode then
        clearManualAim()
        return
    end
    local camera = Workspace.CurrentCamera
    if not camera then return end
    if mode ~= ManualAimMode then
        clearManualAim()
        ManualAimMode = mode
    end
    local now = time()
    if now >= ManualAimNextScan then
        ManualAimNextScan = now + 0.10
        ManualAimTarget = findManualAimTarget(mode, camera)
    end
    if not ManualAimTarget then return end
    local targetCharacter = aimCandidate(ManualAimTarget, mode, camera)
    if not targetCharacter then
        ManualAimTarget = nil
        ManualAimNextScan = 0
        return
    end
    aimAtTarget(targetCharacter, mode)
end
local function updateAimRenderBinding()
    local shouldBind = Running and (Settings.KnifeAimbot or Settings.GunAimbot or Settings.SheriffAuto)
    if shouldBind == AimRenderBound then return end
    AimRenderBound = shouldBind
    if shouldBind then
        RunService:BindToRenderStep("AEVRIX_CombatAim", Enum.RenderPriority.Camera.Value + 2, renderCombatAim)
    else
        RunService:UnbindFromRenderStep("AEVRIX_CombatAim")
    end
end
local function combatTick()
    local mode = getCombatMode()
    if mode ~= CombatMode then
        CombatMode = mode
        clearCombatTarget()
        CombatLastAttack = -math.huge
        if Flight then releaseFlight() end
        if mode then clearTarget() end
    end
    if not mode then
        CombatAimTarget = nil
        if Flight and Flight.IsCombat then releaseFlight() end
        return
    end
    local avatar = canFarmNow()
    if not avatar then
        clearCombatTarget()
        if Flight and Flight.IsCombat then releaseFlight() end
        return
    end
    if not livingTarget(CombatTarget, mode) then clearCombatTarget() end
    local now = time()
    if not CombatTarget and now >= CombatNextScan then
        CombatNextScan = now + 0.08
        CombatTarget = nearestCombatTarget(avatar.Root, mode)
        CombatTargetSince = now
        CombatReadyToAttackAt = now + 0.05
    end
    if not CombatTarget then
        CombatAimTarget = nil
        return
    end
    local targetRoot, targetCharacter = livingTarget(CombatTarget, mode)
    if not targetRoot then clearCombatTarget() return end
    if mode == "Knife" and now - CombatTargetSince > 2.7 then
        CombatCooldowns[CombatTarget] = now + 1.4
        clearCombatTarget()
        return
    end
    local weapon = equippedWeapon(avatar, mode)
    if not weapon then
        CombatAimTarget = nil
        return
    end
    local distance = (targetRoot.Position - avatar.Root.Position).Magnitude
    local targetAim = targetAimPosition(targetCharacter, targetRoot)
    local inRange = distance <= (mode == "Knife" and 2.85 or 15)
    local clearShot = mode == "Knife" or weaponHasLineOfSight(
        avatar.Root.Position + Vector3.new(0, 1, 0), targetAim,
        avatar.Character, targetCharacter)
    if (not inRange or not clearShot) and now >= CombatNextTeleport then
        local moved = teleportNearTarget(avatar, targetRoot, targetCharacter, mode)
        CombatNextTeleport = now + (mode == "Knife" and 0.35 or 0.6)
        if moved then
            CombatReadyToAttackAt = now + (mode == "Gun" and 0.09 or 0.045)
            distance = (targetRoot.Position - avatar.Root.Position).Magnitude
            inRange = distance <= (mode == "Knife" and 2.85 or 15)
            clearShot = mode == "Knife" or weaponHasLineOfSight(
                avatar.Root.Position + Vector3.new(0, 1, 0), targetAim,
                avatar.Character, targetCharacter)
        end
    end
    CombatAimTarget = mode == "Gun" and targetCharacter or nil
    if CombatAimTarget then aimAtTarget(targetCharacter, "Gun") end
    local interval = mode == "Knife" and KNIFE_ATTACK_GAP or GUN_ATTACK_GAP
    if inRange and clearShot and now >= CombatReadyToAttackAt
        and now - CombatLastAttack >= interval then
        CombatLastAttack = now
        pcall(function() weapon:Activate() end)
    end
end
local CombatTickAccum = 0
local FarmTickAccum = 0
table.insert(Connections, RunService.Heartbeat:Connect(function(deltaTime)
    if not Running then return end
    -- Suspend auto travel while the player is intentionally spinning.
    if Settings.SpinFling then return end
    if Settings.MurderKillAll or Settings.SheriffAuto or CombatMode then
        CombatTickAccum += deltaTime
        if CombatTickAccum >= 0.05 then
            CombatTickAccum = 0
            combatTick()
        end
    end
    if not Settings.FarmEnabled or CombatMode then return end
    FarmTickAccum += deltaTime
    if FarmTickAccum < (1 / 30) then return end
    FarmTickAccum = 0
    local avatar, reason = canFarmNow()
    if not avatar then
        clearTarget()
        releaseFlight()
        return
    end
    local root = avatar.Root
    if not isEligibleCoin(TargetCoin) then clearTarget() end
    if not TargetCoin then
        local newTarget = selectNearestCoin(root)
        if newTarget then
            TargetCoin = newTarget
            TargetProgressAt = time()
            TargetBestDistance = (root.Position - newTarget.Position).Magnitude
            TargetNearSince = nil
        else
            releaseFlight()
        end
    end
    if TargetCoin then
        local now = time()
        local delta = TargetCoin.Position - root.Position
        local distance = delta.Magnitude
        if distance < TargetBestDistance - 1.1 then
            TargetBestDistance = distance
            TargetProgressAt = now
        end
        if distance <= 2.8 then
            TargetNearSince = TargetNearSince or now
        else
            TargetNearSince = nil
        end
        if (TargetNearSince and now - TargetNearSince > 1.15)
            or (now - TargetProgressAt > 3.5) then
            CoinCooldowns[TargetCoin] = now + 4
            clearTarget()
            releaseFlight()
        else
            local flight = createFlight(avatar.Character, avatar.Humanoid, root)
            if distance <= 0.85 then
                flight.Velocity.Velocity = Vector3.zero
            else
                local speed = math.min(Settings.FlySpeed, math.max(5, distance * 3.5))
                flight.Velocity.Velocity = delta.Unit * speed
            end
            local planar = Vector3.new(delta.X, 0, delta.Z)
            if planar.Magnitude > 0.1 then
                flight.Gyro.CFrame = CFrame.lookAt(root.Position,
                    root.Position + planar.Unit)
            end
        end
    end
end))
table.insert(Connections, GameplayRemotes:WaitForChild("CoinCollected").OnClientEvent:Connect(
    function(currencyID, currentAmount, maximumAmount)
        if type(currencyID) == "string"
            and type(currentAmount) == "number"
            and type(maximumAmount) == "number"
            and currentAmount >= maximumAmount then
            FullCurrencies[currencyID] = true
            if TargetCoin and TargetCoin:GetAttribute("CoinID") == currencyID then
                clearTarget()
                releaseFlight()
            end
        end
    end
))
table.insert(Connections, GameplayRemotes:WaitForChild("CoinsStarted").OnClientEvent:Connect(function(roundBags)
    table.clear(FullCurrencies)
    table.clear(ActiveCurrencies)
    if type(roundBags) == "table" then
        for _, bagData in pairs(roundBags) do
            if type(bagData) == "table"
                and type(bagData.CurrencyID) == "string"
                and bagData.CurrencyID ~= "" then
                ActiveCurrencies[bagData.CurrencyID] = true
            end
        end
    end
    table.clear(CoinCooldowns)
    clearTarget()
    LastTargetSearch = 0
end))
table.insert(Connections, LocalPlayer.CharacterRemoving:Connect(function()
    clearTarget()
    clearCombatTarget()
    clearManualAim()
    releaseFlight()
end))
-- ========================== AUTO CRAFTING ============================
local CraftSync
local CraftProfile
local CraftInventoryRemote
local CraftEvent
local CraftEventRemote
local CraftInitProblem
local CraftBusy = false
local CraftCount = 0
local CraftSelectedId
local CraftRecipeMap = {}
local CraftRecipeDropdown
local AutoCraftToggle
local CraftWorkerActive = false
local CraftGeneration = 0
local AttemptedEventCrafts = {}
local LastSalvageOwnedCount = {} -- prevent duplicate requests while inventory is syncing
local syncOk, syncError = pcall(function()
    CraftSync = require(ReplicatedStorage:WaitForChild("Database"):WaitForChild("Sync"))
    CraftProfile = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ProfileData"))
    CraftInventoryRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Inventory")
end)
if not syncOk then
    CraftInitProblem = tostring(syncError)
    warn("[AEVRIX Crafting] " .. CraftInitProblem)
end
local function craftNotice(content, duration)
    if not Running then return end
    pcall(function()
        Fluent:Notify({ Title = "AEVRIX | Crafting", Content = content, Duration = duration or 4 })
    end)
end
local function getRecipe()
    if not CraftSelectedId then return nil end
    if Settings.CraftMode == "Standard" then return CraftSync and CraftSync.Recipes and CraftSync.Recipes[CraftSelectedId] end
    local info = CraftEvent and CraftEvent.EventStartInfo
    return info and info.CraftingRecipes and info.CraftingRecipes[CraftSelectedId]
end
local function recipeAffordable(recipe)
    if not recipe or not CraftProfile then return false, { "No recipe selected" } end
    local missing = {}
    if Settings.CraftMode == "Standard" then
        local owned = CraftProfile.Materials and CraftProfile.Materials.Owned or {}
        for materialId, need in pairs(recipe.Materials or {}) do
            local have = tonumber(owned[materialId]) or 0
            if have < need then table.insert(missing, string.format("%s: %d/%d", materialId, have, need)) end
        end
    else
        local eventProfile = CraftEvent and CraftProfile[CraftEvent.Title]
        if eventProfile and eventProfile.Crafted and eventProfile.Crafted[CraftSelectedId] then return false, { "Already crafted this event recipe" } end
        for _, ingredient in ipairs(recipe.Input or {}) do
            local group = CraftProfile[ingredient.ItemType]
            local owned = group and group.Owned or {}
            local have = tonumber(owned[ingredient.ItemID]) or 0
            local need = ingredient.Amount or 1
            if have < need then table.insert(missing, string.format("%s: %d/%d", ingredient.ItemID, have, need)) end
        end
    end
    table.sort(missing)
    return #missing == 0, missing
end
local function isAlreadyCraftedEvent(id)
    local data = CraftEvent and CraftProfile and CraftProfile[CraftEvent.Title]
    return data and data.Crafted and data.Crafted[id] == true
end
local function craftOne(manual)
    if not Running or CraftBusy or not CraftSync or not CraftProfile then return "busy" end
    local recipe = getRecipe()
    if not recipe then
        if manual then craftNotice("No recipe available. Try Refresh Recipes.") end
        return "missing-recipe"
    end
    local enough, missing = recipeAffordable(recipe)
    if not enough then
        if manual then craftNotice(table.concat(missing, " | "), 5) end
        return "missing-materials"
    end
    CraftBusy = true
    local ok, result, amount, itemType
    if Settings.CraftMode == "Standard" then
        local remote = CraftInventoryRemote and CraftInventoryRemote:FindFirstChild("Craft")
        if remote and remote:IsA("RemoteFunction") then
            ok, result, amount, itemType = pcall(function()
                return remote:InvokeServer(CraftSelectedId)
            end)
        else
            ok, result = false, "Standard craft remote not available"
        end
    else
        local remote = CraftEventRemote
        if isAlreadyCraftedEvent(CraftSelectedId) then
            CraftBusy = false
            return "already-crafted"
        end
        if AttemptedEventCrafts[CraftSelectedId] and not manual then
            CraftBusy = false
            return "already-requested"
        end
        if remote and remote:IsA("RemoteEvent") then
            local eventRecipeId = CraftSelectedId
            ok, result = pcall(function() remote:FireServer(eventRecipeId) end)
            if ok then AttemptedEventCrafts[eventRecipeId] = true end
        else
            ok, result = false, "Event craft remote not available"
        end
    end
    CraftBusy = false
    if not ok then
        craftNotice("Craft request failed: " .. tostring(result), 6)
        return "error"
    end
    if Settings.CraftMode == "Standard" then
        if result == nil or result == false then
            if manual then craftNotice("Server did not confirm a craft. Nothing counted.") end
            return "rejected"
        end
        if manual then craftNotice("Crafted: " .. tostring(result)) end
    elseif manual then
        craftNotice("Event craft requested; check your event inventory.", 5)
    end
    if not manual then CraftCount += 1 end
    return Settings.CraftMode == "Standard" and "crafted" or "requested"
end
local function eligibleSalvageCandidate(recipe)
    if Settings.CraftMode ~= "Standard" or not CraftSync or not CraftProfile then return nil end
    local rewardTable = CraftSync.SalvageRewards and CraftSync.SalvageRewards[Settings.SalvageRarity]
    if not rewardTable or type(rewardTable.Rewards) ~= "table" then return nil end
    local needed = false
    local materials = CraftProfile.Materials and CraftProfile.Materials.Owned or {}
    for materialId, required in pairs(recipe.Materials or {}) do
        if (tonumber(materials[materialId]) or 0) < required
            and rewardTable.Rewards[materialId] then
            needed = true
            break
        end
    end
    if not needed then return nil end
    local weapons = CraftProfile.Weapons
    if not weapons or type(weapons.Owned) ~= "table" then return nil end
    local keys = {}
    for itemId, quantity in pairs(weapons.Owned) do
        local item = CraftSync.Weapons and CraftSync.Weapons[itemId]
        if item and item.Rarity == Settings.SalvageRarity
            and item.Event == nil and item.Season == nil
            and item.ItemType ~= "Misc"
            and not (CraftSync.Codes and CraftSync.Codes[itemId])
            and (tonumber(quantity) or 0) > Settings.KeepCopies
            and LastSalvageOwnedCount[itemId] ~= (tonumber(quantity) or 0) then
            local equipped = weapons.Equipped
            local isEquipped = type(equipped) == "table" and (
                equipped.Knife == itemId or equipped.Gun == itemId
            )
            if not isEquipped then table.insert(keys, itemId) end
        end
    end
    table.sort(keys)
    return keys[1]
end
local function salvageOneDuplicate(recipe)
    if not Running or CraftBusy or not Settings.AutoSalvage
        or not Settings.AutoCraft then return "disabled" end
    local itemId = eligibleSalvageCandidate(recipe)
    if not itemId then return "no-duplicate" end
    local remote = CraftInventoryRemote and CraftInventoryRemote:FindFirstChild("Salvage")
    if not remote or not remote:IsA("RemoteFunction") then return "no-remote" end
    local previousQuantity = tonumber(CraftProfile.Weapons.Owned[itemId]) or 0
    CraftBusy = true
    local ok, result = pcall(function() return remote:InvokeServer(itemId) end)
    CraftBusy = false
    if not ok or not result then
        craftNotice("Auto salvage rejected for " .. tostring(itemId) .. ". Salvage stopped.")
        Settings.AutoSalvage = false
        return "failed"
    end
    LastSalvageOwnedCount[itemId] = previousQuantity
    return "salvaged"
end
local function stopAutomaticCrafting()
    Settings.AutoCraft = false
    CraftGeneration += 1
    if AutoCraftToggle and type(AutoCraftToggle.SetValue) == "function" then pcall(function() AutoCraftToggle:SetValue(false) end) end
end
local function startCraftWorker()
    if CraftWorkerActive or not Settings.AutoCraft then return end
    CraftWorkerActive = true
    local myGeneration = CraftGeneration
    task.spawn(function()
        local failures = 0
        while Running and Settings.AutoCraft and CraftGeneration == myGeneration do
            if CraftCount >= Settings.CraftGoal then
                stopAutomaticCrafting()
                craftNotice("Craft goal reached (" .. CraftCount .. "). Auto Craft stopped.")
                break
            end
            if not CraftBusy then
                local result = craftOne(false)
                if result == "crafted" or result == "requested" then
                    failures = 0
                elseif result == "missing-materials" then
                    failures = 0
                    local recipe = getRecipe()
                    if recipe then salvageOneDuplicate(recipe) end
                elseif result == "rejected" or result == "error" then
                    failures += 1
                    if failures >= ... (42 KB left)
