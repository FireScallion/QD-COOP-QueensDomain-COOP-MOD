-- Menu state only. SDK enumeration/invitation stays in the background broker.
return function(read,write,L,join,clock,nonce)
 local M={rows={},page=0,mode='join',access='unavailable',space=false,lobby='0',account='0',revision=0,avatarRevision=0,notice=nil}
 clock=clock or os.clock;nonce=nonce or tostring(os.time())
 local active=false;local last,nextLease='',0;local sequence=0;local pending;local sent={};local pendingAt=0;local nextRead=0
 local function id(s)return s and s:match('^%d+$')and #s<=20 end
 local function fields(line)local t={};for part in (line..'|'):gmatch('(.-)|')do t[#t+1]=part end;return t end
 local function decode(s)return(s:gsub('%%(%x%x)',function(h)return string.char(tonumber(h,16))end))end
 local function apply(text)
  local lines={};for line in text:gmatch('([^\n]+)\n')do lines[#lines+1]=line end
  if #lines<2 or lines[#lines]~='END'or #lines>2050 then return false end
  local h=fields(lines[1]);if #h~=5 or h[1]~='QDSF1'or not id(h[2])or not id(h[3])then return false end
  local rows,seen={},{}
  for i=2,#lines-1 do
   local f=fields(lines[i]);if #f~=8 or not id(f[1])or not id(f[2])or seen[f[1]]or not tonumber(f[6])or not tonumber(f[8])then return false end
   seen[f[1]]=true;rows[#rows+1]={id=f[1],lobby=f[2],playing=f[3]=='1',online=f[4]=='1',inRoom=f[5]=='1',avatar=tonumber(f[6]),name=decode(f[7]),index=tonumber(f[8])}
  end
  local changed=M.account~=h[2]or M.lobby~=h[3]
  if changed then sent={};pending=nil end
  changed=changed or M.space~=(h[4]=='1')or M.access~=h[5]or #M.rows~=#rows
  local avatarsChanged=false
  if not changed then
   for i,row in ipairs(rows)do
    local old=M.rows[i]
    if row.id~=old.id or row.lobby~=old.lobby or row.playing~=old.playing or row.online~=old.online or row.inRoom~=old.inRoom or row.name~=old.name then changed=true;break end
    avatarsChanged=avatarsChanged or row.avatar~=old.avatar or row.index~=old.index
   end
  end
  M.account,M.lobby,M.space,M.access=h[2],h[3],h[4]=='1',h[5];M.rows=rows
  M.page=math.min(M.page,math.max(0,math.ceil(#rows/5)-1))
  if changed then M.revision=M.revision+1 elseif avatarsChanged then M.avatarRevision=M.avatarRevision+1 end
  return true
 end
 function M.open(mode)active=true;M.mode=mode;M.page=0;M.notice=nil;sent={};pending=nil;last='';nextLease=0;nextRead=0;M.tick()end
 function M.close()active=false;pending=nil;write('steam-social-lease.txt','')end
 function M.enabled(row)return not pending and(M.mode=='invite'and M.space and row.online and not row.inRoom and not sent[row.id]or M.mode=='join'and row.lobby~='0')end
 function M.status(row)return row.inRoom and M.mode=='invite'and'friend_in_room'or sent[row.id]and M.mode=='invite'and'friend_invited'or row.playing and'friend_playing'or row.online and'friend_online'or'friend_offline'end
 function M.pick(row)
  if not active or not M.enabled(row)then return false end
  sequence=sequence+1;pending=nonce..'-'..sequence;pendingAt=clock();M.pendingId=row.id
  write('steam-social-action.txt',table.concat({pending,M.mode,row.id,M.mode=='invite'and M.lobby or row.lobby},'|'));M.notice='joining';M.revision=M.revision+1;return true
 end
 function M.turn(delta)M.page=math.max(0,math.min(math.max(0,math.ceil(#M.rows/5)-1),M.page+delta));M.revision=M.revision+1 end
 function M.tick(force)
  if not active then return end
  local now=clock();if now>=nextLease then nextLease=now+1.5;sequence=sequence+1;write('steam-social-lease.txt',nonce..'-lease-'..sequence)end
  if not force and now<nextRead then return end;nextRead=now+.25
  local value=read('steam-social.txt');if value~=last and apply(value)then last=value end
  if pending then
   local f=fields(read('steam-social-result.txt'))
   if f[1]==pending then
    pending=nil;M.revision=M.revision+1
    if f[2]=='join'and id(f[3])and f[3]~='0'then M.notice='joining';join(f[3])
    elseif f[2]=='sent'then sent[M.pendingId]=true;M.notice='friend_invite_sent'
    else M.notice='steam_room_error'end
   elseif now-pendingAt>8 then pending=nil;M.notice='steam_room_error';M.revision=M.revision+1 end
  end
 end
 function M.message()
  if M.notice then return L.get(M.notice)end
  if M.mode=='invite'and not M.space and M.access=='ready'then return L.get('friend_room_full')end
  if M.access~='ready'then return L.get('steam_unavailable')end
  if #M.rows==0 then return L.get('friend_empty')end;return''
 end
 return M
end
