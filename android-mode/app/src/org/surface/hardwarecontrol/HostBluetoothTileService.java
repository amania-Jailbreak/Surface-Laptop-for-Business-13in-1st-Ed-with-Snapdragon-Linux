package org.surface.hardwarecontrol;

import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;

import org.json.JSONObject;

/** Toggles the Linux-owned Bluetooth adapter. */
public final class HostBluetoothTileService extends TileService {
    @Override
    public void onClick() {
        HostControlClient.request("bluetooth.status", null, new HostControlClient.Callback() {
            public void done(JSONObject reply) {
                boolean powered = reply.optBoolean("powered", false);
                HostControlClient.request("bluetooth.power", json("value", powered ? "off" : "on"), new HostControlClient.Callback() {
                    public void done(JSONObject ignored) { refresh(); }
                });
            }
        });
    }

    @Override
    public void onStartListening() { refresh(); }

    private void refresh() {
        HostControlClient.request("bluetooth.status", null, new HostControlClient.Callback() {
            public void done(JSONObject reply) {
                Tile tile = getQsTile();
                if (tile == null) return;
                boolean powered = reply.optBoolean("powered", false);
                tile.setLabel("Bluetooth");
                tile.setState(powered ? Tile.STATE_ACTIVE : Tile.STATE_INACTIVE);
                tile.updateTile();
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
