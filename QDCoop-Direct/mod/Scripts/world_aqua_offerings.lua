-- Four distinct, valid offerings are the source of truth for this gate.
return function(valid,full,log)
 local M={}
 local classPath='/Game/RuinsLevel/AquaRuins/OfferingPuzzle/AqrStatuePuzzleDoor.AqrStatuePuzzleDoor_C'
 local plateClass='^AQ_OfferingPoint_BP_C '
 local gateClass='^AqrStatuePuzzleDoor_C '
 local warned={}
 local nextPoll,lastPoll=0,0

 local function idString(id)
  return string.format('%d,%d,%d,%d',id.A,id.B,id.C,id.D)
 end

 local function isPlate(a)
  return valid(a) and full(a):match(plateClass)~=nil
 end

 function M.repair(gate,save)
  if not valid(gate) or not full(gate):match(gateClass) or not valid(save) then return false end
  local states=save.SavableActorStates
  if #gate.GUIDs<1 or #gate.OfferingPlates~=4 then return false end
  local gateId=gate.GUIDs[1]
  if states:Contains(gateId) and states:Find(gateId):get()>0 then return false end

  local count,seen,source=0,{},nil
  for i=1,4 do
   local plate=gate.OfferingPlates[i]
   if not isPlate(plate) or #plate.GUIDs<1 then return false end
   local id=plate.GUIDs[1]
   local key=idString(id)
   if seen[key] then return false end
   seen[key]=true
   local filled=states:Contains(id) and states:Find(id):get()>0
   if filled then
    local items=save.SavableActorItems
    if not items:Contains(id) or not valid(plate.ContainedKey) then
     if not warned[key] then
      warned[key]=true
      log('WORLD offering receipt missing its item: '..full(plate)..' GUID='..key)
     end
     return false
    end
    local item=items:Find(id):get()
    if not valid(item) or full(item)~=full(plate.ContainedKey) or not plate.HasItem then return false end
    if plate:CheckUnlockConditions() then count=count+1;source=plate end
   elseif plate.HasItem then
    return false
   end
  end

  if count<4 then
   gate.CurrentActivationCount=count
   return false
  end
  -- Use the original completion path once. It saves before the delayed
  -- collapse, so another poll or a later load cannot replay completion.
  gate.CurrentActivationCount=3
  gate:Activate(false,source)
  if states:Contains(gateId) and states:Find(gateId):get()>0 then
   log('WORLD repaired offering gate from four saved items: '..full(gate))
   return true
  end
  return false
 end

 function M.poll(game,player,now,gs)
  if (now>=lastPoll and now<nextPoll) or not valid(game) or not valid(player) or not valid(game.ActiveSaveSlot) then return false end
  lastPoll=now;nextPoll=now+5
  local cls=StaticFindObject(classPath)
  if not valid(cls) then return false end
  local lm=FindFirstOf('FS_LevelManager')
  if valid(lm) and lm:IsProcessingLevelChanges(game) then return false end
  local list={}
  gs:GetAllActorsOfClass(game,cls,list)
  local changed=false
  for _,v in ipairs(list) do
   if M.repair(v:get(),game.ActiveSaveSlot) then changed=true end
  end
  return changed
 end

 -- The original restore fires Activate(true) on linked actors. In a guest
 -- snapshot, the authoritative gate receipt is applied separately.
 function M.restoreGuestPlate(a,restore)
  if not isPlate(a) then return restore() end
  local counts={}
  for i=1,#a.ActivationTarget do
   local target=a.ActivationTarget[i]
   if valid(target) and full(target):match(gateClass) and counts[target:GetAddress()]==nil then
    counts[target:GetAddress()]={actor=target,count=target.CurrentActivationCount}
    target.CurrentActivationCount=0
   end
  end
  local ok,err=pcall(restore)
  for _,entry in pairs(counts) do
   if valid(entry.actor) then entry.actor.CurrentActivationCount=entry.count end
  end
  if not ok then error(err,0) end
 end
 return M
end
