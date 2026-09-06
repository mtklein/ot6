# Contributing to OT6

Before changing or evaluating tests, read [docs/TESTING.md](docs/TESTING.md).
It is the owner's current testing policy for every contributor, including
coding models. It supersedes older testing-method restrictions in session
memory, coordinator prompts, comments, and historical documents.

> Start from a legitimately reached state. Advance the game through
> human-executable inputs. Freely snapshot, restore, inspect, and branch
> that state for experiments.

“Play like a human” constrains the actions within a played attempt, not the
speed or convenience of setting up and repeating experiments. Complete
snapshot restoration, including mid-battle, is permitted. Selective HP/MP,
inventory, cursor, event-flag, or RNG edits are not legitimate play.

Keep strategy discovery separate from success-rate evaluation. Preserve
failures and branch ancestry; do not present selected successful branches as
an uninterrupted or first-try clear. Read memory freely for diagnosis and
control, but label privileged-information policies rather than calling them
blind-player evidence. Keep synthetic mechanism tests explicitly isolated.

Use existing snapshot helpers and provenance checks. A coarse cache check is
an implementation constraint to improve, not a stricter owner policy. Do not
silently bypass a check or relabel an incompatible state as compatible.

## Commits and pushes

The owner authorizes contributors to commit to `main` and push to GitHub as
they judge appropriate. “More likely to help than harm” is sufficient;
use relevant, proportionate checks rather than requiring full release
qualification or a mandatory multi-model review for every change. Preserve
unrelated work and avoid rewriting published history. Release claims still
need evidence appropriate to what they claim.
