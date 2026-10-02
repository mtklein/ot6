package io.github.mtklein.ot6patcher;

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
 * all of it runs off the UI thread.  It never notifies: each result goes to
 * the "last*" settings and logcat, and the app shows it when next opened.
 */
final class Patcher {
    static final String TAG = "OT6Patcher";
    static final String PREFS = "ot6";

    /** The output's fixed name: RetroArch keys saves and states by content file name. */
    static final String OUT = "OT6.sfc";

    private Patcher() {}

    static final class Result {
        boolean ok;          // OT6.sfc is this APK's build
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

    static boolean hasTreeAccess(Context c, Uri tree) {
        for (UriPermission p : c.getContentResolver().getPersistedUriPermissions())
            if (p.getUri().equals(tree) && p.isReadPermission() && p.isWritePermission())
                return true;
        return false;
    }

    static final class Child {
        String docId, name;
        long size;
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
                Document.COLUMN_DISPLAY_NAME, Document.COLUMN_SIZE}, null, null, null);
        if (q == null) throw new IOException("cannot list the folder");
        try {
            while (q.moveToNext()) {
                Child ch = new Child();
                ch.docId = q.getString(0);
                ch.name = q.getString(1);
                ch.size = q.isNull(2) ? -1 : q.getLong(2);
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

    /** Records a result where the app shows it (and logcat); never a notification. */
    private static Result done(Context c, boolean ok, String message, String rom, String crc) {
        Result r = new Result();
        r.ok = ok;
        r.message = message;
        SharedPreferences.Editor e = prefs(c).edit().putBoolean("lastOk", ok)
                .putString("lastMessage", message)
                .putLong("lastTime", System.currentTimeMillis())
                .putString("lastVersion", version(c));
        if (ok) e.putString("lastRom", rom).putString("lastCrc", crc);
        else e.remove("lastRom").remove("lastCrc");
        e.commit();   // the receiver's process may end right after
        Log.i(TAG, (ok ? "ok: " : "failed: ") + message);
        return r;
    }

    /** Releases every persisted grant but the folder's and the remembered ROM's. */
    static void keepOnlyCurrentGrants(Context c) {
        SharedPreferences p = prefs(c);
        String src = p.getString("source", null), tree = p.getString("tree", null);
        ContentResolver cr = c.getContentResolver();
        for (UriPermission g : cr.getPersistedUriPermissions()) {
            String u = g.getUri().toString();
            if (!u.equals(src) && !u.equals(tree))
                cr.releasePersistableUriPermission(g.getUri(),
                        (g.isReadPermission() ? Intent.FLAG_GRANT_READ_URI_PERMISSION : 0)
                        | (g.isWritePermission() ? Intent.FLAG_GRANT_WRITE_URI_PERMISSION : 0));
        }
    }

    /**
     * Patches the player's ROM and writes OT6.sfc into the granted folder,
     * atomically.  The ROM is the remembered one while it still reads and
     * matches; otherwise the folder is scanned for it by CRC32 (RomScan), so a
     * renamed or moved-in ROM still works.  Settings from v0.23's first build
     * (a separately picked ROM plus an output folder) keep working as they are.
     */
    static Result write(Context c) {
        final ContentResolver cr = c.getContentResolver();
        SharedPreferences p = prefs(c);
        String v = "OT6 v" + version(c);
        String treeStr = p.getString("tree", null);
        if (treeStr == null)
            return done(c, false, v + " is installed, but setup isn't finished:"
                    + " open OT6 Patcher and choose the folder your ROM is in.", null, null);
        final Uri tree = Uri.parse(treeStr);
        if (!hasTreeAccess(c, tree))
            return done(c, false, v + " could not be written: OT6 Patcher lost access"
                    + " to its folder. Open it and choose the folder again.", null, null);
        String folder = nameOf(c, tree, true);
        try {
            byte[] patch = bundledPatch(c);
            Bps.Info info = Bps.read(patch);

            byte[] rom = null;
            String used = p.getString("sourceName", null);
            String srcStr = p.getString("source", null);
            if (srcStr != null) {
                try {
                    rom = Bps.source(readAll(cr, Uri.parse(srcStr)), info);
                } catch (Exception gone) {
                    Log.i(TAG, "remembered ROM " + used + " is gone or changed (" + gone
                            + "); scanning " + folder);
                }
            }
            List<Child> kids = children(cr, tree);
            if (rom == null) {
                List<RomScan.Entry> entries = new ArrayList<>();
                for (final Child ch : kids)
                    entries.add(new RomScan.Entry(ch.name, ch.size, new RomScan.Bytes() {
                        @Override public byte[] read() throws IOException {
                            return readAll(cr, childUri(tree, ch.docId));
                        }
                    }, ch));
                RomScan.Result found = RomScan.choose(entries, info);
                if (found.chosen == null)
                    return done(c, false, v + " was not written: no Final Fantasy III"
                            + " (USA) v1.0 ROM (CRC32 " + Bps.hex(info.sourceCrc) + ") is in "
                            + folder + ". " + (found.checked.isEmpty()
                                ? "No file there is the ROM's size."
                                : "Checked: " + RomScan.describe(found) + ".")
                            + " Choose another folder, or pick the ROM file, in OT6 Patcher.", null, null);
                Child ch = (Child) found.chosen.ref;
                rom = found.rom;
                used = ch.name;
                p.edit().putString("source", childUri(tree, ch.docId).toString())
                        .putString("sourceName", ch.name).apply();
                keepOnlyCurrentGrants(c);
                Log.i(TAG, "scan of " + folder + ": " + RomScan.describe(found));
            }
            byte[] target = Bps.apply(patch, rom);        // checks the target CRC32

            String tmp = OUT + ".tmp";
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
            return done(c, true, v + " written to " + folder + "/" + OUT
                    + " (CRC32 " + Bps.hex(info.targetCrc) + ") from " + used + "."
                    + (stray.isEmpty() ? "" : " Warning: " + stray + " is in the same folder,"
                       + " and RetroArch would apply it on top of OT6; delete it."),
                    used, Bps.hex(info.targetCrc));
        } catch (Bps.BpsException e) {
            return done(c, false, v + " was not written: " + e.getMessage() + ".", null, null);
        } catch (Exception e) {
            Log.e(TAG, "write failed", e);
            return done(c, false, v + " could not be written to " + folder + "/"
                    + OUT + ": " + e, null, null);
        }
    }

}
