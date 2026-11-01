CREATE TABLE admins (
    id uuid PRIMARY KEY, slot smallint NOT NULL, name varchar(100) NOT NULL,
    email varchar(254) NOT NULL, password_hash text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_admin_slot CHECK (slot BETWEEN 1 AND 3),
    CONSTRAINT ck_admin_email CHECK (email = lower(btrim(email))),
    CONSTRAINT uq_admin_slot UNIQUE(slot), CONSTRAINT uq_admin_email UNIQUE(email)
);
CREATE TABLE login_sessions (
    token_hash varchar(64) PRIMARY KEY, admin_id uuid NOT NULL REFERENCES admins(id),
    expires_at timestamptz NOT NULL
);
CREATE INDEX ix_login_sessions_admin_id ON login_sessions(admin_id);
CREATE INDEX ix_login_sessions_expires_at ON login_sessions(expires_at);
CREATE TABLE login_buckets (
    key varchar(64) PRIMARY KEY, attempts integer NOT NULL, started_at timestamptz NOT NULL
);
CREATE INDEX ix_login_buckets_started_at ON login_buckets(started_at);
CREATE TABLE gym_settings (
    id smallint PRIMARY KEY, gym_name varchar(100) NOT NULL,
    phone varchar(24) NOT NULL, address varchar(500) NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_single_gym CHECK(id=1)
);
INSERT INTO gym_settings(id,gym_name,phone,address) VALUES(1,'RepLab Fitness','','');
CREATE SEQUENCE member_number_seq AS integer;
CREATE TABLE members (
    id uuid PRIMARY KEY, serial integer NOT NULL DEFAULT nextval('member_number_seq'),
    name varchar(100) NOT NULL, phone varchar(24) NOT NULL, email varchar(254) NOT NULL,
    address varchar(500) NOT NULL, emergency_phone varchar(24) NOT NULL, notes varchar(2000) NOT NULL,
    joined date NOT NULL, is_active boolean NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_member_serial UNIQUE(serial)
);
ALTER SEQUENCE member_number_seq OWNED BY members.serial;
CREATE TABLE audit_logs (
    id uuid PRIMARY KEY, actor_id uuid REFERENCES admins(id),
    action varchar(60) NOT NULL, target_id uuid, details jsonb NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
