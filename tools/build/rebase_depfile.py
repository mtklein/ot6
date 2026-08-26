#!/usr/bin/env python3
"""Rebase a ca65 depfile's paths onto the repo root.

ca65 runs with cwd=ff6/ (its sources use ff6-relative .include/.incbin
paths), so the depfile it writes says `obj/battle_en.o: src/... include/...`.
ninja interprets depfile paths relative to the build.ninja directory (the
repo root), so every relative path here must gain the `ff6/` prefix or the
recorded deps point at files that do not exist and the edge's dependency
tracking silently decays to the explicit inputs alone.

Handles the `\\`-continued multi-line form ca65 can emit by tokenizing the
whole file.  Absolute paths pass through untouched.
"""
import sys


def main(prefix, path):
    with open(path) as f:
        text = f.read()
    # target: deps -- split once on the first ':' (no Windows drive letters
    # here; ca65 on this host writes POSIX paths)
    target, _, deps = text.partition(":")
    toks = deps.replace("\\\n", " ").split()

    def rebase(p):
        return p if p.startswith("/") else f"{prefix}/{p}"

    out = f"{rebase(target.strip())}: " + " ".join(rebase(t) for t in toks) + "\n"
    with open(path, "w") as f:
        f.write(out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))
