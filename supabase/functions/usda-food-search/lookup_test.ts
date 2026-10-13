import { candidateQueries, hasMeaningfulMatch, lookupName, mapFood, nutrientValue, type USDAFood } from "./lookup.ts"

function equal(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`)
  }
}

function nutrient(nutrientId: number, nutrientName: string, value: number, unitName = "G") {
  return { nutrientId, nutrientName, value, unitName }
}

function cerealFood(): USDAFood {
  return {
    fdcId: 168862,
    description: "Kelloggs Nutri Grain cereal bars",
    dataType: "SR Legacy",
    foodNutrients: [
      nutrient(1258, "Fatty acids, total saturated", 1.99),
      nutrient(1292, "Fatty acids, total monounsaturated", 4.54),
      nutrient(1293, "Fatty acids, total polyunsaturated", 2.5),
      nutrient(1008, "Energy", 365, "KCAL"),
      nutrient(1003, "Protein", 6),
      nutrient(1005, "Carbohydrate, by difference", 65),
      nutrient(1004, "Total lipid (fat)", 9.5),
      nutrient(1093, "Sodium, Na", 0.5),
    ],
  }
}

Deno.test("nutrient IDs win over earlier fat subtype rows in every row order", () => {
  const food = cerealFood()
  const rows = food.foodNutrients!
  for (const order of [rows, [...rows].reverse(), [...rows.slice(2), ...rows.slice(0, 2)]]) {
    const mapped = mapFood({ ...food, foodNutrients: order }, "Kelloggs Nutri Grain cereal bars")
    equal(mapped?.fat_per_100g, 9.5)
    equal(mapped?.saturated_fat_per_100g, 1.99)
    equal(mapped?.monounsaturated_fat_per_100g, 4.54)
    equal(mapped?.polyunsaturated_fat_per_100g, 2.5)
  }
})

Deno.test("nutrient names require an exact identity, never substrings", () => {
  const food = { foodNutrients: [{ nutrientName: "Fatty acids, total saturated", value: 1.99, unitName: "G" }] }
  equal(nutrientValue(food, [1004], ["fat"], "G"), null)
  equal(nutrientValue(food, [1292], ["monounsaturated"], "G"), null)
  equal(nutrientValue(food, [1258], ["fatty acids, total saturated"], "G"), 1.99)
})

Deno.test("known IDs cannot be relabeled as another nutrient", () => {
  const food = { foodNutrients: [nutrient(1258, "Fat", 1.99)] }
  equal(nutrientValue(food, [1004], ["fat"], "G"), null)
})

Deno.test("mass and energy units are converted before returning values", () => {
  const food = { foodNutrients: [
    nutrient(1093, "Sodium, Na", 0.5, "G"),
    nutrient(1003, "Protein", 6000, "MG"),
    nutrient(1062, "Energy", 418.4, "KJ"),
  ] }
  equal(nutrientValue(food, [1093], ["sodium, Na"], "MG"), 500)
  equal(nutrientValue(food, [1003], ["protein"], "G"), 6)
  const kcal = nutrientValue(food, [1008, 2047, 2048, 1062], ["energy"], "KCAL")
  if (kcal === null || Math.abs(kcal - 100) > 1e-9) throw new Error("kJ conversion failed")
})

Deno.test("missing or incompatible units cannot masquerade as grams", () => {
  equal(nutrientValue({ foodNutrients: [nutrient(1004, "Fat", 12, "KCAL")] }, [1004], ["fat"], "G"), null)
  equal(nutrientValue({ foodNutrients: [{ nutrientId: 1004, value: 12 }] }, [1004], ["fat"], "G"), null)
})

Deno.test("search preserves brand, variant, country and preparation", () => {
  for (const name of ["Nestle Moça Integral condensed milk Brazil", "Coca Cola Original US", "Nutella Classic UK", "chicken grilled with skin"]) {
    const queries = candidateQueries(name)
    if (queries.length < 1 || queries.length > 2) throw new Error("Unexpected broad aliases")
    if (queries.some((q) => q.split(" ").length < name.split(" ").length)) throw new Error("Identity truncated")
  }
  equal(candidateQueries("US"), ["US", "us"])
  equal(hasMeaningfulMatch({ description: "Milk canned condensed sweetened" }, "Nestle Moça Integral condensed milk Brazil"), false)
  equal(hasMeaningfulMatch({ description: "Coca Cola Zero US" }, "Coca Cola Original US"), false)
})

Deno.test("only complete known Portuguese identities get equivalent aliases", () => {
  const queries = candidateQueries("arroz branco cozido")
  equal(queries, ["arroz branco cozido", "rice white cooked"])
  equal(candidateQueries("arroz branco cozido marca especial"), ["arroz branco cozido marca especial"])
  equal(hasMeaningfulMatch({ description: "Rice white cooked" }, queries[1]), true)
  equal(hasMeaningfulMatch({ description: "Rice white raw" }, queries[1]), false)
})

Deno.test("shared brand words cannot turn ambiguous cereal into a cereal bar", () => {
  equal(hasMeaningfulMatch(cerealFood(), "Kelloggs cereal"), false)
  equal(hasMeaningfulMatch(cerealFood(), "Kelloggs Nutri Grain cereal bars"), true)
  equal(hasMeaningfulMatch({ description: "Milk condensed sweetened" }, "milk"), false)
})

Deno.test("impossible energy, mass and fatty acid totals are rejected", () => {
  for (const replacement of [
    nutrient(1008, "Energy", 1, "KCAL"),
    nutrient(1005, "Carbohydrate, by difference", 140),
    nutrient(1293, "Fatty acids, total polyunsaturated", 40),
  ]) {
    const food = cerealFood()
    food.foodNutrients = food.foodNutrients!.map((n) => n.nutrientId === replacement.nutrientId ? replacement : n)
    equal(mapFood(food, "cereal bar"), null)
  }
})

Deno.test("lookup refuses generic substitutes across all fallback queries", async () => {
  const queries: string[] = []
  const fakeFetch: typeof fetch = async (_input, init) => {
    queries.push(JSON.parse(init!.body as string).query)
    return Response.json({ foods: [cerealFood()] })
  }
  equal(await lookupName("Kelloggs cereal", "TEST_KEY_NOT_REAL", fakeFetch), null)
  equal(queries, ["Kelloggs cereal", "kelloggs cereal"])
})

Deno.test("lookup keeps the requested identity on a valid complete match", async () => {
  const fakeFetch: typeof fetch = async () => Response.json({ foods: [cerealFood()] })
  const result = await lookupName("Kelloggs Nutri Grain cereal bars", "TEST_KEY_NOT_REAL", fakeFetch)
  equal(result?.name, "Kelloggs Nutri Grain cereal bars")
  equal(result?.fat_per_100g, 9.5)
  equal(result?.sodium_per_100g, 500)
  equal(result?.citation_url, "https://fdc.nal.usda.gov/fdc-app.html#/food-details/168862/nutrients")
})

Deno.test("unrequested compositions and competing brands cannot win by source score", async () => {
  for (const [query, description] of [
    ["rice cooked", "Rice cooked with squid"],
    ["arroz cozido", "Rice cooked with squid"],
    ["rice cooked", "Rice cooked squid"],
    ["Nutella", "Nutella sandwich"],
    ["Coke", "Minute Maid Coke fruit juice"],
    ["Coke", "Pepsi Coke cola soft drink"],
    ["egg", "Egg meat"],
  ]) {
    const wrong = { ...cerealFood(), description, dataType: "Foundation" }
    equal(hasMeaningfulMatch(wrong, query), false)
    const queries: string[] = []
    const fakeFetch: typeof fetch = async (_input, init) => {
      queries.push(JSON.parse(init!.body as string).query)
      return Response.json({ foods: [wrong] })
    }
    equal(await lookupName(query, "TEST_KEY_NOT_REAL", fakeFetch), null)
    equal(queries, candidateQueries(query))
  }
})

Deno.test("ordinary food descriptors remain valid without relaxing explicit identity", () => {
  equal(hasMeaningfulMatch({ description: "Rice white long grain enriched cooked" }, "rice cooked"), true)
  equal(hasMeaningfulMatch({ description: "Nutella chocolate hazelnut spread Ferrero" }, "Nutella"), true)
  equal(hasMeaningfulMatch({ description: "Coke cola soft drink carbonated" }, "Coke"), true)
  equal(hasMeaningfulMatch({ description: "Rice white brown cooked" }, "rice white cooked"), false)
  equal(hasMeaningfulMatch({ description: "Milk whole nonfat fluid" }, "milk whole"), false)
  equal(hasMeaningfulMatch({ description: "Chicken raw cooked grilled" }, "chicken grilled"), false)
  equal(hasMeaningfulMatch({ description: "Chicken raw cooked" }, "chicken raw"), false)
  equal(hasMeaningfulMatch({ description: "Rice cooked with squid" }, "rice cooked with squid"), true)
})

Deno.test("USDA cooking, salt and milkfat fortification qualifiers preserve the food identity", () => {
  equal(hasMeaningfulMatch({ description: "Egg, whole, cooked, hard-boiled" }, "egg"), true)
  equal(hasMeaningfulMatch({ description: "Milk, whole, 3.25% milkfat, with added vitamin D" }, "milk whole"), true)
  equal(hasMeaningfulMatch({ description: "Rice, white, long-grain, regular, enriched, cooked without salt" }, "rice cooked"), true)
  equal(hasMeaningfulMatch({ description: "Rice white cooked without added salt and squid" }, "rice cooked"), false)
  equal(hasMeaningfulMatch({ description: "Milk whole 3.25% milkfat with added vitamin D and Nutella" }, "milk whole"), false)
  equal(hasMeaningfulMatch({ description: "Milk whole 15% milkfat with added vitamin D" }, "milk whole"), false)
  equal(hasMeaningfulMatch({ description: "Rice white cooked with added salt" }, "rice cooked"), false)
  equal(hasMeaningfulMatch({ description: "Egg whole raw hard-boiled" }, "egg raw"), false)
})
