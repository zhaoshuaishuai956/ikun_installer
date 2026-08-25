using System;
using System.IO;
using Xunit;

public sealed class ValidationTests
{
    static EventRequest Event(string occurred = "now") => new(
        Guid.NewGuid().ToString(), Guid.NewGuid().ToString(), "update_check", "startup", "2.1.0.122", "2.1.0.123", "1847", "Windows 11 x64", "update_available",
        occurred == "now" ? DateTimeOffset.UtcNow : DateTimeOffset.UtcNow.AddHours(-1));

    [Fact]
    public void Valid_event_is_accepted() => Assert.True(Validation.ValidEvent(Event()));

    [Fact]
    public void Old_event_is_rejected() => Assert.False(Validation.ValidEvent(Event("old")));

    [Fact]
    public void Unknown_event_type_is_rejected()
    {
        var e = Event() with { EventType = "arbitrary" };
        Assert.False(Validation.ValidEvent(e));
    }

    [Fact]
    public void Unknown_trigger_is_rejected()
    {
        var e = Event() with { TriggerSource = "attacker" };
        Assert.False(Validation.ValidEvent(e));
    }

    [Fact]
    public void Token_hash_is_deterministic_and_not_plaintext()
    {
        var h = Security.Hash("secret-token");
        Assert.Equal(64, h.Length);
        Assert.NotEqual("secret-token", h);
        Assert.True(Security.FixedEquals(h, Security.Hash("secret-token")));
        Assert.False(Security.FixedEquals(h, Security.Hash("other-token")));
    }

    [Fact]
    public void Mac_normalization_rejects_zero_broadcast_and_invalid_values()
    {
        Assert.True(Mac.Valid("00:11:22:33:44:55"));
        Assert.Equal("00:11:22:33:44:55", Mac.Normalize("001122334455"));
        Assert.False(Mac.Valid("00:00:00:00:00:00"));
        Assert.False(Mac.Valid("FF:FF:FF:FF:FF:FF"));
        Assert.False(Mac.Valid("not-a-mac"));
    }
}

public sealed class SqlMigrationTests
{
    [Fact]
    public void Migration_has_primary_key_and_deduplication()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "..", "migrations", "001_init.sql");
        var sql = File.ReadAllText(Path.GetFullPath(path));
        Assert.Contains("event_id UUID PRIMARY KEY", sql);
        Assert.Contains("device_snapshots", sql);
        Assert.DoesNotContain("postgresql://", sql);
    }
}
