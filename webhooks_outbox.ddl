CREATE TABLE webhook_events (
  id              BIGSERIAL PRIMARY KEY,        -- Use as idempotency key
  event_type      TEXT NOT NULL,                -- Example "meemoo.sip.archived"
  s3_bucket		  TEXT NOT NULL,                -- Will be used to devise
  correlation_id  VARCHAR(255) NOT NULL,        -- Kind of PK, but loose link
  payload         JSONB NOT NULL,               -- the event payload
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- delivery state
  status          TEXT NOT NULL DEFAULT 'pending',  -- 'pending' | 'sending' | 'sent' | 'dead' | 'skipped'
  attempts        INTEGER NOT NULL DEFAULT 0,
  next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  sent_at         TIMESTAMPTZ,
  error           TEXT,                           -- last error if any
  svix_id         VARCHAR(255)
);

-- Hot-path index for the poller
CREATE INDEX ON webhook_events (status, next_attempt_at, id);

-- Optional: TTL / housekeeping
CREATE INDEX ON webhook_events (sent_at, created_at) WHERE status in ('sent','dead');

-- Helper function
CREATE OR REPLACE FUNCTION to_iso8601z(ts timestamptz)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT to_char(ts AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"');
$$;

-- Function to fill in webhook event
CREATE OR REPLACE FUNCTION enqueue_sip_terminal_status_event()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  event_type   text;
  occurred   text;
  payload    jsonb;
BEGIN
  -- Only care about *changes* to terminal statuses
  IF TG_OP <> 'UPDATE' THEN
    RETURN NEW;
  END IF;

  IF OLD.status IS NOT DISTINCT FROM NEW.status THEN
    RETURN NEW;
  END IF;

  IF NEW.status NOT IN ('success','failure') THEN
    RETURN NEW;
  END IF;

  -- Should be calculated?
  event_type := NEW.last_event_type;

  occurred := to_iso8601z(NEW.last_event_occurred_at);

  payload := jsonb_build_object(
    'type',      event_type,
    'timestamp', occurred,
    'data',      jsonb_build_object(
                   'correlation_id', NEW.correlation_id,
                   'outcome',        NEW.status,
                   'pid',            NEW.pid
                 )
  );

  INSERT INTO webhook_events (event_type, s3_bucket, correlation_id, payload)
  VALUES (event_type, NEW.s3_bucket, NEW.correlation_id, payload)
  ON CONFLICT DO NOTHING;

  RETURN NEW;
END;
$$;

-- Trigger
DROP TRIGGER IF EXISTS trg_sip_deliveries_outbox ON public.sip_deliveries;

CREATE TRIGGER trg_sip_deliveries_outbox
AFTER UPDATE OF status
ON public.sip_deliveries
FOR EACH ROW
EXECUTE FUNCTION enqueue_sip_terminal_status_event();
