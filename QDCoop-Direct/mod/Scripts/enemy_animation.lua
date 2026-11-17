-- Original enemy AnimBP state and montage playback on a cosmetic-only owner.
return function(dir,valid,full,invalidate)
 local C=dofile(dir..'enemy_animation_catalog.lua');local M={catalog=C};local profiles,montages,sequences={},{},{}
 local Clock=dofile(dir..'enemy_montage_clock.lua')(C);M.advance=Clock.advance
 for i,v in ipairs(C.profiles)do profiles[v.path]=i end;for i,v in ipairs(C.montages)do montages[v.path]=i end
 for i,v in ipairs(C.sequences)do sequences[v.path]=i end
 local bindings,hooks=setmetatable({},{__mode='v'}),{}
 function M.ensure(id)
  local profile=C.profiles[id];if not profile.restoreInputs then return true end
  local path=profile.path..':BlueprintUpdateAnimation'
  if hooks[path]then return true end
  local ok,err=pcall(function()
   invalidate();LoadAsset(profile.path);invalidate()
   local fn=StaticFindObject(path);assert(valid(fn),'animation update function unavailable')
   -- UE4SS script hooks use the first callback after script execution;
   -- the separate post callback is supported for native functions, not these.
   local a,b=RegisterHook(path,function(ctx)
    local ai=ctx:get();local address=ai:GetAddress();local r=bindings[address]
    if not r then return end
    if r.dead or not valid(r.pose)or not valid(r.e)or r.e:IsActorBeingDestroyed()then bindings[address]=nil;return end
    local owner=ai:GetOwningComponent()
    if not valid(owner)or owner:GetAddress()~=r.pose:GetAddress()then bindings[address]=nil;return end
    -- Only this registered network instance is affected. The animation graph
    -- evaluates after BlueprintUpdateAnimation; restore authority inputs here
    -- so local targeting/velocity cannot replace the interpolated snapshot.
    local good,why=pcall(function()for name,value in pairs(r.animDesired or{})do ai[name]=value end end)
    if not good and not r.animInputError then r.animInputError=tostring(why);print('[QDCoop] animation input restore failed: '..r.animInputError..'\n')end
   end)
   assert(a and b,'animation update hook unavailable');hooks[path]={a,b}
  end)
  if not ok then print('[QDCoop] owned animation unavailable '..path..': '..tostring(err)..'\n');return false end
  return true
 end
 function M.release(r)
  if r.animBindingAddress then bindings[r.animBindingAddress]=nil end;r.animBindingAddress=nil
  r.animDesired=nil;r.animInputError=nil
 end
 function M.reset()
  bindings=setmetatable({},{__mode='v'})
  for path,t in pairs(hooks)do local ok,err=pcall(UnregisterHook,path,t[1],t[2]);if ok then hooks[path]=nil else print('[QDCoop] animation hook cleanup pending '..path..': '..tostring(err)..'\n')end end
 end
 local flags={'bIsMoving','bIsChasing','bIsFalling','bIsAggro','bIsWandering'}
 local function load(path)local a=StaticFindObject(path);if valid(a)then return a end;invalidate();a=LoadAsset(path);invalidate();return a end
 local function path(o)return valid(o)and full(o):match(' (/[^ ]+)$')end
 function M.capture(r,mesh)
  if r.disableNative then return end
  local ai=mesh:GetAnimInstance();if not valid(ai)then return end
  local aiAddress=ai:GetAddress();local sk=mesh.SkeletalMesh;local meshAddress=valid(sk)and sk:GetAddress()
  local id=r.captureProfile
  if not id or r.captureAI~=aiAddress or r.captureMesh~=meshAddress then
   id=profiles[path(ai:GetClass())];if not id then r.disableNative=true;return end
   if C.meshes[path(sk)]~=C.profiles[id].skeleton then r.disableNative=true;return end
   r.captureProfile=id;r.captureAI=aiAddress;r.captureMesh=meshAddress
  end
  local montage=ai:GetCurrentActiveMontage();local mid=valid(montage)and montages[path(montage)]or 0
  if not mid then r.montageId=nil;r.montagePosition=nil;return end -- Unknown montage falls back only while active.
  if mid>0 and C.montages[mid].skeleton~=C.profiles[id].skeleton then r.montageId=nil;r.montagePosition=nil;return end
  local position,rate=0,1
  if mid>0 then position=ai:Montage_GetPosition(montage);rate=ai:Montage_GetPlayRate(montage)end
  if Clock.restart(r.montageId,mid,r.montagePosition,position)then r.montageSerial=(r.montageSerial or 0)+1 end
  r.montageId=mid;r.montagePosition=position
  local profile=C.profiles[id]
  local bits,aim=0,0
  if not profile.standalone then
   for i,name in ipairs(flags)do if ai[name]then bits=bits+2^(i-1)end end
   aim=ai.CurrentAimAngle
  elseif not profile.noMovementBits then
   -- The original HellSlime AnimBP uses plain Moving/Falling properties
   -- rather than the shared Enemy AnimBP's fields.
   bits=(ai.Moving and 1 or 0)+(ai.Falling and 4 or 0)
  end
  local values={id,mid,r.montageSerial or 0,Clock.advance(mid,position,0,rate),rate,bits,aim}
  for _,input in ipairs(profile.inputs)do
   local v=ai[input.name];local k=input.kind
   if k=='b'then values[#values+1]=v and 1 or 0
   elseif k=='r'or k=='v'then for _,axis in ipairs(k=='r'and{'Pitch','Yaw','Roll'}or{'X','Y','Z'})do values[#values+1]=v[axis]end
   elseif k=='a'then local sid=valid(v)and sequences[path(v)]or 0;if sid==nil or(sid>0 and C.sequences[sid].skeleton~=C.profiles[id].skeleton)then r.disableNative=true;return end;values[#values+1]=sid
   else values[#values+1]=v end
  end
  return values
 end
 function M.setup(r,id)
  M.release(r)
  r.pose:SetAnimClass((load(C.profiles[id].path)));r.pose.VisibilityBasedAnimTickOption=0
  r.anim=r.pose:GetAnimInstance();assert(valid(r.anim),'Enemy cosmetic animation instance');r.nativeId=id
  r.animDesired={}
  if C.profiles[id].restoreInputs and M.ensure(id)then r.animBindingAddress=r.anim:GetAddress();bindings[r.animBindingAddress]=r end
  r.animFrame=nil;r.playingId=nil;r.playingSerial=nil;r.playingMontage=nil
  r.inputCache={}
 end
 function M.apply(r,f,time,b,t)
  -- Graph controls are interpolated; sequence/montage time is advanced by UE.
  local ai=r.anim;local at=36;b=b or f;t=t or 0;if b[29]~=f[29]then b=f;t=0 end
  for _,input in ipairs(C.profiles[r.nativeId].inputs)do
   local k=input.kind;local old=r.inputCache[input.name];local v=f[at]
   if k=='r'or k=='v'then
    local value={};local changed=not old
    for i,axis in ipairs(k=='r'and{'Pitch','Yaw','Roll'}or{'X','Y','Z'})do local a,z=f[at+i-1],b[at+i-1];local delta=z-a;if k=='r'then delta=(delta+180)%360-180 end;value[axis]=a+delta*t;if old and math.abs(old[axis]-value[axis])>.001 then changed=true end end
    if changed then ai[input.name]=value;r.inputCache[input.name]=value end;r.animDesired[input.name]=value;at=at+3
   else
    if k=='f'then v=v+(b[at]-v)*t end
    if k=='b'then r.animDesired[input.name]=v==1 else r.animDesired[input.name]=v end
    if old~=v then
     if k=='b'then ai[input.name]=v==1 elseif k=='a'then ai[input.name]=v>0 and load(C.sequences[v].path)or nil else ai[input.name]=v end
     r.inputCache[input.name]=v
    end;at=at+1
   end
  end
  if r.animFrame==f then return end;r.animFrame=f
  local bits=f[34]
  if not C.profiles[r.nativeId].standalone then
   for i,name in ipairs(flags)do ai[name]=math.floor(bits/2^(i-1))%2==1 end
   ai.CurrentAimAngle=f[35]
   for i,name in ipairs(flags)do r.animDesired[name]=math.floor(bits/2^(i-1))%2==1 end
   r.animDesired.CurrentAimAngle=f[35]
  end
  local mid,serial=f[30],f[31]
  if mid==0 then if r.playingMontage then ai:Montage_Stop(.1,r.playingMontage)end;r.playingMontage=nil;r.playingId=0;r.playingSerial=serial;return end
  local m=r.playingId==mid and r.playingMontage or load(C.montages[mid].path)
  local target=Clock.advance(mid,f[32],time-f[5],f[33]);local length=m.SequenceLength
  if r.playingId~=mid or r.playingSerial~=serial then
   if target<length then ai:Montage_Play(m,f[33],0,target,true)end
   r.playingMontage=m;r.playingId=mid;r.playingSerial=serial;r.montageStarts=(r.montageStarts or 0)+1
  elseif ai:Montage_IsPlaying(m)then
   ai:Montage_SetPlayRate(m,f[33])
   -- Ordinary packets never reset the montage cursor. Correct only material drift.
   if target<length and Clock.drift(mid,ai:Montage_GetPosition(m),target)>.18 then ai:Montage_SetPosition(m,target);r.montageCorrections=(r.montageCorrections or 0)+1 end
  end
 end
 return M
end
