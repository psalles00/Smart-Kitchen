# StoreKit local decimal truncation — Apple-only reproduction

Observed 29 October 2026: Xcode 27.1 (25183.120.5), iOS Simulator 27.0
(24A5380i), iPhone 17 Pro, macOS 27.2 (26B5086k). Host locale pt_BR.

Expected: `Product.price` returns Decimal 99.90 / 49.90 (BRL).
Actual: 99 / 49; `displayPrice` is R$ 99,90 / R$ 49,90; raw offer data
contains `priceString: "99,9"` / `"49,9"`. Both StoreKit 1 and 2 returned
truncated numbers in the application test. The Apple-only reproduction below
also fails, without importing Savoria, SwiftData or any application service.

## Reproduce

Requirements: Xcode selected with xcode-select, an already booted iOS Simulator,
Python 3. No accounts, server, purchases, payments or network required.

```
python3 docs/reproductions/storekit-decimal/reproduce.py \
  --device A3D7F658-1D04-4369-9B96-B3D20591DF0D \
  --output /Volumes/PS-Externo/Coding/Builds/StoreKitDecimalRepro
```

Use a new output path; the script refuses to overwrite it. It compiles a tiny
UIKit host and XCTest bundle, signs ad hoc, and runs one local test. It does
not erase/uninstall simulators, modify global region, clean transactions,
restore/purchase subscriptions or access the Savoria store. Test catalogue IDs
are `com.example.storekitdecimal.annual` and `.monthly`. A failing exit status
is the expected reproduction of the defect, **not a passing product test**.

The catalogue is derived from Apple's local configuration format; prices stay
strings with a decimal point. Do not replace them with comma-formatted strings.
Do not change the expected numeric amounts to integer values to hide the error.

## Recorded evidence

Under `/Volumes/PS-Externo/Coding/Builds/Savoria-Nutrition-Final-20261028/`:

- `decimal-api-boundary-fixed.xcresult`: StoreKit 1 vs 2 and raw JSON;
  both 99/49, while formatted prices retain cents.
- `decimal-process-enUS.xcresult`: process language/region override did not fix it;
  storefront BRA and session locale pt_BR maintained.
- `decimal-apple-only-scene.xcresult`: the independent UIKit/XCTest reproduction
  fails the same decimal assertions, 1 test / 2 assertion failures.
- `decimal-apple-only-portable-final.xcresult`: portable reproducer verified with automatic verbose diagnostics disabled; log `decimal-apple-only-portable-final.log`. The earlier portable run completed its assertions but its Xcode diagnostics collector stalled and was stopped.
- `decimal-runtime-27-1.log`: different runtime comparison could not execute
  (BackBoard startup and invalidDigitCount diagnostics). Not a passing comparison.

The first temporary SKProductsRequest delegate used an incorrect main-actor
callback assumption and crashed. The fixed diagnostic forwards the callback
explicitly; only the fixed run is used for the numeric conclusion. The first
minimal UIKit host required modern scene lifecycle; only the scene-enabled
and portable runs above are evidence of the StoreKit issue.

## Scope and alternatives

This proves a defect outside Savoria on the **local configuration** path for
this toolchain/runtime combination. It does not prove which private Apple
component serializes the comma, whether every OS release has the defect, or
that every Sandbox/production response is affected.

The production app has no `Product.price` arithmetic/conversion. Its paywall
uses Apple's `displayPrice`, and a real Apple Sandbox annual purchase was
confirmed at R$ 99,90, followed by successful restoration. No production price
workaround is justified by the local test. Region override, session lifetime,
explicit storefront, independent product IDs and both APIs were evaluated.
The installed alternative Xcode is older (27.0); no newer local toolchain is
available, and the available 27.1 runtime did not execute the comparison.

Retain numeric assertions as a regression detector. Re-run this reproducer on
an updated Apple toolchain/runtime; do not skip/expect-fail the assertion by
routine. Pedro explicitly declined submission to Apple. This is retained local
diagnostic evidence, **not submitted**, with no Apple case ID. Original draft title: “StoreKit Testing emits locale-comma
priceString and truncates fractional Product.price in both StoreKit APIs”.
Attach this directory and the independent xcresult. No user data is needed.
