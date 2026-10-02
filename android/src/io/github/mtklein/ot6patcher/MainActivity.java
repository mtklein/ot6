package io.github.mtklein.ot6patcher;

import android.app.Activity;
import android.content.Intent;
import android.content.SharedPreferences;
import android.net.Uri;
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
 * Setup is one step: the player chooses the folder their FF3 (USA) ROM is
 * in; the app finds the ROM there by CRC32 and writes OT6.sfc beside it.
 * Picking the ROM file itself is the fallback.  Later: shows what was
 * written and offers to write it again.
 */
public final class MainActivity extends Activity {
    private static final int PICK_ROM = 1, PICK_FOLDER = 2;

    private LinearLayout box;
    private boolean busy;
    private String note;     // a picked file's check, shown above the state

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
        text(getApplicationInfo().loadLabel(getPackageManager()) + " v" + v, 22);
        if (busy) text("Working…", 16);
        if (note != null) text(note, 16);
        String tree = p.getString("tree", null);
        if (tree == null) {
            text("This app makes OT6.sfc from your own Final Fantasy III (USA) v1.0 ROM,"
                    + " in the same folder, and rewrites it after every update, keeping the"
                    + " name so your saves carry over. Your ROM is only read, never changed."
                    + "\n\nChoose the folder your ROM is in (for RetroArch, one its playlist"
                    + " scans); the app finds the ROM there.", 16);
            button("Choose ROM folder", pickFolder);
            return;
        }
        Uri treeUri = Uri.parse(tree);
        StringBuilder s = new StringBuilder();
        s.append("Folder: ").append(Patcher.nameOf(this, treeUri, true))
         .append("\nROM: ").append(p.getString("sourceName", "not found yet"))
         .append("\nThis app carries OT6 v").append(v).append('.');
        if (!Patcher.hasTreeAccess(this, treeUri))
            s.append("\n\nThe app no longer has access to this folder; choose it again.");
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
        button("Choose another folder", pickFolder);
        button("Pick the ROM file instead", pickRom);
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

    @Override
    protected void onActivityResult(int request, int result, Intent data) {
        if (result != RESULT_OK || data == null || data.getData() == null) return;
        final Uri uri = data.getData();
        if (request == PICK_FOLDER) {
            getContentResolver().takePersistableUriPermission(uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
            // a new folder: find the ROM in it afresh
            Patcher.prefs(this).edit().putString("tree", uri.toString())
                    .remove("source").remove("sourceName").apply();
            Patcher.keepOnlyCurrentGrants(this);
            write();
        } else if (request == PICK_ROM) {
            getContentResolver().takePersistableUriPermission(uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION);
            final String name = Patcher.nameOf(this, uri, false);
            note = null;
            background(new Runnable() {
                @Override public void run() { useRomFile(uri, name); }
            });
        }
    }

    /** The fallback: a ROM picked by hand, kept only if it is the one the patch expects. */
    private void useRomFile(Uri uri, String name) {
        try {
            Bps.Info info = Bps.read(Patcher.bundledPatch(this));
            byte[] file = Patcher.readAll(getContentResolver(), uri);
            Bps.source(file, info);
            Patcher.prefs(this).edit().putString("source", uri.toString())
                    .putString("sourceName", name).apply();
            Patcher.keepOnlyCurrentGrants(this);
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
