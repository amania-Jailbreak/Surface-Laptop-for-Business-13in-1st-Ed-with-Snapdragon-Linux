package org.surface.hardwarecontrol;

import android.app.Service;
import android.content.Intent;
import android.database.ContentObserver;
import android.os.Handler;
import android.os.IBinder;
import android.provider.Settings;

import org.json.JSONObject;

/** Keeps Android media/backlight settings and the Linux host in sync. */
public final class SyncService extends Service {
    private final Handler handler = new Handler();
    private ContentObserver settingsObserver;
    private boolean applyingHost;
    private boolean radioObserverReady;

    private final Runnable poll = new Runnable() {
        public void run() {
            syncHostToAndroid();
            handler.postDelayed(this, 2000);
        }
    };

    @Override
    public void onCreate() {
        super.onCreate();
        settingsObserver = new ContentObserver(handler) {
            @Override
            public void onChange(boolean selfChange) {
                if (!applyingHost) syncAndroidToHost();
            }
        };
        getContentResolver().registerContentObserver(
                Settings.System.getUriFor("volume_music"), false, settingsObserver);
        getContentResolver().registerContentObserver(
                Settings.System.getUriFor(Settings.System.SCREEN_BRIGHTNESS), false, settingsObserver);
        getContentResolver().registerContentObserver(
                Settings.Global.getUriFor("wifi_on"), false, settingsObserver);
        getContentResolver().registerContentObserver(
                Settings.Global.getUriFor("bluetooth_on"), false, settingsObserver);
        handler.post(poll);
        handler.postDelayed(new Runnable() {
            public void run() { radioObserverReady = true; }
        }, 5000);
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        if (settingsObserver != null) getContentResolver().unregisterContentObserver(settingsObserver);
        handler.removeCallbacksAndMessages(null);
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) { return null; }

    private void syncAndroidToHost() {
        HostControlClient.request("volume.set", json("value", AndroidSettings.musicVolumePercent(this) / 100.0), null);
        HostControlClient.request("brightness.set", json("value", AndroidSettings.brightnessPercent(this)), null);
        if (radioObserverReady) {
            HostControlClient.request("wifi.radio", null, new HostControlClient.Callback() {
                public void done(JSONObject reply) {
                    boolean hostEnabled = reply.optBoolean("enabled", false);
                    boolean androidEnabled = AndroidSettings.wifiEnabled(SyncService.this) != 0;
                    if (hostEnabled != androidEnabled) HostControlClient.request("wifi.toggle", null, null);
                }
            });
            HostControlClient.request("bluetooth.status", null, new HostControlClient.Callback() {
                public void done(JSONObject reply) {
                    boolean hostEnabled = reply.optBoolean("powered", false);
                    boolean androidEnabled = AndroidSettings.bluetoothEnabled(SyncService.this) != 0;
                    if (hostEnabled != androidEnabled) HostControlClient.request("bluetooth.power", json("value", androidEnabled ? "on" : "off"), null);
                }
            });
        }
    }

    private void syncHostToAndroid() {
        HostControlClient.request("volume.get", null, new HostControlClient.Callback() {
            public void done(JSONObject reply) {
                double value = reply.optDouble("value", -1);
                if (value < 0) return;
                int percent = Math.max(0, Math.min(100, (int) Math.round(value * 100)));
                int current = AndroidSettings.musicVolumePercent(SyncService.this);
                if (Math.abs(current - percent) > 2) {
                    applyingHost = true;
                    AndroidSettings.setMusicVolumePercent(SyncService.this, percent);
                    applyingHost = false;
                }
            }
        });
        HostControlClient.request("brightness.get", null, new HostControlClient.Callback() {
            public void done(JSONObject reply) {
                int value = reply.optInt("value", -1);
                if (value < 0 || !android.provider.Settings.System.canWrite(SyncService.this)) return;
                int current = AndroidSettings.brightnessPercent(SyncService.this);
                if (Math.abs(current - value) > 2) {
                    applyingHost = true;
                    AndroidSettings.setBrightness(SyncService.this, value);
                    applyingHost = false;
                }
            }
        });
        HostControlClient.request("wifi.radio", null, new HostControlClient.Callback() {
            public void done(JSONObject reply) {
                if (!radioObserverReady || !AndroidSettings.canWriteSecure(SyncService.this)) return;
                boolean enabled = reply.optBoolean("enabled", false);
                if ((AndroidSettings.wifiEnabled(SyncService.this) != 0) != enabled) {
                    applyingHost = true;
                    AndroidSettings.setWifiEnabled(SyncService.this, enabled);
                    applyingHost = false;
                }
            }
        });
        HostControlClient.request("bluetooth.status", null, new HostControlClient.Callback() {
            public void done(JSONObject reply) {
                if (!radioObserverReady || !AndroidSettings.canWriteSecure(SyncService.this)) return;
                boolean enabled = reply.optBoolean("powered", false);
                if ((AndroidSettings.bluetoothEnabled(SyncService.this) != 0) != enabled) {
                    applyingHost = true;
                    AndroidSettings.setBluetoothEnabled(SyncService.this, enabled);
                    applyingHost = false;
                }
            }
        });
    }

    private JSONObject json(Object... values) {
        JSONObject result = new JSONObject();
        try {
            for (int i = 0; i < values.length; i += 2) result.put((String) values[i], values[i + 1]);
        } catch (Exception ignored) {}
        return result;
    }
}
