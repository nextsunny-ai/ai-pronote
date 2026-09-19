import unittest
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class LauncherContractTests(unittest.TestCase):
    EXPECTED_VERSION = "v1.5.0-beta13.20260920.3"

    def test_windows_powershell_entrypoints_are_utf8_bom_and_parse_in_legacy_host(self):
        scripts = (
            "install_external_beta.ps1",
            "launch_managed_windows.ps1",
            "start_v15.ps1",
            "start_v15_server_only.ps1",
            "uninstall_windows.ps1",
        )
        powershell = Path(r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe")
        for relative in scripts:
            path = ROOT / relative
            self.assertTrue(path.read_bytes().startswith(b"\xef\xbb\xbf"), relative)
            if powershell.is_file():
                completed = subprocess.run(
                    [
                        str(powershell),
                        "-NoProfile",
                        "-NonInteractive",
                        "-Command",
                        f"[scriptblock]::Create((Get-Content -Raw -LiteralPath '{path}')) | Out-Null",
                    ],
                    capture_output=True,
                    text=True,
                    timeout=15,
                    check=False,
                )
                self.assertEqual(completed.returncode, 0, f"{relative}: {completed.stderr}")

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
        self.assertIn("Confirm-And-StopPreviousVersion", launcher)
        self.assertIn("Get-ActiveJobCount", launcher)
        self.assertIn("$_.summary_status -in @('pending', 'running')", launcher)
        self.assertIn("MessageBoxButtons]::YesNo", launcher)
        self.assertIn("Stop-Process -Id $listener.OwningProcess", launcher)
        self.assertIn("Get-NetTCPConnection -LocalPort $Port", launcher)
        self.assertNotIn("8796..8815", launcher)

    def test_launcher_releases_mutex_before_blocking_error_dialogs(self):
        launcher = (ROOT / "start_v15.ps1").read_text(encoding="utf-8")
        self.assertIn("function Release-LauncherMutex", launcher)
        conflict = launcher.index("Show-VersionConflict ([string]$health.version)")
        self.assertLess(launcher.rfind("Release-LauncherMutex", 0, conflict), conflict)
        catch = launcher.index("} catch {", launcher.index("Show-AppWindow"))
        message = launcher.index("[System.Windows.Forms.MessageBox]::Show($_.Exception.Message", catch)
        self.assertLess(launcher.index("Release-LauncherMutex", catch), message)

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

    def test_windows_launchers_keep_user_data_outside_versioned_package(self):
        for name in ("start_v15.ps1", "start_v15_server_only.ps1"):
            launcher = (ROOT / name).read_text(encoding="utf-8")
            self.assertIn("LocalApplicationData", launcher)
            self.assertIn('AI_PRONOTE\\v1.5\\data', launcher)
            self.assertNotIn('Join-Path $ProjectDir "data_v15"', launcher)

    def test_mac_launchers_keep_user_data_outside_versioned_package(self):
        setup = (ROOT / "mac" / "1_FIRST_SETUP.command").read_text(encoding="utf-8")
        start = (ROOT / "mac" / "3_START_AI_PRONOTE.command").read_text(encoding="utf-8")
        stop = (ROOT / "mac" / "STOP_AI_PRONOTE.command").read_text(encoding="utf-8")
        shared = "Library/Application Support/AI_PRONOTE/v1.5/data"
        for script in (setup, start, stop):
            self.assertIn(shared, script)
        self.assertIn('PRONOTE_DATA_DIR="$DATA_DIR"', start)
        self.assertIn('cp -R "$ROOT/data_v15/." "$DATA_DIR/"', setup)
        self.assertNotIn('PRONOTE_DATA_DIR="$ROOT/data_v15"', start)

    def test_all_launchers_match_application_build_identity(self):
        version_source = (ROOT / "pronote_p0.py").read_text(encoding="utf-8")
        windows = (ROOT / "start_v15.ps1").read_text(encoding="utf-8")
        windows_boot = (ROOT / "start_v15_server_only.ps1").read_text(encoding="utf-8")
        mac = (ROOT / "mac" / "3_START_AI_PRONOTE.command").read_text(encoding="utf-8")
        metadata = (ROOT / "main.py").read_text(encoding="utf-8")
        for source in (version_source, windows, windows_boot, mac):
            self.assertIn(self.EXPECTED_VERSION, source)
        self.assertIn('BUILD_DATE = "2026-09-20"', metadata)
        self.assertIn("v1.5.0-beta13-20260920.3", metadata)
        self.assertNotIn("releases/tag/v1.0.0-beta", metadata)


if __name__ == "__main__":
    unittest.main()
