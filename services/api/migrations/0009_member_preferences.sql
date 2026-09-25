-- Each member's own notification settings and mutes. The household's data
-- is shared; these are not, so one member silencing a card silences it for
-- nobody else. A member with no row has the defaults.
CREATE TABLE member_preferences (
  user_id             uuid        PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
  enabled             boolean     NOT NULL,
  time_of_day         text        NOT NULL CHECK (time_of_day ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'),
  min_value_cents     integer     NOT NULL CHECK (min_value_cents >= 0),
  annual_fee_reminder boolean     NOT NULL,
  enrollment_reminder boolean     NOT NULL,
  updated_at          timestamptz NOT NULL DEFAULT now()
);

-- A mute names a card or a credit, never both; it goes with the card or
-- credit it names.
CREATE TABLE member_mutes (
  user_id    uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  card_id    uuid REFERENCES cards (id) ON DELETE CASCADE,
  benefit_id uuid REFERENCES benefits (id) ON DELETE CASCADE,
  CHECK ((card_id IS NULL) <> (benefit_id IS NULL)),
  UNIQUE (user_id, card_id),
  UNIQUE (user_id, benefit_id)
);
