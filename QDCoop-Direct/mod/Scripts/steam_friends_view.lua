-- Native menu materials and fonts with aligned Steam friend rows.
return function(ui,model,L)
 local M={};local portraits={}
 local inset={Left=16,Top=0,Right=16,Bottom=0}
 local function size(child,w,h)
  local s=ui.create('UMG.SizeBox');if w then s:SetWidthOverride(w)end;if h then s:SetHeightOverride(h)end;if child then s:AddChild(child)end;return s
 end
 local function column(row,child,right,fill)
  local s=row:AddChildToHorizontalBox(child);s:SetVerticalAlignment(2);s:SetPadding({Left=0,Top=0,Right=right or 0,Bottom=0});if fill then s:SetSize({Value=1,SizeRule=1})end;return s
 end
 local function displayName(name)
  local length=0
  -- Keep the leading UTF-8 text readable on the original fixed-width panel.
  -- Match complete characters and leave the full name on the row tooltip.
  for at,character in name:gmatch('()([%z\1-\127\194-\244][\128-\191]*)')do
   length=length+(#character>1 and 2 or 1)
   if length>23 then return name:sub(1,at-1)..'…' end
  end
  return name
 end
 function M.render(box,heading,template,back)
  portraits={};heading:SetText(FText(L.get(model.mode=='invite'and'invite_players'or'steam_friends_title')))
  local first,actions=nil,{}
  for i=model.page*5+1,math.min(#model.rows,model.page*5+5)do
   local item=model.rows[i];local row=ui.create('UMG.HorizontalBox');local image=ui.create('UMG.Image')
   image:SetVisibility(4);image:SetOpacity(0)
   local caption=displayName(item.name)
   local name=ui.text(caption,template);local fit=ui.create('UMG.ScaleBox');fit:SetStretch(2);fit:SetStretchDirection(1);fit:AddChild(name):SetHorizontalAlignment(1)
   if caption~=item.name then fit:SetToolTipText(FText(item.name))end
   local state=ui.text(L.get(model.status(item)),template);local stateBox=size(state,108,38);state.Slot:SetHorizontalAlignment(3);state.Slot:SetVerticalAlignment(2)
   local b
   if model.enabled(item)then
    b=ui.button(model.mode=='invite'and'friend_invite'or'friend_join',function()model.pick(item)end,template)
    first=first or b;actions['friend:'..item.id]=b
   end
   column(row,size(image,32,32),10);column(row,fit,10,true);column(row,stateBox,12);column(row,size(b,96,38))
   box:AddChildToVerticalBox(size(row,nil,42)):SetPadding(inset)
   portraits[#portraits+1]={image=image,id=item.id,row=i}
  end
  local note=ui.text(model.message(),template);note:SetJustification(1);note:SetAutoWrapText(false);note.WrapTextAt=440
  local noteBox=size(note);note.Slot:SetHorizontalAlignment(0);note.Slot:SetVerticalAlignment(3)
  local ns=box:AddChildToVerticalBox(noteBox);ns:SetSize({Value=1,SizeRule=1});ns:SetPadding(inset)
  local bar=ui.create('UMG.HorizontalBox');local previous,next
  if model.page>0 then previous=ui.button('skin_previous',function()model.turn(-1)end,template)end
  if (model.page+1)*5<#model.rows then next=ui.button('skin_next',function()model.turn(1)end,template)end
  local b=ui.button('back',back,template)
  column(bar,size(previous,55,44))
  local middle=size(b,104,44);column(bar,middle,0,true):SetHorizontalAlignment(2)
  column(bar,size(next,55,44))
  box:AddChildToVerticalBox(size(bar,nil,44)):SetPadding({Left=16,Top=0,Right=16,Bottom=6})
  actions.previous,actions.next,actions.back=previous,next,b
  return first or next or previous or b,actions
 end
 function M.avatars(resolve)
  local missing=false
  for _,p in ipairs(portraits)do
   local row=model.rows[p.row]
   if row and row.id==p.id and row.avatar==0 and p.applied then
    p.image:SetOpacity(0);p.applied=nil
   elseif row and row.id==p.id and row.avatar>0 and row.avatar~=p.applied then
    local texture=resolve(p.id,row.avatar,row.index,p.image)
    if texture then
     if texture~=true then p.image:SetBrushFromTexture(texture,false)end
     p.image:SetOpacity(1);p.applied=row.avatar
    else missing=true end
   end
  end
  return missing
 end
 return M
end
