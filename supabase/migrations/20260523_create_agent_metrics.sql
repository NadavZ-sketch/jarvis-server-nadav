-- Per-agent latency + intent-classification metrics (Control Center).
-- Written in batches by the server (service role); read for the live
-- "response time per agent" + intent ratio in the Control Center / dashboard.
create extension if not exists pgcrypto;

create table if not exists public.agent_metrics (
  id uuid primary key default gen_random_uuid(),
  agent text not null,
  ms integer not null,
  intent_mode text,
  created_at timestamptz not null default now()
);

create index if not exists idx_agent_metrics_time
  on public.agent_metrics (created_at desc);

create index if not exists idx_agent_metrics_agent_time
  on public.agent_metrics (agent, created_at desc);

alter table public.agent_metrics enable row level security;

-- Server-only data (no per-user rows); accessible to the service role only.
grant all on table public.agent_metrics to service_role;
