-- Wire identity chooses the recipient; durable identity recovers a pending
-- award after reconnect. Neither is inferred from the copied character alone.
return function(C)
 local M={peers={}}
 function M.refresh(frame,world,now)
  local current=C.RoomProtocol==2 and C.RoomPeers or{peer={frame=frame,at=now}}
  local seen={}
  for id,p in pairs(current or{})do
   seen[id]=true;local f=p.frame;local old=M.peers[id]
   if f and f.P.world==world then
    if not old or old.epoch~=f.T.session then old={};M.peers[id]=old end
    old.epoch=f.T.session;old.position=f.P;old.at=p.at or now
   elseif old then old.position=nil end
  end
  for id in pairs(M.peers)do if not seen[id]then M.peers[id]=nil end end
 end
 function M.source(f)
  local id=C.RoomProtocol==2 and f[1]:match('^(%x+)%-')or'peer'
  return M.peers[id],id
 end
 function M.host()return C.RoomProtocol==2 and C.Room and C.Room.host or'peer'end
 function M.hasReady()for _,p in pairs(M.peers)do if p.identity and p.position then return true end end;return false end
 function M.winner(who,localId,character)
  local found,count=nil,0
  if who==localId or who==character then found='local';count=1 end
  for id,p in pairs(M.peers)do if p.identity==who or p.character==who then found=id;count=count+1 end end
  -- An old ambiguous award stays pending, never pays multiple copied saves.
  if count==1 then return found end
 end
 function M.reset()M.peers={}end
 return M
end
