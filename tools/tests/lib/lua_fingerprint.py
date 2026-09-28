#!/usr/bin/env python3
"""lua_fingerprint.py: the one definition of what a Lua source's provenance
hash covers (issue #247).

A generator's stamp binds the play that reached a fixture.  A comment or a
re-indent changes no play, so the hash is taken over the file's Lua tokens,
not its bytes: comments (`--` line comments, `--[[ ]]` / `--[==[ ]==]` long
comments) and whitespace are dropped, and every other token is kept verbatim,
one per line.  String literals are tokens, so a `--` or a run of spaces
inside "...", '...' or [[...]] / [==[...]==] is kept exactly.  The output is
itself an equivalent Lua program, so two sources that normalize alike differ
only in comments and whitespace.

One kind of comment is kept: a harness directive, a line comment of the
form `-- OT6_NAME: value` (run.sh reads `-- OT6_CHECKPOINT_LAYOUT:` from the
composed script), because it changes what a run does.

savestate_stamp.sh (the `generate` edge's stamps) and compose.py
(--check-states, embed-time checks) both reach this file, and the ninja
graph's generator copies use `copy-if-changed` below, so the stamp checker
and the build schedule agree on what counts as a change.

Usage:
    lua_fingerprint.py normalize FILE        # the token stream, to stdout
    lua_fingerprint.py digest PREFIX FILE... # sha256(PREFIX\\n ++ each file),
                                             # a .lua file as its token stream
    lua_fingerprint.py hash FILE             # sha256 of one file's token stream
    lua_fingerprint.py copy-if-changed SRC DST
        # ninja's copy for a generator: DST gets SRC's bytes, but keeps its
        # mtime when the token streams agree, so restat prunes a comment-only
        # edit and a code edit re-runs everything downstream.
"""

import hashlib
import os
import re
import shutil
import sys

# Order matters: a long comment before a line comment, strings before names
# and operators, a number before the `.` operator.
_TOKEN = re.compile(r"""
    (?P<ws>[ \t\r\n\f\v]+)
  | (?P<longcomment>--\[(?P<lceq>=*)\[.*?\](?P=lceq)\])
  | (?P<linecomment>--[^\n]*)
  | (?P<longstring>\[(?P<lseq>=*)\[.*?\](?P=lseq)\])
  | (?P<string>"(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*')
  | (?P<name>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<number>0[xX][0-9a-fA-F]*(?:\.[0-9a-fA-F]*)?(?:[pP][+-]?[0-9]+)?
              |(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?)
  | (?P<op>\.\.\.|\.\.|==|~=|<=|>=|//|::|<<|>>|[-+*/%^\#&~|<>=(){}\[\];:,.])
""", re.S | re.X)

# A line comment that is a harness directive, kept as a token.
_DIRECTIVE = re.compile(r"--[ \t]*OT6_[A-Z0-9_]+:")


class LuaTokenError(ValueError):
    pass


def tokens(text):
    """The Lua tokens of `text` (a str), comments and whitespace dropped,
    directive comments kept (right-trimmed).  An unlexable character or an
    unterminated string is an error, never a silent skip: a stripper that
    guessed could hash two different programs alike."""
    out = []
    pos, n = 0, len(text)
    # Lua skips a first line that starts with '#' (a shebang).
    if text.startswith("#"):
        nl = text.find("\n")
        out.append(text[:nl if nl >= 0 else n].rstrip())
        pos = nl if nl >= 0 else n
    match = _TOKEN.match
    while pos < n:
        m = match(text, pos)
        if not m:
            line = text.count("\n", 0, pos) + 1
            raise LuaTokenError(
                f"line {line}: cannot lex {text[pos:pos + 20]!r} (an "
                f"unterminated string or a character outside Lua's syntax)")
        kind = m.lastgroup
        if kind in ("lceq", "lseq"):          # a named sub-group; find the outer
            kind = "longcomment" if m.group("longcomment") else "longstring"
        tok = m.group(0)
        if kind == "linecomment":
            if _DIRECTIVE.match(tok):
                out.append(tok.rstrip())
        elif kind not in ("ws", "longcomment"):
            out.append(tok)
        pos = m.end()
    return out


def normalize_bytes(data):
    """The token stream of a Lua source, one token per line, as bytes.
    Bytes map 1:1 through latin-1, so any encoding in a string or comment
    round-trips unchanged."""
    toks = tokens(data.decode("latin-1"))
    return ("\n".join(toks) + "\n").encode("latin-1")


def is_lua(path):
    return str(path).endswith(".lua")


def content(path):
    """What a file contributes to a digest: a .lua file's token stream, any
    other file's bytes (a checkpoint manifest or payload)."""
    with open(path, "rb") as f:
        data = f.read()
    return normalize_bytes(data) if is_lua(path) else data


def digest(prefix, paths):
    h = hashlib.sha256()
    h.update(prefix.encode() + b"\n")
    for p in paths:
        h.update(content(p))
    return h.hexdigest()


def filehash(path):
    return hashlib.sha256(content(path)).hexdigest()


def copy_if_changed(src, dst):
    """cmp -s || cp, except that a Lua source whose token stream did not
    move keeps DST's old mtime (so ninja's restat sees no change) while DST
    still takes SRC's bytes."""
    with open(src, "rb") as f:
        new = f.read()
    try:
        with open(dst, "rb") as f:
            old = f.read()
        st = os.stat(dst)
    except FileNotFoundError:
        old, st = None, None
    if old == new:
        return
    os.makedirs(os.path.dirname(dst) or ".", exist_ok=True)
    same = (old is not None and is_lua(src)
            and normalize_bytes(old) == normalize_bytes(new))
    tmp = dst + ".tmp"
    with open(tmp, "wb") as f:
        f.write(new)
    shutil.copymode(src, tmp)
    os.replace(tmp, dst)
    if same:
        os.utime(dst, ns=(st.st_atime_ns, st.st_mtime_ns))


def main(argv):
    try:
        if len(argv) == 2 and argv[0] == "normalize":
            sys.stdout.buffer.write(content(argv[1]))
        elif len(argv) >= 2 and argv[0] == "digest":
            print(digest(argv[1], argv[2:]))
        elif len(argv) == 2 and argv[0] == "hash":
            print(filehash(argv[1]))
        elif len(argv) == 3 and argv[0] == "copy-if-changed":
            copy_if_changed(argv[1], argv[2])
        else:
            print(__doc__.split("Usage:")[1], file=sys.stderr)
            return 2
    except (OSError, LuaTokenError) as exc:
        print(f"lua_fingerprint: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
