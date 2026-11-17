-- Room-scoped capability quorum. One local capture is reused for all peers.
-- A late join/map reload cannot inherit another member's pose acknowledgement.
return function(catalog,ready,enabled)
 local M={full=0,lite=0,peers={},members={}};local key
 function M.roster(room)
  if M.room~=room.session or M.revision~=room.revision then key=nil end
  if M.room~=room.session then M.peers={}end
  M.room,M.self,M.revision,M.members=room.session,room.self,room.revision,room.members
  for id in pairs(M.peers)do if M.members[id]==nil then M.peers[id]=nil end end
 end
 function M.receive(id,frame,now)
  if M.members[id]==nil or id==M.self or not frame.T then return end
  local k=frame.K;M.peers[id]={session=frame.T.session,at=now,cap=k and k.room==M.room and k.hash==catalog.hash and k.cap==1,ack=k and k.acks[M.self]}
 end
 function M.capture(session,action,down,now)
  local cap=ready()and 1 or 0;local b=action.body;local can=enabled()and cap==1 and b and b.ready and M.room~=nil
  local ids={};for id in pairs(M.members)do if id~=M.self then ids[#ids+1]=id end end;table.sort(ids);local acks={}
  if #ids==0 then can=false end
  for _,id in ipairs(ids)do local p=M.peers[id];local fresh=p and now>=p.at and now-p.at<.75
   if not(fresh and p.cap and p.ack==session)then can=false end
   if fresh then acks[#acks+1]=id..'@'..p.session end
  end
  local nextKey=can and(session..'|'..M.room..'|'..M.revision..'|'..table.concat(acks,',')..'|'..b.root..'|'..b.left..'|'..tostring(down or 0))or nil
  local lite=can and key==nextKey or false;key=nextKey
  if lite then M.lite=M.lite+1 else M.full=M.full+1 end
  return string.format('J|1|%s|%d|None|%d\nK|1|%s|%s|%d|%s',catalog.hash,cap,lite and 1 or 0,M.room or'None',catalog.hash,cap,table.concat(acks,',')),lite
 end
 function M.reset()M.peers={};M.members={};M.room=nil;M.revision=nil;key=nil end
 return M
end
