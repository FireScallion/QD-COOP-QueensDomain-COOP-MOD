-- Mod-owned UI only. Native widgets retain the game's own translations.
return function()
 local M={language='en',revision=0};local nextRead=0
 local strings={
  multiplayer={'多人游戏','Multiplayer'},host={'主持游戏','Host game'},join={'加入游戏','Join game'},back={'返回','Back'},
  host_port={'房间端口','Room port'},host_address={'房主 IP 地址','Host IP address'},port={'端口','Port'},
  choose_save={'选择存档','Choose save'},connect={'连接','Connect'},
  host_save={'主持游戏 — 选择存档','Host game — Choose save'},guest_save={'加入游戏 — 选择角色存档','Join game — Choose character save'},
  joining={'正在连接……','Connecting…'},loading={'正在加载……','Loading…'},receiving_world={'正在接收房主世界……','Receiving host world…'},
  connected={'已连接，请选择自己的角色存档。','Connected. Choose your character save.'},
  invalid_ip={'请输入有效的 IPv4 地址。','Enter a valid IPv4 address.'},invalid_port={'端口须为 1024 至 65535 的整数。','Port must be an integer from 1024 to 65535.'},
  timeout={'连接超时。请确认房主已经开房、IP 和端口正确。','Connection timed out. Check that the host has opened a room and the IP and port are correct.'},
  world_timeout={'接收世界数据超时，请重试。','World transfer timed out. Please try again.'},disconnected={'连接已断开，请重新连接。','Disconnected. Please reconnect.'},
  bridge_error={'联机服务未能建立连接。请检查端口是否被占用，详细信息已写入日志。','The connection service could not start. Check whether the port is in use; details are in the log.'},
  opening={'正在开启房间，端口 %d。','Opening room on port %d.'},
  address_hint={'同机测试用 127.0.0.1；其他电脑填写房主的局域网或 Radmin IP。','Use 127.0.0.1 on the same PC, or the host’s LAN or Radmin IP on another PC.'},
  host_hint={'选择角色存档后进入游戏并开启房间。','Choose a character save to enter the game and open a room.'},place={'放置','Place'}
 }
 function M.refresh()
  local now=os.clock();if now<nextRead then return false end;nextRead=now+.25
  local ok,value=pcall(function()return StaticFindObject('/Script/Engine.Default__KismetInternationalizationLibrary'):GetCurrentLanguage():ToString()end)
  local lang=ok and type(value)=='string'and value:lower():sub(1,2)=='zh'and'zh'or'en'
  if M.language~=lang then M.language=lang;M.revision=M.revision+1;return true end;return false
 end
 function M.get(key,...)
  local pair=assert(strings[key],'Unknown UI text: '..tostring(key));local s=pair[M.language=='zh'and 1 or 2]
  if select('#',...)>0 then return string.format(s,...)end;return s
 end
 M.refresh();return M
end
