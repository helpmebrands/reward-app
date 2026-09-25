-- 0012: opting out of a credit the household will never use. It replaces
-- the old pause (`active = false`), which now marks only a credit that had
-- ended; `tracked_from` is the day tracking resumed after an opt-out, so the
-- windows that closed in between are never counted as missed.
ALTER TABLE benefits
  ADD COLUMN opted_out_at text,
  ADD COLUMN tracked_from date;

-- A credit paused before opting out existed was opted out as of that pause,
-- unless it had already ended by then: by its own end date, or for a linked
-- credit by the end date in its template's latest published version. The
-- instant is written the way the domain writes one.
UPDATE benefits b
SET active = true,
    opted_out_at = to_char(b.updated_at AT TIME ZONE 'UTC',
                           'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
WHERE NOT b.active
  AND COALESCE(
    b.ends_on,
    (SELECT tc.ends_on
     FROM cards c
     JOIN template_credits tc ON tc.template_id = c.template_id
     JOIN template_versions tv
       ON tv.template_id = tc.template_id AND tv.version = tc.version
     WHERE c.id = b.card_id
       AND tc.credit_id = b.template_credit_id
       AND tv.status = 'published'
     ORDER BY tv.effective_from DESC, tv.version DESC
     LIMIT 1),
    'infinity'::date
  ) >= (b.updated_at AT TIME ZONE 'UTC')::date;
