package org.surface.hardwarecontrol;

import android.content.Context;
import android.media.AudioManager;
import android.provider.Settings;

/** Android-side settings used by the bidirectional host synchronizer. */
final class AndroidSettings {
    private AndroidSettings() {}

    static int musicVolumePercent(Context context) {
        AudioManager audio = (AudioManager) context.getSystemService(Context.AUDIO_SERVICE);
        if (audio == null) return 0;
        int max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC);
        if (max <= 0) return 0;
        return audio.getStreamVolume(AudioManager.STREAM_MUSIC) * 100 / max;
    }

    static void setMusicVolumePercent(Context context, int percent) {
        AudioManager audio = (AudioManager) context.getSystemService(Context.AUDIO_SERVICE);
        if (audio == null) return;
        int max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC);
        int value = Math.max(0, Math.min(100, percent)) * max / 100;
        audio.setStreamVolume(AudioManager.STREAM_MUSIC, value, 0);
    }

    static int brightness(Context context) {
        try {
            return Settings.System.getInt(context.getContentResolver(), Settings.System.SCREEN_BRIGHTNESS);
        } catch (Settings.SettingNotFoundException error) {
            return 50;
        }
    }

    static boolean setBrightness(Context context, int percent) {
        if (!Settings.System.canWrite(context)) return false;
        int value = Math.max(0, Math.min(100, percent)) * 255 / 100;
        return Settings.System.putInt(context.getContentResolver(), Settings.System.SCREEN_BRIGHTNESS, value);
    }

    static int brightnessPercent(Context context) {
        return Math.max(0, Math.min(100, brightness(context) * 100 / 255));
    }

    static boolean canWriteSecure(Context context) {
        try {
            Settings.Global.putInt(context.getContentResolver(), "surface_controls_probe", 1);
            return true;
        } catch (SecurityException error) {
            return false;
        }
    }

    static int wifiEnabled(Context context) {
        return Settings.Global.getInt(context.getContentResolver(), "wifi_on", 0);
    }

    static int bluetoothEnabled(Context context) {
        return Settings.Global.getInt(context.getContentResolver(), "bluetooth_on", 0);
    }

    static boolean setWifiEnabled(Context context, boolean enabled) {
        try {
            return Settings.Global.putInt(context.getContentResolver(), "wifi_on", enabled ? 1 : 0);
        } catch (SecurityException error) {
            return false;
        }
    }

    static boolean setBluetoothEnabled(Context context, boolean enabled) {
        try {
            return Settings.Global.putInt(context.getContentResolver(), "bluetooth_on", enabled ? 1 : 0);
        } catch (SecurityException error) {
            return false;
        }
    }
}
