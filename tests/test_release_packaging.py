import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "packaging" / "build_release_candidate.ps1"


class ReleasePackagingContractTests(unittest.TestCase):
    def test_full_desktop_package_contains_server_and_update_runtime(self):
        source = SCRIPT.read_text(encoding="utf-8")
        for required in (
            "main.py",
            "updater.py",
            "pronote_drive_watcher.py",
            "provider_api.py",
            "secure_credentials.py",
            "requirements-lock.txt",
            "install_external_beta.ps1",
            "static",
            "mac",
        ):
            self.assertIn(f"'{required}'", source)

    def test_packager_refuses_overwrite_and_validates_every_required_input(self):
        source = SCRIPT.read_text(encoding="utf-8")
        self.assertIn("Refusing to overwrite existing candidate", source)
        self.assertIn("Required release file is missing", source)
        self.assertIn("Required release directory is missing", source)

    def test_packager_rejects_private_paths_addresses_and_private_keys(self):
        source = SCRIPT.read_text(encoding="utf-8")
        for forbidden in (
            r"C:\Users\nexts",
            r"G:\내 드라이브",
            "/Users/sunny_sever",
            "100.79.",
            "100.89.",
            "100.123.",
            "-----BEGIN PRIVATE KEY-----",
            "-----BEGIN OPENSSH PRIVATE KEY-----",
        ):
            self.assertIn(f"'{forbidden}'", source)
        self.assertIn("Forbidden private release content found", source)
        self.assertIn("Probable secret found in release file", source)
        self.assertIn("'sk-ant-[A-Za-z0-9_-]{20,}'", source)
        self.assertIn("'AIza[0-9A-Za-z_-]{30,}'", source)


if __name__ == "__main__":
    unittest.main()
