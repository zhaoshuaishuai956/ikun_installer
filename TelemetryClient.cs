using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Net.NetworkInformation;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Win32;

namespace ikun_installer;

/// <summary>后台遥测客户端。没有受管注册码时完全停用，不影响安装、更新或插件运行。</summary>
internal static class TelemetryClient
{
    private const string RegistryPath = UpdateManager.RegistryKeyPath;
    private const string InstallIdValue = "telemetry_install_id";
    private const string TokenValue = "telemetry_device_token";
    private const string EnrollmentValue = "telemetry_enrollment_code";
    private const string UrlValue = "telemetry_url";
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public static async Task InitializeAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            var enrollment = ReadSetting(EnrollmentValue, "IKUN_TELEMETRY_ENROLLMENT_CODE");
            if (string.IsNullOrWhiteSpace(enrollment)) return;
            var installId = ReadInstallId();
            var token = ReadProtected(TokenValue);
            var client = CreateClient();
            if (token is null)
            {
                var response = await PostAsync(client, "/v1/register", new { enrollment_code = enrollment, install_id = installId }, cancellationToken);
                if (!response.IsSuccessStatusCode) return;
                var result = await response.Content.ReadFromJsonAsync<RegisterResponse>(JsonOptions, cancellationToken);
                if (string.IsNullOrWhiteSpace(result?.DeviceToken)) return;
                token = result.DeviceToken;
                WriteProtected(TokenValue, token);
            }

            await SendSnapshotAsync(client, installId, token, cancellationToken);
        }
        catch { /* telemetry is best effort and must never affect the installer */ }
    }

    public static void QueueEvent(string eventType, string trigger, string result, Version? remoteVersion = null)
        => _ = Task.Run(() => SendEventAsync(eventType, trigger, result, remoteVersion));

    private static async Task SendEventAsync(string eventType, string trigger, string result, Version? remoteVersion)
    {
        try
        {
            var token = ReadProtected(TokenValue);
            var installId = ReadInstallId();
            if (token is null) return;
            using var client = CreateClient();
            using var request = new HttpRequestMessage(HttpMethod.Post, Endpoint("/v1/events"));
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
            request.Content = JsonContent.Create(new
            {
                event_id = Guid.NewGuid(), install_id = installId, event_type = eventType,
                trigger_source = trigger, installer_version = Versioning.GetLocalVersion().ToString(),
                remote_version = remoteVersion?.ToString(), nx_version = "1847",
                os_version = Environment.OSVersion.VersionString, result, occurred_at = DateTimeOffset.UtcNow
            }, options: JsonOptions);
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(3));
            await client.SendAsync(request, timeout.Token);
        }
        catch { }
    }

    private static async Task SendSnapshotAsync(HttpClient client, Guid installId, string token, CancellationToken cancellationToken)
    {
        var macs = NetworkInterface.GetAllNetworkInterfaces()
            .Where(n => n.OperationalStatus == OperationalStatus.Up)
            .Select(n => n.GetPhysicalAddress().ToString())
            .Where(x => x.Length == 12 && x.Any(c => c != '0') && !x.Equals("FFFFFFFFFFFF", StringComparison.OrdinalIgnoreCase))
            .Distinct(StringComparer.OrdinalIgnoreCase).Take(8).ToArray();
        if (macs.Length == 0) return;
        using var request = new HttpRequestMessage(HttpMethod.Post, Endpoint("/v1/device-snapshot"));
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        request.Content = JsonContent.Create(new
        {
            snapshot_id = Guid.NewGuid(), install_id = installId,
            computer_name = Environment.MachineName,
            windows_user = Environment.UserName,
            mac_addresses = macs, os_version = Environment.OSVersion.VersionString,
            nx_version = "1847", installer_version = Versioning.GetLocalVersion().ToString(),
            occurred_at = DateTimeOffset.UtcNow
        }, options: JsonOptions);
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(3));
        await client.SendAsync(request, timeout.Token);
    }

    private static HttpClient CreateClient() => new() { Timeout = TimeSpan.FromSeconds(3) };
    private static async Task<HttpResponseMessage> PostAsync(HttpClient client, string path, object payload, CancellationToken ct)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeout.CancelAfter(TimeSpan.FromSeconds(3));
        return await client.PostAsJsonAsync(Endpoint(path), payload, JsonOptions, timeout.Token);
    }
    private static string Endpoint(string path) => ReadSetting(UrlValue, "IKUN_TELEMETRY_URL")?.TrimEnd('/') is { Length: > 0 } url
        ? url + path : "https://tm.h.zss.fan:2233" + path;
    private static string? ReadSetting(string registryName, string environmentName)
    {
        var env = Environment.GetEnvironmentVariable(environmentName);
        if (!string.IsNullOrWhiteSpace(env)) return env.Trim();
        try { return Registry.CurrentUser.OpenSubKey(RegistryPath)?.GetValue(registryName) as string; }
        catch { return null; }
    }
    private static Guid ReadInstallId()
    {
        try
        {
            using var key = Registry.CurrentUser.CreateSubKey(RegistryPath);
            if (Guid.TryParse(key?.GetValue(InstallIdValue) as string, out var id)) return id;
            var created = Guid.NewGuid(); key?.SetValue(InstallIdValue, created.ToString("D")); return created;
        }
        catch { return Guid.NewGuid(); }
    }
    private static string? ReadProtected(string name)
    {
        try
        {
            var value = Registry.CurrentUser.OpenSubKey(RegistryPath)?.GetValue(name) as string;
            if (string.IsNullOrWhiteSpace(value)) return null;
            return Encoding.UTF8.GetString(ProtectedData.Unprotect(Convert.FromBase64String(value), null, DataProtectionScope.CurrentUser));
        }
        catch { return null; }
    }
    private static void WriteProtected(string name, string value)
    {
        try
        {
            using var key = Registry.CurrentUser.CreateSubKey(RegistryPath);
            var cipher = ProtectedData.Protect(Encoding.UTF8.GetBytes(value), null, DataProtectionScope.CurrentUser);
            key?.SetValue(name, Convert.ToBase64String(cipher));
        }
        catch { }
    }
    private sealed record RegisterResponse([property: System.Text.Json.Serialization.JsonPropertyName("device_token")] string? DeviceToken);
}
