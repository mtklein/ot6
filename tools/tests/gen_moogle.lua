-- gen_moogle.lua -- from moogle_doorstep.mss (TERRA in Magitek armor at
-- (55,12), map 50, one south of the collapse trigger): step onto (55,11)
-- and ride the WHOLE opening set-piece chain to its far side, generating two
-- states on the way:
--
--   moogle_defense.mss  -- the three-party Moogle defense, first player-
--                          controlled frame (map 51, party 1 = LOCKE+3
--                          moogles at (14,14), Marshal waiting at (15,40))
--   moogle_cleared.mss  -- the far side: LOCKE leads TERRA on the Narshe
--                          streets (map 20), defense won, control returned
--
-- SEQUENCE (all one event, _cca2e5, event_trigger.asm map 50 {55,11},
-- body event_main.asm:102027-103283):
--   * bridge collapse choreography; TERRA falls (map 51 mosaic scene)
--   * Kefka slave-crown flashback (map 250), then the scripted Magitek
--     flashback fight `battle 115` (map 5, event_main.asm:102351) --
--     plain soldiers, won with real input by tap-A (TERRA's beams one-shot
--     them, the same arithmetic as the intro gauntlet)
--   * Gestahl rally (map 244), TERRA wakes in the caves (map 51)
--   * Arvis recruits LOCKE (map 30): dialogs, then `name_menu LOCKE`
--     (event_main.asm:102678) -- the ONE beat advanceStory cannot tap
--     ($0059 flips as the menu opens; START commits the default name,
--     same split as gen_narshe_escape.lua:47-52)
--   * moogle cave scenes; choice dialog $0036 (A picks "Yes", the extra
--     info page $0037 is harmless); 11 moogles join LOCKE across three
--     parties (event_main.asm:103137-103207)
--   * defense setup: switches $0631=1 $060A..$0610=1 $012E=1 $0003=1,
--     map 51 loads with STARTUP_EVENT (its map-init _ccab6f starts the
--     six guard marches), fade in, player_ctrl_on (:103280-103283)
--
-- THE DEFENSE, PLAYED THE WAY IT WAS DESIGNED (issue #75, the input-driven
-- test conversion; every number below measured by probe_moogle_geom /
-- _switch / _rotation / _stations / _marshal on a fresh fixture):
--   * guards NPC_4..NPC_9 spawn at (15,34)..(15,39) (npc_prop.asm map
--     51) and march scripted paths (map-init _ccab6f) that converge on
--     the single-file tail (15,17)->(15,16)->(14,16)->(14,15)->(14,14)
--     ->(14,13); a guard COMPLETING the tail execs _cccb82 = GAME OVER
--     (event_main.asm:108640), so the choke (14,14) stays manned
--   * the marches split by arm: NPC_4/NPC_9 climb the EAST loop through
--     (20,19..23), NPC_7/NPC_8 the WEST loop through (10,19..23),
--     NPC_5/NPC_6 the middle column (15,16..23).  Wave 1 needs ~2100
--     field-frames to reach anything, so there is time to deploy:
--     P3 -> (20,20) east (passed ~f1400), P2 -> (10,21) west (~f1800),
--     P1 keeps the choke.  (15,15) and the mound tiles are off-path.
--   * touching a marching guard fires `battle 5, DEFAULT, COLLISION`
--     (npc events _ccaadf.._ccab57): Vomammoth + Lobo, and the battle
--     AUTO-ENGAGES THE COLLIDED PARTY (measured: a parked, inactive
--     squad fought with its own exact HP table).  So once deployed, the
--     storm needs no choreography: hands off, tap-A each fight, two
--     waves per squad (~90-190 HP each), win path despawns the guard
--     ($060A..$060F=0).  Mid-defense goalie swaps do NOT work: waves
--     1-3 queue nose-to-tail and the aside walk eats wave 3's collision
--     (probe_moogle_rotation measured exactly that).
--   * the Marshal (NPC_3) stands at (15,40) facing UP, npc event
--     _ccada8 -> `battle 6` = Marshal (420 HP) + 2 Lobos.  Plain tap-A
--     LOSES this fight from a two-wave-worn pool (~330/543, measured
--     twice); the winning input-driven tactic is OT6's own boost -- R raises
--     the active character's pending boost (1 bp at battle start,
--     Ot6InitBP), A-A-A confirms the boosted Fight -- which won with
--     MOG alone standing at 89 HP (probe_moogle_marshal).  The margin
--     is thin, so a LOSS is handled the way a player handles it: the
--     loss path _ccada8->_ccaaba revives the squad at 1 HP on (14,11)
--     (NOT game over -- battle 6 and battle 5 both continue on defeat),
--     and the next squad walks in and pokes him again: P2 (MOG, 543
--     pool), then P1 (LOCKE, ~281 left), then P3 (~149 left).
--   * a lost battle parks on the "Annihilated" screen until a keypress
--     (the battle-HP table zeroes, which battleLoadStarted reads as
--     no-battle -- the pilot's 38k-frame "softlock" was this screen
--     unattended), so every post-fight settle keeps tapping A.
--   * winning battle 6 runs _ccadbf: guards despawn, switch $0631=0
--     (the defense-won marker, :103782 -- its ONLY clear), "Thanks,
--     Moogles!", the mine switch scene, TERRA's amnesia dialogs, the
--     secret-entrance reveal on map 20, force-walk DOWN 2 + RIGHT 23
--     from {15,56}, then max_hp/and_status on TERRA+LOCKE+MOG,
--     player_ctrl_on, $01CC=1 (:103769-104188).  First calm control:
--     map 20, LOCKE + TERRA.
--
-- Issue #75: every battle in this unit is PLAYED -- zero state writes.
-- Battle 115 is beam one-shots, the six waves are won by whichever
-- squad each march collides with, and the Marshal falls to boosted
-- Fights; beating him IS winning battle 6, so unlike gen_arvis there is
-- NO spare list anywhere; the fight logger below still names every
-- formation for the record.  input-driven fights cost real ATB rounds, so
-- every budget in this file grew against its battle-clear-write ancestor.
--
-- Switch -> RAM derivations (event bitfield base $1E80, bit = switch&7):
--   $012E -> $1EA5 mask $40      $0631 -> $1F46 mask $02
--   $0609..$060F -> $1F41 masks $02,$04..$80    $0610 -> $1F42 mask $01
--   $012F -> $1EA5 mask $80      $01CC -> $1EB9 mask $10
--   $0003 -> $1E80 mask $08
local H = dofile("tools/tests/lib/ot6.lua")
local DOORSTEP = "build/states/moogle_doorstep.mss.lua"

local function collapseStarted()        -- $012E: set as the defense goes live
  return (H.readByte(0x1ea5) & 0x40) ~= 0
end
local function defenseWon()             -- $0631 cleared ONLY by the win path
  return (H.readByte(0x1f46) & 0x02) == 0
end

-- n consecutive calm frames (control, at rest), optionally an extra pred
local function calm(n, extra)
  local cnt = 0
  return function()
    local ok = H.hasControl() and H.tileAligned() and (not extra or extra())
    cnt = ok and cnt + 1 or 0
    return cnt >= n
  end
end

local function eventFor(n)
  local cnt = 0
  return function()
    cnt = H.eventRunning() and cnt + 1 or 0
    return cnt >= n
  end
end

-- name every fight once on its 3rd consecutive loading frame, with the
-- party number that is fighting it (collision battles auto-engage the
-- collided squad; $1A6D says which).  Registered outside the step
-- machine so whichever phase is driving, the formation gets logged;
-- read-only.
local fightN = 0
emu.addEventCallback(function()
  fightN = H.battleLoadStarted() and fightN + 1 or 0
  if fightN == 3 then
    local w = H.formationWords()
    H.log(string.format("fight up f%d map=%d party=%d (%04X %04X %04X %04X %04X %04X)",
      H.frame, H.mapId(), H.readByte(0x1a6d), w[1], w[2], w[3], w[4], w[5], w[6]))
  end
end, emu.eventType.startFrame)

local aPhase = 0

-- ---------------------------------------------------------- the squads --
-- rosters as character ids (char block $1600 + 37*c: +$09 cur HP, +$0B
-- max), and each squad leader's object offset ($0803 after a Y-switch):
-- P1 = LOCKE(1) KUPEK(2) KUPOP(3) KUMAMA(4), leader obj 1
-- P2 = MOG(10) KUKU(5) KUTAN(6) KUPAN(7),    leader obj 10
-- P3 = KUSHU(8) KURIN(9) KURU(11) KAMOG(12), leader obj 8
local PARTY = { [1] = { 1, 2, 3, 4 }, [2] = { 10, 5, 6, 7 },
                [3] = { 8, 9, 11, 12 } }
local LEADER_OFF = { [1] = 0x0029, [2] = 0x019A, [3] = 0x0148 }

local function poolOf(p)
  local cur = 0
  for _, c in ipairs(PARTY[p]) do cur = cur + H.readWord(0x1609 + 37 * c) end
  return cur
end

local function logPools(tag)
  return H.logStep(function()
    return string.format("%s f%d pools P1=%d P2=%d P3=%d $1F41=%02X", tag,
      H.frame, poolOf(1), poolOf(2), poolOf(3), H.readByte(0x1f41))
  end)
end

-- tap Y until the leader offset says squad p is active.  CheckChangeParty
-- (field/obj.asm:3207) needs Y seen UP then DOWN, control, alignment; the
-- press-release cycle below satisfies the latch, and a press eaten by the
-- switch fade just gets retried.
local function ySwitchTo(p)
  return H.driveUntil(function()
    return H.readWord(0x0803) == LEADER_OFF[p]
  end, 1800, {
    H.pressButtons({ "y" }, 6),
    H.waitFrames(40),
  }, "Y-switch to party " .. p)
end

-- the Marshal's post: npc_prop.asm map 51 NPC_3, {15,40}, static
local MX, MY = 15, 40

local function marshalAdjacent()
  local dx, dy = MX - H.fieldX(), MY - H.fieldY()
  return math.abs(dx) + math.abs(dy) == 1
end

-- one activation attempt: while adjacent, cycle 2 frames facing-press /
-- 4 frames A / 2 neutral until a battle actually loads (3-frame debounce
-- on monsters-present: the load signal lives in field-scribbled RAM) or
-- the defense is already won.  `round` only names the log line.
local function pokeStep(round)
  local battN = 0
  return H.driveUntil(function()
    battN = (H.battleLoadStarted() and H.monstersPresent() > 0)
        and battN + 1 or 0
    return defenseWon() or battN >= 3
  end, 900, {
    H.call(function()
      aPhase = (aPhase + 1) % 8
      if not (H.hasControl() and marshalAdjacent()) then H.setPad({}); return end
      local dx, dy = MX - H.fieldX(), MY - H.fieldY()
      local dir = dx == 1 and "right" or dx == -1 and "left"
               or dy == 1 and "down" or "up"
      if aPhase < 2 then H.setPad({ [dir] = true })
      elseif aPhase < 6 then H.setPad({ "a" })
      else H.setPad({}) end
    end),
  }, "battle 6 engages [attempt " .. round .. "]")
end

-- the input-driven battle-6 driver: R raises the active character's pending
-- boost (characters open with 1 bp, regen 1 per unboosted turn --
-- Ot6InitBP/Ot6ActionEnd), then three edge-tapped A's confirm the
-- boosted Fight and page victory text.  Once the battle module reads
-- gone (a WIN's teardown -- or a WIPE, which zeroes the HP table), keep
-- tapping A: a loss parks on the Annihilated screen until a keypress.
-- Ends on the won-switch or on 240 settled no-battle frames.
local function marshalFight(maxFrames)
  local phase, calmN = 0, 0
  return H.driveUntil(function()
    calmN = (not H.battleLoadStarted()) and calmN + 1 or 0
    return defenseWon() or calmN >= 240
  end, maxFrames, {
    H.call(function()
      phase = (phase + 1) % 32
      if not H.battleLoadStarted() then
        H.setPad(phase % 8 < 4 and { "a" } or {})
        return
      end
      if phase < 4 then H.setPad({ "r" })
      elseif phase < 6 then H.setPad({})
      elseif phase < 10 then H.setPad({ "a" })
      elseif phase < 12 then H.setPad({})
      elseif phase < 16 then H.setPad({ "a" })
      elseif phase < 18 then H.setPad({})
      elseif phase < 22 then H.setPad({ "a" })
      else H.setPad({}) end
    end),
  }, "Marshal fight (boosted Fights)")
end

-- post-attempt settle: on a WIN $0631 clears early in _ccadbf; on a LOSS
-- the squad is revived at 1 HP on (14,11) and control returns.  A-taps
-- ride the Annihilated screen and any dialog either way.
local function settleStep()
  local dlgN = 0
  return H.driveUntil(function()
    return defenseWon() or (H.hasControl() and H.tileAligned())
  end, 2400, {
    H.call(function()
      aPhase = (aPhase + 1) % 8
      dlgN = H.dialogWaiting() and dlgN + 1 or 0
      if not H.hasControl() then H.setPad(aPhase < 4 and { "a" } or {})
      else H.setPad({}) end
    end),
  }, "post-attempt settle")
end

-- one full Marshal attempt by squad p: activate it, walk beside the
-- Marshal, poke, fight boosted, settle.  Written flat (cond/driveUntil/
-- navTo steps carry no reset(), so repeated bodies replay latched
-- state -- the same reason the battle-clear-write ancestor wrote its two poke
-- rounds out flat).
local function attempt(p, round)
  return H.cond(function() return defenseWon() end, {}, {
    logPools("attempt " .. round .. " (P" .. p .. ")"),
    ySwitchTo(p),
    H.navTo(MX, MY - 1, {
      arrive = function()
        return defenseWon()
            or (marshalAdjacent() and H.hasControl() and H.tileAligned())
      end,
      maxFrames = 15000, playBattles = true,
    }),
    pokeStep(round),
    marshalFight(30000),
    settleStep(),
  })
end

H.run({ maxFrames = 200000 }, {
  H.loadState(DOORSTEP),
  H.waitFrames(10),
  H.waitUntil(function() return H.hasControl() end, 300, "entry point control", 5),
  H.call(function()
    H.assertEq(H.mapId(), 50, "boot map is the mines chase map (50)")
    H.assertEq(H.fieldX() == 55 and H.fieldY() == 12, true,
      "at the moogle entry point (55,12)")
    H.assertEq(collapseStarted(), false, "collapse switch $012E clear")
  end),

  -- ===================================================================== --
  -- Phase 1: the deliberate step onto (55,11).  A random encounter on the
  -- step is FOUGHT inline by the same edge-tapped A (real input -- bal_mines'
  -- baseline policy beats this map's whole pool); the trigger fires the
  -- moment we stand on the tile, so the terminator is a sustained event.
  -- ===================================================================== --
  H.driveUntil(eventFor(30), 4000, {
    H.call(function()
      aPhase = (aPhase + 1) % 8
      if H.battleLoadStarted() then
        H.setPad(aPhase < 4 and { "a" } or {})
        return
      end
      if H.dialogWaiting() then H.setPad(aPhase < 4 and { "a" } or {}); return end
      if not H.hasControl() then H.setPad({}); return end
      if not H.tileAligned() then H.setPad({}); return end
      H.setPad(H.fieldY() <= 11 and { down = true } or { up = true })
    end),
  }, "collapse trigger fires"),
  H.logStep(function()
    return string.format("collapse event running at frame %d", H.frame)
  end),

  -- ===================================================================== --
  -- Phase 2: everything up to the LOCKE naming menu.  advanceStory taps
  -- dialogs, FIGHTS battle 115's soldiers (real tap-A), and stays
  -- hands-off through the choreography.  The menu detector is NOT the
  -- $0059 idiom gen_narshe_escape used: $59 is also battle-module
  -- scratch, and run 1 measured it flipping nonzero DURING battle 115 --
  -- the pred fired mid-fight and the real menu later sat unattended
  -- forever.  The reliable signature is the menu itself: it SUSPENDS the
  -- field module, so control, the event PC, dialogs and battle all read
  -- dead at once -- a combination no scene shows for long (event waits
  -- hold the PC in CA-range; ambient ev=false pulses last a frame or
  -- two) -- sustained for 120 consecutive frames on map 30 (run 1
  -- measured the stall holding for 20k+ frames; nothing else on map 30
  -- goes quiet at all: the walk-in choreography and the four Arvis
  -- dialogs keep ev/dlg live).
  -- ===================================================================== --
  H.advanceStory((function()
    local cnt = 0
    return function()
      local quiet = H.mapId() == 30 and not H.hasControl()
        and not H.eventRunning() and not H.dialogWaiting()
        and not H.battleLoadStarted()
      cnt = quiet and cnt + 1 or 0
      return cnt >= 120
    end
  end)(), 35000, { playBattles = true }),
  H.logStep("naming menu open (field module suspended); committing LOCKE"),
  H.call(function() H.screenshot("moogle_naming") end),
  -- START commits the default name (name_change.asm exits on START unless
  -- the name is blank -- the gen_narshe_escape precedent); pressed on
  -- repeat until the event engine audibly resumes, because a single press
  -- during any residual menu fade would vanish
  H.driveUntil(eventFor(10), 1200, {
    H.pressButtons({ "start" }, 8),
    H.waitFrames(12),
  }, "naming committed, event resumed"),

  -- ===================================================================== --
  -- Phase 3: the rest of the recruitment + moogle scenes to the defense.
  -- Done = calm control on map 51 with $012E set: the switch lands three
  -- event commands before player_ctrl_on (event_main.asm:103278-103283),
  -- so calm+switch is exactly "the defense is live and ours to play".
  -- ===================================================================== --
  H.advanceStory(calm(30, function()
    return H.mapId() == 51 and collapseStarted()
  end), 25000, { playBattles = true }),
  H.call(function()
    H.assertEq(H.mapId(), 51, "on the defense map (51)")
    H.assertEq(collapseStarted(), true, "defense-live switch $012E set")
    H.assertEq(defenseWon(), false, "defense not yet won ($0631 still set)")
    H.assertEq(H.readByte(0x1f41) & 0xFC, 0xFC,
      "all six guard switches $060A..$060F set")
    H.log(string.format("defense live: party 1 at (%d,%d), frame %d",
      H.fieldX(), H.fieldY(), H.frame))
    -- log the field objects the fight cares about (Marshal = NPC_3 =
    -- object 18, guards NPC_4..9 = 19..24, TERRA-down = 25; object i's
    -- pixel coords live at $086A/$086D + $29*i, tiles = >>4)
    for i = 16, 25 do
      local ox = H.readWord(0x086a + 0x29 * i) >> 4
      local oy = H.readWord(0x086d + 0x29 * i) >> 4
      H.log(string.format("object %d at (%d,%d)", i, ox, oy))
    end
    H.screenshot("moogle_defense")
  end),
  H.saveState("moogle_defense.mss"),

  -- ===================================================================== --
  -- Phase 4a: deployment, in march order.  Wave 1 (NPC_4) passes the east
  -- station ~1400 field-frames after control, the west arm's first guard
  -- ~1800, the choke ~2100 -- so P1 sidesteps to the off-path (15,15) to
  -- unbox the mound, P3 walks east, P2 west, and P1 re-mans the choke
  -- with ~800 frames to spare (probe_moogle_stations measured f1515
  -- deployed against the f1630 first collision).
  -- ===================================================================== --
  H.navTo(15, 15, { maxFrames = 2500, playBattles = true }),
  ySwitchTo(3),
  H.navTo(20, 20, { maxFrames = 4000, playBattles = true }),
  ySwitchTo(2),
  H.navTo(10, 21, { maxFrames = 4000, playBattles = true }),
  ySwitchTo(1),
  H.navTo(14, 14, { maxFrames = 2500, playBattles = true }),
  logPools("deployed"),

  -- ===================================================================== --
  -- Phase 4b: the storm.  Hands off: each march collides with its arm's
  -- squad, the collision auto-engages that squad, tap-A wins the wave
  -- (Vomammoth + Lobo), and the win path despawns the guard --
  -- $060A..$060F clear one by one, two waves per squad at ~90-190 HP
  -- each.  advanceStory's playBattles mode is exactly this driver.
  -- ===================================================================== --
  H.advanceStory(function()
    return (H.readByte(0x1f41) & 0xFC) == 0
  end, 60000, { playBattles = true }),
  H.logStep(function()
    return string.format("all six wave guards down at frame %d; corridor open",
      H.frame)
  end),
  logPools("waves complete"),
  H.waitUntil(calm(30), 1800, "post-storm calm"),

  -- ===================================================================== --
  -- Phase 4c: the Marshal, up to three input-driven attempts.  P2 first
  -- (MOG's squad, the biggest pool -- it won at 330/543 with MOG alone
  -- standing at 89 HP, probe_moogle_marshal), then P1, then P3 if a wipe
  -- lands:  battle 6's loss path revives the loser at 1 HP on (14,11) and
  -- the Marshal still stands, so retrying with the next squad is the same
  -- move a human player makes.  Attempts 2 and 3 are no-ops (cond on the
  -- won-switch) when an earlier one already cleared it.
  -- ===================================================================== --
  attempt(2, 1),
  attempt(1, 2),
  attempt(3, 3),
  H.call(function()
    H.assertEq(defenseWon(), true, "defense won (switch $0631 cleared)")
    H.log(string.format("Marshal down at frame %d; riding the epilogue", H.frame))
  end),

  -- ===================================================================== --
  -- Phase 5: the epilogue chain (Thanks-Moogles, the mine switch, TERRA's
  -- amnesia dialogs, the secret entrance) ends with player_ctrl_on and
  -- $01CC=1 on map 20 (event_main.asm:104186-104188); no menus, so
  -- advanceStory rides all of it.
  -- ===================================================================== --
  H.advanceStory(calm(60, function()
    return H.mapId() == 20 and (H.readByte(0x1eb9) & 0x10) ~= 0
  end), 30000, { playBattles = true }),

  -- ===================================================================== --
  -- Phase 6: assert the far side and generate.  Roster: char_party TERRA,1 /
  -- LOCKE,1 and every moogle-bearing slot zeroed (event_main.asm:
  -- 103810-103821); party bytes live at $1850+char (low 3 bits = party).
  -- ===================================================================== --
  H.call(function()
    H.assertEq(H.mapId(), 20, "far side is the Narshe streets (map 20)")
    H.assertEq(defenseWon(), true, "defense-won switch state")
    -- bits 1-7 = $0609..$060F (moogle-visible + the six guards); bit 0 is
    -- the unrelated $0608, which run 4 measured set on the far side
    H.assertEq(H.readByte(0x1f41) & 0xFE, 0,
      "guard/moogle switches $0609..$060F clear")
    H.assertEq((H.readByte(0x1ea5) & 0x80) ~= 0, true,
      "secret-entrance switch $012F set")
    H.assertEq(H.readByte(0x1850) & 0x07, 1, "TERRA in party 1")
    H.assertEq(H.readByte(0x1851) & 0x07, 1, "LOCKE in party 1")
    for c = 2, 12 do
      H.assertEq(H.readByte(0x1850 + c) & 0x07, 0,
        string.format("char %d out of party", c))
    end
    -- TERRA per script: max_hp + and_status NONE (event_main.asm:
    -- 104170-104175); char block $1600: +$09 cur HP, +$0B max HP
    local hp, maxhp = H.readWord(0x1609), H.readWord(0x160b)
    H.assertEq(hp > 0 and hp == (maxhp & 0x3fff), true,
      string.format("TERRA at full HP (%d/%d)", hp, maxhp & 0x3fff))
    H.log(string.format("cleared: map=%d (%d,%d) frame=%d",
      H.mapId(), H.fieldX(), H.fieldY(), H.frame))
    H.screenshot("moogle_cleared")
  end),
  H.saveState("moogle_cleared.mss"),
  H.logStep(function()
    return string.format("moogle_cleared generated at frame %d", H.frame)
  end),
})
