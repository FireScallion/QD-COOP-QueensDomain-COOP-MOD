// Retain each outstanding probe so a reply delayed beyond the next heartbeat
// can still update RTT. Timestamps belong to this process's monotonic clock.
sealed class PingTracker
{
    readonly Dictionary<long, long> sent = new();
    public void Sent(long sequence, long now)
    {
        foreach (var key in sent.Where(p => now - p.Value > 20000).Select(p => p.Key).ToArray())
            sent.Remove(key);
        if (sent.Count >= 32) sent.Remove(sent.MinBy(p => p.Value).Key);
        sent[sequence] = now;
    }
    public bool Receive(long sequence, long now, out long elapsed)
    {
        elapsed = 0;
        if (!sent.Remove(sequence, out long start)) return false;
        elapsed = now - start;
        return elapsed >= 0 && elapsed <= 20000;
    }
}
