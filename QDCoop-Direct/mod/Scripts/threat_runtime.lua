return function(dir,C,valid,full,write,log,records,byActor,resolveSource)
 local policy=dofile(dir..'threat_policy.lua');local Interest=dofile(dir..'enemy_interest.lua');local DP=dofile(dir..'damage_protocol.lua');local codec=dofile(dir..'damage_codec.lua')(DP)
 local gs=C.ObjectRefs.find('/Script/Engine.Default__GameplayStatics');local ks=C.ObjectRefs.find('/Script/Engine.Default__KismetSystemLibrary')
 local maths=C.ObjectRefs.find('/Script/Engine.Default__KismetMathLibrary')
 local T={sent=0,received=0,switches=0,hitSerial=0,seen={},unknown=0,guests={}};local clsPath='/Game/QDCoop/QDCoopGuestTarget.QDCoopGuestTarget_C'
 local function same(a,b)return valid(a)and valid(b)and a:GetAddress()==b:GetAddress()end
 local function point(a)return a:K2_GetActorLocation()end
 local function distance(a,b)return math.sqrt((a.X-b.X)^2+(a.Y-b.Y)^2+(a.Z-b.Z)^2)end
 local function state(r)r.threat=r.threat or policy.new();return r.threat end
 local function emit(s,id)local prefix=C.RoomProtocol==2 and id and('TO|'..id..'|')or'';write('out.events',prefix..'THT|'..T.world..'|'..T.session..'|'..s..'\n',true)end
 local function loadClass()
  local c=C.ObjectRefs.find(clsPath)
  if not valid(c)then local path=ks:MakeSoftClassPath(clsPath);local ref=ks:Conv_SoftClassPathToSoftClassRef(path);c=ks:LoadClassAsset_Blocking(ref)end
  assert(valid(c),'Guest target asset missing; launch both games from the complete 0.10 package')
  local gi=FindFirstOf('FS_GameInstance_C');if valid(gi)then local refs,found={},false;gi.ReferencedObjects:ForEach(function(i,v)local o=v:get();refs[#refs+1]=o;if same(o,c)then found=true end end);if not found then refs[#refs+1]=c;gi.ReferencedObjects=refs end end
  return c
 end
 function T.scratch()
  loadClass();return C.ObjectRefs.find('/Game/QDCoop/QDCoopGuestTarget.Default__QDCoopGuestTarget_C')
 end
 function T.guestId(a)for id,g in pairs(T.guests)do if same(a,g.proxy)then return id end end end
 function T.isGuest(a)return T.guestId(a)~=nil end
 function T.guest(id)return T.guests[id or'client']end
 local function attackGuest(r)
  if not r or r.retired or r.syncActive==false or not valid(r.e)then return end
  local id=r.threat and r.threat.target
  local guest=id and T.guests[id]
  if guest and guest.alive and guest.session and same(r.e.TargetPlayer,guest.proxy)then return id,guest end
 end
 local fishman='/Game/Enemies/FishManer_00/FishManer_Base_BP.FishManer_Base_BP_C'
 local fishShot='/Game/Enemies/FishManer_00/Fishmaner_Projectile.Fishmaner_Projectile_C'
 local poisonShot='/Game/Enemies/PoisonFishMan/PoisonFishMan_Projectile.PoisonFishMan_Projectile_C'
 local enemyShot='/Game/Enemies/Shared/Enemy_Projectile_Base.Enemy_Projectile_Base_C'
 local hellbatShot='/Game/Enemies/DemonBosses/HellBat/Hellbat_FireProjectile.Hellbat_FireProjectile_C'
 local pending={}
 local function subclass(a,path)local c=C.ObjectRefs.find(path);return valid(c)and a:IsA(c)end
 local function instigator(a)
  local recordsByActor=byActor()
  local instigator=a:GetInstigator()
  local r=valid(instigator)and recordsByActor[full(instigator)]
  if r then return r end
  local owner=a:GetOwner()
  return valid(owner)and recordsByActor[full(owner)]or nil
 end
 local function isFishShot(a)
  -- Some unrelated projectiles inherit Fishmaner_Projectile. Require a
  -- FishManer shooter too, and apply only to the actual native spit.
  return subclass(a,fishShot)or subclass(a,poisonShot)
 end
 local function aimDirectShot(actor,spawnTransform,record,guest)
  local fish=subclass(record.e,fishman)and isFishShot(actor)
  local bat=not fish and subclass(actor,hellbatShot)
  if not fish and not bat then return end
  local transform=spawnTransform:get();local start=transform.Translation;local finish=point(guest.proxy)
  local dx,dy=finish.X-start.X,finish.Y-start.Y
  local horizontal=math.sqrt(dx*dx+dy*dy)
  if horizontal<1 then return end
  local rot=maths:Quat_Rotator(transform.Rotation)
  local pitch=bat and math.deg(math.atan(finish.Z-start.Z,horizontal))or rot.Pitch
  local aimed=maths:MakeTransform(start,{Pitch=pitch,Yaw=math.deg(math.atan(dy,dx)),Roll=rot.Roll},transform.Scale3D)
  spawnTransform:set(aimed)
  T.rangedAim=(T.rangedAim or 0)+1
 end
 local scriptedHoming=dofile(dir..'enemy_scripted_homing.lua')(C,valid,full,subclass,T)
 local function queueHoming(actor)
  if not valid(actor)or not subclass(actor,enemyShot)then return end
  local id,guest=attackGuest(instigator(actor));if not guest or #pending>=128 then return end
  local entry={weak=C.ObjectRefs.captureFresh(actor),c=actor,path=full(actor):match(' (.+)$'),address=actor:GetAddress()}
  if entry.path then
   entry.guest=id;entry.session=guest.session
   pending[#pending+1]=entry
  end
 end
 local function resolveHoming()
  if #pending==0 then return end
  local work=pending;pending={}
  for _,entry in ipairs(work)do
   local guest=T.guests[entry.guest]
   if guest and guest.alive and guest.session==entry.session and valid(guest.proxy)then
    local projectile=C.ObjectRefs.resolve(entry)
    if valid(projectile)and projectile:GetAddress()==entry.address then
     local movement=projectile.ProjectileMovement
     if valid(movement)then
      local target=movement.HomingTargetComponent:Get()
      if valid(target)and same(target:GetOwner(),T.player)then
       local replacement=guest.proxy.CapsuleComponent
       if same(target,T.player.Arms)and valid(guest.proxy.Arms)then replacement=guest.proxy.Arms
       elseif same(target,T.player.FirstPersonCamera)and valid(guest.proxy.FirstPersonCamera)then replacement=guest.proxy.FirstPersonCamera end
       if valid(replacement)then
        local property=movement:Reflection():GetProperty('HomingTargetComponent')
        local targetPath=full(replacement):match(' (.+)$')
        local ok=targetPath and pcall(function()
         property:ImportText(targetPath,property:ContainerPtrToValuePtr(movement,0),0,movement)
        end)
        if ok and same(movement.HomingTargetComponent:Get(),replacement)then
         T.homingRetargets=(T.homingRetargets or 0)+1
        end
       end
      end
     end
    end
   end
  end
 end
 function T.target(e)
  local r=byActor()[full(e)];local s=r and r.threat
  if T.connected and C.Role=='host'and s and r.syncActive~=false then if valid(r.memoryActor)then return r.memoryActor end;local g=T.guests[s.target];return g and valid(g.proxy)and g.proxy or T.player end
 end
 local function perception(e,r)
  local s=r and r.threat;local c=s and r.threatCandidates and r.threatCandidates[s.target]
  if not T.connected or C.Role~='host'or not s or r.syncActive==false then return end
  local seen=c and c.alive and c.inRange and c.los or false
  local los=e.EnemyLineOfSight;local range=c and c.distance or 100000
  e.SeenPlayerRange=range;e.bPlayerIsSeen=seen;e.HasPlayerlos=seen
  los.SeenRange=range;los.bCanSeeTarget=seen;los.bHasLOS=seen;los.bTargetIsInRange=c and c.inRange or false
  return seen
 end
 function T.record(r,id,amount)
  if not T.connected or C.Role~='host'or not r then return end
  r.syncActive=true;r.wakeUntil=gs:GetRealTimeSeconds(r.e)+4;policy.hit(state(r),id,amount,gs:GetRealTimeSeconds(r.e));r.threatTotals=r.threatTotals or{host=0,client=0};r.threatTotals[id]=(r.threatTotals[id]or 0)+math.max(0,amount or 0)
 end
 function T.capture(d)return codec.capture(d)end
 function T.build(d)return codec.build(T.scratch(),d)end
 function T.decode(...)return DP.decode(...)end
 function T.install(hookIds)
  if T.installed then return end;T.installed=true
  if C.Role~='host'then return end
  loadClass()
  local function hook(path,fn,post)
   local function active(f)if not f then return nil end;return function(...)if not T.connected or C.Role~='host' then return end;return f(...)end end
   local label='hook.threat.'..path:match(':([^:]+)$')
   local a,b=RegisterHook(path,C.Perf.hook(active(fn),label),post and C.Perf.hook(active(post),label..'.post')or nil);hookIds[#hookIds+1]={path,a,b}
  end
  -- EnemyBase pays kill XP to TargetPlayer, which may now be our inert guest
  -- target. The guest already receives its own ER reward; preserve the host's
  -- native award here instead of letting the proxy swallow it. Do not turn
  -- XP-steal attacks into an extra party kill reward.
  hook(clsPath..':AddXP',function(ctx,amount,fromSteal)
   if not T.isGuest(ctx:get())or fromSteal:get()or not valid(T.player)then return end
   local xp=amount:get();if xp<=0 then return end
   T.player:AddXP(xp,false)
   T.hostXPRecovered=(T.hostXPRecovered or 0)+xp
   write('threat-xp-status.txt','hostKillXPRecovered='..T.hostXPRecovered..'\n')
  end)
  -- The original BP supplies GetPlayerPawn(0) here even after TargetPlayer changes.
  hook('/Script/QueensDomain.FS_EnemyCharacterBase:DoBasicCharacterRotationUpdate',function(ctx,a,b,c,d,e,f,target)
   local t=T.target(ctx:get());if valid(t)then target:set(t)end
  end)
  local finish='/Script/Engine.GameplayStatics:FinishSpawningActor'
  hook(finish,function(_,actor,transform)
   local projectile=actor:get()
   if not valid(projectile)or not subclass(projectile,enemyShot)then return end
   local record=instigator(projectile)
   local id,guest=attackGuest(record)
   if not guest then return end
   aimDirectShot(projectile,transform,record,guest)
   scriptedHoming.bind(projectile,id,guest)
  end,
   function(_,ret,actor)queueHoming(actor:get())end)
  hook('/Game/Enemies/EnemyBase.EnemyBase_C:UpdateCanSeePlayer',function(ctx)local e=ctx:get();perception(e,byActor()[full(e)])end)
  hook('/Game/Enemies/EnemyBase.EnemyBase_C:EvaluateAwarenessCones',function(ctx,sensitivity,saw)
   local e=ctx:get();local r=byActor()[full(e)];local seen=perception(e,r);if seen~=nil then saw:set(seen);if not seen then sensitivity:set(0)end end
  end)
  hook('/Game/Enemies/EnemyBase.EnemyBase_C:GetChaseTarget',function(ctx,target)local r=byActor()[full(ctx:get())];if T.connected and C.Role=='host'and r and valid(r.memoryActor)then target:set(r.memoryActor)end end)
  hook('/Game/Enemies/EnemyBase.EnemyBase_C:GetLastSeenPlayerLoc',function(ctx,loc)local r=byActor()[full(ctx:get())];if T.connected and C.Role=='host'and r and valid(r.memoryActor)then local p=point(r.memoryActor);local out=loc:get();out.X=p.X;out.Y=p.Y;out.Z=p.Z end end)
  hook('/Script/QueensDomain.FS_EnemyCharacterBase:GetDistanceToPlayerForAI',function()end,function(ctx,d3,d2)
   local e=ctx:get();local r=byActor()[full(e)];if T.connected and C.Role=='host'and r and valid(r.memoryActor)then local a,b=point(e),point(r.memoryActor);d3:set(distance(a,b));d2:set(math.sqrt((a.X-b.X)^2+(a.Y-b.Y)^2))end
  end)
  hook(clsPath..':TryApplyDamage',function(ctx,hit,damage,applier,applied,pos,hitValid)
   local id=T.guestId(ctx:get());local guest=id and T.guests[id]
   if C.Role~='host'or not T.connected or not guest or not guest.session or not guest.alive then return false end
   -- Native attacks may supply their projectile/component/action as applier.
   -- Resolve the owning enemy using the same bounded chain as effects/audio.
   local source=applier:get();local r=valid(source)and(resolveSource and resolveSource(source)or byActor()[full(source)])
   if not r or r.retired or not valid(r.e)then T.unknown=T.unknown+1;return false end
   local d,encoded=codec.capture(damage:get());if not encoded or d.amount<=0 then return false end
   T.hitSerial=T.hitSerial+1;local p=pos:get()
   emit(string.format('D|%s|%d|%d|%s|%.4f|%.4f|%.4f|%d',guest.session,r.id,T.hitSerial,encoded,p.X,p.Y,p.Z,hitValid:get()and 1 or 0),id);T.sent=T.sent+1
   return true
  end)
 end
 function T.reset(travel)
  scriptedHoming.reset()
  if not travel then
   for _,r in pairs(records())do
    if valid(r.e)then
     if valid(T.player)and T.isGuest(r.e.TargetPlayer)then r.e.TargetPlayer=T.player;local c=r.e:GetController();if valid(c)then c:StopMovement()end end
     if r.losOriginal then r.e.EnemyLineOfSight.bEnabled=r.losOriginal.enabled;r.e.EnemyLineOfSight:SetComponentTickEnabled(r.losOriginal.tick)end
    end
    if valid(r.memoryActor)then r.memoryActor:K2_DestroyActor()end;r.threat=nil;r.memoryActor=nil;r.losOriginal=nil
   end
   for _,guest in pairs(T.guests)do local a=guest.proxy;if valid(a)then local g=gs:GetGameState(a);if valid(g)and g:IsA(C.ObjectRefs.find('/Script/FBAttributes.FB_GameState'))then g:UnregisterDamageableActor(a)end;a:K2_DestroyActor()end end
  end
  pending={};T.guests={};T.proxy=nil;T.proxyAlive=false;T.peer=nil;T.connected=false;T.seen={};T.seenOrder={};T.lastDamage={};T.nextEvaluate=0;T.evaluateQueue=nil;T.evaluateIndex=1;T.proxyAt=nil
 end
 function T.uninstall()scriptedHoming.reset();T.installed=false end
 local function proxy(player,p)
  local t=player:GetTransform();t.Translation={X=p.X,Y=p.Y,Z=p.Z}
  local a=gs:BeginDeferredActorSpawnFromClass(player,loadClass(),t,1,nil);assert(valid(a),'Guest collision proxy spawn failed')
  a:SetActorHiddenInGame(true);gs:FinishSpawningActor(a,t);a:SetActorTickEnabled(false);a.CharacterMovement:DisableMovement();a.CharacterMovement:SetComponentTickEnabled(false)
  a.Mesh:SetCollisionEnabled(0);a.Mesh:SetComponentTickEnabled(false)
  a.CapsuleComponent:SetCollisionEnabled(1);a.CapsuleComponent:SetCollisionResponseToChannel(2,1);a.CapsuleComponent:SetCollisionResponseToChannel(3,0);a.CapsuleComponent:SetCollisionResponseToChannel(4,0)
  a.Health=p.hp;a.IsDead=p.hp<=0;local g=gs:GetGameState(player);if valid(g)and g:IsA(C.ObjectRefs.find('/Script/FBAttributes.FB_GameState'))then g:RegisterDamageableActor(a)end
  log('THREAT guest proxy ready '..full(a));return a
 end
 local function candidate(e,a,id,r,now,sight)
  if not valid(a)or a.IsDead or a.Health<=0 then return {alive=false}end
  if not sight.position then sight.position=point(e);sight.forward=e:GetAIForwardVector()end
  local ep,ap=sight.position,point(a);local dist=distance(ep,ap);local s=state(r);local recent=policy.recent(s,id,now)
  -- Idle detection range is not a combat leash. Short-sighted enemies must
  -- still pursue an observed ranged attacker, without acquiring idle bystanders.
  local range=policy.range(r.awarenessRange,s.target==id or recent>0)
  local inRange=false
  if dist<=range then
   if sight.height==nil then sight.height=e:GetAggroHeight()end
   inRange=math.abs(ep.Z-ap.Z)<=sight.height
  end
   local f=sight.forward;local dx,dy=ap.X-ep.X,ap.Y-ep.Y;local len=math.sqrt(dx*dx+dy*dy);local front=len<1 or (dx*f.X+dy*f.Y)/len>=policy.frontCos
  local los=false
  if inRange then
   if not sight.viewpoint then sight.viewpoint=maths:TransformLocation(e.CapsuleComponent:K2_GetComponentToWorld(),e.LocalViewpoint.Translation)end
   local ignore={e,T.player};for _,g in pairs(T.guests)do if valid(g.proxy)then ignore[#ignore+1]=g.proxy end end
   los=not ks:LineTraceSingle(e,sight.viewpoint,ap,0,true,ignore,0,{},true,{},{},0)
  end
  if los and(front or s.target==id or recent>0)then r.lastVisible=r.lastVisible or{};r.lastVisible[id]={X=ap.X,Y=ap.Y,Z=ap.Z};s.seen[id]=now end
  return {alive=true,inRange=inRange,distance=dist,front=front,los=los,visible=front and los}
 end
 function T.update(player,world,session,now,connected,peer,p)
  T.player=player;T.world=world;T.session=session;T.connected=connected
  if C.Role~='host'or not connected then return end
  if C.RoomProtocol~=2 and T.peer and T.peer~=peer then T.reset(false);T.connected=connected end;T.peer=peer
  local current=C.RoomProtocol==2 and C.RoomPeers or{client={session=peer,pose=p,world=world}}
  current=current or{}
  for id,g in pairs(T.guests)do if not current[id]then
   for _,r in pairs(records())do if valid(r.e)and same(r.e.TargetPlayer,g.proxy)then r.e.TargetPlayer=player;local c=r.e:GetController();if valid(c)then c:StopMovement()end end end
   if valid(g.proxy)then local state=gs:GetGameState(g.proxy);if valid(state)and state:IsA(C.ObjectRefs.find('/Script/FBAttributes.FB_GameState'))then state:UnregisterDamageableActor(g.proxy)end;g.proxy:K2_DestroyActor()end
   T.guests[id]=nil
  end end
  for id,source in pairs(current)do
   local g=T.guests[id]or{};T.guests[id]=g;local pos=source.pose;g.session=source.session or(source.frame and source.frame.T.session)
   local alive=source.world==world and pos and pos.hp and pos.hp>0 and(pos.down or 0)==0 and pos.at and now-pos.at<8 and g.session~=nil
   if alive then
    if not valid(g.proxy)then g.proxy=proxy(player,pos);g.at=nil end
    if not g.alive then g.proxy:SetActorEnableCollision(true)end
    if g.at~=pos.at then g.proxy.Health=pos.hp;g.proxy.IsDead=false;g.proxy:K2_SetActorLocationAndRotation({X=pos.X,Y=pos.Y,Z=pos.Z},{Pitch=0,Yaw=pos.yaw or 0,Roll=0},false,{},true);g.at=pos.at end
   elseif g.alive and valid(g.proxy)then g.proxy.Health=0;g.proxy.IsDead=true;g.proxy:SetActorEnableCollision(false)end
   g.alive=not not alive
  end
  -- The projectile blueprint can assign its homing component after the
  -- FinishSpawningActor call returns. Read the completed assignment here.
  resolveHoming()
  scriptedHoming.update(now)
  local legacy=T.guests.client;T.proxy=legacy and legacy.proxy;T.peerAlive=legacy and legacy.alive
  -- Distribute sight traces across frames instead of a single 5 Hz burst.
  if (not T.evaluateQueue or T.evaluateIndex>#T.evaluateQueue)and now>=(T.nextEvaluate or 0)then
   T.nextEvaluate=now+.2
   T.evaluateQueue={};T.evaluateIndex=1
   local own=point(player)
   for _,r in pairs(records())do
    -- Cached snapshots permit the interest decision without reflected actor
    -- traversal. This gates EXTRA co-op work, not native actors or wire cadence.
    r.syncActive=Interest.active(r,own,p,now,C.RoomProtocol==2 and C.RoomPeers or nil,world)
    if r.syncActive then T.evaluateQueue[#T.evaluateQueue+1]=r
    elseif r.losOriginal and valid(r.e)then local l=r.e.EnemyLineOfSight;l.bEnabled=r.losOriginal.enabled;l:SetComponentTickEnabled(r.losOriginal.tick);r.losOriginal=nil end
   end
  end
  local processed=0;local workStart=os.clock()
  while T.evaluateQueue and T.evaluateIndex<=#T.evaluateQueue do
   local r=T.evaluateQueue[T.evaluateIndex];T.evaluateIndex=T.evaluateIndex+1
   processed=processed+1
   local e=r.e
   if valid(e)and valid(e.Data)and e.HP>0 and not e.bDead and not e.BestiaryInstance and not e.bSpawnerPreviewInstance then
    if r.flee==nil then r.flee=e:IsA('/Game/Enemies/Lizer_00/Default_Lizer_01.Default_Lizer_01_C')and not e.DefaultEnemyMode end
    r.awarenessRange=e.Data.AwarenessProfile:GetRealMaxRangeForProfile(e.AggroRange)
    if not r.losOriginal then local l=e.EnemyLineOfSight;r.losOriginal={enabled=l.bEnabled,tick=l:IsComponentTickEnabled()};l.bEnabled=false;l:SetComponentTickEnabled(false)end
    if not r.threatInitialized and(e.bIsAttacking or e.bInRecoveryTime)then local s=state(r);s.target=T.guestId(e.TargetPlayer)or'host';s.since=now end
    r.threatInitialized=true
    local s=state(r);local sight={}
    local candidates={host=candidate(e,player,'host',r,now,sight)}
    for id,g in pairs(T.guests)do candidates[id]=g.alive and candidate(e,g.proxy,id,r,now,sight)or{alive=false}end
    r.threatCandidates=candidates
    local previous,previousSince=s.target,s.since
    local target,changed=policy.choose(s,candidates,now,e.bIsAttacking or e.bInRecoveryTime,e.Data.HP)
    -- A frightened treasure lizard runs AWAY from its target. Preserve its
    -- native fear decay; a chase-memory timeout must not send it back home.
    if r.flee and not target and e.bAggrod and previous and candidates[previous]and candidates[previous].alive then
     s.target=previous;s.since=previousSince;target=previous;if changed then s.switches=s.switches-1 end;changed=false
    end
    local memory=not r.flee and target and not candidates[target].los and r.lastVisible and r.lastVisible[target]
    if memory and not valid(r.memoryActor)then
     local t=e:GetTransform();t.Translation=memory;local a=gs:BeginDeferredActorSpawnFromClass(e,C.ObjectRefs.find('/Script/Engine.SkeletalMeshActor'),t,1,nil);gs:FinishSpawningActor(a,t);a:SetActorHiddenInGame(true);a:SetActorEnableCollision(false);a:SetActorTickEnabled(false);r.memoryActor=a;local c=e:GetController();if valid(c)and e.bIsChasing then c:StopMovement()end
    elseif not memory and valid(r.memoryActor)then r.memoryActor:K2_DestroyActor();r.memoryActor=nil;local c=e:GetController();if valid(c)and e.bIsChasing then c:StopMovement()end end
    local chosen=target and T.guests[target]and T.guests[target].proxy or player
    if valid(chosen)and not same(e.TargetPlayer,chosen)then
     e.TargetPlayer=chosen
     -- Cancel the old MoveTo once; the original chase-state continuation issues
     -- its next request against GetChaseTarget, which now returns the new pawn.
     local c=e:GetController();if not r.flee and valid(c)and e.bIsChasing then c:StopMovement()end
     e.EnemyLineOfSight:UpdateLOSParams()
    end
    if changed then T.switches=T.switches+1;log('THREAT target '..r.id..'='..tostring(target))end
    perception(e,r)
    if changed and not target and e.bAggrod and not r.flee then e:ForceUnaggro()end
    if not e.bAggrod and target and candidates[target].visible and not e.bIsAIDisabled then e.AggroBuildup=1;e:ForceAggroupdate()end
    if not e.bAggrod and not target then r.threat=nil end
   else r.threat=nil;r.threatTotals=nil;r.threatInitialized=nil;if valid(r.memoryActor)then r.memoryActor:K2_DestroyActor();r.memoryActor=nil end;if valid(e)and r.losOriginal then e.EnemyLineOfSight.bEnabled=r.losOriginal.enabled;e.EnemyLineOfSight:SetComponentTickEnabled(r.losOriginal.tick);r.losOriginal=nil end end
   if processed>=8 or os.clock()-workStart>=.001 then break end
  end
 end
 function T.event(f,world,peer,replicas)
  if C.Role~='client'or not T.connected or f[2]~='THT'or #f~=16 or f[3]~=world or f[4]~=peer or f[5]~='D'or f[6]~=T.session then return end
  local id,serial=tonumber(f[7]),tonumber(f[8]);local d=DP.decode(f[9],f[10],f[11],f[12]);local p={X=tonumber(f[13]),Y=tonumber(f[14]),Z=tonumber(f[15])};local validHit=tonumber(f[16]);local r=id and replicas[id]
  if not r or not valid(r.e)or not d or d.amount<=0 or not serial or serial%1~=0 or serial<1 or serial>1e9 or not p.X or not p.Y or not p.Z or(validHit~=0 and validHit~=1)then return end
  for _,v in pairs(p)do if v~=v or math.abs(v)>1e7 then return end end
  local key=peer..':'..serial;if T.seen[key]then return end;T.seen[key]=true;T.seenOrder=T.seenOrder or{};T.seenOrder[#T.seenOrder+1]=key;if #T.seenOrder>512 then T.seen[table.remove(T.seenOrder,1)]=nil end
  if not valid(T.player)or T.player.IsDead or T.player.Health<=0 then return end
  local before=T.player.Health;local damage=T.build(d)
  T.player:TryApplyDamage({},damage,r.e,{},p,validHit==1);T.received=T.received+1
  write('threat-damage.txt',string.format('enemy=%d serial=%d raw=%.4f before=%.4f after=%.4f\n',id,serial,d.amount,before,T.player.Health))
 end
 function T.status()
  local rows={};for id,r in pairs(records())do local s=r.threat;if s then local t=r.threatTotals or{};rows[#rows+1]=string.format('%d|%s|%.4f|%.4f|%.4f|%.4f|%d|%.4f|%.4f',id,s.target or'none',s.scores and s.scores.host or 0,s.scores and s.scores.client or 0,s.recentDamage and s.recentDamage.host or 0,s.recentDamage and s.recentDamage.client or 0,s.switches,t.host or 0,t.client or 0)end end
  write('threat-bindings.txt',table.concat(rows,'\n'));write('threat-status.txt',string.format('proxy=%s switches=%d sent=%d received=%d unknownSources=%d extraDamageObjects=%d rangedAim=%d homingRetargets=%d scriptedAim=%d scriptedAimActive=%d\n',valid(T.proxy)and full(T.proxy)or'none',T.switches,T.sent,T.received,T.unknown,codec.extraObjects,T.rangedAim or 0,T.homingRetargets or 0,T.scriptedAim or 0,scriptedHoming.count()))
 end
 T.update=C.Perf.measure(T.update,'enemy.threat')
 return T
end
