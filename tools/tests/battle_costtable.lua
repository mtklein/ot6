-- @suite frontier=gau_joined
-- battle_costtable.lua -- issue #45.  The MP rescale's GATE: the kit cost
-- columns are pinned, and -- the part that matters -- they are checked against
-- the RULER the design claims they sit on, recomputed from this ROM's own
-- tables rather than from numbers copied into a test.
--
-- WHY THIS EXISTS.  mp-economy.md has always said kit skills price on "the
-- vanilla spell ruler", but nothing ever measured what that ruler is, so the
-- v0.4/v0.5 columns drifted three-to-eight times under it without any gate
-- noticing.  The owner found it by PLAYING (v0.7, LV14: Cyan holding a 96 MP
-- pool against techs costing 1/2/3, so neither MP nor BP bound him and Fight
-- had no case).  A playtest is an expensive way to learn an arithmetic fact.
--
-- WHAT IT ASSERTS, all derived, none recalled:
--   1. Ot6AbilityCostTbl is exactly the shipped 24-row column, $ff-terminated.
--      (A plain pin: a rescale must be a deliberate edit here too.)
--   2. THE RULER.  For every Blitz and SwdTech row, cost as a fraction of the
--      caster's REAL max MP at the level the row is reachable stays inside
--      4%..25%.  Pool = CharProp+$01 ("starting mp") + the LevelUpMP running
--      sum, which is literally what InitMaxMP computes (field/event.asm:1405).
--      Levels are BlitzLevelTbl / BushidoLevelTbl (event.asm:1236-1240).
--      Vanilla natural magic measured the same way runs 7.5%..20.3%, which is
--      where the 4%/25% brackets come from -- generous on both sides, so this
--      gate catches a column that has fallen OFF the scale, not one that is
--      merely tuned differently.
--   3. PAYABILITY.  Every row affords at least 4 uses from a full pool at the
--      level it becomes available -- the "top-tier abilities stay payable at
--      the level they arrive" property #45 asks for, checked rather than
--      argued.
--   4. THE SERPENT-TRENCH BAND (the knife-edge the owner reported as "barely
--      made it, intense" and which was never balance-swept).  gau_joined IS
--      that doorstep -- gen_sabin_trench.lua boots from it -- so the trio's
--      pools are read live out of the fixture and every ability each of them
--      has actually LEARNED at that level is checked for uses-per-pool.  Gau's
--      Rage price is read too (Ot6DanceCost's immediate, which Ot6RageCost
--      tail-calls), so a change to the possess-verb price shows up here.
--
-- Fixture-free by design apart from step 4: steps 1-3 need no savestate, so
-- this gate keeps working if the frontier chain is stale.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/gau_joined.mss.lua"

local CHAR = { Cyan = 2, Sabin = 5, Gau = 11 }
local CHARPROP_SIZE, CHARPROP_MP = 0x16, 0x01
local REC, REC_SIZE = 0x1600, 37
local REC_LEVEL, REC_MAXMP = 0x08, 0x0f

local LO, HI = 4.0, 25.0        -- the ruler brackets, in percent
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

-- #57: the designated ultimates, by table key.  Bum Rush and Cleave only --
-- see the header for why Tools (Overclock, unbuilt, priced as a sum) and the
-- flat verbs (Steal/Slot/Rage/Dance) do not participate.
local ANCHOR = 99
local ULTIMATE = { [0x64] = "Bum Rush", [0x5c] = "Cleave" }
local TOOLS = {                 -- unchanged by #45; pinned so that stays true
  { 0xaa,  4, "AutoCrossbow" }, { 0xa3,  6, "NoiseBlaster" },
  { 0xa4,  8, "Bio Blaster" },  { 0xa5,  6, "Flash" },
  { 0xa8, 16, "Drill" },        { 0xa6, 18, "Chain Saw" },
  { 0xa7, 10, "Debilitator" },  { 0xa9, 14, "Air Anchor" },
}

-- ca65 symbol -> snesPrgRom file offset (banks $C0-$FF are HiROM).
-- NB: compose.py scrapes LITERAL H.sym(...) calls out of this script to build
-- OT6_SYMS, so every symbol name must appear spelled out at a call site --
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

  --------------------------------------------- 2b. the 99 anchor (#57) -----
  H.call(function()
    local base = romOfs(H.sym("Ot6AbilityCostTbl"))
    -- Walk the LIVE table rather than the pinned literals above: the ceiling
    -- has to hold for whatever is actually in the ROM, including any row a
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
    -- The anchor is the TOP: no non-ultimate row may tie it, or "99 means
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

  ------------------------------------------- 2/3. the ruler + payability ---
  H.call(function()
    levelUpMp = romOfs(H.sym("LevelUpMP"))
    charProp  = romOfs(H.sym("CharProp"))
    -- cross-check the pool model against two numbers measured on real saves
    -- (probe_mppools: Cyan LV11 = 67, Sabin LV15 = 104).  If this trips, the
    -- model below is wrong and every percentage under it is meaningless.
    H.assertEq(pool(CHAR.Cyan, 11), 67, "pool model: Cyan LV11 max MP")
    H.assertEq(pool(CHAR.Sabin, 15), 104, "pool model: Sabin LV15 max MP")

    local kits = {
      { name = "Blitz",   id = CHAR.Sabin, rows = BLITZ,
        levels = learnLevels(H.sym("BlitzLevelTbl")) },
      { name = "SwdTech", id = CHAR.Cyan,  rows = SWDTECH,
        levels = learnLevels(H.sym("BushidoLevelTbl")) },
    }
    -- Rows 1-2 are "learned" at levels 1 and 6, but neither character can be
    -- in the party that early -- both join around LV10-11 on the honest chain
    -- (measured: gau_joined has Cyan 11 / Sabin 11).  Pricing them against a
    -- LV1 pool would be arithmetic about a state the game cannot reach, so the
    -- reachable level is clamped up to the earliest join band.
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

  ------------------------------------------ 4. the Serpent-Trench band -----
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
        "at the Serpent-Trench band %s (LV%d, %d MP) affords only %d uses of "
        .. "his dearest learned ability (%s, %d MP) -- the rescale has turned "
        .. "an 'intense, barely made it' fight into an unanswerable one",
        m.who, lv, mp, uses, worstName, worst))
      H.log(string.format("trench  %s LV%d pool %d: %d uses of %s (dearest)",
        m.who, lv, mp, uses, worstName))
    end
    -- Gau rides the trench too; his verb is Rage, priced by Ot6DanceCost's
    -- immediate (Ot6RageCost tail-calls it -- "possess-verbs share one flat
    -- price", ot6_boost.asm).  Untouched by #45, and pinned so that shows.
    local rage = H.readRomByte(romOfs(H.sym("Ot6DanceCost")) + 1)
    H.assertEq(rage, 8, "the possess-verb price (Dance/Rage) is unchanged at 8")
    local gb = REC + REC_SIZE * CHAR.Gau
    local gmp = H.readWord(gb + REC_MAXMP)
    H.log(string.format("trench  Gau LV%d pool %d: %d Rages",
      H.readByte(gb + REC_LEVEL), gmp, math.floor(gmp / rage)))
    assert(math.floor(gmp / rage) >= MIN_USES,
      "Gau cannot afford " .. MIN_USES .. " Rages at the trench band")
  end),
  H.logStep(function() return "battle_costtable complete" end),
})
