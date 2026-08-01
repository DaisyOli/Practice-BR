// Practice-BR Service Worker v3 — caching estratégico para PWA
//
// v3 (2026-08-01): parou de guardar HTML de página logada. A v2 gravava toda
// resposta HTML num cache com chave só de URL — sem nenhuma noção de QUEM
// estava logado. Numa queda de rede, /student_dashboard devolvia a página
// guardada da última pessoa que visitou aquela URL naquele navegador.
//
// Foi visto acontecendo: navbar da professora aparecendo sobre a dashboard de
// uma conta de aluna, no mesmo navegador. Num computador compartilhado isso é
// vazamento de dado pessoal de uma pessoa para outra.
//
// O nome do cache mudou de propósito: o handler de `activate` apaga todo cache
// com nome diferente, então subir esta versão limpa o HTML já guardado em todos
// os aparelhos que abrirem o app.
var CACHE = 'practicebr-v3';

// ── Instalação: ativa imediatamente sem esperar abas fecharem ──────────────
self.addEventListener('install', function(event) {
  self.skipWaiting();
});

// ── Ativação: apaga caches antigos e assume controle das abas abertas ──────
self.addEventListener('activate', function(event) {
  event.waitUntil(
    caches.keys().then(function(keys) {
      return Promise.all(
        keys.filter(function(k) { return k !== CACHE; })
            .map(function(k) { return caches.delete(k); })
      );
    }).then(function() { return self.clients.claim(); })
  );
});

// ── Fetch: estratégia por tipo de recurso ─────────────────────────────────
self.addEventListener('fetch', function(event) {
  var req = event.request;
  var url = new URL(req.url);

  // Ignora não-GET e requisições externas (Google Fonts, CDNs, etc.)
  if (req.method !== 'GET') return;
  if (url.origin !== self.location.origin) return;
  // Ignora o próprio SW (browser gerencia atualização)
  if (url.pathname === '/sw.js') return;

  // Cache-first: assets com fingerprint (CSS, JS, imagens em /assets/)
  // São imutáveis por definição — a URL muda quando o conteúdo muda
  if (url.pathname.startsWith('/assets/')) {
    event.respondWith(cacheFirst(req));
    return;
  }

  // Stale-while-revalidate: ícones, manifest e apple-touch-icon
  // Raramente mudam; carregar do cache e atualizar em segundo plano
  if (url.pathname.startsWith('/icons/') ||
      url.pathname === '/manifest.json' ||
      url.pathname === '/apple-touch-icon.png') {
    event.respondWith(staleWhileRevalidate(req));
    return;
  }

  // Rede sempre, sem guardar: página HTML carrega dado de UMA pessoa logada, e
  // o cache do SW não tem como saber de quem. Offline, mostra aviso — ver v3 no
  // topo do arquivo.
  if (req.headers.get('accept') && req.headers.get('accept').includes('text/html')) {
    event.respondWith(networkOnly(req));
    return;
  }
});

// ── Estratégias ───────────────────────────────────────────────────────────

function cacheFirst(req) {
  return caches.open(CACHE).then(function(cache) {
    return cache.match(req).then(function(cached) {
      if (cached) return cached;
      return fetch(req).then(function(response) {
        if (response.ok) cache.put(req, response.clone());
        return response;
      });
    });
  });
}

function staleWhileRevalidate(req) {
  return caches.open(CACHE).then(function(cache) {
    return cache.match(req).then(function(cached) {
      var fetchPromise = fetch(req).then(function(response) {
        if (response.ok) cache.put(req, response.clone());
        return response;
      });
      return cached || fetchPromise;
    });
  });
}

// Sem cache nenhum, nem de leitura nem de escrita. A versão anterior caía no
// cache quando a rede falhava — e era exatamente aí que a página de outra
// pessoa aparecia. Um aviso de offline é pior de usar e melhor de confiar.
function networkOnly(req) {
  return fetch(req).catch(function() {
    return new Response('Você está offline. Abra o app com conexão.', {
      status: 503,
      headers: { 'Content-Type': 'text/plain; charset=utf-8' }
    });
  });
}

// ── Push notifications (inalterado) ──────────────────────────────────────
self.addEventListener('push', function(event) {
  if (!event.data) return;
  var data = event.data.json();
  event.waitUntil(
    self.registration.showNotification(data.title, {
      body:    data.body,
      icon:    '/icons/android-chrome-192x192.png',
      badge:   '/icons/favicon-32x32.png',
      data:    { url: data.url || '/student_dashboard' },
      vibrate: [100, 50, 100]
    })
  );
});

self.addEventListener('notificationclick', function(event) {
  event.notification.close();
  var url = event.notification.data.url;
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function(clientList) {
      for (var i = 0; i < clientList.length; i++) {
        if (clientList[i].url === url && 'focus' in clientList[i]) return clientList[i].focus();
      }
      if (clients.openWindow) return clients.openWindow(url);
    })
  );
});
