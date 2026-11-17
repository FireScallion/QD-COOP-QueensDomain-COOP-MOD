-- Only audited placed triggers may ask the host to run their native chain.
-- No client-supplied function names or target lists are executed.
return function(valid,full)
 local M={}
 local specs={
  ['D6A75747-4AD845FD-F12580A4-DF49F8BC']='ChefCrowEventScript_C',
  ['6EE8FF6F-42563AB7-FD8418B5-7205D021']='Boner_ShrineBoss_Spawner_C',
  ['CA806C96-43DADAFE-E0326BBF-3FC80FB4']='ActivatableNamedSaveDataSetter_C',
  ['8F14B8B1-41F310A7-8C5003A5-25E9951C']='LargeRobot_Rusted_Spawner_C'
 }
 local function key(a)
  local g=a.GUIDs[1]
  return string.format('%08X-%08X-%08X-%08X',g.A & 0xffffffff,g.B & 0xffffffff,g.C & 0xffffffff,g.D & 0xffffffff)
 end
 function M.supports(a)
  if not valid(a) or not full(a):match('^ActivationTrigger_C ') or #a.GUIDs<1 then return false end
  local expected=specs[key(a)]
  if expected then
   if #a.ActivationTargets~=1 then return false end
   local target=a.ActivationTargets[1]
   return valid(target) and full(target):match('^([^ ]+) ')==expected
  end
  if a.OnlyOnce and not a.DisableSaveOnlyOnce then return false end
  -- Carry the source trigger across ActivatableGroup, which otherwise drops
  -- ActorThatTriggered. Unknown targets and cyclic groups are rejected.
  local seen,group={},false
  local function safe(t,depth)
   if not valid(t) or depth>8 then return false end
   local c=full(t):match('^([^ ]+) ')
   if c=='ActivatableGroup_C' then
    local id=t:GetAddress();if seen[id] then return false end
    seen[id]=true;group=true
    if #t.ActivationTargets==0 then return false end
    for i=1,#t.ActivationTargets do if not safe(t.ActivationTargets[i],depth+1) then return false end end
    return true
   end
   return t:IsA('/Game/Blueprints/Door_Base.Door_Base_C') or c=='FS_Light_Activatable_C' or c=='ActivatableSound_C'
  end
  for i=1,#a.ActivationTargets do if not safe(a.ActivationTargets[i],0) then return false end end
  return group
 end
 function M.near(a,peer)
  if not M.supports(a) then return false end
  local component=a.BoxMode and a.Box or a.Sphere
  if not valid(component) then return false end
  local p=component:K2_GetComponentLocation()
  local radius
  if a.BoxMode then local e=component:GetScaledBoxExtent();radius=math.sqrt(e.X^2+e.Y^2+e.Z^2)
  else radius=component:GetScaledSphereRadius() end
  return (p.X-peer.X)^2+(p.Y-peer.Y)^2+(p.Z-peer.Z)^2<=(radius+300)^2
 end
 function M.activate(a)
  if not M.supports(a) then return false end
  if a.OnlyOnce and a.HasAlreadybeenTriggered then return false end
  a:DoTrigger()
  return true
 end
 function M.repairKitchen(a,save)
  if not valid(a) or #a.GUIDs<1 or key(a)~='CA806C96-43DADAFE-E0326BBF-3FC80FB4' or not M.supports(a) then return false end
  local id=a.GUIDs[1];local name=FName('PlayerReachedKitchen')
  if not save.SavableActorStates:Contains(id) or save.SavableActorStates:Find(id):get()~=1 then return false end
  if save.NamedSaveData:Contains(name) and save.NamedSaveData:Find(name):get()>0 then return false end
  -- This exact placed trigger only sets PlayerReachedKitchen=1. Do not
  -- replay historic enemy spawns or cutscenes as a generic save repair.
  a.ActivationTargets[1]:Activate(true,a)
  return save.NamedSaveData:Contains(name) and save.NamedSaveData:Find(name):get()>0
 end
 return M
end
