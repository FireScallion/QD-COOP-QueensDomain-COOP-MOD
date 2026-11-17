-- The cooked montage tells us where a hold loops. An out-of-hold sample is
-- required to enter its release section, even when extrapolating a late packet.
local dir=assert(debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])'))
local sections=dofile(dir..'enemy_hold_sections.lua')
return function(catalog)
 local M={};local holds={};local empty={}
 for id,m in ipairs(catalog.montages)do
  holds[id]=sections[m.path:lower()]
 end
 local function window(id,p)
  for _,w in ipairs(holds[id]or empty)do if p>=w[1]and p<w[2]then return w end end
 end
 M.inLoop=function(id,p)return window(id,p)~=nil end
 function M.restart(oldId,id,oldPosition,position)
  if oldId~=id then return true end
  oldPosition=oldPosition or 0
  local before,after=window(id,oldPosition),window(id,position)
  if before~=after then return true end
  return not before and position<oldPosition-.04
 end
 function M.advance(id,p,seconds,rate)
  local hold=holds[id]
  local target=math.max(0,p+math.max(0,seconds)*rate*(hold and hold.rate or 1))
  for _,w in ipairs(hold or empty)do
   local start,finish=w[1],w[2]
   if p>=start and p<finish then
    -- Stay inside after six-decimal wire rounding, at both boundaries.
    local wrapped=start+(target-start)%(finish-start)
    return math.max(start+.000002,math.min(wrapped,finish-.000002))
   elseif p<start and target>=start then
    -- Wait for the host's section change before predicting its hold.
    return math.max(0,start-.000002)
   elseif p>=finish then target=math.max(target,finish+.000002)end
  end
  return target
 end
 function M.drift(id,current,target)
  local before,after=window(id,current),window(id,target)
  if before~=after then return math.huge end
  if after then local size=after[2]-after[1];return math.abs((current-target+size/2)%size-size/2)end
  return math.abs(current-target)
 end
 return M
end
