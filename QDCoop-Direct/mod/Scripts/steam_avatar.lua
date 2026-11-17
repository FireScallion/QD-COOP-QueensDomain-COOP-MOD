-- No Lua roundtrip of SteamBridge's opaque FSteamID, and no global object scan.
return function(dir)
 local native;local M={}
 function M.apply(id,handle,friends,image)
  if not(id and id:match('^%d+$')and #id<=20 and handle>0 and friends and friends:IsValid()and image and image:IsValid())then return false end
  if not native then
   local f=assert(package.loadlib(dir..'qdavatar.dll','qdavatar'))
   local function fields(o)local p={};o:ForEachProperty(function(v)p[v:GetFName():ToString()]=v:GetAddress()end);return p end
   local af=StaticFindObject('/Script/SteamBridge.SteamFriends:GetFriendAvatar');local bf=StaticFindObject('/Script/UMG.Image:SetBrushFromTexture');local a,b=fields(af),fields(bf)
   local v={af:GetAddress(),StaticFindObject('/Script/SteamBridge.SteamFriends'):GetAddress(),bf:GetAddress(),StaticFindObject('/Script/UMG.Image'):GetAddress(),StaticFindObject('/Script/Engine.Texture2D'):GetAddress(),a.SteamIDFriend,a.AvatarSize,a.ImageHandle,a.ReturnValue,b.Texture,b.bMatchSize}
   assert(#v==11 and f('I'..table.concat(v,' '))=='1','Avatar reflected layout unavailable');native=f
  end
  return native('A'..table.concat({id,friends:GetAddress(),image:GetAddress(),handle},' '))=='1'
 end
 return M
end
