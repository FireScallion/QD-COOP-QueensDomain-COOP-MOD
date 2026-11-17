-- Interest controls co-op perception and discovery only. It never retires,
-- hides, pauses or lowers the presentation/capture frequency of an enemy.
local M={}
function M.active(r,host,guest,now,peers,world)
 local f=r.last
 if not f or not r.awarenessRange then return true end
 if r.queued or r.forceAnim or (r.wakeUntil or 0)>now or (r.speed or 0)>10 or r.wasAttacking or (r.threat and r.threat.target)then return true end
 local radius=math.max(3500,r.awarenessRange+750)+(r.syncActive~=false and 750 or 0)
 local function near(p)return p and (f[10]-p.X)^2+(f[11]-p.Y)^2+(f[12]-p.Z)^2<=radius^2 end
 if near(host)or near(guest)then return true end
 if peers then for _,peer in pairs(peers)do if peer.pose and peer.world==world and near(peer.pose)then return true end end end
 return false
end
return M
