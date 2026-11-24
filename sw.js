// =============================================================================
// SERVICE WORKER - CỔNG ĐIỀU HÀNH THPT CHI LĂNG (PWA STANDALONE APP)
// Giúp Chrome trên Android, iOS Safari và Desktop kích hoạt tính năng
// "Cài đặt ứng dụng" (Install App / WebAPK) thay vì chỉ tạo lối tắt.
// =============================================================================

const CACHE_NAME = 'thpt-chilang-pwa-v5';
const DEFAULT_ICON = './Logocl.png';
const BADGE_ICON = './icon-192.png';

self.addEventListener('install', (event) => {
    self.skipWaiting();
    event.waitUntil(
        caches.open(CACHE_NAME).then((cache) => {
            return cache.addAll([
                './',
                './index.html',
                './manifest.json',
                './Logocl.png',
                './icon-192.png',
                './icon-512.png'
            ]).catch(() => {});
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

// Xử lý nhận Web Push Notifications & Tin nhắn kích hoạt Popup hệ thống từ ứng dụng
self.addEventListener('push', (event) => {
    let data = {
        title: 'Cổng Điều Hành THPT Chi Lăng',
        body: 'Bạn có thông báo điều hành mới từ nhà trường.',
        type: 'announcement',
        refId: null,
        badgeCount: 1
    };
    try {
        if (event.data) {
            data = Object.assign(data, event.data.json());
        }
    } catch (_) {}

    if (self.navigator && self.navigator.setAppBadge && data.badgeCount) {
        try { self.navigator.setAppBadge(Number(data.badgeCount) || 1); } catch (_) {}
    }

    event.waitUntil(
        self.registration.showNotification(data.title || 'THPT Chi Lăng', {
            body: data.body || '',
            icon: DEFAULT_ICON,
            badge: BADGE_ICON,
            vibrate: [180, 80, 220],
            renotify: true,
            tag: 'chilang-push-' + (data.refId || Date.now()),
            actions: [
                { action: 'open', title: '👁️ Xem ngay' },
                { action: 'dismiss', title: 'Đóng' }
            ],
            data: data
        })
    );
});

self.addEventListener('notificationclick', (event) => {
    const notifData = event.notification.data || {};
    event.notification.close();
    if (event.action === 'dismiss') {
        return;
    }
    event.waitUntil(
        self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
            for (const client of clientList) {
                if ('focus' in client) {
                    client.focus();
                    client.postMessage({
                        type: 'OPEN_NOTIFICATION_TARGET',
                        targetType: notifData.type || 'announcement',
                        refId: notifData.refId || null
                    });
                    return;
                }
            }
            return self.clients.openWindow('./index.html');
        })
    );
});
