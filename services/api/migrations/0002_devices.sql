-- 0002: push devices. One row per FCM token; the app's own installation id
-- travels with it so a reissued token can later be reconciled to the same
-- install. No accounts: a token is the only identity the service holds.
CREATE TABLE devices (
  token           text        PRIMARY KEY,
  installation_id text        NOT NULL,
  platform        text        NOT NULL CHECK (platform IN ('ios', 'android')),
  timezone        text        NOT NULL,
  registered_at   timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);
