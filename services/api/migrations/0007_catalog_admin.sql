-- Who may change the catalogue. A person becomes an admin by a row here,
-- added by hand (runbook 06 connects to the database); there is no route
-- that grants it.
CREATE TABLE admins (
  user_id    uuid        PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- What happened to the catalogue, for whatever reacts to it: today one kind,
-- `version published`, which the change notices of the follow-on epic
-- consume.
CREATE TABLE catalog_events (
  id           bigserial   PRIMARY KEY,
  kind         text        NOT NULL CHECK (kind IN ('version published')),
  template_id  text        NOT NULL REFERENCES card_templates (id),
  version      integer     NOT NULL,
  published_by text        NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (template_id, version)
    REFERENCES template_versions (template_id, version)
);
