"""Create the publisher signing key once; credentials stay local and ignored."""
from pathlib import Path
import hashlib
import os
import secrets
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
key = root / 'android/ai-gallery-release.jks'
properties = root / 'android/key.properties'
if key.exists() or properties.exists():
    raise SystemExit('Signing files already exist. Refusing to replace an application identity.')
for path in [key, properties]:
    subprocess.run(['git', 'check-ignore', '--quiet', str(path)], cwd=root, check=True)
jdk = Path('/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home')
keytool = str(jdk / 'bin/keytool') if jdk.exists() else shutil.which('keytool')
if not keytool:
    raise SystemExit('Install a JDK with keytool.')
password = secrets.token_urlsafe(40)
environment = os.environ.copy()
environment['AI_GALLERY_SIGNING_PASSWORD'] = password
# env-backed password arguments keep secrets out of the process command line.
previous_mask = os.umask(0o077)
try:
    subprocess.run([keytool, '-genkeypair', '-storetype', 'JKS', '--keystore', str(key),
        '-storepass:env', 'AI_GALLERY_SIGNING_PASSWORD', '-keypass:env', 'AI_GALLERY_SIGNING_PASSWORD',
        '-alias', 'ai-gallery', '-keyalg', 'RSA', '-keysize', '4096', '-validity', '10000',
        '-dname', 'CN=AI Gallery Release, O=AI Gallery', '-noprompt'],
        env=environment, check=True, capture_output=True)
    properties.write_text('storeFile=ai-gallery-release.jks\nstorePassword='+password+
        '\nkeyAlias=ai-gallery\nkeyPassword='+password+'\n')
    key.chmod(0o600);properties.chmod(0o600)
finally:
    os.umask(previous_mask)
cert = subprocess.check_output([keytool, '-exportcert', '-keystore', str(key), '-alias', 'ai-gallery',
    '-storepass:env', 'AI_GALLERY_SIGNING_PASSWORD'], env=environment)
print('Created private signing key and key.properties, both mode 0600 and excluded from Git.')
print('Certificate SHA-256:', hashlib.sha256(cert).hexdigest())
print('Back up these two local files securely before distributing releases.')
