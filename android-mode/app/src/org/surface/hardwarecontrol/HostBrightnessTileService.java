package org.surface.hardwarecontrol;

import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;

import org.json.JSONObject;

/** Steps the Linux host backlight through useful levels. */
public final class HostBrightnessTileService extends TileService {
    @Override
    public void onClick() {
        HostControlClient.request("brightness.step", null, new HostControlClient.Callback() {
            public void done(JSONObject ignored) { refresh(); }
        });
    }

    @Override
    public void onStartListening() { refresh(); }

    private void refresh() {
        HostControlClient.request("brightness.get", null, new HostControlClient.Callback() {
            public void done(JSONObject reply) {
                Tile tile = getQsTile();
                if (tile == null) return;
                tile.setLabel("明るさ " + reply.optInt("value", 0) + "%");
                tile.setState(Tile.STATE_ACTIVE);
                tile.updateTile();
            }
        });
    }
}
