# AI PRONOTE

> **회의·노트·AI 비서** — 한국어 회의 도구. 받아쓰기 + AI 회의록 자동 정리. 100% 로컬 + Claude OAuth (사용자 본인 Pro 구독, 비용 0).

---

## ★ V1.1 신기능 (2026-05-14): Drive 자동 처리 path

**모바일·iPad에서 어디서나 사용 가능:**

```
모바일/iPad = 회의 녹음
    ↓
Google Drive → SUNNY_TEAM/AI_PRONOTE/inbox/ 업로드
    ↓
맥미니 24/7 워커 (pronote_drive_watcher.py) = 30초 폴링
    ↓
받아쓰기 + Claude OAuth 회의록 정리 (= 비용 0)
    ↓
결과 = Drive AI_PRONOTE/results/{날짜_시간_원본명}/ 저장
   ├─ 회의록.md
   ├─ 받아쓰기_full.txt
   ├─ 받아쓰기_segments.json
   └─ 메타.json
    ↓
텔레그램 한국어 알림 + Drive 앱에서 결과 확인
```

**워커 시작 (= 맥미니 1회):**
```bash
pm2 start ~/sunny-team-worker/pronote_drive_watcher.py --name pronote-watcher --interpreter python3
pm2 save
```

---

## ★ 설치 (5분, Windows)

### 빠른 설치 (다른 프로그램처럼)
1. `C:\AI_PRONOTE_proto\install.bat` 더블클릭
2. 4단계 자동:
   - Python 확인 (없으면 = https://python.org/downloads 안내)
   - 의존성 자동 설치 (faster-whisper · FastAPI · uvicorn)
   - 바탕화면 바로가기 + 아이콘
   - 시작 메뉴 등록

### 사용
- **바탕화면 "AI PRONOTE" 더블클릭** → 자동 시작 + 브라우저 자동 열림
- 끝낼 때 = 창 닫음 = 서버도 같이 종료

### 제거
- `uninstall.bat` 더블클릭 = 바로가기·서버 정리

---

## ★ 사용 흐름

### 1. 첫 진입 = 로그인
- 이메일·비번 가입 (초대 코드 X = 단순)
- 또는 = Google·카카오·Apple OAuth
- 비번 잊음 = "비밀번호를 잊으셨나요?" 클릭

### 2. 새 회의 시작
- 홈 → "새 회의 시작" → 모달
- 회의 종류 선택 + 제목·참석자 (선택)
- **화면 오디오 토글**:
  - **OFF (디폴트)** = 대면 회의 = 마이크만
  - **ON** = 줌·Meet 같은 원격 회의 = 마이크 + 화면 오디오
- "녹음 시작 →" → 권한 허용 → 녹음 시작

### 3. 회의 중
- **내 노트** = 직접 작성 (좌측)
- **받아쓰기** = 자동 (회의 끝 후)
- **AI 비서** = 우측 (호출·자료 조사)
- **하이라이트** = H 키 / **일시정지** = Space / **정지** = Esc

### 4. 회의 끝
- 정지 → webm 자동 다운로드 + IndexedDB 자동 저장
- → 받아쓰기 시작 (백그라운드, 8~19분)
- → Claude OAuth 회의록 자동 생성 (35초)
- → 결과 페이지 = 회의록 본문 + 받아쓰기

### 5. 외부 녹음 가져오기
- 홈 → "녹음 파일 업로드" → OS 다이얼로그
- mp3/wav/m4a/webm/ogg/flac 다 OK
- → 시나리오 모달 → 받아쓰기·정리 자동

---

## ★ 받아쓰기 모델 (어드민에서 선택)

| 모델 | 1시간 회의 처리 | 정확도 |
|---|---|---|
| 🚀 **빠르게 (small)** | **8분** | 75~80% |
| ⭐ **표준 (medium)** ★ | **19분** | 80~85% |

검증 = 04-24 회의 mp3 (1시간 14분) 기준.

---

## ★ AI 회의록 형식 6종

라이브러리 카드 → "회의록" 버튼 → 시나리오 모달:

1. 📋 **회의록** — 한눈 요약·주제별·결정·다음 준비·AI 제안
2. 📚 **강의 노트** — 단원 구조·요점·예시·Q&A
3. 💬 **대화 정리** — Q&A 구조·결론
4. 💡 **아이데이션** — 아이디어 리스트·발전 방향
5. 📖 **사용 메모** — 단계별·주의사항·체크리스트
6. ✨ **자유 형식** — 사용자 명시 톤·구조

각 시나리오 = Claude Haiku/Sonnet/Opus 자동 정리.

---

## ★ 라이브러리 (통합 검색)

좌측 "라이브러리" = 우리 도구로 만든 모든 자료:
- 🎤 녹음 (음성 webm)
- 📋 회의록 (Claude 자동 생성)
- ✏️ 노트 (직접 작성)

**필터**: 전체 / 녹음 / 회의록 / 노트 / 시나리오별
**액션**: 재생 / 보기 / 편집 / 다운로드 / 삭제

---

## ★ 다운로드

회의록 결과 페이지 → "회의록 다운로드 ▾":
- **MD** (마크다운)
- **TXT** (일반 텍스트)
- **전체 받아쓰기 TXT**

---

## ★ 모바일·PWA (앱 출시)

### 모바일 반응형
- 768px 이하 = 사이드바 햄버거
- 라이브러리·어드민 = 1열
- 모달 = 풀폭

### PWA 설치
- iOS Safari = 공유 → "홈 화면에 추가"
- Android Chrome = 메뉴 → "홈 화면에 추가"
- manifest 9 사이즈 + maskable + apple-touch
- service worker 정적 자산 캐시

---

## ★ Claude OAuth (BYOK = 비용 0)

### 작동
- 사용자 = 본인 Claude Pro/Max 구독
- 한 번 = `claude login` 터미널 실행
- 우리 도구 = `~/.claude/.credentials.json` OAuth 토큰 자동 사용
- API key 발급 X, 추가 비용 X

### 토큰 만료 시
- `claude --version` 한 번 실행 = 자동 갱신

### 모델
- Haiku = 빠름 (35초/1시간 회의)
- **Sonnet ★** = 정확 (디폴트)
- Opus = 최대 정확

---

## ★ 인증 = Supabase

### 사용자
- 이메일·비번·OAuth (Google·카카오·Apple)
- 비번 재설정·로그아웃·계정 삭제 = 어드민 "내 계정"
- 세션 만료 시 = 자동 view-login 진입

### 가입자 관리 (관리자)
- https://supabase.com/dashboard → Authentication → Users
- 가입자 목록·차단·삭제 = Dashboard에서

---

## ★ 받아쓰기 엔진 비교 (검증 완료)

| 엔진 | 처리 시간 | 정확도 | 결정 |
|---|---|---|---|
| PLAUD | 즉시~수분 | 95~98% | 비교 기준 |
| **faster-whisper small ⭐** | **8m 7s** | 75~80% | **출시 옵션** |
| **faster-whisper medium ⭐** | **19m 14s** | 80~85% | **출시 디폴트** |
| whisper.cpp turbo | 1h 32m | 90~93% | V2 GPU |
| Meetily Vulkan | — | ❌ 영어 인식 | **부적합** |

**Meetily 폐기**: 한국어 → 영어로 잘못 인식 (언어 명시 옵션 X).

---

## ★ 단축키

| 키 | 동작 |
|---|---|
| Space | 일시정지/재개 |
| H | 하이라이트 직전 30초 |
| Esc | 정지 |
| Ctrl+Shift+D | 개발자 모드 |

---

## ★ 트러블슈팅

| 문제 | 해결 |
|---|---|
| OAuth 토큰 만료 (401) | 새 터미널 = `claude --version` |
| Whisper 모델 다운 중 | 첫 회의 = 466MB/514MB 자동 다운 (한 번만) |
| 마이크 권한 거부 | Chrome 자물쇠 → 마이크 = 허용 |
| 화면 오디오 X | 새 회의 모달 = "화면 오디오" 토글 ON |
| 받아쓰기 시간 김 | 어드민 → "빠르게 (small)" |
| 회의록 생성 429 | 1분 후 재시도 (rate limit) |

---

## ★ 파일 구조

```
C:\AI_PRONOTE_proto\
├── start.bat              # 더블클릭 = 자동 시작
├── install.bat            # 4단계 설치 마법사
├── uninstall.bat          # 제거
├── icon.ico               # 바로가기 아이콘
├── main.py                # FastAPI 서버 + Claude OAuth
├── requirements.txt       # Python 의존성
├── .env.local             # Supabase·BYPASS_AUTH (git X)
├── static/
│   ├── index.html         # 메인 시안 (~310 KB)
│   ├── manifest.webmanifest  # PWA
│   ├── sw.js              # 서비스 워커
│   └── icons/             # PWA 아이콘 11개
├── uploads/               # 임시 업로드
└── results/               # 받아쓰기·회의록 결과
```

---

## ★ Drive 백업

- 시안: `G:\내 드라이브\SUNNY_TEAM\AI_PRONOTE\시안\AI_PRONOTE_UI시안_v6_녹음완성.html`
- 테스트 결과: `G:\내 드라이브\SUNNY_TEAM\AI_PRONOTE\테스트결과\`
- 음성 샘플: `C:\Users\nexts\Desktop\NOTEMAKER\` (검증용)

---

*AI PRONOTE V1 — 2026-05-09 출시 수준 완성*
