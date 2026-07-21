-- @suite
-- battle_bushido.lua -- BP-Bushido: boost points pick Cyan's tech, and the
-- vanilla charge gauge is gone.
--
-- Vanilla ran a free-running bar (btlgfx_main.asm UpdateMenuState_37): the
-- counter w7e7b82 climbed one unit every 4 frames, the tech was counter >> 5,
-- it wrapped past $2020 (techs known - 1), and A latched whatever level it
-- happened to be showing.  OT6 deletes the CLOCK and lets the boost bank pick
-- the level instead (Ot6BushidoTier, ot6.asm), clamped by that same $2020.
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
--   2. The ladder, over a sweep of (boost spent, techs known): 0 bp buys
--      Fang, 1 Tiger, 2 Dragon, 3 Tempest -- each dropping to the best tech
--      actually learned when the band's top is above Cyan's level.  The
--      sweep must produce several distinct techs, so a routine that returned
--      a constant cannot pass it.
--   3. Oblivion (tech 8) IS reachable at BP3 now that divine gating landed
--      (Ot6Oblivion, hooked in CalcAttackEffect): the 3-bp band tops at Oblivion once
--      Cyan has learned it and while his once-per-battle latch is clear -- the
--      state this fixture is in (nothing has spent it). The broken-vs-unbroken
--      RESOLUTION gate and the spent-reverts-to-Tempest rule are battle_divines.
--   4. The spend caps at 3 and never exceeds the bank (Ot6Boost's rule,
--      unchanged -- Bushido reads $3E9D, it never writes it).
--   5. The chosen tech RESOLVES: Flurry's id reaches $3410 ("last spell
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

-- vanilla tech names, in the order the swdtech window numbers them, under
-- the kit names docs/design/kits.md gives them
local TECH = { [0] = "fang", "sky", "tiger", "flurry",
               "dragon", "eclipse", "tempest", "oblivion" }

local OT6_SLASH = 0x01
local FLURRY = 3                      -- tech index; attack id $55 + 3 = $58
-- Flurry's four hits measured 81 total on this fixture (intro stats, guards
-- shielded so the 0.5x resistance applies).  A double dip would be
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
  H.writeWord(KNOWN, ceiling)
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
-- {boost spent, techs known - 1, expected tech index}.  The clamped rows are
-- the whole reason the ladder is a band and not a 1:1 map: a band drops to
-- the best tech Cyan has actually learned, so its expression upgrades as he
-- levels (sky -> tiger at 12, flurry -> dragon at 24).
local SWEEP = {
  { 0, 7, 0 },   -- fang: the free tier
  { 1, 7, 2 },   -- tiger tops the 1-bp band
  { 2, 7, 4 },   -- dragon tops the 2-bp band
  { 3, 7, 7 },   -- OBLIVION tops the 3-bp band now (divine gating landed);
                 --   the latch is clear in this fixture, so 7 stands

  { 1, 1, 1 },   -- L6-11 cyan: the 1-bp band is still sky
  { 2, 3, 3 },   -- L15-23 cyan: the 2-bp band is still flurry
  { 3, 5, 5 },   -- L34-43 cyan: the 3-bp band is still eclipse
  { 3, 0, 0 },   -- L1 cyan: three points still only buy fang
}
local seenLevels, sweepRows = {}, 0
local barSeen, barFrames = {}, 0
local sh0, hp0 = {}, {}

H.run({ maxFrames = 40000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
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

  -- 1. THE CLOCK IS DEAD.  Boost held at 1, so the ladder says tiger ($40).
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
    H.assertEq(barSeen[0x40], sampled, "and it is the ladder's tiger ($40)")
  end),

  -- 2/3. the ladder, including the learn-clamped rows
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
    -- a routine that ignored bp and returned a constant would score 1
    H.assertEq(n >= 6, true, "boost really moves the selection")
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

  -- 5. latch flurry and follow it to a resolved, slashing chip
  H.call(function()
    ceiling, pinPend = FLURRY, 2       -- L15-23 cyan: 2 bp is flurry
    pinShields = false
    pin()
  end),
  H.waitFrames(8),
  H.call(function()
    H.assertEq(level(), FLURRY, "the tech about to be latched is flurry")
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
    for _, v in ipairs(spells) do if v == 0x55 + FLURRY then return true end end
    return false
  end, 12000, {
    H.call(function()
      pin()
      if H.readByte(MENU) ~= 0 and not inWindow() then H.setPad({ "a" }) end
    end),
    H.waitFrames(4),
    H.call(function() H.setPad({}) end),
    H.waitFrames(20),
  }, "flurry reaches $3410"),
  H.waitUntil(function() return pend(actor) == 0 end, 1200,
    "the boosted tech resolves", 10),
  H.waitFrames(60),
  H.call(function()
    local ids = {}
    for _, v in ipairs(spells) do ids[#ids + 1] = string.format("%02x", v) end
    H.log("attack ids that reached $3410: " .. table.concat(ids, " "))
    local sawFlurry = false
    for _, v in ipairs(spells) do if v == 0x55 + FLURRY then sawFlurry = true end end
    H.assertEq(sawFlurry, true, "2 bp executed flurry ($58), not fang ($55)")

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

    -- no double dip: the two points bought FLURRY, so they must not also
    -- buy Ot6BoostDmg's x4.  Same shape as battle_fold's bound on a folded
    -- Fire 3 -- the gate itself is structural (the $07 test in Ot6BoostDmg),
    -- so this only has to separate 1x from 4x, not pin the roll.
    local dmg = 0
    for _, s in ipairs(GUARDS) do dmg = dmg + (hp0[s] - H.readWord(MHP(s))) end
    H.log(string.format("flurry dealt %d across both guards", dmg))
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
