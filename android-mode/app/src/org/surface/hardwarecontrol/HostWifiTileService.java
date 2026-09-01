package org.surface.hardwarecontrol;

import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;

import org.json.JSONObject;

/** Toggles the Linux-owned Wi-Fi radio. */
public final class HostWifiTileService extends TileService {
    @Override
    public void onClick() {
        HostControlClient.request("wifi.toggle", null, new HostControlClient.Callback() {
            public void done(JSONObject ignored) { refresh(); }
        });
    }

    @Override
    public void onStartListening() { refresh(); }

    private void refresh() {
        HostControlClient.request("wifi.radio", null, new HostControlClient.Callback() {
            public void done(JSONObject reply) {
                Tile tile = getQsTile();
                if (tile == null) return;
                boolean enabled = reply.optBoolean("enabled", false);
                tile.setLabel("Wi‑Fi");
                tile.setState(enabled ? Tile.STATE_ACTIVE : Tile.STATE_INACTIVE);
                tile.updateTile();
            }
        });
    }
}
