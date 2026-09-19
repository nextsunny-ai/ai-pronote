import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "packaging" / "build_release_candidate.ps1"
MAC_FINALIZER = ROOT / "packaging" / "finalize_macos_candidate.command"


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
            "launch_managed_windows.ps1",
            "static",
            "mac",
        ):
            self.assertIn(f"'{required}'", source)

    def test_packager_refuses_overwrite_and_validates_every_required_input(self):
        source = SCRIPT.read_text(encoding="utf-8")
        self.assertIn("Refusing to overwrite existing candidate", source)
        self.assertIn("Required release file is missing", source)
        self.assertIn("Required release directory is missing", source)

    def test_package_provides_platform_lock_files_for_managed_updates(self):
        source = SCRIPT.read_text(encoding="utf-8")
        self.assertIn("'requirements-lock-windows.txt'", source)
        self.assertIn("'requirements-lock-mac.txt'", source)
        self.assertNotIn("$SharedLock", source)
        windows_lock = (ROOT / "requirements-lock-windows.txt").read_text(encoding="utf-8")
        mac_lock = (ROOT / "requirements-lock-mac.txt").read_text(encoding="utf-8")
        self.assertIn("ctranslate2==4.8.2", windows_lock)
        self.assertIn("uvicorn[standard]==0.53.0", windows_lock)
        self.assertIn("faster-whisper==1.2.1", mac_lock)

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

    def test_macos_finalizer_preserves_clickable_script_permissions(self):
        source = MAC_FINALIZER.read_text(encoding="utf-8")
        self.assertIn("ditto -c -k --sequesterRsrc --keepParent", source)
        self.assertIn('chmod 755 "$SCRIPT"', source)
        self.assertIn("MAC", source.upper())
        self.assertIn("stat -f '%Lp'", source)
        self.assertNotIn("mapfile", source)


if __name__ == "__main__":
    unittest.main()
