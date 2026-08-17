/* Auction Baby PWA service worker — cache-first shell so it installs and works offline. */
const CACHE = "auctionbaby-v4";
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

self.addEventListener("fetch", e => {
  const req = e.request;
  if (req.method !== "GET") return;
  e.respondWith(
    caches.match(req).then(hit => hit || fetch(req).then(res => {
      const copy = res.clone();
      caches.open(CACHE).then(c => c.put(req, copy)).catch(() => {});
      return res;
    }).catch(() => caches.match("./index.html")))
  );
});
