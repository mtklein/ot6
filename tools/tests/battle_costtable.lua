-- @suite savestate=gau_joined
-- battle_costtable.lua -- the test for the MP rescale: the kit cost
-- columns are pinned, and checked against the baseline recomputed from
-- this ROM's own tables rather than from numbers copied into a test.
--
-- What it asserts, all derived from the ROM:
--   1. Ot6AbilityCostTbl is exactly the shipped 24-row column, $ff-terminated.
--   2. the baseline. For every Blitz and SwdTech row, cost as a fraction of
--      the caster's real max MP at the level the row is reachable stays
--      inside 4%..25% (vanilla natural magic measured the same way runs
--      7.5%..20.3%). Pool = CharProp+$01 ("starting mp") plus the
--      LevelUpMP running sum (InitMaxMP); levels are BlitzLevelTbl and
--      BushidoLevelTbl.
--   2b. the 99 anchor. Each ladder's ultimate (Bum Rush and Cleave) costs
--      exactly 99, and no row anywhere costs more than 99: every OT6 price
--      drawer renders two digits, so a three-digit cost would print as
--      punctuation.
--   3. payability. Every row affords at least 4 uses from a full pool at
--      the level it becomes available.
--   3b. Steal. The one costed verb with no table row: Steal is flat,
--      priced by the Ot6StealCost leaf, read at the source and held to the
--      same baseline against the pool Locke joins with (LV6, 31 MP).
--   4. the magic MP column. MagicProp is spliced in battle_main.asm and
--      OT6 owns exactly one byte of that column (Osmose, 1 -> 8), pinned
--      literally like step 1. The chain: battle init seeds each spell-list
--      row's cost from MagicProp+5 through _c25723; ValidateSpellList runs
--      it through CalcMPCost for the caster's relics; GetMPCost reads the
--      row back at queue time; CreateAction banks it into $3620;
--      InitPlayerAction stages it into $3a4c; CalcAttackEffect subtracts
--      it from $3c08.
--   5. the Serpent-Trench section. gau_joined is the entry point
--      gen_sabin_trench.lua boots from, so the trio's pools are read live
--      out of the fixture and every ability each has learned at that
--      level is checked for uses-per-pool. Gau's Rage price is read too
--      (Ot6DanceCost's immediate, which Ot6RageCost tail-calls).
--
-- Fixture-free by design apart from step 5: steps 1-4 need no savestate, so
-- this test keeps working if the chain of generated savestates is stale.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/gau_joined.mss.lua"

local CHAR = { Locke = 1, Cyan = 2, Sabin = 5, Gau = 11 }
local CHARPROP_SIZE, CHARPROP_MP = 0x16, 0x01
local REC, REC_SIZE = 0x1600, 37
local REC_LEVEL, REC_MAXMP = 0x08, 0x0f

local LO, HI = 4.0, 25.0        -- the baseline brackets, in percent
local MIN_USES = 4              -- payability floor, uses from a full pool

-- The shipped column, key -> cost, in table order.  Names are the ones the
-- screen prints (FF3-US; CONTRIBUTING's vocabulary rule).
local BLITZ = {
  { 0x5d,  4, "Pummel" },      { 0x5e, 10, "AuraBolt" },
  { 0x5f, 13, "Suplex" },      { 0x60, 17, "Fire Dance" },
  { 0x61, 16, "Mantra" },      { 0x62, 28, "Air Blade" },
  { 0x63, 50, "Spiraler" },    { 0x64, 99, "Bum Rush" },
}
local SWDTECH = {
  { 0x55,  4, "Dispatch" },    { 0x56, 10, "Retort" },
  { 0x57, 13, "Slash" },       { 0x58, 16, "Quadra Slam" },
  { 0x59, 18, "Empowerer" },   { 0x5a, 28, "Stunner" },
  { 0x5b, 50, "Quadra Slice" },{ 0x5c, 99, "Cleave" },
}

local ANCHOR = 99
local ULTIMATE = { [0x64] = "Bum Rush", [0x5c] = "Cleave" }
local STEAL_COST = 4
local LOCKE_JOIN_LV = 6             -- measured: worldmap_narshe has Locke LV6

local TOOLS = {                 -- unchanged by #45; pinned so that stays true
  { 0xaa,  4, "AutoCrossbow" }, { 0xa3,  6, "NoiseBlaster" },
  { 0xa4,  8, "Bio Blaster" },  { 0xa5,  6, "Flash" },
  { 0xa8, 16, "Drill" },        { 0xa6, 18, "Chain Saw" },
  { 0xa7, 10, "Debilitator" },  { 0xa9, 14, "Air Anchor" },
}

local MAGIC_MP = {
  { 0x00,  4, "Fire" },   { 0x01,  5, "Ice" },    { 0x02,  6, "Bolt" },
  { 0x03,  3, "Poison" }, { 0x04, 15, "Drain" },  { 0x05, 20, "Fire 2" },
  { 0x06, 21, "Ice 2" },  { 0x07, 22, "Bolt 2" }, { 0x08, 26, "Bio" },
  { 0x09, 51, "Fire 3" }, { 0x0a, 52, "Ice 3" },  { 0x0b, 53, "Bolt 3" },
  { 0x0c, 25, "Break" },  { 0x0d, 35, "Doom" },   { 0x0e, 40, "Pearl" },
  { 0x0f, 45, "Flare" },  { 0x10, 33, "Demi" },   { 0x11, 48, "Quartr" },
  { 0x12, 53, "X-Zone" }, { 0x13, 62, "Meteor" }, { 0x14, 80, "Ultima" },
  { 0x15, 50, "Quake" },  { 0x16, 75, "W Wind" }, { 0x17, 85, "Merton" },
  { 0x18,  3, "Scan" },   { 0x19,  5, "Slow" },   { 0x1a, 12, "Rasp" },
  { 0x1b,  8, "Mute" },   { 0x1c, 12, "Safe" },   { 0x1d,  5, "Sleep" },
  { 0x1e,  8, "Muddle" }, { 0x1f, 10, "Haste" },  { 0x20, 10, "Stop" },
  { 0x21, 16, "Bserk" },  { 0x22, 17, "Float" },  { 0x23, 10, "Imp" },
  { 0x24, 22, "Rflect" }, { 0x25, 15, "Shell" },  { 0x26, 18, "Vanish" },
  { 0x27, 38, "Haste2" }, { 0x28, 26, "Slow 2" }, { 0x29,  8, "Osmose" },
  { 0x2a, 20, "Warp" },   { 0x2b, 99, "Quick" },  { 0x2c, 25, "Dispel" },
  { 0x2d,  5, "Cure" },   { 0x2e, 25, "Cure 2" }, { 0x2f, 40, "Cure 3" },
  { 0x30, 30, "Life" },   { 0x31, 60, "Life 2" }, { 0x32,  3, "Antdot" },
  { 0x33, 15, "Remedy" }, { 0x34, 10, "Regen" },  { 0x35, 50, "Life 3" },
}
local MAGIC_PROP_REC = 14
local MAGIC_PROP_MP = 5
local MAGIC_OT6 = { [0x29] = 1 }        -- id -> the vanilla byte OT6 replaced
local SCAN_ID, SCAN_MP = 0x18, 3

-- ca65 symbol -> snesPrgRom file offset (banks $C0-$FF are HiROM).
-- Note: compose.py scrapes literal H.sym(...) calls out of this script to build
-- OT6_SYMS, so every symbol name must appear spelled out at a call site;
-- passing one through a variable resolves to nothing.
local function romOfs(addr) return addr & 0x3FFFFF end

-- pool(charId, level) exactly as InitMaxMP builds it.
local levelUpMp, charProp
local function pool(id, level)
  local mp = H.readRomByte(charProp + id * CHARPROP_SIZE + CHARPROP_MP)
  for i = 0, level - 2 do mp = mp + H.readRomByte(levelUpMp + i) end
  return mp
end

local function learnLevels(addr)
  local t, b = {}, romOfs(addr)
  for i = 0, 7 do t[i + 1] = H.readRomByte(b + i) end
  return t
end

H.run({ maxFrames = 20000 }, {
  ------------------------------------------------------- 1. pin the column --
  H.call(function()
    local base = romOfs(H.sym("Ot6AbilityCostTbl"))
    local want = {}
    for _, r in ipairs(BLITZ)   do want[#want + 1] = r end
    for _, r in ipairs(SWDTECH) do want[#want + 1] = r end
    for _, r in ipairs(TOOLS)   do want[#want + 1] = r end
    for i, r in ipairs(want) do
      local o = base + (i - 1) * 2
      H.assertEq(H.readRomByte(o), r[1],
        string.format("row %d key (%s)", i, r[3]))
      H.assertEq(H.readRomByte(o + 1), r[2],
        string.format("%s costs %d MP", r[3], r[2]))
    end
    H.assertEq(H.readRomByte(base + #want * 2), 0xff,
      "the column is $ff-terminated right after the last Tools row")
  end),

  H.call(function()
    local base = romOfs(H.sym("Ot6AbilityCostTbl"))
    -- Walk the live table rather than the pinned literals above: the ceiling
    -- has to hold for whatever is in the ROM, including any row a
    -- future pass adds that the pin block does not yet know about.
    local seen, rows = {}, 0
    for i = 0, 63 do
      local key = H.readRomByte(base + i * 2)
      if key == 0xff then break end
      local cost = H.readRomByte(base + i * 2 + 1)
      rows, seen[key] = rows + 1, cost
      assert(cost <= ANCHOR, string.format(
        "row %d (key $%02x) costs %d -- above the %d ceiling. That is a "
        .. "DISPLAY break, not a taste question: every OT6 price drawer "
        .. "renders two digits (ListText cmd $02, btlgfx_main.asm:15045; "
        .. "Ot6LoadoutDrawCost, field_menu.asm:3053), so this prints as "
        .. "punctuation on the menu, not as a big number", i + 1, key, cost,
        ANCHOR))
    end
    H.assertEq(rows, 24, "the live table still has 24 rows")
    for key, name in pairs(ULTIMATE) do
      H.assertEq(seen[key], ANCHOR, string.format(
        "%s ($%02x) is a designated ultimate and must cost exactly %d (#57)",
        name, key, ANCHOR))
    end
    -- The anchor is the top: no non-ultimate row may tie it, or "99 means
    -- ultimate" stops being readable off the menu.
    for key, cost in pairs(seen) do
      if not ULTIMATE[key] then
        assert(cost < ANCHOR, string.format(
          "row $%02x costs %d, tying the anchor -- 99 is meant to say "
          .. "'this is the ultimate', which it cannot if a mid-kit row "
          .. "wears it too", key, cost))
      end
    end
    H.log(string.format("anchor: Bum Rush and Cleave at %d; %d rows all <= %d",
      ANCHOR, rows, ANCHOR))
  end),

  ---------------------------------------- 2/3. the baseline + payability ---
  H.call(function()
    levelUpMp = romOfs(H.sym("LevelUpMP"))
    charProp  = romOfs(H.sym("CharProp"))
    H.assertEq(pool(CHAR.Cyan, 11), 67, "pool model: Cyan LV11 max MP")
    H.assertEq(pool(CHAR.Sabin, 15), 104, "pool model: Sabin LV15 max MP")

    local kits = {
      { name = "Blitz",   id = CHAR.Sabin, rows = BLITZ,
        levels = learnLevels(H.sym("BlitzLevelTbl")) },
      { name = "SwdTech", id = CHAR.Cyan,  rows = SWDTECH,
        levels = learnLevels(H.sym("BushidoLevelTbl")) },
    }
    local JOIN = 10
    for _, kit in ipairs(kits) do
      for i, r in ipairs(kit.rows) do
        local lv = math.max(kit.levels[i], JOIN)
        local p = pool(kit.id, lv)
        local pct = 100 * r[2] / p
        H.log(string.format("%-8s %-13s L%-3d pool %4d  %2d MP  %5.1f%%  %d uses",
          kit.name, r[3], kit.levels[i], p, r[2], pct, math.floor(p / r[2])))
        assert(pct >= LO, string.format(
          "%s %s is %.1f%% of the LV%d pool (%d MP of %d) -- under the %.0f%% "
          .. "floor: at that price the ability is free in practice and Fight "
          .. "never has a case (mp-economy.md's stated target)",
          kit.name, r[3], pct, lv, r[2], p, LO))
        assert(pct <= HI, string.format(
          "%s %s is %.1f%% of the LV%d pool (%d MP of %d) -- over the %.0f%% "
          .. "ceiling: dearer than any vanilla spell at the level it is learned",
          kit.name, r[3], pct, lv, r[2], p, HI))
        assert(math.floor(p / r[2]) >= MIN_USES, string.format(
          "%s %s affords only %d uses from a full LV%d pool", kit.name, r[3],
          math.floor(p / r[2]), lv))
      end
    end
    H.log("ruler + payability hold for all 16 kit rows")
  end),

  H.call(function()
    local ofs = romOfs(H.sym("Ot6StealCost"))
    H.assertEq(H.readRomByte(ofs), 0xa9,
      "Ot6StealCost still opens with LDA #imm -- the +1 read below is the price")
    local steal = H.readRomByte(ofs + 1)
    H.assertEq(steal, STEAL_COST, "Steal costs " .. STEAL_COST .. " MP (#52)")

    local p = pool(CHAR.Locke, LOCKE_JOIN_LV)
    H.assertEq(p, 31, "pool model: Locke LV" .. LOCKE_JOIN_LV .. " max MP")
    local pct = 100 * steal / p
    H.log(string.format("Steal   %2d MP of Locke's LV%d pool %d -> %.1f%%, %d uses",
      steal, LOCKE_JOIN_LV, p, pct, math.floor(p / steal)))
    assert(pct >= LO and pct <= HI, string.format(
      "Steal is %.1f%% of the LV%d pool (%d MP of %d) -- outside the %.0f-%.0f%% "
      .. "ruler at the level Locke actually joins with it. Under the floor it "
      .. "is the free-in-practice noise #45 existed to remove; over the ceiling "
      .. "it rations the only verb Locke has until #55 builds his kit",
      pct, LOCKE_JOIN_LV, steal, p, LO, HI))
    assert(math.floor(p / steal) >= MIN_USES, string.format(
      "Steal affords only %d uses from Locke's full LV%d pool",
      math.floor(p / steal), LOCKE_JOIN_LV))

    local base = romOfs(H.sym("Ot6AbilityCostTbl"))
    for _, sig in ipairs({ { 0x5d, "Pummel" }, { 0x55, "Dispatch" },
                           { 0xaa, "AutoCrossbow" } }) do
      for i = 0, 63 do
        local key = H.readRomByte(base + i * 2)
        if key == 0xff then break end
        if key == sig[1] then
          H.assertEq(H.readRomByte(base + i * 2 + 1), steal, string.format(
            "%s is a kit signature and must cost the same as Steal (%d) -- "
            .. "mp-economy.md's 'signatures become the cheapest rows of their "
            .. "kits'", sig[2], steal))
          break
        end
      end
    end
    H.log("Steal is at parity with Pummel / Dispatch / AutoCrossbow")
  end),

  H.call(function()
    local base = romOfs(H.sym("MagicProp"))
    local ot6, checked = 0, 0
    for _, r in ipairs(MAGIC_MP) do
      local got = H.readRomByte(base + r[1] * MAGIC_PROP_REC + MAGIC_PROP_MP)
      H.assertEq(got, r[2], string.format(
        "%s ($%02x) publishes %d MP", r[3], r[1], r[2]))
      checked = checked + 1
      if MAGIC_OT6[r[1]] then ot6 = ot6 + 1 end
    end
    -- Guard the guard.  A base that resolved somewhere harmless would let the
    -- loop above agree with itself: the record after the last pinned spell is
    -- Ramuh's summon ($36), whose price is not in the pinned range, and the
    -- one OT6-authored byte must read as authored rather than as vanilla.
    H.assertEq(checked, 54, "all 54 published spell prices were read")
    H.assertEq(ot6, 1, "exactly one price in this column is OT6's")
    H.assertEq(H.readRomByte(base + 0x29 * MAGIC_PROP_REC + MAGIC_PROP_MP)
               ~= MAGIC_OT6[0x29], true,
      "Osmose no longer carries its vanilla 1 -- the splice is live, so this "
      .. "column is MagicProp and not an untouched copy of the .dat")
    H.assertEq(H.readRomByte(base + 0x36 * MAGIC_PROP_REC + MAGIC_PROP_MP), 25,
      "the record past the pinned range is Ramuh at 25 MP -- the stride and "
      .. "the base both land where they should")

    H.assertEq(H.readRomByte(base + SCAN_ID * MAGIC_PROP_REC + MAGIC_PROP_MP),
      SCAN_MP, string.format(
        "Scan ($%02x) publishes %d MP, and that is also what it charges: "
        .. "every magic charge is this byte, seeded into the caster's list by "
        .. "ValidateSpellList and read back by GetMPCost (see the header). "
        .. "Issue #76 reported Scan charging 0; the measurement behind it used "
        .. "spell id $32 (Antdot), not $18", SCAN_ID, SCAN_MP))
    H.log(string.format("magic: %d published prices pinned (%d authored by "
      .. "OT6); Scan = %d", checked, ot6, SCAN_MP))
  end),

  --------------------------------------- 5. the Serpent-Trench section -----
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.call(function()
    local blitzLv = learnLevels(H.sym("BlitzLevelTbl"))
    local swdLv   = learnLevels(H.sym("BushidoLevelTbl"))
    local trio = {
      { who = "Sabin", id = CHAR.Sabin, rows = BLITZ,   levels = blitzLv },
      { who = "Cyan",  id = CHAR.Cyan,  rows = SWDTECH, levels = swdLv },
    }
    for _, m in ipairs(trio) do
      local b = REC + REC_SIZE * m.id
      local lv = H.readByte(b + REC_LEVEL)
      local mp = H.readWord(b + REC_MAXMP)
      H.assertEq(mp, pool(m.id, lv),
        m.who .. "'s fixture pool matches the derived model at LV" .. lv)
      local worst, worstName = 0, "?"
      for i, r in ipairs(m.rows) do
        if m.levels[i] <= lv then
          H.log(string.format("trench  %-5s %-13s %2d MP of %d  -> %d uses",
            m.who, r[3], r[2], mp, math.floor(mp / r[2])))
          if r[2] > worst then worst, worstName = r[2], r[3] end
        end
      end
      assert(worst > 0, m.who .. " has learned no priced ability at LV" .. lv)
      local uses = math.floor(mp / worst)
      assert(uses >= MIN_USES, string.format(
        "at the Serpent-Trench area %s (LV%d, %d MP) affords only %d uses of "
        .. "his dearest learned ability (%s, %d MP) -- the rescale has turned "
        .. "an 'intense, barely made it' fight into an unanswerable one",
        m.who, lv, mp, uses, worstName, worst))
      H.log(string.format("trench  %s LV%d pool %d: %d uses of %s (dearest)",
        m.who, lv, mp, uses, worstName))
    end
    local rage = H.readRomByte(romOfs(H.sym("Ot6DanceCost")) + 1)
    H.assertEq(rage, 8, "the possess-verb price (Dance/Rage) is unchanged at 8")
    local gb = REC + REC_SIZE * CHAR.Gau
    local gmp = H.readWord(gb + REC_MAXMP)
    H.log(string.format("trench  Gau LV%d pool %d: %d Rages",
      H.readByte(gb + REC_LEVEL), gmp, math.floor(gmp / rage)))
    assert(math.floor(gmp / rage) >= MIN_USES,
      "Gau cannot afford " .. MIN_USES .. " Rages at the trench area")
  end),
  H.logStep(function() return "battle_costtable complete" end),
})
