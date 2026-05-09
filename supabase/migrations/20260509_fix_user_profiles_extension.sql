-- Ensure UUID generation is available in all Supabase environments.
create extension if not exists pgcrypto;

-- Recreate table safely if previous migration failed due missing extension.
create table if not exists user_profiles (
  id uuid primary key default gen_random_uuid(),
  speaking_tone text not null default 'friendly',
  preferred_hours text[] not null default '{}',
  interests text[] not null default '{}',
  recurring_tasks text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
