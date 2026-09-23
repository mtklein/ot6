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
to what they claim.

Keep `main` on GitHub current: push after every landing, including while a
release is being qualified (agent worktrees branch from it).

## Release notes as you go

A change a player would notice adds its line to
[docs/release-notes-next.md](docs/release-notes-next.md) in the same commit,
written for players ([guidelines](docs/guidelines.md#releases-and-the-repository)),
with the test or log line behind it in the commit message. At release the
file becomes `docs/release-notes-vX.Y.md`.
