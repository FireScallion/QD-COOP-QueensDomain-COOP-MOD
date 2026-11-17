return function(dir,valid,W,log)
 local M={}
 local ghostIds=dofile(dir..'personal_ghost_guids.lua')
 local ghostClass
 local altarClass='/Game/Blueprints/SpectralSwordAltar/SpectralSwordAltar.SpectralSwordAltar_C'
 local knownAltars={}
 local altarType,scanDone
 local assets={}
 local helper,kismet
 local nextAfterDialogue=0
 local rune='/Game/Items/Accessories/RuneVisionAccessory/RuneVisionUnlock1.RuneVisionUnlock1'
 local merchantKey='/Game/Items/KeyItems/MerchantKeys/Merchant_Chest_Key_Item.Merchant_Chest_Key_Item'
 local spectral='/Game/Items/Weapons/SpectralSword/SpectralSword_Item.SpectralSword_Item'
 local merchantChest=W.guid('-1291424601,1252954286,2041190562,2128973861')
 local function count(map,key)
  return map:Contains(key) and map:Find(key):get() or 0
 end
 local function named(save,key)return count(save.NamedSaveData,FName(key))end
 local function setNamed(save,key,value)
  if named(save,key)~=value then save.NamedSaveData:Add(FName(key),value)end
 end
 local function item(path)
  if not valid(assets[path])then assets[path]=LoadAsset(path)end
  return assets[path]
 end
 local function grant(save,player,obj,description)
  if not valid(obj)then return false end
  if count(save.InventoryContents,obj)>0 then return true end
  if not valid(helper)then helper=StaticFindObject('/Game/Blueprints/SaveSystem/SaveFunctions.Default__SaveFunctions_C')end
  if not valid(kismet)then kismet=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')end
  if not valid(helper)or not valid(kismet)then return false end
  helper:AddItemToInventory(kismet:Conv_ObjectToSoftObjectReference(obj),1,player)
  if count(save.InventoryContents,obj)==0 then return false end
  log('WORLD restored personal reward '..description)
  return true
 end
 function M.personalGuid(key)return ghostIds[key]end
 function M.discoverGhost(actor)
  if not valid(ghostClass)then ghostClass=StaticFindObject('/Game/NPCs/NPC_Ghost_Base.NPC_Ghost_Base_C')end
  if not valid(ghostClass)or not actor:IsA(ghostClass)then return end
  local g=actor.GUID
  if not g or (g.A==0 and g.B==0 and g.C==0 and g.D==0)then return end
  local id=string.format('%d,%d,%d,%d',g.A,g.B,g.C,g.D)
  if ghostIds[id]then return end
  ghostIds[id]=true
  return id
 end
 function M.onActor(actor)
  if valid(altarType)and actor:IsA(altarType)then
   local path=actor:GetFullName():match(' (.+)$')
   if path then knownAltars[path]=false end
  end
 end
 function M.resetMap()
  knownAltars={}
  scanDone=false
  nextAfterDialogue=0
 end
 local function updateAltar(save,game,gs)
  if named(save,'SpectralSwordForged')<1 then return end
  local sword=item(spectral)
  if not valid(sword)then return end
  local owned=count(save.InventoryContents,sword)>0
  -- This weapon is unique and cannot be dropped. Correct an imported old
  -- host claim from possession, then use the native pickup on the altar.
  setNamed(save,'SpectralSwordAcquired',owned and 1 or 0)
  if not scanDone then
   altarType=StaticFindObject(altarClass)
   if not valid(altarType)then return end
   local out={}
   gs:GetAllActorsOfClass(game,altarType,out)
   for _,param in ipairs(out)do if valid(param:get())then M.onActor(param:get())end end
   scanDone=true
  end
  for id,prior in pairs(knownAltars)do
   local altar=StaticFindObject(id)
   if valid(altar)then
    local pickup=altar.SpectralSword
    if valid(pickup)and not pickup.Acquired then
     local state=owned and 'owned' or 'available'
     if prior~=state then
      pickup:SetActorHiddenInGame(owned)
      pickup:SetActorEnableCollision(not owned)
      knownAltars[id]=state
     end
    end
   else knownAltars[id]=nil end
  end
 end
 function M.ensure(game,player,gs,isClient)
  if not valid(player)or player.IsDead then return end
  local save=game.ActiveSaveSlot
  if not valid(save)then return end
  local dialogue=player.DialogueManager
  if not valid(dialogue)then return end
  local now=os.clock()
  if dialogue.RunningDialogue then nextAfterDialogue=now+3;return end
  if now<nextAfterDialogue then return end
  -- The dialogue completion marker was already personal before this change.
  -- It can repair a missed native handover without trusting the old counter.
  if named(save,'BMMCQuestDone')>0 then
   if grant(save,player,item(rune),'BMMC Rune Vision')then setNamed(save,'BMMC_RewardCount',1)end
  elseif named(save,'BMMC_RewardCount')>0 then
   local obj=item(rune)
   if valid(obj) and count(save.InventoryContents,obj)==0 then setNamed(save,'BMMC_RewardCount',0)end
  end
  if named(save,'Shop_BoughtALot_Acknowledged')>0 then
   local receipt='QDCoopPersonal~merchant~chest_key'
   if named(save,receipt)==0 then
    if count(save.SavableActorStates,merchantChest)>0 or grant(save,player,item(merchantKey),'merchant chest key')then
     setNamed(save,receipt,1)
     setNamed(save,'Umbada_Reward',1)
    end
   end
  elseif named(save,'Umbada_Reward')>0 then
   local obj=item(merchantKey)
   if valid(obj) and count(save.InventoryContents,obj)==0 then setNamed(save,'Umbada_Reward',0)end
  end
  if not isClient then return end
  -- Shared Boss claims are delivered by world_boss_rewards independently.
  updateAltar(save,game,gs)
 end
 return M
end
