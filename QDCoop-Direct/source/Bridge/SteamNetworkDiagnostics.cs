using System.Diagnostics;
using System.Runtime.InteropServices;

// Steamworks x64 ABI. Use a full native buffer for extensible SDK structures.
// Only documented fields shared by the supported interface versions are read.
sealed class SteamNetworkDiagnostics : IDisposable
{
    const int ReceivedTimestampOffset = 160; // SteamNetworkingMessage_t on Windows x64
    readonly SteamApi api;
    readonly SteamApi.SessionInfo? sessionInfo;
    readonly SteamApi.LocalTimestamp? localTimestamp;
    readonly IntPtr quickStatus = Marshal.AllocHGlobal(512);
    readonly IntPtr connectionInfo = Marshal.AllocHGlobal(1024);
    readonly DiagnosticLog log;
    readonly Dictionary<int,long> sendErrors = new();
    long nextSample, previousLoop;
    double loopGap, controlTime, callbackTime, relayTime, receiveWait;
    int receiveFull, sendFull;

    public SteamNetworkDiagnostics(SteamApi api, DiagnosticLog log)
    {
        this.api = api;
        this.log = log;
        sessionInfo = api.Optional<SteamApi.SessionInfo>("SteamAPI_ISteamNetworkingMessages_GetSessionConnectionInfo");
        localTimestamp = api.Optional<SteamApi.LocalTimestamp>("SteamAPI_ISteamNetworkingUtils_GetLocalTimestamp");
        log.Add($"stage=sdk_ready sessionInfo={sessionInfo != null} receiveClock={localTimestamp != null}");
        log.Flush(true);
    }

    public void LoopStarted(bool active, long timestamp)
    {
        if (active && previousLoop != 0)
            loopGap = Math.Max(loopGap, Stopwatch.GetElapsedTime(previousLoop, timestamp).TotalMilliseconds);
        previousLoop = active ? timestamp : 0;
    }

    public void ObserveLoop(long start, long controlEnd, long callbackEnd, long relayEnd)
    {
        controlTime = Math.Max(controlTime, Stopwatch.GetElapsedTime(start, controlEnd).TotalMilliseconds);
        callbackTime = Math.Max(callbackTime, Stopwatch.GetElapsedTime(controlEnd, callbackEnd).TotalMilliseconds);
        relayTime = Math.Max(relayTime, Stopwatch.GetElapsedTime(callbackEnd, relayEnd).TotalMilliseconds);
    }

    public void SendRejected(int code) => sendErrors[code] = sendErrors.GetValueOrDefault(code) + 1;
    public void SendBudgetReached() => sendFull++;
    public void ReceiveBudgetReached() => receiveFull++;
    public long ReceiveBatchTimestamp() => localTimestamp?.Invoke(api.Networking) ?? 0;
    public bool SampleDue(long now) => now >= nextSample;
    public void ObserveReceive(IntPtr message, long batchTimestamp)
    {
        if (batchTimestamp == 0) return;
        long received = Marshal.ReadInt64(message, ReceivedTimestampOffset);
        if (received > 0 && received <= batchTimestamp)
            receiveWait = Math.Max(receiveWait, (batchTimestamp - received) / 1000.0);
    }

    public void Sample(long now, string session, string role, string state, IEnumerable<IntPtr> peers, long tx, long rx, long rejected)
    {
        nextSample = now + (role == "idle" ? 2000 : 500);
        var routes = peers.Where(identity => identity != IntPtr.Zero).ToArray();
        string errors = sendErrors.Count == 0 ? "-" : string.Join(',', sendErrors.OrderBy(x => x.Key).Select(x => $"{x.Key}:{x.Value}"));
        string common = FormattableString.Invariant(
            $"stage=sample session={session} role={role} state={state} tx={tx} rx={rx} rejected={rejected} loopGapMaxMs={loopGap:F1} controlMaxMs={controlTime:F1} callbacksMaxMs={callbackTime:F1} relayMaxMs={relayTime:F1} receiveWaitMaxMs={receiveWait:F1} sendBudgetHits={sendFull} receiveBudgetHits={receiveFull} sendErrors={errors}");
        if (routes.Length == 0) log.Add(common + " routes=0");
        for (int i = 0; i < routes.Length; i++)
            log.Add(common + $" route={i + 1} " + ReadSession(routes[i]));
        loopGap = controlTime = callbackTime = relayTime = receiveWait = 0;
        receiveFull = sendFull = 0;
        sendErrors.Clear();
    }

    string ReadSession(IntPtr identity)
    {
        if (sessionInfo == null) return "sdkStatus=unavailable";
        int state = sessionInfo(api.Messages, identity, connectionInfo, quickStatus);
        if (state != 3) return $"sdkState={state}";
        // SteamNetConnectionRealTimeStatus_t: flags and speeds precede the 64-bit queue time.
        int ping = Marshal.ReadInt32(quickStatus, 4);
        int pendingUnreliable = Marshal.ReadInt32(quickStatus, 36);
        int pendingReliable = Marshal.ReadInt32(quickStatus, 40);
        int sendRate = Marshal.ReadInt32(quickStatus, 32);
        long queueMicroseconds = Marshal.ReadInt64(quickStatus, 48);
        uint relay = unchecked((uint)Marshal.ReadInt32(connectionInfo, 172));
        return FormattableString.Invariant(
            $"sdkState={state} sdkPingMs={ping} sdkQueueMs={queueMicroseconds / 1000.0:F1} sdkPendingUnreliable={pendingUnreliable} sdkPendingReliable={pendingReliable} sdkSendRateBps={sendRate} sdkRelayPop=0x{relay:x}");
    }

    public void Dispose()
    {
        Marshal.FreeHGlobal(quickStatus);
        Marshal.FreeHGlobal(connectionInfo);
    }
}
