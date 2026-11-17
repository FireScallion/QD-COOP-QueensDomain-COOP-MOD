-- Length-delimited broker envelope; character save IDs are never room identity.
-- Lua strings count bytes, matching the broker's UTF-8 frame lengths.
local M={}
local function id(s)return type(s)=='string'and #s==32 and s:match('^%x+$')~=nil end
local function integer(s,low,high)local n=tonumber(s);return n and n%1==0 and n>=low and n<=high and n or nil end
local function fields(s)local t={};for v in(s..'|'):gmatch('(.-)|')do t[#t+1]=v end;return t end
function M.decode(text,magic)
 if type(text)~='string'or #text>24000 then return nil,'size'end
 local pos=1;local function line()local at=text:find('\n',pos,true);if not at then return end;local s=text:sub(pos,at-1);pos=at+1;return s end
 local header=line();if not header then return nil,'header'end;local h=fields(header)
 if #h~=6 or h[1]~=(magic or'QDRS1')or not id(h[2])or not id(h[3])or not id(h[4])or not integer(h[5],1,9007199254740991)or not integer(h[6],2,4)then return nil,'header'end
 local room={session=h[2],self=h[3],host=h[4],revision=tonumber(h[5]),capacity=tonumber(h[6]),members={},frames={},order={}}
 local slots={};local framed=false
 while pos<=#text do
  local s=line();if not s then return nil,'truncated'end
  if s=='END'then
   if pos~=#text+1 or not room.members[room.self]or room.members[room.host]~=0 then return nil,'membership'end
   table.sort(room.order,function(a,b)return room.members[a]<room.members[b]end);return room
  end
  local f=fields(s)
  if f[1]=='M'and not framed then
   local slot=integer(f[3],0,room.capacity-1)
   if #f~=3 or not id(f[2])or not slot or slots[slot]or room.members[f[2]]~=nil or #room.order>=room.capacity then return nil,'member'end
   slots[slot]=true;room.members[f[2]]=slot;room.order[#room.order+1]=f[2]
  elseif f[1]=='F'then
   framed=true;local length=integer(f[3],1,7000)
   if #f~=3 or not length or room.members[f[2]]==nil or f[2]==room.self or room.frames[f[2]]or pos+length-1>#text then return nil,'frame'end
   room.frames[f[2]]=text:sub(pos,pos+length-1);pos=pos+length
  else return nil,'record'end
 end
 return nil,'end'
end
function M.new(parseFrame,joined,left,updated)
 local R={peers={},order={}};local last
 function R.accept(text,now)
  if text==last then return false end
  local room,err=M.decode(text);if not room then return false,err end
  if R.session==room.session and R.revision and room.revision<R.revision then return false,'old membership'end
  if R.session==room.session and (R.self~=room.self or R.host~=room.host)then return false,'identity changed'end
  if R.session==room.session and R.revision==room.revision then
   for id in pairs(R.peers)do if room.members[id]==nil then return false,'unversioned removal'end end
   for id in pairs(room.members)do if id~=R.self and not R.peers[id]then return false,'unversioned addition'end end
  end
  if R.session and R.session~=room.session then R.reset()end
  for peer,p in pairs(R.peers)do if room.members[peer]==nil then left(peer,p);R.peers[peer]=nil end end
  R.session,R.self,R.host,R.revision,R.capacity,R.members=room.session,room.self,room.host,room.revision,room.capacity,room.members;R.order={}
  for _,peer in ipairs(room.order)do if peer~=room.self then
   R.order[#R.order+1]=peer;local p=R.peers[peer]
   if not p then p={id=peer,slot=room.members[peer]};R.peers[peer]=p;joined(peer,p)end
   local raw=room.frames[peer]
   if raw and raw~=p.raw then
    local frame=parseFrame(raw)
    if frame then p.raw=raw;p.frame=frame;p.at=now;updated(peer,p,frame,now)end
   end
  end end
  last=text;return true
 end
 function R.reset()for peer,p in pairs(R.peers)do left(peer,p)end;R.peers={};R.order={};R.members={};R.session=nil;R.revision=nil;last=nil end
 return R
end
return M
