-- Personal delivery of shared, CONFIRMED native Boss dialogue rewards.
-- Catalog verified against native RewardList/ItemsToGrant on 2026-11-15.
-- A kill alone is not a claim: preserve the original dialogue order.
local dir=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
return function(valid,log)
 local effects=dofile(dir..'reward_effects.lua')(valid,log)
 local M={};local assets={};local helper,ks;local errors={};local afterDialogue=0
 local pendingAmulet=false
 local amulet='/Game/Items/Accessories/JosamiAmulet/JosamiAmulet.JosamiAmulet'
 local rewards={
  {'WhaleKingRewardCount',1,'/Game/Items/KeyItems/ShopProgressionKey/SilverDuckShopUnlockKey.SilverDuckShopUnlockKey','ShopkeepUnlock1'},
  {'WhaleKingSGRewardCount',1,'/Game/Items/KeyItems/TridentKeys/TridentKey_04_Data.TridentKey_04_Data'},
  {'WitchBonerRewardCount',1,'/Game/Items/KeyItems/PrisonKeys/Prison_key_2F_Item.Prison_key_2F_Item'},
  {'ROSDragonRewardCount',1,'/Game/Items/Consumables/MementoMirror/MementoMirror.MementoMirror'},
  {'FishwifeEvilRewardCount',1,'/Game/Items/Accessories/RuneVisionAccessory/RuneVisionUnlock4.RuneVisionUnlock4'},
  {'LargeRustyRobotRewardCount',1,'/Game/Items/KeyItems/ShopProgressionKey/MechDuckShopUnlock.MechDuckShopUnlock','ShopkeepUnlock3'},
  {'NecronomiconRewardCount',1,'/Game/Items/KeyItems/AcidVial/AcidVial.AcidVial'},
  {'NecronomiconRewardCount',2,'/Game/Items/KeyItems/ShopProgressionKey/GoldDuckShopUnlockKey.GoldDuckShopUnlockKey','ShopkeepUnlock2'},
  -- This native boss sets the flag when it offers its nut. Preserve the
  -- host's actual handover animation; the guest cannot use that local pickup.
  {'WhiteTreeGolemDead',1,'/Game/Items/Weapons/Daggers/BigNut/BigNut.BigNut',nil,true},
  -- Blood sisters call Pickup directly, without NPC_GiveNextReward.
  {'QDCoopBossClaim~JosamiAmulet',1,amulet}
 }
 local function named(s,k)local n=FName(k);return s.NamedSaveData:Contains(n)and s.NamedSaveData:Find(n):get()or 0 end
 local function count(s,o)return s.InventoryContents:Contains(o)and s.InventoryContents:Find(o):get()or 0 end
 local function deliver(s,p,r)
  if named(s,r[1])<r[2]then return end
  local receipt='QDCoopPersonal~boss~'..r[1]..'~'..r[2]
  -- Ducks are consumed by the merchant, whose unlock is personal. Old duck
  -- receipts alone must not strand a character whose actual hand-in is absent.
  local received=named(s,receipt)>0
  if r[4]and named(s,r[4])>0 then if not received then s.NamedSaveData:Add(FName(receipt),1)end;return end
  if not r[4]and received then return end
  local item=assets[r[3]]
  if not valid(item)then item=LoadAsset(r[3]);assets[r[3]]=item end
  assert(valid(item),'reward asset unavailable: '..r[3])
  if not s.InventoryContents:Contains(item)then
   if not valid(helper)then helper=StaticFindObject('/Game/Blueprints/SaveSystem/SaveFunctions.Default__SaveFunctions_C')end
   if not valid(ks)then ks=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')end
   assert(valid(helper)and valid(ks),'native inventory helper unavailable')
   helper:AddItemToInventory(ks:Conv_ObjectToSoftObjectReference(item),1,p)
   assert(count(s,item)>0,'native inventory did not accept '..r[3])
   log('WORLD Boss reward delivered '..r[1]..' stage='..r[2]..' item='..r[3])
  end
  if not received then effects.reconcile(FindFirstOf('FS_GameInstance_C'),p)end
  -- The receipt lives in the SAME save as the inventory. Do not write it
  -- before native delivery succeeds, or share it with another character.
  if not received then s.NamedSaveData:Add(FName(receipt),1)end
 end
 function M.recordAdded(soft,amount)
  if amount<=0 then return end
  if not valid(ks)then ks=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')end
  if valid(ks)and ks:Conv_SoftObjectReferenceToString(soft):ToString()==amulet then pendingAmulet=true end
 end
 function M.ensure(game,player,isClient)
  if not valid(game)or not valid(player)or player.IsDead then return end
  local s=game.ActiveSaveSlot;if not valid(s)then return end
  if not isClient and pendingAmulet then
   local obj=assets[amulet];if not valid(obj)then obj=LoadAsset(amulet);assets[amulet]=obj end
   if valid(obj)and count(s,obj)>0 then
    if named(s,'QDCoopBossClaim~JosamiAmulet')==0 then
     s.NamedSaveData:Add(FName('QDCoopBossClaim~JosamiAmulet'),1)
     game:GI_NotifyWorldStateChanged()
     log('WORLD Boss native handover confirmed JosamiAmulet')
    end
    pendingAmulet=false
   end
  end
  local now=os.clock();local d=player.DialogueManager
  if valid(d)and d.RunningDialogue then afterDialogue=now+3;return end
  if now<afterDialogue then return end
  for _,r in ipairs(rewards)do
   if not r[5]or isClient then
   local key=r[1]..':'..r[2];local ok,err=pcall(deliver,s,player,r)
   if ok then errors[key]=nil
   elseif not errors[key]or now-errors[key]>30 then
    errors[key]=now;log('WORLD Boss reward pending '..key..': '..tostring(err))
   end
   end
  end
 end
 function M.reset()afterDialogue=0;assets={};helper=nil;ks=nil;errors={};pendingAmulet=false end
 return M
end
