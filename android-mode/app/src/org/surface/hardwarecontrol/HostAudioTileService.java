package org.surface.hardwarecontrol;

import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;

import org.json.JSONObject;

/** Toggles mute on the Linux default audio sink. */
public final class HostAudioTileService extends TileService {
    @Override
    public void onClick() {
        HostControlClient.request("volume.mute.toggle", null, new HostControlClient.Callback() {
            public void done(JSONObject ignored) { refresh(); }
        });
    }

    @Override
    public void onStartListening() { refresh(); }

    private void refresh() {
        HostControlClient.request("volume.get", null, new HostControlClient.Callback() {
            public void done(JSONObject reply) {
                Tile tile = getQsTile();
                if (tile == null) return;
                boolean muted = reply.optBoolean("muted", false);
                tile.setLabel(muted ? "音声（ミュート）" : "音声");
                tile.setState(muted ? Tile.STATE_INACTIVE : Tile.STATE_ACTIVE);
                tile.updateTile();
            }
        });
    }
}
