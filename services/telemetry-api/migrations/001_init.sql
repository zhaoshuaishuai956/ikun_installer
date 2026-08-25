BEGIN;
CREATE SCHEMA IF NOT EXISTS telemetry;
CREATE TABLE IF NOT EXISTS telemetry.enrollment_tokens (
  id BIGSERIAL PRIMARY KEY,
  code_hash TEXT NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL,
  used_at TIMESTAMPTZ
);
CREATE TABLE IF NOT EXISTS telemetry.devices (
  install_id UUID PRIMARY KEY,
  token_hash TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  disabled_at TIMESTAMPTZ
);
CREATE TABLE IF NOT EXISTS telemetry.events (
  event_id UUID PRIMARY KEY,
  install_id UUID NOT NULL REFERENCES telemetry.devices(install_id),
  event_type TEXT NOT NULL,
  trigger_source TEXT NOT NULL,
  installer_version TEXT NOT NULL,
  remote_version TEXT,
  nx_version TEXT,
  os_version TEXT NOT NULL,
  result TEXT NOT NULL,
  occurred_at TIMESTAMPTZ NOT NULL,
  received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (length(event_type) BETWEEN 1 AND 64),
  CHECK (length(trigger_source) BETWEEN 1 AND 64),
  CHECK (length(installer_version) BETWEEN 1 AND 64),
  CHECK (length(os_version) BETWEEN 1 AND 128)
);
CREATE TABLE IF NOT EXISTS telemetry.device_snapshots (
  snapshot_id UUID PRIMARY KEY,
  install_id UUID NOT NULL REFERENCES telemetry.devices(install_id),
  computer_name_cipher BYTEA NOT NULL,
  computer_name_nonce BYTEA NOT NULL,
  computer_name_hmac TEXT NOT NULL,
  windows_user_cipher BYTEA NOT NULL,
  windows_user_nonce BYTEA NOT NULL,
  windows_user_hmac TEXT NOT NULL,
  os_version TEXT NOT NULL,
  nx_version TEXT NOT NULL,
  installer_version TEXT NOT NULL,
  occurred_at TIMESTAMPTZ NOT NULL,
  received_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS telemetry.device_macs (
  snapshot_id UUID NOT NULL REFERENCES telemetry.device_snapshots(snapshot_id) ON DELETE CASCADE,
  mac_cipher BYTEA NOT NULL,
  mac_nonce BYTEA NOT NULL,
  mac_hmac TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_events_install_received ON telemetry.events(install_id, received_at DESC);
CREATE INDEX IF NOT EXISTS ix_events_type_received ON telemetry.events(event_type, received_at DESC);
CREATE INDEX IF NOT EXISTS ix_snapshots_install_received ON telemetry.device_snapshots(install_id, received_at DESC);
CREATE INDEX IF NOT EXISTS ix_snapshots_computer_hmac ON telemetry.device_snapshots(computer_name_hmac);
CREATE INDEX IF NOT EXISTS ix_snapshots_user_hmac ON telemetry.device_snapshots(windows_user_hmac);
CREATE INDEX IF NOT EXISTS ix_macs_hmac ON telemetry.device_macs(mac_hmac);
CREATE TABLE IF NOT EXISTS telemetry.security_blocks (
  key TEXT PRIMARY KEY,
  blocked_until TIMESTAMPTZ NOT NULL,
  reason TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- Execute runtime grants as a migration administrator, replacing the role name if needed.
-- REVOKE ALL ON SCHEMA telemetry FROM PUBLIC;
-- CREATE ROLE ikun_telemetry_runtime NOLOGIN;
-- GRANT CONNECT ON DATABASE <database> TO ikun_telemetry_runtime;
-- GRANT USAGE ON SCHEMA telemetry TO ikun_telemetry_runtime;
-- GRANT SELECT, INSERT, UPDATE ON telemetry.enrollment_tokens, telemetry.devices, telemetry.events, telemetry.security_blocks TO ikun_telemetry_runtime;
-- GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA telemetry TO ikun_telemetry_runtime;
COMMIT;

-- Retention (schedule externally, e.g. daily):
-- DELETE FROM telemetry.events WHERE received_at < now() - interval '90 days';
-- DELETE FROM telemetry.security_blocks WHERE created_at < now() - interval '30 days';

-- Rollback:
-- DROP TABLE telemetry.events, telemetry.devices, telemetry.enrollment_tokens, telemetry.security_blocks;
-- DROP SCHEMA telemetry;
