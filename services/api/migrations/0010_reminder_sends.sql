-- 0010: server-sent reminders. A device now belongs to the member who
-- registered it, so a reminder reaches all of their devices and none of
-- anyone else's. Rows from before sign-in belong to nobody and cannot be
-- sent to, so they go.
DELETE FROM devices;
ALTER TABLE devices
  ADD COLUMN user_id uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE;
CREATE INDEX devices_user ON devices (user_id);

-- One row per reminder sent to a member, so a retried or overlapping run of
-- the sender skips anything already sent. The id is the schedule's own,
-- stable across recomputes (`2026-10-31|urgent`).
CREATE TABLE reminder_sends (
  user_id     uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  reminder_id text        NOT NULL,
  sent_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, reminder_id)
);
