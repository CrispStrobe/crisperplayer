#!/usr/bin/env python3
"""Regenerate native icon assets from the artwork. Requires ImageMagick 7."""
import json
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/branding/app-icon-source.png'
FOREGROUND = ROOT / 'assets/branding/app-icon-foreground.png'


def convert(*args):
    subprocess.run(['magick', *map(str, args)], check=True)


def resize(source, size, output, opaque=True):
    output.parent.mkdir(parents=True, exist_ok=True)
    convert(source, '-resize', f'{size}x{size}!', '-strip', '-depth', '8',
            *(['-alpha', 'off'] if opaque else []),
            ('PNG24:' if opaque else 'PNG32:') + str(output))


with tempfile.TemporaryDirectory(prefix='crisper-icons-') as temporary:
    temp = Path(temporary)
    mac = temp / 'mac.png'
    convert(SOURCE, '-resize', '824x824!', '(', '-size', '824x824', 'xc:black',
            '-fill', 'white', '-draw', 'roundrectangle 0,0 823,823 180,180', ')',
            '-alpha', 'off', '-compose', 'CopyOpacity', '-composite',
            '-compose', 'Over', '-gravity', 'center', '-background', 'none', '-extent', '1024x1024', mac)
    for platform, base, opaque in [
        ('ios', SOURCE, True), ('macos', mac, False),
    ]:
        folder = ROOT / platform / 'Runner/Assets.xcassets/AppIcon.appiconset'
        entries = json.loads((folder / 'Contents.json').read_text())['images']
        for entry in entries:
            size = round(float(entry['size'].split('x')[0]) * float(entry['scale'][:-1]))
            resize(base, size, folder / entry['filename'], opaque)
    android = ROOT / 'android/app/src/main/res'
    for density, size in [('mdpi',48), ('hdpi',72), ('xhdpi',96), ('xxhdpi',144), ('xxxhdpi',192)]:
        resize(SOURCE, size, android / f'mipmap-{density}/ic_launcher.png')
    fg = android / 'drawable-nodpi/ic_launcher_foreground.png'
    fg.parent.mkdir(parents=True, exist_ok=True)
    convert(FOREGROUND, '-resize', '304x304!', '-gravity', 'center', '-background', 'none',
            '-extent', '432x432', '-strip', 'PNG32:' + str(fg))
    adaptive = android / 'mipmap-anydpi-v26/ic_launcher.xml'
    adaptive.parent.mkdir(parents=True, exist_ok=True)
    adaptive.write_text('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
''')
    (android / 'values/icon_colors.xml').write_text('''<?xml version="1.0" encoding="utf-8"?>
<resources><color name="ic_launcher_background">#0D0B40</color></resources>
''')
    for size in [192,512]:
        resize(SOURCE, size, ROOT / f'web/icons/Icon-{size}.png')
        convert(FOREGROUND, '-resize', f'{round(size * .76)}x{round(size * .76)}!',
                '-gravity', 'center', '-background', '#0D0B40', '-extent', f'{size}x{size}',
                '-alpha', 'remove', '-alpha', 'off', '-strip',
                'PNG24:' + str(ROOT / f'web/icons/Icon-maskable-{size}.png'))
    resize(SOURCE, 32, ROOT / 'web/favicon.png')
    convert(mac, '-define', 'icon:auto-resize=256,128,64,48,32,24,16',
            ROOT / 'windows/runner/resources/app_icon.ico')
    resize(SOURCE, 256, ROOT / 'linux/runner/resources/app_icon.png')
print('Generated iOS, macOS, Android adaptive/legacy, Windows, web and Linux icon assets.')
