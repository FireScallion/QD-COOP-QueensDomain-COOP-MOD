-- Recover the named library locks from the original, saved gargoyle receipts.
return function(valid,full,log)
 local M={}
 function M.isSwitch(a)
  return valid(a) and full(a):match('^Gargoyle_Switch_C ')~=nil
 end
 local function named(save,key)
  local name=FName(key)
  return save.NamedSaveData:Contains(name) and save.NamedSaveData:Find(name):get() or 0
 end
 function M.repair(a,save)
  if not M.isSwitch(a) or not valid(save) or #a.GUIDs<1 then return false end
  local id=a.GUIDs[1]
  if not save.SavableActorStates:Contains(id) or save.SavableActorStates:Find(id):get()~=1 then return false end
  if not valid(a.DoorRef) or not full(a.DoorRef):match('^Lib_FrontDoor_BP_C ') then return false end
  local index=a.SwitchIndex
  if index~=0 and index~=1 and index~=2 then return false end
  local key='LibDoorLock'..(index+1)
  local changed=named(save,key)<=0
  if changed then
   save.NamedSaveData:Add(FName(key),1)
   log('WORLD repaired library beacon '..key..' from '..full(a))
  end
  local count=0
  for i=1,3 do if named(save,'LibDoorLock'..i)>0 then count=count+1 end end
  if named(save,'LibraryDoorActivations')~=count then
   save.NamedSaveData:Add(FName('LibraryDoorActivations'),count)
   changed=true
  end
  if changed and valid(a.DoorRef) then a.DoorRef:RestoreStateFromSave() end
  return changed
 end
 local nextPoll=0
 function M.poll(game,player,now,gs)
  if now<nextPoll then return false end
  nextPoll=now+5
  if not valid(game) or not valid(player) or not valid(game.ActiveSaveSlot) then return false end
  local cls=StaticFindObject('/Game/Enemies/Gargler_00/Gargoyle_Switch.Gargoyle_Switch_C')
  if not valid(cls) then return false end
  local list={}
  gs:GetAllActorsOfClass(game,cls,list)
  local changed=false
  for _,v in ipairs(list) do if M.repair(v:get(),game.ActiveSaveSlot) then changed=true end end
  return changed
 end
 return M
end
