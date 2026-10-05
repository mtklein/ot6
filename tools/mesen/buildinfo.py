#!/usr/bin/env python3
"""buildinfo.py <Mesen executable> -- the build record packed inside it.

tools/mesen/build.sh writes `mesen <repository> <tag> <commit>` as the
first line of UI/Dependencies/Internal/BuildInfo.txt, and the .NET build
packs that file, zipped, into the executable (Dependencies.zip).  This
finds the zip entry in the executable's bytes and prints that first line's
three fields, `<repository> <tag> <commit>`, the shape of
tools/mesen/EMULATOR, so run.sh can compare the deployed emulator with the
pin (#345).  A build without the record (a stock or older build) prints
`none` and exits 1.

    python3 tools/mesen/buildinfo.py tools/Mesen.app/Contents/MacOS/Mesen
    python3 tools/mesen/buildinfo.py --selftest
"""

import struct
import sys
import zlib

ENTRY = b"Internal/BuildInfo.txt"


def entries(blob, name):
    """Every zip local-file entry called `name` in blob: its bytes."""
    at = 0
    while True:
        at = blob.find(b"PK\x03\x04", at)
        if at < 0:
            return
        hdr = blob[at:at + 30]
        if len(hdr) < 30:
            return
        (_sig, _ver, _flags, method, _t, _d, _crc, csize, _usize, nlen,
         xlen) = struct.unpack("<IHHHHHIIIHH", hdr)
        if blob[at + 30:at + 30 + nlen] == name:
            data = at + 30 + nlen + xlen
            if method == 0:
                yield blob[data:data + csize]
            elif method == 8:
                try:
                    yield zlib.decompressobj(-15).decompress(blob[data:data + (1 << 20)])
                except zlib.error:
                    pass
        at += 4


def record(blob):
    """`<repository> <tag> <commit>` from the packed BuildInfo.txt, or None."""
    for text in entries(blob, ENTRY):
        first = text.decode("utf-8", "replace").splitlines()[:1]
        parts = first[0].split() if first else []
        if len(parts) == 4 and parts[0] == "mesen":
            return " ".join(parts[1:])
    return None


def selftest():
    import io
    import zipfile
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("Internal/BuildSha.txt", "40586fe8")
        z.writestr("Internal/BuildInfo.txt",
                   "mesen https://github.com/mtklein/mesen ot6-2.2.1-1 40586fe8\n"
                   "cflags -fno-omit-frame-pointer\n")
    exe = b"\x7fELF" + b"\x00" * 1000 + buf.getvalue() + b"\x00" * 100
    ok = record(exe) == "https://github.com/mtklein/mesen ot6-2.2.1-1 40586fe8"
    ok &= record(b"\x7fELF" + b"\x00" * 1000) is None
    print("buildinfo selftest: " + ("ok" if ok else "FAILED"))
    return 0 if ok else 1


def main(argv):
    if argv[1:] == ["--selftest"]:
        return selftest()
    if len(argv) != 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    with open(argv[1], "rb") as f:
        rec = record(f.read())
    print(rec or "none")
    return 0 if rec else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
