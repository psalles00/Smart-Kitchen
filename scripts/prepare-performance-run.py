#!/usr/bin/env python3
"""Copy Savoria's UI test runner without measurement-time diagnostic injection.

The original runner and app remain unchanged. Keep the copy beside the original
so Xcode's __TESTROOT__ references continue to resolve to the same built app.
"""
import argparse
import os
from pathlib import Path
import plistlib


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--use-installed", action="store_true",
                        help="Physical iOS only: use installed app/runner; verify their versions first.")
    args = parser.parse_args()
    source = args.source.resolve(strict=True)
    destination = args.destination.resolve()
    if source.parent != destination.parent or source == destination:
        parser.error("Use a new destination beside the original .xctestrun file.")
    with source.open("rb") as stream:
        configuration = plistlib.load(stream)
    target = configuration.get("SavoriaPerformanceUITests")
    if not isinstance(target, dict) or target.get("BlueprintName") != "SavoriaPerformanceUITests":
        parser.error("Expected the SavoriaPerformance UI runner; no output was written.")
    target["UITargetAppPerformanceAntipatternCheckerEnabled"] = False
    target["SystemAttachmentLifetime"] = "keepNever"
    target["PreferredScreenCaptureFormat"] = "screenshots"
    if args.use_installed:
        if "-iphoneos/" not in target.get("TestHostPath", ""):
            parser.error("UseDestinationArtifacts requires a physical iOS device; use the normal copy for Simulator.")
        if target.get("TestHostBundleIdentifier") != "com.pedrosalles.smartkitchen.sync.performancetests.xctrunner":
            parser.error("Unexpected runner bundle identifier; no output was written.")
        bundle = target.get("TestBundlePath", "")
        if bundle != "__TESTHOST__/PlugIns/SavoriaPerformanceUITests.xctest":
            parser.error("Unexpected test bundle path; no output was written.")
        target["UseDestinationArtifacts"] = True
        target["TestBundleDestinationRelativePath"] = bundle
        target["UITargetAppBundleIdentifier"] = "com.pedrosalles.smartkitchen.sync"
        for key in ("TestBundlePath", "TestHostPath", "UITargetAppPath"):
            target.pop(key, None)
    for name in ("EnvironmentVariables", "UITargetAppEnvironmentVariables"):
        environment = target.get(name, {})
        for key in list(environment):
            if key.startswith("PERFC_") or key == "SQLITE_ENABLE_THREAD_ASSERTIONS":
                del environment[key]
        libraries = environment.get("DYLD_INSERT_LIBRARIES")
        if libraries:
            remaining = [value for value in libraries.split(":")
                         if Path(value).name != "libRPAC.dylib"]
            if remaining:
                environment["DYLD_INSERT_LIBRARIES"] = ":".join(remaining)
            else:
                environment.pop("DYLD_INSERT_LIBRARIES", None)
    encoded = plistlib.dumps(configuration)
    # Exclusive creation preserves earlier runners/results, including on retry.
    with os.fdopen(os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "wb") as stream:
        stream.write(encoded)
    print(destination)


if __name__ == "__main__":
    main()
