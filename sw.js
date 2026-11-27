// Old versions used a service worker to keep offline copies. This one only removes itself and those
// copies, so browsers that still have the old one get the newest files. Safe to delete later.
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (e) => {
  e.waitUntil(caches.keys().then((ks) => Promise.all(ks.map((k) => caches.delete(k))))
    .then(() => self.registration.unregister())
    .then(() => self.clients.matchAll({ type: "window" }))
    .then((list) => list.forEach((c) => c.navigate(c.url))));
});
