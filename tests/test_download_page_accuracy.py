import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class DownloadPageAccuracyTests(unittest.TestCase):
    def test_ai_connection_copy_names_real_connection_methods(self):
        html = (ROOT / "docs" / "index.html").read_text(encoding="utf-8")

        self.assertIn("Claude 또는 ChatGPT/Codex", html)
        self.assertIn("Gemini는 공식 API 키", html)
        self.assertNotIn("Claude, ChatGPT/Codex 또는 Gemini 연결", html)

    def test_ipad_copy_scopes_companion_mode_to_current_beta(self):
        html = (ROOT / "docs" / "index.html").read_text(encoding="utf-8")

        self.assertIn("현재 Beta10의 iPad·휴대폰 사용", html)
        self.assertIn("iPad 네이티브 앱은 별도 배포 준비 중", html)
        self.assertNotIn("휴대폰·iPad 사용</strong> · 별도 앱을 내려받는 방식이 아닙니다", html)

    def test_login_free_transcription_is_scoped_to_desktop_beta(self):
        html = (ROOT / "docs" / "index.html").read_text(encoding="utf-8")

        self.assertIn("Windows·Mac에서는", html)
        self.assertNotIn("네. 일반 녹음, 영상 녹화, 기본 받아쓰기와 필기는", html)


if __name__ == "__main__":
    unittest.main()
