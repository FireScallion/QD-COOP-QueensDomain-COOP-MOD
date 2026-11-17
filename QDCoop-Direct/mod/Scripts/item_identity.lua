-- A copied character is not the same inventory on two installations. Keep a
-- per-profile custody identity outside shared world state and checkpoint files.
return function(dir,C)
 local Store=dofile(dir..'rescue_store.lua');local profile,serial
 return function(character)
  if not profile then
   local root=C.ExpectedSaveDirectory:gsub('\\','/'):gsub('/+$','')..'/SaveGames/'
   profile=Store.open(root..'QDCoopItem_Profile',{});serial=0
  end
  local key='c_'..character;local id=profile.get()[key]
  if not id then
   serial=serial+1;id=C.RunId..'_item_'..serial
   profile.change(function(s)s[key]=id end)
  end
  assert(type(id)=='string'and #id<=80 and id:match('^[%w_%-]+$'),'Invalid item custody identity')
  return id
 end
end
