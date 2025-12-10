-- webhook_events
CREATE TABLE webhook_events (
  id              BIGSERIAL PRIMARY KEY,            -- used to construct an idempotency key
  event_type      TEXT NOT NULL,
  s3_bucket       TEXT NOT NULL,                    -- used for routing
  correlation_id  VARCHAR(255) NOT NULL,
  payload         JSONB NOT NULL,                   -- the event payload
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- delivery state
  status          TEXT NOT NULL DEFAULT 'pending',  -- 'pending' | 'sending' | 'sent' | 'dead' | 'skipped'
  attempts        INTEGER NOT NULL DEFAULT 0,
  next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  sent_at         TIMESTAMPTZ,
  error           TEXT,                             -- last error, if any
  svix_id         VARCHAR(255)                      -- '_msg'-prefixed id returned by svix
);

-- indices
CREATE INDEX ON webhook_events (status, next_attempt_at, id);  -- hot-path
CREATE INDEX ON webhook_events (sent_at, created_at) WHERE status in ('sent', 'dead');

-- helper function
CREATE OR REPLACE FUNCTION to_iso8601z(ts timestamptz)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT to_char(ts AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"');
$$;

-- function to fill in webhook_events
CREATE OR REPLACE FUNCTION enqueue_sip_terminal_status_event()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  correlation_id varchar(255);
  s3_bucket      text;
  pid            varchar(10);
  outcome        text;
  message        text;
  event_type     text;
  occurred       text;
  payload        jsonb;
BEGIN
  -- Only care about *changes* to terminal statuses
  IF TG_OP <> 'UPDATE' THEN
    RETURN NEW;
  END IF;

  IF OLD.status IS NOT DISTINCT FROM NEW.status THEN
    RETURN NEW;
  END IF;

  IF NEW.status NOT IN ('success', 'failure') THEN
    RETURN NEW;
  END IF;

  correlation_id := NEW.correlation_id;
  s3_bucket := NEW.s3_bucket;
  pid := NEW.pid;
  outcome := NEW.status;
  event_type := NEW.last_event_type;
  -- normalize event types (if pulsar topics)
  event_type := CASE WHEN starts_with(LOWER(event_type), 'persistent://public/') THEN replace(regexp_replace(event_type, '^persistent://public/', '', 'i'), '/', '.') ELSE event_type END;
  -- prefix the message with the originating event type
  message := event_type || ' -- ' || NEW.failure_message;
  occurred := to_iso8601z(NEW.last_event_occurred_at);
  -- construct the payload
  payload := jsonb_build_object(
    'type',      'meemoo.sip.archived',  -- collapse all types into this one
    'timestamp', occurred,
    'data',      jsonb_build_object(
                   'correlation_id', correlation_id,
                   'outcome', outcome
                 )  -- joined with optional 'pid' and 'message' keys
                   || CASE WHEN pid IS NOT NULL THEN jsonb_build_object('pid', pid) ELSE '{}'::jsonb END
                   || CASE WHEN message IS NOT NULL THEN jsonb_build_object('message', message) ELSE '{}'::jsonb END
  );

  INSERT INTO webhook_events (event_type, s3_bucket, correlation_id, payload)
  VALUES (event_type, s3_bucket, correlation_id, payload)
  ON CONFLICT DO NOTHING;

  RETURN NEW;
END;
$$;

-- trigger
DROP TRIGGER IF EXISTS trigger_sip_deliveries_outbox ON public.sip_deliveries;
CREATE TRIGGER trigger_sip_deliveries_outbox
AFTER UPDATE OF status
ON public.sip_deliveries
FOR EACH ROW
EXECUTE FUNCTION enqueue_sip_terminal_status_event();
