package org.surface.hardwarecontrol;

import android.net.LocalSocket;
import android.net.LocalSocketAddress;
import android.os.Handler;
import android.os.Looper;

import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.nio.charset.Charset;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

final class HostControlClient {
    private static final String SOCKET_PATH = "/run/surface-control.sock";
    private static final ExecutorService EXECUTOR = Executors.newCachedThreadPool();
    private static final Handler MAIN = new Handler(Looper.getMainLooper());

    interface Callback { void done(JSONObject reply); }

    static void request(final String operation, final JSONObject arguments, final Callback callback) {
        EXECUTOR.execute(new Runnable() {
            public void run() {
                JSONObject reply;
                try {
                    JSONObject request = arguments == null ? new JSONObject() : new JSONObject(arguments.toString());
                    request.put("op", operation);
                    LocalSocket socket = new LocalSocket();
                    socket.connect(new LocalSocketAddress(SOCKET_PATH, LocalSocketAddress.Namespace.FILESYSTEM));
                    OutputStreamWriter writer = new OutputStreamWriter(socket.getOutputStream(), Charset.forName("UTF-8"));
                    writer.write(request.toString());
                    writer.write("\n");
                    writer.flush();
                    BufferedReader reader = new BufferedReader(new InputStreamReader(socket.getInputStream(), Charset.forName("UTF-8")));
                    String line = reader.readLine();
                    socket.close();
                    reply = line == null ? error("No response from Linux host") : new JSONObject(line);
                } catch (Exception error) {
                    reply = error(error.toString());
                }
                final JSONObject result = reply;
                MAIN.post(new Runnable() {
                    public void run() { if (callback != null) callback.done(result); }
                });
            }
        });
    }

    static String encoded(String value) {
        return android.util.Base64.encodeToString(value.getBytes(Charset.forName("UTF-8")), android.util.Base64.NO_WRAP);
    }

    static void shutdown() { EXECUTOR.shutdownNow(); }

    private static JSONObject error(String message) {
        JSONObject result = new JSONObject();
        try { result.put("ok", false); result.put("error", message); } catch (Exception ignored) {}
        return result;
    }
}
