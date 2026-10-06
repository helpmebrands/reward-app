-- 0015: a card belongs to the person who added it, and people share their
-- cards with each other, replacing households (#418). Each household's
-- cards go to its owner, every other member gets an all-cards share from
-- that owner (record usage for an editor, view for a reader), and every
-- claim is attributed to its card's owner. Household invites are deleted.

-- The name on the sign-in account, when it carries one, kept like the email.
ALTER TABLE users ADD COLUMN name text;

-- A household whose owner's user row was deleted by hand has no owner
-- left; its earliest member stands in. A household with no members at all
-- has nobody to give its cards to, so they go.
CREATE TEMPORARY TABLE household_owners ON COMMIT DROP AS
SELECT DISTINCT ON (household_id) household_id, user_id
FROM memberships
ORDER BY household_id, role <> 'owner', joined_at;

ALTER TABLE cards
  ADD COLUMN owner_id uuid REFERENCES users (id) ON DELETE CASCADE;
UPDATE cards c SET owner_id = o.user_id
FROM household_owners o WHERE o.household_id = c.household_id;
DELETE FROM cards WHERE owner_id IS NULL;
ALTER TABLE cards ALTER COLUMN owner_id SET NOT NULL;
CREATE INDEX cards_owner ON cards (owner_id);

-- Who logged a claim. A retried claim is the same person's, so the
-- idempotency key is unique per recorder.
ALTER TABLE claims
  ADD COLUMN recorded_by uuid REFERENCES users (id) ON DELETE CASCADE;
UPDATE claims cl SET recorded_by = c.owner_id
FROM benefits b JOIN cards c ON c.id = b.card_id
WHERE b.id = cl.benefit_id;
ALTER TABLE claims ALTER COLUMN recorded_by SET NOT NULL;

-- One share from an owner to another person: all the owner's cards,
-- including ones added later, or the chosen cards in shared_cards.
CREATE TABLE shares (
  owner_id   uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  member_id  uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  access     text        NOT NULL CHECK (access IN ('view', 'record')),
  all_cards  boolean     NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (owner_id, member_id),
  CHECK (owner_id <> member_id)
);
CREATE INDEX shares_member ON shares (member_id);

CREATE TABLE shared_cards (
  owner_id  uuid NOT NULL,
  member_id uuid NOT NULL,
  card_id   uuid NOT NULL REFERENCES cards (id) ON DELETE CASCADE,
  PRIMARY KEY (owner_id, member_id, card_id),
  FOREIGN KEY (owner_id, member_id)
    REFERENCES shares (owner_id, member_id) ON DELETE CASCADE
);

INSERT INTO shares (owner_id, member_id, access, all_cards)
SELECT o.user_id, m.user_id,
       CASE m.role WHEN 'reader' THEN 'view' ELSE 'record' END, true
FROM memberships m
JOIN household_owners o ON o.household_id = m.household_id
WHERE m.user_id <> o.user_id;

-- An invite carries the share it creates; a chosen-cards invite lists its
-- cards in invite_cards.
DROP TABLE invites;
CREATE TABLE invites (
  code       text        PRIMARY KEY,
  owner_id   uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  access     text        NOT NULL CHECK (access IN ('view', 'record')),
  all_cards  boolean     NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  used_by    uuid        REFERENCES users (id) ON DELETE SET NULL,
  used_at    timestamptz
);

CREATE TABLE invite_cards (
  code    text NOT NULL REFERENCES invites (code) ON DELETE CASCADE,
  card_id uuid NOT NULL REFERENCES cards (id) ON DELETE CASCADE,
  PRIMARY KEY (code, card_id)
);

ALTER TABLE cards DROP COLUMN household_id;
ALTER TABLE benefits DROP COLUMN household_id;
ALTER TABLE claims DROP COLUMN household_id;
ALTER TABLE claims ADD UNIQUE (recorded_by, idempotency_key);
CREATE INDEX claims_benefit ON claims (benefit_id);
DROP TABLE memberships;
DROP TABLE households;

-- Who sees which card, and what they may do with it: its owner, and each
-- person a share covers. A person has at most one row per card, because a
-- share never goes to its own owner and one pair of people has one share.
CREATE VIEW card_access AS
SELECT id AS card_id, owner_id AS user_id, 'owner'::text AS access FROM cards
UNION ALL
SELECT c.id, s.member_id, s.access
FROM shares s JOIN cards c ON c.owner_id = s.owner_id
WHERE s.all_cards
UNION ALL
SELECT c.id, s.member_id, s.access
FROM shares s
JOIN shared_cards sc
  ON sc.owner_id = s.owner_id AND sc.member_id = s.member_id
JOIN cards c ON c.id = sc.card_id AND c.owner_id = s.owner_id
WHERE NOT s.all_cards;
