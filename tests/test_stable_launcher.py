import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from stable_launcher import LauncherError, _launch_target, launch_with_health_check, resolve_launch_target
from updater import activate_staged_version


class StableLauncherTests(unittest.TestCase):
    def _version(self, root: Path, version: str):
        target = root / "versions" / version
        target.mkdir(parents=True)
        (target / "main.py").write_text("ok", encoding="utf-8")
        (target / "start_v15.ps1").write_text("ok", encoding="utf-8")
        return target

    def test_resolves_only_active_version_inside_versions_directory(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            target = root / "versions" / "v1.2.3"
            target.mkdir(parents=True)
            (target / "main.py").write_text("ok", encoding="utf-8")
            (target / "start_v15.ps1").write_text("ok", encoding="utf-8")
            (root / "active-version.json").write_text(
                json.dumps({"active_version": "v1.2.3"}), encoding="utf-8"
            )
            self.assertEqual(resolve_launch_target(root, "windows"), target / "start_v15.ps1")

    def test_rejects_escape_and_incomplete_version(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            root.mkdir(exist_ok=True)
            for version in ("../../escape", "v9.9.9"):
                (root / "active-version.json").write_text(
                    json.dumps({"active_version": version}), encoding="utf-8"
                )
                with self.assertRaises(LauncherError):
                    resolve_launch_target(root, "windows")

    def test_health_checked_launch_keeps_new_version(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            self._version(root, "v1.0.0")
            self._version(root, "v1.1.0")
            activate_staged_version(root, "v1.0.0")
            activate_staged_version(root, "v1.1.0")
            launched = []
            result = launch_with_health_check(
                root, "windows", launcher=lambda target: launched.append(target),
                health_reader=lambda: {"status": "ok", "version": "v1.1.0"},
                timeout_seconds=1, poll_seconds=0,
            )
            self.assertEqual(result, "v1.1.0")
            self.assertEqual(len(launched), 1)

    def test_launch_uses_completed_version_specific_runtime(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            target = self._version(root, "v1.2.3") / "start_v15.ps1"
            runtime = root / "runtime" / "versions" / "v1.2.3"
            (runtime / "Scripts").mkdir(parents=True)
            (runtime / "Scripts" / "python.exe").write_text("test", encoding="utf-8")
            (runtime / ".runtime-complete.json").write_text("{}", encoding="utf-8")
            with patch("stable_launcher.subprocess.Popen") as popen:
                _launch_target(target)
            self.assertEqual(popen.call_args.kwargs["env"]["PRONOTE_SHARED_VENV"], str(runtime))

    def test_failed_new_version_rolls_back_and_launches_previous(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            old = self._version(root, "v1.0.0")
            self._version(root, "v1.1.0")
            activate_staged_version(root, "v1.0.0")
            activate_staged_version(root, "v1.1.0")
            launched = []
            health = iter([None, {"status": "ok", "version": "v1.0.0"}])
            result = launch_with_health_check(
                root, "windows", launcher=lambda target: launched.append(target),
                health_reader=lambda: next(health, None), timeout_seconds=0, poll_seconds=0,
            )
            self.assertEqual(result, "v1.0.0")
            self.assertEqual(launched[-1], old / "start_v15.ps1")

    def test_raises_when_new_and_rollback_versions_both_fail_health(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            self._version(root, "v1.0.0")
            self._version(root, "v1.1.0")
            activate_staged_version(root, "v1.0.0")
            activate_staged_version(root, "v1.1.0")
            with self.assertRaises(LauncherError):
                launch_with_health_check(
                    root, "windows", launcher=lambda _target: None,
                    health_reader=lambda: None, timeout_seconds=0, poll_seconds=0,
                )


if __name__ == "__main__":
    unittest.main()

