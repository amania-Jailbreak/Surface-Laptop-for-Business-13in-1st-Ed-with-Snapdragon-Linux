package org.surface.hardwarecontrol;

import android.content.Intent;
import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;

/** Opens the full host-control screen from Android SystemUI. */
public final class HostControlsTileService extends TileService {
    @Override
    public void onClick() {
        Intent intent = new Intent(this, MainActivity.class);
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        startActivityAndCollapse(intent);
    }

    @Override
    public void onStartListening() {
        Tile tile = getQsTile();
        if (tile != null) {
            tile.setLabel("Surface Controls");
            tile.setState(Tile.STATE_ACTIVE);
            tile.updateTile();
        }
    }
}
