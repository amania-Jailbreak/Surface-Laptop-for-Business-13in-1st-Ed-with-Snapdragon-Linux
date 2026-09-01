package android.service.quicksettings;

/** Compile-time API stub for builds using an older platform android.jar. */
public class Tile {
    public static final int STATE_UNAVAILABLE = 0;
    public static final int STATE_INACTIVE = 1;
    public static final int STATE_ACTIVE = 2;
    public void setLabel(CharSequence label) {}
    public void setState(int state) {}
    public void updateTile() {}
}
