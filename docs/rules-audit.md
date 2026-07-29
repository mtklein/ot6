# Every rule we've written down, ranked by what it actually costs

Written 2026-07-29 at the owner's request: *"I'm starting to think we have
written down too many rules and they're holding you back from doing
interesting work."*

This is my honest accounting, from a session that used nearly all of them.
"Constraining" here means **cost to doing interesting work**, not cost in
keystrokes. A rule that slows a task down but prevents a wrong answer is
cheap. A rule that stops a good idea from being attempted is expensive
even if it never fires.

I've marked each **KEEP / REVISE / CUT** with my recommendation. The
verdicts are mine to defend, not decisions — you asked for a list to go
through.

---

## Tier 1 — genuinely constraining. These shape what we can attempt.

### 1. Disjoint file ownership across parallel worktrees
*(HANDOFF working agreements)*

**The single biggest limit on throughput, and it bit repeatedly today.**
It forced the kit wave (#37, #38, #40) to *wait* for the battle-UI wave
purely because they touched the same files; it made me group issues by
file adjacency rather than by what made sense (#45 with #50, #46 with
#49); and it still produced a merge conflict when two agents allocated
adjacent bytes from the same free WRAM region and could not see each
other. Perfectly legitimate work sat idle for hours.

**REVISE.** The rule is doing a real job — two agents in one `build/`
genuinely collide, and that part is physics. But *file*-level exclusivity
is far stricter than the actual hazard, which is (a) the shared build
directory and (b) textual merge conflicts. Git merges disjoint hunks in
one file fine; I proved that today by handing two agents different procs
in `ot6_kits.asm` deliberately, and it worked. Proposal: keep worktree
isolation, drop file exclusivity to **"declare your hunks, expect to
merge"**, and let me resolve conflicts — which I did in ninety seconds
when it happened.

### 2. "Do not commit" *(agent-brief)*

Every agent's work funnels through me to land. That is a real
serialization point — six reports today each needed a review, a commit
message, a merge, and often a verification run before the next thing
could start.

**REVISE, carefully.** The rule exists because parallel worktrees were
once merged by hand and a stray commit made it worse. But the *value* I
add reviewing is real: I caught a fix that had never rendered the page it
fixed, screenshots that showed a still-broken layout, and a report whose
own numbers contradicted its conclusion. Proposal: let agents **commit on
their own branch** (they cannot push, and I still do every merge and
review the diff). That removes the message-writing serialization without
removing the review.

### 3. "Do not run `make frontier` / `frontier-test` / `release-test`"
*(agent-brief)*

Agents cannot fully verify their own work. Nearly every report today has
an "I could not establish" section whose real content is *"the fixture I
needed was stale and I was not allowed to re-mint it."* One agent burned
an hour proving a red test was not its fault.

**REVISE.** The rule protects a genuinely serial, hour-long resource. But
since #25/#30, the graph is content-addressed and re-mints in parallel
legs — a *targeted* `ninja <state>` is cheap and safe, and agents already
do it. Proposal: explicitly bless targeted re-mints (already de facto
true), keep the full chain mine, and add the recipe to the brief so
nobody rediscovers it. Two agents independently asked for exactly this.

### 4. "Vanilla's quirks stay" *(CONTRIBUTING)*

A design constraint that genuinely forecloses options — it is why we
cannot simply fix things that feel wrong.

**KEEP.** This one earns its cost: it is the project's identity, and the
Vargas tutorial you loved is downstream of it. It has also already been
revised once (the destructive-failure carve-out) and survived contact
with a real case (Sketch) where you overruled a proposal that contradicted
it. Working as intended.

---

## Tier 2 — real overhead, real value. Slows work; catches things.

### 5. Fail-before / pass-after for every check *(agent-brief)*
Costs mint cycles and sometimes a full extra build. **KEEP** — it is the
highest-yield rule we have. Today it caught a SwdTech test that *passed
against the broken ROM* (the agent added a discriminator and caught the
free rung in the act), and it is why we know the cost table's ruler
assertion actually fires.

### 6. "A check that can pass without running is not a check" *(CONTRIBUTING)*
**KEEP.** Cheap to satisfy, and the three incidents behind it are all real.

### 7. Cite `file:line` or label it unverified *(agent-brief, CONTRIBUTING)*
**KEEP.** Nearly free. It is why today's reports could correct *my*
premises with evidence instead of arguing.

### 8. Contract / anchor invariant discipline *(leg-fixtures.md, #25)*
Heavy — every boundary needs a measured contract before a leg can be cut.
**KEEP.** It is what makes the parallel frontier trustworthy at all, and
it caught a stale anchor by name rather than as a timeout.

### 9. Don't weaken an assertion to get green *(agent-brief)*
**KEEP.** Free. Load-bearing.

---

## Tier 3 — nearly free. Keep without thinking about them.

10. **`nice` everything** *(agent-brief)* — replaced a whole throttle
    calculus with one word. Pure win.
11. **Worktrees under `.claude/worktrees/`** *(owner rule)* — costs nothing.
12. **No chips/notifications at the owner** *(agent-brief)* — costs nothing.
13. **Capture output to files, not `tail`/`head`** *(agent-brief)* — mild
    friction, has twice hidden a real failure when violated.
14. **Absolute paths in commands** *(added today, after I nearly edited
    your tree)* — free.
15. **Check the repo's own docs before deriving** *(CONTRIBUTING)* — free,
    and has been right against clever derivations more than once.
16. **The release ratchet** *(HANDOFF/ROADMAP)* — a product rule, no
    creative cost, and it is the reason v0.7 could ship without your
    having played it.
17. **Sketch stays** *(CONTRIBUTING)* — a decision, not a constraint.
18. **Long commit messages explaining what was ruled out** *(HANDOFF)* —
    costs me minutes, repeatedly useful when re-reading history. **KEEP**,
    though nobody would die if it were "when non-obvious".

---

## Tier 4 — candidates I'd cut or fold

### 19. FF3-US vocabulary *(CONTRIBUTING, added today)*
**KEEP but watch.** It cost one agent a real detour (the Leap/Capture
collision) and it is brand new, so it has no track record. Its value is
that the doc and the screen say the same word, which is genuinely a
correctness property here. Revisit if it starts generating make-work.

### 20. "Agents report follow-ups; the dispatcher files issues"
*(HANDOFF)*
**FOLD into #2.** This is really the same serialization as "do not
commit." It has produced good triage — every follow-up got read and
either filed, ruled on, or explicitly dropped — but it is me as a
bottleneck again.

### 21. The standing brief being *included by reference in every dispatch*
**REVISE.** In practice I paste a ~600-word custom brief per agent on top
of it. The brief is good; the duplication between it and my dispatches is
not. Proposal: trim the brief to the rules that actually change agent
behaviour, and stop restating them in dispatches.

---

## What I'd actually change, if it were only up to me

Three edits, in order of payoff:

1. **Drop file exclusivity to hunk declaration** (rule 1). Biggest
   throughput win available; the merge cost is real but small and lands
   on me, which is the right place for it.
2. **Let agents commit on their own branch** (rule 2), keeping review and
   merge with me.
3. **Bless targeted re-mints explicitly** (rule 3), so agents stop
   shipping "could not establish" for things they could have measured.

And one thing I would *not* touch: the verification rules (5–9). They
cost time and buy correctness, and today they repeatedly caught things
that would otherwise have reached you — including two cases where they
corrected me.

**A caveat on my own testimony:** I am the wrong witness for whether these
rules suppressed *ideas*, because I cannot see the work I did not think
to propose. The ones I flagged Tier 1 are the ones I noticed straining
against. There may be others I have simply internalised.
