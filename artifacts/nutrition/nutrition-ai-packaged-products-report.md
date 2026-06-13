# Nutrition AI Packaged Products Report

*   Reference source: Open Food Facts product labels by barcode.
*   Deterministic cases: 7.
*   Reliability score: 100.0%.
*   Test run: `xcodebuild test -project SmartKitchen.xcodeproj -scheme Savoria -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.
*   Note: Open Food Facts exposes sodium per 100 g in grams; the test converts sodium to mg before feeding the app pipeline.

## Results

| Market | Product | Barcode | Expected kcal/P/C/F | Actual kcal/P/C/F | Serving | Status |
| --- | --- | --- | --- | --- | --- | --- |
| United States | Coca-Cola Original Taste | 5449000000996 | 139/0/35/0 | 139/0/35/0 | 330.0g/ml | PASS |
| United States | Kellogg's Corn Flakes Cereal | 038000001277 | 100/2/24/0 | 100/2/24/0 | 28.0g/ml | PASS |
| United States | Jif Creamy Peanut Butter | 051500255162 | 190/7/8/16 | 190/7/8/16 | 33.0g/ml | PASS |
| United States | Lay's Classic | 028400310413 | 160/2/15/10 | 160/2/15/10 | 28.0g/ml | PASS |
| Brazil | Nestle Moca Leite Condensado Integral Moca | 7891000100103 | 65/1/11/2 | 65/1/11/2 | 20.0g/ml | PASS |
| Brazil | Nestle Nescau 2.0 | 7891000053508 | 73/1/17/0 | 73/1/17/0 | 20.0g/ml | PASS |
| Brazil | Soda Antarctica Refrigerante Soda Limonada Antartica | 7891991000833 | 72/0/18/0 | 72/0/18/0 | 350.0g/ml | PASS |

## References

| Product | URL |
| --- | --- |
| Coca-Cola Original Taste | https://world.openfoodfacts.org/product/5449000000996 |
| Kellogg's Corn Flakes Cereal | https://world.openfoodfacts.org/product/038000001277 |
| Jif Creamy Peanut Butter | https://world.openfoodfacts.org/product/051500255162 |
| Lay's Classic | https://world.openfoodfacts.org/product/028400310413 |
| Nestle Moca Leite Condensado Integral Moca | https://world.openfoodfacts.org/product/7891000100103 |
| Nestle Nescau 2.0 | https://world.openfoodfacts.org/product/7891000053508 |
| Soda Antarctica Refrigerante Soda Limonada Antartica | https://world.openfoodfacts.org/product/7891991000833 |

## Confidence

The packaged-product pipeline scored 100.0% for the locked barcode fixtures. This validates that branded label values can flow through the same parser, lookup, portion conversion, rounding and aggregation path used by text, voice transcripts, camera/gallery equivalents and nutrition labels. Live barcode/image recognition is still separate from this deterministic test and depends on image quality and provider availability.