import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import patch

from fastapi.testclient import TestClient

import main


class FakeCredentialStore:
    deleted = []

    def delete(self, provider):
        self.deleted.append(provider)


class PartlyFailingCredentialStore(FakeCredentialStore):
    def delete(self, provider):
        if provider == "gemini":
            raise RuntimeError("simulated backend failure")
        super().delete(provider)


class DataPurgeRegressionTests(unittest.TestCase):
    def test_summary_guard_auth_defer_holds_reservation_against_purge(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "data_v15"
            uploads, results, logs = (root / name for name in ("uploads", "results", "logs"))
            for directory in (uploads, results, logs):
                directory.mkdir(parents=True, exist_ok=True)
            job_id = "b" * 12
            job_path = uploads / f"{job_id}.job.json"
            job_path.write_text(
                '{"job_id":"' + job_id + '","summary_status":"pending","summary_error_kind":"auth","summary_next_at":0}',
                encoding="utf-8",
            )
            entered = threading.Event()
            release = threading.Event()

            def held_login_check():
                entered.set()
                release.wait(2)
                return False

            with (
                patch.object(main, "IPAD_MODE", False),
                patch.object(main, "DATA_ROOT", root),
                patch.object(main, "UPLOAD_DIR", uploads),
                patch.object(main, "RESULT_DIR", results),
                patch.object(main, "LOG_DIR", logs),
                patch.object(main, "_is_logged_in", held_login_check),
                TestClient(main.app, base_url="http://testserver") as client,
            ):
                worker = threading.Thread(target=main._process_pending_summary_file, args=(job_path, 100.0))
                worker.start()
                self.assertTrue(entered.wait(1))
                response = client.post(
                    "/api/data/purge",
                    headers={"origin": "http://testserver"},
                    json={"confirmation": "AI PRONOTE 데이터 영구 삭제"},
                )
                release.set()
                worker.join(2)
            self.assertEqual(response.status_code, 409)
            self.assertTrue(job_path.exists())

    def test_background_worker_keeps_data_operation_reserved_for_its_lifetime(self):
        entered = threading.Event()
        release = threading.Event()

        def held_worker(*_args):
            entered.set()
            release.wait(2)

        original_count = main._active_data_operations
        try:
            with patch.object(main, "_job_worker", held_worker):
                main._job_start("a" * 12, Path("held.wav"), "held.wav", "ko", "small", 1, False)
                self.assertTrue(entered.wait(1))
                self.assertEqual(main._active_data_operations, original_count + 1)
                release.set()
                for _ in range(100):
                    if main._active_data_operations == original_count:
                        break
                    threading.Event().wait(0.01)
                self.assertEqual(main._active_data_operations, original_count)
        finally:
            release.set()

    def test_active_data_operation_blocks_purge_and_maintenance_blocks_new_work(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "data_v15"
            uploads, results, logs = (root / name for name in ("uploads", "results", "logs"))
            for directory in (uploads, results, logs):
                directory.mkdir(parents=True, exist_ok=True)
            with (
                patch.object(main, "IPAD_MODE", False),
                patch.object(main, "DATA_ROOT", root),
                patch.object(main, "UPLOAD_DIR", uploads),
                patch.object(main, "RESULT_DIR", results),
                patch.object(main, "LOG_DIR", logs),
                patch.object(main, "_active_data_operations", 1),
                TestClient(main.app, base_url="http://testserver") as client,
            ):
                response = client.post(
                    "/api/data/purge",
                    headers={"origin": "http://testserver"},
                    json={"confirmation": "AI PRONOTE 데이터 영구 삭제"},
                )
            self.assertEqual(response.status_code, 409)

        with patch.object(main, "_maintenance_mode", True):
            with self.assertRaises(Exception) as raised:
                main._begin_data_operation()
            self.assertEqual(getattr(raised.exception, "status_code", None), 503)

    def test_purge_requires_origin_confirmation_and_idle_jobs_then_deletes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "data_v15"
            uploads, results, logs = (root / name for name in ("uploads", "results", "logs"))
            for directory in (uploads, results, logs):
                directory.mkdir(parents=True, exist_ok=True)
                (directory / "private.txt").write_text("private", encoding="utf-8")
            session_flag = Path(tmp) / "session.flag"
            session_flag.write_text("1", encoding="utf-8")
            FakeCredentialStore.deleted = []

            with (
                patch.object(main, "IPAD_MODE", False),
                patch.object(main, "DATA_ROOT", root),
                patch.object(main, "UPLOAD_DIR", uploads),
                patch.object(main, "RESULT_DIR", results),
                patch.object(main, "LOG_DIR", logs),
                patch.object(main, "SESSION_FLAG_PATH", session_flag),
                patch.object(main, "WindowsCredentialStore", FakeCredentialStore),
                patch.object(main, "_active_job_count", return_value=0),
                TestClient(main.app, base_url="http://testserver") as client,
            ):
                wrong_origin = client.post(
                    "/api/data/purge",
                    headers={"origin": "https://evil.example"},
                    json={"confirmation": "AI PRONOTE 데이터 영구 삭제"},
                )
                self.assertEqual(wrong_origin.status_code, 403)

                wrong_phrase = client.post(
                    "/api/data/purge",
                    headers={"origin": "http://testserver"},
                    json={"confirmation": "삭제"},
                )
                self.assertEqual(wrong_phrase.status_code, 400)

                with patch.object(main, "_active_job_count", return_value=1):
                    busy = client.post(
                        "/api/data/purge",
                        headers={"origin": "http://testserver"},
                        json={"confirmation": "AI PRONOTE 데이터 영구 삭제"},
                    )
                self.assertEqual(busy.status_code, 409)

                response = client.post(
                    "/api/data/purge",
                    headers={"origin": "http://testserver"},
                    json={"confirmation": "AI PRONOTE 데이터 영구 삭제"},
                )

            self.assertEqual(response.status_code, 200)
            self.assertEqual(response.json()["removed_entries"], 3)
            self.assertFalse(session_flag.exists())
            self.assertEqual(FakeCredentialStore.deleted, ["openai", "gemini", "anthropic"])
            for directory in (uploads, results, logs):
                self.assertTrue(directory.is_dir())
                self.assertEqual(list(directory.iterdir()), [])

    def test_credential_failure_is_reported_as_partial_not_success(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "data_v15"
            uploads, results, logs = (root / name for name in ("uploads", "results", "logs"))
            for directory in (uploads, results, logs):
                directory.mkdir(parents=True, exist_ok=True)
            PartlyFailingCredentialStore.deleted = []
            with (
                patch.object(main, "IPAD_MODE", False),
                patch.object(main, "DATA_ROOT", root),
                patch.object(main, "UPLOAD_DIR", uploads),
                patch.object(main, "RESULT_DIR", results),
                patch.object(main, "LOG_DIR", logs),
                patch.object(main, "SESSION_FLAG_PATH", Path(tmp) / "session.flag"),
                patch.object(main, "WindowsCredentialStore", PartlyFailingCredentialStore),
                patch.object(main, "_active_job_count", return_value=0),
                TestClient(main.app, base_url="http://testserver") as client,
            ):
                response = client.post(
                    "/api/data/purge",
                    headers={"origin": "http://testserver"},
                    json={"confirmation": "AI PRONOTE 데이터 영구 삭제"},
                )
            self.assertEqual(response.status_code, 207)
            self.assertFalse(response.json()["ok"])
            self.assertEqual(response.json()["failed_credentials"], ["gemini"])


if __name__ == "__main__":
    unittest.main()
