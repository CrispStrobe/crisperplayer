#!/usr/bin/env python3
"""Install and cold-start the actual release APK on a dedicated Android emulator."""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import time

PACKAGE = 'com.crispstrobe.crisperplayer'
READY = 'CrisperPlayer startup complete'
FAILURES = re.compile(r'Startup failed:|NoSuchMethodError|FATAL EXCEPTION|Unhandled Exception')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    parser.add_argument('--serial', default=os.environ.get('ANDROID_SERIAL'))
    parser.add_argument('--output', type=Path, default=Path('build/android-smoke'))
    args = parser.parse_args()
    adb = shutil.which('adb')
    if not adb:
        sdk = os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT')
        if sdk:
            candidate = Path(sdk) / 'platform-tools/adb'
            if candidate.is_file():
                adb = str(candidate)
    if not adb:
        parser.error('adb is required')
    if not args.serial:
        devices = subprocess.check_output([adb, 'devices'], text=True).splitlines()[1:]
        devices = [line.split()[0] for line in devices if line.endswith('\tdevice')]
        if len(devices) != 1:
            parser.error('Select exactly one dedicated emulator with --serial')
        args.serial = devices[0]
    if not args.serial.startswith('emulator-'):
        parser.error('This smoke test only operates on a dedicated emulator')
    apk = args.apk.resolve(strict=True)
    args.output.mkdir(parents=True, exist_ok=True)
    command = [adb, '-s', args.serial]

    def run(*arguments, check=True):
        return subprocess.run(command + list(arguments), check=check,
                              capture_output=True, text=True, timeout=120)

    def launch(label):
        run('shell', 'am', 'force-stop', PACKAGE)
        run('logcat', '-c')
        run('shell', 'am', 'start', '-W', '-n', PACKAGE + '/.MainActivity')
        deadline = time.monotonic() + 90
        logs = ''
        while time.monotonic() < deadline:
            pid = run('shell', 'pidof', PACKAGE, check=False).stdout.strip()
            if pid:
                logs = run('logcat', '-d', '--pid=' + pid.split()[0]).stdout
                if FAILURES.search(logs):
                    break
                if READY in logs:
                    time.sleep(2)
                    logs = run('logcat', '-d', '--pid=' + pid.split()[0]).stdout
                    break
            time.sleep(1)
        (args.output / (label + '.log')).write_text(logs)
        screenshot = subprocess.run(command + ['exec-out', 'screencap', '-p'],
                                    capture_output=True, check=True, timeout=30)
        (args.output / (label + '.png')).write_bytes(screenshot.stdout)
        if READY not in logs or FAILURES.search(logs):
            raise RuntimeError(f'Release APK failed {label}; inspect {args.output}')
        print(f'Release APK {label}: native startup confirmed')

    run('install', '-r', str(apk))
    launch('cold-start')
    from android_picker_acceptance import check_download_import
    check_download_import(command, args.output)
    # Reinstall in place and restart without clearing app data: this exercises
    # preferences/database reopening and prevents a debug-only smoke test.
    run('install', '-r', str(apk))
    launch('after-reinstall')
    run('shell', 'am', 'force-stop', PACKAGE)


if __name__ == '__main__':
    main()
