-- Fresh native OptionsMenu instance. Closing keeps the native title/pause
-- focus and input restoration; no gameplay input or pause state is rewritten.
return function(dir,C,read,write,log,L,onJoin,avatar)
 local M={};local panel,box,heading,template;local controls,hooks={},{};local pending,back,view,focusKey;local revision,language,avatarRevision=-1,-1,-1;local nextAvatars
 local function valid(o)return o and o:IsValid()end
 local function same(a,b)return valid(a)and valid(b)and a:GetFullName()==b:GetFullName()end
 local function create(kind,owner)return StaticConstructObject(StaticFindObject('/Script/'..kind),(owner or panel).WidgetTree)end
 local function sourceText(o)
  if o:IsA('/Script/CommonUI.CommonTextBlock')then return o end
  if o:IsA('/Script/UMG.PanelWidget')then for i=0,o:GetChildrenCount()-1 do local r=sourceText(o:GetChildAt(i));if r then return r end end end
 end
 local function text(value,t,owner)
  local source=assert(sourceText(t.Subcontent));local w=create('CommonUI.CommonTextBlock',owner);w:SetStyle(source.Style);w:SetFont(source.Font);w:SetJustification(0);w:SetText(FText(value));return w
 end
 local function button(key,fn,t)
  local b=StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary'):Create(panel,t:GetClass(),panel:GetOwningPlayer());b:SetStyle(t.Style);b.SpecialSounds=t.SpecialSounds
  local label=text(L.get(key),t,b);local center=create('UMG.Border',b);center:SetBrushColor({R=1,G=1,B=1,A=0});center:SetPadding({Left=0,Top=0,Right=0,Bottom=0});center:SetHorizontalAlignment(2);center:SetVerticalAlignment(2);center:AddChild(label);b.Subcontent:AddChild(center)
  controls[b:GetFullName()]={widget=b,fn=fn};return b
 end
 local model=dofile(dir..'steam_friends.lua')(read,write,L,function(id)M.close(false);onJoin(id)end,nil,C.RunId)
 local function clear()
  model.close();for _,h in ipairs(hooks)do pcall(UnregisterHook,h[1],h[2],h[3])end;hooks={};controls={};pending=nil;focusKey=nil;nextAvatars=nil;panel,box,heading,template,view=nil,nil,nil,nil,nil
 end
 function M.close(returnToParent)
  local previous,callback=panel,back;back=nil;clear()
  if valid(previous)and previous:IsInViewport()then previous:CloseMenu()end
  if returnToParent and callback then callback()end
 end
 local function hook(path,fn)local a,b=RegisterHook(path,fn);hooks[#hooks+1]={path,a,b}end
 function M.open(p,mode,onBack)
  if valid(panel)then M.close(false)end
  assert(valid(p)and p:IsInViewport(),'Friend panel is not a live native menu');panel=p;back=onBack;template=p.TopLevel_VideoButton
  -- The native options cache assumes a static widget tree. Friend rows are
  -- rebuilt on paging/status changes; do not reuse cached paint geometry.
  local function dynamic(w)
   if w:IsA('/Script/UMG.InvalidationBox')then w:SetCanCache(false)end
   if w:IsA('/Script/UMG.UserWidget')then dynamic(w.WidgetTree.RootWidget)end
   if w:IsA('/Script/UMG.PanelWidget')then for i=0,w:GetChildrenCount()-1 do dynamic(w:GetChildAt(i))end end
  end
  dynamic(p.WidgetTree.RootWidget)
  local frame=p.OptionsSelectMenu:GetChildAt(0);local canvas=frame:GetChildAt(0)
  for i=0,canvas:GetChildrenCount()-1 do local w=canvas:GetChildAt(i);if w:IsA('/Script/UMG.VerticalBox')then box=w elseif w:IsA('/Script/CommonUI.CommonTextBlock')then heading=w end end
  assert(valid(box)and valid(heading),'Native friend panel layout changed')
  frame.Slot:SetAnchors({Minimum={X=.5,Y=.5},Maximum={X=.5,Y=.5}});frame.Slot:SetAlignment({X=.5,Y=.5})
  frame.Slot:SetPosition({X=0,Y=0});frame.Slot:SetSize({X=516,Y=400})
  box.Slot:SetAnchors({Minimum={X=0,Y=0},Maximum={X=1,Y=1}});box.Slot:SetAlignment({X=0,Y=0});box.Slot:SetOffsets({Left=0,Top=84,Right=0,Bottom=10})
  heading:SetJustification(1)
  heading.Slot:SetSize({X=440,Y=36})
  local divider
  for i=0,box:GetChildrenCount()-1 do
   local w=box:GetChildAt(i)
   if w:GetFName():ToString()=='TitleSpacer'then divider=w;break end
  end
  if valid(divider)and divider:IsA('/Script/UMG.Image')then
   -- Preserve the game's textured title divider outside the rebuilt rows.
   divider:RemoveFromParent()
   local slot=canvas:AddChildToCanvas(divider)
   slot:SetAnchors({Minimum={X=0,Y=0},Maximum={X=1,Y=0}})
   slot:SetOffsets({Left=0,Top=65,Right=0,Bottom=12})
   divider:SetVisibility(4)
  end
  view=dofile(dir..'steam_friends_view.lua')({create=create,text=text,button=button},model,L);revision,language=-1,-1;model.open(mode)
  hook('/Game/UI/UI_Style/FS_Button.FS_Button_C:BP_OnClicked',function(ctx)local c=controls[ctx:get():GetFullName()];if c and c.widget:GetIsEnabled()then focusKey=c.key;pending=c.fn end end)
  hook('/Game/UI/Menus/OptionsMenu.OptionsMenu_C:CloseMenu',function(ctx)if same(ctx:get(),panel)then pending=function()M.close(true)end end end)
  M.tick();log('STEAM native-style '..mode..' friend panel opened')
 end
 function M.tick()
  if not panel then return end
  if pending then local fn=pending;pending=nil;fn()end
  if not panel then return end
  if not valid(panel)or not panel:IsInViewport()then M.close(true);return end
  model.tick();if not panel then return end
  if revision~=model.revision or language~=L.revision then
   local selected=panel.LastSelectedWidget
   if not focusKey and valid(selected)then local c=controls[selected:GetFullName()];focusKey=c and c.key end
   revision,language=model.revision,L.revision;controls={};box:ClearChildren()
   local first,actions=view.render(box,heading,template,function()M.close(true)end)
   for key,b in pairs(actions)do controls[b:GetFullName()].key=key end
   first=(focusKey and actions[focusKey])or first;focusKey=nil;panel.LastSelectedWidget=first
   local u=StaticFindObject('/Game/UI/UIUtilFuncs.Default__UIUtilFuncs_C');u['FS Set Focus'](u,first,true,panel)
   nextAvatars=avatar and 0 or nil
  end
  if avatarRevision~=model.avatarRevision then avatarRevision=model.avatarRevision;nextAvatars=avatar and 0 or nil end
  if nextAvatars then
   local now=os.clock()
   if now>=nextAvatars then nextAvatars=view.avatars(avatar)and now+.25 or nil end
  end
 end
 function M.active()return valid(panel)and panel:IsInViewport()end
 return M
end
