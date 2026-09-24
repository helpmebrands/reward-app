-- Households and who is in them. A person is in exactly one household at a
-- time (memberships.user_id is unique); the household owns the data, so a
-- member who leaves or is removed takes nothing with them.
CREATE TABLE households (
  id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE memberships (
  household_id uuid        NOT NULL REFERENCES households (id) ON DELETE CASCADE,
  user_id      uuid        NOT NULL UNIQUE REFERENCES users (id) ON DELETE CASCADE,
  role         text        NOT NULL CHECK (role IN ('owner', 'editor', 'reader')),
  joined_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (household_id, user_id)
);

-- A short code, single-use, for seven days, carrying the role it grants.
CREATE TABLE invites (
  code         text        PRIMARY KEY,
  household_id uuid        NOT NULL REFERENCES households (id) ON DELETE CASCADE,
  role         text        NOT NULL CHECK (role IN ('editor', 'reader')),
  created_by   uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  created_at   timestamptz NOT NULL DEFAULT now(),
  expires_at   timestamptz NOT NULL,
  used_by      uuid        REFERENCES users (id) ON DELETE SET NULL,
  used_at      timestamptz
);

-- The household's cards. Only the ownership is here; the card's own
-- columns arrive with the cards api (#216). Leaving a household that holds
-- cards needs confirmation, so the table exists from the start.
CREATE TABLE cards (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid        NOT NULL REFERENCES households (id) ON DELETE CASCADE,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX cards_household ON cards (household_id);
