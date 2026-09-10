using System.Text.Json;

namespace ikun_installer;

/// <summary>
/// Release 中独立于安装器 exe 的插件资源清单。
/// ReleaseVersion 是资源包版本；InstallerVersion 是安装器本体版本，二者刻意分离。
/// </summary>
public sealed record ResourceManifest(
    int Schema,
    string ReleaseVersion,
    IReadOnlyList<ResourceEntry> Resources,
    string? InstallerVersion = null,
    string? UpdateKind = null)
{
    public static ResourceManifest? Parse(ReadOnlySpan<byte> json)
    {
        try
        {
            var value = JsonSerializer.Deserialize<ResourceManifest>(json, new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true,
                PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower
            });
            if (value is null || value.Schema != 1 || !Version.TryParse(value.ReleaseVersion, out _) || value.Resources.Count == 0)
                return null;
            if (value.InstallerVersion is not null && !Version.TryParse(value.InstallerVersion, out _))
                return null;
            if (value.UpdateKind is not null && value.UpdateKind is not ("plugins" or "installer"))
                return null;
            if (value.Resources.Any(x => !IsSafePath(x.RelativePath) || string.IsNullOrWhiteSpace(x.Asset) ||
                x.Size <= 0 || x.Size > 200L * 1024 * 1024 || !RegexHash.IsMatch(x.Sha256) ||
                !ValidText(x.PluginId, 128) || !ValidText(x.PluginName, 128) || !ValidText(x.Description, 512)) ||
                value.Resources.Select(x => x.RelativePath).Distinct(StringComparer.OrdinalIgnoreCase).Count() != value.Resources.Count) return null;
            return value;
        }
        catch { return null; }
    }

    private static bool IsSafePath(string path)
    {
        if (string.IsNullOrWhiteSpace(path) || Path.IsPathRooted(path) || path.Contains('\\') || path.Contains("..", StringComparison.Ordinal)) return false;
        return path.StartsWith("application/", StringComparison.Ordinal) || path.StartsWith("startup/", StringComparison.Ordinal);
    }

    private static bool ValidText(string? value, int max) => value is null || (value.Length > 0 && value.Length <= max);

    private static readonly System.Text.RegularExpressions.Regex RegexHash = new("^[0-9a-fA-F]{64}$", System.Text.RegularExpressions.RegexOptions.Compiled);
}

public sealed record ResourceEntry(
    string RelativePath,
    string Asset,
    long Size,
    string Sha256,
    string? PluginId = null,
    string? PluginName = null,
    string? Description = null);

public sealed record ResourceUpdateDetail(
    string PluginId,
    string PluginName,
    string RelativePath,
    string Description,
    bool IsNewPlugin);

public sealed record ResourceUpdateResult(
    int Changed,
    int Skipped,
    bool NewPlugin,
    string? Error,
    bool RequiresElevation = false,
    IReadOnlyList<ResourceUpdateDetail>? Details = null)
{
    public bool Succeeded => Error is null;
}

public static class ResourceUpdateDescription
{
    public static string Format(IReadOnlyList<ResourceUpdateDetail>? details)
    {
        if (details is not { Count: > 0 }) return "（未提供具体变更说明）";
        var lines = details
            .GroupBy(x => string.IsNullOrWhiteSpace(x.PluginName) ? x.PluginId : x.PluginName,
                StringComparer.OrdinalIgnoreCase)
            .Select(group =>
            {
                var descriptions = group.Select(x => x.Description)
                    .Where(x => !string.IsNullOrWhiteSpace(x))
                    .Distinct(StringComparer.OrdinalIgnoreCase)
                    .Take(3)
                    .ToArray();
                var suffix = descriptions.Length == 0 ? "部署资源更新" : string.Join("；", descriptions);
                var newMark = group.Any(x => x.IsNewPlugin) ? "（新增插件，重启 NX 后载入）" : "";
                return $"• {group.Key}：{suffix}{newMark}";
            })
            .Take(12)
            .ToArray();
        return lines.Length == 0 ? "（未提供具体变更说明）" : string.Join(Environment.NewLine, lines);
    }
}
