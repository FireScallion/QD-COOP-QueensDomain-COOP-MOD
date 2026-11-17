return function(dir,C,rawValid,full,read,write,log,audio)
 local P=dofile(dir..'enemy_protocol.lua');local Q=dofile(dir..'pose_math.lua');local Timeline=dofile(dir..'enemy_timeline.lua');local cat=P.catalog
 local M={actors={},byActor={},replicas={},frozen={},serial=0,hits=0,applied=0,poses=0,unknown={},received=0};local ids,meshes={},{};for i,v in ipairs(cat.classes)do ids[v]=i end;for i,v in ipairs(cat.meshes)do meshes[v]=i end
 local originals={}
 M.classPaths=cat.classes
 function M.isBodyMesh(path)return meshes[path]~=nil end
 M.timeline=Timeline.new();M.suppressed={}
 local ks=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary');local gs=StaticFindObject('/Script/Engine.Default__GameplayStatics')
 local function safe(fn)local ok,v=pcall(fn);if ok then return v end end
 -- Lua UObject wrappers do not own the engine object. Resolve retained handles
 -- again before dereferencing them after a streamed level has been collected.
 local refs=C.ObjectRefs;local findObject=refs.find
 local scope=dofile(dir..'object_scope.lua')(rawValid,full,refs.validation);local valid=scope.valid;full=scope.full
 local Validation=dofile(dir..'weak_validation.lua')(dir,C.NativePresentation~=false,C.InlineWeakValidation~=false)
 local Known=dofile(dir..'enemy_known.lua')(dir,C,rawValid)
 local function loadAsset(path)local a=findObject(path);if valid(a)then return a end;scope.clear();a=LoadAsset(path);scope.clear();return a end
 local Native=dofile(dir..'enemy_animation.lua')(dir,valid,full,scope.clear)
 local AnimVisibility=dofile(dir..'enemy_anim_visibility.lua')(C,valid)
 local Capture=dofile(dir..'enemy_capture.lua')(dir,C.NativeEnemyCapture~=false,valid)
 local SourcePose=dofile(dir..'enemy_source_pose.lua')(valid)
 local Fog=dofile(dir..'enemy_fog.lua')(valid)
 local Quiescence=dofile(dir..'enemy_quiescence.lua')(valid)
 local function asset(o)return valid(o)and full(o):match(' (/[^ ]+)$')end
 local function hasFurniture(cid)return cat.classes[cid]:find('/Game/Enemies/Poltergeist/',1,true)~=nil end
 local function distance(a,b)return (a.X-b.X)^2+(a.Y-b.Y)^2+(a.Z-b.Z)^2 end
 local function transform(t)return Q.transform({t[1],t[2],t[3]},{t[4],t[5],t[6],t[7]},{t[8],t[9],t[10]})end
 local function appendTransform(snapshot,t)
  local p,q,s=t.Translation,t.Rotation,t.Scale3D
  local i=#snapshot
  snapshot[i+1],snapshot[i+2],snapshot[i+3]=p.X,p.Y,p.Z
  snapshot[i+4],snapshot[i+5],snapshot[i+6],snapshot[i+7]=q.X,q.Y,q.Z,q.W
  snapshot[i+8],snapshot[i+9],snapshot[i+10]=s.X,s.Y,s.Z
 end
 local function vec(v)return {X=v.X,Y=v.Y,Z=v.Z}end
 local function emit(s,recipient)local prefix=C.RoomProtocol==2 and recipient and('TO|'..recipient..'|')or'';write('out.events',prefix..'NPC|'..M.world..'|'..M.session..'|'..s..'\n',true)end
 local threat=dofile(dir..'threat_runtime.lua')(dir,C,valid,full,write,log,function()return M.actors end,function()return M.byActor end,function(source)return M.recordFor(source)end)
 local health=dofile(dir..'enemy_healthbar.lua')(C,valid,full,function(e)return M.byActor[full(e)]end)
 local HealthOrder=dofile(dir..'enemy_health_order.lua')
 local boss=dofile(dir..'boss_healthbar.lua')(C,M,valid,full,emit)
 local function bossUI(fn,...)
  local ok,err=pcall(fn,...)
  if not ok then
   local now=os.clock();if not boss.errorAt or now-boss.errorAt>5 then boss.errorAt=now;write('boss-ui-error.txt',tostring(err));log('Boss HUD: '..tostring(err))end
  end
 end
 local rewards=dofile(dir..'enemy_rewards.lua')(dir,C,M,valid,full,write,log)
 Native.capture=C.Perf.measure(Native.capture,'enemy.animCapture');Native.apply=C.Perf.measure(Native.apply,'enemy.animApply')
 rewards.event=C.Perf.measure(rewards.event,'enemy.reward')
 local Cadence=dofile(dir..'enemy_cadence.lua')
 local rest
 local Lifecycle=dofile(dir..'boss_lifecycle.lua')(dir,C,M,valid,full,write,log);M.lifecycle=Lifecycle
 local detail=dofile(dir..'enemy_present_profile.lua')(C.Perf)
 local Schedule=dofile(dir..'enemy_present_schedule.lua')
 local Place=dofile(dir..'enemy_placement.lua')(dir,C.NativeEnemyPlacement~=false)
 local function urgent(r)if r and not r.queued then r.queued=true;r.forceAnim=true;M.urgent=M.urgent or{};M.urgent[#M.urgent+1]=r end end
 local function refreeze(key)
  M.refreeze=M.refreeze or{};M.refreeze[key]=true
 end
 local function installOriginalVisibility()
  if M.originalVisibilityHook then return end
  -- Register once. UE4SS defers native unregistration, so a permanent empty
  -- fast path is safer across room changes than replacing the native hook.
  RegisterHook('/Script/Engine.Actor:SetActorHiddenInGame',function(ctx,hidden)
   if not M.connected or C.Role~='client'or not next(originals)or hidden:get()then return end
   local e=ctx:get()
   if not rawValid(e)then return end
   local record=originals[e:GetAddress()]
   if not record then return end
   local alive=refs.validation.checkToken(record.weak)
   if alive==false or(alive==nil and full(e)~=record.name)then return end
   hidden:set(true)
   refreeze(record.name)
  end)
  M.originalVisibilityHook=true
 end
 function M.install(hooks)
  M.sessionHooks=hooks
  threat.install(hooks);health.install(hooks);boss.install(hooks);rewards.install(hooks)
  rest=rest or dofile(dir..'enemy_rest.lua')(C,M,valid,full,gs,write,log,health)
  rest.install(hooks)
  if C.Role=='client'then
   installOriginalVisibility()
   local respawn='/Game/Enemies/EnemyBase.EnemyBase_C:Respawn'
   local x,y=RegisterHook(respawn,function(ctx)
    if not M.connected then return end
    local key=full(ctx:get())
    if M.frozen[key]and not M.byActor[key]then
     refreeze(key)
    end
   end);hooks[#hooks+1]={respawn,x,y}
   local path='/Game/Enemies/EnemyBase.EnemyBase_C:Update Fog'
   local a,b=RegisterHook(path,function(ctx)
    if M.connected then Fog.apply(M.byActor[full(ctx:get())])end
   end);hooks[#hooks+1]={path,a,b}
  end
  if C.Role=='host'then for _,name in ipairs({'Montage_Play','Montage_Stop'})do
   local path='/Script/Engine.AnimInstance:'..name
   local a,b=RegisterHook(path,function()end,function(ctx)
    if C.Role=='host'and M.connected then local ai=ctx:get();if valid(ai)then local owner=ai:GetOwningActor();if valid(owner)then urgent(M.byActor[full(owner)])end end end
   end);hooks[#hooks+1]={path,a,b}
  end end
 end
 function M.uninstall()threat.uninstall();M.whaleWakeHook=nil;M.sessionHooks=nil;if rest then rest.installed=false end end
 -- Revisit only when a later route has a larger remaining depth budget.
 -- Owner/instigator graphs can converge or cycle; a depth cap alone repeats work.
 local function recordFor(o,depth,seen)
  depth=depth or 0;if depth>12 or not valid(o)then return end
  local address=o:GetAddress();if seen[address]and seen[address]<=depth then return end;seen[address]=depth
  local r=M.byActor[full(o)];if r then return r end
  if C.Role=='client'and M.frozen[full(o)]then return {e=o,id=0}end
  if o:IsA('/Script/Engine.AnimInstance')then return recordFor(o:GetOwningActor(),depth+1,seen)end
  if o:IsA('/Game/Enemies/Shared/Actions/EnemyAction_Base.EnemyAction_Base_C')then return recordFor(o.EnemyRef,depth+1,seen)end
  local owner=safe(function()return o:GetOwner()end);if valid(owner)and full(owner)~=full(o)then r=recordFor(owner,depth+1,seen);if r then return r end end
  local inst=safe(function()return o:GetInstigator()end);if valid(inst)and full(inst)~=full(o)then return recordFor(inst,depth+1,seen)end
 end
 M.recordFor=scope.wrap(function(o,depth)return recordFor(o,depth,{})end)
 function M.isCosmetic(o,depth)
  if not valid(o)or(depth or 0)>12 then return false end
  local key=full(o);local r=M.byActor[key]
  if r and valid(r.visual)and full(r.visual)==key then return true end
  if o:IsA('/Script/Engine.AnimInstance')then return M.isCosmetic(o:GetOwningActor(),(depth or 0)+1)end
  local owner=safe(function()return o:GetOwner()end)
  return valid(owner)and full(owner)~=key and M.isCosmetic(owner,(depth or 0)+1)or false
 end
 function M.suppressFx(c)
  if C.Role~='client'or not valid(c)then return end
  local key=full(c);if not M.suppressed[key]then M.suppressed[key]={c=c,visible=c:IsVisible(),hidden=c.bHiddenInGame,tick=c:IsComponentTickEnabled()}end
  c:SetVisibility(false,false);c:SetHiddenInGame(true,false);c:SetComponentTickEnabled(false)
 end
 local function hideNativeFx(e)
  local replica=M.byActor[full(e)]
  for _,v in ipairs(e:K2_GetComponentsByClass(findObject('/Script/Engine.SceneComponent')))do local c=v:get()
   if valid(c)and full(c)~=full(e.Mesh)and not(replica and valid(replica.pose)and full(c)==full(replica.pose))and(c:IsA('/Script/Niagara.NiagaraComponent')or c:IsA('/Script/Engine.ParticleSystemComponent')or c:IsA('/Script/Engine.StaticMeshComponent')or c:IsA('/Script/Engine.SkeletalMeshComponent'))then M.suppressFx(c)end
  end
 end
 function M.visualSources()return M.activeVisuals end
 -- Every registered enemy gets one discovery pass, even outside interest.
 -- Interest still limits recurrent discovery, never roster membership.
 function M.initialVisualSource()
  local q=M.initialVisualQueue;if not q then return end
  while M.initialVisualCursor<=#q do local r=q[M.initialVisualCursor];M.initialVisualCursor=M.initialVisualCursor+1;if M.actors[r.id]==r and not r.retired then return r end end
  M.initialVisualQueue=nil;M.initialVisualCursor=nil
 end
 function M.presentation(id)return M.replicas[id]end
 function M.requireAnimatedBones(id,consumer)return AnimVisibility.pin(M.replicas[id],consumer)end
 function M.releaseAnimatedBones(owner,consumer)AnimVisibility.release(owner,consumer)end
 local function freeze(e,again,replica)
  local key=full(e);if M.frozen[key]and not again then return end;hideNativeFx(e)
  local controller=e:GetController();local move=e.CharacterMovement
  if C.Role=='client'and M.sessionHooks and not M.whaleWakeHook and e:IsA('/Game/Enemies/WhaleKing/Whaleking_Boss_BP.Whaleking_Boss_BP_C')then
   local path='/Game/Enemies/WhaleKing/Whaleking_Boss_BP.Whaleking_Boss_BP_C:DoIntro'
   local a,b=RegisterHook(path,function(ctx)
    local key=full(ctx:get())
    if M.connected and M.frozen[key]and not M.byActor[key]then refreeze(key)end
   end)
   M.sessionHooks[#M.sessionHooks+1]={path,a,b};M.whaleWakeHook=true
  end
  if not M.frozen[key]then
  M.frozen[key]={e=e,tick=e:IsActorTickEnabled(),dilation=e.CustomTimeDilation,controller=controller,move=move,mesh=e.Mesh,hp=e.HP,hidden=e.bHidden,collision=e:GetActorEnableCollision()}
  if not replica then
   local record=M.frozen[key]
   record.name=key;record.weak=refs.captureFresh(e);record.address=e:GetAddress()
   originals[record.address]=record
  end
  M.frozen[key].quiet=Quiescence.pause(e)
  local audioComponents={}
  for _,entry in ipairs(e:K2_GetComponentsByClass(findObject('/Script/Engine.AudioComponent')))do
   local c=entry:get();if valid(c)then audioComponents[#audioComponents+1]={c=c,paused=c.bIsPaused};c:SetPaused(true)end
  end
  M.frozen[key].audio=audioComponents
  end
  e:SetActorHiddenInGame(true);e:SetActorEnableCollision(false)
  e:SetActorTickEnabled(false);e.CustomTimeDilation=0
  if valid(move)then move:StopMovementImmediately();move:SetComponentTickEnabled(false)end
  if valid(controller)then controller:StopMovement();controller:SetActorTickEnabled(false);local brain=safe(function()return controller.BrainComponent end);if valid(brain)then brain:StopLogic('QDCoop host authority')end end
  e.Mesh:SetComponentTickEnabled(false)
 end
 local function candidates()
  local out,loaded={},{};gs:GetAllActorsOfClass(M.player,findObject('/Game/Enemies/EnemyBase.EnemyBase_C'),loaded)
  for _,v in ipairs(loaded)do local e=v:get();if valid(e)and not e:IsActorBeingDestroyed()and safe(function()return e.Mesh:GetNumBones()>0 end)then out[#out+1]=e end end;return out
 end
 local function display(r,f,t)
  Native.release(r)
  scope.clear();local visual=gs:BeginDeferredActorSpawnFromClass(M.player,findObject('/Script/Engine.SkeletalMeshActor'),t,1,nil);gs:FinishSpawningActor(visual,t);visual:SetActorEnableCollision(false)
  local native=f[24]==0
  local source=r.e.Mesh
  local owned=native and Native.catalog.profiles[f[29]].ownedBody and Native.ensure(f[29])
  -- Native-to-pose fallback must release the former display mesh's ticking.
  -- Otherwise it remains a hidden, independently animated collision body.
  if r.ownedBody and not owned then source:SetComponentTickEnabled(false);r.e.CustomTimeDilation=0 end
  r.ownedBody=owned==true
  -- A pose fallback uses its added PoseableMesh, not the empty default mesh.
  if not native then local blank=visual:GetComponentByClass(findObject('/Script/Engine.SkeletalMeshComponent'));if valid(blank)and not valid(blank.SkeletalMesh)then blank:SetComponentTickEnabled(false)end end
  local pose=owned and source or native and visual:GetComponentByClass(findObject('/Script/Engine.SkeletalMeshComponent'))or visual:AddComponentByClass(findObject('/Script/Engine.PoseableMeshComponent'),false,Q.transform({0,0,0},{0,0,0,1}),false)
  assert(valid(pose),'Enemy display component');if owned then r.e.CustomTimeDilation=1 else pose:SetSkeletalMesh(loadAsset(cat.meshes[f[7]]),true);pose:SetCollisionEnabled(0)end;pose:SetComponentTickEnabled(true);pose:SetOnlyOwnerSee(false);pose:SetOwnerNoSee(false);pose:SetHiddenInGame(false,false)
  -- Slimer's translucent material participates in Custom Depth in the
  -- original actor. Its hidden gameplay mesh can no longer write that pass.
  if cat.classes[f[6]]:find('/Game/Enemies/Slime_00/',1,true) and source.bRenderCustomDepth then
   pose:SetCustomDepthStencilValue(source.CustomDepthStencilValue)
   pose:SetRenderCustomDepth(true)
  end
  for i=0,source:GetNumMaterials()-1 do pose:SetMaterial(i,source:GetMaterial(i))end
  if not owned then source:SetVisibility(false,false)else source:SetVisibility(true,false)end;r.names={};for i=0,pose:GetNumBones()-1 do r.names[i+1]=pose:GetBoneName(i)end
  r.visual=visual;r.visualVisible=nil;r.pose=pose;r.native=native;r.meshPlacement=nil;r.poseCache={};r.animFrame=nil
  if r.furniture then visual:SetActorHiddenInGame(true);r.visualVisible=false end
  Fog.apply(r)
  M.byActor[full(visual)]=r
  if native then Native.setup(r,f[29]);AnimVisibility.setup(r)end
 end
 local function newReplica(f)
  -- Never borrow a level spawner's actor: it may recycle or destroy it independently.
  local pos={X=f[10],Y=f[11],Z=f[12]};local t=Q.transform({pos.X,pos.Y,pos.Z},{0,0,0,1})
  scope.clear();local e=gs:BeginDeferredActorSpawnFromClass(M.player,loadAsset(cat.classes[f[6]]),t,1,nil);assert(valid(e),'Enemy spawn failed')
  -- WhaleKing destroys ordinary spawner-less actors during BeginPlay. Its
  -- native bestiary path keeps a standalone body without creating an arena.
  local whale=e:IsA('/Game/Enemies/WhaleKing/Whaleking_Boss_BP.Whaleking_Boss_BP_C')
  if whale then e.BestiaryInstance=true end
  gs:FinishSpawningActor(e,t)
  freeze(e,false,true)
  if whale then
   e:SetUpHurtboxes()
   -- Its damage override rejects disabled-AI actors with no OwningSpawner
   -- before reaching EnemyBase's network hit hook. Tick, movement, controller
   -- and perception remain quiescent; this flag only admits the hit path.
   e.bIsAIDisabled=false
  end
  local r={e=e,id=f[4],cid=f[6],mid=f[7],frames={},hp=f[8],fog=f.fog,poseUpdates=0,furniture=hasFurniture(f[6])};display(r,f,t);M.replicas[f[4]]=r;M.byActor[full(e)]=r;return r
 end
 newReplica=C.Perf.measure(newReplica,'enemy.spawn')
 function M.damage(e,amount)
  if C.Role=='host'then M.effective=M.effective or{};M.effective[full(e)]=tonumber(amount)or 0;urgent(M.byActor[full(e)])end
  local r=M.byActor[full(e)]or M.frozen[full(e)];if C.Role=='client'and r and not M.replay then e.HP=math.max(1,r.hp);return true end
 end
 function M.hit(e,amount,token,applier,damage)
  if not M.connected then return false end;local r=M.byActor[full(e)];if not r then return C.Role=='client'and M.frozen[full(e)]~=nil end
  if C.Role=='host'then
   local localHit=full(applier)~=''and full(applier)==full(gs:GetPlayerPawn(e,0));local guestHit=threat.isGuest(applier)
   write('threat-last-hit.txt','source='..full(applier)..' local='..tostring(localHit)..' guest='..tostring(guestHit)..' effective='..tostring(M.effective and M.effective[full(e)])..'\n')
   if localHit or guestHit then threat.record(r,guestHit and threat.guestId(applier)or'host',M.effective and M.effective[full(e)]or 0);audio.commitHit(e,0,false)end
   if M.effective then M.effective[full(e)]=nil end;return true
  end
  if full(applier)==''or full(applier)~=full(gs:GetPlayerPawn(e,0))then return true end
  if not amount or amount<=0 or amount>10000 or r.hp<=0 then return true end
  local _,encoded=threat.capture(damage);if not encoded then return true end
  M.hitPending=M.hitPending or{};local sent=os.clock();for k,v in pairs(M.hitPending)do if sent-v.at>30 then M.hitPending[k]=nil end end
  M.hitPending[token]={id=r.id,at=sent}
  audio.commitHit(e,token,true);emit('H|'..r.id..'|'..token..'|'..encoded);M.hits=M.hits+1;return true
 end
 function M.event(f,world,peer,remotePos)
  if C.Role=='client'and f[2]=='NPC'and f[3]==world and f[4]==peer and f[5]=='F'and(#f==8 or #f==9)then
   local id,token,hp=tonumber(f[6]),tonumber(f[7]),tonumber(f[8]);local p=M.hitPending and M.hitPending[token]
   if p and p.id==id and hp and hp==hp then
    M.hitPending[token]=nil;local ms=math.max(0,os.clock()-p.at)*1000
    local r=M.replicas[id]
    if r and valid(r.e)and HealthOrder.confirm(r,hp,tonumber(f[9]))then
     r.e.HP=hp;health.update(r,hp);bossUI(boss.health)
    end
    M.hitFeedbackCount=(M.hitFeedbackCount or 0)+1;M.hitFeedbackSum=(M.hitFeedbackSum or 0)+ms;M.hitFeedbackMax=math.max(M.hitFeedbackMax or 0,ms)
    write('attack-feedback-status.txt',string.format('confirmed=%d lastRoundTripMs=%.1f meanRoundTripMs=%.1f maxRoundTripMs=%.1f enemy=%d hostHP=%.3f\n',M.hitFeedbackCount,ms,M.hitFeedbackSum/M.hitFeedbackCount,M.hitFeedbackMax,id,hp))
   end
   return
  end
  if f[2]=='BI'then return Lifecycle.event(f,world,peer,remotePos)end
  if f[2]=='NPC'and f[3]==world and f[4]==peer and f[5]=='B'then return boss.event(f)end
  local reward=rewards.event(f,world,peer);if f[2]=='ER'then return reward end
  if rest then rest.event(f,world,peer)end
  threat.event(f,world,peer,M.replicas)
  if f[2]~='NPC'or f[3]~=world or f[4]~=peer or C.Role~='host'or f[5]~='H'or #f~=11 then return end
  local id,token=tonumber(f[6]),tonumber(f[7]);local d=threat.decode(f[8],f[9],f[10],f[11]);local amount=d and d.amount;local r=id and M.actors[id]
  if not r or not valid(r.e)or not remotePos or not amount or amount~=amount or amount<=0 or amount>10000 or not token or token%1~=0 or token<1 or token>1e7 or r.e.HP<=0 or distance(r.e:K2_GetActorLocation(),remotePos)>8000^2 then return end
  local guestId=C.RoomProtocol==2 and f[1]:match('^(%x+)%-')or'client';local guest=threat.guest(guestId)
  if not guest or not valid(guest.proxy)or not guest.alive or guest.session~=peer then return end
  local key=peer..':'..token;M.seen=M.seen or{};if M.seen[key]then return end;M.seen[key]=true;M.seenOrder=M.seenOrder or{};M.seenOrder[#M.seenOrder+1]=key;if #M.seenOrder>512 then M.seen[table.remove(M.seenOrder,1)]=nil end
  local beforeHP=r.e.HP;local beforeThreat=(r.threatTotals or{})[guestId]or 0;audio.beginReplay(token,guestId);local ok,err=pcall(function()r.e:TryApplyDamage({},threat.build(d),guest.proxy,{},r.e:K2_GetActorLocation(),true)end);audio.endReplay();if not ok then error(err)end;M.applied=M.applied+1
  if ((r.threatTotals or{})[guestId]or 0)==beforeThreat then threat.record(r,guestId,math.max(0,beforeHP-r.e.HP))end
  urgent(r);emit('F|'..id..'|'..token..'|'..tostring(math.max(0,r.e.HP))..'|'..string.format('%.6f',gs:GetRealTimeSeconds(r.e)),C.RoomProtocol==2 and guestId or nil)
 end
 function M.reset(travel)
  M.refreeze=nil;originals={}
  Native.reset()
  Lifecycle.reset()
  AnimVisibility.reset()
  Known.reset()
  SourcePose.reset();Capture.reset()
  rewards.reset()
  health.reset()
  boss.reset()
  threat.reset(travel);M.hitPending={};M.hitFeedbackCount=0;M.hitFeedbackSum=0;M.hitFeedbackMax=0;M.effective={};M.captureQueue=nil;M.urgent={};M.planIndex=1;M.pendingFrames={};M.rejectBefore=nil;M.roster=nil;M.rosterAt=nil;M.rosterRaw=nil;M.nextRoster=0
  if rest then rest.reset(travel)end
  if not travel then for _,s in pairs(M.suppressed)do if valid(s.c)then s.c:SetVisibility(s.visible,false);s.c:SetHiddenInGame(s.hidden,false);s.c:SetComponentTickEnabled(s.tick)end end end
  M.suppressed={};M.selected={};M.activeVisuals={};M.timeline:reset();M.sampleTime=nil
  if not travel then for _,r in pairs(M.replicas)do if valid(r.visual)then M.byActor[full(r.visual)]=nil;scope.clear();r.visual:K2_DestroyActor();scope.clear()end;if valid(r.e)then M.frozen[full(r.e)]=nil;scope.clear();r.e:K2_DestroyActor();scope.clear()end end
   for key,s in pairs(M.frozen)do if valid(s.e)then for _,a in ipairs(s.audio or{})do if valid(a.c)then a.c:SetPaused(a.paused)end end;local r=M.byActor[key];if r and r.hp<=0 then s.e:SetActorHiddenInGame(true);s.e:SetActorEnableCollision(false);s.e.HP=0 else Quiescence.restore(s.quiet);s.e.CustomTimeDilation=s.dilation;s.e:SetActorHiddenInGame(s.hidden);s.e:SetActorEnableCollision(s.collision);s.e:SetActorTickEnabled(s.tick);if valid(s.mesh)then s.mesh:SetComponentTickEnabled(true)end;if valid(s.move)then s.move:SetComponentTickEnabled(true)end;if valid(s.controller)then s.controller:SetActorTickEnabled(true);local b=safe(function()return s.controller.BrainComponent end);if valid(b)then b:RestartLogic()end end end end end
  end
  M.initialVisualQueue=nil;M.initialVisualCursor=nil;M.actors={};M.byActor={};M.replicas={};M.presentDue=nil;M.frozen={};M.candidates={};M.scanQueue=nil;M.scanIndex=1;M.nextScan=0;M.nextSend=0;M.nextCaptureWork=0;M.nextSelect=0;M.nextReceive=0;M.raw=nil;M.lastLines={};M.peer=nil;M.seen={};M.seenOrder={};M.connected=false;write('out.enemy','')
 end
 function M.update(player,world,session,now,connected,peerSession,peerPosition)
  M.player=player;M.peer=peerSession;M.peerPosition=peerPosition;M.world=world;M.session=session;M.connected=connected;if not connected then return end
  -- Native Respawn re-enables hidden local actors, even though their meshes
  -- remain frozen. Run after the native call, retaining original restore state.
  if M.refreeze then local pending=M.refreeze;M.refreeze=nil
   for key in pairs(pending)do local s=M.frozen[key];if s and not M.byActor[key]and valid(s.e)then freeze(s.e,true)end end
  end
  Lifecycle.poll(now)
  bossUI(boss.tick,now)
  if rest then rest.update(now)end
  local own
  -- Enumerate once, inspect a bounded slice. Reflected per-actor lookups must
  -- not all land on the same half-second tick.
  if not M.scanQueue and now>=(M.nextScan or 0)then
   Known.prune(M.byActor,M.frozen)
   M.nextScan=now+.5;M.scanQueue={};M.scanIndex=1
   gs:GetAllActorsOfClass(player,findObject('/Game/Enemies/EnemyBase.EnemyBase_C'),M.scanQueue)
  end
  if M.scanQueue then
   local at=os.clock();own=vec(player:K2_GetActorLocation())
   for i=1,8 do
    local v=M.scanQueue[M.scanIndex];if not v then M.scanQueue=nil;break end;M.scanIndex=M.scanIndex+1;local e=v:get()
    local known,record=Known.known(e,C.Role,M.byActor,M.frozen)
    if known and C.Role=='client'then
     -- Direct native field changes can bypass a Blueprint function hook.
     -- Recheck only existing originals during the budgeted discovery pass.
     if record.name and not e.bHidden then freeze(e,true)end
    elseif not known and valid(e)and not e:IsActorBeingDestroyed()then
     if C.Role=='host'then
      local name=full(e)
      if not M.byActor[name]and not e.bSpawnerPreviewInstance and not e.BestiaryInstance and(e.HP>0 or Lifecycle.managed({e=e}))then
       local cid=ids[asset(e:GetClass())];local mid=meshes[asset(e.Mesh.SkeletalMesh)];local pos=e:K2_GetActorLocation()
       if cid and mid and Cadence.pointDistance(pos.X,pos.Y,pos.Z,own,peerPosition,C.RoomProtocol==2 and C.RoomPeers or nil,world)<7000^2 then M.serial=M.serial+1;local r={e=e,id=M.serial,cid=cid,mid=mid,name=name,furniture=hasFurniture(cid)};M.actors[r.id]=r;M.byActor[name]=r;M.initialVisualQueue=M.initialVisualQueue or{};M.initialVisualCursor=M.initialVisualCursor or 1;M.initialVisualQueue[#M.initialVisualQueue+1]=r end
      end
      Known.mark(e,name,M.byActor[name],'host')
     else
      local name=full(e);local frozen=M.frozen[name]
      if frozen and frozen.name and(refs.validation.checkToken(frozen.weak)==false or frozen.address~=e:GetAddress())then
       if originals[frozen.address]==frozen then originals[frozen.address]=nil end
       M.frozen[name]=nil;frozen=nil
      end
      if frozen and frozen.name and not e.bHidden then freeze(e,true)else freeze(e)end
      Known.mark(e,name,M.frozen[name],'client')
     end
    end
    if os.clock()-at>=.0005 then break end
   end
  end
  threat.update(player,world,session,now,connected,peerSession,peerPosition)
  if C.Role=='host'then
   M.playerPosition=own or vec(player:K2_GetActorLocation())
   if now>=(M.nextSelect or 0)then M.nextSelect=now+.2;local list={}
   for id,r in pairs(M.actors)do if(r.ended and now-r.ended>10)or(r.deadSince and now-r.deadSince>10)then SourcePose.release(r);Capture.forget(r);r.retired=true;M.actors[id]=nil;if r.name then M.byActor[r.name]=nil end else list[#list+1]=r end end;table.sort(list,function(a,b)return (a.distance or 0)<(b.distance or 0) end)
    -- Preserve membership for every nearby enemy. Pose detail is budgeted
    -- separately, so scheduling an enemy less often never hides it.
    M.selected=list;M.activeVisuals={};for _,r in ipairs(list)do if r.syncActive~=false then M.activeVisuals[#M.activeVisuals+1]=r end end
   end
   local due=M.captureQueue or{}
   if M.urgent and #M.urgent>0 then for _,r in ipairs(M.urgent)do r.captureAt=0;for i,v in ipairs(due)do if v==r then table.remove(due,i);break end end;table.insert(due,1,r)end;M.urgent={}end
   local function encode(r)local s=P.encode(r.last);if #s<=6900 then r.encoded=s else r.encoded=nil;M.unknown['oversize '..cat.classes[r.cid]]=true end end
   if #due==0 then
    local list=M.selected or{};M.planIndex=M.planIndex or 1
    local planning=os.clock()
    for i=1,24 do
     if M.planIndex>#list then M.planIndex=1;break end
     local r=list[M.planIndex];M.planIndex=M.planIndex+1;local f=r.last
     if f then
      -- Plain snapshot coordinates are safe to inspect without dereferencing an
      -- Unreal object. Approaching either player wakes an idle record promptly.
      r.distance=Cadence.distance(f,M.playerPosition,peerPosition,C.RoomProtocol==2 and C.RoomPeers or nil,world)
      local idle=Cadence.idle(r.distance)
      if idle<(r.interval or 0)then r.captureAt=math.min(r.captureAt or now,f[5]+idle)end
     end
     if r.ended then
      -- A terminal actor keeps its encoded tombstone during the existing grace
      -- period. Never spend another capture slot on the destroyed UObject.
     elseif f and now<(r.captureAt or 0)then
      -- Unchanged distant records need no reflected property calls this frame.
     elseif not r.retired then
      -- The snapshot validates the actor and reads its live state when this
      -- entry is processed, including entries left over from earlier frames.
      due[#due+1]=r
     elseif f and not r.ended then f[5]=now;f[9]=2;r.ended=now;encode(r)end
     if os.clock()-planning>=.0005 then break end
    end
   end
   M.captureQueue=due
   local started=os.clock();local captured,taken=0,0
   -- Bone reads are native calls. Spread them across game frames instead of
   -- sampling 32 full skeletons in one 20 Hz burst. Wire cadence stays at 20 Hz.
   for _,r in ipairs(due)do local e=r.e;local f=r.last;taken=taken+1;r.queued=false
    local state=not r.retired and not r.ended and Capture.capture(r)
    if not r.retired and not r.ended and state~=false and(state or(valid(e)and not e:IsActorBeingDestroyed()))then
     local mesh=state and r.stateCaptureMesh or e.Mesh
     local hp,attacking,recovery,chasing
     if state then hp,attacking,recovery,chasing=state[2],state[3]==1,state[4]==1,state[5]==1
     else hp,attacking,recovery,chasing=e.HP,e.bIsAttacking,e.bInRecoveryTime,e.bIsChasing end
     r.interval=(hp<=0 and .1)or((attacking or recovery or chasing or(r.speed or 0)>10)and .05)or Cadence.idle(r.distance)
     -- Damage and montage hooks interrupt an idle record immediately. Keep its
     -- next observation prompt too, so movement following the action is caught.
     if r.forceAnim then r.interval=.05 end
     -- Motion needs a higher cadence than native animation graph controls.
     -- Reuse controls between full captures; montage time still advances locally.
     if not r.animAt or now>=r.animAt or r.forceAnim then
      r.sourceFog=Fog.capture(e)
      if Lifecycle.managed(r)then
       local mid=meshes[asset(mesh.SkeletalMesh)]
       if mid and mid~=r.mid then r.mid=mid;r.disableNative=nil;r.captureProfile=nil;r.names=nil end
      end
      r.cachedAnim=Native.capture(r,mesh);r.animSampleAt=now;r.animAt=now+.12;r.forceAnim=nil
     end
     local anim=r.cachedAnim
     local n=anim and 0 or mesh:GetNumBones()
     if n>=0 and n<=140 and SourcePose.ready(r,mesh,n>0,now)then
     local vx,vy,vz,x,y,z,pitch,yaw,roll
     if state then vx,vy,vz=state[14],state[15],state[16];x,y,z=state[8],state[9],state[10];pitch,yaw,roll=state[11],state[12],state[13]
     else local v=e:GetVelocity();vx,vy,vz=v.X,v.Y,v.Z;local p=e:K2_GetActorLocation();x,y,z=p.X,p.Y,p.Z;local q=e:K2_GetActorRotation();pitch,yaw,roll=q.Pitch,q.Yaw,q.Roll end
     r.speed=math.sqrt(vx^2+vy^2+vz^2);r.captureAt=now+(r.interval or .05)
     if not r.names or #r.names~=n then r.names={};for b=0,n-1 do r.names[b+1]=mesh:GetBoneName(b)end end
     local p=M.playerPosition;local peer=peerPosition
     r.distance=Cadence.pointDistance(x,y,z,p,peer,C.RoomProtocol==2 and C.RoomPeers or nil,world)
     r.deadSince=hp<=0 and not Lifecycle.managed(r)and(r.deadSince or now)or nil
     -- Double buffer: preserve the last complete frame if a reflected call fails.
     -- Only encoded strings leave the record. Clear changing bone/anim layouts.
     f=r.captureScratch or{};for j=#f,1,-1 do f[j]=nil end
     f[1],f[2],f[3],f[4],f[5],f[6],f[7],f[8]='N',session,world,r.id,now,r.cid,r.mid,math.max(0,hp)
     local hidden=(state and(state[6]==1 or state[7]==0))or(not state and(e.bHidden or not mesh:IsVisible()))
     if r.furniture then
      -- The invisible driver supplies the hurtbox. The static body is sent
      -- by the regular enemy attachments path with its material and offset.
      local furniture=e.StaticMesh
      hidden=e.bHidden or not valid(furniture)or not furniture:IsVisible()or furniture.bHiddenInGame
     end
     f[9]=hidden and 2 or(hp<=0 and 1 or 0)
     f[10],f[11],f[12],f[13]=x,y,z,yaw
     if state then for j=17,26 do f[#f+1]=state[j]end else appendTransform(f,mesh:K2_GetComponentToWorld())end;f[#f+1]=n
     -- GetSocketTransform uses ERelativeTransformSpace (Component = 2), unlike
     -- PoseableMesh bone setters which use EBoneSpaces (ComponentSpace = 1).
     for b=1,n do appendTransform(f,mesh:GetSocketTransform(r.names[b],2))end
     SourcePose.sampled(r,r.syncActive~=false or(r.distance or math.huge)<3500^2)
     f[#f+1]=vx;f[#f+1]=vy;f[#f+1]=vz;f[#f+1]=(attacking and 1 or 0)+(recovery and 2 or 0)
     if anim then for j,v in ipairs(anim)do if j==4 and anim[2]>0 then v=Native.advance(anim[2],v,now-r.animSampleAt,anim[5])end;f[#f+1]=v end end
     f[#f+1]=pitch;f[#f+1]=roll;Fog.append(r,f);Lifecycle.capture(r,f);r.captureScratch=r.last;r.last=f;encode(r);captured=captured+1 end
    elseif not r.ended then
     -- The actor may disappear before its first snapshot too. Such a record
     -- must retire normally instead of being retried forever without a frame.
     r.ended=now;if f then f[5]=now;f[9]=2;encode(r)end
    end
    if captured>=8 or os.clock()-started>=.0015 then break end
   end
   for i=1,taken do table.remove(due,1)end
   if now>=(M.nextRoster or 0)then
    M.nextRoster=now+.5;local live={};for id,r in pairs(M.actors)do if not r.retired and not r.ended then live[#live+1]=id end end;table.sort(live)
    write('out.roster',table.concat({'QDER1',session,world,string.format('%.6f',now),table.concat(live,',')},'|')..'\nEND\n')
   end
   if now>=(M.nextSend or 0)then
    M.nextSend=now+.05
    local sendList={};for _,r in ipairs(M.selected or{})do if r.encoded then sendList[#sendList+1]=r end end
    table.sort(sendList,function(a,b)return (a.sentAt or 0)<(b.sentAt or 0)end)
    local lines={};for i=1,math.min(64,#sendList)do local r=sendList[i];lines[#lines+1]=r.encoded;r.sentAt=now end
    write('out.enemy',table.concat(lines,'\n')..'\n')
   end
  elseif C.Role=='client'then
   local roster=read('in.roster')
   if roster~=M.rosterRaw then
    M.rosterRaw=roster;local rs,rw,at,ids=roster:match('^QDER1|([^|]+)|([^|]+)|([^|]+)|([^\n]*)\nEND\n$');at=tonumber(at)
    if rs==peerSession and rw==world and at and at>(M.rosterAt or 0)then
     local live={};for id in ids:gmatch('%d+')do live[tonumber(id)]=true end;M.roster=live;M.rosterAt=at
     for id,r in pairs(M.replicas)do if not live[id]and(r.sourceTime or 0)<=at then rest.retire(r);M.replicas[id]=nil;M.timeline.tracks[id]=nil end end
     for id,f in pairs(M.pendingFrames or{})do if not live[id]and f[5]<=at then M.pendingFrames[id]=nil end end
    end
   end
   M.pendingFrames=M.pendingFrames or{}
   if now>=(M.nextReceive or 0)then
    M.nextReceive=now+1/30
    local raw=read('in.enemy')
    if raw~=M.raw then
     M.raw=raw;local lines={}
     for line in raw:gmatch('[^\n]+')do
      lines[line]=true
      if not(M.lastLines and M.lastLines[line])then
       local f=P.parse(line)
       if f and f[3]==world and f[2]==peerSession and f[5]>=(M.rejectBefore or 0)and not(M.roster and f[5]<=(M.rosterAt or 0)and not M.roster[f[4]])then
        local prev=M.pendingFrames[f[4]]
        if not prev or f[5]>prev[5]then M.pendingFrames[f[4]]=f end
       end
      end
     end
     M.lastLines=lines
    end
   end
   local due={};local p=own or vec(player:K2_GetActorLocation())
   for _,f in pairs(M.pendingFrames)do due[#due+1]=f end
   table.sort(due,function(a,b)return (a[10]-p.X)^2+(a[11]-p.Y)^2+(a[12]-p.Z)^2 < (b[10]-p.X)^2+(b[11]-p.Y)^2+(b[12]-p.Z)^2 end)
   local created=0;local started=os.clock()
   for _,f in ipairs(due)do
    local r=M.replicas[f[4]]
    if r and f[9]==2 then rest.retire(r);M.replicas[f[4]]=nil;r=nil end
    if r and(not valid(r.e)or r.e:IsActorBeingDestroyed())and not r.dead then
     if valid(r.visual)then M.byActor[full(r.visual)]=nil;scope.clear();r.visual:K2_DestroyActor();scope.clear()end
     M.byActor[full(r.e)]=nil;M.replicas[f[4]]=nil;r=nil
    end
    if r and r.dead and f[8]>0 and(not r.healthAt or f[5]>=r.healthAt)then
     if valid(r.visual)then M.byActor[full(r.visual)]=nil;scope.clear();r.visual:K2_DestroyActor();scope.clear()end
     if valid(r.e)then M.byActor[full(r.e)]=nil;M.frozen[full(r.e)]=nil;scope.clear();r.e:K2_DestroyActor();scope.clear()end
     M.replicas[f[4]]=nil;r=nil
    end
    if not r and(f[9]==2 or(f[8]<=0 and not f.life))then M.pendingFrames[f[4]]=nil
    elseif r or created<2 then
     if not r then r=newReplica(f);created=created+1 end
     r.fog=f.fog;Fog.apply(r)
     M.pendingFrames[f[4]]=nil
     -- Death has handed presentation to the native corpse. Late animation-mode
     -- or mesh changes must not spawn a new, unanimated cosmetic body.
     if not r.dead and(r.native~=(f[24]==0)or r.mid~=f[7])then if valid(r.visual)then M.byActor[full(r.visual)]=nil;scope.clear();r.visual:K2_DestroyActor();scope.clear()end;r.mid=f[7];display(r,f,r.e:GetTransform())
     elseif not r.dead and r.native and r.nativeId~=f[29]then
      local owned=Native.catalog.profiles[f[29]].ownedBody==true
      if r.ownedBody~=owned then
       if valid(r.visual)then M.byActor[full(r.visual)]=nil;scope.clear();r.visual:K2_DestroyActor();scope.clear()end
       display(r,f,r.e:GetTransform())
      else Native.setup(r,f[29]);AnimVisibility.setup(r)end
     end
     if M.timeline:push(f,now)then
      Schedule.wake(r,f,now)
      local hp,freshHealth=HealthOrder.snapshot(r,f[8],f[5]);local hpChanged=r.hp~=hp
      r.hp=hp;r.at=now;r.sourceTime=f[5];M.received=M.received+1
      if valid(r.e)then
       r.e.HP=hp;Lifecycle.apply(r,f)
       if hpChanged or(hp<=0 and not r.dead)then health.update(r,hp);bossUI(boss.health)end
       if freshHealth and f[8]<=0 and not r.dead and not Lifecycle.managed(r)then
        r.dead=true;r.e.CustomTimeDilation=1;r.e:SetActorHiddenInGame(false);r.e:SetActorTickEnabled(true)
        if valid(r.visual)then r.visual:SetActorHiddenInGame(true)end
        r.pose:SetVisibility(false,false);r.pose:SetComponentTickEnabled(false);r.e.Mesh:SetVisibility(true,false);r.e.Mesh:SetComponentTickEnabled(true)
        audio.beginReplicaDeath(r.e);M.replay=true
        -- Bestiary and independent native loot rolls arrive through reliable
        -- reward events, including the host's actual variant/drop overrides.
        local ok,err=pcall(function()
         if r.e:IsA('/Game/Enemies/Fisher_00/Fisher24/Fisher_02/GiantSwampFish/GiantFish_Enemy_BP.GiantFish_Enemy_BP_C')then
          -- Its original Kill needs a level-owned emergence spot. The shared
          -- world result owns that corpse and treasure, not this proxy.
          r.e:SetActorHiddenInGame(true);r.e:SetActorEnableCollision(false);r.e:SetActorTickEnabled(false)
         else rewards.prepareReplicaDeath(r.e);r.e:Kill(true,true)end
        end)
        M.replay=false;audio.endReplicaDeath();if not ok then error(err)end
       end
      end
     end
    end
    if os.clock()-started>.002 then break end
   end
  end
 end

 function M.apply(now)
  if C.Role~='client'or not M.connected then return end
  detail.begin();AnimVisibility.frame(M.player,M.replicas,now);local time=M.timeline:clock(now);M.sampleTime=time
  local ordered=M.presentDue or {};M.presentDue=ordered
  local own=vec(M.player:K2_GetActorLocation())
  local roster=Schedule.prepare(M.replicas,ordered,own,now);detail.queue(ordered,now)
  detail.phase('prepare');local poseStarted=os.clock()
  for _,r in ipairs(ordered)do if os.clock()-poseStarted-detail.overhead()>=.002 then detail.deferred();break end;detail.actor(r)
   -- Missing samples are pure timeline work; do not first validate several
   -- engine objects just to discover there is nothing to present.
   local sample=M.timeline:sample(r.id,time,now);detail.phase('timeline');local a=sample and sample.a
   if not a then
    -- Preserve the existing no-sample hide/collision transition. Once hidden,
    -- repeated empty observations require no further engine calls.
    if r.visualVisible~=false and valid(r.visual)then r.visual:SetActorHiddenInGame(true);r.visualVisible=false end
    if (r.visible~=false or r.collision~=false)and valid(r.e)then r.e:SetActorHiddenInGame(true);r.e:SetActorEnableCollision(false);r.visible=false;r.collision=false end
    Schedule.wait(r,now);M.presentNoSample=(M.presentNoSample or 0)+1
   else
   local alive=valid(r.e)and valid(r.pose);detail.phase('validate')
   if not alive then Schedule.wait(r,now);M.presentInvalid=(M.presentInvalid or 0)+1
   else local visible=a[9]~=2
   -- This cosmetic actor is created and shown/hidden here. Recreated visuals
   -- clear the flag; death and retirement take the record out of presentation.
   local displayVisible=visible and not r.furniture
   if r.visualVisible~=displayVisible and valid(r.visual)then
    if r.visual.bHidden==displayVisible then r.visual:SetActorHiddenInGame(not displayVisible)end
    r.visualVisible=displayVisible
   end
   local collision=visible and(r.hp>0 or r.encounterInteractive);if r.visible~=visible or r.e.bHidden==visible then r.e:SetActorHiddenInGame(not visible);r.visible=visible end;if r.collision~=collision then r.e:SetActorEnableCollision(collision);r.collision=collision end
   detail.phase('visibility');if not visible then Schedule.wait(r,now)else
   local b,t=sample.b,sample.u;r.kind=sample.kind
   local d=(sample.x-own.X)^2+(sample.y-own.Y)^2+(sample.z-own.Z)^2
   local moving=a.vx*a.vx+a.vy*a.vy+a.vz*a.vz>100 or a.action~=0
   detail.classify(d,moving);detail.phase('schedule');local interval=(d<1800^2 or(moving and d<3500^2))and 0 or((moving or d<3500^2)and 1/30 or 1/10)
   -- Nearby motion follows every available engine frame, within the existing
   -- fair 2 ms work budget. Preserve cadence phase further away: now+1/30 can
   -- accidentally become 20 Hz when a frame lands just short of the deadline.
   r.nextPresent=math.max((r.nextPresent or now)+interval,now)
   local last=r.placement
   local changed=not last or math.abs(sample.x-last[1])>.001 or math.abs(sample.y-last[2])>.001
    or math.abs(sample.z-last[3])>.001 or math.abs(sample.yaw-last[4])>.001
    or math.abs(sample.pitch-last[5])>.001 or math.abs(sample.roll-last[6])>.001
   if changed then
    local placement={sample.x,sample.y,sample.z,sample.yaw,sample.pitch,sample.roll}
    if not Place.actor(r.e,placement)then r.e:K2_SetActorLocationAndRotation({X=sample.x,Y=sample.y,Z=sample.z},{Pitch=sample.pitch,Yaw=sample.yaw,Roll=sample.roll},false,{},true)end
    r.placement=placement
   end
   detail.phase('actorTransform');local meshChanged=not r.meshPlacement
   if r.meshPlacement then for i=1,10 do if math.abs(sample.mesh[i]-r.meshPlacement[i])>.0001 then meshChanged=true;break end end end
   if meshChanged then if not Place.mesh(r.pose,sample.mesh)then r.pose:K2_SetWorldTransform(transform(sample.mesh),false,{},true)end;r.meshPlacement=sample.mesh end
   detail.phase('meshTransform');if r.native then AnimVisibility.apply(r,a,d,sample);Native.apply(r,a,sample.time,b,t);detail.phase('native')
   elseif os.clock()-poseStarted-detail.overhead()<.002 and now>=(r.nextPose or 0)and not(r.lastPoseA==a and r.lastPoseB==b and r.lastPoseU==t)then local d=distance(r.e:K2_GetActorLocation(),own);r.nextPose=now+(d<1800^2 and 1/60 or d<3500^2 and 1/20 or 1/8)
    for j=1,math.min(a[24],#r.names)do local value=Q.blendTransform(a.bones[j],b.bones[j],t);local old=r.poseCache[j];local changed=not old;if old then for k=1,10 do if math.abs(old[k]-value[k])>1e-6 then changed=true;break end end end
     if changed then r.pose:SetBoneTransformByName(r.names[j],transform(value),1);r.poseCache[j]=value end
    end;detail.phase('fallback');r.poseUpdates=r.poseUpdates+1;r.lastPoseA=a;r.lastPoseB=b;r.lastPoseU=t
   end
   M.poses=M.poses+1;detail.presented(r,now);r.lastPresented=now
   end
   end
  end;detail.endActor() end
  detail.finish(roster)
 end
 function M.status()threat.status();local n,r=0,0;local rows,render={},{ };for id,a in pairs(M.actors)do n=n+1;if valid(a.e)then rows[#rows+1]=id..'|'..full(a.e)..'|'..a.e.HP end end;for id,a in pairs(M.replicas)do r=r+1;if valid(a.e)then rows[#rows+1]=id..'|'..full(a.e)..'|'..a.hp;render[#render+1]=id..'|'..(a.kind or'none')..'|'..a.poseUpdates..'|'..(a.native and'native'or'pose')..'|'..(a.montageStarts or 0)..'|'..(a.montageCorrections or 0) end end;write('enemy-bindings.txt',table.concat(rows,'\n'));write('enemy-render.txt',table.concat(render,'\n'));local s=M.timeline.stats;return Place.status()..' '..Capture.status()..' hostActors='..n..' activeActors='..#(M.activeVisuals or{})..' replicas='..r..' received='..M.received..' poses='..M.poses..' guestHits='..M.hits..' applied='..M.applied..string.format(' delay=%.4f jitter=%.4f play=%.6f interpolated=%d held=%d extrapolated=%d',M.timeline.delay,M.timeline.jitter,M.sampleTime or 0,s.interpolate,s.hold,s.extrapolate)end
 M.inspect=function()return M end
 local originalStatus=M.status;function M.status()return originalStatus()..' '..Validation.status()..' '..Known.status()..' '..AnimVisibility.status(M.replicas)end
 M.update=scope.wrap(M.update);M.apply=scope.wrap(M.apply,Validation);M.status=scope.wrap(M.status)
 return M
end
