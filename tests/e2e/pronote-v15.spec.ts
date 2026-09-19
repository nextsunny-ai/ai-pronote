import { test, expect, Page } from '@playwright/test';
import fs from 'node:fs';
import path from 'node:path';

const artifactRoot = path.join(process.cwd(), 'tests', 'e2e', 'artifacts', 'screenshots');

const syntheticMeeting = {
  id: 'e2e-meeting-001',
  title: 'E2E 합성 주간 회의',
  tag: '회의',
  date: '2026-09-17',
  dateLabel: '오늘',
  duration: '12분',
  attendees: 3,
  recordingId: 'e2e-recording-001',
  transcript: '합성 회의 원문입니다. 실제 사용자 데이터가 아닙니다.',
  summary: '합성 회의 요약입니다.',
  mynote: '<p>E2E 합성 노트입니다.</p>'
};

async function mockBackend(page: Page, options?: { jobs?: unknown[]; providers?: unknown[] }) {
  await page.route('**/api/**', async route => {
    const url = new URL(route.request().url());
    const json = (body: unknown, status = 200) => route.fulfill({
      status,
      contentType: 'application/json; charset=utf-8',
      body: JSON.stringify(body)
    });

    if (url.pathname === '/api/health') return json({ status: 'ok', version: 'v1.5.0-p0', default_model: 'medium', device: 'cpu' });
    if (url.pathname === '/api/jobs') return json(options?.jobs ?? []);
    if (url.pathname === '/api/results') return json([]);
    if (url.pathname === '/api/pending') return json([]);
    if (url.pathname === '/api/auth/config') return json({ auth_enabled: false });
    if (url.pathname === '/api/llm/status') return json({ available: false, provider: 'none' });
    if (url.pathname === '/api/v15/providers') return json({
      experimental_cli: true,
      providers: options?.providers ?? [
        { name: 'openai', state: 'needs_key', message: 'API 키가 필요합니다.', models: ['gpt-5-mini'] },
        { name: 'gemini', state: 'needs_key', message: 'API 키가 필요합니다.', models: ['gemini-2.5-flash'] },
        { name: 'anthropic', state: 'needs_key', message: 'API 키가 필요합니다.', models: ['claude-haiku'] },
        { name: 'mock', state: 'mock', message: '테스트 전용입니다.', models: ['mock-success'] },
        { name: 'codex_cli', state: 'login_required', message: '로그인이 필요합니다.', models: [] },
        { name: 'claude_cli', state: 'not_installed', message: '설치되지 않았습니다.', models: [] },
      ]
    });
    if (url.pathname === '/api/data/purge') return json({ ok: true, removed_entries: 3, removed_credentials: [], failed_credentials: [] });
    return json({ detail: 'E2E mock: endpoint intentionally unavailable' }, 404);
  });
}

async function seedSyntheticMeeting(page: Page) {
  await page.addInitScript(meeting => {
    localStorage.setItem('ai_pronote.meetings.v1', JSON.stringify([meeting]));
    localStorage.setItem('ai_pronote.current_view_meeting.v1', meeting.id);
  }, syntheticMeeting);
}

async function openApp(page: Page) {
  await page.goto('/');
  await expect(page.locator('#view-home')).toHaveClass(/active/);
  await expect(page.locator('#newMeetingBtn')).toBeVisible();
}

async function installSyntheticCameraAndMicrophone(page: Page) {
  await page.addInitScript(() => {
    const retained: Array<AudioContext | OscillatorNode | HTMLCanvasElement> = [];
    const mediaStreams: MediaStream[] = [];
    const recorderStreams: Array<{ audioTracks: number; videoTracks: number }> = [];
    const NativeMediaRecorder = window.MediaRecorder;
    class InstrumentedMediaRecorder extends NativeMediaRecorder {
      constructor(stream: MediaStream, options?: MediaRecorderOptions) {
        recorderStreams.push({
          audioTracks: stream.getAudioTracks().length,
          videoTracks: stream.getVideoTracks().length
        });
        super(stream, options);
      }
    }
    Object.defineProperty(window, 'MediaRecorder', { configurable: true, value: InstrumentedMediaRecorder });
    Object.defineProperty(navigator, 'mediaDevices', {
      configurable: true,
      value: {
        getUserMedia: async (constraints: MediaStreamConstraints) => {
          if (constraints.video) {
            const canvas = document.createElement('canvas');
            canvas.width = 640;
            canvas.height = 360;
            const context = canvas.getContext('2d')!;
            context.fillStyle = '#172033';
            context.fillRect(0, 0, canvas.width, canvas.height);
            context.fillStyle = '#f5a623';
            context.fillRect(90, 70, 460, 220);
            retained.push(canvas);
            const stream = canvas.captureStream(12);
            mediaStreams.push(stream);
            return stream;
          }

          const audioContext = new AudioContext();
          await audioContext.resume();
          const oscillator = audioContext.createOscillator();
          const destination = audioContext.createMediaStreamDestination();
          oscillator.frequency.value = 440;
          oscillator.connect(destination);
          oscillator.start();
          retained.push(audioContext, oscillator);
          mediaStreams.push(destination.stream);
          return destination.stream;
        }
      }
    });
    (window as typeof window & {
      __syntheticMedia?: unknown[];
      __recorderStreams?: Array<{ audioTracks: number; videoTracks: number }>;
      __syntheticStreams?: MediaStream[];
    }).__syntheticMedia = retained;
    (window as typeof window & {
      __recorderStreams?: Array<{ audioTracks: number; videoTracks: number }>;
    }).__recorderStreams = recorderStreams;
    (window as typeof window & { __syntheticStreams?: MediaStream[] }).__syntheticStreams = mediaStreams;
  });
}

async function openNavView(page: Page, demo: string) {
  const menu = page.locator('#mobileMenuBtn');
  if (await menu.isVisible()) await menu.click();
  await page.locator(`.nav-item[data-demo="${demo}"]`).click();
}

test.beforeAll(() => fs.mkdirSync(artifactRoot, { recursive: true }));

test.describe('v1.5 핵심 발견성과 반응형', () => {
  test.beforeEach(async ({ page }) => mockBackend(page));

  test('홈에서 즉석 회의·외부 업로드·라이브러리·작업함을 바로 찾는다', async ({ page }, testInfo) => {
    await openApp(page);
    await expect(page.locator('#newMeetingBtn')).toBeVisible();
    await expect(page.locator('#newMeetingBtn')).toContainText('녹음 시작');
    await expect(page.locator('#homeUploadCard')).toBeVisible();
    await expect(page.locator('#homeUploadCard')).toContainText('파일로 회의록 만들기');
    await expect(page.locator('[data-demo="library"]').first()).toBeAttached();
    await expect(page.getByTestId('job-center-toggle')).toBeVisible();
    await page.screenshot({ path: path.join(artifactRoot, `${testInfo.project.name}-home.png`), fullPage: true });
  });

  test('홈 업로드 진입점이 파일 선택기를 연다', async ({ page }) => {
    await openApp(page);
    const chooserPromise = page.waitForEvent('filechooser');
    await page.locator('#homeUploadCard').click();
    const chooser = await chooserPromise;
    expect(chooser.isMultiple()).toBeFalsy();
    expect(await chooser.element().getAttribute('id')).toBe('libraryFileInput');
    expect(await chooser.element().getAttribute('accept')).toContain('.mp4');
  });

  test('회의록 생성 화면에서도 기존 작업을 유지한 채 이어서 녹음을 시작한다', async ({ page }) => {
    await seedSyntheticMeeting(page);
    await openApp(page);
    await page.evaluate(() => window.switchView?.('result'));
    await expect(page.locator('#resultContinueRecordingBtn')).toBeVisible();
    await page.evaluate(() => {
      window.__pronoteResult?.render?.();
      window.__pronoteResult?.render?.();
      (window as typeof window & { __continueOpenCount?: number }).__continueOpenCount = 0;
      document.getElementById('newMeetingBtn')?.addEventListener('click', () => {
        (window as typeof window & { __continueOpenCount?: number }).__continueOpenCount! += 1;
      });
    });
    await page.locator('#resultContinueRecordingBtn').click();
    await expect(page.locator('#meetingTypeModal')).toHaveClass(/open/);
    await expect(page.locator('#newMeetingTitle')).toHaveValue('E2E 합성 주간 회의');
    await expect(page.locator('#meetingTypeModal')).toHaveAttribute('data-continuation-meeting-id', syntheticMeeting.id);
    await expect(page.locator('#toast')).toContainText('이 회의에 새 녹음 구간');
    await expect.poll(() => page.evaluate(() => (window as typeof window & { __continueOpenCount?: number }).__continueOpenCount)).toBe(1);
  });

  test('MP4 파일을 고르면 문서 형식과 다음 행동을 명확히 안내한다', async ({ page }) => {
    await openApp(page);
    const chooserPromise = page.waitForEvent('filechooser');
    await page.locator('#homeUploadCard').click();
    const chooser = await chooserPromise;
    await chooser.setFiles({ name: '합성_회의영상.mp4', mimeType: 'video/mp4', buffer: Buffer.from('e2e synthetic media') });
    await expect(page.locator('#view-library')).toHaveClass(/active/);
    await expect(page.locator('#scenarioModal')).toHaveClass(/open/);
    await expect(page.getByRole('heading', { name: '어떤 문서로 정리할까요?' })).toBeVisible();
    await expect(page.locator('#scenarioConfirm')).toHaveText('받아쓰기·회의록 만들기');
    await expect(page.locator('#scenarioGrid')).toContainText('회의록');
    await expect(page.locator('#scenarioGrid')).toContainText('강의 노트');
    await page.locator('#scenarioCancel').click();
    await expect(page.locator('#libraryUploadBtn')).toBeVisible();
    await expect(page.locator('#libraryUploadBtn')).toHaveText('파일로 회의록 만들기');
  });

  test('드래그앤드롭도 같은 검증·라이브러리·문서형식 흐름을 사용한다', async ({ page }) => {
    await openApp(page);
    await openNavView(page, 'dict');
    await page.evaluate(() => {
      const transfer = new DataTransfer();
      transfer.items.add(new File([new Uint8Array([1, 2, 3, 4])], '드롭_회의.mp3', { type: 'audio/mpeg' }));
      document.getElementById('dictStage')!.dispatchEvent(new DragEvent('drop', { bubbles: true, cancelable: true, dataTransfer: transfer }));
    });
    await expect(page.locator('#view-library')).toHaveClass(/active/);
    await expect(page.locator('#scenarioModal')).toHaveClass(/open/);
    await expect(page.locator('#scenarioTitle')).toHaveValue('드롭_회의');
  });

  test('지원하지 않거나 빈 파일을 접근 가능한 메시지로 거절하고 버튼을 복구한다', async ({ page }) => {
    await openApp(page);
    await page.evaluate(async () => {
      await window.__pronoteLibrary.importFiles([new File([], '빈파일.mp3', { type: 'audio/mpeg' })]);
    });
    await expect(page.locator('#toast')).toHaveAttribute('role', 'status');
    await expect(page.locator('#toast')).toHaveAttribute('aria-live', 'polite');
    await expect(page.locator('#toast')).toContainText('내용이 없는 파일');
    await expect(page.locator('#homeUploadCard')).toHaveAttribute('aria-busy', 'false');

    await page.evaluate(async () => {
      await window.__pronoteLibrary.importFiles([new File([new Uint8Array([1])], '회의.aac', { type: 'audio/aac' })]);
    });
    await expect(page.locator('#toast')).toContainText('지원하지 않는 파일');
    await expect(page.locator('#scenarioModal')).not.toHaveClass(/open/);
  });

  test('빈 작업함은 무응답 대신 명확한 빈 상태를 보인다', async ({ page }) => {
    await openApp(page);
    await page.getByTestId('job-center-toggle').click();
    await expect(page.getByTestId('job-center')).toHaveAttribute('aria-hidden', 'false');
    await expect(page.locator('#jobCenterList')).toContainText('진행 중인 작업이 없습니다');
    await page.getByRole('button', { name: '작업함 닫기' }).click();
    await expect(page.getByTestId('job-center')).toHaveAttribute('aria-hidden', 'true');
  });

  test('회의가 없으면 데모 메타데이터와 실행 불가능한 결과 버튼을 숨긴다', async ({ page }) => {
    await openApp(page);
    await openNavView(page, 'result');
    await expect(page.locator('#view-result')).toHaveClass(/active/);
    await expect(page.locator('#view-result .notes-box-body')).toContainText('아직 회의록이 없습니다');
    await expect(page.locator('#meetingResultTabs')).toBeHidden();
    await expect(page.locator('#view-result .result-actionbar')).toBeHidden();
    await expect(page.locator('#view-result #info')).toBeHidden();
    await expect(page.locator('#view-result .result-side')).toBeHidden();
    await page.locator('#emptyResultStartBtn').click();
    await expect(page.locator('#meetingTypeModal')).toHaveClass(/open/);
    await page.locator('#meetingTypeClose').click();

    await page.evaluate(() => {
      const meeting = {
        id: 'empty-state-roundtrip', title: '복원 검증 회의', date: '2026-09-18',
        duration: '00:42', summary: '실제 회의 요약', transcript: '실제 받아쓰기',
        attendees: 0, location: '', tag: '', scenario: ''
      };
      localStorage.setItem('ai_pronote.meetings.v1', JSON.stringify([meeting]));
      localStorage.setItem('ai_pronote.current_view_meeting.v1', meeting.id);
    });
    await openNavView(page, 'home');
    await openNavView(page, 'result');
    await expect(page.locator('#meetingResultTabs')).toBeVisible();
    await expect(page.locator('#view-result .result-actionbar')).toBeVisible();
    await expect(page.locator('#view-result #info')).toBeVisible();
    await expect(page.locator('#view-result .result-side')).toBeVisible();
    await expect(page.locator('#view-result .result-title')).toHaveText('복원 검증 회의');
    await expect(page.locator('#view-result #info')).toContainText('장소 미입력');
    await expect(page.locator('#view-result #info')).toContainText('아젠다 미입력');
    await expect(page.locator('#view-result #info')).toContainText('참석자 미입력');
    await expect(page.locator('#view-result #info')).not.toContainText('[Speaker 1]');
  });

  test('설치본 데이터 삭제는 범위를 정확히 알리고 브라우저 데이터를 정리한다', async ({ page }) => {
    await page.addInitScript(() => {
      localStorage.setItem('ai_pronote.trash.v1', '[{"id":"private"}]');
      localStorage.setItem('pronote_claude_override', 'legacy');
    });
    await openApp(page);
    await openNavView(page, 'admin');
    await page.locator('#view-admin .admin-card[data-admin="account"]').click();
    const deleteButton = page.locator('#acctDelete');
    await expect(deleteButton).toHaveText('이 기기의 AI PRONOTE 데이터 영구 삭제');
    let dialogCount = 0;
    page.on('dialog', async dialog => { dialogCount += 1; await dialog.accept(); });
    await deleteButton.click();
    await expect.poll(() => dialogCount).toBe(2);
    await expect.poll(() => page.evaluate(() => localStorage.getItem('ai_pronote.trash.v1'))).toBeNull();
    await expect.poll(() => page.evaluate(() => localStorage.getItem('pronote_claude_override'))).toBeNull();
    await expect(deleteButton).not.toHaveAttribute('aria-busy', 'true');
  });

  test('안전한 진단정보는 회의 내용·제목·파일명·비밀정보 없이 내려받는다', async ({ page }) => {
    await seedSyntheticMeeting(page);
    await openApp(page);
    await openNavView(page, 'admin');
    const downloadPromise = page.waitForEvent('download');
    await page.locator('#diagnosticExportBtn').click();
    const download = await downloadPromise;
    const downloadPath = await download.path();
    expect(download.suggestedFilename()).toMatch(/^AI_PRONOTE_진단정보_\d{8}-\d{6}\.json$/);
    expect(downloadPath).toBeTruthy();
    const raw = fs.readFileSync(downloadPath!, 'utf8');
    const diagnostic = JSON.parse(raw);
    expect(diagnostic.format).toBe('ai-pronote-safe-diagnostics');
    expect(diagnostic.schema_version).toBe(1);
    expect(diagnostic.local_counts.meetings).toBe(1);
    expect(diagnostic.excluded_fields).toContain('credentials_tokens');
    expect(diagnostic.environment.browser_family).toBeTruthy();
    expect(diagnostic.environment.os_family).toBeTruthy();
    expect(diagnostic.environment.browser).toBeUndefined();
    expect(raw).not.toContain(syntheticMeeting.title);
    expect(raw).not.toContain(syntheticMeeting.transcript);
    expect(raw).not.toContain(syntheticMeeting.summary);
    expect(raw).not.toContain(syntheticMeeting.mynote);
    await expect(page.locator('#toast')).toContainText('민감정보를 제외한 진단정보');
  });
});

test.describe('작업함 상태와 오류 복구', () => {
  test('진행·실패 상태, 퍼센트, ETA, 재시도를 표시한다', async ({ page }) => {
    await mockBackend(page, { jobs: [
      { job_id: 'e2e-running', filename: '합성-60분.m4a', status: 'running', progress: 42, queue_view: { stage_label: '받아쓰기 중', eta_seconds: 180 } },
      { job_id: 'e2e-error', filename: '합성-오류.wav', status: 'error', progress: 12, error: '지원하지 않는 오디오', queue_view: { stage_label: '실패', can_retry: true } }
    ] });
    await openApp(page);
    await page.getByTestId('job-center-toggle').click();
    await expect(page.locator('[data-job-id="e2e-running"]')).toContainText('42%');
    await expect(page.locator('[data-job-id="e2e-running"]')).toContainText('약 3분 남음');
    await expect(page.locator('[data-job-id="e2e-error"]')).toContainText('지원하지 않는 오디오');
    await expect(page.locator('[data-job-id="e2e-error"] button')).toHaveText('다시 시도');
  });
});

test.describe('라이브러리 재열기 회귀', () => {
  test.beforeEach(async ({ page }) => {
    await mockBackend(page);
    await seedSyntheticMeeting(page);
  });

  test('합성 회의는 카드 하나로 나타나며 보기 버튼으로 결과를 연다', async ({ page }) => {
    await openApp(page);
    await openNavView(page, 'library');
    const card = page.locator('.library-card[data-item-id="e2e-meeting-001"][data-item-type="meeting"]');
    await expect(card).toHaveCount(1);
    await expect(card).toContainText('E2E 합성 주간 회의');
    await card.getByRole('button', { name: /보기/ }).click();
    await expect(page.locator('#view-result')).toHaveClass(/active/);
    await expect(page.locator('#meetingResultTabs')).toBeVisible();
    await expect(page.locator('#mynoteBlock')).toBeAttached();
  });

  test('카드 전체 클릭도 같은 결과 화면을 연다', async ({ page }) => {
    await openApp(page);
    await openNavView(page, 'library');
    const card = page.locator('.library-card[data-item-id="e2e-meeting-001"]');
    await card.click({ position: { x: 120, y: 30 } });
    await expect(page.locator('#view-result')).toHaveClass(/active/);
  });

  test('구버전 서버 결과를 홈을 가리지 않고 라이브러리에서 복구한다', async ({ page }) => {
    await page.unroute('**/api/**');
    await page.route('**/api/**', async route => {
      const url = new URL(route.request().url());
      const json = (body: unknown, status = 200) => route.fulfill({
        status, contentType: 'application/json; charset=utf-8', body: JSON.stringify(body)
      });
      if (url.pathname === '/api/results') return json([{
        job_id: 'legacy-result-001', filename: 'legacy.m4a', duration: 12.7,
        char_count: 24, saved_at: 1_789_000_000, preview: '구버전 시험'
      }, {
        job_id: 'legacy/result-실패', filename: 'retry.m4a', duration: 8,
        char_count: 10, saved_at: 1_789_000_001, preview: '재시도 시험'
      }]);
      if (url.pathname === '/api/results/legacy-result-001') return json({
        filename: 'legacy.m4a', duration: 12.7, model: 'medium',
        full_text: '구버전 결과 복구를 확인하는 비민감 시험 문장입니다.', segments: [], job: {}
      });
      if (url.pathname === '/api/results/legacy%2Fresult-%EC%8B%A4%ED%8C%A8') return json({ detail: 'temporary' }, 503);
      if (url.pathname === '/api/health') return json({ status: 'ok', version: 'v1.5.0-p0' });
      if (url.pathname === '/api/jobs' || url.pathname === '/api/pending') return json([]);
      if (url.pathname === '/api/auth/config') return json({ auth_enabled: false });
      if (url.pathname === '/api/llm/status') return json({ available: false, provider: 'none' });
      if (url.pathname === '/api/v15/providers') return json({ providers: [], experimental_cli: false });
      return json({ detail: 'not found' }, 404);
    });
    await openApp(page);
    await expect(page.locator('#serverResultBar')).not.toBeVisible();
    await openNavView(page, 'library');
    await expect(page.locator('#serverResultBar')).toBeVisible();
    await page.evaluate(async () => {
      await (window as typeof window & { __pronoteDB: { put: (record: unknown) => Promise<string> } }).__pronoteDB.put({
        id: 'rec_pending-legacy', jobId: 'legacy-result-001', filename: '원본-녹음.webm',
        blob: new Blob(['original-audio'], { type: 'audio/webm' }), transcribed: false,
        startedAt: 1_789_000_000_000, source: 'recorded'
      });
    });
    await page.reload();
    await openNavView(page, 'library');
    await expect(page.locator('#serverResultBar')).toBeVisible();
    await page.locator('#srvResImport').click();
    await expect(page.locator('#srvResStatus')).toContainText('1건을 가져왔고 1건은 실패했습니다');
    await expect(page.locator('#srvResImport')).toHaveText('다시 시도');
    await openNavView(page, 'library');
    const card = page.locator('.library-card[data-item-id="rec_pending-legacy"]');
    await expect(card).toHaveCount(1);
    const restored = await page.evaluate(async () => {
      const rec = await (
        window as typeof window & { __pronoteDB: { get: (id: string) => Promise<Record<string, unknown>> } }
      ).__pronoteDB.get('rec_pending-legacy');
      return { filename: rec.filename, transcribed: rec.transcribed, transcript: rec.transcript, hasBlob: rec.blob instanceof Blob };
    });
    expect(restored.filename).toBe('원본-녹음.webm');
    expect(restored.transcribed).toBe(true);
    expect(restored.transcript).toContain('구버전 결과 복구');
    expect(restored.hasBlob).toBe(true);
    await card.getByRole('button', { name: /회의록/ }).click();
    await expect(page.locator('#scenarioModal')).toHaveClass(/open/);
    await expect(page.getByRole('heading', { name: '어떤 문서로 정리할까요?' })).toBeVisible();
  });
});

test.describe('필기 저장·복원 계약', () => {
  test.beforeEach(async ({ page }) => {
    await mockBackend(page);
    await seedSyntheticMeeting(page);
  });

  test('필기만 만든 노트는 새로고침 뒤 상세 화면에서 본문까지 다시 열린다', async ({ page }) => {
    await openApp(page);
    await page.locator('#homeNoteOnlyCard').click();
    await expect(page.locator('#view-result')).toHaveClass(/active/);
    await expect(page.locator('#mynoteBlock')).toHaveClass(/fullpage/);
    await page.locator('#mynoteTitleInput').fill('단독 필기 복원 시험');
    await page.locator('#mynoteBlockContent').fill('새로고침 뒤에도 보여야 하는 비민감 시험 본문입니다.');
    await expect(page.locator('#mynoteSaveState')).toContainText('저장됨', { timeout: 3000 });

    const saved = await page.evaluate(() => {
      const meetings = localStorage.getItem('ai_pronote.meetings.v1') || '[]';
      const note = JSON.parse(meetings).find((item: { title?: string }) => item.title === '단독 필기 복원 시험');
      return { meetings, noteId: note.id as string, updatedAt: note.updatedAt as string };
    });
    expect(saved.updatedAt).toBeTruthy();
    await page.addInitScript(data => {
      localStorage.setItem('ai_pronote.meetings.v1', data.meetings);
      localStorage.setItem('ai_pronote.current_view_meeting.v1', data.noteId);
    }, saved);

    await page.reload();
    await openNavView(page, 'result-mynote');
    await expect(page.locator('#view-result')).toHaveClass(/active/);
    await expect(page.locator('#mynoteBlockContent')).toContainText('새로고침 뒤에도 보여야 하는 비민감 시험 본문입니다.');

    await page.locator('#mynoteBlockContent').fill('자동저장 1초 전에도 보존되어야 하는 수정 본문입니다.');
    await openNavView(page, 'home');
    await openNavView(page, 'result-mynote');
    await expect(page.locator('#mynoteBlockContent')).toContainText('자동저장 1초 전에도 보존되어야 하는 수정 본문입니다.');

    await page.evaluate(noteB => {
      const meetings = JSON.parse(localStorage.getItem('ai_pronote.meetings.v1') || '[]');
      meetings.push(noteB);
      localStorage.setItem('ai_pronote.meetings.v1', JSON.stringify(meetings));
      localStorage.setItem('ai_pronote.current_view_meeting.v1', noteB.id);
    }, {
      id: 'note-b', title: '두 번째 노트', tag: '단독 메모', date: '2026-09-18',
      note: '<p>두 번째 노트 본문입니다.</p>', standalone: true
    });
    await openNavView(page, 'result-mynote');
    await expect(page.locator('#mynoteBlockContent')).toContainText('두 번째 노트 본문입니다.');
    const firstNote = await page.evaluate(noteId => {
      const meetings = JSON.parse(localStorage.getItem('ai_pronote.meetings.v1') || '[]');
      return meetings.find((item: { id: string }) => item.id === noteId);
    }, saved.noteId);
    expect(firstNote.note).toContain('자동저장 1초 전에도 보존되어야 하는 수정 본문입니다.');
  });

  test('독립 노트를 주요 문서 형식으로 내보내고 기기 공유 대체 동작을 제공한다', async ({ page }) => {
    await openApp(page);
    await page.locator('#homeNoteOnlyCard').click();
    await page.locator('#mynoteTitleInput').fill('내보내기 점검 노트');
    await page.locator('#mynoteBlockContent').fill('문서 저장과 보내기 점검 본문');
    await expect(page.locator('#mynoteSaveState')).toContainText('저장됨', { timeout: 3000 });

    for (const format of ['txt', 'md', 'html', 'png', 'native']) {
      const downloadPromise = page.waitForEvent('download');
      await page.locator('#mynoteExportSelect').selectOption(format);
      const download = await downloadPromise;
      expect(download.suggestedFilename()).toContain('내보내기 점검 노트');
      if (format === 'png') expect(download.suggestedFilename()).toMatch(/\.png$/);
    }
    await expect(page.locator('#mynoteExportSelect')).toContainText('인쇄 · PDF 저장');
    await page.evaluate(() => {
      Object.defineProperty(navigator, 'share', { configurable: true, value: undefined });
      Object.defineProperty(navigator, 'clipboard', { configurable: true, value: { writeText: async (value: string) => { (window as typeof window & { __sharedNote?: string }).__sharedNote = value; } } });
    });
    await page.locator('#mynoteShareBtn').click();
    expect(await page.evaluate(() => (window as typeof window & { __sharedNote?: string }).__sharedNote)).toContain('문서 저장과 보내기 점검 본문');
  });

  test('프로노트 JSON 백업을 원본을 덮어쓰지 않고 새 노트로 복구한다', async ({ page }) => {
    await openApp(page);
    await page.locator('#homeNoteOnlyCard').click();
    await expect(page.locator('#view-result')).toHaveClass(/active/);
    await expect(page.locator('#mynoteBlock')).toHaveClass(/fullpage/);
    await page.evaluate(() => {
      const meetings = JSON.parse(localStorage.getItem('ai_pronote.meetings.v1') || '[]');
      for (let i = 0; i < 51; i += 1) meetings.push({ id: `preserve-${i}`, title: `보존 노트 ${i}`, note: `<p>보존 ${i}</p>`, standalone: true });
      localStorage.setItem('ai_pronote.meetings.v1', JSON.stringify(meetings));
    });
    const before = await page.evaluate(() => JSON.parse(localStorage.getItem('ai_pronote.meetings.v1') || '[]').length);
    await page.locator('#mynoteImportInput').setInputFiles({
      name: '복구시험.pronote.json',
      mimeType: 'application/json',
      buffer: Buffer.from(JSON.stringify({
        format: 'ai-pronote-note', version: 1, title: '백업에서 복구한 노트',
        html: '<h2>복구 제목</h2><p>다시 편집할 수 있어야 하는 본문</p><script>window.__bad = true</script>',
        text: '복구 제목\n다시 편집할 수 있어야 하는 본문', createdAt: '2026-09-18T00:00:00.000Z'
      }))
    });
    await expect(page.locator('#toast')).toContainText('새 노트로 복구했습니다');
    await expect(page.locator('#mynoteTitleInput')).toHaveValue('백업에서 복구한 노트');
    await expect(page.locator('#mynoteBlockContent')).toContainText('다시 편집할 수 있어야 하는 본문');
    expect(await page.evaluate(() => (window as typeof window & { __bad?: boolean }).__bad)).toBeUndefined();
    expect(await page.evaluate(() => JSON.parse(localStorage.getItem('ai_pronote.meetings.v1') || '[]').length)).toBe(before + 1);
    expect(await page.evaluate(() => JSON.parse(localStorage.getItem('ai_pronote.meetings.v1') || '[]').some((m: { id: string }) => m.id === 'preserve-50'))).toBeTruthy();
  });

  test('저장된 여러 노트를 ZIP 하나로 백업하고 기존 자료를 보존해 일괄 복구한다', async ({ page }) => {
    await openApp(page);
    await page.evaluate(() => {
      localStorage.setItem('ai_pronote.meetings.v1', JSON.stringify([
        { id: 'zip-note-1', title: '해외 회의 메모', tag: '노트', date: '2026-09-17', note: '<p>영문 회의 핵심</p>', standalone: true, noteOnly: true, createdAt: '2026-09-17T01:00:00.000Z' },
        { id: 'zip-note-2', title: '개발 회의 메모', tag: '노트', date: '2026-09-18', note: '<h2>릴리스</h2><p>오류 수정</p><script>window.__zipBad = true</script>', standalone: true, noteOnly: true },
        { id: 'recording-only', title: '노트 없는 녹음', note: '', noteOnly: false },
        { id: 'pen-only-meeting', title: '펜 필기만 있는 회의', tag: '회의', date: '2026-09-18', note: '', noteOnly: false }
      ]));
      localStorage.setItem('ai_pronote.current_view_meeting.v1', 'zip-note-1');
    });
    await page.evaluate(async () => {
      await (window as typeof window & { __pronoteSwitchMyNoteMeeting?: (id: string) => Promise<boolean> }).__pronoteSwitchMyNoteMeeting?.('zip-note-1');
      await (window as typeof window & { PronoteInk?: { importDocuments: (rows: unknown[]) => Promise<void> } }).PronoteInk?.importDocuments([{
        schemaVersion: 1, meetingId: 'zip-note-2', strokes: [{ id: 'stroke-1', tool: 'pen', color: '#1A1A1A', width: 4, points: [{ x: 10, y: 20, pressure: 0.5, t: 1 }] }]
      }, {
        schemaVersion: 1, meetingId: 'pen-only-meeting', strokes: [{ id: 'stroke-2', tool: 'line', color: '#C8453B', width: 3, points: [{ x: 1, y: 2, pressure: 0.5, t: 1 }, { x: 3, y: 4, pressure: 0.5, t: 2 }] }]
      }]);
    });
    await openNavView(page, 'result-mynote');
    await expect(page.locator('#mynoteBackupAllBtn')).toBeVisible();
    const downloadPromise = page.waitForEvent('download');
    await page.locator('#mynoteBackupAllBtn').click();
    const download = await downloadPromise;
    expect(download.suggestedFilename()).toMatch(/AI_PRONOTE_전체노트_.*\.zip$/);
    await expect(page.locator('#toast')).toContainText('노트 3개를 ZIP으로 백업했습니다');
    const zipPath = await download.path();
    expect(zipPath).toBeTruthy();
    const before = await page.evaluate(() => JSON.parse(localStorage.getItem('ai_pronote.meetings.v1') || '[]').length);
    const zipBuffer = await fs.promises.readFile(zipPath!);
    await page.locator('#mynoteImportInput').setInputFiles({
      name: 'AI_PRONOTE_전체노트.zip', mimeType: 'application/zip', buffer: zipBuffer
    });
    await expect(page.locator('#toast')).toContainText('노트 3개를 새 노트로 복구했습니다');
    const result = await page.evaluate(async () => {
      const meetings = JSON.parse(localStorage.getItem('ai_pronote.meetings.v1') || '[]');
      const imported = meetings.filter((m: { id: string }) => m.id.startsWith('note_import_'));
      const devNote = imported.find((m: { title: string }) => m.title === '개발 회의 메모');
      const penOnly = imported.find((m: { title: string }) => m.title === '펜 필기만 있는 회의');
      const ink = await (window as typeof window & { PronoteInk?: { exportDocuments: (ids: string[]) => Promise<Array<{ meetingId: string; strokes: unknown[] }>> } }).PronoteInk?.exportDocuments([devNote.id, penOnly.id]);
      return { count: meetings.length, imported, inkCounts: ink?.map(row => row.strokes.length).sort() || [], bad: (window as typeof window & { __zipBad?: boolean }).__zipBad };
    });
    expect(result.count).toBe(before + 3);
    expect(result.imported).toHaveLength(3);
    expect(result.imported.map((m: { title: string }) => m.title)).toEqual(expect.arrayContaining(['해외 회의 메모', '개발 회의 메모', '펜 필기만 있는 회의']));
    expect(result.imported.find((m: { title: string }) => m.title === '개발 회의 메모').note).not.toContain('<script');
    expect(result.inkCounts).toEqual([1, 1]);
    expect(result.bad).toBeUndefined();

    const afterValidRestore = result.count;
    const corrupted = Buffer.from(zipBuffer);
    corrupted[50] ^= 0xff;
    await page.locator('#mynoteImportInput').setInputFiles({
      name: '손상된_전체노트.zip', mimeType: 'application/zip', buffer: corrupted
    });
    await expect(page.locator('#toast')).toContainText('무결성 검사에 실패했습니다');
    expect(await page.evaluate(() => JSON.parse(localStorage.getItem('ai_pronote.meetings.v1') || '[]').length)).toBe(afterValidRestore);
  });

  test('너무 긴 PNG는 잘린 성공 파일 대신 PDF·HTML 사용을 안내한다', async ({ page }) => {
    await openApp(page);
    await page.locator('#homeNoteOnlyCard').click();
    await expect(page.locator('#view-result')).toHaveClass(/active/);
    await page.locator('#mynoteBlockContent').fill(Array.from({ length: 170 }, (_, i) => `길이 점검 문장 ${i}`).join('\n'));
    await page.locator('#mynoteExportSelect').selectOption('png');
    await expect(page.locator('#toast')).toContainText('PDF 또는 HTML');
  });

  test('PNG 텍스트 스냅샷은 정상 길이 노트의 마지막 줄까지 캔버스 안에 그린다', async ({ page }) => {
    await openApp(page);
    await page.locator('#homeNoteOnlyCard').click();
    await expect(page.locator('#view-result')).toHaveClass(/active/);
    await page.evaluate(() => {
      const original = CanvasRenderingContext2D.prototype.fillText;
      CanvasRenderingContext2D.prototype.fillText = function(text: string, x: number, y: number, maxWidth?: number) {
        const w = window as typeof window & { __pngDraws?: Array<{ text: string; y: number; height: number }> };
        (w.__pngDraws ||= []).push({ text, y, height: this.canvas.height });
        return maxWidth === undefined ? original.call(this, text, x, y) : original.call(this, text, x, y, maxWidth);
      };
    });
    const finalLine = '마지막 줄도 반드시 포함';
    await page.locator('#mynoteBlockContent').fill([...Array.from({ length: 20 }, (_, i) => `본문 ${i}`), finalLine].join('\n'));
    const downloadPromise = page.waitForEvent('download');
    await page.locator('#mynoteExportSelect').selectOption('png');
    await downloadPromise;
    const draw = await page.evaluate(finalText => {
      const all = (window as typeof window & { __pngDraws?: Array<{ text: string; y: number; height: number }> }).__pngDraws || [];
      return all.find(item => item.text === finalText);
    }, finalLine);
    expect(draw).toBeTruthy();
    expect(draw!.y).toBeLessThan(draw!.height);
  });

  test('첨부 이미지를 줄여 자동저장하고 새로고침 뒤에도 복원한다', async ({ page }) => {
    await openApp(page);
    await page.locator('#homeNoteOnlyCard').click();
    await page.locator('#mynoteTitleInput').fill('이미지 저장 점검');
    await page.locator('#mynoteImageInput').setInputFiles({
      name: 'memo.png', mimeType: 'image/png',
      buffer: Buffer.from('iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAIAAACQkWg2AAAAI0lEQVR4nGM8kWLEQApgIkk1w6gG4gATkergYFQDMYDkUAIAYgYBfoIBT3AAAAAASUVORK5CYII=', 'base64')
    });
    await expect(page.locator('#toast')).toContainText('안전하게 첨부했습니다');
    const savedImageNote = await page.evaluate(() => {
      const id = localStorage.getItem('ai_pronote.current_view_meeting.v1');
      const meetings = localStorage.getItem('ai_pronote.meetings.v1') || '[]';
      return { id, meetings, note: JSON.parse(meetings).find((m: { id: string }) => m.id === id)?.note as string };
    });
    expect(savedImageNote.note).toContain('data:image/jpeg;base64,');
    await page.addInitScript(saved => {
      localStorage.setItem('ai_pronote.meetings.v1', saved.meetings);
      if (saved.id) localStorage.setItem('ai_pronote.current_view_meeting.v1', saved.id);
    }, savedImageNote);
    await page.reload();
    await openNavView(page, 'result-mynote');
    await expect(page.locator('#mynoteBlockContent img')).toHaveCount(1);
  });

  test('이미지 저장 실패 뒤에도 직전 미저장 텍스트를 재시도해 보존한다', async ({ page }) => {
    await openApp(page);
    await page.locator('#homeNoteOnlyCard').click();
    await page.locator('#mynoteBlockContent').fill('이미지 오류 뒤에도 남아야 하는 텍스트');
    await page.evaluate(() => {
      const original = Storage.prototype.setItem;
      (window as typeof window & { __restoreStorageSetItem?: () => void }).__restoreStorageSetItem = () => { Storage.prototype.setItem = original; };
      Storage.prototype.setItem = function(key: string, value: string) {
        if (key === 'ai_pronote.meetings.v1') throw new DOMException('quota', 'QuotaExceededError');
        return original.call(this, key, value);
      };
    });
    await page.locator('#mynoteImageInput').setInputFiles({
      name: 'memo.png', mimeType: 'image/png',
      buffer: Buffer.from('iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAIAAACQkWg2AAAAI0lEQVR4nGM8kWLEQApgIkk1w6gG4gATkergYFQDMYDkUAIAYgYBfoIBT3AAAAAASUVORK5CYII=', 'base64')
    });
    await expect(page.locator('#toast')).toContainText('저장 공간을 확인해 주세요');
    await page.evaluate(() => (window as typeof window & { __restoreStorageSetItem?: () => void }).__restoreStorageSetItem?.());
    await expect(page.locator('#mynoteSaveState')).toContainText('저장됨', { timeout: 4000 });
    expect(await page.evaluate(() => {
      const id = localStorage.getItem('ai_pronote.current_view_meeting.v1');
      return JSON.parse(localStorage.getItem('ai_pronote.meetings.v1') || '[]').find((m: { id: string }) => m.id === id)?.note;
    })).toContain('이미지 오류 뒤에도 남아야 하는 텍스트');
  });

  test('이미지 처리 중 다른 노트로 전환해도 새 노트를 이전 내용으로 덮지 않는다', async ({ page }) => {
    await openApp(page);
    await page.locator('#homeNoteOnlyCard').click();
    await page.locator('#mynoteBlockContent').fill('A 노트 원문');
    await page.locator('#mynoteSaveBtn').click();
    await page.evaluate(() => {
      const meetings = JSON.parse(localStorage.getItem('ai_pronote.meetings.v1') || '[]');
      meetings.push({ id: 'image-race-b', title: 'B 노트', note: '<p>B 노트 원문</p>', standalone: true });
      localStorage.setItem('ai_pronote.meetings.v1', JSON.stringify(meetings));
      const original = window.createImageBitmap.bind(window);
      window.createImageBitmap = async (...args: Parameters<typeof createImageBitmap>) => {
        await new Promise(resolve => setTimeout(resolve, 400));
        return original(...args);
      };
    });
    await page.locator('#mynoteImageInput').setInputFiles({
      name: 'memo.png', mimeType: 'image/png',
      buffer: Buffer.from('iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAIAAACQkWg2AAAAI0lEQVR4nGM8kWLEQApgIkk1w6gG4gATkergYFQDMYDkUAIAYgYBfoIBT3AAAAAASUVORK5CYII=', 'base64')
    });
    expect(await page.evaluate(() => (window as typeof window & { __pronoteSwitchMyNoteMeeting: (id: string) => Promise<boolean> }).__pronoteSwitchMyNoteMeeting('image-race-b'))).toBe(true);
    await expect(page.locator('#toast')).toContainText('노트가 바뀌어 첨부를 취소했습니다');
    await expect(page.locator('#mynoteBlockContent')).toContainText('B 노트 원문');
    await expect(page.locator('#mynoteBlockContent')).not.toContainText('A 노트 원문');
    expect(await page.evaluate(() => JSON.parse(localStorage.getItem('ai_pronote.meetings.v1') || '[]').find((m: { id: string }) => m.id === 'image-race-b')?.note)).toBe('<p>B 노트 원문</p>');
  });

  test('새 노트 화면 전환이 실패하면 빈 고아 노트를 남기지 않는다', async ({ page }) => {
    await openApp(page);
    await page.evaluate(() => (window as typeof window & { switchView: (view: string) => void }).switchView('mynotes'));
    const before = await page.evaluate(() => JSON.parse(localStorage.getItem('ai_pronote.meetings.v1') || '[]').length);
    await page.evaluate(() => {
      (window as typeof window & { __pronoteSwitchMyNoteMeeting: (id: string) => Promise<boolean> }).__pronoteSwitchMyNoteMeeting = async () => false;
    });
    await page.locator('#newStandaloneNoteBtn').click();
    expect(await page.evaluate(() => JSON.parse(localStorage.getItem('ai_pronote.meetings.v1') || '[]').length)).toBe(before);
  });

  test('전역 임시 노트에서 회의 노트로 이동해도 두 저장 대상을 섞지 않는다', async ({ page }) => {
    await openApp(page);
    await page.evaluate(() => {
      localStorage.removeItem('ai_pronote.current_view_meeting.v1');
      localStorage.setItem('ai_pronote.note_draft.v1', '<p>전역 임시 노트</p>');
    });
    await openNavView(page, 'result-mynote');
    await expect(page.locator('#mynoteBlockContent')).toContainText('전역 임시 노트');
    await page.locator('#mynoteBlockContent').fill('저장 대상이 섞이면 안 되는 임시 노트 수정본');
    await page.evaluate(() => {
      const meetings = JSON.parse(localStorage.getItem('ai_pronote.meetings.v1') || '[]');
      meetings.push({ id: 'note-target-b', title: '대상 B', note: '<p>B 원본</p>', standalone: true });
      localStorage.setItem('ai_pronote.meetings.v1', JSON.stringify(meetings));
      localStorage.setItem('ai_pronote.current_view_meeting.v1', 'note-target-b');
      (window as typeof window & { __pronoteShowMyNoteFullPage: () => boolean }).__pronoteShowMyNoteFullPage();
    });
    await expect(page.locator('#mynoteBlockContent')).toContainText('B 원본');
    const values = await page.evaluate(() => ({
      draft: localStorage.getItem('ai_pronote.note_draft.v1'),
      meeting: JSON.parse(localStorage.getItem('ai_pronote.meetings.v1') || '[]').find((m: { id: string }) => m.id === 'note-target-b')
    }));
    expect(values.draft).toContain('임시 노트 수정본');
    expect(values.meeting.note).toBe('<p>B 원본</p>');
  });

  test('노트 전환 전 저장 실패 시 입력을 유지하고 화면 이동을 중단한다', async ({ page }) => {
    await openApp(page);
    await page.evaluate(() => {
      const meetings = [
        { id: 'note-save-a', title: '노트 A', note: '<p>A 원본</p>', standalone: true },
        { id: 'note-save-b', title: '노트 B', note: '<p>B 원본</p>', standalone: true }
      ];
      localStorage.setItem('ai_pronote.meetings.v1', JSON.stringify(meetings));
      localStorage.setItem('ai_pronote.current_view_meeting.v1', 'note-save-a');
    });
    await openNavView(page, 'result-mynote');
    await page.locator('#mynoteBlockContent').fill('저장 실패 시 사라지면 안 되는 A 수정본');
    const switched = await page.evaluate(() => {
      const original = Storage.prototype.setItem;
      (window as typeof window & { __inkMeetingSwitches?: Array<string | null> }).__inkMeetingSwitches = [];
      const ink = (window as typeof window & { PronoteInk?: { switchMeeting?: (id: string | null) => Promise<void> } }).PronoteInk;
      if (ink) ink.switchMeeting = async (id: string | null) => {
        (window as typeof window & { __inkMeetingSwitches: Array<string | null> }).__inkMeetingSwitches.push(id);
      };
      Storage.prototype.setItem = function(key: string, value: string) {
        if (key === 'ai_pronote.meetings.v1') throw new DOMException('quota', 'QuotaExceededError');
        return original.call(this, key, value);
      };
      return (window as typeof window & { __pronoteSwitchMyNoteMeeting: (id: string) => Promise<boolean> }).__pronoteSwitchMyNoteMeeting('note-save-b');
    });
    expect(switched).toBe(false);
    await expect(page.locator('#mynoteBlockContent')).toContainText('저장 실패 시 사라지면 안 되는 A 수정본');
    await expect(page.locator('#toast')).toContainText('화면 이동을 중단했습니다');
    expect(await page.evaluate(() => localStorage.getItem('ai_pronote.current_view_meeting.v1'))).toBe('note-save-a');
    expect(await page.evaluate(() => (window as typeof window & { __inkMeetingSwitches: Array<string | null> }).__inkMeetingSwitches)).toEqual([]);
    await expect(page.locator('#noteEmergencyRecoveryPanel')).toBeVisible();
    await expect(page.locator('#mynoteSaveState')).toContainText('복구본 필요');
    const downloadPromise = page.waitForEvent('download');
    await page.locator('#noteEmergencyRecoveryPanel button').click();
    const download = await downloadPromise;
    expect(download.suggestedFilename()).toContain('긴급복구.pronote.json');
    const downloadPath = await download.path();
    const recovery = JSON.parse(fs.readFileSync(downloadPath!, 'utf8'));
    expect(recovery.format).toBe('ai-pronote-note');
    expect(recovery.title).toBe('노트 A');
    expect(recovery.html).toContain('저장 실패 시 사라지면 안 되는 A 수정본');
    expect(recovery.recovery.reason).toBe('local_save_failed');
  });

  test('필기 로드 중 빠른 중복 선택이 회의 상태를 교차시키지 않는다', async ({ page }) => {
    await openApp(page);
    const result = await page.evaluate(async () => {
      localStorage.setItem('ai_pronote.current_view_meeting.v1', 'note-race-a');
      let releaseInk!: () => void;
      const inkPending = new Promise<void>(resolve => { releaseInk = resolve; });
      const ink = (window as typeof window & { PronoteInk?: { switchMeeting?: (id: string | null) => Promise<void> } }).PronoteInk;
      if (ink) ink.switchMeeting = async () => inkPending;
      const api = (window as typeof window & { __pronoteSwitchMyNoteMeeting: (id: string) => Promise<boolean> }).__pronoteSwitchMyNoteMeeting;
      const first = api('note-race-b');
      const second = await api('note-race-c');
      releaseInk();
      return { first: await first, second, current: localStorage.getItem('ai_pronote.current_view_meeting.v1') };
    });
    expect(result).toEqual({ first: true, second: false, current: 'note-race-b' });
  });

  test('필기 탭, 도구, 캔버스, undo/redo와 회의별 IndexedDB 저장을 제공한다', async ({ page }) => {
    await openApp(page);
    await openNavView(page, 'result-mynote');
    await page.locator('#noteModeInk').click();
    await expect(page.locator('#inkPanel')).toBeVisible();
    await expect(page.locator('#inkCanvas')).toBeVisible();
    await expect(page.locator('[data-ink-tool="pen"]')).toBeVisible();
    await expect(page.locator('[data-ink-tool="eraser"]')).toBeVisible();
    await expect(page.locator('#inkUndo')).toBeVisible();
    await expect(page.locator('#inkRedo')).toBeVisible();

    const canvas = page.locator('#inkCanvas');
    await canvas.scrollIntoViewIfNeeded();
    const box = await canvas.boundingBox();
    expect(box).not.toBeNull();
    await page.mouse.move(box!.x + 30, box!.y + 30);
    await page.mouse.down();
    await page.mouse.move(box!.x + 130, box!.y + 100, { steps: 8 });
    await page.mouse.up();

    await expect.poll(() => page.evaluate(async () => {
      const request = indexedDB.open('pronote-ink-v1', 1);
      const db: IDBDatabase = await new Promise((resolve, reject) => {
        request.onsuccess = () => resolve(request.result);
        request.onerror = () => reject(request.error);
      });
      return await new Promise<number>((resolve, reject) => {
        const tx = db.transaction('documents', 'readonly');
        const get = tx.objectStore('documents').get('e2e-meeting-001');
        get.onsuccess = () => resolve(get.result?.strokes?.length || 0);
        get.onerror = () => reject(get.error);
      });
    })).toBeGreaterThan(0);

    await page.locator('#inkUndo').click();
    await page.locator('#inkRedo').click();
    await page.reload();
    await openNavView(page, 'result-mynote');
    await page.locator('#noteModeInk').click();
    await expect(page.locator('#inkCanvas')).toBeVisible();
  });
});

test.describe('AI 연결 구분', () => {
  test('공식 BYOK와 실험 CLI를 오인 없이 구분한다', async ({ page }) => {
    await mockBackend(page);
    await openApp(page);
    await openNavView(page, 'admin');
    await expect(page.getByRole('heading', { name: 'AI 연결 · 개인 API 키' })).toBeVisible();
    await expect(page.locator('#officialProviderSelect')).toContainText('OpenAI (ChatGPT API)');
    await expect(page.locator('#officialProviderSelect')).toContainText('Google Gemini API');
    await expect(page.locator('#officialProviderSelect')).toContainText('Anthropic (Claude API)');
    await expect(page.locator('#providerConsent')).not.toBeChecked();
    await expect(page.locator('#experimentalCliPanel')).toBeVisible();
    await expect(page.locator('#experimentalCliStatuses')).toContainText('Codex CLI (실험)');
    await expect(page.locator('#experimentalCliStatuses')).toContainText('Claude CLI (실험)');
    await expect(page.locator('#experimentalCliStatuses')).not.toContainText('Gemini CLI (실험)');
    await expect(page.locator('#experimentalCliStatuses')).toContainText(/로그인 필요|미설치/);
  });

  test('기존 Gemini CLI 설정은 선택·저장·실행 경계에서 정책 차단한다', async ({ page }) => {
    await page.addInitScript(() => {
      localStorage.setItem('ai_pronote.settings.v1', JSON.stringify({ ai: { provider: 'gemini' } }));
    });
    await mockBackend(page);
    await openApp(page);
    await openNavView(page, 'admin');
    await page.locator('#view-admin .admin-card[data-admin="transcribe"]').click();
    const blocked = page.locator('[data-provider="gemini_cli"]');
    await expect(blocked).toHaveAttribute('aria-disabled', 'true');
    await expect(blocked).not.toHaveClass(/active/);
    expect(await page.evaluate(() => window.__pronoteGetAIProvider())).toBe('policy_blocked');
    await page.evaluate(() => document.getElementById('adminModalSave')!.click());
    expect(await page.evaluate(() => JSON.parse(localStorage.getItem('ai_pronote.settings.v1') || '{}').ai)).toBeUndefined();
  });
});

test.describe('PWA 설치 준비 계약', () => {
  test('manifest, service worker, 아이콘과 standalone 설정이 유효하다', async ({ page, request }) => {
    await mockBackend(page);
    const manifestResponse = await request.get('/static/manifest.webmanifest');
    expect(manifestResponse.ok()).toBeTruthy();
    const manifest = await manifestResponse.json();
    expect(manifest.display).toBe('standalone');
    expect(manifest.icons.some((icon: { sizes?: string }) => icon.sizes === '192x192')).toBeTruthy();
    expect(manifest.icons.some((icon: { sizes?: string }) => icon.sizes === '512x512')).toBeTruthy();

    const swResponse = await request.get('/static/sw.js');
    expect(swResponse.ok()).toBeTruthy();
    expect(await swResponse.text()).toContain('CACHE');

    await openApp(page);
    await expect(page.locator('link[rel="manifest"]')).toHaveAttribute('href', '/static/manifest.webmanifest');
    await expect(page.locator('link[rel="apple-touch-icon"]')).toHaveCount(1);
    await expect(page.locator('meta[name="viewport"]')).toHaveAttribute('content', /viewport-fit=cover/);
  });
});

test.describe('버전 표시와 자동 업데이트 안내', () => {
  test('새 버전이 있으면 팝업을 띄우고 명시적 선택 뒤에만 준비한다', async ({ page }) => {
    await mockBackend(page);
    let prepared = false;
    await page.route('**/api/health', route => route.fulfill({
      status: 200, contentType: 'application/json', body: JSON.stringify({ status: 'ok', version: 'v1.5.0-beta13.20260919' })
    }));
    await page.route('**/api/update/status', route => route.fulfill({
      status: 200, contentType: 'application/json', body: JSON.stringify({
        state: 'available', version: 'v1.5.0-beta13.20260920', prepare_allowed: true,
        release_notes_url: 'https://example.com/release-notes'
      })
    }));
    await page.route('**/api/update/prepare', route => {
      prepared = true;
      return route.fulfill({
        status: 200, contentType: 'application/json', body: JSON.stringify({ state: 'prepared', restart_required: true })
      });
    });
    await openApp(page);
    await expect(page.locator('#appVersionLabel')).toContainText('v1.5.0-beta13.20260919');
    await expect(page.locator('#updateAvailableModal')).toHaveClass(/open/);
    await expect(page.locator('#updateAvailableVersion')).toContainText('1.5.0-beta13.20260920');
    expect(prepared).toBeFalsy();
    await page.locator('#updateAvailablePrepare').click();
    await expect(page.locator('#updateAvailableTitle')).toHaveText('업데이트 준비가 끝났습니다');
    expect(prepared).toBeTruthy();
  });
});

test.describe('카메라 회의 녹화·보존 계약', () => {
  test('마이크 권한이 거부되면 가짜 녹음 화면으로 전환하지 않는다', async ({ page }) => {
    await page.addInitScript(() => {
      Object.defineProperty(navigator, 'mediaDevices', {
        configurable: true,
        value: {
          getUserMedia: async () => {
            throw new DOMException('Permission denied by E2E', 'NotAllowedError');
          }
        }
      });
    });
    await mockBackend(page);
    await openApp(page);

    await page.locator('#newMeetingBtn').click();
    await expect(page.locator('#meetingTypeModal')).toHaveClass(/open/);
    await page.locator('#newMeetingTitle').fill('권한 거부 회의');
    await page.locator('#meetingTypeStart').click();

    await expect(page.locator('#meetingTypeModal')).toHaveClass(/open/);
    await expect(page.locator('#view-live')).not.toHaveClass(/active/);
    await expect(page.locator('#meetingTypeStart')).toBeEnabled();
    await expect(page.locator('#meetingTypeStart')).toHaveText('녹음 시작 →');
    await expect(page.locator('body')).toContainText('녹음 시작 실패: 마이크 권한 거부');
    expect(await page.evaluate(() => window.__pronoteRecording.isActive())).toBeFalsy();
  });

  test('장치 연결 성공 뒤에만 실제 회의 화면과 타이머를 연다', async ({ page }) => {
    await installSyntheticCameraAndMicrophone(page);
    await mockBackend(page);
    await openApp(page);

    await page.locator('#newMeetingBtn').click();
    await page.locator('#newMeetingTitle').fill('UI 장치 연결 성공 회의');
    await page.locator('#newMeetingVideo').locator('xpath=ancestor::label').click();
    await expect(page.locator('#newMeetingVideo')).toBeChecked();
    await page.locator('#meetingTypeStart').click();

    await expect(page.locator('#meetingTypeModal')).not.toHaveClass(/open/);
    await expect(page.locator('#view-live')).toHaveClass(/active/);
    await expect.poll(() => page.evaluate(() => window.__pronoteRecording.isActive())).toBeTruthy();
    await expect(page.locator('#view-live .rec-status-pill')).toContainText(/녹음 중 · 00:00:0[0-9]/);

    await page.waitForTimeout(1200);
    await page.evaluate(() => window.__pronoteRecording.stop());
    await expect.poll(() => page.evaluate(() => window.__pronoteRecording.isActive()), { timeout: 10_000 }).toBeFalsy();
  });

  test('장치 초기화 실패 시 획득한 미디어 트랙과 AudioContext를 정리한다', async ({ page }) => {
    await installSyntheticCameraAndMicrophone(page);
    await page.addInitScript(() => {
      const nativeClose = AudioContext.prototype.close;
      (window as typeof window & { __closedAudioContexts?: number }).__closedAudioContexts = 0;
      AudioContext.prototype.close = function() {
        (window as typeof window & { __closedAudioContexts?: number }).__closedAudioContexts =
          ((window as typeof window & { __closedAudioContexts?: number }).__closedAudioContexts || 0) + 1;
        return nativeClose.call(this);
      };
      Object.defineProperty(window, 'MediaRecorder', {
        configurable: true,
        value: class BrokenMediaRecorder {
          static isTypeSupported() { return true; }
          constructor() { throw new Error('synthetic recorder failure'); }
        }
      });
    });
    await mockBackend(page);
    await openApp(page);

    const started = await page.evaluate(() => window.__pronoteRecording.start('realtime', {
      context: 'live', recordVideo: true, meta: { title: '초기화 실패 정리' }
    }));
    expect(started).toBeFalsy();
    await expect.poll(() => page.evaluate(() => {
      const streams = (window as typeof window & { __syntheticStreams?: MediaStream[] }).__syntheticStreams || [];
      return streams.length >= 2 && streams.every(stream => stream.getTracks().every(track => track.readyState === 'ended'));
    })).toBeTruthy();
    await expect.poll(() => page.evaluate(() =>
      (window as typeof window & { __closedAudioContexts?: number }).__closedAudioContexts || 0
    )).toBeGreaterThanOrEqual(1);
  });

  test('동시에 두 번 시작해도 recorder는 하나만 만든다', async ({ page }) => {
    await installSyntheticCameraAndMicrophone(page);
    await mockBackend(page);
    await openApp(page);

    const results = await page.evaluate(() => Promise.all([
      window.__pronoteRecording.start('realtime', { context: 'live', meta: { title: '첫 시작' } }),
      window.__pronoteRecording.start('realtime', { context: 'live', meta: { title: '중복 시작' } })
    ]));
    expect(results.filter(Boolean)).toHaveLength(1);
    expect(await page.evaluate(() =>
      (window as typeof window & { __syntheticStreams?: MediaStream[] }).__syntheticStreams?.length || 0
    )).toBe(1);
    await page.evaluate(() => window.__pronoteRecording.stop());
    await expect.poll(() => page.evaluate(() => window.__pronoteRecording.isActive()), { timeout: 10_000 }).toBeFalsy();
  });

  test('실시간 초안 recorder 시작 실패가 본 녹음을 숨기거나 중단하지 않는다', async ({ page }) => {
    await installSyntheticCameraAndMicrophone(page);
    await page.addInitScript(() => {
      const NativeMediaRecorder = window.MediaRecorder;
      let starts = 0;
      class PartialStartFailureRecorder extends NativeMediaRecorder {
        start(timeslice?: number) {
          starts += 1;
          if (starts === 2) throw new Error('synthetic partial recorder start failure');
          return super.start(timeslice);
        }
      }
      Object.defineProperty(window, 'MediaRecorder', { configurable: true, value: PartialStartFailureRecorder });
    });
    await mockBackend(page);
    await openApp(page);

    const started = await page.evaluate(() => window.__pronoteRecording.start('realtime', {
      context: 'live', meta: { title: '부분 받아쓰기 실패 회의' }
    }));
    expect(started).toBeTruthy();
    expect(await page.evaluate(() => window.__pronoteRecording.isActive())).toBeTruthy();
    await page.waitForTimeout(1200);
    await page.evaluate(() => window.__pronoteRecording.stop());
    await expect.poll(() => page.evaluate(() => window.__pronoteRecording.isActive()), { timeout: 10_000 }).toBeFalsy();
  });

  test('권한 대기 중 취소하면 뒤늦게 회의 화면을 열지 않고 트랙을 정리한다', async ({ page }) => {
    await installSyntheticCameraAndMicrophone(page);
    await page.addInitScript(() => {
      const media = navigator.mediaDevices;
      const original = media.getUserMedia.bind(media);
      media.getUserMedia = async constraints => {
        await new Promise(resolve => setTimeout(resolve, 400));
        return original(constraints);
      };
    });
    await mockBackend(page);
    await openApp(page);

    await page.locator('#newMeetingBtn').click();
    await page.locator('#meetingTypeStart').click();
    await expect(page.locator('#meetingTypeStart')).toBeDisabled();
    await page.locator('#meetingTypeCancel').click();
    await expect(page.locator('#meetingTypeModal')).not.toHaveClass(/open/);
    await page.waitForTimeout(700);
    await expect(page.locator('#view-live')).not.toHaveClass(/active/);
    expect(await page.evaluate(() => window.__pronoteRecording.isActive())).toBeFalsy();
    await expect.poll(() => page.evaluate(() => {
      const streams = (window as typeof window & { __syntheticStreams?: MediaStream[] }).__syntheticStreams || [];
      return streams.length > 0 && streams.every(stream => stream.getTracks().every(track => track.readyState === 'ended'));
    })).toBeTruthy();
  });

  test('영상과 별도 음성 원본을 함께 저장하고 회의 기록을 만든다', async ({ page }) => {
    await installSyntheticCameraAndMicrophone(page);
    await mockBackend(page);
    await openApp(page);

    const started = await page.evaluate(() => window.__pronoteRecording.start('realtime', {
      context: 'live',
      recordVideo: true,
      meta: { title: 'E2E 카메라 회의', tag: '프로젝트', language: 'ko' }
    }));
    expect(started).toBeTruthy();
    await expect.poll(() => page.evaluate(() => window.__pronoteRecording.isActive())).toBeTruthy();

    await page.waitForTimeout(2200);
    await page.evaluate(() => window.__pronoteRecording.stop());
    await expect.poll(() => page.evaluate(() => window.__pronoteRecording.isActive()), { timeout: 10_000 }).toBeFalsy();

    await expect.poll(async () => page.evaluate(async () => {
      const records = await window.__pronoteDB.getAll();
      return records.filter((record: { source?: string }) =>
        record.source === 'recorded' || record.source === 'recorded-video').length;
    }), { timeout: 10_000 }).toBe(2);

    const result = await page.evaluate(async () => {
      const records = await window.__pronoteDB.getAll();
      const audio = records.find((record: { source?: string }) => record.source === 'recorded');
      const video = records.find((record: { source?: string }) => record.source === 'recorded-video');
      const meetings = JSON.parse(localStorage.getItem('ai_pronote.meetings.v1') || '[]');
      const recorderStreams = (window as typeof window & {
        __recorderStreams?: Array<{ audioTracks: number; videoTracks: number }>;
      }).__recorderStreams || [];
      const audioContexts = ((window as typeof window & { __syntheticMedia?: unknown[] }).__syntheticMedia || [])
        .filter((item): item is AudioContext => item instanceof AudioContext);
      return {
        audioSize: audio?.blob?.size || 0,
        videoSize: video?.blob?.size || 0,
        videoHasAudio: recorderStreams.some(stream => stream.videoTracks > 0 && stream.audioTracks > 0),
        separateAudioRecorder: recorderStreams.some(stream => stream.videoTracks === 0 && stream.audioTracks > 0),
        audioContextsRunning: audioContexts.length > 0 && audioContexts.every(context => context.state === 'running'),
        meetingRecordingId: meetings[0]?.recordingId || '',
        summaryPending: meetings[0]?.summaryPending === true
      };
    });
    expect(result.audioSize).toBeGreaterThan(0);
    expect(result.videoSize).toBeGreaterThan(0);
    expect(result.videoHasAudio).toBeTruthy();
    expect(result.separateAudioRecorder).toBeTruthy();
    expect(result.audioContextsRunning).toBeTruthy();
    expect(result.meetingRecordingId).toMatch(/^rec_/);
    expect(result.summaryPending).toBeTruthy();
  });

  test('이어 녹음은 새 회의를 만들지 않고 원 회의에 두 번째 녹음 구간을 추가한다', async ({ page }) => {
    await installSyntheticCameraAndMicrophone(page);
    await mockBackend(page);
    await seedSyntheticMeeting(page);
    await openApp(page);
    await page.evaluate(async () => {
      await window.__pronoteDB.put({
        id: 'e2e-recording-001', filename: '첫구간.webm', title: 'E2E 합성 주간 회의',
        blob: new Blob(['first'], { type: 'audio/webm' }), durationSec: 720,
        startedAt: Date.now() - 730_000, endedAt: Date.now() - 10_000,
        source: 'recorded', transcribed: true, transcript: '첫 번째 구간 원문', summary: '첫 번째 구간 회의록'
      });
    });

    const started = await page.evaluate(meetingId => window.__pronoteRecording.start('realtime', {
      context: 'live',
      meta: { title: 'E2E 합성 주간 회의', tag: '회의', language: 'ko', parentMeetingId: meetingId }
    }), syntheticMeeting.id);
    expect(started).toBeTruthy();
    await page.waitForTimeout(1200);
    await page.evaluate(() => window.__pronoteRecording.stop());
    await expect.poll(() => page.evaluate(() => window.__pronoteRecording.isActive()), { timeout: 10_000 }).toBeFalsy();

    const merged = await page.evaluate(async meetingId => {
      const meetings = JSON.parse(localStorage.getItem('ai_pronote.meetings.v1') || '[]');
      const meeting = meetings.find((item: { id: string }) => item.id === meetingId);
      const records = await window.__pronoteDB.getAll();
      return {
        meetingCount: meetings.length,
        title: meeting?.title,
        recordingIds: meeting?.recordingIds || [],
        segments: meeting?.recordingSegments || [],
        durationSec: meeting?.recordingDurationSec,
        linkedMeetingIds: records.filter((record: { source?: string }) => record.source === 'recorded').map((record: { meetingId?: string }) => record.meetingId)
      };
    }, syntheticMeeting.id);
    expect(merged.meetingCount).toBe(1);
    expect(merged.title).toBe('E2E 합성 주간 회의');
    expect(merged.recordingIds).toHaveLength(2);
    expect(merged.recordingIds[0]).toBe('e2e-recording-001');
    expect(merged.segments).toHaveLength(2);
    expect(merged.durationSec).toBeGreaterThan(0);
    expect(merged.linkedMeetingIds).toContain(syntheticMeeting.id);

    await page.evaluate(() => window.switchView?.('result'));
    await page.evaluate(() => window.__pronoteLoadResultAudio?.());
    await expect(page.locator('#sideAudioSegmentSelect')).toBeVisible();
    await expect(page.locator('#sideAudioSegmentSelect option')).toHaveCount(2);
    await page.locator('#sideAudioSegmentSelect').selectOption('e2e-recording-001');
    await page.locator('.side-tab[data-side-tab="transcript"]').click();
    await expect(page.locator('#sideTranscriptPanel')).toBeVisible();
    await page.evaluate(() => {
      const select = document.getElementById('sideAudioSegmentSelect') as HTMLSelectElement;
      select.selectedIndex = 1;
      select.dispatchEvent(new Event('change', { bubbles: true }));
    });
    await expect(page.locator('#sideTranscriptPanel')).toBeHidden();
  });

  test('이어진 각 구간의 받아쓰기와 회의록 결과를 원 회의 순서로 합친다', async ({ page }) => {
    await mockBackend(page);
    await page.route('**/api/llm/summarize', route => route.fulfill({
      status: 200,
      contentType: 'application/json; charset=utf-8',
      body: JSON.stringify({ summary: '두 번째 구간 회의록', model_id: 'mock', elapsed_sec: 1, char_count: 12 })
    }));
    await page.addInitScript(() => {
      localStorage.setItem('ai_pronote.meetings.v1', JSON.stringify([{
        id: 'merged-meeting', title: '합쳐진 회의', tag: '회의', date: '2026-09-18',
        recordingId: 'merged-rec-1', recordingIds: ['merged-rec-1', 'merged-rec-2'],
        recordingSegments: [{ id: 'merged-rec-1' }, { id: 'merged-rec-2' }], summaryPending: true
      }]));
      localStorage.setItem('ai_pronote.current_view_meeting.v1', 'merged-meeting');
    });
    await openApp(page);
    await page.evaluate(async () => {
      await window.__pronoteDB.put({
        id: 'merged-rec-1', filename: '1.webm', blob: new Blob(['one']), source: 'recorded',
        startedAt: Date.now() - 2000, transcribed: true, transcript: '첫 번째 구간 원문', summary: '첫 번째 구간 회의록', scenarioKey: 'meeting'
      });
      await window.__pronoteDB.put({
        id: 'merged-rec-2', filename: '2.webm', blob: new Blob(['two']), source: 'recorded',
        startedAt: Date.now() - 1000, transcribed: true, transcript: '두 번째 구간 원문', scenarioKey: 'meeting'
      });
      await window.__pronoteLibrary.runSummarize('merged-rec-2');
    });
    const merged = await page.evaluate(() => JSON.parse(localStorage.getItem('ai_pronote.meetings.v1') || '[]')[0]);
    expect(merged.title).toBe('합쳐진 회의');
    expect(merged.transcript).toContain('녹음 구간 1');
    expect(merged.transcript).toContain('첫 번째 구간 원문');
    expect(merged.transcript).toContain('두 번째 구간 원문');
    expect(merged.summary).toContain('녹음 구간 회의록 1');
    expect(merged.summary).toContain('첫 번째 구간 회의록');
    expect(merged.summary).toContain('두 번째 구간 회의록');
  });

  test('두 구간 결과가 동시에 끝나도 최신 노트 수정과 다른 편집 화면을 보존한다', async ({ page }) => {
    await mockBackend(page);
    await page.route('**/api/llm/summarize', async route => {
      const payload = route.request().postDataJSON() as { transcript?: string };
      if (payload.transcript?.includes('첫 구간')) await new Promise(resolve => setTimeout(resolve, 180));
      await route.fulfill({
        status: 200, contentType: 'application/json; charset=utf-8',
        body: JSON.stringify({
          summary: payload.transcript?.includes('첫 구간') ? '첫 구간 동시 완료 요약' : '둘째 구간 동시 완료 요약',
          model_id: 'mock', elapsed_sec: 1, char_count: 12
        })
      });
    });
    await page.addInitScript(() => {
      localStorage.setItem('ai_pronote.meetings.v1', JSON.stringify([
        { id: 'race-parent', title: '동시 완료 회의', tag: '회의', date: '2026-09-18', dateLabel: '오늘', duration: '2분', recordingId: 'race-1', recordingIds: ['race-1', 'race-2'], note: '<p>원래 노트</p>' },
        { id: 'editing-note', title: '지금 편집 중인 노트', tag: '단독 메모', date: '2026-09-18', dateLabel: '오늘', duration: '—', note: '<p>편집 유지</p>', standalone: true }
      ]));
      localStorage.setItem('ai_pronote.current_view_meeting.v1', 'editing-note');
    });
    await openApp(page);
    await page.evaluate(async () => {
      await window.__pronoteDB.put({ id: 'race-1', blob: new Blob(['1']), transcript: '첫 구간 원문', transcribed: true, scenarioKey: 'meeting', startedAt: Date.now() - 2000 });
      await window.__pronoteDB.put({ id: 'race-2', blob: new Blob(['2']), transcript: '둘째 구간 원문', transcribed: true, scenarioKey: 'meeting', startedAt: Date.now() - 1000 });
      (window as typeof window & { __mergePromise?: Promise<unknown> }).__mergePromise = Promise.all([
        window.__pronoteLibrary.runSummarize('race-1'),
        window.__pronoteLibrary.runSummarize('race-2')
      ]);
    });
    await page.waitForTimeout(70);
    await page.evaluate(() => {
      const meetings = JSON.parse(localStorage.getItem('ai_pronote.meetings.v1') || '[]');
      meetings.find((m: { id: string }) => m.id === 'race-parent').note = '<p>처리 중 사용자가 수정한 노트</p>';
      localStorage.setItem('ai_pronote.meetings.v1', JSON.stringify(meetings));
    });
    await page.evaluate(() => (window as typeof window & { __mergePromise?: Promise<unknown> }).__mergePromise);
    const state = await page.evaluate(() => {
      const meetings = JSON.parse(localStorage.getItem('ai_pronote.meetings.v1') || '[]');
      return {
        currentId: localStorage.getItem('ai_pronote.current_view_meeting.v1'),
        parent: meetings.find((m: { id: string }) => m.id === 'race-parent')
      };
    });
    expect(state.currentId).toBe('editing-note');
    expect(state.parent.note).toContain('처리 중 사용자가 수정한 노트');
    expect(state.parent.summary).toContain('첫 구간 동시 완료 요약');
    expect(state.parent.summary).toContain('둘째 구간 동시 완료 요약');
    expect(state.parent.transcript).toContain('첫 구간 원문');
    expect(state.parent.transcript).toContain('둘째 구간 원문');
  });

  test('상태 기록이 없는 다른 구간이 남아 있으면 한 구간 실패를 전체 완료로 표시하지 않는다', async ({ page }) => {
    await mockBackend(page);
    await page.addInitScript(() => {
      localStorage.setItem('ai_pronote.meetings.v1', JSON.stringify([{
        id: 'pending-parent', title: '상태 집계 회의', tag: '회의', date: '2026-09-18', dateLabel: '오늘', duration: '2분',
        recordingId: 'pending-1', recordingIds: ['pending-1', 'pending-2'], summary: '', summaryPending: true
      }]));
    });
    await openApp(page);
    await page.evaluate(async () => {
      await window.__pronoteDB.put({ id: 'pending-2', filename: 'pending.webm', blob: new Blob(['x']), scenarioKey: 'meeting', startedAt: Date.now() });
      await window.__pronoteLibrary.runTranscribe('pending-2');
    });
    const meeting = await page.evaluate(() => JSON.parse(localStorage.getItem('ai_pronote.meetings.v1') || '[]')[0]);
    expect(meeting.recordingStatuses['pending-2'].error).toContain('받아쓰기 요청 실패');
    expect(meeting.summaryPending).toBeTruthy();
  });

  test('녹음 전 저장공간이 부족하면 장치 권한 요청 전에 시작을 막는다', async ({ page }) => {
    await installSyntheticCameraAndMicrophone(page);
    await page.addInitScript(() => {
      Object.defineProperty(navigator, 'storage', {
        configurable: true,
        value: { estimate: async () => ({ quota: 300 * 1024 ** 2, usage: 250 * 1024 ** 2 }) }
      });
    });
    await mockBackend(page);
    await openApp(page);

    const started = await page.evaluate(() => window.__pronoteRecording.start('realtime', {
      context: 'live', recordVideo: true, meta: { title: '저장공간 부족 회의' }
    }));
    expect(started).toBeFalsy();
    expect(await page.evaluate(() =>
      (window as typeof window & { __syntheticStreams?: MediaStream[] }).__syntheticStreams?.length || 0
    )).toBe(0);
    await expect(page.locator('body')).toContainText('저장 공간이 부족합니다');
  });

  test('마이크 연결이 끊기면 현재 녹음을 자동 종료해 저장한다', async ({ page }) => {
    await installSyntheticCameraAndMicrophone(page);
    await mockBackend(page);
    await openApp(page);

    expect(await page.evaluate(() => window.__pronoteRecording.start('realtime', {
      context: 'live', meta: { title: '마이크 분리 회의' }
    }))).toBeTruthy();
    await page.waitForTimeout(1200);
    await page.evaluate(() => {
      const stream = (window as typeof window & { __syntheticStreams?: MediaStream[] }).__syntheticStreams?.[0];
      stream?.getAudioTracks()[0]?.dispatchEvent(new Event('ended'));
    });

    await expect.poll(() => page.evaluate(() => window.__pronoteRecording.isActive()), { timeout: 10_000 }).toBeFalsy();
    await expect.poll(async () => page.evaluate(async () =>
      (await window.__pronoteDB.getAll()).filter((record: { source?: string }) => record.source === 'recorded').length
    )).toBe(1);
  });

  test('최종 저장소 오류 시 회의 유령기록을 만들지 않고 긴급 복구 파일을 내려받는다', async ({ page }) => {
    await installSyntheticCameraAndMicrophone(page);
    await mockBackend(page);
    await openApp(page);

    expect(await page.evaluate(() => window.__pronoteRecording.start('realtime', {
      context: 'live', meta: { title: '저장 실패 복구 회의' }
    }))).toBeTruthy();
    await page.waitForTimeout(1200);
    await page.evaluate(() => {
      const db = window.__pronoteDB;
      const originalPut = db.put.bind(db);
      db.put = async (record: { source?: string }) => {
        if (record.source === 'recorded') throw new Error('synthetic quota exceeded');
        return originalPut(record);
      };
    });
    const downloadPromise = page.waitForEvent('download');
    await page.evaluate(() => window.__pronoteRecording.stop());
    const download = await downloadPromise;

    expect(download.suggestedFilename()).toMatch(/^긴급복구_.*\.(mp3|webm|m4a)$/);
    await expect.poll(() => page.evaluate(() => window.__pronoteRecording.isActive()), { timeout: 10_000 }).toBeFalsy();
    expect(await page.evaluate(() => JSON.parse(localStorage.getItem('ai_pronote.meetings.v1') || '[]').length)).toBe(0);
    await expect(page.locator('#view-library')).toHaveClass(/active/);
    await expect(page.locator('body')).toContainText('긴급 복구 다운로드를 요청했습니다');
    await expect(page.locator('#emergencyRecoveryPanel')).toBeVisible();
    await expect(page.locator('#emergencyRecoveryPanel button')).toHaveCount(1);
  });

  test('영상과 음성 저장이 모두 실패해도 두 복구 파일을 각각 다시 받을 수 있다', async ({ page }) => {
    await installSyntheticCameraAndMicrophone(page);
    await mockBackend(page);
    await openApp(page);

    expect(await page.evaluate(() => window.__pronoteRecording.start('realtime', {
      context: 'live', recordVideo: true, meta: { title: '영상 음성 동시 복구' }
    }))).toBeTruthy();
    await page.waitForTimeout(1200);
    await page.evaluate(() => {
      const db = window.__pronoteDB;
      const originalPut = db.put.bind(db);
      db.put = async (record: { source?: string }) => {
        if (record.source === 'recorded' || record.source === 'recorded-video') throw new Error('synthetic quota exceeded');
        return originalPut(record);
      };
      window.__pronoteRecording.stop();
    });

    await expect.poll(() => page.evaluate(() => window.__pronoteRecording.isActive()), { timeout: 10_000 }).toBeFalsy();
    await expect(page.locator('#emergencyRecoveryPanel button')).toHaveCount(2);
    const recoveryNames = await page.evaluate(() => (window as typeof window & {
      __pronoteEmergencyRecoveries?: Array<{ filename: string }>;
    }).__pronoteEmergencyRecoveries?.map(item => item.filename) || []);
    expect(recoveryNames).toHaveLength(2);
    expect(recoveryNames).toContain('영상 음성 동시 복구 (화면 영상).webm');
    expect(recoveryNames.some(name => /^회의_영상 음성 동시 복구_.*\.(mp3|webm|m4a)$/.test(name))).toBeTruthy();
  });

  test('진행 중 자동저장과 정지가 겹쳐도 완료 뒤 중단 초안을 남기지 않는다', async ({ page }) => {
    await installSyntheticCameraAndMicrophone(page);
    await mockBackend(page);
    await openApp(page);

    expect(await page.evaluate(() => window.__pronoteRecording.start('realtime', {
      context: 'live', meta: { title: '자동저장 경쟁 회의' }
    }))).toBeTruthy();
    await page.waitForTimeout(1200);
    await page.evaluate(() => {
      const db = window.__pronoteDB;
      const originalPut = db.put.bind(db);
      db.put = async (record: { id?: string }) => {
        if (record.id === '__draft_recording__') await new Promise(resolve => setTimeout(resolve, 500));
        return originalPut(record);
      };
      window.__pronoteRecording.saveDraftNow();
      window.__pronoteRecording.stop();
    });

    await expect.poll(() => page.evaluate(() => window.__pronoteRecording.isActive()), { timeout: 10_000 }).toBeFalsy();
    expect(await page.evaluate(async () => !!(await window.__pronoteDB.get('__draft_recording__')))).toBeFalsy();
  });

  test('60개 녹음 조각마다 중단 복구본을 저장하고 다시 열어 복구한다', async ({ page }) => {
    test.setTimeout(90_000);
    await installSyntheticCameraAndMicrophone(page);
    await mockBackend(page);
    await openApp(page);

    const started = await page.evaluate(() => window.__pronoteRecording.start('realtime', {
      context: 'live',
      recordVideo: false,
      meta: { title: 'E2E 중단 복구 회의', tag: '프로젝트', language: 'ko' }
    }));
    expect(started).toBeTruthy();

    await expect.poll(async () => page.evaluate(async () => {
      const draft = await window.__pronoteDB.get('__draft_recording__');
      return draft?.blob?.size || 0;
    }), { timeout: 70_000, intervals: [1000] }).toBeGreaterThan(0);

    await page.reload();
    await expect(page.locator('#recoverRun')).toBeVisible({ timeout: 10_000 });
    await expect(page.locator('body')).toContainText('E2E 중단 복구 회의');
    await page.evaluate(() => {
      const db = window.__pronoteDB;
      const originalPut = db.put.bind(db);
      let failOnce = true;
      db.put = async (...args: Parameters<typeof originalPut>) => {
        if (failOnce) {
          failOnce = false;
          throw new Error('E2E 저장소 오류');
        }
        return originalPut(...args);
      };
    });
    await page.locator('#recoverRun').click();
    await expect(page.locator('#recoverRun')).toBeVisible();
    await expect(page.locator('#recoverRun')).toHaveText('다시 복구');
    await page.locator('#recoverRun').click();

    await expect.poll(async () => page.evaluate(async () => {
      const records = await window.__pronoteDB.getAll();
      return {
        draftExists: records.some((record: { id?: string }) => record.id === '__draft_recording__'),
        recovered: records.find((record: { source?: string }) => record.source === 'recovered')
      };
    })).toMatchObject({
      draftExists: false,
      recovered: { source: 'recovered', isDraft: false }
    });
  });

  test('중단된 카메라 회의의 음성과 영상을 함께 복구한다', async ({ page }) => {
    await mockBackend(page);
    await openApp(page);
    await page.evaluate(async () => {
      const startedAt = Date.now() - 12_000;
      await window.__pronoteDB.put({
        id: '__draft_recording__', isDraft: true,
        blob: new Blob(['audio-draft'], { type: 'audio/webm' }),
        mimeType: 'audio/webm', filename: '(중단된 녹음) 카메라 회의',
        title: '카메라 회의', mode: 'realtime', durationSec: 12, startedAt, savedAt: Date.now()
      });
      await window.__pronoteDB.put({
        id: '__draft_video__', isDraft: true, isVideo: true,
        blob: new Blob(['video-draft'], { type: 'video/webm' }),
        mimeType: 'video/webm', filename: '(중단된 영상) 카메라 회의.webm',
        title: '카메라 회의', durationSec: 12, startedAt, savedAt: Date.now()
      });
    });

    await page.reload();
    await expect(page.locator('#recoverRun')).toBeVisible();
    await expect(page.locator('body')).toContainText('중단된 녹음과 영상');
    await page.locator('#recoverRun').click();

    await expect.poll(async () => page.evaluate(async () => {
      const records = await window.__pronoteDB.getAll();
      return {
        drafts: records.filter((record: { isDraft?: boolean }) => record.isDraft).length,
        audio: records.some((record: { source?: string }) => record.source === 'recovered'),
        video: records.some((record: { source?: string }) => record.source === 'recovered-video')
      };
    })).toEqual({ drafts: 0, audio: true, video: true });
  });

  test('이전 영상 저장이 늦어져도 다음 회의의 영상 복구본을 지우지 않는다', async ({ page }) => {
    test.setTimeout(60_000);
    await installSyntheticCameraAndMicrophone(page);
    await mockBackend(page);
    await openApp(page);

    await page.evaluate(() => {
      const db = window.__pronoteDB;
      const originalPut = db.put.bind(db);
      let releaseFinal!: () => void;
      const gate = new Promise<void>(resolve => { releaseFinal = resolve; });
      (window as typeof window & { __releaseVideoFinal?: () => void; __videoFinalWaiting?: boolean }).__releaseVideoFinal = releaseFinal;
      db.put = async (record: { source?: string }) => {
        if (record.source === 'recorded-video') {
          (window as typeof window & { __videoFinalWaiting?: boolean }).__videoFinalWaiting = true;
          await gate;
        }
        return originalPut(record);
      };
    });

    expect(await page.evaluate(() => window.__pronoteRecording.start('realtime', {
      context: 'live', recordVideo: true, meta: { title: '첫 영상 회의' }
    }))).toBeTruthy();
    await page.waitForTimeout(1200);
    await page.evaluate(() => window.__pronoteRecording.stop());
    await expect.poll(() => page.evaluate(() =>
      !!(window as typeof window & { __videoFinalWaiting?: boolean }).__videoFinalWaiting
    )).toBeTruthy();
    await expect.poll(() => page.evaluate(() => window.__pronoteRecording.isActive())).toBeFalsy();

    expect(await page.evaluate(() => window.__pronoteRecording.start('realtime', {
      context: 'live', recordVideo: true, meta: { title: '두 번째 영상 회의' }
    }))).toBeTruthy();
    await page.waitForTimeout(1200);
    await page.evaluate(async () => {
      await window.__pronoteDB.put({
        id: '__draft_video__second-session', isDraft: true, isVideo: true,
        blob: new Blob(['second-video-draft'], { type: 'video/webm' }),
        mimeType: 'video/webm', filename: '(중단된 영상) 두 번째 영상 회의.webm',
        title: '두 번째 영상 회의', durationSec: 4, startedAt: Date.now(), savedAt: Date.now()
      });
    });
    await expect.poll(() => page.evaluate(async () => {
      const all = await window.__pronoteDB.getAll();
      return all.filter((record: { id?: string }) => String(record.id || '').startsWith('__draft_video__')).length;
    })).toBe(1);

    await page.evaluate(() =>
      (window as typeof window & { __releaseVideoFinal?: () => void }).__releaseVideoFinal?.()
    );
    await page.waitForTimeout(500);
    expect(await page.evaluate(async () => {
      const all = await window.__pronoteDB.getAll();
      return all.some((record: { id?: string; title?: string }) =>
        String(record.id || '').startsWith('__draft_video__') && record.title === '두 번째 영상 회의'
      );
    })).toBeTruthy();
    await page.evaluate(() => window.__pronoteRecording.stop());
  });

  test('이전 세션 영상 자동저장이 지연돼도 새 세션 복구본을 독립 저장한다', async ({ page }) => {
    await installSyntheticCameraAndMicrophone(page);
    await mockBackend(page);
    await openApp(page);
    expect(await page.evaluate(() => window.__pronoteRecording.start('realtime', {
      context: 'live', recordVideo: false, meta: { title: '자동저장 경합 시험' }
    }))).toBeTruthy();

    await page.evaluate(async () => {
      const db = window.__pronoteDB;
      const originalPut = db.put.bind(db);
      let release!: () => void;
      const gate = new Promise<void>(resolve => { release = resolve; });
      (window as typeof window & { __releaseOldDraft?: () => void }).__releaseOldDraft = release;
      db.put = async (record: { id?: string }) => {
        if (record.id === '__draft_video__old-session') await gate;
        return originalPut(record);
      };
      void window.__pronoteRecording.saveVideoDraftNow(
        [new Blob(['old'], { type: 'video/webm' })], 'video/webm', '이전 회의', Date.now() - 5000, '__draft_video__old-session'
      );
      await window.__pronoteRecording.saveVideoDraftNow(
        [new Blob(['new'], { type: 'video/webm' })], 'video/webm', '새 회의', Date.now(), '__draft_video__new-session'
      );
    });

    expect(await page.evaluate(async () => !!(await window.__pronoteDB.get('__draft_video__new-session')))).toBeTruthy();
    await page.evaluate(() =>
      (window as typeof window & { __releaseOldDraft?: () => void }).__releaseOldDraft?.()
    );
    await expect.poll(() => page.evaluate(async () => !!(await window.__pronoteDB.get('__draft_video__old-session')))).toBeTruthy();
    await page.evaluate(() => window.__pronoteRecording.stop());
  });
});
