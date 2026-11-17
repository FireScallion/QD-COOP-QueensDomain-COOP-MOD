-- These Blueprint graphs obtain player 0 through their own WorldContext.
-- Keep the native steering, life span, and collision logic for every shot.
return function(C,valid,full,subclass,threat)
 local scripts='/Game/Enemies/'
 local pawnClasses={
  scripts..'Boner_00/Skeletons24/Black/Mage/WitchBoner_Projectile.WitchBoner_Projectile_C',
  scripts..'Waspdeer/WaspDeer_MagicProjectile.WaspDeer_MagicProjectile_C',
  scripts..'Queen/Queen_FastProjectile_BP.Queen_FastProjectile_BP_C',
 }
 local characterClass=scripts..'Necronomicon/NecronomiconHomingProjectile.NecronomiconHomingProjectile_C'
 local bindings={Pawn={},Character={}}
 local hooks={}
 local nextSweep=0
 local size=0
 local M={}
 local vampiricClass=scripts..'JosamiLord/BloodSisters/JosamiLords_HomingProjectiles.JosamiLords_HomingProjectiles_C'
 local function targetFor(entry)
  local guest=threat.guests[entry.guest]
  if guest and guest.alive and guest.session==entry.session and valid(guest.proxy)then return guest.proxy end
 end
 local function unchanged(entry,actor)
  local refs=C.ObjectRefs
  if entry.weak and refs.validation then
   local live=refs.validation.checkToken(entry.weak)
   if live~=nil then return live end
  end
  return full(actor):match(' (.+)$')==entry.path
 end
 local function hook(kind)
  if hooks[kind]then return end
  local path='/Script/Engine.GameplayStatics:GetPlayer'..kind
  local redirect=C.Perf.hook(function(result,context,index,group)
   local actor=context:get()
   if not actor then return end
   local entry=group[actor:GetAddress()]
   if not entry or index:get()~=0 or not unchanged(entry,actor)then return end
   local target=targetFor(entry)
   if not target then return end
   local original=result:get()
   if not valid(original)or not valid(threat.player)or original:GetAddress()~=threat.player:GetAddress()then return end
   if kind=='Character'and not valid(target.FirstPersonCamera)then return end
   -- Write the typed return parameter. A Lua callback return of an UObject
   -- was unstable in the shipped UE4SS build.
   result:set(target)
   threat.scriptedAim=(threat.scriptedAim or 0)+1
  end,'hook.threat.ranged'..kind)
  -- UE4SS defers native unregistration to a later invocation. Register at
  -- most once, then leave an empty fast path between shots and rooms.
  RegisterHook(path,function()end,function(_,result,context,index)
   local group=bindings[kind]
   if threat.connected and next(group)then redirect(result,context,index,group)end
  end)
  hooks[kind]=true
 end
 function M.bind(actor,id,guest)
  if size>=256 then return end
  -- This variant also compares GetPlayerPawn inside its vampirism handler.
  -- Resolve that impact call separately so a host interception still counts.
  if subclass(actor,vampiricClass)then return end
  local kind
  for _,class in ipairs(pawnClasses)do if subclass(actor,class)then kind='Pawn';break end end
  if not kind and subclass(actor,characterClass)then kind='Character' end
  if not kind then return end
  local refs=C.ObjectRefs
  local entry={weak=refs.captureFresh(actor),c=actor,path=full(actor):match(' (.+)$')}
  if not entry.path then return end
  entry.address=actor:GetAddress()
  entry.guest=id
  entry.session=guest.session
  hook(kind)
  local group=bindings[kind]
  if not group[entry.address]then size=size+1 end
  group[entry.address]=entry
 end
 function M.update(now)
  if size==0 or now<nextSweep then return end
  nextSweep=now+.5
  for _,group in pairs(bindings)do
   for address,entry in pairs(group)do
    if not targetFor(entry)or not valid(C.ObjectRefs.resolve(entry))then group[address]=nil;size=size-1 end
   end
  end
 end
 function M.count()return size end
 function M.reset()
  for kind in pairs(bindings)do bindings[kind]={}end
  size=0;nextSweep=0
 end
 return M
end
