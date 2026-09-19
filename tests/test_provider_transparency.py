import unittest
from unittest.mock import patch

import main
from fastapi import HTTPException


class ProviderTransparencyTests(unittest.TestCase):
    def test_summary_redo_rejects_unknown_provider_before_job_mutation(self):
        with self.assertRaises(HTTPException) as caught:
            main.summarize_redo(
                "missing-job",
                provider="unknown-provider",
                external_consent=True,
            )

        self.assertEqual(caught.exception.status_code, 400)
        self.assertEqual(caught.exception.detail, "지원하지 않는 AI 연결 방식입니다")

    def test_codex_auto_title_and_summary_use_only_codex(self):
        calls = []

        def fake_call(provider, system, prompt, content="", **kwargs):
            calls.append(provider)
            return "Codex 제목" if len(calls) == 1 else "Codex 회의록"

        with patch.object(main, "call_llm", side_effect=fake_call):
            result = main.build_summary(
                "비민감 시험 받아쓰기", provider="codex_cli", auto_title=True
            )

        self.assertEqual(calls, ["codex_cli", "codex_cli"])
        self.assertEqual(result["provider"], "codex_cli")
        self.assertEqual(result["model"], "configured-default")
        self.assertEqual(result["model_id"], "codex-cli-configured-default")

    def test_claude_metadata_keeps_selected_model(self):
        with patch.object(main, "call_llm", return_value="Claude 회의록"):
            result = main.build_summary(
                "비민감 시험 받아쓰기", provider="claude_cli",
                model_alias="haiku", title="제목", auto_title=False,
            )

        self.assertEqual(result["provider"], "claude_cli")
        self.assertEqual(result["model"], "haiku")
        self.assertEqual(result["model_id"], main.CLAUDE_MODELS["haiku"])

    def test_title_endpoint_routes_codex_and_reports_codex_metadata(self):
        with patch.object(main, "generate_title", return_value="Codex 제목") as mocked:
            result = main.llm_title(main.TitleRequest(
                transcript="비민감 시험 받아쓰기",
                provider="codex_cli",
                external_consent=True,
            ))

        mocked.assert_called_once_with(
            "비민감 시험 받아쓰기", model_alias="haiku", provider="codex_cli"
        )
        self.assertEqual(result["provider"], "codex_cli")
        self.assertEqual(result["model"], "configured-default")
        self.assertEqual(result["model_id"], "codex-cli-configured-default")


if __name__ == "__main__":
    unittest.main()
