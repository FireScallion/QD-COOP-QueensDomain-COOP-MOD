using System.Text;

// The bridge and Steam helper own different files. A crash can lose the current
// batch, while complete batches remain readable even after the IPC is cleared.
sealed class DiagnosticLog
{
    const int FileLimit = 8 * 1024 * 1024;
    readonly string? path;
    readonly StringBuilder pending = new();
    long nextWrite, length = -1;
    bool full;

    public DiagnosticLog(string? directory, string name)
    {
        if (!string.IsNullOrEmpty(directory)) path = Path.Combine(directory, name);
    }

    public void Add(string value)
    {
        if (path == null || full || pending.Length >= 128 * 1024) return;
        pending.Append(DateTime.UtcNow.ToString("O")).Append(' ').AppendLine(value);
    }

    public void Flush(bool force = false)
    {
        long now = Environment.TickCount64;
        if (path == null || pending.Length == 0 || (!force && now < nextWrite)) return;
        nextWrite = now + 500;
        try
        {
            if (length < 0)
            {
                Directory.CreateDirectory(Path.GetDirectoryName(path)!);
                length = new FileInfo(path) is { Exists: true } existing ? existing.Length : 0;
            }
            string batch = pending.ToString();
            int size = Encoding.UTF8.GetByteCount(batch);
            if (length + size > FileLimit)
            {
                batch = $"\n{DateTime.UtcNow:O} capture_limit_reached\n";
                size = Encoding.UTF8.GetByteCount(batch);
                full = true;
            }
            File.AppendAllText(path, batch);
            length += size;
            pending.Clear();
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            // The next flush retries the bounded buffer. Gameplay can proceed.
        }
    }
}
