package com.nabdh.max;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.os.IBinder;
import android.os.SystemClock;
import java.io.BufferedInputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * Multi-connection continuous downloader. Measures real bytes received, never a
 * synthesized / peak-held "real-time" rate. Cellular and server congestion
 * cannot be prevented by app code.
 */
public final class SpeedService extends Service {
    private static final String CHANNEL = "speed";
    private static final int NOTIFICATION_ID = 7;
    private static final int MAX_CONNECTIONS = 40;
    private static final int BUFFER_SIZE = 128 * 1024;
    private static final String[] ENDPOINTS = {
        "https://a205.speedtest.wobcom.de/sparsefiles/1G",
        "https://a208.speedtest.wobcom.de/sparsefiles/1G",
        "https://a209.speedtest.wobcom.de/sparsefiles/1G",
        "https://a210.speedtest.wobcom.de/sparsefiles/1G",
        "https://a400.speedtest.wobcom.de/sparsefiles/1G",
        "https://fsn1-speed.hetzner.com/1GB.bin",
        "https://nbg1-speed.hetzner.com/1GB.bin",
        "https://speed.cloudflare.com/__down?bytes=100000000"
    };
    private final AtomicBoolean running = new AtomicBoolean(false);
    private final AtomicLong total = new AtomicLong();
    private final AtomicLong window = new AtomicLong();
    private ExecutorService pool;
    private Thread ticker;
    private final AtomicInteger activeWorkers = new AtomicInteger();
    private final AtomicLong[] lanes = new AtomicLong[10];
    private volatile long sessionStartedAt;
    private volatile int targetWorkers;

    @Override public void onCreate() {
        super.onCreate();
        for (int i=0; i<lanes.length; i++) lanes[i] = new AtomicLong();
        NotificationChannel channel = new NotificationChannel(
            CHANNEL, "نبض نت: تنزيل فعلي", NotificationManager.IMPORTANCE_LOW);
        ((NotificationManager) getSystemService(NOTIFICATION_SERVICE))
            .createNotificationChannel(channel);
    }

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent != null && "STOP".equals(intent.getAction())) {
            stopMeasurement();
            stopSelf();
            return START_NOT_STICKY;
        }
        if (!running.compareAndSet(false, true)) return START_STICKY;
        String mode = intent == null ? "ultra" : intent.getStringExtra("mode");
        if ("normal".equals(mode)) targetWorkers = 8;
        else if ("strong".equals(mode)) targetWorkers = 16;
        else targetWorkers = MAX_CONNECTIONS;

        total.set(0L);
        window.set(0L);
        activeWorkers.set(0);
        for(AtomicLong lane:lanes) lane.set(0);
        sessionStartedAt = SystemClock.elapsedRealtime();
        startForeground(NOTIFICATION_ID, notification("جاري تشغيل " + targetWorkers + " اتصال تنزيل..."));
        pool = Executors.newFixedThreadPool(targetWorkers);
        final int n = targetWorkers;
        for (int i = 0; i < n; i++) {
            final int id = i;
            pool.execute(() -> downloadLoop(id));
        }
        ticker = new Thread(this::publishSpeed, "nabdh-speed-meter");
        ticker.start();
        return START_STICKY;
    }

    private void downloadLoop(int id) {
        int failures = 0;
        int index = id % ENDPOINTS.length;
        byte[] buffer = new byte[BUFFER_SIZE];
        while (running.get() && !Thread.currentThread().isInterrupted()) {
            HttpURLConnection conn = null;
            boolean counted = false;
            try {
                String location = ENDPOINTS[index];
                // A query nonce only on the Cloudflare endpoint prevents HTTP caches.
                if (location.contains("cloudflare.com"))
                    location += "&nonce=" + System.nanoTime();
                conn = (HttpURLConnection) new URL(location).openConnection();
                conn.setConnectTimeout(6500);
                conn.setReadTimeout(8000);
                conn.setUseCaches(false);
                conn.setRequestProperty("Accept-Encoding", "identity");
                conn.setRequestProperty("Cache-Control", "no-store");
                conn.setRequestProperty("Connection", "keep-alive");
                int code = conn.getResponseCode();
                if (code < 200 || code >= 300)
                    throw new java.io.IOException("HTTP " + code);
                activeWorkers.incrementAndGet();
                counted = true;
                try (InputStream stream = new BufferedInputStream(conn.getInputStream(), BUFFER_SIZE)) {
                    int count;
                    while (running.get() && !Thread.currentThread().isInterrupted()
                            && (count = stream.read(buffer)) != -1) {
                        if (count <= 0) continue;
                        total.addAndGet(count);
                        window.addAndGet(count);
                        lanes[id % lanes.length].addAndGet(count);
                    }
                }
                failures = 0;
                // Reconnect immediately when a large test object naturally ends.
            } catch (Exception error) {
                failures++;
                index = (index + 1) % ENDPOINTS.length;
                if (!running.get()) break;
                try {
                    Thread.sleep(Math.min(3500L, 350L * failures));
                } catch (InterruptedException interrupted) {
                    Thread.currentThread().interrupt();
                }
            } finally {
                if (counted) activeWorkers.decrementAndGet();
                if (conn != null) conn.disconnect();
            }
        }
    }

    private void publishSpeed() {
        long previous = SystemClock.elapsedRealtime();
        long rollingBytes = 0;
        long[] recent = new long[4];
        int next = 0;
        while (running.get() && !Thread.currentThread().isInterrupted()) {
            try { Thread.sleep(1000L); }
            catch (InterruptedException e) { Thread.currentThread().interrupt(); break; }
            long now = SystemClock.elapsedRealtime();
            long duration = now - previous;
            previous = now;
            if (duration < 100) continue;
            long bytes = window.getAndSet(0L);
            rollingBytes += bytes - recent[next];
            recent[next] = bytes;
            next = (next + 1) % recent.length;
            double currentMbps = bytes * 8000.0 / duration / 1000000.0;
            double smoothMbps = rollingBytes * 8.0 / 4.0 / 1000000.0;
            long consumed = total.get();
            String report = String.format(Locale.US,
                "%.1f Mbps (4s %.1f) • %.1f MB • %d/%d",
                currentMbps, smoothMbps, consumed / 1000000.0,
                activeWorkers.get(), targetWorkers);
            ((NotificationManager) getSystemService(NOTIFICATION_SERVICE))
                .notify(NOTIFICATION_ID, notification(report));
            getSharedPreferences("nabdh_speed_stats", MODE_PRIVATE).edit()
                .putFloat("instant_mbps", (float) currentMbps)
                .putFloat("rolling_mbps", (float) smoothMbps)
                .putLong("total_bytes", consumed)
                .putInt("active_connections", activeWorkers.get())
                .putLong("window_bytes",bytes)
                .putLong("window_ms",duration)
                .putLong("elapsed_ms",now-sessionStartedAt)
                .putBoolean("is_running",true)
                .apply();
            android.content.SharedPreferences.Editor counters = getSharedPreferences("nabdh_speed_stats", MODE_PRIVATE).edit();
            for(int i=0;i<lanes.length;i++) counters.putLong("lane_"+i,lanes[i].get());
            counters.apply();
        }
    }

    private Notification notification(String message) {
        Intent stop = new Intent(this, SpeedService.class);
        stop.setAction("STOP");
        PendingIntent stopAction = PendingIntent.getService(
            this, 1, stop, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        return new Notification.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle("نبض نت • تنزيل متوازٍ فعلي")
            .setContentText(message)
            .setOngoing(true)
            .addAction(new Notification.Action.Builder(
                android.R.drawable.ic_media_pause, "إيقاف", stopAction).build())
            .build();
    }

    private void stopMeasurement() {
        if (!running.getAndSet(false)) return;
        getSharedPreferences("nabdh_speed_stats",MODE_PRIVATE).edit().putBoolean("is_running",false).apply();
        if (ticker != null) ticker.interrupt();
        if (pool != null) pool.shutdownNow();
        stopForeground(STOP_FOREGROUND_REMOVE);
    }

    @Override public void onDestroy() {
        stopMeasurement();
        super.onDestroy();
    }
    @Override public IBinder onBind(Intent intent) { return null; }
}
