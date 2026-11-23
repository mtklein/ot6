# Six weapon classes (#566): handover, 2026-11-23

Branch `wt/v051-six-classes` (pushed; head at the commit that adds this file, on top of d06078af). Based on
origin/main eb1c9f56 (merged). All six helper branches and the opening helper's branch are merged into it; a
file-by-file compare of each helper worktree's own area against this tree found nothing uncommitted left behind
(the docs helper's 16 uncommitted docs/design files were committed by it and are merged). Nothing of mine is
running except the baseline replay named in section 9.

## 1. The grouping: tables versus what the owner settled

They agree. `ff6/src/battle/ot6_class.asm` (now hand-edited; rewrite_class.py is retired) and
`tools/proto_six/classes.py` (the same grouping as data; `tools/ot6_class.py selftest` and
`tools/check_six_classes.py` hold the two together) say:

| class | bit | what carries it |
|---|---|---|
| Sword | $01 | swords; Chain Saw |
| Dagger | $02 | daggers; ninja blades $25-$2a; Trickshot and Dismantle (OT6_CLS_THIEF; Mug swings the weapon in hand); Gau's fangs = his empty hand and either hand while raging (OT6_CLS_FANG, Ot6WeaponClass in ot6_break.asm) |
| Blunt | $04 | bare fists (not Gau's), knuckles $53/$55/$57, rods $34-$3c, brushes, Flail, Morning Star, Bone Club; Pummel, Suplex, Bum Rush; Umaro's Charge/Throw |
| Ranged | $08 | AutoCrossbow, Air Anchor, TekMissile; stars $41-$43, the three skeans; darts; cards, Trump, dice (Fixed Dice null-break); Coin Toss/GP Rain; Full Moon, Boomerang, Rising Sun, Hawk Eye, Sniper, Wing Edge |
| Katana | $10 | katanas; edged claws $54/$56/$58/$59; SwdTech |
| Spear | $20 | spears; Drill |

Not in the owner's list, decided by me (see `python3 tools/proto_six/classes.py` "sits badly"): Chain Saw Sword;
Air Anchor Ranged; skeans Ranged; Umaro's Throw Blunt; Trickshot Dagger; Hawk Eye Ranged; brushes Blunt; Heal Rod
classless; Hired Help swings the lowest-bit class its target is weak to (animation family: Sword/Katana blade,
Dagger/Spear/Ranged point, Blunt blow).

## 2. Built and working (evidence)

- ROM assembles: `ninja build/ot6.sfc` (identity changes with each merge; final split was ac057dac6cf8 at
  84b3bae0). Six class bits through chip, reveal, HUD, hit-event queue (pin mark moved to bits 6-7), messages
  (Ot6ClassMsgTbl), Hired Help, Gau's fangs, any-weapon HUD cell for a $3f row (OT6_ANYWEAPON $df).
- Save codex O9 + migration (Ot6CodexSix, ot6_codex.asm; Ot6ClassSplitTbl four bytes a species): saves helper's
  report, build/attempts/wt/v051-six-classes/saves/ (golden v0.28..v0.50 48 PASS, battle_sixcodex + mutants, on
  ROM 726acd37 = before the final split; NOT re-run on the final ROM: the helper was cut off mid re-run).
- Static checks green on the final split (run at 84b3bae0): check_shield_rows, check_break_reach,
  check_save_layout, check_text_widths. check_boss_rows RED: 13 lines of bosses-wob.md (section 4).
- New suites (newsuites helper, merged): tools/check_six_classes.py, battle_sixchip/sixhud/sixgau with mutants,
  green on ROM 19da7218 (build/attempts/wt/v051-six-classes/newsuites/rom-19da7218/); not re-run on the final
  ROM, and battle_sixhud does not yet know the any-weapon cell.
- Break-row suites (merged): script-derived rows (build/attempts/.../breaksuites/tools/rewrite_want.py); 35 of
  36 pure-ROM green on its proposal-4 preview; NOT re-derived for the final split (opening rows moved).
- Docs: weapon-classes.md, DESIGN.md, PLAYING.md, kits.md, release-notes-next.md, opening.md,
  narshe-school.md, save-layout.md done for the regroup; route/lab docs and bosses-wor.md still say Fist/Arcane.
- Baseline replay of main's line with the [keys] instrument: 141+ leg logs in
  build/attempts/wt/v051-six-classes/line/base/ (pull more with `sh tools/proto_six/pull_logs.sh`).

## 3. Half-built

- **The line does not pass the Lete** on six classes: `scenario_hub` fails, "river: BANON did not survive any of
  3 attempts ... vs $012C" (mbp ~/work/ot6-proto-six/build/states/scenario_hub.log, ROM 4cca4e0ab976). Cause:
  the route's hands. tools/tests/gen_kolts.lua gearTrip (about :928-970) buys one MithrilBlade for Locke; the
  gear policy (tools/tests/lib/ot6_field.lua M.gearValue/weaponKeys, about :7426-7560, GEAR_KEY) then keeps Terra
  on her Mithril Knife (a unique Dagger key) and Edgar on the Mithril Pike; on the raft nobody holds Sword, and
  Ultros (Sword|Ranged) is keyed only by the AutoCrossbow (Edgar arrives with ~1 MP). Fix in the route/driver,
  not the row: Terra buys/holds a sword at South Figaro, Edgar keeps the Mithril Blade until Narshe (opening.md
  proposal 7), or teach gearValue to weigh the keys of the bodies ahead. Then replay.
- tools/tests/lib/ot6_contract.lua: the 16 ULTROS2 codex witnesses read `M.speciesClassRow(0x12d)` (a function
  value); true only if the line reveals both of his classes at the Lete -- re-measure after the replay.
- Suites: the suites helper edited ~35 files (merged) but its table of what is green on the final ROM does not
  exist; school suites need `tools/tests/school_bytes.py` re-run ($0264 is seven pages now).
- HUD overflow: bodies with elements+classes over four cells lose the overflow (newsuites hudcap.txt, 22 species
  on 19da7218; e.g. Ultros 4 never shows Ranged). Only the $3f case is solved.

## 4. Not started / remaining steps to a green gate, in order

1. Fix the route's hands for the river (section 3), relaunch the line (section 8), fix legs as they fail.
2. bosses-wob.md's 13 lines check_boss_rows names (:171, :300, :389, :661, :700-708, :777, :808, :1009; and
   "Party" for Ultros 1) from docs/design/opening.md; break-coverage-wob.md via
   build/attempts/wt/v051-six-classes/tools/rewrite_break_docs.py --write.
3. Break-row suites: rewrite_want.py on the final rows; restate the 11 proofs the opening overrides (split
   report section "SUITE PINS THE OPENING OVERRIDES") and the Narshe squads; Umaro leaves one blade out.
4. Other suites on the final ROM (opening/suites-naming-changed-rows.txt lists candidates); battle_sixhud for
   the any-weapon cell; saves suites re-run (table shapes: two bits in a byte, $00, three-weakness rows).
5. ot6_hud.asm row comments outside the opening, route/lab docs, bosses-wor.md to the final rows (comment/doc
   only); booklet rebuild (manual_pdf is red) and screenshots (school_0264_p3..p6, a "Weak against daggers").
6. Move tools/proto_six/{classes,stages}.py to tools/weapon_classes.py and tools/story_stages.py
   (tools/ot6_class.py grouping() imports them); delete six_class_split.json (nothing reads it) and split.py's
   write of it; decide whether split.py/pins stay (they are the record of why each row is what it is).
7. Baseline on today's main with the instrument (branch wt/v051-six-classes-base is main BEFORE leo-espers plus
   this harness; refresh it), then `python3 tools/proto_six/line_stats.py base/ six/ --legs` for deaths,
   retries, frames, breaks per battle, nokit/nohand shares (the owner wants the opening legs' numbers too).
8. Merge origin/main, `sh tools/gate.sh -k 0` from a clean tree, re-cut checkpoints
   (checkpoint_drift.py --recut), release notes check.
Open questions for the owner/coordinator: opening.md's proposals (Guard element add, Lobo shields 3->1, Mithril
Pike in South Figaro's shop, opt_equip Celes, Kefka's poison add, "Weak against blunt/ranged attacks" wording);
Umaro's third weakness; whether Dragoon Boots (#567) relieve Spear.

## 5. split.py: rules and how to run

`tools/proto_six/split.py` header is the spec. Inputs: the four-class table from git (`OT6_SPLIT_BASE`, default
origin/main); pins.py (PIN by weapon KIND with a source: "opening"/"wob"/"suite" bind, "row" prefers;
OPENING = the hand-authored opening, binds first; EVERY = all classes; ADD = extra weakness; FAMILY = Ultros);
pins_suite.py (the break suites' proofs, proposal-4); stages.py (rosters, forced, HELD); the route's hands
(tools/proto_six/route-keys-base.json, from `route_fights.py --keys` over the baseline's leg logs).
Order: opening/pinned -> family -> holder rule -> route hands (in hand, then kit, then most holders) -> row
comment -> balance. THE SPLIT IS FINAL: never run it bare again (the balance step moves unpinned rows); to change
a row edit the pins and run `python3 tools/proto_six/split.py --keep HEAD`, then
`python3 ff6/tools/gen_break_floor.py`, `ninja build/ot6.sfc`. `--report-only` prints every row and why
(build/attempts/wt/v051-six-classes/split-report-final.txt). Dealt+gauged species per class (349): Sword 120,
Dagger 102, Blunt 141, Ranged 128, Katana 83, Spear 79.

## 6. Save/codex approach

Codex page magic O8 -> O9 (OT6_SAVEVER stays 2). First touch of an O8/O7 page: each species' class byte becomes
the OR of Ot6ClassSplitTbl[species][k] for each four-class bit k set; Continue ensures the page
(Ot6EsperContinue -> Ot6CodexLoaded). Ot6SeedShields masks the revealed byte with the body's row, so nothing false
draws. docs/design/save-layout.md "The six-class codex" has "Going back to four classes". The table freezes at
release (pin its hash in check_save_layout.py then). Found on main by the saves helper and fixed here: an
unsigned codex page for slot 2/3/new game crashed at first touch (Ot6CodexEnsure wipe loops).

## 7. Decisions of mine not in the issue or briefs

Bits ($04 Blunt, $08 Ranged keep bludgeon's/special's numbers); CHILDREN (pierce may become Ranged, bludgeon
Ranged, special Ranged or Blunt); the items in section 1's last paragraph; EVERY rows take all six and draw one
any-weapon cell; ADD rows (Bogy +Blunt, Tritoch and the Long Arm +Katana; Umaro's refused for the HUD);
the opening helper's count changes (12 rows more, 3 fewer: opening.md "Departures"); Number 128's blades
unpinned; the [keys] instrument in the run loop (M.keysWatch/M.keyLine, log only); contract field values may be
functions; gen_break_floor: a rowed species' floor byte is its row's lowest class; VERSION stays main's.

## 8. Commands, machines, pitfalls

- Build: `python3 configure.py && ninja build/ot6.sfc`. Never `ninja -t clean`.
- Line on the mbp (12 slots; claim first on px13: `python3 tools/stream/live.py --place 6 --claim <branch>`; the
  tool fills px13 first and prints the mbp's room -- stay within that):
  `scp tools/proto_six/mbp_line.sh mbp.local:work/proto-six-line.sh` then
  `ssh mbp.local 'rm -rf ~/work/ot6-proto-six/build/{states,checkpoints,test-runs,LINE_DONE*}; cd ~/work; nohup caffeinate -is zsh ~/work/proto-six-line.sh <full sha> 6 ~/work/ot6-proto-six wt/v051-six-classes > ~/work/proto-six-line.out 2>&1 < /dev/null &'`
  Log ~/work/ot6-proto-six/build/line.log, done marker build/LINE_DONE; status `zsh ~/work/p6-status.sh`
  (tools/proto_six/mbp_status.sh); stop `zsh ~/work/p6-stop.sh` (mbp_stop.sh: kills ninja by cwd -- ninja's
  command line names no tree, pkill by path misses it). `sh tools/proto_six/wait_line.sh 9` blocks for an event.
- Suites on a Mac: tools/proto_six/mac_tree.sh (header). Helpers' clones: Air ~/work/ot6-six-{suites,
  breaksuites,saves,saves-main}; mbp ~/work/ot6-six-newsuites. Logs under
  build/attempts/wt/v051-six-classes/{saves,tools,breaksuites,suites,newsuites,opening,line}/ and
  build/attempts/wt/proto-six-classes/ (the v0.50 prototype: its .bps is obsolete).
- Pitfalls: the generate-edge grep must exclude quick_ states (mbp_line.sh does); a library-only change replays
  no state, so delete build/states to get new log lines; log lines are doubled ("[ot6note] N ..." and
  "[ot6] ..."): anchor regexes on "^\[ot6\] "; Guest moogles (char id >= 16) are not in the [keys] model;
  tools/tests/lib/ot6.lua's main chunk is at Lua's 200-local limit (add to M); the Veldt deals everything
  (stages.VELDT is skipped by the holder rule).

## 9. Still running

mbp.local: the baseline replay (main before leo-espers + this harness), clone ~/work/ot6-proto-six-base,
log build/line.log there, at ~206 stamps in Kefka's Tower when I stopped; harmless, ends by itself
(build/LINE_DONE); pull its logs with `sh tools/proto_six/pull_logs.sh`. The six-class line on the final split
ended rc=1 at scenario_hub (nothing running).

## Appendix: the coordinator's instruction messages, verbatim

### A. The original brief

You are working on OT6 (an FF6 ROM hack with Octopath-style break/boost combat) for the project's technical lead. First command: `sh tools/worktree-setup.sh`. Then start your branch from the v0.50 release tag, not from main: `git checkout -b wt/proto-six-classes v0.50` (the owner is playing v0.50-compatible saves and will A/B this against the release). Read AGENTS.md, docs/guidelines.md, docs/DESIGN.md ("The cast as jobs", "Break system"), ff6/src/battle/ot6_class.asm, and `gh issue view 566`.

This is a PROTOTYPE for the owner to play and for numbers, not a branch to merge: no full gate, no suite repairs, no docs beyond a short README of what you did. Keep it honest and playable.

Build a six-weapon-class variant of OT6. Today there are four break classes (OT6_SLASH swords/katanas/claws, OT6_PIERCE spears/daggers/thrown edges/bolts/darts, OT6_BLUDG fists/staves/rods/flails/boomerangs, OT6_SPECIAL dice/cards/brushes). The six:
- Sword (swords)
- Dagger (daggers, knives, thrown edges and stars, darts)
- Spear (spears, lances, bolts)
- Katana (katanas and ninja blades)
- Fist (fists, claws, fangs, clubs, flails)
- Arcane (rods, staves, brushes, cards, dice, boomerangs)
Adjust the edges where the ROM's weapon categories argue for it and say what you did. Map every weapon in Ot6WeapClassTbl, every skill that carries a class (Blitzes, Tools, SwdTech, throws, Rages/monster specials used by the party, Umaro's arms, Gau's fangs, etc.), and anything else that reads the class bits.

Monsters: each species' weapon weaknesses (Ot6ShieldTbl masks for authored rows; ot6_break_floor.inc for the rest; find its generator) are split mechanically so the NUMBER of weapon weaknesses a species has stays what it is today: a slash weakness becomes Sword or Katana, pierce becomes Dagger or Spear, bludgeon becomes Fist or Arcane, special becomes Arcane or (your choice, say why). Choose each split by a deterministic rule that keeps the six classes roughly evenly represented across the species the game deals (tools/check_shield_rows.py reachable_formations) and that, where a boss's break story in docs/design/bosses-wob.md names the member whose weapon is the key, keeps that member's new class as the key. Elemental weaknesses unchanged.

Display: the HUD's weakness icons need six class glyphs (the battle font already holds weapon glyphs from item names: pick six that read apart); the reveal/codex storage holds four class bits a species today -- find where (the per-save codex, save-layout.md) and make six work without corrupting a v0.50 save: a v0.50 save must load and play; its already-revealed class weaknesses may reset or map approximately, say which. Do not bump the save version; if six bits cannot fit without a layout change, keep class reveals in battle RAM only for the prototype and say so. Everything else that enumerates classes (Relm's Tint is elements, fine; Appraise/Scan reads; the kit pages; Mimic keys) must not crash or lie.

Harness: make the automated driver's key model follow the six classes (it should read tables rather than hard-code four; fix what hard-codes). Then replay the line with this ROM on a Mac, not px13 (px13 is busy): a clone under ~/work/ on the mbp (`ssh mbp.local`, 12 slots, `eval "$(/opt/homebrew/bin/brew shellenv zsh)"`, `caffeinate -is`, detached with a log and a done marker; take the claim first with `python3 tools/stream/live.py --place 12 --claim wt/proto-six-classes` on px13 and stay within what it gives the mbp), `ninja -k 0` on the generate edges only (the states; suites will fail on purpose and are not your job). Report: legs that fail and why, deaths/retries/frames against v0.50's qualification (legcmp; v0.50's numbers: deaths 63-ish, see build/attempts/v050-qual/gate.log and the leg comparison tools under tools/), and from the logs the share of battles in which the party held no weapon key for a body, and breaks per battle, against v0.50.

Also report by analysis (no emulator): for the parties the route and a typical player field at each story stage (bosses-wob.md's party lists; the WoR's from the route docs), the share of dealt species each party can weapon-key under four classes (today) and six.

Deliver: the branch pushed; the playable patch `build/attempts/wt/proto-six-classes/ot6-proto-six-classes.bps` (made the way the release patch is made, against the same base ROM; say the exact command) -- its title screen/Config version text should read something that tells it apart from v0.50 if that is cheap (e.g. "OT6 v0.50s6"), within OT6_VERSION_CELLS; a README.md in that directory: the class table with who holds what, the split rule, what resets in an old save, known rough edges; and your report with the numbers and a list of what a real implementation would still need (suites, docs, bosses' break stories, tools) with a size estimate.

Report only to the coordinating session, in your final report. Never use spawn_task, PushNotification, SendUserFile, AskUserQuestion, Artifact, or any other user-facing channel; put out-of-scope findings and questions in the report instead. Push your own wt/* branch as you go; do not merge, tag, or touch main. Follow docs/TESTING.md and docs/guidelines.md; keep failed attempts. Cite evidence under build/attempts/<your branch>/ and quote the raw log lines behind every number you report. Stop anything you started before you report, except a detached replay or grid that is still making progress: leave it running and name it in the report (the machine, the command, its log, and what to do when it ends).

### B. One-weakness dropped; care for what a player sees

The owner dropped the one-weakness prototype ("more i'm thinking, less i'm interested in the version that drops weaknesses. let's focus on the 6 weapon class version"). Yours is the one that matters now. The Air (ssh air.local, 8 slots) is free as well as the mbp: if splitting the line's replay across two Macs is not practical (each needs its own states), use the mbp for the replay and the Air for anything independent (e.g. spot fights the owner would care about: Zozo and Dadaluma, the opera, the Magitek factory, with the story party at each). Since this is now the likely direction rather than one of two options, spend a little more care on the parts a player sees: six icons that read apart at a glance, who holds which class (include a table by character of every class they can equip into), and bosses' keys staying with the members their break stories name.

### C. A real feature for main

Change of plan from the owner (2026-11-23): "i think we can treat it as a normal v0.y release to try. no big deal if y+1 needs to go back to 4. as long as you can make it up through kefka on the snowfield, don't see huge need to replay through that part myself either." So six weapon classes is no longer a throwaway prototype off v0.50: build it as a real feature for main, to ship in a normal release. What changes in your brief:

1. Base: move your work onto current main (`git fetch origin && git rebase origin/main`, or restart the branch from origin/main and re-apply; keep the name wt/proto-six-classes or rename to wt/v051-six-classes and tell me). A merge is about to land on main (wt/v051-leo-espers: C3 menu/esper code and save version 1 -> 2), and other branches are in flight (wt/v051-dance-opener; wt/v051-spellblade: Celes's list, Break Blade, which chips whatever the keys, and a weapon-element rune; wt/v051-fuse: break-site changes in ot6_break.asm, a HUD mark). Yours touches the class tables more broadly than any of them: keep your edits to shared files (ot6_break.asm, ot6_hud.asm, lib/ot6.lua) tight and well-marked, merge origin/main before final qualification, and expect to land last.
2. Quality bar is the normal one (AGENTS.md, docs/TESTING.md): the full gate green from a clean tree (`sh tools/gate.sh -k 0`), the line replayed (the owner's condition: the automated line must get through Kefka on the Narshe snowfield, and the gate requires all of it), checkpoints re-cut, and every suite that names a class or a key updated to the six classes with its assertions intact (same assertion, new key; never removed, loosened or turned into a log line; if a suite's premise no longer exists under six classes, say so and propose its replacement rather than deleting it). New suite coverage for what is new: each of the six classes chips and reveals; each weapon maps to its class (table-driven); the HUD shows six distinct icons; mutants.
3. Break coverage must hold: tools/audit_break_coverage.py (the ratchet: "an encounter nobody can chip cannot ship"), tools/check_break_reach.py, tools/check_boss_rows.py, tools/check_shield_rows.py green. Choose each species' split so the story party at that point still holds a key (update the audits' party-hands model from PARTY_CLASSES = slash|pierce|bludgeon to what the parties really hold under six classes, per story stage if the model allows; it "may only tighten" -- read that rule and respect it or explain). Bosses' break stories in bosses-wob.md and the WoR route docs keep working: update their key names.
4. Saves properly, not a prototype expedient: find how the per-save codex stores revealed class weaknesses (save-layout.md) and make six classes fit under the compatibility policy (every golden save v0.28..v0.50 loads; an older save's revealed class weaknesses map to something sensible -- e.g. a revealed "slash" shows as revealed for whichever of Sword/Katana that species now has -- with no lie on screen). If it needs new save bytes, use the version rule main has after the Leo merge (version 2; read save-layout.md on main once it lands) and document it. The owner accepts that a later release might go back to four classes: write down in save-layout.md what going back would take.
5. Docs: DESIGN.md (the cast table's weapon column, "Break classes (4)"), PLAYING.md ("Weapon types", the character sections, the display section), kits.md, bosses-wob.md and route docs' key names, kit pages, tools/manual (rebuild the booklet on the mbp; retake any booklet screenshot that shows weakness icons: tools/manual/shots.py), docs/release-notes-next.md (a clear paragraph: the six types, who holds which, and that weaknesses already revealed in a save carry over as described).
6. Still wanted from the old brief: the per-character table of classes each can equip into; the analysis of party coverage by story stage under four and six; the line's numbers against today's (deaths, retries, frames, breaks per battle, share of battles where the party held no weapon key). The v0.50-based .bps is no longer needed.

Use the mbp and the Air for replays and batches as before (claims first). This is a large change; take the time it needs and report walls early in your final report rather than working around them.

Report only to the coordinating session, in your final report. Never use spawn_task, PushNotification, SendUserFile, AskUserQuestion, Artifact, or any other user-facing channel; put out-of-scope findings and questions in the report instead. Push your own wt/* branch as you go; do not merge, tag, or touch main. Follow docs/TESTING.md and docs/guidelines.md; keep failed attempts. Cite evidence under build/attempts/<your branch>/ and quote the raw log lines behind every number you report. Stop anything you started before you report, except a detached replay or grid that is still making progress: leave it running and name it in the report (the machine, the command, its log, and what to do when it ends).

### D. After the first usage limit; the docs helper's findings

You were cut off by a usage limit; it has been lifted. Continue from where you stopped (applying edits one at a time; last pushed commit 58b3ef85). Your helpers were cut off as well: check each helper worktree (wt/v051-six-tools, -six-suites, -six-saves, -six-breaksuites, -six-docs, -six-newsuites) for what it left and finish or redo it; nothing of theirs is merged unless you did it. Main has moved (8510e7e1 leo-espers: save version 2 and C3 menu code; cbebcbb4 docs): merge origin/main before final qualification.

One helper ("Six-class docs: WoB design set", worktree agent-ae6d1f9ec15bbaddc) finished and reported to me instead of you. Its edits are in that worktree's docs/design/ (16 files, uncommitted: no git writes). Its findings that matter for the split itself, which you must resolve in the SPLIT (my brief: where a break story names the member whose weapon is the key, that member keeps the key), not by rewording docs:
1. Mega Armor $102: Locke's daggers keyed pierce; the row is now Spear|Fist.
2. Gigantos $0AE: Terra/Locke/Edgar's swords keyed slash and the lab's lever was boosted slash Fights; the row is Katana|Fist, so of the landing four only Shadow's ninja blade keys it.
3. Bug $0E8: Celes's sword and Edgar's pike/crossbow keyed it; the row is Dagger|Katana (only Locke's knife).
4. ChickenLip $03D: Celes's sword keyed slash; now Katana|Fist (Sabin alone).
5. Grenade $0AA: Edgar's tools keyed pierce; now Dagger|Fist.
6. Intangir $0A3: the doc said every class keys it; now Sword|Dagger|Fist|Arcane (no Spear).
7. Ifrit $109, Number 128 $10b, Left Crane $10d: Locke's daggers keyed pierce; all three are Spear. "Every Facility boss is class-breakable by Locke and Celes" is now false (the other three need Edgar). Fix this one for certain: the factory's story party must hold its keys.
8. Sabin's claws no longer give him a second class (claws and Pummel are both Fist): decide whether claws should be their own thing or whether Sabin holding one class is right, and say why.
9. Laser Gun $145 and MissileBay $147: Edgar's AutoCrossbow keyed pierce on every part; both are Dagger now.
10. Keys gained that reverse recorded findings (fine, but the docs' conclusions must be restated): seven formerly bludgeon bodies are Fist, so Sabin's plain Fight chips them; Trapper $02D likewise.
Also: tools/audit_multihit.py, tools/check_break_reach.py and tools/tests/battle_breakwob_sidetrips.lua still name four classes and mask class bytes with $0F; multi-hit.md §3.1's Retort/Empowerer/Quadra Slice rows were already stale before the split (classless, classless, wind); floating-continent-route.md §3's Sky Armor/Spit Fire shield counts (5) disagree with the rows (2).
Rule of thumb for the redo: a row that had a key in the hands of the story party at that point keeps a key in those same hands unless you can show the party has another weapon key for it and say so in the doc.

### E. First regrouping and the holder rule (superseded in its grouping by F)

Design direction from the owner's review of your early findings (2026-11-23). The owner: "we don't want just one particular character to be required to get through fights"; on Sabin, "has been very versatile for having slashing and pummel"; and "it's pretty rare anyone will want to be wielding a dagger" -- so a class's holders must be counted by who really wields it (signature weapon or signature command), not by who could equip one. Working grouping (the lead's; the owner may still amend, so keep the class tables data-driven and cheap to regroup):
- Sword: swords. (Terra, Celes; Edgar and Locke when they carry one.)
- Dagger: daggers and Shadow's ninja blades, as vanilla's own "dirk" icon groups them (Imperial, Kodachi, Blossom, Hardened, Striker, Stunner). (Locke, Shadow's held weapon.)
- Spear: spears, bolts (AutoCrossbow, Drill as today), thrown stars (Shuriken, Ninja Star, Tack Star: Shadow's Throw) and darts (Darts, Doom Darts). (Edgar, Mog, Shadow's Throw, Setzer with darts.)
- Katana: katanas and claws (Mithril Claw, Poison Claw, Dragon Claw, Tiger Fangs: the edged ones). (Cyan; Sabin with claws.)
- Fist: bare fists, knuckles (MetalKnuckle, Fire Knuckle, Kaiser), the blows of Pummel and Bum Rush whatever he wears, fangs, clubs, flails. (Sabin, Gau, Umaro.)
- Arcane: rods, staves, brushes, cards, dice, boomerangs and the other thrown rings. (Strago, Relm, Setzer; a mage with a rod.)
So Sabin with claws holds two classes (Fight Katana, Pummel Fist) as he held slash and bludgeon before; Shadow holds Dagger in hand and Spear by Throw; Setzer Arcane or Spear by weapon. Check each named weapon against the ROM and say where a weapon sits badly.

Holder rule for the split and the audits: at every story stage, for every class a dealt species is weak to as its ONLY weapon key, at least two characters the player can field then really hold that class (signature weapon or command, per the list above), and no fight the story forces is keyable by one named character alone unless the story also forces that character into the party. Build that into split.py's route step and into the audits' party model, and report the stages where it cannot be met (e.g. before Mog, Spear is Edgar plus Shadow's Throw only when Shadow is along).

### F. The regrouping to finish with

Regrouping from the owner (2026-11-23), replacing the grouping in my last message. The owner mapped the classes to Octopath's six (sword, spear, dagger, axe, bow, staff): "katana is axe", a class that "gathers together all the ranged physicals, bolts, stars, darts, cards, dice, boomerangs" is the bow, and "rods and fists could group". So the six are:
- Sword: swords. (Terra, Celes; Edgar and Locke when they carry one.)
- Dagger: daggers and Shadow's ninja blades (vanilla's dirk icon group). (Locke, Shadow's held weapon.)
- Spear: spears; Drill stays here. (Edgar, Mog.)
- Katana: katanas and the edged claws (Mithril Claw, Poison Claw, Dragon Claw, Tiger Fangs). (Cyan; Sabin with claws.)
- Blunt: rods, staves, brushes, bare fists, knuckles (MetalKnuckle, Fire Knuckle, Kaiser), the blows of Pummel and Bum Rush whatever he wears, fangs, clubs, flails. (Sabin, Gau, Umaro, Strago, Relm, a mage with a rod.) Player-facing name "Blunt" (vanilla's own item-type word) unless it reads badly; report.
- Ranged: bolts (AutoCrossbow), thrown stars (Shadow's Throw), darts, cards, dice, boomerangs and the other thrown rings. (Setzer, Shadow's Throw, Edgar's AutoCrossbow, Locke with a boomerang.)
Check every named weapon and every class-carrying skill against the ROM and say where one sits badly (Chainsaw, Air Anchor, skeans, Umaro's Throw, Gau's rages' specials, monster-box oddities).

Spear is thin on purpose under this grouping (Edgar and Mog; before Mog, Edgar alone). The holder rule from my last message handles it: no dealt species has Spear as its ONLY weapon key at a story stage where the story does not put a spear holder in the party, and more generally a sole weapon key always has at least two real holders fieldable then. Report the stages where the rule binds. A reserve idea, NOT to build: Jump counting as Spear whatever the weapon (Dragoon Boots); say what it would take.

Keep the tables data-driven; this is the grouping to finish with unless the numbers argue against it.

### G. Blunt settled; Dragoon Boots

Two notes from the owner (2026-11-23): (1) "yes i like blunt": the class's player-facing name is Blunt, settled. (2) "let's make it that dragon boots allow equipping a spear": a separate branch (wt/v051-dragoon-spear, issue #567) is building that relic permit in the equip code; do not build it yourself and do not depend on it. For your holder rule, a character wearing Dragoon Boots may count as a Spear holder only from the point the player can certainly own the boots (that branch will report where they are obtainable); until you have that, treat Spear's holders as Edgar and Mog, and note in your report which stages the boots would relieve.

### H. Gau's fangs

Owner (2026-11-23): "fangs could be daggers maybe? they're more piercing than blunt." Decision: Gau's innate fangs (his weaponless Fight, and whatever today reads his "fangs" class) are Dagger, not Blunt. That makes Dagger's real holders Locke, Shadow in hand, and Gau. Sabin's Tiger Fangs stays with the edged claws in Katana. Rages keep whatever class each rage's attack carries; say how a raging Gau's plain attack is classed today and whether it should follow the fangs.

(Answer: through v0.50 a raging Gau's plain attack took the class of whatever item id the rage monster's
weapon-graphics byte numbered (SetRage writes MonsterProp+26 into his hands): arbitrary. It now follows the
fangs: Dagger. Ot6WeaponClass, ot6_break.asm; battle_sixgau.)

### I. The opening

Owner (2026-11-23): "i think this is also enough different that i'm going to want to playtest from zero on this new plan. the beginning of the game is especially important to get right because of how limited your options are, and how if it doesn't go well it's likely to turn off new players." So the opening hours are the part of your work that will be judged first and hardest. Add:

1. Author the opening by hand, not by the mechanical split: every species and boss the game deals from the Narshe mines through the Narshe defense (the mines, the moogle defense, Figaro's desert and cave, South Figaro, Mt. Kolts, the Lete, each of the three scenarios, the Narshe defense; then Kohlingen and Zozo as the next tier). For each, a row in a table in your report and in the design doc: the party the story forces there, the classes and elements that party really holds, the species' weapon and elemental weaknesses under six classes, and how the fight teaches something. Principles: with one or two characters the player must always hold an obvious weapon key for most bodies (the opening teaches the loop; it must not open with enemies nobody in hand can chip); each new member's class should matter soon after they join (Locke's Dagger, Edgar's Spear and his Ranged crossbow, Sabin's Blunt, then Katana with Cyan and Dagger with Gau's fangs and Shadow in Sabin's scenario); no opening fight needs a class only an optional hire (Shadow) holds; elements stay the mage's lever (Terra's Fire). Bosses 1-10 of bosses-wob.md keep break stories the forced party can execute, restated in the new classes.
2. The in-game teaching text: the Narshe school (docs/design/narshe-school.md; the $0264 line "swords and claws slash, spears and knives pierce, rods bludgeon" and the other screens) must teach the six classes correctly and briefly, within its windows; and the "Weak against ..." battle messages. Screenshots.
3. Report a walk-through of the first hours as a new player meets them: in order, each new class or element the player gains and the first enemies that reward it. Flag any stretch where the forced party holds only one weapon class and say what the enemies there are weak to.
4. The line's numbers for the opening legs specifically (deaths, breaks per battle, battles with no weapon key held), four classes against six, from the replay.
The owner replaying from the start does not relax anything else in your brief (older saves still load; the whole line still passes).

### J. The owner's read of the opening

Owner's read of the opening, for your hand-authored tables (2026-11-23): "terra and edgar and sabin are versatile, and locke always has something to do with steal. if we get the parts of the game that involve those four and their scenarios feeling good, the rest should follow pretty easily." So measure the opening by those four and their scenarios: Terra (Sword, fire), Edgar (Spear, Ranged crossbow, tools' elements), Sabin (Blunt, Katana with claws, his Blitz elements) should each usually have a key or a clear second option; Locke need not hold a weapon key for everything, since Steal and his list give him a turn worth taking, but his Dagger should matter often enough that it is a class the player learns. "Edgar is the natural pick to bring along anyway, both for new and returning players", so Ranged leaning on his crossbow early is accepted.

### K. The handover instruction

The usage limit was lifted again, but the Fable budget cannot carry this branch to the end, so a fresh agent on another model will finish it. Do not relaunch helpers. Do only this, as cheaply as you can, then stop: (1) commit and push everything worth keeping to wt/v051-six-classes, including what each helper worktree holds (wt/v051-six-tools, -six-suites, -six-saves, -six-breaksuites, -six-docs, -six-newsuites, and the docs helper's uncommitted edits in agent-ae6d1f9ec15bbaddc): merge or cherry-pick what is good, and list what you left behind and why; (2) write build/attempts/wt/v051-six-classes/HANDOVER.md: the grouping as it stands in the tables versus the final one the owner settled (Sword; Dagger with ninja blades and Gau's fangs; Spear with Drill; Katana with edged claws; Blunt with rods, brushes, fists, knuckles, Pummel/Bum Rush, clubs; Ranged with bolts, stars, darts, cards, dice, boomerangs), what is built and working (with the test or log that shows it), what is half-built and where (file:line), what is not started, split.py's rules and how to run it, the save/codex approach, every decision you made that is not in the issue (#566) or the briefs, the pitfalls, the exact commands for builds/replays, where clones and logs live on which machine (mbp, Air), and the remaining steps in order to reach a green gate; also paste the full text of every instruction message you received from the coordinator, verbatim, in an appendix (the next agent will not have them). Stop anything you have running unless it is a line replay on the final split that is still useful; name it in the handover. Report in two lines.
