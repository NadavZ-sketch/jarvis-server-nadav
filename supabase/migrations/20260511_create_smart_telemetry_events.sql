-- Smart Roadmap Lab telemetry (MVP)
create extension if not exists pgcrypto;

create table if not exists public.smart_telemetry_events (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  event_name text not null,
  event_value integer not null default 1,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_smart_telemetry_user_time
  on public.smart_telemetry_events (user_id, created_at desc);

alter table public.smart_telemetry_events enable row level security;

drop policy if exists smart_telemetry_select_own on public.smart_telemetry_events;
drop policy if exists smart_telemetry_insert_own on public.smart_telemetry_events;

create policy smart_telemetry_select_own
  on public.smart_telemetry_events
  for select
  using (auth.uid()::text = user_id);

create policy smart_telemetry_insert_own
  on public.smart_telemetry_events
  for insert
  with check (auth.uid()::text = user_id);

grant select, insert on table public.smart_telemetry_events to authenticated;
grant all on table public.smart_telemetry_events to service_role;
