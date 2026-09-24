-- One row per person who has signed in, created on their first
-- authenticated call. `firebase_uid` is the Identity Platform user id from
-- the verified ID token; `id` is what every other table references.
CREATE TABLE users (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  firebase_uid text        NOT NULL UNIQUE,
  email        text,
  created_at   timestamptz NOT NULL DEFAULT now()
);
