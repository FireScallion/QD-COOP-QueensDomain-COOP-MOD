-- One independent presentation controller per transport member. No local
-- input writes, gameplay hooks, capture loops, or duplicated enemy simulators.
return function(dir,C,valid,full,engine,primary)
 local S=dofile(dir..'smoothing.lua');local protocol=dofile(dir..'protocol.lua')
 local roomProtocol=dofile(dir..'room_protocol.lua');local M={peers={},count=0}
 local function destroy(p)
  if p.body then p.body.reset()end
  if valid(p.actor)then engine.destroy(p.actor)end;p.actor,p.mesh=nil,nil;p.pose=nil;p.sample=nil
  if engine.remove then engine.remove(p.id)end
 end
 local function joined(id,p)
  p.smooth=S.new();p.body=dofile(dir..'body_router.lua')(dir,valid,full,C)
  p.smooth.nativeBody=function(view,now)return p.body.usesNative(view,now,p.pose and p.pose.down)end
  p.body.native.shareResources(primary.native);M.peers[id]=p;M.count=M.count+1
 end
 local function left(id,p)destroy(p);M.peers[id]=nil;M.count=M.count-1 end
 local function update(id,p,frame,now)
  if not frame.T or not frame.M then return end
  if frame.P.world~=M.world then destroy(p);p.smooth:reset();p.world=frame.P.world;return end
  local f=frame.P;p.world=f.world
  if frame.view then frame.view.action=frame.A;frame.view.actionTime=frame.T.time;frame.view.body=frame.R;frame.view.bodyTime=frame.T.time end
  if not p.smooth:push(f,frame.T,frame.M,now,frame.B,frame.view)then return end
  p.body.observe(frame,now);p.pose={id=id,X=f.x,Y=f.y,Z=f.z,yaw=f.yaw,hp=f.hp,down=frame.downed,at=now};p.lastAt=now
 end
 M.room=roomProtocol.new(protocol.frame,joined,left,update)
 function M.accept(text,world,now)
  if M.world~=world then for _,p in pairs(M.peers)do destroy(p);p.smooth:reset();p.raw=nil end end
  M.world=world;return M.room.accept(text,now)
 end
 function M.present(now)
  for _,id in ipairs(M.room.order)do local p=M.peers[id]
   if p and p.pose and p.world==M.world then
    if now-p.lastAt>3 then destroy(p)
    else
     if not p.body.native.ready then p.body.native.shareResources(primary.native)end
     local pose=p.smooth:sample(now)
     if pose then
      if not valid(p.actor)then p.actor,p.mesh=engine.spawn(p.pose,id)end
      if valid(p.actor)and valid(p.mesh)then
       engine.position(p.actor,{X=pose.X,Y=pose.Y,Z=pose.Z-85},pose.yaw)
       local ok,err=pcall(p.body.apply,p.actor,p.mesh,pose,now,p.pose.down)
       if ok then p.sample=pose elseif engine.error then engine.error(id,err)end
      end
     end
    end
   end
  end
 end
 function M.reset()M.room.reset();M.world=nil end
 return M
end
