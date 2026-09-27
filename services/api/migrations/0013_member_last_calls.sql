-- 0013: last call becomes each member's own. A row says this member hears
-- about this credit only on the last rung of its ladder (Last chance); a
-- mute in member_mutes still outranks it. It goes with the member and the
-- credit it names.
CREATE TABLE member_last_calls (
  user_id    uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  benefit_id uuid NOT NULL REFERENCES benefits (id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, benefit_id)
);

-- A credit the household set to last call only keeps it for every member
-- in the household today, so no one's reminders change. The column stays
-- until the cleanup that removes Benefit.lastCallOnly (#362).
INSERT INTO member_last_calls (user_id, benefit_id)
SELECT m.user_id, b.id
FROM benefits b
JOIN memberships m ON m.household_id = b.household_id
WHERE b.last_call_only;
