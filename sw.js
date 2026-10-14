

self.addEventListener("install", function () { self.skipWaiting(); });
self.addEventListener("activate", function (e) { e.waitUntil(self.clients.claim()); });

self.addEventListener("fetch", function (e) {
  var req = e.request;
  if (req.method !== "GET") return;
  var url = new URL(req.url);
  if (url.origin !== self.location.origin) return;

  if (/\/play\/seibucup\.(wasm|js)$/.test(url.pathname)) return;

  var nav = req.mode === "navigate";
  e.respondWith(fetch(url.href, { cache: "no-store", credentials: "same-origin", redirect: nav ? "manual" : "follow" }));
});
