-- gen_whelk_poweron.lua -- reach the Whelk doorstep from COLD POWER-ON, fully
-- scripted, with NO save sidecar.  This is the SRM-free replacement for
-- gen_whelk.lua: same output (build/states/whelk_doorstep.mss, the field state
-- one tile SOUTH of the Whelk trigger at map 41 (42,5)), reached by playing the
-- opening from New Game instead of injecting a human play save into SRAM.  The
-- SRM path was a fresh-clone trap -- gen_whelk boots from
-- build/states/playthrough_srm.mss.lua, a git-ignored fixture minted from a
-- human save by make_srm_sidecar.sh, so a fresh checkout could not mint STATE3.
--
-- ROUTE (all New-Game, all automatic input; trigger tiles from
-- event_trigger.asm, scene bodies from event_main.asm, both verified):
--   power-on -> title Start-presses -> ~15.5k frames of automatic intro
--     march (the "1000 years have passed..." narration + Magitek credits walk)
--   -> blind UP+A masher (gen_battle_state's proven step) lands the
--     game-starting keypress, rides the cliff dialogs, and walks into the
--     first scripted guard fight -- frame 15500 is still MID-CREDITS and a
--     hands-off pad loops the attract forever (both measured, see Phase 2a)
--   -> map 19 (Narshe approach): scripted fights fire at the x=38 column
--     triggers {38,38} {38,26} {38,17} (event_trigger.asm map 19); blind
--     held-UP + kill-bit clears climbs y=38 -> 1 into map 39 (measured)
--   -> map 39 (Narshe town): blind-UP stalls at (26,42) (measured), so BFS
--     to (31,23), one south of the mines-approach trigger line {30..32,22}
--     (_cc9db2).  En route the {30,37} trigger (_cc9d0d) springs the 4-guard
--     ambush `battle 4`; navTo clears it.  Then blind-UP: the regroup scene
--     (dialog $0010, WEDGE/VICKS walk UP into the mine door and hide,
--     switch $012B=1) plays out, and the door north of (31,22) loads
--     map 41 at (38,33) facing up (load_map 41, event_main.asm:101393).
--   -> map 41 (Narshe mines): the security door at {41,5}x{3,4} boots CLOSED
--     (map-init draws wall tiles while switch $012C=0, _cc9ef2), so the
--     doorstep (42,6) is BFS-UNREACHABLE until the door-blast scene at
--     trigger {42,9} (_cc9e23) runs: choreography + dialog $0011, the BG mod
--     opens the x=42 column, TERRA ends force-marched to (42,8), and
--     switch $012C=1 marks it done.  So: navTo(42,9) with arrive=blastDone,
--     THEN navTo(42,6) -- two tiles, never touching (42,5).
--   -> assert the doorstep is calm and the whelk-done switch is CLEAR, mint
--     whelk_doorstep.mss, then (positive control) take the one deliberate
--     step onto the trigger and prove the Whelk fight comes up.
--
-- WHELK trigger, verbatim semantics from gen_whelk / the disassembly:
--   * map 41 event trigger {42,5} -> _cc9f37 (event_trigger.asm map 41,
--     event_main.asm:101417).  It force-walks the party down, shows dialogs
--     $0B6E ("We won't hand over the Esper!!") then $0B6F ("Whelk! Get them!"),
--     runs `battle 64` (event_main.asm:101431-101442), and on completion sets
--     `switch $0135=1` (event_main.asm:101449) -- the whelk-done switch, which
--     guards the trigger (`if_switch $0135=1, EventReturn`, event_main.asm
--     101418).  Event switch $0135 lives at $1E80 + ($135>>3) = $1EA6, bit
--     ($135&7)=5 -> mask $20 (event bitfield base $1E80, src/world/event.asm).
--   * during the fight the six formation species words at $57C0 read 0x0100
--     and 0x0134 (0x0134 is the distinctive one); both are spared so the
--     kill-bit clears never touch the goal fight.  $57C0 is battle scratch
--     (garbage before the first fight, stale after), so gate every read on
--     battleLoadStarted() -- see gen_whelk.lua:16-26 and ot6.lua:670-681.
--
-- Deterministic by construction, same as every harness run: AllZeros power-on
-- RAM + no frame skip + a pre-launch srm wipe (docs/playing-headless.md
-- "Runtime limits").  Because SRAM boots zeroed and empty, the title's Start
-- press goes straight to New Game with no save-select -- the same clean boot
-- gen_battle_state relies on (gen_battle_state.lua:6-10, README "Input
-- injection").
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")

-- goal-fight signature (verbatim, gen_whelk.lua:20-26): 0x0134 is the
-- distinctive Whelk species word; both it and 0x0100 are spared from the
-- kill-bit clears so the goal fight is never instakilled.
local WHELK = { [0x0134] = true }
local SPARE = { 0x0134, 0x0100 }
local function whelk()
  return H.battleLoadStarted() and H.formationHas(WHELK)
end

-- whelk-done event switch $0135 -> $1EA6 bit $20 (derivation above).  Once set
-- the trigger is inert, so the doorstep is worthless: assert it CLEAR at mint.
local function whelkDone() return (H.readByte(0x1ea6) & 0x20) ~= 0 end

-- door-blast event switch $012C -> $1E80 + ($12C>>3) = $1EA5, bit ($12C&7)=4
-- -> mask $10.  Set at the end of the {42,9} blast scene (_cc9e23); the
-- security door tiles are open once it is.
local function blastDone() return (H.readByte(0x1ea5) & 0x10) ~= 0 end

-- Log the formation words on every fight's rising edge, whichever phase or
-- navigator is driving at the time (the risk list wants every forced fight
-- named).  Registered OUTSIDE the step machine so navTo's fights get named
-- too; 3-frame debounce like navTo's ($57C0 is scratch the field module also
-- scribbles on).  Read-only -- the step machine still owns the pad.
local fightN = 0
emu.addEventCallback(function()
  fightN = H.battleLoadStarted() and fightN + 1 or 0
  if fightN == 3 then
    local w = H.formationWords()
    H.log(string.format("fight up f%d map=%d (%04X %04X %04X %04X %04X %04X)",
      H.frame, H.mapId(), w[1], w[2], w[3], w[4], w[5], w[6]))
  end
end, emu.eventType.startFrame)

-- shared edge-press phase for A taps (4 on / 4 off): dialog/victory-text
-- advancing is EDGE-triggered, so a continuous hold yields exactly one page
-- (docs/playing-headless.md; ot6.lua clearBattle/advanceStory use the same).
local aPhase = 0

-- clear the current random encounter in place: kill-bit every present monster
-- (present bit $3aa8 bit0 -> dead bit $3eec bit7) and edge-tap A through the
-- victory text.  This is the ot6.lua kill-bit idiom (clearBattle, ot6.lua
-- 692-716; navTo's inline clear, 905-920) lifted out so both the climb and the
-- post-mint positive control use it identically.  NEVER call it on the whelk:
-- callers gate on `whelk()` first and hand off instead.
local function clearRandomStep()
  if H.monstersPresent() > 0 then
    for slot = 0, 5 do
      if H.readByte(0x3aa8 + slot * 2) % 2 == 1 then
        H.writeByte(0x3eec + slot * 2, H.readByte(0x3eec + slot * 2) | 0x80)
      end
    end
  end
  H.setPad(aPhase < 4 and { "a" } or {})
end

-- climb instrumentation: northmost tile reached and a stall counter, so a
-- headless run leaves a breadcrumb trail of where blind-UP took us and (if it
-- jams) exactly which tile to teach.  bestY starts high so the first aligned
-- sample always adopts it, and is PER-MAP (a Y from one map is meaningless on
-- the next -- entry Y is arbitrary), so the tracker resets on map change.
local bestY, stall, climbHb = 0xFFFF, 0, -600
local battN, dlgN = 0, 0  -- 3-frame debounce (the navTo/advanceStory idiom)
local climbMap = -1
-- STALL_LIMIT counts CONSECUTIVE tile-aligned, in-control frames with no
-- northward progress.  A moving party is only momentarily aligned at each tile
-- boundary (at a fresh, lower Y), so a healthy climb never accrues; a party
-- jammed against a wall (or stopped at a corridor turn blind-UP can't round)
-- is aligned every frame at a fixed Y and trips this in a few seconds.  240
-- frames (~4 s) is well past any legitimate pause.  Map 19's corridor is
-- measured UP-navigable; map 39's is not (that leg is BFS'd) -- if the route
-- shifts, this errors AT the stuck tile with the map/coords to fix.
local STALL_LIMIT = 240

-- The blind-northward climb body, shared by phases 2b and 2d.  Each call
-- builds a fresh zero-frame step; state (aPhase, debounces, stall tracker)
-- lives in the shared upvalues above.  Frames are classified with the
-- navTo/advanceStory 3-frame debounce (the battle/dialog signal bytes live in
-- RAM the field module also scribbles on; kill-bitting a 1-frame ghost would
-- poke battle addresses while the FIELD module owns them):
--   battle -> kill-bit + edge-tap A (never the whelk); dialog -> edge-tap A;
--   other control loss (scenes walking the party, fades) -> neutral pad;
--   control -> stall-watch, then hold UP.
local function climbStep()
  return H.call(function()
    aPhase = (aPhase + 1) % 8
    if H.frame - climbHb >= 600 then
      climbHb = H.frame
      H.log(string.format("climb f%d map=%d (%d,%d) ctl=%s algn=%s dlg=%s batt=%s",
        H.frame, H.mapId(), H.fieldX(), H.fieldY(),
        tostring(H.hasControl()), tostring(H.tileAligned()),
        tostring(H.dialogWaiting()), tostring(H.battleLoadStarted())))
    end

    battN = H.battleLoadStarted() and battN + 1 or 0
    dlgN  = H.dialogWaiting() and dlgN + 1 or 0

    -- battle: clear randoms/forced fights.  The whelk cannot appear on the
    -- climb legs (it lives past the map-41 door), but gate defensively anyway
    -- so a surprise never gets kill-bitted.
    if battN >= 3 then
      if whelk() then H.setPad({}); return end
      clearRandomStep()
      return
    end
    -- dialog waiting for a keypress: edge-tap A.
    if dlgN >= 3 then
      H.setPad(aPhase < 4 and { "a" } or {})
      return
    end
    -- a cutscene walking the party (fades, forced marches) or a still-
    -- undebounced battle/dialog flicker: hands off.
    if battN > 0 or dlgN > 0 or not H.hasControl() then H.setPad({}); return end

    -- in control: stall-watch on valid (tile-aligned) position samples, then
    -- hold UP.  (We hold through the unaligned frames too -- a continuous
    -- climb, not step-verified -- because these legs only need "keep going
    -- north"; BFS owns every precise part.)
    if H.tileAligned() then
      if H.mapId() ~= climbMap then
        climbMap = H.mapId()
        bestY, stall = 0xFFFF, 0
      end
      local y = H.fieldY()
      if y < bestY then
        bestY = y; stall = 0
      else
        stall = stall + 1
        if stall > STALL_LIMIT then
          error(string.format(
            "climb stalled at map %d (%d,%d) after %d aligned frames: blind-UP " ..
            "cannot advance here (a corridor turn or wall).  Teach this leg an " ..
            "H.navTo target -- see the route map in the header.",
            H.mapId(), H.fieldX(), H.fieldY(), stall), 0)
        end
      end
    end
    H.setPad({ up = true })
  end)
end

-- ------------------------------------------------------- the mint's proof --
-- The captured doorstep, held in memory until the sweep clears it.  Emitting
-- only after validation means a run that fails leaves NO whelk_doorstep.mss
-- behind to be mistaken for a good one.
local mintReq, doorstep = nil, nil

-- The single deliberate step onto the trigger (verbatim from gen_whelk.lua
-- :74-99): the event force-walks the party down and opens the edge-triggered
-- dialogs $0B6E/$0B6F; a random encounter on the way is cleared like any
-- other.  A fresh step object per call -- H.driveUntil bodies are stateful.
local function stepOntoTrigger()
  return H.call(function()
    aPhase = (aPhase + 1) % 8
    if H.battleLoadStarted() then
      if whelk() then H.setPad({}); return end     -- pred fires next frame
      clearRandomStep()
      return
    end
    if H.dialogWaiting() then                       -- $0B6E then $0B6F
      H.setPad(aPhase < 4 and { "a" } or {})
      return
    end
    if not H.hasControl() then H.setPad({}); return end  -- event walking us
    if not H.tileAligned() then H.setPad({}); return end -- glide out steps
    -- at rest with control: step toward the trigger (down = re-approach if
    -- we somehow stand on/above an unfired trigger)
    H.setPad(H.fieldY() <= 5 and { down = true } or { up = true })
  end)
end

-- DID A COMMAND LIST ACTUALLY DRAW?  Every battle list-text template writes
-- vanilla's staging buffer at $7e5755 (`ram_res w7e5755, 128`,
-- btlgfx/btlgfx_ram.inc:71) -- the item family fills $5755-$5767, magic
-- $5755-$5764, magitek $5755-$5761 (`cpx #$000d`, madou_line_mess_set).  The
-- shortest of the three still covers this window, so watching it detects a
-- list of ANY command without repointing anybody's commands first.
--
-- Keyed on the BUFFER, never on a drawer's instruction address.  This ROM's
-- bank C1 sits 11 bytes below ff6/notes/ff3u.asm (DrawMagicListText is at
-- C1/4DC0 per ff6/rom/ff6-en.map:539, not the notes' C1/4DB5), which is how
-- probe_shadow_overlap ended up with an exec watch on an operand byte that
-- could never fire.  Vanilla's RAM reservations do not move; its code does.
--
-- Measured quiet: this window takes ZERO writes while the battle sits
-- settled and zero at the command level, then 60 from bank C1 the moment a
-- list opens.  So a nonzero count is a list, not hud chatter.
local listWrites = 0
emu.addMemoryCallback(function()
  local ok, bank = pcall(function() return emu.getState()["cpu.k"] end)
  if ok and bank ~= 0xF0 then listWrites = listWrites + 1 end
end, emu.callbackType.write, 0x7E5755, 0x7E5761)

-- WHY A SWEEP AND NOT A SEARCH, and why the settle above is arbitrary now.
--
-- Battle init seeds the RNG index from the game-time frame counter --
-- `lda $021e / asl2 / sta $be` (battle_main.asm:6092-6094) -- and $021E
-- ticks once per frame, wrapping at 60 (time_calc, C3/13C8-C3/1410).  So the
-- doorstep's frame phase picks one of sixty battle seeds, InitGauge draws
-- the starting ATB gauges off it (battle_main.asm:6230+), and that decides
-- whose menu opens first.  That much the old comment here had right.
--
-- What it had wrong is that the mint can steer it.  It cannot: the seed is
-- set at BATTLE init, not at the doorstep, so every consumer adds its own
-- walk length to the mint's phase before the roll happens.  Measured, all
-- three consumers on one identical fixture (sha 84209ed55945):
--   probe_shadow_overlap  264 frames doorstep -> fight
--   battle_whelkwipe      266
--   battle_dlgmenu        267
-- Three walks, three residues of $021E, three different seeds.  One knob
-- here cannot set three rolls, so "advance a frame and re-check" would only
-- move the coin flip around -- it would satisfy whichever consumer the mint
-- happened to imitate and re-roll the other two.
--
-- The useful thing the mint CAN do is prove the fixture does not depend on
-- the roll at all.  So: replay the doorstep at four spread phases, and
-- require of each that the Whelk fight comes up, a battle command menu
-- opens, and a command list actually draws.  Four seeds is not sixty --
-- this is a roll-dependence detector, not a proof over the whole seed space
-- -- but it is the difference between a fixture that happened to work once
-- and one that has been shown to work across rolls.  A phase that fails is
-- the real defect and must be fixed in the consumer's drive, NOT by
-- retuning the settle above.
local SWEEP = { 0, 7, 23, 41 }

local steps = {
  -- ===================================================================== --
  -- Phase 1: power-on -> title -> automatic intro march.
  -- Reused VERBATIM from gen_battle_state.lua:26-34 (the only existing
  -- power-on play): the srm inject is simply dropped -- New Game on empty
  -- SRAM needs nothing injected.
  -- ===================================================================== --
  H.waitFrames(355),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.logStep("title handled; riding out the opening march (this takes a while)..."),
  H.waitUntil(function() return H.frame >= 15500 end, 16000, "intro march to finish"),
  H.call(function() H.screenshot("poweron_cliff") end),

  -- ===================================================================== --
  -- Phase 2a: frame 15500 is still MID-CREDITS (measured: poweron_cliff.png
  -- shows the "MAIN PROGRAMMER" snow walk, byte-identical to the passing
  -- mint's gen_cliff.png), and a hands-off pad from here leaves the game in
  -- the attract loop FOREVER (measured: the map/position signature repeats
  -- with an ~11k-frame period -- the real game never starts).  The blind
  -- UP-hold + A-press masher is what lands the game-starting keypress and
  -- rides the cliff dialogs into the first scripted guard fight, so reuse it
  -- VERBATIM from gen_battle_state.lua:38-53 (minus the rolling-savestate
  -- machinery), with its exact proven terminator: battleLoadStarted().
  -- ===================================================================== --
  H.driveUntil(function() return H.battleLoadStarted() end, 15000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "first battle load"),
  H.logStep(function()
    return string.format("first forced fight loading at frame %d", H.frame)
  end),

  -- ===================================================================== --
  -- Phase 2b: clear the map-19 gauntlet.  From the first fight on, the world
  -- is the real game: the climb body kill-bits the x=38-column scripted
  -- fights ({38,38} {38,26} {38,17}, all measured clearing fine) and holds
  -- UP the cliff corridor (measured UP-navigable, y=38 -> 1) until the town
  -- map loads.
  -- ===================================================================== --
  H.driveUntil(function() return H.mapId() == 39 end, 22000,
    { climbStep() }, "reach Narshe town (map 39)"),
  H.logStep(function()
    return string.format("entered town (map 39) at (%d,%d), frame %d",
      H.fieldX(), H.fieldY(), H.frame)
  end),

  -- The map is NOT final at the first frame control reads true on a freshly
  -- loaded map: the fade-in is still running, the $7F0000 tilemap settles
  -- during it, and held input is ignored for ~50 more frames (all measured --
  -- an entry-instant BFS here saw a different, sealed geometry and found no
  -- path; the identical BFS later found the 26-step street route).  So wait
  -- for control, then full screen brightness, then a margin, before ANY
  -- planning on this map.
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 900,
    "control in town", 4),
  H.waitUntil(function()
    return (emu.getState()["ppu.screenBrightness"] or 0) >= 15
  end, 900, "town fade-in", 10),
  H.waitFrames(30),

  -- ===================================================================== --
  -- Phase 2c: cross town by BFS.  Blind-UP stalls at (26,42) (measured, run
  -- 2), so navigate to (31,23) -- one tile SOUTH of the mines-approach
  -- trigger line {30..32,22} (_cc9db2), so the scene fires on OUR deliberate
  -- step in 2d, not mid-plan.  The {30,37} ambush (`battle 4`, _cc9d0d,
  -- self-gating on $0131) springs en route if BFS crosses it; navTo clears
  -- it like any fight.
  -- ===================================================================== --
  H.navTo(31, 23, { maxFrames = 9000 }),
  H.logStep(function()
    return string.format("at the mines approach (31,23), frame %d", H.frame)
  end),

  -- ===================================================================== --
  -- Phase 2d: step onto the trigger line and ride the regroup scene (dialog
  -- $0010 edge-tapped; WEDGE/VICKS walk up into the mine door and hide;
  -- $012B=1), then keep holding UP through the door north of (31,22): the
  -- gated door event (`if_switch $012C=1, EventReturn; load_map 41,
  -- {38,33}, UP, STARTUP_EVENT`, event_main.asm:101391-101393) loads the
  -- mines -- $012C is still clear on this first approach.
  -- ===================================================================== --
  H.driveUntil(function() return H.mapId() == 41 end, 8000,
    { climbStep() }, "reach the Narshe mines (map 41)"),
  H.logStep(function()
    return string.format("entered map 41 at (%d,%d), frame %d",
      H.fieldX(), H.fieldY(), H.frame)
  end),

  -- same fresh-map settling wait as the town entry (see above): control,
  -- then full brightness, then margin, before BFS planning on map 41.  The
  -- startup event (magitek re-mount, _cc9ef2) runs inside this window; the
  -- control wait rides it out too.
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 900,
    "control in the mines", 4),
  H.waitUntil(function()
    return (emu.getState()["ppu.screenBrightness"] or 0) >= 15
  end, 900, "mines fade-in", 10),
  H.waitFrames(30),

  -- ===================================================================== --
  -- Phase 3a: the security door boots CLOSED (map-init draws wall tiles over
  -- {41,5}x{3,4} while $012C=0), so (42,6) is unreachable to BFS until the
  -- blast scene runs.  Navigate to its trigger {42,9}: stepping on fires
  -- _cc9e23 (choreography, dialog $0011 edge-tapped by navTo, the BG mod
  -- that opens the x=42 door column, TERRA force-marched to (42,8), then
  -- $012C=1).  arrive=blastDone so the walk ends the moment the switch
  -- lands, wherever the scene parked us.  The map-41 startup event re-mounts
  -- the Magitek armor first (map_init_event.asm $0029 -> _cc9ef2); navTo
  -- waits out that control loss on its own.  whelk() is checked too, pure
  -- paranoia: BFS south of the closed door cannot reach (42,5).
  -- ===================================================================== --
  H.navTo(42, 9, {
    arrive = function() return blastDone() or whelk() end,
    maxFrames = 12000, spare = SPARE,
  }),
  -- navTo can complete in the 1-frame window between landing on (42,9) and
  -- the event engine starting the scene (measured: run 4 arrived in exactly
  -- the walk time, then planned against the still-closed door and died with
  -- "no path").  So ride the scene explicitly: advanceStory taps its dialog
  -- ($0011), stays hands-off through the choreography, and returns the
  -- moment switch $012C lands.  Instant no-op if the scene already ran.
  H.advanceStory(function() return blastDone() end, 4000, { spare = SPARE }),
  H.logStep(function()
    return string.format("door blasted (switch $012C set); at (%d,%d), frame %d",
      H.fieldX(), H.fieldY(), H.frame)
  end),

  -- ===================================================================== --
  -- Phase 3b: BFS to the doorstep tile (42,6), one south of the trigger --
  -- from (42,8) that is two steps up the now-open door column, never
  -- touching (42,5).  Identical contract to gen_whelk.lua:54.
  -- ===================================================================== --
  H.navTo(42, 6, { arrive = whelk, maxFrames = 4000, spare = SPARE }),

  -- ===================================================================== --
  -- Phase 4: assert + mint + prove.  Mirrors gen_whelk.lua:56-112 so the two
  -- generators emit interchangeable states (downstream tests are documented
  -- mint-independent: battle_dlgmenu / battle_whelkwipe / probe_shadow_overlap
  -- each load whelk_doorstep.mss and drive it onto the trigger themselves).
  -- ===================================================================== --
  H.cond(function() return whelk() end, {
    -- shouldn't happen (BFS from the south never crosses (42,5)); if the event
    -- somehow fired en route the fight IS the goal -- just no doorstep this run
    H.logStep("whelk fired en route; NO doorstep state minted this run"),
  }, {
    H.call(function()
      H.assertEq(H.mapId(), 41, "on the Narshe mines map (41)")
      H.assertEq(H.fieldX() == 42 and H.fieldY() == 6, true,
        "at the whelk doorstep (42,6)")
      H.assertEq(H.hasControl() and H.tileAligned(), true,
        "doorstep is calm (user control, at rest, no battle)")
      H.assertEq(whelkDone(), false,
        "whelk-done switch $1EA6 bit $20 is CLEAR (trigger still live)")
    end),
    -- A short settle before the capture.  THE NUMBER IS ARBITRARY, and the
    -- sweep below is what makes that safe to say -- see its block comment.
    H.waitFrames(14),
    H.call(function() mintReq = H.requestSaveState() end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(mintReq, "doorstep savestate capture")
      doorstep = mintReq.blob
      H.log(string.format("doorstep captured at (42,6), frame %d (%d bytes) " ..
        "-- NOT emitted until the sweep below passes", H.frame, #doorstep))
    end),
  }),
}

-- ===================================================================== --
-- Phase 5: THE SWEEP.  Replay the captured doorstep at each phase and
-- require a usable fight of every one.  This is also the mint's positive
-- control -- it takes the same deliberate step onto (42,5) the old
-- single-shot control did, four times, and asks more of each.
-- ===================================================================== --
local seen = {}
for _, k in ipairs(SWEEP) do
  local tag = string.format("sweep +%d", k)
  local shot = {}
  local loadReq
  local phaseSteps = {
    H.call(function() loadReq = H.requestLoadState(doorstep) end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(loadReq, tag .. ": doorstep reload")
      -- same two writes H.loadState makes: savestates do not restore battery
      -- sram, so invalidate the weakness codex the way every consumer does
      emu.write(0x316000, 0, emu.memType.snesMemory)
      emu.write(0x316001, 0, emu.memType.snesMemory)
      listWrites = 0
    end),
    H.waitFrames(k),        -- the phase itself: k more ticks of $021E
    H.call(function()
      shot.t0 = H.readByte(0x021e)
      H.assertEq(H.fieldX() == 42 and H.fieldY() == 6, true,
        tag .. ": reloaded state is the doorstep (42,6)")
    end),
    H.driveUntil(function() return whelk() end, 2200,
      { stepOntoTrigger() }, tag .. ": whelk event fires"),
    H.call(function() H.setPad({}) end),
    H.waitUntil(function() return H.battleActive() end, 900,
      tag .. ": whelk up", 30),
    H.waitFrames(240),
    -- a battle command menu must open: every consumer's first drive in this
    -- fight waits on exactly this byte
    H.driveUntil(function() return H.readByte(0x7bca) ~= 0 end, 4000, {
      H.call(function()
        local n = (H.vars.mn or 0) + 1 ; H.vars.mn = n
        H.setPad(n % 60 < 4 and { "a" } or {})
      end),
    }, tag .. ": a battle command menu opens"),
    H.call(function()
      H.setPad({})
      shot.actor = H.readByte(0x62ca) & 3
      shot.charid = H.readByte(0x3ed8 + shot.actor * 2)
      listWrites = 0        -- only count what the presses below cause
    end),
    H.waitFrames(120),
    -- ...and a command list must draw from it.  No command surgery: everyone
    -- in this fight rides magitek armor, so A on the top command opens the
    -- magitek list whoever the roll picked.
    H.driveUntil(function() return listWrites > 0 end, 1200, {
      H.pressButtons({ "a" }, 4), H.waitFrames(90),
      H.pressButtons({ "b" }, 4), H.waitFrames(45),
      H.pressButtons({ "down" }, 4), H.waitFrames(30),
    }, tag .. ": a command list draws"),
    H.call(function()
      H.assertEq(listWrites > 0, true, tag .. ": command list really drew")
      seen[#seen + 1] = string.format("%s: $021e=$%02x -> menu slot %d char $%02x, "
        .. "%d list writes", tag, shot.t0 or 0, shot.actor, shot.charid, listWrites)
      H.log(seen[#seen])
    end),
  }
  for _, s in ipairs(phaseSteps) do steps[#steps + 1] = s end
end

steps[#steps + 1] = H.call(function()
  H.log("---- doorstep proved usable at every swept phase ----")
  for _, line in ipairs(seen) do H.log("  " .. line) end
end)

-- the last sweep phase left us in the fight; prove it's the Whelk
-- (gen_whelk.lua:103-112).
steps[#steps + 1] = H.call(function() H.setPad({}) end)
steps[#steps + 1] =
  H.waitUntilSoft(function() return H.battleActive() end, 900, "whelk_up", 30)
steps[#steps + 1] = H.call(function()
  H.assertEq(whelk(), true, "Whelk formation words present at $57C0")
  local w = H.formationWords()
  H.log(string.format("formation: %04X %04X %04X %04X %04X %04X (screen up=%s)",
    w[1], w[2], w[3], w[4], w[5], w[6], tostring(H.vars.whelk_up)))
  H.screenshot("poweron_whelk_battle")
  H.log(string.format("WHELK battle at frame %d (power-on route)", H.frame))
end)

-- EMIT LAST, after every assertion above has held.  A failed run leaves no
-- whelk_doorstep.mss at all rather than an unvalidated one.
steps[#steps + 1] = H.call(function()
  H.emitBlob("whelk_doorstep.mss", doorstep)
  H.log("doorstep minted")
end)

H.run({ maxFrames = 60000 }, steps)
