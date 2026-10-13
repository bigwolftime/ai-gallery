"""Repeatable OTA commands. Default builds validate; --publish uploads explicitly."""
from pathlib import Path
import argparse
import fcntl
import os
import re
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('action', choices=['init', 'doctor', 'release', 'patch'])
parser.add_argument('--platform', choices=['ios', 'android'], default='ios')
parser.add_argument('--track', choices=['beta', 'stable', 'staging'], default='beta')
parser.add_argument('--release-version', default='0.4.0+4')
parser.add_argument('--publish', action='store_true')
args = parser.parse_args()
cli = shutil.which('shorebird') or str(Path.home() / '.shorebird/bin/shorebird')
if not Path(cli).exists():
    raise SystemExit('Install Shorebird first: https://docs.shorebird.dev/code-push/get-started/')
# JSON mode avoids unattended release/patch commands waiting for confirmation.
command = [cli, '--json', args.action] if args.publish else [cli, args.action]
if args.action == 'init':
    command += ['--display-name=AI Gallery']
elif args.action in ['release', 'patch']:
    if not (root / 'shorebird.yaml').exists():
        raise SystemExit('Run python3 scripts/ota.py init after logging in.')
    command += [f'--platforms={args.platform}', f'--dart-define=OTA_TRACK={args.track}']
    if not args.publish:
        command.append('--dry-run')
    if args.platform == 'ios':
        command.append('--no-codesign')
    if args.action == 'release':
        command.append('--flutter-version=3.47.7')
        if args.platform == 'android':
            command += ['--artifact=apk', '--target-platform=android-arm64,android-x64']
    else:
        actual = re.search(r'^version:\s*(\S+)', (root / 'pubspec.yaml').read_text(), re.M)
        if not actual or actual[1] != args.release_version:
            raise SystemExit('A Dart patch must keep the exact base release version in pubspec.yaml.')
        command += [f'--release-version={args.release_version}', f'--track={args.track}']
        # Keep native/asset difference protection enabled. Never silently allow it.
environment = os.environ.copy()
jdk21 = Path('/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home')
if jdk21.exists():
    environment['JAVA_HOME'] = str(jdk21)
print('Running:', ' '.join(command), flush=True)
# Shorebird temporarily replaces package_config.json and restores it afterwards.
# Its Flutter startup lock does not cover that whole operation. Serialize all
# commands in this checkout to avoid one platform deleting another's config.
with (root / '.ota-command.lock').open('a') as lock:
    print('Waiting for exclusive OTA access to this project...', flush=True)
    fcntl.flock(lock, fcntl.LOCK_EX)
    result = subprocess.run(command, cwd=root, env=environment)
    if result.returncode == 0 and args.action == 'init':
        result = subprocess.run([sys.executable, str(root / 'scripts/configure_ota.py')], cwd=root)
raise SystemExit(result.returncode)
