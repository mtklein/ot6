-- STATUS 2026-08-20 (issue #127, NINTH pass -- owner's ruling: the root
-- cause is SOLVED, owner playtested it live -- the ambush and FlameEater
-- are winnable and correctly tuned; every prior loss was an UNPREPARED
-- party (no gear, no espers, no MP items, no pre-fight heal). Directive:
-- make the generator prep the party like a player, then fight with
-- weakness AoE. Do NOT touch enemy stats. Do NOT grind.
-- VERDICT: the grind is gone and PREP is real and working, but the ambush
-- STILL loses on every rung tried (10 attempts across two from-scratch
-- runs) -- per the coordinator's own decision rule ("if it still loses
-- with espers+gear+AoE and full prep, capture the numbers and STOP, don't
-- grind around it"), stopping here with the numbers below rather than
-- chasing a further gear/tuning guess blind.
--
-- 0. THE GRIND IS GONE. GRIND_*/grindLeg and the whole pre-inn shuttle
--    loop are deleted outright; the route now goes boot -> care -> PREP ->
--    town -> shop -> inn -> fire -> house, exactly as directed.
--
-- 1. PREP, BUILT AND WORKING. TERRA and LOCKE each get their 4-piece
--    checkpoint-bag loadout (Blizzard/Mithril Shld/Bandana/Mithril Vest;
--    ThunderBlade/Buckler/Head Band/Kung Fu Suit) via H.equipLoadout, plus
--    an Ice-granting esper each (SHIVA->TERRA, MADUIN->LOCKE -- both
--    confirmed via genju_prop.asm's real grant lists: {ICE,OSMOSE,SHELL}
--    and {FIRE,ICE,BOLT} respectively). STRAGO gets BISMARK right after he
--    joins, in the house. MEASURED CORRECTION to the brief's own esper
--    read: BISMARK does NOT grant a castable Water spell in this build --
--    genju_prop.asm's real grant list is {HASTE,SLOW,{}} -- Sea Song is
--    Bismark's own once-per-battle SUMMON, not a Magic-list grant, so
--    STRAGO's free Aqua Rake stays the only repeatable water answer. Ice
--    is the only repeatable elemental AoE this loadout actually has.
--    MEASURED (live, this pass): the equip menu HANGS at 1200 frames on
--    the WORLD MAP specifically -- M.hasControl(), what every equip
--    helper's "back out" step waits for, tests the field party-object
--    movement-type byte, and the world map's own party object apparently
--    never reads that way; M.worldHasControl() is a different, unrelated
--    gate none of M.equipWeapon/M.equipEsper know about. Fixed by moving
--    TERRA/LOCKE's PREP to right after town re-entry (plain M.hasControl()
--    works fine there, like every other menu call in this file). Also
--    extended M.equipEsper (lib/ot6_field.lua) to accept a function `pos`,
--    matching M.equipWeapon's existing lazy-resolution shape -- used for
--    STRAGO, whose join-time party row this file never asserted anywhere.
--
-- 2. THE FIGHT PLAN NOW LEADS WITH AOE ICE. newAmbushPlan's decideTurn
--    gives TERRA/LOCKE a boosted, multi-target Ice cast (spellCellA, the
--    same magic-list walk M.newFightDriver's own opts.magic uses, ported
--    into this bespoke driver) ahead of their old Fight/Filch fallback,
--    folding Ice->Ice2->Ice3 via the same BP-bank shape Fight's boost
--    already used. STRAGO keeps his free Aqua Rake. flameEaterAttempt gets
--    the same lead via the generic driver's own opts.magic. MEASURED: the
--    cast mechanically WORKS -- "Ice cast #1 confirmed" landed in several
--    attempts once an actor got a turn at all.
--
-- 3. MEASURED, THE ACTUAL BLOCKER: the ambush's OPENER -- before this (or
--    any) driver's first action ever executes -- deals large, variable
--    damage across the whole party. TERRA's missing HP across five
--    attempts of one run: 345, 293, 271, 345, 345 (of her 345 max) --
--    lethal 3 of 5 times, and gear did NOT change her max HP at all
--    (345/345 before AND after the full loadout -- this bag's armor
--    carries no HP bonus in this build). LOCKE and STRAGO usually survive
--    the opener itself at 20-55% hp, but with ZERO player actions ever
--    landed (tally: Aqua Rake x0, Ice x0, Filch x0, boosted burst x0 on
--    more than one attempt) a second hit or two finishes off whoever
--    is left before the driver's first confirmed action, leaving at most
--    ONE character alive out of three.
--
-- 4. A REAL BUG FOUND AND FIXED ALONG THE WAY, THEN UN-FIXED ON EVIDENCE:
--    when phase 1 ends with 1-2 party members dead, a probeEventDump
--    right at that moment reads ev=true (a field event genuinely running)
--    and $050A newly SET, which first looked like "a real win, just cut
--    off too early" -- raising the win-tail settle budget 6200->40000
--    seemed like the obvious fix. MEASURED: it was NOT the fix -- the
--    budget change did not change the outcome at all, just how long it
--    took to report the same "map=0, absurd field coords" result. A
--    temporary per-frame HP trace (since removed) showed why: monster HP
--    sits at full 555 x4 for the ENTIRE visible fight (no damage ever
--    landed), and surviving characters' HP goes flat too once the last
--    action is taken -- consistent with a scripted post-ambush field event
--    that requires a full living party of three to complete, stalling
--    forever (or at least past any reasonable budget) when it is short a
--    member. Budgets left at a middling 12000 (up from 6200, in case a
--    genuine full-survival win's own tail is a little longer) rather than
--    reverted outright, but the real fix is upstream of this code: keep
--    everyone alive through the opener, not give the settle more time.
--
-- 5. NOT YET TRIED, filed for whoever picks this up next: row placement
--    (M.setRows -- TERRA in the back row would halve PHYSICAL opener
--    damage, unexercised this pass), Ethers/Tinctures for the MP the
--    brief specifically named ("no MP items" in the owner's diagnosis --
--    this pass bought none), and whether the bag holds a better DEF/HP
--    piece than Mithril Vest/Shld for either caster. The 10 measured
--    opener numbers above are real data for whichever of those is tried.
--
-- Files touched this pass: tools/tests/gen_thamasa_fire.lua (grind
-- removed; PREP added; fight plan amended); tools/tests/lib/ot6_field.lua
-- (M.equipEsper's `pos` may now be a function). savestate_graph.py's
-- `fire_out` edge and chests_opened.txt's bits 104/105 stay OUT -- the
-- fight is not won, so checkpoint M was not captured.
--
-- ---------------------------------------------------------------------
--
-- STATUS 2026-08-20 (issue #127, EIGHTH pass -- owner's ruling: not the
-- grind, the FIGHT PLAN. Built a bespoke per-fight driver (Aqua Rake
-- lead, Filch/burst fallback, survivor-mode gate, revive window) to
-- replace the generic driver's proven "revive treadmill" failure mode.
-- VERDICT: still a #74-style balance finding, and now the clearest
-- version of it yet -- with a properly-executing tactical plan, 4 of 4
-- completed rungs are clean, consistent losses, and the plan's OWN
-- offense (Aqua Rake, the burst half of break-and-burst) never got to
-- fire even ONCE across any of them):
--
-- 0. THE PLAN BUILT: newAmbushPlan (right above ambushAttempt), a
--    bespoke raw-button state-machine fighter -- modeled on
--    gen_narshe_battle.lua's per-fight fighter and battle_thief.lua's
--    decide() -- NOT H.newFightDriver, replacing it for this fight only.
--    STRAGO alive -> Aqua Rake (lore id 3, researched fresh this pass:
--    ST_LORE=$1B, cursor block $891F/$8923/$8927, row found via
--    $306A+id==id+$8B, the same table battle_lore.lua's own passing test
--    exercises) every turn -- multi-target water, hits all four Balloons,
--    and because the Exploder self-destruct deals CURRENT hp, a landed
--    Rake also defuses whatever a surviving Balloon's own explosion would
--    do. LOCKE alive, Strago down -> Filch (thief submenu row 1, strips
--    a shield class-blind, banks +2 BP) while any Balloon still carries
--    one, else an R-boosted Fight (4x on a broken target) on the default
--    cursor. Revives withheld entirely while 2+ Balloons live (the
--    measured treadmill); the gate opens at <=1 Balloon, reviving STRAGO
--    first. Self-heal below 40% HP always allowed (never spent on
--    corpses).
--
-- 1. A REAL STALL BUG, FOUND AND FIXED LIVE: the first full run stalled
--    the ENTIRE 1800000-frame phase-1 budget on LOCKE's own self-heal --
--    H.targetCursor's own documented limit ("the two-press rotation...
--    cannot reach a slot that needs a bare up-then-right", ot6.lua's own
--    header) most likely means the character-column rotation this fight's
--    2-down-of-3 shape needs isn't reachable by the shared 4-direction
--    rotation. Fixed with a stall-breaker (240 failed-confirm ticks, then
--    force A regardless of the latch) -- the same #111-backstop shape
--    already used elsewhere in this codebase. With it, every attempt now
--    resolves in ~5000-6000 frames instead of never.
--
-- 2. RESULT, ALL 4 CLEAN RUNGS: TERRA and STRAGO are ALWAYS both fully
--    killed by the opener (missing = their own exact max HP, i.e. 550 and
--    488, every single attempt -- STRAGO never once got to cast Aqua
--    Rake) -- LOCKE is ALWAYS the sole survivor, at a genuinely NEW
--    number each time: missing 157, 433, 279, 279 out of his 558 max
--    across the four attempts (the FIRST direct measurement of the
--    opener's real per-target damage the task asked for -- it is neither
--    "555" nor uniform; it ranges 157-433 on the one character it doesn't
--    outright kill, no visible pattern to the four numbers this pass had
--    time to look for). Even so, LOCKE alone could not turn the fight:
--    tally across the 4 rungs is Filch x1, x0, x2, x2 -- and BOOSTED
--    BURST FIGHT x0, x0, x0, x0. The burst half of break-and-burst never
--    fired ONCE. Every one of LOCKE's turns not spent on the 1-2 Filches
--    he did land went to self-healing (the 40% floor triggering
--    repeatedly, sometimes on his very first turn -- attempt 2's 125/558
--    opening) -- the three still-full-HP Balloons' own ongoing damage
--    output overwhelms what his self-heal-only sustain can offset, so he
--    never reaches the "no shields left, go boosted Fight" branch at all.
--    This is a DIFFERENT treadmill than the generic driver's revive loop
--    (which the survivor-mode gate did successfully kill -- no revive-
--    while-2+-alive ever fired), but the SAME shape: one character cannot
--    out-sustain three L22 Balloons long enough to ever land a real
--    offensive turn, whether that turn would have been a revive or a
--    burst kill.
--
-- 3. RUNG 5: the SAME pre-filed, confirmed-deterministic creepNav no-path
--    bug from the sixth pass (identical addresses: "no path (26,36)->
--    (22,25)"), unrelated to the fight plan. Per the coordinator's own
--    instruction this stays filed; 4 clean rungs are the report.
--
-- 4. PER THE COORDINATOR'S OWN DECISION RULE ("if all rungs STILL lose
--    with break-and-burst executed, report per-rung numbers and stop"):
--    stopping here. The bespoke plan executed as designed (Filch landed,
--    the survivor-mode gate held, self-heal fired correctly) and still
--    lost every completed rung. Given a properly-driven Locke -- fighting
--    honestly, healing himself, never wasting a turn on a doomed revive
--    -- cannot survive long enough to land even one boosted burst against
--    three full-HP Balloons, and Strago (whose Aqua Rake is the plan's
--    entire engine) has a 0-for-4 survival record against the opener,
--    this reads as conclusive: the fix this fight needs is not in the
--    driver.
--
-- ---------------------------------------------------------------------
--
-- STATUS 2026-08-19 (issue #127, SEVENTH pass -- coordinator's diagnosis
-- of the plateau (Baskervor attrition, not thin XP -- OT6's 2x reward
-- scaler means real wins should climb fast) is plausible but the directed
-- fix, teaching the grind to flee Baskervor specifically, was tried live
-- and made things WORSE, not better; REVERTED. Superseded by the eighth
-- pass above, which is the current report -- kept for the record):
--
-- 0. THE FIX BUILT: M.worldNavTo gained opts.fleeSpecies (lib/ot6_field.
--    lua, a real, general-purpose, KEPT library feature -- a set of
--    formation species words to flee via the existing newFlee sub-driver
--    -- cap, can't-run/pincer-refusal fallback, no new state writes --
--    while fighting everything else tactically). Wired into the grind as
--    fleeSpecies = { Baskervor $01D }, fight Cephaler ($096) and anything
--    else.
--
-- 1. MEASURED RESULT: worse. The "flee:" diagnostic (newFlee's own 600-
--    frame heartbeat) fired dozens of times back to back with genuinely
--    different counter values each time -- not one stuck fight, real
--    fleeing on nearly every single encounter this tile rolled. Repeated
--    flees appear to have a real position-drift cost this codebase's
--    other flee callers (all short, bounded corridor walks) have never
--    exercised at this scale: the party ended up stuck at (232,146),
--    "no path with 4 blocked edges" in all four directions, FIGHTING
--    CHIMERA ($01F, the FOREST terrain group's own no-weakness HP2237
--    monster) -- a formation this grass-tile shuttle should never roll at
--    all. Chimera wiped the party repeatedly. The grind never reached
--    GOAL MET or CAP REACHED; it burned through all 220 scheduled legs
--    (many landing in the wipe branch, which never checks the fight-cap
--    condition) and fell through to "enter town" with the party nowhere
--    near its expected staging tile, failing there instead.
--
-- 2. REVERTED: GRIND_WALK is back to plain playBattles="tactical" (fight
--    everything), the SIXTH pass's configuration, which reliably
--    completes even though it plateaus at TERRA 550hp/LOCKE 558hp (both
--    L18). Root cause of the plateau itself -- whether it really is
--    Baskervor-attrition (wipes reloading away all progress) or something
--    else (an XP-share-for-survivors-only mechanic, since TERRA is the
--    one who dies almost every fight) -- was NOT conclusively settled
--    this pass: a leg-by-leg audit of the 60->85-fight stretch (run18's
--    own log) found only ONE explicit party-wide WIPE line in that whole
--    range, while the fight counter climbed steadily via real battle
--    starts -- which sits uneasily next to "mostly wiped fights" as the
--    full explanation, though it does not rule out individual-character
--    death-without-a-full-wipe as a contributing factor. Filed, not
--    chased further.
--
-- 3. NO NEW AMBUSH DATA THIS PASS. The sixth pass's 4 clean rungs (L18,
--    TERRA 550hp/LOCKE 558hp, full-kit driver, restocked bag) are
--    unaffected by this reverted experiment and remain the report: TERRA
--    dies on the pincer's opening frame in every attempt, LOCKE is the
--    reliable survivor, three Balloons sit untouched at 555hp for the
--    whole fight while the lone survivor cycles revive-items without
--    ever landing a real attack. Given two independent attempts to move
--    TERRA past the exact >555 threshold (a cap raise, then selective
--    fleeing) both failed to help -- one plateaued outright, the other
--    actively regressed -- this is where the report stops rather than
--    trying a third grinding mechanism.
--
-- opener looks level-INDEPENDENT, which the L16 data alone could not show):
--
-- 0. THE GRIND, BUILT AND WORKING (moved pre-inn per the coordinator's own
--    course-correction -- checkpoint L boots directly onto the world map
--    as TERRA-LOCKE-SHADOW, so grinding needs no town exit at all): out of
--    three real bugs found live, the one that mattered most was a
--    checkpoint that was captured ONCE before leg 1 and never refreshed,
--    so every wipe (measured: roughly 1 in 2-3 legs, even at three
--    members, against Baskervor's L22 HP750 no-weakness) reloaded all the
--    way back to the START, discarding every level gained since -- 137
--    legs (900000 frames) produced ZERO net progress before this was
--    caught. Fixed by re-checkpointing after every leg that didn't wipe.
--    Also built: the Thamasa item shop, decoded from source (short_
--    entrance.dat's map-343 block $15f0, shop_prop.dat record 35) rather
--    than guessed, with two real UI bugs fixed (a 2-tile counter-talk
--    staging fallback; edge-tapped not held B to close the shop -- shop.
--    asm's B-handler reads a fresh-press edge). M.worldNavTo gained
--    opts.wipeEndsRide (lib/ot6_field.lua), extending advanceStory's own
--    soft-wipe convention, so a grind wipe ends that leg instead of
--    hard-failing the run.
--
-- 1. THE GRIND'S OWN RESULT: TERRA plateaued. First cap (60 fights):
--    TERRA L14->L18 (+4) 550hp, LOCKE L15->L18 (+3) 558hp -- LOCKE clears
--    the >555 target, TERRA sits 5hp under it. Coordinator raised the cap
--    to 85 (correctly judging the stop-rule's "thin XP" trigger, <2
--    levels/60 fights, did not apply -- both characters gained 3-4
--    levels, healthy ground). Result at 85 fights: TERRA STILL exactly
--    550hp, LOCKE STILL exactly 558hp -- 25 more fights, ZERO further
--    progress for EITHER character. That is a plateau, not "close and
--    still climbing"; root cause not chased down this pass, but a
--    plausible mechanism is sitting in the data (see #3 below) -- a
--    character who is dead more often than alive at fight-end may be
--    earning little or none of that fight's XP, and TERRA is the one who
--    dies almost every single time (see #3).
--
-- 2. PER THE COORDINATOR'S OWN CALL, PROCEEDED TO THE AMBUSH ANYWAY (L18,
--    550/558hp, NOT the exact >555 goal, but the "if it still loses all 5
--    rungs, report the L18 numbers" framing): a healthy restock first
--    (30 tonic / 15 potion / 20 fenix down, gil never came close to
--    short -- 161155 left after buying). Then the SAME 5-rung ladder +
--    full-kit driver (items, cure, boosted Fight, healer=TERRA) from
--    pass five, now fighting from L18 instead of L16.
--
-- 3. RESULT: 4 OF 5 RUNGS ARE CLEAN, REAL, CONSISTENT LOSSES (reproduced
--    IDENTICALLY across two separate full runs -- same frames, same
--    partyhp, same monhp, down to the byte). Every attempt's very first
--    logged battle frame (f+1, before the tactical driver has thrown a
--    single input) already shows TERRA at 0 or near-0 hp -- every attempt,
--    no exceptions -- with LOCKE the sole reliable survivor (401,
--    282, 393, 393 hp across the four clean attempts) and STRAGO also
--    dead at f+1 in three of the four. Monster HP is the more striking
--    number: one Balloon already at 0/sh0 (a self-destruct, killing
--    whoever it caught) and the other THREE sit at a completely
--    unmoved 555/555/555 for the ENTIRE fight in every attempt watched in
--    detail (6300+ frames, zero damage landed) -- the lone survivor
--    spends the whole fight cycling revive-item turns on the fallen
--    rather than ever landing an attack, because the moment anyone is
--    healed up they die again to something (unclear what, given the
--    Balloons are demonstrably not attacking for 555+ damage every round
--    themselves -- worth the next pass's attention). THE LEVEL-INDEPENDENCE
--    IS THE HEADLINE FINDING: TERRA died to this SAME opener at L16 (pass
--    five, ~290-345hp) AND at L18 (this pass, 550hp) -- climbing 200+ max
--    HP changed nothing about whether she survives the opening round.
--    Either the real damage/effect is well above the "555, a Balloon's
--    own full HP" hypothesis the grind target was built on, or -- worth
--    flagging explicitly -- the opener may not be a plain damage roll at
--    all (an instant-KO-shaped effect would explain a kill rate that
--    doesn't move with HP the way ordinary damage should). Filed, not
--    chased further this pass: the task's own scope was "grind to the
--    measured target," not "re-derive the opener's mechanic."
--
-- 4. RUNG 5 IS BLOCKED BY A CONFIRMED-DETERMINISTIC NAVIGATION BUG, NOT A
--    COMBAT OUTCOME: attempt 5's own approach walk, creepNav(21, 23,
--    FLEE_WALK) from the post-reload position (26,36), fails with "no
--    path (26,36)->(22,25) [0 edges blocklisted, 20 retries]" --
--    reproduced IDENTICALLY in two separate full runs (same source tile,
--    same target tile, same "20 retries" exhaustion), so this is not a
--    one-off flake. One mitigation was tried and made things WORSE: a
--    smaller creep step (8, forcing a different intermediate waypoint)
--    broke attempt 1 too (previously clean) with a *different*
--    "no path (26,36)->(23,30)", which disproves the "one specific tile
--    transiently blocked by a wandering flame" theory this pass started
--    with -- reverted back to the default step. Root cause not found:
--    the leading candidate is some state that only exists after exactly
--    four requestLoadState reloads (attempts 2, 3, 4 each reload once;
--    attempt 5 is the fourth), since attempts 1-4 from the SAME nominal
--    starting tile never hit this. Filed for whoever next touches map
--    351's navigation or the reload trampoline; the 4 clean rungs already
--    on hand are sufficient, consistent evidence for the balance verdict
--    without a 5th.
--
-- 5. NOT REACHED THIS PASS: FlameEater, the win tail, Shadow's goodbye,
--    the world save, checkpoint M. The savestate_graph.py `fire_out` edge
--    stays commented out; no new chest bits were opened (the route still
--    reaches the ambush before either rod chest).
--
-- 1. THE PHASE-BOUNDARY BUG (pass four's actual failure, per the
--    coordinator): the fight-phase driveUntil's old exit condition,
--    `not H.battleLoadStarted() and not H.battleActive()`, trusted a
--    SINGLE frame's read of two flags both documented flaky mid-fight
--    (battleLoadStarted's own header: "a total party wipe is all zeros,
--    which is also what a menu leaves, so this reports false";
--    battleActive() adds a screenshot check a single big-effect frame can
--    also fail). One bad frame handed off from the tactical driver
--    (F.frame(): items, revives, cures, boosted Fight) to the win-tail's
--    BLIND A-mash (no F.frame() call at all) WHILE THE FIGHT WAS STILL
--    LIVE -- confirmed by the coordinator's screenshots: TERRA and STRAGO
--    die in the pincer, LOCKE solos unsupported, no items/revives spent,
--    until the party wipes for real and Game Over auto-Continues
--    thamasa-night-v1. Pass four's own "M.gameOverFired stayed 0" claim
--    was correct but MEANINGLESS: that canary was an EXEC watch on
--    $CC/E568, and GameOver there is event-SCRIPT DATA the interpreter
--    only ever READS, never executes as CPU code -- the watch could not
--    have fired regardless of outcome. FIXED this pass: ambushAttempt/
--    flameEaterAttempt's phase-1 loop now keeps calling F.frame() for as
--    long as the battle module MIGHT still own the screen, and only
--    concludes "the battle is over" after CONFIRM_BATTLE_GONE=90
--    CONSECUTIVE confirming frames -- one bad frame can no longer end a
--    live fight early.
--
-- 2. WITH THE FIX, THE FIGHT GENUINELY PLAYS OUT -- AND STILL LOSES, ALL
--    5 SEEDS, TWICE (10 total attempts across two full runs, frame-for-
--    frame identical in matching pairs -- this route is deterministic).
--    Per-rung battle-frame-+1 partyhp (TERRA/LOCKE/STRAGO/-, entity
--    order), i.e. the state before the tactical driver has thrown a
--    single input:
--      attempt 1: 0,290,216,0    (TERRA dead on the pincer's opening hit)
--      attempt 2: 0,345,334,0    (TERRA dead)
--      attempt 3: 345,397,0,0    (STRAGO dead; TERRA/LOCKE untouched)
--      attempt 4: 0,292,116,0    (TERRA dead)
--      attempt 5: 0,237,16,0     (TERRA dead)
--    -- 4 of 5 seeds kill TERRA outright on the pincer's opening round,
--    before any input is possible; the 5th kills STRAGO instead. Every
--    attempt's monhp trace shows the SAME shape: monsters=4, one Balloon
--    already at 0/sh0 (self-destructed taking the opening kill with it,
--    consistent with the OT6 Exploder-at-full-HP mechanic the task brief
--    named), the other 2-3 Balloons sitting at FULL 555/sh1 (unbroken)
--    for THOUSANDS of battle frames while the 1-2 survivors fight on --
--    attempt 2's three remaining Balloons never move off 555 for the
--    entire attempt; attempt 4's best case chips two more down to 0 over
--    ~5400 frames before its own solo survivor (TERRA, Cure-healed
--    43->240->119) also runs out; attempt 3 gets one Balloon to 305/555
--    before losing. Items and revives ARE being spent this pass (Cure
--    casts landing 197hp, Fenix Down uses logged in the raw trace) --
--    this is the honest-tactics result, not an under-driven one. No
--    attempt reached a state where H.gameOverFired, map()==351, and
--    partyOf(STRAGO)~=0 were simultaneously true (the new win-verification
--    gate), so ambWon never flips and the ladder correctly reports "all 5
--    seed-ladder attempts lost" and fails the run rather than misreading
--    a loss as a win.
--
-- 3. STILL UNRESOLVED, FLAGGED RATHER THAN CHASED FURTHER: what a lost
--    attempt's field state actually IS after the loss.  Two GameOver-
--    adjacent canaries were tried and NEITHER fired on any of the 10 lost
--    attempts (lib/ot6.lua, both uncommitted): a READ watch on the
--    GameOver event script ($CC/E568, the coordinator's fix for the first
--    pass's blind EXEC watch -- turns out `_ca5ea9`'s `call GameOver` is
--    an 8-site, story-only path, not what a genuine in-battle wipe takes),
--    and this pass's own addition, an EXEC watch on TitleScreen
--    (cutscene_main.asm, $C2680C, the real title-screen module entry any
--    path back to the title screen should reach). Both stayed at 0
--    through every loss. What IS observed post-loss: map()==0 and
--    pos=(14,3792) at the final win-verification check, but the raw
--    per-frame tile trace shows map id READINGS BOUNCING among small
--    values (0, 3, 5) with position stuck near (8,7) rather than settling
--    on thamasa-night-v1's actual saved state (world map 0, position
--    (249,128)) -- which does not cleanly match "a clean SRAM reload" any
--    more than it matches pass four's original "stuck engine" theory (its
--    own probeDump/probeEventDump calls, still in this file, are the
--    instruments for whoever picks this up: they show the field state
--    genuinely mid-event, bank $CB, $050A still 1, TERRA/LOCKE/STRAGO
--    still valid party members, only ~90-6000 frames before the garbage
--    reading sets in). This does not change the balance verdict in #2 --
--    win-verification's map/roster check independently confirms every
--    attempt as a loss regardless of which theory of the post-loss state
--    is right -- but it is a real, still-open harness/engine question for
--    the next pass, distinct from the fight-balance question this pass
--    answers.
--
-- 4. VERDICT PER THE TASK'S OWN DECISION RULE: after honest tactics (a
--    fight-engaged driver: boosted Fight, TERRA's unboosted Ice, items,
--    Cure/Fenix Down revives) across 5 varied seeds, the ambush cannot be
--    won at this party level (TERRA/LOCKE/STRAGO, L16-ish, STRAGO freshly
--    joined) against 4x L22 Balloons (HP555 each) in a pincer whose
--    opening round routinely kills one party member (usually TERRA)
--    before any input is possible. This is the #74-style balance finding
--    the task and the coordinator's own directive both anticipated as a
--    legitimate outcome: the survey's L16-vs-L22 gap, made concrete.
--    FlameEater and checkpoint M were NOT reached this pass; the
--    savestate_graph.py `fire_out` edge stays commented out.
--
-- Files touched this pass: tools/tests/lib/ot6.lua (the TitleScreen exec
-- backstop added to the existing GameOver read-watch canary, both
-- uncommitted), this file (ambushAttempt/flameEaterAttempt's phase-1
-- debounce + phase-2 win-verification rewrite; removed the prior pass's
-- deliberate data-gathering stop -- the always-false 400-frame trace plus
-- forced error() -- probe instruments themselves are kept).
--
-- ---------------------------------------------------------------------
--
-- STATUS 2026-08-19 (issue #127, FOURTH pass -- SUPERSEDED, see the FIFTH
-- pass block above: this pass's "WON on attempt 1" was a lost fight
-- silently auto-Continuing to the world save, caught by an EXEC watch on
-- GameOver that could never fire because $CC/E568 is event-script DATA,
-- never CPU-executed code. Kept for its own still-valid archaeology
-- (sort_obj_work/$0803/$07fb reading, the probe methodology) but its
-- headline claim is wrong -- the blocker was DEEPER than post-win
-- because there never was a win):
--
-- 1. THE GAME-OVER CANARY WORKS AND THE AMBUSH IS REAL. tools/tests/
--    lib/ot6.lua's new M.gameOverFired exec canary on event GameOver
--    ($CC/E568) plus this file's lossReload() (reload the pre-fight blob
--    and clear M.gameOverFired the instant a real loss is detected, before
--    any A-mash can reach a Continue prompt) landed clean. Two full live
--    runs from thamasa-night-v1 (OT6_SRAM_CHECKPOINT + OT6_TIMEOUT=2400)
--    both won the (21,22) ambush (battle 45) on ATTEMPT 1 OF 5, frame-for-
--    frame identical (battle ends f20732, $050A clears f21833,
--    M.gameOverFired stayed 0 THE WHOLE ATTEMPT -- watched live). Pass
--    three's "silently auto-Continued Game Over" theory is DISPROVEN as
--    the cause of what follows: this reproduces on a CONFIRMED clean win
--    with zero Game Over and zero button presses of ours in the window
--    that matters (H.dialogWaiting() reads false throughout).
--
-- 2. THE REAL BLOCKER: post-win field control never returns, confirmed to
--    be a genuine non-walkable state, not a slow fade or a stuck
--    predicate. Live evidence (not through a savestate reload -- see #3
--    for why that matters), watched every frame with zero input from us:
--      f21833 (battle teardown) $0803=$0000 movByte=$10 map1f64=$2000
--      f21835  $0084=$01 (blocks hasControl) movByte=$02 (valid!)
--      f21836  $0084=$00 -> H.hasControl()=TRUE, tileAligned=TRUE,
--              $07fb=$0000 (TERRA's own object pointer -- LEGITIMATE,
--              not the $07d9 "empty slot" sentinel), $1a6d=$01,
--              $1850/51/57 (TERRA/LOCKE/STRAGO membership)=$C1/$69/$00
--              -- TERRA and LOCKE correctly read "in party 1"; STRAGO
--              reads $00, "in no party", the one clearly-wrong byte in
--              the group. bright()=0 (screen still black).
--    THIS PASS'S DECISIVE TEST: held DOWN for 40 frames starting the
--    instant hasControl()+tileAligned() went true (f21836), bypassing the
--    brightness gate entirely to ask "is this window really walkable".
--    Position never moved (pos=(8,7) before AND after). This confirms,
--    with better instrumentation, pass three's own probe_ambush_stall.lua
--    finding ("hasControl() reading true here is not evidence of a
--    walkable party") -- and rules out "the old settle predicate was just
--    waiting on the wrong flag (brightness)" as the fix. map1f64 reads
--    $2000 (worldMode()-shaped: &0x3FF=0<3) the whole time; position
--    settles at world-mode-flavored (8,7)/(14,3792)-ish readings
--    afterward, and a subsequent navTo (P3 leg) times out at 20000 frames
--    making zero progress, confirming the party truly cannot walk from
--    here by any means this pass tried.
--
-- 3. LIKELY ROOT CAUSE, precisely located via a live $7E-address write-
--    watch with PC capture (new: tools/tests/probe_ambush_poststall2.lua,
--    loads the ambush_won.mss savestate this pass's live run captured
--    right at the win and re-drives from there in seconds instead of
--    ~20 real minutes -- keep this probe, it is the fast iteration loop
--    the next pass needs). CAVEAT FIRST: the reloaded-savestate probe's
--    OWN trace of the SAME captured moment reads DIFFERENTLY from the
--    live run ($07fb=$07d9 "empty", $1850/51/57 all $00, vs the live
--    run's $07fb=$0000 valid and $1850/51=$C1/$69 valid) -- a savestate
--    round-trip through emu.createSavestate()/loadSavestate() does not
--    perfectly preserve this transient state, so trust the LIVE numbers
--    in #2, not the probe's post-reload numbers, for what the game is
--    actually doing; the probe is still useful for locating WHICH CODE
--    touches these addresses, just not for the exact values at each frame.
--    ff6/src/field/obj.asm's sort_obj_work (CalcObjPtrs/GetTopCharPtr/
--    CheckSlot1-4/CheckOtherSlots, ~obj.asm:3769-3900, called from
--    ff6/src/field/event.asm:577/748 and reachable via the `sort_obj`
--    event command) is the routine that (re)builds the $0803-$0866
--    object-pointer list every time it runs, per its own header comment:
--    "the first object in the list (the player object at $0803) is
--    always the first character in the active party... if there are no
--    characters in the active party, the CAMERA object acts as the
--    player object." CheckSlot1 skips writing $0803 for a character slot
--    whose $07fb/7fd/7ff/0801 pointer already reads the empty sentinel
--    $07d9 -- i.e. IF something upstream (battle teardown, or a missing
--    re-assertion) leaves $07fb empty when sort_obj_work next runs, this
--    routine will legitimately fall through to the camera object, which
--    is consistent with the probe's own (reload-tainted, see above)
--    $07fb=$07d9/$0803=$07B0-lands-on-object-slot-48(the last slot,
--    camera) trace. The likely missing piece: `_cbe622` (the ambush event,
--    event_main.asm:71907-72029) never re-asserts `party_chars`/`sort_obj`
--    after `battle 45` + `call _ca5ea9`, unlike `_cbe5e4` (the working
--    (4,10) floor-trigger scene just before it), which explicitly does
--    `party_chars TERRA, LOCKE, STRAGO` + `sort_obj` right after its own
--    battle-adjacent work and is the one piece of this map's scripted
--    spine confirmed to "run clean and repeatedly" every pass. `_ca5ea9`
--    itself is trivial (event_main.asm:14171-14174: `if_b_switch $40,
--    return; call GameOver`) and is shared with Dadaluma/TunnelArmr/
--    FlameEater without incident, so the bug is not in the shared gate --
--    it is specific to what `_cbe622` does (or omits) around it, most
--    likely interacting with the event's own `create_obj NPC_4..7` /
--    `delete_obj NPC_4..7` pair (a shape none of this map's OTHER working
--    scripted beats use). NOT FIXED THIS PASS: this is an event/engine
--    ASM change (most likely adding a `party_chars`/`sort_obj` call to
--    `_cbe622` after its battle, mirroring `_cbe5e4`), which needs
--    assembler-level verification against vanilla behavior and is out of
--    a route-generator script's scope to apply unilaterally. Filed for
--    the orchestrator/owner; this file cannot reach FlameEater or capture
--    checkpoint M until it lands.
--
-- 4. Two harness-side ideas tried and MEASURED NOT TO WORK, so the next
--    pass does not re-try them: (a) writing $0803 back to 0 every frame
--    once the game overwrites it (tools/tests/probe_ambush_poststall2.lua
--    still carries the commented-out attempt) keeps $0803 valid but
--    movByte at that pinned offset still reads 0, not 2 -- the real
--    blocker is deeper than this one pointer; (b) dropping the
--    bright()>=15 requirement from the "settled" predicate and walking
--    the instant hasControl()+tileAligned() go true (#2's decisive test)
--    -- the window is real by every flag this harness can read, but the
--    party still does not move, so this is not a settle-predicate bug at
--    all.
--
-- Files touched this pass: tools/tests/lib/ot6.lua (M.gameOverFired
-- canary, uncommitted -- see its own comment), this file (lossReload(),
-- the win-tail driveUntil's H.gameOverFired watch, allowGameOver=true on
-- H.run, the walk-test/trace block above the P3 leg),
-- tools/tests/probe_ambush_poststall2.lua (new fast reload-based probe,
-- caveat in #3 above). Checkpoint M (`fire-out-v1`) was NOT captured;
-- the savestate_graph.py `fire_out` edge stays commented out; no new
-- chest bits were opened (the route reaches the ambush before either
-- rod chest, per the island graph in the next STATUS block down).
--
-- ---------------------------------------------------------------------
--
-- STATUS 2026-08-19 (issue #127 stall investigation, pass three): the
-- post-ambush "field-control stall" documented below (the [ambush dbg]
-- dump at f17665, movByte=$10, map1f64=$2000) is NOT a predicate misread.
-- It is a real, reproducible engine event: winning the (21,22) scripted
-- ambush (battle 45) on this event-only map is followed, ~130-380 real
-- frames later, by the game visibly leaving map 351 altogether and
-- landing back on the WORLD MAP, then Thamasa TOWN (343) at (23,46) --
-- the same tile this generator's own step 1 lands on -- WITH THE PARTY
-- ROSTER REVERTED to the pre-inn state (TERRA/LOCKE/SHADOW, Strago absent,
-- confirmed via a live field-menu screenshot: build/states/shots/
-- stall_probe3_after_menu_try.png shows TERRA/LOCKE/SHADOW, no Strago).
-- This looks exactly like the checkpoint being silently re-Continued, not
-- a stuck predicate.
--
-- Evidence (tools/tests/probe_ambush_stall.lua, run 3x refining the
-- method -- runs need `OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/
-- thamasa-night-v1 OT6_TIMEOUT=1800 tools/tests/run.sh ...`, NOT bare
-- run.sh, or it boots a fresh game and never reaches the ambush at all):
--   * take 1 used H.repeatN(60,{H.call(setPad)}) to "hold" a direction --
--     wrong: H.call never returns "frame", so seqStep drains all 60
--     iterations in one real frame (see ot6.lua's seqStep/M.call). No real
--     time passed, so that run's movement test was meaningless (though it
--     incidentally showed hasControl() flipping true ~10 real frames after
--     the dump). Fixed in takes 2-3 with H.hold(dir)+H.waitFrames(n), the
--     same idiom H.pressButtons already uses.
--   * take 2 (proper real-frame holds, but run only after a 400-frame
--     passive delay) found hasControl()=true from dump+~4f to dump+~130f
--     (movByte=$02, position holds steady at tile (8,7)), then a relapse
--     into movByte=$E9 / pxY=$ED00-ish garbage that outlasted the rest of
--     that run (260+ more frames, zero pixel displacement under 4x60
--     frames of held directional input) -- but the movement test landed
--     entirely in the BAD window by accident (the delay overshot the good
--     one), so it didn't test whether the party could actually walk while
--     hasControl() genuinely read true.
--   * take 3 fixed that: high-resolution (every real frame) logging plus a
--     movement test fired INSIDE the dump+4..130f good window. Verdict:
--     the party does NOT move. Four directions x 20 real frames each,
--     hasControl()=true and movByte=$02 (nominally "user-controlled")
--     before AND after every hold, yet pixel position (0x80,0x70, tile
--     (8,7)) never changes by even one pixel. hasControl() reading true
--     here is not evidence of a walkable party.
--   * Past dump+~130f (during the 4th direction hold, "right", though the
--     SAME transition happens on an equivalent zero-input passive wait at
--     the same offset -- it is time-triggered, not input-triggered):
--     $1f64 flips from $2000 to intermediate garbage then settles at
--     $0157 (343, Thamasa town); position settles at (0x170,0x2E0) = tile
--     (23,46); an event runs (eventRunning()=true) for ~35 frames partway
--     through (probably a map-load startup event); brightness ramps
--     0->15 TWICE (two fade cycles) before the state goes rock-stable for
--     the remaining 400+ observed frames: hasControl=true, tileAligned=
--     true, bright=15, movByte=$02, map=343, position (23,46).
--     build/states/shots/stall_probe3_after_inwindow_moves.png (taken
--     right as the transition starts) shows the WORLD MAP, not the house
--     -- a small island at night, party standing on it. worldMode()
--     ($1f64 & 0x3FF < 3) was ALREADY true at $2000 from the very first
--     dump, so the "good window" was likely already mid-transition the
--     whole time; the tile-(8,7)-looking reads were stale leftover field-
--     object bytes, not a genuine walkable field state.
--   * The field menu (X) DOES open successfully at every point tested
--     (ZMENUSTATE hits $05), including inside the "bad" window -- menu
--     access is gated separately from hasControl() and is not informative
--     about whether the party can walk.
--   * The settled end state's own field-menu screenshot
--     (stall_probe3_after_menu_try.png) shows party TERRA Lv14 / LOCKE
--     Lv15 / SHADOW Lv14 -- Shadow, not Strago. That is the checkpoint's
--     OWN pre-inn roster, not this run's actual party (which had joined
--     Strago and lost Shadow hours of real playtime earlier in the SAME
--     run). This is the strongest single piece of evidence: something
--     about winning battle 45 on this map's floor trigger reverts the
--     session to look like the SRAM checkpoint was just re-Continued,
--     not merely a stale-memory-read predicate bug.
--
-- Verdict per the task's own decision rule ("if movement does NOT work:
-- capture the evidence and stop -- report as a real engine interaction"):
-- movement does not work, and the failure is far larger than a stuck
-- predicate -- it looks like a full session/checkpoint revert triggered by
-- winning this specific scripted battle. Do NOT "fix" this by loosening
-- hasControl()/mapId() waits in houseWarp/ambushAttempt/settle: that would
-- let the generator drive forward on a WORLD/TOWN map believing it is
-- still on map 351, silently producing a corrupt or misleading checkpoint.
-- Filed for the orchestrator; not chased further this pass (root cause
-- needs either a real-hardware/vanilla comparison of event_trigger.asm's
-- (21,22) record and _cbe622/_ca5ea9's actual post-battle behavior, or
-- instrumentation this pass didn't build to catch the exact instruction
-- that touches $1f64/$086a/$086d/$1850 during the dump+130..380f window).
-- The route below (islands 1/28/4/12/26/24, FlameEater) was NOT re-walked
-- this pass as a result -- see the caller's final report.
--
-- ---------------------------------------------------------------------
--
-- STATUS 2026-08-19 (previous pass): the previous pass's mystery is SOLVED.
-- The "one-way relocation" at (4,3)->(4,38) is not a scripted event or an
-- engine tile-fall at all: it is an ordinary SAME-MAP short_entrance
-- record (src=(4,3) map=351 dest=(4,38), flags $01;
-- ff6/src/field/trigger/short_entrance.dat offset $167a, decoded by hand
-- against short_entrance.inc's ITEM_SIZE=6 layout). event_trigger.asm's
-- map-351 block (3 records: (4,10)/(21,22)/(46,53)) and npc_prop.asm's
-- (20 make_npc records, all decoded, coordinates below) between them
-- explain NOTHING south of the landing pocket, because the mechanism
-- neither of those tables can express (a same-map warp) lives in a THIRD
-- table this pass had not yet read. Map 351's short_entrance block runs
-- $167a..$16e0 (17 records = one landing-pocket exit plus 8 forward/return
-- pairs). Decoded and cross-checked against a live grid dump (a new probe,
-- tools/tests/probe_thamasa_house_map.lua, boots the checkpoint, rides the
-- same verified boot/inn/fire/join/  (4,10)-trigger sequence, then reads
-- the LIVE decompressed tile-property tables ($7E7600/$7E7700 through the
-- BG1 tilemap byte, i.e. exactly what H.canStep/H.bfsPath already read)
-- across the whole 64x64 map in one pass -- no walking, so no bfsPath
-- node-cap risk): the map is NOT one contiguous floor. It is 35 separate
-- cardinally-disconnected tile islands (a Python flood fill over the dump
-- confirms zero walkable path between any two of them), stitched together
-- ONLY by the 8 short_entrance pairs. This is why the old plan's
-- navTo(1,0) "explore the north room" reasoning was doomed regardless of
-- BFS cap size: there IS no walkable route from the landing pocket to
-- (4,52)/(21,22)/(45,7)/(46,53) at all, by design (the burning-house
-- "each room is its own pocket, doors do the connecting" structure, same
-- idea as the town's long/short entrances, just entirely internal to one
-- map ID). The full island graph, landing to every objective:
--   island 0  (landing pocket + "north room", the (4,10) trigger lands
--              here) --(4,3)->(4,38)--> island 13 (return via (4,39) or
--              (5,39)->(4,5))
--   island 13 --(2,24)->(26,36)--> island 11 (the (21,22) AMBUSH trigger
--              lives here; return via (26,37)->(2,26))
--   island 11 --(26,21)->(21,9)--> island 1 (the north corridor; return
--              via (21,10)->(26,23))
--   island 1  --(28,3)->(4,55)--> island 28 (FIRE ROD chest (4,52) is
--              here, a dead-end spur; return via (4,56)->(28,5))
--   island 1  --(23,3)->(46,27)--> island 12 (the east wing; return via
--              (46,28)->(23,5))
--   island 12 --(49,21)->(45,10)--> island 4 (ICE ROD chest (45,7) is
--              here, a dead-end spur; return via (45,11)->(49,23))
--   island 12 --(43,21)->(21,54)--> island 26 (the south hall; return via
--              (21,55)->(43,23))
--   island 26 --(21,49)->(46,54)--> island 24 (FLAMEEATER trigger (46,53)
--              is here; no return recorded -- one-way into the boss room,
--              consistent with the win tail's own load_map 349 exit)
-- houseWarp() below rides each of these exactly like crossDoor() rides a
-- town door, except the arrival test is a coordinate match rather than a
-- map-ID change (src map == dest map == 351 for all of them, so
-- crossDoor's own "map() ~= startMap" test would never fire here).
-- This solves the KO risk the previous pass flagged too: the "contact
-- battle at (4,38)" that cost TERRA and STRAGO both KO'd was not caused by
-- the relocation itself (there is no such coupling) -- it was an ordinary
-- wandering-flame contact fought blind by navTo's own tactical driver
-- while pathing toward a target it could never reach; walking each island
-- deliberately (with a care() stop at every warp) should not change the
-- flame encounter rate but keeps healing current between them, per the
-- task's "care between chained fights" rule and #128's healer-lock note.
-- Everything through Strago's join and the map-351 load at (4,11) remains
-- VERIFIED per the prior pass (build/test-runs/fire_out.*). The house
-- graph above is decoded from source + a live grid probe but the walk
-- through it, the FlameEater fight, and the win tail below are being run
-- for the first time this pass; see the caller's final report for the
-- live result.
--
-- gen_thamasa_fire.lua -- v0.13 step L->M (issue #127, "the Thamasa wave"):
-- docs/design/thamasa-route.md section 1, segment 2-4 (the Thamasa fire
-- block).  Cold-boots the tracked `thamasa-night-v1` SRAM checkpoint
-- (world outside Thamasa, $008D=1, party TERRA-LOCKE-SHADOW, pre-inn) the
-- way gen_vector_crash cold-boots `gate-cave-save-v1`: this state is a
-- checkpoint= graph entry, not a prev= savestate link, so every run starts
-- from the real Continue screen.  Generates checkpoint M `fire-out`: world
-- outside Thamasa, $0090=$0091=$0092=1, party TERRA-LOCKE-STRAGO,
-- $02F3=0 (SHADOW gone).
--
-- The route (event_main.asm citations from docs/design/thamasa-route.md
-- section 1 segments 2-4, cross-checked live against the disassembly --
-- see the SURVEY CORRECTIONS below):
--
--  1. Re-enter town the same way K->L did: held RIGHT onto the (250,128)
--     world trigger -> map 343 (23,46).
--  2. The inn.  SURVEY CORRECTION: the survey names no coordinates for the
--     inn door or the innkeeper.  Decoded live from the disassembly rather
--     than guessed: short_entrance.dat's map-343 block has a record
--     src=(12,19) -> map 90+256=346 dest=(23,23) (the "+256" offset is
--     measured against the already-known Strago's-house record,
--     src=(29,13) -> map 93+256=349 dest=(37,24), which matches
--     thamasa-route.md exactly).  So the inn's exterior door is 343
--     (12,19) -> interior map 346 (23,23), and NPCProp::_346's first
--     record (obj $10, the "$10 + record order" rule gen_thamasa_arrive's
--     Strago talk already relies on) is the innkeeper at (24,15), event
--     _cbd73f: "1 GP per night. Why not relax for a spell? 0: Yes / 1: No"
--     (dlg $079D, since $008D=1 and $007D=1 by the time L is reached).
--     Choosing Yes (the default cursor position, so plain edge-A works)
--     runs _cbd7ac: take_gil 1, the innkeeper walks off-screen, and since
--     $008D=1 it falls straight into _cbdcc7 -- the whole night/fire scene
--     -- with NO further choice screens.  So this is one advanceStory-style
--     drive from the Yes confirm to control settling back on map 343.
--  3. The night scene (_cbdcc7, :70419): SHADOW leaves the party
--     (char_party SHADOW,0 :70456), the fire starts, $0190=1 $008E=1
--     (:70634-70635), Shadow runs off after Interceptor and goes
--     unavailable ($02F3=0 :70653).  Control returns on map 343 at
--     (12,21), retiled burning (mod_bg_tiles under $008E && !$0090).
--  4. Talk to Strago at the house door.  This is an NPC event, NOT the
--     (29,13) tile door: NPCProp::_343 record 5 (index 4, 0-based;
--     make_npc {39,24}, $0508, event _cbde30) -- so obj $10+4 = $14.
--     Discovered live (findNpc below) rather than trusted blind, because
--     map 343 carries far more than 16 make_npc records across its many
--     switch-gated variants and the "$10 + order" rule is unverified past
--     16 entries on this specific map.
--     The scene ends with Strago joining (char_party STRAGO,1 + $02E7=1
--     $02F7=1, :71790-71801) and load_map 351 {4,11} (:71852), forced
--     entry party TERRA-LOCKE-STRAGO (:71874).
--  5. Map 351, the burning house (event-only; every exit is scripted).
--     Two chests, visible on the walk (chest_visibility.py / the #84
--     rule): Fire Rod bit 104 (4,52), Ice Rod bit 105 (45,7) -- decoded
--     live from treasure_prop.dat (audit_chests.py's own table), not
--     guessed.  Twelve wandering flame NPCs (make_npc ... set_npc_movement
--     RANDOM, npc_prop.asm:15717-15860) fire battle 31 (formation 158/159,
--     Balloon x3/x6) on contact; a scripted four-Balloon ambush sits on
--     the (21,22) FLOOR TRIGGER (event_trigger.asm:1715, not an NPC).
--     FlameEater's fight is ALSO a floor trigger, (46,53)
--     (event_trigger.asm:1716, _cbe767) -- there is no FlameEater sprite
--     record in NPCProp::_351 at all, so the previous plan's assumption of
--     a contact-talk NPC there was wrong; it fires on tile entry like the
--     ambush.  The trigger's own script re-forces party order
--     STRAGO,TERRA,LOCKE (party_chars STRAGO,TERRA,LOCKE, :72101) right
--     before `battle 79` (:72124), and the post-battle gate is
--     `call _ca5ea9` -- the SAME win/lose gate Dadaluma and TunnelArmr use
--     (a real win sets $0090=1 at :72129 and despawns the trigger NPC; a
--     loss falls into vanilla GameOver), so the ladder below watches
--     $0090 rather than any battle-menu flag.
--  6. Win tail: the Relm/Interceptor rescue, Shadow's smoke-bomb exit, the
--     night talk at Strago's house (load_map 349 {64,16} :72613), ending
--     $0091=1 $0098=1 (:73000-73001), control in the house, party
--     TERRA-LOCKE-STRAGO.
--  7. Leaving the house through 349 (37,25) (event_trigger.asm:1708,
--     gated $0091 && !$0092) plays Shadow's goodbye on town 343 (29,15):
--     remove_equip SHADOW (:73018, his gear returns to inventory),
--     $0092=1 (:73302).  This MUST run before the town is left, per the
--     task brief -- it is the last chance this segment gets at it.
--  8. Out of town the way K->L measured it (long_entrance.dat map-343
--     south strip, src (19,48) len 6, landing world (249,128)) and the
--     real Save UI at slot 3 -- checkpoint M, `fire-out-v1`.
--
-- Ice Rod: not driven as an in-battle item cast this pass.  newFightDriver
-- has no generic "cast an item's attached spell" branch (only the named
-- Tonic/Potion/Fenix Down heal line and the Tools/Blitz skill lines), and
-- building a bespoke Item->target steer for one rod cast was cut for scope
-- -- the chest is opened and carried, but FlameEater is fought with the
-- lib driver's plain kit (boosted Fight from whoever holds it, TERRA's
-- Cure).  This is the "verify what the engine supports" question the task
-- flagged as open; it stays open.  Filed rather than guessed at.
--
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
-- ^ run.sh refuses, before boot, any OT6_SRAM_CHECKPOINT whose manifest
--   declares a different persistent_layout.
local H = dofile("tools/tests/lib/ot6.lua")

local SAVE_SELECT = 0x14
local ZMENUSTATE = 0x26
local TERRA, LOCKE, STRAGO, SHADOW = 0, 1, 7, 3
local FIRE_ROD, ICE_ROD = 0x35, 0x36
local TONIC, POTION, FENIX_DOWN = 0xE8, 0xE9, 0xF0
local ICE_SPELL = 0x01
local saveArg = nil

-- ---- PREP (owner's ruling, issue #127, ninth pass): the ROOT CAUSE was
-- never the fight plan -- it was an UNPREPARED party.  Every prior pass
-- fought the ambush and FlameEater with whatever gear/espers checkpoint L
-- happened to carry (owner playtested this live and confirmed the fight is
-- winnable once the party is actually geared).  No enemy stat changes; the
-- party preps instead, the same spirit as the earlier grind attempt this
-- pass replaces outright (grinding is fine but not needed here -- prep is
-- the fix).  Item ids are from ff6/notes/battle-lists.txt's weapon/armor
-- section, cross-checked against the checkpoint's own bag by
-- probe_state.lua (all four pieces per character, plus the ambush's own
-- item shop restock, confirmed present).
local TERRA_GEAR = { { 0, 0x0E }, { 1, 0x5C }, { 2, 0x6E }, { 3, 0x89 } }
  -- Blizzard(w) / Mithril Shld(sh) / Bandana(he) / Mithril Vest(ar)
local LOCKE_GEAR = { { 0, 0x0F }, { 1, 0x5A }, { 2, 0x73 }, { 3, 0x86 } }
  -- ThunderBlade(w) / Buckler(sh) / Head Band(he) / Kung Fu Suit(ar)
-- Esper indices (genju_prop.asm's own numbering, verified 2026-08-20):
-- SHIVA=2 grants {ICE, OSMOSE, SHELL}; MADUIN=6 grants {FIRE, ICE, BOLT} --
-- both are real ICE-spell donors, so one goes to TERRA and the other to
-- LOCKE, each giving that character the boosted, multi-target Ice cast the
-- fight plan below leads with (OT6 folds a boosted base spell to its next
-- tier via Ot6FoldTbl -- Ice -> Ice2 -> Ice3 -- so the base grant is enough).
-- BISMARK=7 was originally read as a water-spell donor; genju_prop.asm's
-- actual grant list is {HASTE, SLOW, {}} -- no castable Water spell exists
-- in this build at all (Sea Song is Bismark's own once-per-battle summon,
-- not a Magic-list grant).  Given to STRAGO regardless, by elimination (the
-- two Ice donors are already spoken for) and because Haste on the party's
-- free-attacking Lore-caster is a real, if secondary, benefit; his own Aqua
-- Rake stays the fight's actual water-elemental answer.
local SHIVA_ESPER, MADUIN_ESPER, BISMARK_ESPER = 2, 6, 7
-- char-select row, resolved live rather than hardcoded -- the same
-- (partyByte>>3)&3 read M.equipLoadout/M.equipWeapon already trust,
-- wrapped as a function so M.equipEsper (extended this pass to accept one,
-- matching M.equipWeapon's own targetPos) can resolve it lazily.  Needed
-- for STRAGO especially: his join-time party row isn't asserted anywhere
-- in this file, so guessing it would be exactly the kind of guess this
-- whole pass is supposed to stop making.
local function charPos(charId)
  return function() return (H.readByte(0x1850 + charId) >> 3) & 0x03 end
end

-- ISSUE #127 PROBE INSTRUMENTATION (data-gathering only, not part of the
-- route): dump the exact byte obj.asm's sort_obj_work reads for
-- CheckSlot1-4/CheckOtherSlots -- $0867+41*id, bit $40 = enabled, low 3
-- bits = party number -- for TERRA/LOCKE/SHADOW/STRAGO, plus $1a6d (active
-- party number) and the four slot object pointers $07fb/07fd/07ff/0801 and
-- leader $0803, at three moments (a known-good point right after the fire
-- scene, immediately before battle 45/the ambush fires, and at the post-win
-- stall).  Also arms a write-watch (with PC) on all four $0867+41*id bytes,
-- armed before the house is entered, ring-buffered to the last 40 hits.
local PROBE_IDS = { { 0, "TERRA" }, { 1, "LOCKE" }, { 3, "SHADOW" }, { 7, "STRAGO" } }
-- ISSUE #127 PROBE, COORDINATOR'S FINAL DATA ROUND: frames to screenshot
-- across the 1101-frame win-tail teardown window (f20732->f21833) and the
-- post-stall corruption (f21958) -- frame numbers hardcoded from the prior
-- pass's confirmed frame-for-frame-identical repro from this checkpoint.
local SHOT_FRAMES_TAIL = {
  [20740] = true, [20900] = true, [21100] = true, [21300] = true,
  [21500] = true, [21700] = true, [21958] = true, [22100] = true,
}
-- ISSUE #127 PROBE, THE WHITE-BOX TRACE: the event PC through the ejection
-- window (f21200-21900), logged on every change -- shared across the two
-- separate step blocks that tick frames in this range (the win-tail
-- A-mash loop and the post-stall driveUntil), via this file-scope upvalue.
local peTrailLast = nil
local _cbe622Sym = nil
do
  local ok, v = pcall(H.sym, "_cbe622")
  if ok then _cbe622Sym = v end
end
local function probePcTrail()
  if H.frame < 21200 or H.frame > 21900 then return end
  local bank, hi, lo = H.readByte(0x00e7), H.readByte(0x00e6), H.readByte(0x00e5)
  local e8 = H.readWord(0x00e8)
  local wm = H.worldMode()
  local m1f64 = H.readWord(0x1f64)
  local key = string.format("%02X:%02X%02X:%04X:%s:%04X", bank, hi, lo, e8,
    tostring(wm), m1f64)
  if key ~= peTrailLast then
    peTrailLast = key
    H.log(string.format(
      "[probe127-pctrail] f%d eventPC=%02X:%02X%02X e8=$%04X worldMode=%s 1f64=$%04X",
      H.frame, bank, hi, lo, e8, tostring(wm), m1f64))
  end
end
local function probeDump(tag)
  local parts = {}
  for _, e in ipairs(PROBE_IDS) do
    local id, name = e[1], e[2]
    local b = H.readByte(0x0867 + 41 * id)
    parts[#parts + 1] = string.format("%s=$%02X(en=%d,pty=%d)",
      name, b, (b & 0x40) ~= 0 and 1 or 0, b & 0x07)
  end
  H.log(string.format(
    "[probe127 %s] f%d 1a6d=$%02X 07fb=$%04X 07fd=$%04X 07ff=$%04X " ..
    "0801=$%04X 0803=$%04X %s",
    tag, H.frame, H.readByte(0x1a6d), H.readWord(0x07fb), H.readWord(0x07fd),
    H.readWord(0x07ff), H.readWord(0x0801), H.readWord(0x0803),
    table.concat(parts, " ")))
end
local probeHits = {}
local function probePc()
  local s = emu.getState()
  return string.format("%02X:%04X", s["cpu.k"] or 0, s["cpu.pc"] or 0)
end
local function armProbeWatch()
  for _, e in ipairs(PROBE_IDS) do
    local id, name = e[1], e[2]
    local addr = 0x7E0867 + 41 * id
    emu.addMemoryCallback(function(a, v)
      local line = string.format(
        "[probe127 watch] f%d pc=%s %s($0867+41*%d) <- $%02X",
        H.frame, probePc(), name, id, v)
      probeHits[#probeHits + 1] = line
      if #probeHits > 40 then table.remove(probeHits, 1) end
      H.log(line)
    end, emu.callbackType.write, addr, addr)
  end
  H.log("[probe127] write-watch armed on $0867+41*{0,1,3,7} (TERRA/LOCKE/SHADOW/STRAGO)")
end

-- Owner's insight: control handed to the CAMERA object is normal MID-SCENE
-- semantics (sort_obj_work falls back to it whenever no character is in the
-- active party, which is also true while an event owns the stage), so the
-- stall may be the event engine still running rather than corrupted party
-- bytes. This dumps the raw event-engine state field-ram.txt documents
-- ($E1 waiting-flags, $E2 object-to-wait-for, $E3 pause counter, $E5-E7
-- event PC, $E8 event stack pointer, $EA event opcode, $DA/$DC current
-- object) plus whether the party/camera position sits on the (21,22)
-- ambush trigger tile -- _cbe622 (event_main.asm:71906) sets switch
-- $050A=1 unconditionally as its FIRST action with no if_b_switch guard
-- ahead of it, so $050A is a teardown-completion flag the SAME script
-- clears at its own end (:72009), not a one-shot latch a re-entry would be
-- blocked by; if tile entry is re-detected while parked on (21,22), this
-- floor trigger can refire.
local function probeEventDump(tag)
  local sw050A = (H.readByte(0x1E80 + (0x050A >> 3)) >> (0x050A & 7)) & 1
  local e1 = H.readByte(0x00e1)
  H.log(string.format(
    "[probe127-event %s] f%d ctl=%s algn=%s ev=%s dlg=%s " ..
    "e1(wait o/f/s)=$%02X(o=%d,f=%d,s=%d) e2(objWait)=$%02X " ..
    "e3(pauseCnt)=$%02X eventPC(bank:e6e5)=%02X:%02X%02X e8(evStackPtr)=$%04X " ..
    "ea(opcode)=$%02X da(curObjOfs)=$%02X dc(curObj)=$%02X pos=(%d,%d) " ..
    "onAmbushTile(21,22)=%s sw($050A)=%d",
    tag, H.frame, tostring(H.hasControl()), tostring(H.tileAligned()),
    tostring(H.eventRunning()), tostring(H.dialogWaiting()),
    e1, (e1 >> 7) & 1, (e1 >> 6) & 1, (e1 >> 5) & 1,
    H.readByte(0x00e2), H.readByte(0x00e3),
    H.readByte(0x00e7), H.readByte(0x00e6), H.readByte(0x00e5),
    H.readWord(0x00e8), H.readByte(0x00ea),
    H.readByte(0x00da), H.readByte(0x00dc),
    H.fieldX(), H.fieldY(),
    tostring(H.fieldX() == 21 and H.fieldY() == 22), sw050A))
end

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function partyOf(c) return H.readByte(0x1850 + c) & 0x07 end
local function seq(steps) return H.cond(function() return true end, steps) end

local function calm(n, extra)
  local cnt = 0
  return function()
    local ok = H.hasControl() and H.tileAligned() and (not extra or extra())
    cnt = ok and cnt + 1 or 0
    return cnt >= n
  end
end

-- edge-A through dialogs/scenes until settled (gen_thamasa_arrive's settle)
local function settle(maxFrames, what)
  local ph = 0
  return H.driveUntil(function()
    return H.hasControl() and H.tileAligned() and not H.dialogWaiting()
       and not H.battleLoadStarted()
  end, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      H.setPad(H.dialogWaiting() and (ph < 4 and { "a" } or {}) or {})
    end),
  }, what)
end

local function pressWalk(dir, pred, maxFrames, what)
  local ph = 0
  return H.driveUntil(pred, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then
        H.setPad({ l = true, r = true }); return
      end
      if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
      H.setPad({ [dir] = true })
    end),
  }, what)
end

-- gen_thamasa_arrive's crossDoor, unchanged
local DIAGSTAGE = {
  { 0, 1, "up" }, { 0, -1, "down" }, { -1, 0, "right" }, { 1, 0, "left" },
  { -1, 1, "upright" }, { -1, -1, "downright" },
  { 1, -1, "downleft" }, { 1, 1, "upleft" },
}
local function crossDoor(sx, sy, dm, dx, dy, what, opts)
  opts = opts or {}
  local pick, startMap
  local function stage()
    if not pick then
      for _, c in ipairs(DIAGSTAGE) do
        local cx, cy, move = sx + c[1], sy + c[2], c[3]
        local press = H.movePress(move)
        if H.bfsPath(cx, cy) and (press == move or H.canStep(cx, cy, move)) then
          pick = { cx, cy, press }; break
        end
      end
      pick = pick or { sx, sy + 1, "up" }
      H.log(string.format("%s: staging (%d,%d), hold %s into (%d,%d)",
        what, pick[1], pick[2], pick[3], sx, sy))
    end
    return pick
  end
  local settled = calm(20)
  local aPhase = 0
  return seq({
    H.call(function() pick, startMap = nil, map() end),
    H.navTo(function() return stage()[1] end, function() return stage()[2] end,
      { maxFrames = 9000, playBattles = "tactical", healer = TERRA, bank = 3,
        items = true, avoid = opts.avoid,
        arrive = function() return map() ~= startMap end }),
    H.driveUntil(function()
      return map() ~= startMap or (H.fieldX() == dx and H.fieldY() == dy)
    end, 1800, {
      H.call(function()
        aPhase = (aPhase + 1) % 8
        if H.dialogWaiting() then H.setPad(aPhase < 4 and { "a" } or {}); return end
        H.setPad({ [stage()[3]] = true })
      end),
    }, what),
    H.release(),
    H.waitUntil(settled, 1800, what .. ": far-side control"),
    H.waitUntil(function() return bright() >= 15 end, 900, what .. ": fade-in", 10),
    H.waitFrames(30),
    H.call(function()
      H.assertEq(map(), dm, what .. ": landed on the right map")
      H.log(string.format("[ot6] %s: DONE (%d,%d) frame=%d", what,
        H.fieldX(), H.fieldY(), H.frame))
    end),
  })
end

-- Live NPC lookup: scan object slots 16..31 for whichever sits nearest
-- (x,y), rather than trust the "$10 + record order" arithmetic past 16
-- make_npc records on one map (see the header's survey correction).
local function objAt(idx)
  local off = 0x29 * idx
  return H.readWord(0x086a + off) >> 4, H.readWord(0x086d + off) >> 4
end
local function findNpc(x, y, fallback)
  local best, bestD = nil, nil
  for i = 16, 31 do
    local ox, oy = objAt(i)
    local d = math.abs(ox - x) + math.abs(oy - y)
    if (ox ~= 0 or oy ~= 0) and (not bestD or d < bestD) then
      best, bestD = i, d
    end
  end
  H.log(string.format(
    "[npc] nearest object to (%d,%d): slot $%02X at distance %d (fallback $%02X)",
    x, y, best or 0, bestD or -1, fallback))
  return best or fallback
end

-- chaseTalk needs a concrete object index at construction time (every step
-- in an H.run list is built before the emulator boots -- gen_tunnelarmr's
-- posOf note), but the door NPC's slot is only knowable live.  This is
-- M.chaseTalk's body (lib/ot6_field.lua) with the one line that reads
-- objIdx replaced by a call to idxFn() every frame instead.
local function chaseTalkLazy(idxFn, maxFrames, what, opts)
  opts = opts or {}
  local ph, hb = 0, 0
  local done = opts.done or function()
    return H.readByte(0x056f) >= 2 and H.dialogWaiting()
  end
  return H.driveUntil(done, maxFrames or 9000, {
    H.call(function()
      ph = (ph + 1) % 8
      hb = hb + 1
      if H.battleLoadStarted() then
        for s = 0, 5 do
          if H.readByte(0x3aa8 + s * 2) % 2 == 1 then H.killbit(s) end
        end
        H.setPad(ph < 4 and { "a" } or {})
        return
      end
      if H.readByte(0x056f) >= 2 then H.setPad({}); return end
      if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
      if not (H.hasControl() and H.tileAligned()) then H.setPad({}); return end
      local objIdx = idxFn()
      local ox, oy = objAt(objIdx)
      local px, py = H.fieldX(), H.fieldY()
      local dx, dy = ox - px, oy - py
      if math.abs(dx) + math.abs(dy) == 1 then
        local dir
        if dx == 1 then dir = "right" elseif dx == -1 then dir = "left"
        elseif dy == 1 then dir = "down" else dir = "up" end
        H.setPad(ph < 4 and { "a", [dir] = true } or { [dir] = true })
        return
      end
      local best, bestC
      for _, c in ipairs({ { ox, oy + 1 }, { ox - 1, oy },
                           { ox + 1, oy }, { ox, oy - 1 } }) do
        local p = H.bfsPath(c[1], c[2])
        if p and (not best or #p < #best) then best, bestC = p, c end
      end
      if hb % 300 == 0 then
        H.log(string.format(
          "[chaseTalkLazy dbg] %s: f%d party=(%d,%d) obj$%02X=(%d,%d) " ..
          "best=%s bestLen=%s", what, H.frame, px, py, objIdx, ox, oy,
          bestC and string.format("(%d,%d)", bestC[1], bestC[2]) or "NONE",
          best and tostring(#best) or "-"))
      end
      if best and #best > 0 then
        H.setPad({ [H.movePress(best[1])] = true })
      else
        H.setPad({})
      end
    end),
  }, what or "chaseTalkLazy")
end

-- MEASURED (2026-08-19): map 351 is big enough that H.bfsPath's 4096-node
-- cap (nodes are (x,y,z) triples; ot6_field.lua:503) goes dry on a single
-- long query -- the Fire Rod's stand ((4,52), ~40 tiles straight down the
-- entry shaft) came back "no path" even though the shaft is a plain
-- corridor, the same trap gen_tunnelarmr's header documents for map 75
-- ("long BFS queries... run the 4096-node cap dry and answer 'no path' for
-- tiles that are plainly walkable"; its fix there is a chain of short
-- hand-placed waypoints).  Map 351 has no waypoint table here, so instead
-- of hard-coding one, creepXY hands navTo a MOVING target: a function that
-- always names a point at most `step` tiles away in the straight-line
-- direction of the real destination, and the real destination once within
-- `step`.  navTo re-resolves tx()/ty() on every replan, so this is a
-- continuous short-hop pursuit that converges on the real target through
-- many small (cheap, cap-safe) BFS queries instead of one long one.
local function creepXY(tx, ty, step)
  step = step or 14
  local function pt()
    local px, py = H.fieldX(), H.fieldY()
    local dx, dy = tx - px, ty - py
    local dist = math.abs(dx) + math.abs(dy)
    if dist <= step or dist == 0 then return tx, ty end
    return px + math.floor(dx * step / dist), py + math.floor(dy * step / dist)
  end
  return function() return (pt()) end,
         function() local _, y = pt(); return y end
end
local function creepNav(tx, ty, opts, step)
  local fx, fy = creepXY(tx, ty, step)
  return H.navTo(fx, fy, opts)
end

-- a care stop that skips (logged) rather than hangs when the field isn't
-- settled -- zozo4's climbCare rule, needed on map 351's scripted stretches
-- SUPERSEDED (coordinator's directive, tenth pass, owner doctrine: "do ALL
-- prep OUTSIDE combat... full-heal between EVERY fight... combat turns are
-- for OFFENSE only"): the 2026-08-19 finding below (H.fieldCare refused
-- every plan and hung closing the menu, on this map, regardless of party
-- state) is STALE -- this pass's own pre-ambush top-off calls H.fieldCare
-- directly on map 351 with TERRA actually dead (0/345) and it worked
-- clean, live: "[prep] pre-ambush top-off done: TERRA 345/345 LOCKE
-- 397/397 STRAGO 434/434", no refusal, no hang. Whatever library bug the
-- 2026-08-19 note hit has since been fixed elsewhere (the STATUS header's
-- own "the old 'fieldCare broken on 351' was our lib bug" note, confirmed
-- here). care() now spends the menu on this map like every other -- kept
-- as its own function (not deleted) only because the settle/skip-when-
-- unsettled shape around it is still worth keeping. threshold=1.0: this
-- is now full-heal-between-every-fight, not a partial top-up -- matching
-- the owner's own play (no chip damage carried into the next fight,
-- including the ambush/FlameEater triggers themselves).
local function care(what)
  return seq({
    H.waitUntilSoft(function()
      return H.hasControl() and H.tileAligned() and bright() >= 15
         and not H.dialogWaiting() and not H.battleLoadStarted()
    end, 1200, "care " .. what),
    H.cond(function()
      return H.hasControl() and H.tileAligned() and not H.dialogWaiting()
         and not H.battleLoadStarted()
    end, {
      H.waitFrames(60),
      H.fieldCare({ tag = "care " .. what, threshold = 1.0 }),
    }, {
      H.logStep(function()
        return string.format("[care %s] SKIPPED -- not settled at (%d,%d) map %d",
          what, H.fieldX(), H.fieldY(), map())
      end),
    }),
  })
end

-- gen_thamasa_arrive's chestAuto: live-staged (bfsPath candidates), so no
-- hand-guessed stand tile is needed for either map-351 chest.
local CHEST_CAND = {
  { 0, 1, "up" }, { 0, -1, "down" }, { -1, 0, "right" }, { 1, 0, "left" },
}
local FACE_VAL = { up = 0, right = 1, down = 2, left = 3 }
local function chestAuto(cx, cy, bit, what, item)
  local pick
  -- NOTE (2026-08-19): the CHEST_CAND reachability probe below is only a
  -- heuristic at range -- H.bfsPath's 4096-node cap can make a genuinely
  -- reachable candidate read NONE from far away (see creepXY's header) --
  -- so a bad pick here is not fatal; the walk itself creeps in short hops
  -- regardless of which candidate was chosen.
  local function stage()
    if not pick then
      for _, c in ipairs(CHEST_CAND) do
        local sx, sy = cx + c[1], cy + c[2]
        if H.bfsPath(sx, sy) then pick = { sx, sy, c[3] }; break end
      end
      pick = pick or { cx, cy + 1, "up" }
      H.log(string.format("[chest] (%d,%d) %s: staging (%d,%d) face %s",
        cx, cy, what, pick[1], pick[2], pick[3]))
    end
    return pick
  end
  local tag = string.format("chest bit %d (%s)", bit, what)
  local before
  local aPh = 0
  return H.cond(function() return not H.chestOpen(bit) end, {
    H.call(function() pick = nil end),
    H.navTo(
      function() local p = stage(); local fx = creepXY(p[1], p[2]); return fx() end,
      function() local p = stage(); local _, fy = creepXY(p[1], p[2]); return fy() end,
      { maxFrames = 40000, playBattles = "tactical", healer = TERRA, bank = 3,
        items = true, healPercent = 85,
        magic = { [TERRA] = { spell = ICE_SPELL, boost = false } } }),
    H.call(function() before = item and H.invCountOf(item) or nil end),
    H.driveUntil(function()
      return H.readByte(0x087f + H.readWord(0x0803)) == FACE_VAL[stage()[3]]
    end, 300, {
      H.call(function() H.setPad({ [stage()[3]] = true }) end),
    }, tag .. ": faced"),
    H.release(), H.waitFrames(4),
    H.driveUntil(function() return H.dialogWaiting() end, 6000, {
      H.call(function()
        aPh = (aPh + 1) % 12
        H.setPad(aPh < 4 and { a = true } or {})
      end),
    }, tag .. ": the chest answered"),
    H.driveUntil(function() return not H.dialogWaiting() end, 600, {
      H.call(function()
        aPh = (aPh + 1) % 8
        H.setPad(aPh < 4 and { a = true } or {})
      end),
    }, tag .. ": dialog dismissed"),
    H.call(function()
      H.setPad({})
      H.assertEq(H.chestOpen(bit), true, tag .. ": treasure bit set")
      if item then
        local now = H.invCountOf(item)
        H.assertEq(now, before + 1,
          string.format("%s: bag %d -> %d of item $%02X", tag, before, now, item))
      end
      H.log("[chest] " .. tag .. ": OPENED")
    end),
  }, {
    H.call(function()
      H.log(string.format("[chest] %s: already open (rerun), skipping", tag))
    end),
  })
end

-- ------------------------------------------------------ the item shop --
-- MEASURED live (this pass): a first grind attempt at these settings ran
-- the bag dry -- tonic=0 potion=0 fenix=0 by leg 8 -- and once items ran
-- out, the survivor(s) had only Cure's finite MP left, which was not
-- enough against Baskervor (L22 HP750, no weakness); the party wiped on
-- leg 10. The fix a real player would reach for is exactly this: stock up
-- before grinding. Thamasa's item shop, decoded from source rather than
-- guessed (ff6/src/field/trigger/short_entrance.dat's map-343 block,
-- offset $15f0, 7 records, decoded the same way the inn/Strago-door
-- records already in this file were): town 343 door (26,37) -> map 347
-- dest (36,44) (the "+256" high-map convention already established for
-- Strago's own door record); the shopkeeper NPC inside sits at (36,39)
-- (ff6/src/event/npc_prop.asm's NPCProp::_347, event _cbd730,
-- `shop_menu 35`). Shop 35's stock (ff6/src/menu/shop_prop.dat, 128
-- fixed 9-byte records -- shop.asm's own "shop type" + 8 item-id bytes
-- comment -- record 35 decoded byte-for-byte: 03 E8 E9 EB F5 FD F1 F0 F7):
-- row 0 = $E8 Tonic, row 1 = $E9 Potion, row 6 = $F0 Fenix Down (thamasa-
-- route.md's own prose summary, "Revivify, Remedy, Warp Stone", was not
-- exhaustive -- it named three of the eight rows, not all of them).
local function gil()
  return H.readByte(0x1860) + H.readByte(0x1861) * 256 + H.readByte(0x1862) * 65536
end
-- MEASURED (this pass, live, twice -- a settle wait before the first
-- pathfinding call did NOT change the result, ruling out the map-351-style
-- late-decompression timing gap): NONE of CHEST_CAND's four 1-tile-
-- adjacent candidates around the Thamasa shopkeeper (36,39) pass bfsPath
-- -- the fallback silently defaulted to the same unreachable (36,40) both
-- times. This is the innkeeper's own "talk-across-a-counter" shape
-- (player.asm's CheckNPCs extension, the Dadaluma-note case this file's
-- inn-door code already documents) -- a counter blocks the 1-tile
-- approach, and the real stand tile is 2 tiles back. SHOP_CAND tries
-- 1-tile candidates first (the common case elsewhere in this file) and
-- falls back to 2-tile candidates in the same four directions before
-- giving up to the same hardcoded default the old code had.
local SHOP_CAND = {
  { 0, 1, "up" }, { 0, -1, "down" }, { -1, 0, "right" }, { 1, 0, "left" },
  { 0, 2, "up" }, { 0, -2, "down" }, { -2, 0, "right" }, { 2, 0, "left" },
}
local function shopTalk(nx, ny, what)
  local pick
  local function stage()
    if not pick then
      for _, c in ipairs(SHOP_CAND) do
        local sx, sy = nx + c[1], ny + c[2]
        if H.bfsPath(sx, sy) then pick = { sx, sy, c[3] }; break end
      end
      pick = pick or { nx, ny + 1, "up" }
      H.log(string.format("[shop] %s: staging (%d,%d) face %s",
        what, pick[1], pick[2], pick[3]))
    end
    return pick
  end
  local aPh = 0
  return seq({
    H.navTo(function() return stage()[1] end, function() return stage()[2] end,
      { maxFrames = 9000, playBattles = "tactical", healer = TERRA, bank = 3,
        items = true }),
    H.driveUntil(function()
      return H.readByte(0x087f + H.readWord(0x0803)) == FACE_VAL[stage()[3]]
    end, 300, {
      H.call(function() H.setPad({ [stage()[3]] = true }) end),
    }, what .. ": faced"),
    H.release(), H.waitFrames(4),
    H.driveUntil(function() return H.readByte(0x0026) == 0x25 end, 3000, {
      H.call(function()
        aPh = (aPh + 1) % 12
        H.setPad(aPh < 4 and { a = true, [stage()[3]] = true } or {})
      end),
    }, what .. ": shop opens"),
    H.call(function()
      H.log(string.format("[shop] %s: open at f%d, gil=%d", what, H.frame, gil()))
    end),
  })
end
-- MEASURED (this pass, live): a continuously-HELD B timed out at 900
-- frames -- shop.asm's own B-handlers (MenuState_25/26/27) read z08+1's
-- JOY_B bit, which is an EDGE flag (a fresh press), not a level; the last
-- buyItem call leaves the shop at state $26 (the buy list, per
-- MenuState_26's own B-handler jumping back to $25, not straight to
-- closed), so closing needs TWO separate B edges (26->25, then 25->
-- closed) and a held button only ever supplies the first one. Edge-tapped
-- (on/off cycling), matching every OTHER button-press idiom already in
-- this file (H.pressButtons's own 4-on/4-off, the A-mash phase pattern),
-- fixes it.
local function shopClose(what)
  local ph = 0
  return seq({
    H.driveUntil(function()
      return H.hasControl() and H.readByte(0x0026) ~= 0x25
         and H.readByte(0x0026) ~= 0x26 and H.readByte(0x0026) ~= 0x27
    end, 1800, {
      H.call(function()
        ph = (ph + 1) % 8
        H.setPad(ph < 4 and { b = true } or {})
      end),
    }, what .. ": shop closed"),
    H.release(),
    H.waitFrames(30),
  })
end

-- ---------------------------------------------------------- P3: Strago's --
-- join-level probe (the survey's join-level question -- no norm_lvl at
-- join, per thamasa-route.md finding 3.  Logged, not asserted: whatever
-- char_prop's init-time averaging produces is measured here rather than
-- predicted).
-- NOTE: returns a step object (H.call(...)) -- call it as a list ENTRY,
-- never from inside another H.call's body (that only constructs a
-- throwaway step and logs nothing; measured the hard way, see the STATUS
-- note at the top of this file).  The one live call site inlines this
-- instead, for exactly that reason.
local function logStragoJoin()
  return H.call(function()
    -- ff6/notes/field-ram.txt:885-895: the 37-byte character record,
    -- indexed by character id (same convention as $1850+charId): +$08
    -- level, +$09 current HP, +$0B max HP (top 2 bits are the hp-boost
    -- flag, masked off), +$0D current MP, +$0F max MP (same mask).
    local lvl = H.readByte(0x1600 + 37 * STRAGO + 0x08)
    local hp = H.readWord(0x1600 + 37 * STRAGO + 0x09)
    local mhp = H.readWord(0x1600 + 37 * STRAGO + 0x0B) & 0x3FFF
    local mp = H.readWord(0x1600 + 37 * STRAGO + 0x0D)
    local mmp = H.readWord(0x1600 + 37 * STRAGO + 0x0F) & 0x3FFF
    H.log(string.format(
      "[P3] STRAGO join stats: level=%d hp=%d/%d mp=%d/%d (measured, no " ..
      "norm_lvl expected at join)", lvl, hp, mhp, mp, mmp))
  end)
end

-- --------------------------------------------------------- battle 31/45 --
-- The wandering flames and the (21,22) ambush are ordinary contact/tile
-- battles; navTo's playBattles="tactical" branch (H.newFightDriver
-- underneath) already fights anything that starts while it walks.  No
-- special handling needed beyond passing tactical opts through, and a care
-- stop after each leg per the task's "care between chained fights" note.
--
-- MEASURED (2026-08-19): the default healPercent=55 was NOT enough.  A live
-- run wiped the party approaching the (21,22) ambush -- creepNav(21,22,...)
-- chained 4-5 wandering-flame contact battles back to back inside ISLAND
-- 11 alone (three flames live there per npc_prop.asm, and the corridor from
-- P2's landing (26,36) to the ambush tile crosses all of them) with no
-- care() stop possible in between (they're random-movement contacts, not
-- plannable waypoints), so chip damage from each fight carried into the
-- next; by the time the scripted 4x-Balloon ambush (battle 45) started the
-- party was already down to ~65-90% and TERRA -- the designated healer --
-- was the FIRST to drop, which stops all further in-battle healing (the
-- exact risk the task brief named: "TERRA the healer DIED in the prior
-- session's one deep run"). Raising healPercent so newFightDriver tops
-- everyone up much earlier per-fight is the only lever available inside a
-- single navTo call (no post-battle-field-care hook exists).
--
-- FURTHER MEASURED (2026-08-19): even with healPercent=85 and mid-leg
-- waypoints (below), island 13 alone burned all 3 Fenix Downs and still
-- wiped -- H.fieldCare turned out to be non-functional on this map (see
-- care()'s own note), so once the bag ran dry there was no recovery left
-- at all. Tried healer=nil (letting every actor reach for the bag from
-- turn one, not just TERRA once she falls, per #128's mayHeal fallback)
-- expecting more resilience; it backfired live -- monhp sat at 555/555
-- UNCHANGED for 3300+ straight frames while the whole party did nothing
-- but heal/revive each other in a loop, because mayHeal now made healing
-- look attractive to everyone every turn instead of only the down actor's
-- own fallback case, so nobody ever finished the fight and the bag drained
-- for zero progress. Reverted to healer=TERRA (the #128 fallback alone,
-- not a blanket policy, is the correct amount of sharing) -- the real fix
-- for this segment is smaller waypoint chunks (below), not who is allowed
-- to open the bag.
-- MEASURED (2026-08-19): the fights themselves are slow, not just chained.
-- Live battle logs sat at "monhp=0/sh0,555/sh1,555/sh1,0/sh0" -- two
-- Balloons at full HP -- for 3000+ straight frames with the party fighting
-- the whole time, i.e. plain boosted Fight was landing near zero net
-- damage. The design doc's own finding (thamasa-route.md's Balloon row):
-- weak to ice|water, and OT6's shield-break ratio is 4:1 weak:unweak
-- (ot6_break.asm:1487-1497, cited in newFightDriver's own boost comment) --
-- an unweak physical hit while shields hold is doing a QUARTER the damage
-- an elemental hit would. opts.magic routes TERRA's turns to Ice (spell
-- $01, `boost=false` per newFightDriver's own note: "what a caller wants
-- when the point is the element rather than the damage") instead of
-- boosted Fight whenever she is not needed to heal; if she does not know
-- Ice yet at this join level the driver's own fallback (spellCell finds
-- nothing -> falls through to Tools/Fight) keeps this harmless to try.
local WALK = { playBattles = "tactical", healer = TERRA, bank = 3,
               items = true, maxFrames = 20000, healPercent = 85,
               magic = { [TERRA] = { spell = ICE_SPELL, boost = false } } }
-- islands 13/11 only: flee wandering flames rather than fight every one
-- (see houseWarp's own note on the `flee` parameter, below).
local FLEE_WALK = { playBattles = "flee", healer = TERRA, bank = 3,
                     items = true, maxFrames = 20000, healPercent = 85,
                     magic = { [TERRA] = { spell = ICE_SPELL, boost = false } } }
-- MEASURED (tenth pass, live): the FlameEater trigger tile (46,53) sits
-- directly on the only path from the checkpoint's landing (46,54) to the
-- creep target (46,52) one tile past it -- a straight two-tile walk that
-- geometrically has to cross (46,53) -- so the fight can start mid-nav,
-- fought by whatever kit this creep call carries, rather than only via the
-- dedicated pressWalk("down",...) trigger step flameEaterAttempt() also
-- has below. NO opts.magic here (this carried a boosted Ice line through
-- the ninth pass; dropped this pass -- see flameEaterAttempt's own header
-- for why): TERRA's Blizzard sword and STRAGO's Ice Rod are both already
-- ice-elemental, and a plain Fight is never reflected the way a cast is,
-- so leaving the offense on Fight is what actually keeps landing once
-- FlameEater's own Reflect goes up. healPercent=60 matches
-- flameEaterAttempt's own H.newFightDriver. maxFrames generous: this is
-- potentially the ENTIRE FlameEater fight (L26 HP8400), not a trash
-- contact.
local FLAMEEATER_WALK = { playBattles = "tactical", healer = TERRA, bank = 3,
  items = true, maxFrames = 100000, healPercent = 60 }

-- Map 351's internal short_entrance warps (STATUS header): a short_entrance
-- fires purely by standing on its SrcPos tile (ff6/src/field/entrance.asm's
-- CheckShortEntrance compares the live position against SrcPos with no
-- direction test), exactly like the (4,10) floor trigger this file already
-- rides with a plain H.navTo/creepNav -- no crossDoor-style staged/held
-- diagonal approach is needed.
--
-- Two dead ends on the way to this shape, both MEASURED, worth keeping so a
-- third pass doesn't retry them:
-- (1) crossDoor-style staging (reasoning: src map == dest map == 351, so
--     crossDoor's own "map() ~= startMap" arrival test can't fire here) --
--     worked for P1, then failed on P2 with "no path (4,38)->(2,25)" even
--     though the SAME bfsPath call had just approved that candidate when
--     staging picked it.
-- (2) plain `creepNav(sx, sy, WALK)` with no `arrive` override -- this is
--     what actually explains (1)'s ghost failure too. navTo's own
--     completion test wants the party CALM (settled, tileAligned) ON the
--     goal tile for up to 48 frames (ot6_field.lua's calmWant*3 rule,
--     "the party has control OR has been on the goal tile long enough
--     regardless"); a short_entrance instead relocates the party the
--     INSTANT it lands tile-aligned on SrcPos, so fieldX/Y jump to DestPos
--     before calm ever accumulates. navTo's driveUntil never reports
--     "done", so it keeps re-planning -- now FROM the post-warp island,
--     TOWARD a source tile on an island that same warp is the only link
--     to, which of course has "no path". Live evidence: P1's own
--     creepNav(4,3,...) got the party to (4,38) (the warp fired -- visible
--     in the log as the FAIL's own "no path (4,38)->(4,24)" source
--     coordinate, (4,24) being creepXY's fresh waypoint FROM (4,38) TOWARD
--     the now-unreachable (4,3)) and then hard-failed retrying anyway.
-- The fix: pass navTo's own `arrive` opt (an OR'd alternate stop
-- condition, ot6_field.lua:698) so the walk-to-SrcPos step ends the moment
-- fieldX/Y read the KNOWN DestPos, sidestepping the calm/settle race
-- entirely rather than waiting on it.
--
-- `flee`: islands 13 and 11 (the stretch this file's own STATUS/WALK notes
-- above document wiping the party even with healPercent=85 and mid-leg
-- waypoints) hold six of the twelve wandering flames between them, and
-- none of the twelve are required content -- the doc's own words, "A
-- fought flame is hidden+deleted for the rest of the visit", describes an
-- optional contact, not a gate. holding L+R (playBattles="flee") past a
-- wandering flame instead of fighting it is available and unused content
-- on the safer legs, and here it directly avoids fights this route does
-- not need to survive. Defaults to "tactical" (unchanged behavior) so
-- callers on calmer islands, and the ambush/FlameEater trigger legs which
-- SHOULD fight what they hit, are unaffected.
local function houseWarp(sx, sy, dx, dy, what, playBattles)
  return seq({
    creepNav(sx, sy, { playBattles = playBattles or "tactical", healer = TERRA,
      bank = 3, items = true, maxFrames = 20000, healPercent = 85,
      magic = { [TERRA] = { spell = ICE_SPELL, boost = false } },
      arrive = function() return H.fieldX() == dx and H.fieldY() == dy end }),
    H.waitUntil(function()
      return H.hasControl() and H.tileAligned() and bright() >= 15
    end, 2400, what .. ": settled", 10),
    H.waitFrames(30),
    H.call(function()
      H.assertEq(H.fieldX(), dx, what .. ": landed at the right x")
      H.assertEq(H.fieldY(), dy, what .. ": landed at the right y")
      H.log(string.format("[ot6] %s: DONE (%d,%d) frame=%d", what,
        H.fieldX(), H.fieldY(), H.frame))
    end),
  })
end

local function battleHpAllZero()
  for e = 0, 3 do
    if H.readWord(0x3BF4 + e * 2) ~= 0 then return false end
  end
  return true
end

-- --------------------------------------------------- #127 GameOver guard --
-- M.run (tools/tests/lib/ot6.lua, this pass's lib addition) now arms an
-- exec canary on the event GameOver routine ($CC/E568,
-- ff6/src/event/event_main.asm's `.proc GameOver`) and FAILS THE WHOLE RUN
-- LOUDLY (H.gameOverFired > 0 -> emu.stop(3)) the frame after it fires,
-- unless opts.allowGameOver is set -- built exactly to catch the disaster
-- this file's own STATUS header documents: a lost ambush whose A-mashing
-- auto-Continued the SRAM checkpoint and silently reverted the whole
-- session (roster included) while every predicate here kept reading
-- healthy. This file's H.run() call passes allowGameOver=true (both
-- fights below are seed ladders BUILT to survive a loss), so the canary
-- alone no longer aborts the run -- but a real GameOver must still never
-- be allowed to reach a title-screen Continue prompt, which is what the
-- old "A-mash until the win switch clears" tail step did for up to 3200
-- frames on every loss, GameOver or not.
--
-- Fix, in both ambushAttempt and flameEaterAttempt's tail step below:
-- the win-tail driveUntil's own predicate now also stops the instant
-- H.gameOverFired > 0 (M.driveUntil checks its predicate BEFORE running
-- its body each tick, so the exit lands before one more "a" press goes
-- out -- no mash reaches a Continue prompt), and lossReload() here
-- reloads the ladder's pre-fight blob and resets H.gameOverFired back to
-- 0 right after, so neither the next attempt's own frame-boundary state
-- nor a final failed-ladder error() ever trips on a stale nonzero counter
-- left over from THIS attempt's loss.
local function lossReload(blobFn, tag)
  local req
  return seq({
    H.call(function() req = H.requestLoadState(blobFn()) end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(req, tag .. ": loss-reload")
      H.gameOverFired = 0
      H.log(string.format("[%s] loss-reload done, GameOver counter cleared, f%d",
        tag, H.frame))
    end),
    H.waitFrames(90),
  })
end

-- --------------------------------------------------------- the ambush --
-- MEASURED (2026-08-19): the (21,22) ambush (battle 45, 4x Balloon,
-- formation 158/159's bigger sibling per event_main.asm:71993) is NOT
-- survivable by preparation alone. Every live attempt -- full HP entering
-- the fight or not, flee-mode-preserved or worn down -- read partyhp with
-- TERRA and STRAGO ALREADY at 0 on the very first logged battle frame
-- (f+1, menu=82, before the tactical driver has thrown a single input):
-- a pincer opening apparently lands its first round before the player
-- gets a turn, and losing two of three members to it is not something
-- healPercent or a well-timed care() stop can prevent -- there is no
-- frame to act on. This is exactly the shape the FlameEater seed ladder
-- below already solves: a hard, RNG-sensitive fight, retried from a
-- checkpoint with a spread battle seed rather than assumed winnable in
-- one try. event_main.asm's own _cbe622 sets switch $050A=1 as its first
-- action and clears it only at the very end, after the post-battle
-- teardown (`hide_obj`/`delete_obj` the ambush NPCs, `fade_in`) -- the
-- SAME "only a real win reaches the tail" shape $0090 gives FlameEater --
-- so the ladder here watches $050A instead of a battle-menu flag, exactly
-- as FlameEater's own header explains for $0090.
local L45 = H.newSeedLadder("ambush (battle 45)", { attempts = 5 })
local ambBlob, ambWon = nil, false

-- FRAME-BUDGET FOR "the battle module is really gone": pass five's own
-- correction (coordinator, live screenshots).  The OLD exit condition
-- `(not H.battleLoadStarted() and not H.battleActive())` trusted a SINGLE
-- frame's read of two flags that are both known-flaky mid-fight
-- (battleLoadStarted's own header: "a total party wipe is all zeros, which
-- is also what a menu leaves, so this reports false"; battleActive() adds
-- a screenshot check that a single big-effect frame -- an Exploder self-
-- destruct flash, say -- can also fail).  One bad frame handed control from
-- the tactical driver (F.frame(), which casts Cure/uses Fenix Downs/etc)
-- to the win-tail's blind A-mash WHILE THE FIGHT WAS STILL LIVE: TERRA and
-- STRAGO died in the pincer, LOCKE then soloed unsupported (no items, no
-- revives -- the win-tail never calls F.frame() at all) until the party
-- wiped for real, Game Over fired, and the blind A-mash walked itself onto
-- the vanilla Continue prompt, silently re-loading the thamasa-night-v1
-- SRAM. Every one of pass four's "post-ambush stall" readings (world-mode-
-- shaped $1f64, position (8,7)-ish, no Strago in the party) was that
-- reloaded save, not a stuck engine. CONFIRM_BATTLE_GONE is the debounce
-- fix: only trust "the battle is over" after this many CONSECUTIVE frames
-- of both flags reading false, so one bad frame can no longer end the
-- fight early.
local CONFIRM_BATTLE_GONE = 90

-- ==================================================== the ambush FIGHT PLAN
-- Owner's pass-eight ruling (amended to lead with Aqua Rake): the generic
-- H.newFightDriver ends every attempt the same way -- "the lone survivor
-- cycles revive-items without ever landing a real attack" (pass six's own
-- STATUS finding) -- a revive treadmill feeding fresh bodies to three live
-- Balloons every round, never actually damaging them. This is a BESPOKE
-- driver for this one fight, modeled on gen_narshe_battle.lua's raw per-
-- character button-sequence fighter and battle_thief.lua's state-machine
-- decide() (its exact CMDTBL/ST_THIEF/KCOL/KROW addresses for Filch, and
-- the Lore addresses researched fresh this pass -- see below), NOT
-- H.newFightDriver: the generic driver has no Lore arm at all (Strago's
-- cmd $0C never gets driven), and its unconditional item/cure loop is
-- exactly the treadmill bug this plan exists to fix.
--
-- THE PLAN:
--   STRAGO alive -> Aqua Rake (lore id 3, $8e) every turn. Multi-target
--     water, hits all four Balloons: chips their shields (their own
--     weakness) AND lowers their current HP, which matters because the
--     Exploder self-destruct deals CURRENT hp (thamasa-route.md/the task
--     brief) -- so a landed Rake also defuses whatever a surviving
--     Balloon's own self-destruct would otherwise do. Multi-target, no
--     cursor steering: enters ST_TGT and confirms with a bare A.
--   LOCKE alive, Strago down -> break-and-burst fallback: Filch (thief
--     submenu row 1, strips one shield class-blind, banks Locke +2 BP)
--     while ANY live Balloon still carries a shield, else an R-boosted
--     Fight (a broken target takes 4x) on whatever the default enemy
--     cursor lands on.
--   anyone else (TERRA, if she is the one left standing) -> plain
--     boosted Fight. NOT built this pass: an Ice-cast line for her (the
--     original, pre-Aqua-Rake-amendment brief's fallback) -- Strago
--     surviving is the plan's whole premise (he opens for free the
--     instant he is alive at all), so this is filed as a known gap
--     rather than chased, same spirit as the Ice Rod cast this file's own
--     header already leaves undriven.
--   SURVIVOR MODE / REVIVE WINDOW (rule 1 & 3 of the brief, collapsed
--     into one gate): revives are WITHHELD entirely while 2+ Balloons are
--     still alive -- "every revived body dies before acting" is the
--     measured failure mode this exists to stop. The instant at most ONE
--     Balloon remains, the gate opens: revive STRAGO first (his Rake is
--     the plan's engine), then anyone else down, then resume offense.
--   SELF-HEAL: any acting, living character below 40% HP uses a Tonic/
--     Potion on THEMSELVES before anything else, survivor-mode or not
--     ("the fence lesson" -- rule 4). Never spent topping off a body that
--     is about to be revived instead; the revive-window gate already
--     keeps those two lines from colliding (a corpse cannot act, so it
--     is never the "acting character" self-heal fires for).
--
-- RAM/menu addresses, all either already-proven-live in this file/library
-- (CMDTBL, ST_CMD/ST_TGT/ST_ITEM, the thief submenu) or researched fresh
-- this pass and cited: Lore's own steady-browse MSTATE ($1B, "lore
-- select" per btlgfx_main.asm's own UpdateMenuState_1b comment; $19 is
-- the transitional DMA-fill state on the way in), its single-column
-- cursor block ($891F/$8923/$8927, immediately following Magic's own
-- $8913/$8917/$891B block and Rage's own $892B one tier further -- all
-- three are one contiguous 12-byte-stride table), and the row-lookup via
-- $306A+loreId reading that lore's own attack id (loreId+$8B) iff it is
-- currently offered (battle_lore.lua's own already-passing test exercises
-- this exact table). Aqua Rake = lore id 3 ($8e - $8b), confirmed inside
-- Strago's own InitLore starting set {3,7,20} (ff6/src/field/init.asm) --
-- the AUTO five-lore rule offers all three known lores in ascending id
-- order when only three are known, so id 3 (the lowest) should land at
-- row 0, but the driver below does not hardcode that: it counts offered
-- ids below 3 live, the same shape the generic driver's own spellCell
-- uses for Magic.
local MENU_A, ACTOR_A, MSTATE_A = 0x7BCA, 0x62CA, 0x7BC2
local CMDTBL_A, CMDROW_A = 0x202E, 0x890F
local BCHID_A, BCHP_A, BCMAXHP_A = 0x3ED8, 0x3BF4, 0x3C1C
local BP_A = 0x3E9C
local ST_CMD_A, ST_TGT_A, ST_ITEM_A, ST_THIEF_A = 0x05, 0x38, 0x0A, 0x30
local KCOL_A, KROW_A = 0x8963, 0x8967
local ST_LORE_OPEN_A, ST_LORE_A = 0x19, 0x1B
local LROW_A = 0x8927
local TBL_306A_A = 0x306A
local CMD_FIGHT_A, CMD_ITEM_A, CMD_STEAL_A, CMD_LORE_A = 0x00, 0x01, 0x05, 0x0C
local ITEMSCR_A, ITEMROW_A, BATTINV_A = 0x8947, 0x894F, 0x2686
local AQUA_RAKE_LORE_ID = 3
-- PREP amendment (ninth pass): TERRA and LOCKE now both carry an
-- Ice-granting esper (SHIVA/MADUIN), so the plan below leads THEM with
-- boosted Ice too, not just STRAGO's free Aqua Rake -- the same magic-list
-- walk M.newFightDriver's own makePlan/button use for opts.magic, copied
-- here because this fight runs its own bespoke driver, not the generic one.
local CMD_MAGIC_A, ST_MAGIC_A = 0x02, 0x0E
local MLISTPTR_A = 0x302C
local MSCROLL_A, MCOL_A, MROW_A = 0x8913, 0x8917, 0x891B
local CURMP_A = 0x3C08
local function spellCellA(actor, id, strict)
  local base = H.readWord(MLISTPTR_A + actor * 2)
  if base < 0x2000 or base > 0x2600 then return nil end
  for cell = 0, 53 do
    local a = base + (cell + 1) * 4
    if H.readByte(a) == id then
      local cost = H.readByte(a + 3)
      if H.readWord(CURMP_A + actor * 2) < cost then return nil end
      if strict and (H.readByte(a + 1) & 0x80) ~= 0 then return nil end
      return cell, cost
    end
  end
  return nil
end
local function monHpA(i) return H.readWord(0x3BFC + i * 2) end
local function monShieldsA(i) return H.readByte(0x3E40 + i * 2) end
local function monPresentA(i) return H.readByte(0x3AA8 + i * 2) % 2 == 1 end
local function cmdRowA(actor, cmd)
  for r = 0, 3 do
    if H.readByte(CMDTBL_A + actor * 12 + r * 3) == cmd then return r end
  end
  return nil
end
local function bagIdxOfA(ids)
  for i = 0, 251 do
    local id = H.readByte(BATTINV_A + i * 5)
    for _, w in ipairs(ids) do
      if id == w and H.readByte(BATTINV_A + i * 5 + 3) > 0 then return i end
    end
  end
  return nil
end
-- battle_lore.lua's own tested fact: $306A+id reads id+$8B iff that lore
-- id is currently offered by Ot6LoreMask's live walk; otherwise whatever
-- InitBattle's own clear left there. Comparing against the exact expected
-- value (rather than measuring a separate "fill" byte first) sidesteps
-- needing that extra live-measurement step.
local function loreOfferedA(id) return H.readByte(TBL_306A_A + id) == id + 0x8B end
local function loreRowForA(targetId)
  local row = 0
  for id = 0, targetId - 1 do
    if loreOfferedA(id) then row = row + 1 end
  end
  return row
end
local ambushCharTC = H.targetCursor({ mask = 0x7B7D, dirs = { "down", "up", "left", "right" } })

local function newAmbushPlan(tag)
  local F = {}
  local phase, mf = 0, 0
  local turnActor, turnPlan = nil, nil
  local stepIdx = 0
  local aqCasts, filchCasts, fightBursts, iceCasts = 0, 0, 0, 0
  local openerLogged = false
  local function partyCounts()
    local balloonsAlive = 0
    for s = 0, 5 do if monPresentA(s) and monHpA(s) > 0 then balloonsAlive = balloonsAlive + 1 end end
    local stragoSlot, downSlots, anyAlive = nil, {}, false
    for e = 0, 3 do
      if H.readWord(BCMAXHP_A + e * 2) > 0 then
        local cid = H.readByte(BCHID_A + e * 2)
        if cid == STRAGO then stragoSlot = e end
        if H.readWord(BCHP_A + e * 2) > 0 then anyAlive = true
        else downSlots[#downSlots + 1] = e end
      end
    end
    return balloonsAlive, stragoSlot, downSlots, anyAlive
  end
  local function anyShielded()
    for s = 0, 5 do
      if monPresentA(s) and monHpA(s) > 0 and monShieldsA(s) > 0 then return true end
    end
    return false
  end
  -- built once per fresh ST_CMD (turnPlan == nil or a new actor's turn)
  local function decideTurn(actor)
    if not openerLogged then
      openerLogged = true
      local hp, mx = H.readWord(BCHP_A + actor * 2), H.readWord(BCMAXHP_A + actor * 2)
      H.log(string.format(
        "[%s] opener check f%d: first actor to get a turn is slot %d " ..
        "(char $%02X) at %d/%d hp -- the opener's own damage on whoever it " ..
        "caught is whatever's MISSING from THEIR max, logged separately " ..
        "per party member below", tag, H.frame, actor,
        H.readByte(BCHID_A + actor * 2), hp, mx))
      for e = 0, 3 do
        if H.readWord(BCMAXHP_A + e * 2) > 0 then
          H.log(string.format(
            "[%s] opener dbg: slot %d char $%02X hp=%d/%d (missing=%d)",
            tag, e, H.readByte(BCHID_A + e * 2), H.readWord(BCHP_A + e * 2),
            H.readWord(BCMAXHP_A + e * 2),
            H.readWord(BCMAXHP_A + e * 2) - H.readWord(BCHP_A + e * 2)))
        end
      end
    end
    local charId = H.readByte(BCHID_A + actor * 2)
    local hp, mx = H.readWord(BCHP_A + actor * 2), H.readWord(BCMAXHP_A + actor * 2)
    local balloonsAlive, stragoSlot, downSlots = partyCounts()
    -- 1. self-heal, always allowed (the fence lesson)
    if mx > 0 and hp > 0 and hp < mx * 0.40 then
      local idx = bagIdxOfA({ TONIC, POTION })
      if idx then return { kind = "item", ids = { TONIC, POTION }, target = actor } end
    end
    -- 2. revive window: at most one Balloon left, revive STRAGO first
    if balloonsAlive <= 1 and #downSlots > 0 then
      local idx = bagIdxOfA({ FENIX_DOWN })
      if idx then
        local tgt = downSlots[1]
        if stragoSlot then
          for _, s in ipairs(downSlots) do if s == stragoSlot then tgt = s end end
        end
        return { kind = "item", ids = { FENIX_DOWN }, target = tgt }
      end
    end
    -- 3. offense -- lead with AoE weakness magic (PREP amendment, ninth
    -- pass): STRAGO's Aqua Rake is free every turn regardless; TERRA and
    -- LOCKE now both carry an Ice-granting esper (SHIVA/MADUIN), so they
    -- lead with a boosted, multi-target Ice cast (Balloons are weak to
    -- ice|water, thamasa-route.md) whenever they can pay for it, falling
    -- back to the pre-PREP break-and-burst kit (Filch/boosted Fight) only
    -- when the cast isn't available (esper unequipped, out of MP, or the
    -- greyed bit refuses it).
    if charId == STRAGO then
      return { kind = "lore", loreId = AQUA_RAKE_LORE_ID }
    end
    if charId == TERRA or charId == LOCKE then
      if spellCellA(actor, ICE_SPELL, true) then
        return { kind = "magic", spell = ICE_SPELL }
      end
    end
    if charId == LOCKE then
      if anyShielded() then return { kind = "filch" } end
      return { kind = "fight", boost = true }
    end
    return { kind = "fight", boost = true }
  end
  -- per-frame button for the CURRENT plan/state
  local function buttonFor(actor, st)
    local plan = turnPlan
    if plan.kind == "item" then
      if st == ST_CMD_A then
        local want = cmdRowA(actor, CMD_ITEM_A)
        if want == nil then return "a" end
        local cur = H.readByte(CMDROW_A + actor) & 3
        if cur == want then return "a" end
        return cur < want and "down" or "up"
      elseif st == ST_ITEM_A then
        local want = bagIdxOfA(plan.ids)
        if want == nil then return "b" end
        local cur = H.readByte(ITEMSCR_A + actor) + H.readByte(ITEMROW_A + actor)
        if cur < want then return "down" end
        if cur > want then return "up" end
        return "a"
      elseif st == ST_TGT_A then
        -- MEASURED (this pass, live): a self-heal on LOCKE (the sole
        -- survivor, both allies down) stalled the WHOLE attempt for the
        -- full 1800000-frame budget right here -- H.targetCursor's own
        -- documented limit ("the two-press rotation cycles among three
        -- hover positions... cannot reach a slot that needs a bare up-
        -- then-right", ot6.lua's own header) most likely means the
        -- character-column rotation this fight's 2-down-of-3 shape needs
        -- isn't one the shared {down,up,left,right} rotation can reach.
        -- Backstop, same shape as the library's own #111 fix elsewhere in
        -- this codebase: past a real frame budget of failed confirms,
        -- stop steering and just press A on whatever is highlighted --
        -- with at most one living character in most of this fight's own
        -- turns, "whatever is highlighted" IS the only valid choice
        -- anyway.
        plan.tgtSpin = (plan.tgtSpin or 0) + 1
        if plan.tgtSpin > 240 then return "a" end
        ambushCharTC.observe()
        return ambushCharTC.steer(plan.target, mf)
      end
      return "b"
    end
    if plan.kind == "filch" then
      if st == ST_CMD_A then
        local want = cmdRowA(actor, CMD_STEAL_A)
        if want == nil then return "a" end
        local cur = H.readByte(CMDROW_A + actor) & 3
        if cur == want then return "a" end
        return cur < want and "down" or "up"
      elseif st == ST_THIEF_A then
        local cur = H.readByte(KROW_A + actor)
        if H.readByte(KCOL_A + actor) ~= 0 then return "left" end
        if cur < 1 then return "down" end
        if cur > 1 then return "up" end
        return "a"
      elseif st == ST_TGT_A then
        return "a"                       -- default enemy cursor, no steer
      end
      return "b"
    end
    if plan.kind == "lore" then
      if st == ST_CMD_A then
        local want = cmdRowA(actor, CMD_LORE_A)
        if want == nil then return "a" end
        local cur = H.readByte(CMDROW_A + actor) & 3
        if cur == want then return "a" end
        return cur < want and "down" or "up"
      elseif st == ST_LORE_OPEN_A then
        return nil                       -- transitional DMA fill, just wait
      elseif st == ST_LORE_A then
        local want = loreRowForA(plan.loreId)
        local cur = H.readByte(LROW_A + actor)
        if cur == want then return "a" end
        return cur < want and "down" or "up"
      elseif st == ST_TGT_A then
        return "a"                       -- multi-target, no steer
      end
      return "b"
    end
    if plan.kind == "magic" then
      -- Same boost-bank shape the fight fallback uses below (spend BP,
      -- capped at 3, only once at least 2 is banked) -- OT6 folds a boosted
      -- base cast to its next tier via Ot6FoldTbl (Ice -> Ice2 -> Ice3), so
      -- this is how the plan gets the bigger AoE hit rather than the base
      -- 4 MP tier every single cast.
      if st == ST_CMD_A then
        if not plan.boosted then
          local bp = H.readByte(BP_A + actor * 2)
          local want = (bp >= 2) and math.min(bp, 3) or 0
          plan.boostLeft = plan.boostLeft or want
          if plan.boostLeft > 0 then
            plan.boostLeft = plan.boostLeft - 1
            return "r"
          end
          plan.boosted = true
        end
        local want = cmdRowA(actor, CMD_MAGIC_A)
        if want == nil then return "b" end
        local cur = H.readByte(CMDROW_A + actor) & 3
        if cur == want then return "a" end
        return cur < want and "down" or "up"
      elseif st == ST_MAGIC_A then
        -- re-read the cell every tick (not just at plan time): the list is
        -- rebuilt when the window opens, matching M.newFightDriver's own
        -- button()'s "re-read, don't trust the plan-time cell" note.
        local cell = spellCellA(actor, plan.spell, false)
        if cell == nil then return "b" end
        local wr, wc = cell // 2, cell % 2
        local ar = H.readByte(MSCROLL_A + actor) + H.readByte(MROW_A + actor)
        local col = H.readByte(MCOL_A + actor)
        if ar < wr then return "down" end
        if ar > wr then return "up" end
        if col < wc then return "right" end
        if col > wc then return "left" end
        return "a"
      elseif st == ST_TGT_A then
        return "a"                       -- multi-target, no steer
      end
      return "b"
    end
    -- fight (default/fallback)
    if st == ST_CMD_A then
      if plan.boost and not plan.boosted then
        local bp = H.readByte(BP_A + actor * 2)
        local want = (bp >= 2) and math.min(bp, 3) or 0
        plan.boostLeft = plan.boostLeft or want
        if plan.boostLeft > 0 then
          plan.boostLeft = plan.boostLeft - 1
          return "r"
        end
        plan.boosted = true
      end
      local want = cmdRowA(actor, CMD_FIGHT_A)
      local cur = H.readByte(CMDROW_A + actor) & 3
      if want == nil then return "a" end
      if cur == want then return "a" end
      return cur < want and "down" or "up"
    elseif st == ST_TGT_A then
      return "a"                         -- default enemy cursor, no steer
    end
    return "b"
  end
  function F.frame()
    phase = (phase + 1) % 8
    if H.readByte(MENU_A) == 0 then
      turnActor, turnPlan = nil, nil
      H.setPad(phase < 4 and { "a" } or {})
      return
    end
    mf = mf + 1
    local actor = H.readByte(ACTOR_A) & 3
    local st = H.readByte(MSTATE_A)
    if st == 0x01 then H.setPad({}); return end   -- ST_TRANS
    if (turnPlan == nil or turnActor ~= actor) and st ~= ST_CMD_A then
      -- a fresh actor turn hasn't reached the command list yet (a
      -- transitional state); hold still rather than build a plan off a
      -- read that might still be settling, matching H.newFightDriver's
      -- own "only build a plan at ST_CMD" convention.
      H.setPad({})
      return
    end
    if turnPlan == nil or turnActor ~= actor then
      turnActor = actor
      turnPlan = decideTurn(actor)
      H.log(string.format("[%s] f%d slot=%d char=$%02X plan=%s%s", tag,
        H.frame, actor, H.readByte(BCHID_A + actor * 2), turnPlan.kind,
        turnPlan.kind == "item" and (" tgt=" .. turnPlan.target) or ""))
    end
    local slow = (st == ST_ITEM_A)
    local period = slow and 30 or 8
    local on = slow and 6 or 4
    if mf % period >= on then H.setPad({}); return end
    local btn = buttonFor(actor, st)
    -- count landed actions on the ST_TGT->confirm edge, logged once per
    -- kind so the report has real cadence numbers
    if st == ST_TGT_A and btn == "a" then
      if turnPlan.kind == "lore" and not turnPlan.counted then
        turnPlan.counted = true; aqCasts = aqCasts + 1
        H.log(string.format("[%s] Aqua Rake cast #%d confirmed f%d", tag, aqCasts, H.frame))
      elseif turnPlan.kind == "filch" and not turnPlan.counted then
        turnPlan.counted = true; filchCasts = filchCasts + 1
        H.log(string.format("[%s] Filch #%d confirmed f%d", tag, filchCasts, H.frame))
      elseif turnPlan.kind == "fight" and turnPlan.boost and not turnPlan.counted then
        turnPlan.counted = true; fightBursts = fightBursts + 1
        H.log(string.format("[%s] boosted burst Fight #%d confirmed f%d", tag, fightBursts, H.frame))
      elseif turnPlan.kind == "magic" and not turnPlan.counted then
        turnPlan.counted = true; iceCasts = iceCasts + 1
        H.log(string.format("[%s] Ice cast #%d confirmed f%d", tag, iceCasts, H.frame))
      end
    end
    H.setPad(btn and { [btn] = true } or {})
  end
  function F.idle()
    turnActor, turnPlan = nil, nil
    H.log(string.format(
      "[%s] tally: Aqua Rake x%d, Ice x%d, Filch x%d, boosted burst x%d",
      tag, aqCasts, iceCasts, filchCasts, fightBursts))
  end
  return F
end

local function ambushAttempt(n)
  local F = newAmbushPlan("ambush-plan-" .. n)
  local notBattle, giveUp = 0, 0
  local loadReq
  -- BUG FOUND LIVE (2026-08-19): H.cond(pred, thenSteps, elseSteps) hands
  -- elseSteps to the shared lib's own seqStep(), which needs a PLAIN list
  -- (#steps/steps[i]) -- passing seq({...}) here instead of the bare
  -- {...} hands seqStep a COMPOUND step object (a {tick=,reset=} table
  -- with no integer part), so #that is 0 and seqStep's tick() loop exits
  -- immediately as "done" without ever running a single inner step. Fixed
  -- here (bare {...}, matching every OTHER H.cond call in this file) and
  -- in flameEaterAttempt.
  return H.cond(function() return ambWon end, {}, {
    H.logStep(function()
      return string.format("ambush attempt %d at f%d", n, H.frame)
    end),
    n > 1 and seq({
      H.call(function() loadReq = H.requestLoadState(ambBlob) end),
      H.waitFrames(2),
      H.call(function() H.checkReq(loadReq, "ambush entry-point reload") end),
      H.waitFrames(90),
    }) or seq({}),
    L45.spread(n),
    H.call(function() H.log(string.format(
      "[ambush] approaching (21,22), attempt %d", n)) end),
    -- MEASURED (this pass, live, twice): attempt 5 of one run hit "no path
    -- (26,36)->(22,25) [0 edges blocklisted, 20 retries]" from this same
    -- reload point after attempts 1-4 reached the fight cleanly. Tried and
    -- REJECTED: a smaller creep step (8, forcing a different intermediate
    -- waypoint) -- this made it WORSE, failing on attempt 1 too with "no
    -- path (26,36)->(23,30)", proving the theory wrong: it is not one
    -- specific tile being transiently blocked by a live NPC, since a
    -- DIFFERENT waypoint choice hit the SAME class of failure on a
    -- PREVIOUSLY-clean attempt. Reverted to the default step (14, the
    -- original, mostly-reliable behavior -- 4 of 5 attempts clean in the
    -- run that surfaced this). Root cause not chased further this pass;
    -- filed as an occasional (not systematic) pathing flake for whoever
    -- picks up map 351 next, alongside this file's other creepXY/bfsPath
    -- notes on this same map.
    creepNav(21, 23, FLEE_WALK),
    -- probe instrument kept (issue #127): the party-membership/object-
    -- pointer dump right before the trigger fires, for comparison against
    -- the post-battle dump below.
    H.call(function() probeDump("PRE-BATTLE45 attempt-" .. n) end),
    pressWalk("up", function()
      return H.battleLoadStarted() or not H.hasControl()
    end, 1800, "step onto (21,22) -> battle 45"),
    H.waitUntil(function() return H.battleActive() end, 6000,
      "ambush battle up", 10),
    H.waitFrames(90),
    -- PHASE 1 (pass five fix): drive the fight TACTICALLY (F.frame() --
    -- items, revives, Terra's Ice, boosted Fight) for as long as the
    -- battle module might still own the screen, and ONLY conclude the
    -- battle is over after CONFIRM_BATTLE_GONE consecutive confirming
    -- frames.  H.gameOverFired is checked first and exits immediately
    -- with no debounce: it is now a READ watch on the event GameOver
    -- SCRIPT bytes in bank $CC (lib/ot6.lua, uncommitted -- the coordinator's
    -- fix for the earlier EXEC watch, which could never fire because
    -- $CC/E568 is event-interpreter DATA, never CPU-executed code), so it
    -- is ground truth for "this attempt just lost", not a heuristic.
    H.driveUntil(function()
      if H.gameOverFired > 0 then return true end
      if H.battleLoadStarted() or H.battleActive() then
        notBattle = 0
      else
        notBattle = notBattle + 1
      end
      return notBattle >= CONFIRM_BATTLE_GONE
    end, 1800000, {
      H.call(function()
        if H.gameOverFired > 0 then H.setPad({}); return end
        F.frame()
      end),
    }, "ambush fight (attempt " .. n .. ")"),
    H.call(function()
      F.idle()
      H.log(string.format(
        "[ambush] phase 1 done (battle module gone or GameOver read), " ..
        "attempt %d, f%d, gameOverFired=%d", n, H.frame, H.gameOverFired))
      probeDump("POST-BATTLE45 attempt-" .. n)
      probeEventDump("POST-BATTLE45 attempt-" .. n)
    end),
    -- PHASE 2 (pass five fix; budget raised ninth pass -- see below).
    -- $050A is UNSOUND as a win signal (the coordinator's correction):
    -- thamasa-night-v1, the SRAM a loss silently re-Continues to, has
    -- NEVER set $050A either, so it reads 0 there too and cannot tell a
    -- win from a reload.  This phase just settles (edge-A through
    -- anything waiting, same idiom newFightDriver's own menu==0 case
    -- uses) and hands off to the win-verification call below, which
    -- checks real ground truth instead of any single field switch.
    --
    -- MEASURED live (ninth pass, PREP): first read as "the win-tail just
    -- needs a bigger budget" -- probeEventDump at the exact moment phase 1
    -- exits reads ev=true (an event genuinely running), $050A newly SET,
    -- and TERRA/LOCKE/STRAGO still en=1/pty=1 -- but raising this budget
    -- 6200->40000 did NOT fix it (same "map=0, absurd field coords" result
    -- on every rung, now just 6.5x slower to report it). A per-frame HP
    -- trace through the fight (temporarily added, since removed) showed
    -- why: the opener alone -- BEFORE this driver's first turn -- deals
    -- large, variable damage (TERRA missing 271-345 of her 345 max across
    -- five attempts, sometimes lethal, sometimes not) that killed 1-2 of
    -- the 3 party members on every single attempt, with monster HP still
    -- reading full (555 x4) the whole time (no player action ever landed
    -- before the damage did). The field event this phase is waiting on
    -- appears to be the fight's own scripted continuation, and it never
    -- returns control when it is short a living party member -- so this
    -- budget's actual size does not matter once someone has died. Left at
    -- a middling 12000 (up from the original 6200, in case a genuine
    -- full-party-survives win's own tail is a little longer than a losing
    -- run's) rather than reverted outright, but the real fix is upstream:
    -- keeping TERRA and LOCKE from dying to the opener in the first place.
    H.driveUntil(function()
      if H.gameOverFired > 0 then return true end
      giveUp = giveUp + 1
      return (map() == 351 and H.hasControl() and H.tileAligned())
         or giveUp >= 11800
    end, 12000, {
      H.call(function()
        if H.gameOverFired > 0 then H.setPad({}); return end
        local ph = (giveUp % 8)
        if not H.hasControl() then H.setPad(ph < 4 and { "a" } or {})
        else H.setPad({}) end
      end),
    }, "ambush win-tail settle (or a real GameOver shows itself)"),
    -- WIN VERIFICATION (coordinator's directive 3, pass five): a real win
    -- needs ALL THREE -- H.gameOverFired stayed 0 the whole attempt, we
    -- are STILL on map 351 (a reload lands on the world map/town, not
    -- here), and STRAGO is still in the active party (thamasa-night-v1's
    -- own roster is pre-Strago, so his presence alone rules out a reload).
    H.call(function()
      H.setPad({})
      local realWin = H.gameOverFired == 0 and map() == 351
         and partyOf(STRAGO) ~= 0
      if H.gameOverFired > 0 then
        H.log(string.format(
          "ambush attempt %d LOST -- GameOver read-fired (event GameOver, " ..
          "$CC/E568), f%d", n, H.frame))
      elseif realWin then
        ambWon = true
        H.log(string.format(
          "ambush BEATEN on attempt %d, f%d, map=%d pos=(%d,%d) partyOf(STRAGO)=%d",
          n, H.frame, map(), H.fieldX(), H.fieldY(), partyOf(STRAGO)))
      else
        H.log(string.format(
          "ambush attempt %d LOST -- win verification failed (map=%d " ..
          "pos=(%d,%d) partyOf(STRAGO)=%d gameOverFired=%d), f%d",
          n, map(), H.fieldX(), H.fieldY(), partyOf(STRAGO),
          H.gameOverFired, H.frame))
      end
    end),
    H.cond(function() return not ambWon end, {
      lossReload(function() return ambBlob end, "ambush"),
    }, {}),
  })
end

-- ---------------------------------------------------------- FlameEater --
-- Battle 79, formation 449: shields 7, pierce class, weak ice, absorbs
-- fire, the authored OT6 water add.  Fired by stepping on the (46,53)
-- floor trigger (event_trigger.asm:1716), which re-forces party order
-- STRAGO,TERRA,LOCKE itself.  A win sets $0090=1 (the SAME _ca5ea9 gate
-- Dadaluma/TunnelArmr use); a loss is vanilla GameOver.  L26 HP8400 vs a
-- party around L16-19 is a long fight -- newFightDriver's own tactical
-- kit (boosted Fight, TERRA's Cure, the item bag) fights it honestly, no
-- bespoke per-turn plan (the Aqua Rake/Ice Rod optimizations are filed,
-- not built -- see the header).  A seed ladder (H.newSeedLadder, 5 rungs
-- like gen_sabin_train's battle 68) retries a loss from a checkpoint taken
-- just before the trigger tile, with a care stop each attempt.
local L79 = H.newSeedLadder("FlameEater (battle 79)", { attempts = 5 })
local feBlob, feWon = nil, false

local function flameEaterAttempt(n)
  -- PREP amendment (ninth pass), REVERSED THIS PASS (tenth): the ninth
  -- pass routed TERRA/LOCKE's turns to a boosted Ice CAST via opts.magic.
  -- MEASURED live, tenth pass: FlameEater's own AI script (ai_script.asm
  -- AIScript::_278) casts Safe+Reflect on itself once its hit counter
  -- passes 6, and a live trace showed FlameEater's hp FROZEN for 12000+
  -- straight frames right after that point while the party's OWN Ice
  -- casts apparently bounced back and helped grind them down to a wipe --
  -- two full seed-ladder attempts lost this exact way. Reflect only ever
  -- bounces SPELLS, never a Fight, so this drops opts.magic entirely and
  -- leans on gear instead: TERRA's Blizzard sword and STRAGO's Ice Rod
  -- (equipped right after its own chest, above) are both already
  -- ice-elemental, so a plain boosted Fight keeps the weakness bonus AND
  -- keeps landing for the entire fight, Reflect or no Reflect --
  -- docs/design/thamasa-route.md's own line ("the Ice Rod is a FlameEater
  -- counter picked up on the way in") is about exactly this weapon, not a
  -- Rod-break spell-cast trick.
  local F = H.newFightDriver("FlameEater", { tactical = true, boost = true,
    bank = 3, items = true, cure = true, healer = TERRA, healPercent = 60 })
  local notBattle, giveUp = 0, 0
  local loadReq
  -- was `seq({...})` here -- ambushAttempt's header explains the bug this
  -- hid (seqStep needs a plain list, not a pre-wrapped compound step); a
  -- bare {...} is the fix, same as every other H.cond call in this file.
  return H.cond(function() return feWon end, {}, {
    H.logStep(function()
      return string.format("FlameEater attempt %d at f%d", n, H.frame)
    end),
    n > 1 and seq({
      H.call(function() loadReq = H.requestLoadState(feBlob) end),
      H.waitFrames(2),
      H.call(function() H.checkReq(loadReq, "FlameEater entry-point reload") end),
      H.waitFrames(90),
      care("post-reload, attempt " .. n),
    }) or seq({}),
    L79.spread(n),
    H.call(function() H.log(string.format(
      "[FlameEater] approaching (46,53), attempt %d", n)) end),
    -- MEASURED (tenth pass, live): the trigger tile (46,53) sits ON the
    -- only path from this checkpoint's landing to the (46,52) creep target
    -- (a straight two-tile walk), so the fight can start MID-NAV, fought
    -- by creepNav's own internal tactical driver -- not only via the
    -- dedicated pressWalk("down",...) trigger step below. FLAMEEATER_WALK
    -- (not plain WALK) carries the real fight kit for exactly that case
    -- (see its own comment). Two prior fixes tried and rejected here, for
    -- the record: a passive settle wait (didn't press a button to fight
    -- the mid-nav trigger) and an unconditional F.frame() drive (read
    -- newFightDriver's own raw menu byte, which is NOT reliably 0 outside
    -- battle -- one live trace showed menu=$82/cmds=FF,FF,FF,FF/monsters=6,
    -- uninitialized RAM, and the driver pressed X on it).
    creepNav(46, 52, FLAMEEATER_WALK),
    -- MEASURED (tenth pass, live), TWICE: a point-in-time H.cond check right
    -- after creepNav is not enough -- it can read "no battle yet" and then
    -- have the fight start a few frames INTO the settle wait that follows,
    -- which is a passive H.waitUntil that never notices (hasControl()
    -- correctly stays false for the whole fight, not a brief flicker, so
    -- the wait just times out). The fix: one continuous driveUntil that
    -- presses "down" (pressWalk's own dialog-aware idiom) every frame,
    -- checking for "the fight has started or is already won" on EVERY
    -- frame rather than once -- if it's already resolved or already
    -- fighting (creepNav's own tactical kit, carrying FlameEater's real
    -- loadout, caught it mid-nav -- the trigger tile sits on the only path
    -- in), this exits in 0 frames with no button ever pressed, same as the
    -- ordinary "already there" case elsewhere in this file; if not, it
    -- walks onto (46,53) and PHASE 1 below picks up the resulting battle
    -- (PHASE 1's own debounce loop already handles both "already over" and
    -- "still going" correctly, so no separate battleActive() wait or
    -- formation assert is needed here either).
    pressWalk("down", function()
      return sw(0x0090) == 1 or H.battleLoadStarted() or H.battleActive()
    end, 8000, "walk onto (46,53) until battle 79 starts (or it's already won)"),
    -- PHASE 1 (pass five fix, same as ambushAttempt above -- see its own
    -- comment for the measured bug this debounce fixes): drive
    -- tactically until the battle module is confirmed gone for
    -- CONFIRM_BATTLE_GONE consecutive frames, or H.gameOverFired reads
    -- (the READ watch, ground truth) fires -- whichever first.
    H.driveUntil(function()
      if H.gameOverFired > 0 then return true end
      if H.battleLoadStarted() or H.battleActive() then
        notBattle = 0
      else
        notBattle = notBattle + 1
      end
      return notBattle >= CONFIRM_BATTLE_GONE
    end, 1800000, {
      H.call(function()
        if H.gameOverFired > 0 then H.setPad({}); return end
        F.frame()
      end),
    }, "FlameEater fight (attempt " .. n .. ")"),
    H.call(function()
      H.log(string.format(
        "[FlameEater] phase 1 done (battle module gone or GameOver read), " ..
        "attempt %d, f%d, gameOverFired=%d", n, H.frame, H.gameOverFired))
    end),
    -- PHASE 2 (pass five fix; budget middled up ninth pass -- see the
    -- ambush's own phase 2 above for the measured story: raising this a
    -- lot did NOT fix a loss, since a dead-party-member win-tail stall
    -- turned out to be the real shape, not an underset budget. Left at a
    -- middling 12000 on the same reasoning as the ambush). $0090 alone is
    -- a decent positive signal here (thamasa-night-v1 never sets it
    -- either, so ==1 cannot be confused with the reloaded save the way the
    -- ambush's $050A==0 could) but the win-verification call below still
    -- cross-checks party/roster sanity rather than trusting one switch in
    -- isolation, matching the ambush fix for consistency.
    H.driveUntil(function()
      if H.gameOverFired > 0 then return true end
      giveUp = giveUp + 1
      return sw(0x0090) == 1 or giveUp >= 11800
    end, 12000, {
      H.call(function()
        if H.gameOverFired > 0 then H.setPad({}); return end
        local ph = (giveUp % 8)
        if not H.hasControl() then H.setPad(ph < 4 and { "a" } or {})
        else H.setPad({}) end
      end),
    }, "the win tail flips $0090 (or a real GameOver shows itself)"),
    -- WIN VERIFICATION (coordinator's directive 3, pass five): gameOverFired
    -- stayed 0, $0090 flipped, and the roster is still sane (STRAGO/TERRA
    -- present -- a reload to thamasa-night-v1 would drop both).
    H.call(function()
      H.setPad({})
      local realWin = H.gameOverFired == 0 and sw(0x0090) == 1
         and partyOf(STRAGO) ~= 0 and partyOf(TERRA) ~= 0
      if H.gameOverFired > 0 then
        H.log(string.format(
          "FlameEater attempt %d LOST -- GameOver read-fired (event " ..
          "GameOver, $CC/E568), f%d", n, H.frame))
      elseif realWin then
        feWon = true
        H.log(string.format(
          "FlameEater BEATEN on attempt %d, f%d, map=%d pos=(%d,%d)",
          n, H.frame, map(), H.fieldX(), H.fieldY()))
      else
        H.log(string.format(
          "FlameEater attempt %d LOST -- win verification failed " ..
          "($0090=%d partyOf(STRAGO)=%d partyOf(TERRA)=%d " ..
          "gameOverFired=%d, giveUp=%d), f%d",
          n, sw(0x0090), partyOf(STRAGO), partyOf(TERRA), H.gameOverFired,
          giveUp, H.frame))
      end
    end),
    H.cond(function() return not feWon end, {
      lossReload(function() return feBlob end, "FlameEater"),
    }, {}),
  })
end

-- ------------------------------------------------------------------------
local steps = {
  -- ---- 1. cold Continue the thamasa-night-v1 checkpoint -----------------
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  (function()
    local ph = 0
    local function atSite()
      return H.worldMode() and H.worldX() == 249 and H.worldY() == 128
    end
    return H.driveUntil(function() return atSite() and bright() >= 15 end,
      4000, {
      H.call(function()
        ph = (ph + 1) % 48
        if atSite() or bright() < 15 then H.setPad({}); return end
        H.setPad(ph < 8 and { "a" } or {})
      end),
    }, "Continue -> the L tile (A gated by brightness+position)")
  end)(),
  H.release(),
  H.waitUntil(function()
    return H.worldMode() and bright() >= 15 and H.worldHasControl()
  end, 1800, "world control at the L tile", 5),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format(
      "[ot6] boot f%d world=(%d,%d) party0=%02X party1=%02X party3=%02X",
      H.frame, H.worldX(), H.worldY(), H.readByte(0x1850) & 7,
      H.readByte(0x1851) & 7, H.readByte(0x1853) & 7))
    H.assertEntryContract("thamasa-night-v1")
  end),

  -- ---- 2. care, then PREP, then into town ---------------------------------
  H.fieldCare({ tag = "care at the L tile", threshold = 0.9 }),

  H.driveUntil(function() return not H.worldMode() end, 2000, {
    H.call(function()
      if H.battleLoadStarted() then H.setPad({ l = true, r = true }); return end
      H.setPad({ right = true })
    end),
  }, "held RIGHT onto (250,128) -> Thamasa 343 (23,46)"),
  H.release(),
  H.waitUntil(function() return map() == 343 and H.hasControl() end, 3000,
    "Thamasa map re-loaded", 5),
  H.call(function()
    H.log(string.format("[ot6] town re-entry f%d map=%d (%d,%d)",
      H.frame, map(), H.fieldX(), H.fieldY()))
  end),

  -- ---- 2.5. PREP (owner's ruling, ninth pass, replacing the grind outright
  -- -- see the STATUS header): MEASURED live this pass -- doing this on the
  -- WORLD MAP (right after boot, the first thing tried) hangs every equip
  -- menu's own "back out" step at its 1200-frame cap: M.hasControl(), what
  -- that step waits for, tests the field party-object's movement-type byte
  -- ($087c, wants 2 = user-controlled), and the world map's own party
  -- object apparently never reads that way even with the menu fully closed
  -- -- H.worldHasControl() is the world map's own, DIFFERENT gate, and none
  -- of M.equipWeapon/M.equipEsper's internals know about it. Town is the
  -- fix (also the owner's own first suggestion): plain M.hasControl() is
  -- exactly what every other menu call in this file already trusts here.
  -- Right after town re-entry, before the shop/inn -- STRAGO isn't in the
  -- party yet; his own esper equip happens right after he joins, below.
  H.call(function()
    H.log(string.format(
      "[prep] gearing TERRA/LOCKE at f%d map=%d (%d,%d): TERRA %d/%dhp, " ..
      "LOCKE %d/%dhp (pre-gear)", H.frame, map(), H.fieldX(), H.fieldY(),
      H.charHp(TERRA), H.charMaxHp(TERRA), H.charHp(LOCKE), H.charMaxHp(LOCKE)))
  end),
  H.equipLoadout(TERRA, TERRA_GEAR, { tag = "TERRA loadout" }),
  H.equipLoadout(LOCKE, LOCKE_GEAR, { tag = "LOCKE loadout" }),
  H.equipEsper(charPos(TERRA), SHIVA_ESPER, { tag = "SHIVA -> TERRA (Ice)" }),
  H.equipEsper(charPos(LOCKE), MADUIN_ESPER, { tag = "MADUIN -> LOCKE (Ice)" }),
  -- BACK ROW (coordinator's directive, tenth pass): the owner's own FIRST
  -- move, live, before anything else -- M.setRows's own header explains
  -- why this matters here specifically: "damage taken is halved for
  -- physical attacks" regardless of weapon, so this is real mitigation
  -- against the ambush's opener, not a damage-output tradeoff, for anyone
  -- whose offense doesn't run through a Fight command. TERRA's is Ice
  -- magic and STRAGO's is Lore, so back row costs them nothing at all;
  -- LOCKE still has a Fight fallback (per M.setRows's own note, back row
  -- only reduces HIS damage OUTPUT, never his damage TAKEN) but a LOCKE
  -- who survives to swing does more than one who doesn't survive at all.
  H.setRows({ [TERRA] = true, [LOCKE] = true }, { tag = "TERRA/LOCKE back row" }),
  H.call(function()
    H.log(string.format(
      "[prep] TERRA/LOCKE geared f%d: TERRA %d/%dhp, LOCKE %d/%dhp (post-gear)",
      H.frame, H.charHp(TERRA), H.charMaxHp(TERRA), H.charHp(LOCKE),
      H.charMaxHp(LOCKE)))
  end),

  -- ---- 2.6. stock up before the inn (owner's ruling, pass six; MOVED
  -- pre-inn along with the grind -- both the shop and the new (33,25) save
  -- point are available before the inn, and the grind's own tactical
  -- driving eats the bag fast, so there is no reason to wait). Quantities
  -- are generous asks, not requirements -- H.buyItem's own purse-clamp
  -- acceptance takes whatever gil actually covers and logs it, same as
  -- gen_sabin_train's shop.
  crossDoor(26, 37, 347, 36, 44, "item shop door 343(26,37)->347(36,44)"),
  -- MEASURED (this pass, live): shopTalk's own staging picked (36,40) as
  -- reachable right after the door load, then H.navTo's live walk failed
  -- with "no path (36,44)->(36,40)" -- the same "door loads finalize the
  -- decompressed prop table LATE" timing gap gen_zozo2/gen_zozo4 already
  -- measured (this file's own map-351-entry comment cites it too). A
  -- settle wait before the first pathfinding call is the fix there; same
  -- fix here.
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 2400,
    "shop interior settled before pathfinding", 10),
  H.waitFrames(150),
  shopTalk(36, 39, "Thamasa item shop"),
  H.buyItem(TONIC, 0, function() return 30 - H.invCountOf(TONIC) end, "TONIC to 30"),
  H.buyItem(POTION, 1, function() return 15 - H.invCountOf(POTION) end, "POTION to 15"),
  -- Coordinator's directive (pass six): "grab a healthy Fenix stock -- the
  -- ambush plan leans on revives" -- raised from 8 to 20 (gil was in no
  -- danger of running short: 64594 left over buying to 8 the first time).
  H.buyItem(FENIX_DOWN, 6, function() return 20 - H.invCountOf(FENIX_DOWN) end,
    "FENIX DOWN to 20"),
  H.call(function()
    H.log(string.format(
      "[shop] Thamasa item shop done: tonic=%d potion=%d fenix=%d gil=%d f%d",
      H.invCountOf(TONIC), H.invCountOf(POTION), H.invCountOf(FENIX_DOWN),
      gil(), H.frame))
  end),
  shopClose("Thamasa item shop"),
  -- MEASURED (this pass, source decode): the return record is NOT the
  -- forward one mirrored -- map 347's own short_entrance block ($1656,
  -- decoded the same way) is src=(36,45) map=87(+256=343) dest=(26,39),
  -- two tiles off the forward door's own (26,37)/(36,44) on both ends.
  crossDoor(36, 45, 343, 26, 39, "item shop door 347(36,45)->343(26,39), return"),

  -- ---- 3. the inn: door, innkeeper, the whole fire scene -----------------
  crossDoor(12, 19, 346, 23, 23, "inn door 343(12,19)->346(23,23)"),
  H.call(function()
    H.log(string.format("[ot6] inn interior f%d (%d,%d)", H.frame,
      H.fieldX(), H.fieldY()))
  end),
  -- MEASURED (2026-08-19, this generator's own probe pass): the innkeeper
  -- at (24,15) sits behind a counter tile at (24,16) that bfsPath refuses
  -- as a stand (it is solid), while (24,17) -- two tiles south, the far
  -- side of the counter -- IS reachable (bfsPath len 7 from the door
  -- landing).  This is the Dadaluma note's "talk-across-a-counter"
  -- mechanic (CheckNPCs' extension, player.asm @478e): stand one tile back
  -- from the counter, face it, and the talk reaches through to the NPC
  -- beyond.  chaseTalk's "walk directly adjacent" model does not fit a
  -- counter NPC (it was built for wandering NPCs on open floor), so this is
  -- a face+A stand rather than a chase.
  H.navTo(24, 17, { maxFrames = 9000, playBattles = "tactical", healer = TERRA,
    bank = 3, items = true }),
  H.driveUntil(function()
    return H.readByte(0x087f + H.readWord(0x0803)) == 0  -- facing UP
  end, 300, {
    H.call(function() H.setPad({ up = true }) end),
  }, "face up at the inn counter"),
  H.release(), H.waitFrames(4),
  (function()
    local ph = 0
    return H.driveUntil(function() return H.dialogWaiting() end, 3000, {
      H.call(function()
        ph = (ph + 1) % 12
        H.setPad(ph < 4 and { a = true, up = true } or {})
      end),
    }, "talk-across-the-counter -> innkeeper's 1 GP choice")
  end)(),
  -- one continuous scripted stretch from here: the Yes confirm (default
  -- cursor), the innkeeper walking off, and (since $008D=1) straight into
  -- the night/fire scene with no further choice screens (see header).
  H.advanceStory(calm(30), 30000, { playBattles = "tactical" }),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 343, "control back on Thamasa town map after the fire")
    H.assertEq(H.fieldX(), 12, "fire scene end x (12,21)")
    H.assertEq(H.fieldY(), 21, "fire scene end y")
    H.assertEq(sw(0x008E), 1, "$008E SET -- the fire has started")
    H.assertEq(sw(0x0190), 1, "$0190 SET (the fire's companion switch)")
    H.assertEq(sw(0x0090), 0, "$0090 CLEAR -- FlameEater not fought yet")
    H.assertEq(partyOf(SHADOW), 0, "SHADOW left the party at the inn night")
    H.log(string.format(
      "[ot6] FIRE STARTED f%d map=%d (%d,%d) party[TERRA LOCKE]=%d %d",
      H.frame, map(), H.fieldX(), H.fieldY(),
      H.readByte(0x1850) & 7, H.readByte(0x1851) & 7))
    H.screenshot("thamasa_fire_started")
  end),
  -- ISSUE #127 PROBE: known-good moment (right after the fire scene,
  -- before the house is entered) -- baseline for the $0867+41*id dump, and
  -- where the write-watch on those four bytes is armed (before the house).
  H.call(function()
    probeDump("GOOD-post-fire")
    armProbeWatch()
  end),

  -- ---- 4. talk to Strago at the house door -> STRAGO joins -> map 351 ---
  (function()
    local idxCell = { v = 0x14 }
    return seq({
      H.call(function()
        idxCell.v = findNpc(39, 24, 0x14)
        H.log(string.format("[ot6] chasing Strago's door NPC at slot $%02X, f%d",
          idxCell.v, H.frame))
      end),
      chaseTalkLazy(function() return idxCell.v end, 9000,
        "chase+talk Strago's door NPC",
        { done = function() return H.eventRunning() or H.dialogWaiting() end }),
    })
  end)(),
  H.advanceStory(function() return map() == 351 and H.hasControl() end,
    40000, { playBattles = "tactical" }),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(map(), 351, "loaded into the burning house (map 351)")
    H.assertEq(sw(0x02E7), 1, "$02E7 -- STRAGO joined")
    H.assertEq(sw(0x02F7), 1, "$02F7 -- STRAGO available")
    H.assertEq(partyOf(STRAGO) ~= 0, true, "STRAGO is in party 1")
    H.assertEq(partyOf(TERRA) ~= 0, true, "TERRA is in party 1")
    H.assertEq(partyOf(LOCKE) ~= 0, true, "LOCKE is in party 1")
    -- P3 (issue #127): inlined rather than calling logStragoJoin() here --
    -- that helper is itself an H.call step object, and invoking it from
    -- inside ANOTHER H.call's body only constructs a throwaway step and
    -- runs nothing (measured: no [P3] line ever appeared in a real run
    -- that reached this point).  logStragoJoin is left in place as a
    -- standalone step for a future caller; this inlines its body.
    do
      -- ff6/notes/field-ram.txt:885-895: the 37-byte character record,
      -- indexed by character id (same convention as $1850+charId): +$08
      -- level, +$09 current HP, +$0B max HP (top 2 bits are the hp-boost
      -- flag, masked off), +$0D current MP, +$0F max MP (same mask).
      local lvl = H.readByte(0x1600 + 37 * STRAGO + 0x08)
      local hp = H.readWord(0x1600 + 37 * STRAGO + 0x09)
      local mhp = H.readWord(0x1600 + 37 * STRAGO + 0x0B) & 0x3FFF
      local mp = H.readWord(0x1600 + 37 * STRAGO + 0x0D)
      local mmp = H.readWord(0x1600 + 37 * STRAGO + 0x0F) & 0x3FFF
      H.log(string.format(
        "[P3] STRAGO join stats: level=%d hp=%d/%d mp=%d/%d (measured, no " ..
        "norm_lvl expected at join)", lvl, hp, mhp, mp, mmp))
    end
    H.log(string.format("[ot6] map 351 entry f%d (%d,%d)", H.frame,
      H.fieldX(), H.fieldY()))
    H.screenshot("thamasa_house_entry")
  end),

  -- ---- 4.5. PREP, part 2: STRAGO's esper, right after he joins (owner
  -- confirmed the menu works inside the burning house -- the earlier
  -- "fieldCare broken on 351" finding was this file's own library bug, not
  -- a game limit).  BISMARK by elimination (see the STATUS header/PREP
  -- comment above: it grants Haste/Slow, not a Water spell as first
  -- assumed -- Aqua Rake stays STRAGO's real water answer).  charPos(STRAGO)
  -- resolves his char-select row live rather than guessing it, since this
  -- file never asserts what row he joins into.
  H.equipEsper(charPos(STRAGO), BISMARK_ESPER, { tag = "BISMARK -> STRAGO" }),
  -- BACK ROW, part 2 (coordinator's directive, tenth pass): STRAGO joins
  -- into whatever row the game defaults him to, so this asserts it rather
  -- than trusting it -- his whole offense is Lore, which (like TERRA's
  -- magic) never runs through the row-checked Fight code path, so back
  -- row is pure mitigation for him too, no cost at all.
  H.setRows({ [STRAGO] = true }, { tag = "STRAGO back row" }),

  -- ---- 5. the burning house: two chests, the ambush, FlameEater ----------
  -- MEASURED (2026-08-19): the load_map lands the party in a 3-tile
  -- landing pocket ((4,10)-(4,11)-(4,12); prop1=$F7, fully solid, on all
  -- three other sides -- bfsPath confirmed the enclosure before this fix).
  -- The way out is a FLOOR TRIGGER at (4,10) (event_trigger.asm:1714,
  -- _cbe5e4), not an automatic startup event: stepping onto it (gated
  -- `$0190==1`, true here) plays the short "avoid the flames... find
  -- RELM!" scene, re-orders the party, walks LOCKE/STRAGO a few tiles
  -- diagonally into the house proper, and clears $0190.  Ridden with
  -- advanceStory like every other scripted stretch.
  H.navTo(4, 10, WALK),
  H.advanceStory(function()
    return H.hasControl() and H.tileAligned() and bright() >= 15
       and sw(0x0190) == 0
  end, 12000, { playBattles = "tactical" }),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format(
      "[ot6] map 351 opening scene settled f%d (%d,%d) $0190=%d $008F=%d",
      H.frame, H.fieldX(), H.fieldY(), sw(0x0190), sw(0x008F)))
    H.assertEq(sw(0x0190), 0, "$0190 cleared by the (4,10) trigger")
  end),
  -- door loads finalize the decompressed prop table LATE (gen_zozo2's
  -- measured rule, reused by gen_zozo4's door()); settle before any
  -- pathfinding reads it.
  H.waitUntil(function()
    return H.hasControl() and H.tileAligned() and bright() >= 15
  end, 2400, "map 351 settled before pathfinding", 10),
  H.waitFrames(150),
  -- The house graph, decoded from ff6/src/field/trigger/short_entrance.dat
  -- offset $167a (17 records, map 351 -> map 351) and cross-checked against
  -- a live full-map tile-property dump (probe_thamasa_house_map.lua): 35
  -- cardinally-disconnected tile islands stitched together ONLY by these
  -- warps.  See the STATUS header for the full island graph.  Each hop
  -- rides houseWarp() (crossDoor's same-map twin); a care() stop follows
  -- every hop, per the task's "care between chained fights" rule -- the
  -- wandering flames sit inside these islands (12 of them, all decoded
  -- from npc_prop.asm), so a contact battle can start on any leg.
  H.call(function() H.log("[ot6] island 0 -> 13: (4,3)->(4,38)") end),
  houseWarp(4, 3, 4, 38, "P1 (4,3)->(4,38): the floor warp into the main hall"),
  care("after P1"),
  -- MEASURED (2026-08-19): this whole route is deterministic frame-for-
  -- frame given identical code (P1 lands at (4,38) on the exact same frame,
  -- 10534, across half a dozen otherwise-different attempts), which means
  -- the wandering flames' contact timing and the pincer/ambush RNG draws
  -- are ALSO pinned by real-time frame count, not luck -- a plain re-run
  -- with no code change reproduces the same wipe every time. A battle
  -- seed ladder (H.newSeedLadder, the FlameEater pattern below) is the
  -- correct tool for this but needs a save/reload-on-loss loop, which
  -- needs the wipe to be caught rather than hard-erroring the whole run
  -- (M.run's own pcall stops the process on the first error() -- there is
  -- no per-step retry); building that around H.navTo's built-in wipe
  -- canary (a hard error by design, ot6_field.lua's wipeCanary) was out of
  -- scope for this pass. This single extra wait is the cheap version of
  -- the same idea: shifting every subsequent battle's frame phase by a
  -- fixed offset changes which byte of the seed table each one draws
  -- (spread()'s own docs: "Replaces H.waitFrames((n-1)*37)"), without
  -- needing the full ladder machinery.
  -- MEASURED (tenth pass): this file's own PREP additions (gear/esper
  -- equips, back row, the pre-ambush top-off) push several thousand extra
  -- frames earlier in the route, which shifted this same 37-frame spread
  -- off whatever phase used to keep island 13's wandering flames clear of
  -- the (4,30)->(2,24) hop -- "no path (4,30)->(2,24) [0 edges
  -- blocklisted, 20 retries]" reproduced twice, back to back, deterministic
  -- given identical code (the same "pinned by real-time frame count" fact
  -- this wait's own header cites). Re-spread to clear it.
  H.waitFrames(137),

  -- MEASURED (2026-08-19): island 13 (three wandering flames,
  -- (2,29)/(5,31)/(4,35)) and island 11 (three more,
  -- (17,34)/(22,25)/(17,27)) chain-battled the party WIPED on multiple live
  -- runs -- 4-5 contact fights back to back with no field-menu heal between
  -- them (only newFightDriver's in-battle threshold heal, which can't act
  -- once the healer is down, AND H.fieldCare turned out to be broken on
  -- this map, see care()'s note) burned all 3 Fenix Downs and then had
  -- nothing left when the LAST survivor also went down. Two things
  -- together got a live run past this stretch: a mid-leg waypoint + care()
  -- (halving the run of chained fights between real heals; (4,30) and
  -- (24,29) are plain confirmed-walkable tiles from the grid dump, nothing
  -- special about the coordinates) AND fleeing the wandering flames
  -- (FLEE_WALK) on every leg through these two islands rather than fighting
  -- every one -- none of the twelve flames are required content (see
  -- houseWarp's own note on `flee`).
  creepNav(4, 30, FLEE_WALK),
  care("partway through the main hall (island 13)"),

  H.call(function() H.log("[ot6] island 13 -> 11: (2,24)->(26,36)") end),
  houseWarp(2, 24, 26, 36, "P2 (2,24)->(26,36): into the ambush hall", "flee"),
  care("after P2"),

  -- MEASURED (2026-08-19): a (24,29) mid-leg waypoint was tried here too
  -- (matching island 13's), but bfsPath came back "no path (26,36)-
  -- >(24,29)" on a live run -- the offline flood fill that suggested it was
  -- walkable used undirected reachability (any nonzero exit nibble), which
  -- overlooks one-way exit-bit walls the live engine enforces; the earlier
  -- P2 fix (see the STATUS header's dead-end #1) hit the same false-
  -- positive-connectivity trap. Dropped rather than re-guessed: flee mode
  -- already got P2 through island 13 wipe-free and much faster (16621 vs
  -- 35999 frames on the same leg pre-flee), so island 11's own P2->ambush
  -- stretch goes straight there without a waypoint that isn't real.
  -- MEASURED (2026-08-19): with the (24,29) waypoint gone, this leg went
  -- straight back to fighting every wandering flame between (26,36) and
  -- (21,22) (WALK is tactical) and wiped again, right where the earlier
  -- attempts did. FLEE_WALK here too: the flames along the way are still
  -- optional, and the SCRIPTED ambush itself, once triggered by stepping
  -- on (21,22), should be exactly the "unrunnable formation" flee mode's
  -- own fallback describes -- when running fails for M.FLEE_CAP frames it
  -- hands off to the SAME tactical driver WALK would have used, so in
  -- theory the ambush still gets fought properly.  MEASURED live: it does
  -- NOT work out that way for a formation flee refuses outright.  The log:
  -- "flee: this formation refuses the run ($b1 bit 1 held 60 frames -- a
  -- pincer, or a monster nobody runs from) after 62 frames; fighting it
  -- out instead" -- and by the time the fallback took over, partyhp was
  -- already 0,5,0,0 on the very FIRST logged battle frame.  A pincer
  -- (party surrounded) apparently still lets the enemy act during the ~60
  -- frames flee spends standing still trying to run, so attempting to flee
  -- an unrunnable ambush is worse than not trying -- it eats a full round
  -- of free damage before the tactical driver ever gets a turn. Fix:
  -- FLEE_WALK only as far as (21,23), one tile short of the trigger (a
  -- confirmed-walkable staging tile from the grid dump), so any wandering
  -- flame on the way there is still skippable; then a single tactical
  -- WALK hop onto (21,22) itself so the ambush is fought from turn one,
  -- never attempted-and-refused.
  -- MEASURED (2026-08-19): staging at (21,23) and stepping onto (21,22)
  -- tactically (below) fixed the "flee refuses the ambush and eats a free
  -- round" problem, but the ambush itself still wiped the party outright --
  -- see ambushAttempt's own header for the evidence (TERRA and STRAGO both
  -- read 0 hp on the battle's very first frame, before the driver ever
  -- acted). No amount of pre-fight preparation moves that number; this is
  -- the same "hard, luck-sensitive fight" shape FlameEater already has a
  -- seed ladder for, so it gets one too, checkpointed here.
  -- FULL HP/MP BEFORE STEPPING IN (coordinator's directive, tenth pass):
  -- the owner Fenix'd + Cure'd to top off before triggering the ambush --
  -- care()'s own map-351 skip (above, "H.fieldCare is broken on map 351")
  -- predates the STATUS header's own correction (the menu works fine in
  -- the house; that was this file's library bug, already fixed) and this
  -- fight's opener is exactly the case a partial top-off isn't enough
  -- for, so this calls H.fieldCare directly here rather than trusting the
  -- wrapper's stale skip. threshold=1.0: full, not "mostly there".
  H.call(function()
    H.log(string.format(
      "[prep] pre-ambush top-off f%d: TERRA %d/%d LOCKE %d/%d STRAGO %d/%d",
      H.frame, H.charHp(TERRA), H.charMaxHp(TERRA), H.charHp(LOCKE),
      H.charMaxHp(LOCKE), H.charHp(STRAGO), H.charMaxHp(STRAGO)))
  end),
  H.fieldCare({ tag = "pre-ambush full top-off", threshold = 1.0 }),
  H.call(function()
    H.log(string.format(
      "[prep] pre-ambush top-off done f%d: TERRA %d/%d LOCKE %d/%d STRAGO %d/%d",
      H.frame, H.charHp(TERRA), H.charMaxHp(TERRA), H.charHp(LOCKE),
      H.charMaxHp(LOCKE), H.charHp(STRAGO), H.charMaxHp(STRAGO)))
  end),
  H.call(function() H.log("[ot6] checkpointing before the ambush trigger") end),
  (function()
    local ckReq
    return seq({
      H.call(function() ckReq = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(ckReq, "ambush entry-point checkpoint")
        ambBlob = ckReq.blob
      end),
    })
  end)(),
  L45.watch(),
  ambushAttempt(1),
  ambushAttempt(2),
  ambushAttempt(3),
  ambushAttempt(4),
  ambushAttempt(5),
  H.call(function()
    if not ambWon then
      error("ambush (battle 45): all 5 seed-ladder attempts lost", 0)
    end
  end),
  L45.report(),
  -- SUPERSEDED 2026-08-19 (issue #127, pass five, coordinator's major
  -- correction): the "post-ambush field-control stall" that passes three
  -- and four spent most of their time on (world-mode-shaped $1f64, no
  -- Strago in the party, position stuck around (8,7)) was NEVER a stuck
  -- engine. It was the reloaded thamasa-night-v1 SRAM -- the ambush was
  -- being LOST the whole time (a real GameOver, invisible to pass four's
  -- own canary because that canary armed an EXEC watch on $CC/E568, and
  -- GameOver there is event-interpreter DATA, never CPU-executed code, so
  -- the watch could never fire), and the win-tail's blind A-mash walked
  -- the resulting Game Over screen onto the vanilla Continue prompt.
  -- ambushAttempt() above now (a) drives the fight tactically with a
  -- debounced end-of-battle check instead of handing off to the blind
  -- A-mash mid-fight, (b) watches a READ watch on those same bytes
  -- (lib/ot6.lua, ground truth -- the event interpreter really does fetch
  -- them to run the script), and (c) verifies a win against map/roster
  -- ground truth instead of a switch that reads identically on the
  -- reloaded save. A real win no longer needs a bespoke settle dance here:
  -- ambushAttempt's own phase 2 already leaves the party settled on map
  -- 351 with control back before ambWon is allowed to flip true. The
  -- probe instruments this investigation built (probeDump/probeEventDump/
  -- probePcTrail/armProbeWatch/PROBE_IDS/SHOT_FRAMES_TAIL, plus
  -- ambushAttempt's own PRE/POST-BATTLE45 probeDump calls) are KEPT for
  -- the next pass that needs them; only the deliberate stop below (an
  -- always-false 400-frame trace + a forced error(), built to gather this
  -- pass's screenshot evidence and never meant to reach FlameEater) is
  -- removed.
  care("after the (21,22) ambush"),

  H.call(function() H.log("[ot6] island 11 -> 1: (26,21)->(21,9)") end),
  houseWarp(26, 21, 21, 9, "P3 (26,21)->(21,9): into the north corridor", "flee"),
  care("after P3"),

  -- the Fire Rod spur: a dead-end island (28) off the north corridor,
  -- reached and left by the SAME pair, forward then return
  H.call(function() H.log("[ot6] island 1 -> 28: (28,3)->(4,55), Fire Rod spur") end),
  houseWarp(28, 3, 4, 55, "P5 (28,3)->(4,55): the Fire Rod spur"),
  care("after the Fire Rod spur-in"),
  chestAuto(4, 52, 104, "Fire Rod", FIRE_ROD),
  care("after the Fire Rod"),
  houseWarp(4, 56, 28, 5, "P5 return (4,56)->(28,5): back to the north corridor"),
  care("after the Fire Rod spur-out"),

  H.call(function() H.log("[ot6] island 1 -> 12: (23,3)->(46,27)") end),
  houseWarp(23, 3, 46, 27, "P4 (23,3)->(46,27): into the east wing"),
  care("after P4"),

  -- the Ice Rod spur: a dead-end island (4) off the east wing, same shape
  H.call(function() H.log("[ot6] island 12 -> 4: (49,21)->(45,10), Ice Rod spur") end),
  houseWarp(49, 21, 45, 10, "P6 (49,21)->(45,10): the Ice Rod spur"),
  care("after the Ice Rod spur-in"),
  chestAuto(45, 7, 105, "Ice Rod", ICE_ROD),
  care("after the Ice Rod"),
  -- MEASURED (tenth pass, live): FlameEater's own AI script (ai_script.asm
  -- AIScript::_278) casts Safe+Reflect on itself once its own hit counter
  -- (battle_var 2) passes 6 -- exactly the brief's own prediction. Once
  -- that lands, TERRA/LOCKE's Ice MAGIC cast (this file's whole "lead with
  -- AoE weakness magic" plan) starts bouncing off Reflect every single
  -- turn instead of landing -- a live trace showed FlameEater's hp FROZEN
  -- for 12000+ straight frames while the party's OWN reflected casts
  -- apparently helped grind them down to a wipe. docs/design/thamasa-
  -- route.md's own line is the fix: "Rods break for a spell cast, so the
  -- Ice Rod is a FlameEater counter" -- but the counter that actually
  -- matters here is simpler than that: Reflect only ever bounces SPELLS,
  -- never a physical Fight, elemental or not, so an ice-elemental WEAPON
  -- swung as a plain Fight keeps landing (and keeps the weakness bonus)
  -- for the entire fight, Reflect or no Reflect. STRAGO carries no weapon
  -- of his own in this route; the Ice Rod picked up right here is his.
  H.equipWeapon(charPos(STRAGO), ICE_ROD, { slot = 0, tag = "Ice Rod -> STRAGO" }),
  houseWarp(45, 11, 49, 23, "P6 return (45,11)->(49,23): back to the east wing"),
  care("after the Ice Rod spur-out"),

  H.call(function() H.log("[ot6] island 12 -> 26: (43,21)->(21,54)") end),
  houseWarp(43, 21, 21, 54, "P7 (43,21)->(21,54): into the south hall"),
  care("after P7"),

  -- island 26 -> 24 is one-way in the decoded table (no return pair
  -- recorded) -- consistent with it leading straight to FlameEater's room,
  -- whose own win tail exits via load_map 349 rather than back through here
  H.call(function() H.log("[ot6] island 26 -> 24: (21,49)->(46,54), FlameEater's chamber") end),
  houseWarp(21, 49, 46, 54, "P8 (21,49)->(46,54): into FlameEater's chamber"),
  care("before the FlameEater trigger"),

  -- checkpoint the entry point for the retry ladder, once
  H.call(function() H.log("[ot6] checkpointing before the FlameEater trigger") end),
  (function()
    local ckReq
    return seq({
      H.call(function() ckReq = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(ckReq, "FlameEater entry-point checkpoint")
        feBlob = ckReq.blob
      end),
    })
  end)(),
  L79.watch(),
  flameEaterAttempt(1),
  flameEaterAttempt(2),
  flameEaterAttempt(3),
  flameEaterAttempt(4),
  flameEaterAttempt(5),
  H.call(function()
    if not feWon then
      error("FlameEater: all 5 seed-ladder attempts lost", 0)
    end
  end),
  L79.report(),

  -- ---- 6. the win tail: rescue, the night talk at Strago's house --------
  H.advanceStory(function()
    return map() == 349 and H.hasControl() and sw(0x0091) == 1
       and sw(0x0098) == 1
  end, 60000, { playBattles = "tactical" }),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 349, "control in Strago's house after the win tail")
    H.assertEq(sw(0x0091), 1, "$0091 -- FlameEater aftermath resolved")
    H.assertEq(sw(0x0098), 1, "$0098 -- morning-after companion switch")
    H.assertEq(sw(0x0090), 1, "$0090 still SET -- FlameEater beaten")
    H.log(string.format("[ot6] win tail settled f%d (%d,%d)", H.frame,
      H.fieldX(), H.fieldY()))
    H.screenshot("thamasa_after_fight")
  end),

  -- ---- 7. leave the house -> Shadow's goodbye ----------------------------
  -- SHADOW's gear, recorded before remove_equip fires, so the exit
  -- contract's "gear back in the bag" claim is an inventory delta rather
  -- than a guess at what he carries.
  H.call(function()
    H._shadowWeapon = H.readByte(0x1600 + 37 * SHADOW + 0x1F)
    H._shadowWeaponBefore = H._shadowWeapon ~= 0xFF
      and H.invCountOf(H._shadowWeapon) or nil
    H.log(string.format("[ot6] SHADOW's weapon before remove_equip: $%02X (bag=%s)",
      H._shadowWeapon, tostring(H._shadowWeaponBefore)))
  end),
  -- MEASURED (tenth pass, live): "no path (64,13)->(37,25) [0 edges
  -- blocklisted, 20 retries]" -- NOT a settle-timing flake (a settle wait
  -- first didn't change the result). docs/design/thamasa-route.md's own
  -- line explains it: map 349 has an "interior stair pair (39,10)<->
  -- (61,20)" -- the night-talk scene lands the party UPSTAIRS (near
  -- (61,20)/(64,16)) and the exit trigger (37,25) is DOWNSTAIRS, near the
  -- town door landing (37,24). A flat bfsPath call spanning both floors
  -- can never find that route -- the stair is a warp tile, not a walkable
  -- connection (the exact same shape as map 351's own internal
  -- short_entrance warps this file already rides with houseWarp()).
  -- houseWarp() applies here unchanged: creep to the stair, land at its
  -- known downstairs destination.
  -- MEASURED (tenth pass, live, corrected): the first guess, SrcPos
  -- (61,20)->(39,10), landed the party AT (61,20) with no warp -- decoded
  -- ff6/src/field/trigger/short_entrance.dat directly (map 349's own
  -- three records start at $1662 per short_entrance.inc's _349): record 1
  -- is SrcPos (39,10) -> DestPos (61,20) (the UPSTAIRS direction, the
  -- reverse of what's wanted here) and record 2 is SrcPos (60,21) ->
  -- DestPos (38,11) -- the real downstairs trigger.
  houseWarp(60, 21, 38, 11, "stairs (60,21)->(38,11): upstairs to downstairs, Strago's house"),
  care("after the stairs down"),
  H.navTo(37, 25, { maxFrames = 6000, playBattles = "tactical", healer = TERRA,
    bank = 3, items = true, arrive = function() return map() ~= 349 end }),
  pressWalk("down", function() return map() ~= 349 end, 1800,
    "held DOWN through 349(37,25) -> Shadow's goodbye on 343(29,15)"),
  H.advanceStory(function()
    return map() == 343 and H.hasControl() and sw(0x0092) == 1
  end, 20000, { playBattles = "tactical" }),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 343, "back on the town map after Shadow's goodbye")
    H.assertEq(sw(0x0092), 1, "$0092 -- Shadow's goodbye played")
    if H._shadowWeapon ~= 0xFF and H._shadowWeaponBefore ~= nil then
      local now = H.invCountOf(H._shadowWeapon)
      H.assertEq(now, H._shadowWeaponBefore + 1, string.format(
        "SHADOW's weapon ($%02X) returned to the bag: %d -> %d",
        H._shadowWeapon, H._shadowWeaponBefore, now))
    else
      H.log("[ot6] SHADOW carried no measurable weapon at boot -- " ..
        "remove_equip's bag delta is NOT asserted, only logged")
    end
    H.log(string.format("[ot6] Shadow's goodbye done f%d (%d,%d)", H.frame,
      H.fieldX(), H.fieldY()))
    H.screenshot("thamasa_shadow_goodbye")
  end),

  -- ---- 8. out of town the way K->L measured it, and the world save ------
  care("before leaving town"),
  H.navTo(21, 47, { maxFrames = 20000, playBattles = "tactical", healer = TERRA,
    bank = 3, items = true }),
  pressWalk("down", function() return H.worldMode() end, 900,
    "held DOWN onto the south strip -> world (249,128)"),
  H.waitUntil(function()
    return H.worldMode() and H.worldHasControl() and H.worldAligned()
       and bright() >= 15
  end, 3600, "world control outside Thamasa", 5),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("[ot6] outside Thamasa: world (%d,%d) f%d",
      H.worldX(), H.worldY(), H.frame))
    H.screenshot("thamasa_fireout_world")
  end),
  H.fieldCare({ tag = "care before the M save", threshold = 0.9 }),
  H.call(function()
    H.assertPartyStanding("fire_out exit")
    H.assertEq(H.readByte(0x11FA) & 3, 0, "ON FOOT outside Thamasa")
    H.assertEq(partyOf(TERRA) ~= 0, true, "TERRA in party 1 at the M boundary")
    H.assertEq(partyOf(LOCKE) ~= 0, true, "LOCKE in party 1 at the M boundary")
    H.assertEq(partyOf(STRAGO) ~= 0, true, "STRAGO in party 1 at the M boundary")
    H.assertEq(partyOf(SHADOW), 0, "SHADOW not in the party at the M boundary")
  end),

  -- ---- 9. the world battery save -- checkpoint M -------------------------
  H.call(function()
    H.assertExitContractPreSave("fire-out-v1")
  end),
  H.saveState("fire_out.mss"),
  (function()
    local saveReq, loadReq
    return H.cond(function() return true end, {
      H.call(function() saveReq = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(saveReq, "generated-state verify: capture")
        loadReq = H.requestLoadState(saveReq.blob)
      end),
      H.waitFrames(2),
      H.call(function() H.checkReq(loadReq, "generated-state verify: reload") end),
      H.waitFrames(180),
      H.call(function()
        H.assertEq(H.worldMode(), true, "reload: on the world map")
        H.assertEq(H.readByte(0x11FA) & 3, 0, "reload: still ON FOOT")
        H.assertEq(H.worldHasControl() and H.worldAligned(), true,
          "reload: controllable at rest")
        H.assertEq(H.battleLoadStarted(), false, "reload: no battle pending")
        H.log("generated-state verify: the reload stayed calm -- fire_out verified")
      end),
    })
  end)(),
  (function() local calmN, ph = 0, 0
    return H.driveUntil(function()
      calmN = (H.readByte(0x59) ~= 0) and calmN + 1 or 0
      return calmN >= 30
    end, 1800, {
      H.call(function()
        ph = (ph + 1) % 48
        if H.readByte(0x59) ~= 0 then H.setPad({}); return end
        H.setPad(ph < 6 and { "x" } or {})
      end),
    }, "world menu open outside Thamasa")
  end)(),
  H.waitFrames(30),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == 0x05 end, 600,
    "main menu state", 5),
  H.call(function()
    H.assertEq((H.readByte(0x0201) & 0x80) ~= 0, true,
      "menu-flags $0201 bit7 SET -- the save-enable flow reached the menu")
    local entry = H.sym("CopyGameDataToSRAM")
    emu.addMemoryCallback(function()
      saveArg = emu.getState()["cpu.a"] & 0xff
    end, emu.callbackType.exec, entry, entry)
  end),
  H.driveUntil(function()
    return H.readByte(ZMENUSTATE) == 0x05 and H.readByte(0x4b) == 6
  end, 600, {
    H.pressButtons({ "up" }, 4), H.waitFrames(16),
  }, "main-menu cursor on Save"),
  H.pressButtons({ "a" }, 4),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == SAVE_SELECT end,
    600, "save-slot selection", 5),
  H.driveUntil(function()
    return H.readByte(ZMENUSTATE) == SAVE_SELECT and H.readByte(0x4b) == 2
  end, 600, {
    H.pressButtons({ "down" }, 4), H.waitFrames(16),
  }, "save cursor on slot 3"),
  H.driveUntil(function()
    return saveArg == 3
       and emu.read(0x307ff0, emu.memType.snesMemory) == 3
  end, 1800, {
    H.pressButtons({ "a" }, 4), H.waitFrames(20),
  }, "save confirmed -- CopyGameDataToSRAM ran for slot 3 (exec hook)"),
  H.waitFrames(120),
  H.call(function()
    H.assertEq(emu.read(0x307ff0, emu.memType.snesMemory), 3,
      "SRAM $307ff0 records slot 3")
    H.assertEq(saveArg, 3, "CopyGameDataToSRAM ran for persistent slot 3")
    H.assertExitContract("fire-out-v1")
    H.screenshot("thamasa_fireout_saved")
  end),
  H.logStep(function()
    return string.format("fire-out-v1 saved via the real Save UI at "
      .. "frame %d -- FlameEater beaten, Shadow's gear back in the bag; "
      .. "checkpoint M of v0.13", H.frame)
  end),
}

-- flatten nested step lists
local flat = {}
local function push(t)
  if type(t) == "table" and t[1] ~= nil and type(t[1]) == "table" then
    for _, s in ipairs(t) do push(s) end
  else
    flat[#flat + 1] = t
  end
end
for _, s in ipairs(steps) do push(s) end

-- allowGameOver=true: both the ambush and FlameEater below are seed
-- ladders explicitly built to survive a real loss (see the #127 GameOver
-- guard note above lossReload()) -- without this the lib's own canary
-- would abort the whole run the frame after either fight's first loss,
-- before the ladder ever got a chance to reload and retry.
-- MEASURED (this pass, live): 900000 was not enough headroom for the grind
-- alone -- 137 legs (~900000 frames) burned the whole budget without ever
-- leveling up once, because of the stale-checkpoint bug grindLeg's own
-- comment now documents (every wipe was reloading the ORIGINAL pre-grind
-- state, discarding all progress since the very first leg, not just that
-- one). With that fixed (grindBlob now refreshes after every successful
-- leg), a wipe only costs its own leg's frames, but the wipe rate itself
-- is real (roughly 1 in 2-3 legs against Baskervor even at 3 members), so
-- reaching 60 real fights can still cost several times as many total
-- frames as a wipe-free grind would. 3000000 gives real headroom for
-- that plus the rest of the route (ambush ladder, FlameEater, the win
-- tail) behind it.
H.run({ maxFrames = 3000000, allowGameOver = true }, flat)
