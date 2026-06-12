-- ============================================================
-- MIGRATION 1: SCHEMA
-- ============================================================


-- ============================================================
-- ENUMS
-- ============================================================

DO $$ BEGIN
  CREATE TYPE device_type_enum AS ENUM ('auto_night_light');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE action_type_enum AS ENUM (
    'led_on',
    'led_off',
    'auto_mode_on',
    'auto_mode_off',
    'auto_triggered_on',
    'auto_triggered_off'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE triggered_by_enum AS ENUM ('user', 'auto_mode');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;


-- ============================================================
-- 4.5 households (created before users due to FK dependency)
-- ============================================================

CREATE TABLE IF NOT EXISTS households (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name         TEXT NOT NULL,
  creator_id   UUID,
  join_code    TEXT NOT NULL UNIQUE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);


-- ============================================================
-- 4.1 users
-- ============================================================

CREATE TABLE IF NOT EXISTS users (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  username       TEXT NOT NULL UNIQUE,
  email          TEXT NOT NULL UNIQUE,
  password_hash  TEXT NOT NULL,
  is_verified    BOOLEAN NOT NULL DEFAULT false,
  household_id   UUID REFERENCES households(id) ON DELETE SET NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Add FK from households.creator_id → users
ALTER TABLE households
  DROP CONSTRAINT IF EXISTS fk_households_creator;

ALTER TABLE households
  ADD CONSTRAINT fk_households_creator
  FOREIGN KEY (creator_id) REFERENCES users(id) ON DELETE SET NULL;


-- ============================================================
-- 4.2 product_keys
-- ============================================================

CREATE TABLE IF NOT EXISTS product_keys (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_key    TEXT UNIQUE,
  device_type    device_type_enum NOT NULL,
  is_registered  BOOLEAN NOT NULL DEFAULT false,
  registered_at  TIMESTAMPTZ,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);


-- ============================================================
-- 4.3 devices
-- ============================================================

CREATE TABLE IF NOT EXISTS devices (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_key_id  UUID NOT NULL REFERENCES product_keys(id) ON DELETE RESTRICT,
  owner_id        UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_name     TEXT NOT NULL,
  device_type     device_type_enum NOT NULL,
  is_online       BOOLEAN NOT NULL DEFAULT false,
  last_seen_at    TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);


-- ============================================================
-- 4.4 night_light_state
-- ============================================================

CREATE TABLE IF NOT EXISTS night_light_state (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id   UUID NOT NULL UNIQUE REFERENCES devices(id) ON DELETE CASCADE,
  auto_mode   BOOLEAN NOT NULL DEFAULT false,
  led1_state  BOOLEAN NOT NULL DEFAULT false,
  led1_label  TEXT NOT NULL DEFAULT 'LED 1',
  led2_state  BOOLEAN NOT NULL DEFAULT false,
  led2_label  TEXT NOT NULL DEFAULT 'LED 2',
  led3_state  BOOLEAN NOT NULL DEFAULT false,
  led3_label  TEXT NOT NULL DEFAULT 'LED 3',
  ldr_value   INTEGER,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);


-- ============================================================
-- 4.6 activity_logs
-- ============================================================

CREATE TABLE IF NOT EXISTS activity_logs (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id     UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  performed_by  UUID REFERENCES users(id) ON DELETE SET NULL,
  action_type   action_type_enum NOT NULL,
  led_number    INTEGER CHECK (led_number BETWEEN 1 AND 3),
  led_label     TEXT,
  triggered_by  triggered_by_enum NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);


-- ============================================================
-- 4.7 otp_verifications
-- ============================================================

CREATE TABLE IF NOT EXISTS otp_verifications (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email       TEXT NOT NULL,
  otp_code    TEXT NOT NULL,
  expires_at  TIMESTAMPTZ NOT NULL,
  is_used     BOOLEAN NOT NULL DEFAULT false,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);


-- ============================================================
-- INDEXES
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_users_email          ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_household      ON users(household_id);
CREATE INDEX IF NOT EXISTS idx_devices_owner        ON devices(owner_id);
CREATE INDEX IF NOT EXISTS idx_devices_product_key  ON devices(product_key_id);
CREATE INDEX IF NOT EXISTS idx_night_light_device   ON night_light_state(device_id);
CREATE INDEX IF NOT EXISTS idx_activity_logs_device ON activity_logs(device_id);
CREATE INDEX IF NOT EXISTS idx_activity_logs_user   ON activity_logs(performed_by);
CREATE INDEX IF NOT EXISTS idx_otp_email            ON otp_verifications(email);
