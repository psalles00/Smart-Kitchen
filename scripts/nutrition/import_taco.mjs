#!/usr/bin/env node
/**
 * Import TACO 4ª ed. (597 foods) into Supabase via PostgREST.
 *
 * Requires Node 18+ (built-in fetch). No external deps.
 *
 * Env vars (in scripts/nutrition/.env):
 *   SUPABASE_URL              e.g. https://yfcmvdijvgeaihvwyssb.supabase.co
 *   SUPABASE_SERVICE_ROLE_KEY eyJhbGci...  (NEVER commit this)
 *
 * Usage:
 *   node scripts/nutrition/import_taco.mjs
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// ---------- Env loader (no dotenv dep) -------------------------------
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const envPath = path.join(__dirname, '.env');
if (fs.existsSync(envPath)) {
  for (const line of fs.readFileSync(envPath, 'utf8').split(/\r?\n/)) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/);
    if (m && !process.env[m[1]]) process.env[m[1]] = m[2].replace(/^["']|["']$/g, '');
  }
}

const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_KEY  = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!SUPABASE_URL || !SERVICE_KEY) {
  console.error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY in env.');
  process.exit(1);
}

// ---------- PostgREST helpers ----------------------------------------
const REST = `${SUPABASE_URL}/rest/v1`;
const headers = {
  apikey: SERVICE_KEY,
  Authorization: `Bearer ${SERVICE_KEY}`,
  'Content-Type': 'application/json',
  'Content-Profile': 'nutrition',
  'Accept-Profile': 'nutrition',
};

async function rest(method, pathname, { body, prefer, query } = {}) {
  const url = `${REST}${pathname}${query ? `?${query}` : ''}`;
  const res = await fetch(url, {
    method,
    headers: { ...headers, ...(prefer ? { Prefer: prefer } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`${method} ${url} -> ${res.status} ${res.statusText}\n${text}`);
  }
  return text ? JSON.parse(text) : null;
}

// ---------- TACO -> INFOODS mapping ----------------------------------
// Only the nutrients whose TACO field exists and is meaningful for MVP.
const TACO_TO_INFOODS = {
  energy_kcal:        'ENERC_KCAL',
  energy_kj:          'ENERC_KJ',
  protein_g:          'PROCNT',
  lipid_g:            'FAT',
  carbohydrate_g:     'CHOAVLDF', // TACO's carbohydrate column excludes fibre (by difference)
  fiber_g:            'FIBTG',
  cholesterol_mg:     'CHOLE',
  humidity_percents:  'WATER',
  ashes_g:            'ASH',
  calcium_mg:         'CA',
  magnesium_mg:       'MG',
  manganese_mg:       'MN',
  phosphorus_mg:      'P',
  iron_mg:            'FE',
  sodium_mg:          'NA',
  potassium_mg:       'K',
  copper_mg:          'CU',
  zinc_mg:            'ZN',
  retinol_mcg:        'RETOL',
  re_mcg:             'VITA',
  rae_mcg:            'VITA_RAE',
  thiamine_mg:        'THIA',
  riboflavin_mg:      'RIBF',
  pyridoxine_mg:      'VITB6A',
  niacin_mg:          'NIA',
  vitaminC_mg:        'VITC',
  saturated_g:        'FASAT',
  monounsaturated_g:  'FAMS',
  polyunsaturated_g:  'FAPU',
};

// TACO food groups (pt-BR) -> food_groups.code
const GROUP_MAP = {
  'Cereais e derivados':                   'cereais',
  'Verduras, hortaliças e derivados':      'verduras',
  'Frutas e derivados':                    'frutas',
  'Gorduras e óleos':                      'gorduras',
  'Pescados e frutos do mar':              'pescados',
  'Carnes e derivados':                    'carnes',
  'Leite e derivados':                     'leite',
  'Bebidas (alcoólicas e não alcoólicas)': 'bebidas',
  'Ovos e derivados':                      'ovos',
  'Produtos açucarados':                   'acucarados',
  'Miscelâneas':                           'miscelaneas',
  'Outros alimentos industrializados':     'industrializados',
  'Alimentos preparados':                  'preparados',
  'Leguminosas e derivados':               'leguminosas',
  'Nozes e sementes':                      'nozes',
};

function parseAmount(v) {
  if (v === null || v === undefined) return null;
  if (typeof v === 'number') return Number.isFinite(v) ? v : null;
  const s = String(v).trim();
  if (!s || s === 'NA' || s === 'na' || s === '-' || s === '*') return null;
  if (s === 'Tr' || s === 'tr') return 0;      // trace -> store as 0
  const n = Number(s.replace(',', '.'));
  return Number.isFinite(n) ? n : null;
}

// ---------- Main -----------------------------------------------------
async function main() {
  console.log('→ Loading reference data from Supabase...');
  const [sources, nutrients, groups] = await Promise.all([
    rest('GET', '/sources',     { query: 'select=id,code' }),
    rest('GET', '/nutrients',   { query: 'select=id,code' }),
    rest('GET', '/food_groups', { query: 'select=id,code' }),
  ]);

  const sourceId = sources.find(s => s.code === 'taco')?.id;
  if (!sourceId) throw new Error('Source "taco" not found. Run 001_seed_reference.sql first.');
  const nutrientByCode = Object.fromEntries(nutrients.map(n => [n.code, n.id]));
  const groupByCode    = Object.fromEntries(groups.map(g => [g.code, g.id]));

  const raw = JSON.parse(fs.readFileSync(path.join(__dirname, 'data', 'TACO.json'), 'utf8'));
  console.log(`→ Parsed TACO.json: ${raw.length} foods`);

  // ---------- Upsert foods ----------
  const foodRows = raw.map(item => {
    const groupCode = GROUP_MAP[item.category] || 'miscelaneas';
    return {
      source_id:      sourceId,
      source_food_id: String(item.id),
      food_group_id:  groupByCode[groupCode] ?? null,
      name_pt:        item.description,
      country_code:   'BR',
      data_type:      'generic',
    };
  });

  console.log('→ Upserting foods...');
  const CHUNK = 250;
  const insertedFoods = [];
  for (let i = 0; i < foodRows.length; i += CHUNK) {
    const batch = foodRows.slice(i, i + CHUNK);
    const rows = await rest('POST', '/foods', {
      body: batch,
      prefer: 'resolution=merge-duplicates,return=representation',
      query: 'on_conflict=source_id,source_food_id&select=id,source_food_id',
    });
    insertedFoods.push(...rows);
    process.stdout.write(`  ${Math.min(i + CHUNK, foodRows.length)}/${foodRows.length}\r`);
  }
  console.log(`  ${insertedFoods.length}/${foodRows.length} foods upserted.`);

  const foodIdBySourceId = Object.fromEntries(
    insertedFoods.map(f => [f.source_food_id, f.id])
  );

  // ---------- Build food_nutrients rows ----------
  console.log('→ Building food_nutrients...');
  const nutrientRows = [];
  for (const item of raw) {
    const foodId = foodIdBySourceId[String(item.id)];
    if (!foodId) continue;
    for (const [tacoKey, infoodsCode] of Object.entries(TACO_TO_INFOODS)) {
      const amt = parseAmount(item[tacoKey]);
      if (amt === null) continue;
      const nid = nutrientByCode[infoodsCode];
      if (!nid) continue;
      nutrientRows.push({
        food_id:         foodId,
        nutrient_id:     nid,
        amount_per_100g: amt,
      });
    }
  }
  console.log(`  ${nutrientRows.length} nutrient rows ready.`);

  // ---------- Upsert food_nutrients ----------
  console.log('→ Upserting food_nutrients...');
  for (let i = 0; i < nutrientRows.length; i += 1000) {
    const batch = nutrientRows.slice(i, i + 1000);
    await rest('POST', '/food_nutrients', {
      body: batch,
      prefer: 'resolution=merge-duplicates,return=minimal',
      query: 'on_conflict=food_id,nutrient_id',
    });
    process.stdout.write(`  ${Math.min(i + 1000, nutrientRows.length)}/${nutrientRows.length}\r`);
  }
  console.log(`  ${nutrientRows.length}/${nutrientRows.length} food_nutrients upserted.`);

  // ---------- Mark source as imported ----------
  await rest('PATCH', '/sources', {
    body: { imported_at: new Date().toISOString() },
    query: 'code=eq.taco',
  });

  console.log('✅ TACO import complete.');
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
