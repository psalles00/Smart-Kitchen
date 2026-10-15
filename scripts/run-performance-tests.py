#!/usr/bin/env python3
"""Run read-only page measurements and reopen Savoria before result export ends."""
import argparse
from pathlib import Path
import plistlib
import subprocess


BUNDLE = "com.pedrosalles.smartkitchen.sync"
PAGES = ("Home", "Lists", "Nutrition", "Recipes", "Search")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--xctestrun", type=Path, required=True)
    destination = parser.add_mutually_exclusive_group(required=True)
    destination.add_argument("--simulator")
    destination.add_argument("--device")
    parser.add_argument("--result", type=Path, required=True)
    parser.add_argument("--page", action="append", choices=PAGES)
    args = parser.parse_args()
    with args.xctestrun.open("rb") as stream:
        runner = plistlib.load(stream).get("SavoriaPerformanceUITests", {})
    if runner.get("UITargetAppPerformanceAntipatternCheckerEnabled") is not False:
        parser.error("Prepare a measurement copy with prepare-performance-run.py first.")
    result = args.result.resolve()
    log_path = result.with_suffix(".log")
    if result.exists() or log_path.exists():
        parser.error("Use new result and log paths; existing evidence is preserved.")
    identifier = args.simulator or args.device
    command = ["xcodebuild", "test-without-building", "-xctestrun", str(args.xctestrun.resolve()),
               "-destination", "id=" + identifier, "-parallel-testing-enabled", "NO",
               "-enableCodeCoverage", "NO", "-enablePerformanceTestsDiagnostics", "NO",
               "-collect-test-diagnostics", "never", "-resultBundlePath", str(result)]
    for page in args.page or PAGES:
        method = "testHitchesSearchAndForeground" if page == "Search" else "testHitches" + page + "ScrollAndForeground"
        command.append("-only-testing:SavoriaPerformanceUITests/PageActionTracingTests/" + method)
    flags = ["-SavoriaActionTrace", "-SavoriaKeepAwakeForValidation"]
    launch = (["xcrun", "simctl", "launch", "--terminate-running-process", identifier, BUNDLE] + flags
              if args.simulator else
              ["xcrun", "devicectl", "device", "process", "launch", "--device", identifier,
               "--terminate-existing", BUNDLE, "--"] + flags)
    result.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("x") as log:
        def reopen():
            log.write("\nReopening validation app before/after Xcode result export.\n")
            log.flush()
            try:
                status = subprocess.run(launch, stdout=log, stderr=subprocess.STDOUT, timeout=20).returncode
            except subprocess.TimeoutExpired:
                status = 124
            log.write(f"Validation reopen exit: {status}\n")
            log.flush()
            return status

        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   text=True, bufsize=1)
        reopened = False
        for line in process.stdout:
            log.write(line)
            log.flush()
            # XCTest may terminate the target during teardown. Do not wait for
            # xcodebuild to finish symbolication/export while the phone idles.
            if not reopened and "Test Suite 'Selected tests' passed" in line:
                reopen()
                reopened = True
        status = process.wait()
        if status == 0:
            launch_status = reopen()
            if launch_status:
                print(f"Tests passed; app reopening requires attention (exit {launch_status}).")
                raise SystemExit(launch_status)
    print(f"Tests exit: {status}; evidence: {result}")
    raise SystemExit(status)


if __name__ == "__main__":
    main()
