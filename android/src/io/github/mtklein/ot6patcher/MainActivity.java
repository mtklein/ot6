package io.github.mtklein.ot6patcher;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.UriPermission;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.view.View;
import android.view.WindowInsets;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.text.DateFormat;
import java.util.Date;

/**
 * First launch: the player picks their own FF3 (USA) ROM, which is checked
 * against the patch, then an output folder; the app writes OT6.sfc there.
 * Later: shows what was written and offers to write it again.
 */
public final class MainActivity extends Activity {
    private static final int PICK_ROM = 1, PICK_FOLDER = 2;

    private LinearLayout box;
    private boolean busy;
    private String note;     // the latest ROM check's outcome, shown above the state

    @Override
    protected void onCreate(Bundle saved) {
        super.onCreate(saved);
        ScrollView scroll = new ScrollView(this);
        box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        int pad = dp(16);
        box.setPadding(pad, pad, pad, pad);
        scroll.addView(box);
        scroll.setOnApplyWindowInsetsListener(new View.OnApplyWindowInsetsListener() {
            @Override @SuppressWarnings("deprecation")
            public WindowInsets onApplyWindowInsets(View v, WindowInsets in) {
                v.setPadding(in.getSystemWindowInsetLeft(), in.getSystemWindowInsetTop(),
                        in.getSystemWindowInsetRight(), in.getSystemWindowInsetBottom());
                return in;
            }
        });
        setContentView(scroll);

        SharedPreferences p = Patcher.prefs(this);
        if (Build.VERSION.SDK_INT >= 33 && !p.getBoolean("askedNotify", false)
                && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                   != PackageManager.PERMISSION_GRANTED) {
            p.edit().putBoolean("askedNotify", true).apply();
            requestPermissions(new String[] {Manifest.permission.POST_NOTIFICATIONS}, 0);
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        render();
    }

    private int dp(int x) {
        return (int) (x * getResources().getDisplayMetrics().density + 0.5f);
    }

    private void text(String s, float size) {
        TextView t = new TextView(this);
        t.setText(s);
        t.setTextSize(size);
        t.setPadding(0, 0, 0, dp(12));
        box.addView(t);
    }

    private void button(String label, View.OnClickListener onClick) {
        Button b = new Button(this);
        b.setText(label);
        b.setEnabled(!busy);
        b.setOnClickListener(onClick);
        box.addView(b);
    }

    private final View.OnClickListener pickRom = new View.OnClickListener() {
        @Override public void onClick(View v) {
            Intent i = new Intent(Intent.ACTION_OPEN_DOCUMENT);
            i.addCategory(Intent.CATEGORY_OPENABLE);
            i.setType("*/*");
            i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION
                    | Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);
            startActivityForResult(i, PICK_ROM);
        }
    };

    private final View.OnClickListener pickFolder = new View.OnClickListener() {
        @Override public void onClick(View v) {
            Intent i = new Intent(Intent.ACTION_OPEN_DOCUMENT_TREE);
            i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION
                    | Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                    | Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);
            startActivityForResult(i, PICK_FOLDER);
        }
    };

    private final View.OnClickListener writeAgain = new View.OnClickListener() {
        @Override public void onClick(View v) { write(); }
    };

    private void render() {
        box.removeAllViews();
        SharedPreferences p = Patcher.prefs(this);
        String v = Patcher.version(this);
        text("OT6 Patcher v" + v, 22);
        if (busy) text("Working…", 16);
        if (note != null) text(note, 16);
        String src = p.getString("source", null), tree = p.getString("tree", null);
        if (src == null) {
            if (note == null)
                text("This app makes OT6.sfc from your own Final Fantasy III (USA) v1.0 ROM"
                        + " and rewrites it after every update, keeping the same name so your"
                        + " saves carry over. Your ROM is only read, never changed.\n\n"
                        + "First, choose your ROM.", 16);
            button("Choose your FF3 ROM", pickRom);
            return;
        }
        if (tree == null) {
            text("ROM: " + p.getString("sourceName", "?") + "\n\nNow choose the folder to"
                    + " write OT6.sfc into (for RetroArch, the folder its playlist scans).", 16);
            button("Choose output folder", pickFolder);
            button("Choose another ROM", pickRom);
            return;
        }
        Uri treeUri = Uri.parse(tree);
        StringBuilder s = new StringBuilder();
        s.append("ROM: ").append(p.getString("sourceName", "?"))
         .append("\nOutput: ").append(Patcher.nameOf(this, treeUri, true)).append('/')
         .append(Patcher.OUT)
         .append("\nThis app carries OT6 v").append(v).append('.');
        if (!Patcher.hasReadAccess(this, Uri.parse(src)))
            s.append("\n\nThe app no longer has access to the ROM; choose it again.");
        if (!Patcher.hasTreeAccess(this, treeUri))
            s.append("\n\nThe app no longer has access to the output folder; choose it again.");
        String last = p.getString("lastMessage", null);
        if (last != null)
            s.append("\n\nLast write (")
             .append(DateFormat.getDateTimeInstance().format(new Date(p.getLong("lastTime", 0))))
             .append("):\n").append(last);
        if (last == null || !v.equals(p.getString("lastVersion", null))
                || !p.getBoolean("lastOk", false))
            s.append("\n\nOT6.sfc is not known to be v").append(v).append(" yet.");
        text(s.toString(), 16);
        button("Write OT6.sfc again", writeAgain);
        button("Choose another ROM", pickRom);
        button("Choose another output folder", pickFolder);
    }

    private void background(final Runnable work) {
        busy = true;
        render();
        new Thread(new Runnable() {
            @Override public void run() {
                try {
                    work.run();
                } finally {
                    runOnUiThread(new Runnable() {
                        @Override public void run() {
                            busy = false;
                            render();
                        }
                    });
                }
            }
        }, "ot6-work").start();
    }

    private void write() {
        note = null;
        background(new Runnable() {
            @Override public void run() { Patcher.write(MainActivity.this); }
        });
    }

    /** Keeps only the grants for the ROM and the folder in use. */
    private void releaseOtherGrants() {
        SharedPreferences p = Patcher.prefs(this);
        String src = p.getString("source", null), tree = p.getString("tree", null);
        for (UriPermission g : getContentResolver().getPersistedUriPermissions()) {
            String u = g.getUri().toString();
            if (!u.equals(src) && !u.equals(tree))
                getContentResolver().releasePersistableUriPermission(g.getUri(),
                        (g.isReadPermission() ? Intent.FLAG_GRANT_READ_URI_PERMISSION : 0)
                        | (g.isWritePermission() ? Intent.FLAG_GRANT_WRITE_URI_PERMISSION : 0));
        }
    }

    @Override
    protected void onActivityResult(int request, int result, Intent data) {
        if (result != RESULT_OK || data == null || data.getData() == null) return;
        final Uri uri = data.getData();
        SharedPreferences p = Patcher.prefs(this);
        if (request == PICK_ROM) {
            getContentResolver().takePersistableUriPermission(uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION);
            final String name = Patcher.nameOf(this, uri, false);
            final boolean needFolder = p.getString("tree", null) == null;
            note = null;
            background(new Runnable() {
                @Override public void run() { checkRom(uri, name, needFolder); }
            });
        } else if (request == PICK_FOLDER) {
            getContentResolver().takePersistableUriPermission(uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
            p.edit().putString("tree", uri.toString()).apply();
            releaseOtherGrants();
            write();
        }
    }

    /** Reads the picked file and keeps it only if it is the ROM the patch expects. */
    private void checkRom(Uri uri, String name, boolean thenFolder) {
        try {
            Bps.Info info = Bps.read(Patcher.bundledPatch(this));
            byte[] file = Patcher.readAll(getContentResolver(), uri);
            Bps.source(file, info);
            Patcher.prefs(this).edit().putString("source", uri.toString())
                    .putString("sourceName", name).remove("lastMessage").apply();
            releaseOtherGrants();
            note = name + " is Final Fantasy III (USA) v1.0 (CRC32 " + Bps.hex(info.sourceCrc)
                    + (Bps.headered(file, info) ? ", after removing its 512-byte copier header"
                       : "") + ").";
            if (thenFolder)
                runOnUiThread(new Runnable() {
                    @Override public void run() { pickFolder.onClick(null); }
                });
            else
                Patcher.write(this);
        } catch (Bps.BpsException e) {
            if (!uri.toString().equals(Patcher.prefs(this).getString("source", null)))
                getContentResolver().releasePersistableUriPermission(uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION);
            note = name + " can't be used: " + e.getMessage() + ".";
        } catch (Exception e) {
            note = name + " could not be read: " + e;
        }
    }
}
