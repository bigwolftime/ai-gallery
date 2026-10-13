"""Configure the real app ID produced by `shorebird init`; never invent an ID."""
from pathlib import Path
import re
import uuid

root = Path(__file__).resolve().parents[1]
config = root / 'shorebird.yaml'
if not config.exists():
    raise SystemExit('Run shorebird login and shorebird init first.')
source = config.read_text()
match = re.search(r'^app_id:\s*([0-9a-fA-F-]+)\s*$', source, re.M)
if not match:
    raise SystemExit('shorebird.yaml has no valid app_id; run shorebird init.')
uuid.UUID(match[1])
if re.search(r'^#?\s*auto_update:', source, re.M):
    source = re.sub(r'^#?\s*auto_update:.*$', 'auto_update: false', source, flags=re.M)
else:
    source += '\nauto_update: false\n'
config.write_text(source)
pubspec = root / 'pubspec.yaml'
text = pubspec.read_text()
if '    - shorebird.yaml' not in text:
    text = text.replace('  assets:\n', '  assets:\n    - shorebird.yaml\n')
text = re.sub(r'^version:.*$', 'version: 0.4.0+4', text, flags=re.M)
pubspec.write_text(text)
print('Configured real Shorebird app ID; updates are controlled by the in-app UI.')
