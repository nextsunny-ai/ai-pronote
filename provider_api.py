"""Official API provider contracts without network side effects or embedded keys."""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import shutil
from typing import Literal, Protocol

from secure_credentials import CredentialBackendError, CredentialStore


@dataclass(frozen=True)
class ProviderStatus:
    name: str
    state: Literal["ready", "needs_key", "mock", "experimental", "error", "not_installed", "login_required"]
    models: tuple[str, ...]
    message: str
    sends_data_externally: bool


class ProviderAdapter(Protocol):
    name: str
    models: tuple[str, ...]
    def status(self) -> ProviderStatus: ...


class _OfficialAdapter:
    name = ""
    models: tuple[str, ...] = ()

    def __init__(self, store: CredentialStore) -> None:
        self.store = store

    def status(self) -> ProviderStatus:
        try:
            ready = bool(self.store.get(self.name))
        except CredentialBackendError:
            return ProviderStatus(self.name, "error", self.models, "Windows 자격 증명 상태를 확인하지 못했습니다.", True)
        return ProviderStatus(
            self.name, "ready" if ready else "needs_key", self.models,
            "Windows 자격 증명에 키가 있습니다." if ready else "대표님 승인 후 API 키 등록이 필요합니다.",
            True,
        )


class OpenAIAdapter(_OfficialAdapter):
    name = "openai"
    models = ("gpt-5-mini", "gpt-5.1")


class GeminiAdapter(_OfficialAdapter):
    name = "gemini"
    models = ("gemini-2.5-flash", "gemini-2.5-pro")


class AnthropicAdapter(_OfficialAdapter):
    name = "anthropic"
    models = ("claude-sonnet-5", "claude-haiku-4-5-20251001")


class MockAdapter:
    name = "mock"
    models = ("mock-safe",)

    def __init__(self, store: CredentialStore) -> None:
        self.store = store

    def status(self) -> ProviderStatus:
        return ProviderStatus(self.name, "mock", self.models, "네트워크·키 없는 계약 테스트 전용", False)


class ExperimentalCliAdapter(MockAdapter):
    """Read-only view of a locally installed CLI subscription session."""

    name = ""
    models = ("subscription-experimental",)
    executable = ""
    auth_markers: tuple[Path, ...] = ()

    def _installed(self) -> bool:
        return shutil.which(self.executable) is not None

    def _logged_in(self) -> bool:
        return any(path.expanduser().exists() for path in self.auth_markers)

    def status(self) -> ProviderStatus:
        if not self._installed():
            message = "CLI가 설치되지 않았습니다. 로그인 실행은 이 화면에서 하지 않습니다."
            state = "not_installed"
        elif not self._logged_in():
            message = "CLI는 설치되어 있으나 로그인이 필요합니다. 취소·실패 시 연결되지 않은 상태로 유지됩니다."
            state = "login_required"
        else:
            message = "기존 로컬 로그인 흔적을 확인했습니다. 세션이나 키는 변경하지 않았습니다."
            state = "ready"
        return ProviderStatus(self.name, state, self.models, message, True)


class CodexCliAdapter(ExperimentalCliAdapter):
    name = "codex_cli"
    executable = "codex"
    auth_markers = (Path("~/.codex/auth.json"),)


class ClaudeCliAdapter(ExperimentalCliAdapter):
    name = "claude_cli"
    executable = "claude"
    auth_markers = (Path("~/.claude/.credentials.json"), Path("~/.claude.json"))


class GeminiCliAdapter(ExperimentalCliAdapter):
    name = "gemini_cli"
    executable = "gemini"
    auth_markers = (Path("~/.gemini/oauth_creds.json"),)


class ProviderRegistry:
    def __init__(self, store: CredentialStore, allow_experimental_cli: bool = False) -> None:
        adapters: list[ProviderAdapter] = [OpenAIAdapter(store), GeminiAdapter(store), AnthropicAdapter(store), MockAdapter(store)]
        if allow_experimental_cli:
            adapters.extend((CodexCliAdapter(store), ClaudeCliAdapter(store)))
        self._adapters = {adapter.name: adapter for adapter in adapters}

    def names(self) -> tuple[str, ...]:
        return tuple(self._adapters)

    def public_names(self) -> tuple[str, ...]:
        return tuple(name for name in self._adapters if not name.endswith("_cli"))

    def statuses(self) -> list[dict]:
        return [status.__dict__ for status in (adapter.status() for adapter in self._adapters.values())]
