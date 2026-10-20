"""Generate a full-release manifest from verified APK/IPA artifacts, without uploading."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import plistlib
import subprocess
import urllib.parse
import zipfile

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--apk', type=Path)
parser.add_argument('--ipa', type=Path)
parser.add_argument('--base-url', default='https://img.zonheng.net/apps/ai-gallery/')
parser.add_argument('--notes', default='支持整包版本检查与更新引导；保留已下载模型和照片索引。')
parser.add_argument('--output', type=Path, default=root / 'dist/app-updates/releases.json')
parser.add_argument('--merge-from', type=Path, help='Keep other platform/channel entries from an existing manifest.')
parser.add_argument('--application-id', default='com.aigallery.app')
args = parser.parse_args()
if not (args.apk or args.ipa):
    parser.error('Provide an APK and/or IPA.')
base = urllib.parse.urlparse(args.base_url)
if base.scheme != 'https' or not base.netloc or base.query or base.fragment:
    parser.error('Use a stable HTTPS directory URL without query parameters.')

environment = os.environ.copy()
jdk = Path('/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home')
if jdk.exists() and not environment.get('JAVA_HOME'):
    environment['JAVA_HOME'] = str(jdk)

def checksum(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()

def android_info(path):
    sdk = next(line.split('=', 1)[1] for line in (root / 'android/local.properties').read_text().splitlines() if line.startswith('sdk.dir='))
    analyzer = str(Path(sdk) / 'cmdline-tools/latest/bin/apkanalyzer')
    def read(field):
        return subprocess.check_output([analyzer, 'manifest', field, str(path)], env=environment, text=True).strip()
    if read('application-id') != args.application_id:
        raise SystemExit('The APK belongs to another application.')
    return read('version-name'), int(read('version-code'))

entries, artifacts = [], []
if args.merge_from:
    previous = json.loads(args.merge_from.read_text())
    if previous.get('schemaVersion') != 1 or previous.get('appId') != args.application_id:
        parser.error('The existing manifest belongs to another application or schema.')
    entries = previous['releases']
    if not isinstance(entries, list):
        parser.error('The existing releases must be a list.')
for platform, channel, kind, path in [('android', 'direct', 'apk', args.apk), ('ios', 'sideload', 'ipa', args.ipa)]:
    if path is None:
        continue
    path = path.resolve()
    if platform == 'android':
        version, build = android_info(path)
    else:
        with zipfile.ZipFile(path) as archive:
            info = plistlib.loads(archive.read('Payload/Runner.app/Info.plist'))
            if info['CFBundleIdentifier'] != args.application_id:
                raise SystemExit('The IPA belongs to another application.')
            version, build = info['CFBundleShortVersionString'], int(info['CFBundleVersion'])
    # Include the build in the immutable path, even when the marketing version
    # remains unchanged. Never overwrite a binary already advertised to users.
    relative = f'{version}-{build}/{platform}/{path.name}'
    url = args.base_url.rstrip('/') + '/' + urllib.parse.quote(relative, safe='/')
    entry = {'platform': platform, 'channel': channel, 'kind': kind,
             'version': version, 'buildNumber': build, 'url': url,
             'notes': args.notes, 'sha256': checksum(path), 'size': path.stat().st_size}
    # Publishing Android alone must not remove the current iOS download entry.
    entries = [value for value in entries
               if (value['platform'], value['channel']) != (platform, channel)]
    entries.append(entry)
    artifacts.append({'local_path': str(path), 'object_key': urllib.parse.urlparse(url).path.lstrip('/'),
                      'url': url, 'sha256': entry['sha256'], 'size': entry['size']})
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps({'schemaVersion': 1, 'appId': args.application_id, 'releases': entries}, ensure_ascii=False, indent=2) + '\n')
args.output.with_name('upload-plan.json').write_text(json.dumps({'artifacts': artifacts,
    'manifest': {'local_path': str(args.output.resolve()),
                 'object_key': urllib.parse.urlparse(args.base_url).path.strip('/') + '/releases.json'},
    'publish_manifest_last': True}, ensure_ascii=False, indent=2) + '\n')
print(args.output.resolve())
print('Upload immutable binaries first; publish releases.json only after checking their URLs.')
