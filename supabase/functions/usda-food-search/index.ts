const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, accept-language",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
}

type USDAFood = {
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

type NutritionPayload = {
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
  arroz: ["white rice cooked", "rice cooked"],
  banana: ["banana raw"],
  batata: ["potato cooked", "potato"],
  cebola: ["onion raw"],
  cenoura: ["carrot raw"],
  feijao: ["beans cooked", "black beans cooked"],
  frango: ["chicken breast roasted", "chicken breast"],
  iogurte: ["yogurt plain"],
  leite: ["milk whole"],
  maca: ["apple with skin raw", "apple raw"],
  ovo: ["egg whole raw", "egg whole"],
  pao: ["bread white"],
  queijo: ["cheese cheddar", "cheese mozzarella"],
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

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  })
}

function normalizeName(value: string) {
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

function hasMeaningfulMatch(food: USDAFood, rawName: string) {
  const queryTokens = [...tokenSet(rawName)]
  if (queryTokens.length === 0) return false

  const descriptionTokens = tokenSet(food.description ?? "")
  return queryTokens.every((token) => descriptionTokens.has(token))
}

function candidateQueries(rawName: string) {
  const normalized = normalizeName(rawName)
  const singular = normalized.endsWith("s") ? normalized.slice(0, -1) : normalized
  const tokens = singular.split(" ").filter(Boolean)
  const firstTwo = tokens.slice(0, 2).join(" ")
  const aliases = [
    ...(aliasMap[normalized] ?? []),
    ...(aliasMap[singular] ?? []),
    ...(firstTwo ? aliasMap[firstTwo] ?? [] : []),
  ]

  return Array.from(new Set([
    rawName.trim(),
    normalized,
    singular,
    firstTwo,
    ...aliases,
  ].filter(Boolean)))
}

function nutrientValue(food: USDAFood, ids: number[], names: string[], preferredUnits: string[] = []) {
  const nutrients = food.foodNutrients ?? []
  let unitFallback: number | null = null

  for (const nutrient of nutrients) {
    const unitName = nutrient.unitName?.toUpperCase() ?? ""
    if (nutrient.nutrientId && ids.includes(nutrient.nutrientId) && typeof nutrient.value === "number") {
      if (preferredUnits.length === 0 || preferredUnits.includes(unitName)) {
        return nutrient.value
      }
      if (unitFallback === null) {
        unitFallback = nutrient.value
      }
    }
    const nutrientName = nutrient.nutrientName?.toLowerCase() ?? ""
    if (names.some((name) => nutrientName.includes(name)) && typeof nutrient.value === "number") {
      if (preferredUnits.length === 0 || preferredUnits.includes(unitName)) {
        return nutrient.value
      }
      if (unitFallback === null) {
        unitFallback = nutrient.value
      }
    }
  }
  return unitFallback
}

function scoreFood(food: USDAFood, rawName: string) {
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
    nutrientValue(food, [1008], ["energy"], ["KCAL"]),
    nutrientValue(food, [1003], ["protein"], ["G"]),
    nutrientValue(food, [1005], ["carbohydrate"], ["G"]),
    nutrientValue(food, [1004], ["total lipid", "fat"], ["G"]),
  ].every((value) => typeof value === "number")

  if (hasMacros) score += 25
  return score
}

async function searchFood(query: string, apiKey: string) {
  const response = await fetch(`${endpoint}?api_key=${encodeURIComponent(apiKey)}`, {
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

function mapFood(food: USDAFood, rawName: string): NutritionPayload | null {
  const kcal = nutrientValue(food, [1008], ["energy"], ["KCAL"])
  const protein = nutrientValue(food, [1003], ["protein"], ["G"])
  const carbs = nutrientValue(food, [1005], ["carbohydrate"], ["G"])
  const fat = nutrientValue(food, [1004], ["total lipid", "fat"], ["G"])

  if ([kcal, protein, carbs, fat].some((value) => typeof value !== "number")) {
    return null
  }

  const fdcId = food.fdcId
  return {
    name: rawName,
    display_name: food.description ?? rawName,
    kcal_per_100g: kcal as number,
    protein_per_100g: protein as number,
    carbs_per_100g: carbs as number,
    fat_per_100g: fat as number,
    sugar_per_100g: nutrientValue(food, [2000], ["sugars, total", "total sugar"], ["G"]),
    added_sugar_per_100g: nutrientValue(food, [1235], ["added sugars"], ["G"]),
    fiber_per_100g: nutrientValue(food, [1079], ["fiber"], ["G"]),
    saturated_fat_per_100g: nutrientValue(food, [1258], ["saturated"], ["G"]),
    monounsaturated_fat_per_100g: nutrientValue(food, [1292], ["monounsaturated"], ["G"]),
    polyunsaturated_fat_per_100g: nutrientValue(food, [1293], ["polyunsaturated"], ["G"]),
    cholesterol_per_100g: nutrientValue(food, [1253], ["cholesterol"], ["MG"]),
    sodium_per_100g: nutrientValue(food, [1093], ["sodium"], ["MG"]),
    potassium_per_100g: nutrientValue(food, [1092], ["potassium"], ["MG"]),
    emoji: null,
    citation_url: typeof fdcId === "number"
      ? `https://fdc.nal.usda.gov/fdc-app.html#/food-details/${fdcId}/nutrients`
      : null,
  }
}

async function lookupName(rawName: string, apiKey: string) {
  const queries = candidateQueries(rawName)
  let best: USDAFood | null = null
  let bestScore = Number.NEGATIVE_INFINITY

  for (const query of queries) {
    const foods = await searchFood(query, apiKey)
    for (const food of foods) {
      if (!hasMeaningfulMatch(food, query)) {
        continue
      }
      const score = scoreFood(food, query)
      if (score > bestScore) {
        best = food
        bestScore = score
      }
    }
    if (bestScore >= 85) {
      break
    }
  }

  return best ? mapFood(best, rawName) : null
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405)
  }

  const apiKey = Deno.env.get("USDA_API_KEY")
  if (!apiKey) {
    return json({ error: "USDA_API_KEY not configured" }, 500)
  }

  try {
    const body = await request.json()
    const names = Array.isArray(body.names)
      ? body.names.filter((value: unknown): value is string => typeof value === "string" && value.trim().length > 0)
      : []

    if (names.length === 0) {
      return json({ items: [] })
    }

    const items: NutritionPayload[] = []
    for (const name of names.slice(0, 20)) {
      try {
        const match = await lookupName(name, apiKey)
        if (match) {
          items.push(match)
        }
      } catch (error) {
        console.error(`USDA lookup failed for ${name}:`, error)
      }
    }

    return json({ items })
  } catch (error) {
    console.error("usda-food-search fatal error", error)
    return json({ error: error instanceof Error ? error.message : "Unknown error" }, 500)
  }
})
