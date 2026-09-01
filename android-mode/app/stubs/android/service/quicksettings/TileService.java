package android.service.quicksettings;

import android.app.Service;
import android.content.Intent;
import android.os.IBinder;

/** Compile-time API stub for builds using an older platform android.jar. */
public class TileService extends Service {
    public void onClick() {}
    public void onStartListening() {}
    public Tile getQsTile() { return null; }
    public void startActivityAndCollapse(Intent intent) {}
    public IBinder onBind(Intent intent) { return null; }
}
