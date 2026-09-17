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
--   4b. the boosted column (#219). Every priced row is a BASE price; a
--      boosted use of an escalating verb costs
--      min(99, floor(base * 2.5^boost + 0.5)). The whole table is
--      recomputed from this ROM's own base column and held to the
--      rulings the design locks: the 99 cap, the flattening it causes
--      for dear rows, Bum Rush already sitting at the cap, and the
--      exempt columns -- the eight SwdTech rows, Steal and Rage -- held
--      flat across all four levels. The ceiling constant is read out of
--      Ot6BoostPriceFor itself, so a ROM that capped somewhere else
--      fails here rather than in a play test.
--   4c. WHO reaches the escalation, disassembled out of the built ROM
--      rather than declared in this script. The design rule is one test:
--      a verb's price escalates exactly when Ot6BoostDmg multiplies it.
--      Ot6BoostDmg's gate names fight $00, capture $06, bushido $07,
--      steal $05, slot $0f and rage $10, so exactly two of
--      Ot6AbilityCost's own arms may reach Ot6BoostPriceFor -- @dance
--      and @boosted -- and the Steal, Rage and SwdTech arms may not.
--      This step finds each leaf call in the proc's byte range and asks
--      whether the escalation follows it, so re-adding the call to a
--      chance verb fails here and not only in a play test.
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

  ------------------------------------------ 4b. the boosted column (#219) --
  H.call(function()
    -- The one arithmetic authority is Ot6BoostPriceFor (ot6_boost.asm):
    --   price = min(99, floor(base * 2.5^boost + 0.5))
    -- exact in integers as (base * 5^n + 2^(n-1)) >> n.  Recomputed here
    -- rather than copied, so it is checkable against the base column this
    -- ROM really ships.
    local function boosted(b, n)
      if n == 0 then return b end
      local x = b
      for _ = 1, n do x = x * 5 end
      x = (x + (1 << (n - 1))) >> n
      return math.min(ANCHOR, x)
    end

    -- The ceiling lives in the ROM, not in this script: Ot6BoostPriceFor
    -- ends its scale arm with `cmp #100 / bcc + / lda #99` under a 16-bit
    -- accumulator, so the immediates are C9 64 00 / 90 xx / A9 63 00.
    local pf, capAt = romOfs(H.sym("Ot6BoostPriceFor")), nil
    for i = 0, 0x7f do
      if H.readRomByte(pf + i) == 0xc9 and H.readRomByte(pf + i + 1) == 0x64
         and H.readRomByte(pf + i + 2) == 0x00
         and H.readRomByte(pf + i + 3) == 0x90
         and H.readRomByte(pf + i + 5) == 0xa9 then
        capAt = pf + i + 6
        break
      end
    end
    H.assertEq(capAt ~= nil, true,
      "Ot6BoostPriceFor still ends its scale arm with `cmp #100 / bcc / "
      .. "lda #imm` -- the ceiling is read out of the ROM below, so a "
      .. "rewritten tail has to be re-read here rather than assumed")
    H.assertEq(H.readRomByte(capAt), ANCHOR, string.format(
      "the boosted-price ceiling in the ROM is %d.  It is a DISPLAY bound, "
      .. "not a taste question: the price drawers render two digits, so a "
      .. "boosted price over %d prints as punctuation (#219, ruling 1)",
      ANCHOR, ANCHOR))

    -- Steal and the possess verbs are leaves, not table rows; read their
    -- immediates at the source the same way step 3b does.  Rage tail-calls
    -- Ot6DanceCost, so the two possess verbs share one base and differ only
    -- in whether it escalates -- which makes them the sharpest pair in the
    -- table for the rule below.
    local steal = H.readRomByte(romOfs(H.sym("Ot6StealCost")) + 1)
    local dance = H.readRomByte(romOfs(H.sym("Ot6DanceCost")) + 1)
    -- Ot6RageCost is `jmp Ot6DanceCost`, not an immediate of its own, so
    -- read the jump and follow it rather than reading a +1 that would be an
    -- operand byte.
    local rageOfs, danceAddr = romOfs(H.sym("Ot6RageCost")), H.sym("Ot6DanceCost")
    H.assertEq(H.readRomByte(rageOfs), 0x4c,
      "Ot6RageCost is still a JMP (its price is Dance's, tail-called)")
    H.assertEq(H.readRomByte(rageOfs + 1) | (H.readRomByte(rageOfs + 2) << 8),
      danceAddr & 0xffff,
      "...and the JMP still lands on Ot6DanceCost, so Rage's base IS Dance's")
    local rage = dance
    -- Which columns escalate is the design's own split, not a free choice,
    -- and it is ONE test: a price escalates exactly when Ot6BoostDmg
    -- multiplies the action.  Blitz ($0a), Tools ($09) and Dance ($13) are
    -- outside that gate, so they take the 2.5x.  SwdTech ($07), Steal ($05)
    -- and Rage ($10) are inside it, so they are flat at every level: the
    -- tech's boost was already spent picking the row, and Steal's and Rage's
    -- boost buys certainty across a spread of outcomes rather than
    -- magnitude, which the BP already pays for.  Step 4c reads that split
    -- back off the ROM rather than trusting this table.
    local rows = {}
    for _, kit in ipairs({ { "Blitz", BLITZ, true }, { "SwdTech", SWDTECH, false },
                           { "Tools", TOOLS, true } }) do
      for _, r in ipairs(kit[2]) do
        rows[#rows + 1] = { kit[1], r[3], r[1], nil, kit[3] }
      end
    end
    rows[#rows + 1] = { "Steal", "Steal", nil, steal, false }
    rows[#rows + 1] = { "Possess", "Dance", nil, dance, true }
    rows[#rows + 1] = { "Possess", "Rage", nil, rage, false }

    local tbl = romOfs(H.sym("Ot6AbilityCostTbl"))
    local function liveCost(key)
      for i = 0, 63 do
        local k = H.readRomByte(tbl + i * 2)
        if k == 0xff then return nil end
        if k == key then return H.readRomByte(tbl + i * 2 + 1) end
      end
    end
    local WHYFLAT = {
      SwdTech = "its boost bought the row, and the row is charged at its "
             .. "own price (cmd $07 is in Ot6BoostDmg's gate)",
      Steal   = "cmd $05 is in Ot6BoostDmg's gate: the boost buys the "
             .. "rare/guarantee ladder, not a multiplier, and the BP pays "
             .. "for that certainty",
      Rage    = "cmd $10 is in Ot6BoostDmg's gate: the boost buys the "
             .. "trance's coin, not a multiplier, and the BP pays for it",
    }
    local atCap, exempt, flatKinds = 0, 0, {}
    for _, r in ipairs(rows) do
      local b = r[4] or liveCost(r[3])
      H.assertEq(b ~= nil and b > 0, true, r[2] .. " has a base price")
      local c = {}
      for n = 0, 3 do c[n + 1] = r[5] and boosted(b, n) or b end
      H.log(string.format("boost   %-8s %-13s %3d %3d %3d %3d%s",
        r[1], r[2], c[1], c[2], c[3], c[4], r[5] and "" or "   (flat)"))
      H.assertEq(c[1], b, r[2] .. ": boost 0 is the base price, untouched")
      if not r[5] then
        exempt = exempt + 1
        local kind = WHYFLAT[r[2]] and r[2] or r[1]
        flatKinds[kind] = (flatKinds[kind] or 0) + 1
        for i = 2, 4 do
          H.assertEq(c[i], b, string.format(
            "%s at boost %d still costs its base %d -- %s", r[2], i - 1, b,
            WHYFLAT[kind]))
        end
      end
      for i = 2, 4 do
        assert(c[i] <= ANCHOR, string.format(
          "%s at boost %d costs %d -- above the %d ceiling; every OT6 price "
          .. "drawer renders two digits", r[2], i - 1, c[i], ANCHOR))
        assert(c[i] >= c[i - 1], string.format(
          "%s costs %d at boost %d but %d at boost %d -- a dearer boost must "
          .. "never be cheaper", r[2], c[i], i - 1, c[i - 1], i - 2))
      end
      if b == ANCHOR and r[5] then
        atCap = atCap + 1
        H.assertEq(c[4], ANCHOR, r[2] .. " is already at the cap and stays "
          .. "there at every boost (#219, ruling 1: accepted, not a bug)")
      end
    end
    H.assertEq(exempt, 10, "ten rows are exempt from the escalation")
    H.assertEq(flatKinds.SwdTech, 8, "the eight SwdTech rows are flat")
    H.assertEq(flatKinds.Steal, 1,
      "Steal is flat -- the chance-verb exemption, and NOT merely unasserted: "
      .. "at boost 3 it costs 4 and not 63")
    H.assertEq(flatKinds.Rage, 1,
      "Rage is flat -- the same exemption, and the sharpest case in the table: "
      .. "Rage and Dance share one base (Ot6RageCost tail-calls Ot6DanceCost), "
      .. "so 8 / 8 / 8 / 8 against Dance's 8 / 20 / 50 / 99 is the whole rule "
      .. "in one pair of rows")
    H.assertEq(atCap, 1,
      "one escalating row (Bum Rush) ships at the cap and therefore never "
      .. "moves; Cleave is the other, and it is exempt for a different reason")

    -- The points the design names by number, so a rounding change cannot
    -- pass unnoticed.
    H.assertEq(boosted(4, 1), 10, "4 MP at boost 1 is 10 (4 x 2.5)")
    H.assertEq(boosted(4, 2), 25, "4 MP at boost 2 is 25 (4 x 6.25)")
    H.assertEq(boosted(4, 3), 63,
      "4 MP at boost 3 is 63 (62.5, rounded half up)")
    H.assertEq(boosted(50, 1), ANCHOR,
      "Spiraler's 50 hits the cap at boost 1 -- the named consequence of "
      .. "ruling 1")
    H.assertEq(boosted(15, 2), 94,
      "Drain's 15 at boost 2 is 94 (93.75, rounded half up)")
    H.log(string.format("boosted column: %d priced rows recomputed and held "
      .. "to the %d cap", #rows, ANCHOR))
  end),

  ------------------------------- 4c. who reaches the escalation, off the ROM --
  H.call(function()
    -- The split in 4b is a table in a Lua script, and a Lua script agrees
    -- with itself for free.  This step asks the assembled bytes instead.
    --
    -- The design rule is one test: a price escalates exactly when
    -- Ot6BoostDmg multiplies the action.  Ot6BoostDmg's gate names fight
    -- $00, capture $06, bushido $07, steal $05, slot $0f and rage $10, so in
    -- Ot6AbilityCost exactly the @dance and @boosted arms may reach
    -- Ot6BoostPriceFor.  Each arm ends in a leaf call (Ot6StealCost,
    -- Ot6DanceCost, Ot6RageCost, Ot6CostFor), so "does this arm escalate?"
    -- is "are the four bytes after its leaf call a jsl Ot6BoostPriceFor?".
    local function jsl(addr)              -- the 4 bytes of `jsl <addr>`
      return { 0x22, addr & 0xff, (addr >> 8) & 0xff, (addr >> 16) & 0xff }
    end
    local function matches(ofs, bytes)
      for i, b in ipairs(bytes) do
        if H.readRomByte(ofs + i - 1) ~= b then return false end
      end
      return true
    end
    local function sites(lo, hi, bytes)   -- offsets of `bytes` in [lo, hi)
      local t = {}
      for o = lo, hi - #bytes do
        if matches(o, bytes) then t[#t + 1] = o end
      end
      return t
    end

    local PRICE = jsl(H.sym("Ot6BoostPriceFor"))
    local acLo = romOfs(H.sym("Ot6AbilityCost"))
    local acHi = romOfs(H.sym("Ot6CostFor"))     -- the next proc in the file
    H.assertEq(acHi > acLo, true,
      "Ot6CostFor still follows Ot6AbilityCost, so [Ot6AbilityCost, "
      .. "Ot6CostFor) is exactly the proc's own bytes")

    local escalating = sites(acLo, acHi, PRICE)
    local function armEscalates(leaf)
      local at = sites(acLo, acHi, jsl(H.sym(leaf)))
      local hits, n = 0, #at
      for _, o in ipairs(at) do
        if matches(o + 4, PRICE) then hits = hits + 1 end
      end
      return hits, n
    end

    local sHit, sN = armEscalates("Ot6StealCost")
    H.assertEq(sN, 1, "one Ot6StealCost call in Ot6AbilityCost (the @steal arm)")
    H.assertEq(sHit, 0,
      "the @steal arm does NOT reach Ot6BoostPriceFor: cmd $05 is in "
      .. "Ot6BoostDmg's gate, so Steal is flat at every boost level.  Boost "
      .. "buys it the rare/guarantee ladder -- certainty across a spread of "
      .. "outcomes, not magnitude -- and the BP already pays for that")

    local rHit, rN = armEscalates("Ot6RageCost")
    H.assertEq(rN, 1, "one Ot6RageCost call in Ot6AbilityCost (the @rage arm)")
    H.assertEq(rHit, 0,
      "the @rage arm does NOT reach Ot6BoostPriceFor either: cmd $10 is in "
      .. "the same gate, and the boost buys the trance's coin")

    local dHit, dN = armEscalates("Ot6DanceCost")
    H.assertEq(dN, 1, "one Ot6DanceCost call in Ot6AbilityCost (the @dance arm)")
    H.assertEq(dHit, 1,
      "the @dance arm DOES reach Ot6BoostPriceFor -- cmd $13 is NOT in "
      .. "Ot6BoostDmg's gate, so a boosted Dance really is multiplied and "
      .. "really does pay 2.5x.  Dance and Rage sharing a base price is what "
      .. "makes this pair the test of the rule rather than of a habit")

    local cHit, cN = armEscalates("Ot6CostFor")
    H.assertEq(cN, 2,
      "two Ot6CostFor calls in Ot6AbilityCost: @swdtech and @boosted")
    H.assertEq(cHit, 1,
      "exactly one of them escalates -- @boosted (blitz $0a / tools $09, "
      .. "outside the gate); @swdtech ($07, inside it) does not")

    H.assertEq(#escalating, 2,
      "Ot6AbilityCost reaches the escalation from exactly 2 of its arms, "
      .. "@dance and @boosted.  That count IS the design rule: a verb's price "
      .. "escalates exactly when Ot6BoostDmg multiplies it, and #219's four "
      .. "call sites became two when the owner exempted the chance verbs")
    H.log(string.format("Ot6AbilityCost: %d escalating arms (dance %d/%d, "
      .. "boosted %d/%d); steal %d/%d and rage %d/%d flat",
      #escalating, dHit, dN, cHit, cN, sHit, sN, rHit, rN))

    -- The drawn price has to make the same split, or the menu and the charge
    -- disagree.  Ot6KitRowCost's thief arm is now one flat tail-call, so the
    -- proc holds exactly one escalation (blitz's), and Ot6ThiefListOpen's
    -- Steal row stamps a bare Ot6ThiefCost with no price call at all.
    local function jml(addr)
      return { 0x5c, addr & 0xff, (addr >> 8) & 0xff, (addr >> 16) & 0xff }
    end
    local PEND_J, PEND_L = jsl(H.sym("Ot6PendPrice")), jml(H.sym("Ot6PendPrice"))
    local krLo, krHi = romOfs(H.sym("Ot6KitRowCost")),
                       romOfs(H.sym("Ot6BushidoRowGrey"))
    local krN = #sites(krLo, krHi, PEND_J) + #sites(krLo, krHi, PEND_L)
    H.assertEq(krN, 1,
      "Ot6KitRowCost draws exactly one escalating ladder (blitz).  SwdTech "
      .. "never did, and the thief arm no longer does: all three thief rows "
      .. "take one flat tail-call now, so there is no dead per-row branch")
    local tlLo, tlHi = romOfs(H.sym("Ot6ThiefListOpen")),
                       romOfs(H.sym("Ot6ThiefIsNew"))
    local tlN = #sites(tlLo, tlHi, PEND_J) + #sites(tlLo, tlHi, PEND_L)
    H.assertEq(tlN, 0,
      "Ot6ThiefListOpen stamps no escalated price at all -- the Steal row's "
      .. "Ot6PendPrice call is gone, so the stamp, the per-draw price and the "
      .. "charge are the same flat number")
    H.log(string.format("menu side: Ot6KitRowCost %d escalating arm, "
      .. "Ot6ThiefListOpen %d", krN, tlN))
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
