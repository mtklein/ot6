package io.github.mtklein.ot6patcher;

import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.Arrays;

/**
 * Host-side check of the app's BPS code on the real patch:
 *   java BpsTest <base rom> <ot6 .bps> <patched rom the repo built>
 * The patch applied to the base ROM must give exactly the repo's patched
 * ROM, also through a 512-byte copier header; a corrupted patch (caught by
 * its own CRC, and with that CRC refreshed, by the target CRC), a wrong
 * source ROM and a short one must each be refused.
 */
public final class BpsTest {
    static int failures = 0, passes = 0;

    static void pass(String what) { passes++; System.out.println("PASS: " + what); }
    static void fail(String what) { failures++; System.out.println("FAIL: " + what); }

    interface Body { void run() throws Exception; }

    /** A negative control: body must throw a BpsException naming `expect`. */
    static void refuses(String what, String expect, Body body) {
        try {
            body.run();
            fail(what + ": accepted");
        } catch (Bps.BpsException e) {
            if (e.getMessage().contains(expect)) pass(what + ": refused (" + e.getMessage() + ")");
            else fail(what + ": refused for the wrong reason (" + e.getMessage() + ")");
        } catch (Exception e) {
            fail(what + ": " + e);
        }
    }

    /** A folder entry whose bytes count their reads. */
    static final class File {
        final RomScan.Entry entry;
        int reads;

        File(String name, final byte[] data) {
            this(name, data.length, data);
        }

        File(String name, long size, final byte[] data) {
            entry = new RomScan.Entry(name, size, new RomScan.Bytes() {
                @Override public byte[] read() { reads++; return data; }
            }, null);
        }
    }

    static RomScan.Result scan(File... files) throws Exception {
        java.util.List<RomScan.Entry> list = new java.util.ArrayList<>();
        for (File f : files) list.add(f.entry);
        return RomScan.choose(list, scanInfo);
    }

    static Bps.Info scanInfo;

    /** The folder scan that finds the player's ROM (RomScan). */
    static void scans(byte[] base, byte[] headered, byte[] wrong, byte[] shortRom, byte[] want,
                      Bps.Info info) throws Exception {
        scanInfo = info;
        // the ROM among other files; a wrong-size file is never read
        File notes = new File("notes.txt", new byte[100]);
        File big = new File("Chrono Trigger (USA).sfc", new byte[4194304]);
        File rom = new File("Final Fantasy III (USA).sfc", base);
        RomScan.Result r = scan(notes, big, rom);
        if (r.chosen == rom.entry && !r.headered && Arrays.equals(r.rom, base)
                && notes.reads == 0 && big.reads == 0 && r.skipped == 2)
            pass("scan picks the ROM by CRC32 and reads no wrong-size file (" + RomScan.describe(r) + ")");
        else
            fail("scan: chose " + (r.chosen == null ? "nothing" : r.chosen.name) + ", read notes "
                    + notes.reads + "x and the 4 MB file " + big.reads + "x");

        // a copier-headered copy matches, and gives the bare ROM image
        File smc = new File("ff3.smc", headered);
        r = scan(smc);
        if (r.chosen == smc.entry && r.headered && Arrays.equals(r.rom, base))
            pass("scan matches a copy with a copier header (" + RomScan.describe(r) + ")");
        else
            fail("scan did not match the copier-headered copy");

        // OT6.sfc is never a candidate, even holding the very bytes of the ROM
        File out = new File("OT6.sfc", base);
        r = scan(out);
        if (r.chosen == null && out.reads == 0 && r.skipped == 1)
            pass("scan skips OT6.sfc unread, even when it holds the source ROM");
        else
            fail("scan considered OT6.sfc (read " + out.reads + "x)");

        File lower = new File("ot6.SFC", base), tmp = new File("OT6.sfc.tmp", base);
        r = scan(lower, tmp);
        if (r.chosen == null && lower.reads == 0 && tmp.reads == 0)
            pass("scan skips ot6.SFC and OT6.sfc.tmp too (any case)");
        else
            fail("scan considered a differently cased OT6.sfc or its temporary");

        String[] strays = {"OT6.bps", "ot6.IPS", "OT6.ups", "OT6.xdelta", "OT6.ips1", "OT6.bps9"};
        String[] fine = {"OT6.sfc", "OT6.ips10", "OT6.bps0", "Final Fantasy III (USA).bps", "OT6.zip"};
        boolean ok = true;
        for (String s : strays) ok &= RomScan.isSoftPatch(s);
        for (String s : fine) ok &= !RomScan.isSoftPatch(s);
        if (ok) pass("soft-patches RetroArch would apply to OT6.sfc are recognised, others not");
        else fail("soft-patch recognition is wrong");

        // no match: everything checked is listed, nothing chosen
        File bad = new File("wrong.sfc", wrong);
        File cut = new File("short.sfc", shortRom.length, shortRom);
        File ot6 = new File("OT6 copy.sfc", want);
        r = scan(bad, cut, ot6);
        if (r.chosen == null && r.checked.size() == 1 && r.checked.get(0).name.equals("wrong.sfc")
                && !r.checked.get(0).matches && cut.reads == 0 && ot6.reads == 0)
            pass("scan with no match chooses nothing and lists what it read (" + RomScan.describe(r) + ")");
        else
            fail("scan with no match: chose " + (r.chosen == null ? "nothing" : r.chosen.name)
                    + ", checked " + RomScan.describe(r));

        // a size that lies (the listing says ROM-sized, the bytes aren't): read, refused
        File liar = new File("liar.sfc", base.length, shortRom);
        r = scan(liar);
        if (r.chosen == null && liar.reads == 1)
            pass("scan refuses a file whose bytes don't match its listed size");
        else
            fail("scan accepted a file whose bytes don't match its listed size");
    }

    static void putLe32(byte[] b, int at, int v) {
        for (int i = 0; i < 4; i++) b[at + i] = (byte) (v >>> (8 * i));
    }

    public static void main(String[] args) throws Exception {
        if (args.length != 3) {
            System.err.println("usage: BpsTest <base rom> <patch.bps> <expected patched rom>");
            System.exit(2);
        }
        final byte[] base = Files.readAllBytes(Paths.get(args[0]));
        final byte[] patch = Files.readAllBytes(Paths.get(args[1]));
        final byte[] want = Files.readAllBytes(Paths.get(args[2]));

        final Bps.Info info = Bps.read(patch);
        System.out.println("patch: " + patch.length + " bytes, source " + info.sourceSize
                + " bytes crc32 " + Bps.hex(info.sourceCrc) + ", target " + info.targetSize
                + " bytes crc32 " + Bps.hex(info.targetCrc));

        byte[] got = Bps.apply(patch, Bps.source(base, info));
        if (Arrays.equals(got, want))
            pass("patch on the base ROM gives " + args[2] + " exactly (" + got.length
                    + " bytes, crc32 " + Bps.hex(Bps.crc32(got)) + ")");
        else
            fail("patch on the base ROM differs from " + args[2]);

        byte[] headered = new byte[base.length + Bps.COPIER_HEADER];
        System.arraycopy(base, 0, headered, Bps.COPIER_HEADER, base.length);
        if (Bps.headered(headered, info) && Arrays.equals(Bps.apply(patch, Bps.source(headered, info)), want))
            pass("a 512-byte copier header is recognised and stripped");
        else
            fail("a 512-byte copier header was not handled");

        // Negative controls.
        final byte[] flipped = patch.clone();
        flipped[patch.length / 2] ^= 0x01;
        refuses("patch with one bit flipped", "patch is corrupted", () -> Bps.apply(flipped, base));

        // The same kind of damage with the patch CRC recomputed, so only the
        // target CRC check stands between it and a bad ROM.
        final byte[] forged = patch.clone();
        int at = Bps.firstTargetReadPayload(forged);
        if (at < 0) fail("patch has no TargetRead to corrupt");
        else {
            forged[at] ^= 0x01;
            putLe32(forged, forged.length - 4, Bps.crc32(forged, 0, forged.length - 4));
            refuses("patch with a payload bit flipped and its own CRC refreshed",
                    "patched ROM has CRC32", () -> Bps.apply(forged, base));
        }

        final byte[] wrong = base.clone();
        wrong[0x10000] ^= 0x01;
        refuses("source ROM with one bit flipped", "wrong ROM", () -> Bps.source(wrong, info));
        refuses("source ROM with one bit flipped, straight to apply", "wrong source",
                () -> Bps.apply(patch, wrong));
        final byte[] shortRom = Arrays.copyOf(base, base.length - 1);
        refuses("source ROM one byte short", "wrong ROM", () -> Bps.source(shortRom, info));
        refuses("the patched ROM offered as the source", "wrong ROM", () -> Bps.source(want, info));

        scans(base, headered, wrong, shortRom, want, info);

        System.out.println("android_bps: " + passes + " passed, " + failures + " failed");
        System.exit(failures == 0 ? 0 : 1);
    }
}
