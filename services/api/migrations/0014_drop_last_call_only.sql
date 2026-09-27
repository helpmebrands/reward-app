-- 0014: last call is each member's own since 0013 (member_last_calls), so
-- the household's column goes (#362).
ALTER TABLE benefits DROP COLUMN last_call_only;
