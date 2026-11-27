/* ═══════════════════════════════════════════
   Service Worker — مركز الكتاب للتحفيظ
   يحفظ الملفات محلياً للعمل بدون إنترنت
═══════════════════════════════════════════ */

const CACHE_NAME = 'markaz-alkitab-v2-3-3';

/* ملفات التطبيق الأساسية (تُحفظ كلها عند التثبيت، والمكتبات محلية فتعمل بلا إنترنت) */
const CORE = [
  './',
  './index.html',
  './competition.js?v=2.3.3',
  './manifest.json',
  './icon-192.png',
  './icon-512.png',
  './apple-touch-icon.png',
  './vendor/jszip.min.js',
  './vendor/chart.umd.min.js',
  './vendor/sbclient.umd.js'
];

/* اختياري: خط IBM Plex (إن فشل تحميله لا يفشل التثبيت) */
const FONT_CSS = 'https://fonts.googleapis.com/css2?family=IBM+Plex+Sans+Arabic:wght@300;400;500;600;700;800&display=swap';

/* أقصى انتظار للشبكة قبل الرجوع للنسخة المحفوظة (يمنع التعليق عند ضعف الإنترنت) */
const NET_TIMEOUT = 3500;

/* ── تثبيت: كل ملف يُحفظ على حدة، ويفشل التثبيت فقط إن غابت الصفحة الرئيسية ── */
self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);
    await Promise.all(CORE.map(u => cache.add(u).catch(() => {})));
    await cache.add(FONT_CSS).catch(() => {});
    if (!(await cache.match('./index.html'))) throw new Error('index.html not cached');
  })());
  self.skipWaiting();
});

/* ── تفعيل: حذف الكاش القديم ── */
self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k)))
    )
  );
  self.clients.claim();
});

/* ── الشبكة أولاً (لتصل الإصلاحات مباشرة) بمهلة قصيرة ثم النسخة المحفوظة ── */
async function networkFirst(req) {
  const cache = await caches.open(CACHE_NAME);
  const fromCache = async () =>
    (await cache.match(req)) || (await cache.match(req, { ignoreSearch: true }));

  /* بلا اتصال أصلاً: النسخة المحفوظة فوراً بدون انتظار */
  if (self.navigator && self.navigator.onLine === false) {
    const c = await fromCache();
    if (c) return c;
  }

  const net = fetch(req).then(res => {
    if (res && res.ok && !res.redirected) cache.put(req, res.clone()).catch(() => {});
    return res;
  });
  net.catch(() => {}); /* لا نترك رفضاً غير معالَج إن فاز الكاش بالسباق */

  try {
    return await Promise.race([
      net,
      new Promise((_, rej) => setTimeout(() => rej(new Error('timeout')), NET_TIMEOUT))
    ]);
  } catch (e) {
    const c = await fromCache();
    if (c) return c;
    if (req.mode === 'navigate' || (req.headers.get('accept') || '').includes('text/html')) {
      const shell = (await cache.match('./index.html')) || (await cache.match('./'));
      if (shell) return shell;
    }
    return Response.error();
  }
}

/* ── الكاش أولاً: للمكتبات المحلية (ثابتة لا تتغير) وللخطوط ── */
async function cacheFirst(req, allowOpaque) {
  const cache = await caches.open(CACHE_NAME);
  const hit = await cache.match(req, { ignoreVary: true });
  if (hit) return hit;
  const res = await fetch(req);
  if (res && (res.ok || (allowOpaque && res.type === 'opaque'))) cache.put(req, res.clone()).catch(() => {});
  return res;
}

self.addEventListener('fetch', event => {
  const req = event.request;
  if (req.method !== 'GET') return;
  if (!req.url.startsWith('http')) return;

  const url = new URL(req.url);

  /* طلبات سيرفر Supabase لا تمر بالكاش */
  if (url.hostname.endsWith('.supabase.co') || url.hostname.endsWith('.supabase.in')) return;

  /* الخطوط: الكاش أولاً */
  if (url.hostname === 'fonts.googleapis.com' || url.hostname === 'fonts.gstatic.com') {
    event.respondWith(cacheFirst(req, true));
    return;
  }

  /* أي موقع آخر: المتصفح يتصرف كالمعتاد */
  if (url.origin !== self.location.origin) return;

  /* المكتبات المحلية: الكاش أولاً */
  if (url.pathname.includes('/vendor/')) {
    event.respondWith(cacheFirst(req, false));
    return;
  }

  event.respondWith(networkFirst(req));
});
