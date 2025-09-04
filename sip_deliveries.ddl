DO $$
BEGIN
  IF to_regtype('public.sip_deliveries_status') IS NULL THEN
    CREATE TYPE public.sip_deliveries_status AS ENUM (
      'in_progress',
      'success',
      'failure'
    );
  END IF;
END
$$ LANGUAGE plpgsql;

CREATE TABLE IF NOT EXISTS public.sip_deliveries (
  correlation_id VARCHAR(255) PRIMARY KEY,
  s3_bucket TEXT NOT NULL,
  s3_key TEXT NOT NULL,
  pid VARCHAR(10) NULL,
  status public.sip_deliveries_status NOT NULL DEFAULT 'in_progress',
  failure_message TEXT NULL,
  last_event_type TEXT NOT NULL,
  last_event_occurred_at TIMESTAMP NOT NULL
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION public.set_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW IS DISTINCT FROM OLD THEN
    NEW.updated_at = NOW();
    RETURN NEW;
  END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_updated_at
BEFORE UPDATE ON public.sip_deliveries
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at_column();
