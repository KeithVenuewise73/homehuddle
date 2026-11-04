-- coach_connections.coach_id was an unconstrained, unused uuid column
-- (0 rows in the table). Replace it cleanly with a single properly
-- constrained coach_id column instead of leaving two similarly named
-- columns around.
alter table public.coach_connections drop column coach_id;
alter table public.coach_connections rename column coach_id_link to coach_id;