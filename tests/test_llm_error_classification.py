import unittest

from main import LLMError, _classify_llm_error, call_llm


class LlmErrorClassificationTests(unittest.TestCase):
    def test_gemini_unsupported_client_is_actionable_and_not_retryable(self):
        kind, message = _classify_llm_error(
            "IneligibleTierError reasonCode: UNSUPPORTED_CLIENT client is no longer supported",
            "gemini",
        )
        self.assertEqual(kind, "account_unsupported")
        self.assertIn("Gemini", message)
        self.assertIn("공식 API", message)

    def test_provider_specific_auth_and_rate_messages(self):
        self.assertEqual(_classify_llm_error("401 not logged in", "codex")[0], "auth")
        self.assertIn("Codex", _classify_llm_error("401 not logged in", "codex")[1])
        self.assertIn("Gemini", _classify_llm_error("429 rate limit", "gemini")[1])

    def test_gemini_cli_is_blocked_before_subprocess_or_feature_flag(self):
        with self.assertRaises(LLMError) as caught:
            call_llm("gemini_cli", "system", "prompt", "private meeting")
        self.assertEqual(caught.exception.kind, "policy")
        self.assertIn("공식 Gemini API", str(caught.exception))

    def test_router_rejects_unknown_and_legacy_aliases(self):
        providers = ("unknown", "claude", "codex", " gemini_cli ")
        for provider in providers:
            with self.subTest(provider=provider), self.assertRaises(LLMError) as caught:
                call_llm(provider, "system", "prompt", "private meeting")
            self.assertEqual(caught.exception.kind, "policy")


if __name__ == "__main__":
    unittest.main()
