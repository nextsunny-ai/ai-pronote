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


if __name__ == "__main__":
    unittest.main()
