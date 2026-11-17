-- Read-slot repair, also runs when the multiplayer menu has no active room.
-- Native consumption retains InventoryContents[item] = 0: presence is history.
local dir=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
return function(valid,log)
 local effects=dofile(dir..'reward_effects.lua')(valid,log)
 local R={};local nextPoll=0;local identity;local readyAt=0;local finished=false
 local rows={
  {'Fisher_00/Fisher24/Fisher_02/GiantSwampFish/GiantFish_Data','GiantSwampFish_IsDead',1,'KeyItems/JigekiKeys/JIgeki_Key_2_Item'},
  {'Boner_00/Skeletons24/ShrineBoss/Boner_Shrineboss_Data','ShrineBossRewardCount',1,'KeyItems/ShopProgressionKey/StoneDuckShopUnlock','ShopUnlockFinished'},
  {'WhaleKing/WhaleKing_Boss_Data','WhaleKingRewardCount',1,'KeyItems/ShopProgressionKey/SilverDuckShopUnlockKey','ShopkeepUnlock1'},
  {'WhaleKing/WhaleKing_SG/WhaleKing_SZ_Data','WhaleKingSGRewardCount',1,'KeyItems/TridentKeys/TridentKey_04_Data'},
  {'Necronomicon/Necronomicon_Data','NecronomiconRewardCount',1,'KeyItems/AcidVial/AcidVial'},
  {'Necronomicon/Necronomicon_Data','NecronomiconRewardCount',2,'KeyItems/ShopProgressionKey/GoldDuckShopUnlockKey','ShopkeepUnlock2'},
  {'LargeRobot/LargeRobot_Rusted_Data','LargeRustyRobotRewardCount',1,'KeyItems/ShopProgressionKey/MechDuckShopUnlock','ShopkeepUnlock3'},
  {'Dragon/Dragon_ROS/ROSDragon_Data','ROSDragonRewardCount',1,'Consumables/MementoMirror/MementoMirror'},
  {'FishWifeEvil/FishWifeEvil_Data','FishwifeEvilRewardCount',1,'Accessories/RuneVisionAccessory/RuneVisionUnlock4'},
  {'Golem/Golem_WhiteTree_Data','WhiteTreeGolemDead',1,'Weapons/Daggers/BigNut/BigNut'},
  -- Their ordinary enemies share bestiary identities; never infer a special
  -- Boss handover solely from a regular mage/blood-lord kill.
  {false,'WitchBonerRewardCount',1,'KeyItems/PrisonKeys/Prison_key_2F_Item'},
  {false,'QDCoopBossClaim~JosamiAmulet',1,'Accessories/JosamiAmulet/JosamiAmulet'}
 }
 local function path(base,s)return base..s..'.'..s:match('([^/]+)$')end
 local function named(s,k)local n=FName(k);return s.NamedSaveData:Contains(n)and s.NamedSaveData:Find(n):get()or 0 end
 function R.repair(game,player)
  local s=game.ActiveSaveSlot;local helper,ks;local pending=false;local grants=0
  for _,r in ipairs(rows)do
   local ok,err=pcall(function()
    local eligible=named(s,r[2])>=r[3];local evidence='claim:'..r[2]
    if not eligible and r[1]then
     local data=LoadAsset(path('/Game/Enemies/',r[1]));assert(valid(data),'Boss data unavailable '..r[1])
     eligible=s.KilledEnemyCounts:Contains(data)and s.KilledEnemyCounts:Find(data):get()>0
     evidence='bestiary:'..r[1]
    end
    if not eligible then return end
    local receipt=r[2]=='ShrineBossRewardCount'and 'QDCoopPersonal~story~stoneDuck'or'QDCoopPersonal~boss~'..r[2]..'~'..r[3]
    local item=LoadAsset(path('/Game/Items/',r[4]));assert(valid(item),'Reward asset unavailable '..r[4])
    -- Do not refill an owned item, a consumed zero-count slot, an earlier
    -- confirmed delivery, or a duck already handed to the shopkeeper.
    if not s.InventoryContents:Contains(item)and named(s,receipt)==0 and not(r[5]and named(s,r[5])>0)then
     helper=helper or StaticFindObject('/Game/Blueprints/SaveSystem/SaveFunctions.Default__SaveFunctions_C')
     ks=ks or StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')
     assert(valid(helper)and valid(ks),'Inventory helper unavailable')
     helper:AddItemToInventory(ks:Conv_ObjectToSoftObjectReference(item),1,player)
     assert(s.InventoryContents:Contains(item)and s.InventoryContents:Find(item):get()>0,'Inventory did not accept reward')
     grants=grants+1;log('BOSS LOAD RECOVERY delivered '..r[4]..' evidence='..evidence)
    end
    if named(s,receipt)==0 then s.NamedSaveData:Add(FName(receipt),1)end
    if r[2]=='GiantSwampFish_IsDead' then
     -- Native pickup index 0 means acquired; personal GUID must agree with
     -- compensation, including a retained zero-count inventory entry.
     s.SavableActorStates:Add({A=-1546420983,B=1277528438,C=-1596733035,D=1335765958},1)
    end
    -- The item is now accounted for. Keep native reward selection from
    -- handing out the same unique equipment in a later Boss conversation.
    if named(s,r[2])<r[3]then s.NamedSaveData:Add(FName(r[2]),r[3])end
   end)
   if not ok then pending=true;log('BOSS LOAD RECOVERY pending '..r[2]..': '..tostring(err))end
  end
  local effectOK,effectErr=pcall(effects.reconcile,game,player)
  if not effectOK then pending=true;log('REWARD EFFECTS pending '..tostring(effectErr))end
  log('BOSS LOAD RECOVERY checked granted='..grants..' retry='..tostring(pending))
  return not pending,grants
 end
 function R.poll(game,player,now)
  if now<nextPoll then return end;nextPoll=now+1
  if not valid(game)or not valid(player)then identity=nil;finished=false;return end
  local s=game.ActiveSaveSlot;if not valid(s)then return end
  local key=tostring(s:GetAddress())..':'..tostring(player:GetAddress())
  if key~=identity then identity=key;finished=false;readyAt=now+2 end
  if finished or now<readyAt or s.DoIntro or s.DoWakeOnBeach or player.IsDead then return end
  local d=player.DialogueManager;if valid(d)and d.RunningDialogue then return end
  finished=R.repair(game,player)
  if not finished then nextPoll=now+10 end
 end
 return R
end
