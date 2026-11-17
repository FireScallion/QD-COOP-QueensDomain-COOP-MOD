-- Native scene corpse and attached personal treasure are separate from combat.
return function(valid,log,gs)
 local M={};local nextPoll=0;local applied;local observedAlive=false
 local base='/Game/Enemies/Fisher_00/Fisher24/Fisher_02/GiantSwampFish/'
 local prefix='QDCoopGiantFishSpot~'
 local function named(s,k)local n=FName(k);return s.NamedSaveData:Contains(n)and s.NamedSaveData:Find(n):get()or 0 end
 function M.poll(game,player,guest)
  if os.clock()<nextPoll then return end;nextPoll=os.clock()+1
  if not valid(game)or not valid(player)or not valid(game.ActiveSaveSlot)then return end
  local save=game.ActiveSaveSlot
  if named(save,'GiantSwampFish_IsDead')<1 then applied=nil;observedAlive=true;return end
  local cls=StaticFindObject(base..'GiantFish_Spawner_BP.GiantFish_Spawner_BP_C');if not valid(cls)then return end
  local all={};gs:GetAllActorsOfClass(game,cls,all)
  for _,v in ipairs(all)do local sp=v:get()
   if valid(sp)and #sp.EmergeSpots>0 and valid(sp.ObjectInMouth)then
    local chosen;local index=named(save,'GiantSwampFish_DeathSpot')
    for i=1,#sp.EmergeSpots do local a=sp.EmergeSpots[i]
     if valid(a)and named(save,prefix..a:GetFName():ToString())==1 then chosen=a;break end
    end
    if not guest and not chosen then
     local enemy=sp.CurrentManagedEnemy
     if valid(enemy)and valid(enemy.CurrentAttackSpot)then chosen=enemy.CurrentAttackSpot end
     if not chosen then for i=1,#sp.EmergeSpots do local a=sp.EmergeSpots[i];if valid(a)and a.Index==index then chosen=a;break end end end
     if chosen then save.NamedSaveData:Add(FName(prefix..chosen:GetFName():ToString()),1);game:GI_NotifyWorldStateChanged()end
    end
    if chosen then
     local key=tostring(save:GetAddress())..':'..tostring(chosen:GetAddress())
     local remap=not guest and chosen.Index~=index
     if remap then index=chosen.Index;save.NamedSaveData:Add(FName('GiantSwampFish_DeathSpot'),index);game:GI_NotifyWorldStateChanged()end
     if (guest or remap)and applied~=key then
      -- Enumeration indices need not match between machines. Invoke Init with
      -- a temporary index, retaining the original actor order for later play.
      for i=1,#sp.EmergeSpots do local a=sp.EmergeSpots[i]
       if valid(a)and valid(a.ObjectInMouth)then local old=a.Index;a.Index=a:GetAddress()==chosen:GetAddress()and index or -1;a:Init();a.Index=old end
      end
      if guest and observedAlive then chosen:DoDeathSequence()end
      local children={};sp.ObjectInMouth:GetAttachedActors(children,true)
      for _,child in ipairs(children)do local a=child:get()
       if valid(a)and a:IsA('/Game/Items/KeyItems/JigekiKeys/JIgeki_Key_2_BP.JIgeki_Key_2_BP_C')then a.MySaveData:Empty();a:RestoreFromSave()end
      end
      log('WORLD giant serf corpse restored '..chosen:GetFName():ToString())
      applied=key;observedAlive=false
     end
    end
   end
  end
 end
 function M.reset()applied=nil;nextPoll=0;observedAlive=false end
 return M
end
