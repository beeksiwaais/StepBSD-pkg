import hashlib
import importlib.util
import io
import pathlib
import tarfile
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location("sources", pathlib.Path(__file__).resolve().parents[1] / "scripts/sources.py")
sources = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(sources)


class SourceIntegrityTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = pathlib.Path(self.temporary.name)
        self.cache = self.root / "cache"
        self.cache.mkdir()

    def archive(self, member="upstream/file", digest_override=None):
        archive = self.root / "upstream.tar.gz"
        with tarfile.open(archive, "w:gz") as output:
            info = tarfile.TarInfo(member)
            info.size = 4
            output.addfile(info, io.BytesIO(b"test"))
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        pinned = digest_override or digest
        (self.root / "sources.lock").write_text(f"example 1 {pinned} https://example.com/upstream.tar.gz\n")
        cached = self.cache / f"example-{pinned[:16]}-upstream.tar.gz"
        cached.write_bytes(archive.read_bytes())

    def test_verified_archive_extracts(self):
        self.archive()
        sources.fetch(self.root, "example", self.cache, self.root / "src")
        self.assertEqual((self.root / "src/file").read_bytes(), b"test")

    def test_modified_cache_fails_before_extraction(self):
        self.archive(digest_override="0" * 64)
        with self.assertRaisesRegex(ValueError, "SHA-256 mismatch"):
            sources.fetch(self.root, "example", self.cache, self.root / "src")
        self.assertFalse((self.root / "src").exists())

    def test_archive_cannot_escape_source_directory(self):
        self.archive("upstream/../../escaped")
        with self.assertRaises(tarfile.FilterError):
            sources.fetch(self.root, "example", self.cache, self.root / "src")
        self.assertFalse((self.root / "escaped").exists())

    def test_duplicate_pin_is_rejected(self):
        self.archive()
        pin = (self.root / "sources.lock").read_text()
        (self.root / "sources.lock").write_text(pin + pin)
        with self.assertRaisesRegex(ValueError, "duplicate"):
            sources.pins(self.root)

    def test_distribution_pins_use_no_xlibre_sources(self):
        for recipe in ("pkg", "xorg"):
            self.assertTrue(sources.pins(sources.ROOT / "packages" / recipe))


if __name__ == "__main__":
    unittest.main()
