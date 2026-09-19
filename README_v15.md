# AI PRONOTE v1.5 비공개 베타

회의를 음성만 녹음하거나 카메라 영상과 함께 녹화하고, 받아쓰기·AI 회의록·내 노트·원본 기록을 한 회의 안에서 확인하는 Mac·Windows용 로컬 앱입니다. 기존 녹음 파일 가져오기와 필기만 사용하기도 지원합니다.

## 안전한 실행

1. Windows는 `3_START_AI_PRONOTE.vbs`, Mac은 `mac/AI PRONOTE.app` 또는 `mac/3_START_AI_PRONOTE.command`를 실행합니다.
2. 준비 화면 뒤 `http://127.0.0.1:8795` 앱 창이 열립니다.
3. 다시 실행하면 기존 v1.5 서버와 창을 재사용하며 다른 프로세스를 강제 종료하지 않습니다.

데이터는 기본적으로 이 폴더의 `data_v15`에만 저장됩니다. 기존 v1.3/v1.4의 포트 8771과 데이터 폴더, 바탕화면 바로가기, 시작프로그램은 건드리지 않습니다.

## 현재 지원

- MP3, WAV, M4A, WEBM, OGG, FLAC, MP4 업로드(최대 512MB)
- 음성만 녹음 / 카메라 영상+음성 녹화 / 필기만 사용
- 영상 모드에서도 별도 음성 트랙으로 받아쓰기와 AI 회의록 생성
- Claude 또는 ChatGPT/Codex 로그인 선택
- OpenAI·Gemini·Anthropic 공식 API(BYOK) 연결은 후속 베타에서 제공 예정
- 서버 권위 작업함: 대기·받아쓰기·AI 정리·완료·실패·재시도
- 회의 결과: AI 회의록·전체 원문·내 노트·녹음
- DOCX/PDF/TXT/MD/오디오 내보내기(기존 기능 포함)
- localhost 전용 실행, 경로·Host 검증, 원자 상태 저장과 재시작 복구

## 테스트 명령

```powershell
cd C:\Users\nexts\SUNNY_WORK\AI_PRONOTE_v1.5_P0
python -B -m unittest discover -s tests -v
```

현재 기준 자동화 UI 36개와 변경 계약 테스트 21개가 통과했습니다.

## 알려진 제한

- 이 배포본은 코드 서명 전 지정 사용자용 비공개 베타입니다.
- iPad는 승인 후 실행하는 HTTPS companion과 설치형 PWA로 시험할 수 있습니다. Pointer Events 기반 필기 캔버스는 구현됐지만 실제 Safari·Apple Pencil·palm rejection·VoiceOver 검증은 남아 있습니다.
- AI 로그인 상태와 사용량은 각 AI 제공사의 계정 정책을 따릅니다.
- 설치 프로그램·코드 서명·자동 업데이트는 아직 없습니다.
- 녹음·녹화 및 외부 AI 사용 기준은 사용 지역의 법규와 조직 정책을 확인하세요.

## 중지·롤백

이 테스트본을 닫아도 기존 8771 버전은 영향을 받지 않습니다. v1.5 전환 승인이 나기 전에는 기존 바로가기와 시작프로그램을 바꾸지 않습니다. 문제 발생 시 v1.5 창만 닫고 기존 바탕화면 아이콘을 그대로 사용합니다.
