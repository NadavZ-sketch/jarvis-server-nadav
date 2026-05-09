-- Some environments enable RLS by default on newly-created tables.
-- The backend uses server-side Supabase access and needs write access for MVP.
alter table if exists user_profiles disable row level security;

grant select, insert, update, delete on table user_profiles to anon;
grant select, insert, update, delete on table user_profiles to authenticated;
grant select, insert, update, delete on table user_profiles to service_role;
