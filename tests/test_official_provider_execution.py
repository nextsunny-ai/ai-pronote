import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient

import main
from secure_credentials import MemoryCredentialStore


class OfficialProviderExecutionTests(unittest.TestCase):
    def setUp(self):
        self.store = MemoryCredentialStore()
        for provider in ("openai", "gemini", "anthropic"):
            self.store.set(provider, "test-secret-value")

    def test_openai_response_contract(self):
        captured = {}

        def fake_post(url, payload, headers, timeout):
            captured.update(url=url, payload=payload, headers=headers, timeout=timeout)
            return {"output_text": "회의 후속 작업입니다."}

        with patch.object(main, "_credential_store", return_value=self.store), patch.object(main, "_post_json", side_effect=fake_post):
            text = main.call_official_api("openai", "system", "prompt", "context", "gpt-5-mini", 30)
        self.assertEqual(text, "회의 후속 작업입니다.")
        self.assertEqual(captured["url"], "https://api.openai.com/v1/responses")
        self.assertFalse(captured["payload"]["store"])
        self.assertEqual(captured["headers"]["Authorization"], "Bearer test-secret-value")

    def test_gemini_response_contract(self):
        with patch.object(main, "_credential_store", return_value=self.store), patch.object(
            main, "_post_json", return_value={"candidates": [{"content": {"parts": [{"text": "Gemini 결과"}]}}]},
        ) as post:
            text = main.call_official_api("gemini", "system", "prompt", "", "gemini-2.5-flash", 30)
        self.assertEqual(text, "Gemini 결과")
        self.assertIn("models/gemini-2.5-flash:generateContent", post.call_args.args[0])
        self.assertEqual(post.call_args.args[2]["x-goog-api-key"], "test-secret-value")

    def test_anthropic_response_contract(self):
        with patch.object(main, "_credential_store", return_value=self.store), patch.object(
            main, "_post_json", return_value={"content": [{"type": "text", "text": "Claude 결과"}]},
        ) as post:
            text = main.call_official_api("anthropic", "system", "prompt", "", "claude-haiku-4-5-20251001", 30)
        self.assertEqual(text, "Claude 결과")
        self.assertEqual(post.call_args.args[0], "https://api.anthropic.com/v1/messages")
        self.assertEqual(post.call_args.args[2]["anthropic-version"], "2023-06-01")

    def test_call_llm_routes_official_provider(self):
        with patch.object(main, "call_official_api", return_value="공식 API 결과") as call:
            result = main.call_llm("gemini", "system", "prompt", "context", model_alias="gemini-2.5-flash")
        self.assertEqual(result, "공식 API 결과")
        self.assertEqual(call.call_args.args[0], "gemini")

    def test_credential_endpoint_requires_explicit_local_action(self):
        class FakeVault:
            def __init__(self): self.values = {}
            def get(self, provider): return self.values.get(provider)
            def set(self, provider, value): self.values[provider] = value
            def delete(self, provider): self.values.pop(provider, None)

        vault = FakeVault()
        client = TestClient(main.app)
        with patch.object(main, "_credential_store", return_value=vault):
            denied = client.post("/api/v15/providers/openai/credential", json={"secret": "secret-value"})
            saved = client.post(
                "/api/v15/providers/openai/credential",
                json={"secret": "secret-value"},
                headers={"X-Pronote-Credential": "store"},
            )
            deleted = client.delete(
                "/api/v15/providers/openai/credential",
                headers={"X-Pronote-Credential": "delete"},
            )
        self.assertEqual(denied.status_code, 403)
        self.assertEqual(saved.status_code, 200)
        self.assertNotIn("secret-value", saved.text)
        self.assertEqual(deleted.status_code, 200)
        self.assertEqual(vault.values, {})


if __name__ == "__main__":
    unittest.main()
