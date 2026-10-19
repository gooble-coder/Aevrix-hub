local function Loading(n) print(("[%d%%]"):format(n)) end
Loading(0)

local RS,Players=game:GetService("ReplicatedStorage"),game:GetService("Players")
local Player=Players.LocalPlayer
if not game:IsLoaded() then game.Loaded:Wait() end
Loading(10)

local Knit=require(RS:WaitForChild("Packages"):WaitForChild("Knit"))
local Info=RS:WaitForChild("Shared"):WaitForChild("Info")
local SeedConfig=require(Info:WaitForChild("SeedConfig"))
local FertilizerConfig=require(Info:WaitForChild("FertilizerConfig"))
local MutationConfig=require(Info:WaitForChild("MutationConfig"))
local CustomEnum=require(Info:WaitForChild("CustomEnum"))
Loading(20);Knit.OnStart():await();Loading(30)

local DataClient=Knit.GetController("DataClient")
local SeedService=Knit.GetService("SeedConveyorService")
local PlantService=Knit.GetService("PlantRoundService")
local PlotService=Knit.GetService("PlayerPlotService")
local SellService=Knit.GetService("SellStandService")
local SellFruits=Knit.GetService("SellFruitsService")
local ToolService=Knit.GetService("ToolService")
Loading(40)

local S={
	AutoFarm=false,AutoFarmFruit=false,AutoFertilizer=true,AutoSellAll=false,AutoSellDead=true,AutoSellFruit=true,
	HarvestWhen=false,HarvestSize=16,HarvestMinRarity="COMMON",KeepMutations={},KeepFruits={},
	CashReserve=0,MinRarity="COMMON",ScanDelay=.05,FruitDelay=.025
}

local RARITIES={"COMMON","RARE","EPIC","LEGENDARY","MYTHIC","CELESTIAL","SECRET","DIVINE","TRANSCENDENT","ANCIENT","ETHEREAL","GODLY"}
local RANK,MUTATIONS,FRUITS,seen={},{},{},{}
for i,v in ipairs(RARITIES) do RANK[v]=i end
for _,v in ipairs(MutationConfig.Order or {}) do MUTATIONS[#MUTATIONS+1]=v end
for _,v in pairs(SeedConfig.Seeds or {}) do
	local n=v.fruitName
	if n and not seen[n] then seen[n]=true;FRUITS[#FRUITS+1]=n end
end
table.sort(FRUITS)

local state,queued="IDLE",false
local fruitCollectBusy,fruitSellBusy,allSellBusy,fruitBulkQueued=false,false,false,false
local plot,pending,roundStart
local failed,collecting,fruitAck={},{},{}
local muted=setmetatable({},{__mode="k"})
local startingFertilizer,activeFertilizer="None","None"
local harvestRequested,fruitCollectToken=false,0
local queue,cycle,recover,fruitCycle,wakeSeller,bulkFruitSell

local function call(fn)
	local a,b,c=pcall(fn)
	if not a or not b then return false,c end
	return true,c
end
local function data() return DataClient.currentData end
local function inventory() local d=data();return d and d.Inventory end
local function money() local d=data();return d and d.Currency and d.Currency[CustomEnum.CURRENCIES.COINS] or 0 end
local function rebirth() local d=data();return d and d.Rebirth or 0 end
local function sellerBusy() return fruitSellBusy or allSellBusy end
local function sameId(a,b) return a~=nil and b~=nil and tostring(a)==tostring(b) end

local function currentSize()
	if typeof(roundStart)~="number" then return 0 end
	return math.max(0,math.floor((math.exp(.28*(workspace:GetServerTimeNow()-roundStart))-1)*100)/100)
end

local function fertilizerCost(key,seed)
	local cfg=SeedConfig.GetSeed(seed)
	return FertilizerConfig.GetCost(key,FertilizerConfig.GetSeedValue(seed,cfg and cfg.plantCost or 0),seed) or 0
end

local function bestFertilizer(seed)
	if not S.AutoFertilizer then return "None" end
	local budget,order=math.max(0,money()-S.CashReserve),FertilizerConfig.Order or {"None"}
	for i=#order,1,-1 do
		local key=order[i]
		if FertilizerConfig.IsUnlocked(key,rebirth()) and fertilizerCost(key,seed)<=budget then return key end
	end
	return "None"
end

local function checkHarvest()
	if not S.AutoFarm or not S.HarvestWhen or state~="GROWING" or harvestRequested or typeof(roundStart)~="number" or currentSize()<S.HarvestSize then return end
	harvestRequested=true
	if not pcall(function() PlantService:StopPlant() end) then harvestRequested=false;return end
	task.delay(1,function() if state=="GROWING" then harvestRequested=false end end)
end

local function getPlot()
	if plot and plot.Parent then return plot end
	local field=workspace:FindFirstChild("BigField")
	local plots=field and field:FindFirstChild("PlayerPlots")
	if not plots then return end
	for _,p in ipairs(plots:GetChildren()) do
		if p:GetAttribute("OwnerUserId")==Player.UserId then plot=p;return p end
	end
	local ok,id=call(function() return PlotService:GetMyPlot():await() end)
	if ok and id then plot=plots:FindFirstChild("PlayerPlot"..tostring(id)) end
	return plot
end

local function findTool(filter)
	for _,c in ipairs({Player.Character,Player:FindFirstChildOfClass("Backpack")}) do
		if c then for _,t in ipairs(c:GetChildren()) do if t:IsA("Tool") and filter(t) then return t end end end
	end
end

local function equip(tool)
	local char=Player.Character
	local hum=char and char:FindFirstChildOfClass("Humanoid")
	if not tool or not hum then return false end
	if tool.Parent~=char then hum:EquipTool(tool);task.wait(.015) end
	return tool.Parent==char
end

local function findSeed(seed) return findTool(function(t) return t:GetAttribute("IsSeed") and t:GetAttribute("SeedType")==seed end) end
local function findTree(dead) return findTool(function(t) return t:GetAttribute("IsTree") and (dead==nil or t:GetAttribute("IsDead")==dead) end) end

local function waitTree(dead)
	local start=os.clock()
	while os.clock()-start<2 do
		local tree=findTree(dead)
		if tree then return tree end
		task.wait(.04)
	end
end

local function bestSeed()
	local field=workspace:FindFirstChild("BigField")
	local conveyor=field and field:FindFirstChild("ConveyorSeeds")
	if not conveyor then return end
	local cash,minRank=math.max(0,money()-S.CashReserve),RANK[S.MinRarity] or 1
	local best,free
	for _,h in ipairs(conveyor:GetChildren()) do
		local seed,id,rarity=h:GetAttribute("SeedType"),h:GetAttribute("SpawnId"),h:GetAttribute("Rarity")
		local prompt=h:FindFirstChildWhichIsA("ProximityPrompt",true)
		if seed and id and prompt and prompt.Enabled and (not failed[id] or os.clock()>=failed[id]) and (RANK[rarity] or 0)>=minRank then
			local cfg=SeedConfig.GetSeed(seed)
			if cfg then
				local cost=cfg.plantCost or 0
				local item={type=seed,id=id,cost=cost}
				if cost==0 then free=free or item elseif cost<=cash and (not best or cost>best.cost) then best=item end
			end
		end
	end
	return best or free
end

local function buy(seed)
	state="BUYING"
	local ok,result=call(function() return SeedService:RequestPurchase(seed.id):await() end)
	failed[seed.id]=os.clock()+.5
	if not ok or result==false then return false end
	pending={type=seed.type,time=os.clock()}
	return true
end

local function plant()
	local seed=pending
	if not seed then return false end
	state="PLANTING"
	local tool,start=findSeed(seed.type),os.clock()
	while not tool and os.clock()-start<.75 do
		task.wait(.015)
		if pending~=seed then return false end
		tool=findSeed(seed.type)
	end
	if not tool then
		if pending==seed and os.clock()-seed.time>4 then pending=nil end
		return false
	end
	if not equip(tool) then return false end

	local p=getPlot()
	local root=Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
	if not p or not root then return false end
	root.CFrame=p:GetPivot()
	if pending~=seed then return false end

	local fert=bestFertilizer(seed.type)
	startingFertilizer=fert
	local ok,result=call(function() return PlantService:StartRound(seed.type,fert):await() end)
	if not ok or result==false then startingFertilizer="None";return false end
	if pending==seed then pending=nil end
	state="GROWING"
	return true
end

local function sellEverything(preserve)
	if allSellBusy then return false end
	allSellBusy=true
	if not preserve then state="SELLING" end
	local ok,result=call(function() return SellService:SellAll():await() end)
	if not preserve and state=="SELLING" then state="IDLE" end
	allSellBusy=false
	return ok and result~=false
end

local function sellTree(tree)
	if not tree or not tree.Parent or not equip(tree) then return false end
	state="SELLING"
	local ok,result=call(function() return SellService:SellTree():await() end)
	state="IDLE"
	return ok and result~=false
end

local function treeRarity(tree)
	local seed=tree and tree:GetAttribute("SeedType")
	local cfg=seed and SeedConfig.GetSeed(seed)
	return cfg and cfg.rarity or "COMMON"
end

local function treeMutations(tree)
	local t,raw={},tree and tree:GetAttribute("Mutations")
	if typeof(raw)=="string" and raw~="" then
		for _,m in ipairs(MutationConfig.Sanitize(string.split(raw,","))) do t[m]=true end
	end
	return t
end

local function keepTree(tree)
	if not tree or (RANK[treeRarity(tree)] or 1)>=(RANK[S.HarvestMinRarity] or 1) then return true end
	local muts=treeMutations(tree)
	for m,on in pairs(S.KeepMutations) do if on and muts[m] then return true end end
	return false
end

local function handleHarvestedTree()
	local tree=waitTree(false)
	if not tree or keepTree(tree) then state="IDLE";return end
	sellTree(tree)
end

local function fruitName(tool)
	if not tool then return end
	local n=tool:GetAttribute("FruitName")
	if n then return n end
	local seed=tool:GetAttribute("SeedType")
	local cfg=seed and SeedConfig.GetSeed(seed)
	return cfg and cfg.fruitName or seed
end

local function itemFruitName(item)
	if not item then return end
	if item.fruitName then return item.fruitName end
	local cfg=item.seedType and SeedConfig.GetSeed(item.seedType)
	return cfg and cfg.fruitName or item.seedType
end

local function keptFruit(n) return n and S.KeepFruits[n]==true end
local function fruitState()
	return state=="IDLE" or state=="GROWING" or
		(not S.AutoFarm and state~="BUYING" and state~="PLANTING" and state~="SELLING" and state~="RECOVERING")
end
local function canCollect(token) return S.AutoFarmFruit and fruitState() and (token==nil or token==fruitCollectToken) end
local function canSellFruit() return S.AutoSellFruit and not S.AutoSellAll and fruitState() end

local function fruitCount()
	local inv=inventory()
	if not inv then return 0 end
	local n=0
	for _,list in ipairs({inv.Hotbar or {},inv.Storage or {}}) do
		for _,x in ipairs(list) do if x and not x.empty and x.itemType=="Fruit" then n+=1 end end
	end
	return n
end

bulkFruitSell=function()
	if fruitBulkQueued or allSellBusy or not S.AutoSellAll or fruitCount()==0 or pending then return end
	if state=="BUYING" or state=="PLANTING" or state=="SELLING" or state=="RECOVERING" then return end
	fruitBulkQueued=true
	task.spawn(function()
		sellEverything(true)
		fruitBulkQueued=false
		if S.AutoSellAll and fruitCount()>0 then task.delay(.025,bulkFruitSell) end
		if S.AutoFarm and state=="IDLE" then queue() end
	end)
end

local function muteFruit(tool)
	if not tool or muted[tool] then return end
	local save={}
	for _,p in ipairs(tool:GetDescendants()) do
		if p:IsA("BasePart") then
			save[#save+1]={p,p.CanQuery,p.CanCollide,p.CanTouch,p.LocalTransparencyModifier}
			p.CanQuery=false;p.CanCollide=false;p.CanTouch=false;p.LocalTransparencyModifier=1
		end
	end
	muted[tool]=save
end

local function restoreFruit(tool)
	local save=muted[tool]
	if not save then return end
	muted[tool]=nil
	for _,x in ipairs(save) do
		local p=x[1]
		if p and p.Parent then p.CanQuery=x[2];p.CanCollide=x[3];p.CanTouch=x[4];p.LocalTransparencyModifier=x[5] end
	end
end

local function nextFruitItem()
	local inv=inventory()
	if not inv then return end
	for _,pack in ipairs({{true,inv.Hotbar or {}},{false,inv.Storage or {}}}) do
		for i,item in ipairs(pack[2]) do
			if item and not item.empty and item.itemType=="Fruit" and not keptFruit(itemFruitName(item)) then return pack[1],i,item end
		end
	end
end

local function itemExists(id)
	if id==nil then return false end
	local inv=inventory()
	if not inv then return false end
	for _,list in ipairs({inv.Hotbar or {},inv.Storage or {}}) do
		for _,item in ipairs(list) do if item and not item.empty and sameId(item.id,id) then return true end end
	end
	return false
end

local function fruitTool(id,container)
	if not container then return end
	for _,tool in ipairs(container:GetChildren()) do
		if tool:IsA("Tool") and tool:GetAttribute("IsFruit") and not keptFruit(fruitName(tool))
			and (id==nil or sameId(tool:GetAttribute("ItemId"),id)) then return tool end
	end
end

local function equippedFruit(id) return fruitTool(id,Player.Character) end
local function backpackFruit(id) return fruitTool(id,Player:FindFirstChildOfClass("Backpack")) end

local function equipFruitItem(hotbar,index,item)
	local id=item.id
	local tool=equippedFruit(id)
	if tool then muteFruit(tool);return tool end

	tool=backpackFruit(id)
	if tool then
		muteFruit(tool)
		local char=Player.Character
		local hum=char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum:EquipTool(tool)
			local start=os.clock()
			while canSellFruit() and os.clock()-start<.1 do
				if tool.Parent==char then return tool end
				if id and not itemExists(id) then return end
				task.wait(.003)
			end
		end
		restoreFruit(tool)
		return
	end

	ToolService.ToggleEquip:Fire(hotbar,index)
	local start=os.clock()
	while canSellFruit() and os.clock()-start<.12 do
		tool=equippedFruit(id)
		if tool then muteFruit(tool);return tool end
		if id and not itemExists(id) then return end
		task.wait(.003)
	end
end

local function sellFruitFast()
	if not canSellFruit() then return false end
	local hotbar,index,item=nextFruitItem()
	if index==nil then return false end

	local id=item.id
	local fruit=equipFruitItem(hotbar,index,item)
	if not fruit then return false end

	muteFruit(fruit)
	if not pcall(function() SellFruits:SellFruit() end) then restoreFruit(fruit);return false end

	task.delay(.025,function()
		if canSellFruit() and fruit.Parent==Player.Character and (id==nil or itemExists(id)) then
			pcall(function() SellFruits:SellFruit() end)
		end
	end)

	local start=os.clock()
	while os.clock()-start<.16 do
		if (id~=nil and not itemExists(id)) or not fruit.Parent then muted[fruit]=nil;return true end
		if fruit.Parent~=Player.Character then break end
		task.wait(.003)
	end
	restoreFruit(fruit)
	return false
end

wakeSeller=function()
	if S.AutoSellAll then bulkFruitSell();return end
	if fruitSellBusy or not canSellFruit() then return end
	local _,index=nextFruitItem()
	if index==nil then return end

	fruitSellBusy=true
	task.spawn(function()
		local ok,err=pcall(function()
			local fails=0
			while canSellFruit() do
				local _,i=nextFruitItem()
				if i==nil then break end
				if sellFruitFast() then fails=0 else
					fails+=1
					if fails>=4 then break end
					task.wait(.008)
				end
			end
		end)

		fruitSellBusy=false
		if not ok then warn("[FRUIT SELL]",err) end
		local _,i=nextFruitItem()
		if canSellFruit() and i~=nil then task.delay(.02,wakeSeller) end
	end)
end

local toolConns={}
local function bindFruitTools()
	for _,c in ipairs(toolConns) do c:Disconnect() end
	table.clear(toolConns)

	local function added(tool)
		if S.AutoSellFruit and not S.AutoSellAll and tool:IsA("Tool") and tool:GetAttribute("IsFruit") and not keptFruit(fruitName(tool)) then
			muteFruit(tool)
			if not fruitSellBusy then task.defer(wakeSeller) end
		end
	end

	for _,container in ipairs({Player.Character,Player:FindFirstChildOfClass("Backpack")}) do
		if container then
			toolConns[#toolConns+1]=container.ChildAdded:Connect(added)
			for _,tool in ipairs(container:GetChildren()) do added(tool) end
		end
	end
end

bindFruitTools()
Player.CharacterAdded:Connect(function() task.defer(bindFruitTools) end)

pcall(function()
	DataClient.EV_UPDATE:Connect(function()
		if S.AutoSellAll then bulkFruitSell()
		elseif S.AutoSellFruit and not fruitSellBusy then task.defer(wakeSeller) end
	end)
end)

local function readyFruit(spawn,tree,p)
	if not spawn or not spawn.Parent or spawn:GetAttribute("FruitLocked")==true then return false end
	local start=spawn:GetAttribute("FruitStartTime")
	return typeof(start)=="number" and workspace:GetServerTimeNow()-start>=
		SeedConfig.GetFruitGrowthTime(tree:GetAttribute("Multiplier") or 1,SeedConfig.PlotGrowthMult(p))
end

local function firePrompt(prompt)
	if not prompt or not prompt.Parent then return false end
	local old=prompt.Enabled
	prompt.Enabled=true
	local ok=pcall(function()
		if type(fireproximityprompt)=="function" then fireproximityprompt(prompt)
		else prompt:InputHoldBegin();task.wait(math.max(prompt.HoldDuration,.02));prompt:InputHoldEnd() end
	end)
	task.delay(.03,function() if prompt.Parent then prompt.Enabled=old end end)
	return ok
end

local function normId(v) return tostring(v or ""):gsub("^PlotTree_","") end
local function fruitKey(tree,spawn) return normId(tree.Name)..":"..tostring(spawn:GetAttribute("SpawnIndex")) end

local function waitCollect(spawn,key,before,token,time)
	local start=os.clock()
	while canCollect(token) and os.clock()-start<time do
		if (fruitAck[key] or 0)>before or not spawn.Parent then return true end
		task.wait(.005)
	end
	return false
end

local function collectFruit(tree,spawn,token)
	if collecting[spawn] or not canCollect(token) or not spawn.Parent then return false end
	local prompt=spawn:FindFirstChildWhichIsA("ProximityPrompt")
	if not prompt then return false end

	collecting[spawn]=true
	local key=fruitKey(tree,spawn)
	local before=fruitAck[key] or 0

	firePrompt(prompt)
	local done=waitCollect(spawn,key,before,token,.07)

	if not done and canCollect(token) and spawn.Parent then
		firePrompt(prompt)
		done=waitCollect(spawn,key,before,token,.1)
	end

	if not done and canCollect(token) and type(fireproximityprompt)~="function" then
		local root=Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
		if root and spawn.Parent then
			local old=root.CFrame
			root.CFrame=spawn.CFrame*CFrame.new(0,0,2);task.wait(.01)
			if canCollect(token) and spawn.Parent then firePrompt(prompt) end
			done=waitCollect(spawn,key,before,token,.25)
			if root.Parent then root.CFrame=old end
		end
	end

	collecting[spawn]=nil
	if done then if S.AutoSellAll then bulkFruitSell() else task.defer(wakeSeller) end end
	return done
end

local function collectFruits(token)
	if not canCollect(token) then return end
	local p=getPlot()
	if not p then return end

	for _,tree in ipairs(p:GetChildren()) do
		if not canCollect(token) then return end
		if tree:IsA("Model") and tree.Name:match("^PlotTree_") then
			local spawns=tree:FindFirstChild("FruitSpawns")
			if spawns then for _,spawn in ipairs(spawns:GetChildren()) do
				if not canCollect(token) then return end
				if spawn:IsA("BasePart") and readyFruit(spawn,tree,p) then collectFruit(tree,spawn,token) end
			end end
		end
	end
end

fruitCycle=function()
	if fruitCollectBusy or not canCollect() then return end
	fruitCollectBusy=true
	local token=fruitCollectToken

	task.spawn(function()
		local ok,err=pcall(function() collectFruits(token) end)
		fruitCollectBusy=false
		if not ok then warn("[FRUIT]",err) end
		if S.AutoFarm and state=="IDLE" then queue() end
	end)
end

queue=function(delay)
	if queued or not S.AutoFarm then return end
	queued=true
	task.delay(delay or 0,function()
		queued=false
		if S.AutoFarm then cycle() end
	end)
end

recover=function()
	if not S.AutoFarm then state="CRASHED";return end
	if state=="RECOVERING" then return end
	state="RECOVERING"

	task.spawn(function()
		for _=1,40 do
			if not S.AutoFarm then state="CRASHED";return end
			local ok,result=call(function() return PlantService:CollectDeadTree():await() end)

			if ok and result~=false then
				while sellerBusy() and S.AutoFarm do task.wait(.005) end
				if S.AutoSellDead then
					local tree=waitTree(true)
					if tree then sellTree(tree) else state="IDLE" end
				else state="IDLE" end
				queue();return
			end
			task.wait(.025)
		end
		state="IDLE";queue()
	end)
end

cycle=function()
	if not S.AutoFarm or state~="IDLE" or fruitCollectBusy or sellerBusy() then return end

	if pending then
		if not plant() and state=="PLANTING" then state="IDLE";queue(.03) end
		return
	end

	local seed=bestSeed()
	if not seed then return end
	if not buy(seed) then state="IDLE";queue(.03);return end
	state="IDLE";queue()
end

local function clearRound()
	roundStart=nil
	activeFertilizer,startingFertilizer="None","None"
	harvestRequested=false
end

PlotService.FruitCollected:Connect(function(_,treeId,index)
	local key=normId(treeId)..":"..tostring(index)
	fruitAck[key]=(fruitAck[key] or 0)+1
	if S.AutoSellAll then bulkFruitSell() else task.defer(wakeSeller) end
end)

PlantService.RoundStartedAll:Connect(function(uid,_,startTime)
	if uid~=Player.UserId then return end
	pending=nil
	roundStart=typeof(startTime)=="number" and startTime or nil
	activeFertilizer=startingFertilizer or "None"
	startingFertilizer="None"
	harvestRequested=false
	state="GROWING"
	if S.AutoSellAll then bulkFruitSell() else task.defer(wakeSeller) end
end)

PlantService.CrashedAll:Connect(function(uid)
	if uid~=Player.UserId then return end
	clearRound()
	if state~="RECOVERING" and state~="SELLING" then recover() end
end)

PlantService.PlantStoppedAll:Connect(function(uid)
	if uid~=Player.UserId then return end
	local wasAutoHarvest=harvestRequested
	clearRound()
	if state=="RECOVERING" or state=="SELLING" then return end

	task.spawn(function()
		while sellerBusy() and S.AutoFarm do task.wait(.005) end
		if wasAutoHarvest then
			if S.AutoSellAll then sellEverything(false) else handleHarvestedTree() end
		else state="IDLE" end

		queue()
		if S.AutoSellAll then bulkFruitSell() else task.defer(wakeSeller) end
	end)
end)

PlantService.RoundResetAll:Connect(function(uid)
	if uid~=Player.UserId then return end
	clearRound()
	if state=="RECOVERING" or state=="SELLING" then return end
	state="IDLE";queue()
	if S.AutoSellAll then bulkFruitSell() else task.defer(wakeSeller) end
end)

SeedService.SeedSpawned:Connect(function()
	if S.AutoFarm and state=="IDLE" and not pending then queue(.37) end
end)

PlotService.FruitReady:Connect(function()
	if S.AutoFarmFruit then task.delay(.005,fruitCycle) end
end)

while not DataClient.currentData do task.wait(.025) end
task.spawn(getPlot)
Loading(55)

local Library=loadstring(game:HttpGetAsync("https://github.com/ActualMasterOogway/Fluent-Renewed/releases/latest/download/Fluent.luau"))()
Loading(75)
local InterfaceManager=loadstring(game:HttpGetAsync("https://raw.githubusercontent.com/ActualMasterOogway/Fluent-Renewed/master/Addons/InterfaceManager.luau"))()
Loading(90)

local Window=Library:CreateWindow{Title="Gooble",SubTitle="Auto Farm",TabWidth=160,Size=UDim2.fromOffset(680,460),Resize=true,MinSize=Vector2.new(520,380),Acrylic=false,Theme="Dark",MinimizeKey=Enum.KeyCode.RightControl}
local Tabs={Main=Window:CreateTab{Title="Main",Icon="sprout"},Hotkeys=Window:CreateTab{Title="Hotkeys",Icon="keyboard"},Settings=Window:CreateTab{Title="Settings",Icon="settings"}}
local M=Tabs.Main

local function T(id,title,desc,default) return M:CreateToggle(id,{Title=title,Description=desc,Default=default}) end
local function D(id,title,desc,values,multi,default) return M:CreateDropdown(id,{Title=title,Description=desc,Values=values,Multi=multi,Default=default}) end

local Status=M:CreateParagraph("Status",{Title="Status",Content="Auto Farm: OFF"})
local Farm=T("AutoFarm","Auto Farm","Automatically farms trees.",false)
local AutoFarmFruit=T("AutoFarmFruit","Auto Farm Fruits","Automatically collect ready fruits.",false)
local AutoFertilizer=T("AutoFertilizer","Auto Fertilizer","Use strongest affordable unlocked fertilizer.",true)
local AutoSellAll=M:CreateToggle("AutoSellAll",{Title="Auto Sell All (Recommended when selling fruits)",Default=false})
local AutoSellDead=T("AutoSellDead","Auto Sell Dead Trees","Sell trees collected after crashes.",true)
local AutoSellFruit=T("AutoSellFruit","Auto Sell Fruits","Fruit-only seller used while Auto Sell All is OFF.",true)
local KeepFruits=D("KeepFruits","Keep Fruits","Ignored while Auto Sell All is ON.",FRUITS,true,{})
local HarvestWhen=T("HarvestWhen","Harvest At","Harvest current tree at selected size.",false)
local HarvestSize=M:CreateSlider("HarvestSize",{Title="Harvest Size",Description="Multiplier to harvest at.",Default=16,Min=2.5,Max=100,Rounding=1})
local HarvestRarity=D("HarvestRarity","Harvest Minimum Rarity","Sell harvested trees below this rarity.",RARITIES,false,1)
local MutationFilter=D("KeepMutations","Keep Mutations","Keep low-rarity trees with selected mutations.",MUTATIONS,true,{})
local Rarity=D("Rarity","Minimum Seed Rarity","Ignore conveyor seeds below this rarity.",RARITIES,false,1)
local Reserve=M:CreateInput("Reserve",{Title="Cash Reserve",Description="Coins farming/fertilizer will not spend.",Default="0",Placeholder="0",Numeric=true,Finished=true})

local function selectedSet(v)
	local t={}
	if type(v)=="table" then
		for k,x in pairs(v) do
			if type(k)=="number" and type(x)=="string" then t[x]=true
			elseif type(k)=="string" and x then t[k]=true end
		end
	end
	return t
end

Farm:OnChanged(function(v)
	S.AutoFarm=v==true
	if not S.AutoFarm then queued=false;return end
	if state=="CRASHED" then recover() else checkHarvest();if state=="IDLE" then queue() end end
end)

AutoFarmFruit:OnChanged(function(v)
	fruitCollectToken+=1
	S.AutoFarmFruit=v==true
	if S.AutoFarmFruit then fruitCycle() end
end)

AutoFertilizer:OnChanged(function(v) S.AutoFertilizer=v==true end)

AutoSellAll:OnChanged(function(v)
	S.AutoSellAll=v==true
	if S.AutoSellAll then task.defer(bulkFruitSell)
	elseif S.AutoSellFruit then task.defer(wakeSeller) end
end)

AutoSellDead:OnChanged(function(v) S.AutoSellDead=v==true end)
AutoSellFruit:OnChanged(function(v) S.AutoSellFruit=v==true;if S.AutoSellFruit and not S.AutoSellAll then task.defer(wakeSeller) end end)
KeepFruits:OnChanged(function(v) S.KeepFruits=selectedSet(v);if S.AutoSellFruit and not S.AutoSellAll then task.defer(wakeSeller) end end)
HarvestWhen:OnChanged(function(v) S.HarvestWhen=v==true;harvestRequested=false;if S.HarvestWhen then checkHarvest() end end)
HarvestSize:OnChanged(function(v) S.HarvestSize=tonumber(v) or 16;harvestRequested=false;if S.HarvestWhen then checkHarvest() end end)

HarvestRarity:SetValue(S.HarvestMinRarity)
HarvestRarity:OnChanged(function(v) if type(v)=="string" and RANK[v] then S.HarvestMinRarity=v end end)
MutationFilter:OnChanged(function(v) S.KeepMutations=selectedSet(v) end)

Rarity:SetValue(S.MinRarity)
Rarity:OnChanged(function(v)
	if type(v)=="string" and RANK[v] then
		S.MinRarity=v
		if S.AutoFarm and state=="IDLE" then queue() end
	end
end)

Reserve:OnChanged(function(v)
	S.CashReserve=math.max(0,tonumber(v or Reserve.Value) or 0)
	if S.AutoFarm and state=="IDLE" then queue() end
end)

Tabs.Hotkeys:CreateKeybind("FarmKey",{Title="Auto Farm Hotkey",Description="Toggle Auto Farm",Default="F6",Mode="Hold",Callback=function(v) if v then Farm:SetValue(not Farm.Value) end end})
Tabs.Hotkeys:CreateKeybind("FruitFarmKey",{Title="Fruit Farm Hotkey",Description="Toggle Auto Farm Fruits",Default="F7",Mode="Hold",Callback=function(v) if v then AutoFarmFruit:SetValue(not AutoFarmFruit.Value) end end})
Tabs.Hotkeys:CreateParagraph("HotkeyInfo",{Title="UI Hotkey",Content="RightControl = Minimize / Open UI"})

Loading(97)

pcall(function()
	InterfaceManager:SetLibrary(Library)
	InterfaceManager:SetFolder("Gooble")
	InterfaceManager:BuildInterfaceSection(Tabs.Settings)
end)

Window:SelectTab(1)

local function selectedNames(list,set)
	local t={}
	for _,n in ipairs(list) do if set[n] then t[#t+1]=n end end
	return #t>0 and table.concat(t,", ") or "None"
end

task.spawn(function()
	while not Library.Unloaded do
		task.wait(.25)
		pcall(function()
			local fert=FertilizerConfig.Get(activeFertilizer)
			Status:SetValue(string.format(
				"State: %s\nCoins: %d\nRebirth: %d\nFertilizer: %s (%.2fx)\nFruits: %d\nFruit Farm: %s\nFruit Seller: %s\nKeep Fruits: %s\nCurrent Size: %.2fx\nHarvest: %s @ %.1fx\nHarvest Keep: %s+\nKeep Mutations: %s\nAuto Farm: %s\nSell All: %s\nDead Tree Sell: %s\nFruit Sell: %s\nSeed Rarity: %s\nCash Reserve: %d",
				state,math.floor(money()),rebirth(),activeFertilizer,fert and fert.mult or 1,fruitCount(),
				S.AutoFarmFruit and "ON" or "OFF",allSellBusy and "SELL ALL" or fruitSellBusy and "SELLING" or "IDLE",
				selectedNames(FRUITS,S.KeepFruits),currentSize(),S.HarvestWhen and "ON" or "OFF",S.HarvestSize,
				S.HarvestMinRarity,selectedNames(MUTATIONS,S.KeepMutations),S.AutoFarm and "ON" or "OFF",
				S.AutoSellAll and "ON" or "OFF",S.AutoSellDead and "ON" or "OFF",S.AutoSellFruit and "ON" or "OFF",
				S.MinRarity,S.CashReserve
			))
		end)
	end
end)

task.spawn(function()
	local nextFarm=0
	while true do
		task.wait(S.FruitDelay)
		local now=os.clock()

		if S.AutoFarm and now>=nextFarm then
			nextFarm=now+S.ScanDelay
			checkHarvest()
			if state=="IDLE" and not fruitCollectBusy and not sellerBusy() then queue() end
		end

		if S.AutoFarmFruit then fruitCycle() end
		if S.AutoSellAll then bulkFruitSell() elseif S.AutoSellFruit then wakeSeller() end
	end
end)

Loading(100)
