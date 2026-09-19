import hashlib
import io
import json
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

from updater import (
    UpdateError,
    activate_staged_version,
    compare_versions,
    download_update,
    load_manifest,
    prepare_update,
    prepare_version_runtime,
    read_active_version,
    rollback_active_version,
    stage_update_archive,
)


class UpdateContractTests(unittest.TestCase):
    def test_download_streams_to_partial_file_and_verifies_size_and_hash(self):
        class Response:
            def __init__(self, payload):
                self.payload = io.BytesIO(payload)
            def __enter__(self): return self
            def __exit__(self, *_args): return False
            def read(self, size): return self.payload.read(size)

        payload = b"verified update package"
        digest = hashlib.sha256(payload).hexdigest()
        with tempfile.TemporaryDirectory() as td:
            destination = Path(td) / "update.zip"
            result = download_update(
                "https://example.com/update.zip", len(payload), digest, destination,
                opener=lambda *_args, **_kwargs: Response(payload),
            )
            self.assertEqual(result, destination)
            self.assertEqual(destination.read_bytes(), payload)
            self.assertFalse(destination.with_suffix(".zip.partial").exists())

            with self.assertRaises(UpdateError):
                download_update(
                    "https://example.com/bad.zip", len(payload) + 1, digest,
                    Path(td) / "bad.zip", opener=lambda *_a, **_k: Response(payload),
                )
            self.assertFalse((Path(td) / "bad.zip").exists())

    def test_prepare_update_downloads_and_stages_without_activating(self):
        class Response:
            def __init__(self, payload): self.payload = io.BytesIO(payload)
            def __enter__(self): return self
            def __exit__(self, *_args): return False
            def read(self, size): return self.payload.read(size)
        payload_io = io.BytesIO()
        with zipfile.ZipFile(payload_io, "w") as archive:
            archive.writestr("AI_PRONOTE/main.py", "ok")
            archive.writestr("AI_PRONOTE/pronote_p0.py", "ok")
            archive.writestr("AI_PRONOTE/provider_api.py", "ok")
            archive.writestr("AI_PRONOTE/secure_credentials.py", "ok")
            archive.writestr("AI_PRONOTE/updater.py", "ok")
            archive.writestr("AI_PRONOTE/requirements-lock-windows.txt", "fastapi==1")
            archive.writestr("AI_PRONOTE/requirements-lock-mac.txt", "fastapi==1")
            archive.writestr("AI_PRONOTE/start_v15.ps1", "ok")
            archive.writestr("AI_PRONOTE/3_START_AI_PRONOTE.vbs", "ok")
            archive.writestr("AI_PRONOTE/static/index.html", "ok")
        payload = payload_io.getvalue()
        manifest = load_manifest(json.dumps({
            "schema_version": 1, "version": "v1.2.3", "channel": "beta",
            "published_at": "2026-09-19T00:00:00Z",
            "release_notes_url": "https://example.com/notes",
            "artifacts": {"windows": {"url": "https://example.com/app.zip",
                "sha256": hashlib.sha256(payload).hexdigest(), "size": len(payload)}}
        }), "windows")
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            staged = prepare_update(manifest, root, opener=lambda *_a, **_k: Response(payload))
            self.assertEqual(staged, root / "versions" / "v1.2.3")
            self.assertTrue((staged / "main.py").is_file())
            self.assertFalse((root / "active-version.json").exists())

    def test_activation_is_atomic_and_keeps_rollback_pointer(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            versions = root / "versions"
            old = versions / "v1.0.0"
            new = versions / "v1.1.0"
            old.mkdir(parents=True)
            new.mkdir()
            (old / "main.py").write_text("old", encoding="utf-8")
            (new / "main.py").write_text("new", encoding="utf-8")
            activate_staged_version(root, "v1.0.0")
            activate_staged_version(root, "v1.1.0")
            self.assertEqual(read_active_version(root), "v1.1.0")
            state = json.loads((root / "active-version.json").read_text(encoding="utf-8"))
            self.assertEqual(state["rollback_version"], "v1.0.0")

            rolled_back = rollback_active_version(root)
            self.assertEqual(rolled_back, old)
            self.assertEqual(read_active_version(root), "v1.0.0")
            rolled_state = json.loads((root / "active-version.json").read_text(encoding="utf-8"))
            self.assertEqual(rolled_state["rollback_version"], "v1.1.0")

            with self.assertRaises(UpdateError):
                activate_staged_version(root, "../../escape")
            self.assertEqual(read_active_version(root), "v1.0.0")

    def test_version_runtime_is_published_only_after_all_checks_pass(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            version = "v1.2.3"
            version_root = root / "versions" / version
            version_root.mkdir(parents=True)
            lock_name = "requirements-lock-windows.txt" if sys.platform == "win32" else "requirements-lock-mac.txt"
            (version_root / lock_name).write_text("fastapi==1\n", encoding="utf-8")
            calls = []

            def successful_runner(command, *, check):
                calls.append(command)
                if command[1:3] == ["-m", "venv"]:
                    runtime = Path(command[3])
                    python = runtime / ("Scripts/python.exe" if sys.platform == "win32" else "bin/python")
                    python.parent.mkdir(parents=True, exist_ok=True)
                    python.write_text("test", encoding="utf-8")

            runtime = prepare_version_runtime(root, version, runner=successful_runner)
            self.assertTrue((runtime / ".runtime-complete.json").is_file())
            self.assertEqual(len(calls), 4)
            self.assertEqual(prepare_version_runtime(root, version, runner=lambda *_a, **_k: self.fail()), runtime)

    def test_failed_version_runtime_never_becomes_visible(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            version = "v1.2.3"
            version_root = root / "versions" / version
            version_root.mkdir(parents=True)
            lock_name = "requirements-lock-windows.txt" if sys.platform == "win32" else "requirements-lock-mac.txt"
            (version_root / lock_name).write_text("fastapi==1\n", encoding="utf-8")

            def failed_runner(command, *, check):
                if command[1:3] == ["-m", "venv"]:
                    runtime = Path(command[3])
                    python = runtime / ("Scripts/python.exe" if sys.platform == "win32" else "bin/python")
                    python.parent.mkdir(parents=True, exist_ok=True)
                    python.write_text("test", encoding="utf-8")
                    return
                raise subprocess.CalledProcessError(1, command)

            with self.assertRaises(UpdateError):
                prepare_version_runtime(root, version, runner=failed_runner)
            self.assertFalse((root / "runtime" / "versions" / version).exists())

    def test_version_comparison_handles_beta_and_stable(self):
        self.assertLess(compare_versions("v1.5.0-beta9.20260918", "v1.5.0-beta10.20260920"), 0)
        self.assertLess(compare_versions("v1.5.0-beta10.20260920", "v1.5.0"), 0)
        self.assertEqual(compare_versions("1.5.0", "v1.5.0"), 0)

    def test_manifest_requires_https_sha256_and_platform_artifact(self):
        valid = {
            "schema_version": 1,
            "version": "v1.5.0-beta10.20260920",
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
        }
        parsed = load_manifest(json.dumps(valid), "windows")
        self.assertEqual(parsed.version, valid["version"])
        self.assertEqual(parsed.artifact.sha256, "a" * 64)

        invalid = json.loads(json.dumps(valid))
        invalid["artifacts"]["windows"]["url"] = "http://example.com/app.zip"
        with self.assertRaises(UpdateError):
            load_manifest(json.dumps(invalid), "windows")

    def test_stage_update_rejects_zip_slip_and_hash_mismatch(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            bad_zip = root / "bad.zip"
            with zipfile.ZipFile(bad_zip, "w") as archive:
                archive.writestr("../escape.txt", "no")
            digest = hashlib.sha256(bad_zip.read_bytes()).hexdigest()
            with self.assertRaises(UpdateError):
                stage_update_archive(bad_zip, digest, root / "stage")
            self.assertFalse((root / "escape.txt").exists())

            with self.assertRaises(UpdateError):
                stage_update_archive(bad_zip, "0" * 64, root / "stage2")

    def test_stage_update_reuses_only_the_same_verified_package(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            package = root / "app.zip"
            with zipfile.ZipFile(package, "w") as archive:
                archive.writestr("AI_PRONOTE/main.py", "print('ok')")
                archive.writestr("AI_PRONOTE/pronote_p0.py", "ok")
                archive.writestr("AI_PRONOTE/provider_api.py", "ok")
                archive.writestr("AI_PRONOTE/secure_credentials.py", "ok")
                archive.writestr("AI_PRONOTE/updater.py", "ok")
                archive.writestr("AI_PRONOTE/requirements-lock-windows.txt", "fastapi==1")
                archive.writestr("AI_PRONOTE/requirements-lock-mac.txt", "fastapi==1")
                archive.writestr("AI_PRONOTE/3_START_AI_PRONOTE.vbs", "' start")
                archive.writestr("AI_PRONOTE/static/index.html", "ok")
            digest = hashlib.sha256(package.read_bytes()).hexdigest()
            staged = stage_update_archive(package, digest, root / "versions" / "v2")
            self.assertTrue((staged / "main.py").exists())
            self.assertEqual(stage_update_archive(package, digest, root / "versions" / "v2"), staged)
            with self.assertRaises(UpdateError):
                stage_update_archive(package, "0" * 64, root / "versions" / "v2")


if __name__ == "__main__":
    unittest.main()

