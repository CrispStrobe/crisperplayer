import io
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest

from scripts import smoke_desktop_audio

sys.path.insert(0, str(Path(__file__).parents[1]))
try:
    from scripts import build_linux_audio as build
finally:
    sys.path.pop(0)


class LinuxAudioCandidateTest(unittest.TestCase):
    def test_recipe_has_no_automatic_dependency_downloads_or_gpl_flags(self):
        commands = build.build_commands({name: Path('/source') / name for name in ('ffmpeg', 'mpv', 'libass', 'libplacebo')}, Path('/output'), 2)
        configure = commands[0]['argv']
        for required in ('--disable-gpl', '--disable-nonfree', '--disable-version3', '--disable-autodetect', '--disable-everything', '--disable-static', '--enable-shared'):
            self.assertIn(required, configure)
        self.assertNotIn('--enable-gpl', configure)
        self.assertNotIn('--enable-nonfree', configure)
        meson_setup = [item['argv'] for item in commands if item['argv'][:2] == ['meson', 'setup']]
        self.assertEqual(len(meson_setup), 3)
        for argv in meson_setup:
            self.assertIn('--wrap-mode=nofallback', argv)
            self.assertIn('-Dauto_features=disabled', argv)
            self.assertIn('-Ddefault_library=shared', argv)
        self.assertIn('-Dgpl=false', meson_setup[-1])
        self.assertIn('-Drubberband=disabled', meson_setup[-1])

    def test_cached_source_tampering_is_rejected_before_build(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'source.tar.gz'
            path.write_bytes(b'changed upstream archive')
            with self.assertRaisesRegex(ValueError, 'Cached source hash mismatch'):
                build.download({'id': 'source', 'url': 'https://example.invalid/unused', 'sha256': '0' * 64}, path)

    def test_source_archive_cannot_write_outside_its_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            archive = directory / 'bad.tar'
            with tarfile.open(archive, 'w') as output:
                entry = tarfile.TarInfo('../escape')
                entry.size = 4
                output.addfile(entry, io.BytesIO(b'oops'))
            with self.assertRaises(tarfile.FilterError):
                build.extract(archive, directory / 'unpacked')
            self.assertFalse((directory / 'escape').exists())

    def test_pcm_measurement_reports_real_fixture_timing_and_pitch(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'tone.wav'
            smoke_desktop_audio.fixture(path)
            duration, pitch = smoke_desktop_audio.pcm_measurements(path)
            self.assertAlmostEqual(duration, 6)
            self.assertAlmostEqual(pitch, 440, delta=1)

    def test_native_smoke_options_match_media_kit_rate_and_pitch_contract(self):
        automatic = smoke_desktop_audio.render_options(Path('/output/tone.wav'), 1.5, 'automatic')
        self.assertEqual(automatic['speed'], '1.5')
        self.assertEqual(automatic['audio-pitch-correction'], 'yes')
        self.assertNotIn('af', automatic)
        legacy = smoke_desktop_audio.render_options(Path('/output/tone.wav'), 1.5, 'legacy_scaletempo')
        self.assertEqual(legacy['speed'], '1.0')
        self.assertEqual(legacy['audio-pitch-correction'], 'no')
        self.assertEqual(legacy['af'], 'scaletempo:scale=1.50000000')

    def test_portable_filters_use_mpv_speed_and_preserve_its_source_clock(self):
        for engine in ('sonic', 'wsola', 'signalsmith', 'bungee'):
            options = smoke_desktop_audio.render_options(Path('/output/tone.wav'), 2.5, engine)
            self.assertEqual(options['speed'], '2.5')
            self.assertEqual(options['audio-pitch-correction'], 'yes')
            self.assertEqual(options['af'], f'crisperdsp=engine={engine}')
        atempo = smoke_desktop_audio.render_options(Path('/output/tone.wav'), 1.75, 'atempo')
        self.assertEqual(atempo['speed'], '1.75')
        self.assertEqual(atempo['af'], 'lavfi-tempo=filter=atempo')

    def test_windows_recipe_builds_its_own_lgpl_ffmpeg_and_uses_wasapi(self):
        commands = build.build_commands({name: Path('/source') / name for name in ('ffmpeg', 'mpv', 'libass', 'libplacebo')}, Path('/output'), 2, 'windows')
        configure = commands[0]['argv']
        self.assertEqual(configure[0], 'bash')
        self.assertIn('--disable-gpl', configure)
        self.assertIn('--enable-w32threads', configure)
        self.assertIn('--disable-pthreads', configure)
        mpv = [entry['argv'] for entry in commands if entry['argv'][:2] == ['meson', 'setup']][-1]
        self.assertIn('-Dwasapi=enabled', mpv)
        self.assertIn('-Dgpl=false', mpv)
        self.assertNotIn('-Dalsa=enabled', mpv)
        self.assertNotIn('-Dpulse=enabled', mpv)

    def test_pcm_measurement_rejects_non_audio_output(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'tone.wav'
            path.write_bytes(b'a native process wrote an error message')
            with self.assertRaisesRegex(ValueError, 'not a RIFF WAVE file'):
                smoke_desktop_audio.pcm_measurements(path)


if __name__ == '__main__':
    unittest.main()
