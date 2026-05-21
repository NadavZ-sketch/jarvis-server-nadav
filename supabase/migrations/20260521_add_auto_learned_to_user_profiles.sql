-- Auto-learned profile fields, distinct from values the user set manually.
-- The learner writes derived values into the visible columns (preferred_hours,
-- interests, recurring_tasks) only for fields NOT listed in
-- auto_learned.user_overridden, so explicit user edits are never clobbered.
alter table user_profiles
    add column if not exists auto_learned jsonb not null default '{}'::jsonb;
