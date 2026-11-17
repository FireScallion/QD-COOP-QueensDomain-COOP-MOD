-- Preserve roster and native animation playback at every distance. Only the
-- observation of idle, stationary enemies is less frequent beyond 25 metres.
local M={}
function M.idle(squaredDistance)
 local d=squaredDistance or 0
 return d<2500^2 and .1 or d<3500^2 and .2 or .5
end
function M.pointDistance(x,y,z,localPosition,peerPosition,peers,world)
 local function d(p)
  return p and ((x-p.X)^2+(y-p.Y)^2+(z-p.Z)^2)or 1e20
 end
 local nearest=math.min(d(localPosition),d(peerPosition))
 if peers then for _,peer in pairs(peers)do if peer.world==world then nearest=math.min(nearest,d(peer.pose))end end end
 return nearest
end
function M.distance(f,localPosition,peerPosition,peers,world)
 return M.pointDistance(f[10],f[11],f[12],localPosition,peerPosition,peers,world)
end
return M
