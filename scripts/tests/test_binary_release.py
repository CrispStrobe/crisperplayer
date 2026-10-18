import hashlib
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import release

class BinaryReleaseTests(unittest.TestCase):
    def test_older_build_cannot_replace_a_newer_latest_release(self):
        self.assertFalse(release.should_be_latest('v0.1.0+13', 'v0.1.0+14'))
        self.assertTrue(release.should_be_latest('v0.1.0+14', 'v0.1.0'))
        self.assertTrue(release.should_be_latest('v0.2.0+15', 'v0.1.0+99'))
        self.assertTrue(release.should_be_latest('v0.1.0+14', ''))
        with self.assertRaises(ValueError):
            release.should_be_latest('v0.1.0+14', 'unversioned')

    def test_rejects_mistagged_build(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'pubspec.yaml').write_text('version: 0.1.0+13\n')
            with self.assertRaisesRegex(ValueError, 'exactly match'):
                release.release_info('v0.1.0', root)
            with patch.object(release.subprocess, 'check_output', return_value='revision\n'):
                self.assertEqual(release.release_info('v0.1.0+13', root)['build'], '13')

    def test_refuses_incomplete_release_and_hashes_every_asset(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with self.assertRaisesRegex(ValueError, 'incomplete'):
                release.checksums(root)
            names = ['CrisperPlayer-android.apk']
            for platform in release.PLATFORMS:
                ext = '.tar.gz' if platform.startswith('linux') else '.zip'
                names += [f'CrisperPlayer-{platform}{ext}', f'CrisperPlayer-cli-{platform}{ext}']
            for name in names:
                (root / name).write_bytes(name.encode())
            release.checksums(root)
            lines = (root / 'SHA256SUMS.txt').read_text().splitlines()
            self.assertEqual(len(lines), 9)
            for line in lines:
                digest, name = line.split('  ')
                self.assertEqual(digest, hashlib.sha256((root / name).read_bytes()).hexdigest())

    def test_linux_bundle_keeps_libraries_data_cli_and_symlinks(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); app = root / 'app'; cli = root / 'cli'
            for relative in ['crisperplayer', 'lib/libengine.so', 'data/flutter_assets/asset']:
                path = app / relative; path.parent.mkdir(parents=True, exist_ok=True); path.write_text(relative)
            (app / 'lib/alias.so').symlink_to('libengine.so')
            (cli / 'bin').mkdir(parents=True); (cli / 'bin/crisperplayer').write_text('cli')
            def notice(target):
                target.mkdir(); (target / 'LICENSE.txt').write_text('notice')
            with patch.object(release, 'notices', side_effect=notice):
                release.package('linux-x64', app, cli, root / 'out', {'version':'0.1.0','build':'13','revision':'commit'})
            with tarfile.open(root / 'out/CrisperPlayer-linux-x64.tar.gz') as archive:
                self.assertTrue(archive.getmember('CrisperPlayer/lib/alias.so').issym())
                for name in ['lib/libengine.so', 'data/flutter_assets/asset', 'cli/bin/crisperplayer', 'BUILD.json', 'licenses/LICENSE.txt']:
                    self.assertIsNotNone(archive.getmember('CrisperPlayer/' + name))
