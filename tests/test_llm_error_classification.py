import unittest

from main import _classify_llm_error


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


if __name__ == "__main__":
    unittest.main()
