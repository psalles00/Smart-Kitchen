# Adaptive workspace — SDK 27.1

The app builds with Xcode 27.1 (27A9275), iOS/iPhoneSimulator SDK 27.1 and macOS SDK 27.0. Deployment remains iOS 17/macOS 26; new APIs are availability guarded. Existing device families include iPhone and iPad. SDKROOT remains automatic instead of pinning an SDK path/version.

## Layout contract

- Home and assistant: pantry reference alongside the current activity.
- Lists: compare the primary list with a different pantry/reserve/grocery list, reusing the existing item operations.
- Recipes: library and selected recipe side by side. One shared selection projects into compact stack navigation when closing the device/window; clearing the selection cannot resurrect an old recipe.
- Nutrition: summary/calendar/macros alongside meals for the same selected day. Entry callbacks and already fetched data are shared.
- Each panel has its own rounded light/dark surface. One shared shader field extends behind both; controls remain inside asymmetric safe areas.
- SDK 27.1 uses native `ArrangementView` with split arrangements on both axes. The active division controls displacement. No device-model, main-screen, orientation, or hinge-angle assumptions.
- In narrow windows/accessibility text sizes, all functionality remains reachable through the primary flow. A horizontal reserved division also permits vertically stacked panels where two horizontal columns would not fit.
- The single assistant field measures local reserved division geometry; it does not stretch through a vertical fold or duplicate focus state.
- macOS uses equivalent two-column behavior when there is room, with a compact home shortcut deck.

## Apple sources checked 2026-10-25

- [Prepare your app for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111461/): SDK opt-in, resizing, asymmetric safe areas and native navigation.
- [Strike a pose with adaptive layouts](https://developer.apple.com/videos/play/tech-talks/111463/): arrangements, both split axes and reserved regions.
- [Raise the bar with iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111462/): native vertical tab/navigation bars.
- [Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo).
- Installed 27.1 SwiftUI/SwiftUICore public interfaces and Xcode App Resizability safe-area guide were checked against the actual API signatures.

## Data and resource boundaries

No production schema, container layout/URL, bootstrap, sync flag, signing Team or capability changes. The ordered iCloud containers and App Group remain unchanged. Rendering fixtures exist only in the test target, with an in-memory container and CloudKit disabled; onboarding fixtures never enter user stores.

Budget before implementation: zero new remote requests/bytes per navigation action, zero idle polling, zero new services/fixed charges, and zero paid AI requests. The companions use local data: at most one visible pantry/list reference, or existing recipe/nutrition data. Retained inactive tabs do not mount companion observers. Existing explicit edits use their existing save/sync path; there is no extra background write or AI retry path. This is a UI-only change, so no provider price/plan is changed. Local GPU work reuses one field rather than rendering a second shader. Remote quota headroom and device performance are not claimed measured by layout tests.

Readback after the first macOS installation exactly matched the full pre-change backend snapshot (items, categories, recipes, counts, grouping, flags and revision).

## Validation

`AdaptiveWorkspaceLayoutTests`: compact, wide and accessibility policies.
`RecipeWorkspaceNavigationTests`: selection clearing, folding/unfolding, back navigation.
`AdaptiveWorkspaceRenderingTests`: actual native window-scene rendering of all five pages with isolated data, reserved-region/frame assertions and image attachments. It waits for native display commits, not wall-clock sleeps. Fixture readback checks item/recipe counts and zero chat messages.

Evidence is retained outside the repository in `/Volumes/PS-Externo/Coding/Builds/Savoria-Duo-20261025`. Native rendering uses the installed app's views in the actual simulator scene, with test-only data; it is not a claim of CloudKit delivery or real foldable hardware validation.

Final validation matrix (2026-10-25):

| Destination | Evidence | Result |
| --- | --- | --- |
| Duo open, horizontal | `duo-horizontal-final` | 2 native tests passed; both panels and actual input/tab bar frames |
| Duo partially open | `duo-partial` | 2 native tests passed; vertical division excluded |
| Duo portrait partially open | `duo-portrait-partial` | 2 native tests passed; horizontal division excluded |
| Duo closed | `duo-closed` | 2 native tests passed; complete compact flow |
| Duo portrait, dark | `duo-dark-bar-final` | 2 native tests passed; input does not overlap bottom navigation |
| iPad portrait | `ipad-portrait` | 2 native tests passed; independent panels |
| iPad horizontal | `ipad-horizontal-verified` | 2 native tests passed; native top tabs and input |
| iPhone 17 Pro | `iphone17-final`, `iphone17-bar-final` | 8 layout/navigation/rendering tests, then 2 native tests after final clearance correction |
| macOS installed app | independent CUA journey + backend readback | Lists comparison, recipe/detail, clearing selection via notebooks, same-day nutrition and assistant/pantry verified |

The rendering test checks the actual visible `UITextField` against every visible `UITabBar`. iPad's top tab switcher uses a different native representation, so the test does not incorrectly require a bottom/side `UITabBar` there.

Both code review and E2E validation were performed in separate delegated contexts. Final app source is commit `406669ec`; `9b7b8f63` adjusts only the iPad test expectation. No outstanding code defects were reported.

Final iOS Debug SDK 27.1, physical iOS Release SDK 27.1 and macOS builds passed. The current app was installed and launched on the iPhone 17 Pro, Duo and iPad simulators, preserving existing containers. macOS was installed/opened at `/Applications/Savoria.app`, with the complete original signed entitlement dictionary preserved. Simulator entitlement checks use Xcode's `Savoria.app-Simulated.xcent` linked into the executable; an empty ad-hoc code-signing dictionary is not evidence that Simulator capabilities were removed.

Physical iPhone 12 Pro installation initially reported CoreDevice 4016 (unavailable connectivity/services). After the device became available, installation succeeded for `com.pedrosalles.smartkitchen.sync`, database sequence 16776. Bundle, signing Team and ordered iCloud containers were checked before installation. The physical app was not opened or operated for routine tests; no uninstall was performed. This layout change was validated in Simulator; real foldable hardware, live fold/keyboard transitions, CloudKit delivery and migration remain unverified. No persistence migration is introduced.

Final backend snapshot is byte-for-byte identical to the baseline, SHA-256 `18aceb3680763cd7f239bf4e3d89986e3e42fb281468b1612323e5bf200f431d`. New remote operations remain zero by construction of the changed paths; no paid AI query was submitted. This does not claim measured total background network consumption of existing services.

Superseded raw test bundles are replaced by compact report summaries; final frame/image evidence and the latest three raw results are retained for review. Build caches were reused. Only temporary simulators booted for this task are stopped after validation; their data remains intact.

## Manual smoke test

1. Open Home/Listas/Nutrição on Duo open; check aligned rounded panels, shader on both sides and accessible controls beside the system status region.
2. Compare Despensa/Para depois/Mercado without selecting the same list twice. Do not alter real items merely to test layout.
3. Open a recipe, close/reopen the Duo, then return to the library; the current recipe should persist, and a dismissed recipe should remain dismissed.
4. Check assistant input and virtual keyboard in both poses, without submitting a paid query for a layout check.
5. Repeat with an iPad window made narrow/wide, large accessibility text, light/dark appearance, and the iPhone 17 Pro fallback.
