import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class DownloadPageAccuracyTests(unittest.TestCase):
    def test_ai_connection_copy_matches_current_single_selection_flow(self):
        html = (ROOT / "docs" / "index.html").read_text(encoding="utf-8")

        self.assertIn("Claude 또는 ChatGPT 중 하나를 선택", html)
        self.assertIn("Gemini는 준비 중", html)
        self.assertNotIn("동시에 연결", html)

    def test_platform_copy_scopes_current_beta_without_unverified_mac_download(self):
        html = (ROOT / "docs" / "index.html").read_text(encoding="utf-8")

        self.assertIn("iPad·휴대폰", html)
        self.assertIn("v1.5.0-beta13.20260920.13", html)
        self.assertIn("WINDOWS 10 / 11", html)
        self.assertIn("14.4 MB", html)
        self.assertIn("㈜써니엔터테인먼트", html)
        self.assertIn("대표 승인 전 검토 후보", html)
        self.assertGreaterEqual(html.count("disabled"), 2)
        self.assertNotIn("Mac용 내려받기", html)
        self.assertNotIn("v1.5.0-beta11-20260919", html)
        self.assertNotIn("현재 공개 베타 내려받기", html)
        self.assertNotRegex(html, r'href="[^"]+\.zip"')

    def test_mobile_copy_does_not_claim_independent_app_release(self):
        html = (ROOT / "docs" / "index.html").read_text(encoding="utf-8")

        self.assertIn("독립 설치 앱은 별도 검증 후 제공", html)
        self.assertNotIn("App Store에서 다운로드", html)

    def test_account_copy_matches_local_only_storage_boundary(self):
        html = (ROOT / "docs" / "index.html").read_text(encoding="utf-8")

        self.assertIn("이 기기의 자료를 사용자별로 구분", html)
        self.assertIn("클라우드 동기화는 준비 중", html)
        self.assertNotIn("내 자료와 구독을 관리", html)


if __name__ == "__main__":
    unittest.main()
