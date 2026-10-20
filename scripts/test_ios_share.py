"""Run the real UIKit sharing contract without linking device-only LiteRT-LM."""
from pathlib import Path
import platform
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
if platform.system() != 'Darwin':
    raise SystemExit('The UIKit sharing checks require macOS and Xcode.')
sdk = subprocess.check_output(
    ['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
with tempfile.TemporaryDirectory(prefix='ai-gallery-share-checks-') as directory:
    executable = Path(directory) / 'share-checks'
    subprocess.run([
        'xcrun', 'swiftc', '-parse-as-library',
        '-target', f'{platform.machine()}-apple-ios15.0-macabi', '-sdk', sdk,
        '-F', f'{sdk}/System/iOSSupport/System/Library/Frameworks',
        '-I', f'{sdk}/System/iOSSupport/usr/include',
        '-L', f'{sdk}/System/iOSSupport/usr/lib',
        str(root / 'packages/ai_gallery_native/ios/Classes/PhotoShareItem.swift'),
        str(root / 'packages/ai_gallery_native/ios/Tests/PhotoShareItemChecks.swift'),
        '-o', str(executable),
    ], check=True)
    subprocess.run([str(executable)], check=True)
