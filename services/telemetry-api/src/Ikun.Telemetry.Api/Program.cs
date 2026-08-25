using System.Collections.Concurrent;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Npgsql;

var builder = WebApplication.CreateBuilder(args);
var bindAddress = Environment.GetEnvironmentVariable("IKUN_TELEMETRY_BIND_ADDRESS") ?? "127.0.0.1";
builder.WebHost.ConfigureKestrel(o =>
{
    if (bindAddress == "0.0.0.0") o.ListenAnyIP(5080); else o.ListenLocalhost(5080);
    o.Limits.MaxRequestBodySize = 8192;
    o.Limits.RequestHeadersTimeout = TimeSpan.FromSeconds(5);
    o.Limits.KeepAliveTimeout = TimeSpan.FromSeconds(30);
});
builder.Services.ConfigureHttpJsonOptions(o =>
{
    o.SerializerOptions.UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow;
    o.SerializerOptions.PropertyNameCaseInsensitive = false;
});
builder.Services.AddSingleton<RateLimitState>();
builder.Services.AddSingleton<TelemetryStore>();
builder.Services.AddSingleton<DashboardStore>();
builder.Services.AddHealthChecks();
var app = builder.Build();
app.UseExceptionHandler(error => error.Run(async c =>
{
    c.Response.StatusCode = 503;
    await c.Response.WriteAsJsonAsync(new { error = "service_unavailable" });
}));
app.Use(async (ctx, next) =>
{
    var limit = ctx.Request.Path.Equals("/v1/register", StringComparison.Ordinal) ? 4096 : 8192;
    if (ctx.Request.ContentLength > limit)
    {
        ctx.Response.StatusCode = 413;
        await ctx.Response.WriteAsJsonAsync(new { error = "request_too_large" });
        return;
    }
    using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ctx.RequestAborted);
    timeout.CancelAfter(TimeSpan.FromSeconds(5));
    ctx.Items["request_token"] = timeout.Token;
    await next();
});
app.MapHealthChecks("/health/live");
app.MapGet("/health/ready", (TelemetryStore db) => db.Ready ? Results.Ok(new { status = "ready" }) : Results.StatusCode(503));
if (!string.Equals(Environment.GetEnvironmentVariable("IKUN_TELEMETRY_DASHBOARD_ENABLED"), "false", StringComparison.OrdinalIgnoreCase))
{
    app.MapGet("/dashboard", (IWebHostEnvironment env) => Results.File(Path.Combine(env.WebRootPath ?? "wwwroot", "index.html"), "text/html; charset=utf-8"));
    app.MapGet("/dashboard/api/summary", async (DashboardStore db, HttpContext ctx) => Results.Ok(await db.SummaryAsync(RequestCancellation(ctx))));
    app.MapGet("/dashboard/api/events", async (DashboardStore db, HttpContext ctx) => Results.Ok(await db.RecentEventsAsync(RequestCancellation(ctx))));
    if (string.Equals(Environment.GetEnvironmentVariable("IKUN_TELEMETRY_DASHBOARD_ROOT"), "true", StringComparison.OrdinalIgnoreCase))
    {
        app.MapGet("/", (IWebHostEnvironment env) => Results.File(Path.Combine(env.WebRootPath ?? "wwwroot", "index.html"), "text/html; charset=utf-8"));
        app.MapGet("/api/summary", async (DashboardStore db, HttpContext ctx) => Results.Ok(await db.SummaryAsync(RequestCancellation(ctx))));
        app.MapGet("/api/events", async (DashboardStore db, HttpContext ctx) => Results.Ok(await db.RecentEventsAsync(RequestCancellation(ctx))));
        app.MapGet("/api/devices", async (DashboardStore db, HttpContext ctx) => Results.Ok(await db.DevicesAsync(RequestCancellation(ctx))));
    }
}

app.MapPost("/v1/register", async (HttpContext ctx, RegisterRequest request, RateLimitState limits, TelemetryStore db) =>
{
    if (limits.IsBlocked(ctx) || !limits.AllowGlobal() || !limits.AllowIp(ctx, "register", 3, TimeSpan.FromMinutes(1))) return Results.Unauthorized();
    var autoEnroll = string.Equals(Environment.GetEnvironmentVariable("IKUN_TELEMETRY_AUTO_ENROLL"), "true", StringComparison.OrdinalIgnoreCase);
    if (!Guid.TryParse(request.InstallId, out var installId) || (!autoEnroll && (request.EnrollmentCode is null || request.EnrollmentCode.Length is < 32 or > 256))) return Results.BadRequest(new { error = "invalid_request" });
    var ct = RequestCancellation(ctx);
    if (!autoEnroll && !await db.ConsumeEnrollmentAsync(request.EnrollmentCode!, ct)) return Results.BadRequest(new { error = "invalid_request" });
    var token = Convert.ToBase64String(RandomNumberGenerator.GetBytes(48));
    if (!await db.CreateDeviceAsync(installId, Security.Hash(token), ClientIp(ctx), ct)) return Results.BadRequest(new { error = "invalid_request" });
    return Results.Ok(new { install_id = installId, device_token = token });
});

app.MapPost("/v1/events", async (HttpContext ctx, EventRequest request, RateLimitState limits, TelemetryStore db) =>
{
    if (limits.IsBlocked(ctx) || !limits.AllowGlobal()) return Results.Unauthorized();
    var token = Bearer(ctx);
    if (token is null || !Guid.TryParse(request.InstallId, out var installId)) return Results.Unauthorized();
    var tokenHash = Security.Hash(token);
    var ct = RequestCancellation(ctx);
    if (!await db.TokenBelongsAsync(installId, tokenHash, ClientIp(ctx), ct)) { limits.InvalidToken(ctx); return Results.Unauthorized(); }
    if (!limits.AllowIp(ctx, "events", 30, TimeSpan.FromMinutes(1)) || !limits.AllowToken(tokenHash, 10, TimeSpan.FromMinutes(1)) || !limits.AllowDaily(tokenHash, 200)) return TooManyResult.Instance;
    if (!Validation.ValidEvent(request)) return Results.BadRequest(new { error = "invalid_request" });
    await db.InsertEventAsync(request, ct);
    return Results.StatusCode(202);
});

app.MapPost("/v1/device-snapshot", async (HttpContext ctx, SnapshotRequest request, RateLimitState limits, TelemetryStore db) =>
{
    if (limits.IsBlocked(ctx) || !limits.AllowGlobal()) return Results.Unauthorized();
    var token = Bearer(ctx);
    if (token is null || !Guid.TryParse(request.InstallId, out var installId)) return Results.Unauthorized();
    var tokenHash = Security.Hash(token);
    var ct = RequestCancellation(ctx);
    if (!await db.TokenBelongsAsync(installId, tokenHash, ClientIp(ctx), ct)) { limits.InvalidToken(ctx); return Results.Unauthorized(); }
    if (!limits.AllowIp(ctx, "snapshot", 10, TimeSpan.FromMinutes(1)) || !limits.AllowToken(tokenHash, 10, TimeSpan.FromMinutes(1))) return TooManyResult.Instance;
    if (!Validation.ValidSnapshot(request)) return Results.BadRequest(new { error = "invalid_request" });
    await db.InsertSnapshotAsync(request, ct);
    return Results.StatusCode(202);
});
app.Run();

static CancellationToken RequestCancellation(HttpContext c) => c.Items["request_token"] is CancellationToken t ? t : c.RequestAborted;
static string ClientIp(HttpContext c) => c.Connection.RemoteIpAddress?.ToString() ?? "unknown";
static string? Bearer(HttpContext c) { var value = c.Request.Headers.Authorization.ToString(); return value.StartsWith("Bearer ", StringComparison.Ordinal) ? value[7..].Trim() : null; }
public sealed record RegisterRequest([property: JsonPropertyName("enrollment_code")] string? EnrollmentCode, [property: JsonPropertyName("install_id")] string InstallId);
public sealed record EventRequest([property: JsonPropertyName("event_id")] string EventId, [property: JsonPropertyName("install_id")] string InstallId, [property: JsonPropertyName("event_type")] string EventType, [property: JsonPropertyName("trigger_source")] string TriggerSource, [property: JsonPropertyName("installer_version")] string InstallerVersion, [property: JsonPropertyName("remote_version")] string? RemoteVersion, [property: JsonPropertyName("nx_version")] string? NxVersion, [property: JsonPropertyName("os_version")] string OsVersion, [property: JsonPropertyName("result")] string Result, [property: JsonPropertyName("occurred_at")] DateTimeOffset OccurredAt);
public sealed record SnapshotRequest([property: JsonPropertyName("snapshot_id")] string SnapshotId, [property: JsonPropertyName("install_id")] string InstallId, [property: JsonPropertyName("computer_name")] string ComputerName, [property: JsonPropertyName("windows_user")] string WindowsUser, [property: JsonPropertyName("mac_addresses")] string[] MacAddresses, [property: JsonPropertyName("os_version")] string OsVersion, [property: JsonPropertyName("nx_version")] string NxVersion, [property: JsonPropertyName("installer_version")] string InstallerVersion, [property: JsonPropertyName("occurred_at")] DateTimeOffset OccurredAt);

public static class Validation
{
    public static readonly HashSet<string> EventTypes = ["update_check", "update_offer_shown", "update_offer_closed", "download_started", "download_completed", "download_failed", "install_completed", "install_failed"];
    public static readonly HashSet<string> Results = ["update_available", "up_to_date", "started", "completed", "failed", "closed", "skipped"];
    public static readonly HashSet<string> Triggers = ["first_plugin_use", "manual", "startup", "scheduled", "user_action", "unknown"];
    public static bool ValidEvent(EventRequest x) => Guid.TryParse(x.EventId, out _) && Guid.TryParse(x.InstallId, out _) && EventTypes.Contains(x.EventType) && Triggers.Contains(x.TriggerSource) && Results.Contains(x.Result) && Len(x.TriggerSource, 1, 64) && Len(x.InstallerVersion, 1, 64) && Len(x.RemoteVersion, 0, 64) && Len(x.NxVersion, 0, 64) && Len(x.OsVersion, 1, 128) && InWindow(x.OccurredAt);
    public static bool ValidSnapshot(SnapshotRequest x) => Guid.TryParse(x.SnapshotId, out _) && Guid.TryParse(x.InstallId, out _) && Len(x.ComputerName, 1, 128) && Len(x.WindowsUser, 1, 256) && Len(x.OsVersion, 1, 128) && Len(x.NxVersion, 1, 64) && Len(x.InstallerVersion, 1, 64) && x.MacAddresses is { Length: <= 8 } && x.MacAddresses.All(Mac.Valid) && x.MacAddresses.Select(Mac.Normalize).Distinct().Count() == x.MacAddresses.Length && InWindow(x.OccurredAt);
    static bool Len(string? x, int min, int max) => x is not null && x.Length >= min && x.Length <= max;
    static bool InWindow(DateTimeOffset x) => x >= DateTimeOffset.UtcNow.AddMinutes(-5) && x <= DateTimeOffset.UtcNow.AddMinutes(5);
}
public static class Mac
{
    public static bool Valid(string? value)
    {
        if (value is null) return false;
        try { var b = Convert.FromHexString(value.Replace(":", "").Replace("-", "")); return b.Length == 6 && b.Any(x => x != 0) && b.Any(x => x != 255); } catch { return false; }
    }
    public static string Normalize(string value) => string.Join(':', Convert.FromHexString(value.Replace(":", "").Replace("-", "")).Select(x => x.ToString("X2")));
}
public static class Security
{
    public static string Hash(string value) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value))).ToLowerInvariant();
    public static bool FixedEquals(string a, string b) => CryptographicOperations.FixedTimeEquals(Encoding.UTF8.GetBytes(a), Encoding.UTF8.GetBytes(b));
}
public sealed class TooManyResult : IResult
{
    public static readonly TooManyResult Instance = new();
    public async Task ExecuteAsync(HttpContext context) { context.Response.StatusCode = 429; context.Response.Headers.RetryAfter = "60"; await context.Response.WriteAsJsonAsync(new { error = "rate_limited" }); }
}
public sealed class RateLimitState
{
    readonly ConcurrentDictionary<string, (DateTimeOffset Start, int Count)> counters = new();
    readonly ConcurrentDictionary<string, (DateTimeOffset Day, int Count)> daily = new();
    readonly ConcurrentDictionary<string, DateTimeOffset> blocked = new();
    int globalCount; DateTimeOffset globalStart = DateTimeOffset.UtcNow;
    public bool AllowGlobal() { lock (this) { var n = DateTimeOffset.UtcNow; if (n - globalStart >= TimeSpan.FromSeconds(1)) { globalStart = n; globalCount = 0; } return ++globalCount <= 200; } }
    public bool AllowIp(HttpContext c, string kind, int max, TimeSpan window) => Allow(kind + ":" + (c.Connection.RemoteIpAddress?.ToString() ?? "unknown"), max, window);
    public bool AllowToken(string hash, int max, TimeSpan window) => Allow("token:" + hash, max, window);
    public bool AllowDaily(string hash, int max) { var day = DateTimeOffset.UtcNow.Date; var x = daily.AddOrUpdate(hash, (day, 1), (_, old) => old.Day == day ? (day, old.Count + 1) : (day, 1)); return x.Count <= max; }
    public bool IsBlocked(HttpContext c) => c.Connection.RemoteIpAddress is { } ip && blocked.TryGetValue(ip.ToString(), out var until) && until > DateTimeOffset.UtcNow;
    public void InvalidToken(HttpContext c) { var key = "invalid:" + (c.Connection.RemoteIpAddress?.ToString() ?? "unknown"); if (!Allow(key, 20, TimeSpan.FromMinutes(5))) blocked[key[8..]] = DateTimeOffset.UtcNow.AddMinutes(15); }
    bool Allow(string key, int max, TimeSpan window) { var now = DateTimeOffset.UtcNow; var x = counters.AddOrUpdate(key, (now, 1), (_, old) => now - old.Start >= window ? (now, 1) : (old.Start, old.Count + 1)); return x.Count <= max; }
}
public sealed class TelemetryStore
{
    readonly string? connectionString; readonly byte[] encryptionKey; readonly byte[] hmacKey;
    public bool Ready => !string.IsNullOrWhiteSpace(connectionString) && encryptionKey.Length == 32 && hmacKey.Length >= 32;
    public TelemetryStore(IConfiguration config)
    {
        connectionString = Environment.GetEnvironmentVariable("IKUN_TELEMETRY_DB") ?? config["IKUN_TELEMETRY_DB"];
        encryptionKey = DecodeKey("IKUN_TELEMETRY_ENCRYPTION_KEY"); hmacKey = DecodeKey("IKUN_TELEMETRY_HMAC_KEY");
    }
    byte[] DecodeKey(string name) { var value = Environment.GetEnvironmentVariable(name) ?? ""; try { return Convert.FromBase64String(value); } catch { return []; } }
    async Task<NpgsqlConnection> Open(CancellationToken ct) { if (!Ready) throw new InvalidOperationException("not configured"); var csb = new NpgsqlConnectionStringBuilder(connectionString) { MaxPoolSize = 20, Timeout = 3, CommandTimeout = 3 }; var c = new NpgsqlConnection(csb.ConnectionString); await c.OpenAsync(ct); return c; }
    public async Task<bool> ConsumeEnrollmentAsync(string code, CancellationToken ct) { await using var c = await Open(ct); await using var q = new NpgsqlCommand("UPDATE telemetry.enrollment_tokens SET used_at=now() WHERE code_hash=$1 AND used_at IS NULL AND expires_at>now() RETURNING id", c); q.Parameters.AddWithValue(Security.Hash(code)); return await q.ExecuteScalarAsync(ct) is not null; }
    public async Task<bool> CreateDeviceAsync(Guid id, string hash, string ip, CancellationToken ct) { await using var c = await Open(ct); await using var q = new NpgsqlCommand("INSERT INTO telemetry.devices(install_id,token_hash,last_ip,last_seen_at) VALUES($1,$2,$3::inet,now()) ON CONFLICT(install_id) DO NOTHING", c); q.Parameters.AddWithValue(id); q.Parameters.AddWithValue(hash); q.Parameters.AddWithValue(ip); return await q.ExecuteNonQueryAsync(ct) == 1; }
    public async Task<bool> TokenBelongsAsync(Guid id, string hash, string ip, CancellationToken ct) { await using var c = await Open(ct); await using var q = new NpgsqlCommand("UPDATE telemetry.devices SET last_ip=$3::inet,last_seen_at=now() WHERE install_id=$1 AND token_hash=$2 AND disabled_at IS NULL RETURNING token_hash", c); q.Parameters.AddWithValue(id); q.Parameters.AddWithValue(hash); q.Parameters.AddWithValue(ip); return await q.ExecuteScalarAsync(ct) is not null; }
    public async Task InsertEventAsync(EventRequest x, CancellationToken ct) { await using var c = await Open(ct); await using var q = new NpgsqlCommand("INSERT INTO telemetry.events(event_id,install_id,event_type,trigger_source,installer_version,remote_version,nx_version,os_version,result,occurred_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) ON CONFLICT(event_id) DO NOTHING", c); q.Parameters.AddWithValue(Guid.Parse(x.EventId)); q.Parameters.AddWithValue(Guid.Parse(x.InstallId)); q.Parameters.AddWithValue(x.EventType); q.Parameters.AddWithValue(x.TriggerSource); q.Parameters.AddWithValue(x.InstallerVersion); q.Parameters.AddWithValue((object?)x.RemoteVersion ?? DBNull.Value); q.Parameters.AddWithValue((object?)x.NxVersion ?? DBNull.Value); q.Parameters.AddWithValue(x.OsVersion); q.Parameters.AddWithValue(x.Result); q.Parameters.AddWithValue(x.OccurredAt); await q.ExecuteNonQueryAsync(ct); }
    public async Task InsertSnapshotAsync(SnapshotRequest x, CancellationToken ct)
    {
        var names = Encrypt(x.ComputerName); var users = Encrypt(x.WindowsUser); var macs = x.MacAddresses.Select(Mac.Normalize).ToArray();
        await using var c = await Open(ct); await using var tx = await c.BeginTransactionAsync(ct);
        await using (var q = new NpgsqlCommand("INSERT INTO telemetry.device_snapshots(snapshot_id,install_id,computer_name_cipher,computer_name_nonce,computer_name_hmac,windows_user_cipher,windows_user_nonce,windows_user_hmac,os_version,nx_version,installer_version,occurred_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12) ON CONFLICT(snapshot_id) DO NOTHING RETURNING snapshot_id", c, tx))
        {
            q.Parameters.AddWithValue(Guid.Parse(x.SnapshotId)); q.Parameters.AddWithValue(Guid.Parse(x.InstallId)); q.Parameters.AddWithValue(names.Cipher); q.Parameters.AddWithValue(names.Nonce); q.Parameters.AddWithValue(Hmac(x.ComputerName)); q.Parameters.AddWithValue(users.Cipher); q.Parameters.AddWithValue(users.Nonce); q.Parameters.AddWithValue(Hmac(x.WindowsUser)); q.Parameters.AddWithValue(x.OsVersion); q.Parameters.AddWithValue(x.NxVersion); q.Parameters.AddWithValue(x.InstallerVersion); q.Parameters.AddWithValue(x.OccurredAt);
            if (await q.ExecuteScalarAsync(ct) is null) { await tx.CommitAsync(ct); return; }
        }
        foreach (var mac in macs) { var e = Encrypt(mac); await using var q = new NpgsqlCommand("INSERT INTO telemetry.device_macs(snapshot_id,mac_cipher,mac_nonce,mac_hmac) VALUES($1,$2,$3,$4)", c, tx); q.Parameters.AddWithValue(Guid.Parse(x.SnapshotId)); q.Parameters.AddWithValue(e.Cipher); q.Parameters.AddWithValue(e.Nonce); q.Parameters.AddWithValue(Hmac(mac)); await q.ExecuteNonQueryAsync(ct); }
        await tx.CommitAsync(ct);
    }
    (byte[] Cipher, byte[] Nonce) Encrypt(string value) { var nonce = RandomNumberGenerator.GetBytes(12); var plain = Encoding.UTF8.GetBytes(value); var cipher = new byte[plain.Length]; var tag = new byte[16]; using var aes = new AesGcm(encryptionKey, 16); aes.Encrypt(nonce, plain, cipher, tag, Encoding.UTF8.GetBytes("ikun-telemetry-v1")); return (cipher.Concat(tag).ToArray(), nonce); }
    string Hmac(string value) => Convert.ToHexString(new HMACSHA256(hmacKey).ComputeHash(Encoding.UTF8.GetBytes(value))).ToLowerInvariant();
}

public sealed class DashboardStore
{
    private readonly string? connectionString;
    public DashboardStore(IConfiguration config) => connectionString = Environment.GetEnvironmentVariable("IKUN_TELEMETRY_DB") ?? config["IKUN_TELEMETRY_DB"];
    private async Task<NpgsqlConnection> Open(CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(connectionString)) throw new InvalidOperationException("not configured");
        var csb = new NpgsqlConnectionStringBuilder(connectionString) { MaxPoolSize = 4, Timeout = 3, CommandTimeout = 3 };
        var c = new NpgsqlConnection(csb.ConnectionString); await c.OpenAsync(ct); return c;
    }
    public async Task<object> SummaryAsync(CancellationToken ct)
    {
        await using var c = await Open(ct);
        async Task<long> Count(string sql) { await using var q = new NpgsqlCommand(sql, c); return (long)(await q.ExecuteScalarAsync(ct) ?? 0L); }
        return new { devices = await Count("SELECT count(*) FROM telemetry.devices"), active_devices = await Count("SELECT count(*) FROM telemetry.devices WHERE disabled_at IS NULL"), events_24h = await Count("SELECT count(*) FROM telemetry.events WHERE received_at >= now() - interval '24 hours'"), snapshots_24h = await Count("SELECT count(*) FROM telemetry.device_snapshots WHERE received_at >= now() - interval '24 hours'") };
    }
    public async Task<IReadOnlyList<object>> RecentEventsAsync(CancellationToken ct)
    {
        var result = new List<object>();
        await using var c = await Open(ct);
        await using var q = new NpgsqlCommand("SELECT event_type, trigger_source, result, installer_version, remote_version, received_at FROM telemetry.events ORDER BY received_at DESC LIMIT 30", c);
        await using var rows = await q.ExecuteReaderAsync(ct);
        while (await rows.ReadAsync(ct)) result.Add(new { event_type = rows.GetString(0), trigger_source = rows.GetString(1), result = rows.GetString(2), installer_version = rows.GetString(3), remote_version = rows.IsDBNull(4) ? null : rows.GetString(4), received_at = rows.GetDateTime(5) });
        return result;
    }
    public async Task<IReadOnlyList<object>> DevicesAsync(CancellationToken ct)
    {
        var result = new List<object>();
        await using var c = await Open(ct);
        await using var q = new NpgsqlCommand("SELECT install_id, last_ip::text, last_seen_at, created_at, disabled_at FROM telemetry.devices ORDER BY COALESCE(last_seen_at, created_at) DESC", c);
        await using var rows = await q.ExecuteReaderAsync(ct);
        while (await rows.ReadAsync(ct)) result.Add(new { install_id = rows.GetGuid(0), ip = rows.IsDBNull(1) ? null : rows.GetString(1), last_seen_at = rows.IsDBNull(2) ? (DateTime?)null : rows.GetDateTime(2), created_at = rows.GetDateTime(3), status = rows.IsDBNull(4) ? "active" : "disabled" });
        return result;
    }
}
public partial class Program { }
