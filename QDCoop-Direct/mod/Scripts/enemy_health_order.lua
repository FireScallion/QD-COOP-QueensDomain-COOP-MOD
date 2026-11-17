-- Reliable hit confirmations and pose snapshots share the host's clock.
-- Health must not wait for pose capture or roll back on an older datagram.
local M={}
function M.confirm(r,hp,at)
 if not at or at~=at or at==math.huge or at<0 or hp~=hp or hp<0 or hp==math.huge then return false end
 if at<math.max(r.sourceTime or 0,r.healthAt or 0)then return false end
 r.healthAt=at;r.hp=hp;return true
end
function M.snapshot(r,hp,at)
 if r.healthAt and at<r.healthAt then return r.hp,false end
 r.healthAt=at;return hp,true
end
return M
