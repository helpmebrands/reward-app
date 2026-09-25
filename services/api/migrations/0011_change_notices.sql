-- 0011: catalogue change notices. The sender marks each publish event once
-- it has told the holders; events from before notices existed count as
-- told, or the first run would announce the seed.
ALTER TABLE catalog_events ADD COLUMN noticed_at timestamptz;
UPDATE catalog_events SET noticed_at = now();

-- A "terms changed" mark on a linked card, one per member, so seeing it
-- clears it for that member only. It goes with the card, so converting or
-- deleting the card takes it.
CREATE TABLE terms_changed (
  card_id    uuid        NOT NULL REFERENCES cards (id) ON DELETE CASCADE,
  user_id    uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  version    integer     NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (card_id, user_id)
);
