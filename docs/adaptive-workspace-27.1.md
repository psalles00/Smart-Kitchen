# Adaptive workspace — SDK 27.1

Updated 2026-10-25. Xcode 27.1 (27A9275), iOS/Simulator SDK 27.1, macOS SDK 27.0; deployment remains iOS 17/macOS 26. SDKROOT is automatic. This document supersedes the earlier two-page/two-header design.

## Presentation contract

Wide iOS uses **one page title, description and action row**, spanning one rounded surface with two functional regions and a middle divider. macOS retains the original sidebar and single content column. Narrow windows and accessibility layouts keep the complete compact flow; no device-model or forced size-class assumptions.

- Home: original shortcut/status content on the left, original assistant option deck on the right. The deck uses `optionsOnly` in its embedded presentation and cannot mount another chat consumer.
- Lists: complete original Despensa and Mercado content, pickers, rows, selection and sheets. Selecting a list already shown on the other side swaps their positions. Shared page actions operate on the primary selection; the other list remains reachable through the same picker.
- Recipes: original gallery and notebook management. Selecting a recipe animates the gallery toward the left and presents its original detail on the right. Closing returns to notebooks; shared selection also projects into compact navigation when folded. Notebook refresh/invalidation includes visible wide layouts and foreground updates.
- Assistant: original options on the left and one chat/results subtree on the right. `AnyLayout` retains that subtree when changing between wide, stacked and compact placement, preserving conversation state instead of creating conditional copies. Inactive pushed pages do not mount a second consumer.
- Nutrition: original overview and selected-day meals share the page and callbacks.

A single shader field remains behind the complete page. Region content reuses the existing ModelContext. Inactive retained tabs do not mount companions. There is no additional container, renderer, remote service, polling or automatic AI request.

## Native system chrome and camera

On iOS 27.1, documented `toolbarVerticalBehavior(.disabled)` keeps horizontal navigation. `statusBarHidden` follows the containing window's public `verticalBarEdge` preference, observed through `systemTraitsAffectingVerticalBarEdge`. The narrow UIKit reader deduplicates events; it does not poll or manipulate global application/window settings. Older iOS and macOS do not adopt this policy.

The closed-Duo header enters the top camera band, with controls avoiding actual native occlusion geometry. The root supplies occlusion extent directly; the header never measures its own height back into state. Only this chrome treatment enters the top unsafe region; foreground content still respects camera/division geometry. The wider page uses native ArrangementView/SplitArrangementViewStyle; the assistant's stable AnyLayout reads native division orientation. Backgrounds extend behind both regions. The main light/dark surface extends to the app’s bottom edge behind navigation; only its background/border ignore the bottom safe area. Foreground clipping and scroll clearance remain intact. No wide-panel bottom padding may detach that surface from the safe-area boundary.

Wide assistant input and navigation share one bottom row. The native tab bar is hidden at each tab root to prevent a duplicate bar; the custom SwiftUI buttons use the existing selection/routes. Compact layouts retain native tabs. The keyboard uses normal safe-area handling; physical Mac keyboard capture is never enabled.

Onboarding progress has a bounded width on wide windows and shares the native camera row when closed. Recipe interests show 3 columns at closed-Duo width, 5 at wide width, and fewer in narrow/accessibility contexts. Cards have bounded covers and intrinsic text rather than scaling to oversized aspect ratios. Overview/Coach use the parent's proposed height, scrollable content and a fixed bottom Continue action; projection also scrolls above its fixed action, keeping the hero and chart accessible.

## Apple sources checked 2026-10-25

- [Prepare your app for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111461/)
- [Strike a pose with adaptive layouts](https://developer.apple.com/videos/play/tech-talks/111463/)
- [Raise the bar with iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111462/)
- [Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo)
- [statusBarHidden](https://developer.apple.com/documentation/swiftui/view/statusbarhidden(_:)) and installed public UIKit/SwiftUI interfaces.
- Xcode's bundled App Resizability safe-area guide. Public documented APIs do not constitute a guarantee of App Review acceptance.

## Data, calls and validation boundaries

No schema, store URL/layout, bootstrap, sync flag, Team, App Group or capability changes. Bundle remains `com.pedrosalles.smartkitchen.sync`, Team `44K57HQAP9`; ordered iCloud containers remain `iCloud.com.pedrosalles.smartkitchen.syn`, then `iCloud.com.pedrosalles.smartkitchen.sync`, with CloudKit/CloudDocuments intact.

Incremental budget before/after: **0 new remote requests/bytes per navigation action, 0 idle polling, 0 paid AI calls, 0 new services**. Existing local caches and explicit saves are reused. Native fixture readback confirms 6 items, 1 recipe and 0 chat messages remain unchanged. These are isolated in-memory tests, not proof of CloudKit delivery or foldable hardware performance. Existing services' aggregate background traffic and shared quota headroom are not claimed measured.

The complete installed Mac snapshot before/after is byte-identical: SHA-256 `18aceb3680763cd7f239bf4e3d89986e3e42fb281468b1612323e5bf200f431d`, preserving IDs, photos, flags, grouping and revision.

Evidence root: `/Volumes/PS-Externo/Coding/Builds/Savoria-Duo-20261025/system-chrome`.

| Destination | Evidence | Result |
| --- | --- | --- |
| iPhone 17 Pro | `unified-iphone17-verified`, `full-surface-iphone17` | 15 core tests and 4 final native tests passed, including compact layout, selection/navigation, original bulk operations and bottom-edge pixels |
| Duo open | `full-surface-duo-expanded` | 4 native tests passed; one header, aligned content regions and no overlapping duplicate native navigation |
| Duo closed | `full-surface-duo-closed` | 4 native tests passed in the actual 466×678 outer scene; camera clearance and 3 recipe columns |
| iPad | `full-surface-ipad` | 4 native tests passed with the original feature content |
| macOS | `full-surface-mac` and installed app | Build succeeded, full signed entitlements preserved, real single-column interface and identical data readback |

Core implementation: `93277455`; preceding native chrome policy: `37d44d16`. Independent review approved exact core patch SHA-256 `45667840477d17f06f1718135db07843eb87a585ba18ececb756c67f3bdecc51`. The bounded Overview/Coach follow-up is `505e3ed3`; the final bottom-surface/readiness change is `6d65294e`, independently approved against patch SHA-256 `d9448916a844850afd48220aa03b20d0d8c7fc8c3c08297a7e6ac952887b6b73`. Goal snapshots wait for the existing entrance-completion preference, so they show the final hero instead of a blank animation frame. Final surface checks sample actual bottom pixels in the native host; the final wide/compact results and live E2E evidence are recorded alongside the results above; see `unified-e2e.md` in the evidence root.

Live E2E on the installed Duo exercised Home → Lists → Recipes → existing detail → close → Assistant → empty chat → background/resume, without sending an AI query or changing records. It checked Open/Closed × Light/Dark after the final surface correction, preserving the native camera and header. macOS navigation retained one content column. Overview and Coach were observed through the safe debug preview; recipe-grid density and completed Goal Projection are explicitly native-fixture visual evidence, not a completed persisted onboarding journey. The E2E report records this boundary.

## Debugging trace

Preset used: `preset-twin-execution-debugging`.

1. Passing execution: native placed bounds and actual Duo screenshot were centered.
2. Failing execution: the first geometry probe reported a full-width primary header as if it were one half.
3. Checkpoints: native scene, status preference, reserved regions, intermediate layout proposals, final placed anchors and rendered pixels.
4. Trace comparison: intermediate widths included 128, 951, 459.5 and 935; final half-width placement was 459.5.
5. First meaningful divergence: the probe retained a transient ArrangementView proposal instead of final placement.
6. Root cause: asynchronous self-measurement was used as an assertion/layout input.
7. Smallest fix: resolve Anchor preferences in the test root; compute Home deck height in Layout; derive camera/hero geometry from the parent proposal without self-feedback.
8. Verification: final native tests and real UI checks are distinguished from earlier failed/stale harness attempts. Temporary DEBUG_TRACE logging was removed.

Retain the current reports, final results and images until superseded. Compact superseded raw attempts to summaries and delete only owned temporary artifacts, never user data or recovery material. Reuse build caches and stop additional test simulators when no longer needed; leave the requested Duo validation screen open.

## Manual smoke test

1. Fold/unfold Duo: check header/camera clearance, one title, rounded surface, continuous shader and input/navigation alignment.
2. In Lists, swap Despensa/Mercado and select Para depois; open an item and cancel without changing data.
3. In Recipes, open an existing recipe, close it to return to notebooks, then fold/unfold and verify selection/navigation.
4. In Assistant, open an empty chat without sending, fold/unfold, background/resume and verify options/chat placement.
5. In onboarding preview, check progress, 3/5 recipe columns, full projection hero and reachable Continue; close the preview. Confirm the installed Mac retains its original single-column interface.
