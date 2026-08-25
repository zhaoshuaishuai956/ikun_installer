using System.Security.Cryptography;
using System.Text;
using Npgsql;

if (args.Length < 1) { Usage(); return 2; }
var connection = Environment.GetEnvironmentVariable("IKUN_TELEMETRY_ADMIN_DB");
if (string.IsNullOrWhiteSpace(connection)) { Console.Error.WriteLine("IKUN_TELEMETRY_ADMIN_DB is required"); return 2; }
await using var db = new NpgsqlConnection(connection);
await db.OpenAsync();
switch (args[0].ToLowerInvariant())
{
    case "create-code":
        var hours = args.Length > 1 && int.TryParse(args[1], out var h) ? Math.Clamp(h, 1, 720) : 24;
        var code = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32)).TrimEnd('=').Replace('+', '-').Replace('/', '_');
        await using (var cmd = new NpgsqlCommand("INSERT INTO telemetry.enrollment_tokens(code_hash, expires_at) VALUES($1, now() + make_interval(hours => $2))", db))
        { cmd.Parameters.AddWithValue(Hash(code)); cmd.Parameters.AddWithValue(hours); await cmd.ExecuteNonQueryAsync(); }
        Console.WriteLine(code); return 0;
    case "disable-device":
        if (args.Length != 2 || !Guid.TryParse(args[1], out var id)) { Console.Error.WriteLine("disable-device requires install_id"); return 2; }
        await using (var cmd = new NpgsqlCommand("UPDATE telemetry.devices SET disabled_at=now() WHERE install_id=$1", db)) { cmd.Parameters.AddWithValue(id); Console.WriteLine($"disabled={await cmd.ExecuteNonQueryAsync()}"); }
        return 0;
    case "list-devices":
        await using (var cmd = new NpgsqlCommand("SELECT install_id, created_at, disabled_at FROM telemetry.devices ORDER BY created_at DESC", db))
        await using (var rows = await cmd.ExecuteReaderAsync()) while (await rows.ReadAsync()) Console.WriteLine($"{rows.GetGuid(0)}\t{rows.GetDateTime(1):O}\t{(rows.IsDBNull(2) ? "enabled" : rows.GetDateTime(2).ToString("O"))}");
        return 0;
    default: Usage(); return 2;
}

static string Hash(string value) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value))).ToLowerInvariant();
static void Usage() => Console.Error.WriteLine("create-code [hours 1..720] | disable-device <install_id> | list-devices");
