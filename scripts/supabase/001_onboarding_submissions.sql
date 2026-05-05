create extension if not exists pgcrypto;

create table if not exists public.onboarding_submissions (
    id uuid primary key default gen_random_uuid(),
    submission_id text not null unique,
    submitted_at timestamptz not null default now(),
    locale_identifier text not null,
    preferred_language text not null,
    region_code text,
    discovery_source_id text,
    discovery_source_title text,
    nutrition_goal text,
    nutrition_sex text,
    nutrition_activity text,
    nutrition_rate_mode text not null,
    age_years integer,
    height_cm double precision not null,
    weight_kg double precision not null,
    weekly_change_kg double precision not null,
    target_weight_kg double precision not null,
    target_months integer not null,
    selected_plan_id text,
    subscribed boolean not null default false,
    pantry_item_ids jsonb not null default '[]'::jsonb,
    grocery_item_ids jsonb not null default '[]'::jsonb,
    recipe_template_ids jsonb not null default '[]'::jsonb,
    pantry_item_names jsonb not null default '[]'::jsonb,
    grocery_item_names jsonb not null default '[]'::jsonb,
    recipe_template_names jsonb not null default '[]'::jsonb,
    created_at timestamptz not null default now()
);

comment on table public.onboarding_submissions is
    'One-row onboarding summary captured client-side. region_code is locale-derived; the app does not currently ask explicit nationality.';

alter table public.onboarding_submissions enable row level security;

drop policy if exists "anon_insert_onboarding_submissions" on public.onboarding_submissions;
create policy "anon_insert_onboarding_submissions"
on public.onboarding_submissions
for insert
to anon
with check (true);

drop policy if exists "anon_no_select_onboarding_submissions" on public.onboarding_submissions;
create policy "anon_no_select_onboarding_submissions"
on public.onboarding_submissions
for select
to anon
using (false);