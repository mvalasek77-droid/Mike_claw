/* Auction Baby PWA service worker — network-first for code, cache-first for images.
   This means updates are picked up automatically on every page load without
   the user needing to hard-reload. Falls back to cache when offline. */
const CACHE = "auctionbaby-v29";
const ASSETS = [
  "./", "./index.html", "./styles.css", "./app.js", "./api.js", "./config.js",
  "./manifest.webmanifest", "./icons/icon.svg", "./icons/icon-180.png",
  "./icons/icon-192.png", "./icons/icon-512.png"
];
self.addEventListener("install", e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(ASSETS)).then(() => self.skipWaiting()));
});
self.addEventListener("activate", e => {
  e.waitUntil(caches.keys().then(keys =>
    Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});

// ── Web Push ──
self.addEventListener("push", e => {
  let data = {};
  try { data = e.data ? e.data.json() : {}; } catch { data = { body: e.data && e.data.text() }; }
  const title = data.title || "Auction Baby";
  const options = {
    body: data.body || "",
    icon: "./icons/icon.svg",
    badge: "./icons/icon.svg",
    data: { url: data.url || "./index.html" + (data.hash || "") },
  };
  e.waitUntil(self.registration.showNotification(title, options));
});
self.addEventListener("notificationclick", e => {
  e.notification.close();
  const url = (e.notification.data && e.notification.data.url) || "./index.html";
  e.waitUntil(clients.matchAll({ type: "window", includeUncontrolled: true }).then(list => {
    for (const c of list) { if ("focus" in c) { c.navigate(url); return c.focus(); } }
    return clients.openWindow(url);
  }));
});

// ── Fetch strategy ──
// Network-first for code files (JS, CSS, HTML) → always get latest when online.
// Cache-first for everything else (images, manifest) → fast, no re-fetch needed.
const CODE_EXT = [".js", ".css", ".html", "/"];

self.addEventListener("fetch", e => {
  const req = e.request;
  if (req.method !== "GET") return;

  const url = new URL(req.url);
  const isCode = CODE_EXT.some(ext => url.pathname.endsWith(ext));

  if (isCode) {
    // Network-first: try network, fall back to cache, fall back to index.html
    e.respondWith(
      fetch(req).then(res => {
        // Cache the fresh copy for offline use
        const copy = res.clone();
        caches.open(CACHE).then(c => c.put(req, copy)).catch(() => {});
        return res;
      }).catch(() => caches.match(req).then(hit => hit || caches.match("./index.html")))
    );
  } else {
    // Cache-first for images, icons, manifest, etc.
    e.respondWith(
      caches.match(req).then(hit => hit || fetch(req).then(res => {
        const copy = res.clone();
        caches.open(CACHE).then(c => c.put(req, copy)).catch(() => {});
        return res;
      }).catch(() => caches.match("./index.html")))
    );
  }
});