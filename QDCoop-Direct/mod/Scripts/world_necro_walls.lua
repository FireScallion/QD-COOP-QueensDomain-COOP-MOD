-- Head receipts are authoritative; manager counters are derived, not guest
-- absolute writes (two guests can otherwise overwrite each other's progress).
return function(valid,full,log)
 local M={}
 function M.head(a)return valid(a)and full(a):match('^NecroHead_BP_C ')~=nil end
 function M.manager(a)return valid(a)and full(a):match('^NecroWall_Manager_BP_C ')~=nil end
 local function value(save,a,index)
  if not valid(a)or #a.GUIDs<=index then return nil end
  local key=a.GUIDs[index+1]
  if save.SavableActorStates:Contains(key)then return save.SavableActorStates:Find(key):get()end
  return 0
 end
 function M.repair(manager,save)
  if not M.manager(manager)or not valid(save)or manager.Destroyed or (value(save,manager,0)or 0)>0 then return false end
  local count,total,origin=0,#manager.NecroHeads,nil
  if total==0 then return false end
  for i=1,total do
   local head=manager.NecroHeads[i]
   if not M.head(head)then return false end -- streamed-out references are not cleared heads
   if (value(save,head,0)or 0)>0 then count=count+1;origin=head end
  end
  local changed=(value(save,manager,1)or 0)~=count
  if changed then manager['Save Data Index to World Save'](manager,1,count)end
  if count==total then
   -- Call the original completion, including chained walls, collisions,
   -- activation targets, named progress, audio and the dissolve timeline.
   manager:DissolveNecroWall(origin)
   log('WORLD necro wall completed from '..count..' head receipts: '..full(manager))
   return true
  end
  return changed
 end
 function M.afterHead(head,save)
  local manager=head.ManagerToActivate
  return M.repair(manager,save)
 end
 local nextPoll=0
 function M.offline(game,player,now,gs)
  if now<nextPoll then return end;nextPoll=now+5
  if not valid(game)or not valid(player)or not valid(game.ActiveSaveSlot)then return end
  -- A coarse, class-specific query also covers old saves when the library is
  -- streamed in after loading elsewhere. No whole-object search or frame scan.
  local cls=StaticFindObject('/Game/RuinsLevel/Library/NecroWall/NecroWall_Manager_BP.NecroWall_Manager_BP_C')
  if not valid(cls)then return end
  local actors={};gs:GetAllActorsOfClass(game,cls,actors)
  for _,v in ipairs(actors)do M.repair(v:get(),game.ActiveSaveSlot)end
 end
 return M
end
