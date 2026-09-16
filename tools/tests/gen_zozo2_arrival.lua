-- gen_zozo2_arrival.lua -- v0.4 step 1b: figaro_submerged (engine room, map
-- 61 {6,34}, castle parked west at ~world {30,48}) -> up and out of the
-- castle -> the western WoB -> Zozo's world tiles {21..22,92} -> generate
-- zozo_arrival.mss on map 221 at the street landing {61,44}.

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

-- The pool is breakable by the party that walks it, which is why it is safe
-- to fight rather than flee.  Iron Fist carries an authored row (2 shields,
-- PIERCE|BLUDG, ot6_hud.asm Ot6ShieldTbl); Vulture and Mind Candy have no
-- authored row and take the generated floor, which keys both to slash
-- (OT6_FLOOR_CLASS, ot6_break_floor.inc, seeded at ot6_break.asm:96-108).
-- EDGAR's MithrilBlade is the party's slash ($0a, ot6_class.asm:57),
-- SABIN's fists and Pummel cover bludgeon, LOCKE and CELES cover pierce.

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

-- Then the grind laps: (34,99) <-> (34,112), 13 steps each way on the x=34
-- column, all group 10, no entrance and no trigger on it, and no map load
-- (the danger counter is zeroed by every battle and every map load, so a
-- lap that ducks into a town throws away what it has accumulated).  The
-- loop is target-driven off the party's levels rather than lap count.

-- The target is L18 for every member (#158, owner: "a one-shot means we're
-- just too low level; get that hp up by leveling").  Map 225, the first
-- interior both zozo3 and zozo4 enter, rolls a solo SlamDancer 31% of the
-- time whose single-target Fire 2 / Ice 2 / Bolt 2 measured 464..492 raw
-- (docs/design/zozo-street.md, n=5).  The monster is L15 whatever the party
-- is, so the roll does not grow with the party; max HP does (LevelUpHP,
-- field/event.asm: +54 at L17, +57 at L18).  L17 puts LOCKE at 501 and
-- CELES at 497, 5..9 over the largest roll seen in five samples of a
-- 224..255/256 variance window; L18 puts all four at 554+, ~60 over it.
-- The grind ends at Jidoor, a few steps south, for the Potion and Fenix
-- band the higher level asks for (shop 22 sells no Tonic).
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
local LOCKE, CELES = 1, 6

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
                         healPercent = 60, healer = CELES,
                         reserve = { [POTION] = 3 },
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
-- The target is every member's LEVEL (see the header): experience is split
-- evenly among the living, so the member with the least experience (LOCKE
-- on this route) is the one the loop is really waiting on.

local LEVEL_TARGET = 18
local HP_FLOOR = 540      -- the measured 492 roll plus ~10%
local grindLaps = 0
local function minLevel()
  local m = 99
  for _, c in ipairs(H.partyMembers()) do m = math.min(m, levelOf(c)) end
  return m
end
local function grindDone() return minLevel() >= LEVEL_TARGET end

local function lap(n)
  return H.cond(function() return not grindDone() end, {
    H.logStep(function()
      return string.format("grind lap %d: min L%d (target L%d) %s f%d", n,
        minLevel(), LEVEL_TARGET, rosterLine(), H.frame)
    end),
    walk(34, 112, "grind lap " .. n .. " south"),
    walk(34, 99, "grind lap " .. n .. " north"),
    H.call(function() grindLaps = n; where("grind lap " .. n) end),
    care("grind lap " .. n),
  }, {})
end

local function grind()
  local steps = {}
  for n = 1, 160 do steps[#steps + 1] = lap(n) end
  steps[#steps + 1] = H.call(function()
    H.log(string.format("[grind] %d laps: min L%d (target L%d), gil=%d, f%d",
      grindLaps, minLevel(), LEVEL_TARGET, gil(), H.frame))
    H.assertEq(grindDone(), true,
      string.format("the grind reached L%d for every member in %d laps " ..
        "(lowest L%d)", LEVEL_TARGET, grindLaps, minLevel()))
  end)
  return seq(steps)
end

local function door(nx, ny, dir, m, what)
  return H.cond(function() return true end, {
    H.navTo(nx, ny, { maxFrames = 12000, playBattles = "tactical" }),
    H.driveUntil(function() return map() == m end, 900, {
      H.hold({ dir }), H.waitFrames(4),
    }, what .. ": through the door"),
    H.advanceStory(landed(m, 10), 2400, { playBattles = "tactical" }),
    H.waitFrames(150),
  })
end

H.run({ maxFrames = 1200000 }, {
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

  -- SABIN's Pummel is row-exempt, so the back row is pure defense on this
  -- physical crossing.  LOCKE stays in front because his Fight chips the
  -- generated pierce/slash rows; EDGAR and CELES already inherit back-row
  -- assignments from the Narshe defense.
  H.setRows({ [5] = true }, { tag = "Zozo crossing rows" }),

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

  -- 5b. Jidoor's item shop (#158): the level the grind reached raises the
  --     supply band (docs/design/level-curve.md: Potion ~level x1.5, Fenix
  --     ~level), and the Zozo climb has no shop.  World door (27,130) from
  --     (27,129) -> map 198; the item shop is door (27,41) -> map 201
  --     (34,20), keeper (34,15) running _cb4460 = shop 22 while $00A4 is
  --     clear (event_main.asm); shop 22 rows: Potion 0, Fenix Down 5, and no
  --     Tonic.  Out by the south edge, as gen_opera2_open leaves.
  walk(27, 129, "Jidoor approach",
       { arrive = function() return not H.worldMode() end }),
  H.driveUntil(function() return not H.worldMode() and map() == 198 end, 4000, {
    H.hold({ "down" }), H.waitFrames(4),
  }, "into Jidoor (map 198)"),
  H.waitUntil(landed(198, 10), 2400, "Jidoor up", 1),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(sw(0x00A4), 0, "$00A4 clear -- the item shop opens as shop 22")
    where("Jidoor")
  end),
  H.crossDoor(27, 41, 201, 34, 20, "Jidoor item shop door 198(27,41)->201"),
  H.shopTalk(34, 15, "Jidoor item shop", { healer = CELES }),
  H.call(function()
    H.assertEq(H.readByte(0x0201), 22, "the counter opened shop 22 ($0201)")
  end),
  H.buyItem(POTION, 0, function() return 30 - invCount(POTION) end,
    "POTION to 30"),
  H.buyItem(FENIX, 5, function() return 20 - invCount(FENIX) end,
    "FENIX DOWN to 20"),
  H.shopClose("Jidoor item shop"),
  H.call(function()
    H.log(string.format("[shop] Jidoor done: %s", rosterLine()))
    H.assertEq(invCount(POTION) >= 30, true, "Potions at 30 leaving Jidoor")
    H.assertEq(invCount(FENIX) >= 20, true, "Fenix Downs at 20 leaving Jidoor")
  end),
  H.crossDoor(34, 21, 198, 27, 43, "Jidoor item shop -> street"),
  H.navTo(16, 61, { maxFrames = 24000, playBattles = "tactical" }),
  H.driveUntil(function() return H.worldMode() end, 6000, {
    H.hold({ "down" }), H.waitFrames(4),
  }, "off Jidoor's south edge"),
  H.waitUntil(function()
    return H.worldHasControl() and H.worldAligned() and bright() >= 15
  end, 2000, "world control", 5),
  H.waitFrames(30),
  H.call(function() where("left Jidoor") end),
  -- Back to the grind column's north end first, stepping east off the
  -- town's doorstep so no shortest path crosses Jidoor's door tile; from
  -- (34,99) the approach is the one the route always walked.
  walk(31, 132, "east of Jidoor's door"),
  walk(34, 112, "back to the grind column"),
  walk(34, 99, "the column's north end"),
  H.call(function()
    H.assertEq(H.worldMode(), true, "still on the world map after the return")
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
    -- down: everyone alive, nobody below half hit points, and every member
    -- at the level the grind was run for, with the max HP that level buys.
    for _, c in ipairs(H.partyMembers()) do
      H.assertEq(H.charHp(c) > 0, true,
        string.format("char %d reached Zozo alive", c))
      H.assertEq(H.charHp(c) * 2 >= H.charMaxHp(c), true,
        string.format("char %d is at or above half hp (%d/%d)",
          c, H.charHp(c), H.charMaxHp(c)))
      H.assertEq(levelOf(c) >= LEVEL_TARGET, true,
        string.format("char %d reaches Zozo at L%d or better (L%d, xp %d)",
          c, LEVEL_TARGET, levelOf(c), expOf(c)))
      H.assertEq(H.charMaxHp(c) >= HP_FLOOR, true,
        string.format("char %d max HP %d clears the SlamDancer's 492 roll " ..
          "with margin (floor %d)", c, H.charMaxHp(c), HP_FLOOR))
    end
    H.screenshot("zozo_arrival")
  end),
  H.saveState("zozo_arrival.mss"),
  H.logStep(function()
    return string.format("zozo_arrival generated at frame %d", H.frame)
  end),
})
