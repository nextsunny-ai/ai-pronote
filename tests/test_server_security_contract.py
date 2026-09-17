import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MAIN = (ROOT / "main.py").read_text(encoding="utf-8")


class ServerSecurityContractTests(unittest.TestCase):
    def test_job_ids_are_strict_and_json_writes_are_atomic(self):
        self.assertIn('re.compile(r"^[0-9a-f]{12}$")', MAIN)
        self.assertIn("temp.replace(path)", MAIN)
        self.assertIn("_job_state_lock = threading.RLock()", MAIN)

    def test_auxiliary_uploads_are_bounded(self):
        self.assertIn("while chunk := await file.read(1024 * 1024)", MAIN)
        self.assertIn("background=BackgroundTask(finish_response)", MAIN)
        self.assertIn("partial_limit = 25 * 1024 * 1024", MAIN)

    def test_p0_rejects_non_loopback_bind(self):
        self.assertIn('HOST not in {"127.0.0.1", "localhost"}', MAIN)
        self.assertIn("TrustedHostMiddleware", MAIN)

    def test_summary_write_failure_is_not_marked_done(self):
        marker = 'summary_error=f"회의록 저장 실패: {e}"'
        self.assertIn(marker, MAIN)
        self.assertIn("return False", MAIN[MAIN.index(marker):MAIN.index(marker) + 200])
        self.assertIn('d.get("summary_status") == "running"', MAIN)
        self.assertIn('summary_status="pending"', MAIN)
        self.assertGreaterEqual(MAIN.count('sf.exists() and job.get("summary_status") == "done"'), 2)

    def test_upload_capacity_is_reserved_before_body_write(self):
        self.assertIn("_upload_reservations", MAIN)
        self.assertIn("_reserve_queue_slot()", MAIN)
        self.assertIn("_release_queue_slot()", MAIN)

    def test_permanent_delete_is_loopback_confirmed_and_blocked_while_busy(self):
        self.assertIn('@app.post("/api/data/purge")', MAIN)
        self.assertIn('req.confirmation != "AI PRONOTE 데이터 영구 삭제"', MAIN)
        self.assertIn('client_host not in {"127.0.0.1", "::1", "testclient"}', MAIN)
        self.assertIn('or _active_data_operations > 0 or summary_running', MAIN)
        self.assertIn('if _maintenance_mode:', MAIN)
        self.assertGreaterEqual(MAIN.count('_begin_data_operation()'), 3)
        self.assertGreaterEqual(MAIN.count('_end_data_operation()'), 4)
        self.assertIn('purge_managed_data(DATA_ROOT, (UPLOAD_DIR, RESULT_DIR, LOG_DIR))', MAIN)

    def test_cli_login_files_are_not_reported_as_verified_ready(self):
        self.assertIn('out["gemini"] = "login_unverified"', MAIN)
        self.assertIn('out["codex"] = "login_unverified"', MAIN)
        self.assertIn('"account_unsupported"', MAIN)


if __name__ == "__main__":
    unittest.main()
