#!/usr/bin/env python3
"""Compile and execute an Apple-only, local StoreKit price reproduction."""
import argparse
import json
import plistlib
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--device', required=True, help='Already booted Simulator UDID')
parser.add_argument('--output', type=Path, required=True, help='New output directory')
args = parser.parse_args()
root = args.output.resolve()
if root.exists():
    parser.error('Output already exists; choose a new path. Nothing was changed.')
devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', '--json']))
if not any(d['udid'] == args.device and d['state'] == 'Booted'
           for group in devices['devices'].values() for d in group):
    parser.error('Requested Simulator must already be booted.')
source = Path(__file__).resolve().parent
sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'], text=True).strip()
developer = Path(subprocess.check_output(['xcode-select', '-p'], text=True).strip())
platform = developer / 'Platforms/iPhoneSimulator.platform/Developer'
root.mkdir(parents=True)
app = root / 'StoreKitDecimalRepro.app'
tests = root / 'DecimalReproTests.xctest'
for path, identifier, executable, package in [
    (app, 'com.example.storekitdecimal', 'StoreKitDecimalRepro', 'APPL'),
    (tests, 'com.example.storekitdecimal.tests', 'DecimalReproTests', 'BNDL')]:
    path.mkdir()
    info = dict(CFBundleIdentifier=identifier, CFBundleExecutable=executable,
                CFBundleName=executable, CFBundlePackageType=package,
                CFBundleVersion='1', CFBundleShortVersionString='1.0',
                MinimumOSVersion='17.0', UIDeviceFamily=[1, 2], LSRequiresIPhoneOS=True)
    if path == app:
        info['UIApplicationSceneManifest'] = dict(UIApplicationSupportsMultipleScenes=False,
                                                  UISceneConfigurations={})
    (path / 'Info.plist').write_bytes(plistlib.dumps(info))
(app / 'Configuration.storekit').write_bytes((source / 'Configuration.storekit').read_bytes())
common = ['xcrun', 'swiftc', '-sdk', sdk, '-target', 'arm64-apple-ios17.0-simulator']
subprocess.run(common + ['-module-name', 'StoreKitDecimalRepro', str(source / 'main.swift'),
                        '-o', str(app / 'StoreKitDecimalRepro')], check=True)
frameworks = str(platform / 'Library/Frameworks')
libraries = str(platform / 'usr/lib')
subprocess.run(common + ['-F', frameworks, '-F', sdk + '/Developer/Library/Frameworks',
                        '-I', libraries, '-L', libraries, '-lXCTestSwiftSupport',
                        '-parse-as-library', '-emit-library', '-module-name', 'DecimalReproTests',
                        '-framework', 'XCTest', '-framework', 'StoreKitTest',
                        str(source / 'DecimalReproTests.swift'), '-o', str(tests / 'DecimalReproTests')],
               check=True)
for path in [app, tests]:
    subprocess.run(['codesign', '--force', '--sign', '-', str(path)], check=True)
run = dict(BlueprintName='DecimalReproTests', ProductModuleName='DecimalReproTests',
           TestBundlePath=str(tests), TestHostPath=str(app),
           TestHostBundleIdentifier='com.example.storekitdecimal',
           IsAppHostedTestBundle=True, DependentProductPaths=[str(app), str(tests)],
           TestTimeoutsEnabled=True, DefaultTestExecutionTimeAllowance=60,
           MaximumTestExecutionTimeAllowance=60, CommandLineArguments=[],
           TestingEnvironmentVariables={
               'DYLD_FRAMEWORK_PATH': frameworks,
               'DYLD_LIBRARY_PATH': libraries,
               'DYLD_INSERT_LIBRARIES': str(platform / 'usr/lib/libXCTestBundleInject.dylib')})
runfile = root / 'DecimalRepro.xctestrun'
runfile.write_bytes(plistlib.dumps({'DecimalReproTests': run,
                                    '__xctestrun_metadata__': {'FormatVersion': 1}}))
subprocess.run(['xcodebuild', 'test-without-building', '-xctestrun', str(runfile),
                '-destination', 'platform=iOS Simulator,id=' + args.device,
                '-parallel-testing-enabled', 'NO', '-collect-test-diagnostics', 'never', '-resultBundlePath', str(root / 'Result.xcresult')],
               check=True)
