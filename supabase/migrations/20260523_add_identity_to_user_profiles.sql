-- Add identity fields to user_profiles so that userName, assistantName,
-- gender and personality survive device reinstalls / device switches.
alter table user_profiles
    add column if not exists user_name      text not null default 'נדב',
    add column if not exists assistant_name text not null default 'Jarvis',
    add column if not exists gender         text not null default 'male',
    add column if not exists personality    text not null default 'friendly';
