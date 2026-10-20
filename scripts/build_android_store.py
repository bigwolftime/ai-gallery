"""Build F-Droid/Play artifacts with the ordinary Flutter SDK, never Shorebird."""
from pathlib import Path
import argparse
import fcntl
import json
import os
import re
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
REQUIRED_FLUTTER_REVISION = '00b0c91f06209d9e4a41f71b7a512d6eb3b9c694'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--channel', choices=['fdroid', 'play'], required=True)
parser.add_argument('--artifact', choices=['apk', 'appbundle'])
parser.add_argument('--unsigned', action='store_true', help='F-Droid server signing or local review; not a Play upload.')
parser.add_argument('--flutter', default=shutil.which('flutter'))
args = parser.parse_args()
if not args.flutter:
    parser.error('Install the ordinary Flutter 3.41.9 SDK or supply --flutter.')
args.artifact = args.artifact or ('apk' if args.channel == 'fdroid' else 'appbundle')
version = re.search(r'^version:\s*(\S+)', (root / 'pubspec.yaml').read_text(), re.M)[1]
listing = ('https://f-droid.org/packages/net.zonheng.aigallery/' if args.channel == 'fdroid'
           else 'https://play.google.com/store/apps/details?id=net.zonheng.aigallery')
environment = os.environ.copy()
environment['ORG_GRADLE_PROJECT_distributionChannel'] = args.channel
environment['ORG_GRADLE_PROJECT_allowUnsignedStoreRelease'] = str(args.unsigned).lower()
jdk = Path('/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home')
if jdk.exists() and not environment.get('JAVA_HOME'):
    environment['JAVA_HOME'] = str(jdk)
command = [args.flutter, 'build', args.artifact, '--release',
           '--target-platform=android-arm64,android-x64',
           f'--dart-define=APP_DISTRIBUTION_CHANNEL={args.channel}',
           '--dart-define=APP_APPLICATION_ID=net.zonheng.aigallery',
           f'--dart-define=APP_STORE_LISTING_URL={listing}']
# Serialize with the existing OTA commands: both Flutter tools rewrite the same
# package configuration, even though the store build does not use Shorebird.
with (root / '.ota-command.lock').open('a') as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    sdk = subprocess.check_output([args.flutter, '--version', '--machine'], env=environment, text=True)
    sdk_info = json.loads(sdk)
    if sdk_info.get('repositoryUrl') != 'https://github.com/flutter/flutter.git':
        parser.error('Use the official Flutter SDK, not a patched update engine.')
    if sdk_info.get('frameworkRevision') != REQUIRED_FLUTTER_REVISION:
        parser.error('This release pins ordinary Flutter 3.41.9; pass its SDK with --flutter.')
    subprocess.run(command, cwd=root, env=environment, check=True)
    if args.artifact == 'apk':
        candidates = list((root / 'build/app/outputs/flutter-apk').glob('app-release*.apk'))
    else:
        candidates = list((root / 'build/app/outputs/bundle/release').glob('*.aab'))
    if not candidates:
        raise SystemExit('No store artifact found.')
    source = max(candidates, key=lambda path: path.stat().st_mtime)
    # Inspect the artifact before copying: an old sideload output must never be
    # labelled as a store release, while valid cached builds can be reused.
    validation = [os.sys.executable, str(root / 'scripts/test_android_store.py'), str(source), '--channel', args.channel]
    if not args.unsigned:
        validation.append('--require-signed')
    subprocess.run(validation, cwd=root, env=environment, check=True)
    output = root / 'dist/stores' / f'AI-Gallery-{args.channel}-{version.replace("+", "-")}{"-unsigned" if args.unsigned else ""}{source.suffix}'
    output.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, output)
print(output)
