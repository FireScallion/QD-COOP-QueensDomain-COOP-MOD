return function(C)
 local M={}
 function M.refresh(s)
  s.members=s.members or{}
  local members=C.Room and C.Room.members or{}
  for id in pairs(s.members)do if members[id]==nil then s.members[id]=nil end end
  for id in pairs(members)do if id~=C.Room.self then
   local p=C.RoomPeers and C.RoomPeers[id];local epoch=p and p.frame and p.frame.T.session
   local old=s.members[id]
   if not old or old.epoch~=epoch then s.members[id]={epoch=epoch}end
  end end
  local ready,done,acked=true,true,true
  for _,p in pairs(s.members)do ready=ready and p.ready==true;done=done and p.done==true;acked=acked and p.acked==true end
  s.ready,s.peerDone,s.acked=ready,done,acked
 end
 function M.mark(s,event,key)
  M.refresh(s);local id=event:match('^(%x+)%-');local p=s.members[id]
  if not p or not p.epoch then return false end
  p[key]=true;M.refresh(s);return true
 end
 return M
end
