-- EnemyBase's original Update Fog writes per-component primitive data.
-- Sharing a material alone does not transfer it to our independent display mesh.
return function(valid)
 local functions=StaticFindObject('/Script/QueensDomain.Default__FS_FogFunctions')
 local M={}
 function M.capture(e)
  local c=e.CurrentFogColor
  return {c.R,c.G,c.B,c.A,e.CurrentFogStartDistance,e.CurrentFogFadeRange}
 end
 function M.append(r,f)
  if r.sourceFog then f[#f+1]=-902;for _,v in ipairs(r.sourceFog)do f[#f+1]=v end end
 end
 function M.apply(r)
  if not r or not valid(r.e)or not valid(r.pose)or not valid(functions)then return end
  local e=r.e
  local f=r.fog or M.capture(e);local previous=r.fogApplied
  local changed=r.fogTarget~=r.pose or not previous
  if not changed then for i=1,6 do if previous[i]~=f[i]then changed=true;break end end end
  if not changed then return end
  functions:SetFogPropsOnPrimComp(r.pose,{R=f[1],G=f[2],B=f[3],A=f[4]},f[5],f[6],false,false)
  r.fogTarget=r.pose;r.fogApplied=f
 end
 return M
end
