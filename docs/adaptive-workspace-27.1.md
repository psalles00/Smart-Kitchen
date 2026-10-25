# Adaptive workspace — SDK 27.1

Validated with Xcode 27.1 (27A9275), iOS/iPhoneSimulator SDK 27.1 and macOS SDK 27.0 on 2026-10-25. Deployment remains iOS 17/macOS 26; new APIs are availability guarded. SDKROOT remains automatic; existing device families include iPhone and iPad.

## Layout contract

Adaptive secondary regions are exclusive to iOS. **macOS retains its original single content column and original home shortcut layout**; it never mounts the new companions. The generic parity rule does not expand this request to add Mac columns.

The second region adapts the original feature instead of recreating a simplified panel:

- Lists starts with Despensa on one side and Mercado on the other. Both regions instantiate the complete original `ListsTabView`, including its header, tabs, search, filters, add/edit sheets, checkboxes, selection, swipe and bulk actions. A small paired selection value swaps the two sides when needed and reconciles hidden optional tabs. It changes presentation state, not stored items.
- Home and assistant display that same complete original Lists page alongside the current activity, initially on Despensa.
- Recipes uses the original library and `RecipeDetailView`. One selection projects into compact stack navigation on folding; clearing it cannot resurrect a dismissed recipe.
- Nutrition uses the existing dashboard sections, shared selected day, fetched data and entry callbacks.

Each region owns its original rounded light/dark surface and header. A single shader field extends behind both. Secondary pages inherit the same ModelContext, mark themselves as already assigned to a region, and do not recursively create another workspace or consume the root search context. Inactive retained tabs do not mount companions. Bulk selection in either list hides the persistent assistant field.

SDK 27.1 uses native `ArrangementView`, split arrangements on both axes and reserved division/occlusion geometry. No device-model, main-screen, orientation or hinge-angle assumptions. Foreground controls respect asymmetric safe areas; only backgrounds extend beneath them. Compact/accessibility layouts keep the primary flow. A horizontal reserved division permits stacked panels. The single assistant field measures its local division and avoids the native tab bar.

## Apple sources checked 2026-10-25

- [Prepare your app for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111461/)
- [Strike a pose with adaptive layouts](https://developer.apple.com/videos/play/tech-talks/111463/)
- [Raise the bar with iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111462/)
- [Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo)
- Installed public SwiftUI/SwiftUICore interfaces and Xcode App Resizability safe-area guide, checked against the actual API signatures.

## Data and resource boundaries

No production schema, container layout/URL, bootstrap, sync flag, signing Team or capability changes. Team remains `44K57HQAP9`, bundle `com.pedrosalles.smartkitchen.sync`. The ordered iCloud containers, CloudKit/CloudDocuments and App Group remain unchanged. Simulator capability checks use Xcode’s linked `Savoria.app-Simulated.xcent`; the ad-hoc signature’s empty dictionary is normal.

Before/after budget for the new UI paths: zero new remote requests/bytes per navigation action, zero idle polling, zero paid AI calls or new services. Each visible secondary list reuses existing local queries and explicit save/sync operations; it creates no additional container or background mutation. There is one shared shader, not a second GPU renderer. Existing services’ aggregate background traffic, quota headroom and real-device performance are not claimed measured by layout tests.

The full Mac backend snapshot after the corrected installation exactly matches the baseline: SHA-256 `18aceb3680763cd7f239bf4e3d89986e3e42fb281468b1612323e5bf200f431d`. All IDs, records, grouping, flags and revision are preserved.

## Validation of the corrected implementation

Evidence root: `/Volumes/PS-Externo/Coding/Builds/Savoria-Duo-20261025`.

| Destination | Current evidence | Result |
| --- | --- | --- |
| iPhone 17 Pro | `correction-iphone17` | 13 tests passed: compact/accessibility policy, recipe navigation, paired-list selection, original bulk operations and native rendering |
| Duo open | `correction-duo-open-verified` | 2 native tests passed; actual scene 951×669, secondary visible, panels 417.5 points wide, right reserved area 84 points respected |
| Duo partially open | `correction-duo-partial` | 2 native tests passed; original pages respect the active division |
| iPad portrait | `correction-ipad` | 2 native tests passed; actual scene 834×1210, both original list pages visible |
| macOS | corrected build and installed app | Original single content column; complete original signed entitlements preserved |
| iPhone 12 Pro | `correction-install-physical.log` | Release installed successfully, database sequence 16808; no routine physical app interaction |

Native rendering hosts the actual production views in the simulator’s real window scene, with an isolated in-memory test-only ModelContainer and CloudKit disabled. It captures all five pages, checks panel frames against reserved regions, and verifies fixture readback. No synthetic onboarding or food records enter user stores. These tests prove native layout with fixtures; they do not prove CloudKit delivery, real foldable hardware, or every live fold/keyboard transition.

The earlier runs named `correction-duo` and `correction-duo-open` actually rendered the Duo closed (466×678); they are compact evidence only. The final run explicitly verifies `expanded:true`. A Device Hub slider initially changed its displayed angle without applying the pose; selecting another simulator and returning exposed the working native Open/Partially Open/Closed controls.

The corrected source was independently approved against patch SHA-256 `d3a154ce841c1a71650510433764187b2901f07750f37c1e6bc5fcac2cf10b0a` after the actual open-pose evidence was available. Implementation commits are `3c0c2c0d` (Mac scope) and `fa2c7621` (complete original list pages).

Fresh independent E2E validation of the installed Mac app navigated Home → Lists → Recipes → Nutrition, confirmed a single primary content column, and read back the identical full data snapshot. The report is `correction-e2e.md`; iOS fixture-based validation is explicitly distinguished from a persisted-live user-store journey.

Both iOS configurations and macOS build successfully. The updated app is installed/opened on the iPhone 17 Pro, Duo and iPad simulators, preserving their containers. macOS is installed/opened at `/Applications/Savoria.app`. The physical installation preserves the existing app data and was not opened for routine testing.

Retain compact reports and the current final images/results until superseded by the next validated release; discard duplicate raw attempts, never user data or recovery material. Reuse build caches and stop only the additional simulators started for this task after validation.

## Manual smoke test

1. On Duo/iPad, open Listas: check Despensa and Mercado side by side, with the same original tabs, header buttons, item rows and rounded surfaces.
2. Choose Mercado on the first side; the other should become Despensa. Choose Para depois on either side and check independent search/filter state. Open an item and cancel without changing real data.
3. Open a recipe, fold/unfold, then return to the library; the current selection should persist and a dismissed recipe should remain dismissed.
4. Check shader continuity, status-region clearance, assistant input and virtual keyboard in open/partial/closed poses; no paid query is needed.
5. Open Home, Lists, Recipes and Nutrition on the installed Mac app: each should retain its original single content column. Repeat compact/accessibility layouts on the iPhone 17 Pro.
