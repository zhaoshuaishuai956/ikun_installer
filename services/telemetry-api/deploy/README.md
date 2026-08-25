# Deployment template

This directory contains templates only. This task does not install or enable a service.

## Runtime secrets

Provide these only through a protected environment file or systemd credentials:

- `IKUN_TELEMETRY_DB`: runtime PostgreSQL connection string.
- `IKUN_TELEMETRY_ENCRYPTION_KEY`: base64 of exactly 32 random bytes.
- `IKUN_TELEMETRY_HMAC_KEY`: base64 of at least 32 random bytes.

Do not place values in Git, appsettings, Dockerfile, command arguments, or logs. The PostgreSQL password supplied during planning must be rotated before deployment.

## Build

```bash
dotnet publish src/Ikun.Telemetry.Api/Ikun.Telemetry.Api.csproj -c Release -o /opt/ikun-telemetry
```

## Migration

Run `migrations/001_init.sql` manually with a migration identity. Then apply `runtime-grants.sql` after replacing placeholders. The runtime identity must not execute migrations or create schema.

## Systemd

Review `ikun-telemetry.service.example`, create a non-root `ikun-telemetry` user, install the protected environment file as root-owned mode 0640, and only then enable the service. The API binds `127.0.0.1:5080` when run directly on the host. For a container with a loopback-only host port mapping, set the container bind address to `0.0.0.0` and publish only to host loopback; otherwise set `IKUN_TELEMETRY_BIND_ADDRESS=127.0.0.1`.

## Lucky

Only after the service is locally healthy, configure a separate Lucky Web reverse-proxy hostname with TLS. Do not expose `/health/ready`, management commands, Swagger, metrics, or PostgreSQL. Keep `5080` and `5432` off the public interface. This task did not modify Lucky because the hostname was not supplied.

## Management CLI

A production CLI for enrollment-code generation, device disable, device listing, and token rotation is not installed by this task. It must be added before production enrollment, and it must use the same protected secrets without exposing them in output or process arguments.

## Rollback

```bash
systemctl disable --now ikun-telemetry
```

Restore the previous binary and environment file. Do not drop the telemetry schema during a normal rollback.

## Tests executed in this worktree

The host has no .NET SDK. Tests were executed in an isolated ARM64 .NET 9 SDK container:

```bash
docker run --rm -v "$PWD:/src" -w /src mcr.microsoft.com/dotnet/sdk:9.0 \
  dotnet test tests/Ikun.Telemetry.Tests/Ikun.Telemetry.Tests.csproj
```

Current result: 7 passed, 0 failed. These are unit/static contract tests, not PostgreSQL integration tests.

## Limitations before production

- Add and test the management CLI.
- Add a real IP/KnownProxies policy based on the exact Lucky source IP.
- Add full integration tests against PostgreSQL.
- Add runtime privilege negative tests.
- Add structured privacy-safe logs.
- Add load tests, backup/restore rehearsal, and database retention jobs.
- Review authenticated-encryption versioning/AAD before long-term retention.
- Confirm all public Lucky routes are limited to the allowed endpoints.

No production deployment has occurred.

## Git

Target branch: `codex/telemetry-api`. Commit only task files, run secret scanning, use Conventional Commits, and never force push.

## Privacy

Device fields are encrypted with AES-256-GCM and indexed with keyed HMAC. Raw device information is never returned by public API responses and must not appear in application, Lucky, or exception logs.

## Public API contract

- `POST /v1/register`
- `POST /v1/events`
- `POST /v1/device-snapshot`
- `GET /health/live`
- `GET /health/ready` is internal only

The API binds to localhost:5080 and does not configure Swagger, metrics, or public management routes.

## Current deployment status

This task has not modified Lucky, PostgreSQL, any client, NX plugin, update logic, download logic, or installation logic. It has not opened a port or sent data to a real device.

## Credentials

A PostgreSQL connection string was provided during planning. Rotate that password before deployment and inject the replacement only through protected server-side secrets.

## Further work

Before client integration, the server owner must supply the deployment hostname and exact Lucky source IP, then perform Lucky backup, migration, runtime-grant validation, local health verification, HTTPS proxy verification, and P0/P1 adversarial testing.

## End

Do not claim this service is deployed until those steps produce real evidence.
