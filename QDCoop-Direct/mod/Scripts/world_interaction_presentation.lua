-- Recreate only presentation after the native save restore. Never call Interact/Open reward paths.
return function(valid,gs,poseMath)
 local M={};local time=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary');local moves={};local maths,sparks,lightSound
 local keySlides,doorMotion={},{}
 local doorKeys={
  {'/Game/RuinsLevel/AquaRuins/AquaDoor_00.AquaDoor_00_C','AquaDoorKey',4,'Y','/Game/RuinsLevel/AquaRuins/AquaDoor_InsertKey.AquaDoor_InsertKey'},
  {'/Game/RuinsLevel/SecretZones/RitualSite/prop/JigekiDoor_BP.JigekiDoor_BP_C','Key',3,'X','/Game/Items/KeyItems/JigekiKeys/JigekiDoor_InsertKey.JigekiDoor_InsertKey'},
 }
 local function keyDoor(a)
  for _,entry in ipairs(doorKeys)do if a:IsA(entry[1])then return entry end end
 end
 function M.savedDoorOpen(a,save)
  if not keyDoor(a)then return end
  local key=a.GUIDs[1]
  return save.SavableActorStates:Contains(key)and save.SavableActorStates:Find(key):get()>0
 end
 local function soundAt(a,sound)
  if valid(sound)then gs:PlaySoundAtLocation(a,sound,a:K2_GetActorLocation(),{Pitch=0,Yaw=0,Roll=0},1,1,0,nil,nil,nil)end
 end
 local function transformValues(t)
  local p,q,s=t.Translation,t.Rotation,t.Scale3D
  return {p.X,p.Y,p.Z,q.X,q.Y,q.Z,q.W,s.X,s.Y,s.Z}
 end
 local function setPose(c,v)
  c:K2_SetRelativeTransform(poseMath.transform({v[1],v[2],v[3]},{v[4],v[5],v[6],v[7]},{v[8],v[9],v[10]}),false,{},true)
 end
 local function slide(a,c,from,to,duration)
  setPose(c,from)
  keySlides[c:GetAddress()]={a=a,c=c,from=from,to=to,at=time:GetGameTimeInSeconds(a),duration=duration}
 end
 local function timelines(a)
  local out={}
  for _,v in ipairs(a:K2_GetComponentsByClass(StaticFindObject('/Script/Engine.TimelineComponent')))do
   local t=v:get();if valid(t)then out[#out+1]={t=t,position=t:GetPlaybackPosition()}end
  end
  return out
 end
 function M.doorBefore(a)
  local c=a.DoorMesh
  return {opened=a.Opened,timelines=timelines(a),mesh=c,pose=valid(c)and transformValues(c:GetRelativeTransform())}
 end
 function M.door(a,b,opened,animate)
  a.Opened=opened
  if valid(b.mesh)and b.pose then setPose(b.mesh,b.pose)end
  for _,v in ipairs(b.timelines)do if valid(v.t)then v.t:SetPlaybackPosition(v.position,false,true)end end
  if animate then animate(a,opened)
  elseif opened then a:OpenDoor()else a:CloseDoor()end
  doorMotion[a:GetAddress()]={a=a,untilTime=time:GetGameTimeInSeconds(a)+1,timelines=b.timelines}
 end
 function M.animatedDoor(a)
  local prior=doorMotion[a:GetAddress()]
  if not prior then return false end
  if not valid(prior.a)then doorMotion[a:GetAddress()]=nil;return false end
  if time:GetGameTimeInSeconds(a)<prior.untilTime then return true end
  for _,v in ipairs(prior.timelines)do if valid(v.t)and v.t:IsPlaying()then return true end end
  doorMotion[a:GetAddress()]=nil
  return false
 end
 local function buttonPose(a,t)
  -- DaggerButton_DamageTarget's native QuickTimeline: 0.5s, easing enum 12.
  -- Reproduce only its mesh/material writes, never Hit() or its activations.
  if not valid(maths)then maths=StaticFindObject('/Script/Engine.Default__KismetMathLibrary')end
  local x=maths:Ease(0,1,t,12,2,2);local mesh=a.StaticMesh
  mesh:K2_SetRelativeLocation({X=a.ButtonPushinPos*x,Y=0,Z=0},false,{},false)
  mesh:SetScalarParameterValueOnMaterials(FName('Color_Brightness'),1-.8*x)
  mesh:SetScalarParameterValueOnMaterials(FName('Cubemap_Intensity'),1-.9*x)
  mesh:SetScalarParameterValueOnMaterials(FName('Emissive_Brightness'),.3-.25*x)
 end
 function M.tick()
  for k,v in pairs(moves)do
   if not valid(v.a)then moves[k]=nil else local t=math.min(1,math.max(0,(time:GetGameTimeInSeconds(v.a)-v.at)/.5));buttonPose(v.a,t);if t>=1 then moves[k]=nil end end
  end
  for k,v in pairs(keySlides)do
   if not valid(v.a)or not valid(v.c)then keySlides[k]=nil
   else
    local t=math.min(1,math.max(0,(time:GetGameTimeInSeconds(v.a)-v.at)/v.duration))
    setPose(v.c,poseMath.blendTransform(v.from,v.to,1-(1-t)^2))
    if t>=1 then keySlides[k]=nil end
   end
  end
 end
 function M.reset()
  for _,v in pairs(moves)do if valid(v.a)then buttonPose(v.a,1)end end
  for _,v in pairs(keySlides)do if valid(v.c)then setPose(v.c,v.to)end end
  moves={};keySlides={};doorMotion={}
 end
 function M.before(a)
  if a:IsA('/Game/RuinsLevel/Models/DaggerButton/DaggerButton_DamageTarget.DaggerButton_DamageTarget_C')then return {kind='daggerButton',hit=a.AlreadyHit}
  elseif a:IsA('/Game/Enemies/Gargler_00/Gargoyle_Switch.Gargoyle_Switch_C')then return {kind='gargoyle',lit=a.Lit}
  elseif a:IsA('/Game/LD45/Blueprints/Objects/Gate/Lever.Lever_C')then
   return {kind='lever',on=a.ToggledOn}
  elseif a:IsA('/Game/RuinsLevel/AquaRuins/AQR_KeyRecepticle_BP.AQR_KeyRecepticle_BP_C')then
   return {kind='socket',item=valid(a.ContainedKey)and a.ContainedKey:GetAddress()or nil,filled=a.HasItem}
  elseif a:IsA('/Game/Blueprints/Door_Base.Door_Base_C')then
   local b=M.doorBefore(a);b.kind='door';b.keyDoor=keyDoor(a)
   if b.keyDoor then for i=1,b.keyDoor[3]do b[i]=a['Key'..i..'In']end end
   return b
  elseif a:IsA('/Game/Blueprints/SecretWall.SecretWall_C')then return {kind='secret',opened=a.Opened,running=a.AnimRunning}
  elseif a:IsA('/Game/Props/Chest_00/Chest.Chest_C')then return {kind='chest',opened=a.InteractBox:GetCollisionEnabled()==0,running=a.OpenLid:IsPlaying()}end
 end
 function M.after(a,b,deferDoor)
  if not b then return end
  if b.kind=='daggerButton'then
   if not b.hit and a.AlreadyHit then
    moves[a:GetAddress()]={a=a,at=time:GetGameTimeInSeconds(a)};buttonPose(a,0)
    if valid(a.SoundOnHit)then gs:PlaySoundAtLocation(a,a.SoundOnHit,a:K2_GetActorLocation(),{Pitch=0,Yaw=0,Roll=0},1,1,0,nil,nil,nil)end
    if not valid(sparks)then sparks=LoadAsset('/Game/RuinsLevel/Models/DaggerButton/DaggerButton_Hitspakrs.DaggerButton_Hitspakrs')end
    if valid(sparks)then StaticFindObject('/Script/Niagara.Default__NiagaraFunctionLibrary'):SpawnSystemAtLocation(a,sparks,a:K2_GetActorLocation(),a:K2_GetActorRotation(),{X=1,Y=1,Z=1},true,true,1,true)end
   end
  elseif b.kind=='gargoyle'then
   if not b.lit and a.Lit then
    a.Timeline_0:PlayFromStart()
    if not valid(lightSound)then lightSound=LoadAsset('/Game/Enemies/Gargler_00/Audio/Gargoyle_Switch_Light.Gargoyle_Switch_Light')end
    if valid(lightSound)then gs:SpawnSoundAttached(lightSound,a.SkeletalMesh,FName('None'),{X=0,Y=0,Z=0},{Pitch=0,Yaw=0,Roll=0},0,false,1,1,0,nil,nil,true)end
   end
  elseif b.kind=='lever'then
   if a.ToggledOn~=b.on then
    if a.ToggledOn and a:IsA('/Game/RuinsLevel/Mausoleum/QueensGrave/RuneButton.RuneButton_C')then
     a.Timeline_0_0:SetPlaybackPosition(0,false,true)
    end
    if a.ToggledOn then a:AnimateLeverPull()else a:AnimateLeverReset()end
    if a.ToggledOn then soundAt(a,a.ActivateSound)end
   end
  elseif b.kind=='socket'then
   if a.HasItem and valid(a.ContainedKey)and(not b.filled or b.item~=a.ContainedKey:GetAddress())then
    local c=a.KeyMesh
    -- The original insertion also controls the actor at the player's camera,
    -- closes the key menu and writes the save; just move the visible key here.
    local target=transformValues(c:GetRelativeTransform())
    local start=transformValues(a.InsertAnimStartTransform)
    local s=a.KeyScale;start[8],start[9],start[10]=s.X,s.Y,s.Z
    slide(a,c,start,target,.45)
    soundAt(a,a.InsertSound)
   end
  elseif b.kind=='door'then
   local entry=b.keyDoor
   if entry then
    for i=1,entry[3]do
     if not b[i]and a['Key'..i..'In']then
      local c=a[entry[2]..i];local target=transformValues(c:GetRelativeTransform())
      local start={table.unpack(target)};local axis=entry[4]=='X'and 1 or 2;start[axis]=start[axis]+40
      slide(a,c,start,target,.32)
      if not valid(entry.sound)then entry.sound=LoadAsset(entry[5])end
      soundAt(a,entry.sound)
     end
    end
   end
   if not deferDoor and a.Opened~=b.opened then M.door(a,b,a.Opened)end
  elseif b.kind=='chest'then
   if not b.opened and not b.running and a.InteractBox:GetCollisionEnabled()==0 then
    a.OpenLid:PlayFromStart()
    if valid(a.OpenSound)then gs:PlaySoundAtLocation(a,a.OpenSound,a:K2_GetActorLocation(),{Pitch=0,Yaw=0,Roll=0},1,1,0,nil,nil,nil)end
   end
  elseif b.kind=='secret'and a.Opened~=b.opened and not b.running then
   a.AnimStartTime=time:GetGameTimeInSeconds(a);a.AnimRunning=true;a:SetActorTickEnabled(true)
   local sound=valid(a.OpenSoundOverride)and a.OpenSoundOverride or a.OpenSound
   if valid(sound)then
    a.OpeningSoundComp=gs:SpawnSoundAttached(sound,a.DefaultSceneRoot,FName('None'),{X=0,Y=0,Z=0},{Pitch=0,Yaw=0,Roll=0},0,false,1,1,0,nil,nil,true)
    if valid(a.OpeningSoundComp)then a.OpeningSoundComp:FadeIn(.2,1,0,0)end
   end
  end
 end
 return M
end
