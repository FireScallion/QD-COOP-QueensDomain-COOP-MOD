-- Native title entry, OptionsMenu frame and complete native save/new-game flow.
return function(C,P,read,write,log,worldSync,L)
 local steam=dofile(debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')..'steam_menu.lua')(debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])'),C,read,log,L)
 local M={};local title,entry,entryLabel,panel,box,heading,frame,message,ip,port
 local divider,dividerPadding
 local titleNotice,mountRetryAt
 local phase='home';local queued;local hooks={};local optionsHook=false;local suppressClose=false
 local joiningSteam=false
 local controls,labels={},{};local request='';local generation,started=0,0
 local joinAddress,joinPort,hostPort='127.0.0.1','47771','47771'
 local seats=math.max(2,math.min(4,C.MaxPlayers or 2))
 local preferences=dofile(debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')..'join_preferences.lua')
 local preferencesFile=C.Ipc..'/../last-join.txt'
 local savedAddress,savedPort=preferences.load(preferencesFile);if savedAddress then joinAddress,joinPort=savedAddress,savedPort end
 local lastRejectedFrame;local lastConnected=0;local lastHostFrame,lastHostFrameAt;local statusKey,statusArgs;local revision=-1
 local status
 local titlePath='/Game/UI/Title/TitleScreenUI.TitleScreenUI_C:'
 local optionsPath='/Game/UI/Menus/OptionsMenu.OptionsMenu_C:'
 local function valid(o)return o and o:IsValid()end
 local titleConstructHook
 local function same(a,b)return valid(a)and valid(b)and a:GetFullName()==b:GetFullName()end
 local function hook(path,fn)
  assert(valid(StaticFindObject(path)),'Missing native UI function '..path)
  local a,b=RegisterHook(path,fn)
  assert(type(a)=='number' and a>=0 and type(b)=='number' and b>=0,'Native UI hook registration returned invalid handles for '..path)
  hooks[#hooks+1]={path,a,b}
 end
 local function create(kind,owner)return StaticConstructObject(StaticFindObject('/Script/'..kind),(owner or panel or title).WidgetTree)end
 local function findText(o)
  if o:IsA('/Script/CommonUI.CommonTextBlock')then return o end
  if o:IsA('/Script/UMG.PanelWidget')then for i=0,o:GetChildrenCount()-1 do local t=findText(o:GetChildAt(i));if t then return t end end end
 end
 local function label(key,template,owner)
  -- Match native buttons: center the desired-size widget in its slot. A filled
  -- text layout with Center justification can drift at the game's UI scale.
  local w=create('CommonUI.CommonTextBlock',owner);w:SetStyle(template.Style);w:SetFont(template.Font);w:SetJustification(0);w:SetText(FText(L.get(key)));return w
 end
 local function clearTitleNotice()
  if valid(titleNotice)then titleNotice:RemoveFromParent()end
  titleNotice=nil
 end
 local function menuError(stage,key,err)
  local detail='MENU '..stage..' failed: '..tostring(err)
  log(detail)
  pcall(write,'menu-error.txt',detail..'\n')
  pcall(status,key)
  local ok,why=pcall(function()
   if not valid(title)then return end
   if not valid(titleNotice)then
    local template=assert(findText(title.LoadGameButton.Subcontent),'Native title text template missing')
    titleNotice=label(key,template,title)
    titleNotice:SetAutoWrapText(true)
    titleNotice:SetJustification(1)
    local slot=title.LoadGameButton:GetParent():AddChildToVerticalBox(titleNotice)
    slot:SetHorizontalAlignment(2);slot:SetPadding({Left=0,Top=8,Right=0,Bottom=0})
   end
   titleNotice:SetText(FText(L.get(key)))
  end)
  if not ok then log('MENU could not display title notice: '..tostring(why))end
 end
 local function focus(w)
  if valid(w)then local u=StaticFindObject('/Game/UI/UIUtilFuncs.Default__UIUtilFuncs_C');u['FS Set Focus'](u,w,true,title)end
 end
 local function button(key,fn,template,parent,height)
  local b=StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary'):Create(title,template:GetClass(),title:GetOwningPlayer())
  b:SetStyle(template.Style);b.SpecialSounds=template.SpecialSounds
  local l=label(key,assert(findText(template.Subcontent)),b);local center=create('UMG.Border',b)
  center:SetBrushColor({R=1,G=1,B=1,A=0});center:SetPadding(template.Subcontent:GetChildAt(0).Padding);center:SetHorizontalAlignment(2);center:SetVerticalAlignment(2);center:AddChild(l);b.Subcontent:AddChild(center)
  local translation=findText(template.Subcontent).RenderTransform.Translation;l:SetRenderTranslation({X=translation.X,Y=translation.Y})
  if parent then local size=create('UMG.SizeBox');size:SetHeightOverride(height or 45);size:AddChild(b);local s=parent:AddChildToVerticalBox(size);s:SetHorizontalAlignment(0)end
  controls[b:GetFullName()]={b=b,fn=fn};labels[#labels+1]={w=l,key=key};return b,l
 end
 local function addText(key,height)
  local l=label(key,assert(findText(panel.TopLevel_AudioButton.Subcontent)));l:SetAutoWrapText(false);if height and height>50 then l.WrapTextAt=440 end
  local size=create('UMG.SizeBox');if height then size:SetHeightOverride(height)end;local slot=size:AddChild(l);slot:SetHorizontalAlignment(2);slot:SetVerticalAlignment(2)
  box:AddChildToVerticalBox(size):SetPadding({Left=16,Top=4,Right=16,Bottom=4});labels[#labels+1]={w=l,key=key};return l
 end
 local function field(value)
  local e=create('UMG.EditableTextBox');e.WidgetStyle.Font=findText(panel.TopLevel_AudioButton.Subcontent).Font;e:SetJustification(0);e:SetText(FText(value))
  -- Center the input's desired width too, including symmetric click padding.
  -- It grows with the address instead of justifying text across a filled row.
  e.WidgetStyle.Padding.Left=16;e.WidgetStyle.Padding.Right=16
  local size=create('UMG.SizeBox');size:SetHeightOverride(40);local slot=size:AddChild(e);slot:SetHorizontalAlignment(2);slot:SetVerticalAlignment(2);box:AddChildToVerticalBox(size):SetPadding({Left=35,Top=2,Right=35,Bottom=8});return e
 end
 status=function(key,...)
  statusKey=key;statusArgs={...};local s=key and L.get(key,...)or''
  if valid(message)then message:SetText(FText(s))end;write('menu-status.txt',s)
 end
 local function send(role,address,p,slot)
  lastRejectedFrame=nil;lastHostFrame,lastHostFrameAt=nil,nil;generation=generation+1;write('in.state','');write('status.txt','')
  if role=='host'then role=C.MenuTransport=='steam'and'host-steam'or'host-lan'end
  request=table.concat({role,address,p,slot,C.RunId..'-'..generation,seats,C.RoomProtocol or 1},'|');write('session.request',request);log('MENU room request transport='..role)
 end
 local function cancelJoin()worldSync.ended();write('session.request','');C.Role='menu' end
 local roomCodec=C.RoomProtocol==2 and dofile(debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')..'room_protocol.lua')or nil
 local function hostFrame()
  if read('session.ready')~=request then return end
  local network=read('status.txt')
  if network:match('^connected|')then lastConnected=os.time()elseif network~=''or os.time()-lastConnected>2 then return end
  local raw=read('in.state')
  if roomCodec then local room=roomCodec.decode(raw);raw=room and room.frames[room.host]or''end
  local f=P.frame(raw);if f then lastHostFrame,lastHostFrameAt=f,os.clock();return f end
  if raw~='' and not lastRejectedFrame then lastRejectedFrame=true;log('MENU connected but host state rejected; bytes='..#raw)end
  if lastHostFrameAt and os.clock()-lastHostFrameAt<2 then return lastHostFrame end
 end
 local dir=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
 local dynamicMenu=dofile(dir..'dynamic_menu.lua')
 local friendPanel=dofile(dir..'steam_friends_panel.lua')(dir,C,read,write,log,L,steam.requestJoin,steam.avatar)
 steam.onInvite(function(pause)
  if pause.InOptions or pause.ModalOpen then return end
  pause:OpenOptions();friendPanel.open(pause.ActiveOptionsMenu,'invite')
 end)
 local skinMenu=dofile(dir..'skin_menu.lua')(C,L,C.SkinCatalog,C.SkinSelection,create,button,function(key,template,owner)return label(key,assert(findText(template.Subcontent)),owner)end,valid,log)
 local show
 local function clearPanelState()
  panel,box,heading,frame,message,ip,port,divider,dividerPadding=nil,nil,nil,nil,nil,nil,nil,nil,nil
  controls={};labels={}
  if valid(entry)then controls[entry:GetFullName()]={b=entry,fn='choose'}end
 end
 local function closePanel()
  skinMenu.close()
  if valid(panel)and panel:IsInViewport()then
   suppressClose=true
   local ok,err=pcall(function()panel:CloseMenu()end)
   suppressClose=false
   if not ok then error(err,0)end
  end
  clearPanelState()
 end
 local function openPanel()
  if valid(panel)and panel:IsInViewport()then return end
  -- The original event binds close/focus restoration and controller hints.
  -- Customize only its fresh instance; ordinary Options remains unchanged.
  local instance=FindFirstOf('FS_GameInstance_C');assert(valid(instance),'Game instance unavailable')
  local old=instance.CurrentOptionsMenu
  local ok,err=pcall(function()
   title.BndEvt__TitleScreenUI_Options_K2Node_ComponentBoundEvent_4_CommonButtonBaseClicked__DelegateSignature(title,title.Options)
  end)
  local created=instance.CurrentOptionsMenu
  if valid(created)and (not same(old,created)or ok)then panel=created end
  assert(ok,err)
  assert(valid(panel)and panel:IsInViewport(),'Native options panel missing or not in viewport')
  dynamicMenu(panel)
  frame=panel.OptionsSelectMenu:GetChildAt(0);local canvas=frame:GetChildAt(0)
  for i=0,canvas:GetChildrenCount()-1 do local w=canvas:GetChildAt(i);if w:IsA('/Script/UMG.VerticalBox')then box=w elseif w:IsA('/Script/CommonUI.CommonTextBlock')then heading=w end end
  assert(valid(box)and valid(heading),'Native options layout changed')
  divider=box:GetChildAt(0);assert(divider:IsA('/Script/UMG.Image'),'Native options divider changed');local pad=divider.Slot.Padding;dividerPadding={Left=pad.Left,Top=pad.Top,Right=pad.Right,Bottom=pad.Bottom}
  if not optionsHook then hook(optionsPath..'CloseMenu',function(ctx)
   if same(ctx:get(),panel)and not suppressClose then
    if phase=='waiting'or phase=='join_prepare'or phase=='join'then cancelJoin()end
    queued=phase=='choose'and'home'or'choose'
   end
  end);optionsHook=true end
 end
 local function showSaves(role)
  closePanel();phase=role=='host'and'host_save'or'join_save'
  title.BndEvt__TitleScreenUI_LoadGameButton_K2Node_ComponentBoundEvent_0_CommonButtonBaseClicked__DelegateSignature(title,title.LoadGameButton)
  title.SaveScreenTitle:SetText(FText(L.get(role=='host'and'host_save'or'guest_save')))
  status(role=='client'and'connected'or nil)
 end
 local function joinFailed(key)
  cancelJoin();if valid(title)and title.InSaveMenu then title:CloseModal();title:BackToMainMenu()end
  queued=nil;show(joiningSteam and'choose'or'join');status(joiningSteam and'steam_room_error'or key)
 end
 local function readPort(widget)
  local n=tonumber(widget:GetText():ToString());if not n or n%1~=0 or n<1024 or n>65535 then status('invalid_port');return end;return n
 end
 local function seatPicker(screen)
  local row=create('UMG.HorizontalBox')
  local function cell(widget,width)local s=create('UMG.SizeBox');s:SetWidthOverride(width);s:SetHeightOverride(45);s:AddChild(widget);row:AddChildToHorizontalBox(s)end
  local less=button('skin_previous',function()if valid(port)then hostPort=port:GetText():ToString()end;seats=math.max(2,seats-1);show(screen)end,panel.TopLevel_VideoButton)
  local more=button('skin_next',function()if valid(port)then hostPort=port:GetText():ToString()end;seats=math.min(C.RoomProtocol==2 and 4 or 2,seats+1);show(screen)end,panel.TopLevel_VideoButton)
  less:SetIsEnabled(seats>2);more:SetIsEnabled(C.RoomProtocol==2 and seats<4)
  local value=label('loading',findText(panel.TopLevel_VideoButton.Subcontent));value:SetText(FText(L.get('room_seats',seats)))
  labels[#labels+1]={w=value,key='room_seats',args={seats}}
  local centered=create('UMG.Border');centered:SetBrushColor({R=1,G=1,B=1,A=0});centered:SetHorizontalAlignment(2);centered:SetVerticalAlignment(2);centered:AddChild(value)
  cell(less,55);cell(centered,210);cell(more,55);box:AddChildToVerticalBox(row):SetHorizontalAlignment(2)
 end
 show=function(screen)
  if screen=='home'then closePanel();phase='home';status(nil);focus(entry);return end
  openPanel();phase=screen;controls={};labels={};box:ClearChildren();ip,port=nil,nil
  box:AddChildToVerticalBox(divider):SetPadding(dividerPadding)
  local key=screen=='choose'and'multiplayer'or((screen=='host'or screen=='host_steam')and'host'or'join')
  heading:SetText(FText(L.get(key)));labels[#labels+1]={w=heading,key=key};local first
  if screen=='choose'then
   first=button('host_steam',function()C.MenuTransport='steam';show('host_steam')end,panel.TopLevel_VideoButton,box)
   button('join_steam',function()
    closePanel();title.BndEvt__TitleScreenUI_Options_K2Node_ComponentBoundEvent_4_CommonButtonBaseClicked__DelegateSignature(title,title.Options)
    friendPanel.open(FindFirstOf('FS_GameInstance_C').CurrentOptionsMenu,'join',function()queued='choose'end)
   end,panel.TopLevel_VideoButton,box)
   button('host_lan',function()C.MenuTransport='lan';show('host')end,panel.TopLevel_VideoButton,box)
   button('join_lan',function()show('join')end,panel.TopLevel_VideoButton,box)
   button('back',function()show('home')end,panel.TopLevel_VideoButton,box)
  elseif screen=='host'then
   addText('host_port',30);port=field(hostPort)
   seatPicker(screen)
   first=button('host',function()local n=readPort(port);if n then hostPort=tostring(n);C.MenuPort=n;showSaves('host')end end,panel.TopLevel_VideoButton,box)
   button('back',function()show('choose')end,panel.TopLevel_VideoButton,box)
  elseif screen=='host_steam'then
   seatPicker(screen)
   first=button('choose_save',function()if steam.available()then C.MenuPort=tonumber(hostPort);showSaves('host')else status('steam_unavailable')end end,panel.TopLevel_VideoButton,box)
   button('back',function()show('choose')end,panel.TopLevel_VideoButton,box)
  else
   addText('host_address',30);ip=field(joinAddress);addText('port',30);port=field(joinPort)
   first=button('connect',function()
    if phase~='join'then return end
    local addr=ip:GetText():ToString();local count,good=0,true
    for part in addr:gmatch('[^.]+')do count=count+1;if not part:match('^%d+$')or tonumber(part)>255 then good=false end end
    if not good or count~=4 or not addr:match('^%d+%.%d+%.%d+%.%d+$')then status('invalid_ip');return end
    local n=readPort(port);if not n then return end
    joiningSteam=false;joinAddress,joinPort=addr,tostring(n);if not preferences.save(preferencesFile,joinAddress,joinPort)then log('MENU could not persist join address')end;C.Role='client';phase='waiting';started=os.time();send('client',addr,n,0);status('joining')
   end,panel.TopLevel_VideoButton,box)
   addText('address_hint',110);button('back',function()joinAddress=ip:GetText():ToString();joinPort=port:GetText():ToString();cancelJoin();show('choose')end,panel.TopLevel_VideoButton,box)
  end
  message=label('loading',findText(panel.TopLevel_AudioButton.Subcontent));message:SetAutoWrapText(false);message.WrapTextAt=440;message:SetText(FText(''))
  local msgSize=create('UMG.SizeBox');msgSize:SetHeightOverride(110);local msgSlot=msgSize:AddChild(message);msgSlot:SetHorizontalAlignment(2);msgSlot:SetVerticalAlignment(2);box:AddChildToVerticalBox(msgSize):SetPadding({Left=18,Top=5,Right=18,Bottom=5})
  local height=(screen=='choose'or screen=='host'or screen=='host_steam')and 440 or 680
  frame.Slot:SetSize({X=516,Y=height});box.Slot:SetAnchors({Minimum={X=0,Y=0},Maximum={X=1,Y=1}});box.Slot:SetAlignment({X=0,Y=0});box.Slot:SetOffsets({Left=0,Top=68,Right=0,Bottom=10})
  panel.LastSelectedWidget=first;focus(first);status(nil)
  local ok,err=xpcall(function()skinMenu.open(panel,frame,panel.TopLevel_VideoButton)end,debug.traceback)
  if not ok then
   pcall(skinMenu.close)
   frame.Slot:SetPosition({X=0,Y=0})
   log('MENU skin preview unavailable: '..tostring(err))
  end
  clearTitleNotice()
 end
 local function runMenuAction(action)
  local ok,err=xpcall(function()
   if type(action)=='string'then show(action)else action()end
  end,debug.traceback)
  if ok then return true end
  local closed,why=pcall(closePanel)
  if not closed then
   log('MENU panel cleanup failed: '..tostring(why))
   if valid(panel)then pcall(function()panel:RemoveFromParent()end)end
   clearPanelState()
  end
  if phase=='waiting'or phase=='join_prepare'or phase=='join_save'then pcall(cancelJoin)end
  phase='home';queued=nil
  pcall(focus,entry)
  menuError('open/action','menu_open_failed',err)
  return false
 end
 local function clearHooks()
  for _,h in ipairs(hooks)do pcall(UnregisterHook,h[1],h[2],h[3])end
  hooks={};optionsHook=false
 end
 local function mount(t)
  if not titleConstructHook then
   -- The native delete progress bar ships with designer Percent=0.5 and red
   -- fill. Reset before first paint, not after travel's gameplay warm-up.
   -- Keep the hook across UI resets; normal hold-to-delete updates stay native.
   titleConstructHook={RegisterHook(titlePath..'Construct',function(ctx)local p=ctx:get().DeleteProgress;if valid(p)then p:SetPercent(0)end end)}
  end
  if valid(t.DeleteProgress)then t.DeleteProgress:SetPercent(0)end
  dynamicMenu(t)
  controls={};labels={};local parent=title.LoadGameButton:GetParent();assert(parent:IsA('/Script/UMG.VerticalBox'),'Native title button list changed')
  entry,entryLabel=button('multiplayer','choose',title.LoadGameButton,nil)
  local children={};for i=0,parent:GetChildrenCount()-1 do local w=parent:GetChildAt(i);children[#children+1]={w=w,padding=w.Slot.Padding,size=w.Slot.Size,h=w.Slot.HorizontalAlignment,v=w.Slot.VerticalAlignment}end
  hook('/Game/UI/UI_Style/FS_Button.FS_Button_C:BP_OnClicked',function(ctx)
   local c=controls[ctx:get():GetFullName()];if c and c.b:GetIsEnabled()then queued=c.fn end
  end)
  -- FS_Button:OnPreviewKeyDown broadcasts the native click directly after
  -- CheckUIBinding. That gamepad path does not call BP_OnClicked.
  hook('/Game/UI/Input/CheckUIBinding.CheckUIBinding_C:CheckUIBinding',function(_,_,binding,source,pressed)
   if not pressed:get()then return end
   local widget=source:get()
   local c=valid(widget)and controls[widget:GetFullName()]
   if c and c.b:GetIsEnabled()and same(c.b.ConfirmButton,binding:get())then queued=c.fn end
  end)
  hook(titlePath..'Load Slot',function(ctx,slot)
   if same(ctx:get(),title)and(phase=='host_save'or phase=='join_save')then
    if phase=='join_save'then worldSync.prepareJoin()end
    C.Role=phase=='host_save'and'host'or'client';C.SelectedSlot=slot:get();phase='loading';status('loading');log('MENU '..C.Role..' selected slot '..C.SelectedSlot)
   end
  end)
  hook(titlePath..'BackToMainMenu',function(ctx)
   if same(ctx:get(),title)and(phase=='host_save'or phase=='join_save')then if phase=='join_save'then cancelJoin()end;queued='choose' end
  end)
  local function add(w,c)
   local slot=parent:AddChildToVerticalBox(w);slot:SetPadding(c.padding);slot:SetSize(c.size)
   slot:SetHorizontalAlignment(c.h);slot:SetVerticalAlignment(c.v)
  end
  parent:ClearChildren()
  local ok,err=pcall(function()
   for _,c in ipairs(children)do
    add(c.w,c)
    if same(c.w,title.LoadGameButton)then add(entry,c)end
   end
  end)
  if not ok then
   parent:ClearChildren()
   for _,c in ipairs(children)do pcall(add,c.w,c)end
   error(err,0)
  end
  phase='home';revision=L.revision;log('MENU mounted native title entry')
 end
 function M.tick(player)
  L.refresh()
  local skinOk,skinError=pcall(skinMenu.tick)
  if not skinOk then pcall(skinMenu.close);log('MENU skin preview update failed: '..tostring(skinError))end
  friendPanel.tick()
  if os.clock()>=(steam.retryAt or 0)then
   local ok,err=pcall(steam.tick,player)
   if not ok then
    steam.retryAt=os.clock()+2
    pcall(steam.resetUI)
    if steam.lastError~=tostring(err)then steam.lastError=tostring(err);log('STEAM UI retry after transient error: '..tostring(err))end
   else steam.lastError=nil;steam.retryAt=nil end
  end
  if valid(player)then
   if phase=='loading'and C.Role=='host'then send('host','127.0.0.1',C.MenuPort,C.SelectedSlot);status('opening',C.MenuPort);log('MENU host requested room on UDP '..C.MenuPort)end
   if C.Role~='menu'then phase='session'end;return C.Role=='menu'
  end
  local t=valid(title)and title:IsInViewport()and title or nil
  if not t then for _,candidate in ipairs(FindAllOf('TitleScreenUI_C')or{})do if valid(candidate)and candidate:IsInViewport()then t=candidate;break end end end
  if not valid(t)then return true end
  if phase=='session'then C.Role='menu';write('session.request','');write('out.state','');M.ended=true;phase='home'end
  if not same(title,t)then
   M.resetUI()
   title=t
  end
  if not valid(entry)then
   if mountRetryAt and os.clock()<mountRetryAt then return true end
   local ok,err=xpcall(function()mount(t)end,debug.traceback)
   if not ok then
    if valid(entry)then pcall(function()entry:RemoveFromParent()end)end
    entry,entryLabel=nil,nil;controls={};labels={};clearHooks()
    mountRetryAt=os.clock()+2
    menuError('bind/title setup','menu_binding_failed',err)
    return true
   end
   mountRetryAt=nil;clearTitleNotice()
   if statusKey=='menu_binding_failed'then status(nil)end
  end
  local steamJoin=steam.takeJoin()
  if steamJoin then
   cancelJoin();if title.InSaveMenu then title:CloseModal();title:BackToMainMenu()end
   local other=FindFirstOf('FS_GameInstance_C').CurrentOptionsMenu
   if valid(other)and other:IsInViewport()and not same(other,panel)then other:CloseMenu()end
   joiningSteam=true;queued=nil
   if runMenuAction('choose')then C.Role='client';phase='waiting';started=os.time();send('steam',steamJoin,0,0);status('joining')end
  end
  if queued then local action=queued;queued=nil;runMenuAction(action)end
  if revision~=L.revision then
   revision=L.revision;if valid(entryLabel)then entryLabel:SetText(FText(L.get('multiplayer')))end
   for _,l in ipairs(labels)do if valid(l.w)then l.w:SetText(FText(L.get(l.key,table.unpack(l.args or{}))))end end
   if phase=='host_save'or phase=='join_save'then title.SaveScreenTitle:SetText(FText(L.get(phase=='host_save'and'host_save'or'guest_save')))end
   if statusKey then status(statusKey,table.unpack(statusArgs))end
  end
  if phase=='waiting'or phase=='join_prepare'then
   if phase=='join_prepare'and os.time()-started>30 then joinFailed('world_timeout');return true end
   local error=read('session.error');if error~=''then log('MENU connection error '..error);joinFailed('bridge_error');return true end
   local f=hostFrame()
   if f then
    if phase=='waiting'then phase='join_prepare';started=os.time();log('MENU host state accepted; preparing world')end
    local ready=worldSync.prepareJoin();if ready then showSaves('client')else status('receiving_world')end
   elseif os.time()-started>(phase=='waiting'and 45 or 30)then joinFailed(phase=='waiting'and'timeout'or'world_timeout')end
  elseif phase=='join_save'then
   if read('status.txt'):match('^connected|')then lastConnected=os.time()end
   if os.time()-lastConnected>10 then joinFailed('disconnected')end
  end
  return true
 end
 function M.resetUI()
  friendPanel.close(false)
  closePanel()
  steam.resetUI()
  clearHooks();clearTitleNotice()
  if valid(entry)then entry:RemoveFromParent()end
  mountRetryAt=nil
  title,entry,entryLabel,panel,box,heading,frame,message,ip,port,divider,dividerPadding=nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil;controls={};labels={};queued=nil
 end
 return M
end
