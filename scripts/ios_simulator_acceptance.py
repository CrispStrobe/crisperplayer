#!/usr/bin/env python3
"""Run mobile UI acceptance on an isolated iPhone simulator, then delete it."""
import json
import subprocess


def main():
    data = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '-j']))
    candidates = [(runtime, device) for runtime, devices in data['devices'].items()
                  if '.iOS-' in runtime for device in devices
                  if device.get('isAvailable') and 'iPhone' in device['name']]
    if not candidates:
        raise RuntimeError('Install an iOS Simulator runtime and iPhone device type first')
    runtime, device = candidates[0]
    simulator = subprocess.check_output(['xcrun', 'simctl', 'create', 'CrisperPlayer acceptance',
        device['deviceTypeIdentifier'], runtime], text=True).strip()
    try:
        subprocess.run(['xcrun', 'simctl', 'boot', simulator], check=True)
        subprocess.run(['xcrun', 'simctl', 'bootstatus', simulator, '-b'], check=True)
        for target in ['integration_test/app_test.dart', 'integration_test/browser_upload_test.dart']:
            subprocess.run(['flutter', 'test', target, '-d', simulator], check=True)
    finally:
        subprocess.run(['xcrun', 'simctl', 'shutdown', simulator], capture_output=True)
        subprocess.run(['xcrun', 'simctl', 'delete', simulator], check=True)


if __name__ == '__main__':
    main()
