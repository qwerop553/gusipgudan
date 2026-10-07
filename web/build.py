"""web/app.html -> docs/ (GitHub Pages용 PWA). 실행: python3 web/build.py"""
import pathlib, hashlib

root = pathlib.Path(__file__).resolve().parent.parent
app = (root / "web/app.html").read_text(encoding="utf-8")
docs = root / "docs"
docs.mkdir(exist_ok=True)

head = """<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover, user-scalable=no">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="default">
<meta name="apple-mobile-web-app-title" content="99단">
<meta name="theme-color" content="#F3F5F4" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#0F1417" media="(prefers-color-scheme: dark)">
<link rel="manifest" href="manifest.webmanifest">
<link rel="apple-touch-icon" href="apple-touch-icon.png">
<link rel="icon" href="icon-192.png">
<style>:root{padding-block:env(safe-area-inset-top,0px) env(safe-area-inset-bottom,0px)}</style>
</head>
<body>
"""
(docs / "index.html").write_text(head + app + "\n</body>\n</html>\n", encoding="utf-8")

(docs / "manifest.webmanifest").write_text("""{
  "name": "99단 연습장",
  "short_name": "99단",
  "start_url": "./",
  "scope": "./",
  "display": "standalone",
  "background_color": "#F3F5F4",
  "theme_color": "#0E6E66",
  "icons": [
    { "src": "icon-192.png", "sizes": "192x192", "type": "image/png" },
    { "src": "icon-512.png", "sizes": "512x512", "type": "image/png" }
  ]
}
""", encoding="utf-8")

# 앱이 바뀔 때마다 캐시 이름이 바뀌어 새 버전이 받아지도록
version = hashlib.sha1(app.encode()).hexdigest()[:10]
(docs / "sw.js").write_text(f"""const CACHE = '99dan-{version}';
const FILES = ['./', 'index.html', 'manifest.webmanifest', 'icon-192.png', 'icon-512.png', 'apple-touch-icon.png'];
self.addEventListener('install', e => {{
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(FILES)).then(() => self.skipWaiting()));
}});
self.addEventListener('activate', e => {{
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim()));
}});
// 앱 파일: 네트워크 우선, 오프라인이면 캐시. 글꼴: 캐시 우선.
self.addEventListener('fetch', e => {{
  const url = new URL(e.request.url);
  if (e.request.method !== 'GET') return;
  if (url.origin === location.origin) {{
    e.respondWith(fetch(e.request).then(r => {{
      const copy = r.clone(); caches.open(CACHE).then(c => c.put(e.request, copy)); return r;
    }}).catch(() => caches.match(e.request).then(r => r || caches.match('index.html'))));
  }} else if (/fonts\\.(googleapis|gstatic)\\.com$/.test(url.hostname)) {{
    e.respondWith(caches.match(e.request).then(hit => hit || fetch(e.request).then(r => {{
      const copy = r.clone(); caches.open(CACHE).then(c => c.put(e.request, copy)); return r;
    }})));
  }}
}});
""", encoding="utf-8")
print("built docs/ version", version)
