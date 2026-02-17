const CACHE = "ai-corners-pwa-v1";
const ASSETS = [
  "/",
  "/manifest.webmanifest",
  "/icon.svg"
];

// instala e cacheia o básico
self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE).then((cache) => cache.addAll(ASSETS)).then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then(keys => Promise.all(keys.map(k => (k !== CACHE ? caches.delete(k) : null))))
      .then(() => self.clients.claim())
  );
});

// Estratégia:
// - Navegação: tenta rede, se falhar usa cache (app abre offline)
// - Assets: cache-first
self.addEventListener("fetch", (event) => {
  const req = event.request;
  const url = new URL(req.url);

  // só trata o mesmo domínio
  if (url.origin !== self.location.origin) return;

  if (req.mode === "navigate") {
    event.respondWith(
      fetch(req).then(res => {
        const copy = res.clone();
        caches.open(CACHE).then(cache => cache.put("/", copy)).catch(()=>{});
        return res;
      }).catch(() => caches.match("/") )
    );
    return;
  }

  event.respondWith(
    caches.match(req).then(cached => cached || fetch(req).then(res => {
      const copy = res.clone();
      caches.open(CACHE).then(cache => cache.put(req, copy)).catch(()=>{});
      return res;
    }))
  );
});
