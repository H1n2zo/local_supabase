-- ============================================================
-- MIGRATION 2: PRODUCT KEY GENERATOR
-- Format: XXXXX-XXXXX-XXXXX-XXXXX-XXXXX
-- Characters: A-Z and 0-9 (uppercase alphanumeric)
-- Example: VR8LW-7CCF9-DRCEB-Z8EW4-AWJ6H
-- ============================================================


-- Helper: generate one 5-character segment
CREATE OR REPLACE FUNCTION generate_key_segment()
RETURNS TEXT AS $$
DECLARE
  chars  TEXT := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  result TEXT := '';
  i      INT;
BEGIN
  FOR i IN 1..5 LOOP
    result := result || substr(chars, floor(random() * length(chars) + 1)::INT, 1);
  END LOOP;
  RETURN result;
END;
$$ LANGUAGE plpgsql;


-- Main: generate a unique full product key
CREATE OR REPLACE FUNCTION generate_product_key()
RETURNS TEXT AS $$
DECLARE
  new_key    TEXT;
  key_exists BOOLEAN;
BEGIN
  LOOP
    new_key := generate_key_segment() || '-' ||
               generate_key_segment() || '-' ||
               generate_key_segment() || '-' ||
               generate_key_segment() || '-' ||
               generate_key_segment();

    SELECT EXISTS (
      SELECT 1 FROM product_keys WHERE product_key = new_key
    ) INTO key_exists;

    EXIT WHEN NOT key_exists;
  END LOOP;

  RETURN new_key;
END;
$$ LANGUAGE plpgsql;


-- Trigger function: auto-assign product_key before insert
CREATE OR REPLACE FUNCTION trigger_set_product_key()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.product_key IS NULL THEN
    NEW.product_key := generate_product_key();
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- Attach trigger to product_keys table
DROP TRIGGER IF EXISTS set_product_key_trigger ON product_keys;

CREATE TRIGGER set_product_key_trigger
BEFORE INSERT ON product_keys
FOR EACH ROW
EXECUTE FUNCTION trigger_set_product_key();


-- ============================================================
-- VIEW: unregistered keys (ready to ship with devices)
-- ============================================================

CREATE OR REPLACE VIEW available_product_keys AS
SELECT
  id,
  product_key,
  device_type,
  created_at
FROM product_keys
WHERE is_registered = false
ORDER BY created_at DESC;


-- ============================================================
-- FUNCTION: register a product key (called from Flutter app)
-- ============================================================

CREATE OR REPLACE FUNCTION register_product_key(
  p_product_key TEXT,
  p_user_id     UUID,
  p_device_name TEXT
)
RETURNS TABLE (
  device_id   UUID,
  device_name TEXT,
  device_type device_type_enum
) AS $$
DECLARE
  v_key_id      UUID;
  v_device_type device_type_enum;
  v_device_id   UUID;
BEGIN
  -- Find the key and lock the row
  SELECT id, pk.device_type
  INTO v_key_id, v_device_type
  FROM product_keys pk
  WHERE pk.product_key = p_product_key
    AND pk.is_registered = false
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid or already registered product key: %', p_product_key;
  END IF;

  -- Mark key as registered
  UPDATE product_keys
  SET is_registered = true,
      registered_at = now()
  WHERE id = v_key_id;

  -- Create the device record
  INSERT INTO devices (product_key_id, owner_id, device_name, device_type)
  VALUES (v_key_id, p_user_id, p_device_name, v_device_type)
  RETURNING id INTO v_device_id;

  -- Create initial night_light_state row for this device
  INSERT INTO night_light_state (device_id)
  VALUES (v_device_id);

  -- Return the new device info
  RETURN QUERY
  SELECT v_device_id, p_device_name, v_device_type;
END;
$$ LANGUAGE plpgsql;
