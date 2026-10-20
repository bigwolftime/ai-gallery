"""Check JNI lookup names in the final, R8-optimized Android APK."""
from pathlib import Path
import argparse
import os
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('apk', type=Path)
parser.add_argument('--apkanalyzer', type=Path)
args = parser.parse_args()

analyzer = args.apkanalyzer or shutil.which('apkanalyzer')
if not analyzer:
    properties = (root / 'android/local.properties').read_text()
    sdk = next(line.split('=', 1)[1] for line in properties.splitlines()
               if line.startswith('sdk.dir='))
    analyzer = Path(sdk) / 'cmdline-tools/latest/bin/apkanalyzer'
if not Path(analyzer).is_file() or not args.apk.is_file():
    raise SystemExit('Provide an existing APK and Android SDK apkanalyzer.')

environment = os.environ.copy()
jdk = Path('/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home')
if jdk.exists() and not environment.get('JAVA_HOME'):
    environment['JAVA_HOME'] = str(jdk)

# JNI resolves every input variant even when this app only supplies images/text.
# Checking the APK, rather than rules or mapping.txt, also catches deleted members.
contracts = {
    'InputData$Text': ('<init>(Ljava/lang/String;)V', 'getText()Ljava/lang/String;'),
    'InputData$Image': ('<init>([B)V', 'getBytes()[B'),
    'InputData$Audio': ('<init>([B)V', 'getBytes()[B'),
    'EmbeddingResponse': ('<init>([F)V', 'getEmbedding()[F'),
}
failures = []
for name, members in contracts.items():
    qualified = f'com.google.ai.edge.litertlm.{name}'
    result = subprocess.run(
        [str(analyzer), 'dex', 'code', '--class', qualified, str(args.apk)],
        env=environment, capture_output=True, text=True)
    missing = [member for member in members if member not in result.stdout]
    if result.returncode or missing:
        failures.append(f'{qualified}: missing JNI class or members {missing}')
    else:
        print(f'PASS {qualified}')
if failures:
    raise SystemExit('\n'.join(failures))
print('Android release JNI contract verified.')
