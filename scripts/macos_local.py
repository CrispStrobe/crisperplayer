#!/usr/bin/env python3
"""Build/run/test locally using the explicitly selected Brickwright keychain."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TEAM = 'N9XSJ4M3GT'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['build', 'run', 'test'], nargs='?', default='build')
    parser.add_argument('--keychain', type=Path,
                        default=Path.home() / 'Library/Keychains/brickwright-build.keychain-db')
    parser.add_argument('--test-file', default='integration_test/desktop_test.dart')
    args = parser.parse_args()
    keychain = args.keychain.expanduser().resolve(strict=True)
    if any(char in str(keychain) for char in '\r\n"'):
        parser.error('Unsupported characters in keychain path')
    identities = subprocess.check_output(
        ['security', 'find-identity', '-v', '-p', 'codesigning', str(keychain)], text=True)
    identity = next((fingerprint for fingerprint, label in
                     re.findall(r'([A-Fa-f0-9]{40}) "([^"]+)"', identities)
                     if label.startswith('Apple Distribution:') and TEAM in label), None)
    if identity is None:
        parser.error('No valid Apple Distribution identity in the selected keychain')
    # Xcode applies these settings to its signing steps, including embedded code.
    # No default-keychain/search-list mutation or private-key export is needed.
    with tempfile.TemporaryDirectory(prefix='crisper-macos-signing-') as directory:
        configuration = Path(directory) / 'LocalSigning.xcconfig'
        configuration.write_text(
            f'CODE_SIGN_STYLE = Manual\nDEVELOPMENT_TEAM = {TEAM}\n'
            f'CODE_SIGN_IDENTITY = {identity}\nCODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO\n'
            f'OTHER_CODE_SIGN_FLAGS = --keychain "{keychain}"\n')
        environment = dict(os.environ, XCODE_XCCONFIG_FILE=str(configuration),
                           CRISPERPLAYER_MACOS_KEYCHAIN=str(keychain))
        for variable in ['GEM_HOME', 'GEM_PATH', 'RUBYOPT']:
            environment.pop(variable, None)
        definition = f'--dart-define=CRISPERPLAYER_MACOS_KEYCHAIN={keychain}'
        command = (['flutter', 'test', args.test_file, '-d', 'macos', definition]
                   if args.action == 'test' else ['flutter', 'build', 'macos', '--debug', definition])
        foreground = None
        if args.action == 'test':
            # LaunchServices sometimes cannot foreground a locally signed test
            # bundle. Activate only the new test process, never a running user app.
            process_list = subprocess.check_output(['ps', '-axo', 'pid=,comm='], text=True)
            executable = str(ROOT / 'build/macos/Build/Products/Debug/crisperplayer.app/Contents/MacOS/crisperplayer')
            existing = [int(line.strip().split(None, 1)[0]) for line in process_list.splitlines()
                        if line.strip().endswith(executable)]
            excluded = ', '.join(str(pid) for pid in existing)
            swift = f'''import AppKit
let excluded: Set<pid_t> = [{excluded}]
let deadline = Date().addingTimeInterval(600)
while Date() < deadline {{
    if let app = NSWorkspace.shared.runningApplications.first(where: {{
        $0.bundleIdentifier == "com.crispstrobe.crisperplayer" && !excluded.contains($0.processIdentifier)
    }}) {{
        _ = app.activate(options: [.activateAllWindows]); break
    }}
    RunLoop.current.run(until: Date().addingTimeInterval(0.25))
}}
'''
            foreground = subprocess.Popen(['swift', '-e', swift], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            subprocess.run(command, cwd=ROOT, env=environment, check=True)
        finally:
            if foreground is not None and foreground.poll() is None:
                foreground.terminate()
                foreground.wait(timeout=10)
        app = ROOT / 'build/macos/Build/Products/Debug/crisperplayer.app'
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
        signature = subprocess.check_output(['codesign', '-d', '--verbose=4', str(app)],
                                            stderr=subprocess.STDOUT, text=True)
        if f'TeamIdentifier={TEAM}' not in signature or 'Authority=Apple Distribution:' not in signature:
            raise RuntimeError('The local app was not signed with the selected distribution identity')
    environment.pop('XCODE_XCCONFIG_FILE', None)
    if args.action == 'run':
        binary = ROOT / 'build/macos/Build/Products/Debug/crisperplayer.app/Contents/MacOS/crisperplayer'
        os.execve(str(binary), [str(binary)], environment)


if __name__ == '__main__':
    main()
