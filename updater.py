"""Safe update-manifest validation and side-by-side package staging.

This module deliberately does not replace the running application.  It prepares a
verified version directory which a small stable launcher can activate on restart.
"""

from __future__ import annotations

import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import zipfile
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from urllib.parse import urlparse


class UpdateError(RuntimeError):
    pass


@dataclass(frozen=True)
class UpdateArtifact:
    url: str
    sha256: str
    size: int


@dataclass(frozen=True)
class UpdateManifest:
    schema_version: int
    version: str
    channel: str
    published_at: str
    release_notes_url: str
    artifact: UpdateArtifact


_VERSION = re.compile(r"^v?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?$")
_SHA256 = re.compile(r"^[0-9a-fA-F]{64}$")
_SAFE_VERSION = re.compile(r"^v?[0-9A-Za-z][0-9A-Za-z.-]{0,79}$")
_MAX_PACKAGE_BYTES = 4 * 1024 * 1024 * 1024


def _version_parts(value: str) -> tuple[tuple[int, int, int], tuple[tuple[int, object], ...] | None]:
    match = _VERSION.fullmatch(value.strip())
    if not match:
        raise UpdateError(f"지원하지 않는 버전 형식입니다: {value}")
    core = tuple(int(match.group(i)) for i in range(1, 4))
    prerelease = match.group(4)
    if prerelease is None:
        return core, None
    tokens: list[tuple[int, object]] = []
    for token in re.findall(r"[A-Za-z]+|\d+", prerelease):
        tokens.append((0, int(token)) if token.isdigit() else (1, token.lower()))
    return core, tuple(tokens)


def compare_versions(left: str, right: str) -> int:
    """Return -1, 0 or 1 using SemVer-like stable/prerelease ordering."""
    left_core, left_pre = _version_parts(left)
    right_core, right_pre = _version_parts(right)
    if left_core != right_core:
        return -1 if left_core < right_core else 1
    if left_pre is None and right_pre is None:
        return 0
    if left_pre is None:
        return 1
    if right_pre is None:
        return -1
    if left_pre == right_pre:
        return 0
    return -1 if left_pre < right_pre else 1


def _https_url(value: object, label: str) -> str:
    if not isinstance(value, str):
        raise UpdateError(f"{label} 주소가 없습니다")
    parsed = urlparse(value)
    if parsed.scheme != "https" or not parsed.netloc or parsed.username or parsed.password:
        raise UpdateError(f"{label}는 자격정보가 없는 HTTPS 주소여야 합니다")
    return value


def load_manifest(raw: str, platform: str) -> UpdateManifest:
    try:
        data = json.loads(raw)
    except (TypeError, json.JSONDecodeError) as exc:
        raise UpdateError("업데이트 정보가 올바른 JSON이 아닙니다") from exc
    if not isinstance(data, dict) or data.get("schema_version") != 1:
        raise UpdateError("지원하지 않는 업데이트 정보 형식입니다")
    version = data.get("version")
    if not isinstance(version, str):
        raise UpdateError("업데이트 버전이 없습니다")
    _version_parts(version)
    artifacts = data.get("artifacts")
    item = artifacts.get(platform) if isinstance(artifacts, dict) else None
    if not isinstance(item, dict):
        raise UpdateError(f"{platform} 설치 파일이 없습니다")
    sha256 = item.get("sha256")
    if not isinstance(sha256, str) or not _SHA256.fullmatch(sha256):
        raise UpdateError("설치 파일 SHA-256이 올바르지 않습니다")
    size = item.get("size")
    if not isinstance(size, int) or size <= 0:
        raise UpdateError("설치 파일 크기가 올바르지 않습니다")
    return UpdateManifest(
        schema_version=1,
        version=version,
        channel=str(data.get("channel") or "stable"),
        published_at=str(data.get("published_at") or ""),
        release_notes_url=_https_url(data.get("release_notes_url"), "릴리스 노트"),
        artifact=UpdateArtifact(
            url=_https_url(item.get("url"), "설치 파일"),
            sha256=sha256.lower(),
            size=size,
        ),
    )


def _safe_member(name: str) -> bool:
    path = PurePosixPath(name.replace("\\", "/"))
    return bool(path.parts) and not path.is_absolute() and ".." not in path.parts


def stage_update_archive(archive_path: Path, expected_sha256: str, target: Path) -> Path:
    """Verify and extract a package beside existing versions without overwriting."""
    archive_path = Path(archive_path)
    target = Path(target)
    if target.exists():
        marker = target / ".package-complete.json"
        try:
            completed_hash = json.loads(marker.read_text(encoding="utf-8")).get("sha256")
        except (OSError, json.JSONDecodeError, AttributeError):
            completed_hash = None
        if completed_hash == expected_sha256.lower():
            return target
        raise UpdateError("같은 버전의 불완전하거나 다른 설치 폴더가 이미 있습니다")
    if not _SHA256.fullmatch(expected_sha256 or ""):
        raise UpdateError("예상 SHA-256이 올바르지 않습니다")
    actual = hashlib.sha256(archive_path.read_bytes()).hexdigest()
    if actual.lower() != expected_sha256.lower():
        raise UpdateError("다운로드한 설치 파일의 무결성 검증에 실패했습니다")

    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=f".{target.name}-", dir=target.parent))
    try:
        with zipfile.ZipFile(archive_path) as archive:
            members = archive.infolist()
            if not members or any(not _safe_member(member.filename) for member in members):
                raise UpdateError("설치 파일에 안전하지 않은 경로가 있습니다")
            archive.extractall(temporary)
        roots = [item for item in temporary.iterdir() if item.is_dir()]
        package_root = roots[0] if len(roots) == 1 else temporary
        platform_lock = "requirements-lock-windows.txt" if sys.platform == "win32" else "requirements-lock-mac.txt"
        platform_launcher = "3_START_AI_PRONOTE.vbs" if sys.platform == "win32" else "mac/3_START_AI_PRONOTE.command"
        required = (
            "main.py", "pronote_p0.py", "provider_api.py", "secure_credentials.py", "updater.py",
            platform_lock, platform_launcher, "static/index.html",
        )
        if not all((package_root / item).is_file() for item in required):
            raise UpdateError("설치 파일에 필수 프로그램 파일이 없습니다")
        (package_root / ".package-complete.json").write_text(
            json.dumps({"schema_version": 1, "sha256": expected_sha256.lower()}, indent=2), encoding="utf-8"
        )
        if package_root == temporary:
            temporary.replace(target)
        else:
            package_root.replace(target)
            shutil.rmtree(temporary, ignore_errors=True)
        return target
    except Exception:
        shutil.rmtree(temporary, ignore_errors=True)
        raise


def download_update(
    url: str,
    expected_size: int,
    expected_sha256: str,
    destination: Path,
    *,
    opener=urllib.request.urlopen,
) -> Path:
    """Stream an HTTPS package to a temporary file and publish only after verification."""
    _https_url(url, "설치 파일")
    if not isinstance(expected_size, int) or not 0 < expected_size <= _MAX_PACKAGE_BYTES:
        raise UpdateError("설치 파일 크기가 올바르지 않습니다")
    if not _SHA256.fullmatch(expected_sha256 or ""):
        raise UpdateError("예상 SHA-256이 올바르지 않습니다")
    destination = Path(destination)
    if destination.exists():
        raise UpdateError("다운로드 파일이 이미 있습니다")
    destination.parent.mkdir(parents=True, exist_ok=True)
    partial = destination.with_suffix(destination.suffix + ".partial")
    digest = hashlib.sha256()
    total = 0
    try:
        request = urllib.request.Request(url, headers={"User-Agent": "AI-PRONOTE-Updater/1"})
        with opener(request, timeout=30) as response, partial.open("xb") as output:
            while chunk := response.read(1024 * 1024):
                total += len(chunk)
                if total > expected_size:
                    raise UpdateError("다운로드 크기가 업데이트 정보와 다릅니다")
                output.write(chunk)
                digest.update(chunk)
        if total != expected_size or digest.hexdigest().lower() != expected_sha256.lower():
            raise UpdateError("다운로드한 설치 파일의 무결성 검증에 실패했습니다")
        partial.replace(destination)
        return destination
    except Exception:
        partial.unlink(missing_ok=True)
        raise


def prepare_update(
    manifest: UpdateManifest,
    install_root: Path,
    *,
    opener=urllib.request.urlopen,
) -> Path:
    """Download, verify and stage a version while leaving the active version untouched."""
    install_root = Path(install_root)
    if not _SAFE_VERSION.fullmatch(manifest.version):
        raise UpdateError("업데이트 버전 이름이 올바르지 않습니다")
    target = install_root / "versions" / manifest.version
    download_dir = install_root / "downloads"
    archive_path = download_dir / f"{manifest.version}.zip"
    try:
        download_update(
            manifest.artifact.url,
            manifest.artifact.size,
            manifest.artifact.sha256,
            archive_path,
            opener=opener,
        )
        return stage_update_archive(archive_path, manifest.artifact.sha256, target)
    finally:
        archive_path.unlink(missing_ok=True)
        archive_path.with_suffix(".zip.partial").unlink(missing_ok=True)


def prepare_version_runtime(
    install_root: Path,
    version: str,
    *,
    python_executable: str | Path = sys.executable,
    runner=subprocess.run,
) -> Path:
    """Build a version-isolated runtime completely before making it visible."""
    if not isinstance(version, str) or not _SAFE_VERSION.fullmatch(version):
        raise UpdateError("업데이트 버전 이름이 올바르지 않습니다")
    install_root = Path(install_root)
    version_root = install_root / "versions" / version
    lock_name = "requirements-lock-windows.txt" if sys.platform == "win32" else "requirements-lock-mac.txt"
    requirements = version_root / lock_name
    if not requirements.is_file():
        raise UpdateError("업데이트 실행환경 정보가 없습니다")
    runtimes_root = install_root / "runtime" / "versions"
    target = runtimes_root / version
    marker = target / ".runtime-complete.json"
    if marker.is_file():
        return target
    if target.exists():
        raise UpdateError("완료되지 않은 업데이트 실행환경이 이미 있습니다")
    runtimes_root.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=f".{version}-", dir=runtimes_root))
    try:
        runner([str(python_executable), "-m", "venv", str(temporary)], check=True)
        runtime_python = temporary / ("Scripts/python.exe" if sys.platform == "win32" else "bin/python")
        runner([str(runtime_python), "-m", "pip", "install", "--disable-pip-version-check", "pip==26.2.1"], check=True)
        runner([
            str(runtime_python), "-m", "pip", "install", "--disable-pip-version-check",
            "--requirement", str(requirements),
        ], check=True)
        runner([
            str(runtime_python), "-c",
            "import fastapi,uvicorn,multipart,faster_whisper,requests",
        ], check=True)
        (temporary / ".runtime-complete.json").write_text(
            json.dumps({"schema_version": 1, "version": version}, indent=2), encoding="utf-8"
        )
        temporary.replace(target)
        return target
    except (OSError, subprocess.SubprocessError) as exc:
        raise UpdateError("업데이트 실행환경 준비에 실패했습니다") from exc
    finally:
        if temporary.exists():
            shutil.rmtree(temporary, ignore_errors=True)


def _active_state_path(install_root: Path) -> Path:
    return Path(install_root) / "active-version.json"


def read_active_version(install_root: Path) -> str | None:
    state_path = _active_state_path(install_root)
    if not state_path.is_file():
        return None
    try:
        value = json.loads(state_path.read_text(encoding="utf-8")).get("active_version")
    except (OSError, json.JSONDecodeError, AttributeError):
        return None
    return value if isinstance(value, str) and _SAFE_VERSION.fullmatch(value) else None


def activate_staged_version(install_root: Path, version: str) -> Path:
    """Atomically move the launch pointer; the previous pointer remains for rollback."""
    if not isinstance(version, str) or not _SAFE_VERSION.fullmatch(version):
        raise UpdateError("활성화할 버전 이름이 올바르지 않습니다")
    install_root = Path(install_root)
    version_root = install_root / "versions" / version
    if not (version_root / "main.py").is_file():
        raise UpdateError("활성화할 버전이 준비되지 않았습니다")
    current = read_active_version(install_root)
    state = {"schema_version": 1, "active_version": version}
    if current and current != version:
        state["rollback_version"] = current
    state_path = _active_state_path(install_root)
    state_path.parent.mkdir(parents=True, exist_ok=True)
    temporary = state_path.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")
    temporary.replace(state_path)
    return version_root


def rollback_active_version(install_root: Path) -> Path:
    """Atomically swap active and rollback pointers after a failed launch."""
    install_root = Path(install_root)
    state_path = _active_state_path(install_root)
    try:
        state = json.loads(state_path.read_text(encoding="utf-8"))
        active = state.get("active_version")
        rollback = state.get("rollback_version")
    except (OSError, json.JSONDecodeError, AttributeError) as exc:
        raise UpdateError("복구할 이전 버전 정보가 없습니다") from exc
    if not isinstance(active, str) or not _SAFE_VERSION.fullmatch(active):
        raise UpdateError("현재 버전 정보가 올바르지 않습니다")
    if not isinstance(rollback, str) or not _SAFE_VERSION.fullmatch(rollback):
        raise UpdateError("복구할 이전 버전 정보가 없습니다")
    rollback_root = install_root / "versions" / rollback
    if not (rollback_root / "main.py").is_file():
        raise UpdateError("복구할 이전 버전이 준비되지 않았습니다")
    next_state = {
        "schema_version": 1,
        "active_version": rollback,
        "rollback_version": active,
    }
    temporary = state_path.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(next_state, ensure_ascii=False, indent=2), encoding="utf-8")
    temporary.replace(state_path)
    return rollback_root

