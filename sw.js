// =============================================================================
// SERVICE WORKER - CỔNG ĐIỀU HÀNH THPT CHI LĂNG (PWA STANDALONE APP)
// Giúp Chrome trên Android, iOS Safari và Desktop kích hoạt tính năng
// "Cài đặt ứng dụng" (Install App / WebAPK) thay vì chỉ tạo lối tắt.
// =============================================================================

const CACHE_NAME = 'thpt-chilang-pwa-v2';
const DEFAULT_ICON = 'https://raw.githubusercontent.com/truongthptchilang/tasks/main/Logocl.png';

self.addEventListener('install', (event) => {
    self.skipWaiting();
    event.waitUntil(
        caches.open(CACHE_NAME).then((cache) => {
            return cache.addAll(['./', './index.html', './manifest.json']).catch(() => {});
        })
    );
});

self.addEventListener('activate', (event) => {
    event.waitUntil(
        Promise.all([
            self.clients.claim(),
            caches.keys().then((keys) =>
                Promise.all(
                    keys.map((key) => {
                        if (key !== CACHE_NAME) {
                            return caches.delete(key);
                        }
                    })
                )
            )
        ])
    );
});

// BẮT BUỘC PHẢI CÓ FETCH HANDLER ĐỂ CHROME TRÊN ANDROID CHO PHÉP "CÀI ĐẶT ỨNG DỤNG" (WebAPK)
self.addEventListener('fetch', (event) => {
    const req = event.request;
    if (req.method !== 'GET') return;

    // Không cache các request gọi API Supabase để dữ liệu luôn realtime
    if (req.url.includes('supabase.co')) {
        return;
    }

    event.respondWith(
        fetch(req)
            .then((networkRes) => {
                return networkRes;
            })
            .catch(() => {
                return caches.match(req).then((cachedRes) => {
                    return cachedRes || caches.match('./index.html');
                });
            })
    );
});

// Xử lý nhận Web Push Notifications
self.addEventListener('push', (event) => {
    let data = {
        title: 'Cổng Điều Hành THPT Chi Lăng',
        body: 'Bạn có thông báo điều hành mới từ nhà trường.'
    };
    try {
        if (event.data) {
            data = event.data.json();
        }
    } catch (_) {}

    event.waitUntil(
        self.registration.showNotification(data.title || 'THPT Chi Lăng', {
            body: data.body || '',
            icon: DEFAULT_ICON,
            badge: DEFAULT_ICON,
            data: data
        })
    );
});

self.addEventListener('notificationclick', (event) => {
    event.notification.close();
    event.waitUntil(
        self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
            if (clientList.length > 0) {
                return clientList[0].focus();
            }
            return self.clients.openWindow('./');
        })
    );
});
