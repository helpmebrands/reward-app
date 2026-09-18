-- 0001: the first migration. Nothing product-shaped lives here yet; the
-- device registration table arrives with its endpoint. This file exists so
-- the runner has a real migration to apply and the integration test a row
-- to find in schema_migrations.
COMMENT ON SCHEMA public IS 'HelpMe Reward, migrated by services/api';
