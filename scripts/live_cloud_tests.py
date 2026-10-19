#!/usr/bin/env python3
"""Run opt-in cloud tests locally, injecting only selected ../.env credentials."""
import argparse
import os
from pathlib import Path
import shlex
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--env-file', type=Path, default=Path('../.env'))
    parser.add_argument('--provider', choices=['filen', 'internxt', 'all'], default='all')
    args = parser.parse_args()
    if os.environ.get('CI') or os.environ.get('GITHUB_ACTIONS'):
        parser.error('Live account credentials are local-only; never upload the .env to CI')
    selected = {}
    allowed = {'FILEN_LOGIN', 'FILEN_PW', 'INTERNXT_LOGIN_TESTS', 'INTERNXT_PW_TESTS'}
    for line in args.env_file.read_text().splitlines():
        line = line.strip()
        if line.startswith('export '):
            line = line[7:]
        key, separator, value = line.partition('=')
        key = key.strip()
        if not separator or key not in allowed:
            continue
        parts = shlex.split(value, comments=True, posix=True)
        selected[key] = ' '.join(parts)
    environment = dict(os.environ, CRISPER_RUN_LIVE_CLOUD='1')
    for kind, login, password in [('FILEN', 'FILEN_LOGIN', 'FILEN_PW'),
                                   ('INTERNXT', 'INTERNXT_LOGIN_TESTS', 'INTERNXT_PW_TESTS')]:
        if args.provider != 'all' and args.provider != kind.lower():
            continue
        if not selected.get(login) or not selected.get(password):
            parser.error(f'Missing {kind} test credential variables in the selected local file')
        environment[f'CRISPER_{kind}_LOGIN'] = selected[login]
        environment[f'CRISPER_{kind}_PASSWORD'] = selected[password]
    command = ['flutter', 'test', '--no-pub', 'test/live/cloud_accounts_test.dart', '--reporter', 'expanded']
    if args.provider != 'all':
        command += ['--plain-name', args.provider + ' real account']
    subprocess.run(command, env=environment, check=True)


if __name__ == '__main__':
    main()
