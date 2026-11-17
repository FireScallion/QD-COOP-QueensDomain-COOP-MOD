-- Repairs derived world progress only from original persisted receipts.
-- Never infers a spent key from the absence of an inventory item.
return function(valid,full,log,triggers)
 local M={}
 local nextPoll,lastPoll=0,0
 local function class(a,c)return valid(a) and full(a):match('^([^ ]+) ')==c end
 local function guid(g)return string.format('%d,%d,%d,%d',g.A,g.B,g.C,g.D)end
 local function value(save,a)
  if not valid(a) or #a.GUIDs<1 then return 0 end
  local id=a.GUIDs[1]
  return save.SavableActorStates:Contains(id) and save.SavableActorStates:Find(id):get() or 0
 end
 local function named(save,key)
  return save.NamedSaveData:Contains(FName(key)) and save.NamedSaveData:Find(FName(key)):get() or 0
 end
 local function restored(a)a.MySaveData:Empty();a:RestoreFromSave()end
 function M.restoreGuest(a,save,restore)
  if class(a,'LIB_BookRecepticle_BP_C') then
   local gates={}
   for i=1,#a.ActivationTarget do
    local t=a.ActivationTarget[i]
    if class(t,'Ros_Cage_Gate_BP_C') or class(t,'Lib_TreasureGate_BP_C') then
     local id=t:GetAddress()
     if not gates[id] then
      gates[id]={actor=t,scriptOpenable=t.ScriptOpenable}
      t.ScriptOpenable=false
     end
    end
   end
   local ok,err=pcall(restore)
   for _,g in pairs(gates) do if valid(g.actor) then g.actor.ScriptOpenable=g.scriptOpenable end end
   if not ok then error(err,0) end
   return
  end
  if not class(a,'SG_Pedestal_TridentKeyReceptacle_C') then return restore() end
  -- The manager's native Activate checks this flag before incrementing its
  -- private counter. Presentation refreshes must not solve/consume keys.
  local key=FName('StoneGardenPuzzleFinished');local map=save.NamedSaveData
  local existed=map:Contains(key);local old=existed and map:Find(key):get()
  map:Add(key,1)
  local ok,err=pcall(restore)
  if existed then map:Add(key,old) else map:Remove(key) end
  if not ok then error(err,0) end
 end
 local function slot(save,a,seen,consumed)
  if not valid(a) or #a.GUIDs<1 then return false end
  local id=a.GUIDs[1];local key=guid(id)
  if seen[key] then return false end;seen[key]=true
  if value(save,a)~=1 or not save.SavableActorItems:Contains(id) then return false end
  local item=save.SavableActorItems:Find(id):get()
  if not valid(item) or not valid(a.ContainedKey) or full(item)~=full(a.ContainedKey) then return false end
  if consumed and full(item):match(' /Game/Items/KeyItems/TridentKeys/TridentKey_Consumed_Data%.TridentKey_Consumed_Data$') then return true end
  return a.HasItem and a:CheckUnlockConditions()
 end
 function M.stone(a,save)
  if not class(a,'StoneGardenPuzzleScript_C') or not valid(save) or #a.GUIDs<1 then return false end
  local done=value(save,a)>0;local flag=named(save,'StoneGardenPuzzleFinished')>0
  if done and flag then return false end
  if not done and not flag then
   if #a.Pedestals~=5 then return false end
   local seen={}
   for i=1,5 do
    local p=a.Pedestals[i]
    if not class(p,'SG_Pedestal_TridentKeyReceptacle_C') or not slot(save,p,seen,true) then return false end
   end
   -- The five native item receipts prove completion. Avoid refeeding the
   -- transient Blueprint counter, which may already contain partial counts.
   a:ConsumePedestalKeys()
  end
  a['Save Data Index to World Save'](a,0,1)
  save.NamedSaveData:Add(FName('StoneGardenPuzzleFinished'),1)
  restored(a)
  log('WORLD repaired Stone Garden completion: '..full(a))
  return true
 end
 function M.cage(a,save,books)
  if not class(a,'Ros_Cage_Gate_BP_C') or not valid(save) or #a.GUIDs<1 then return false end
  if value(save,a)>0 or named(save,'ROSBookPuzzleComplete')>0 then
   if named(save,'ROSBookPuzzleComplete')>0 and value(save,a)>0 then return false end
   a['Save Data Index to World Save'](a,0,1)
   save.NamedSaveData:Add(FName('ROSBookPuzzleComplete'),1);restored(a)
   return true
  end
  local count,seen=0,{}
  for _,p in ipairs(books) do
   if class(p,'LIB_BookRecepticle_BP_C') then
    local linked=false
    for i=1,#p.ActivationTarget do
     local t=p.ActivationTarget[i]
     if valid(t) and t:GetAddress()==a:GetAddress() then linked=true end
    end
    if linked then
     if not slot(save,p,seen,false) then return false end
     count=count+1
    end
   end
  end
  if count~=4 then return false end
  -- Old-save repair uses the saved-state path; current host inserts retain
  -- their native animation. This cannot increment the gate a fifth time.
  a['Save Data Index to World Save'](a,0,1)
  save.NamedSaveData:Add(FName('ROSBookPuzzleComplete'),1);restored(a)
  log('WORLD repaired RoS cage from four saved books: '..full(a))
  return true
 end
 function M.network(a)return class(a,'ElecNodeNetwork_C') end
 function M.finishNetwork(a,save)
  if not M.network(a) or not valid(save) or value(save,a)~=1 or a.Finished then return false end
  if not valid(a.ElecNodeNetworkScript) then return false end
  -- Same original completion callback as solving the circuit. Finished is
  -- set before its save and activation loop, so snapshots cannot replay it.
  a:BndEvt__ElecNodeNetwork_ElecNodeNetworkScript_K2Node_ComponentBoundEvent_0_AllActive__DelegateSignature()
  return a.Finished
 end
 function M.nearNetwork(a,peer)
  if not M.network(a) or not valid(a.ElecNodeNetworkScript) then return false end
  local near=false
  local queue,seen={a.AnyNodeInNetwork},{}
  local at=1
  while at<=#queue and at<=256 do
   local node=queue[at];at=at+1
   if valid(node) then
    local id=node:GetAddress()
    if not seen[id] then
     seen[id]=true
     local p=node:K2_GetActorLocation()
     if (p.X-peer.X)^2+(p.Y-peer.Y)^2+(p.Z-peer.Z)^2<=1200^2 then near=true;break end
     for i=1,#node.ConnectedNodes do queue[#queue+1]=node.ConnectedNodes[i] end
    end
   end
  end
  return near
 end
 local paths={
  stone='/Game/RuinsLevel/StoneGarden/StoneGardenPuzzleScript.StoneGardenPuzzleScript_C',
  cage='/Game/RuinsLevel/SecretZones/RoS/MovingShit/Ros_Cage_Gate_BP.Ros_Cage_Gate_BP_C',
  books='/Game/Items/KeyItems/BookKeys/LIB_BookRecepticle_BP.LIB_BookRecepticle_BP_C',
  network='/Game/OtherWorld/OW_MK/NodeKit/ElecNodeNetwork.ElecNodeNetwork_C',
  triggers='/Game/Blueprints/ActivationTrigger.ActivationTrigger_C'
 }
 function M.poll(game,player,now,gs)
  if now>=lastPoll and now<nextPoll then return false end
  lastPoll=now;nextPoll=now+5
  if not valid(game) or not valid(player) or not valid(game.ActiveSaveSlot) then return false end
  local lm=FindFirstOf('FS_LevelManager')
  if valid(lm) and lm:IsProcessingLevelChanges(game) then return false end
  local function actors(key)
   local cls=StaticFindObject(paths[key]);local out,list={},{}
   if valid(cls) then gs:GetAllActorsOfClass(game,cls,out) end
   for _,v in ipairs(out) do local a=v:get();if valid(a) then list[#list+1]=a end end
   return list
  end
  local save,changed=game.ActiveSaveSlot,false
  for _,a in ipairs(actors('stone')) do if M.stone(a,save) then changed=true end end
  local cages=actors('cage')
  if #cages>0 then local books=actors('books');for _,a in ipairs(cages) do if M.cage(a,save,books) then changed=true end end end
  for _,a in ipairs(actors('network')) do if M.finishNetwork(a,save) then changed=true end end
  if triggers then
   for _,a in ipairs(actors('triggers')) do if triggers.repairKitchen(a,save) then changed=true end end
  end
  return changed
 end
 return M
end
