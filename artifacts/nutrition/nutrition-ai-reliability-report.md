# Nutrition AI Reliability Report

*   Reference source: USDA FoodData Central.
*   Deterministic cases: 11.
*   Reliability score: 100.0%.
*   Accuracy rule: exact rounded kcal/protein/carbs/fat and +/-0.1g or mg for tracked micros.
*   Test run: `xcodebuild test -project SmartKitchen.xcodeproj -scheme Savoria -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.

## Results

| Case | Cuisine | Channel | Expected kcal/P/C/F | Actual kcal/P/C/F | Grams | Status |
| --- | --- | --- | --- | --- | --- | --- |
| Single banana | Whole food | Text | 116/1/27/0 | 116/1/27/0 | 120.0 | PASS |
| Two boiled eggs | Breakfast | Voice transcript | 155/13/1/11 | 155/13/1/11 | 100.0 | PASS |
| Rice and black beans | Brazilian | Text | 327/13/66/1 | 327/13/66/1 | 250.0 | PASS |
| Rice, beans, roasted chicken | Brazilian | Text | 563/49/66/10 | 563/49/66/10 | 370.0 | PASS |
| Salmon and rice | Japanese-style | Gallery/photo equivalent | 361/29/45/6 | 361/29/45/6 | 260.0 | PASS |
| Lentils and rice | Indian-style | Text | 365/19/70/1 | 365/19/70/1 | 300.0 | PASS |
| Corn tortilla tacos | Mexican | Camera/photo equivalent | 552/46/69/11 | 552/46/69/11 | 310.0 | PASS |
| Tofu, lentils, rice | Vegetarian | Text | 520/42/63/14 | 520/42/63/14 | 400.0 | PASS |
| Chicken and rice | Fitness | Text | 615/59/56/15 | 615/59/56/15 | 380.0 | PASS |
| Tofu and corn tortilla | Vegetarian Mexican-style | Text | 304/24/30/12 | 304/24/30/12 | 180.0 | PASS |
| Eggs and banana | Breakfast | Voice transcript | 271/13/28/11 | 271/13/28/11 | 220.0 | PASS |

## USDA References

| Food | FDC ID | Data type | kcal | Protein | Carbs | Fat | URL |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Banana, raw | 2709224 | Survey (FNDDS) | 97 | 0.74 | 22.71 | 0.28 | https://fdc.nal.usda.gov/fdc-app.html#/food-details/2709224/nutrients |
| Egg, whole, cooked, hard-boiled | 173424 | SR Legacy | 155 | 12.6 | 1.12 | 10.6 | https://fdc.nal.usda.gov/fdc-app.html#/food-details/173424/nutrients |
| Rice, white, long-grain, regular, enriched, cooked | 168878 | SR Legacy | 130 | 2.69 | 28.2 | 0.28 | https://fdc.nal.usda.gov/fdc-app.html#/food-details/168878/nutrients |
| Beans, black, mature seeds, cooked, boiled, without salt | 173735 | SR Legacy | 132 | 8.86 | 23.7 | 0.54 | https://fdc.nal.usda.gov/fdc-app.html#/food-details/173735/nutrients |
| Chicken, broilers or fryers, breast, meat and skin, cooked, roasted | 171075 | SR Legacy | 197 | 29.8 | 0 | 7.78 | https://fdc.nal.usda.gov/fdc-app.html#/food-details/171075/nutrients |
| Fish, salmon, pink, cooked, dry heat | 172001 | SR Legacy | 153 | 24.6 | 0 | 5.28 | https://fdc.nal.usda.gov/fdc-app.html#/food-details/172001/nutrients |
| Tofu, raw, firm, prepared with calcium sulfate | 172475 | SR Legacy | 144 | 17.3 | 2.78 | 8.72 | https://fdc.nal.usda.gov/fdc-app.html#/food-details/172475/nutrients |
| Lentils, mature seeds, cooked, boiled, without salt | 172421 | SR Legacy | 116 | 9.02 | 20.1 | 0.38 | https://fdc.nal.usda.gov/fdc-app.html#/food-details/172421/nutrients |
| Tortilla, corn | 2707823 | Survey (FNDDS) | 218 | 5.7 | 44.64 | 2.85 | https://fdc.nal.usda.gov/fdc-app.html#/food-details/2707823/nutrients |

## Confidence

The deterministic core pipeline scored 100.0% against the locked USDA fixture. This measures route coverage, JSON parsing resilience, per-100g lookup alignment, portion conversion, rounding and aggregation. Live model identification and real camera/microphone permissions still need manual validation because those depend on device permissions, image quality, speech recognition and provider availability.