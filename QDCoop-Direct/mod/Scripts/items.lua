return function(dir,C,P,valid,full,write,log,checkpoint,L)
 local R=dofile(dir..'item_records.lua')
 local gs=StaticFindObject('/Script/Engine.Default__GameplayStatics')
 local system=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')
 local visual=dofile(dir..'item_visuals.lua')(valid,full,gs,system)
 local M={};local ctx,peerId,identity,room,saveName,character
 local peers=dofile(dir..'item_peers.lua')(C)
 local custodyIdentity=dofile(dir..'item_identity.lua')(dir,C)
 local drops,escrow,receipts,winners={},{},{},{}
 local actors,byActor,claims,ui={},{},{},{}
 local serial,nextSync,nextScan=0,0,0
 local queuedPlace,queuedClaim,dirty,message
 local itemCache={}
 local fastDrops,notices={},{};local stateSerial=0
 local dynamicMenu=dofile(dir..'dynamic_menu.lua')
 -- Diagnostic snapshots only: native IPC retains/retries each queued write.
 -- Do not rewrite identical files every tick; gameplay journals bypass this cache.
 local diagnosticCache={}
 local function diagnostic(name,text)
  if diagnosticCache[name]~=text then write(name,text);diagnosticCache[name]=text end
 end
 local functions='/Game/Blueprints/SaveSystem/SaveFunctions.Default__SaveFunctions_C'
 local inspectPath='/Game/UI/Widgets/FS_InspectItem.FS_InspectItem_C:'
 local itemClass=StaticFindObject('/Game/Blueprints/ItemSystem/FS_ItemData.FS_ItemData_C')
 local function asset(o)return valid(o)and full(o):match(' (/Game/.*)$')or ''end
 local function report(s)message=s;log('ITEMS '..s)end
 local function save()return ctx and ctx.gi.ActiveSaveSlot end
 local function count(item)local m=save().InventoryContents;local e=m:Contains(item)and m:Find(item);return e and e:get()or 0 end
 local function mark(key,value)R.set(save(),key,value);dirty=true;nextScan=0 end
 local function send(op,value,recipient)
  recipient=recipient or peers.host();local peer=peers.peers[recipient]
  if ctx and ctx.connected and peer then
   local prefix=C.RoomProtocol==2 and C.Role=='host'and('TO|'..recipient..'|')or''
   write('out.events',prefix..table.concat({'IT',ctx.world,ctx.epoch,peer.epoch,op,value or '-'},'|')..'\n',true)
  end
 end
 local function itemFor(path)
  if not path or not path:match('^/Game/Items/[%w_/%.-]+$')or #path>250 then return end
  local item=itemCache[path];if not valid(item)then item=LoadAsset(path);itemCache[path]=item end
  if not valid(itemClass)then itemClass=StaticFindObject('/Game/Blueprints/ItemSystem/FS_ItemData.FS_ItemData_C')end
  if not valid(item)or not item:IsA(itemClass)or item.ShowInKeyMenu or path:find('/KeyItems/',1,true)or path:find('/Upgrades/',1,true)then return end
  if not item.Equippable and not item.Consumable then return end
  return item
 end
 -- Weapons, ranged weapons and charms are Equippable in the native item data.
 -- Keep resolving legacy records so their original owner can recover them.
 local function placeable(item)return item and item.Consumable and not item.Equippable and not item.Unstackable end
 local function scan()
  drops,escrow,receipts,winners,character,room=R.scan(save())
  -- A reliable host result need not wait for the sliced world snapshot.
  -- These overrides live only in this room/map epoch; the host save remains authoritative.
  for id,r in pairs(fastDrops)do if r.room==room then drops[id]=r end end
  if not R.id(character)then character=C.RunId;mark('QDCoopPersonal~id~'..character,1)end
  identity=custodyIdentity(character)
  if C.Role=='host'and not R.id(room)then room=C.RunId;mark('QDCoopRoom~'..room,1)end
 end
 local function closeUI(w)
  if valid(w)then w:CloseInspectModal()end
  if ctx and valid(ctx.player.CurrentGameMenu)then
   local menu=ctx.player.CurrentGameMenu;menu:UpdateInventory();menu:RefreshEquipSlotsAndStats()
  end
 end
 local function available()
  return ctx and ctx.connected and ctx.stable and not ctx.player.IsDead and ctx.player.Health>0 and peers.hasReady()and R.id(room)
 end
 local function custodyBusy()
  for id,r in pairs(drops)do if r.state==1 then return true end end
  for id,r in pairs(escrow)do if r.room==room and not drops[id]then return true end end
  return queuedPlace~=nil or queuedClaim~=nil
 end
 function M.busy()return custodyBusy()end
 local function placementFull()
  -- Include unacknowledged local drops and in-flight awards without counting
  -- the same durable ID twice. Independent drops do not share a settlement lock.
  local n=0
  for _,r in pairs(drops)do if r.state~=2 then n=n+1 end end
  for id,r in pairs(escrow)do if r.room==room and not drops[id]then n=n+1 end end
  return n>=64
 end
 local function checkpointBusy()return checkpoint.busy and checkpoint.busy()end
 local function ground()
  local p=ctx.player;local pos=p:K2_GetActorLocation();local yaw=p:GetControlRotation().Yaw
  local angle=math.rad(yaw);local x,y=pos.X+95*math.cos(angle),pos.Y+95*math.sin(angle)
  local hit={};local clear=not system:LineTraceSingle(p,{X=pos.X,Y=pos.Y,Z=pos.Z},{X=x,Y=y,Z=pos.Z},0,false,{p},0,hit,true,{},{},0)
  if not clear then return end
  hit={};if not system:LineTraceSingle(p,{X=x,Y=y,Z=pos.Z+30},{X=x,Y=y,Z=pos.Z-240},0,false,{p},0,hit,true,{},{},0)then return end
  local h=hit.OutHit or hit;local q=h.ImpactPoint
  if not q then return end
  return {X=q.X,Y=q.Y,Z=q.Z+12},yaw
 end
 local function unequip(item,before)
  if before>1 then return end
  local slots={};save().EquipmentSlots:ForEach(function(k,v)if full(v:get())==full(item)then slots[#slots+1]=k:get()end end)
  local maths=StaticFindObject('/Game/Player/Assets/Blueprints/PlayerMathFunctions.Default__PlayerMathFunctions_C')
  for _,id in ipairs(slots)do local out={};maths:GetSlotTypeAndIndexFromID(id,ctx.player,out,out);ctx.player:UnequipItem(item,out.Index)end
  if #slots>0 then
   local still=false;save().EquipmentSlots:ForEach(function(_,v)if full(v:get())==full(item)then still=true end end)
   assert(not still,'Equipped item could not be released')
  end
 end
 local function register(r)
  if drops[r.id]then if drops[r.id].raw~=r.raw then return false end;notices[r.id]=true;return true end
  mark(R.prefix..r.raw,0);r.state=0;drops[r.id]=r;notices[r.id]=true;return true
 end
 local function place(w,item)
  if not available()or checkpointBusy()then report('Waiting for connection or save settlement');return end
  local path=type(item)=='string'and item or asset(item);item=itemFor(path)
  if not placeable(item)then report('Only stackable consumables can be placed');return end
  if not item or count(item)<1 then report('Item is unavailable '..path..' resolved='..tostring(valid(item))..' count='..tostring(item and count(item)));return end
  if placementFull()then report('Pick up an existing placed item first');return end
  local p,yaw=ground();if not p or not visual.template(item)then report('No safe ground or original item model');return end
  serial=serial+1
  local raw=R.encode(C.RunId..'_'..serial,identity,room,path,ctx.world,p,yaw);local r=assert(R.decode(raw))
  -- Construct before consuming, so a missing model can never eat inventory.
  local actor=visual.create(ctx.player,r,item);if not valid(actor)then return end
  local before=count(item)
  local ok,err=pcall(function()
   unequip(item,before)
   StaticFindObject(functions):TryConsumingItemFromInventory(system:Conv_ObjectToSoftObjectReference(item),1,ctx.player,{})
   assert(count(item)==before-1,'Inventory deduction failed')
  end)
  if not ok then visual.destroy(actor);report(tostring(err));return end
  mark('QDCoopPersonal~place~'..raw,1);escrow[r.id]=r
  actors[r.id]=actor;byActor[full(actor)]=r.id
  if C.Role=='host'then register(r)else send('PUT',raw)end
  ctx.player:RefreshSelectedConsumable();closeUI(w)
  report('Placed one '..path)
 end
 local function nearby(r,position)
  if not position or r.map~=ctx.world then return false end
  local x,y,z=position.X or position.x,position.Y or position.y,position.Z or position.z
  if not x or (x-r.x)^2+(y-r.y)^2+(z-r.z)^2>250^2 then return false end
  return not system:LineTraceSingle(ctx.player,{X=x,Y=y,Z=z},{X=r.x,Y=r.y,Z=r.z+18},0,false,{ctx.player,actors[r.id]},0,{},true,{},{},0)
 end
 local function grant(r)
  if receipts[r.id]then return true end
  local item=itemFor(r.item);if not item then return false end
  if not placeable(item)and r.owner~=identity and r.owner~=character then report('Equipment transfer disabled; original owner may recover this item');return false end
  local before=count(item);if (item.Unstackable or item.Equippable)and before>0 then return false end
  StaticFindObject(functions):AddItemToInventory(system:Conv_ObjectToSoftObjectReference(item),1,ctx.player)
  if count(item)~=before+1 then return false end
  mark('QDCoopPersonal~got~'..r.id,1);receipts[r.id]=true
  ctx.player:RefreshSelectedConsumable()
  report('Picked up one '..r.item)
  return true
 end
 local function finish(r)
  r.state=2;mark(R.prefix..r.raw,2);notices[r.id]=true
 end
 local function reject(r)
  local who=winners[r.id];if who then mark('QDCoopWinner~'..r.id..'~'..who,0)end
  winners[r.id]=nil;r.state=0;mark(R.prefix..r.raw,0);notices[r.id]=true
 end
 local function claim(id,who,position,recipient,legacy)
  local r=drops[id]
  if not r or r.state~=0 or not available()or checkpointBusy()or not nearby(r,position)then return end
  local item=itemFor(r.item)
  if not item or(not placeable(item)and who~=r.owner and legacy~=r.owner)then report('Equipment transfer disabled; original owner may recover this item');return end
  winners[id]=who;mark('QDCoopWinner~'..id..'~'..who,1);r.state=1;mark(R.prefix..r.raw,1);notices[id]=true
  if recipient=='local'then if grant(r)then finish(r)else reject(r);report('This unique item is already owned')end
  else send('GRANT',r.raw,recipient)end
 end
 function M.event(f)
  if #f~=7 or f[2]~='IT'or not ctx or not ctx.connected or f[3]~=ctx.world or f[5]~=ctx.epoch then return end
  local peer,sender=peers.source(f)
  if not peer then return'retry'end
  if f[4]~=peer.epoch or(C.Role=='client'and sender~=peers.host())then return end
  local op,s=f[6],f[7]
  if op=='STATE'and C.Role=='client'then
   local revision,state,raw=s:match('^(%d+)~([012])~(.+)$');revision=tonumber(revision)
   local r=raw and R.decode(raw)
   if r and r.room==room and revision and revision>0 and revision<=1e9 then
    local old=fastDrops[r.id];if not old or revision>old.revision then
     if old and old.raw~=r.raw then return end
     r.state=tonumber(state);r.revision=revision;fastDrops[r.id]=r;drops[r.id]=r
    end
   end
   return
  end
  if op=='HELLO'then
   local id,char=s:match('^([^~]+)~([^~]+)$');id=id or s;char=char or s
   if R.id(id)and R.id(char)then peer.identity=id;peer.character=char;peerId=id end;return
  end
  -- UDP delivery can precede HELLO or an in-progress checkpoint. Keep the
  -- unapplied request in the event mailbox; transport ACK is not settlement.
  if not peer.identity then return'retry'end
  if op=='PUT'and C.Role=='host'then
   local r=R.decode(s);if r and(r.owner==peer.identity or r.owner==peer.character)and r.room==room then
    local existing=drops[r.id]
    if placeable(itemFor(r.item))or(existing and existing.raw==r.raw)then register(r)end
   end
  elseif op=='CLAIM'and C.Role=='host'and R.id(s)then
   local r=drops[s]
   if r and r.state==0 and(not available()or checkpointBusy())then return'retry'end
   claim(s,peer.identity,peer.position,sender,peer.character)
  elseif op=='GRANT'and C.Role=='client'then
   local r=R.decode(s);if not r or r.room~=room then return end
   -- The host owns the award. A late grant still settles after leaving range.
   if grant(r)then send('GOT',r.id)else send('REJECT',r.id)end
  elseif C.Role=='host'and(op=='GOT'or op=='REJECT')then
   local r=drops[s];if r and r.state==1 and peers.winner(winners[s],identity,character)==sender then if op=='GOT'then finish(r)else reject(r)end end
  end
 end
 local function mount(w)
  if ui[full(w)]then return end
  dynamicMenu(w)
  local rows,labels={},{};ui[full(w)]={widget=w,rows=rows,labels=labels,languageRevision=L.revision}
  for _,pair in ipairs({{'ConsumableActions','UseButton'}})do
   local parent,original=w[pair[1]],w[pair[2]]
   local button=StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary'):Create(ctx.gi,original:GetClass(),ctx.player:GetController())
   button:SetStyle(original.Style)
   local label=StaticConstructObject(StaticFindObject('/Script/CommonUI.CommonTextBlock'),button.WidgetTree)
   label:SetFont(w.ConfirmButtonText.Font);label:SetJustification(1);label:SetText(FText(L.get('place')))
   local center=StaticConstructObject(StaticFindObject('/Script/UMG.Border'),button.WidgetTree)
   center:SetBrushColor({R=1,G=1,B=1,A=0});center:SetPadding({Left=0,Top=0,Right=0,Bottom=0});center:SetHorizontalAlignment(0);center:SetVerticalAlignment(2)
   center:AddChild(label);button.Subcontent:AddChild(center);labels[#labels+1]=label
   local children={};for i=0,parent:GetChildrenCount()-1 do local child=parent:GetChildAt(i);children[#children+1]={child=child,padding=child.Slot.Padding}end
   parent:ClearChildren()
   for _,old in ipairs(children)do parent:AddChildToVerticalBox(old.child):SetPadding(old.padding);if full(old.child)==full(original)then parent:AddChildToVerticalBox(button):SetPadding(old.padding)end end
   rows[#rows+1]=button
  end
 end
 function M.install(register)
  register(inspectPath..'OpenForItem',function(c)if ctx and ctx.connected then mount(c:get())end end)
  register('/Game/UI/UI_Style/FS_Button.FS_Button_C:BP_OnClicked',function(c)
   if not available()then return end
   for _,entry in pairs(ui)do if valid(entry.widget)and entry.widget.IsOpen then for _,b in ipairs(entry.rows)do if full(b)==full(c:get())then queuedPlace={widget=full(entry.widget),item=asset(entry.widget.CurrentItem)};return end end end end
  end)
  register('/Game/QDCoop/QDCoopPlacedItem.QDCoopPlacedItem_C:Interact',function(c)
   if available()then queuedClaim=byActor[full(c:get())]end
  end)
 end
 function M.poll(gi,player,world,epoch,connected,frame,stable,now)
  L.refresh()
  if not valid(gi.ActiveSaveSlot)then return end
  if not ctx or ctx.epoch~=epoch or saveName~=full(gi.ActiveSaveSlot)then
   M.reset(false);ctx={gi=gi,player=player,world=world,epoch=epoch};saveName=full(gi.ActiveSaveSlot);scan()
  end
  ctx.connected=connected;ctx.stable=stable;ctx.now=now;ctx.player=player
  if not connected then peerId=nil;ctx.peer=nil;peers.reset()else peers.refresh(frame,world,now)end
  if frame and frame.P.world==world then
   if ctx.peer~=frame.T.session then peerId=nil end
   ctx.peer=frame.T.session;ctx.position=frame.P;ctx.seen=now
  elseif C.RoomProtocol~=2 and(not ctx.seen or now-ctx.seen>1)then ctx.stable=false end
  if now>=nextScan then scan();nextScan=now+.3 end
  if queuedPlace then local q=queuedPlace;queuedPlace=nil;place(StaticFindObject(q.widget:match(' (.+)$')),q.item)end
  if queuedClaim then local id=queuedClaim;queuedClaim=nil;if available()then if C.Role=='host'then claim(id,identity,player:K2_GetActorLocation(),'local',character)else send('CLAIM',id)end end end
  if connected and now>=nextSync then
   if C.Role=='host'then for id in pairs(peers.peers)do send('HELLO',identity..'~'..character,id)end else send('HELLO',identity..'~'..character)end
   if peers.hasReady()and room then
    for id,r in pairs(escrow)do if r.room==room then if drops[id]then if drops[id].state==2 then mark('QDCoopPersonal~place~'..r.raw,2)end elseif C.Role=='client'then send('PUT',r.raw)elseif C.Role=='host'then register(r)end end end
    if C.Role=='host'then for id,r in pairs(drops)do if r.state==1 then
     local recipient=peers.winner(winners[id],identity,character)
     if recipient=='local'then if grant(r)then finish(r)else reject(r)end
     elseif recipient then send('GRANT',r.raw,recipient)end
    end end end
   end
   nextSync=now+1
  end
  local seen={}
  if connected then for id,r in pairs(drops)do if r.map==world and r.state==0 and not receipts[id]then
   seen[id]=true;if not valid(actors[id])then local item=itemFor(r.item);if item then local a=visual.create(player,r,item);if valid(a)then actors[id]=a;byActor[full(a)]=id end end end
  end end end
  for id,a in pairs(actors)do if not seen[id]and not(escrow[id]and not drops[id]and connected)then byActor[full(a)]=nil;visual.destroy(a);actors[id]=nil end end
  local uiState='closed'
  for key,entry in pairs(ui)do
   if not valid(entry.widget)then ui[key]=nil else
    if entry.languageRevision~=L.revision then for _,l in ipairs(entry.labels)do if valid(l)then l:SetText(FText(L.get('place')))end end;entry.languageRevision=L.revision end
    local item=entry.widget.CurrentItem;local supported=placeable(itemFor(asset(item)));local allowed=entry.widget.IsOpen and available()and not checkpointBusy()and not placementFull()and supported and count(item)>0
    for _,b in ipairs(entry.rows)do if valid(b)then b:SetIsEnabled(allowed==true);b:SetVisibility(connected and supported and 0 or 1)end end
    if entry.widget.IsOpen then
     uiState=allowed and 'ready' or not connected and 'disconnected' or not ctx.stable and 'world-loading' or checkpointBusy()and 'checkpoint-settlement' or placementFull()and 'placement-capacity' or not supported and 'unsupported-item' or count(item)<=0 and 'empty-stack' or 'player-or-peer-unavailable'
    end
   end
  end
  if dirty and not player.IsDead then gi:GI_WriteSuspendSaveImmediately(true);dirty=false end
  -- Publish only after the native custody save call succeeds. Gameplay grants
  -- still use GRANT/GOT and inventory receipts, never a cosmetic prediction.
  if C.Role=='host'and not dirty then for id in pairs(notices)do local r=drops[id]
   if r then stateSerial=stateSerial+1;for recipient in pairs(peers.peers)do send('STATE',stateSerial..'~'..r.state..'~'..r.raw,recipient)end end
   notices[id]=nil
  end end
  diagnostic('items-status.txt',string.format('identity=%s peer=%s room=%s busy=%s ui=%s\n%s\n',identity or '-',peerId or '-',room or '-',tostring(custodyBusy()),uiState,message or ''))
  local lines={};for id,r in pairs(drops)do lines[#lines+1]=id..'|'..r.state..'|'..(winners[id]or '-')..'|'..r.item..'|'..(valid(actors[id])and full(actors[id])or '-')end;table.sort(lines);diagnostic('placed-items.txt',table.concat(lines,'\n'))
 end
 function M.reset(travel)
  diagnosticCache={}
  if not travel then for _,a in pairs(actors)do visual.destroy(a)end end
  ctx,peerId,identity,room,saveName,character=nil,nil,nil,nil,nil,nil;peers.reset()
  actors,byActor,claims,ui,drops,escrow,receipts,winners={},{},{},{},{},{},{},{}
  queuedPlace,queuedClaim,dirty=nil,nil,false;nextSync,nextScan=0,0
  fastDrops,notices={},{};stateSerial=0
 end
 return M
end
