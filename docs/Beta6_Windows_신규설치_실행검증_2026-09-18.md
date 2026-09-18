# Beta6 Windows 신규 압축 해제본 실행 검증

검증일: 2026-09-18  
대상: `AI_PRONOTE_v1.5_windows_beta6_2026-09-18.zip`

## 검증 환경

- 기존 설치와 분리된 새 압축 해제 경로
- 새 `.venv` 생성
- `requirements-lock.txt`만 사용해 의존성 설치
- 분리 포트 `127.0.0.1:8896`
- 분리 데이터 폴더 `test_runtime/beta6_fresh_runtime_data`

## 실제 실행 결과

- 잠금 의존성 전체 설치 통과
- `/api/health` 응답 `ok`
- 실행 버전 `v1.5.0-beta6.20260918`
- 압축 해제본 서버를 대상으로 핵심 Playwright 사용 여정 5건 통과
  - 이어 녹음이 새 회의를 만들지 않고 두 번째 구간을 추가
  - 구간별 받아쓰기와 회의록을 원 회의 순서로 합침
  - 동시 AI 결과가 사용자의 최신 노트와 다른 편집 화면을 보존
  - PNG 텍스트 스냅샷의 마지막 줄 보존
  - 너무 긴 PNG 요청은 잘린 파일 대신 PDF·HTML 사용 안내
- 전체 Python 계약 테스트 80건 통과
- 전체 화면 크기 자동 사용 여정 200건 통과

## 배포 압축 검증

- Windows ZIP 95개 항목, CRC 오류 없음
- Mac ZIP 99개 항목, CRC 오류 없음
- 실제 비밀 파일명 패턴 없음
- Mac의 네 개 `.command` 파일 실행권한 `0755`
- SHA-256
  - Windows `B5266810CDDFB6626018E50F08AAE9462EAA679F3CDD52797AB46148A1541B33`
  - Mac `04D090AFA5A82A97C8BCB361C4C4E3AA8C9597AE2A13546F84E2879FA4FD9861`

## 이번 검증이 증명하지 않는 항목

- 실제 물리 Mac 설치·마이크·카메라·시스템 오디오
- Windows·Mac 60분 연속 녹음
- Windows 잠금·절전 복귀
- 코드 서명과 Apple 공증
- Claude·OpenAI·Gemini 실제 계정 전체 흐름

따라서 Beta6는 외부 프리뷰 공유 후보이며 정식 출시 완료판으로 판정하지 않습니다.
