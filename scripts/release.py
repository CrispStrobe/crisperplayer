#!/usr/bin/env python3
"""Validate release tags and package complete native app/CLI bundles."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PLATFORMS = ('windows-x64', 'linux-x64', 'macos-arm64', 'macos-x64')


def release_info(tag, root=ROOT):
    match = re.search(r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$', (root / 'pubspec.yaml').read_text(), re.M)
    if not match or tag != f'v{match[1]}+{match[2]}':
        raise ValueError('Release tag must exactly match pubspec.yaml, for example v0.1.0+13.')
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
    return {'tag': tag, 'version': match[1], 'build': match[2], 'revision': revision}


def notices(target):
    target.mkdir(parents=True, exist_ok=True)
    for source in (ROOT / 'assets/licenses').glob('*.txt'):
        shutil.copy2(source, target / source.name)
    config = ROOT / '.dart_tool/package_config.json'
    if config.exists():
        from urllib.parse import urljoin, urlparse
        from urllib.request import url2pathname
        row = next(p for p in json.loads(config.read_text())['packages'] if p['name'] == 'crisp_storage')
        storage = Path(url2pathname(urlparse(urljoin(config.resolve().as_uri(), row['rootUri'] + '/')).path))
        shutil.copy2(storage / 'NOTICE-LIBSMB2.txt', target / 'NOTICE-LIBSMB2.txt')
    else:
        raise ValueError('Run flutter pub get before packaging licenses.')
    if (ROOT / 'LICENSE').exists():
        shutil.copy2(ROOT / 'LICENSE', target / 'CrisperPlayer-LICENSE.txt')


def archive(directory, destination, platform):
    if platform.startswith('macos'):
        subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(directory), str(destination)], check=True)
    elif destination.name.endswith('.tar.gz'):
        with tarfile.open(destination, 'w:gz') as output:
            output.add(directory, arcname=directory.name)
    else:
        with zipfile.ZipFile(destination, 'w', zipfile.ZIP_DEFLATED) as output:
            for path in sorted(directory.rglob('*')):
                if path.is_file():
                    output.write(path, path.relative_to(directory.parent))


def package(platform, app, cli, output, info):
    if platform not in PLATFORMS:
        raise ValueError('Unknown release platform.')
    executable = 'crisperplayer.exe' if platform == 'windows-x64' else 'crisperplayer'
    if not app.is_dir() or not (cli / 'bin' / executable).is_file():
        raise ValueError('App and compiled CLI bundles must exist before packaging.')
    expected = app / executable
    if platform.startswith('macos'):
        expected = app / 'Contents/MacOS/crisperplayer'
    if not expected.is_file():
        raise ValueError(f'Missing native application executable: {expected}')
    output.mkdir(parents=True, exist_ok=True)
    extension = '.tar.gz' if platform.startswith('linux') else '.zip'
    with tempfile.TemporaryDirectory(prefix='crisper-release-') as temporary:
        stage = Path(temporary) / 'CrisperPlayer'
        if platform.startswith('macos'):
            shutil.copytree(app, stage / app.name, symlinks=True)
        else:
            shutil.copytree(app, stage, symlinks=True)
        shutil.copytree(cli, stage / 'cli', symlinks=True)
        notices(stage / 'licenses')
        (stage / 'BUILD.json').write_text(json.dumps(info, indent=2) + '\n')
        (stage / 'README-START.txt').write_text(
            f"CrisperPlayer {info['version']} build {info['build']} ({info['revision']})\n\n"
            'Keep this entire directory together: the executable needs its bundled libraries and data.\n'
            'The CLI is in cli/bin/ and controls the running desktop app.\n'
            'Linux requires system libmpv, GTK, libsecret and their runtime dependencies.\n'
            'Windows builds are unsigned. Mac builds are ad-hoc signed, not notarized.\n'
            'Installation: https://github.com/CrispStrobe/crisperplayer/blob/master/docs/RELEASES.md\n')
        archive(stage, output / f'CrisperPlayer-{platform}{extension}', platform)
        cli_stage = Path(temporary) / 'CrisperPlayer-CLI'
        shutil.copytree(cli, cli_stage, symlinks=True)
        notices(cli_stage / 'licenses')
        (cli_stage / 'BUILD.json').write_text(json.dumps(info, indent=2) + '\n')
        archive(cli_stage, output / f'CrisperPlayer-cli-{platform}{extension}', platform)


def checksums(directory):
    required = {'CrisperPlayer-android.apk'}
    for platform in PLATFORMS:
        extension = '.tar.gz' if platform.startswith('linux') else '.zip'
        required |= {f'CrisperPlayer-{platform}{extension}', f'CrisperPlayer-cli-{platform}{extension}'}
    missing = required - {p.name for p in directory.iterdir() if p.is_file()}
    if missing:
        raise ValueError(f'Refusing to publish an incomplete release: {sorted(missing)}')
    lines = []
    for path in sorted(directory.iterdir()):
        if path.is_file() and path.name != 'SHA256SUMS.txt':
            with path.open('rb') as source:
                digest = hashlib.sha256()
                for block in iter(lambda: source.read(1024 * 1024), b''):
                    digest.update(block)
                digest = digest.hexdigest()
            lines.append(f'{digest}  {path.name}')
    (directory / 'SHA256SUMS.txt').write_text('\n'.join(lines) + '\n')



def should_be_latest(tag, current):
    def version(value):
        match = re.fullmatch(r'v(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?', value)
        if not match:
            raise ValueError('Cannot compare release tag: ' + value)
        return tuple(int(part or 0) for part in match.groups())
    return not current or version(tag) >= version(current)


def publish(tag, directory):
    release_info(tag)
    checksums(directory)
    latest = subprocess.run(['gh', 'api', 'repos/{owner}/{repo}/releases/latest'],
                            capture_output=True, text=True)
    if latest.returncode and '(HTTP 404)' not in latest.stderr:
        raise RuntimeError('Could not determine the current latest release; publication stopped.')
    current = json.loads(latest.stdout)['tag_name'] if latest.returncode == 0 else ''
    make_latest = should_be_latest(tag, current)
    subprocess.run(['gh', 'release', 'upload', tag, *[str(p) for p in sorted(directory.iterdir()) if p.is_file()], '--clobber'], check=True)
    subprocess.run(['gh', 'release', 'edit', tag, '--draft=false',
                    '--latest=' + str(make_latest).lower(), '--notes-file', str(ROOT / 'docs/RELEASE_NOTES.md')], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    validate = commands.add_parser('validate')
    validate.add_argument('tag')
    build = commands.add_parser('package')
    build.add_argument('--tag', required=True)
    build.add_argument('--platform', choices=PLATFORMS, required=True)
    build.add_argument('--app', type=Path, required=True)
    build.add_argument('--cli', type=Path, default=Path('build/cli/bundle'))
    build.add_argument('--output', type=Path, default=Path('dist'))
    publish_command = commands.add_parser('publish')
    publish_command.add_argument('--tag', required=True)
    publish_command.add_argument('--directory', type=Path, required=True)
    check = commands.add_parser('checksums')
    check.add_argument('directory', type=Path)
    args = parser.parse_args()
    if args.command == 'validate':
        info = release_info(args.tag)
        print(json.dumps(info))
        if os.environ.get('GITHUB_OUTPUT'):
            with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
                for key, value in info.items():
                    output.write(f'{key}={value}\n')
    elif args.command == 'package':
        package(args.platform, args.app.resolve(), args.cli.resolve(), args.output.resolve(), release_info(args.tag))
    elif args.command == 'publish':
        publish(args.tag, args.directory)
    else:
        checksums(args.directory)


if __name__ == '__main__':
    main()
