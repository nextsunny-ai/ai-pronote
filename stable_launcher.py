"""Stable, version-independent launcher for side-by-side AI PRONOTE installs."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

from updater import read_active_version, rollback_active_version


class LauncherError(RuntimeError):
    pass


def resolve_launch_target(install_root: Path, platform: str) -> Path:
    install_root = Path(install_root).resolve()
    try:
        state = json.loads((install_root / "active-version.json").read_text(encoding="utf-8"))
        version = state["active_version"]
    except (OSError, json.JSONDecodeError, KeyError, TypeError) as exc:
        raise LauncherError("활성 버전 정보가 없습니다") from exc
    if not isinstance(version, str) or not version or any(part in ("", "..") for part in Path(version).parts):
        raise LauncherError("활성 버전 이름이 올바르지 않습니다")
    version_root = (install_root / "versions" / version).resolve()
    versions_root = (install_root / "versions").resolve()
    if versions_root not in version_root.parents or not (version_root / "main.py").is_file():
        raise LauncherError("활성 버전 파일이 준비되지 않았습니다")
    relative = "start_v15.ps1" if platform == "windows" else "mac/3_START_AI_PRONOTE.command"
    target = version_root / relative
    if not target.is_file():
        raise LauncherError("운영체제용 실행 파일이 없습니다")
    return target


def _launch_target(target: Path) -> None:
    env = os.environ.copy()
    version_root = target.parent.parent if target.parent.name == "mac" else target.parent
    if version_root.parent.name == "versions":
        install_root = version_root.parent.parent
        runtime_root = install_root / "runtime" / "versions" / version_root.name
        runtime_python = runtime_root / ("Scripts/python.exe" if target.suffix.lower() == ".ps1" else "bin/python")
        if runtime_python.is_file() and (runtime_root / ".runtime-complete.json").is_file():
            env["PRONOTE_SHARED_VENV"] = str(runtime_root)
    if target.suffix.lower() == ".ps1":
        system_root = Path(os.environ.get("SystemRoot", r"C:\Windows"))
        powershell = system_root / "System32" / "WindowsPowerShell" / "v1.0" / "powershell.exe"
        if not powershell.is_file():
            raise LauncherError("Windows PowerShell 실행 파일을 찾을 수 없습니다")
        subprocess.Popen(
            [str(powershell), "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(target)],
            cwd=target.parent,
            env=env,
        )
    else:
        subprocess.Popen(["/bin/zsh", str(target)], cwd=target.parent.parent, env=env)


def _read_health() -> dict | None:
    try:
        port = os.environ.get("PRONOTE_PORT", "8795")
        if not port.isdigit() or not 1 <= int(port) <= 65535:
            return None
        with urllib.request.urlopen(f"http://127.0.0.1:{port}/api/health", timeout=2) as response:
            data = json.loads(response.read(64 * 1024).decode("utf-8"))
        return data if isinstance(data, dict) else None
    except Exception:
        return None


def launch_with_health_check(
    install_root: Path,
    platform: str,
    *,
    launcher=_launch_target,
    health_reader=_read_health,
    timeout_seconds: float = 45,
    poll_seconds: float = 0.5,
) -> str:
    """Launch active version, then rollback and relaunch once if health never matches."""
    install_root = Path(install_root)
    active = read_active_version(install_root)
    if not active:
        raise LauncherError("활성 버전 정보가 없습니다")
    def wait_for(version: str) -> bool:
        deadline = time.monotonic() + max(0, timeout_seconds)
        while True:
            health = health_reader()
            if health and health.get("status") == "ok" and health.get("version") == version:
                return True
            if time.monotonic() >= deadline:
                return False
            time.sleep(max(0, poll_seconds))

    launcher(resolve_launch_target(install_root, platform))
    if wait_for(active):
        return active
    try:
        rollback_root = rollback_active_version(install_root)
        rollback_version = rollback_root.name
        launcher(resolve_launch_target(install_root, platform))
        if wait_for(rollback_version):
            return rollback_version
        raise LauncherError("이전 버전도 정상 상태를 확인하지 못했습니다")
    except Exception as exc:
        raise LauncherError("새 버전 시작과 이전 버전 복구에 실패했습니다") from exc


def main() -> int:
    default_root = (
        Path(os.environ.get("LOCALAPPDATA", Path.home())) / "AI_PRONOTE" / "v1.5" / "install"
        if os.name == "nt"
        else Path.home() / "Library" / "Application Support" / "AI_PRONOTE" / "v1.5" / "install"
    )
    install_root = Path(os.environ.get("PRONOTE_INSTALL_ROOT", default_root))
    platform = "windows" if os.name == "nt" else "mac"
    try:
        try:
            health_timeout = float(os.environ.get("PRONOTE_UPDATE_HEALTH_TIMEOUT", "45"))
        except ValueError:
            health_timeout = 45
        health_timeout = min(120, max(5, health_timeout))
        launch_with_health_check(install_root, platform, timeout_seconds=health_timeout)
        return 0
    except (LauncherError, OSError) as exc:
        print(f"AI PRONOTE 시작 실패: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

