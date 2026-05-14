/* ═══════════════════════════════════════════
   Service Worker — مركز الكتاب للتحفيظ
   يحفظ الملفات محلياً للعمل بدون إنترنت
═══════════════════════════════════════════ */

const CACHE_NAME = 'markaz-alkitab-v2';

const ASSETS = [
  './',
  './index.html',
  './manifest.json',
  './icon-192.png',
  './icon-512.png',
  'https://fonts.googleapis.com/css2?family=IBM+Plex+Sans+Arabic:wght@300;400;500;600;700;800&display=swap'
];

/* ── تثبيت: تحميل الملفات في الكاش ── */
self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME).then(cache => {
      return cache.addAll(ASSETS).catch(() => {
        // تجاهل أخطاء الفونت إن لم يكن هناك إنترنت
        return cache.addAll(['./', './index.html', './manifest.json']);
      });
    })
  );
  self.skipWaiting();
});

/* ── تفعيل: حذف الكاش القديم ── */
self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys =>
      Promise.all(
        keys
          .filter(k => k !== CACHE_NAME)
          .map(k => caches.delete(k))
      )
    )
  );
  self.clients.claim();
});

/* ── طلبات الشبكة: الشبكة أولاً حتى تصل إصلاحات التطبيق مباشرة ── */
self.addEventListener('fetch', event => {
  // تجاهل طلبات POST وغير http
  if (event.request.method !== 'GET') return;
  if (!event.request.url.startsWith('http')) return;
  if (event.request.url.includes('supabase')) return;

  event.respondWith(
    fetch(event.request)
        .then(response => {
          // حفظ نسخة في الكاش (الملفات المحلية فقط)
          if (
            response.ok &&
            event.request.url.includes(self.location.origin)
          ) {
            const clone = response.clone();
            caches.open(CACHE_NAME).then(c => c.put(event.request, clone));
          }
          return response;
        })
        .catch(() =>
          caches.match(event.request).then(cached => {
            if (cached) return cached;
            // إذا فشل الإنترنت → أرجع index.html
            if (event.request.headers.get('accept')?.includes('text/html')) {
              return caches.match('./index.html');
            }
            return Response.error();
          })
        )
  );
});
