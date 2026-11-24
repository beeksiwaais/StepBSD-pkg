import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / 'scripts/verify-stage.py'


class StageToolTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.stage = self.root / 'stage'
        self.sysroot = self.root / 'sysroot'
        self.stage.mkdir()
        self.sysroot.mkdir()
        self.config = self.root / 'pkg.conf'
        self.config.write_text('')
        self.tool = self.root / 'selected-pkg'
        self.tool.write_text('#!/bin/sh\ntest "$1" = -C || exit 91\nprintf "%s\\n" /System/base-owned\n')
        self.tool.chmod(0o755)

    def verify(self, select=True):
        env = os.environ.copy()
        env.pop('STEPBSD_PKG_TOOL', None)
        env.pop('STEPBSD_PKG_CONFIG', None)
        if select:
            env.update(STEPBSD_PKG_TOOL=str(self.tool), STEPBSD_PKG_CONFIG=str(self.config))
        return subprocess.run([sys.executable, str(SCRIPT), str(self.stage), str(self.sysroot), 'pkg'],
                              env=env, capture_output=True, text=True)

    def test_no_fallback_to_the_host_package_manager(self):
        result = self.verify(select=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('selected ABI-aware package tool', result.stderr)

    def test_selected_tool_preserves_ownership_checks(self):
        self.assertEqual(self.verify().returncode, 0)
        (self.stage / 'System').mkdir()
        (self.stage / 'System/base-owned').write_text('collision')
        result = self.verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('would overwrite a base-owned file', result.stderr)


if __name__ == '__main__':
    unittest.main()
