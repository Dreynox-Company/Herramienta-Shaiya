import importlib.util
import io
import json
import pathlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('build_diagnostics', pathlib.Path(__file__).resolve().parents[1] / 'build_diagnostics.py')
build = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(build)


class BuildDiagnosticsTests(unittest.TestCase):
    def test_pinned_sdk_and_dart_revision_accepted(self):
        build.validate_toolchain({'frameworkVersion': '3.47.4', 'dartSdkVersion': '3.14.1 (stable)'})

    def test_old_sdk_refused_before_pub(self):
        with self.assertRaisesRegex(RuntimeError, 'SDK incompatible'):
            build.validate_toolchain({'frameworkVersion': '3.41.6', 'dartSdkVersion': '3.11.4'})

    def test_classifier_distinguishes_network_and_solver(self):
        self.assertEqual(build.classify_pub_failure('SocketException: Failed host lookup'), 'network-or-download')
        self.assertEqual(build.classify_pub_failure('The current Dart SDK version is 3.11.4'), 'sdk-incompatible')
        self.assertEqual(build.classify_pub_failure('Cannot satisfy --enforce-lockfile'), 'dependency-resolution')
        self.assertEqual(build.classify_pub_failure('A different error'), 'unclassified-see-original-diagnostic')

    def test_failed_pub_preserves_original_diagnostic_and_exit(self):
        class Process:
            stdout = iter(['Resolving dependencies...\n', 'Version solving failed: fixture incompatibility.\n'])
            def wait(self): return 65
        with tempfile.TemporaryDirectory() as td:
            path = pathlib.Path(td) / 'build.log'
            with path.open('w') as log, patch.object(subprocess, 'Popen', return_value=Process()), patch('sys.stdout', new=io.StringIO()):
                with self.assertRaisesRegex(RuntimeError, 'fixture incompatibility'):
                    build.run_logged(['flutter','pub','get','--enforce-lockfile'], cwd=path.parent, log=log, log_path=path)
            failure = json.loads(path.with_suffix('.failure.json').read_text())
            self.assertEqual(failure['exitCode'],65)
            self.assertIn('fixture incompatibility',failure['diagnosticTail'])
            self.assertFalse(failure['success'])

    def test_success_does_not_generate_failure_report(self):
        class Process:
            stdout = iter(['Got dependencies!\n'])
            def wait(self): return 0
        with tempfile.TemporaryDirectory() as td:
            path = pathlib.Path(td) / 'build.log'
            with path.open('w') as log, patch.object(subprocess, 'Popen', return_value=Process()), patch('sys.stdout', new=io.StringIO()):
                build.run_logged(['flutter','pub','get'], cwd=path.parent, log=log, log_path=path)
            self.assertFalse(path.with_suffix('.failure.json').exists())


if __name__ == '__main__': unittest.main()
