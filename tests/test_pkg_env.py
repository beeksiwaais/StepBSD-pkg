import io
import os
import pathlib
import subprocess
import tarfile
import tempfile
import unittest

HELPER = pathlib.Path(__file__).resolve().parents[1] / 'scripts/pkg-env.sh'


class PackageEnvironmentTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.work = self.root / 'work with spaces'
        self.repo = self.root / 'repository with spaces'
        self.repo.mkdir()
        self.write_command('uname', 'printf "%s\\n" "$TEST_HOST"')
        self.write_command('pkg', 'echo "host pkg must not be used" >&2; exit 99')

    def write_command(self, name, content):
        path = self.bin / name
        path.write_text('#!/bin/sh\n' + content + '\n')
        path.chmod(0o755)

    def archive(self, path, abi='NextBSD:27:amd64', bootstrap=False, wrong_tool=False):
        body = ('#!/bin/sh\n'
                'test "$1" = -C || exit 91\n'
                'test ! -s "$2" || exit 92\n'
                'shift 2\n'
                'case "$1" in\n'
                'config) printf "%s\\n" "' + ('FreeBSD:15:amd64' if wrong_tool else '${ABI}') + '" ;;\n'
                'query) case "$4" in %n) echo pkg ;; %q) echo "' + abi + '" ;; *) exit 93 ;; esac ;;\n'
                '*) exit 94 ;;\nesac\n').encode()
        with tarfile.open(path, 'w:gz') as output:
            member = tarfile.TarInfo('./usr/sbin/pkg-static' if bootstrap else '/usr/sbin/pkg-static')
            member.mode = 0o500
            member.size = len(body)
            output.addfile(member, io.BytesIO(body))

    def run_shell(self, commands, host='amd64', **extra):
        env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'],
                   TEST_HOST=host, TEST_REPO=str(self.repo), TEST_WORK=str(self.work),
                   HELPER=str(HELPER))
        env.pop('STEPBSD_PKG_HOST_REPO', None)
        env.update(extra)
        return subprocess.run(['/bin/sh', '-eu', '-c', '. "$HELPER"\n' + commands],
                              env=env, capture_output=True, text=True)

    def test_target_metadata_does_not_change_compiler_target(self):
        for arch, suffix in [('amd64', 'amd64'), ('x86_64', 'amd64'),
                             ('arm64', 'aarch64'), ('aarch64', 'aarch64')]:
            result = self.run_shell('TARGET_TRIPLE=keep-freebsd-toolchain; stepbsd_pkg_target ' + arch +
                                    '; printf "%s %s %s" "$ABI" "$OSVERSION" "$TARGET_TRIPLE"')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, f'NextBSD:27:{suffix} 2700000 keep-freebsd-toolchain')

    def test_unknown_architecture_is_rejected(self):
        self.assertNotEqual(self.run_shell('stepbsd_pkg_target invalid').returncode, 0)

    def test_bootstrap_uses_build_host_architecture_and_checks_abi(self):
        for host in ['amd64', 'arm64']:
            with self.subTest(host=host):
                bootstrap = self.root / f'{host}.tar.gz'
                self.archive(bootstrap, bootstrap=True)
                self.write_command('fetch', 'test "$1" = -o; printf "%s" "$3" > "$TEST_URL"; cp "$TEST_BOOTSTRAP" "$2"')
                result = self.run_shell('stepbsd_pkg_target arm64; stepbsd_pkg_bootstrap "$TEST_WORK"',
                                        host=host, TEST_BOOTSTRAP=str(bootstrap), TEST_URL=str(self.root / 'url'),
                                        TEST_WORK=str(self.root / host))
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertTrue((self.root / 'url').read_text().endswith(f'nextbsd-contrib-pkg-{host}.tar.gz'))

    def test_own_package_works_without_host_pkg_and_with_spaces(self):
        self.archive(self.repo / 'pkg-2.8.4_3.pkg')
        result = self.run_shell('stepbsd_pkg_target amd64; stepbsd_pkg_from_repository "$TEST_REPO" "$TEST_WORK"')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_old_archive_is_rejected(self):
        self.archive(self.repo / 'pkg-2.8.4_2.pkg', abi='FreeBSD:15:amd64')
        result = self.run_shell('stepbsd_pkg_target amd64; stepbsd_pkg_from_repository "$TEST_REPO" "$TEST_WORK"')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('rebuild', result.stderr)

    def test_old_tool_is_rejected(self):
        self.archive(self.repo / 'pkg-2.8.4_2.pkg', wrong_tool=True)
        result = self.run_shell('stepbsd_pkg_target amd64; stepbsd_pkg_from_repository "$TEST_REPO" "$TEST_WORK"')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('cannot handle target ABI', result.stderr)

    def test_missing_and_ambiguous_packages_are_rejected(self):
        script = 'stepbsd_pkg_target amd64; stepbsd_pkg_from_repository "$TEST_REPO" "$TEST_WORK"'
        self.assertNotEqual(self.run_shell(script).returncode, 0)
        self.archive(self.repo / 'pkg-1.pkg')
        self.archive(self.repo / 'pkg-2.pkg')
        self.assertNotEqual(self.run_shell(script).returncode, 0)

    def test_cross_target_requires_explicit_native_tool(self):
        self.archive(self.repo / 'pkg-2.8.4_3.pkg', abi='NextBSD:27:aarch64')
        script = 'stepbsd_pkg_target arm64; stepbsd_pkg_metadata_tool "$TEST_REPO" "$TEST_WORK"'
        result = self.run_shell(script)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('STEPBSD_PKG_HOST_REPO', result.stderr)
        native = self.root / 'native'
        native.mkdir()
        self.archive(native / 'pkg-2.8.4_3.pkg')
        result = self.run_shell(script, STEPBSD_PKG_HOST_REPO=str(native))
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main()
