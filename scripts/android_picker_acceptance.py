#!/usr/bin/env python3
"""Exercise the real Downloads picker and import in a signed APK emulator."""
import io
from pathlib import Path
import re
import subprocess
import tempfile
import time
import uuid
import wave
import xml.etree.ElementTree as ET


def check_download_import(command, output):
    """Only called after the release smoke test verifies a dedicated emulator."""
    output = Path(output)

    def run(*args, **kwargs):
        return subprocess.run(command + list(args), capture_output=True,
                              check=True, timeout=45, **kwargs)

    def hierarchy():
        run('shell', 'uiautomator', 'dump', '/sdcard/crisper-picker.xml')
        xml = run('shell', 'cat', '/sdcard/crisper-picker.xml').stdout
        (output / 'picker-latest.xml').write_bytes(xml)
        return ET.fromstring(xml)

    def wait_node(predicate, timeout=40):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            for node in hierarchy().iter('node'):
                if predicate(node.attrib):
                    return node
            time.sleep(1)
        raise RuntimeError('Expected picker/import UI missing; inspect picker-latest.xml')

    def label(value):
        return lambda a: value in (a.get('text', ''), a.get('content-desc', ''))

    def tap(node):
        if node.get('enabled') != 'true':
            raise RuntimeError('Downloads file is disabled in the system picker')
        bounds = [int(n) for n in re.findall(r'\d+', node.get('bounds', ''))]
        if len(bounds) != 4:
            raise RuntimeError('Missing UI bounds')
        run('shell', 'input', 'tap', str((bounds[0] + bounds[2]) // 2),
            str((bounds[1] + bounds[3]) // 2))

    initial = wait_node(lambda a: label('Skip')(a) or
                        label('Import audiobooks')(a) or label('Import')(a))
    if label('Skip')(initial.attrib):
        tap(initial)

    # Real AAC/MP4 M4B, plus PCM WAV. Both are deliberately advertised by the
    # Downloads provider as application/octet-stream to reproduce the bug.
    with tempfile.TemporaryDirectory(prefix='crisper-picker-') as temporary:
        root = Path(temporary)
        wav = root / 'source.wav'
        buffer = io.BytesIO()
        with wave.open(buffer, 'wb') as audio:
            audio.setnchannels(1)
            audio.setsampwidth(2)
            audio.setframerate(16000)
            audio.writeframes(b'\x00\x00' * 32000)
        wav.write_bytes(buffer.getvalue())
        m4b = root / 'source.m4b'
        subprocess.run(['ffmpeg', '-nostdin', '-loglevel', 'error', '-i', str(wav),
                        '-c:a', 'aac', '-f', 'mp4', str(m4b)], check=True, timeout=30)
        for source in (m4b, wav):
            title = 'CrisperPicker' + uuid.uuid4().hex[:10]
            name = title + source.suffix
            inserted = run('shell', 'content', 'insert', '--uri',
                           'content://media/external/downloads', '--bind',
                           '_display_name:s:' + name, '--bind',
                           'mime_type:s:application/octet-stream', '--bind',
                           'relative_path:s:Download/').stdout.decode()
            match = re.search(r'content://media/[^\s]+/\d+', inserted)
            if not match:
                raise RuntimeError('Cannot create isolated Downloads fixture: ' + inserted)
            uri = match[0]
            try:
                run('shell', 'content', 'write', '--uri', uri, input=source.read_bytes())
                metadata = run('shell', 'content', 'query', '--uri', uri,
                               '--projection', '_display_name:mime_type').stdout.decode()
                if 'application/octet-stream' not in metadata:
                    raise RuntimeError('Fixture did not retain the regression MIME type')
                (output / ('picker-fixture' + source.suffix + '.txt')).write_text(metadata)
                tap(wait_node(lambda a: label('Import audiobooks')(a) or label('Import')(a)))
                tap(wait_node(label('Import audio files')))
                # Select the actual Downloads root via the system navigation drawer.
                tap(wait_node(lambda a: a.get('content-desc') in
                              ('Show roots', 'Open navigation drawer')))
                tap(wait_node(label('Downloads')))
                tap(wait_node(label(name)))
                wait_node(lambda a: a.get('package') == 'com.crispstrobe.crisperplayer'
                          and title in (a.get('text', '') + a.get('content-desc', '')))
                screenshot = run('exec-out', 'screencap', '-p').stdout
                (output / ('picker-import' + source.suffix + '.png')).write_bytes(screenshot)
                print('Signed APK Downloads picker imported ' + source.suffix + ' with generic MIME type')
            finally:
                # Remove only the UUID-owned fixture. App-owned imported copy remains
                # for the subsequent in-place reinstall/data-preservation check.
                run('shell', 'content', 'delete', '--uri', uri)
        run('shell', 'rm', '-f', '/sdcard/crisper-picker.xml')
