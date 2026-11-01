-- Refuse multiple accounts before running this migration; never delete admins.
SELECT pg_advisory_xact_lock(73421001);
GRANT UPDATE (expires_at) ON login_sessions TO replab_app;
ALTER TABLE admins DROP CONSTRAINT ck_admin_slot;
UPDATE admins SET slot=1;
ALTER TABLE admins ADD CONSTRAINT ck_admin_slot CHECK(slot=1);
ALTER TABLE replab_schema DROP CONSTRAINT replab_schema_version_check;
ALTER TABLE replab_schema ADD CONSTRAINT replab_schema_version_check CHECK(version IN (1,2));
UPDATE replab_schema SET version=2;
