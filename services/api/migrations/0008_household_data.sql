-- A household's cards, credits and claims. A card linked to a catalogue
-- template stores only what is the household's own (label, kind, last four,
-- anniversary, archived); its terms come from the template's versions. A
-- card the household maintains itself stores its terms here. The same split
-- holds for each credit.
ALTER TABLE cards
  ADD COLUMN template_id      text REFERENCES card_templates (id),
  ADD COLUMN label            text,
  ADD COLUMN issuer           text,
  ADD COLUMN product          text,
  ADD COLUMN network          text,
  ADD COLUMN kind             text NOT NULL DEFAULT 'personal'
    CHECK (kind IN ('personal', 'business')),
  ADD COLUMN last4            text,
  ADD COLUMN annual_fee_cents integer CHECK (annual_fee_cents >= 0),
  ADD COLUMN anniversary_on   date,
  ADD COLUMN archived         boolean NOT NULL DEFAULT false,
  ADD COLUMN updated_at       timestamptz NOT NULL DEFAULT now(),
  ADD CONSTRAINT cards_terms CHECK (
    template_id IS NOT NULL OR (
      issuer IS NOT NULL AND product IS NOT NULL AND network IS NOT NULL
      AND annual_fee_cents IS NOT NULL
    )
  );

CREATE TABLE benefits (
  id                    uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id          uuid        NOT NULL REFERENCES households (id) ON DELETE CASCADE,
  card_id               uuid        NOT NULL REFERENCES cards (id) ON DELETE CASCADE,
  template_credit_id    text,
  -- The household's own state, on any credit.
  enrolled_at           text,
  enrollment_note       text,
  enrollment_url        text,
  spend_met_at          text,
  last_call_only        boolean     NOT NULL DEFAULT false,
  active                boolean     NOT NULL DEFAULT true,
  -- The terms, on a credit the household maintains; null on a linked one.
  name                  text,
  description           text,
  category              text,
  icon                  text,
  merchant              text,
  value_cents           integer CHECK (value_cents > 0),
  cadence               text,
  anchor                text,
  interval_months       integer,
  enrollment_required   boolean,
  spend_threshold_cents integer,
  ends_on               date,
  redemption_steps      jsonb,
  notes                 text,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  UNIQUE (card_id, template_credit_id),
  CHECK (
    template_credit_id IS NOT NULL OR (
      name IS NOT NULL AND category IS NOT NULL AND value_cents IS NOT NULL
      AND cadence IS NOT NULL AND anchor IS NOT NULL
      AND enrollment_required IS NOT NULL
    )
  )
);
CREATE INDEX benefits_household ON benefits (household_id);

-- A claim is logged at the till, often offline, and retried until it lands:
-- the client's idempotency key makes a retry a no-op.
CREATE TABLE claims (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id    uuid        NOT NULL REFERENCES households (id) ON DELETE CASCADE,
  benefit_id      uuid        NOT NULL REFERENCES benefits (id) ON DELETE CASCADE,
  cycle_key       text        NOT NULL,
  amount_cents    integer     NOT NULL CHECK (amount_cents > 0),
  claimed_at      text        NOT NULL,
  note            text,
  idempotency_key text        NOT NULL,
  request_body    text        NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (household_id, idempotency_key)
);
CREATE INDEX claims_household ON claims (household_id);
