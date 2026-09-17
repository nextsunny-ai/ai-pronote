import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


from pronote_p0 import (
    JobQueueView,
    LaunchDecision,
    allowed_upload,
    estimate_remaining_seconds,
    purge_managed_data,
    safe_data_root,
    select_launch_action,
)


class UploadValidationTests(unittest.TestCase):
    def test_accepts_supported_audio_at_limit(self):
        ok, reason = allowed_upload("meeting.m4a", 512 * 1024 * 1024)
        self.assertTrue(ok, reason)

    def test_rejects_unsupported_extension(self):
        ok, reason = allowed_upload("notes.exe", 1024)
        self.assertFalse(ok)
        self.assertIn("지원", reason)

    def test_rejects_empty_and_oversized_files(self):
        self.assertFalse(allowed_upload("meeting.mp3", 0)[0])
        self.assertFalse(allowed_upload("meeting.mp3", 512 * 1024 * 1024 + 1)[0])


class DataIsolationTests(unittest.TestCase):
    def test_explicit_data_root_is_used_without_touching_source_tree(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = safe_data_root(Path(tmp) / "v15-data")
            self.assertEqual(root, Path(tmp) / "v15-data")
            self.assertTrue((root / "uploads").is_dir())
            self.assertTrue((root / "results").is_dir())
            self.assertTrue((root / "logs").is_dir())

    def test_purge_removes_only_managed_children(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "data_v15"
            uploads = root / "uploads"
            results = root / "results"
            uploads.mkdir(parents=True)
            results.mkdir()
            (uploads / "private.wav").write_bytes(b"audio")
            nested = results / "nested"
            nested.mkdir()
            (nested / "meeting.json").write_text("{}", encoding="utf-8")
            keep = root / "keep.txt"
            keep.write_text("outside managed dirs", encoding="utf-8")

            removed = purge_managed_data(root, (uploads, results))

            self.assertEqual(removed, 2)
            self.assertEqual(list(uploads.iterdir()), [])
            self.assertEqual(list(results.iterdir()), [])
            self.assertTrue(keep.exists())

    def test_purge_rejects_directory_outside_data_root(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "data_v15"
            root.mkdir()
            with self.assertRaises(ValueError):
                purge_managed_data(root, (Path(tmp) / "other",))

    def test_purge_rejects_managed_junction_before_reading_children(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "data_v15"
            uploads = root / "uploads"
            uploads.mkdir(parents=True)
            with patch.object(Path, "is_junction", lambda path: path.name == "uploads"):
                with self.assertRaises(ValueError):
                    purge_managed_data(root, (uploads,))


class LauncherDecisionTests(unittest.TestCase):
    def test_reuses_matching_healthy_server(self):
        self.assertEqual(
            select_launch_action(True, "v1.5.0-p0", "v1.5.0-p0"),
            LaunchDecision.REUSE,
        )

    def test_refuses_to_kill_other_version(self):
        self.assertEqual(
            select_launch_action(True, "v1.3", "v1.5.0-p0"),
            LaunchDecision.CONFLICT,
        )

    def test_starts_when_port_is_free(self):
        self.assertEqual(
            select_launch_action(False, None, "v1.5.0-p0"),
            LaunchDecision.START,
        )


class JobPresentationTests(unittest.TestCase):
    def test_queue_view_exposes_user_visible_stage_and_retry(self):
        view = JobQueueView.from_job({
            "job_id": "abc",
            "status": "running",
            "phase": "받아쓰기 중 25%",
            "progress": 25,
            "duration": 3600,
            "elapsed_sec": 300,
            "summary_status": "none",
        })
        self.assertEqual(view.stage, "transcribing")
        self.assertEqual(view.progress, 25)
        self.assertGreater(view.eta_seconds, 0)
        self.assertFalse(view.can_retry)

    def test_failed_job_is_retryable_when_audio_survives(self):
        view = JobQueueView.from_job({
            "job_id": "abc",
            "status": "error",
            "error": "decode failed",
            "has_audio": True,
        })
        self.assertEqual(view.stage, "failed")
        self.assertTrue(view.can_retry)
        self.assertIn("decode", view.error)

    def test_eta_uses_observed_progress(self):
        self.assertEqual(estimate_remaining_seconds(25, 100), 300)
        self.assertIsNone(estimate_remaining_seconds(0, 100))
        self.assertEqual(estimate_remaining_seconds(100, 100), 0)


if __name__ == "__main__":
    unittest.main()
