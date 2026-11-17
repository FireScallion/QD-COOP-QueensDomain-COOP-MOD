using System.Buffers.Binary;
using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text.Json;

// Persistent, background-only Steam room and datagram adapter. The existing game
// protocol still owns ordering, deduplication, reliability, snapshots and timeouts.
// No Steam or network waits run on the Unreal thread. Never accepts arbitrary peers.
sealed class SteamService : IDisposable {
    public record Configuration(string Directory,string Dll,string Build,int OwnerPid,long OwnerStartTicks,bool PrivateTest=false,string? DiagnosticDirectory=null);
    public record Command(string Token,string Role,int Port=0,string Lobby="",int MaxPlayers=2,int RoomProtocol=1);
    record Operation(int Callback,string Token,string Role,long Started);
    readonly Configuration config; readonly SteamApi api; readonly Process owner; readonly SteamSocial social;
    readonly SteamNetworkDiagnostics diagnostics;
    readonly DiagnosticLog diagnosticLog;
    readonly Socket udp=new(AddressFamily.InterNetwork,SocketType.Dgram,ProtocolType.Udp);
    readonly byte[] packet=new byte[1232]; readonly IntPtr[] received=new IntPtr[64];
    readonly IntPtr sendBuffer=Marshal.AllocHGlobal(1232),result=Marshal.AllocHGlobal(512);
    readonly Dictionary<ulong,Operation> calls=[];
    HashSet<ulong> members=[]; ulong lobby,peer; IntPtr peerIdentity;
    sealed record Route(Socket Socket,IntPtr Identity);
    readonly Dictionary<ulong,Route> routes=[];
    bool multi;int capacity=2;
    IPEndPoint? bridge; string token="",role="idle",state="ready",error="",lastCommand="",lastStatus="",pendingInvite="";
    bool joinable,disposed; string groupSize="";long nextControl,nextReport,nextPresence,requestStarted,tx,rx,rejected;
    const int Channel=17,MaxDatagram=1200; const uint Magic=0x31534451; // QDS1, lobby-scoped envelope
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate byte LobbyType(IntPtr p,ulong lobby,int type);
    public SteamService(Configuration cfg,DiagnosticLog logger){
        config=cfg;diagnosticLog=logger;owner=Process.GetProcessById(cfg.OwnerPid);
        if(owner.StartTime.ToUniversalTime().Ticks!=cfg.OwnerStartTicks)throw new InvalidOperationException("Game process identity changed");
        api=new SteamApi(cfg.Dll);
        diagnosticLog.Add($"stage=send_config minRateBps=1048576 maxRateBps=2097152 accepted={api.ConfigureSendRate()}");
        diagnosticLog.Flush(true);
        social=new SteamSocial(api,Read,(name,value)=>Atomic(PathOf(name),value));
        udp.Bind(new IPEndPoint(IPAddress.Loopback,0));udp.ReceiveBufferSize=2*1024*1024;udp.SendBufferSize=1024*1024;
        if(OperatingSystem.IsWindows())udp.IOControl(unchecked((int)0x9800000C),new byte[4],null);
        api.F<SteamApi.VoidP>("SteamAPI_ISteamNetworkingUtils_InitRelayNetworkAccess")(api.Networking);
        diagnostics=new SteamNetworkDiagnostics(api,diagnosticLog);
        Publish();
    }
    string PathOf(string name)=>Path.Combine(config.Directory,name);
    static bool Atomic(string path,string value){
        try{File.WriteAllText(path+".tmp",value);File.Move(path+".tmp",path,true);return true;}
        catch(Exception e)when(e is IOException or UnauthorizedAccessException){return false;}
    }
    string Read(string file){try{return File.ReadAllText(PathOf(file));}catch(IOException){return "";}}
    void Publish(){
        string s=JsonSerializer.Serialize(new{State=state,Lobby=lobby.ToString(),Port=((IPEndPoint)udp.LocalEndPoint!).Port,Token=token,Error=error,Joinable=joinable,Peer=peer.ToString()});
        if(s==lastStatus)return;
        if(s!=lastDiagnosticStatus){
            diagnosticLog.Add($"stage=state session={token} role={role} state={state} error={error}");
            diagnosticLog.Flush(true);
            lastDiagnosticStatus=s;
        }
        bool statusWritten=Atomic(PathOf("steam.status"),s);
        bool uiWritten=Atomic(PathOf("steam-ui.txt"),state+"|"+lobby+"|"+error.Replace('|',' '));
        if(statusWritten&&uiWritten)lastStatus=s; // Retry a briefly locked control file next tick.
    }
    string lastDiagnosticStatus="";
    void Peer(ulong id){
        if(peer==id)return;
        if(peer!=0 && role=="host"){
            // Steam has definitive membership information. Release ONLY the
            // bridge session carried by this adapter, never a LAN guest or a
            // newer session. Otherwise a departed guest occupies the slot for
            // the bridge's 20-second lost-packet grace period.
            var fields=Read("status.txt").Trim().Split('|');
            if(fields.Length>=3 && fields[0]=="connected")Atomic(PathOf("steam-peer-left.txt"),fields[1]+"|"+fields[2]+"|"+((IPEndPoint)udp.LocalEndPoint!).Port);
        }
        if(peerIdentity!=IntPtr.Zero){api.F<SteamApi.Session>("SteamAPI_ISteamNetworkingMessages_CloseSessionWithUser")(api.Messages,peerIdentity);Marshal.FreeHGlobal(peerIdentity);peerIdentity=IntPtr.Zero;}
        peer=id;if(id!=0)peerIdentity=api.Identity(id);
    }
    void Leave(){
        if(lobby!=0){
            if(role=="host")api.F<SteamApi.Joinable>("SteamAPI_ISteamMatchmaking_SetLobbyJoinable")(api.Matchmaking,lobby,0);
            api.F<SteamApi.Leave>("SteamAPI_ISteamMatchmaking_LeaveLobby")(api.Matchmaking,lobby);
        }
        if(role=="host"&&!config.PrivateTest){api.SetPresence("connect",null);api.SetPresence("steam_player_group",null);api.SetPresence("steam_player_group_size",null);}
        foreach(var id in routes.Keys.ToArray())RemoveRoute(id);
        Peer(0);lobby=0;bridge=null;members.Clear();joinable=false;groupSize="";nextPresence=0;role="idle";
        // Late asynchronous Create/Join completions are still consumed and left.
        while(udp.Available>0){EndPoint ep=new IPEndPoint(IPAddress.Any,0);udp.ReceiveFrom(packet,ref ep);}
    }
    void Fail(string message){Console.Error.WriteLine(message);Leave();state="error";error=message;Publish();}
    void Apply(Command c){
        Leave();token=c.Token;error="";state="ready";requestStarted=Environment.TickCount64;
        if(c.RoomProtocol is not (1 or 2)||c.MaxPlayers is <2 or >4||(c.RoomProtocol==1&&c.MaxPlayers!=2)){Fail("Invalid Steam room capacity/protocol");return;}
        multi=c.RoomProtocol==2;capacity=c.MaxPlayers;
        if(c.Role=="idle"){Publish();return;}
        if(c.Role=="host" && c.Port is >=1024 and <=65535){
            role="host";state="creating";bridge=new(IPAddress.Loopback,c.Port);
            ulong call=api.F<SteamApi.Create>("SteamAPI_ISteamMatchmaking_CreateLobby")(api.Matchmaking,0,capacity);
            if(call==0){Fail("Steam could not create a room");return;}
            calls[call]=new(513,token,role,requestStarted);
        }else if(c.Role=="join" && ValidLobby(c.Lobby,out var id)){
            role="client";state="joining";
            ulong call=api.F<SteamApi.Join>("SteamAPI_ISteamMatchmaking_JoinLobby")(api.Matchmaking,id);
            if(call==0){Fail("Steam could not join this room");return;}
            calls[call]=new(504,token,role,requestStarted);
        }else{Fail("Invalid Steam room request");return;}
        Publish();
    }
    internal static bool ValidLobby(string s,out ulong id)=>ulong.TryParse(s,out id)&&s.Length<=20&&id!=0&&((id>>52)&15)==8; // Steam chat/lobby ID
    void Complete(ulong handle,int callback,int size){
        if(!calls.Remove(handle,out var op))return;
        int expected=op.Callback==513?16:24;
        if(callback!=op.Callback||size!=expected||api.F<SteamApi.CallResult>("SteamAPI_ManualDispatch_GetAPICallResult")(api.Pipe,handle,result,size,callback,out var failed)==0||failed!=0){if(op.Token==token)Fail("Steam room request failed");return;}
        bool ok=callback==513?Marshal.ReadInt32(result)==1:Marshal.ReadInt32(result,16)==1;
        ulong id=(ulong)Marshal.ReadInt64(result,callback==513?8:0);
        if(op.Token!=token || role!=op.Role || state is not ("creating" or "joining")){
            if(ok && id!=0 && id!=lobby)api.F<SteamApi.Leave>("SteamAPI_ISteamMatchmaking_LeaveLobby")(api.Matchmaking,id);return;
        }
        if(!ok||id==0){Fail("Room is unavailable, full, or not accessible to this Steam account");return;}
        lobby=id;members=api.Members(lobby);
        if(role=="host"){
            api.F<SteamApi.Joinable>("SteamAPI_ISteamMatchmaking_SetLobbyJoinable")(api.Matchmaking,lobby,0);
            api.SetLobbyData(lobby,"mod","QDCoop");api.SetLobbyData(lobby,"build",config.Build);api.SetLobbyData(lobby,"transport",multi?"QDS2":"QDS1");api.SetLobbyData(lobby,"owner",api.Self.ToString());
            if(!config.PrivateTest && api.F<LobbyType>("SteamAPI_ISteamMatchmaking_SetLobbyType")(api.Matchmaking,lobby,1)==0){Fail("Could not publish a friends room");return;}
            state="hosting";UpdateMembers();
        }else{
            ulong host=api.LobbyOwner(lobby);
            if(api.LobbyData(lobby,"mod")!="QDCoop"||api.LobbyData(lobby,"build")!=config.Build||api.LobbyData(lobby,"transport")!=(multi?"QDS2":"QDS1")||api.LobbyData(lobby,"owner")!=host.ToString()||host==api.Self){Fail("Room requires the same QDCoop and game version, and another host account");return;}
            Peer(host);state="joined";
        }
        Publish();Console.WriteLine("Steam "+state+" room established");
    }
    void UpdateMembers(){
        if(lobby==0)return;
        members=api.Members(lobby);
        if(role=="client"){
            if(!members.Contains(peer)||api.LobbyOwner(lobby)!=peer){Fail("The Steam host left the room");}return;
        }
        if(role!="host")return;
        ulong ownerId=api.LobbyOwner(lobby);
        // A disconnected Steam backend can temporarily return no cached owner.
        // This is not an ownership transfer and must not destroy a LAN room.
        if(ownerId==0)return;
        if(ownerId!=api.Self){Fail("Steam room ownership changed");return;}
        if(multi){
            foreach(var id in routes.Keys.Where(id=>!members.Contains(id)).ToArray())RemoveRoute(id);
            foreach(var id in members.Where(id=>id!=api.Self))if(!routes.ContainsKey(id)){
                var socket=new Socket(AddressFamily.InterNetwork,SocketType.Dgram,ProtocolType.Udp);socket.Bind(new IPEndPoint(IPAddress.Loopback,0));
                if(OperatingSystem.IsWindows())socket.IOControl(unchecked((int)0x9800000C),new byte[4],null);
                routes.Add(id,new(socket,api.Identity(id)));
            }
            SetRoomPresence(members.Count<capacity,members.Count.ToString());return;
        }
        ulong guest=members.FirstOrDefault(id=>id!=api.Self);
        string net=Read("status.txt");bool connected=net.StartsWith("connected|",StringComparison.Ordinal);
        // Existing LAN bridge owns the single peer slot; never admit a third player.
        bool lan=connected && peer==0;
        if(guest!=0 && !lan)Peer(guest);else if(guest==0)Peer(0);
        bool open=!connected && guest==0;
        SetRoomPresence(open,connected?"2":"1");
    }
    void SetRoomPresence(bool open,string count){
        long now=Environment.TickCount64;
        if(open!=joinable || now>=nextPresence){
            // Do not cache success before Steam accepts it. Periodic repair also
            // restores presence after a Steam reconnect or another API owner
            // clears it; no per-frame work enters the Unreal thread.
            bool admitted=api.F<SteamApi.Joinable>("SteamAPI_ISteamMatchmaking_SetLobbyJoinable")(api.Matchmaking,lobby,open?(byte)1:(byte)0)!=0;
            bool published=config.PrivateTest || api.SetPresence("connect",open?"+qdcoop_lobby "+lobby:null);
            if(admitted)joinable=open;
            nextPresence=now+(admitted&&published?5000:500);
        }
        if(!config.PrivateTest && groupSize!=count){if(api.SetPresence("steam_player_group",lobby.ToString())&&api.SetPresence("steam_player_group_size",count))groupSize=count;}
    }
    void RemoveRoute(ulong id){
        if(!routes.Remove(id,out var route))return;
        // Explicit endpoint-scoped departure; room protocol checks its current
        // transport endpoint, never a saved character identity.
        try{File.AppendAllText(PathOf("steam-room-departures.txt"),token+"|"+route.Socket.LocalEndPoint+"|"+Environment.TickCount64+"\n");}catch(IOException){}
        api.F<SteamApi.Session>("SteamAPI_ISteamNetworkingMessages_CloseSessionWithUser")(api.Messages,route.Identity);
        Marshal.FreeHGlobal(route.Identity);route.Socket.Dispose();
    }
    bool Allowed(ulong id)=>id!=0&&lobby!=0&&members.Contains(id)&&(multi&&role=="host"?routes.ContainsKey(id):id==peer);
    void Invite(ulong id){if(!ValidLobby(id.ToString(),out _))return;pendingInvite=Guid.NewGuid().ToString("N")+"|"+id;}
    void Callbacks(){
        api.F<SteamApi.VoidI>("SteamAPI_ManualDispatch_RunFrame")(api.Pipe);
        for(int n=0;n<256 && api.F<SteamApi.Next>("SteamAPI_ManualDispatch_GetNextCallback")(api.Pipe,out var cb)!=0;n++){
            try{
                if(cb.Id==703 && cb.Size>=16)Complete((ulong)Marshal.ReadInt64(cb.Data),Marshal.ReadInt32(cb.Data,8),Marshal.ReadInt32(cb.Data,12));
                else if(cb.Id==1251 && cb.Size>=136){UpdateMembers();ulong id=api.F<SteamApi.IdentityGet>("SteamAPI_SteamNetworkingIdentity_GetSteamID64")(cb.Data);api.F<SteamApi.Session>(Allowed(id)?"SteamAPI_ISteamNetworkingMessages_AcceptSessionWithUser":"SteamAPI_ISteamNetworkingMessages_CloseSessionWithUser")(api.Messages,cb.Data);}
                else if(cb.Id==333 && cb.Size>=16)Invite((ulong)Marshal.ReadInt64(cb.Data));
                else if(cb.Id==337 && cb.Size>=264){string s=Marshal.PtrToStringUTF8(cb.Data+8,256)?.TrimEnd('\0')??"";if(s.StartsWith("+qdcoop_lobby ")&&ValidLobby(s[14..].Trim(),out var id))Invite(id);}
                else if(cb.Id==506)UpdateMembers();
            }finally{api.F<SteamApi.VoidI>("SteamAPI_ManualDispatch_FreeLastCallback")(api.Pipe);}
        }
    }
    void Relay(){
        if(multi&&role=="host")foreach(var route in routes.Values)SendRoute(route.Socket,route.Identity);
        else SendRoute(udp,peerIdentity);
        ReceiveRoutes();
    }
    void SendRoute(Socket socket,IntPtr identity){
        int i=0;
        for(;i<256 && socket.Available>0;i++){
            EndPoint from=new IPEndPoint(IPAddress.Loopback,0);int count;
            try{count=socket.ReceiveFrom(packet.AsSpan(12),SocketFlags.None,ref from);}catch(SocketException){rejected++;continue;}
            if(count<=0||count>MaxDatagram||lobby==0||identity==IntPtr.Zero||from is not IPEndPoint ep||!IPAddress.IsLoopback(ep.Address)){rejected++;continue;}
            if(role=="client" && bridge==null)bridge=ep;
            if(!ep.Equals(bridge)){rejected++;continue;}
            BinaryPrimitives.WriteUInt32LittleEndian(packet,Magic);BinaryPrimitives.WriteUInt64LittleEndian(packet.AsSpan(4),lobby);
            Marshal.Copy(packet,0,sendBuffer,count+12);
            // AutoRestartBrokenSession retains UDP-like recovery after transient route loss.
            int r=api.F<SteamApi.Send>("SteamAPI_ISteamNetworkingMessages_SendMessageToUser")(api.Messages,identity,sendBuffer,(uint)(count+12),1|32,Channel);
            if(r==1)tx++;else{rejected++;diagnostics.SendRejected(r);}
        }
        if(i==256 && socket.Available>0)diagnostics.SendBudgetReached();
    }
    void ReceiveRoutes(){
        int drained=0;
        for(int batch=0;batch<4;batch++){
            int count=api.F<SteamApi.Receive>("SteamAPI_ISteamNetworkingMessages_ReceiveMessagesOnChannel")(api.Messages,Channel,received,received.Length);if(count<=0)break;
            drained+=count;
            long batchTimestamp=diagnostics.ReceiveBatchTimestamp();
            for(int i=0;i<count;i++){
                IntPtr msg=received[i];try{
                    int size=Marshal.ReadInt32(msg,8);ulong sender=api.F<SteamApi.IdentityGet>("SteamAPI_SteamNetworkingIdentity_GetSteamID64")(msg+16);
                    if(size<=12||size>MaxDatagram+12||!Allowed(sender)||bridge==null){rejected++;continue;}
                    Marshal.Copy(Marshal.ReadIntPtr(msg),packet,0,size);
                    if(BinaryPrimitives.ReadUInt32LittleEndian(packet)!=Magic||BinaryPrimitives.ReadUInt64LittleEndian(packet.AsSpan(4))!=lobby){rejected++;continue;}
                    var route=multi&&role=="host"?routes[sender].Socket:udp;
                    diagnostics.ObserveReceive(msg,batchTimestamp);
                    route.SendTo(packet.AsSpan(12,size-12),SocketFlags.None,bridge);rx++;
                }finally{api.F<SteamApi.VoidP>("SteamAPI_SteamNetworkingMessage_t_Release")(msg);}
            }
        }
        if(drained==4*received.Length)diagnostics.ReceiveBudgetReached();
    }
    void Loop(){
        while(!owner.HasExited && !File.Exists(PathOf("stop.steam"))){
            long now=Environment.TickCount64;
            long start=Stopwatch.GetTimestamp();
            diagnostics.LoopStarted(lobby!=0,start);
            if(now>=nextControl){
                nextControl=now+250;string command=Read("steam.command");
                if(command!="" && command!=lastCommand){try{var c=JsonSerializer.Deserialize<Command>(command);if(c!=null){lastCommand=command;Apply(c);}}catch(JsonException){}}
                if(state is "creating" or "joining" && now-requestStarted>30000)Fail("Steam room request timed out");
                UpdateMembers();Publish();
                // Optional UI failure must not terminate the transport service.
                try{social.Tick(now,role=="host"?lobby:0,joinable);}catch(Exception e)when(e is not OutOfMemoryException){Atomic(PathOf("steam-social.txt"),"QDSF1|0|0|0|unavailable\nEND\n");}
                if(pendingInvite!=""&&Atomic(PathOf("steam-invite.txt"),pendingInvite))pendingInvite="";
            }
            long controlEnd=Stopwatch.GetTimestamp();
            Callbacks();
            long callbackEnd=Stopwatch.GetTimestamp();
            Relay();
            if(role!="idle"){
                diagnostics.ObserveLoop(start,controlEnd,callbackEnd,Stopwatch.GetTimestamp());
            }
            long sampleNow=Environment.TickCount64;
            if(diagnostics.SampleDue(sampleNow)){
                IEnumerable<IntPtr> identities=multi&&role=="host"?routes.Values.Select(route=>route.Identity):new[]{peerIdentity};
                diagnostics.Sample(sampleNow,token,role,state,identities,tx,rx,rejected);
            }
            diagnosticLog.Flush();
            if(now>=nextReport){nextReport=now+5000;Atomic(PathOf("steam-metrics.txt"),$"state={state} tx={tx} rx={rx} rejected={rejected} cpu_ms={Process.GetCurrentProcess().TotalProcessorTime.TotalMilliseconds:F0}\n");}
            if(routes.Count>0){var sockets=routes.Values.Select(r=>r.Socket).Append(udp).ToList();Socket.Select(sockets,null,null,10000);}
            else udp.Poll(peer!=0?10000:50000,SelectMode.SelectRead);
        }
    }
    public void Dispose(){if(disposed)return;disposed=true;try{diagnosticLog.Add($"stage=stop session={token} role={role} tx={tx} rx={rx}");diagnosticLog.Flush(true);Leave();}finally{diagnostics.Dispose();api.Dispose();udp.Dispose();owner.Dispose();Marshal.FreeHGlobal(sendBuffer);Marshal.FreeHGlobal(result);}}
    public static int Run(string path){
        Configuration? cfg=null;
        DiagnosticLog? log=null;
        try{
            cfg=JsonSerializer.Deserialize<Configuration>(File.ReadAllText(path))??throw new IOException("Steam config missing");
            log=new(cfg.DiagnosticDirectory,"steam-network-history.txt");
            log.Add("stage=start");log.Flush(true);
            using var service=new SteamService(cfg,log);service.Loop();return 0;
        }
        catch(Exception e){
            log?.Add($"stage=error type={e.GetType().Name} message={e.Message}");log?.Flush(true);
            Console.Error.WriteLine(e);if(cfg!=null){try{Atomic(Path.Combine(cfg.Directory,"steam.status"),JsonSerializer.Serialize(new{State="unavailable",Lobby="0",Port=0,Token="",Error=e.Message}));Atomic(Path.Combine(cfg.Directory,"steam-ui.txt"),"unavailable|0|Steam unavailable; LAN remains available");}catch(IOException){}}
            return 1;
        }
    }
}
