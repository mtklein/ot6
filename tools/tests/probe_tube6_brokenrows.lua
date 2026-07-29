-- probe_tube6_brokenrows.lua -- the FAIL-BEFORE / PASS-AFTER instrument for
-- the three tube-room rows magicite-tube-six.md calls actively broken
-- (§1, issue #31).  Run it against a ROM built before the genju_prop change
-- and it fails, with all three rows' granted lists in the log; run it against
-- the ROM built after and it passes.
--
--   OT6_ROM=<pre-change>.sfc tools/tests/run.sh tools/tests/probe_tube6_brokenrows.lua
--   tools/tests/run.sh tools/tests/probe_tube6_brokenrows.lua
--
-- WHY THIS EXISTS SEPARATELY FROM battle_esperstats_tube6.lua.  That file is
-- the gate and asserts everything -- stat mod first, then grants.  Against a
-- pre-change ROM it therefore dies on Maduin's flat mag.pwr and never reaches
-- a single grant assertion, so the "before" log proves nothing about the three
-- broken rows.  This probe measures all four scenarios FIRST, logs every
-- granted list, and only then asserts, so one failing run carries the whole
-- before-picture.  It also asserts nothing about the stat table, which is a
-- different file's change.
--
-- THE THREE CLAIMS, each verified against the data before it was changed:
--   MADUIN  genju_prop.asm:128 held {FIRE_2, ICE_2, BOLT_2} -- three dead
--           pre-folded tiers at once.  Ot6FoldTbl rows 0-2 (ot6_boost.asm:
--           341-343) fold the BASE tiers up under boost, so a granted tier-2
--           is unreachable-by-boost and priced at 20-22 MP for what 4-6 MP
--           buys.  Now {FIRE, ICE, BOLT}.
--   BISMARK genju_prop.asm:131 held {FIRE, ICE, BOLT, LIFE}.  LIFE violates
--           kits.md:262-263: revival "lives on Terra, Fenix Downs, and
--           Sraphim, and nowhere else" -- and a stone is wearable by anyone.
--           Now {HASTE, SLOW}.
--   SHOAT   genju_prop.asm:125 held {BIO, BREAK, DOOM}.  BIO is the pre-folded
--           CAP of the poison family (Ot6FoldTbl row 3, ot6_boost.asm:344):
--           26 MP for what a 3 MP Poison folds into at 1 BP.  Now
--           {BREAK, DOOM}.
--
-- List-window rationale (slots 1..54, skipping the esper row and the lore
-- block): see battle_esperstats_tube6.lua's header and probe_tube6_list.lua.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_doorstep.mss.lua"

local FIRE, ICE, BOLT         = 0x00, 0x01, 0x02
local FIRE2, ICE2, BOLT2, BIO = 0x05, 0x06, 0x07, 0x08
local BREAK, DOOM             = 0x0c, 0x0d
local SLOW, HASTE, LIFE       = 0x19, 0x1f, 0x30

local SHOAT, MADUIN, BISMARK  = 0x05, 0x06, 0x07

local ESPER0 = 0x161e
local LIST0  = 0x208e

local R = {}

local function unionSet()
  local set = {}
  for n = 1, 54 do
    local id = H.readByte(LIST0 + n * 4)
    if id ~= 0xff then set[id] = true end
  end
  return set
end
local function has(set, id) return set[id] == true end
local function idsOf(set)
  local t = {}
  for id in pairs(set) do t[#t + 1] = id end
  table.sort(t)
  local s = {}
  for i, id in ipairs(t) do s[i] = string.format("$%02x", id) end
  return table.concat(s, " ")
end

local function driveIn(tag, esper)
  local steps = { H.loadState(STATE), H.waitFrames(10) }
  steps[#steps + 1] = H.call(function()
    if esper then H.writeByte(ESPER0, esper) end
  end)
  steps[#steps + 1] = H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load (" .. tag .. ")")
  steps[#steps + 1] = H.waitUntil(function() return H.battleActive() end, 900,
    "battle active (" .. tag .. ")", 30)
  steps[#steps + 1] = H.waitFrames(120)
  steps[#steps + 1] = H.call(function()
    R[tag] = unionSet()
    H.log(string.format("[%s] esper row=$%02x  granted spell ids: %s",
      tag, H.readByte(LIST0), idsOf(R[tag])))
  end)
  return steps
end

local all = { H.waitFrames(20) }
local function add(l) for _, s in ipairs(l) do all[#all + 1] = s end end

-- MEASURE ALL FOUR FIRST -- nothing is asserted until every list is logged.
add(driveIn("base", nil))
add(driveIn("maduin", MADUIN))
add(driveIn("shoat", SHOAT))
add(driveIn("bismark", BISMARK))

add({ H.call(function()
  -- The control this all rests on: none of the six signatures is innate here.
  -- (Fire IS innate to Terra at this fixture and is therefore NOT a control --
  -- it is only ever used as a "grants" corroboration below.)
  for _, s in ipairs({
    { ICE, "Ice" }, { BOLT, "Bolt" }, { FIRE2, "Fire2" }, { ICE2, "Ice2" },
    { BOLT2, "Bolt2" }, { BIO, "Bio" }, { BREAK, "Break" }, { DOOM, "Doom" },
    { HASTE, "Haste" }, { SLOW, "Slow" }, { LIFE, "Life" },
  }) do
    H.assertEq(has(R.base, s[1]), false, "[base] " .. s[2] .. " innately absent")
  end

  -- BROKEN ROW 1 -- Maduin's three dead pre-folded tiers.
  H.assertEq(has(R.maduin, ICE), true, "[maduin] grants Ice (base tier)")
  H.assertEq(has(R.maduin, BOLT), true, "[maduin] grants Bolt (base tier)")
  H.assertEq(has(R.maduin, FIRE), true, "[maduin] grants Fire (innate too -- corroboration)")
  H.assertEq(has(R.maduin, FIRE2), false, "[maduin] Fire2 GONE (dead pre-folded tier)")
  H.assertEq(has(R.maduin, ICE2), false, "[maduin] Ice2 GONE (dead pre-folded tier)")
  H.assertEq(has(R.maduin, BOLT2), false, "[maduin] Bolt2 GONE (dead pre-folded tier)")

  -- BROKEN ROW 2 -- Shoat's Bio.
  H.assertEq(has(R.shoat, BREAK), true, "[shoat] grants Break")
  H.assertEq(has(R.shoat, DOOM), true, "[shoat] grants Doom")
  H.assertEq(has(R.shoat, BIO), false, "[shoat] Bio GONE (pre-folded poison cap)")

  -- BROKEN ROW 3 -- Bismark's Life, against kits.md's revival rule.
  H.assertEq(has(R.bismark, HASTE), true, "[bismark] grants Haste")
  H.assertEq(has(R.bismark, SLOW), true, "[bismark] grants Slow")
  H.assertEq(has(R.bismark, LIFE), false,
    "[bismark] Life GONE (kits.md:262-263: revival is Terra/Fenix Down/Sraphim only)")

  H.log("[brokenrows] all three rows fixed: Maduin base tiers, Shoat without "
    .. "Bio, Bismark without Life")
end) })

H.run({ maxFrames = 200000 }, all)
