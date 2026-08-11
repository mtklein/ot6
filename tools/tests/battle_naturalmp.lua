-- @suite savestate=kolts_cave
-- battle_naturalmp.lua -- issue #32: battle MP is universal, on natural MP.
--
-- The bug: vanilla's battle init loads every character's MP through
-- LoadCharProp (battle_main.asm:6621-6640) and then clears it again unless a
-- magic or lore command init set the has-mp flag $f8, that is, unless the
-- character knows a spell (InitCmdList, battle_main.asm:13950-13956 plus
-- InitCmd_03/04/05).  Under the live MP economy (OT6_MP_COSTS, v0.5) that sent
-- every spell-less character into battle at 0/0 while Ot6AbilityCost priced
-- their whole kit: Blitz, Tools, Bushido and Steal all fizzled through
-- CalcAttackEffect's insufficient-MP gate (:8311-8329) as wasted turns with no
-- message, and the max-0 writeback skip (:12265-12267) kept field MP full so
-- nothing on the field showed it.  The suite could not see this by
-- construction, because every battle test and generator pins MP before acting.
-- This test pins no character state, and is the natural-MP coverage this class
-- of bug requires.
--
-- Fixture: kolts_cave.mss (make savestates): map 96, party TERRA LOCKE EDGAR
-- with whatever MP their real save carries, which gives one innate mage
-- (TERRA, the unchanged-path control) and two spell-less kit carriers.  The
-- natural encounter drive is battle_flyin's (same fixture, same lane pacing).
--
-- Asserted, in order:
--   1. universal load: every party slot enters battle with cur MP equal to
--      its field MP ($160d via $3010) and max MP nonzero.  Fails pre-fix:
--      LOCKE and EDGAR read 0/0.
--   2. a priced verb executes on natural MP: Edgar's AutoCrossbow (4 MP,
--      Ot6AbilityCostTbl) is driven as real pad edges, the cost queue prices
--      it, monster HP drops, and exactly that cost is charged.  Fails
--      pre-fix: the fizzle deals nothing and charges nothing.
--   3. writeback integrity: after the battle the field character data holds
--      pre-battle MP minus exactly what was spent, for every member.  The
--      max-0 skip no longer hides the pool, so this guards that the
--      now-live writeback path is correct.
-- No state is written at all (issue #75).  Two idioms this file used to
-- carry are gone.  The danger pin ($1f6e := 0xff00 per pace frame) is the
-- same pin 77bc4f9 deleted on this fixture: the pace loop was
-- already walking the lane, so the engine accrues danger per step and
-- rolls the encounter itself.  And the monster staging (stop bit plus HP
-- floored to 0xF000 so nothing died before the measurement) is deleted
-- outright, because the party only Defends until Edgar's turn, so nobody on
-- our side deals damage, and the map-96 pool's damage output cannot zero
-- anyone's MP, which is what phases 1-2 measure.  The battle then ends by
-- fleeing (held L+R, the engine's own run mechanic) instead of clearBattle
-- writing the battle-clearing flag, which makes phase 3 a stronger claim:
-- the writeback path is exercised on the flee exit, not just the victory exit.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/kolts_cave.mss.lua"

local MENU, ACTOR = 0x7BCA, 0x62CA
local EDGAR = 0x04
local AUTOCROSSBOW, XBOW_COST = 0xAA, 4    -- Ot6AbilityCostTbl: $aa, 4
local ITEMLIST = 0x4005                    -- MakeToolsList's wItemList

local function CURMP(s) return 0x3C08 + s * 2 end
local function MAXMP(s) return 0x3C30 + s * 2 end
local function MHP(m)  return 0x3BFC + m * 2 end
local CHARS = { [0]="TERRA","LOCKE","CYAN","SHADOW","EDGAR","SABIN",
                "CELES","STRAGO","RELM","SETZER","MOG","GAU","GOGO","UMARO" }

local function map() return H.mapId() & 0x1ff end

local slotOf, msPresent = {}, {}
local charOfs, fieldPre = {}, {}          -- per-slot $1600 offset / field MP
local costs = {}                          -- $3620 stores while cmd $09 queues
local edgarPre, hpsumPre

local function monsterHpSum()
  local t = 0
  for _, m in ipairs(msPresent) do t = t + H.readWord(MHP(m)) end
  return t
end

-- wait for a character's menu, consuming other characters' turns with a
-- real Defend (right swaps Fight->Def, then A), the probe_factory_menus
-- pattern; Defend is unpriced so it cannot move anyone's MP.  The monsters
-- take their own turns in here now, since there is no stop bit: their damage
-- lands on party HP, which nothing in this test asserts on.
local function menuFor(charId, what)
  local ph = 0
  local function up()
    return H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == slotOf[charId]
  end
  return H.driveUntil(up, 20000, {
    H.call(function()
      ph = ph + 1
      if H.readByte(MENU) ~= 0 and H.readByte(ACTOR) ~= slotOf[charId] then
        local step = ph % 40
        if step < 4 then H.setPad({ right = true })
        elseif step >= 20 and step < 24 then H.setPad({ a = true })
        else H.setPad({}) end
      else
        H.setPad({})
      end
    end),
  }, what)
end

local function tap(btn, gap)
  return H.repeatN(1, {
    H.pressButtons({ btn }, 4),
    H.waitFrames(gap or 16),
  })
end

H.run({ maxFrames = 60000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000,
    "field control in cave 96"),
  H.call(function() H.assertEq(map(), 96, "kolts_cave on map 96") end),

  -- pace the auto-detected lane until a natural encounter fires
  -- (battle_flyin's drive: the danger counter accrues per step and rolls
  -- the encounter itself; 77bc4f9 measured the natural roll at ~1300
  -- frames of pacing on this fixture, well inside the budget below)
  (function()
    local battN, waited, lane = 0, 0, nil
    local BACK = { left = "right", right = "left", up = "down", down = "up" }
    return H.driveUntil(function()
      waited = waited + 1
      battN = H.battleLoadStarted() and battN + 1 or 0
      if battN >= 1 then H.setPad({}) return true end
      if map() ~= 96 then error("paced off map 96 (now " .. map() .. ")", 0) end
      return waited >= 8000
    end, 8600, {
      H.call(function()
        if not (H.hasControl() and H.tileAligned()) then H.setPad({}) return end
        local x, y = H.fieldX(), H.fieldY()
        if lane == nil then
          for _, d in ipairs({ "right", "left", "up", "down" }) do
            if H.canStep(x, y, d) then lane = { ax = x, ay = y, out = d, back = BACK[d] } break end
          end
        end
        H.setPad({ [(x == lane.ax and y == lane.ay) and lane.out or lane.back] = true })
      end),
      H.waitFrames(1),
    }, "a cave encounter fires")
  end)(),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle armed", 5),
  H.waitFrames(240),

  -- ------------------------- 1. universal load: battle MP == field MP --
  H.call(function()
    for s = 0, 3 do
      local id = H.readByte(0x3ED8 + s * 2)
      if id ~= 0xFF then
        slotOf[id] = s
        charOfs[s] = H.readWord(0x3010 + s * 2)
        fieldPre[s] = H.readWord(0x160d + charOfs[s])
        local cur, max = H.readWord(CURMP(s)), H.readWord(MAXMP(s))
        H.log(string.format("[slot %d] %s battle MP=%d/%d field MP=%d", s,
          CHARS[id] or tostring(id), cur, max, fieldPre[s]))
        H.assertEq(max > 0, true, string.format(
          "%s enters battle with a real max MP (got %d; the vanilla "
          .. "spell-less clear zeroes it)", CHARS[id] or tostring(id), max))
        H.assertEq(cur, fieldPre[s], string.format(
          "%s enters battle with the save's own MP", CHARS[id] or tostring(id)))
      end
    end
    for m = 0, 5 do
      if H.readByte(0x3AA8 + m * 2) % 2 == 1 then msPresent[#msPresent + 1] = m end
    end
    assert(slotOf[EDGAR], "EDGAR present (kolts party)")
    assert(slotOf[0x00], "TERRA present (the innate-mage control)")
    H.assertEq(fieldPre[slotOf[EDGAR]] >= XBOW_COST, true,
      "positive control: Edgar's save MP can afford an AutoCrossbow")
    -- mp-cost queue store (CreateAction), filtered to Tools (cmd $09):
    -- battle_stealmp's instrument
    emu.addMemoryCallback(function(_, v)
      if H.readByte(0x3A7A) == 0x09 then costs[#costs + 1] = v end
    end, emu.callbackType.write, 0x7E3620, 0x7E3620 + 0xFE)
  end),

  -- --------------- 2. a priced verb executes and charges, naturally --
  menuFor(EDGAR, "edgar_menu"),
  H.waitFrames(30),
  H.call(function()
    costs = {}
    edgarPre = H.readWord(CURMP(slotOf[EDGAR]))
    hpsumPre = monsterHpSum()
    H.log(string.format("[edgar pre] MP=%d hpsum=%d", edgarPre, hpsumPre))
  end),
  tap("down", 20),                        -- Fight -> Tools (row 1, cmd $09)
  tap("a", 60),                           -- the Tools submenu opens
  -- steer to AutoCrossbow wherever MakeToolsList put it.  wItemList holds
  -- 3-byte records (id, usage flags, targeting; measured live, for example
  -- { A4 01 6A  A3 01 6A  AA 01 6A }); the drawn grid is 2 columns,
  -- row-major, so tool index i sits at row i//2, column i%2.
  H.call(function()
    H.log(string.format("[edgar] mstate=%02X after Tools A", H.readByte(0x7BC2)))
    local list, idx = {}, nil
    for i = 0, 7 do
      local id = H.readByte(ITEMLIST + i * 3)
      list[#list + 1] = string.format("%02X", id)
      if id == 0xFF then break end            -- end of the packed list
      if id == AUTOCROSSBOW and not idx then idx = i end
    end
    H.log("[edgar] tool ids = { " .. table.concat(list, " ") .. " }")
    assert(idx, "AutoCrossbow in the tools list")
    H.log(string.format("[edgar] AutoCrossbow at tools index %d", idx))
    H.vars.xbowRow, H.vars.xbowRight = math.floor(idx / 2), (idx % 2) == 1
    H.screenshot("naturalmp_tools_open")
  end),
  H.cond(function() return H.vars.xbowRight end, { tap("right", 16) }, {}),
  (function()
    local steps = {}
    for _ = 1, 3 do
      steps[#steps + 1] = H.cond(function()
        if (H.vars.xbowSteps or 0) < H.vars.xbowRow then
          H.vars.xbowSteps = (H.vars.xbowSteps or 0) + 1
          return true
        end
        return false
      end, { tap("down", 16) }, {})
    end
    return H.repeatN(1, steps)
  end)(),
  tap("a", 30),                           -- pick AutoCrossbow
  tap("a", 30),                           -- confirm target
  H.waitFrames(400),
  H.call(function()
    local after, hpsum = H.readWord(CURMP(slotOf[EDGAR])), monsterHpSum()
    local c = {}
    for _, v in ipairs(costs) do c[#c + 1] = string.format("%d", v) end
    H.log(string.format(
      "[edgar autocrossbow] MP %d -> %d, hpsum %d -> %d (dmg %d), costq={%s}",
      edgarPre, after, hpsumPre, hpsum, hpsumPre - hpsum, table.concat(c, ",")))
    H.assertEq(costs[1], XBOW_COST,
      "Ot6AbilityCost priced the AutoCrossbow at 4 MP")
    H.assertEq(after, edgarPre - XBOW_COST,
      "the AutoCrossbow charged exactly its price from NATURAL MP "
      .. "(pre-fix: the 0/0 fizzle charges nothing)")
    H.assertEq(hpsumPre - hpsum > 0, true,
      "the AutoCrossbow dealt damage (pre-fix: the fizzle deals nothing)")
    H.screenshot("naturalmp_xbow_resolved")
  end),

  -- ----------------------------------- 3. writeback: field MP correct --
  -- End the fight the way a player can, by fleeing with held L+R.  The
  -- clearBattle flag write this replaces ended by forced victory; the flee
  -- exit runs the same character writeback, and asserting on it here means the
  -- writeback guard covers the exit path a real escape takes.
  H.fleeBattle(12000),
  H.waitFrames(120),
  H.call(function()
    for s = 0, 3 do
      if charOfs[s] then
        local want = fieldPre[s] - (s == slotOf[EDGAR] and XBOW_COST or 0)
        local now = H.readWord(0x160d + charOfs[s])
        H.log(string.format("[writeback slot %d] field MP %d -> %d", s,
          fieldPre[s], now))
        H.assertEq(now, want,
          "post-battle field MP = pre-battle minus exactly what was spent")
      end
    end
  end),

  H.logStep(function() return "battle_naturalmp complete" end),
})
