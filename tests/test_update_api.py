import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from fastapi.testclient import TestClient

import main


class _Response:
    def __init__(self, body: bytes):
        self.body = body

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def read(self, limit: int):
        return self.body[:limit]


class UpdateApiTests(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(main.app, base_url="http://testserver")

    def tearDown(self):
        self.client.close()

    @staticmethod
    def _manifest(version="v1.5.0-beta13.20260920"):
        return json.dumps({
            "schema_version": 1,
            "version": version,
            "channel": "beta",
            "published_at": "2026-09-20T00:00:00Z",
            "release_notes_url": "https://example.com/notes",
            "artifacts": {
                "windows": {
                    "url": "https://example.com/app.zip",
                    "sha256": "a" * 64,
                    "size": 123,
                }
            },
        }).encode()

    def test_disabled_when_no_manifest_url_is_configured(self):
        with patch.object(main, "UPDATE_MANIFEST_URL", ""):
            response = self.client.get("/api/update/status")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["state"], "disabled")

    def test_public_update_channel_is_enabled_by_default(self):
        self.assertEqual(
            main.UPDATE_MANIFEST_URL,
            "https://nextsunny-ai.github.io/ai-pronote/update-manifest.json",
        )

    def test_reports_newer_verified_manifest_without_downloading_package(self):
        with (
            patch.object(main, "UPDATE_MANIFEST_URL", "https://example.com/update.json"),
            patch.object(main, "UPDATE_PLATFORM", "windows"),
            patch.object(main.urllib.request, "urlopen", return_value=_Response(self._manifest())),
        ):
            data = self.client.get("/api/update/status").json()
        self.assertEqual(data["state"], "available")
        self.assertEqual(data["version"], "v1.5.0-beta13.20260920")
        self.assertNotIn("sha256", data)
        self.assertNotIn("url", data["artifact"])
        self.assertTrue(data["prepare_allowed"])

    def test_remote_companion_can_check_but_cannot_prepare_update(self):
        request = SimpleNamespace(client=SimpleNamespace(host="192.168.0.25"))
        with (
            patch.object(main, "UPDATE_MANIFEST_URL", "https://example.com/update.json"),
            patch.object(main, "UPDATE_PLATFORM", "windows"),
            patch.object(main.urllib.request, "urlopen", return_value=_Response(self._manifest())),
        ):
            data = main.update_status(request)
        self.assertEqual(data["state"], "available")
        self.assertFalse(data["prepare_allowed"])

    def test_bad_manifest_returns_safe_error(self):
        with (
            patch.object(main, "UPDATE_MANIFEST_URL", "https://example.com/update.json"),
            patch.object(main.urllib.request, "urlopen", return_value=_Response(b"not-json")),
        ):
            data = self.client.get("/api/update/status").json()
        self.assertEqual(data["state"], "error")
        self.assertEqual(data["message"], "업데이트 정보를 확인하지 못했습니다")

    def test_prepare_requires_loopback_and_explicit_action_header(self):
        with patch.object(main, "UPDATE_MANIFEST_URL", "https://example.com/update.json"):
            response = self.client.post("/api/update/prepare")
        self.assertEqual(response.status_code, 403)

    def test_prepare_downloads_verified_package_but_does_not_activate_it(self):
        staged = main.UPDATE_INSTALL_ROOT / "versions" / "v1.5.0-beta13.20260920"
        with (
            patch.object(main, "UPDATE_MANIFEST_URL", "https://example.com/update.json"),
            patch.object(main, "UPDATE_PLATFORM", "windows"),
            patch.object(main.urllib.request, "urlopen", return_value=_Response(self._manifest())),
            patch.object(main, "prepare_update", return_value=staged) as prepare,
            patch.object(main, "read_active_version", return_value=main.APP_VERSION),
            patch.object(main, "_managed_update_ready", return_value=True),
            patch.object(main, "prepare_version_runtime") as runtime,
            patch.object(main, "activate_staged_version") as activate,
        ):
            response = self.client.post(
                "/api/update/prepare", headers={"X-Pronote-Update": "prepare"}
            )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["state"], "prepared")
        self.assertEqual(response.json()["version"], "v1.5.0-beta13.20260920")
        self.assertNotIn("path", response.json())
        prepare.assert_called_once()
        runtime.assert_called_once_with(main.UPDATE_INSTALL_ROOT, "v1.5.0-beta13.20260920")
        activate.assert_called_once_with(main.UPDATE_INSTALL_ROOT, "v1.5.0-beta13.20260920")

    def test_legacy_portable_install_prepares_but_never_changes_active_pointer(self):
        staged = main.UPDATE_INSTALL_ROOT / "versions" / "v1.5.0-beta13.20260920"
        with (
            patch.object(main, "UPDATE_MANIFEST_URL", "https://example.com/update.json"),
            patch.object(main, "UPDATE_PLATFORM", "windows"),
            patch.object(main.urllib.request, "urlopen", return_value=_Response(self._manifest())),
            patch.object(main, "prepare_update", return_value=staged),
            patch.object(main, "read_active_version", return_value=None),
            patch.object(main, "_managed_update_ready", return_value=False),
            patch.object(main, "prepare_version_runtime") as runtime,
            patch.object(main, "activate_staged_version") as activate,
        ):
            data = self.client.post(
                "/api/update/prepare", headers={"X-Pronote-Update": "prepare"}
            ).json()
        self.assertEqual(data["state"], "prepared_manual_install")
        self.assertFalse(data["restart_required"])
        activate.assert_not_called()
        runtime.assert_not_called()

    def test_managed_update_requires_active_version_runtime_and_marker(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            version = "v1.5.0-beta13.20260919"
            runtime = root / "runtime" / "versions" / version
            executable = runtime / (
                "Scripts/pythonw.exe" if main.UPDATE_PLATFORM == "windows" else "bin/python"
            )
            executable.parent.mkdir(parents=True)
            executable.write_text("runtime", encoding="utf-8")
            (runtime / ".runtime-complete.json").write_text("{}", encoding="utf-8")
            (root / "stable_launcher.py").write_text("launcher", encoding="utf-8")
            (root / "updater.py").write_text("updater", encoding="utf-8")
            with (
                patch.object(main, "UPDATE_INSTALL_ROOT", root),
                patch.object(main, "read_active_version", return_value=version),
            ):
                self.assertTrue(main._managed_update_ready())
                (runtime / ".runtime-complete.json").unlink()
                self.assertFalse(main._managed_update_ready())


if __name__ == "__main__":
    unittest.main()

