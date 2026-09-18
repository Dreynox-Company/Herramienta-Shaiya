"""Offline safeguards for the user-authorized, exact-commit build handoff."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import cloud_build as cloud
import publish_release as release

SHA = 'a' * 40
BRANCH = 'feat/studio-04-20260917-abc123'

class CloudDeliveryTest(unittest.TestCase):
    def receipt(self):
        return {'version': cloud.VERSION, 'repository': cloud.REPOSITORY,
                'branch': BRANCH, 'commit': SHA}

    def run_info(self, sha=SHA, **kwargs):
        return {'head_sha': sha, 'head_branch': BRANCH, 'event': 'push',
                'path': '.github/workflows/build.yml', 'id': 100, **kwargs}

    def release_info(self):
        tag = cloud.release_tag(SHA)
        return {'tag_name': tag, 'draft': False, 'assets': [
            {'name': name, 'size': 100, 'browser_download_url':
                f'https://github.com/{cloud.REPOSITORY}/releases/download/{tag}/{name}'}
            for name in cloud.EXPECTED_OUTPUTS | {'compilacion-verificada.json'}
        ]}

    def proof(self):
        return {'version': cloud.VERSION, 'repository': cloud.REPOSITORY,
                'workflow_run': 100, 'commit': SHA,
                'sha256': {name: 'b'*64 for name in cloud.EXPECTED_OUTPUTS}}

    def test_selects_only_exact_commit_push_workflow(self):
        data = {'workflow_runs': [self.run_info('b'*40, id=200), self.run_info(),
                                 self.run_info(event='pull_request', id=300)]}
        self.assertEqual(cloud.choose_run(data, SHA, BRANCH)['id'], 100)

    def test_no_old_run_when_current_not_created(self):
        self.assertIsNone(cloud.choose_run({'workflow_runs': [self.run_info('b'*40)]}, SHA, BRANCH))

    def test_changed_receipt_repo_or_sha_or_branch_rejected(self):
        for field, value in [('repository', 'someone/else'), ('commit', 'main'),
                             ('branch', 'main'), ('version', '0.2')]:
            receipt = self.receipt(); receipt[field] = value
            with self.subTest(field=field), self.assertRaises(RuntimeError):
                cloud.validate_receipt(receipt)

    def test_cancellation_never_clones_or_pushes(self):
        with patch.object(cloud.publish_sources, 'verified_sources', return_value={}), \
                patch.object(cloud.shutil, 'which', return_value='git'), \
                patch('builtins.input', return_value='NO'), \
                patch.object(cloud.subprocess, 'run') as run:
            with self.assertRaisesRegex(RuntimeError, 'cancelada'):
                cloud.publish_new()
            run.assert_not_called()

    def test_failed_build_does_not_download(self):
        run = self.run_info(status='completed', conclusion='failure')
        with patch.object(cloud, 'get_json', return_value={'workflow_runs': [run]}), \
                patch.object(cloud, 'download') as download:
            with tempfile.TemporaryDirectory() as temp, self.assertRaisesRegex(RuntimeError, 'no terminó'):
                cloud.wait_and_download(self.receipt(), 5, Path(temp))
            download.assert_not_called()

    def test_release_needs_all_outputs(self):
        data = self.release_info(); data['assets'].pop()
        with self.assertRaisesRegex(RuntimeError, 'ambos binarios'):
            cloud.validate_release(data, SHA)

    def test_release_cannot_link_to_other_repository(self):
        data = self.release_info()
        data['assets'][0]['browser_download_url'] = 'https://github.com/someone/else/releases/download/abc/a.zip'
        with self.assertRaisesRegex(RuntimeError, 'no pertenece'):
            cloud.validate_release(data, SHA)

    def test_safe_release_is_accepted(self):
        self.assertEqual(set(cloud.validate_release(self.release_info(), SHA)),
                         cloud.EXPECTED_OUTPUTS | {'compilacion-verificada.json'})

    def test_download_does_not_accept_cleartext_or_credentials(self):
        for url in ['http://github.com/a/b', 'https://token@github.com/a/b', 'https://github.com.evil.test/a']:
            with self.subTest(url=url), self.assertRaises(RuntimeError):
                cloud.safe_url(url)

    def test_proof_must_match_both_commit_and_run(self):
        for field, value in [('commit','b'*40), ('workflow_run', 99), ('version','0.2')]:
            proof = self.proof(); proof[field] = value
            with self.subTest(field=field), self.assertRaises(RuntimeError):
                cloud.validate_proof(proof,SHA,100)

    def test_proof_cannot_omit_android_hash(self):
        proof=self.proof(); proof['sha256'].pop(next(iter(proof['sha256'])))
        with self.assertRaises(RuntimeError):
            cloud.validate_proof(proof, SHA, 100)

    def test_zip_traversal_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            file = Path(temp)/'test.zip'
            with zipfile.ZipFile(file, 'w') as z: z.writestr('../DATA/overwrite', 'bad')
            with self.assertRaisesRegex(RuntimeError, 'Ruta no segura'):
                cloud.verify_archive(file, windows=True)

    def test_windows_package_requires_compiled_app_and_native_runtime(self):
        with tempfile.TemporaryDirectory() as temp:
            file = Path(temp)/'test.zip'
            with zipfile.ZipFile(file, 'w') as z: z.writestr('herramienta_shaiya.exe', b'MZ-test')
            with self.assertRaisesRegex(RuntimeError, 'completa'):
                cloud.verify_archive(file, windows=True)

    def test_release_program_cannot_publish_from_local_machine(self):
        with self.assertRaises(RuntimeError): release.validate_environment({})

    def test_release_program_rejects_pr_and_main(self):
        env={'GITHUB_ACTIONS':'true', 'GITHUB_EVENT_NAME':'push',
             'GITHUB_REPOSITORY':release.REPOSITORY, 'GITHUB_SHA':SHA,
             'GITHUB_REF':'refs/heads/'+BRANCH, 'GITHUB_RUN_ID':'100'}
        self.assertEqual(release.validate_environment(env), (SHA,100,cloud.release_tag(SHA)))
        for change in [{'GITHUB_EVENT_NAME':'pull_request'}, {'GITHUB_REF':'refs/heads/main'},
                       {'GITHUB_REPOSITORY':'else/project'}]:
            with self.subTest(change=change), self.assertRaises(RuntimeError):
                release.validate_environment({**env, **change})

if __name__ == '__main__': unittest.main()
