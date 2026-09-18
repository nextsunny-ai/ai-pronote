import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class LauncherContractTests(unittest.TestCase):
    EXPECTED_VERSION = "v1.5.0-beta8.20260918"

    def test_launcher_is_safe_and_version_aware(self):
        launcher = (ROOT / "start_v15.ps1").read_text(encoding="utf-8")
        lowered = launcher.lower()
        self.assertNotIn("taskkill", lowered)
        self.assertIn("Mutex", launcher)
        self.assertIn(self.EXPECTED_VERSION, launcher)
        self.assertIn("127.0.0.1", launcher)
        self.assertIn("8795", launcher)
        self.assertIn("AppActivate", launcher)
        self.assertIn("version conflict", lowered)
        self.assertIn("AbandonedMutexException", launcher)

    def test_hidden_vbs_wrapper_targets_new_launcher_only(self):
        wrapper = (ROOT / "start_v15.vbs").read_text(encoding="utf-8")
        self.assertIn("start_v15.ps1", wrapper)
        self.assertIn("-WindowStyle Hidden", wrapper)

    def test_desktop_and_boot_launchers_share_startup_mutex(self):
        desktop = (ROOT / "start_v15.ps1").read_text(encoding="utf-8")
        boot = (ROOT / "start_v15_server_only.ps1").read_text(encoding="utf-8")
        mutex_name = "Local\\AI_PRONOTE_v15_Launcher"
        self.assertIn(mutex_name, desktop)
        self.assertIn(mutex_name, boot)
        self.assertIn('.venv\\Scripts\\pythonw.exe', boot)
        self.assertNotIn('Get-Command python', boot)

    def test_all_launchers_match_application_build_identity(self):
        version_source = (ROOT / "pronote_p0.py").read_text(encoding="utf-8")
        windows = (ROOT / "start_v15.ps1").read_text(encoding="utf-8")
        windows_boot = (ROOT / "start_v15_server_only.ps1").read_text(encoding="utf-8")
        mac = (ROOT / "mac" / "3_START_AI_PRONOTE.command").read_text(encoding="utf-8")
        metadata = (ROOT / "main.py").read_text(encoding="utf-8")
        for source in (version_source, windows, windows_boot, mac):
            self.assertIn(self.EXPECTED_VERSION, source)
        self.assertIn('BUILD_DATE = "2026-09-18"', metadata)
        self.assertIn("v1.5.0-beta8-20260918", metadata)
        self.assertNotIn("releases/tag/v1.0.0-beta", metadata)


if __name__ == "__main__":
    unittest.main()
