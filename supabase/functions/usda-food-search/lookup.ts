export type USDAFood = {
  fdcId?: number
  description?: string
  dataType?: string
  foodNutrients?: Array<{
    nutrientId?: number
    nutrientName?: string
    unitName?: string
    value?: number
  }>
}

export type NutritionPayload = {
  name: string
  display_name: string
  kcal_per_100g: number
  protein_per_100g: number
  carbs_per_100g: number
  fat_per_100g: number
  sugar_per_100g: number | null
  added_sugar_per_100g: number | null
  fiber_per_100g: number | null
  saturated_fat_per_100g: number | null
  monounsaturated_fat_per_100g: number | null
  polyunsaturated_fat_per_100g: number | null
  cholesterol_per_100g: number | null
  sodium_per_100g: number | null
  potassium_per_100g: number | null
  emoji: string | null
  citation_url: string | null
}

const endpoint = "https://api.nal.usda.gov/fdc/v1/foods/search"

const aliasMap: Record<string, string[]> = {
  arroz: ["rice"],
  "arroz cozido": ["rice cooked"],
  "arroz branco cozido": ["rice white cooked"],
  "arroz integral cozido": ["rice brown cooked"],
  "arroz cru": ["rice raw"],
  banana: ["banana raw"],
  bananas: ["banana raw"],
  batata: ["potato"],
  "batata cozida": ["potato cooked"],
  cebola: ["onion raw"],
  cenoura: ["carrot raw"],
  feijao: ["beans"],
  "feijao cozido": ["beans cooked"],
  "feijao preto cozido": ["black beans cooked"],
  frango: ["chicken"],
  "frango grelhado": ["chicken grilled"],
  "peito de frango grelhado": ["chicken breast grilled"],
  "peito de frango assado": ["chicken breast roasted"],
  iogurte: ["yogurt"],
  "iogurte natural": ["yogurt plain"],
  leite: ["milk"],
  "leite integral": ["milk whole"],
  "leite desnatado": ["milk nonfat"],
  maca: ["apple with skin raw", "apple raw"],
  ovo: ["egg whole raw", "egg whole"],
  ovos: ["egg whole raw", "egg whole"],
  pao: ["bread"],
  "pao branco": ["bread white"],
  queijo: ["cheese"],
  "queijo cheddar": ["cheese cheddar"],
  "queijo mussarela": ["cheese mozzarella"],
  tomate: ["tomato raw"],
}

const preferredDataTypes = ["Foundation", "SR Legacy", "Survey (FNDDS)"]
const negativeDescriptionTerms = [
  "dehydrated",
  "powder",
  "dried",
  "restaurant",
  "noodle",
  "noodles",
  "babyfood",
  "con grandules",
  "mix",
  "flavor",
]

export function normalizeName(value: string) {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
}

function tokenSet(value: string) {
  return new Set(normalizeName(value).split(" ").filter(Boolean))
}

export function hasMeaningfulMatch(food: USDAFood, rawName: string) {
  const queryTokens = [...tokenSet(rawName)]
  if (queryTokens.length === 0) return false

  const descriptionTokens = tokenSet(food.description ?? "")
  if (!queryTokens.every((token) => descriptionTokens.has(token))) return false
  // Shared brand/ingredient words do not make a cereal bar a breakfast cereal,
  // or powdered/condensed milk the requested plain milk.
  const distinctForms = [
    ["bar", "bars"], ["powder", "powdered"], ["condensed"],
    ["dehydrated", "dried"], ["formula", "babyfood"],
  ]
  return distinctForms.every((forms) =>
    !forms.some((form) => descriptionTokens.has(form)) ||
    forms.some((form) => queryTokens.includes(form))
  )
}

export function candidateQueries(rawName: string) {
  const normalized = normalizeName(rawName)
  // Translate only a complete known food identity. Truncating to the first
  // words loses brands, product variants, country and preparation.
  return Array.from(new Set([
    rawName.trim(),
    normalized,
    ...(aliasMap[normalized] ?? []),
  ].filter(Boolean)))
}

type NutrientUnit = "G" | "MG" | "KCAL"

function convertUnit(value: number, rawUnit: string | undefined, target: NutrientUnit) {
  if (!Number.isFinite(value) || value < 0) return null
  const unit = rawUnit?.trim().toUpperCase()
  if (unit === target) return value
  if (unit === "MG" && target === "G") return value / 1000
  if (unit === "G" && target === "MG") return value * 1000
  if (unit === "KJ" && target === "KCAL") return value / 4.184
  return null
}

export function nutrientValue(food: USDAFood, ids: number[], names: string[], unit: NutrientUnit) {
  const nutrients = food.foodNutrients ?? []
  // Search the entire array for the authoritative ID before name fallback.
  // Row order and substrings such as fat/saturated/monounsaturated must never
  // select a different nutrient.
  for (const id of ids) {
    for (const nutrient of nutrients) {
      if (nutrient.nutrientId === id && typeof nutrient.value === "number") {
        const converted = convertUnit(nutrient.value, nutrient.unitName, unit)
        if (converted !== null) return converted
      }
    }
  }
  const exactNames = names.map(normalizeName)
  for (const nutrient of nutrients) {
    if (nutrient.nutrientId != null && !ids.includes(nutrient.nutrientId)) continue
    if (exactNames.includes(normalizeName(nutrient.nutrientName ?? "")) && typeof nutrient.value === "number") {
      const converted = convertUnit(nutrient.value, nutrient.unitName, unit)
      if (converted !== null) return converted
    }
  }
  return null
}

export function scoreFood(food: USDAFood, rawName: string) {
  const normalizedQuery = normalizeName(rawName)
  const description = normalizeName(food.description ?? "")

  let score = 0
  if (food.dataType === "Foundation") score += 60
  if (food.dataType === "SR Legacy") score += 50
  if (food.dataType === "Survey (FNDDS)") score += 40
  if (description === normalizedQuery) score += 35
  if (description.startsWith(normalizedQuery)) score += 20
  if (normalizedQuery.split(" ").every((token) => description.includes(token))) score += 10
  if (negativeDescriptionTerms.some((term) => description.includes(term))) score -= 40
  score -= Math.max(description.split(" ").length - normalizedQuery.split(" ").length, 0)

  const hasMacros = [
    nutrientValue(food, [1008, 2047, 2048, 1062], ["energy"], "KCAL"),
    nutrientValue(food, [1003], ["protein"], "G"),
    nutrientValue(food, [1005], ["carbohydrate, by difference"], "G"),
    nutrientValue(food, [1004], ["total lipid (fat)", "fat"], "G"),
  ].every((value) => typeof value === "number")

  if (hasMacros) score += 25
  return score
}

async function searchFood(query: string, apiKey: string, fetcher: typeof fetch) {
  const response = await fetcher(`${endpoint}?api_key=${encodeURIComponent(apiKey)}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      query,
      pageSize: 8,
      dataType: preferredDataTypes,
    }),
  })

  if (!response.ok) {
    const message = await response.text()
    throw new Error(`USDA search failed (${response.status}): ${message}`)
  }

  const jsonBody = await response.json()
  return (jsonBody.foods ?? []) as USDAFood[]
}

export function mapFood(food: USDAFood, rawName: string): NutritionPayload | null {
  const kcal = nutrientValue(food, [1008, 2047, 2048, 1062], ["energy"], "KCAL")
  const protein = nutrientValue(food, [1003], ["protein"], "G")
  const carbs = nutrientValue(food, [1005], ["carbohydrate, by difference"], "G")
  const fat = nutrientValue(food, [1004], ["total lipid (fat)", "fat"], "G")

  if ([kcal, protein, carbs, fat].some((value) => typeof value !== "number")) {
    return null
  }

  const fdcId = food.fdcId
  const result: NutritionPayload = {
    name: rawName,
    display_name: food.description ?? rawName,
    kcal_per_100g: kcal as number,
    protein_per_100g: protein as number,
    carbs_per_100g: carbs as number,
    fat_per_100g: fat as number,
    sugar_per_100g: nutrientValue(food, [2000], ["sugars, total", "sugars, total including NLEA", "total sugar"], "G"),
    added_sugar_per_100g: nutrientValue(food, [1235], ["sugars, added", "added sugars"], "G"),
    fiber_per_100g: nutrientValue(food, [1079], ["fiber, total dietary"], "G"),
    saturated_fat_per_100g: nutrientValue(food, [1258], ["fatty acids, total saturated"], "G"),
    monounsaturated_fat_per_100g: nutrientValue(food, [1292], ["fatty acids, total monounsaturated"], "G"),
    polyunsaturated_fat_per_100g: nutrientValue(food, [1293], ["fatty acids, total polyunsaturated"], "G"),
    cholesterol_per_100g: nutrientValue(food, [1253], ["cholesterol"], "MG"),
    sodium_per_100g: nutrientValue(food, [1093], ["sodium, Na"], "MG"),
    potassium_per_100g: nutrientValue(food, [1092], ["potassium, K"], "MG"),
    emoji: null,
    citation_url: typeof fdcId === "number"
      ? `https://fdc.nal.usda.gov/fdc-app.html#/food-details/${fdcId}/nutrients`
      : null,
  }
  return isPlausibleNutrition(result) ? result : null
}

export function isPlausibleNutrition(value: NutritionPayload) {
  const { kcal_per_100g: kcal, protein_per_100g: protein, carbs_per_100g: carbs, fat_per_100g: fat } = value
  if (!Number.isFinite(kcal) || kcal < 0 || kcal > 950) return false
  if (![protein, carbs, fat].every((v) => Number.isFinite(v) && v >= 0 && v <= 100)) return false
  if (protein + carbs + fat > 110) return false
  const macroEnergy = 4 * protein + 4 * carbs + 9 * fat
  // Allow differing energy factors and label rounding, reject gross mismatches.
  if (Math.abs(kcal - macroEnergy) > Math.max(40, macroEnergy * 0.3)) return false
  const fattyAcids = [value.saturated_fat_per_100g, value.monounsaturated_fat_per_100g, value.polyunsaturated_fat_per_100g]
  if (!fattyAcids.every((v) => v === null || (Number.isFinite(v) && v >= 0 && v <= fat + 1.5))) return false
  if (fattyAcids.reduce<number>((sum, v) => sum + (v ?? 0), 0) > fat + 2) return false
  if (value.sugar_per_100g !== null && value.sugar_per_100g > carbs + 1.5) return false
  if (value.added_sugar_per_100g !== null && value.added_sugar_per_100g > (value.sugar_per_100g ?? carbs) + 1.5) return false
  return true
}

export async function lookupName(rawName: string, apiKey: string, fetcher: typeof fetch = fetch) {
  const queries = candidateQueries(rawName)
  let best: NutritionPayload | null = null
  let bestScore = Number.NEGATIVE_INFINITY

  for (const query of queries) {
    const foods = await searchFood(query, apiKey, fetcher)
    for (const food of foods) {
      if (!hasMeaningfulMatch(food, query)) {
        continue
      }
      const mapped = mapFood(food, rawName)
      if (!mapped) continue
      const score = scoreFood(food, query)
      if (score > bestScore) {
        best = mapped
        bestScore = score
      }
    }
    if (bestScore >= 85) {
      break
    }
  }

  return best
}

