CREATE TYPE sipin_sip_deliveries_status AS ENUM (
  'in_progress',
  'success',
  'failure'
);

CREATE TABLE sipin_sip_deliveries (
  id SERIAL PRIMARY KEY,
  correlation_id VARCHAR(32) NOT NULL,
  s3_bucket VARCHAR(255) NOT NULL,
  s3_key TEXT NOT NULL,
  pid VARCHAR(10) NULL, -- nullable
  status sipin_sip_deliveries_status NOT NULL,
  failure_message TEXT NULL, -- nullable
  last_event_type VARCHAR(255) NOT NULL,
  last_event_occurred_at TIMESTAMP NOT NULL
);
