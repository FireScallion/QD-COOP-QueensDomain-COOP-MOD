using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

// Four-seat transport branch. No Unreal calls, AI, inventory, damage or save rules.
// One world publisher; independent peer ACK/retry/RTT and snapshot baselines.
sealed class RoomBridge : IDisposable
{
    sealed class Peer(string id,IPEndPoint endpoint,long now)
    {
        public readonly string Id=id;public readonly IPEndPoint Endpoint=endpoint;
        public readonly long CreatedAt=Environment.TickCount64;
        public long Seen=now,Heartbeat,RosterSeq=-1;public double Rtt=150;
        public readonly PingTracker Pings=new();
        public readonly Dictionary<long,Pending> Reliable=[],Cosmetic=[];
        public readonly Queue<Pending> CombatWaiting=[],OtherWaiting=[]; public long RetryCount;
        public readonly HashSet<long> Received=[];public readonly Queue<long> Order=[];
        public readonly WorldChannel World=new();public readonly EnemySendCache Enemies=new();
    }
    readonly Config cfg;readonly string identity=Guid.NewGuid().ToString("N");
    readonly Dictionary<string,Peer> peers=[];
    readonly Dictionary<string,(long Seq,long At,string Text)> states=[],visuals=[],enemies=[];
    readonly Stopwatch clock=Stopwatch.StartNew();readonly UdpClient udp;readonly Wire wire;
    sealed record Dispatch(Message Message,bool Cosmetic,List<Peer> Targets);
    readonly List<Dispatch> outgoing=[];
    readonly Queue<string> combatTrace=[]; bool traceDirty;
    readonly DiagnosticLog diagnosticLog, combatLog;
    long nextDiagnosticSample;
    string? lastFeedbackSample;
    void Trace(string stage,string peer,Message m,long age=0){
        if(!Combat(m))return;
        combatTrace.Enqueue($"utc={DateTime.UtcNow:O} localMs={clock.ElapsedMilliseconds} stage={stage} peer={peer} seq={m.Seq} ageMs={age} payload={m.Payload}");
        if(cfg.DiagnosticDirectory!=null)combatLog.Add($"monoMs={Environment.TickCount64} stage={stage} peer={peer} seq={m.Seq} ageMs={age} payload={m.Payload}");
        while(combatTrace.Count>128)combatTrace.Dequeue();traceDirty=true;
    }
    readonly MemoryMailbox mailbox;readonly EventJournal journal;readonly NetworkWake wake;readonly Mutex mutex;
    readonly EventJournal departures;
    readonly IPEndPoint? host;RoomDirectory? room;string session="",world="",roster="",state="",visual="";
    string? parsedEnemyText; (string Key,string Text)[] parsedEnemies=[];
    long seq,hello=-1000,status=-1000,membersAt=-1000,stateAt=-1000,worldAt=-1000,enemyAt=-1000,rosterAt=-1000;
    long ownerAt,controlAt,rx,tx,rejected,retries;bool dirtyStates=true,dirtyVisuals=true,dirtyEnemies=true,running=true;
    public RoomBridge(Config config)
    {
        cfg=config;
        diagnosticLog=new(cfg.DiagnosticDirectory,"bridge-transport.txt");
        combatLog=new(cfg.DiagnosticDirectory,"combat-transport-trace.txt");
        if(cfg.Role is not ("host" or "client")||cfg.MaxPlayers is <2 or >4||cfg.Port is <1024 or >65535||cfg.Key.Length<8)throw new ArgumentException("Invalid room configuration");
        Directory.CreateDirectory(cfg.Directory);
        string departurePath=Path.Combine(cfg.Directory,"steam-room-departures.txt");
        using(File.Open(departurePath,FileMode.OpenOrCreate,FileAccess.Write,FileShare.ReadWrite|FileShare.Delete)){}
        departures=new(departurePath);departures.SkipExisting();
        mutex=new Mutex(true,"Local\\QDCoopBridge_"+Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(Path.GetFullPath(cfg.Directory))))[..24],out bool created);
        if(!created)throw new InvalidOperationException("Bridge already running for this profile");
        mailbox=new(cfg.IpcChannel);mailbox.DiscardEvents(0);wire=new(Encoding.UTF8.GetBytes(cfg.Key));
        journal=new(Path.Combine(cfg.Directory,"out.events"),mailbox.Enabled?()=>mailbox.EventRevision(0):null);
        udp=new(new IPEndPoint(IPAddress.Any,cfg.Role=="host"?cfg.Port:0));udp.Client.ReceiveBufferSize=4*1024*1024;udp.Client.SendBufferSize=1024*1024;
        if(OperatingSystem.IsWindows())udp.Client.IOControl(unchecked((int)0x9800000C),new byte[4],null);
        wake=new(udp.Client,mailbox.Ready);host=cfg.Role=="client"?new(IPAddress.Parse(cfg.Host),cfg.Port):null;
        if(cfg.Role=="host"){session=Guid.NewGuid().ToString("N");room=new(identity,cfg.MaxPlayers);}
        foreach(string name in new[]{"in.state","in.visual","in.world","in.enemy","in.roster"})Write(name,"");
        File.WriteAllText(Path.Combine(cfg.Directory,"in.events"),"");journal.SkipExisting();
    }
    void Log(string text){
        diagnosticLog.Add(text);
        diagnosticLog.Flush(true);
        File.AppendAllText(Path.Combine(cfg.Directory,"bridge.log"),DateTime.UtcNow.ToString("O")+" ROOM2 "+text+"\n");
    }
    Message Make(string kind,string payload="",long ack=0)=>new(2,cfg.Build,identity,session,++seq,kind,payload,ack);
    void Send(Message m,IPEndPoint endpoint){foreach(var packet in wire.Encode(m))try{udp.Send(packet,endpoint);tx++;}catch(SocketException){rejected++;}}
    bool Write(string name,string value)
    {
        if(mailbox.Handles(name))return mailbox.Write(name,value);
        try{var p=Path.Combine(cfg.Directory,name);File.WriteAllText(p+".tmp",value,new UTF8Encoding(false));File.Move(p+".tmp",p,true);return true;}
        catch(Exception e)when(e is IOException or UnauthorizedAccessException){return false;}
    }
    string? Read(string name)
    {
        if(mailbox.Handles(name))return mailbox.Read(name);
        try{using var stream=new FileStream(Path.Combine(cfg.Directory,name),FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete);using var reader=new StreamReader(stream);return reader.ReadToEnd();}catch(Exception e)when(e is IOException or UnauthorizedAccessException){return null;}
    }
    bool Fresh(string name)=>mailbox.Handles(name)?mailbox.Fresh(name):DateTime.UtcNow-File.GetLastWriteTimeUtc(Path.Combine(cfg.Directory,name))<TimeSpan.FromSeconds(3);
    bool Alive()
    {
        if(cfg.OwnerPid==0||clock.ElapsedMilliseconds<ownerAt)return true;ownerAt=clock.ElapsedMilliseconds+250;
        try{using var p=Process.GetProcessById(cfg.OwnerPid);return !p.HasExited&&p.StartTime.ToUniversalTime().Ticks==cfg.OwnerStartTicks;}catch{return false;}
    }
    static bool Frame(string value,string magic)=>value.Length<=7000&&value.StartsWith(magic+"\n")&&value.EndsWith("\nEND\n");
    static string? EnemyKey(string s){if(s.Length>6900||s.Contains('\n')||s.Contains('\r'))return null;var f=s.Split('|',6);return f.Length==6&&f[0]=="N"&&f[1].Length<=80&&int.TryParse(f[3],out int id)&&id is >0 and <=100000?f[1]+":"+id:null;}
    void Drop(Peer p,string reason)
    {
        peers.Remove(p.Id);states.Remove(p.Id);visuals.Remove(p.Id);dirtyStates=dirtyVisuals=true;
        if(cfg.Role=="host"){room!.Leave(p.Id);membersAt=-1000;}else{session="";room=null;states.Clear();visuals.Clear();enemies.Clear();world="";roster="";state="";visual="";dirtyEnemies=true;Write("in.world","");Write("in.roster","");}
        Log("left "+p.Id+" "+reason);
    }
    void Membership(){if(room==null)return;var m=Make("MEMBERS",room.Encode(session));foreach(var p in peers.Values)Send(m,p.Endpoint);membersAt=clock.ElapsedMilliseconds;}
    bool StoreEvent(string origin,long originalSeq,string value)
    {
        string line=origin+"-"+originalSeq+"|"+value+"\n";
        if(mailbox.Enabled&&MemoryMailbox.IsCosmetic(value))return mailbox.PushEvent(1,line);
        try{File.AppendAllText(Path.Combine(cfg.Directory,"in.events"),line,new UTF8Encoding(false));mailbox.NotifyEvents(1);return true;}
        catch(Exception e)when(e is IOException or UnauthorizedAccessException){return false;}
    }
    static bool Combat(Message m){
        if(m.Kind!="EVENT")return false;var f=m.Payload.Split('|');
        return f.Length>3&&((f[0]=="NPC"&&f[3] is "H" or "F")||(f[0]=="THT"&&f[3]=="D"));
    }
    bool Queue(Peer p,Message m,bool cosmetic){
        if(cosmetic){if(p.Cosmetic.Count>=128)p.Cosmetic.Remove(p.Cosmetic.MinBy(x=>x.Value.Created).Key);
            p.Cosmetic.Add(m.Seq,new(m,clock.ElapsedMilliseconds,clock.ElapsedMilliseconds,0));Send(m,p.Endpoint);return true;}
        // Retain ownership on failed admission; never evict gameplay messages.
        if(p.Reliable.Count+p.CombatWaiting.Count+p.OtherWaiting.Count>=4096)return false;
        (Combat(m)?p.CombatWaiting:p.OtherWaiting).Enqueue(new(m,0,clock.ElapsedMilliseconds,0));return true;
    }
    void Flush(Peer p){
        for(int i=0;i<16;i++){
            bool combat=p.CombatWaiting.Count>0&&(i%4!=3||p.OtherWaiting.Count==0||p.Reliable.Count>=448);
            var q=combat?p.CombatWaiting:p.OtherWaiting;
            if(q.Count==0||p.Reliable.Count>=(combat?512:448))break;
            var v=q.Dequeue() with{SentAt=clock.ElapsedMilliseconds};p.Reliable.Add(v.Message.Seq,v);Send(v.Message,p.Endpoint);Trace("send",p.Id,v.Message,clock.ElapsedMilliseconds-v.Created);
        }
    }
    void DispatchOutgoing(){
        foreach(var d in outgoing.ToArray()){
            for(int i=d.Targets.Count-1;i>=0;i--){var p=d.Targets[i];
                if(!peers.TryGetValue(p.Id,out var current)||!ReferenceEquals(current,p)||Queue(p,d.Message,d.Cosmetic))d.Targets.RemoveAt(i);
            }
            if(d.Targets.Count==0)outgoing.Remove(d);
        }
    }
    static bool RescueRoute(string payload)
    {
        var fields=payload.Split('|');
        return fields.Length==8&&fields[0]=="RV"&&fields[4] is "HELLO2" or "P2" or "R2" or "C2" or "D2" or "X2" or "N2" or "A2";
    }
    void Receive(Message m,IPEndPoint endpoint)
    {
        long now=clock.ElapsedMilliseconds;
        if(m.Version!=2||m.Build!=cfg.Build||m.Id==identity||m.Id==null||!RoomDirectory.Id(m.Id)||m.Payload==null||m.Payload.Length>8000||m.Seq<=0||m.Session==null){rejected++;return;}
        if(cfg.Role=="host"&&m.Kind=="HELLO"){
            if(m.Session!=""||m.Payload!="room2")return;
            if(peers.TryGetValue(m.Id,out var old)&&!old.Endpoint.Equals(endpoint)){rejected++;return;}
            if(peers.Values.Any(p=>p.Id!=m.Id&&p.Endpoint.Equals(endpoint))){rejected++;return;}
            bool joined=!peers.ContainsKey(m.Id);if(room!.Join(m.Id)==null){Send(Make("FULL"),endpoint);return;}
            if(joined){var p=new Peer(m.Id,endpoint,now);p.World.Publish(world);peers.Add(m.Id,p);dirtyStates=dirtyVisuals=true;Log("joined "+m.Id);}
            peers[m.Id].Seen=now;Send(Make("WELCOME",room.Encode(session)),endpoint);Membership();
            // A joining peer gets all current poses, not only the next local change.
            if(Frame(state,"QDCP1"))Send(Make("STATE",state),endpoint);
            foreach(var f in states)if(f.Key!=m.Id)Send(Make("FROMSTATE",f.Key+"\n"+f.Value.Text),endpoint);
            if(Frame(visual,"QDVF1"))Send(Make("VISUAL",visual),endpoint);
            foreach(var f in visuals)if(f.Key!=m.Id)Send(Make("FROMVISUAL",f.Key+"\n"+f.Value.Text),endpoint);
            enemyAt=rosterAt=-1000;return;
        }
        if(cfg.Role=="client"&&m.Kind=="WELCOME"&&endpoint.Equals(host)&&RoomDirectory.Id(m.Session)){
            var header=m.Payload.Split('\n',2)[0].Split('|');if(header.Length!=4||!int.TryParse(header[3],out int capacity)||capacity is <2 or >4)return;
            var next=new RoomDirectory(m.Id,capacity);if(!next.Accept(m.Payload,m.Session)||!next.Members.ContainsKey(identity))return;
            if(session!=m.Session||!peers.ContainsKey(m.Id)){foreach(var p in peers.Values.ToArray())Drop(p,"new host session");session=m.Session;peers.Add(m.Id,new(m.Id,endpoint,now));room=next;stateAt=-1000;Log("joined host "+m.Id);}else room!.Accept(m.Payload,session);
            peers[m.Id].Seen=now;dirtyStates=dirtyVisuals=true;return;
        }
        if(!peers.TryGetValue(m.Id,out var peer)||!peer.Endpoint.Equals(endpoint)||session!=m.Session){rejected++;return;}
        peer.Seen=now;
        switch(m.Kind){
            case "GOODBYE":Drop(peer,"goodbye");break;
            case "PING":Send(Make("PONG","",m.Seq),endpoint);break;
            case "PONG":if(peer.Pings.Receive(m.Ack,now,out long elapsed))peer.Rtt=peer.Rtt*.8+elapsed*.2;break;
            case "MEMBERS":if(cfg.Role=="client"&&room!.Accept(m.Payload,session)){foreach(var id in states.Keys.Where(id=>!room.Members.ContainsKey(id)).ToArray())states.Remove(id);foreach(var id in visuals.Keys.Where(id=>!room.Members.ContainsKey(id)).ToArray())visuals.Remove(id);dirtyStates=dirtyVisuals=true;}break;
            case "STATE":case "VISUAL":case "FROMSTATE":case "FROMVISUAL":{
                bool isVisual=m.Kind.EndsWith("VISUAL"),relay=m.Kind.StartsWith("FROM");string origin=m.Id,payload=m.Payload;
                if(relay){if(cfg.Role!="client")return;int n=payload.IndexOf('\n');if(n!=32)return;origin=payload[..n];payload=payload[(n+1)..];}
                if(origin==identity||!room!.Members.ContainsKey(origin)||!Frame(payload,isVisual?"QDVF1":"QDCP1"))return;
                var values=isVisual?visuals:states;if(values.TryGetValue(origin,out var previous)&&m.Seq<=previous.Seq)return;
                values[origin]=(m.Seq,now,payload);if(isVisual)dirtyVisuals=true;else dirtyStates=true;
                if(cfg.Role=="host"){var forward=Make(isVisual?"FROMVISUAL":"FROMSTATE",origin+"\n"+payload);foreach(var p in peers.Values)if(p.Id!=origin)Send(forward,p.Endpoint);}break;
            }
            case "ROSTER":if(cfg.Role=="client"&&m.Seq>peer.RosterSeq&&m.Payload.StartsWith("QDER1|")&&m.Payload.EndsWith("\nEND\n")&&Write("in.roster",m.Payload))peer.RosterSeq=m.Seq;break;
            case "WORLD":if(cfg.Role=="client")peer.World.Receive(m.Payload,now,ack=>Send(Make("WORLDACK",ack),endpoint),data=>Write("in.world",data));break;
            case "WORLDACK":if(cfg.Role=="host")peer.World.Acknowledge(m.Payload);break;
            case "ENEMY":if(cfg.Role=="client"&&EnemyKey(m.Payload) is string key&&(!enemies.TryGetValue(key,out var e)||m.Seq>e.Seq)&&(enemies.ContainsKey(key)||enemies.Count<256)){enemies[key]=(m.Seq,now,m.Payload);dirtyEnemies=true;}break;
            case "ACK":
                if(peer.Reliable.Remove(m.Ack,out var acked)&&cfg.DiagnosticDirectory!=null)
                    Trace("ack",m.Id,acked.Message,now-acked.Created);
                peer.Cosmetic.Remove(m.Ack);break;
            case "ROUTE":{
                if(cfg.Role!="host")return;
                var f=m.Payload.Split('|',2);
                if(f.Length!=2||!RoomDirectory.Id(f[0])||f[0]==m.Id||f[1].Length>1000||f[1].Contains('\n')||f[1].Contains('\r')||!RescueRoute(f[1]))return;
                if(!peer.Received.Contains(m.Seq)){
                    if(f[0]==identity){if(!StoreEvent(m.Id,m.Seq,f[1]))return;}
                    else if(peers.TryGetValue(f[0],out var target)){
                        // Do not ACK the source until the destination's reliable
                        // queue owns this message. Lua settlement has its own ACK.
                        if(!Queue(target,Make("FROMEVENT",m.Id+"|"+m.Seq+"|"+f[1]),false))return;
                    }else rejected++; // recipient left; durable gameplay retry can rediscover it
                    peer.Received.Add(m.Seq);peer.Order.Enqueue(m.Seq);while(peer.Order.Count>4096)peer.Received.Remove(peer.Order.Dequeue());
                }
                Send(Make("ACK","",m.Seq),endpoint);break;
            }
            case "EVENT":case "FROMEVENT":{
                string origin=m.Id,payload=m.Payload;long originalSeq=m.Seq;
                if(m.Kind=="FROMEVENT"){if(cfg.Role!="client")return;var f=payload.Split('|',3);if(f.Length!=3||!room!.Members.ContainsKey(f[0])||f[0]==identity||!long.TryParse(f[1],out originalSeq)||originalSeq<=0)return;origin=f[0];payload=f[2];}
                if(payload.Length>1000||payload.Contains('\n')||payload.Contains('\r'))return;
                if(!peer.Received.Contains(m.Seq)){
                    if(!StoreEvent(origin,originalSeq,payload))return;
                    Trace("receive",origin,m with{Kind="EVENT",Payload=payload});
                    peer.Received.Add(m.Seq);peer.Order.Enqueue(m.Seq);while(peer.Order.Count>4096)peer.Received.Remove(peer.Order.Dequeue());
                    if(cfg.Role=="host"&&MemoryMailbox.IsCosmetic(payload)){var forward=Make("FROMEVENT",origin+"|"+originalSeq+"|"+payload);foreach(var p in peers.Values)if(p.Id!=origin)Queue(p,forward,true);}
                }
                Send(Make("ACK","",m.Seq),endpoint);break;
            }
        }
    }
    double RetryDelay(Peer p,Pending q)=>Math.Clamp(p.Rtt*1.6+40,120,1200)*Math.Min(4,1+q.Attempts*.35);
    void Tick()
    {
        long now=clock.ElapsedMilliseconds;
        for(int i=0;i<128&&udp.Available>0;i++){IPEndPoint from=new(IPAddress.Any,0);try{var m=wire.Decode(udp.Receive(ref from),from,now);if(m!=null){rx++;Receive(m,from);}}catch(Exception e)when(e is JsonException or FormatException or ArgumentException or IOException or SocketException){rejected++;}}
        foreach(var p in peers.Values.Where(p=>now-p.Seen>20000).ToArray())Drop(p,"timeout");
        if(cfg.Role=="client"&&peers.Count==0&&now-hello>=500){Send(Make("HELLO","room2"),host!);hello=now;}
        if(cfg.Role=="host"&&peers.Count>0&&now-membersAt>=500)Membership();
        if(peers.Count>0){
            uint dirty=mailbox.DirtyMask;
            if(now-stateAt>=10&&(dirty&5)!=0){
                var s=Read("out.state");if(s!=null&&s!=state&&Fresh("out.state")&&Frame(s,"QDCP1")){state=s;var m=Make("STATE",s);foreach(var p in peers.Values)Send(m,p.Endpoint);}
                var v=Read("out.visual");if(v!=null&&v!=visual&&Fresh("out.visual")&&Frame(v,"QDVF1")){visual=v;var m=Make("VISUAL",v);foreach(var p in peers.Values)Send(m,p.Endpoint);}stateAt=now;
            }
            if(cfg.Role=="host"){
                if(now-worldAt>=100&&(dirty&(1u<<8))!=0){var value=Read("out.world");if(value!=null&&value!=world){world=value;foreach(var p in peers.Values)p.World.Publish(value);}worldAt=now;}
                if(now-rosterAt>=500){roster=Read("out.roster")??"";if(roster.Length<=7000&&roster.StartsWith("QDER1|")&&Fresh("out.roster")){var m=Make("ROSTER",roster);foreach(var p in peers.Values)Send(m,p.Endpoint);}rosterAt=now;}
                if(now-enemyAt>=25){var value=Read("out.enemy");if(value!=null&&value.Length<=450000&&Fresh("out.enemy")){
                    if(value!=parsedEnemyText){parsedEnemyText=value;parsedEnemies=value.Split('\n').Take(64).Select(s=>(EnemyKey(s),s)).Where(e=>e.Item1!=null).Select(e=>(e.Item1!,e.s)).ToArray();}
                    foreach(var e in parsedEnemies)foreach(var p in peers.Values)if(p.Enemies.ShouldSend(e.Key,e.Text,now))Send(Make("ENEMY",e.Text),p.Endpoint);
                    foreach(var p in peers.Values)p.Enemies.Trim(now);
                }enemyAt=now;}
            }
            // Bounded backpressure affects network settlement only, never local input.
            DispatchOutgoing();
            if(outgoing.Count<=32)foreach(var line in journal.Read(16).Concat(mailbox.DrainEvents(0,16))){
                if(line.Length==0)continue;string payload=line;IEnumerable<Peer> destinations=peers.Values;
                if(line.StartsWith("TO|")){
                    var f=line.Split('|',3);if(f.Length!=3||!RoomDirectory.Id(f[1]))continue;payload=f[2];
                    if(cfg.Role=="client"){
                        if(payload.Length<=1000&&!payload.Contains('\r')&&RescueRoute(payload)&&room!.Members.ContainsKey(f[1])&&f[1]!=identity)
                            outgoing.Add(new(Make("ROUTE",f[1]+"|"+payload),false,[peers[room.Host]]));
                        continue;
                    }
                    if(!peers.TryGetValue(f[1],out var dest))continue;destinations=[dest];
                }
                if(payload.Length>1000||payload.Contains('\r'))continue;
                var m=Make("EVENT",payload);bool cosmetic=MemoryMailbox.IsCosmetic(payload);outgoing.Add(new(m,cosmetic,destinations.ToList()));
            }
            DispatchOutgoing();
            foreach(var p in peers.Values){
                Flush(p);
                if(cfg.Role=="host")p.World.Tick(now,payload=>Send(Make("WORLD",payload),p.Endpoint));
                if(now-p.Heartbeat>=1000){var ping=Make("PING");p.Pings.Sent(ping.Seq,now);Send(ping,p.Endpoint);p.Heartbeat=now;}
                int budget=8;foreach(var q in new[]{p.Reliable,p.Cosmetic}){
                 if(!q.Values.Any(v=>now-v.SentAt>=RetryDelay(p,v)||(ReferenceEquals(q,p.Cosmetic)&&now-v.Created>1200)))continue;
                 foreach(var entry in q.OrderBy(x=>x.Value.SentAt).ToArray()){
                    if(ReferenceEquals(q,p.Cosmetic)&&now-entry.Value.Created>1200){q.Remove(entry.Key);continue;}
                    if(budget>0&&now-entry.Value.SentAt>=RetryDelay(p,entry.Value)){Send(entry.Value.Message,p.Endpoint);Trace("retry",p.Id,entry.Value.Message,now-entry.Value.Created);q[entry.Key]=entry.Value with{SentAt=now,Attempts=entry.Value.Attempts+1};retries++;p.RetryCount++;budget--;}
                 }
                }
            }
        }else{outgoing.Clear();journal.SkipExisting();mailbox.DiscardEvents(0);}
        foreach(var group in new[]{states,visuals,enemies})foreach(var key in group.Where(e=>now-e.Value.At>3000).Select(e=>e.Key).ToArray()){group.Remove(key);if(ReferenceEquals(group,states))dirtyStates=true;else if(ReferenceEquals(group,visuals))dirtyVisuals=true;else dirtyEnemies=true;}
        if(dirtyStates){if(Write("in.state",room?.Snapshot(session,identity,states.Select(x=>(x.Key,x.Value.Text)))??""))dirtyStates=false;}
        if(dirtyVisuals){if(Write("in.visual",room?.Snapshot(session,identity,visuals.Select(x=>(x.Key,x.Value.Text)),"QDRV1")??""))dirtyVisuals=false;}
        if(dirtyEnemies&&Write("in.enemy",string.Join('\n',enemies.Values.Select(x=>x.Text))+"\n"))dirtyEnemies=false;
        if(now-status>=250){
            string first=cfg.Role=="client"?room?.Host??"":peers.Keys.FirstOrDefault()??"";
            Write("status.txt",$"{(peers.Count>0?"connected":"waiting")}|{session}|{first}|{rx}|{tx}|{peers.Values.Sum(p=>p.Reliable.Count)}|{retries}|{rejected}|0|{DateTimeOffset.UtcNow.ToUnixTimeSeconds()}\n");
            Write("room-status.txt",$"protocol=2 identity={identity} host={room?.Host} members={room?.Members.Count??0} capacity={room?.Capacity??cfg.MaxPlayers} reliable={peers.Values.Sum(p=>p.Reliable.Count)} cosmetic={peers.Values.Sum(p=>p.Cosmetic.Count)} rejected={rejected}\n");status=now;
            if(traceDirty&&Write("combat-transport-trace.txt",string.Join("\n",combatTrace)+"\n"))traceDirty=false;
            string transport=string.Join("\n",peers.Values.Select(p=>$"peer={p.Id} rttMs={p.Rtt:F1} inFlight={p.Reliable.Count} combatWaiting={p.CombatWaiting.Count} otherWaiting={p.OtherWaiting.Count} oldestMs={p.Reliable.Values.Concat(p.CombatWaiting).Concat(p.OtherWaiting).Select(v=>now-v.Created).DefaultIfEmpty(0).Max()} retries={p.RetryCount} dispatchPending={outgoing.Count}"));
            Write("transport-status.txt",transport+"\n");
            if(cfg.DiagnosticDirectory!=null&&now>=nextDiagnosticSample){
                nextDiagnosticSample=now+500;
                diagnosticLog.Add($"stage=sample monoMs={Environment.TickCount64} room={session} role={cfg.Role} peers={peers.Count} rx={rx} tx={tx} rejected={rejected} retries={retries} "+transport.Replace('\n',' '));
                if(cfg.Role=="client"&&Read("attack-feedback-status.txt") is { Length: >0 and <=512 } feedback&&feedback!=lastFeedbackSample){
                    lastFeedbackSample=feedback;
                    diagnosticLog.Add("stage=guest_feedback "+feedback.Trim());
                }
                diagnosticLog.Flush();
            }
        }
        combatLog.Flush();
    }
    public static int Run(Config cfg)
    {
        using var bridge=new RoomBridge(cfg);bridge.Log("start "+cfg.Role+" "+bridge.udp.Client.LocalEndPoint);
        ConsoleCancelEventHandler stop=(_,e)=>{e.Cancel=true;bridge.running=false;};Console.CancelKeyPress+=stop;
        try{while(bridge.running&&bridge.Alive()){
            long now=bridge.clock.ElapsedMilliseconds;if(now>=bridge.controlAt){
                if(File.Exists(Path.Combine(cfg.Directory,"stop.bridge")))break;bridge.controlAt=now+250;
                if(cfg.Role=="host"&&cfg.RoomToken!="")foreach(var line in bridge.departures.Read(16,8192)){
                    var f=line.Split('|');if(f.Length!=3||f[0]!=cfg.RoomToken||!long.TryParse(f[2],out var removedAt)||!IPEndPoint.TryParse(f[1],out var endpoint)||!IPAddress.IsLoopback(endpoint.Address))continue;
                    var departed=bridge.peers.Values.FirstOrDefault(p=>p.Endpoint.Equals(endpoint)&&p.CreatedAt<=removedAt);if(departed!=null)bridge.Drop(departed,"Steam membership left");
                }
            }
            try{bridge.Tick();}catch(Exception e)when(e is IOException or UnauthorizedAccessException){bridge.rejected++;}
            // All waiting is in this background process, outside the game thread.
            bridge.wake.Wait(bridge.peers.Count>0?10:100);
        }}finally{
            Console.CancelKeyPress-=stop;
            foreach(var p in bridge.peers.Values){var m=bridge.Make("GOODBYE");for(int i=0;i<3;i++)bridge.Send(m,p.Endpoint);}
            bridge.combatLog.Add("stage=stop");
            bridge.combatLog.Flush(true);
            bridge.diagnosticLog.Add("stage=stop");
            bridge.diagnosticLog.Flush(true);
            bridge.Write("status.txt","stopped||||||||\n");bridge.Log("stop");
        }
        return 0;
    }
    public void Dispose(){wake.Dispose();udp.Dispose();mailbox.Dispose();mutex.Dispose();}
}
