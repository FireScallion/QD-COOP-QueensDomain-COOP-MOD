return function(valid,log,worldProtocol)
 local turnIns='RaiderNeckacesTurnedIn' -- Original spelling in Raider_TurnInNecklace.
 local completed='GaveRaiderCaptainNecklaces'
 local keyReceipt='QDCoopPersonal~raider~key'
 local necklacePath='/Game/Items/KeyItems/RaiderNecklaceKey/RaiderNecklace.RaiderNecklace'
 local finePath='/Game/Items/Accessories/RaidersFineNecklace/RaidersFineNecklace.RaidersFineNecklace'
 local keyPath='/Game/Items/KeyItems/RaidersKey/RaidersKey_Item.RaidersKey_Item'
 local talkPath='/Game/NPCs/Raider/Raider_Dialogue_00.Raider_Dialogue_00'
 local rewardTalkPath='/Game/NPCs/Raider/Raider_GiveReward_Dialogue_00.Raider_GiveReward_Dialogue_00'
 -- Placed pickups in 100_GR, 200_AQ and 210_AQ_underground. World sync
 -- already preserves these four acquisition flags per character.
 local necklacePickups={
  '-434081760,1157379197,-111805776,688105455',
  '1428293653,1299548456,-1827607404,1887470207',
  '-1294286527,1262725422,-1655822965,1563568804',
  '-1560990982,1276812181,-26079078,-566537090'
 }
 local chests={
  '-1253637519,1108050512,-979715159,-340830499',
  '-1706795218,1133031367,918382238,-911778596'
 }
 local assets={}
 local helper,kismet,recoverySave
 local settleUntil=0
 local function handle(path)
  if not valid(assets[path])then assets[path]=LoadAsset(path)end
  return assets[path]
 end
 local function count(map,key)
  return map:Contains(key)and map:Find(key):get()or 0
 end
 local function named(save,key)return count(save.NamedSaveData,FName(key))end
 local function grant(save,player,item)
  if not valid(helper)then helper=StaticFindObject('/Game/Blueprints/SaveSystem/SaveFunctions.Default__SaveFunctions_C')end
  if not valid(kismet)then kismet=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')end
  if not valid(helper)or not valid(kismet)then return false end
  helper:AddItemToInventory(kismet:Conv_ObjectToSoftObjectReference(item),1,player)
  return count(save.InventoryContents,item)>0
 end
 local function retiredKey(save)
  for _,id in ipairs(chests)do
   if count(save.SavableActorStates,worldProtocol.guid(id))>0 then return true end
  end
  return false
 end
 return function(save,player)
  if not valid(save)or not valid(player)or player.IsDead then return end
  local dialogue=player.DialogueManager
  if not valid(dialogue)then return end
  local running=dialogue.RunningDialogue
  if named(save,completed)>0 then
   if running then settleUntil=os.clock()+3;return end
   if os.clock()<settleUntil then return end
   -- Native QuestStateFixup lists these two items for this completion flag.
   -- Verify them once the handover has finished; the native montage can be
   -- interrupted before its item notify. A used key must never be reissued.
   local fine=handle(finePath)
   if valid(fine)and count(save.InventoryContents,fine)==0 and grant(save,player,fine)then
    log('WORLD recovered completed Raider quest necklace')
   end
   if named(save,keyReceipt)==0 then
    local key=handle(keyPath)
    if not valid(key)then return end
    if count(save.InventoryContents,key)>0 or retiredKey(save)then
     save.NamedSaveData:Add(FName(keyReceipt),1)
    elseif grant(save,player,key)then
     save.NamedSaveData:Add(FName(keyReceipt),1)
     log('WORLD recovered completed Raider quest key')
    end
   end
   return
  end
  if running and recoverySave~=save:GetAddress()then return end
  for _,id in ipairs(necklacePickups)do
   if count(save.SavableActorStates,worldProtocol.guid(id))~=1 then return end
  end
  local necklace=handle(necklacePath)
  if not valid(necklace)then return end
  local held=count(save.InventoryContents,necklace)
  if held>4 then return end
  -- An old save may have already paid all four and lost the cumulative
  -- count. Arm recovery outside dialogue so we do not race the normal
  -- turn-in action, then resume the native reward dialogue on the next talk.
  if held==0 then
   if not running then recoverySave=save:GetAddress();return end
   local current=dialogue.CurrentDialogue
   if not valid(current)or current:GetFullName()~='FS_DialogueData '..talkPath then return end
   local rewardTalk=handle(rewardTalkPath)
   if not valid(rewardTalk)then return end
   dialogue:JumpToDialogue(rewardTalk,false)
   current=dialogue.CurrentDialogue
   if valid(current)and current:GetAddress()==rewardTalk:GetAddress()then
    save.NamedSaveData:Add(FName(turnIns),4)
    recoverySave=nil
    log('WORLD resumed Raider reward dialogue from four recorded personal pickups')
   end
   return
  end
  if running then return end
  if recoverySave==save:GetAddress()then recoverySave=nil end
  local paid=4-held
  if paid~=named(save,turnIns)then
   save.NamedSaveData:Add(FName(turnIns),paid)
   log('WORLD reconciled personal Raider turn-ins to '..paid)
  end
 end
end
