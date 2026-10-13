"""Package a no-codesign Flutter app for user re-signing, with artifact checks."""
from pathlib import Path
import argparse
import plistlib
import re
import subprocess
import zipfile

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--ota', action='store_true', help='Package the Shorebird archive, never the ordinary Flutter app.')
args = parser.parse_args()
# Use an explicit build source: the two engines must never be confused.
app = root / ('build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app'
              if args.ota else 'build/ios/iphoneos/Runner.app')
info = plistlib.loads((app / 'Info.plist').read_bytes())
version = info['CFBundleShortVersionString']
output = root / ('dist/AI-Gallery-OTA-' + version + '-unsigned.ipa'
                 if args.ota else 'dist/AI-Gallery-Flutter-unsigned.ipa')
assert info['CFBundleIdentifier'] == 'com.aigallery.app'
assert (app / info['CFBundleExecutable']).is_file()
models = list(app.rglob('*.litertlm'))
assert not models, f'Model must be downloaded independently: {models}'
for name in ['Flutter', 'App', 'CLiteRTLM', 'ai_gallery_native']:
    framework = app / 'Frameworks' / f'{name}.framework'
    framework_info = plistlib.loads((framework / 'Info.plist').read_bytes())
    assert (framework / framework_info['CFBundleExecutable']).is_file(), name
if args.ota:
    # Reject stale archives before producing an installable OTA baseline.
    expected = next(line.split(':', 1)[1].strip() for line in
                    (root / 'pubspec.yaml').read_text().splitlines() if line.startswith('version:'))
    assert f"{version}+{info['CFBundleVersion']}" == expected
    bundled_config = app / 'Frameworks/App.framework/flutter_assets/shorebird.yaml'
    # Shorebird normalizes YAML and strips comments during the release build.
    for key in ('app_id', 'auto_update'):
        pattern = rf'^{key}:\s*([^\n#]+)'
        source = re.search(pattern, (root / 'shorebird.yaml').read_text(), re.M)
        bundled = re.search(pattern, bundled_config.read_text(), re.M)
        assert source and bundled and source[1].strip() == bundled[1].strip(), key
    symbols = subprocess.check_output(['nm', '-gU', str(app / 'Frameworks/Flutter.framework/Flutter')], text=True)
    assert '_shorebird_current_boot_patch_number' in symbols, 'Missing Shorebird updater engine'
output.parent.mkdir(exist_ok=True)
partial = output.with_suffix('.partial')
try:
    with zipfile.ZipFile(partial, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in sorted(app.rglob('*')):
            if path.is_file():
                archive.write(path, Path('Payload/Runner.app') / path.relative_to(app))
    with zipfile.ZipFile(partial) as archive:
        assert archive.testzip() is None
    partial.replace(output)
finally:
    partial.unlink(missing_ok=True)
print(f'{output.name}: {output.stat().st_size / 1024**2:.1f} MiB; no bundled model; frameworks verified')
