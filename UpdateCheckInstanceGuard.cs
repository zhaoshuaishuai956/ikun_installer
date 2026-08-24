namespace ikun_installer;

/// <summary>
/// Holds a named mutex for the complete lifetime of an update-check process.
/// </summary>
internal sealed class UpdateCheckInstanceGuard : IDisposable
{
    internal const string DefaultMutexName = "Local\\ikun_tools_update_check_process";

    private readonly Mutex _mutex;
    private bool _disposed;

    private UpdateCheckInstanceGuard(Mutex mutex)
    {
        _mutex = mutex;
    }

    /// <summary>
    /// Returns an owned guard, or null when another update check is already alive.
    /// The caller must keep and dispose the guard after the check window closes.
    /// </summary>
    internal static UpdateCheckInstanceGuard? TryAcquire(string mutexName = DefaultMutexName)
    {
        var mutex = new Mutex(initiallyOwned: true, mutexName, out var createdNew);
        if (createdNew)
            return new UpdateCheckInstanceGuard(mutex);

        mutex.Dispose();
        return null;
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _mutex.ReleaseMutex();
        _mutex.Dispose();
    }
}
