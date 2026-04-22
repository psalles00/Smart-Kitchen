-- =====================================================================
-- Smart Kitchen — Reference data seeds
-- =====================================================================
-- Sources, nutrient taxonomy (INFOODS tagnames), and food groups.
-- Idempotent via ON CONFLICT.
-- Run in Supabase Dashboard -> SQL Editor after 000_schema.sql.
-- =====================================================================

-- ---------------------------------------------------------------------
-- SOURCES
-- ---------------------------------------------------------------------
insert into nutrition.sources (code, name, license, license_url, attribution_required, attribution_text, website_url, version) values
  ('taco',     'TACO – Tabela Brasileira de Composição de Alimentos (NEPA/Unicamp)', 'Free distribution with citation', 'https://www.nepa.unicamp.br/taco/',                                                                      true,  'Dados: TACO 4ª ed. (NEPA/Unicamp)', 'https://www.nepa.unicamp.br/taco/',        '4ed'),
  ('ibge_pof', 'IBGE — Pesquisa de Orçamentos Familiares',                          'Public domain (government data)', 'https://www.ibge.gov.br/estatisticas/sociais/saude/24786-pesquisa-de-orcamentos-familiares-2.html',        true,  'Dados: IBGE POF',                   'https://www.ibge.gov.br/',                  'POF 2017-2018'),
  ('usda_api', 'USDA FoodData Central (live API)',                                  'CC0 1.0 Universal',               'https://creativecommons.org/publicdomain/zero/1.0/',                                                       false, 'U.S. Department of Agriculture, Agricultural Research Service, FoodData Central', 'https://fdc.nal.usda.gov/', 'api-v1'),
  ('off_api',  'Open Food Facts (live API)',                                        'ODbL 1.0 + DbCL 1.0',              'https://opendatacommons.org/licenses/odbl/1.0/',                                                           true,  'Contém dados do Open Food Facts (ODbL)', 'https://world.openfoodfacts.org/', 'api-v2')
on conflict (code) do update set
  name = excluded.name,
  license = excluded.license,
  license_url = excluded.license_url,
  attribution_required = excluded.attribution_required,
  attribution_text = excluded.attribution_text,
  website_url = excluded.website_url,
  version = excluded.version;

-- ---------------------------------------------------------------------
-- FOOD GROUPS (TACO's 15 groups + a few extras)
-- ---------------------------------------------------------------------
insert into nutrition.food_groups (code, name_pt, name_en) values
  ('cereais',         'Cereais e derivados',                   'Cereals and derivatives'),
  ('verduras',        'Verduras, hortaliças e derivados',      'Vegetables'),
  ('frutas',          'Frutas e derivados',                    'Fruits and derivatives'),
  ('gorduras',        'Gorduras e óleos',                      'Fats and oils'),
  ('pescados',        'Pescados e frutos do mar',              'Fish and seafood'),
  ('carnes',          'Carnes e derivados',                    'Meats and derivatives'),
  ('leite',           'Leite e derivados',                     'Dairy'),
  ('bebidas',         'Bebidas (alcoólicas e não alcoólicas)', 'Beverages'),
  ('ovos',            'Ovos e derivados',                      'Eggs and derivatives'),
  ('acucarados',      'Produtos açucarados',                   'Sugary products'),
  ('miscelaneas',     'Miscelâneas',                           'Miscellaneous'),
  ('industrializados','Outros alimentos industrializados',     'Industrialized foods'),
  ('preparados',      'Alimentos preparados',                  'Prepared foods'),
  ('leguminosas',     'Leguminosas e derivados',               'Legumes and derivatives'),
  ('nozes',           'Nozes e sementes',                      'Nuts and seeds'),
  ('fast_food',       'Fast food',                             'Fast food'),
  ('fins_especiais',  'Alimentos para fins especiais',         'Special purpose foods')
on conflict (code) do update set
  name_pt = excluded.name_pt,
  name_en = excluded.name_en;

-- ---------------------------------------------------------------------
-- NUTRIENTS — INFOODS tagnames
-- display_order groups related nutrients; is_primary flags macros used
-- on the quick-glance card in the mobile app.
-- ---------------------------------------------------------------------
insert into nutrition.nutrients (code, name_pt, name_en, unit, category, display_order, is_primary) values
  -- Energy (10-19)
  ('ENERC_KCAL', 'Energia',                  'Energy',                 'kcal', 'energy',      10, true),
  ('ENERC_KJ',   'Energia',                  'Energy',                 'kJ',   'energy',      11, false),
  -- Macros (20-49)
  ('PROCNT',     'Proteínas',                'Protein',                'g',    'macro',       20, true),
  ('FAT',        'Lipídios totais',          'Total fat',              'g',    'macro',       21, true),
  ('CHOAVLDF',   'Carboidratos disponíveis', 'Available carbohydrate', 'g',    'macro',       22, true),
  ('CHOCDF',     'Carboidratos totais',      'Carbohydrate (by diff)', 'g',    'macro',       23, false),
  ('FIBTG',      'Fibra alimentar',          'Dietary fibre',          'g',    'macro',       24, true),
  ('SUGAR',      'Açúcares totais',          'Total sugars',           'g',    'macro',       25, false),
  ('WATER',      'Umidade',                  'Water',                  'g',    'other',       26, false),
  ('ASH',        'Cinzas',                   'Ash',                    'g',    'other',       27, false),
  ('ALC',        'Álcool',                   'Alcohol',                'g',    'macro',       28, false),
  -- Fatty acids (50-69)
  ('FASAT',      'Gorduras saturadas',       'Saturated fat',          'g',    'fatty_acid',  50, true),
  ('FAMS',       'Gorduras monoinsaturadas', 'Monounsaturated fat',    'g',    'fatty_acid',  51, false),
  ('FAPU',       'Gorduras poli-insaturadas','Polyunsaturated fat',    'g',    'fatty_acid',  52, false),
  ('FATRN',      'Gorduras trans',           'Trans fat',              'g',    'fatty_acid',  53, true),
  ('CHOLE',      'Colesterol',               'Cholesterol',            'mg',   'fatty_acid',  54, false),
  -- Minerals (70-99)
  ('NA',         'Sódio',                    'Sodium',                 'mg',   'mineral',     70, true),
  ('K',          'Potássio',                 'Potassium',              'mg',   'mineral',     71, false),
  ('CA',         'Cálcio',                   'Calcium',                'mg',   'mineral',     72, false),
  ('MG',         'Magnésio',                 'Magnesium',              'mg',   'mineral',     73, false),
  ('P',          'Fósforo',                  'Phosphorus',             'mg',   'mineral',     74, false),
  ('FE',         'Ferro',                    'Iron',                   'mg',   'mineral',     75, false),
  ('ZN',         'Zinco',                    'Zinc',                   'mg',   'mineral',     76, false),
  ('CU',         'Cobre',                    'Copper',                 'mg',   'mineral',     77, false),
  ('MN',         'Manganês',                 'Manganese',              'mg',   'mineral',     78, false),
  ('SE',         'Selênio',                  'Selenium',               'mcg',  'mineral',     79, false),
  -- Vitamins (100-129)
  ('VITA_RAE',   'Vitamina A (RAE)',         'Vitamin A (RAE)',        'mcg',  'vitamin',    100, false),
  ('VITA',       'Vitamina A (RE)',          'Vitamin A (RE)',         'mcg',  'vitamin',    101, false),
  ('RETOL',      'Retinol',                  'Retinol',                'mcg',  'vitamin',    102, false),
  ('THIA',       'Tiamina (B1)',             'Thiamin',                'mg',   'vitamin',    103, false),
  ('RIBF',       'Riboflavina (B2)',         'Riboflavin',             'mg',   'vitamin',    104, false),
  ('NIA',        'Niacina (B3)',             'Niacin',                 'mg',   'vitamin',    105, false),
  ('VITB6A',     'Vitamina B6',              'Vitamin B6',             'mg',   'vitamin',    106, false),
  ('FOLDFE',     'Folato (DFE)',             'Folate (DFE)',           'mcg',  'vitamin',    107, false),
  ('VITB12',     'Vitamina B12',             'Vitamin B12',            'mcg',  'vitamin',    108, false),
  ('VITC',       'Vitamina C',               'Vitamin C',              'mg',   'vitamin',    109, false),
  ('VITD',       'Vitamina D',               'Vitamin D',              'mcg',  'vitamin',    110, false),
  ('TOCPHA',     'Vitamina E (α-tocoferol)', 'Vitamin E',              'mg',   'vitamin',    111, false),
  ('VITK',       'Vitamina K',               'Vitamin K',              'mcg',  'vitamin',    112, false)
on conflict (code) do update set
  name_pt = excluded.name_pt,
  name_en = excluded.name_en,
  unit = excluded.unit,
  category = excluded.category,
  display_order = excluded.display_order,
  is_primary = excluded.is_primary;
