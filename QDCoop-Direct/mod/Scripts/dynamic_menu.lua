-- Runtime-rebuilt native menus must not reuse the original static paint cache.
-- Scope this to the edited widget instance, never a global Slate setting.
return function(root)
 local count=0
 local function visit(w)
  if not w or not w:IsValid()then return end
  if w:IsA('/Script/UMG.InvalidationBox')then w:SetCanCache(false);count=count+1 end
  if w:IsA('/Script/UMG.UserWidget')then visit(w.WidgetTree.RootWidget)
  elseif w:IsA('/Script/UMG.PanelWidget')then for i=0,w:GetChildrenCount()-1 do visit(w:GetChildAt(i))end end
 end
 visit(root);return count
end
