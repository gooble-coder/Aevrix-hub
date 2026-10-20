local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Run = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local VU = game:GetService("VirtualUser")
local Core = game:GetService("CoreGui")
local P = Players.LocalPlayer
local Env = getgenv and getgenv() or _G

if type(Env.AevrixCleanup) == "function" then pcall(Env.AevrixCleanup) end
if type(Env.AevrixEggCleanup) == "function" then
    pcall(Env.AevrixEggCleanup)
    Env.AevrixEggCleanup = nil
end

local VIM
pcall(function() VIM = game:GetService("VirtualInputManager") end)
local Comm = RS:WaitForChild("Remotes"):WaitForChild("CommF_")
local Quests = require(RS:WaitForChild("Quests"))
local Net = RS:FindFirstChild("Modules")
Net = Net and Net:FindFirstChild("Net")
local RegisterAttack = Net and Net:FindFirstChild("RE/RegisterAttack")
local RegisterHit = Net and Net:FindFirstChild("RE/RegisterHit")

local BossActive = false

local A = {
    Farm=false,AcceptBossQuest=false,Chest=false,
    PlayerESP=false,ChestESP=false,Skills=false,Stats=false,
    Hotkey="F",TargetLevel=2800,Speed=320,ChestSpeed=320,
    Weapon="Melee",Range=12,Delay=0.15,SkillCooldown=6,
    Points=1,SelectedStats={Melee=true},
    PlayerColor="Cyan",ChestColor="Gold"
}

local S = {
    Running=true,Connections={},Watched={},Collisions={},
    Highlights={},Labels={},Chests={},ChestDone={},ChestFailed={},
    SpawnMemory={},SkillTimes={},BossCooldown={},
    Velocity=Vector3.zero,Updating=false,
    StatBusy=false,StatIndex=1,SkillIndex=0,
    Quest=nil,QuestSerial=0,Target=nil,Spawn=nil,ChestTarget=nil,
    LastScan=0,LastSpawn=0,LastChest=0,LastStat=0,LastSkill=0,
    LastAttack=0,LastRemote=0,LastError=0,LastMemory=0,
    RetreatUntil=0,CombatMode="probe"
}

local StatNames={"Melee","Defense","Sword","Gun","Blox Fruit"}
local ColorNames={"Cyan","Gold","Red","Green","Blue","Purple","Pink","White"}
local Colors={
    Cyan=Color3.fromRGB(0,220,255),Gold=Color3.fromRGB(255,200,40),
    Red=Color3.fromRGB(255,65,65),Green=Color3.fromRGB(60,255,120),
    Blue=Color3.fromRGB(75,130,255),Purple=Color3.fromRGB(175,90,255),
    Pink=Color3.fromRGB(255,100,190),White=Color3.new(1,1,1)
}

local Melee,Bosses={},{}
for name in ("combat,darkstep,blackleg,electric,waterkungfu,dragonbreath,superhuman,deathstep,sharkmankarate,electricclaw,dragontalon,godhuman,sanguineart"):gmatch("[^,]+") do
    Melee[name]=true
end
for name in ("gorillaking,bobby,yeti,mobleader,viceadmiral,warden,chiefwarden,swan,magmaadmiral,fishmanlord,wysper,thundergod,cyborg,diamond,jeremy,fajita,donswan,smokeadmiral,awakenediceadmiral,tidekeeper,darkbeard,cursedcaptain,order,stone,islandempress,kiloadmiral,captainelephant,beautifulpirate,longma,soulreaper,cakequeen,cakeprince,doughking,ripindra,saberexpert,greybeard,saw,iceadmiral,doughprince,leviathan,terrorshark"):gmatch("[^,]+") do
    Bosses[name]=true
end

local Spawns={
    bandit=Vector3.new(1060,17,1547),
    monkey=Vector3.new(-1460,40,100),
    gorilla=Vector3.new(-1190,40,-470),
    pirate=Vector3.new(-1115,14,3938),
    brute=Vector3.new(-1145,15,4350),
    desertbandit=Vector3.new(930,7,4485),
    desertofficer=Vector3.new(1550,14,4370),
    snowbandit=Vector3.new(1345,105,-1300),
    snowman=Vector3.new(1220,138,-1480),
    chiefpettyofficer=Vector3.new(-4850,23,4300),
    skypiean=Vector3.new(-4950,295,-2900),
    darkmaster=Vector3.new(-5250,390,-2270),
    prisonerguard=Vector3.new(4870,6,740)
}

local function Normal(value)
    return tostring(value or ""):lower():gsub("%[.*",""):gsub("[^%w]","")
end
local function CleanText(value)
    return tostring(value or ""):gsub("<.->","")
end
local function BossName(value)
    local name=Normal(value)
    local noThe=name:gsub("^the","")
    return Bosses[name]==true or Bosses[noThe]==true
        or name:find("boss",1,true)~=nil
end
local function Root(model)
    return model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
end
local function Char()
    local character=P.Character
    local humanoid=character and character:FindFirstChildOfClass("Humanoid")
    local root=character and character:FindFirstChild("HumanoidRootPart")
    if humanoid and humanoid.Health>0 and root then
        return character,humanoid,root
    end
end
local function Level()
    local data=P:FindFirstChild("Data")
    local value=data and data:FindFirstChild("Level")
    return value and tonumber(value.Value) or 1
end
local function EnemyFolder()
    return workspace:FindFirstChild("Enemies")
end
local function Alive(npc)
    local humanoid=npc and npc:FindFirstChildOfClass("Humanoid")
    local root=Root(npc)
    return npc and npc:IsA("Model") and npc.Parent==EnemyFolder()
        and humanoid and humanoid.Health>0 and root
        and root:IsDescendantOf(workspace)
end
local function BossNPC(npc)
    if not npc then return false end
    if BossName(npc.Name) then return true end
    for _,key in ipairs({"Boss","IsBoss","RaidBoss","IsRaidBoss"}) do
        if npc:GetAttribute(key)==true then return true end
    end
    return false
end
local function FindEnemy(name,bossOnly)
    local folder=EnemyFolder()
    local _,_,playerRoot=Char()
    if not folder or not name then return nil end
    local best,closest
    for _,npc in ipairs(folder:GetChildren()) do
        if Alive(npc) and Normal(npc.Name)==Normal(name)
            and (not bossOnly or BossNPC(npc)) then
            local distance=playerRoot
                and (playerRoot.Position-Root(npc).Position).Magnitude or 0
            if not closest or distance<closest then
                best,closest=npc,distance
            end
        end
    end
    return best
end
local function BossAlive(name)
    if os.clock()<(S.BossCooldown[Normal(name)] or 0) then return nil end
    return FindEnemy(name,false)
end
local function Moving()
    return S.Running and (
        A.Farm or A.Chest or BossActive or S.FruitFlight~=nil
        or S.FruitPurchaseLock==true or S.PvPFlight~=nil
    )
end

local function Noclip()
    local character=P.Character
    if not character then return end
    for _,part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            if S.Collisions[part]==nil then
                S.Collisions[part]=part.CanCollide
            end
            part.CanCollide=false
        end
    end
end
local function RestoreNoclip()
    for part,original in pairs(S.Collisions) do
        pcall(function()
            if part.Parent then part.CanCollide=original end
        end)
        S.Collisions[part]=nil
    end
end
local function ClearFlight()
    for _,object in ipairs({S.BV,S.BG}) do
        if object then pcall(function() object:Destroy() end) end
    end
    S.BV,S.BG,S.FlightRoot=nil,nil,nil
    S.Velocity=Vector3.zero
end
local function Flight()
    local _,humanoid,root=Char()
    if not root or not Moving() then return false end
    if S.FlightRoot~=root or not S.BV or not S.BV.Parent
        or not S.BG or not S.BG.Parent then
        ClearFlight()
        local velocity=Instance.new("BodyVelocity")
        velocity.Name="AevrixFlight"
        velocity.MaxForce=Vector3.new(1e9,1e9,1e9)
        velocity.P=15000
        velocity.Velocity=Vector3.zero
        velocity.Parent=root

        local gyro=Instance.new("BodyGyro")
        gyro.Name="AevrixFacing"
        gyro.MaxTorque=Vector3.new(1e9,1e9,1e9)
        gyro.P=10000
        gyro.D=1400
        gyro.CFrame=root.CFrame
        gyro.Parent=root
        S.BV,S.BG,S.FlightRoot=velocity,gyro,root
    end
    humanoid.AutoRotate=false
    humanoid:Move(Vector3.zero)
    return true
end
local function Move(goal,speed,dt,face)
    if not goal or not Flight() then return end
    local _,_,root=Char()
    if not root then return end
    dt=math.clamp(dt,1/240,0.1)
    local delta=goal-root.Position
    local distance=delta.Magnitude
    local desired=distance>0.15
        and delta.Unit*math.min(speed,distance*7) or Vector3.zero
    S.Velocity=S.Velocity:Lerp(
        desired,1-math.exp(-(distance>25 and 11 or 15)*dt)
    )
    S.BV.Velocity=S.Velocity
    local look=face
        and Vector3.new(face.X-root.Position.X,0,face.Z-root.Position.Z)
        or Vector3.new(S.Velocity.X,0,S.Velocity.Z)
    if look.Magnitude>0.05 then
        S.BG.CFrame=CFrame.lookAt(root.Position,root.Position+look.Unit)
    end
end
local function Hold()
    S.Velocity=Vector3.zero
    if S.BV then S.BV.Velocity=Vector3.zero end
end
local function Stop()
    ClearFlight()
    RestoreNoclip()
    local _,humanoid=Char()
    if humanoid then humanoid.AutoRotate=true end
    S.Target,S.ChestTarget=nil,nil
end

local function RememberNPCs()
    local folder=EnemyFolder()
    if not folder then return end
    for _,npc in ipairs(folder:GetChildren()) do
        if Alive(npc) and not BossNPC(npc) then
            S.SpawnMemory[Normal(npc.Name)]=Root(npc).Position
        end
    end
end

local function FindSpawn(name)
    if not name or BossName(name) then return nil end
    local _,_,playerRoot=Char()
    if not playerRoot then return nil end
    local folders={}
    local worldOrigin=workspace:FindFirstChild("_WorldOrigin")
    for _,parent in ipairs({workspace,worldOrigin}) do
        if parent then
            for _,key in ipairs({"EnemySpawns","NPCSpawns","MobSpawns"}) do
                local folder=parent:FindFirstChild(key)
                if folder then table.insert(folders,folder) end
            end
        end
    end
    local best,closest
    local wanted=Normal(name)
    for _,folder in ipairs(folders) do
        for _,object in ipairs(folder:GetDescendants()) do
            if object:IsA("BasePart") or object:IsA("Attachment") then
                local part=object:IsA("Attachment") and object.Parent or object
                if part and part:IsA("BasePart") then
                    local found=false
                    for _,candidate in ipairs({
                        object.Name,part.Name,
                        object:GetAttribute("EnemyName") or "",
                        object:GetAttribute("MobName") or "",
                        part:GetAttribute("EnemyName") or ""
                    }) do
                        if Normal(candidate)==wanted then
                            found=true
                            break
                        end
                    end
                    if found then
                        local position=object:IsA("Attachment")
                            and object.WorldPosition or part.Position
                        local distance=(playerRoot.Position-position).Magnitude
                        if not closest or distance<closest then
                            best,closest=position,distance
                        end
                    end
                end
            end
        end
    end
    return best or S.SpawnMemory[wanted] or Spawns[wanted]
end

-- QUEST DATABASE

local QuestList,QuestNames,BossQuestNames={},{},{}

for id,stages in pairs(Quests) do
    if type(stages)=="table" then
        for index,record in pairs(stages) do
            if type(index)=="number" and type(record)=="table"
                and type(record.LevelReq)=="number"
                and type(record.Task)=="table" then
                local enemy,count,total=nil,nil,0
                for name,amount in pairs(record.Task) do
                    if type(name)=="string" and type(amount)=="number"
                        and amount>0 then
                        enemy,count=name,amount
                        total=total+1
                    end
                end
                if total==1 then
                    local boss=count==1 or BossName(enemy)
                        or BossName(id) or BossName(record.Name)
                        or BossName(record.Title)
                    table.insert(QuestList,{
                        ID=id,Index=index,Enemy=enemy,Count=count,
                        LevelReq=record.LevelReq,Boss=boss
                    })
                    QuestNames[enemy]=true
                    if boss then BossQuestNames[Normal(enemy)]=true end
                end
            end
        end
    end
end
table.sort(QuestList,function(a,b) return a.LevelReq>b.LevelReq end)

local function QuestIsBoss(name)
    return BossQuestNames[Normal(name)]==true or BossName(name)
end
local function IsBossQuestRecord(record)
    if not record then return false end
    if tonumber(record.Count)==1 then return true end
    local stages=record.ID and Quests[record.ID]
    local raw=type(stages)=="table" and stages[record.Index]
    if type(raw)=="table" and type(raw.Task)=="table" then
        for _,amount in pairs(raw.Task) do
            if tonumber(amount)==1 then return true end
        end
    end
    if record.Boss==true or QuestIsBoss(record.Enemy)
        or BossName(record.ID) then
        return true
    end
    local npc=record.Enemy and FindEnemy(record.Enemy,false)
    return npc~=nil and BossNPC(npc) or false
end
local function FindQuestRecord(name)
    for _,quest in ipairs(QuestList) do
        if Normal(quest.Enemy)==Normal(name)
            and quest.LevelReq<=Level() then
            return quest
        end
    end
end
local function SelectQuest(normalOnly)
    local normal,boss
    local level=Level()
    for _,quest in ipairs(QuestList) do
        if quest.LevelReq<=level then
            if IsBossQuestRecord(quest) then
                quest.Boss=true
                if not normalOnly and not boss
                    and BossAlive(quest.Enemy) then
                    boss=quest
                end
            elseif not normal then
                normal=quest
            end
        end
        if normal and boss then break end
    end
    return boss or normal
end

local function QuestGui()
    local pg=P:FindFirstChild("PlayerGui")
    if not pg then return nil end
    local main=pg:FindFirstChild("Main")
    if main then
        local quest=main:FindFirstChild("Quest",true)
        if quest then return quest end
    end
    return pg:FindFirstChild("Quest",true)
end
local function GuiShown(object)
    if not object then return false end
    local current=object
    while current do
        if current:IsA("GuiObject") and not current.Visible then
            return false
        end
        if current:IsA("ScreenGui") and not current.Enabled then
            return false
        end
        current=current.Parent
        if current==P:FindFirstChild("PlayerGui") then break end
    end
    return true
end
local function QuestVisible()
    local gui=QuestGui()
    return gui~=nil and GuiShown(gui)
end
local function QuestText()
    local gui=QuestGui()
    if not gui then return "" end
    local lines={}
    for _,object in ipairs(gui:GetDescendants()) do
        if (object:IsA("TextLabel") or object:IsA("TextButton"))
            and object.Text~="" then
            table.insert(lines,CleanText(object.Text))
        end
    end
    return table.concat(lines,"\n")
end

local function DetectEnemy(text)
    local cleaned=tostring(text):lower():gsub("[^%w]","")
    local best,longest=nil,0
    for name in pairs(QuestNames) do
        local normalized=Normal(name)
        if #normalized>=4 and #normalized>longest
            and cleaned:find(normalized,1,true) then
            best,longest=name,#normalized
        end
    end
    return best
end
local function CompletionText(text)
    local cleaned=CleanText(text):lower()
    return cleaned:find("quest completed",1,true)
        or cleaned:find("quest complete!",1,true)
        or cleaned:find("quest finished",1,true)
end
local function ObjectiveProgress(text,quest)
    if not quest or not quest.Enemy or not quest.Count then return nil end
    local wanted=Normal(quest.Enemy)
    for line in tostring(text):gmatch("[^\r\n]+") do
        local cleaned=CleanText(line)
        local normalized=cleaned:lower():gsub("[^%w]","")
        if normalized:find(wanted,1,true) then
            for a,b in cleaned:gmatch("(%d+)%s*/%s*(%d+)") do
                local current,required=tonumber(a),tonumber(b)
                if current and required==quest.Count
                    and current>=0 and current<=required then
                    return current
                end
            end
        end
    end
end

local function ResetCombat()
    S.CombatTarget=nil
    S.CombatHealth=nil
    S.CombatMode="probe"
    S.CombatStart=0
    S.LastDamage=0
    S.CombatRetry=0
end
local function ClearQuestConnections(quest)
    if not quest or not quest.TargetConnections then return end
    for npc,connection in pairs(quest.TargetConnections) do
        pcall(function() connection:Disconnect() end)
        quest.TargetConnections[npc]=nil
    end
end
local function ResetQuest()
    ClearQuestConnections(S.Quest)
    S.QuestSerial=S.QuestSerial+1
    S.Quest=nil
    S.Target=nil
    S.Spawn=nil
    S.LastScan=0
    S.LastSpawn=0
    ResetCombat()
end
local function NewQuest(record,adopted)
    S.QuestSerial=S.QuestSerial+1
    local now=os.clock()
    local isBoss=IsBossQuestRecord(record)
    local quest={
        ID=record.ID,Index=record.Index,
        Enemy=record.Enemy,Count=record.Count,Boss=isBoss,
        NoQuest=isBoss and not A.AcceptBossQuest and not adopted,
        FarmingReady=adopted==true
            or (isBoss and not A.AcceptBossQuest),
        GuiConfirmed=adopted==true,
        RequestSent=false,RequestBusy=false,RequestedAt=0,
        FullProgress=false,CompletionNotice=false,Progress=0,
        Kills=0,CountedNPCs={},TargetConnections={},
        FarmStarted=false,FirstCombatAt=0,LastCombatAt=0,LastKillAt=0,
        EverVisible=adopted==true,
        LastVisibleAt=adopted and now or 0,
        HiddenSince=nil,BossMissingSince=nil,
        Abandoning=false,AbandonAt=0,AbandonHidden=nil
    }
    S.Quest=quest
    S.Target=nil
    S.Spawn=nil
    S.LastScan=0
    S.LastSpawn=0
    ResetCombat()
    print("[Aevrix Quest] Selected:",quest.Enemy,"Required:",quest.Count)
    return quest
end
local function RequestQuest(quest)
    if not S.Running or not A.Farm or not quest
        or S.Quest~=quest or quest.RequestSent or quest.RequestBusy
        or quest.GuiConfirmed
        or (not A.AcceptBossQuest and IsBossQuestRecord(quest))
        or not quest.ID or not quest.Index then
        return
    end

    if quest.Boss and not BossAlive(quest.Enemy) then return end

    if not A.AcceptBossQuest
        and (tonumber(quest.Count)==1 or IsBossQuestRecord(quest)) then
        quest.NoQuest=true
        quest.FarmingReady=true
        return
    end

    quest.RequestSent=true
    quest.RequestBusy=true
    quest.RequestedAt=os.clock()
    local serial=S.QuestSerial
    task.spawn(function()
        if not S.Running or not A.Farm or S.Quest~=quest
            or S.QuestSerial~=serial
            or (not A.AcceptBossQuest and IsBossQuestRecord(quest)) then
            quest.RequestBusy=false
            return
        end

        local ok,result=pcall(function()
            if not A.AcceptBossQuest
                and (tonumber(quest.Count)==1
                    or IsBossQuestRecord(quest)) then
                return false
            end
            return Comm:InvokeServer("StartQuest",quest.ID,quest.Index)
        end)

        quest.RequestBusy=false
        if ok and result~=false then
            print("[Aevrix Quest] StartQuest sent:",quest.Enemy)
        elseif not ok then
            warn("[Aevrix Quest] StartQuest error:",result)
        end
    end)
end
local function RegisterKill(npc,quest)
    if not quest or S.Quest~=quest or quest.CountedNPCs[npc]
        or (not quest.RequestSent
            and not quest.GuiConfirmed and not quest.NoQuest) then
        return
    end
    quest.CountedNPCs[npc]=true
    quest.Kills=quest.Kills+1
    quest.LastKillAt=os.clock()
    print("[Aevrix Quest] NPC defeated:",
        quest.Kills,"/",quest.Count or "?")
end
local function TrackNPC(npc,quest)
    if not quest or quest.TargetConnections[npc] then return end
    local humanoid=npc:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    quest.TargetConnections[npc]=humanoid.Died:Connect(function()
        RegisterKill(npc,quest)
    end)
end
local function FinishQuest(quest,reason)
    if not quest or S.Quest~=quest then return end
    print("[Aevrix Quest] Completed:",quest.Enemy,
        "Reason:",reason,"Kills:",quest.Kills)
    ResetQuest()
end
local function AbandonBoss(quest)
    if not quest or S.Quest~=quest or not quest.Boss
        or quest.Abandoning then return end
    quest.Abandoning=true
    quest.AbandonAt=os.clock()
    quest.AbandonHidden=nil
    S.BossCooldown[Normal(quest.Enemy)]=os.clock()+5
    S.Target,S.Spawn=nil,nil
    Hold()
    task.spawn(function()
        pcall(function() Comm:InvokeServer("AbandonQuest") end)
    end)
end
local function WatchNotifications()
    local pg=P:WaitForChild("PlayerGui")
    local function Watch(object)
        if S.Watched[object]
            or not (object:IsA("TextLabel")
                or object:IsA("TextButton")) then return end
        S.Watched[object]=
            object:GetPropertyChangedSignal("Text"):Connect(function()
                if not A.Farm then return end
                local quest=S.Quest
                if not quest or quest.Abandoning
                    or (not quest.RequestSent and not quest.GuiConfirmed)
                    or not CompletionText(object.Text) then
                    return
                end
                local panel=QuestGui()
                if panel and object:IsDescendantOf(panel) then return end
                quest.CompletionNotice=true
            end)
    end
    for _,object in ipairs(pg:GetDescendants()) do Watch(object) end
    table.insert(S.Connections,pg.DescendantAdded:Connect(Watch))
end
local function HasCompletionEvidence(quest)
    if not quest then return false end
    if quest.FullProgress or quest.CompletionNotice then return true end
    return quest.Count and quest.Kills>=quest.Count or false
end
local function QuestHasStarted(quest)
    return quest and (quest.RequestSent or quest.GuiConfirmed)
end

local function UpdateQuest()
    if not A.Farm then return end
    local now=os.clock()
    local visible=QuestVisible()
    local text=visible and QuestText() or ""
    local detected=visible and DetectEnemy(text) or nil
    local quest=S.Quest

    if quest and quest.NoQuest then
        if not BossAlive(quest.Enemy) then
            S.BossCooldown[Normal(quest.Enemy)]=now+5
            ResetQuest()
        end
        return
    end

    if not A.AcceptBossQuest and visible then
        local existing=detected and FindQuestRecord(detected)
        local required=tonumber(text:match("%d+%s*/%s*(%d+)"))
        if required==1 or (existing and IsBossQuestRecord(existing)) then
            if now-(S.LastBossAbandon or -100)>=5 then
                S.LastBossAbandon=now
                task.spawn(function()
                    pcall(function()
                        Comm:InvokeServer("AbandonQuest")
                    end)
                end)
            end
            if quest and not quest.NoQuest then ResetQuest() end
            return
        end
    end

    if not quest and visible then
        if detected then
            local record=FindQuestRecord(detected)
            if record then
                NewQuest(record,true)
            else
                NewQuest({
                    Enemy=detected,Boss=QuestIsBoss(detected)
                },true)
            end
        end
        return
    end

    if not quest then
        if visible then return end
        local selected=SelectQuest(false)
        if not selected then return end
        if selected.Boss and not BossAlive(selected.Enemy) then
            selected=SelectQuest(true)
        end
        if not selected then return end
        quest=NewQuest(selected,false)
        RequestQuest(quest)
        return
    end

    if quest.Abandoning then
        if not visible then
            quest.AbandonHidden=quest.AbandonHidden or now
            if now-quest.AbandonHidden>=0.4 then
                S.BossCooldown[Normal(quest.Enemy)]=now+5
                ResetQuest()
            end
        else
            quest.AbandonHidden=nil
            if now-quest.AbandonAt>=2 then
                quest.AbandonAt=now
                task.spawn(function()
                    pcall(function()
                        Comm:InvokeServer("AbandonQuest")
                    end)
                end)
            end
        end
        return
    end

    if visible then
        quest.HiddenSince=nil
        if detected and Normal(detected)==Normal(quest.Enemy) then
            quest.GuiConfirmed=true
            quest.FarmingReady=true
            quest.EverVisible=true
            quest.LastVisibleAt=now
        elseif detected and Normal(detected)~=Normal(quest.Enemy)
            and not quest.GuiConfirmed then
            local record=FindQuestRecord(detected)
            if record then
                NewQuest(record,true)
            else
                NewQuest({Enemy=detected,Boss=QuestIsBoss(detected)},true)
            end
            return
        elseif quest.GuiConfirmed then
            quest.EverVisible=true
            quest.LastVisibleAt=now
        end

        if quest.GuiConfirmed then
            local progress=ObjectiveProgress(text,quest)
            if progress then
                quest.Progress=math.max(quest.Progress,progress)
                if quest.Count and progress>=quest.Count then
                    quest.FullProgress=true
                end
            end
        end
    else
        quest.HiddenSince=quest.HiddenSince or now
    end

    if CompletionText(text) then
        quest.CompletionNotice=true
    end

    local hiddenFor=quest.HiddenSince and now-quest.HiddenSince or 0
    local completion=HasCompletionEvidence(quest)

    if QuestHasStarted(quest) and not visible and completion
        and hiddenFor>=0.45 then
        FinishQuest(quest,"completion evidence")
        return
    end
    if quest.GuiConfirmed and quest.EverVisible and quest.FarmStarted
        and quest.Kills>0 and not visible and hiddenFor>=1.5 then
        FinishQuest(quest,"quest panel cleared")
        return
    end
    if not quest.GuiConfirmed and quest.RequestSent and quest.Count
        and quest.Kills>=quest.Count and not visible
        and now-quest.LastKillAt>=0.7 then
        FinishQuest(quest,"required kills tracked")
        return
    end

    if quest.Boss then
        if BossAlive(quest.Enemy) then
            quest.BossMissingSince=nil
        else
            quest.BossMissingSince=quest.BossMissingSince or now
            if now-quest.BossMissingSince>=1.5 then
                if not visible then
                    S.BossCooldown[Normal(quest.Enemy)]=now+5
                    if completion then
                        FinishQuest(quest,"boss finished")
                    else
                        ResetQuest()
                    end
                elseif quest.GuiConfirmed then
                    AbandonBoss(quest)
                end
            end
        end
        return
    end

    if not quest.FarmingReady and quest.RequestSent
        and now-quest.RequestedAt>=0.65 then
        quest.FarmingReady=true
    end
end

-- COMBAT

local function WeaponMatch(tool)
    if not tool:IsA("Tool") then return false end
    local kind=tool:GetAttribute("WeaponType")
    local tip=(tool.ToolTip or ""):lower()
    if A.Weapon=="Melee" then
        return kind=="Melee" or kind=="FightingStyle"
            or tip=="melee" or Melee[Normal(tool.Name)]==true
    elseif A.Weapon=="Fruit" then
        return kind=="Fruit" or kind=="Demon Fruit"
            or tip=="fruit" or tip=="blox fruit"
    end
    return kind==A.Weapon or tip==A.Weapon:lower()
end
local function Equip()
    local character,humanoid=Char()
    if not character then return nil end
    for _,tool in ipairs(character:GetChildren()) do
        if WeaponMatch(tool) then return tool end
    end
    local backpack=P:FindFirstChild("Backpack")
    if backpack then
        for _,tool in ipairs(backpack:GetChildren()) do
            if WeaponMatch(tool) then
                humanoid:EquipTool(tool)
                return tool.Parent==character and tool or nil
            end
        end
    end
end
local function RemoteAttack(npc)
    if not Alive(npc) or not RegisterAttack or not RegisterHit
        or not RegisterAttack:IsA("RemoteEvent")
        or not RegisterHit:IsA("RemoteEvent")
        or os.clock()-S.LastRemote<A.Delay then return end
    if not Equip() then return end
    local part=npc:FindFirstChild("Head") or Root(npc)
    if not part then return end
    S.LastRemote=os.clock()
    pcall(function()
        RegisterAttack:FireServer(0.1)
        RegisterHit:FireServer(part,{{npc,part}})
    end)
end

local ClickPositions={
    {88,45},{91,55},{85,32},{87,68},
    {75,45},{75,65},{12,45},{15,30},{50,75},{50,50}
}

local function Blocked(x,y)
    for _,gui in ipairs({P:FindFirstChild("PlayerGui"),Core}) do
        if gui then
            for _,object in ipairs(gui:GetDescendants()) do
                if object:IsA("GuiObject") and (
                    object:IsA("GuiButton") or object:IsA("TextBox")
                    or object.Active or object.Selectable
                ) then
                    local shown=true
                    local parent=object
                    while parent do
                        if parent:IsA("GuiObject") and not parent.Visible then
                            shown=false
                            break
                        end
                        if parent:IsA("ScreenGui") and not parent.Enabled then
                            shown=false
                            break
                        end
                        parent=parent.Parent
                    end
                    if shown then
                        local pos=object.AbsolutePosition
                        local size=object.AbsoluteSize
                        if x>=pos.X-7 and x<=pos.X+size.X+7
                            and y>=pos.Y-7 and y<=pos.Y+size.Y+7 then
                            return true
                        end
                    end
                end
            end
        end
    end
    return false
end

local function NormalAttack()
    if os.clock()-S.LastAttack<A.Delay or not Equip() then return end
    local camera=workspace.CurrentCamera
    if not camera then return end
    for _,point in ipairs(ClickPositions) do
        local x=math.floor(camera.ViewportSize.X*point[1]/100)
        local y=math.floor(camera.ViewportSize.Y*point[2]/100)
        if not Blocked(x,y) then
            S.LastAttack=os.clock()
            local ok=false
            if VIM then
                ok=pcall(function()
                    VIM:SendMouseButtonEvent(x,y,0,true,game,0)
                    VIM:SendMouseButtonEvent(x,y,0,false,game,0)
                end)
            end
            if not ok then
                pcall(function()
                    VU:CaptureController()
                    VU:Button1Down(Vector2.new(x,y),camera.CFrame)
                    VU:Button1Up(Vector2.new(x,y),camera.CFrame)
                end)
            end
            return
        end
    end
end
local function UseSkills()
    if not A.Skills or not VIM
        or os.clock()-S.LastSkill<1 then return end
    local tool=Equip()
    if not tool then return end
    local keys={"Z","X","C","V"}
    for offset=1,#keys do
        local index=(S.SkillIndex+offset-1)%#keys+1
        local key=keys[index]
        local id=tool.Name..":"..key
        if os.clock()-(S.SkillTimes[id] or -math.huge)>=A.SkillCooldown then
            S.SkillIndex=index
            S.LastSkill=os.clock()
            S.SkillTimes[id]=S.LastSkill
            task.spawn(function()
                pcall(function()
                    VIM:SendKeyEvent(true,Enum.KeyCode[key],false,game)
                    task.wait(0.08)
                    VIM:SendKeyEvent(false,Enum.KeyCode[key],false,game)
                end)
            end)
            break
        end
    end
end
local function GluePosition(npc)
    local root=Root(npc)
    local forward=root.CFrame.LookVector
    forward=Vector3.new(forward.X,0,forward.Z)
    forward=forward.Magnitude>0.1
        and forward.Unit or Vector3.new(0,0,-1)
    local distance=math.clamp(A.Range*0.23,2.3,3)
    if root.Size.Z>4 then
        distance=math.min(4,distance+(root.Size.Z-4)*0.15)
    end
    return root.Position-forward*distance+Vector3.new(0,0.3,0)
end
local function SurfaceDistance(npc,position)
    local ok,cf,size=pcall(function() return npc:GetBoundingBox() end)
    if not ok then return (position-Root(npc).Position).Magnitude end
    local p=cf:PointToObjectSpace(position)
    local half=size/2
    return Vector3.new(
        math.max(math.abs(p.X)-half.X,0),
        math.max(math.abs(p.Y)-half.Y,0),
        math.max(math.abs(p.Z)-half.Z,0)
    ).Magnitude
end

local function UpdateFarm(dt)
    if Level()>=A.TargetLevel then return false end
    local quest=S.Quest
    if not quest or quest.Abandoning then
        Hold()
        return true
    end
    if not quest.FarmingReady then
        if quest.RequestSent
            and os.clock()-quest.RequestedAt>=0.65 then
            quest.FarmingReady=true
        else
            Hold()
            return true
        end
    end
    local enemy=quest.Enemy
    if quest.Boss and not BossAlive(enemy) then
        S.Target,S.Spawn=nil,nil
        Hold()
        return true
    end

    if S.Target and (
        not Alive(S.Target) or Normal(S.Target.Name)~=Normal(enemy)
    ) then
        local old=S.Target
        local humanoid=old:FindFirstChildOfClass("Humanoid")
        if humanoid and humanoid.Health<=0 then
            RegisterKill(old,quest)
        end
        S.Target=nil
        S.LastScan=0
        ResetCombat()
    end

    if not S.Target and os.clock()-S.LastScan>=0.1 then
        S.LastScan=os.clock()
        S.Target=FindEnemy(enemy,quest.Boss)
    end

    local npc=S.Target
    if not npc then
        if quest.Boss then
            Hold()
            return true
        end
        if not S.Spawn or os.clock()-S.LastSpawn>=2 then
            S.LastSpawn=os.clock()
            S.Spawn=FindSpawn(enemy)
        end
        if S.Spawn then
            Move(S.Spawn+Vector3.new(0,40,0),A.Speed,dt)
        else
            Hold()
        end
        return true
    end

    local npcRoot=Root(npc)
    local _,humanoid,playerRoot=Char()
    if not npcRoot or not playerRoot then return true end

    if not quest.Boss then
        S.SpawnMemory[Normal(enemy)]=npcRoot.Position
    end
    TrackNPC(npc,quest)

    if S.CombatTarget~=npc then
        ResetCombat()
        S.CombatTarget=npc
        local enemyHumanoid=npc:FindFirstChildOfClass("Humanoid")
        S.CombatHealth=enemyHumanoid and enemyHumanoid.Health
        S.CombatStart=os.clock()
        S.LastDamage=os.clock()
    end

    local enemyHumanoid=npc:FindFirstChildOfClass("Humanoid")
    if enemyHumanoid then
        if S.CombatHealth and enemyHumanoid.Health<S.CombatHealth then
            S.LastDamage=os.clock()
            if S.CombatMode=="probe" then S.CombatMode="verified" end
        end
        S.CombatHealth=enemyHumanoid.Health
    end

    quest.FarmStarted=true
    if quest.FirstCombatAt==0 then
        quest.FirstCombatAt=os.clock()
    end
    quest.LastCombatAt=os.clock()
    local now=os.clock()

    if humanoid.Health/math.max(humanoid.MaxHealth,1)<0.25 then
        S.RetreatUntil=now+5
    end

    if now<S.RetreatUntil then
        Move(npcRoot.Position+Vector3.new(0,65,0),
            A.Speed,dt,npcRoot.Position)
        return true
    end

    if S.CombatMode=="normal" and now>=S.CombatRetry then
        S.CombatMode="probe"
        S.CombatStart=now
        S.LastDamage=now
    end

    if S.CombatMode=="probe" or S.CombatMode=="verified" then
        local goal=npcRoot.Position+Vector3.new(0,40,0)
        Move(goal,A.Speed,dt,npcRoot.Position)
        if (playerRoot.Position-goal).Magnitude<=5 then
            RemoteAttack(npc)
            if S.CombatMode=="probe" and now-S.CombatStart>=3
                and now-S.LastDamage>=2.5 then
                S.CombatMode="normal"
                S.CombatRetry=now+12
            elseif S.CombatMode=="verified"
                and now-S.LastDamage>=5 then
                S.CombatMode="normal"
                S.CombatRetry=now+12
            end
        end
        return true
    end

    Move(GluePosition(npc),A.Speed,dt,npcRoot.Position)
    local distance=math.min(
        (playerRoot.Position-npcRoot.Position).Magnitude,
        SurfaceDistance(npc,playerRoot.Position)+2
    )
    if distance<=A.Range then
        NormalAttack()
        UseSkills()
    end
    return true
end

-- AUTO CHEST

local function ChestName(name)
    local n=Normal(name)
    return n=="chest" or n:match("^chest%d+$")~=nil
        or n:match("^chest%a+$")~=nil
end
local function ChestPart(object)
    if not object or not object.Parent then return nil end
    if object:IsA("BasePart") and ChestName(object.Name) then
        return object
    end
    if object:IsA("Model") and ChestName(object.Name) then
        return object.PrimaryPart
            or object:FindFirstChildWhichIsA("BasePart",true)
    end
end
local function ChestObject(object)
    if not object or not ChestName(object.Name) then return nil end
    if object:IsA("Model") then
        return ChestPart(object) and object or nil
    end
    if object:IsA("BasePart") then
        local parent=object.Parent
        return parent and parent:IsA("Model")
            and ChestName(parent.Name) and parent or object
    end
end
local function RefreshChests()
    local found,seen={},{}
    for _,object in ipairs(workspace:GetDescendants()) do
        local chest=ChestObject(object)
        if chest and ChestPart(chest) and not seen[chest] then
            seen[chest]=true
            table.insert(found,chest)
        end
    end
    S.Chests=found
    S.LastChest=os.clock()
    for _,bucket in ipairs({S.ChestDone,S.ChestFailed}) do
        for chest in pairs(bucket) do
            if not ChestPart(chest) then bucket[chest]=nil end
        end
    end
end

local function FindChest()
    local _,_,playerRoot=Char()
    if not playerRoot then return nil end
    local best,closest
    for _,chest in ipairs(S.Chests) do
        local part=ChestPart(chest)
        if part and not S.ChestDone[chest]
            and (S.ChestFailed[chest] or 0)<=os.clock() then
            local distance=(playerRoot.Position-part.Position).Magnitude
            if not closest or distance<closest then
                best,closest=chest,distance
            end
        end
    end
    return best
end
local function NextChest()
    S.ChestTarget=FindChest()
    S.ChestProgress=nil
    S.ChestProgressTime=nil
    S.ChestStuck=0
end
local function UpdateChest(dt)
    if os.clock()-S.LastChest>=5 then RefreshChests() end
    if S.ChestTarget and (
        not ChestPart(S.ChestTarget) or S.ChestDone[S.ChestTarget]
    ) then
        S.ChestTarget=nil
    end
    if not S.ChestTarget then NextChest() end
    local chest=S.ChestTarget
    if not chest then
        Hold()
        return
    end
    local part=ChestPart(chest)
    local _,_,playerRoot=Char()
    if not part or not playerRoot then
        S.ChestTarget=nil
        return
    end
    local distance=(playerRoot.Position-part.Position).Magnitude
    if distance<=3.5 then
        S.ChestDone[chest]=true
        NextChest()
        return
    end
    local now=os.clock()
    if not S.ChestProgressTime then
        S.ChestProgressTime=now
        S.ChestProgress=distance
    elseif now-S.ChestProgressTime>=1.5 then
        if (S.ChestProgress or distance)-distance<10 then
            S.ChestStuck=(S.ChestStuck or 0)+1
        else
            S.ChestStuck=0
        end
        S.ChestProgressTime=now
        S.ChestProgress=distance
        if S.ChestStuck>=3 then
            S.ChestFailed[chest]=now+180
            NextChest()
            return
        end
    end
    Move(part.Position,A.ChestSpeed,dt,part.Position)
end

-- ESP

local function RemoveESP(object)
    for _,bucket in ipairs({S.Highlights,S.Labels}) do
        if bucket[object] then
            pcall(function() bucket[object]:Destroy() end)
            bucket[object]=nil
        end
    end
end
local function ESP(object,part,name,color)
    if not object or not part then return end
    local highlight=S.Highlights[object]
    if not highlight or not highlight.Parent then
        highlight=Instance.new("Highlight")
        highlight.Name="AevrixESP"
        highlight.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop
        highlight.FillTransparency=0.75
        highlight.Parent=Core
        S.Highlights[object]=highlight
    end
    highlight.Adornee=object
    highlight.FillColor=color
    highlight.OutlineColor=color

    local billboard=S.Labels[object]
    if not billboard or not billboard.Parent then
        billboard=Instance.new("BillboardGui")
        billboard.Name="AevrixLabel"
        billboard.Size=UDim2.fromOffset(160,30)
        billboard.StudsOffsetWorldSpace=Vector3.new(0,3,0)
        billboard.AlwaysOnTop=true
        billboard.Parent=Core

        local label=Instance.new("TextLabel")
        label.Name="Name"
        label.Size=UDim2.fromScale(1,1)
        label.BackgroundTransparency=1
        label.Font=Enum.Font.GothamBold
        label.TextSize=14
        label.TextStrokeTransparency=0.35
        label.Parent=billboard
        S.Labels[object]=billboard
    end
    billboard.Adornee=part
    local text=billboard:FindFirstChild("Name")
    if text then
        text.Text=name
        text.TextColor3=color
    end
end
local function UpdateESP()
    local active={}
    if A.PlayerESP then
        for _,player in ipairs(Players:GetPlayers()) do
            if player~=P then
                local character=player.Character
                local root=character and Root(character)
                if character and root then
                    active[character]=true
                    ESP(character,
                        character:FindFirstChild("Head") or root,
                        player.DisplayName,Colors[A.PlayerColor])
                end
            end
        end
    end
    if A.ChestESP then
        for _,chest in ipairs(S.Chests) do
            local part=ChestPart(chest)
            if part then
                active[chest]=true
                ESP(chest,part,"Chest",Colors[A.ChestColor])
            end
        end
    end
    for object in pairs(S.Highlights) do
        if not active[object] then RemoveESP(object) end
    end
end

-- AUTO STATS

local function SelectedStats()
    local result={}
    for _,name in ipairs(StatNames) do
        if A.SelectedStats[name] then table.insert(result,name) end
    end
    return result
end
local function DistributeStats()
    if S.StatBusy or not A.Stats then return end
    local data=P:FindFirstChild("Data")
    local points=data and data:FindFirstChild("Points")
    if not points or points.Value<=0 then return end
    S.StatBusy=true
    local amount=math.min(math.floor(points.Value),math.floor(A.Points))
    for _=1,amount do
        if not S.Running or not A.Stats or not points.Parent
            or points.Value<=0 then break end
        local selected=SelectedStats()
        if #selected==0 then break end
        if S.StatIndex>#selected then S.StatIndex=1 end
        local stat=selected[S.StatIndex]
        local before=points.Value
        local serverName=stat=="Blox Fruit" and "Demon Fruit" or stat
        local ok,result=pcall(function()
            return Comm:InvokeServer("AddPoint",serverName,1)
        end)
        if not ok or result==false then break end
        S.StatIndex=S.StatIndex%#selected+1
        task.wait(0.08)
        if points.Parent and points.Value>=before then
            task.wait(0.12)
        end
    end
    S.StatBusy=false
end

local Notify=function() end

-- FRUITS

local Fruits={
    AutoRoll=false,Stock="Loading...",StockBusy=false,
    NextStock=0,Rotation=-1,Client=nil,CheckBusy=false,
    NextCheck=0,Ready=false,Status="Checking...",
    Deadline=nil,RollBusy=false,NextAttempt=0,
    FlightStatus="Idle",Paragraphs={},Shown={},Toggle=nil
}

local FruitNPCNames={
    Gacha="Blox Fruit Gacha",
    Dealer="Blox Fruit Dealer"
}

local function FruitTime(seconds)
    seconds=math.max(0,math.floor(tonumber(seconds) or 0))
    return string.format("%02d:%02d:%02d",
        math.floor(seconds/3600),
        math.floor(seconds%3600/60),seconds%60)
end
local function FruitInfo(id,text)
    text=tostring(text)
    if Fruits.Shown[id]==text then return end
    local p=Fruits.Paragraphs[id]
    if p then
        local ok=pcall(function() p:SetValue(text) end)
        if ok then Fruits.Shown[id]=text end
    end
end
local function FruitStock()
    if Fruits.StockBusy or not S.Running then return end
    Fruits.StockBusy=true
    Fruits.NextStock=os.clock()+45
    local ok,data=pcall(function()
        return Comm:InvokeServer("GetFruits")
    end)
    if ok and type(data)=="table" then
        local names,seen={},{}
        for _,fruit in pairs(data) do
            if type(fruit)=="table" and type(fruit.Name)=="string"
                and fruit.OnSale==true and not seen[fruit.Name] then
                seen[fruit.Name]=true
                table.insert(names,fruit.Name)
            end
        end
        table.sort(names)
        Fruits.Stock=#names>0 and table.concat(names,"\n")
            or "No fruits in stock returned"
    else
        Fruits.Stock="Stock unavailable; retrying"
    end
    Fruits.StockBusy=false
end

local function FruitNPC(kind)
    local wanted=FruitNPCNames[kind]
    if not wanted then return end
    local _,_,me=Char()
    local best,bestDistance=nil,math.huge
    for _,npc in ipairs(workspace:GetDescendants()) do
        local n=Normal(npc.Name)
        local matches=(kind=="Gacha" and (
            n=="bloxfruitgacha" or n=="bloxfruitsgacha" or n=="zioles"
        )) or (kind=="Dealer" and (
            n=="bloxfruitdealer" or n=="bloxfruitsdealer"
        ))
        if not matches and npc:IsA("Model") then
            local label=npc:GetAttribute("NPCName")
                or npc:GetAttribute("DisplayName")
            local labelName=Normal(label)
            matches=(kind=="Gacha" and (
                labelName=="bloxfruitgacha" or labelName=="zioles"
            )) or (kind=="Dealer" and labelName=="bloxfruitdealer")
        end
        if npc:IsA("Model") and matches then
            local part=Root(npc) or npc:FindFirstChild("Head")
            if part and part:IsA("BasePart") then
                local distance=me
                    and (me.Position-part.Position).Magnitude or 0
                if distance<bestDistance then
                    best,bestDistance=part,distance
                end
            end
        end
    end
    return best
end

local FruitWaypoints={
    [2753915549]={
        Gacha=Vector3.new(-656,22,1574),
        Dealer=Vector3.new(-923,12,1609)
    },
    [4442272183]={
        Gacha=Vector3.new(-400,74,317),
        Dealer=Vector3.new(-451,74,356)
    },
    [7449423635]={
        Gacha=Vector3.new(-12491,337,-7449),
        Dealer=Vector3.new(-12511,337,-7448)
    }
}

local FruitAreaNames={
    [2753915549]="Middle Town",
    [4442272183]="Cafe",
    [7449423635]="Mansion"
}
local function FruitFallback(kind)
    local points=FruitWaypoints[game.PlaceId]
    return points and points[kind] or nil
end
local function EndFruitFlight(success,message)
    local flight=S.FruitFlight
    if not flight then return end
    flight.Done,flight.Success=true,success==true
    flight.Message=message
    Fruits.FlightStatus=message
        or (success and "Arrived" or "Flight stopped")
    S.FruitFlight=nil
    ClearFlight()
    if not (A.Farm or A.Chest) then
        RestoreNoclip()
        local _,humanoid=Char()
        if humanoid then humanoid.AutoRotate=true end
    end
end
local function BeginFruitFlight(kind,automatic)
    if S.FruitFlight or S.PvPFlight or BossActive then
        return nil,"Stop Boss Farm or existing flight first"
    end
    local _,_,hrp=Char()
    if not hrp then return nil,"Character not ready" end
    local npc=FruitNPC(kind)
    local target=npc and npc.Position+Vector3.new(4,3,0)
        or FruitFallback(kind)
    if not target then return nil,"Unsupported sea / NPC unavailable" end
    local flight={
        Kind=kind,Automatic=automatic==true,Exact=npc~=nil,
        Target=target,
        CruiseY=math.max(hrp.Position.Y,target.Y)+80,
        Phase="Climb",Deadline=os.clock()+180,
        LastRefine=0,Done=false,Success=false
    }
    S.FruitFlight=flight
    Fruits.FlightStatus="Flying to "..FruitNPCNames[kind]
    return flight
end
local function UpdateFruitFlight(dt)
    local flight=S.FruitFlight
    if not flight then return end
    local _,_,hrp=Char()
    if not hrp or os.clock()>=flight.Deadline then
        EndFruitFlight(false,"Flight timed out / character reset")
        return
    end
    if not flight.Exact and os.clock()-flight.LastRefine>1.5 then
        flight.LastRefine=os.clock()
        local npc=FruitNPC(flight.Kind)
        if npc then
            flight.Exact=true
            flight.Target=npc.Position+Vector3.new(4,3,0)
            flight.CruiseY=math.max(hrp.Position.Y,flight.Target.Y)+80
            flight.Phase="Climb"
        end
    end

    local goal,radius
    if flight.Phase=="Climb" then
        goal=Vector3.new(hrp.Position.X,flight.CruiseY,hrp.Position.Z)
        radius=7
    elseif flight.Phase=="Cruise" then
        goal=Vector3.new(flight.Target.X,flight.CruiseY,flight.Target.Z)
        radius=11
    else
        goal=flight.Target
        radius=5
    end

    if (hrp.Position-goal).Magnitude>radius then
        Move(goal,320,dt)
        return
    end

    if flight.Phase=="Climb" then
        flight.Phase="Cruise"
    elseif flight.Phase=="Cruise" then
        flight.Phase="Land"
    elseif not flight.Exact then
        local npc=FruitNPC(flight.Kind)
        if npc then
            flight.Exact=true
            flight.Target=npc.Position+Vector3.new(4,3,0)
            flight.CruiseY=math.max(hrp.Position.Y,flight.Target.Y)+80
            flight.Phase="Climb"
        else
            EndFruitFlight(false,"Reached "..
                (FruitAreaNames[game.PlaceId] or "area")..
                "; exact NPC not loaded")
        end
    else
        EndFruitFlight(true,"Arrived at "..FruitNPCNames[flight.Kind])
    end
end

-- GACHA

local function FruitClient()
    if Fruits.Client then return Fruits.Client end
    local folder=RS:FindFirstChild("Controllers")
    local module=folder and folder:FindFirstChild("GachaClient")
    if not module then return nil end
    local ok,client=pcall(require,module)
    if ok and type(client)=="table"
        and type(client.CheckGachaAsync)=="function"
        and type(client.PurchaseGachaAsync)=="function" then
        Fruits.Client=client
    end
    return Fruits.Client
end
local function FruitCheckData(data)
    if type(data)~="table" then
        return false,"Status unavailable",nil
    end
    if type(data.Level)=="table"
        and data.Level.RequirementMet==false then
        return false,"Level requirement not met",nil
    end
    local restriction=data.PaidRandomItemsRestricted
    if type(restriction)=="table" and restriction.Value==true then
        return false,"Gacha restricted",nil
    end
    local cooldown=data.Cooldown
    if type(cooldown)~="table" then
        return false,"Cooldown unknown",nil
    end
    if cooldown.RequirementMet==false then
        local finish=tonumber(cooldown.TimeEnds)
        local remaining
        if finish then
            if finish>1e12 then
                remaining=finish/1000-os.time()
            elseif finish>1e9 then
                remaining=finish-os.time()
            elseif finish>=0 and finish<=7200 then
                remaining=finish
            end
        end
        return false,"On cooldown",
            remaining and math.max(0,remaining) or nil
    end
    if cooldown.RequirementMet~=true then
        return false,"Cooldown unknown",nil
    end
    if type(data.Price)~="table"
        or data.Price.RequirementMet~=true then
        return false,"Not enough Beli",nil
    end
    return true,"Ready",0
end
local function ApplyFruitCheck(data)
    local ready,status,remaining=FruitCheckData(data)
    Fruits.Ready,Fruits.Status=ready,status
    Fruits.Deadline=remaining and remaining>0
        and os.clock()+remaining or nil
    return ready,status
end
local function CheckFruitsGacha()
    if Fruits.CheckBusy or not S.Running then return end
    Fruits.CheckBusy=true
    Fruits.NextCheck=os.clock()+20
    local client=FruitClient()
    if client then
        local ok,data=pcall(function()
            return client.CheckGachaAsync("ZiolesGacha","Blox Fruit Gacha")
        end)
        if ok then ApplyFruitCheck(data)
        else ApplyFruitCheck(nil) end
    else
        Fruits.Ready,Fruits.Status,Fruits.Deadline=
            false,"Controller unavailable",nil
    end
    Fruits.CheckBusy=false
end
local function StopFruitAuto()
    Fruits.AutoRoll=false
    if Fruits.Toggle then
        pcall(function() Fruits.Toggle:SetValue(false) end)
    end
end

local function FruitRollCycle()
    if Fruits.RollBusy or not Fruits.AutoRoll or not Fruits.Ready
        or not S.Running or S.FruitFlight or S.PvPFlight or BossActive
        or os.clock()<Fruits.NextAttempt then return end
    Fruits.RollBusy=true
    S.FruitPurchaseLock=true
    Fruits.NextAttempt=os.clock()+120

    task.spawn(function()
        local ok,success,message=pcall(function()
            local client=FruitClient()
            if not client then
                return false,"Gacha controller unavailable"
            end
            local data=client.CheckGachaAsync(
                "ZiolesGacha","Blox Fruit Gacha"
            )
            local ready,reason=ApplyFruitCheck(data)
            if not ready or not Fruits.AutoRoll then
                return false,reason
            end
            local flight,errorText=BeginFruitFlight("Gacha",true)
            if not flight then return false,errorText end

            while S.Running and Fruits.AutoRoll and not flight.Done do
                task.wait(0.2)
            end
            if not flight.Done then
                if S.FruitFlight==flight then
                    EndFruitFlight(false,"Auto Roll cancelled")
                end
                return false,"Auto Roll cancelled"
            end
            if not flight.Success then return false,flight.Message end
            if not S.Running or not Fruits.AutoRoll then
                return false,"Cancelled"
            end

            local updated=client.CheckGachaAsync(
                "ZiolesGacha","Blox Fruit Gacha"
            )
            local canBuy,why=ApplyFruitCheck(updated)
            if not canBuy then return false,why end

            local purchased,failure=
                client.PurchaseGachaAsync("ZiolesGacha")
            if purchased==true then
                Fruits.Ready,Fruits.Status=
                    false,"Purchase accepted; checking timer"
                Fruits.Deadline=nil
                Fruits.NextCheck=0
                Fruits.NextAttempt=os.clock()+120
                return true,"Gacha purchase accepted"
            end

            local rejection=type(failure)=="table"
                and (failure.ErrorMessage or failure.Message) or failure
            return false,"Purchase not confirmed: "..
                tostring(rejection or "Unknown")
        end)

        Fruits.RollBusy=false
        S.FruitPurchaseLock=false
        if not S.Running then return end

        if not ok then
            Fruits.Status="Roll error"
            StopFruitAuto()
            Notify("Fruits","Roll error: "..tostring(success))
        elseif success then
            Notify("Fruits",message)
        elseif message
            and message:find("Purchase not confirmed",1,true) then
            StopFruitAuto()
            Notify("Fruits",message)
        elseif message and message~="On cooldown"
            and message~="Cancelled" then
            Fruits.NextCheck=0
            Notify("Fruits",message)
        end
    end)
end

local function FruitScheduler()
    while S.Running do
        local now=os.clock()
        local rotation=math.floor(os.time()/14400)

        if rotation~=Fruits.Rotation then
            Fruits.Rotation,Fruits.NextStock=rotation,0
        end
        if now>=Fruits.NextStock and not Fruits.StockBusy then
            Fruits.NextStock=now+45
            task.spawn(function()
                local ok,err=pcall(FruitStock)
                if not ok then
                    Fruits.StockBusy=false
                    warn("[Aevrix Fruits]",err)
                end
            end)
        end
        if now>=Fruits.NextCheck and not Fruits.CheckBusy then
            Fruits.NextCheck=now+20
            task.spawn(function()
                local ok,err=pcall(CheckFruitsGacha)
                if not ok then
                    Fruits.CheckBusy=false
                    warn("[Aevrix Gacha]",err)
                end
            end)
        end
        if Fruits.Deadline and now>=Fruits.Deadline then
            Fruits.Deadline=nil
            Fruits.Ready,Fruits.Status=false,"Cooldown ended; verifying"
            Fruits.NextCheck=0
        end
        if Fruits.AutoRoll and Fruits.Ready and not Fruits.RollBusy
            and not S.FruitFlight and not S.PvPFlight
            and now>=Fruits.NextAttempt then
            FruitRollCycle()
        end

        FruitInfo("FruitStock",Fruits.Stock)
        FruitInfo("FruitRestock",FruitTime(14400-os.time()%14400))
        FruitInfo("FruitCooldown",
            Fruits.Deadline and FruitTime(Fruits.Deadline-now)
            or (Fruits.Ready and "Ready" or Fruits.Status))
        task.wait(1)
    end
end

-- PVP

local PvP={
    Selected=nil,Dropdown=nil,Lookup={},
    Status=nil,LastStatus=""
}

local function PvPStatus(message)
    if PvP.LastStatus==message then return end
    PvP.LastStatus=message
    if PvP.Status then
        pcall(function() PvP.Status:SetValue(message) end)
    end
end
local function PvPTargetRoot(player)
    local character=player and player.Character
    local humanoid=character
        and character:FindFirstChildOfClass("Humanoid")
    local root=character and character:FindFirstChild("HumanoidRootPart")
    if humanoid and humanoid.Health>0 and root then return root end
end
local function RefreshPvPPlayers()
    local options,lookup={},{}
    for _,player in ipairs(Players:GetPlayers()) do
        if player~=P then
            local label=player.DisplayName.." (@"..player.Name..")"
            table.insert(options,label)
            lookup[label]=player
        end
    end
    table.sort(options)
    PvP.Lookup=lookup
    if PvP.Dropdown then
        pcall(function() PvP.Dropdown:SetValues(options) end)
    end
    if PvP.Selected and PvP.Selected.Parent~=Players then
        PvP.Selected=nil
    end
    if #options==0 then PvPStatus("No other players in server") end
    return #options
end
local function EndPvPFlight(message)
    if not S.PvPFlight then return end
    S.PvPFlight=nil
    PvPStatus(message or "Flight stopped")
    ClearFlight()
    if not (A.Farm or A.Chest or S.FruitFlight
        or S.FruitPurchaseLock) then
        RestoreNoclip()
        local _,humanoid=Char()
        if humanoid then humanoid.AutoRotate=true end
    end
end
local function StartPvPFlight()
    if S.PvPFlight or S.FruitFlight or S.FruitPurchaseLock or BossActive then
        Notify("PvP","Stop the existing flight or wait for Auto Roll")
        return
    end
    local player=PvP.Selected
    if not player or player.Parent~=Players then
        Notify("PvP","Choose a player first")
        return
    end
    local _,_,root=Char()
    local targetRoot=PvPTargetRoot(player)
    if not root or not targetRoot then
        Notify("PvP","A character is not loaded")
        return
    end
    S.PvPFlight={
        Player=player,Phase="Climb",
        CruiseY=math.max(root.Position.Y,targetRoot.Position.Y)+80,
        Deadline=os.clock()+180
    }
    PvPStatus("Flying to @"..player.Name)
end

local function UpdatePvPFlight(dt)
    local flight=S.PvPFlight
    if not flight then return end
    local _,_,root=Char()
    local target=PvPTargetRoot(flight.Player)

    if not root or not target or flight.Player.Parent~=Players then
        EndPvPFlight("Target left or character unavailable")
        return
    end
    if os.clock()>=flight.Deadline then
        EndPvPFlight("Flight timed out")
        return
    end

    local targetPos=target.Position
    local goal
    if flight.Phase=="Climb" then
        goal=Vector3.new(root.Position.X,flight.CruiseY,root.Position.Z)
        if (root.Position-goal).Magnitude<7 then
            flight.Phase="Cruise"
        end
    elseif flight.Phase=="Cruise" then
        goal=Vector3.new(
            targetPos.X,
            math.max(flight.CruiseY,targetPos.Y+20),
            targetPos.Z
        )
        local flat=Vector3.new(
            root.Position.X-targetPos.X,0,
            root.Position.Z-targetPos.Z
        )
        if flat.Magnitude<=14 then flight.Phase="Land" end
    else
        goal=targetPos+Vector3.new(5,3,0)
        if (root.Position-goal).Magnitude<=8 then
            EndPvPFlight("Arrived near @"..flight.Player.Name)
            return
        end
        local flat=Vector3.new(
            root.Position.X-targetPos.X,0,
            root.Position.Z-targetPos.Z
        )
        if flat.Magnitude>60 then flight.Phase="Cruise" end
    end
    if goal then Move(goal,320,dt,targetPos) end
end

-- CONTROLS

local function SyncToggle(toggle,value)
    if not toggle or S.Updating then return end
    S.Updating=true
    pcall(function() toggle:SetValue(value) end)
    S.Updating=false
end
local BossForceStop
local function SetFarm(enabled)
    if A.Farm==enabled then return end
    if enabled and BossForceStop then BossForceStop() end
    if enabled and A.Chest then
        A.Chest=false
        SyncToggle(S.ChestToggle,false)
        Stop()
    end
    A.Farm=enabled
    S.RetreatUntil=0
    ResetQuest()
    if enabled then Flight() else Stop() end
    SyncToggle(S.FarmToggle,enabled)
    Notify(enabled and "Auto Farm Enabled"
        or "Auto Farm Disabled","Hotkey: "..A.Hotkey)
end
local function SetChest(enabled)
    if A.Chest==enabled then return end
    if enabled and BossForceStop then BossForceStop() end
    if enabled and A.Farm then
        A.Farm=false
        SyncToggle(S.FarmToggle,false)
        Stop()
    end
    A.Chest=enabled
    S.ChestTarget=nil
    if enabled then
        RefreshChests()
        Flight()
    else
        Stop()
    end
    SyncToggle(S.ChestToggle,enabled)
    Notify(enabled and "Auto Chest Enabled"
        or "Auto Chest Disabled","Aevrix Hub")
end
-- BOSS FARM ENGINE | integrated with the main hub's flight/noclip/controller
local BossNames={}
for name in ("thegorillaking,bobby,yeti,mobleader,viceadmiral,warden,chiefwarden,swan,magmaadmiral,fishmanlord,wysper,thundergod,cyborg,saberexpert,thesaw,greybeard,iceadmiral,diamond,jeremy,fajita,donswan,smokeadmiral,awakenediceadmiral,tidekeeper,darkbeard,cursedcaptain,order,stone,islandempress,kiloadmiral,captainelephant,beautifulpirate,longma,soulreaper,cakequeen,cakeprince,doughking,doughprince,urban,diablo,deandre,ripindratrueform"):gmatch("[^,]+") do
    BossNames[name]=true
end
local BossChoices={"The Gorilla King","Bobby","Yeti","Mob Leader","Vice Admiral","Warden","Chief Warden","Swan","Magma Admiral","Fishman Lord","Wysper","Thunder God","Cyborg","Saber Expert","The Saw","Greybeard","Ice Admiral","Diamond","Jeremy","Fajita","Don Swan","Smoke Admiral","Awakened Ice Admiral","Tide Keeper","Darkbeard","Cursed Captain","Order","Stone","Island Empress","Kilo Admiral","Captain Elephant","Beautiful Pirate","Longma","Soul Reaper","Cake Queen","Cake Prince","Dough King","Dough Prince","rip_indra True Form","Urban","Diablo","Deandre"}
local B={
    Enabled=false,Lock=nil,Serial=0,Cache={},Memory={},Route={},RouteIndex=1,
    Checked={},Ignored={},Excluded={cyborg=true},Checking=false,ScanBusy=false,
    CheckEpoch=0,NextQuick=0,NextFull=0,NextRoute=0,NextDistance=0,
    NextAura=0,NextQuest=0,QuestBusy=false,QuestLock=nil,
    LastHP=nil,RetreatUntil=0,Side=1,Travel=nil,AttackAt=0,
    Info={},Shown={},BlacklistDropdown=nil,Toggle=nil,SeaTravel=false
}
local BConfig={Speed=260,Behind=35,Height=12,Range=55,Near=180,Cruise=300,Skip=180,Check=0.25}
local function BKey(name)
    local raw=tostring(name or ""):lower()
    if raw:find("rip_indra",1,true) then
        return (raw:find("true form",1,true) or raw:find("raid boss",1,true)) and "ripindratrueform" or "ripindra"
    end
    return Normal(name)
end
local function BShow(id,value)
    value=tostring(value)
    if B.Shown[id]==value then return end
    B.Shown[id]=value
    local p=B.Info[id]
    if p then pcall(function() p:SetValue(value) end) end
end
local function BStatus(v) BShow("Status",v) end
local function BRoot(m) return Root(m) end
local function BHum(m) return m and m:FindFirstChildOfClass("Humanoid") end
local function BAlive(m)
    if not m or not m:IsA("Model") or not m:IsDescendantOf(workspace) or Players:GetPlayerFromCharacter(m) then return false end
    local h=BHum(m)
    return h and h.Health>0 and BRoot(m)~=nil or false
end
local function BRecognized(m)
    if not BAlive(m) or BKey(m.Name)=="ripindra" then return false end
    local raw=m.Name:lower()
    if raw:find("[boss]",1,true) or raw:find("[raid boss]",1,true) or BossNames[BKey(m.Name)] then return true end
    for _,a in ipairs({"Boss","IsBoss","RaidBoss","IsRaidBoss"}) do
        if m:GetAttribute(a)==true then return true end
    end
    local h=BHum(m)
    local title=h and h.DisplayName or ""
    return title:lower():find("[boss]",1,true)~=nil or title:lower():find("[raid boss]",1,true)~=nil
end
local function BRemember(m)
    local r=BRoot(m)
    if r then B.Memory[BKey(m.Name)]={Name=m.Name,Position=r.Position} end
end
local function BCache(m)
    if BRecognized(m) then B.Cache[m]=true BRemember(m) end
end
local function BEligible(m)
    if not BRecognized(m) or B.Excluded[BKey(m.Name)] then return false end
    local r=BRoot(m)
    local k=BKey(m.Name)..":"..math.floor(r.Position.X/160)..":"..math.floor(r.Position.Z/160)
    return os.clock()>=(B.Ignored[m] or 0) and os.clock()>=(B.Ignored[k] or 0)
end
local function BNearest(pos,radius,key,exclude)
    local best,dist=nil,math.huge
    for m in pairs(B.Cache) do
        if m~=exclude and BEligible(m) and (not key or BKey(m.Name)==key) then
            local d=(BRoot(m).Position-pos).Magnitude
            if d<dist and (not radius or d<=radius) then best,dist=m,d end
        end
    end
    return best
end
local function BCount()
    local n=0 for m in pairs(B.Cache) do if BEligible(m) then n=n+1 end end
    return n
end
local function BScan(full)
    local folder=workspace:FindFirstChild("Enemies")
    if folder then
        for _,m in ipairs(folder:GetDescendants()) do
            if m:IsA("Model") and (BossNames[BKey(m.Name)] or m.Name:lower():find("[boss]",1,true)) then BCache(m) end
        end
    end
    if full and not B.ScanBusy then
        B.ScanBusy=true
        for _,m in ipairs(workspace:GetDescendants()) do
            if m:IsA("Model") and (BossNames[BKey(m.Name)] or m.Name:lower():find("[boss]",1,true) or m:GetAttribute("Boss")==true or m:GetAttribute("IsBoss")==true) then BCache(m) end
        end
        B.ScanBusy=false
    end
    for m in pairs(B.Cache) do if not m:IsDescendantOf(workspace) then B.Cache[m]=nil end end
    BShow("Detection",string.format("%s | Alive: %d | Spawns: %d",({[2753915549]="First Sea",[4442272183]="Second Sea",[7449423635]="Third Sea"})[game.PlaceId] or "Unknown Sea",BCount(),#B.Route))
end
local function BRoute()
    if B.Lock or B.Checking then return end
    local old=B.Route[B.RouteIndex]
    local oldKey=old and old.Key
    local route,seen={},{}
    local function add(name,pos)
        if typeof(pos)~="Vector3" or B.Excluded[BKey(name)] then return end
        local key=math.floor(pos.X/120)..":"..math.floor(pos.Z/120)
        if seen[key] then return end
        seen[key]=true
        route[#route+1]={Name=tostring(name),Position=pos,Key=key}
    end
    for _,info in pairs(B.Memory) do add(info.Name,info.Position) end
    for _,v in ipairs(workspace:GetDescendants()) do
        if v:IsA("BasePart") or v:IsA("Attachment") then
            local n=v.Name:lower()
            if v:GetAttribute("Boss")==true or v:GetAttribute("IsBoss")==true or n:find("bossspawn",1,true) or n:find("spawn_boss",1,true) then
                add(v.Name,v:IsA("Attachment") and v.WorldPosition or v.Position)
            end
        end
    end
    if #route==0 then
        local origin=workspace:FindFirstChild("_WorldOrigin")
        local locations=origin and origin:FindFirstChild("Locations")
        if locations then
            for _,v in ipairs(locations:GetChildren()) do
                if v:IsA("BasePart") or v:IsA("Attachment") then add(v.Name,v:IsA("Attachment") and v.WorldPosition or v.Position) end
            end
        end
    end
    table.sort(route,function(a,b) return a.Name==b.Name and a.Key<b.Key or a.Name<b.Name end)
    B.Route=route
    B.RouteIndex=math.min(B.RouteIndex,math.max(#route,1))
    if oldKey then for i,item in ipairs(route) do if item.Key==oldKey then B.RouteIndex=i break end end end
end
local function BNextSpawn()
    local count=#B.Route
    for _=1,count do
        if B.RouteIndex>count then B.RouteIndex=1 end
        local item=B.Route[B.RouteIndex]
        B.RouteIndex=B.RouteIndex%count+1
        if not B.Excluded[BKey(item.Name)] and os.clock()>=(B.Checked[item.Key] or 0) then return item end
    end
end
local function BDirect(goal,face)
    local _,_,r=Char()
    if not r or not Flight() then return end
    local d=goal-r.Position
    S.Velocity=d.Magnitude>1 and d.Unit*math.min(BConfig.Speed,d.Magnitude*20) or Vector3.zero
    S.BV.Velocity=S.Velocity
    if face then
        local f=Vector3.new(face.X-r.Position.X,0,face.Z-r.Position.Z)
        if f.Magnitude>0.05 then S.BG.CFrame=CFrame.lookAt(r.Position,r.Position+f.Unit) end
    end
end
local function BTravel(goal,face)
    local _,_,r=Char() if not r then return end
    local dx=Vector3.new(r.Position.X-goal.X,0,r.Position.Z-goal.Z).Magnitude
    if dx<=BConfig.Near then B.Travel=nil BDirect(goal,face) return end
    if not B.Travel then B.Travel={Phase="Climb",Y=math.max(BConfig.Cruise,r.Position.Y+85,goal.Y+100)} end
    local t=B.Travel
    if t.Phase=="Climb" then
        BDirect(Vector3.new(r.Position.X,t.Y,r.Position.Z),face)
        if r.Position.Y>=t.Y-8 then t.Phase="Cruise" end
    else BDirect(Vector3.new(goal.X,t.Y,goal.Z),face) end
end
local function BRelease(manual,blacklist)
    local l=B.Lock if not l then return end
    B.Ignored[l.Model]=os.clock()+(manual and BConfig.Skip or 15)
    if manual then
        local key=BKey(l.Name)..":"..math.floor(l.Position.X/160)..":"..math.floor(l.Position.Z/160)
        B.Ignored[key]=os.clock()+BConfig.Skip
    end
    B.Lock=nil B.QuestLock=nil B.Travel=nil B.RetreatUntil=0
    BShow("Target","None") BShow("Distance","No boss selected")
    BStatus(blacklist and "Blacklisted boss; finding next" or (manual and "Boss skipped; finding next" or "Boss defeated; finding next"))
end
local function BSelect(m)
    if B.Lock or not BEligible(m) then return false end
    B.Serial=B.Serial+1
    B.Lock={ID=B.Serial,Model=m,Name=m.Name,Key=BKey(m.Name),Position=BRoot(m).Position,HP=BHum(m).Health,LastDamage=os.clock()}
    B.Travel=nil B.QuestLock=nil B.NextQuest=0 B.RetreatUntil=0
    BShow("Target",m.Name) BStatus("LOCKED: "..m.Name)
    return true
end
local function BLocked()
    local l=B.Lock if not l then return end
    if B.Excluded[l.Key] then BRelease(false,true) return end
    local h=BHum(l.Model)
    if h and h.Health<=0 then BRelease(false,false) return end
    if BRecognized(l.Model) then l.Position=BRoot(l.Model).Position return l.Model end
    local recovered=BNearest(l.Position,350,l.Key,l.Model)
    if recovered then l.Model=recovered l.Position=BRoot(recovered).Position l.HP=BHum(recovered).Health return recovered end
    BStatus("Waiting for locked boss: "..l.Name)
end
local function BSkip()
    if B.Lock then BRelease(true,false) else BStatus("No current boss to skip") end
end
local function BSet(on)
    if B.Enabled==on then return end
    B.Enabled=on BossActive=on B.CheckEpoch=B.CheckEpoch+1 B.Checking=false B.Lock=nil B.Travel=nil B.LastHP=nil B.QuestLock=nil
    if on then
        if A.Farm then SetFarm(false) end
        if A.Chest then SetChest(false) end
        B.Checked={} B.NextQuick=0 B.NextFull=0 B.NextRoute=0
        BShow("Target","None") BShow("Distance","No boss selected") BStatus("Scanning loaded bosses...")
        if S.FruitFlight or S.PvPFlight or S.FruitPurchaseLock then
            B.Enabled=false BossActive=false
            BStatus("Stop fruit/PvP flight before boss farming")
            if B.Toggle then pcall(function() B.Toggle:SetValue(false) end) end
            return
        end
        Flight()
    else
        BShow("Target","None") BShow("Distance","Farm disabled") BStatus("Stopped")
        if not (A.Farm or A.Chest or S.FruitFlight or S.PvPFlight or S.FruitPurchaseLock) then Stop() end
    end
end
BossForceStop=function()
    BSet(false)
    if A.Farm then SetFarm(false) end
    if A.Chest then SetChest(false) end
    Fruits.AutoRoll=false
    if S.FruitFlight then EndFruitFlight(false,"Sea travel") end
    if S.PvPFlight then EndPvPFlight("Sea travel") end
    if B.Toggle then pcall(function() B.Toggle:SetValue(false) end) end
end
local function BQuest(m)
    local l=B.Lock
    if not l or B.QuestBusy or B.QuestLock==l.ID or os.clock()<B.NextQuest or QuestVisible() then return end
    local chosen
    for _,q in ipairs(QuestList) do
        if tonumber(q.Count)==1 and Normal(q.Enemy)==Normal(m.Name) and q.LevelReq<=Level() then chosen=q break end
    end
    if not chosen then B.NextQuest=os.clock()+20 return end
    local id,epoch=l.ID,B.CheckEpoch
    B.QuestBusy=true B.NextQuest=os.clock()+10
    task.spawn(function()
        local ok,result=pcall(function() return Comm:InvokeServer("StartQuest",chosen.ID,chosen.Index) end)
        B.QuestBusy=false
        if ok and result~=false and B.Enabled and B.CheckEpoch==epoch and B.Lock and B.Lock.ID==id then B.QuestLock=id end
    end)
end
local function BAura()
    if not S.Running or os.clock()<B.NextAura then return end
    local c=Char()
    if not c then return end
    B.NextAura=os.clock()+3
    local marker=c:FindFirstChild("HasBuso")
    local enabled=marker and (not marker:IsA("BoolValue") or marker.Value)
        or c:GetAttribute("HasBuso")==true
    if enabled then
        BShow("Aura","Enabled")
        return
    end
    if B.AuraBusy then return end
    B.AuraBusy=true
    BShow("Aura","Enabling...")
    task.spawn(function()
        local ok=pcall(function() Comm:InvokeServer("Buso") end)
        B.AuraBusy=false
        if S.Running then BShow("Aura",ok and "Checking..." or "Retrying...") end
    end)
end

task.spawn(function()
    while S.Running do
        pcall(BAura)
        task.wait(1)
    end
end)
local function BAttack(m)
    if not RegisterAttack or not RegisterHit or not RegisterAttack:IsA("RemoteEvent") or not RegisterHit:IsA("RemoteEvent") then return false,"Attack remotes unavailable" end
    local _,_,r=Char()
    if not r or (r.Position-BRoot(m).Position).Magnitude>BConfig.Range then return false,"Out of range" end
    local c,h=Char()
    local tool
    for _,t in ipairs(c:GetChildren()) do if t:IsA("Tool") and (t:GetAttribute("WeaponType")=="Melee" or t:GetAttribute("WeaponType")=="FightingStyle" or Melee[Normal(t.Name)] or (t.ToolTip or ""):lower()=="melee") then tool=t break end end
    if not tool then
        local backpack=P:FindFirstChild("Backpack")
        if backpack then
            for _,t in ipairs(backpack:GetChildren()) do
                if t:IsA("Tool") and (t:GetAttribute("WeaponType")=="Melee" or Melee[Normal(t.Name)]) then
                    h:EquipTool(t) tool=t break
                end
            end
        end
    end
    if not tool then return false,"Melee unavailable" end
    local part=m:FindFirstChild("Head") or BRoot(m)
    local ok=pcall(function() RegisterAttack:FireServer(0.1) RegisterHit:FireServer(part,{{m,part}}) end)
    return ok,ok and "Sent" or "Attack error"
end
local function BCheckSpawn()
    if B.Checking or B.Lock or not B.Enabled then return end
    local _,_,root=Char() if not root then return end
    local found=BNearest(root.Position)
    if found then BSelect(found) return end
    local loc=BNextSpawn()
    if not loc then BStatus("No known boss spawns; awaiting loaded bosses") return end
    B.Checking=true
    local epoch=B.CheckEpoch
    BStatus("Checking spawn: "..loc.Name)
    task.spawn(function()
        local c,h,r=Char()
        local candidate
        if r then
            local saved=r.CFrame
            ClearFlight()
            pcall(function()
                r.CFrame=CFrame.new(loc.Position+Vector3.new(0,25,0))
                r.AssemblyLinearVelocity=Vector3.zero
                local deadline=os.clock()+BConfig.Check
                repeat
                    BScan(false)
                    candidate=BNearest(loc.Position,225)
                    if candidate then break end
                    Run.Heartbeat:Wait()
                until not S.Running or not B.Enabled or B.CheckEpoch~=epoch or os.clock()>=deadline
            end)
            if P.Character==c and h.Health>0 and r.Parent then
                pcall(function() r.CFrame=saved r.AssemblyLinearVelocity=Vector3.zero end)
            end
        end
        if not S.Running or B.CheckEpoch~=epoch then return end
        B.Checking=false B.Checked[loc.Key]=os.clock()+8
        if not B.Enabled or B.Lock then return end
        local _,_,current=Char()
        local target=current and BNearest(current.Position) or candidate
        if target then BSelect(target) elseif candidate and BEligible(candidate) then BSelect(candidate) else BStatus("No eligible boss at "..loc.Name) end
    end)
end
local function BUpdate(dt)
    if not B.Enabled or B.SeaTravel or B.Checking then return end
    local _,h,r=Char() if not r then return end
    local now=os.clock()
    if now>=B.NextQuick then B.NextQuick=now+0.7 BScan(false) end
    if now>=B.NextFull and not B.ScanBusy then B.NextFull=now+6 task.defer(function() if B.Enabled and not B.Checking then pcall(BScan,true) end end) end
    if not B.Lock and now>=B.NextRoute then B.NextRoute=now+35 task.defer(function() if B.Enabled and not B.Lock then pcall(BRoute) end end) end
    if B.LastHP and h.Health<B.LastHP then B.RetreatUntil=now+2.5 B.Side=-B.Side end
    B.LastHP=h.Health
    local m
    if B.Lock then
        m=BLocked()
        if B.Lock and not m then
            B.Travel=nil
            if (r.Position-B.Lock.Position).Magnitude>20 then BDirect(B.Lock.Position) else Hold() end
        end
    end
    if not B.Lock then
        m=BNearest(r.Position)
        if m then BSelect(m) else BCheckSpawn() end
    end
    local l=B.Lock
    if l and m and l.Model==m and BAlive(m) then
        local br=BRoot(m)
        BQuest(m)
        local goal
        local dodge=now<B.RetreatUntil
        if dodge then
            goal=br.Position-br.CFrame.LookVector*85+br.CFrame.RightVector*(40*B.Side)+Vector3.new(0,65,0)
        else
            local forward=br.CFrame.LookVector
            local dir=Vector3.new(forward.X,0,forward.Z)
            dir=dir.Magnitude>0.01 and dir.Unit or Vector3.new(0,0,-1)
            goal=br.Position-dir*BConfig.Behind+Vector3.new(0,BConfig.Height,0)
        end
        BTravel(goal,br.Position)
        local hit,why=false,"Retreating"
        if not dodge then hit,why=BAttack(m) end
        local hp=BHum(m).Health
        if hp<l.HP then l.LastDamage=now end
        l.HP=hp
        if hp<=0 then BRelease(false,false)
        elseif dodge then BStatus("Locked: retreating from "..l.Name)
        elseif (r.Position-br.Position).Magnitude>BConfig.Range then BStatus("Locked: approaching "..l.Name)
        elseif not hit then BStatus("Locked: "..tostring(why))
        elseif now-l.LastDamage>5 then BStatus("Locked: attacking; no damage detected")
        else BStatus("Locked: attacking "..l.Name) end
    end
    if now>=B.NextDistance then
        B.NextDistance=now+0.2
        if B.Lock then
            local br=B.Lock.Model and BAlive(B.Lock.Model) and BRoot(B.Lock.Model)
            local pos=br and br.Position or B.Lock.Position
            BShow("Distance",(br and "Distance: " or "Last known: ")..math.floor((r.Position-pos).Magnitude+0.5).." studs")
        else BShow("Distance","No boss selected") end
    end
end
local function BBlacklistUpdate(selected)
    local exclusions={}
    if type(selected)=="table" then
        for k,v in pairs(selected) do
            local name=(type(k)=="number" and type(v)=="string") and v or (type(k)=="string" and v==true and k or nil)
            if name then exclusions[BKey(name)]=true end
        end
    end
    B.Excluded=exclusions
    if B.Lock and B.Excluded[B.Lock.Key] then BRelease(false,true) end
    B.NextRoute=0
end
local function BChangeSea(name)
    local destinations={
        ["First Sea"]={2753915549,"TravelMain"},
        ["Second Sea"]={4442272183,"TravelDressrosa"},
        ["Third Sea"]={7449423635,"TravelZou"}
    }
    local data=destinations[name]
    if not data or B.SeaTravel then return end
    if game.PlaceId==data[1] then BShow("SeaStatus","Already in "..name) return end
    BSet(false)
    if B.Toggle then pcall(function() B.Toggle:SetValue(false) end) end
    B.SeaTravel=true
    BShow("SeaStatus","Requesting "..name.."...")
    task.spawn(function()
        local ok,result=pcall(function() return Comm:InvokeServer(data[2]) end)
        if S.Running then BShow("SeaStatus",not ok and ("Travel error: "..tostring(result)) or result==false and "Travel rejected by game" or ("Travel requested: "..name)) end
        B.SeaTravel=false
    end)
end

local function Connect(signal,callback)
    table.insert(S.Connections,signal:Connect(callback))
end

Connect(Run.PreSimulation,function()
    if Moving() then Noclip() end
end)

Connect(Run.Heartbeat,function(dt)
    if not Moving() then return end
    local ok,err=pcall(function()
        if B.Checking then return end
        if not Flight() then return end

        if S.PvPFlight then
            UpdatePvPFlight(dt)
        elseif S.FruitFlight then
            UpdateFruitFlight(dt)
        elseif S.FruitPurchaseLock then
            Hold()
        elseif BossActive then
            BUpdate(dt)
        elseif A.Chest then
            UpdateChest(dt)
        elseif A.Farm and not UpdateFarm(dt) then
            SetFarm(false)
        end
    end)
    if not ok and os.clock()-S.LastError>3 then
        S.LastError=os.clock()
        warn("[Aevrix Hub]",err)
    end
end)

Connect(P.CharacterAdded,function()
    B.CheckEpoch=B.CheckEpoch+1 B.Checking=false B.Lock=nil B.Travel=nil B.LastHP=nil
    BShow("Target","None") BShow("Distance","No boss selected")
    if S.PvPFlight then EndPvPFlight("Character reset") end
    if S.FruitFlight then
        EndFruitFlight(false,"Character reset")
    end
    ClearFlight()
    RestoreNoclip()
    S.Target=nil
    S.ChestTarget=nil
    ResetCombat()
end)

Connect(UIS.InputBegan,function(input)
    if not S.Running or UIS:GetFocusedTextBox() then return end
    if input.UserInputType==Enum.UserInputType.Keyboard
        and input.KeyCode==Enum.KeyCode[A.Hotkey] then
        SetFarm(not A.Farm)
    end
end)

task.spawn(function() pcall(WatchNotifications) end)

task.spawn(function()
    while S.Running do
        if A.Farm and not S.PvPFlight and not S.FruitFlight
            and not S.FruitPurchaseLock then
            local ok,err=pcall(UpdateQuest)
            if not ok and os.clock()-S.LastError>3 then
                S.LastError=os.clock()
                warn("[Aevrix Quest]",err)
            end
        end
        task.wait(0.1)
    end
end)

task.spawn(function()
    while S.Running do
        if A.Farm and os.clock()-S.LastMemory>=2 then
            S.LastMemory=os.clock()
            pcall(RememberNPCs)
        end
        if (A.Chest or A.ChestESP)
            and os.clock()-S.LastChest>=5 then
            pcall(RefreshChests)
        end
        pcall(UpdateESP)
        task.wait(0.5)
    end
end)

task.spawn(function()
    while S.Running do
        if A.Stats and os.clock()-S.LastStat>=1 then
            S.LastStat=os.clock()
            local ok,err=pcall(DistributeStats)
            if not ok then
                S.StatBusy=false
                warn("[Aevrix Stats]",err)
            end
        end
        task.wait(0.25)
    end
end)

local function Cleanup()
    S.Running=false
    A.Farm=false
    A.Chest=false
    A.Stats=false
    B.Enabled=false BossActive=false B.CheckEpoch=B.CheckEpoch+1
    Fruits.AutoRoll=false
    S.FruitPurchaseLock=false
    if S.FruitFlight then EndFruitFlight(false,"Hub closed") end
    if S.PvPFlight then EndPvPFlight("Hub closed") end
    Stop()
    ResetQuest()
    for _,connection in ipairs(S.Connections) do
        pcall(function() connection:Disconnect() end)
    end
    for _,connection in pairs(S.Watched) do
        pcall(function() connection:Disconnect() end)
    end
    for object in pairs(S.Highlights) do RemoveESP(object) end
    if S.Library then
        pcall(function() S.Library:Unload() end)
    end
end
Env.AevrixCleanup=Cleanup

-- FLUENT UI

local ok,Lib=pcall(function()
    return loadstring(game:HttpGetAsync(
        "https://github.com/ActualMasterOogway/Fluent-Renewed/releases/latest/download/Fluent.luau"
    ))()
end)

if not ok then
    Cleanup()
    error("[Aevrix Hub] "..tostring(Lib))
end

S.Library=Lib
Notify=function(title,message)
    pcall(function()
        Lib:Notify({
            Title="Aevrix Hub | "..title,
            Content=message,Duration=3
        })
    end)
end

local Window=Lib:CreateWindow({
    Title="Aevrix Hub",
    SubTitle="Blox Fruits",
    TabWidth=145,
    Size=UDim2.fromOffset(650,455),
    Resize=true,
    MinSize=Vector2.new(470,350),
    Acrylic=true,
    Theme="Dark",
    MinimizeKey=Enum.KeyCode.RightControl
})

local FarmTab=Window:CreateTab({Title="Auto Farm",Icon="swords"})
local BossTab=Window:CreateTab({Title="Boss Farm",Icon="target"})
local SeaTab=Window:CreateTab({Title="Sea Travel",Icon="ship"})
local ChestTab=Window:CreateTab({Title="Auto Chest",Icon="package"})
local FruitsTab=Window:CreateTab({Title="Fruits",Icon="apple"})
local PvPTab=Window:CreateTab({Title="PvP",Icon="swords"})
local ESPTab=Window:CreateTab({Title="ESP",Icon="eye"})
local StatsTab=Window:CreateTab({
    Title="Auto Stats",Icon="chart-no-axes-column"
})
local SettingsTab=Window:CreateTab({
    Title="Settings",Icon="settings"
})

local function Toggle(tab,id,title,key)
    return tab:CreateToggle(id,{
        Title=title,Default=A[key],
        Callback=function(value)
            if S.Updating then return end
            if key=="Farm" then
                SetFarm(value)
            elseif key=="Chest" then
                SetChest(value)
            elseif key=="AcceptBossQuest" then
                A.AcceptBossQuest=value
                if A.Farm and S.Quest
                    and IsBossQuestRecord(S.Quest) then
                    if not value and QuestVisible() then
                        task.spawn(function()
                            pcall(function()
                                Comm:InvokeServer("AbandonQuest")
                            end)
                        end)
                    end
                    ResetQuest()
                end
            else
                A[key]=value
            end
        end
    })
end

local function Slider(tab,id,title,key,min,max,round)
    tab:CreateSlider(id,{
        Title=title,Min=min,Max=max,
        Default=A[key],Rounding=round or 0,
        Callback=function(value) A[key]=value end
    })
end
local function Drop(tab,id,title,key,values)
    tab:CreateDropdown(id,{
        Title=title,Values=values,Multi=false,
        Default=table.find(values,A[key]) or 1,
        Callback=function(value) A[key]=value end
    })
end

-- AUTO FARM TAB

FarmTab:CreateParagraph("FarmInfo",{
    Title="Auto Farm",
    Content="Default hotkey is F. Change it in Settings."
})
S.FarmToggle=Toggle(FarmTab,"Farm","Auto Farm","Farm")
Toggle(FarmTab,"AcceptBossQuest",
    "Accept Boss Quest","AcceptBossQuest")
Slider(FarmTab,"Target","Target Level","TargetLevel",1,3000)
Slider(FarmTab,"Speed","Movement Speed","Speed",50,650)
Drop(FarmTab,"Weapon","Weapon","Weapon",
    {"Melee","Sword","Gun","Fruit"})
Slider(FarmTab,"Range","Attack Range","Range",3,50)
Slider(FarmTab,"Delay","Attack Interval","Delay",0.005,1,2)
Toggle(FarmTab,"Skills","Auto Skills","Skills")
FarmTab:CreateParagraph("SkillsWarning",{
    Title="Auto Skills",
    Content="May cause you to get hit."
})
Slider(FarmTab,"SkillCooldown",
    "Skill Cooldown","SkillCooldown",1,30)


-- BOSS FARM / BLACKLIST UI (inside the integrated window)
for _,spec in ipairs({
    {"Target","Current Boss","None"},
    {"Status","Boss Farm Status","Stopped"},
    {"Distance","Distance to Boss","Farm disabled"},
    {"Detection","Boss Detection","Waiting"},
    {"Aura","Aura Status","Waiting"}
}) do
    B.Info[spec[1]]=BossTab:CreateParagraph("Boss"..spec[1],{
        Title=spec[2],Content=spec[3]
    })
end
B.Toggle=BossTab:CreateToggle("AutoBossFarm",{
    Title="Auto Boss Farm",Default=false,Callback=BSet
})
BossTab:CreateButton({Title="Skip Current Boss",Description="Skip for 3 minutes",Callback=BSkip})
BossTab:CreateParagraph("BlacklistInstructions",{
    Title="Boss Blacklist",Content="Choose bosses to skip. Cyborg starts excluded. Noncombat rip_indra is never targeted."
})
B.BlacklistDropdown=BossTab:CreateDropdown("BossBlacklist",{
    Title="Blacklisted Bosses",Values=BossChoices,Multi=true,
    Default={"Cyborg"},Callback=BBlacklistUpdate
})
BossTab:CreateButton({Title="Clear Blacklist",Callback=function()
    B.BlacklistDropdown:SetValue({}) BBlacklistUpdate({})
end})
BossTab:CreateButton({Title="Restore Default Blacklist",Callback=function()
    local values={Cyborg=true}
    B.BlacklistDropdown:SetValue(values) BBlacklistUpdate(values)
end})
B.Info.SeaStatus=SeaTab:CreateParagraph("SeaStatus",{
    Title="Sea Travel Status",Content="Current Sea: "..(({[2753915549]="First Sea",[4442272183]="Second Sea",[7449423635]="Third Sea"})[game.PlaceId] or "Unknown Sea")
})
for _,sea in ipairs({"First Sea","Second Sea","Third Sea"}) do
    SeaTab:CreateButton({Title="Go to "..sea,Callback=function() BChangeSea(sea) end})
end

-- AUTO CHEST TAB

S.ChestToggle=Toggle(ChestTab,"Chest","Auto Chest","Chest")
Slider(ChestTab,"ChestSpeed",
    "Chest Movement Speed","ChestSpeed",50,650)

-- ESP TAB

Toggle(ESPTab,"PlayerESP","Player ESP","PlayerESP")
Drop(ESPTab,"PlayerColor","Player Color",
    "PlayerColor",ColorNames)
Toggle(ESPTab,"ChestESP","Chest ESP","ChestESP")
Drop(ESPTab,"ChestColor","Chest Color",
    "ChestColor",ColorNames)

-- AUTO STATS TAB

Toggle(StatsTab,"AutoStats","Auto Stats","Stats")
StatsTab:CreateDropdown("MultiStats",{
    Title="Stats",
    Values=StatNames,
    Multi=true,
    Default={"Melee"},
    Callback=function(values)
        local selected={}
        for name,enabled in pairs(values) do
            if enabled and table.find(StatNames,name) then
                selected[name]=true
            end
        end
        A.SelectedStats=selected
        S.StatIndex=1
    end
})
Slider(StatsTab,"Points","Points Per Use","Points",1,100)

-- FRUITS TAB

local function FruitParagraph(id,title,initial)
    Fruits.Paragraphs[id]=FruitsTab:CreateParagraph(id,{
        Title=title,Content=initial
    })
end
FruitParagraph("FruitStock","Fruits In Stock","Loading...")
FruitParagraph("FruitRestock","Next Stock Refresh","Loading...")
FruitParagraph("FruitCooldown","Next Fruit Roll","Checking...")

Fruits.Toggle=FruitsTab:CreateToggle("AutoRollFruit",{
    Title="Auto Roll Fruit",
    Default=false,
    Callback=function(value)
        Fruits.AutoRoll=value
        if value then Fruits.NextCheck=0 end
        if not value and S.FruitFlight
            and S.FruitFlight.Automatic then
            EndFruitFlight(false,"Auto Roll disabled")
        end
    end
})
FruitsTab:CreateButton({
    Title="Fly to Blox Fruit Gacha",
    Callback=function()
        local flight,err=BeginFruitFlight("Gacha",false)
        if not flight then Notify("Fruits",err) end
    end
})
FruitsTab:CreateButton({
    Title="Fly to Blox Fruit Dealer",
    Callback=function()
        local flight,err=BeginFruitFlight("Dealer",false)
        if not flight then Notify("Fruits",err) end
    end
})
FruitsTab:CreateButton({
    Title="Stop Flight",
    Callback=function()
        if S.FruitFlight then
            if S.FruitFlight.Automatic then StopFruitAuto() end
            EndFruitFlight(false,"Flight cancelled")
        end
    end
})
task.spawn(FruitScheduler)

-- PVP TAB

PvP.Dropdown=PvPTab:CreateDropdown("PvPPlayer",{
    Title="Select Player",
    Values={},
    Multi=false,
    Default=nil,
    Callback=function(value)
        PvP.Selected=PvP.Lookup[value]
    end
})

PvP.Status=PvPTab:CreateParagraph("PvPStatus",{
    Title="Flight Status",
    Content="Select a player"
})

PvPTab:CreateButton({
    Title="Fly to Selected Player",
    Callback=StartPvPFlight
})

PvPTab:CreateButton({
    Title="Stop PvP Flight",
    Callback=function()
        EndPvPFlight("Flight cancelled")
    end
})

PvPTab:CreateButton({
    Title="Refresh Player List",
    Callback=function()
        Notify("PvP","Players found: "..RefreshPvPPlayers())
    end
})

Connect(Players.PlayerAdded,function()
    task.defer(RefreshPvPPlayers)
end)

Connect(Players.PlayerRemoving,function(player)
    if PvP.Selected==player then
        PvP.Selected=nil
        EndPvPFlight("Target left server")
    end
    task.defer(RefreshPvPPlayers)
end)

RefreshPvPPlayers()

-- SETTINGS TAB

local Hotkeys={}
for key in ("ABCDEFGHIJKLMNOPQRSTUVWXYZ"):gmatch(".") do
    table.insert(Hotkeys,key)
end
for i=1,10 do
    table.insert(Hotkeys,"F"..i)
end

Drop(SettingsTab,"Hotkey","Auto Farm Hotkey","Hotkey",Hotkeys)

Window:SelectTab(1)
Notify("Loaded","Aevrix Hub")
print("[Aevrix Hub ] Aevrix hub loaded")
