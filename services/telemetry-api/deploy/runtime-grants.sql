-- Run as a migration administrator in the dedicated database.
-- Replace placeholders; never put passwords here.
REVOKE ALL ON SCHEMA telemetry FROM PUBLIC;
-- CREATE ROLE ikun_telemetry_runtime NOLOGIN;
GRANT CONNECT ON DATABASE <database> TO ikun_telemetry_runtime;
GRANT USAGE ON SCHEMA telemetry TO ikun_telemetry_runtime;
GRANT SELECT, INSERT, UPDATE ON telemetry.enrollment_tokens, telemetry.devices, telemetry.device_snapshots, telemetry.device_macs, telemetry.events, telemetry.security_blocks TO ikun_telemetry_runtime;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA telemetry TO ikun_telemetry_runtime;
REVOKE DELETE, TRUNCATE, REFERENCES, TRIGGER ON telemetry.enrollment_tokens, telemetry.devices, telemetry.device_snapshots, telemetry.device_macs, telemetry.events, telemetry.security_blocks FROM ikun_telemetry_runtime;
-- Verify separately: pg_roles must show rolsuper=false, rolcreatedb=false, rolcreaterole=false.
-- SET ROLE ikun_telemetry_runtime; CREATE TABLE telemetry.must_fail(id int); RESET ROLE;
-- Do not grant access to GitHub schemas/databases.
-- Apply migrations with a separate migration role, never with runtime.
-- Passwords are injected outside this file.
