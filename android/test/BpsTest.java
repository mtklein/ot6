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

        System.out.println("android_bps: " + passes + " passed, " + failures + " failed");
        System.exit(failures == 0 ? 0 : 1);
    }
}
