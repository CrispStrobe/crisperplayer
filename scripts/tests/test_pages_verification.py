import os
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import verify_pages_source as pages


class PagesVerificationTests(unittest.TestCase):
    def setUp(self):
        self.environment = patch.dict(os.environ, {
            'GITHUB_REF': 'refs/heads/master', 'GITHUB_REPOSITORY': 'CrispStrobe/crisperplayer'})
        self.environment.start()
        self.addCleanup(self.environment.stop)
        self.run = {'path': '.github/workflows/pages.yml', 'head_branch': 'master',
                    'head_repository': {'full_name': 'CrispStrobe/crisperplayer'}, 'head_sha': 'a' * 40,
                    'status': 'completed', 'conclusion': 'cancelled'}
        self.jobs = {'jobs': [{'name': 'build', 'conclusion': 'success',
                              'steps': [{'name': 'Run npm test', 'conclusion': 'success'}]}]}

    def test_completed_browser_checks_can_be_reused_after_deployment_cancellation(self):
        with patch.object(pages, 'api', side_effect=[self.run, self.jobs]), \
                patch.object(pages.subprocess, 'run'):
            pages.verify('123')

    def test_successful_build_without_successful_browser_tests_is_rejected(self):
        self.jobs['jobs'][0]['steps'][0]['conclusion'] = 'skipped'
        with patch.object(pages, 'api', side_effect=[self.run, self.jobs]):
            with self.assertRaisesRegex(ValueError, 'not passed'):
                pages.verify('123')

    def test_changed_website_or_test_inputs_cannot_be_published(self):
        with patch.object(pages, 'api', side_effect=[self.run, self.jobs]), \
                patch.object(pages.subprocess, 'run', side_effect=subprocess.CalledProcessError(1, 'git diff')):
            with self.assertRaises(subprocess.CalledProcessError):
                pages.verify('123')

    def test_fork_or_non_master_source_is_rejected(self):
        self.run['head_repository']['full_name'] = 'other/repository'
        with patch.object(pages, 'api', return_value=self.run):
            with self.assertRaisesRegex(ValueError, 'master Pages workflow'):
                pages.verify('123')
        self.run['head_repository']['full_name'] = 'CrispStrobe/crisperplayer'
        self.run['head_branch'] = 'feature'
        with patch.object(pages, 'api', return_value=self.run):
            with self.assertRaises(ValueError):
                pages.verify('123')

    def test_invalid_id_and_non_master_target_are_rejected_before_api_access(self):
        with patch.object(pages, 'api') as api:
            with self.assertRaises(ValueError):
                pages.verify('../other')
            with patch.dict(os.environ, {'GITHUB_REF': 'refs/heads/feature'}):
                with self.assertRaises(ValueError):
                    pages.verify('123')
            api.assert_not_called()
