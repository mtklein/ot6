package io.github.mtklein.ot6patcher;

import java.io.IOException;
import java.util.ArrayList;
import java.util.List;

/**
 * Finds the patch's source ROM among a folder's files.  Plain Java, so
 * android/test/BpsTest.java runs it on the host.  A file is read only when
 * its size fits (the ROM, or the ROM plus a 512-byte copier header) and it
 * isn't the app's own output; the first whose CRC32 matches is chosen.
 */
public final class RomScan {
    private RomScan() {}

    /** The output file, never a candidate. */
    public static final String OUT = "OT6.sfc";
    public static final String TMP = OUT + ".tmp";

    /** OT6.sfc or its temporary (any case): files the app writes and deletes. */
    public static boolean isOutput(String name) {
        return name != null && (name.equalsIgnoreCase(OUT) || name.equalsIgnoreCase(TMP));
    }

    /**
     * A soft-patch RetroArch would apply on top of OT6.sfc: OT6.ips, .bps,
     * .ups or .xdelta, or a numbered follow-on patch (.ips1 to .ips9 and so
     * on), as RetroArch's tasks/task_patch.c looks for them.
     */
    public static boolean isSoftPatch(String name) {
        return name != null && name.matches("(?i)OT6\\.(ips|bps|ups|xdelta)[1-9]?");
    }

    public interface Bytes {
        byte[] read() throws IOException;
    }

    public static final class Entry {
        public final String name;
        public final long size;
        public final Bytes bytes;
        public final Object ref;   // the caller's handle (a document id)

        public Entry(String name, long size, Bytes bytes, Object ref) {
            this.name = name;
            this.size = size;
            this.bytes = bytes;
            this.ref = ref;
        }
    }

    /** One file that was read, and what it turned out to be. */
    public static final class Checked {
        public String name;
        public long size;
        public int crc;           // of the whole file
        public boolean matches, headered;

        @Override public String toString() {
            return name + " (" + size + " bytes, CRC32 " + Bps.hex(crc)
                    + (matches ? headered ? ", matches after its copier header" : ", matches" : "")
                    + ")";
        }
    }

    public static final class Result {
        public Entry chosen;          // null when nothing matched
        public byte[] rom;            // the chosen file's ROM image, header stripped
        public boolean headered;
        public final List<Checked> checked = new ArrayList<>();
        public int skipped;           // files not read: wrong size, or OT6.sfc
    }

    public static boolean sizeFits(long size, Bps.Info info) {
        return size == info.sourceSize || size == info.sourceSize + Bps.COPIER_HEADER;
    }

    public static Result choose(List<Entry> files, Bps.Info info) throws IOException {
        Result r = new Result();
        for (Entry e : files) {
            if (e.name == null || isOutput(e.name) || !sizeFits(e.size, info)) {
                r.skipped++;
                continue;
            }
            byte[] file = e.bytes.read();
            Checked c = new Checked();
            c.name = e.name;
            c.size = file.length;
            c.crc = Bps.crc32(file);
            c.headered = Bps.headered(file, info);
            r.checked.add(c);
            try {
                byte[] rom = Bps.source(file, info);
                c.matches = true;
                r.chosen = e;
                r.rom = rom;
                r.headered = c.headered;
                return r;
            } catch (Bps.BpsException notIt) {
                // keep looking
            }
        }
        return r;
    }

    /** "a (n bytes, CRC32 x); b (...)" for messages. */
    public static String describe(Result r) {
        StringBuilder s = new StringBuilder();
        for (Checked c : r.checked) s.append(s.length() > 0 ? "; " : "").append(c);
        return s.toString();
    }
}
