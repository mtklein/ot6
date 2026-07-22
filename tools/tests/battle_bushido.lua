-- @suite
-- battle_bushido.lua -- BP-Bushido: boost points pick Cyan's tech, and the
-- vanilla charge gauge is gone.
--
-- Vanilla ran a free-running bar (btlgfx_main.asm UpdateMenuState_37): the
-- counter w7e7b82 climbed one unit every 4 frames, the tech was counter >> 5,
-- it wrapped past $2020 (techs known - 1), and A latched whatever level it
-- happened to be showing.  OT6 deletes the CLOCK and lets the boost bank pick
-- the tech instead (Ot6BushidoTier, ot6.asm): a MOVING WINDOW OF FOUR (issue
-- #5) where boost 0/1/2/3 selects Cyan's top four LEARNED techs weakest ->
-- strongest, the window bounded by that same $2020.
-- Everything downstream is vanilla: the +$55 in FixPlayerAttack, Cmd_07's
-- dispatch, and Ot6SkillClassTbl's slashing classification of all eight.
--
-- Cyan is not recruitable until the v0.3 arc, so he is INSTALLED into the
-- opening guard fight the way the balance labs pin state -- every party slot
-- gets CHAR::CYAN ($3ED8), a Bushido-only command list ($202E, stride 12),
-- the weapon SWDTECH flag ($3BA4/$3BA5 bit 1, without which UpdateCmd_02
-- greys the command out -- battle_main.asm:13690), and a pinned $2020 that
-- stands in for his level.  probe_bushido.lua is the instrument this was
-- built from; it logs the same RAM without asserting on it.
--
-- What is asserted:
--   1. THE CLOCK IS DEAD.  150 consecutive in-window frames with the boost
--      held still must show ONE bar value.  Vanilla would step ~38 times
--      across that span, so a reverted hook fails here first and loudly.
--   2. THE MOVING WINDOW OF FOUR, over a sweep of (boost spent, techs known):
--      boost 0/1/2/3 lands on the base..base+3 techs of the top-four window
--      (base = max(0, ceiling-3), capped at ceiling).  While four or fewer are
--      known every learned tech is reachable -- 3 techs give Dispatch/Retort/
--      Slash at 0/1/2, so the Retort the OLD band design skipped is asserted
--      back.  Learn a fifth and the window slides up one, retiring the weakest.
--      The sweep walks N = 3,4,5,6,8 and pins EACH tech the four boosts select,
--      so a band-compressor (or a constant) fails on the very first slid row.
--   3. Oblivion (tech 8) is the window's TOP RUNG at full kit: with all eight
--      learned the window is {4,5,6,7} and BP3 lands on 7 = Oblivion, gated at
--      RESOLUTION by Ot6Oblivion (hooked in CalcAttackEffect) and reachable
--      while the once-per-battle latch is clear -- the state this fixture is in.
--      The broken-vs-unbroken gate and spent-reverts-to-Tempest are battle_divines.
--   4. The spend caps at 3 and never exceeds the bank (Ot6Boost's rule,
--      unchanged -- Bushido reads $3E9D, it never writes it).
--   5. The chosen tech RESOLVES: Quadra Slam's id reaches $3410 ("last spell
--      used", InitTarget_02 battle_main.asm:6545), it chips a slashing-weak
--      guard and reveals the slash class, and the boost is consumed with no
--      +1 regen that turn (Ot6ActionEnd).
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local BAR, KNOWN = 0x7B82, 0x2020     -- w7e7b82 (level*32) / techs known - 1
local ST_BUSHIDO = 0x37               -- UpdateMenuStateTbl entry $37

local PARTY = { 0, 1, 2 }
local GUARDS = { 2, 3 }               -- monster slots -> entity offset 8+slot*2
local function SH(s)  return 0x3E38 + (8 + s * 2) end   -- shields
local function TM(s)  return 0x3E88 + (8 + s * 2) end   -- broken timer
local function WKE(s) return 0x3BE0 + (8 + s * 2) end   -- weak elements
local function WKC(s) return 0x3E9C + (8 + s * 2) end   -- weak classes
local function RVC(s) return 0x3E9D + (8 + s * 2) end   -- revealed classes
local function MHP(s) return 0x3BFC + s * 2 end
-- status 3; bit $10 is stop, which is the bit Ot6Gate reads to skip a turn
local function ST3(e) return 0x3EF8 + e end

local function bp(s)   return H.readByte(0x3E9C + s * 2) end
local function pend(s) return H.readByte(0x3E9D + s * 2) end
local function level() return H.readByte(BAR) // 32 end
local function inWindow() return H.readByte(MSTATE) == ST_BUSHIDO end

-- the ACTUAL in-game tech names (ff6/src/text/bushido_name_en.json), in the
-- order the swdtech window numbers them.  tech 7 (Cleave) is the divine the
-- code calls Oblivion.
local TECH = { [0] = "Dispatch", "Retort", "Slash", "Quadra Slam",
               "Empowerer", "Stunner", "Quadra Slice", "Cleave" }

local OT6_SLASH = 0x01
local QSLAM = 3                       -- Quadra Slam: tech index; id $55 + 3 = $58
-- Quadra Slam's four hits measured 81 total on this fixture (intro stats,
-- guards shielded so the 0.5x resistance applies).  A double dip would be
-- Ot6BoostDmg's x4 on top, ~324, so the bound only has to sit between: 240
-- leaves 3x headroom over the roll and still fails a multiplied hit.
local DMG_CAP = 240

local actor                           -- the party slot whose menu we drive
local ceiling = 7                     -- pinned $2020: techs known - 1
local pinPend = nil                   -- when set, pending boost is held here
local pinBp = true                    -- hold the bank full (off for the end)
local pinShields = true
local pinHp = true                    -- off once we want to measure damage
local spells = {}                     -- every attack id that reached $3410

local function pinCyan()
  -- issue #4 regression: pin $2020 with a GARBAGE HIGH BYTE, the way InitSkills
  -- really leaves it (it stores CountBits's uninitialized high byte via `stx`;
  -- measured $FF02 in the Doma solo fight). Before the byte-read fix in
  -- Ot6BushidoTier, this read as $FFxx, tripped `>= 8`, and collapsed EVERY
  -- ceiling to 0 -- Cyan frozen at Dispatch regardless of techs or boost.
  -- Pinning a clean word here (the old code) is exactly why the suite missed it.
  H.writeWord(KNOWN, 0xFF00 | ceiling)
  for _, s in ipairs(PARTY) do
    H.writeByte(0x3ED8 + s * 2, 0x02)                 -- CHAR::CYAN
    local st1 = 0x3EE4 + s * 2
    H.writeByte(st1, H.readByte(st1) & 0xF7)          -- clear magitek
    H.writeByte(0x202E + s * 12, 0x07)                -- Bushido, alone
    H.writeByte(0x2031 + s * 12, 0xFF)
    H.writeByte(0x2034 + s * 12, 0xFF)
    H.writeByte(0x2037 + s * 12, 0xFF)
    H.writeByte(0x3BA4 + s * 2, H.readByte(0x3BA4 + s * 2) | 0x02)
    H.writeByte(0x3BA5 + s * 2, H.readByte(0x3BA5 + s * 2) | 0x02)
    H.writeWord(0x3BF4 + s * 2, 999)                  -- nobody dies mid-bench
    -- v0.5 costs are LIVE: pin MP high so the costed tech never fizzles on an
    -- empty pool (the intro fixture's installed slots carry little/no MP).
    -- Scarcity is not this test's subject -- the tier ladder and the chip are.
    H.writeWord(0x3C08 + s * 2, 99)                   -- current MP
    H.writeWord(0x3C30 + s * 2, 99)                   -- max MP (nothing clamps it)
  end
  if actor and pinBp then H.writeByte(0x3E9C + actor * 2, 5) end
  if actor and pinPend then H.writeByte(0x3E9D + actor * 2, pinPend) end
end

local function pinGuards()
  for _, s in ipairs(GUARDS) do
    H.writeByte(WKE(s), 0)              -- no element weakness: class chips only
    H.writeByte(WKC(s), OT6_SLASH)      -- slashing-weak, so bushido chips
    H.writeByte(TM(s), 0)               -- never broken (x2 would muddy damage)
    local st3 = ST3(8 + s * 2)
    H.writeByte(st3, H.readByte(st3) | 0x10)   -- stopped: nothing contests
    if pinHp then H.writeWord(MHP(s), 0xF000) end   -- a hit never kills
    if pinShields then H.writeByte(SH(s), 8) end
  end
end

local function pin() pinCyan(); pinGuards() end

-- ------------------------------------------------------------------ sweep --
-- {boost spent, techs known - 1 (the ceiling), expected tech index}.  This
-- walks the MOVING WINDOW OF FOUR: base = max(0, ceiling-3), and boost 0/1/2/3
-- selects tech min(base+boost, ceiling).  The window is grouped by N (techs
-- known): each group pins all four boosts, so we assert the exact four techs
-- boost reaches AND that they slide as N grows.  The old band table -- which
-- named each band's TOP tech (0/2/4/7) and clamped it -- fails the very first
-- N=3 group (it gave 0/2/2/2, skipping Retort).
local SWEEP = {
  -- N=3 (ceiling 2), window {0,1,2}: every learned tech reachable.  Row 2 is
  -- issue #5's headline -- boost 1 reaches Retort, which the band design could
  -- not (it jumped 0-bp Dispatch straight to Slash).  Boost 3 caps at Slash.
  { 0, 2, 0 },   -- Dispatch
  { 1, 2, 1 },   -- Retort   <- the fix: a mid-tech the old bands skipped
  { 2, 2, 2 },   -- Slash
  { 3, 2, 2 },   -- Slash (boost overruns a 3-tech window -> capped at ceiling)

  -- N=4 (ceiling 3), window {0,1,2,3}: the full base kit, 1:1 across the four
  -- boosts -- Dispatch/Retort/Slash/Quadra Slam.
  { 0, 3, 0 }, { 1, 3, 1 }, { 2, 3, 2 }, { 3, 3, 3 },

  -- N=5 (ceiling 4), window {1,2,3,4}: Dispatch has RETIRED off the bottom.
  { 0, 4, 1 },   -- Retort   (weakest still in the window)
  { 1, 4, 2 },   -- Slash
  { 2, 4, 3 },   -- Quadra Slam
  { 3, 4, 4 },   -- Empowerer

  -- N=6 (ceiling 5), window {2,3,4,5}: Retort has retired too.
  { 0, 5, 2 },   -- Slash
  { 1, 5, 3 },   -- Quadra Slam
  { 2, 5, 4 },   -- Empowerer
  { 3, 5, 5 },   -- Stunner

  -- N=8 (ceiling 7), window {4,5,6,7}: his top four.  Boost 3 lands on 7 =
  -- Oblivion (Cleave), the window's conditional top rung; the once-per-battle
  -- latch is clear in this fixture, so 7 stands.
  { 0, 7, 4 },   -- Empowerer
  { 1, 7, 5 },   -- Stunner
  { 2, 7, 6 },   -- Quadra Slice
  { 3, 7, 7 },   -- Cleave / Oblivion (the divine top rung)
}
local seenLevels, sweepRows = {}, 0
local barSeen, barFrames = {}, 0
local sh0, hp0 = {}, {}

H.run({ maxFrames = 40000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.enterEncounter(),
  H.call(function()
    emu.addMemoryCallback(function(_, v) spells[#spells + 1] = v end,
      emu.callbackType.write, 0x7E3410, 0x7E3410)
  end),
  -- install Cyan every frame until a menu belongs to somebody
  H.driveUntil(function() return H.readByte(MENU) ~= 0 end, 3000, {
    H.call(pin), H.waitFrames(1),
  }, "a battle menu opens"),
  H.call(function()
    actor = H.readByte(ACTOR)
    pinPend = 1
    H.log(string.format("cyan installed in slot %d (char id $%02x)",
      actor, H.readByte(0x3ED8 + actor * 2)))
  end),
  -- open the swdtech window.  Short presses: $04 is the REPEAT-mode button
  -- word (UpdateCtrl swaps $04/$0a every frame), so a long hold can select the
  -- command AND latch a tech in one go.
  H.driveUntil(inWindow, 900, {
    H.call(function() pin(); H.setPad({ "a" }) end),
    H.waitFrames(2),
    H.call(function() H.setPad({}) end),
    H.waitFrames(14),
  }, "the swdtech window opens (menu state $37)"),
  H.call(function() H.screenshot("bushido_window") end),

  -- 1. THE CLOCK IS DEAD.  Boost held at 1 with all eight techs known (window
  -- {4,5,6,7}), so the window selects Stunner -- tech 5, bar 5*32 = $a0.
  -- The first in-window frames still carry UpdateMenuState_35's `stz
  -- w7e7b82`: steps run on startFrame, so the earliest samples are taken
  -- before Ot6BushidoTier has run even once.  Settle past that, then the
  -- rest of the span must not move at all.
  H.repeatN(160, {
    H.call(function()
      pin()
      if inWindow() then
        barFrames = barFrames + 1
        if barFrames > 10 then
          local v = H.readByte(BAR)
          barSeen[v] = (barSeen[v] or 0) + 1
        end
      end
    end),
    H.waitFrames(1),
  }),
  H.call(function()
    local parts, distinct, sampled = {}, 0, 0
    for v, n in pairs(barSeen) do
      parts[#parts + 1] = string.format("$%02x x%d", v, n)
      distinct, sampled = distinct + 1, sampled + n
    end
    H.log("bar values over " .. sampled .. " settled in-window frames: "
      .. table.concat(parts, ", "))
    H.assertEq(sampled >= 140, true, "the window stayed open to be sampled")
    -- vanilla stepped the counter every 4 frames and would show ~36 values
    H.assertEq(distinct, 1, "the charge gauge does not tick: one bar value")
    H.assertEq(barSeen[0xA0], sampled, "and it is the window's Stunner ($a0)")
  end),

  -- 2/3. the moving window of four, group by group as N grows
  H.driveUntil(function() return sweepRows > #SWEEP end, 4000, {
    H.call(function()
      local row = SWEEP[math.min(sweepRows + 1, #SWEEP)]
      pinPend, ceiling = row[1], row[2]
      pin()
    end),
    H.waitFrames(8),
    H.call(function()
      local row = SWEEP[math.min(sweepRows + 1, #SWEEP)]
      if sweepRows < #SWEEP then
        local got = level()
        H.log(string.format("  %d bp, %d techs known -> tech %d (%s)",
          row[1], row[2] + 1, got + 1, TECH[got]))
        H.assertEq(inWindow(), true, "still in the swdtech window")
        H.assertEq(got, row[3], string.format(
          "%d bp with %d techs known selects %s", row[1], row[2] + 1,
          TECH[row[3]]))
        seenLevels[got] = true
      end
      sweepRows = sweepRows + 1
    end),
  }, "the whole tier sweep"),
  H.call(function()
    local n = 0
    for _ in pairs(seenLevels) do n = n + 1 end
    H.log("distinct techs reached across the sweep: " .. n)
    -- the window walk reaches EVERY tech 0-7 across the N groups; a band
    -- compressor skips the middle ones and a constant scores 1
    H.assertEq(n >= 8, true, "boost + the sliding window reach all eight techs")
  end),

  -- 4. the spend cap, driven by real R presses inside the window
  H.call(function() pinPend, ceiling = 0, 7; pin() end),
  H.waitFrames(8),
  H.repeatN(5, {
    H.call(function() pinPend = nil; pin(); H.setPad({ "r" }) end),
    H.waitFrames(6),
    H.call(function() H.setPad({}) end),
    H.waitFrames(16),
  }),
  H.call(function()
    H.log(string.format("after five R presses: pending=%d tech=%d (%s)",
      pend(actor), level() + 1, TECH[level()]))
    H.assertEq(pend(actor), 3, "the spend caps at 3 (Ot6Boost, unchanged)")
    H.assertEq(level(), 7, "and 3 bp now tops out at OBLIVION (divine unspent)")
    H.screenshot("bushido_boosted")
  end),

  -- 5. latch Quadra Slam and follow it to a resolved, slashing chip.  N=5
  -- (ceiling 4), window {1,2,3,4}: boost 2 -> base 1 + 2 = tech 3, a slid-
  -- window pick (Dispatch retired).  The OLD band table gave tech 4 here
  -- (dragon, id $59), so the resolved $58 also proves the mechanic changed.
  H.call(function()
    ceiling, pinPend = 4, 2
    pinShields = false
    pin()
  end),
  H.waitFrames(8),
  H.call(function()
    H.assertEq(level(), QSLAM, "the tech about to be latched is Quadra Slam")
    -- park the other two Cyans so only the boosted tech moves guard HP
    for _, s in ipairs(PARTY) do
      if s ~= actor then
        H.writeByte(ST3(s * 2), H.readByte(ST3(s * 2)) | 0x10)
      end
    end
    pinHp = false                      -- let the damage stand to be measured
    for _, s in ipairs(GUARDS) do
      H.writeByte(SH(s), 8)
      H.writeByte(RVC(s), 0)           -- nothing revealed yet
      sh0[s] = 8
      hp0[s] = H.readWord(MHP(s))
    end
    H.assertEq(H.readByte(RVC(GUARDS[1])), 0, "no class revealed before the tech")
  end),
  H.driveUntil(function() return not inWindow() end, 900, {
    H.call(function() pin(); H.setPad({ "a" }) end),
    H.waitFrames(2),
    H.call(function() H.setPad({}) end),
    H.waitFrames(14),
  }, "the window closes on a latch"),
  -- stop pinning the boost so Ot6ActionEnd's arithmetic is observable
  H.call(function() pinPend, pinBp = nil, false end),
  H.driveUntil(function()
    for _, v in ipairs(spells) do if v == 0x55 + QSLAM then return true end end
    return false
  end, 12000, {
    H.call(function()
      pin()
      if H.readByte(MENU) ~= 0 and not inWindow() then H.setPad({ "a" }) end
    end),
    H.waitFrames(4),
    H.call(function() H.setPad({}) end),
    H.waitFrames(20),
  }, "Quadra Slam reaches $3410"),
  H.waitUntil(function() return pend(actor) == 0 end, 1200,
    "the boosted tech resolves", 10),
  H.waitFrames(60),
  H.call(function()
    local ids = {}
    for _, v in ipairs(spells) do ids[#ids + 1] = string.format("%02x", v) end
    H.log("attack ids that reached $3410: " .. table.concat(ids, " "))
    local sawQslam = false
    for _, v in ipairs(spells) do if v == 0x55 + QSLAM then sawQslam = true end end
    H.assertEq(sawQslam, true, "2 bp executed Quadra Slam ($58), not Empowerer ($59)")

    -- the class chip: bushido is slashing (Ot6SkillClassTbl), the guards are
    -- pinned slashing-weak, so the tech must chip and reveal
    local revealed, chipped = false, false
    for _, s in ipairs(GUARDS) do
      local r, sh = H.readByte(RVC(s)), H.readByte(SH(s))
      H.log(string.format("  guard %d: shields %d -> %d, revealed classes $%02x",
        s, sh0[s], sh, r))
      if r & OT6_SLASH ~= 0 then revealed = true end
      if sh < sh0[s] then chipped = true end
    end
    H.assertEq(chipped, true, "the tech chipped a slashing-weak guard's shields")
    H.assertEq(revealed, true, "and revealed the slash class ($01)")

    -- no double dip: the two points bought Quadra Slam, so they must not also
    -- buy Ot6BoostDmg's x4.  Same shape as battle_fold's bound on a folded
    -- Fire 3 -- the gate itself is structural (the $07 test in Ot6BoostDmg),
    -- so this only has to separate 1x from 4x, not pin the roll.
    local dmg = 0
    for _, s in ipairs(GUARDS) do dmg = dmg + (hp0[s] - H.readWord(MHP(s))) end
    H.log(string.format("Quadra Slam dealt %d across both guards", dmg))
    H.assertEq(dmg > 0, true, "the tech actually dealt damage")
    H.assertEq(dmg < DMG_CAP, true,
      "boost bought the tech, not a damage multiplier too")

    -- the economy: 5 banked, 2 spent, and no +1 on a turn that boosted
    H.log(string.format("bp %d -> %d, pending %d", 5, bp(actor), pend(actor)))
    H.assertEq(bp(actor), 3, "boost consumed (5-2) with no regen that turn")
    H.assertEq(pend(actor), 0, "pending cleared after the action")
    H.screenshot("bushido_resolved")
  end),
})
