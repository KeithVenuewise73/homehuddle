-- ============================================================================
-- PlayingTime Football — reverse of 0001.
--
-- Additive migration, so the reverse is a clean drop of the schema it created.
-- Nothing outside `playingtime` is touched, and nothing in `public` was ever
-- altered, so there is nothing else to restore.
--
-- This DELETES every PlayingTime game stored in the database. Take a backup
-- first; the app's Settings > Export gives each parent their own copy.
-- ============================================================================

drop schema if exists playingtime cascade;
