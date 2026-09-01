package org.surface.hardwarecontrol;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Bundle;
import android.text.InputType;
import android.view.View;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.CompoundButton;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.SeekBar;
import android.widget.TextView;

import org.json.JSONArray;
import org.json.JSONObject;

/** Host hardware controls. Linux remains the owner of the physical devices. */
public final class MainActivity extends Activity {
    private TextView status;
    private SeekBar volume;
    private SeekBar brightness;
    private CheckBox mute;
    private EditText ssid;
    private EditText wifiPassword;
    private EditText bluetoothAddress;
    private LinearLayout wifiDevices;
    private LinearLayout bluetoothDevices;
    private LinearLayout audioSinks;

    @Override
    public void onCreate(Bundle state) {
        super.onCreate(state);
        setTitle("Surface Controls");
        setContentView(buildUi());
        startService(new Intent(this, SyncService.class));
        refreshAll();
    }

    private View buildUi() {
        ScrollView scroll = new ScrollView(this);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(28, 20, 28, 28);
        root.setBackgroundColor(Color.rgb(250, 247, 252));
        scroll.addView(root);

        TextView title = text("Surface Controls", 28, true);
        title.setTextColor(Color.rgb(43, 34, 49));
        root.addView(title);
        status = text("Linuxホストへ接続中…", 14, false);
        status.setTextColor(Color.DKGRAY);
        root.addView(status);

        LinearLayout audio = section(root, "音量と明るさ");
        audio.addView(text("音量", 18, true));
        volume = new SeekBar(this);
        volume.setMax(150);
        volume.setProgress(70);
        audio.addView(volume);
        mute = new CheckBox(this);
        mute.setText("ミュート");
        audio.addView(mute);
        volume.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            public void onProgressChanged(SeekBar bar, int value, boolean fromUser) {
                if (fromUser) {
                    AndroidSettings.setMusicVolumePercent(MainActivity.this, value * 100 / 150);
                    request("volume.set", json("value", value / 100.0), null);
                }
            }
            public void onStartTrackingTouch(SeekBar bar) {}
            public void onStopTrackingTouch(SeekBar bar) {}
        });
        mute.setOnCheckedChangeListener(new CompoundButton.OnCheckedChangeListener() {
            public void onCheckedChanged(CompoundButton button, boolean checked) {
                if (button.isPressed()) request("volume.mute", json("value", checked ? 1 : 0), null);
            }
        });

        audio.addView(text("画面の明るさ", 18, true));
        brightness = new SeekBar(this);
        brightness.setMax(100);
        brightness.setProgress(50);
        audio.addView(brightness);
        brightness.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            public void onProgressChanged(SeekBar bar, int value, boolean fromUser) {
                if (fromUser) {
                    AndroidSettings.setBrightness(MainActivity.this, value);
                    request("brightness.set", json("value", value), null);
                }
            }
            public void onStartTrackingTouch(SeekBar bar) {}
            public void onStopTrackingTouch(SeekBar bar) {}
        });

        LinearLayout wifi = section(root, "Wi‑Fi");
        ssid = edit("ネットワーク名 (SSID)");
        wifiPassword = edit("パスワード");
        wifi.addView(ssid);
        wifi.addView(wifiPassword);
        wifi.addView(rowButtons(
                button("状態", new View.OnClickListener() {
                    public void onClick(View view) { request("wifi.status", null, null); }
                }),
                button("ネットワークを検索", new View.OnClickListener() {
                    public void onClick(View view) { scanWifi(); }
                }),
                button("接続", new View.OnClickListener() {
                    public void onClick(View view) { connectWifi(); }
                }),
                button("切断", new View.OnClickListener() {
                    public void onClick(View view) { request("wifi.disconnect", null, null); }
                })
        ));
        wifiDevices = listBox();
        wifi.addView(wifiDevices);

        LinearLayout bluetooth = section(root, "Bluetooth");
        bluetoothAddress = edit("デバイスアドレス (AA:BB:CC:DD:EE:FF)");
        bluetooth.addView(bluetoothAddress);
        bluetooth.addView(rowButtons(
                button("状態", new View.OnClickListener() {
                    public void onClick(View view) { request("bluetooth.status", null, null); }
                }),
                button("デバイスを検索", new View.OnClickListener() {
                    public void onClick(View view) { scanBluetooth(); }
                }),
                button("ペアリング", new View.OnClickListener() {
                    public void onClick(View view) { request("bluetooth.pair", json("address", bluetoothAddress.getText().toString()), null); }
                }),
                button("接続", new View.OnClickListener() {
                    public void onClick(View view) { request("bluetooth.connect", json("address", bluetoothAddress.getText().toString()), null); }
                }),
                button("切断", new View.OnClickListener() {
                    public void onClick(View view) { request("bluetooth.disconnect", json("address", bluetoothAddress.getText().toString()), null); }
                })
        ));
        bluetoothDevices = listBox();
        bluetooth.addView(bluetoothDevices);

        LinearLayout outputs = section(root, "音声出力先");
        outputs.addView(text("Linux側で選択した出力先へAndroidの音声を送ります。", 14, false));
        outputs.addView(button("出力先を更新", new View.OnClickListener() {
            public void onClick(View view) { refreshAudioSinks(); }
        }));
        audioSinks = listBox();
        outputs.addView(audioSinks);

        root.addView(text("SystemUIのクイック設定にSurface Controls / Wi‑Fi / Bluetooth / 明るさのタイルを追加できます。", 13, false));
        return scroll;
    }

    private void refreshAll() {
        request("ping", null, null);
        request("volume.get", null, new HostControlClient.Callback() {
            public void done(JSONObject reply) { updateVolume(reply); }
        });
        request("brightness.get", null, new HostControlClient.Callback() {
            public void done(JSONObject reply) { updateBrightness(reply); }
        });
        request("wifi.list", null, new HostControlClient.Callback() {
            public void done(JSONObject reply) { renderWifi(reply); }
        });
        request("bluetooth.devices", null, new HostControlClient.Callback() {
            public void done(JSONObject reply) { renderBluetooth(reply); }
        });
        refreshAudioSinks();
    }

    private void scanWifi() {
        request("wifi.scan", null, new HostControlClient.Callback() {
            public void done(JSONObject reply) { renderWifi(reply); }
        });
    }

    private void scanBluetooth() {
        request("bluetooth.scan", null, new HostControlClient.Callback() {
            public void done(JSONObject reply) { renderBluetooth(reply); }
        });
    }

    private void refreshAudioSinks() {
        request("audio.sinks", null, new HostControlClient.Callback() {
            public void done(JSONObject reply) { renderAudioSinks(reply); }
        });
    }

    private void connectWifi() {
        request("wifi.connect", json(
                "ssid", HostControlClient.encoded(ssid.getText().toString()),
                "password", HostControlClient.encoded(wifiPassword.getText().toString())), null);
    }

    private void updateVolume(JSONObject reply) {
        try {
            double value = reply.optDouble("value", -1);
            if (value >= 0 && volume != null) volume.setProgress((int) Math.round(value * 100));
            mute.setChecked(reply.optBoolean("muted", false));
        } catch (Exception error) {
            setStatus(error.toString());
        }
    }

    private void updateBrightness(JSONObject reply) {
        int value = reply.optInt("value", -1);
        if (value >= 0 && brightness != null) brightness.setProgress(value);
    }

    private void renderWifi(JSONObject reply) {
        if (wifiDevices == null) return;
        wifiDevices.removeAllViews();
        JSONArray networks = reply.optJSONArray("networks");
        if (networks == null || networks.length() == 0) {
            wifiDevices.addView(text("利用可能なネットワークはありません。", 14, false));
            return;
        }
        for (int i = 0; i < networks.length(); i++) {
            JSONObject network = networks.optJSONObject(i);
            if (network == null) continue;
            final String networkSsid = network.optString("ssid", "(hidden)");
            String security = network.optString("security", "");
            String signal = network.optString("signal", "");
            LinearLayout item = itemRow(networkSsid + "  " + signal + "%  " + security);
            item.addView(button("選択", new View.OnClickListener() {
                public void onClick(View view) { ssid.setText(networkSsid); ssid.setSelection(ssid.length()); }
            }));
            wifiDevices.addView(item);
        }
    }

    private void renderBluetooth(JSONObject reply) {
        if (bluetoothDevices == null) return;
        bluetoothDevices.removeAllViews();
        JSONArray devices = reply.optJSONArray("devices");
        if (devices == null || devices.length() == 0) {
            bluetoothDevices.addView(text("デバイスが見つかりません。検索ボタンを押してペアリング待機状態にしてください。", 14, false));
            return;
        }
        for (int i = 0; i < devices.length(); i++) {
            JSONObject device = devices.optJSONObject(i);
            if (device == null) continue;
            final String address = device.optString("address", "");
            String label = device.optString("name", address);
            LinearLayout item = itemRow(label + "\n" + address);
            item.addView(button("選択", new View.OnClickListener() {
                public void onClick(View view) { bluetoothAddress.setText(address); }
            }));
            item.addView(button("接続", new View.OnClickListener() {
                public void onClick(View view) { request("bluetooth.connect", json("address", address), null); }
            }));
            bluetoothDevices.addView(item);
        }
    }

    private void renderAudioSinks(JSONObject reply) {
        if (audioSinks == null) return;
        audioSinks.removeAllViews();
        JSONArray sinks = reply.optJSONArray("sinks");
        if (sinks == null || sinks.length() == 0) {
            audioSinks.addView(text("出力先が見つかりません。", 14, false));
            return;
        }
        for (int i = 0; i < sinks.length(); i++) {
            JSONObject sink = sinks.optJSONObject(i);
            if (sink == null) continue;
            final int id = sink.optInt("id", -1);
            LinearLayout item = itemRow(sink.optString("name", "Audio output"));
            item.addView(button("この出力先を使う", new View.OnClickListener() {
                public void onClick(View view) { request("audio.default", json("id", id), null); }
            }));
            audioSinks.addView(item);
        }
    }

    private LinearLayout section(LinearLayout parent, String heading) {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setPadding(18, 12, 18, 16);
        box.setBackgroundColor(Color.WHITE);
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(-1, -2);
        params.setMargins(0, 16, 0, 0);
        parent.addView(box, params);
        box.addView(text(heading, 21, true));
        return box;
    }

    private LinearLayout listBox() {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setPadding(0, 6, 0, 0);
        return box;
    }

    private LinearLayout itemRow(String label) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(android.view.Gravity.CENTER_VERTICAL);
        TextView name = text(label, 14, false);
        name.setLayoutParams(new LinearLayout.LayoutParams(0, -2, 1));
        row.addView(name);
        return row;
    }

    private LinearLayout rowButtons(View... buttons) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        for (View button : buttons) row.addView(button);
        return row;
    }

    private TextView text(String value, int size, boolean bold) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(size);
        view.setTextColor(Color.rgb(45, 40, 48));
        view.setTypeface(Typeface.DEFAULT, bold ? Typeface.BOLD : Typeface.NORMAL);
        view.setPadding(0, 8, 8, 8);
        return view;
    }

    private EditText edit(String hint) {
        EditText view = new EditText(this);
        view.setHint(hint);
        view.setSingleLine(true);
        if (hint.contains("パスワード")) {
            view.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
        }
        return view;
    }

    private Button button(String label, View.OnClickListener listener) {
        Button button = new Button(this);
        button.setText(label);
        button.setOnClickListener(listener);
        return button;
    }

    private JSONObject json(Object... values) {
        JSONObject object = new JSONObject();
        try {
            for (int i = 0; i < values.length; i += 2) object.put((String) values[i], values[i + 1]);
        } catch (Exception error) {
            setStatus(error.toString());
        }
        return object;
    }

    private void request(final String operation, final JSONObject arguments, final HostControlClient.Callback callback) {
        HostControlClient.request(operation, arguments, new HostControlClient.Callback() {
            public void done(JSONObject reply) {
                if (callback != null) callback.done(reply);
                String output = reply.optString("error", reply.optString("output", "OK"));
                if (!reply.optBoolean("ok", false)) setStatus(operation + ": " + output);
                else if ("ping".equals(operation)) setStatus("Linuxホストに接続しました");
            }
        });
    }

    private void setStatus(String message) {
        if (status != null) status.setText(message);
    }
}
