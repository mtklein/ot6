package io.github.mtklein.ot6patcher;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.util.Log;

/**
 * After every update of this app (MY_PACKAGE_REPLACED), writes the new OT6.sfc,
 * silently: the result is in the app's settings and logcat, shown when it's next opened.
 */
public final class UpdateReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (!Intent.ACTION_MY_PACKAGE_REPLACED.equals(intent.getAction())) return;
        Log.i(Patcher.TAG, "MY_PACKAGE_REPLACED: writing OT6.sfc for v" + Patcher.version(context));
        final Context c = context.getApplicationContext();
        final PendingResult pending = goAsync();
        new Thread(new Runnable() {
            @Override public void run() {
                try {
                    Patcher.write(c);
                } catch (Throwable t) {
                    Log.e(Patcher.TAG, "update write failed", t);
                } finally {
                    pending.finish();
                }
            }
        }, "ot6-update").start();
    }
}
