package io.github.mtklein.ot6patcher;

import java.util.zip.CRC32;

/**
 * BPS patches (byuu's format, what flips --create --bps writes): reading the
 * header and footer, and applying one.  Plain Java with no Android
 * dependencies, so android/test/BpsTest.java runs it on the host JVM.
 */
public final class Bps {
    private Bps() {}

    /** Any refusal: a malformed or corrupted patch, or the wrong source. */
    public static final class BpsException extends Exception {
        private static final long serialVersionUID = 1L;

        BpsException(String message) { super(message); }
    }

    /** What a patch says about itself; read() has already checked its CRC. */
    public static final class Info {
        public long sourceSize, targetSize;
        public int sourceCrc, targetCrc, patchCrc;
        public String metadata;
        int actionsStart;   // offset of the first action
    }

    /** SNES copier headers are 512 bytes in front of the ROM image. */
    public static final int COPIER_HEADER = 512;

    public static int crc32(byte[] b, int off, int len) {
        CRC32 c = new CRC32();
        c.update(b, off, len);
        return (int) c.getValue();
    }

    public static int crc32(byte[] b) { return crc32(b, 0, b.length); }

    public static String hex(int crc) { return String.format("%08x", crc); }

    private static int le32(byte[] b, int at) {
        return (b[at] & 0xff) | (b[at + 1] & 0xff) << 8
             | (b[at + 2] & 0xff) << 16 | (b[at + 3] & 0xff) << 24;
    }

    /** The format's variable-length number; pos[0] advances past it. */
    private static long varint(byte[] p, int[] pos, int end) throws BpsException {
        long data = 0, shift = 1;
        while (true) {
            if (pos[0] >= end) throw new BpsException("patch ends inside a number");
            int x = p[pos[0]++] & 0xff;
            data += (x & 0x7f) * shift;
            if ((x & 0x80) != 0) return data;
            shift <<= 7;
            data += shift;
            if (shift > (1L << 42)) throw new BpsException("number too large in patch");
        }
    }

    /** Parses the header and footer and checks the patch's own CRC32. */
    public static Info read(byte[] patch) throws BpsException {
        if (patch.length < 4 + 3 + 12 || patch[0] != 'B' || patch[1] != 'P'
                || patch[2] != 'S' || patch[3] != '1')
            throw new BpsException("not a BPS patch");
        int end = patch.length - 12;
        Info info = new Info();
        info.sourceCrc = le32(patch, end);
        info.targetCrc = le32(patch, end + 4);
        info.patchCrc = le32(patch, end + 8);
        int actual = crc32(patch, 0, patch.length - 4);
        if (actual != info.patchCrc)
            throw new BpsException("patch is corrupted: its CRC32 is " + hex(actual)
                    + ", its footer says " + hex(info.patchCrc));
        int[] pos = {4};
        info.sourceSize = varint(patch, pos, end);
        info.targetSize = varint(patch, pos, end);
        long metaSize = varint(patch, pos, end);
        if (metaSize > end - pos[0]) throw new BpsException("metadata runs past the patch");
        info.metadata = new String(patch, pos[0], (int) metaSize,
                java.nio.charset.StandardCharsets.UTF_8);
        pos[0] += (int) metaSize;
        info.actionsStart = pos[0];
        if (info.sourceSize > Integer.MAX_VALUE || info.targetSize > Integer.MAX_VALUE)
            throw new BpsException("patch sizes too large");
        return info;
    }

    /**
     * The ROM image the patch's source CRC names, from a file's bytes: the
     * file itself, or the file minus a 512-byte copier header.  Throws with
     * what was found when neither matches.
     */
    public static byte[] source(byte[] file, Info info) throws BpsException {
        if (file.length == info.sourceSize && crc32(file) == info.sourceCrc) return file;
        if (file.length == info.sourceSize + COPIER_HEADER
                && crc32(file, COPIER_HEADER, file.length - COPIER_HEADER) == info.sourceCrc) {
            byte[] rom = new byte[(int) info.sourceSize];
            System.arraycopy(file, COPIER_HEADER, rom, 0, rom.length);
            return rom;
        }
        throw new BpsException("wrong ROM: the patch expects " + info.sourceSize
                + " bytes with CRC32 " + hex(info.sourceCrc) + "; this file is "
                + file.length + " bytes with CRC32 " + hex(crc32(file)));
    }

    /** Whether a file is the patch's source with a copier header in front. */
    public static boolean headered(byte[] file, Info info) {
        return file.length == info.sourceSize + COPIER_HEADER
            && crc32(file, COPIER_HEADER, file.length - COPIER_HEADER) == info.sourceCrc;
    }

    /** Applies the patch to an exact source image; checks both CRCs. */
    public static byte[] apply(byte[] patch, byte[] source) throws BpsException {
        Info info = read(patch);
        if (source.length != info.sourceSize || crc32(source) != info.sourceCrc)
            throw new BpsException("wrong source: the patch expects " + info.sourceSize
                    + " bytes with CRC32 " + hex(info.sourceCrc) + ", got " + source.length
                    + " bytes with CRC32 " + hex(crc32(source)));
        int end = patch.length - 12;
        byte[] target = new byte[(int) info.targetSize];
        int[] pos = {info.actionsStart};
        int out = 0;
        long sourceRel = 0, targetRel = 0;
        while (pos[0] < end) {
            long data = varint(patch, pos, end);
            int command = (int) (data & 3);
            long length = (data >> 2) + 1;
            if (length > target.length - out) throw new BpsException("patch writes past the target");
            int n = (int) length;
            switch (command) {
                case 0:  // SourceRead
                    if (out + n > source.length) throw new BpsException("SourceRead past the source");
                    System.arraycopy(source, out, target, out, n);
                    out += n;
                    break;
                case 1:  // TargetRead
                    if (n > end - pos[0]) throw new BpsException("TargetRead past the patch");
                    System.arraycopy(patch, pos[0], target, out, n);
                    pos[0] += n;
                    out += n;
                    break;
                case 2: {  // SourceCopy
                    long d = varint(patch, pos, end);
                    sourceRel += ((d & 1) != 0 ? -1 : 1) * (d >> 1);
                    if (sourceRel < 0 || sourceRel + n > source.length)
                        throw new BpsException("SourceCopy outside the source");
                    System.arraycopy(source, (int) sourceRel, target, out, n);
                    sourceRel += n;
                    out += n;
                    break;
                }
                default: {  // TargetCopy: may overlap its own output, so byte by byte
                    long d = varint(patch, pos, end);
                    targetRel += ((d & 1) != 0 ? -1 : 1) * (d >> 1);
                    if (targetRel < 0 || targetRel >= out)
                        throw new BpsException("TargetCopy outside the target written so far");
                    for (int i = 0; i < n; i++) target[out++] = target[(int) targetRel++];
                    break;
                }
            }
        }
        if (out != target.length)
            throw new BpsException("patch wrote " + out + " of " + target.length + " bytes");
        int crc = crc32(target);
        if (crc != info.targetCrc)
            throw new BpsException("patched ROM has CRC32 " + hex(crc)
                    + ", the patch says " + hex(info.targetCrc));
        return target;
    }

    /** Offset of the first TargetRead payload byte, or -1 (for the tests). */
    static int firstTargetReadPayload(byte[] patch) throws BpsException {
        Info info = read(patch);
        int end = patch.length - 12;
        int[] pos = {info.actionsStart};
        while (pos[0] < end) {
            long data = varint(patch, pos, end);
            int command = (int) (data & 3);
            if (command == 1) return pos[0];
            if (command >= 2) varint(patch, pos, end);
        }
        return -1;
    }
}
