// AI PRONOTE service worker = 정적 자산 캐시 (offline 일부 지원)
const CACHE_NAME = 'ai-pronote-v15-pro-note-9';
const PRECACHE = [
  '/',
  '/static/manifest.webmanifest',
  '/static/icons/v15-pro-note/full-192.png',
  '/static/icons/v15-pro-note/full-512.png',
  '/static/icons/v15-pro-note/full-152.png',
  '/static/v15-ink.js?v=beta13-hotfix3',
];

self.addEventListener('install', e => {
  self.skipWaiting();
  e.waitUntil(caches.open(CACHE_NAME).then(c => c.addAll(PRECACHE).catch(() => {})));
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys => Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k))))
  );
  self.clients.claim();
});

self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);
  // /api/* = 절대 캐시 X (받아쓰기·인증 등)
  if (url.pathname.startsWith('/api/') || url.pathname.startsWith('/companion/')) return;
  if (e.request.method !== 'GET') return;
  e.respondWith(
    fetch(e.request).then(res => {
        if (res.ok && res.status === 200 && res.type === 'basic') {
          const clone = res.clone();
          caches.open(CACHE_NAME).then(c => c.put(e.request, clone)).catch(() => {});
        }
        return res;
      }).catch(() => caches.match(e.request).then(cached => cached || caches.match('/')))
  );
});
