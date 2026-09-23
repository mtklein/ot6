#!/usr/bin/env python3
"""retain_evidence.py -- keep a worktree's cited evidence before it is
removed (#222).

Merge messages and design docs quote lines out of logs under
`build/attempts/`, `build/lab/` and `build/sweeps/`.  Those trees live in
the agent worktree the work was done in, so `git worktree remove` takes
them with it and every citation stops resolving.  Run this from the
worktree, or name it, BEFORE removing it:

    python3 tools/retain_evidence.py <worktree> <branch> [options]

Each of the three trees is copied into the main tree under
`build/attempts/<branch>/<tree>/`, relative paths preserved:

    <worktree>/build/lab/zozo-grind/aggregate.txt
        -> <main>/build/attempts/wt/zozo-grind/lab/zozo-grind/aggregate.txt

TEXT EVIDENCE ONLY.  Logs, tables, traces, the one-off generator copies a
lab ran and the failure frames a run names are evidence; savestates
(`*.mss`), ROMs (`*.sfc`), battery saves and archives are bulk that the
graph regenerates.  The copy takes the extensions in KEEP_EXT (plus
screenshots under --max-bytes) and skips everything else, printing a
per-extension tally of what it left so the skip is visible rather than
silent.

SAFE TO RUN TWICE.  A destination file whose bytes already match is
counted as already retained and not rewritten.  A destination file whose
bytes DIFFER is a conflict: nothing at all is copied, the conflicting
paths are listed, and the exit is 1 unless `--force` says to overwrite
them.  `--dry-run` plans and prints without writing.

Options: `--dest DIR` (default: the first worktree git lists, i.e. the
main checkout), `--max-bytes N` (screenshot cap, default 4 MiB),
`--force`, `--dry-run`, `--selftest`.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import shutil
import subprocess
import sys

# The three evidence trees, in the order they are reported.
TREES = ("attempts", "lab", "sweeps")

# Text evidence: run logs, tables, traces, aggregates, the JSON a probe
# dumps, and the one-off script copies a lab actually ran.
KEEP_EXT = {
    ".log", ".txt", ".tsv", ".csv", ".json", ".jsonl", ".out", ".err",
    ".md", ".lua", ".py", ".sh", ".ninja", ".diff", ".patch", ".stamp",
    ".yaml", ".yml", ".ini", ".cfg",
    # A run's captured console.  This one was missing on the first real use
    # and the tool skipped 29 of them out of a branch whose report cited
    # them by name (build/attempts/steal_2.console, waiver_gate_probe...),
    # which is precisely the failure #222 exists to prevent.  The lesson is
    # that the filter is a promise about citations, so a suffix a report can
    # cite belongs here rather than in the skip tally.
    ".console", ".stdout", ".stderr",
}
# Screenshots are evidence too (a FAIL line names its frame), but they are
# binary and unbounded, so they ride the size cap.
CAPPED_EXT = {".png"}
DEFAULT_MAX_BYTES = 4 << 20


def human(n: int) -> str:
    """A byte count as the report prints it."""
    x = float(n)
    for unit in ("B", "KiB", "MiB", "GiB"):
        if x < 1024 or unit == "GiB":
            return f"{int(x)} B" if unit == "B" else f"{x:.1f} {unit}"
        x /= 1024.0
    raise AssertionError("unreachable")


def sha256(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def same_bytes(a: str, b: str) -> bool:
    """True if two files hold the same bytes (size first, then hash)."""
    if os.path.getsize(a) != os.path.getsize(b):
        return False
    return sha256(a) == sha256(b)


def main_tree(start: str) -> str:
    """The main checkout: the first worktree git lists for this repo."""
    out = subprocess.run(["git", "-C", start, "worktree", "list", "--porcelain"],
                         capture_output=True, text=True)
    if out.returncode != 0:
        raise SystemExit(f"not a git worktree: {start}\n{out.stderr.strip()}")
    for line in out.stdout.splitlines():
        if line.startswith("worktree "):
            return line[len("worktree "):].strip()
    raise SystemExit(f"git listed no worktree for {start}")


def keep(name: str, size: int, max_bytes: int) -> tuple[bool, str]:
    """Is this file text evidence?  Returns (keep, reason-if-not)."""
    ext = os.path.splitext(name)[1].lower()
    if ext in KEEP_EXT:
        return True, ""
    if ext in CAPPED_EXT:
        if size <= max_bytes:
            return True, ""
        return False, f"{ext} over --max-bytes"
    return False, ext or "(no extension)"


def plan(worktree: str, branch: str, dest_root: str, max_bytes: int):
    """Walk the three trees and decide, per file, copy / same / skip.

    Returns (copies, sames, conflicts, skipped) where copies and conflicts
    are (src, dst, size) and skipped is a reason -> count tally.
    """
    copies, sames, conflicts = [], [], []
    skipped: dict[str, int] = {}
    for tree in TREES:
        src_root = os.path.join(worktree, "build", tree)
        if not os.path.isdir(src_root):
            continue
        if os.path.islink(src_root):
            # worktree-setup.sh links build/attempts to the main tree's, so
            # its evidence is already there; walking it would copy the main
            # tree's evidence into itself.
            continue
        out_root = os.path.join(dest_root, "build", "attempts", branch, tree)
        for dirpath, dirnames, filenames in os.walk(src_root):
            dirnames.sort()
            for name in sorted(filenames):
                src = os.path.join(dirpath, name)
                if os.path.islink(src) or not os.path.isfile(src):
                    skipped["(symlink or special)"] = \
                        skipped.get("(symlink or special)", 0) + 1
                    continue
                size = os.path.getsize(src)
                ok, why = keep(name, size, max_bytes)
                if not ok:
                    skipped[why] = skipped.get(why, 0) + 1
                    continue
                rel = os.path.relpath(src, src_root)
                dst = os.path.join(out_root, rel)
                if os.path.exists(dst):
                    (sames if same_bytes(src, dst) else conflicts).append(
                        (src, dst, size))
                else:
                    copies.append((src, dst, size))
    return copies, sames, conflicts, skipped


def retain(worktree: str, branch: str, dest_root: str, *, max_bytes: int,
           force: bool, dry_run: bool, out=sys.stdout) -> int:
    """Copy one worktree's evidence.  Returns a process exit status."""
    worktree = os.path.realpath(worktree)
    dest_root = os.path.realpath(dest_root)
    if worktree == dest_root:
        print(f"refusing: {worktree} is the destination tree itself", file=out)
        return 2
    if branch.startswith("/") or os.path.pardir in branch.split("/"):
        print(f"refusing: unusable branch name {branch!r}", file=out)
        return 2
    have = [t for t in TREES if os.path.isdir(os.path.join(worktree, "build", t))
            and not os.path.islink(os.path.join(worktree, "build", t))]
    if not have:
        print(f"no build/{{{','.join(TREES)}}} in {worktree}; nothing to retain",
              file=out)
        return 0

    copies, sames, conflicts, skipped = plan(worktree, branch, dest_root,
                                             max_bytes)
    if conflicts and not force:
        print(f"refusing to clobber {len(conflicts)} differing file(s) under "
              f"build/attempts/{branch}/ (nothing was copied):", file=out)
        for _, dst, _ in conflicts:
            print(f"  {os.path.relpath(dst, dest_root)}", file=out)
        print("re-run with --force to overwrite them.", file=out)
        return 1

    todo = sorted(copies + (conflicts if force else []), key=lambda t: t[1])
    rels = [os.path.relpath(dst, dest_root) for _, dst, _ in todo]
    wide = max((len(r) for r in rels), default=0)
    total = 0
    for (src, dst, size), rel in zip(todo, rels):
        mark = "overwrite" if os.path.exists(dst) else "new"
        if not dry_run:
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy2(src, dst)
        print(f"  {rel:<{wide}}  {human(size):>9}  {mark}", file=out)
        total += size

    verb = "would copy" if dry_run else "copied"
    print(f"{verb} {len(todo)} file(s), {human(total)} into "
          f"{os.path.join(dest_root, 'build', 'attempts', branch)}"
          f" (trees: {', '.join(have)})", file=out)
    if sames:
        print(f"{len(sames)} file(s) already retained identically", file=out)
    if skipped:
        tally = ", ".join(f"{n} {why}"
                          for why, n in sorted(skipped.items(),
                                               key=lambda kv: (-kv[1], kv[0])))
        print(f"skipped {sum(skipped.values())} non-evidence file(s): {tally}",
              file=out)
    return 0


# ----------------------------------------------------------------- selftest --
def selftest() -> int:
    """Build a fake worktree in a temp dir and assert the four behaviours:
    what is copied, what is skipped, that a second run is a no-op, and that
    a differing file is refused without --force and taken with it."""
    import io
    import tempfile

    failures = []

    def check(cond, what):
        if not cond:
            failures.append(what)

    with tempfile.TemporaryDirectory() as tmp:
        wt = os.path.join(tmp, "wt")
        main = os.path.join(tmp, "main")
        files = {
            "build/attempts/zozo/run.log": b"attempt 1 FAILED\n",
            "build/attempts/zozo/shot.mss": b"\x00" * 4096,
            "build/lab/zozo-grind/aggregate.txt": b"policy n wins\n",
            "build/lab/zozo-grind/bake/bake.log": b"[west landing]\n",
            "build/sweeps/s-1/summary.tsv": b"seed\tverdict\n",
            "build/sweeps/s-1/ot6.sfc": b"\xff" * 2048,
            "build/sweeps/s-1/notes.zip": b"PK\x03\x04",
            "build/states/keepout.log": b"not an evidence tree\n",
        }
        for rel, data in files.items():
            path = os.path.join(wt, rel)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "wb") as f:
                f.write(data)
        os.makedirs(main, exist_ok=True)

        def run(**kw):
            buf = io.StringIO()
            rc = retain(wt, "wt/demo", main, max_bytes=DEFAULT_MAX_BYTES,
                        force=kw.get("force", False),
                        dry_run=kw.get("dry_run", False), out=buf)
            return rc, buf.getvalue()

        base = os.path.join(main, "build", "attempts", "wt", "demo")

        rc, _ = run(dry_run=True)
        check(rc == 0, "dry run exits 0")
        check(not os.path.exists(base), "dry run writes nothing")

        rc, text = run()
        check(rc == 0, "first run exits 0")
        for rel in ("attempts/zozo/run.log", "lab/zozo-grind/aggregate.txt",
                    "lab/zozo-grind/bake/bake.log", "sweeps/s-1/summary.tsv"):
            check(os.path.isfile(os.path.join(base, rel)), f"copied {rel}")
        for rel in ("attempts/zozo/shot.mss", "sweeps/s-1/ot6.sfc",
                    "sweeps/s-1/notes.zip"):
            check(not os.path.exists(os.path.join(base, rel)), f"skipped {rel}")
        check(not os.path.exists(os.path.join(base, "states")),
              "build/states is not an evidence tree")
        check("copied 4 file(s)" in text, f"reports 4 copies: {text!r}")
        check("skipped 3 non-evidence file(s)" in text,
              f"reports 3 skips: {text!r}")

        rc, text = run()
        check(rc == 0, "second run exits 0")
        check("copied 0 file(s)" in text, f"second run copies nothing: {text!r}")
        check("4 file(s) already retained identically" in text,
              f"second run reports 4 retained: {text!r}")

        with open(os.path.join(base, "attempts/zozo/run.log"), "wb") as f:
            f.write(b"tampered\n")
        rc, text = run()
        check(rc == 1, "a differing file is refused")
        check("attempts/zozo/run.log" in text, "the refusal names the file")
        with open(os.path.join(base, "attempts/zozo/run.log"), "rb") as f:
            check(f.read() == b"tampered\n", "the refusal copied nothing")

        rc, text = run(force=True)
        check(rc == 0, "--force exits 0")
        with open(os.path.join(base, "attempts/zozo/run.log"), "rb") as f:
            check(f.read() == b"attempt 1 FAILED\n", "--force overwrites")

        rc = retain(main, "wt/demo", main, max_bytes=DEFAULT_MAX_BYTES,
                    force=False, dry_run=True, out=io.StringIO())
        check(rc == 2, "the destination tree refuses itself")

    for f in failures:
        print(f"FAIL: {f}")
    print(f"retain_evidence selftest: {'FAIL' if failures else 'ok'}")
    return 1 if failures else 0


def main(argv=None) -> int:
    p = argparse.ArgumentParser(
        description="copy a worktree's build/attempts, build/lab and "
                    "build/sweeps evidence into the main tree under "
                    "build/attempts/<branch>/")
    p.add_argument("worktree", nargs="?", help="the worktree about to be removed")
    p.add_argument("branch", nargs="?", help="its branch, the name under "
                                             "build/attempts/ to file it as")
    p.add_argument("--dest", help="destination tree (default: the main checkout)")
    p.add_argument("--max-bytes", type=int, default=DEFAULT_MAX_BYTES,
                   help="per-file cap for screenshots (default 4 MiB)")
    p.add_argument("--force", action="store_true",
                   help="overwrite retained files whose bytes differ")
    p.add_argument("--dry-run", action="store_true", help="plan, write nothing")
    p.add_argument("--selftest", action="store_true")
    a = p.parse_args(argv)
    if a.selftest:
        return selftest()
    if not a.worktree or not a.branch:
        p.error("worktree and branch are required")
    dest = a.dest or main_tree(a.worktree)
    return retain(a.worktree, a.branch, dest, max_bytes=a.max_bytes,
                  force=a.force, dry_run=a.dry_run)


if __name__ == "__main__":
    sys.exit(main())
