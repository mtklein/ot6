# Contributing to OT6

[docs/TESTING.md](docs/TESTING.md) is the testing policy: how evidence is
gathered and what counts as play. It supersedes older testing-method
restrictions in session memory, coordinator prompts, comments, and
historical documents. Read it before changing or evaluating tests.

[docs/guidelines.md](docs/guidelines.md) is the owner's standing guidance
on playing, designing, testing and releasing OT6. Read it before planning
work.

## Commits and pushes

Contributors may commit to `main` and push to GitHub as they judge
appropriate; "more likely to help than harm" is sufficient. Use relevant,
proportionate checks rather than full release qualification or a
multi-model review for every change. Preserve unrelated work and never
rewrite published history. Release claims still need evidence appropriate
to what they claim. A release's play is replayed under the
release's own library: `ninja release` fails while any generated state was
played under other library halves, and the remedy is a dated line in
`tools/tests/replay.txt` and `ninja` ([TESTING.md](docs/TESTING.md#what-each-build-target-counts-as)).

Keep `main` on GitHub current: push after every landing, including while a
release is being qualified (agent worktrees branch from it).

## Shared machines

Several agents run on the same machines at once. Stop only what you
started: by PID, or with a pattern that contains your own tree's path
(`pkill -f "$HOME/work/<your-tree>/"`), never a bare command line such as
`pkill -f "ninja -k 0"`, which kills every agent's build (2026-10-07: one
agent's pattern killed another's final qualification). A pattern run over
ssh also matches the ssh command itself; put it in a script. Take emulators
through `live.py --place` and never start more than you claimed; run.sh's
slot limit is the ceiling, not a target. Open few ssh connections (reuse
one session for a batch of commands): a flood of them can make a machine's
sshd refuse new connections.

## Release notes as you go

A change a player would notice adds its line to
[docs/release-notes-next.md](docs/release-notes-next.md) in the same commit,
written for players ([guidelines](docs/guidelines.md#releases-and-the-repository)),
with the test or log line behind it in the commit message. At release the
file becomes `docs/release-notes-vX.Y.md`.
