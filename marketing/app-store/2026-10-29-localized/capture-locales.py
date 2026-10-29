"""Capture only the six native views used by marketing, from memory-only fixtures."""
import copy, hashlib, json, os, pathlib, plistlib, shutil, subprocess, sys
ROOT = pathlib.Path(__file__).resolve().parent
BUILD = pathlib.Path('/Volumes/PS-Externo/Coding/Builds/Savoria-Reserve-Tests/Products')
EVIDENCE = pathlib.Path('/Volumes/PS-Externo/Coding/Builds/Savoria-Nutrition-Final-20261028')
DEVICE = 'A3D7F658-1D04-4369-9B96-B3D20591DF0D'
LANGUAGES = {'en': ('en-US', 'US'), 'es': ('es-ES', 'ES'), 'fr': ('fr-FR', 'FR'), 'de': ('de-DE', 'DE'), 'it': ('it-IT', 'IT'), 'ja': ('ja-JP', 'JP')}
gallery_only = os.getenv('SAVORIA_CAPTURE_GALLERY_ONLY') == '1'
base = plistlib.load(open(BUILD / 'Savoria-marketing-ptBR.xctestrun', 'rb'))
app = plistlib.load(open(BUILD / 'Release-iphonesimulator/Savoria.app/Info.plist', 'rb'))
assert app['CFBundleIdentifier'] == 'com.pedrosalles.smartkitchen.sync'
manifest_path = ROOT / 'capture-manifest.json'
manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
for language in sys.argv[1:] or LANGUAGES:
    locale, region = LANGUAGES[language]
    data = copy.deepcopy(base)
    target = data['SavoriaTests']
    target['EnvironmentVariables'].update(SAVORIA_TEST_LOCALE=locale, SAVORIA_MARKETING_CAPTURE='1')
    if gallery_only:
        target['EnvironmentVariables']['SAVORIA_MARKETING_PAGES'] = 'recipes'
    target['CommandLineArguments'] = ['-AppleLanguages', '(' + language + ')', '-AppleLocale', locale.replace('-', '_')]
    target['TestLanguage'], target['TestRegion'] = language, region
    spec = BUILD / ('Savoria-marketing-' + language + '.xctestrun')
    plistlib.dump(data, open(spec, 'wb'))
    suffix = '-v5-gallery' if gallery_only else '-v3'
    result = EVIDENCE / ('marketing-locale-' + language + suffix + '.xcresult')
    log = EVIDENCE / ('marketing-locale-' + language + suffix + '.log')
    if result.exists():
        if not log.exists() or '** TEST EXECUTE SUCCEEDED **' not in log.read_text():
            raise RuntimeError('Reconcile existing result before retrying: ' + str(result))
    else:
        print('Capturing native locale:', language, flush=True)
        with open(log, 'w') as output:
            subprocess.run(['xcodebuild', 'test-without-building', '-xctestrun', str(spec), '-destination', 'platform=iOS Simulator,id=' + DEVICE,
                '-only-testing:SavoriaTests/AdaptiveWorkspaceRenderingTests/testAppStoreDemonstrationCaptures', '-resultBundlePath', str(result), '-parallel-testing-enabled', 'NO'], stdout=output, stderr=subprocess.STDOUT, check=True)
    export = EVIDENCE / ('marketing-locale-' + language + suffix + '-export')
    if not (export / 'manifest.json').exists():
        subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(result), '--output-path', str(export)], check=True, stdout=subprocess.DEVNULL)
    output = ROOT / 'captures' / language
    output.mkdir(parents=True, exist_ok=True)
    files = []
    for test in json.loads((export / 'manifest.json').read_text()):
        for attachment in test['attachments']:
            name = attachment['suggestedHumanReadableName'].split('_0_')[0].removeprefix('store-')
            if name not in ['home', 'pantry', 'market', 'recipes', 'recipe', 'nutrition', 'recipe-scrolled']:
                continue
            source = export / attachment['exportedFileName']
            dest = output / (name + '.png')
            shutil.copyfile(source, dest)
            digest = hashlib.sha256(dest.read_bytes()).hexdigest()
            assert digest == hashlib.sha256(source.read_bytes()).hexdigest()
            files.append({'name': name, 'path': str(dest.relative_to(ROOT)), 'sha256': digest, 'captureResult': str(result)})
    assert len(files) == (1 if gallery_only else 7), (language, files)
    if gallery_only:
        merged = {entry['name']: entry for entry in manifest[language]['files']}
        merged.update({entry['name']: entry for entry in files})
        files = list(merged.values())
    prior = manifest.get(language, {})
    manifest[language] = {'locale': locale, 'device': 'iPhone 17 Pro Simulator', 'result': prior['result'] if gallery_only else str(result), 'galleryResult': str(result) if gallery_only else None, 'fixture': 'memory-only, no CloudKit', 'files': files}
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    print('Verified seven native captures:', language, flush=True)
