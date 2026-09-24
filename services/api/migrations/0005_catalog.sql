-- The versioned catalogue. A template's terms are whole versions, each
-- taking effect on a date; a draft becomes immutable when it is published,
-- which the database itself enforces, and records who published it and from
-- what source. Credit ids are stable across versions (`<template>/<slug>`),
-- so a linked card's claims keep attaching when the terms change.
CREATE TABLE card_templates (
  id         text        PRIMARY KEY,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE template_versions (
  template_id      text        NOT NULL REFERENCES card_templates (id) ON DELETE CASCADE,
  version          integer     NOT NULL CHECK (version > 0),
  effective_from   date        NOT NULL,
  status           text        NOT NULL CHECK (status IN ('draft', 'published')),
  issuer           text        NOT NULL,
  product          text        NOT NULL,
  network          text        NOT NULL,
  kind             text        NOT NULL CHECK (kind IN ('personal', 'business')),
  annual_fee_cents integer     NOT NULL CHECK (annual_fee_cents >= 0),
  published_by     text,
  published_at     timestamptz,
  source_url       text,
  notes            text,
  created_at       timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (template_id, version),
  CHECK (status = 'draft' OR (published_by IS NOT NULL AND published_at IS NOT NULL))
);

CREATE TABLE template_credits (
  template_id           text    NOT NULL,
  version               integer NOT NULL,
  credit_id             text    NOT NULL,
  position              integer NOT NULL,
  name                  text    NOT NULL,
  description           text,
  category              text    NOT NULL,
  icon                  text    NOT NULL,
  merchant              text,
  value_cents           integer NOT NULL CHECK (value_cents > 0),
  cadence               text    NOT NULL,
  anchor                text    NOT NULL,
  interval_months       integer,
  enrollment_required   boolean NOT NULL DEFAULT false,
  spend_threshold_cents integer,
  ends_on               date,
  redemption_steps      jsonb   NOT NULL DEFAULT '[]',
  notes                 text,
  PRIMARY KEY (template_id, version, credit_id),
  FOREIGN KEY (template_id, version)
    REFERENCES template_versions (template_id, version) ON DELETE CASCADE
);

-- A published version never changes: not its fields, not its status, and
-- it is never deleted.
CREATE FUNCTION forbid_published_version_change() RETURNS trigger AS $$
BEGIN
  IF OLD.status = 'published' THEN
    RAISE EXCEPTION 'template % version % is published and cannot change',
      OLD.template_id, OLD.version USING ERRCODE = 'check_violation';
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END
$$ LANGUAGE plpgsql;

CREATE TRIGGER template_versions_immutable
  BEFORE UPDATE OR DELETE ON template_versions
  FOR EACH ROW EXECUTE FUNCTION forbid_published_version_change();

-- Nor do its credits: none added, changed or removed once it is published.
CREATE FUNCTION forbid_published_credit_change() RETURNS trigger AS $$
DECLARE
  published boolean;
BEGIN
  IF TG_OP <> 'INSERT' THEN
    SELECT status = 'published' INTO published FROM template_versions
      WHERE template_id = OLD.template_id AND version = OLD.version;
    IF published THEN
      RAISE EXCEPTION 'template % version % is published and cannot change',
        OLD.template_id, OLD.version USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  IF TG_OP <> 'DELETE' THEN
    SELECT status = 'published' INTO published FROM template_versions
      WHERE template_id = NEW.template_id AND version = NEW.version;
    IF published THEN
      RAISE EXCEPTION 'template % version % is published and cannot change',
        NEW.template_id, NEW.version USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
  END IF;
  RETURN OLD;
END
$$ LANGUAGE plpgsql;

CREATE TRIGGER template_credits_immutable
  BEFORE INSERT OR UPDATE OR DELETE ON template_credits
  FOR EACH ROW EXECUTE FUNCTION forbid_published_credit_change();
