import os
import unittest
from pathlib import Path

from provider_api import (
    AnthropicAdapter,
    GeminiAdapter,
    MockAdapter,
    OpenAIAdapter,
    ProviderRegistry,
    CodexCliAdapter,
    ClaudeCliAdapter,
    GeminiCliAdapter,
)
from secure_credentials import MemoryCredentialStore
from secure_credentials import CredentialBackendError


ROOT = Path(__file__).resolve().parents[1]


class ProviderContractTests(unittest.TestCase):
    def test_frontend_explains_all_expected_connection_states(self):
        html = (ROOT / "static" / "index.html").read_text(encoding="utf-8")
        for state in ("not_installed", "login_required", "expired", "cancelled", "network_error", "error"):
            self.assertIn(state, html)
        self.assertIn("BYOK", html)
        self.assertIn("experimental", html.lower())

    def test_official_adapters_share_contract_without_real_keys(self):
        store = MemoryCredentialStore()
        registry = ProviderRegistry(store=store, allow_experimental_cli=False)
        self.assertEqual({"openai", "gemini", "anthropic", "mock"}, set(registry.public_names()))
        for adapter_type in (OpenAIAdapter, GeminiAdapter, AnthropicAdapter, MockAdapter):
            adapter = adapter_type(store)
            status = adapter.status()
            self.assertIn(status.state, {"needs_key", "ready", "mock"})
            self.assertTrue(status.models)

    def test_memory_store_never_uses_environment_or_disk(self):
        store = MemoryCredentialStore()
        store.set("openai", "secret-test-value")
        self.assertEqual("secret-test-value", store.get("openai"))
        self.assertNotIn("secret-test-value", repr(store))
        self.assertFalse(any(v == "secret-test-value" for v in os.environ.values()))

    def test_cli_is_feature_flagged_out_of_public_default(self):
        store = MemoryCredentialStore()
        self.assertNotIn("claude_cli", ProviderRegistry(store, False).names())
        names = ProviderRegistry(store, True).names()
        self.assertTrue({"codex_cli", "claude_cli"}.issubset(names))
        self.assertNotIn("gemini_cli", names)
        self.assertFalse(any(name.endswith("_cli") for name in ProviderRegistry(store, True).public_names()))

    def test_cli_status_probe_is_read_only_and_handles_all_states(self):
        store = MemoryCredentialStore()
        for adapter_type in (CodexCliAdapter, ClaudeCliAdapter, GeminiCliAdapter):
            adapter = adapter_type(store)
            adapter._installed = lambda: False
            self.assertEqual("not_installed", adapter.status().state)
            adapter._installed = lambda: True
            adapter._logged_in = lambda: False
            self.assertEqual("login_required", adapter.status().state)
            adapter._logged_in = lambda: True
            self.assertEqual("ready", adapter.status().state)

    def test_frontend_has_consent_and_no_key_persistence(self):
        html = (ROOT / "static" / "index.html").read_text(encoding="utf-8")
        self.assertIn('id="providerConsent"', html)
        self.assertIn('id="officialProviderSelect"', html)
        self.assertIn('id="officialApiKey"', html)
        self.assertIn('id="officialCredentialSave"', html)
        self.assertIn('id="officialCredentialDelete"', html)
        self.assertIn('API 키는 이 브라우저에 저장하지 않습니다', html)
        self.assertIn('id="experimentalCliPanel" hidden', html)
        self.assertIn('Codex CLI (실험)', html)
        self.assertIn('Gemini CLI — 앱 연결 안 함', html)
        self.assertIn('data-policy-blocked="true"', html)
        self.assertIn('aria-disabled="true"', html)
        self.assertIn("return 'policy_blocked';", html)
        self.assertNotIn("window.__pronoteGetAIProvider() : 'claude_cli'", html)
        self.assertIn("if (selectedProvider() !== 'claude_cli')", html)
        self.assertIn("if (provider === 'policy_blocked')", html)
        self.assertIn("if (provider === 'claude_cli' && ai", html)
        self.assertIn("value === 'openai_api'", html)
        self.assertIn("value === 'gemini_api'", html)
        self.assertIn("value === 'anthropic_api'", html)
        self.assertIn('window.__pronoteExternalConsent', html)
        self.assertIn("'X-Pronote-Credential': 'store'", html)
        self.assertNotIn('챗GPT (Plus 구독)', html)
        self.assertNotIn("localStorage.setItem('api_key'", html)
        self.assertNotIn('localStorage.setItem("api_key"', html)

    def test_credential_backend_failure_is_sanitized_per_provider(self):
        class FailingStore:
            def get(self, provider): raise CredentialBackendError("private backend detail")
            def set(self, provider, secret): raise AssertionError
            def delete(self, provider): raise AssertionError
        statuses = ProviderRegistry(FailingStore(), False).statuses()
        official = [item for item in statuses if item["name"] != "mock"]
        self.assertTrue(all(item["state"] == "error" for item in official))
        self.assertFalse(any("private backend detail" in item["message"] for item in statuses))

    def test_server_enforces_consent_and_cli_feature_flag(self):
        source = (ROOT / "main.py").read_text(encoding="utf-8")
        self.assertGreaterEqual(source.count('raise HTTPException(403, "외부 AI 전송 동의가 필요합니다")'), 5)
        self.assertIn('PRONOTE_EXPERIMENTAL_CLI', source)
        self.assertIn('구독형 CLI 경로는 공개 기본 설정에서 비활성화', source)
        self.assertIn('Gemini CLI 로그인은 공급자 정책상 앱 연결에 사용할 수 없습니다', source)


if __name__ == "__main__":
    unittest.main()
