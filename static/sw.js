// CampusScan Service Worker for mobile caching
const CACHE_NAME = 'campuss-scan-v1';

self.addEventListener('install', (event) => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('fetch', (event) => {
  // Let network requests pass through, fallback for basic static assets
  event.respondWith(
    fetch(event.request).catch(() => caches.match(event.request))
  );
});
