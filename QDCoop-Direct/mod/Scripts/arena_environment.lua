-- Fixed original scene objects. These samples never run native fight starts,
-- enemy spawns or timeline event tracks on the receiving machine.
local M={}
local function placed(map,name)
 return '/Game/RuinsLevel/Maps/'..map..'.'..map..':PersistentLevel.'..name
end
local profiles={
 {path=placed('780_SZ_Depths','Josami_Des_BloodPoolSpawner_2'),name='Josami_Des_BloodPoolSpawner_2',
  class='/Game/Enemies/JosamiKnight_00/DesBoss/Josami_Des_BloodPoolSpawner.Josami_Des_BloodPoolSpawner_C',
  moving='Dome',blocker='Dome_Collision',effects={'OverflowFX','RainFX'},guards={'Activate','BeginFight'}},
 {path=placed('600_Castle','BloodPool_EnemySpawner_2'),name='BloodPool_EnemySpawner_2',
  class='/Game/Enemies/BloodPoolDuo/BloodPool_EnemySpawner.BloodPool_EnemySpawner_C',
  moving='BloodPool',effects={},guards={'StartFight','ReceiveTick'}},
 {path=placed('900_SipehaWorld','Sipeha_Spawner'),name='Sipeha_Spawner',
  class='/Game/Enemies/Sipeha/Sipeha_Spawner.Sipeha_Spawner_C',moving='DoorParent',
  blocker='DoorBlocker',effects={'DoorParticles'},guards={}},
}
function M.decode(fields,W)
 if #fields~=12 then return end
 local id=W.integer(fields[2],1,#profiles)
 if not id then return end
 local v={}
 for i=3,5 do v[i-2]=W.number(fields[i],-1e7,1e7);if not v[i-2]then return end end
 for i=6,8 do v[i-2]=W.number(fields[i],-10000,10000);if not v[i-2]then return end end
 v.fade=W.number(fields[9],-1,10)
 local visible=W.integer(fields[10],0,1)
 local collision=W.integer(fields[11],0,1)
 local fx=W.integer(fields[12],0,(1<<#profiles[id].effects)-1)
 if not v.fade or not visible or not collision or not fx then return end
 v.visible=visible==1;v.collision=collision==1;v.fx=fx
 return id,v
end
function M.runtime(dir,valid,gs)
 local N=dofile(dir..'encounter_native.lua')(dir,valid)
 local R={}
 local active={}
 local names={}
 local fadeName=FName('FadeOut')
 for _,p in ipairs(profiles)do names[p.name]=p end
 local function actor(p)
  local a=StaticFindObject(p.path)
  if valid(a)and a:IsA(p.class)then return a end
 end
 local function fx(a,field)
  local o=a[field]
  local c=valid(o)and o.NiagaraComponent
  if valid(c)then return c end
 end
 function R.guestActor(a)
  local p=names[a:GetFName():ToString()]
  if not p or not a:IsA(p.class)then return end
  for _,fn in ipairs(p.guards)do N.guard(p.class..':'..fn)end
 end
 function R.capture(add)
  for id,p in ipairs(profiles)do
   local a=actor(p)
   local moving=valid(a)and a[p.moving]
   if valid(moving)then
    local loc,scale=moving:K2_GetActorLocation(),moving:GetActorScale3D()
    local collider=p.blocker and a[p.blocker]
    local shown=not moving.bHidden
    local fade=-1
    if id==1 then
     local mesh=moving.StaticMeshComponent
     shown=mesh:IsVisible()and shown
     local mat=mesh:GetMaterial(0)
     if valid(mat)and mat:IsA('/Script/Engine.MaterialInstanceDynamic')then fade=mat:K2_GetScalarParameterValue(fadeName)end
    end
    local bits=0
    for i,field in ipairs(p.effects)do
     local c=fx(a,field)
     if c and c:IsActive()then bits=bits|(1<<(i-1))end
    end
    add('A',id,string.format('%.3f|%.3f|%.3f|%.5f|%.5f|%.5f|%.4f',loc.X,loc.Y,loc.Z,scale.X,scale.Y,scale.Z,fade),
     shown and 1 or 0,valid(collider)and collider:GetActorEnableCollision()and 1 or 0,bits)
   end
  end
 end
 local function blend(state,t)
  local a,b=state.from,state.to
  local f=math.max(0,math.min(1,(t-state.at)/state.duration))
  local values={}
  for i=1,6 do values[i]=a[i]+(b[i]-a[i])*f end
  values.fade=b.fade<0 and -1 or(a.fade<0 and b.fade or a.fade+(b.fade-a.fade)*f)
  return values,f
 end
 local function same(a,b)
  if not a or a.fade~=b.fade or a.visible~=b.visible or a.collision~=b.collision or a.fx~=b.fx then return false end
  for i=1,6 do if a[i]~=b[i]then return false end end
  return true
 end
 function R.accept(rows,clock)
  for id in pairs(active)do if not rows[id]then active[id]=nil end end
  for id,to in pairs(rows)do
   local prior=active[id]
   if not prior then
    active[id]={from=to,to=to,at=clock,duration=.001,scanAt=0}
   elseif not same(prior.to,to)then
    active[id]={from=blend(prior,clock),to=to,at=clock,duration=math.max(.15,math.min(.65,clock-prior.at)),scanAt=0}
   end
  end
 end
 function R.tick(clock)
  for id,state in pairs(active)do
   if clock>=state.scanAt then
    local p=profiles[id]
    local a=actor(p)
    local moving=valid(a)and a[p.moving]
    if not valid(moving)then
     state.object=nil;state.scanAt=clock+.3
    else
     local collider=p.blocker and a[p.blocker]
     local v,f=blend(state,clock)
     -- An actor streamed in after the movement gets the current baseline.
     local address=moving:GetAddress()
     if state.object~=address then
      state.object=address
      state.fade=nil
      for _,fn in ipairs(p.guards)do N.guard(p.class..':'..fn)end
     end
     local loc,scale=moving:K2_GetActorLocation(),moving:GetActorScale3D()
     if math.abs(loc.X-v[1])+math.abs(loc.Y-v[2])+math.abs(loc.Z-v[3])>.02 then
      moving:K2_SetActorLocation({X=v[1],Y=v[2],Z=v[3]},false,{},true)
     end
     if math.abs(scale.X-v[4])+math.abs(scale.Y-v[5])+math.abs(scale.Z-v[6])>.0001 then
      moving:SetActorScale3D({X=v[4],Y=v[5],Z=v[6]})
     end
     local shown=state.to.visible or(f<1 and state.from.visible==true)
     if id==1 then
      local mesh=moving.StaticMeshComponent
      if mesh:IsVisible()~=shown then mesh:SetVisibility(shown,false)end
      if v.fade>=0 and state.fade~=v.fade then
       mesh:SetScalarParameterValueOnMaterials(fadeName,v.fade)
       state.fade=v.fade
      end
     end
     if moving.bHidden==shown then moving:SetActorHiddenInGame(not shown)end
     if valid(collider)and collider:GetActorEnableCollision()~=state.to.collision then collider:SetActorEnableCollision(state.to.collision)end
     for i,field in ipairs(p.effects)do
      local c=fx(a,field)
      local playing=(state.to.fx&(1<<(i-1)))~=0
      if c and c:IsActive()~=playing then if playing then c:Activate(false)else c:Deactivate()end end
     end
     if f==1 then state.scanAt=clock+.3 end
    end
   end
  end
 end
 function R.reset()
  active={}
  N.restore()
 end
 return R
end
return M
