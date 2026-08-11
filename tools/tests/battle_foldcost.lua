-- @suite
-- battle_foldcost.lua -- issue #64's BASELINE, recomputed from this ROM.
-- (school.lua / battle_breaktbl pattern: pure ROM bytes, no savestate.)
--
--   tools/tests/run.sh tools/tests/battle_foldcost.lua
--
-- #64 made a boost-folded spell cost the TIER's real MP instead of the base
-- spell's.  The live half of that -- what the queue actually charges -- is
-- battle_fold.lua's.  This is the arithmetic half, and it exists because #45
-- taught us that an unmeasured price scale drifts for three releases and is
-- then found by the owner PLAYING rather than by a test.
--
-- Every number below is read out of the shipped ROM: the family table is
-- Ot6FoldTbl (ot6_boost.asm), the costs are MagicProp+5 -- the very byte
-- Ot6SpellMP reads -- the learn levels are NaturalMagic (field/event.asm:1245)
-- and the pools are CharProp+$01 plus the LevelUpMP running sum, which is what
-- InitMaxMP computes.  Nothing is copied in except the eight family names and
-- the two design constants.
--
-- WHAT IT ASSERTS
--
--   1. THE FAMILY TABLE IS THE SHIPPED ONE.  8 rows x [base, +1, +2], pinned
--      by spell id, so a retune of which tier a boost reaches is a deliberate
--      edit here too.  The shallow families repeat their second entry on
--      purpose (Poison/Life/Slow/Haste have no third tier in vanilla), so a
--      3-BP spend is never dead -- asserted, not assumed.
--
--   2. MONOTONIC.  Within a family, cost(+2) >= cost(+1) >= cost(base).  This
--      is the anti-regression for #64 itself: the bug was that boost made a
--      spell strictly CHEAPER per point of power, and any future table where a
--      higher tier undercuts a lower one re-opens it.
--
--   3. THE 99 CEILING (#57).  No folded tier may cost more than 99.  Same
--      reason battle_costtable asserts it on the kit column: every OT6 price
--      drawer renders two digits (ListText cmd $02, btlgfx_main.asm:15045-73),
--      so 100 prints as punctuation.  Measured headroom today: the dearest
--      folded tier is Life 2 at 60.
--
--   4a. THE FOLD STILL BUYS SOMETHING.  This is the assertion that would have
--      caught #64 going too far, and it is the one worth having.  Folding is
--      source-agnostic, so a tier is REACHABLE the moment the base spell is
--      known and 2 BP are banked -- which is a character's second action of
--      their first battle (open with 1 BP, +1 a turn: DESIGN.md).  Charging
--      the tier's real MP does not change reachability, it changes
--      AFFORDABILITY: the pool has to cover the price.  So for every family
--      whose base spell is learned naturally, the level at which the folded
--      tier first becomes PAYABLE must be strictly below the level that tier
--      is LEARNED.  If it were not, real cost would have made the fold
--      worthless -- you would only afford Fire 3 after Terra had learned Fire
--      3 anyway -- and #64 would be the wrong call rather than the right one.
--
--   4b. AND MP GENUINELY BUYS THE POWER: every folded tier costs at least 2x
--      its base spell.  The complement of 4a, guarding the other direction --
--      a table where the tiers crept back toward the base price would pass 4a
--      trivially while quietly restoring the discount #64 closed.  Stated as
--      a ratio on purpose: pools cancel, so no choice of measurement level
--      can argue it away.
--
--   5. And the same numbers are LOGGED as %-of-pool at both levels, because
--      #64 asks for that comparison explicitly and a number nobody prints is
--      a number nobody checks.
--
-- Why families whose base spell is NOT natural magic (Bolt, Poison, Slow) are
-- measured at a CLAMPED level rather than skipped: they arrive by esper, which
-- is story-gated rather than level-gated, so there is no learn level to read.
-- #45 hit the same wall and set the same clamp -- L6, the earliest level the
-- party is actually presented at (kolts_doorstep) -- on the grounds that a
-- pool the game never shows is not a price anyone pays.  Those rows take part
-- in 1-3 and are logged in 5; assertion 4 needs a real learn level and says so.
local H = dofile("tools/tests/lib/ot6.lua")

local CEILING = 99              -- #57: the display and design ceiling
local CLAMP_LV = 6              -- #45's floor: the earliest level the party
                                --   is actually presented at
local MAGIC_STRIDE, MAGIC_MP = 14, 5
local CHARPROP_SIZE, CHARPROP_MP = 0x16, 0x01
local CHAR_TERRA, CHAR_CELES = 0, 6
local NAT_STRIDE, NAT_ROWS = 2, 16      -- NaturalMagic: 16 [id, level] pairs
local NAT_CELES = 0x20                  -- ...Celes's block follows Terra's

-- The eight families, in Ot6FoldTbl order.  ids are the pin; the names are
-- what the screen prints (CONTRIBUTING's vocabulary rule).
local FAMILIES = {
  { "Fire",   0x00, 0x05, 0x09, "Fire 2",  "Fire 3"  },
  { "Ice",    0x01, 0x06, 0x0a, "Ice 2",   "Ice 3"   },
  { "Bolt",   0x02, 0x07, 0x0b, "Bolt 2",  "Bolt 3"  },
  { "Poison", 0x03, 0x08, 0x08, "Bio",     "Bio"     },
  { "Cure",   0x2d, 0x2e, 0x2f, "Cure 2",  "Cure 3"  },
  { "Life",   0x30, 0x31, 0x31, "Life 2",  "Life 2"  },
  { "Slow",   0x19, 0x28, 0x28, "Slow 2",  "Slow 2"  },
  { "Haste",  0x1f, 0x27, 0x27, "Haste2",  "Haste2"  },
}

-- ca65 symbol -> snesPrgRom file offset (banks $C0-$FF are HiROM).
-- NB: compose.py scrapes LITERAL H.sym(...) calls out of this script to build
-- OT6_SYMS, so every symbol name must be spelled out at its call site.
local function romOfs(addr) return addr & 0x3FFFFF end

local magicProp, charProp, levelUpMp, naturalMagic, foldTbl

local function mpCost(id)
  return H.readRomByte(magicProp + id * MAGIC_STRIDE + MAGIC_MP)
end

-- pool(charId, level) exactly as InitMaxMP builds it (battle_costtable's own
-- helper, kept identical so the two tests cannot disagree about a pool).
local function pool(id, level)
  local mp = H.readRomByte(charProp + id * CHARPROP_SIZE + CHARPROP_MP)
  for i = 0, level - 2 do mp = mp + H.readRomByte(levelUpMp + i) end
  return mp
end

-- the level a character learns a spell naturally, or nil
local function learnLevel(charId, spellId)
  local base = naturalMagic + (charId == CHAR_CELES and NAT_CELES or 0)
  for i = 0, NAT_ROWS - 1 do
    if H.readRomByte(base + i * NAT_STRIDE) == spellId then
      return H.readRomByte(base + i * NAT_STRIDE + 1)
    end
  end
  return nil
end

-- who learns this spell naturally, and when?  Terra first, then Celes.
local function natural(spellId)
  local lv = learnLevel(CHAR_TERRA, spellId)
  if lv then return CHAR_TERRA, "Terra", lv end
  lv = learnLevel(CHAR_CELES, spellId)
  if lv then return CHAR_CELES, "Celes", lv end
  return nil
end

-- the lowest level at which `who` can pay `cost` from a full pool
local function payableAt(charId, cost)
  for lv = 1, 99 do
    if pool(charId, lv) >= cost then return lv end
  end
  return nil
end

local function pct(cost, p) return 100.0 * cost / p end

H.run({ maxFrames = 20000 }, {
  H.call(function()
    magicProp    = romOfs(H.sym("MagicProp"))
    charProp     = romOfs(H.sym("CharProp"))
    levelUpMp    = romOfs(H.sym("LevelUpMP"))
    naturalMagic = romOfs(H.sym("NaturalMagic"))
    foldTbl      = romOfs(H.sym("Ot6FoldTbl"))

    -- the helpers must not be vacuous before anything leans on them
    H.assertEq(learnLevel(CHAR_TERRA, 0x00), 3,
      "NaturalMagic says Terra learns Fire at 3")
    H.assertEq(learnLevel(CHAR_TERRA, 0x09), 43,
      "...and Fire 3 at 43 -- the level folding is measured against")
    H.assertEq(learnLevel(CHAR_CELES, 0x01), 1,
      "NaturalMagic says Celes learns Ice at 1")
    H.assertEq(learnLevel(CHAR_TERRA, 0x01), nil,
      "and the reader really is per-character (Terra never learns Ice)")
    H.assertEq(mpCost(0x2b), CEILING, string.format(
      "MagicProp's dearest spell is Quick at %d -- the series' own ceiling, "
      .. "which is where #57 got the anchor", CEILING))
  end),

  ------------------------------------------- 1. the family table is shipped --
  H.call(function()
    for i, f in ipairs(FAMILIES) do
      local o = foldTbl + (i - 1) * 3
      H.assertEq(H.readRomByte(o), f[2],
        string.format("family %d base is %s ($%02x)", i, f[1], f[2]))
      H.assertEq(H.readRomByte(o + 1), f[3],
        string.format("%s +1 tier is %s ($%02x)", f[1], f[5], f[3]))
      H.assertEq(H.readRomByte(o + 2), f[4],
        string.format("%s +2 tiers is %s ($%02x)", f[1], f[6], f[4]))
    end
    -- a 3-BP spend must never be dead: the shallow families repeat, so the
    -- +2 entry is always a real spell and never a pad
    for _, f in ipairs(FAMILIES) do
      assert(f[4] ~= 0xff and mpCost(f[4]) > 0, string.format(
        "%s's +2 entry ($%02x) must be a real, priced spell -- a pad here "
        .. "would make the third boost point buy nothing", f[1], f[4]))
    end
  end),

  ------------------------------------------------------------ 2 & 3. shape --
  H.call(function()
    local dearest, dearestName = 0, nil
    for _, f in ipairs(FAMILIES) do
      local c0, c1, c2 = mpCost(f[2]), mpCost(f[3]), mpCost(f[4])
      -- MONOTONIC.  #64's whole point: a boost may not buy a discount.
      assert(c1 >= c0, string.format(
        "%s: %s costs %d but base %s costs %d -- a higher tier that undercuts "
        .. "a lower one re-opens exactly the discount #64 closed",
        f[1], f[5], c1, f[1], c0))
      assert(c2 >= c1, string.format(
        "%s: %s costs %d but %s costs %d -- see above",
        f[1], f[6], c2, f[5], c1))
      for _, pair in ipairs({ { f[2], f[1] }, { f[3], f[5] }, { f[4], f[6] } }) do
        local c = mpCost(pair[1])
        assert(c <= CEILING, string.format(
          "%s costs %d, above the %d ceiling -- that is a DISPLAY break, not "
          .. "a taste question: every OT6 price drawer renders two digits "
          .. "(ListText cmd $02, btlgfx_main.asm:15045-15073)",
          pair[2], c, CEILING))
        if c > dearest then dearest, dearestName = c, pair[2] end
      end
    end
    H.log(string.format(
      "ceiling: dearest folded tier is %s at %d MP, %d under the %d limit",
      dearestName, dearest, CEILING - dearest, CEILING))
  end),

  -------------------------------- 4 & 5. the baseline, and what folding buys --
  H.call(function()
    H.log("family   tier      MP   reachable-by-fold      learned      payable")
    local checked = 0
    for _, f in ipairs(FAMILIES) do
      local baseId, baseName = f[2], f[1]
      local who, whoName, baseLv = natural(baseId)
      -- the level the fold is reachable from: the base spell's own arrival,
      -- floored at #45's clamp.  BP is never the binding constraint -- 2 BP
      -- is a character's second action of their first battle.
      local measureLv = math.max(baseLv or 0, CLAMP_LV)
      local measureWho = who or CHAR_TERRA
      local measureName = whoName or "Terra*"
      local basePool = pool(measureWho, measureLv)

      for step = 1, 2 do
        local id = (step == 1) and f[3] or f[4]
        local name = (step == 1) and f[5] or f[6]
        if not (step == 2 and f[4] == f[3]) then   -- shallow families once
          local cost = mpCost(id)
          local pay = payableAt(measureWho, cost)
          local tierLv = learnLevel(measureWho, id)
          H.log(string.format(
            "%-8s %-8s %4d   L%-2d %s pool %-3d %5.1f%%   %-8s %5s   L%d",
            baseName, name, cost, measureLv, measureName, basePool,
            pct(cost, basePool),
            tierLv and ("L" .. tierLv) or "esper",
            tierLv and string.format("%.1f%%",
              pct(cost, pool(measureWho, tierLv))) or "-",
            pay or 99))

          -- THE ASSERTION #64 TURNS ON.  Only meaningful where the tier has a
          -- real learn level to be earlier than.
          if tierLv and baseLv then
            checked = checked + 1
            assert(pay ~= nil and pay < tierLv, string.format(
              "%s costs %d, first payable at L%d, but %s learns it at L%d. "
              .. "Folding would then buy NOTHING -- you could only afford the "
              .. "tier after you already knew it -- which is the failure mode "
              .. "#64's repricing has to avoid, not cause",
              name, cost, pay or 99, measureName, tierLv))
          end
          -- ...and MP GENUINELY BUYS THE POWER.  The other side of #64: a
          -- folded tier must cost at least twice its base, or the fold is
          -- back to being a discount engine in all but name.  This one is
          -- deliberately about the RATIO rather than a %-of-pool bracket:
          -- pools cancel, so it holds at every level and cannot be argued
          -- away by picking a measurement level.  Measured headroom: Life 2
          -- is the tightest family in the shipped table at exactly 2.0x,
          -- Bio the loosest at 8.7x.
          local baseCost = mpCost(baseId)
          assert(cost >= 2 * baseCost, string.format(
            "%s costs %d against base %s's %d -- only %.1fx.  A folded tier "
            .. "under 2x its base means BP is buying the power again and MP "
            .. "is back to being a rounding error, which is the exact "
            .. "discount #64 closed", name, cost, baseName, baseCost,
            cost / baseCost))
        end
      end
    end
    assert(checked >= 4, string.format(
      "only %d families had both a base and a tier learn level -- assertion 4 "
      .. "must not quietly measure nothing", checked))
    H.log(string.format("the fold-buys-something check covered %d tiers",
      checked))
  end),
})
