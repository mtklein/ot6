-- @suite slow
-- battle_break.lua -- the M1 acceptance test: chip -> break -> recover, live.
--
--   tools/tests/run.sh tools/tests/battle_break.lua
--
-- Drives the Whelk head fight:
--
--   * fire-weak for real -- Ot6ElemAddTbl authors $0134 + fire
--     (ff6/src/battle/ot6_break.asm:404-406, "the tutorial probe"), so the
--     chip key is the one the game teaches rather than one this file writes;
--   * a real gauge -- Ot6ShieldTbl gives $0134 four shields and OT6_PIERCE
--     (ff6/src/battle/ot6_hud.asm:1730-1731);
--   * 1600 HP (monster_prop.dat $0134 +8) against a party that chips it for
--     a few hundred a hit;
--   * and only Terra beams.  Vicks and Wedge spend their turns on Heal
--     Force, so every recorded drop on the head comes from one caster with
--     one spell.
--
-- Asserts, in order:
--   1. the head seeds at 4 shields, fire-weak, class-weak PIERCE -- the
--      authored row, read not written.  This is the positive control for
--      everything below: without a real weakness no beam would chip at all.
--   2. a fire hit chips the head's shield and reveals the fire weakness
--      (mask $01 in the head's $3E91 slot)
--   3. shields reach 0 -> broken timer nonzero
--   3b. the broken x2 for a flags3-$20 attack: Fire Beam carries flags3
--      $20 (can't dodge), and the old whole-byte $f2 gate denied it the
--      broken double.  The breaking hit lands with the timer already
--      set, so its recorded drop must be ~4x the first (unbroken) chip's
--      drop on the same body: the first chip is elemental-weak x2 then
--      shielded-resistance x0.5 (Ot6ShieldedDmg attenuates while shields
--      hold), giving ~1x base, while the breaking hit's chip empties the
--      shields before the damage tail runs, so it collects weak x2 and
--      broken x2 unattenuated, giving ~4x base.  Bounded 3x-6x (vanilla's
--      224..255/256 damage spread keeps the true ratio inside [3.51, 4.55]).
--   4. the broken timer expires -> shields restore to max, and the revealed
--      mask survives recovery
--
-- Addresses, all +slot*2 off the monster slot the head lands in (found by
-- species scan, never hardcoded): shields $3E40, broken timer $3E90,
-- revealed elements $3E91, weak elements $3BE8, class-weak $3EA4, HP $3BFC,
-- presence $3AA8, status-1 $3EEC, species $57C0.

local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/whelk_entry.mss.lua"

local SHLD, TIMER, REVEAL = 0x3E40, 0x3E90, 0x3E91
local WEAK, CWEAK, MHP = 0x3BE8, 0x3EA4, 0x3BFC
local ALIVE, MSTAT, SPEC = 0x3AA8, 0x3EEC, 0x57C0
local MENU, ACTOR, CHID = 0x7BCA, 0x62CA, 0x3ED8
local HEAD_SP = 0x0134

local PHP, PMAXHP = 0x3BF4, 0x3C1C    -- party HP / max HP, +char slot*2
local MFLAGS, MGAUGE = 0x3AA8, 0x3221 -- monster $3AA0/$3219 rows, +slot*2

local hs                              -- head monster slot
local shell                           -- the shell's monster slot

local function shields()  return H.readByte(SHLD + hs * 2) end
local function maxShield() return H.readByte(SHLD + hs * 2 + 1) end
local function timer()    return H.readByte(TIMER + hs * 2) end
local function revealed() return H.readByte(REVEAL + hs * 2) end
local function headHp()   return H.readWord(MHP + hs * 2) end
-- the head retracts into the shell on its own timer; while it is gone the
-- default target is the shell, and any shell hit draws the MegaVolt counter.
local function headAlive()
  return (H.readByte(ALIVE + hs * 2) & 1) == 1
     and (H.readByte(MSTAT + hs * 2) & 0xC2) == 0
end

local function report(tag)
  return H.call(function()
    H.log(string.format(
      "%s shields=%d/%d timer=%02X revealed=%02X hp=%d alive=%s",
      tag, shields(), maxShield(), timer(), revealed(), headHp(),
      tostring(headAlive())))
  end)
end

-- Who acts: ExecCmd is entered once per action with x = the acting
-- entity (0,2,4,6 the party, 8.. the monsters), and actions run one at a
-- time, so the entity latched here is the one whose action lands the next
-- HP write.  Every head drop is attributed to it.
local lastActor = nil
local shellActs, counters = 0, 0
emu.addMemoryCallback(function()
  local x = emu.getState()["cpu.x"] & 0xff
  lastActor = x
  if shell ~= nil and x == 8 + shell * 2 then
    shellActs = shellActs + 1
  end
end, emu.callbackType.exec, H.sym("ExecCmd@battle_code"),
  H.sym("ExecCmd@battle_code"))

local function who(x)
  if x == nil then return "?" end
  if x < 8 then
    local id = H.readByte(CHID + x)
    return string.format("p%d(char %02X)", x // 2, id)
  end
  return string.format("m%d", (x - 8) // 2)
end

-- per-frame HP watcher on the head: every discrete drop is recorded with the
-- broken-timer state at observation time and the entity whose action it
-- was.  The breaking hit's damage is computed in the same CalcTargetDmg
-- call that sets the timer (chip runs before the broken-double join), and
-- the HP write lands frames later during the animation, so a drop observed
-- with the timer up is a hit that ran the broken-double path.
local drops = {}
local prevHp, prevShellHp = nil, nil
local prevParty = {}
local headWasUp, showFrame, showTurns, showBeams = nil, nil, {}, 0
local showings = {}
local strays = 0
local function sampleDrops()
  local hp = headHp()
  if prevHp ~= nil and hp < prevHp then
    local d = prevHp - hp
    drops[#drops + 1] = { d = d, broken = timer() ~= 0, by = lastActor }
    H.log(string.format("hp drop: head -%d by %s (timer %02X, shields %d)",
      d, who(lastActor), timer(), shields()))
  end
  prevHp = hp
  local sh = H.readWord(MHP + shell * 2)
  if prevShellHp ~= nil and sh < prevShellHp then
    strays = strays + 1
    H.log(string.format("hp drop: shell -%d by %s (an attack that missed "
      .. "the head's window)", prevShellHp - sh, who(lastActor)))
  end
  prevShellHp = sh
  -- party damage dealt by the shell is its Mega Volt counter (AIScript
  -- _256 has no other attack)
  for s = 0, 3 do
    local php = H.readWord(PHP + s * 2)
    if prevParty[s] ~= nil and php < prevParty[s]
       and lastActor == 8 + shell * 2 then
      H.log(string.format("hp drop: p%d -%d by the shell's counter "
        .. "(%d/%d left)", s, prevParty[s] - php, php,
        H.readWord(PMAXHP + s * 2)))
    end
    prevParty[s] = php
  end
  local up = headAlive()
  if up ~= headWasUp then
    if up then
      showFrame, showTurns, showBeams = H.frame, {}, 0
      H.log(string.format("head shows f%d", H.frame))
    elseif headWasUp then
      local t = {}
      for s = 0, 3 do
        if showTurns[s] then t[#t + 1] = string.format("p%d:%d", s, showTurns[s]) end
      end
      showings[#showings + 1] = { f = H.frame - showFrame, turns = showTurns }
      H.log(string.format("head hides f%d after %d frames up; turns while up %s; beams %d",
        H.frame, H.frame - showFrame, table.concat(t, " "), showBeams))
    end
    headWasUp = up
  end
end

-- ------------------------------------------------------------- driver --
-- Sequences run from the settled top command menu, on the MagiTek cursor:
--   Fire Beam at the default target  A A A
--   Heal Force (2,0), both lists      A dn dn A A  (self-target by default)
--
-- The owner's way with this fight: "I always find I get one round with
-- each character to attack, then the gruuu comes up and the head will
-- disappear, one round of healing on each character, then the head comes
-- back and I can finish it off round 2."  So each member, when their turn
-- comes, looks at the field: head up, Fire Beam it (the head is authored
-- fire-weak, Ot6ElemAddTbl, and every MagiTek list starts on Fire Beam);
-- head gone, Heal Force.  No one waits with a menu open.
--
-- The shell's own turn hides and shows the head (AIScript _256: each turn
-- past its 10-tick timer toggles the head, "Gruuu..."), and a beam lands
-- 165-527 frames after it is ordered, so a beam ordered just before the
-- hide retargets to the shell and draws its Mega Volt counter.  The
-- watcher above logs those as shell drops and counters.
local BEAM = { "a", "a", "a" }
local HEAL = { "a", "down", "down", "a", "a" }
local mStreak, mSeq, mIdx, mStall, mNoMenu = 0, nil, 1, 0, 0
local beamsOrdered = 0

local function shellGauge() return H.readByte(MGAUGE + shell * 2) end

local function seqFor(actor)
  local up = headAlive()
  local why = up and "beam" or "heal"
  H.log(string.format("p%d turn f%d: %s (head up=%s, shell gauge=%d "
    .. "flags=%02X, hp=%d/%d)", actor, H.frame, why, tostring(up),
    shellGauge(), H.readByte(MFLAGS + shell * 2),
    H.readWord(PHP + actor * 2), H.readWord(PMAXHP + actor * 2)))
  if up then
    showTurns[actor] = (showTurns[actor] or 0) + 1
    showBeams = showBeams + 1
    beamsOrdered = beamsOrdered + 1
    return BEAM
  end
  return HEAL
end

-- nothing in this fight revives, so a wipe ends the measurement: say so
-- instead of driving out the budget.
local function assertPartyUp()
  for s = 0, 3 do
    if (H.readByte(CHID + s * 2)) ~= 0xFF and H.readWord(PHP + s * 2) > 0 then
      return
    end
  end
  error(string.format("the party fell with the head at %d/4 shields after "
    .. "%d beam(s) ordered", shields(), beamsOrdered), 0)
end

local function policyPulse()
  if H.readByte(MENU) == 0 then
    mStreak, mSeq, mIdx, mStall = 0, nil, 1, 0
    mNoMenu = mNoMenu + 1
    return mNoMenu % 2 == 0 and { "a" } or {}
  end
  mNoMenu = 0
  mStreak = mStreak + 1
  if mStreak < 4 then return {} end
  if mSeq == nil then
    mSeq, mIdx = seqFor(H.readByte(ACTOR)), 1
  end
  if mIdx <= #mSeq then
    local b = mSeq[mIdx]
    mIdx = mIdx + 1
    return { b }
  end
  mStall = mStall + 1
  if mStall > 2 then
    mSeq, mStall = nil, 0             -- back out; rebuild from scratch
    return { "b" }
  end
  return { "a" }
end

local pulseAge = 29
local function pulseTick()
  pulseAge = (pulseAge + 1) % 30
  if pulseAge == 0 then
    H.setPad(policyPulse())
  elseif pulseAge == 6 then
    H.setPad({})
  end
end

local aPhase = 0

H.run({ maxFrames = 60000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),

  -- walk onto the trigger tile
  H.driveUntil(function()
    return H.battleLoadStarted() and H.monstersPresent() > 0
  end, 2600, {
    H.call(function()
      aPhase = (aPhase + 1) % 8
      if H.battleLoadStarted() then H.setPad({}); return end
      if H.dialogWaiting() then
        H.setPad(aPhase < 4 and { "a" } or {})
        return
      end
      if not H.hasControl() then H.setPad({}); return end
      if not H.tileAligned() then H.setPad({}); return end
      H.setPad(H.fieldY() <= 5 and { down = true } or { up = true })
    end),
  }, "whelk event fires"),
  H.call(function() H.setPad({}) end),
  H.waitUntil(function() return H.battleActive() end, 900, "whelk up", 30),

  -- The whelk's scripted intro dialogue re-uploads the small font for its
  -- whole ~13s run and the hud is veiled while it is up (battle_hudclobber),
  -- so tap through it and wait for a font-whole, un-veiled hud.  The run is
  -- past the intro when the first battle menu opens.
  H.driveUntil(function()
    return H.readByte(MENU) ~= 0 and H.readByte(0x64d5) == 0
       and H.fieldHudPresent()
  end, 6000, {
    H.call(function()
      if H.readByte(MENU) == 0 then H.setPad({ "a" }) else H.setPad({}) end
    end),
    H.waitFrames(10), H.release(), H.waitFrames(10),
  }, "whelk intro dismissed, menu up, hud font whole"),
  H.waitFrames(120),

  -- 1. seeding, and the positive control for the whole file: the head's
  -- weakness and its gauge are authored, so a chip below is the game's own
  -- key rather than one this test wrote.
  H.call(function()
    H.assertEq(H.formationHas({ [HEAD_SP] = true }), true, "whelk head fight")
    for slot = 0, 5 do
      local sp = H.readWord(SPEC + slot * 2)
      if sp == HEAD_SP then hs = slot end
    end
    H.assertEq(hs ~= nil, true, "the head has a monster slot")
    -- the shell: the one other monster on the field, whose turns hide and
    -- show the head (the beam window above reads its gauge)
    local others = 0
    for slot = 0, 5 do
      if slot ~= hs and (H.readByte(ALIVE + slot * 2) & 1) == 1 then
        shell, others = slot, others + 1
      end
    end
    H.assertEq(others, 1, "exactly one other monster (the shell) beside the head")
    H.log(string.format("head slot %d, shell slot %d", hs, shell))

    -- Ot6ShieldTbl authors $0134 as 4 shields / OT6_PIERCE (ot6_hud.asm:1730)
    H.assertEq(shields(), 4, "head seeded at its authored 4 shields")
    H.assertEq(maxShield(), 4, "and 4 is its max")
    -- Ot6ElemAddTbl authors $0134 + fire (ot6_break.asm:404-406)
    H.assertEq(H.readByte(WEAK + hs * 2) & 0x01, 0x01,
      "head is really fire-weak -- the authored tutorial probe, not a poke")
    H.assertEq(H.readByte(CWEAK + hs * 2), 0x02,
      "and class-weak PIERCE, the other authored axis")
    H.assertEq(revealed(), 0, "nothing revealed before the first chip")
    H.assertEq(headHp() > 1000, true,
      "the head carries the headroom this measurement needs (1600 authored)")
  end),
  report("seeded"),

  -- 2+3. the party beams the head until it breaks (watcher rides the pred)
  H.driveUntil(function()
    sampleDrops()
    assertPartyUp()
    return timer() > 0
  end, 40000, { H.call(pulseTick) }, "the head to break"),
  H.release(),
  -- keep sampling: the breaking hit's HP write lands frames after the timer
  -- went up (the pred stopped the drive at the timer write)
  H.repeatN(240, { H.call(sampleDrops), H.waitFrames(1) }),

  -- the beams that broke the head went through the magitek list, whose
  -- rendered rows persist in the menu map: assert the colored element icon
  -- right of "Fire Beam".  A blank icon here would mean only the pre-render
  -- is present, so the real list draw lost its icon column.
  H.call(function()
    local vr = emu.memType.snesVideoRam
    local best = nil
    for w = 0x6000, 0x7FF0 do
      if (emu.readWord(w*2, vr) & 0xFF) == 0x85
        and (emu.readWord(w*2+2, vr) & 0xFF) == 0xA2
        and (emu.readWord(w*2+4, vr) & 0xFF) == 0xAB then
        local icon = emu.readWord((w + 10) * 2, vr)
        if best == nil or icon == 0x3DEB then best = icon end
      end
    end
    H.assertEq(best, 0x3DEB, "fire icon glyph + red palette in the rendered list")
  end),
  report("broken"),
  H.call(function()
    -- The headroom check, stated as its own assertion so that a future
    -- failure reads as "the fixture ran out of HP" rather than as a broken
    -- gauge.
    H.assertEq(headHp() > 0, true,
      "the head survived its own break -- the 1600 HP is the headroom this "
      .. "measurement runs on")
    H.assertEq(shields(), 0, "broken head's shields at 0")
    H.assertEq(revealed() & 0x01, 0x01, "fire weakness revealed on the head")
    H.assertEq(beamsOrdered >= 4, true,
      "four or more beams were ordered -- the drive really fired the key "
      .. "(a break with no beams ordered would mean something else chipped)")
    -- 3b. broken x2 for a flags3-$20 beam: the breaking hit (the first
    -- drop observed with the timer up) must be ~4x the same caster's first
    -- unbroken chip.  Several members beam, and Fire Beam's damage follows
    -- its caster's level and magic, so the ratio pairs one caster's two
    -- hits, attributed by the acting entity at ExecCmd; it needs no stat
    -- equalization that way.
    local parts = {}
    for _, e in ipairs(drops) do
      parts[#parts + 1] = string.format("%d%s/%s", e.d, e.broken and "B" or "",
        who(e.by))
    end
    H.log(string.format("head drop record: %s", table.concat(parts, " ")))
    H.log(string.format("drive tally: beams ordered %d, shell drops %d, "
      .. "shell actions %d, showings %d", beamsOrdered, strays, shellActs,
      #showings))
    H.assertEq(#drops >= 2, true, "two chip hits recorded on the head")
    for _, e in ipairs(drops) do
      H.assertEq(e.by ~= nil and e.by < 8, true,
        "every head drop was a party member's action")
    end
    local brk = nil
    for _, e in ipairs(drops) do
      if e.broken then brk = e; break end
    end
    H.assertEq(brk ~= nil, true, "breaking hit landed with the timer up")
    local first = nil
    for _, e in ipairs(drops) do
      if e == brk then break end
      if e.by == brk.by then first = e; break end
    end
    H.assertEq(first ~= nil, true, string.format(
      "the breaking caster (%s) chipped the head unbroken before it broke",
      who(brk.by)))
    H.assertEq(first.broken, false, "that chip landed unbroken")
    H.log(string.format("ratio pair (%s): chip %d, breaking hit %d",
      who(brk.by), first.d, brk.d))
    -- shielded resistance sets these bounds: the unbroken chip is weak x2 *
    -- shielded x0.5 = ~1x base; the breaking hit is weak x2 * broken x2,
    -- unattenuated because its chip zeroed the shields before the damage
    -- tail, giving ~4x base.  True range [3.51, 4.55] under vanilla's
    -- 224..255/256 spread.
    H.assertEq(brk.d > first.d * 3, true,
      "broken beam hit > 3x the same caster's shielded chip (0.5x lifted, x2 collected)")
    H.assertEq(brk.d < first.d * 6, true,
      "and < 6x (weak x2 * broken x2, not something wilder)")
    H.screenshot("break_broken")
  end),

  -- 4. recovery: timer expires, shields restore, reveal persists.  Nothing
  -- is pressed from here on, so the head takes no further damage; the shell
  -- keeps acting, which is what the party's earlier Heal Force turns paid for.
  -- The break stops the drive wherever its blind sequence was, and if that
  -- is inside a submenu, wait mode holds battle time still ($2f41 & $3a8f,
  -- UpdateBattleTime) and the timer can never run out: measured on the #314
  -- ROM at shift 0, the MagiTek list (menu state $2a) up, $2f41=$01,
  -- DecCounters frozen for 12000 frames.  So back out with B until battle
  -- time runs, then hold.
  H.driveUntil(function()
    return (H.readByte(0x2F41) & H.readByte(0x3A8F)) == 0
  end, 600, {
    H.call(function() H.setPad(H.frame % 10 < 5 and { "b" } or {}) end),
  }, "battle time running (no submenu holding it in wait mode)"),
  H.release(),
  H.waitUntil(function()
    sampleDrops()
    return timer() == 0 and shields() == 4
  end, 12000, "broken head to recover", 1),
  H.waitFrames(30),
  report("recovered"),
  H.call(function()
    H.assertEq(shields(), 4, "shields restored to max")
    H.assertEq(revealed() & 0x01, 0x01, "revealed weakness survives recovery")
    H.screenshot("break_recovered")
  end),
})
