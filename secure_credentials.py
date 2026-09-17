"""Credential storage abstraction for official BYOK providers.

The production store uses Windows Credential Manager. Importing this module never
reads or writes credentials; explicit user-approved setup must call set().
"""
from __future__ import annotations

import ctypes
from ctypes import wintypes
from typing import Protocol


SERVICE_PREFIX = "AI_PRONOTE/v1.5/provider/"
CRED_TYPE_GENERIC = 1
CRED_PERSIST_LOCAL_MACHINE = 2
ERROR_NOT_FOUND = 1168


class CredentialBackendError(RuntimeError):
    """Sanitized Credential Manager failure; never includes credential data."""


class CredentialStore(Protocol):
    def get(self, provider: str) -> str | None: ...
    def set(self, provider: str, secret: str) -> None: ...
    def delete(self, provider: str) -> None: ...


class MemoryCredentialStore:
    """Non-persistent test double. Never touches disk, environment, or browser."""

    def __init__(self) -> None:
        self._values: dict[str, str] = {}

    def get(self, provider: str) -> str | None:
        return self._values.get(provider)

    def set(self, provider: str, secret: str) -> None:
        if not secret:
            raise ValueError("empty credential")
        self._values[provider] = secret

    def delete(self, provider: str) -> None:
        self._values.pop(provider, None)

    def __repr__(self) -> str:
        return f"MemoryCredentialStore(providers={sorted(self._values)})"


class _CREDENTIALW(ctypes.Structure):
    _fields_ = [
        ("Flags", wintypes.DWORD), ("Type", wintypes.DWORD),
        ("TargetName", wintypes.LPWSTR), ("Comment", wintypes.LPWSTR),
        ("LastWritten", wintypes.FILETIME), ("CredentialBlobSize", wintypes.DWORD),
        ("CredentialBlob", ctypes.POINTER(ctypes.c_ubyte)),
        ("Persist", wintypes.DWORD), ("AttributeCount", wintypes.DWORD),
        ("Attributes", wintypes.LPVOID), ("TargetAlias", wintypes.LPWSTR),
        ("UserName", wintypes.LPWSTR),
    ]


class WindowsCredentialStore:
    """Windows Credential Manager backend; secrets are not persisted by this app elsewhere."""

    def __init__(self, prefix: str = SERVICE_PREFIX) -> None:
        if not hasattr(ctypes, "WinDLL"):
            raise RuntimeError("Windows Credential Manager is only available on Windows")
        self.prefix = prefix
        self._advapi = ctypes.WinDLL("advapi32", use_last_error=True)
        self._advapi.CredReadW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD, ctypes.POINTER(ctypes.POINTER(_CREDENTIALW))]
        self._advapi.CredReadW.restype = wintypes.BOOL
        self._advapi.CredWriteW.argtypes = [ctypes.POINTER(_CREDENTIALW), wintypes.DWORD]
        self._advapi.CredWriteW.restype = wintypes.BOOL
        self._advapi.CredDeleteW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD]
        self._advapi.CredDeleteW.restype = wintypes.BOOL
        self._advapi.CredFree.argtypes = [wintypes.LPVOID]
        self._advapi.CredFree.restype = None

    def _target(self, provider: str) -> str:
        if provider not in {"openai", "gemini", "anthropic"}:
            raise ValueError("unsupported provider")
        return self.prefix + provider

    def get(self, provider: str) -> str | None:
        pointer = ctypes.POINTER(_CREDENTIALW)()
        if not self._advapi.CredReadW(self._target(provider), CRED_TYPE_GENERIC, 0, ctypes.byref(pointer)):
            error = ctypes.get_last_error()
            if error == ERROR_NOT_FOUND:
                return None
            raise CredentialBackendError(f"Credential Manager read failed ({error})")
        try:
            cred = pointer.contents
            raw = ctypes.string_at(cred.CredentialBlob, cred.CredentialBlobSize)
            return raw.decode("utf-16-le")
        finally:
            self._advapi.CredFree(pointer)

    def set(self, provider: str, secret: str) -> None:
        if not secret:
            raise ValueError("empty credential")
        raw = secret.encode("utf-16-le")
        blob = (ctypes.c_ubyte * len(raw)).from_buffer_copy(raw)
        cred = _CREDENTIALW(Type=CRED_TYPE_GENERIC, TargetName=self._target(provider),
                            CredentialBlobSize=len(raw), CredentialBlob=blob,
                            Persist=CRED_PERSIST_LOCAL_MACHINE, UserName="AI PRONOTE")
        if not self._advapi.CredWriteW(ctypes.byref(cred), 0):
            error = ctypes.get_last_error()
            raise CredentialBackendError(f"Credential Manager write failed ({error})")

    def delete(self, provider: str) -> None:
        if not self._advapi.CredDeleteW(self._target(provider), CRED_TYPE_GENERIC, 0):
            error = ctypes.get_last_error()
            if error != ERROR_NOT_FOUND:
                raise CredentialBackendError(f"Credential Manager delete failed ({error})")
