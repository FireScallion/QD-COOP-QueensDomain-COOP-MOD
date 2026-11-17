-- Membership and routing only. Native healing, inventory receipts and the
-- hold-to-interact clock remain in rescue.lua on the local game thread.
return function(C,write)
 local M={peers={}}
 function M.update(world,now)
  local seen={}
  for id,p in pairs(C.RoomPeers or{})do
   seen[id]=true;local f=p.frame;local old=M.peers[id]
   if f and f.T and f.P.world==world and now-(p.at or 0)<=8 then
    if not old or old.epoch~=f.T.session then old={id=id,epoch=f.T.session};M.peers[id]=old end
    old.position=f.P;old.down=f.downed or 0;old.ready=true;old.at=p.at
   elseif old then old.ready=false end
  end
  for id in pairs(M.peers)do if not seen[id]then M.peers[id]=nil end end
 end
 function M.source(fields)
  local id=fields[1]:match('^(%x+)%-');local p=M.peers[id]
  return p and p.ready and p.epoch==fields[4]and p or nil
 end
 function M.identities()
  local result={};local count={}
  for _,p in pairs(M.peers)do if p.ready and p.identity then count[p.identity]=(count[p.identity]or 0)+1 end end
  for id,n in pairs(count)do if n==1 then result[id]=true end end
  return result
 end
 function M.find(identity)
  local result
  for _,p in pairs(M.peers)do if p.ready and p.identity==identity then if result then return end;result=p end end
  return result
 end
 function M.send(context,p,op,target,attempt,value)
  if not p or not p.ready then return end
  local prefix=C.Role=='client'and C.Room and p.id==C.Room.host and''or('TO|'..p.id..'|')
  write('out.events',prefix..table.concat({'RV',context.world,context.epoch,p.epoch,op,target,attempt,value or'-'},'|')..'\n',true)
 end
 function M.pick(locked,allowed)
  if locked then local p=M.peers[locked];return p and p.ready and p or nil end
  local best,score
  for _,p in pairs(M.peers)do if p.ready and p.identity and p.life and p.life~='-'and p.lifeDown==p.down and p.down>0 then
   local ok,distance=allowed(p)
   if ok and(not score or distance<score or distance==score and p.id<best.id)then best,score=p,distance end
  end end
  return best
 end
 function M.allDown()
  if not C.Room or not C.Room.members then return end
  local result,count={},0
  for id in pairs(C.Room.members)do if id~=C.Room.self then
   local p=M.peers[id];if not p or not p.ready or p.down<=0 then return end
   result[id]={epoch=p.epoch,down=p.down};count=count+1
  end end
  return count>0 and result or nil
 end
 function M.sameDown(snapshot)
  local current=M.allDown();if not current then return false end
  for id,p in pairs(current)do local old=snapshot[id];if not old or old.epoch~=p.epoch or old.down~=p.down then return false end end
  for id in pairs(snapshot)do if not current[id]then return false end end
  return true
 end
 function M.reset()M.peers={}end
 return M
end
