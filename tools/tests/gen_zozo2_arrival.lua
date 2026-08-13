-- gen_zozo2_arrival.lua -- v0.4 step 1b: figaro_submerged (engine room, map
-- 61 {6,34}, castle parked west at ~world {30,48}) -> up and out of the
-- castle -> the western WoB -> Zozo's world tiles {21..22,92} -> generate
-- zozo_arrival.mss on map 221 at the street landing {61,44}.
--
-- Route checkpoints (from source, not the survey):
--  * 61 door (11,32) -> 59 {10,48}; 59 door (12,41) -> 55 {28,31}
--    (short_entrance.dat _61/_59)
--  * map 55's row y=43 is the world-exit long entrance (gen_kolts's rule:
--    keep it off every route except when leaving on purpose).  Here it is
--    the exit: navTo(28,42), hold down
--  * the world landing is measured by this run's log (parent record vs the
--    long-entrance dest {65,77} was statically ambiguous; the ride's
--    SET_PARENT points at the west parking ~{30,48})
--  * world {30,48}/{31,48} are the west castle trigger tiles (_ca5ec2,
--    gated $010C=1, which is set here).  Triggers fire on step, so the exit
--    placement is safe, and the Zozo step heads south-west away from them
--  * Zozo: world {21,92}/{22,92}/{22,93} -> map 221 {61,44}
--    (short_entrance.dat _0)
--
-- Issue #75, playBattles: every navigator call passes the option, so none
-- reaches the library's monster-dead flag write.  Maps 61, 59 and 55 have
-- random encounters disabled -- a field map only rolls when map_prop.dat
-- byte +5 bit 7 is set (field/map.asm:143-158 loads the record to $0520,
-- field/battle.asm:333-347 returns early unless $0525 is negative) -- so
-- those steps pass "tactical" as intent only, and fight rather than flee if
-- something unscripted ever does fire.
--
-- ------------------------------------------------------- the world walk --
-- The crossing to Zozo used to be one 177-step worldNavTo with
-- playBattles="flee", and that is what left the party too weak for the
-- town.  Zozo's own maps draw levels 15 and 16 -- map 221 is
-- sub_battle_group 78 (Gabbldegak 15, Harvester 16, HadesGigas 16) and map
-- 225 is group 77 (SlamDancer 15, Harvester 16) -- while the party arrived
-- at LOCKE 11, EDGAR 12, SABIN 12, CELES 11 and was wiped on the climb
-- ("all four battle-HP words have read 0 ... at (45,54) on map 221").
-- Grinding inside Zozo is circular, so the levels are earned on the way in,
-- which is also what the route is supposed to do: docs/design/wob-route.md
-- section 2, "the route plays casual" -- a normal player fights what they
-- meet and grinds a little for experience.
--
-- The ground is the western World of Balance between the west Figaro castle
-- and Zozo, and it is the right tier rather than a soft one.  Decoded from
-- world_1_tilemap.dat + WorldTileProp ($EE9B14) through the chain
-- CheckBattleWorld walks (field/battle.asm:97-214): zone =
-- (tileY & $E0) | ((tileX >> 3) & $1C), group =
-- WorldBattleGroup[zone | BattleBGGroupTbl[bg]], formations =
-- RandBattleGroup[group * 8 + {0,2,4,6}] at 31.25/31.25/31.25/6.25%.  Of
-- the 177 tiles on the walk, 158 are world battle group 10 -- Vulture 15,
-- Iron Fist 15, Mind Candy 15 -- and 4/11/1 are groups 12/9/11.  Group 10
-- pays an expected 918 experience and 1504 gil a fight once OT6's
-- Ot6RewardMulW = $0020 doubling is applied (ot6_break.asm:693-696), and
-- WinBattle divides experience by the number of allies alive
-- (battle_main.asm:15790-15800), so 4 alive is about 229 each.  The same
-- pair of knobs halves the per-step danger increment (Ot6DangerMulW =
-- $0008), which puts a fight roughly every 37 steps.
--
-- The pool is breakable by the party that walks it, which is why it is safe
-- to fight rather than flee.  Iron Fist carries an authored row (2 shields,
-- PIERCE|BLUDG, ot6_hud.asm Ot6ShieldTbl); Vulture and Mind Candy have no
-- authored row and take the generated floor, which keys both to slash
-- (OT6_FLOOR_CLASS, ot6_break_floor.inc, seeded at ot6_break.asm:96-108).
-- EDGAR's MithrilBlade is the party's slash ($0a, ot6_class.asm:57),
-- SABIN's fists and Pummel cover bludgeon, LOCKE and CELES cover pierce.
--
-- Shape of the walk, and why it is segmented.  HANDOFF's rule is that a
-- world walk which fights its encounters needs a care stop BETWEEN battles
-- or it wipes, because in-battle healing is bounded by turns and a field
-- menu between fights costs none.  So the crossing is 13 hops of 12 steps
-- with H.fieldCare after each, instead of one long drive.  The hops are
-- tiles of the same 177-step shortest path the single call used to walk:
-- the pairwise distances sum to 151 + 26 = 177, so the segmentation costs
-- no extra steps.  No hop, and no shortest path between any two of them,
-- touches a world entrance record or a world event trigger (checked against
-- all 45 ShortEntrance records for world 0 and all 9 EventTrigger records
-- for map 0), which matters because BFS knows about neither.
--
-- Then the grind laps: (34,99) <-> (34,112), 13 steps each way on the x=34
-- column, all group 10, no entrance and no trigger on it, and no map load
-- (the danger counter is zeroed by every battle and every map load, so a
-- lap that ducks into a town throws away what it has accumulated).  The
-- loop is target-driven off LOCKE's total experience rather than lap count,
-- because he is the lowest of the four and the crossing's own fights
-- already pay part of the bill.
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id)
  return (H.readByte(0x1E80 + math.floor(id / 8)) >> (id % 8)) & 1
end

local function landed(m, n)
  local cnt, hb = 0, -600
  return function()
    local ok = map() == m and H.hasControl() and H.tileAligned()
           and bright() >= 15 and not H.battleLoadStarted()
           and not H.dialogWaiting() and not H.worldMode()
    cnt = ok and cnt + 1 or 0
    if not ok and H.frame - hb >= 600 then
      hb = H.frame
      H.log(string.format("landed(%d) f%d: map=%d ctl=%s dlg=%s ev=%s (%d,%d)",
        m, H.frame, map(), tostring(H.hasControl()),
        tostring(H.dialogWaiting()), tostring(H.eventRunning()),
        H.fieldX(), H.fieldY()))
    end
    return cnt >= (n or 20)
  end
end

-- ------------------------------------------------------------ the roster --
-- $1600 + 37*c: +8 level, +9/+11 cur/max hp, +13/+15 cur/max mp, +$11 a
-- 3-byte total experience.  Printed at every hop so the walk's damage and
-- levelling are legible step by step rather than only at the end.
local POTION, TONIC, FENIX = 0xE9, 0xE8, 0xF0
local LOCKE = 1

local function invCount(id)
  for i = 0, 255 do
    if H.readByte(0x1869 + i) == id then return H.readByte(0x1969 + i) end
  end
  return 0
end
local function gil()
  return H.readByte(0x1860) + (H.readByte(0x1861) << 8)
       + (H.readByte(0x1862) << 16)
end
local function levelOf(c) return H.readByte(0x1600 + 37 * c + 8) end
local function expOf(c)
  local b = 0x1600 + 37 * c + 0x11
  return H.readByte(b) + (H.readByte(b + 1) << 8) + (H.readByte(b + 2) << 16)
end

local function rosterLine()
  local out = {}
  for _, c in ipairs(H.partyMembers()) do
    out[#out + 1] = string.format("c%d L%d xp=%d %d/%d hp %d/%d mp", c,
      levelOf(c), expOf(c), H.charHp(c), H.charMaxHp(c),
      H.charMp(c), H.charMaxMp(c))
  end
  return string.format("%s | gil=%d tonic=%d potion=%d fenix=%d",
    table.concat(out, " | "), gil(),
    invCount(TONIC), invCount(POTION), invCount(FENIX))
end

local function where(tag)
  H.log(string.format("[%s] f%d world=(%d,%d) map=%d",
    tag, H.frame, H.worldX(), H.worldY(), map()))
  H.log(string.format("[%s] %s", tag, rosterLine()))
end

-- The care stop between fights.  Potions are reserved down to three because
-- the fight driver spends them inside a battle; the walk may not empty the
-- bag on top-ups.  CELES is the only caster here (Ice, Cure, Antdot at
-- zozo_arrival), and casting is what makes this cheap: OT6 restores HP and
-- MP in full on level up (ot6_progression.asm:3-6), so MP spent between
-- fights on a grind is refunded and a Tonic is not.
local function care(tag, threshold)
  return H.fieldCare({ tag = "care " .. tag, threshold = threshold or 0.9,
                       reserve = { [POTION] = 3 } })
end

local function seq(steps) return H.cond(function() return true end, steps) end

local function walk(x, y, what, opts)
  opts = opts or {}
  return seq({
    H.logStep(function()
      return string.format("%s -> world (%d,%d): %s", what, x, y, rosterLine())
    end),
    H.worldNavTo(x, y, { maxFrames = 40000, playBattles = "tactical",
                         healPercent = 60, reserve = { [POTION] = 3 },
                         arrive = opts.arrive }),
    H.release(),
  })
end

-- ------------------------------------------------------ the crossing hops --
-- Waypoints every 12 steps along the shortest path from the west castle
-- parking to (34,99); the last hop is the 7-step remainder.
local CROSSING = {
  { 30, 60 }, { 27, 69 }, { 22, 76 }, { 16, 82 }, { 12, 90 }, { 11, 101 },
  { 15, 109 }, { 19, 117 }, { 23, 125 }, { 30, 126 }, { 34, 118 },
  { 34, 106 }, { 34, 99 },
}

local function crossing()
  local steps = {}
  for i, w in ipairs(CROSSING) do
    steps[#steps + 1] = walk(w[1], w[2], "crossing hop " .. i)
    steps[#steps + 1] = care("crossing hop " .. i)
  end
  return seq(steps)
end

-- ----------------------------------------------------------- the grind --
-- The target is LOCKE's TOTAL experience, not a level, and it is his rather
-- than the party's because experience is split evenly and he is the lowest
-- of the four, so a target that satisfies him satisfies everyone.
--
-- 6432 is level 13 (8 * sum(LevelUpExp[2..L]), CalcLevelExpTotal,
-- ff6/src/menu/status.asm:581-609; LevelUpExp is field/event.asm:1329).  He
-- reached this point at 4428 on the chain of 2026-07-22, so the bill is
-- about 2000 experience, of which the crossing's own four or five fights pay
-- roughly half.  Two levels for LOCKE and CELES and one or two for EDGAR and
-- SABIN is "a level or two", the owner's words, rather than a grind to the
-- cap: it puts a party of 13s and 14s against a pool of 15s and 16s, where
-- the losing party was 11s and 12s.
local EXP_TARGET = 6432
local grindLaps = 0
local function grindDone() return expOf(LOCKE) >= EXP_TARGET end

local function lap(n)
  return H.cond(function() return not grindDone() end, {
    H.logStep(function()
      return string.format("grind lap %d: LOCKE L%d xp=%d/%d gil=%d f%d", n,
        levelOf(LOCKE), expOf(LOCKE), EXP_TARGET, gil(), H.frame)
    end),
    walk(34, 112, "grind lap " .. n .. " south"),
    walk(34, 99, "grind lap " .. n .. " north"),
    H.call(function() grindLaps = n; where("grind lap " .. n) end),
    care("grind lap " .. n),
  }, {})
end

-- The lap cap is a bound on a runaway, not a plan: the loop exits on the
-- target, and a lap it skips costs one predicate call.  36 is set against
-- the measured rate -- about 200 experience each a fight, a fight about
-- every 37 steps, 26 steps a lap -- so it covers roughly 2600 experience,
-- comfortably more than the largest gap seen at this point in the route.
local function grind()
  local steps = {}
  for n = 1, 36 do steps[#steps + 1] = lap(n) end
  steps[#steps + 1] = H.call(function()
    H.log(string.format("[grind] %d laps: LOCKE L%d xp=%d (target %d), " ..
      "gil=%d, f%d", grindLaps, levelOf(LOCKE), expOf(LOCKE), EXP_TARGET,
      gil(), H.frame))
    H.assertEq(expOf(LOCKE) >= EXP_TARGET, true,
      string.format("the grind reached its experience target in %d laps " ..
        "(LOCKE %d of %d)", grindLaps, expOf(LOCKE), EXP_TARGET))
  end)
  return seq(steps)
end

local function door(nx, ny, dir, m, what)
  return H.cond(function() return true end, {
    H.navTo(nx, ny, { maxFrames = 12000, playBattles = "tactical" }),
    H.driveUntil(function() return map() == m end, 900, {
      H.hold({ dir }), H.waitFrames(4),
    }, what .. ": through the door"),
    -- ride any arrival scene out (the west castle greets with one:
    -- measured, an event walks the party to (28,28) and parks a dialog)
    H.advanceStory(landed(m, 10), 2400, { playBattles = "tactical" }),
    -- door loads finalize the decompressed prop table late: ~150 frames
    -- after control and brightness the engine still walked (and modelled)
    -- on the previous map's props (measured, probe_n20c on map 30->20: a
    -- legal step refused at +40f, accepted at +80f; the census flipped
    -- from all-walls to correct at ~+150f).  Settle long before any BFS.
    H.waitFrames(150),
  })
end

-- maxFrames: the fleeing version of this step ran inside 90000.  Measured
-- 2026-08-13, the fought crossing alone reaches the grind column at f25743
-- having fought four battles, and the grind is the larger half; a group-10
-- fight runs in the same range as the Zozo street's measured 6352 frames.
-- 600000 is the lap cap's worth of that with room, rather than a number
-- tuned to one run.
H.run({ maxFrames = 600000 }, {
  H.loadState("build/states/figaro_submerged.mss.lua"),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 61, "booted in the engine room (map 61)")
    H.assertEq(sw(0x010C), 1, "$010C SET -- castle parked WEST")
  end),

  -- 1. engine room -> keep hall -> the gate map.  (11,32) is a walk-in
  --    doorway (directly reachable, probe_eng61) landing at 59 {10,48};
  --    the keep->gate door (28,32)-side needs the held press.
  H.navTo(11, 32, { arrive = function() return map() == 59 end,
                    maxFrames = 9000, playBattles = "tactical" }),
  H.waitUntil(landed(59, 10), 1500, "keep hall", 1),
  H.waitFrames(150),
  door(12, 42, "up", 55, "keep -> the gate map"),

  -- 2. the arrival scene parks the party on the front terrace at (28,28),
  --    which is walled from the gate: drop through door (28,32) -> 59
  --    {12,43}, then door (12,50) -> 55 {28,40}, the lower gate yard.
  door(28, 31, "down", 59, "terrace -> vestibule"),
  door(12, 49, "down", 55, "vestibule -> gate yard"),

  -- 3. off the castle onto the world: row y=43 is the exit
  H.navTo(28, 42, { maxFrames = 12000, playBattles = "tactical" }),
  H.driveUntil(function() return H.worldMode() end, 900, {
    H.hold({ "down" }), H.waitFrames(4),
  }, "off the castle to the world"),
  H.waitUntil(function()
    return H.worldHasControl() and H.worldAligned() and bright() >= 15
  end, 1500, "world control", 5),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("[world] west landing at (%d,%d)",
      H.worldX(), H.worldY()))
    where("west landing")
  end),

  -- 4. south-west to (34,99), fighting, with a care stop every 12 steps.
  crossing(),

  -- 5. the grind laps on the x=34 column, until LOCKE clears EXP_TARGET.
  H.call(function()
    H.assertEq(H.worldX(), 34, "staged on the grind column, x=34")
    H.assertEq(H.worldY(), 99, "staged at the grind column's north end, y=99")
    where("grind start")
  end),
  grind(),
  H.call(function()
    where("grind done")
    H.screenshot("zozo_grind_done")
  end),

  -- 6. the last 26 steps to Zozo: park one tile above the {22,92} entrance,
  --    then step onto it.  arrive bails if a step lands the entrance early.
  walk(22, 91, "zozo approach",
       { arrive = function() return not H.worldMode() end }),
  care("outside Zozo", 0.95),
  H.driveUntil(function() return not H.worldMode() and map() == 221 end, 900, {
    H.hold({ "down" }), H.waitFrames(4),
  }, "onto Zozo's entrance tile"),
  H.waitUntil(landed(221, 10), 1500, "Zozo street up", 1),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 221, "on the Zozo exterior (map 221)")
    H.log(string.format("[zozo_arrival] f%d at (%d,%d)",
      H.frame, H.fieldX(), H.fieldY()))
    where("zozo_arrival")
    -- The entry-point contract for the climb.  The town that follows drew
    -- the party's wipe once already, so this fixture says what it is
    -- handing over rather than leaving it to be discovered three edges
    -- down: everyone alive, nobody below half hit points, and LOCKE at the
    -- level the grind was run for.
    for _, c in ipairs(H.partyMembers()) do
      H.assertEq(H.charHp(c) > 0, true,
        string.format("char %d reached Zozo alive", c))
      H.assertEq(H.charHp(c) * 2 >= H.charMaxHp(c), true,
        string.format("char %d is at or above half hp (%d/%d)",
          c, H.charHp(c), H.charMaxHp(c)))
    end
    H.assertEq(levelOf(LOCKE) >= 13, true,
      string.format("LOCKE reaches Zozo at level 13 or better (L%d, xp %d)",
        levelOf(LOCKE), expOf(LOCKE)))
    H.screenshot("zozo_arrival")
  end),
  H.saveState("zozo_arrival.mss"),
  H.logStep(function()
    return string.format("zozo_arrival generated at frame %d", H.frame)
  end),
})
