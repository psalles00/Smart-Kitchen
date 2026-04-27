-- =====================================================================
-- Smart Kitchen — AI food cache (Exa + LLM fallback)
-- =====================================================================
-- Safe to run multiple times. Creates a dedicated cache in `public` so we do
-- not mutate the curated `nutrition.*` schema.
--
-- Objects:
--   * public.ai_food_cache
--   * public.ai_food_votes
--   * public.ai_cast_food_vote(uuid, uuid, smallint)
--   * public.ai_upsert_food(...)
--
-- Run this in Supabase Dashboard -> SQL Editor.
-- =====================================================================

create extension if not exists pgcrypto;

create table if not exists public.ai_food_cache (
  id uuid primary key default gen_random_uuid(),
  canonical_name text not null,
  locale text not null default 'pt-BR',
  display_name text,
  kcal_per_100g numeric,
  protein_per_100g numeric,
  carbs_per_100g numeric,
  fat_per_100g numeric,
  sugar_per_100g numeric,
  added_sugar_per_100g numeric,
  fiber_per_100g numeric,
  saturated_fat_per_100g numeric,
  monounsaturated_fat_per_100g numeric,
  polyunsaturated_fat_per_100g numeric,
  cholesterol_per_100g numeric,
  sodium_per_100g numeric,
  potassium_per_100g numeric,
  source text not null check (source in ('exa', 'llm', 'manual')),
  citation_url text,
  emoji text,
  upvotes integer not null default 0,
  downvotes integer not null default 0,
  invalidated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ai_food_cache_canonical_locale_unique unique (canonical_name, locale)
);

create index if not exists ai_food_cache_lookup_idx
  on public.ai_food_cache (canonical_name, locale)
  where invalidated_at is null;

create table if not exists public.ai_food_votes (
  food_id uuid not null references public.ai_food_cache(id) on delete cascade,
  device_id uuid not null,
  vote smallint not null check (vote in (-1, 1)),
  created_at timestamptz not null default now(),
  primary key (food_id, device_id)
);

alter table public.ai_food_cache enable row level security;
alter table public.ai_food_votes enable row level security;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public' and tablename = 'ai_food_cache' and policyname = 'ai_food_cache_read'
  ) then
    create policy ai_food_cache_read
      on public.ai_food_cache
      for select
      using (invalidated_at is null);
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public' and tablename = 'ai_food_votes' and policyname = 'ai_food_votes_read'
  ) then
    create policy ai_food_votes_read
      on public.ai_food_votes
      for select
      using (true);
  end if;
end
$$;

grant select on public.ai_food_cache to anon, authenticated;
grant select on public.ai_food_votes to anon, authenticated;

create or replace function public.ai_cast_food_vote(
  p_food_id uuid,
  p_device_id uuid,
  p_vote smallint
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_vote not in (-1, 1) then
    raise exception 'invalid vote';
  end if;

  insert into public.ai_food_votes (food_id, device_id, vote)
  values (p_food_id, p_device_id, p_vote)
  on conflict (food_id, device_id)
  do update set vote = excluded.vote, created_at = now();

  update public.ai_food_cache
  set
    upvotes = (
      select count(*)
      from public.ai_food_votes
      where food_id = p_food_id and vote = 1
    ),
    downvotes = (
      select count(*)
      from public.ai_food_votes
      where food_id = p_food_id and vote = -1
    ),
    updated_at = now()
  where id = p_food_id;

  update public.ai_food_cache
  set invalidated_at = now()
  where id = p_food_id
    and downvotes >= 3
    and downvotes > upvotes
    and invalidated_at is null;
end;
$$;

revoke all on function public.ai_cast_food_vote(uuid, uuid, smallint) from public;
grant execute on function public.ai_cast_food_vote(uuid, uuid, smallint) to anon, authenticated;

create or replace function public.ai_upsert_food(
  p_canonical_name text,
  p_locale text,
  p_display_name text,
  p_kcal numeric,
  p_protein numeric,
  p_carbs numeric,
  p_fat numeric,
  p_sugar numeric,
  p_added_sugar numeric,
  p_fiber numeric,
  p_sat_fat numeric,
  p_mono_fat numeric,
  p_poly_fat numeric,
  p_cholesterol numeric,
  p_sodium numeric,
  p_potassium numeric,
  p_source text,
  p_citation_url text,
  p_emoji text
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  insert into public.ai_food_cache (
    canonical_name,
    locale,
    display_name,
    kcal_per_100g,
    protein_per_100g,
    carbs_per_100g,
    fat_per_100g,
    sugar_per_100g,
    added_sugar_per_100g,
    fiber_per_100g,
    saturated_fat_per_100g,
    monounsaturated_fat_per_100g,
    polyunsaturated_fat_per_100g,
    cholesterol_per_100g,
    sodium_per_100g,
    potassium_per_100g,
    source,
    citation_url,
    emoji
  ) values (
    p_canonical_name,
    p_locale,
    p_display_name,
    p_kcal,
    p_protein,
    p_carbs,
    p_fat,
    p_sugar,
    p_added_sugar,
    p_fiber,
    p_sat_fat,
    p_mono_fat,
    p_poly_fat,
    p_cholesterol,
    p_sodium,
    p_potassium,
    p_source,
    p_citation_url,
    p_emoji
  )
  on conflict (canonical_name, locale)
  do update set
    display_name = excluded.display_name,
    kcal_per_100g = excluded.kcal_per_100g,
    protein_per_100g = excluded.protein_per_100g,
    carbs_per_100g = excluded.carbs_per_100g,
    fat_per_100g = excluded.fat_per_100g,
    sugar_per_100g = excluded.sugar_per_100g,
    added_sugar_per_100g = excluded.added_sugar_per_100g,
    fiber_per_100g = excluded.fiber_per_100g,
    saturated_fat_per_100g = excluded.saturated_fat_per_100g,
    monounsaturated_fat_per_100g = excluded.monounsaturated_fat_per_100g,
    polyunsaturated_fat_per_100g = excluded.polyunsaturated_fat_per_100g,
    cholesterol_per_100g = excluded.cholesterol_per_100g,
    sodium_per_100g = excluded.sodium_per_100g,
    potassium_per_100g = excluded.potassium_per_100g,
    source = excluded.source,
    citation_url = excluded.citation_url,
    emoji = excluded.emoji,
    upvotes = 0,
    downvotes = 0,
    invalidated_at = null,
    updated_at = now()
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.ai_upsert_food(text, text, text, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, text, text, text) from public;
grant execute on function public.ai_upsert_food(text, text, text, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, text, text, text) to anon, authenticated;