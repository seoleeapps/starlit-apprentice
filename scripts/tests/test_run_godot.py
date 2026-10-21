"""실제 자식 프로세스로 Godot gate의 세 가지 실패 모드를 재현한다."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

RUNNER = Path(__file__).resolve().parents[1] / 'run_godot.py'


class GodotGateTest(unittest.TestCase):
    def call_runner(self, source, timeout='5'):
        with tempfile.TemporaryDirectory() as base:
            log = Path(base) / 'process.log'
            result = subprocess.run([sys.executable, str(RUNNER), '--log', str(log),
                                     '--timeout', timeout, '--', sys.executable, '-c', source],
                                    capture_output=True, text=True, timeout=15)
            return result.returncode, log.read_text(), Path(str(log) + '.clean').read_text()

    def test_exit_zero_with_colored_engine_error_fails(self):
        status, raw, clean = self.call_runner("print('\\x1b[31mSCRIPT ERROR: parse failed\\x1b[0m')")
        self.assertNotEqual(status, 0)
        self.assertIn('\x1b[31m', raw)
        self.assertEqual(clean.strip(), 'SCRIPT ERROR: parse failed')

    def test_timeout_cannot_report_pass(self):
        status, _, _ = self.call_runner('import time; time.sleep(30)', '0.1')
        self.assertEqual(status, 124)

    def test_success_has_isolated_save_directory(self):
        status, raw, _ = self.call_runner("import os; from pathlib import Path; p=Path(os.environ['STARLIT_SAVE_DIR']); print('ISOLATED' if p.is_dir() and 'starlit-test-' in p.name else 'ERROR: unisolated')")
        self.assertEqual(status, 0)
        self.assertIn('ISOLATED', raw)


if __name__ == '__main__':
    unittest.main()
