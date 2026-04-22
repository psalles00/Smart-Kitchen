-- =====================================================================
-- Smart Kitchen — Nutrition schema (MVP, Supabase free tier)
-- =====================================================================
-- Safe to run multiple times. Creates a dedicated `nutrition` schema with:
--   * Reference tables: sources, food_groups, nutrients
--   * Local canonical foods (TACO/IBGE) + food_nutrients
--   * foods_cache for responses fetched from external APIs (USDA/OFF)
--   * RLS policies (anon/authenticated can read; authenticated can cache)
--   * RPCs: search_food, get_food_detail
-- Run this once in Supabase Dashboard -> SQL Editor.
-- =====================================================================

create schema if not exists nutrition;

create extension if not exists pg_trgm;
create extension if not exists unaccent;
create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- Reference tables
-- ---------------------------------------------------------------------
create table if not exists nutrition.sources (
  id                    smallserial primary key,
  code                  text unique not null,
  name                  text not null,
  license               text,
  license_url           text,
  attribution_required  boolean default false,
  attribution_text      text,
  website_url           text,
  version               text,
  imported_at           timestamptz
);

create table if not exists nutrition.food_groups (
  id        smallserial primary key,
  code      text unique not null,
  name_pt   text not null,
  name_en   text
);

create table if not exists nutrition.nutrients (
  id             smallserial primary key,
  code           text unique not null,   -- INFOODS tagname
  name_pt        text not null,
  name_en        text not null,
  unit           text not null,          -- kcal | kJ | g | mg | mcg
  category       text not null,          -- energy | macro | mineral | vitamin | fatty_acid | other
  display_order  smallint default 100,
  is_primary     boolean default false   -- shown on quick macro card
);

-- ---------------------------------------------------------------------
-- Foods
-- ---------------------------------------------------------------------
create table if not exists nutrition.foods (
  id                   uuid primary key default gen_random_uuid(),
  source_id            smallint not null references nutrition.sources(id),
  source_food_id       text not null,
  food_group_id        smallint references nutrition.food_groups(id),
  name_pt              text,
  name_en              text,
  scientific_name      text,
  description          text,
  country_code         char(2),           -- BR | US | null=global
  data_type            text,              -- generic | branded | preparation
  brand                text,
  barcode              text,
  serving_size_g       numeric,
  serving_description  text,
  name_normalized      text generated always as (
                          lower(unaccent(coalesce(name_pt, name_en, '')))
                        ) stored,
  created_at           timestamptz default now(),
  unique (source_id, source_food_id)
);

create index if not exists foods_name_trgm_idx
  on nutrition.foods using gin (name_normalized gin_trgm_ops);
create index if not exists foods_barcode_idx
  on nutrition.foods (barcode) where barcode is not null;
create index if not exists foods_country_idx
  on nutrition.foods (country_code);
create index if not exists foods_group_idx
  on nutrition.foods (food_group_id);

create table if not exists nutrition.food_nutrients (
  food_id          uuid not null references nutrition.foods(id) on delete cascade,
  nutrient_id      smallint not null references nutrition.nutrients(id),
  amount_per_100g  numeric not null,
  primary key (food_id, nutrient_id)
);

create index if not exists food_nutrients_nutrient_idx
  on nutrition.food_nutrients (nutrient_id);

-- ---------------------------------------------------------------------
-- Cache for external API lookups (USDA FoodData Central, Open Food Facts)
-- Kept lightweight so the free tier stays within 500 MB budget.
-- ---------------------------------------------------------------------
create table if not exists nutrition.foods_cache (
  id            bigserial primary key,
  source        text not null,            -- 'usda_api' | 'off_api'
  external_id   text not null,            -- fdcId or OFF code
  barcode       text,
  name          text,
  country_code  char(2),
  payload       jsonb not null,
  cached_at     timestamptz default now(),
  unique (source, external_id)
);

create index if not exists foods_cache_barcode_idx
  on nutrition.foods_cache (barcode) where barcode is not null;
create index if not exists foods_cache_name_trgm
  on nutrition.foods_cache using gin (
    (lower(unaccent(coalesce(name, '')))) gin_trgm_ops
  );

-- ---------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------
alter table nutrition.sources         enable row level security;
alter table nutrition.food_groups     enable row level security;
alter table nutrition.nutrients       enable row level security;
alter table nutrition.foods           enable row level security;
alter table nutrition.food_nutrients  enable row level security;
alter table nutrition.foods_cache     enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where schemaname='nutrition' and policyname='read_sources') then
    create policy read_sources        on nutrition.sources        for select using (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname='nutrition' and policyname='read_food_groups') then
    create policy read_food_groups    on nutrition.food_groups    for select using (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname='nutrition' and policyname='read_nutrients') then
    create policy read_nutrients      on nutrition.nutrients      for select using (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname='nutrition' and policyname='read_foods') then
    create policy read_foods          on nutrition.foods          for select using (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname='nutrition' and policyname='read_food_nutrients') then
    create policy read_food_nutrients on nutrition.food_nutrients for select using (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname='nutrition' and policyname='read_foods_cache') then
    create policy read_foods_cache    on nutrition.foods_cache    for select using (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname='nutrition' and policyname='insert_foods_cache') then
    create policy insert_foods_cache  on nutrition.foods_cache    for insert to authenticated with check (true);
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------
grant usage on schema nutrition to anon, authenticated;
grant select on all tables in schema nutrition to anon, authenticated;
grant insert on nutrition.foods_cache to authenticated;
grant usage, select on all sequences in schema nutrition to authenticated;

-- ---------------------------------------------------------------------
-- RPC: search_food
--   Fuzzy search by portuguese/english name with optional country boost.
--   Returns the quick macro card values for ranking preview.
-- ---------------------------------------------------------------------
create or replace function nutrition.search_food(
  q            text,
  country      char(2) default null,
  max_results  int     default 20
) returns table (
  id            uuid,
  name_pt       text,
  name_en       text,
  source_code   text,
  country_code  char(2),
  food_group    text,
  energy_kcal   numeric,
  protein_g     numeric,
  carb_g        numeric,
  fat_g         numeric,
  rank          real
) language sql stable as $$
  with q_norm as (select lower(unaccent(q)) as nq)
  select
    f.id,
    f.name_pt,
    f.name_en,
    s.code,
    f.country_code,
    g.name_pt,
    (select fn.amount_per_100g from nutrition.food_nutrients fn
       join nutrition.nutrients n on n.id = fn.nutrient_id
       where fn.food_id = f.id and n.code = 'ENERC_KCAL' limit 1),
    (select fn.amount_per_100g from nutrition.food_nutrients fn
       join nutrition.nutrients n on n.id = fn.nutrient_id
       where fn.food_id = f.id and n.code = 'PROCNT' limit 1),
    (select fn.amount_per_100g from nutrition.food_nutrients fn
       join nutrition.nutrients n on n.id = fn.nutrient_id
       where fn.food_id = f.id and n.code = 'CHOAVLDF' limit 1),
    (select fn.amount_per_100g from nutrition.food_nutrients fn
       join nutrition.nutrients n on n.id = fn.nutrient_id
       where fn.food_id = f.id and n.code = 'FAT' limit 1),
    similarity(f.name_normalized, (select nq from q_norm)) as rank
  from nutrition.foods f
  left join nutrition.sources     s on s.id = f.source_id
  left join nutrition.food_groups g on g.id = f.food_group_id
  where f.name_normalized % (select nq from q_norm)
    and (country is null or f.country_code = country or f.country_code is null)
  order by
    case when country is not null and f.country_code = country then 0 else 1 end,
    rank desc
  limit max_results;
$$;

-- ---------------------------------------------------------------------
-- RPC: get_food_detail
--   Returns all nutrients + metadata for a single food as a JSON blob.
-- ---------------------------------------------------------------------
create or replace function nutrition.get_food_detail(food_uuid uuid)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'food',       to_jsonb(f.*),
    'source',     to_jsonb(s.*),
    'food_group', to_jsonb(g.*),
    'nutrients',  coalesce((
      select jsonb_agg(jsonb_build_object(
        'code',            n.code,
        'name_pt',         n.name_pt,
        'name_en',         n.name_en,
        'unit',            n.unit,
        'category',        n.category,
        'is_primary',      n.is_primary,
        'amount_per_100g', fn.amount_per_100g
      ) order by n.display_order)
      from nutrition.food_nutrients fn
      join nutrition.nutrients n on n.id = fn.nutrient_id
      where fn.food_id = f.id
    ), '[]'::jsonb)
  )
  from nutrition.foods f
  left join nutrition.sources     s on s.id = f.source_id
  left join nutrition.food_groups g on g.id = f.food_group_id
  where f.id = food_uuid;
$$;

grant execute on function nutrition.search_food(text, char, int)  to anon, authenticated;
grant execute on function nutrition.get_food_detail(uuid)         to anon, authenticated;
