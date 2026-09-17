import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MAIN = (ROOT / "main.py").read_text(encoding="utf-8")
LOCK = (ROOT / "requirements-lock.txt").read_text(encoding="utf-8")


class ServerSecurityContractTests(unittest.TestCase):
    def test_release_direct_dependencies_are_exactly_pinned(self):
        requirement_lines = [line for line in LOCK.splitlines() if line and not line.startswith("#")]
        self.assertGreaterEqual(len(requirement_lines), 7)
        self.assertTrue(all("==" in line for line in requirement_lines))

    def test_mac_existing_venv_requires_supported_64_bit_architecture(self):
        installer = (ROOT / "mac" / "1_FIRST_SETUP.command").read_text(encoding="utf-8")
        self.assertIn('struct.calcsize("P")*8 == 64', installer)
        self.assertIn('{"arm64","x86_64"}', installer)

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
        self.assertIn('out["gemini"] = "policy_blocked"', MAIN)
        self.assertIn('out["codex"] = "login_unverified"', MAIN)
        self.assertIn('"account_unsupported"', MAIN)

    def test_cli_provider_ids_are_strict_and_legacy_jobs_are_migrated(self):
        self.assertIn('p not in {"claude_cli", "codex_cli"}', MAIN)
        self.assertIn('{"claude": "claude_cli", "codex": "codex_cli"}.get(', MAIN)
        self.assertIn('stored_provider or "claude_cli"', MAIN)
        self.assertIn('_job_write(job_id, provider=provider)', MAIN)


if __name__ == "__main__":
    unittest.main()
