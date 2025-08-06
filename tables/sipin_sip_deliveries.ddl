DO $$
BEGIN
  IF to_regtype('public.sipin_sip_deliveries_status') IS NULL THEN
    CREATE TYPE public.sipin_sip_deliveries_status AS ENUM (
      'in_progress',
      'success',
      'failure'
    );
  END IF;
END
$$ LANGUAGE plpgsql;

CREATE TABLE IF NOT EXISTS public.sipin_sip_deliveries (
  correlation_id VARCHAR(255) PRIMARY KEY,
  s3_bucket TEXT NOT NULL,
  s3_key TEXT NOT NULL,
  pid VARCHAR(10) NULL,
  status public.sipin_sip_deliveries_status NOT NULL DEFAULT 'in_progress',
  failure_message TEXT NULL,
  last_event_type TEXT NOT NULL,
  last_event_occurred_at TIMESTAMP NOT NULL,

  CONSTRAINT check_failure_message
    CHECK (
      (status = 'failure' AND failure_message IS NOT NULL)
      OR
      (status <> 'failure' AND failure_message IS NULL)
    )
);
