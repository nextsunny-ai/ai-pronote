import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class DownloadPageAccuracyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.html = (ROOT / "docs" / "index.html").read_text(encoding="utf-8")

    def test_korean_copy_is_valid_utf8_without_replacement_characters(self):
        self.assertNotIn("\ufffd", self.html)
        self.assertIn('lang="ko"', self.html)

    def test_ai_connection_copy_names_real_connection_methods(self):
        self.assertIn("Claude", self.html)
        self.assertIn("ChatGPT", self.html)
        self.assertIn("Gemini", self.html)
        self.assertNotIn("ChatGPT/Codex", self.html)

    def test_ipad_copy_scopes_companion_mode_to_current_beta(self):
        self.assertIn("iPad", self.html)
        self.assertIn("iPhone", self.html)
        self.assertIn("IPAD / IPHONE", self.html)
        self.assertIn("Android", self.html)
        self.assertIn("Mac", self.html)

    def test_login_free_transcription_is_scoped_to_desktop_beta(self):
        self.assertIn("WINDOWS 10 / 11", self.html)
        self.assertIn("PRIVATE BETA", self.html)
        self.assertIn("AI_PRONOTE_1.0.10_Windows_Private_Beta.zip", self.html)
        self.assertIn("C3C4B41BA407527B8E9BAFBC0CAE671EE19C6051A314857DE1F0260A917D72BD", self.html)


if __name__ == "__main__":
    unittest.main()

