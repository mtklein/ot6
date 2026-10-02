package io.github.mtklein.ot6patcher;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.ContentResolver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.UriPermission;
import android.database.Cursor;
import android.net.Uri;
import android.provider.DocumentsContract;
import android.provider.DocumentsContract.Document;
import android.util.Log;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/**
 * Applies the patch this APK carries (assets/ot6.bps) to the player's own
 * ROM and writes the result as OT6.sfc in the folder they chose.  The
 * source ROM is only ever read.  Shared by MainActivity and UpdateReceiver;
 * all of it runs off the UI thread.
 */
final class Patcher {
    static final String TAG = "OT6Patcher";
    static final String PREFS = "ot6";
    static final String CHANNEL = "updates";

    /** The output's fixed name: RetroArch keys saves and states by content file name. */
    static final String OUT = "OT6.sfc";

    private Patcher() {}

    static final class Result {
        boolean ok;          // OT6.sfc is this APK's build
        boolean needsUser;   // only opening the app can fix it
        String message;
    }

    static SharedPreferences prefs(Context c) {
        return c.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    static String version(Context c) {
        try {
            return c.getPackageManager().getPackageInfo(c.getPackageName(), 0).versionName;
        } catch (Exception e) {
            return "?";
        }
    }

    static byte[] readAll(InputStream in) throws IOException {
        try {
            ByteArrayOutputStream out = new ByteArrayOutputStream(1 << 22);
            byte[] buf = new byte[1 << 16];
            int n;
            while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
            return out.toByteArray();
        } finally {
            in.close();
        }
    }

    static byte[] readAll(ContentResolver cr, Uri u) throws IOException {
        InputStream in = cr.openInputStream(u);
        if (in == null) throw new IOException("cannot open " + u);
        return readAll(in);
    }

    static byte[] bundledPatch(Context c) throws IOException {
        return readAll(c.getAssets().open("ot6.bps"));
    }

    static boolean hasReadAccess(Context c, Uri doc) {
        for (UriPermission p : c.getContentResolver().getPersistedUriPermissions())
            if (p.getUri().equals(doc) && p.isReadPermission()) return true;
        return false;
    }

    static boolean hasTreeAccess(Context c, Uri tree) {
        for (UriPermission p : c.getContentResolver().getPersistedUriPermissions())
            if (p.getUri().equals(tree) && p.isReadPermission() && p.isWritePermission())
                return true;
        return false;
    }

    static final class Child {
        String docId, name;
    }

    static Uri folderUri(Uri tree) {
        return DocumentsContract.buildDocumentUriUsingTree(tree,
                DocumentsContract.getTreeDocumentId(tree));
    }

    static Uri childUri(Uri tree, String docId) {
        return DocumentsContract.buildDocumentUriUsingTree(tree, docId);
    }

    static List<Child> children(ContentResolver cr, Uri tree) throws IOException {
        Uri list = DocumentsContract.buildChildDocumentsUriUsingTree(tree,
                DocumentsContract.getTreeDocumentId(tree));
        List<Child> out = new ArrayList<>();
        Cursor q = cr.query(list, new String[] {Document.COLUMN_DOCUMENT_ID,
                Document.COLUMN_DISPLAY_NAME}, null, null, null);
        if (q == null) throw new IOException("cannot list the folder");
        try {
            while (q.moveToNext()) {
                Child ch = new Child();
                ch.docId = q.getString(0);
                ch.name = q.getString(1);
                out.add(ch);
            }
        } finally {
            q.close();
        }
        return out;
    }

    static Child find(List<Child> kids, String name) {
        for (Child ch : kids) if (name.equals(ch.name)) return ch;
        return null;
    }

    static String displayName(ContentResolver cr, Uri doc) {
        Cursor q = cr.query(doc, new String[] {Document.COLUMN_DISPLAY_NAME}, null, null, null);
        if (q == null) return null;
        try {
            return q.moveToFirst() ? q.getString(0) : null;
        } finally {
            q.close();
        }
    }

    static String nameOf(Context c, Uri doc, boolean tree) {
        try {
            String n = displayName(c.getContentResolver(), tree ? folderUri(doc) : doc);
            return n != null ? n : doc.getLastPathSegment();
        } catch (Exception e) {
            return doc.getLastPathSegment();
        }
    }

    /** Soft-patches RetroArch would apply on top of OT6.sfc, if any sit beside it. */
    static String strays(List<Child> kids) {
        StringBuilder s = new StringBuilder();
        for (Child ch : kids)
            for (String ext : new String[] {".bps", ".ips", ".ups"})
                if (ch.name != null && ch.name.equalsIgnoreCase("OT6" + ext))
                    s.append(s.length() > 0 ? ", " : "").append(ch.name);
        return s.toString();
    }

    private static Result done(Context c, boolean ok, boolean needsUser, String message) {
        Result r = new Result();
        r.ok = ok;
        r.needsUser = needsUser;
        r.message = message;
        prefs(c).edit().putBoolean("lastOk", ok).putString("lastMessage", message)
                .putLong("lastTime", System.currentTimeMillis())
                .putString("lastVersion", version(c)).apply();
        Log.i(TAG, (ok ? "ok: " : "failed: ") + message);
        return r;
    }

    /** Patches the remembered ROM and writes OT6.sfc into the remembered folder, atomically. */
    static Result write(Context c) {
        ContentResolver cr = c.getContentResolver();
        SharedPreferences p = prefs(c);
        String v = "OT6 v" + version(c);
        String srcStr = p.getString("source", null);
        String srcName = p.getString("sourceName", "your ROM");
        String treeStr = p.getString("tree", null);
        if (srcStr == null || treeStr == null)
            return done(c, false, true, v + " is installed, but setup isn't finished:"
                    + " open OT6 Patcher to choose your ROM and an output folder.");
        Uri src = Uri.parse(srcStr), tree = Uri.parse(treeStr);
        if (!hasReadAccess(c, src))
            return done(c, false, true, v + " could not be written: OT6 Patcher lost access"
                    + " to " + srcName + ". Open it and choose your ROM again.");
        if (!hasTreeAccess(c, tree))
            return done(c, false, true, v + " could not be written: OT6 Patcher lost access"
                    + " to the output folder. Open it and choose the folder again.");
        String folder = nameOf(c, tree, true);
        try {
            byte[] patch = bundledPatch(c);
            Bps.Info info = Bps.read(patch);
            byte[] file;
            try {
                file = readAll(cr, src);
            } catch (IOException | SecurityException e) {
                return done(c, false, true, v + " could not be written: " + srcName
                        + " can't be read any more (" + e.getMessage()
                        + "). Open OT6 Patcher and choose your ROM again.");
            }
            byte[] rom = Bps.source(file, info);         // throws on the wrong ROM
            byte[] target = Bps.apply(patch, rom);        // checks the target CRC32

            String tmp = OUT + ".tmp";
            List<Child> kids = children(cr, tree);
            Child stale = find(kids, tmp);
            if (stale != null) DocumentsContract.deleteDocument(cr, childUri(tree, stale.docId));
            Uri t = DocumentsContract.createDocument(cr, folderUri(tree),
                    "application/octet-stream", tmp);
            if (t == null) throw new IOException("could not create " + tmp);
            String tName = displayName(cr, t);
            if (!tmp.equals(tName)) {
                DocumentsContract.deleteDocument(cr, t);
                throw new IOException("the folder named the new file " + tName + ", not " + tmp);
            }
            OutputStream o = cr.openOutputStream(t, "w");
            if (o == null) throw new IOException("cannot write " + tmp);
            try {
                o.write(target);
            } finally {
                o.close();
            }
            if (!Arrays.equals(readAll(cr, t), target)) {
                DocumentsContract.deleteDocument(cr, t);
                throw new IOException(tmp + " did not read back as written");
            }
            // SAF's rename never replaces (the file provider picks "OT6 (1).sfc"
            // instead), so the old OT6.sfc goes first: the folder holds the old
            // ROM or the new one, never a partial file, though for a moment it
            // holds neither.
            Child old = find(kids, OUT);
            if (old != null) DocumentsContract.deleteDocument(cr, childUri(tree, old.docId));
            Uri r = DocumentsContract.renameDocument(cr, t, OUT);
            if (r == null) r = t;
            String rName = displayName(cr, r);
            if (!OUT.equals(rName))
                throw new IOException("renaming " + tmp + " gave " + rName + ", not " + OUT);
            String stray = strays(kids);
            p.edit().putString("strays", stray).apply();
            return done(c, true, false, v + " written to " + folder + "/" + OUT
                    + " (CRC32 " + Bps.hex(info.targetCrc) + ")."
                    + (stray.isEmpty() ? "" : " Warning: " + stray + " is in the same folder,"
                       + " and RetroArch would apply it on top of OT6; delete it."));
        } catch (Bps.BpsException e) {
            return done(c, false, true, v + " was not written: " + srcName + ": "
                    + e.getMessage() + ".");
        } catch (Exception e) {
            Log.e(TAG, "write failed", e);
            return done(c, false, false, v + " could not be written to " + folder + "/"
                    + OUT + ": " + e);
        }
    }

    static void notify(Context c, Result r) {
        NotificationManager nm = c.getSystemService(NotificationManager.class);
        nm.createNotificationChannel(new NotificationChannel(CHANNEL, "Patch updates",
                NotificationManager.IMPORTANCE_DEFAULT));
        Intent open = new Intent(c, MainActivity.class)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        PendingIntent pi = PendingIntent.getActivity(c, 0, open,
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        Notification n = new Notification.Builder(c, CHANNEL)
                .setSmallIcon(r.ok ? android.R.drawable.stat_sys_download_done
                                   : android.R.drawable.stat_notify_error)
                .setContentTitle(r.ok ? "OT6 v" + version(c) + " ready"
                        : r.needsUser ? "OT6 Patcher: open the app" : "OT6 Patcher failed")
                .setContentText(r.message)
                .setStyle(new Notification.BigTextStyle().bigText(r.message))
                .setContentIntent(pi)
                .setAutoCancel(true)
                .build();
        nm.notify(1, n);
    }
}
