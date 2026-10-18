#!/usr/bin/env python3
"""Allow a Pages deployment retry only for unchanged, already-tested website inputs."""
import json
import os
import re
import subprocess
import sys

INPUTS = ['site', 'tests/web', 'package.json', 'package-lock.json',
          'playwright.config.js', 'scripts/serve_site.js']


def api(path):
    return json.loads(subprocess.check_output(['gh', 'api', path], text=True))


def verify(run_id):
    if not re.fullmatch(r'[0-9]+', run_id):
        raise ValueError('Use a numeric Pages run ID.')
    repository = os.environ.get('GITHUB_REPOSITORY', 'CrispStrobe/crisperplayer')
    if os.environ.get('GITHUB_REF', 'refs/heads/master') != 'refs/heads/master':
        raise ValueError('Deployments must use master.')
    run = api(f'repos/{repository}/actions/runs/{run_id}')
    if (run['path'] != '.github/workflows/pages.yml' or
            run['head_branch'] != 'master' or
            run['head_repository']['full_name'].lower() != repository.lower()):
        raise ValueError('The source must be this repository\'s master Pages workflow.')
    jobs = api(f'repos/{repository}/actions/runs/{run_id}/jobs?per_page=100')['jobs']
    if not any(job['name'] == 'build' and job['conclusion'] == 'success' for job in jobs):
        raise ValueError('The browser build and checks have not passed.')
    revision = run['head_sha']
    if not re.fullmatch(r'[0-9a-f]{40}', revision):
        raise ValueError('Invalid verified revision.')
    subprocess.run(['git', 'diff', '--exit-code', revision, 'HEAD', '--', *INPUTS], check=True)
    print('Verified: website and browser-test inputs match successful Pages run ' + run_id)


if __name__ == '__main__':
    verify(sys.argv[1])
