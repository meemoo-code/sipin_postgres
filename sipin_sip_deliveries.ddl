CREATE TYPE sipin_sip_deliveries_status AS ENUM (
  'in_progress',
  'success',
  'failure'
);

CREATE TABLE sipin_sip_deliveries (
  id SERIAL PRIMARY KEY,
  correlation_id VARCHAR(32),
  s3_bucket VARCHAR(255),
  s3_key TEXT,
  pid VARCHAR(10),
  status sipin_sip_deliveries_status,
  failure_message TEXT,
  last_event_type VARCHAR(255),
  last_event_occurred_at TIMESTAMP
);
