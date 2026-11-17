-- Bone snapshots require refreshed bones even when only a guest sees the actor.
-- Native graph replication does not need this override. Restore on inactivity,
-- mesh replacement, retirement and room teardown.
return function(valid)
 local M={};local pinned={}
 function M.release(r)
  local s=pinned[r];if not s then return end
  if valid(s.mesh)and s.mesh.VisibilityBasedAnimTickOption==0 then s.mesh.VisibilityBasedAnimTickOption=s.mode end
  pinned[r]=nil
 end
 function M.ready(r,mesh,needed,now)
  local s=pinned[r]
  if s and(not valid(s.mesh)or s.address~=mesh:GetAddress()or not needed)then M.release(r);s=nil end
  if not needed then return true end
  if not s then
   local mode=mesh.VisibilityBasedAnimTickOption
   if mode==0 then return true end
   pinned[r]={mesh=mesh,address=mesh:GetAddress(),mode=mode,at=now};mesh.VisibilityBasedAnimTickOption=0
   return false -- Allow an engine animation tick before the first bone read.
  end
  return now>s.at
 end
 function M.reset()for r in pairs(pinned)do M.release(r)end end
 function M.sampled(r,continuous)if not continuous then M.release(r)end end
 return M
end
