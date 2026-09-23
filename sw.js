// Every page, style, script and picture of this site comes straight from the server, never from
// the browser's cache. GitHub Pages sends a fixed 10-minute cache time we cannot change, and a
// visitor then kept seeing an old stylesheet after a fix had gone out. The whole site is well
// under a megabyte, so fetching it afresh each time costs little.
//
// Nothing is stored here and nothing is served offline: a request that fails, fails as it would
// without this worker. Other hosts (the web font) keep their own caching - they never change.
self.addEventListener("install", function () { self.skipWaiting(); });
self.addEventListener("activate", function (e) { e.waitUntil(self.clients.claim()); });

self.addEventListener("fetch", function (e) {
  var req = e.request;
  if (req.method !== "GET") return;
  var url = new URL(req.url);
  if (url.origin !== self.location.origin) return;
  // a page load must get any redirect back as a redirect, so the browser follows it itself
  var nav = req.mode === "navigate";
  e.respondWith(fetch(url.href, { cache: "no-store", credentials: "same-origin", redirect: nav ? "manual" : "follow" }));
});
