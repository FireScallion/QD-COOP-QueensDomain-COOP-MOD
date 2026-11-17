return function(dir, C, P, valid, full, write, log, checkpoint, worldSync)
 local M = {}
 local room=C.RoomProtocol==2 and dofile(dir..'rescue_room.lua')(C,write)or nil
 local duration, range = 2.6, 235
 local playerClass = '/Game/Player/FS_PlayerChar.FS_PlayerChar_C:'
 local saveFunctions = '/Game/Blueprints/SaveSystem/SaveFunctions.Default__SaveFunctions_C'
 local gs = StaticFindObject('/Script/Engine.Default__GameplayStatics')
 local system = StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')
 local items, codes = {}, {}
 local context, down, charge, reservation, wipe, leaving
 local downSerial, attemptSerial = 0, 0
 local pendingDown, restoreBar = false, false
 local held, attempted = false, false
 local progress = 0
 local aimed = false
 local diagnostic = ''
 local transaction, persistence, rescuePeer, peerLife, peerLifeDown
 local readyOffer
 local pendingNativeReceipt
 local nextHello=0
 local cancelPending,recoveryError,nextRecovery,loggedRecovery=nil,nil,0,0
 local nextRecoveryStatus=0
 local function recovery(fn,force)
  if not force and os.clock()<nextRecovery then return false end
  local ok,result=pcall(fn)
  if ok then recoveryError=nil;nextRecovery=0;return true,result end
  recoveryError=tostring(result);nextRecovery=os.clock()+.5
  if os.clock()-loggedRecovery>=5 then
   loggedRecovery=os.clock();log('RESCUE recovery waiting: '..recoveryError)
   write('rescue-recovery-error.txt',recoveryError..'\n')
  end
  return false
 end

 -- These six item objects and their level indices come from UseHealingItem.
 for _, group in ipairs({
  {'/Game/Items/Consumables/HealingPotion/', 'HealingPotion', 'ApplyHealingPotion'},
  {'/Game/Items/Consumables/Herb/', 'HealingHerb', 'ApplyHerb'},
 }) do
  for level = 0, 2 do
   local name = group[2] .. ({'', '_02', '_03'})[level + 1]
   local asset = group[1] .. name .. '.' .. name
   items[#items + 1] = {method = group[3], level = level, asset=asset}
   codes[asset] = #items
  end
 end

 persistence=dofile(dir..'rescue_persistence.lua')(dir,C,valid,full,items)
 local Transactions=dofile(dir..'rescue_transactions.lua')
 local function life()return down and context and(context.epoch..'_down_'..down.id)or'-'end
 local function pendingCommit()local a=transaction and transaction.active();return a and a.phase=='C'end

 local function status()
  local text = string.format(
   'role=%s down=%d peerDown=%d progress=%.3f phase=%s held=%s identity=%s partner=%s\n%s\n',
   C.Role, down and down.id or 0, context and context.peerDown or 0,
   progress, charge and charge.phase or pendingCommit()and'settling'or wipe and 'wipe' or 'idle', tostring(held), transaction and transaction.identity()or'-',rescuePeer or'-',diagnostic)
  if text ~= M.lastStatus then
   write('rescue-status.txt', text)
   M.lastStatus = text
  end
 end

 local function report(text)
  diagnostic = text
  log('RESCUE ' .. text)
  status()
 end

 local function send(action, target, attempt, value)
  if room then return room.send(context,room.peers[context.peerId],action,target,attempt,value)end
  write('out.events', table.concat({
   'RV', context.world, context.epoch, context.peer, action, target, attempt, value or '-'
  }, '|') .. '\n', true)
 end

 local function samePlayer(p)
  return context and valid(context.player) and full(p) == full(context.player)
 end

 local function cancelCharge()
  if charge and charge.phase=='offered' then cancelPending=charge.id end
  charge, progress = nil, 0
 end

 local function count(item)
  if not valid(item) then return 0 end
  local inventory=context.gi.ActiveSaveSlot.InventoryContents
  local entry = inventory:Contains(item) and inventory:Find(item)
  return entry and entry:get() or 0
 end

 local function selected()
  local item = context.gi.ActiveSaveSlot.SelectedConsumable
  local name = valid(item) and full(item):match(' (/Game/.*)$') or ''
  return item, name, codes[name] or 0
 end

 local function near(peer)
  local a, b = context.player:K2_GetActorLocation(), peer and peer.position or context.peerPosition
  return b and (a.X-b.x)^2 + (a.Y-b.y)^2 + (a.Z-b.z)^2 <= range^2
 end

 local function canRescue(peer)
  local p = context.player
  if down or pendingDown or not context.ready or(peer and peer.down or context.peerDown or 0)==0 then return false, 'partner state changed' end
  if not near(peer) then return false, 'out of range' end
  if p.IsInGameplayModal or p.PlayerInteractionComponent.DisableInteraction or not p:CanInteractFlags() then return false, 'interaction unavailable' end
  local manager = gs:GetPlayerCameraManager(p, 0)
  if not valid(manager) then return false, 'camera unavailable' end
  local start = manager:GetCameraLocation()
  local b = peer and peer.position or context.peerPosition
  local rot = p:GetControlRotation()
  local yaw, pitch = math.rad(rot.Yaw), math.rad(rot.Pitch)
  local dx, dy, dz = b.x-start.X, b.y-start.Y, b.z-62-start.Z
  local along = dx*math.cos(pitch)*math.cos(yaw) + dy*math.cos(pitch)*math.sin(yaw) + dz*math.sin(pitch)
  if along < 0 or dx*dx+dy*dy+dz*dz-along*along > 65^2 then return false, 'aim at partner' end
  return not system:LineTraceSingle(p, start, {X=b.x,Y=b.y,Z=b.z-58},
   0, false, {p}, 0, {}, true, {R=0,G=0,B=0,A=0}, {R=0,G=0,B=0,A=0}, 0), 'obstructed'
 end

 local function selectPeer()
  if not room or not context then return end
  local peer=room.pick(charge and charge.peerId,function(p)
   local ok=canRescue(p);local a=context.player:K2_GetActorLocation();local b=p.position
   return ok,(a.X-b.x)^2+(a.Y-b.y)^2+(a.Z-b.z)^2
  end)
  context.peerId=peer and peer.id;context.peer=peer and peer.epoch
  context.peerPosition=peer and peer.position;context.peerDown=peer and peer.down or 0
  rescuePeer=peer and peer.identity;peerLife=peer and peer.life;peerLifeDown=peer and peer.lifeDown
 end

 local function beginCharge()
  if not context or recoveryError or charge or(transaction and transaction.active())or not transaction or not rescuePeer or peerLifeDown~=context.peerDown or peerLife=='-'or not held or attempted or context.peerDown == 0 then return end
  local allowed, reason = canRescue()
  if not allowed then diagnostic = 'cannot rescue: '..reason;return end
  local item, name, code = selected()
  if code > 0 and count(item) < 1 then code = 0 end
  attemptSerial = attemptSerial + 1
  attempted = true
  diagnostic = ''
  charge = {phase='holding', id=attemptSerial, target=context.peerDown, selection=name,peerId=context.peerId,
   item=code, started=context.now, health=context.player.Health, life=peerLife, recipient=rescuePeer}
  progress = .001
  status()
 end

 local function unlock()
  local old = down
  down = nil
  if not old then return end
  if valid(old.gi) then old.gi:UnBlockSuspendSaves() end
  if not valid(old.player) then return end
  local p = old.player
  if valid(old.controller) then old.controller:SetIgnoreMoveInput(false) end
  p.bUseControllerRotationYaw = old.followYaw
  if valid(old.camera) then old.camera:K2_SetRelativeLocation(old.cameraLocation,false,{},true) end
  p.IsDead = false
  p.bCanBeDamaged = old.damage
  p.Arms:SetVisibility(old.arms, false)
  p.CharacterMovement:SetMovementMode(old.mode == 0 and 1 or old.mode, 0)
 end

 local function offerCharge(a)
  if a.phase~='holding' then return end
  -- Completion belongs to the local hold clock, not the network round trip.
  -- Once full, releasing E or moving the crosshair must not revoke the offer.
  a.phase,a.expires='offered',context.now+30
  local ok,serial=recovery(function()return transaction and transaction.begin(a.recipient,a.life,a.item)end)
  if ok and serial then a.id=serial;report('charge complete; awaiting rescue confirmation')else cancelCharge()end
 end

 local function enterDown()
  local p = context.player
  pendingDown = false
  if down then return end
  downSerial = downSerial + 1
  down = {id=downSerial, player=p, gi=context.gi, controller=p:GetController(),
   damage=p.bCanBeDamaged, arms=p.Arms:IsVisible(), mode=p.CharacterMovement.MovementMode,
   followYaw=p.bUseControllerRotationYaw, yaw=p:K2_GetActorRotation().Yaw,
   camera=p.FirstPersonCamera, cameraLocation={X=p.FirstPersonCamera.RelativeLocation.X,Y=p.FirstPersonCamera.RelativeLocation.Y,Z=p.FirstPersonCamera.RelativeLocation.Z}, started=context.now}
  cancelCharge()
  down.gi:BlockSuspendSaves()
  p:CancelCurrentAttacks()
  p:CureAllNegativeEffects()
  p.bCanBeDamaged = false
  p.IsDead = true
  p.bUseControllerRotationYaw = false
  if valid(down.controller) then down.controller:SetIgnoreMoveInput(true) end
  if not p.CharacterMovement:IsFalling() then
   p.CharacterMovement:StopMovementImmediately()
   p.CharacterMovement:DisableMovement()
  end
  p.Arms:SetVisibility(false, false)
  p['Set Health Points'](p, 0)
  report('downed ' .. down.id)
 end

 local function revive(code)
  local p = context.player
  unlock()
  if code == 0 then
   p['Set Health Points'](p, 1)
  else
   local item = items[code]
   p[item.method](p, item.level)
   if p.Health <= 0 then p['Set Health Points'](p, 1) end
  end
  report(string.format('revived item=%d hp=%.3f', code, p.Health))
 end

 function M.localFrame(now)
  if not context or not valid(context.player) then return end
  -- ReceiveTick and Tick Camera can both dispatch in the same engine frame.
  if M.localFrameAt==now then return end;M.localFrameAt=now
  context.now = now
  if down and valid(down.camera) then
   local p = down.player
   p.bUseControllerRotationYaw=false
   p:K2_SetActorRotation({Pitch=0,Yaw=down.yaw,Roll=0},true)
   local alpha = math.min(1, math.max(0, (now-down.started)/.72))
   alpha = alpha*alpha*(3-2*alpha)
   local origin = p:K2_GetActorLocation()
   local yaw = math.rad(down.yaw)
   local height = p.CapsuleComponent:GetScaledCapsuleHalfHeight()
   local start = down.cameraLocation
   down.camera:K2_SetWorldLocation({
    X=origin.X + math.cos(yaw)*54*alpha,
    Y=origin.Y + math.sin(yaw)*54*alpha,
    Z=origin.Z + start.Z*(1-alpha) + (20-height)*alpha
   },false,{},true)
  end
  selectPeer()
  aimed = context.ready and canRescue() or false
  -- InteractHeld is the native mapped action, including E and controller input.
  -- Charge is local and requires the mapped interaction action to stay held.
  local pressed = context.player.InteractHeld == true
  if pressed and not held then attempted=false end
  held=pressed
  if not held and charge and charge.phase=='holding' then cancelCharge();diagnostic='charge interrupted: released';status()end
  beginCharge()
  if charge and charge.phase=='holding' then
   if not aimed then cancelCharge()
   else progress=math.min(1,(now-charge.started)/duration);if progress==1 then offerCharge(charge)end end
  end
 end

 function M.install(register)
  register('/Game/Player/Assets/Input/FS_HUD.FS_HUD_C:CanInteractHighlight',function(ctx,p,result)
   if aimed and samePlayer(p:get())then result:set(true)end
  end)
  register(playerClass..'Tick Camera',function(ctx)
   if samePlayer(ctx:get())then M.localFrame(gs:GetRealTimeSeconds(context.player))end
  end)
  local function look(ctx,value,pitch,mouse)
   local p=ctx:get()
   if not down or not samePlayer(p) or p.IsInGameplayModal then return end
   local mult=pitch and p:GetVerticalInputMultiplier(mouse) or p['Get Horizontal Input Multiplier'](p,mouse)
   local scale=mouse and p.MouseSensitivity or (pitch and p.BaseLookUpRate or p.BaseTurnRate)*gs:GetWorldDeltaSeconds(p)
   if pitch then p:AddControllerPitchInput(value:get()*scale*mult)
   else p:AddControllerYawInput(value:get()*scale*mult)end
  end
  register(playerClass..'InpAxisEvt_LookUpMouse_K2Node_InputAxisEvent_2',function(ctx,v)look(ctx,v,true,true)end)
  register(playerClass..'InpAxisEvt_TurnMouse_K2Node_InputAxisEvent_3',function(ctx,v)look(ctx,v,false,true)end)
  register(playerClass..'HandlePitchInput',function(ctx,v)look(ctx,v,true,false)end)
  register(playerClass..'HandleYawInput',function(ctx,v)look(ctx,v,false,false)end)
  register(playerClass .. 'Set Health Points', function(ctx)
   local p = ctx:get()
   if samePlayer(p) and context.armed and not down and not p.IsDead and p.Health <= 0 then
    -- Both native damage paths test Health immediately after this Blueprint
    -- returns. Defer movement and HUD work out of that call stack.
    p.Health = 1
    pendingDown = true
   elseif down and samePlayer(p) and p.Health ~= 0 then
    p.Health = 0
   end
  end)
  register('/Game/UI/HUD/Widgets/StatusCluster.StatusCluster_C:UpdatePowerMeter', function(ctx)
   if progress == 0 and not restoreBar then return end
   local widget = ctx:get()
   if not context or not samePlayer(widget.PlayerChar) then return end
   local material = widget.PowerMeterFill:GetDynamicMaterial()
   if not valid(material) then return end
   material:SetScalarParameterValue(FName('ChargeFill'), progress)
   material:SetScalarParameterValue(FName('ChargeActive'), progress >= 1 and 1 or 0)
   restoreBar = progress > 0
  end)
 end

 function M.reset()
  M.localFrameAt=nil
  unlock()
  worldSync.cancelRollback()
  cancelCharge()
  context, reservation, wipe, leaving = nil, nil, nil, nil
  pendingDown, restoreBar, diagnostic = false, false, ''
  held, attempted, aimed = false, false, false
  transaction=nil;persistence.reset();rescuePeer,peerLife,peerLifeDown=nil,nil,nil;nextHello=0
  if room then room.reset()end
  pendingNativeReceipt=nil
  cancelPending=nil
  status()
 end

 function M.id()
  return down and down.id or 0
 end


 readyOffer=function(t)
  local a=charge
  if not a or a.phase~='offered'or a.id~=t.serial or a.life~=t.life or a.item~=t.code or a.recipient~=t.recipient then
   if transaction then transaction.cancel(t.serial)end;return
  end
  if down or pendingDown or not context.ready or not near()or context.peerDown~=a.target then cancelCharge();report('completed rescue cancelled: recipient or rescuer changed');return end
  if t.code>0 and persistence.inventory(t.code)<1 then cancelCharge();report('completed rescue cancelled: medicine unavailable');return end
  if transaction.commit(t.serial)then charge,progress=nil,0;report('durable rescue sent item='..t.code)end
 end

 local function sendTransaction(op,t)
  if not context or not context.ready then return end
  if room then
   local recipient=transaction.identity()==t.donor and t.recipient or t.donor
   return room.send(context,room.find(recipient),op,t.donor,t.serial,table.concat({t.recipient,t.life,t.code},'~'))
  end
  write('out.events',table.concat({'RV',context.world,context.epoch,context.peer,op,t.donor,t.serial,
   table.concat({t.recipient,t.life,t.code},'~')},'|')..'\n',true)
 end
 local function bindPersistence(gi,player)
  local b,fresh=persistence.bind(gi,player)
  if not fresh and transaction then return end
  pendingNativeReceipt=nil
  transaction=Transactions(b.store,{
   now=os.clock,send=sendTransaction,balance=persistence.adjust,inventory=persistence.inventory,life=life,forget=persistence.forget,
   receipt=function(t)
    if pendingNativeReceipt and pendingNativeReceipt.donor==t.donor and pendingNativeReceipt.serial==t.serial then
     persistence.applied(t);pendingNativeReceipt=nil;return true
    end
    return persistence.receipt(t)
   end,
   ready=function(t)readyOffer(t)end,
   prepare=function(t)
    local peer=room and room.find(t.donor)
    return context and context.ready and life()==t.life and(room and peer and peer.down==0 or not room and context.peerDown==0)and near(peer)and not wipe
   end,
   apply=function(t)
    if not context or life()~=t.life then return false end
    local old=down;local ok,err=pcall(revive,t.code)
    if not down and context.player.Health>0 then
     pendingNativeReceipt=t;persistence.applied(t);pendingNativeReceipt=nil;return true
    end
    if not down then
     -- A failed native healing callback must not leave an unlocked zero-HP pawn.
     enterDown();down.id=old.id;downSerial=math.max(downSerial,old.id)
    end
    if not ok then report('rescue heal retry: '..tostring(err))end
    return false
   end,
  })
  transaction.recoverPrepared()
 end

 local function identity(s)return type(s)=='string'and #s<=150 and s:match('^[%w_%-]+$')end
 function M.event(fields)
  if #fields~=9 or fields[2]~='RV'or not context or not context.ready then return end
  if fields[3]~=context.world or fields[5]~=context.epoch then return end
  local source=room and room.source(fields)
  if room and not source or not room and fields[4]~=context.peer then return end
  local action,value=fields[6],fields[9]
  if action=='HELLO2'then
   local n=P.number(fields[8],0,1e9)
   if identity(fields[7])and n and n%1==0 and(value=='-'or P.id(value))then
    if room then source.identity=fields[7];source.lifeDown=n;source.life=value else rescuePeer,peerLifeDown,peerLife=fields[7],n,value end
    if transaction then recovery(function()transaction.poll(room and room.identities()or rescuePeer)end)end
   end;return
  end
  if action:match('^[PRCDXNA]2$')then
   local sender=source and source.identity or rescuePeer
   if not transaction or not sender then return end
   local who,token,code=value:match('^([^~]+)~([^~]+)~(%d+)$');local serial=P.number(fields[8],1,1e9);code=tonumber(code)
   if identity(fields[7])and identity(who)and P.id(token)and serial and serial%1==0 and code and code>=0 and code<=#items then
    -- A rejection may itself resolve a missing-item debit. Do not let the
    -- background retry backoff starve the response which repairs that failure.
    local ok=recovery(function()transaction.event(action,{donor=fields[7],recipient=who,life=token,code=code,serial=serial},sender)end,true)
    if not ok then return'retry'end
   end;return
  end
  -- Legacy RV is retained only for the existing shared-checkpoint wipe flow.
  -- Mixed versions cannot enter a drug-consuming rescue without HELLO2.
  local target,attempt=P.number(fields[7],1,1e9),P.number(fields[8],1,1e9)
  if not target or not attempt or target%1~=0 or attempt%1~=0 then return end
  if room then
   if action=='WPREP'and C.Role=='client'and source.id==C.Room.host and M.id()==target and source.down==attempt then
    if not wipe or wipe.id~=value then
     local save=value~='-'and checkpoint.open(value)
     if not save or pendingCommit()or not worldSync.stageRollback(save)then room.send(context,source,'WFAIL',target,attempt,value);return end
     wipe={id=value,target=target,attempt=attempt};report('guest checkpoint prepared '..value)
    end
    room.send(context,source,'WREADY',target,attempt,value)
   elseif C.Role=='host'and wipe and wipe.id==value and M.id()==attempt then
    local expected=wipe.members and wipe.members[source.id]
    if expected and expected.epoch==source.epoch and expected.down==target then
     if action=='WREADY'then wipe.ready[source.id]=true elseif action=='WFAIL'then wipe.failed=true end
    end
   end
   return
  end
  if action=='WPREP'and C.Role=='client'and M.id()==target and context.peerDown==attempt then
   if not wipe then
    local save=value~='-'and checkpoint.open(value)
    if not save or not worldSync.stageRollback(save)then send('WFAIL',target,attempt,value);return end
    wipe={id=value,target=target,attempt=attempt};report('guest checkpoint prepared '..value)
   end
   if wipe.id==value then send('WREADY',target,attempt,value)end
  elseif action=='WREADY'and C.Role=='host'and wipe and wipe.id==value and wipe.target==target and M.id()==attempt then wipe.go=true
  elseif action=='WFAIL'and C.Role=='host'and wipe and wipe.id==value and wipe.target==target and M.id()==attempt then wipe.failed=true
  elseif action=='EXIT'and C.Role=='client'and M.id()==target then leaving=context.now+.2 end
 end
 function M.busy()return pendingNativeReceipt~=nil or charge~=nil or pendingCommit()==true end
 worldSync.setRollbackListener(function(save)persistence.rollback(save);transaction=nil;rescuePeer,peerLife=nil,nil end)

 local function exitRoom()
  gs:OpenLevel(context.gi, FName('/Game/LD45/Maps/title_screen'), true, '')
  return true
 end

 function M.poll(gi, player, world, epoch, connected, frame, stable, now)
  recovery(function()
   bindPersistence(gi,player)
   if cancelPending and transaction then transaction.cancel(cancelPending);cancelPending=nil end
  end)
  if not connected then
   if transaction then recovery(function()transaction.poll(nil)end)end
   if down then
    if C.Role == 'client' then return exitRoom() end
    unlock()
    player:Kill(false)
   end
   if context then M.reset() end
   return false
  end
  if room then
   room.update(world,now)
   if not context or context.epoch~=epoch then
    context={player=player,gi=gi,world=world,epoch=epoch,peerDown=0};cancelCharge();wipe,leaving=nil,nil;nextHello=0
   end
   context.player,context.gi=player,gi;context.now=now
   local any=false;for _,p in pairs(room.peers)do if p.ready then any=true;break end end
   context.ready=any and(stable or down~=nil);context.armed=any and stable
   if C.Role=='client'and wipe then
    local host=room.peers[C.Room.host]
    if not host or not host.ready or host.down~=wipe.attempt or M.id()~=wipe.target then wipe=nil;worldSync.cancelRollback()end
   end
   selectPeer()
   if not context.ready then cancelCharge();status();return false end
  else
  if not frame and context and now-context.seenAt <= 8 then frame = context.lastFrame end
  if not frame or not frame.T or frame.P.world ~= world then
   if context then context.ready, context.armed = false, false end
   if not down then cancelCharge() end
   return false
  end
  if not context or context.peer ~= frame.T.session or context.epoch ~= epoch then
   if not down and not stable then return false end
   context = {player=player, gi=gi, world=world, epoch=epoch, peer=frame.T.session}
   cancelCharge()
   reservation, wipe, leaving = nil, nil, nil
   rescuePeer,peerLife,peerLifeDown=nil,nil,nil;nextHello=0
  end
  if not context.lastFrame or frame.T.seq ~= context.lastFrame.T.seq then
   context.lastFrame, context.seenAt = frame, now
  end
  if now-context.seenAt > 8 then
   context.ready, context.armed = false, false
   cancelCharge()
   status()
   return false
  end
  context.ready, context.armed = stable or down ~= nil, stable
  context.now, context.peerPosition, context.peerDown = now, frame.P, frame.downed or 0
  end
  if pendingDown then enterDown(); context.ready = true end
  if down and player.CharacterMovement.MovementMode ~= 0 and not player.CharacterMovement:IsFalling() then
   player.CharacterMovement:DisableMovement()
  end
  if leaving and now >= leaving then return exitRoom() end
  if transaction then
   recovery(function()transaction.poll(room and room.identities()or rescuePeer)end)
   if pendingCommit()and charge then charge,progress=nil,0 end
   if os.clock()>=nextHello then
    if room then for _,p in pairs(room.peers)do room.send(context,p,'HELLO2',transaction.identity(),M.id(),life())end
    else write('out.events',table.concat({'RV',context.world,context.epoch,context.peer,'HELLO2',transaction.identity(),M.id(),life()},'|')..'\n',true)end
    nextHello=os.clock()+.8
   end
   if os.clock()>=nextRecoveryStatus then
    nextRecoveryStatus=os.clock()+1
    local s=transaction.inspect();local rows={'id='..transaction.identity(),'out='..(s.out or'-'),'closed='..(s.closed or'0'),'error='..(recoveryError or'')}
    for i=1,6 do rows[#rows+1]='balance'..i..'='..(s['b'..i]or'0');rows[#rows+1]='revision'..i..'='..(s['r'..i]or'0');rows[#rows+1]='quantity'..i..'='..(s['n'..i]or'-')end
    for k,v in pairs(s)do if k:sub(1,2)=='i:'then rows[#rows+1]=k..'='..v end end
    write('rescue-recovery-status.txt',table.concat(rows,'\n')..'\n')
   end
  end
  if charge then
   local item, name = selected()
   local a = charge
   local allowed, reason = canRescue()
   if (a.phase=='holding' and (not player.InteractHeld or not allowed or name ~= a.selection
    or (a.item > 0 and count(item) < 1) or player.Health < a.health - .1))
    or context.peerDown ~= a.target or (a.expires and now > a.expires) then
    cancelCharge()
    report('charge interrupted: ' .. (not allowed and reason or 'state or selection changed'))
   elseif a.phase == 'holding' then
    a.health = math.max(a.health, player.Health)
    progress = math.min(1, (now - a.started)/duration)
    if progress == 1 then
     offerCharge(a)
    end
   end
  end
  if room and C.Role=='host'then
   local members=down and not leaving and not pendingCommit()and room.allDown()
   if wipe and(not members or not room.sameDown(wipe.members))then wipe=nil;worldSync.cancelRollback()end
   if members then
    if not wipe then wipe={id=checkpoint.latest()or'-',members=members,ready={},retry=0,expires=now+10}end
    local ready=true;for id in pairs(members)do if not wipe.ready[id]then ready=false end end
    if ready and not wipe.failed then
     local save=checkpoint.open(wipe.id)
     if save and worldSync.rollbackHost(save)then return true end
     wipe.failed=true
    end
    if wipe.failed or wipe.id=='-'or now>wipe.expires then
     if now>=wipe.retry then wipe.id=checkpoint.latest()or'-';wipe.failed=nil;wipe.ready={};wipe.retry=now+2;wipe.expires=now+10;report('checkpoint not ready; retrying without leaving room')end
    elseif now>=wipe.retry then
     for id,p in pairs(members)do if not wipe.ready[id]then room.send(context,room.peers[id],'WPREP',p.down,down.id,wipe.id)end end
     wipe.retry=now+1
    end
   end
  elseif not room and C.Role == 'host' and down and context.peerDown > 0 and not leaving and not pendingCommit() and not reservation then
   if not wipe then
    local id = checkpoint.latest()
    wipe = {id=id or '-', target=context.peerDown, attempt=down.id, retry=0, expires=now+10}
   end
   if wipe.go and not wipe.failed then
    local save = checkpoint.open(wipe.id)
    if save then
     report('loading shared checkpoint ' .. wipe.id)
     if worldSync.rollbackHost(save) then return true end
    end
    wipe.failed = true
   end
   if wipe.failed or wipe.id == '-' or now > wipe.expires then
    if now >= wipe.retry then
     report('checkpoint not ready; retrying without leaving room')
     wipe.id=checkpoint.latest()or'-';wipe.failed=nil;wipe.go=nil
     wipe.retry=now+2;wipe.expires=now+10
    end
   elseif now >= wipe.retry then
    send('WPREP', wipe.target, wipe.attempt, wipe.id)
    wipe.retry = now+1
   end
  end
  status()
  return false
 end

 M.localFrame=C.Perf.measure(M.localFrame,'rescue.localFrame')
 return M
end
