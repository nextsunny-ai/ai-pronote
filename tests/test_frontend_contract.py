import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HTML = (ROOT / "static" / "index.html").read_text(encoding="utf-8")


class FrontendContractTests(unittest.TestCase):
    def test_experimental_cli_login_is_present_but_not_claimed_verified(self):
        self.assertIn("login_unverified", HTML)
        self.assertIn("계정 자격은 첫 회의록 생성 때 확인됩니다", HTML)

    def test_persistent_job_center_is_present(self):
        self.assertIn('id="jobCenter"', HTML)
        self.assertIn('/api/jobs', HTML)
        self.assertIn('data-testid="job-center"', HTML)
        self.assertIn("view.can_retry", HTML)
        self.assertIn("if (!response.ok)", HTML)
        self.assertIn("aria-controls=\"jobCenter\"", HTML)
        self.assertIn("progress aria-label=", HTML)

    def test_legacy_direct_upload_uses_async_job_watcher(self):
        self.assertNotIn("progress.style.display = 'none';\n        showResult(data);", HTML)
        self.assertIn("watchStandaloneJob", HTML)

    def test_meeting_result_has_clear_unified_tabs(self):
        for label in ("AI 회의록", "전체 원문", "내 노트", "녹음"):
            self.assertIn(label, HTML)
        self.assertIn("__pronoteOpenResultAudio", HTML)
        self.assertIn("await ensureBlob(rec)", HTML)
        self.assertIn("aria-pressed=\"true\"", HTML)

    def test_v15_accessibility_and_responsive_tokens_exist(self):
        self.assertIn('id="v15-design-system"', HTML)
        self.assertIn(":focus-visible", HTML)
        self.assertIn("prefers-reduced-motion", HTML)
        self.assertIn("max-width: 1023px", HTML)

    def test_wave_note_is_used_only_by_v15_web_assets(self):
        manifest = (ROOT / "static" / "manifest.webmanifest").read_text(encoding="utf-8")
        self.assertIn("v15-wave-note/full-192.png", HTML)
        self.assertIn("v15-wave-note/full-512.png", manifest)
        self.assertTrue((ROOT / "icon_v15_wave_note.ico").exists())

    def test_terminal_job_lookup_errors_do_not_poll_forever(self):
        self.assertIn("e.status === 404 || e.status === 410", HTML)
        self.assertIn("offline >= 20", HTML)
        self.assertIn("resultFailures >= 5", HTML)
        self.assertIn("summaryFailures >= 5", HTML)

    def test_audio_never_falls_back_to_an_unrelated_recording(self):
        self.assertNotIn("all.find(r => r.context === 'live') || all[0]", HTML)
        self.assertIn("이 회의에 연결된 녹음 파일이 없습니다", HTML)

    def test_note_only_and_camera_meeting_modes_are_real_flows(self):
        self.assertIn('id="homeNoteOnlyCard"', HTML)
        self.assertIn("newStandaloneNoteBtn", HTML)
        self.assertIn('id="newMeetingVideo"', HTML)
        self.assertIn("cameraStream = await navigator.mediaDevices.getUserMedia", HTML)
        self.assertIn("...cameraStream.getVideoTracks()", HTML)
        self.assertIn("state.cameraStream?.getTracks().forEach", HTML)

    def test_recording_storage_and_device_failures_have_recovery_paths(self):
        self.assertIn("navigator.storage?.estimate", HTML)
        self.assertIn("긴급복구_", HTML)
        self.assertIn("track.addEventListener('ended'", HTML)
        self.assertIn("if (!recordingStored)", HTML)
        failure = HTML.index("if (!recordingStored)")
        meeting = HTML.index("saveMeetingFromLive(elapsed", failure)
        self.assertLess(failure, meeting)
        self.assertIn("document.addEventListener('visibilitychange'", HTML)

    def test_live_view_opens_only_after_media_recorder_starts(self):
        start_call = HTML.index("recordingStarted = !!(window.__pronoteRecording")
        start_result = HTML.index("if (!recordingStarted) return;", start_call)
        live_view = HTML.index("switchView('live')", start_result)
        self.assertLess(start_call, start_result)
        self.assertLess(start_result, live_view)
        self.assertIn("await window.__pronoteRecording.start('realtime'", HTML)
        self.assertIn("마이크·카메라 연결 중…", HTML)
        self.assertNotIn("REC · 00:23:14", HTML)
        self.assertNotIn("녹음 중 · 00:23:14", HTML)

    def test_file_import_uses_one_validated_flow(self):
        self.assertIn('id="libraryUploadBtn"', HTML)
        self.assertIn('id="libraryEmptyUploadBtn"', HTML)
        self.assertIn("importFiles: importFilesAndChoose", HTML)
        self.assertIn("window.__pronoteLibrary.importFiles([file])", HTML)
        self.assertIn("512 * 1024 * 1024", HTML)
        self.assertIn("const timer = setTimeout(() => finish(0), 8000)", HTML)
        self.assertIn('role="status" aria-live="polite"', HTML)
        self.assertNotIn('id="libraryFileInput" accept="audio/*', HTML)

    def test_mac_beta_has_three_ai_login_and_safe_launchers(self):
        mac = ROOT / "mac"
        for name in ("1_FIRST_SETUP.command", "2_AI_LOGIN.command", "3_START_AI_PRONOTE.command", "STOP_AI_PRONOTE.command"):
            self.assertTrue((mac / name).exists())
        login = (mac / "2_AI_LOGIN.command").read_text(encoding="utf-8")
        for marker in ("claude", "@google/gemini-cli", "@openai/codex"):
            self.assertIn(marker, login)
        start = (mac / "3_START_AI_PRONOTE.command").read_text(encoding="utf-8")
        setup = (mac / "1_FIRST_SETUP.command").read_text(encoding="utf-8")
        self.assertIn('PRONOTE_HOST="127.0.0.1"', start)
        self.assertIn('PRONOTE_EXPERIMENTAL_CLI="true"', start)
        self.assertIn('python3 -m venv .venv', setup)
        self.assertIn('.venv/bin/python', start)
        self.assertIn('EXPECTED_VERSION="v1.5.0-p0"', start)
        self.assertIn('health_version()', start)
        self.assertIn('kill -0 "$owner"', start)
        self.assertIn('trap on_error ERR', setup)

    def test_external_beta_uses_an_isolated_python_environment(self):
        installer = (ROOT / "install_external_beta.ps1").read_text(encoding="utf-8")
        launcher = (ROOT / "start_v15.ps1").read_text(encoding="utf-8")
        self.assertIn("-m venv", installer)
        self.assertIn("requirements-lock.txt", installer)
        self.assertIn("venvArchitecture", installer)
        self.assertIn("amd64|x86_64", installer)
        self.assertIn(".venv\\Scripts\\python.exe", installer)
        self.assertIn(".venv\\Scripts\\pythonw.exe", launcher)
        self.assertNotIn("2_CLAUDE_LOGIN.cmd", installer)
        self.assertIn("64비트 Python", installer)
        self.assertIn("-gt 12", installer)

    def test_permanent_delete_clears_server_and_browser_namespaces(self):
        self.assertIn("fetch('/api/data/purge'", HTML)
        self.assertIn("AI PRONOTE 데이터 영구 삭제", HTML)
        self.assertIn("k.startsWith('ai_pronote.')", HTML)
        self.assertIn("Object.keys(sessionStorage)", HTML)
        self.assertIn("window.__pronoteRecording?.isActive?.()", HTML)
        self.assertIn("window.__pronoteDeletionInProgress", HTML)
        self.assertIn("Promise.allSettled", HTML)
        self.assertIn("pronote_claude_override", HTML)
        self.assertIn("if (result?.error) throw result.error", HTML)
        self.assertIn("window.__pronoteImportCount", HTML)
        self.assertIn("accountDeleteButton.setAttribute('aria-busy', 'true')", HTML)

    def test_safe_diagnostics_excludes_meeting_content_and_secrets(self):
        self.assertIn('id="diagnosticExportBtn"', HTML)
        self.assertIn("format: 'ai-pronote-safe-diagnostics'", HTML)
        self.assertIn("schema_version: 1", HTML)
        self.assertIn("'meeting_content', 'transcript', 'summary', 'notes', 'titles', 'filenames'", HTML)
        self.assertIn("'audio_video_blob', 'credentials_tokens', 'email_name', 'exact_file_paths'", HTML)
        self.assertIn("safeJsonArrayCount('ai_pronote.meetings.v1')", HTML)
        self.assertIn('AI_PRONOTE_진단정보_', HTML)
        self.assertIn('function coarseBrowserEnvironment()', HTML)
        self.assertNotIn("browser: navigator.userAgent", HTML)
        self.assertIn('if (diagnosticExportInProgress) return;', HTML)
        self.assertIn('setTimeout(() => URL.revokeObjectURL(url), 60000)', HTML)


if __name__ == "__main__":
    unittest.main()
