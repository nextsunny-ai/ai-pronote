import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]
DOCS = [
    ROOT / "빠른시작_가이드.md",
    ROOT / "상황별_사용가이드.md",
    ROOT / "AI_PRONOTE_사용설명서.md",
    ROOT / "docs" / "FAQ_외부베타_v1.md",
    ROOT / "docs" / "휴대폰_iPad_사용가이드.md",
    ROOT / "docs" / "지원환경_v1.md",
    ROOT / "docs" / "알려진_제한_v1.md",
    ROOT / "SECURITY.md",
]


class ReleaseDocsConsistencyTests(unittest.TestCase):
    def test_current_processing_label_is_used(self):
        for path in DOCS:
            text = path.read_text(encoding="utf-8-sig")
            self.assertNotIn("작업함", text, path.name)

    def test_obsolete_version_and_api_key_first_copy_are_removed(self):
        combined = "\n".join(path.read_text(encoding="utf-8-sig") for path in DOCS)
        self.assertNotRegex(combined, r"v1\.5\.0-beta13\.20260920\.4(?!\d)")
        self.assertNotIn("AI 연결 · 개인 API 키", combined)
        self.assertNotIn("로그인 없이", combined)

    def test_account_roles_and_mobile_entry_are_documented(self):
        manual = (ROOT / "AI_PRONOTE_사용설명서.md").read_text(encoding="utf-8-sig")
        mobile = (ROOT / "docs" / "휴대폰_iPad_사용가이드.md").read_text(encoding="utf-8-sig")
        self.assertIn("앱 계정과 AI 계정은 별개", manual)
        self.assertIn("처리 중", manual)
        self.assertIn("브라우저 동반 사용 방식", mobile)
        self.assertIn("네이티브 iPad 앱이나 App Store 출시본으로 안내하지 않습니다", mobile)
        self.assertNotIn("같은 Wi-Fi", mobile)

    def test_current_beta_does_not_claim_cloud_sync_or_subscription_management(self):
        combined = "\n".join(path.read_text(encoding="utf-8-sig") for path in DOCS)
        for unsupported in ("내 자료와 구독을 관리", "동기화·구독을 관리"):
            self.assertNotIn(unsupported, combined)
        self.assertIn("이 기기", combined)
        self.assertIn("클라우드 동기화", combined)

    def test_public_manual_titles_use_product_version_one(self):
        for path in DOCS[:4]:
            title = path.read_text(encoding="utf-8-sig").splitlines()[0]
            self.assertIn("AI PRONOTE 1.0", title, path.name)
            self.assertNotIn("v1.5", title, path.name)

    def test_quick_start_uses_current_import_actions(self):
        guide = (ROOT / "빠른시작_가이드.md").read_text(encoding="utf-8-sig")
        self.assertIn("왼쪽의 `받아쓰기`", guide)
        self.assertIn("`받아쓰기만`", guide)
        self.assertIn("`받아쓰기 + AI 회의록`", guide)
        self.assertIn("`작업 기록`", guide)
        self.assertIn("`1_FIRST_SETUP.cmd`", guide)
        self.assertNotIn("`파일로 회의록 만들기`", guide)
        self.assertNotIn("`받아쓰기·회의록 만들기`", guide)

    def test_scenario_guide_uses_current_navigation_and_manual_record_start(self):
        guide = (ROOT / "상황별_사용가이드.md").read_text(encoding="utf-8-sig")
        self.assertIn("새 회의 준비창", guide)
        self.assertIn("`녹음 시작`을 눌러야", guide)
        self.assertIn("왼쪽 `받아쓰기`", guide)
        self.assertIn("`작업 기록`", guide)
        self.assertIn("Claude와 ChatGPT", guide)
        self.assertIn("Gemini는 공식 API 키", guide)
        self.assertNotIn("`파일 가져오기`", guide)
        self.assertNotIn("`회의 기록`", guide)
        self.assertNotIn("음성 녹음이 바로 시작", guide)

    def test_public_readme_uses_product_version_one(self):
        readme = (ROOT / "README.md").read_text(encoding="utf-8-sig")
        self.assertEqual(readme.splitlines()[0].strip(), "# AI PRONOTE 1.0")

    def test_release_scope_copy_matches_current_rc(self):
        combined = "\n".join(path.read_text(encoding="utf-8-sig") for path in DOCS)
        self.assertNotIn("RC29", combined)
        self.assertNotIn("RC31", combined)
        self.assertIn("1.0.10", combined)
        self.assertIn("Mac 독립 설치판은 이번 1.0.10", combined)
        self.assertIn("Gemini CLI 로그인은 사용하지 않으며 공식 Gemini API", combined)
        self.assertIn("PC 동반형", combined)


if __name__ == "__main__":
    unittest.main()
