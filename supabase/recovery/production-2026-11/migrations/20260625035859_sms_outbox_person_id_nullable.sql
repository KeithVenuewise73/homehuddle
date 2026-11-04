
-- Confirmations and reminders to confirmed-but-not-yet-logged-in roster members
-- have no person record, so person_id must be allowed to be null.
alter table public.sms_outbox alter column person_id drop not null;
