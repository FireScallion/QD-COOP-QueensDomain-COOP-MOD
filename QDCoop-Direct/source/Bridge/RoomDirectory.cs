using System.Net;
using System.Text;

// Transport membership, deliberately separate from saved character identifiers.
// A copied character save must never decide packet routing or room ownership.
sealed class RoomDirectory
{
    public record Member(string Id, int Slot);
    public readonly string Host;
    public readonly int Capacity;
    public long Revision { get; private set; } = 1;
    public Dictionary<string, Member> Members { get; } = [];
    public RoomDirectory(string host, int capacity)
    {
        if (!Id(host) || capacity is < 2 or > 4) throw new ArgumentException("Invalid room");
        Host=host;Capacity=capacity;Members[host]=new(host,0);
    }
    public static bool Id(string value)=>value.Length==32&&value.All(Uri.IsHexDigit);
    public Member? Join(string id)
    {
        if (!Id(id)) return null;
        if (Members.TryGetValue(id,out var existing)) return existing;
        if (Members.Count>=Capacity) return null;
        int slot=Enumerable.Range(1,Capacity-1).First(i=>Members.Values.All(m=>m.Slot!=i));
        var member=new Member(id,slot);Members.Add(id,member);Revision++;return member;
    }
    public bool Leave(string id)
    {
        if(id==Host||!Members.Remove(id))return false;
        Revision++;return true;
    }
    public string Encode(string session)=>$"QDR1|{session}|{Revision}|{Capacity}\n"+
        string.Join('\n',Members.Values.OrderBy(m=>m.Slot).Select(m=>$"{m.Id}|{m.Slot}"))+"\nEND\n";
    public bool Accept(string text,string session)
    {
        var lines=text.Split('\n');var h=lines[0].Split('|');
        if(h.Length!=4||h[0]!="QDR1"||h[1]!=session||!long.TryParse(h[2],out long rev)||rev<Revision||
            !int.TryParse(h[3],out int capacity)||capacity!=Capacity||lines.Length<5||lines.Length>7||lines[^2]!="END"||lines[^1]!="")return false;
        var next=new Dictionary<string,Member>();var slots=new HashSet<int>();
        foreach(var line in lines.Skip(1).SkipLast(2)){
            var f=line.Split('|');if(f.Length!=2||!Id(f[0])||!int.TryParse(f[1],out int slot)||slot<0||slot>=Capacity||!slots.Add(slot)||!next.TryAdd(f[0],new(f[0],slot)))return false;
        }
        if(!next.TryGetValue(Host,out var host)||host.Slot!=0||next.Count>Capacity)return false;
        if(rev==Revision&&Members.Count>1)return Encode(session)==text;
        Members.Clear();foreach(var pair in next)Members.Add(pair.Key,pair.Value);Revision=rev;return true;
    }
    public string Snapshot(string session,string self,IEnumerable<(string Id,string Payload)> frames,string magic="QDRS1")
    {
        var b=new StringBuilder($"{magic}|{session}|{self}|{Host}|{Revision}|{Capacity}\n");
        foreach(var m in Members.Values.OrderBy(m=>m.Slot))b.Append($"M|{m.Id}|{m.Slot}\n");
        foreach(var f in frames.OrderBy(f=>f.Id))if(f.Id!=self&&Members.ContainsKey(f.Id)){
            b.Append($"F|{f.Id}|{Encoding.UTF8.GetByteCount(f.Payload)}\n");b.Append(f.Payload);
        }
        b.Append("END\n");return b.ToString();
    }
}
