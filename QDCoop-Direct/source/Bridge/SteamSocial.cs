using System.Runtime.InteropServices;
using System.Text;

// Menu-only SDK work runs in the existing broker, never on the game thread.
// Layout mirrors M138, but membership/transport authority remains in this branch.
sealed class SteamSocial(SteamApi api, Func<string,string> read, Func<string,string,bool> write)
{
    [StructLayout(LayoutKind.Sequential)] struct Game { public ulong Id; public uint IP; public ushort Port,Query; public ulong Lobby; }
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int Count(IntPtr p,int flags);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate ulong At(IntPtr p,int i,int flags);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate IntPtr Name(IntPtr p,ulong id);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int State(IntPtr p,ulong id);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate byte Playing(IntPtr p,ulong id,out Game game);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate byte Friend(IntPtr p,ulong id,int flags);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate IntPtr Presence(IntPtr p,ulong id,[MarshalAs(UnmanagedType.LPUTF8Str)]string key);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate byte Invite(IntPtr p,ulong lobby,ulong id);
    long next;string lease=read("steam-social-lease.txt"),command=read("steam-social-action.txt"),snapshot="";long leaseUntil;string result="";
    bool IsFriend(ulong id)=>api.F<Friend>("SteamAPI_ISteamFriends_HasFriend")(api.Friends,id,4)!=0;
    bool IsPlaying(ulong id)=>api.F<Playing>("SteamAPI_ISteamFriends_GetFriendGamePlayed")(api.Friends,id,out var g)!=0&&(g.Id&0xffffff)==1799840;
    public ulong FriendLobby(ulong id){
        if(!IsFriend(id)||!IsPlaying(id))return 0;
        string p=Marshal.PtrToStringUTF8(api.F<Presence>("SteamAPI_ISteamFriends_GetFriendRichPresence")(api.Friends,id,"connect"))??"";
        return p.StartsWith("+qdcoop_lobby ",StringComparison.Ordinal)&&SteamService.ValidLobby(p[14..],out var lobby)?lobby:0;
    }
    HashSet<ulong> Members(ulong lobby){
        var set=new HashSet<ulong>();if(lobby==0)return set;
        int count=api.F<SteamApi.Count>("SteamAPI_ISteamMatchmaking_GetNumLobbyMembers")(api.Matchmaking,lobby);
        for(int i=0;i<Math.Clamp(count,0,4);i++)set.Add(api.F<SteamApi.Member>("SteamAPI_ISteamMatchmaking_GetLobbyMemberByIndex")(api.Matchmaking,lobby,i));return set;
    }
    bool Space(ulong lobby,HashSet<ulong> members)=>lobby!=0&&api.LobbyOwner(lobby)==api.Self&&members.Contains(api.Self)&&
        api.F<SteamApi.Count>("SteamAPI_ISteamMatchmaking_GetLobbyMemberLimit")(api.Matchmaking,lobby) is >=2 and <=4&&
        members.Count<api.F<SteamApi.Count>("SteamAPI_ISteamMatchmaking_GetLobbyMemberLimit")(api.Matchmaking,lobby);
    static string Escape(string value)=>Uri.EscapeDataString(string.Concat(value.Take(256).Select(c=>char.IsControl(c)?' ':c)));
    public void Tick(long now,ulong hostedLobby,bool accepting){
        string current=read("steam-social-lease.txt");
        if(current!=lease){lease=current;leaseUntil=now+5000;next=0;}
        if(current==""||now>leaseUntil)return;
        var members=Members(hostedLobby);bool space=accepting&&Space(hostedLobby,members);
        string requested=read("steam-social-action.txt");
        if(requested!=""&&requested!=command){
            command=requested;var f=requested.Split('|');string outcome="invalid",value="0";
            if(f.Length==4&&f[0].Length<=80&&ulong.TryParse(f[2],out var id)&&ulong.TryParse(f[3],out var expected)){
                if(f[1]=="join"){
                    ulong target=FriendLobby(id);if(target!=0&&target==expected){outcome="join";value=target.ToString();}else outcome="changed";
                }else if(f[1]=="invite"){
                    if(expected==hostedLobby&&space&&!members.Contains(id)&&IsFriend(id)&&api.F<State>("SteamAPI_ISteamFriends_GetFriendPersonaState")(api.Friends,id)>0)
                        outcome=api.F<Invite>("SteamAPI_ISteamMatchmaking_InviteUserToLobby")(api.Matchmaking,hostedLobby,id)!=0?"sent":"failed";
                    else outcome="unavailable";
                }
                result=f[0]+"|"+outcome+"|"+value;
            }
            next=0;
        }
        if(result!=""&&write("steam-social-result.txt",result))result="";
        if(now<next)return;next=now+1500;
        var rows=new List<(ulong Id,string Name,bool Playing,bool Online,bool InRoom,ulong Lobby,int Avatar,int Index)>();
        int count=Math.Clamp(api.F<Count>("SteamAPI_ISteamFriends_GetFriendCount")(api.Friends,4),0,2048);
        for(int i=0;i<count;i++){
            ulong id=api.F<At>("SteamAPI_ISteamFriends_GetFriendByIndex")(api.Friends,i,4);if(id==0||id==api.Self)continue;
            bool playing=IsPlaying(id),online=playing||api.F<State>("SteamAPI_ISteamFriends_GetFriendPersonaState")(api.Friends,id)>0;
            string name=Marshal.PtrToStringUTF8(api.F<Name>("SteamAPI_ISteamFriends_GetFriendPersonaName")(api.Friends,id))??"Steam friend";
            rows.Add((id,name,playing,online,members.Contains(id),playing?FriendLobby(id):0,api.F<State>("SteamAPI_ISteamFriends_GetSmallFriendAvatar")(api.Friends,id),i));
        }
        var b=new StringBuilder($"QDSF1|{api.Self}|{hostedLobby}|{(space?1:0)}|ready\n");
        foreach(var r in rows.OrderByDescending(r=>r.Lobby!=0).ThenByDescending(r=>r.Playing).ThenByDescending(r=>r.Online).ThenBy(r=>r.Name,StringComparer.OrdinalIgnoreCase).ThenBy(r=>r.Id))
            b.Append($"{r.Id}|{r.Lobby}|{(r.Playing?1:0)}|{(r.Online?1:0)}|{(r.InRoom?1:0)}|{r.Avatar}|{Escape(r.Name)}|{r.Index}\n");
        b.Append("END\n");string text=b.ToString();if(text!=snapshot&&write("steam-social.txt",text))snapshot=text;
    }
}
