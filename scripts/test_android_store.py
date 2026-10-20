"""Inspect final store APK/AAB code and permissions; never modify an artifact."""
from pathlib import Path
import argparse
import json
import os
import re
import struct
import subprocess
import xml.etree.ElementTree as ET
import zipfile

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('artifact', type=Path)
parser.add_argument('--channel', choices=['public', 'fdroid', 'play'], required=True)
parser.add_argument('--bundletool', type=Path, help='Official bundletool jar for AAB manifest inspection.')
parser.add_argument('--require-signed', action='store_true')
args = parser.parse_args()
environment = os.environ.copy()
jdk = Path('/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home')
if jdk.exists() and not environment.get('JAVA_HOME'):
    environment['JAVA_HOME'] = str(jdk)
sdk = Path(next(line.split('=', 1)[1] for line in
               (root / 'android/local.properties').read_text().splitlines() if line.startswith('sdk.dir=')))
if args.require_signed:
    if args.artifact.suffix == '.apk':
        certificate = subprocess.check_output([str(sdk / 'build-tools/36.0.0/apksigner'), 'verify', '--print-certs', str(args.artifact)], env=environment, text=True)
    else:
        keytool = str(Path(environment['JAVA_HOME']) / 'bin/keytool') if environment.get('JAVA_HOME') else 'keytool'
        certificate = subprocess.check_output([keytool, '-J-Duser.language=en', '-printcert', '-jarfile', str(args.artifact)], env=environment, text=True)
        assert 'Owner:' in certificate, 'AAB is not signed'
    assert 'cn=android debug' not in certificate.lower(), 'A debug certificate cannot be used for store publishing'
if args.artifact.suffix == '.apk':
    manifest = subprocess.check_output([str(sdk / 'cmdline-tools/latest/bin/apkanalyzer'),
        'manifest', 'print', str(args.artifact)], env=environment, text=True)
else:
    bundletool = args.bundletool or Path.home() / '.shorebird/bin/cache/artifacts/bundletool/bundletool.jar'
    if not bundletool.is_file():
        parser.error('AAB inspection needs the official bundletool jar; supply --bundletool.')
    manifest = subprocess.check_output([str(Path(environment['JAVA_HOME']) / 'bin/java') if environment.get('JAVA_HOME') else 'java',
        '-jar', str(bundletool), 'dump', 'manifest', '--bundle=' + str(args.artifact)], env=environment, text=True)
if manifest:
    android = '{http://schemas.android.com/apk/res/android}'
    tree = ET.fromstring(manifest)
    assert tree.get('package') == 'net.zonheng.aigallery', 'Wrong production identity'
    expected = re.search(r'^version:\s*(\S+)', (root / 'pubspec.yaml').read_text(), re.M)[1]
    assert tree.get(android + 'versionName') + '+' + tree.get(android + 'versionCode') == expected, 'Stale store artifact'
    has_installer = any(node.get(android + 'name') == 'android.permission.REQUEST_INSTALL_PACKAGES'
                        for node in tree.findall('uses-permission'))
    assert has_installer == (args.channel == 'public'), 'Wrong distribution install permissions'
    app = tree.find('application')
    assert app.get(android + 'debuggable', 'false') == 'false'
    has_provider = any('ai_gallery.updates' in node.get(android + 'authorities', '') for node in app.findall('provider'))
    assert has_provider == (args.channel == 'public'), 'Wrong distribution update provider'
    assert any(node.get(android + 'name') == 'ai_gallery.distribution_channel'
               and node.get(android + 'value') == args.channel for node in app.findall('meta-data'))
    if args.artifact.suffix == '.apk':
        subprocess.run([str(sdk / 'build-tools/36.0.0/zipalign'), '-c', '-P', '16', '4', str(args.artifact)], check=True)
with zipfile.ZipFile(args.artifact) as archive:
    assert not any(name.endswith('.litertlm') for name in archive.namelist()), 'Bundled model weight'
    libraries = [name for name in archive.namelist() if name.endswith('.so')]
    assert libraries
    engines = [name for name in libraries if name.endswith('/libflutter.so')]
    assert engines
    for name in libraries:
        data = archive.read(name)
        if name in engines:
            shorebird = b'shorebird_current_boot_patch_number' in data
            assert shorebird == (args.channel == 'public'), 'Wrong Flutter engine for this distribution'
        if name.endswith('/libapp.so'):
            assert b'AI_GALLERY_DEMO_ONLY' not in data, 'Screenshot fixture must never be published'
        assert data[:5] == b'\x7fELF\x02', name
        endian = '<' if data[5] == 1 else '>'
        header = struct.unpack_from(endian + '16sHHIQQQIHHHHHH', data)
        loads = [struct.unpack_from(endian + 'IIQQQQQQ', data, header[5] + index * header[9])
                 for index in range(header[10])]
        alignments = [entry[7] for entry in loads if entry[0] == 1]
        assert alignments and min(alignments) >= 16384, f'16 KB ELF alignment: {name}'
print(json.dumps({'artifact': str(args.artifact), 'channel': args.channel,
                  'ordinary_flutter_engine': args.channel != 'public', 'native_16kb_alignment': True,
                  'model_weights_bundled': False,
                  'manifest_checked': True}))
