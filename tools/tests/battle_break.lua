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
--   3b. every hit is judged on the head's state before it lands (#542).
--      Each hit's damage is read as it enters OT6's factor (Ot6HitJoin)
--      and as it leaves (CalcMaxDmg, next), with the head's shields and
--      timer as CalcTargetDmg began: a hit on a shielded head is halved,
--      the hit that takes the last shield included, and a hit on a head
--      already Broken is doubled.  So the breaking beam's recorded HP drop
--      is about the first chip's (both elemental-weak x2 then shielded
--      x0.5; vanilla's 224..255/256 spread bounds the ratio to [0.87,
--      1.14]), where v0.45's breaking hit skipped the halving and took the
--      double, about 4x (build/attempts/wt/v046-break-feel/).  Then, from a
--      snapshot taken at the break, Terra beams the Broken head once more:
--      that hit is doubled.  The run goes back to the snapshot for 4.
--   4. the broken timer expires -> shields restore to max, and the revealed
--      mask survives recovery
--
-- And how the shield gauge looks (#397), read from VRAM and WRAM:
--   1h. under the head, the gauge: the emblem (cell $71) one cell left of
--      the line's anchor and the head's count cell at the anchor, both under
--      the gauge attribute $21 (text palette 0), the count cell holding the
--      ROM's tile for 4; its two unrevealed weaknesses as '?' under $25
--      (palette 1); and the colours on screen: the gauge plain white, the
--      '?' a mid grey, neither one any weakness icon's colour but for the
--      icons colourCheck names;
--   3h. broken, the lead cell holds the head's broken-shield tile (tile 100)
--      under $3D (text palette 7) and the count cell is empty; the head's
--      sprite stays on its own palette (#543 took the grey away: the broken
--      shield is the whole broken look), though the formation leaves a
--      spare palette the old grey would have used.
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
local CHAR_TERRA = 0x00

local PHP, PMAXHP = 0x3BF4, 0x3C1C    -- party HP / max HP, +char slot*2
local MFLAGS, MGAUGE = 0x3AA8, 0x3221 -- monster $3AA0/$3219 rows, +slot*2

local hs, terra                       -- head monster slot, Terra's char slot
local shell                           -- the shell's monster slot

-- the shield gauge (#397)
local HUDSHADOW = 0xECF1              -- OT6_SHADOW: 6 lines x 14, +0 anchor
local SPRDATA = 0x80DB                -- w7e80db: bits 1-3 the obj palette
local LOADED = 0x8123                 -- w7e8123: the formation's palettes
local MONPAL = 0x8117                 -- w7e8117: each slot's palette id
local GAUGE, BROKEN_ATTR = H.HUD_GAUGE_ATTR, H.HUD_BROKEN_ATTR
local vram = emu.memType.snesVideoRam
local function vword(w) return emu.readWord(w * 2, vram) end
local function palBits(s) return H.readByte(SPRDATA + s * 2) & 0x0E end
local function palsLoaded()
  local k = 0
  while k < 3 and H.readWord(LOADED + k * 2) ~= 0xFFFF do k = k + 1 end
  return k
end
local function slotCell(s)
  return H.readRomByte((H.sym("Ot6ShieldSlotCellTbl") & 0x3FFFFF) + s)
end
local function tileIs(cell, n)
  local base = (H.sym("Ot6ShieldGlyphs") & 0x3FFFFF) + (n - 1) * 16
  for i = 0, 15 do
    if emu.read(0xB000 + cell * 16 + i, vram) ~= H.readRomByte(base + i) then return false end
  end
  return true
end
-- the head's hud line as drawn: anchor, lead word, count word (nil if off)
local function headLine()
  local a = H.readWord(HUDSHADOW + hs * 14)
  if a == 0 then return nil end
  return a, vword(a - 1), vword(a)
end
-- the gauge's cells drawn (any attribute: the attribute and the colours are
-- asserted on their own, after colourCheck)
local function gaugeShown()
  local a, lead, count = headLine()
  return a ~= nil and lead & 0xFF == 0x71
    and count & 0xFF == slotCell(hs) and tileIs(slotCell(hs), H.readByte(0x3E40 + hs * 2))
end
-- The line's colours, as the screen has them (H.hudColours): the gauge
-- plain white, emblem and count alike; an unrevealed weakness's '?' a mid
-- grey, well apart from that white; and neither the colour of any weakness
-- icon, save the ones named here.  The four white icons share the gauge's
-- white and earth's icon shares the '?' grey: the battle text palettes
-- hold no other white or mid grey, and every one of their eight palettes
-- is drawn in (build/attempts/wt/v044-shield-colors/census_*.log).  The
-- lists are exact, so a recoloured icon, or the gauge put back on a hue,
-- goes red here.  #397's gold gauge was lightning's and holy's yellow.
local SHARE_WHITE = { wind = true, slash = true, pierce = true, special = true }
local SHARE_GREY = { earth = true }
local function rgb(c) return c & 31, (c >> 5) & 31, (c >> 10) & 31 end
local function colourCheck()
  local a, lead, count = headLine()
  H.assertEq(vword(a + 1) & 0xFF, 0xBF, "the head's first weakness cell is a '?' (nothing revealed)")
  local c = H.hudColours({ emblem = lead, count = count, qmark = vword(a + 1) })
  local parts = {}
  for _, ic in ipairs(c.icons) do parts[#parts + 1] = string.format("%s=%04X", ic[1], ic[2]) end
  H.log(string.format("[colours] gauge emblem %04X count %04X; '?' %04X; icons %s",
    c.gauge.emblem, c.gauge.count, c.qmark, table.concat(parts, " ")))
  local gauge, qm = c.gauge.emblem, c.qmark
  H.assertEq(c.gauge.count, gauge, "the shield count draws in the emblem's colour")
  for _, ic in ipairs(c.icons) do
    local name, col = ic[1], ic[2]
    H.assertEq(col == gauge, SHARE_WHITE[name] == true,
      string.format("the %s icon's colour (%04X) %s the shield gauge's (%04X)", name, col,
        SHARE_WHITE[name] and "is" or "is not", gauge))
    H.assertEq(col == qm, SHARE_GREY[name] == true,
      string.format("the %s icon's colour (%04X) %s the '?' colour (%04X)", name, col,
        SHARE_GREY[name] and "is" or "is not", qm))
  end
  local r, g, b = rgb(gauge)
  H.assertEq(r == g and g == b and r >= 28, true,
    string.format("the shield gauge is plain white (got %04X)", gauge))
  local qr, qg, qb = rgb(qm)
  H.assertEq(qr == qg and qg == qb and qr >= 8 and qr <= 23, true,
    string.format("an unrevealed weakness's '?' is a mid grey (got %04X)", qm))
  H.assertEq(r - qr >= 8, true, "the '?' grey stands well apart from the gauge's white")
end
-- the head's weakness cells while nothing is revealed: its fire '?' and its
-- PIERCE '?', both in the '?' attribute
local function qmarksShown()
  local a = headLine()
  return a ~= nil and vword(a + 1) == (H.HUD_QMARK_ATTR << 8) | 0xBF
    and vword(a + 2) == (H.HUD_QMARK_ATTR << 8) | 0xBF
end
local function brokenShown()
  local a, lead, count = headLine()
  return a ~= nil and lead == (BROKEN_ATTR << 8) | slotCell(hs) and count == 0x21FF
    and tileIs(slotCell(hs), 100)
end
-- a slot's own palette bits, assigned the way LoadMonsterPal does: twice
-- the index of its palette id in the loaded list (0 when not among the three)
local function ownBits(s)
  local id = H.readWord(MONPAL + s * 2)
  for k = 0, 2 do
    if H.readWord(LOADED + k * 2) == id then return k * 2 end
  end
  return 0
end
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

-- #542: every hit on the head, judged.  CalcTargetDmg's entry is the head's
-- state before the hit (no chip of this hit has run: Ot6Chip sits in its
-- weak branch, the rest in Ot6HitJoin); $f0 at Ot6HitJoin's entry is the
-- damage OT6's factor receives (vanilla's elemental x2 included), and $f0 at
-- CalcMaxDmg, the next call after the join, is what it leaves.  Read only.
local hits, cur = {}, nil
local function armHitWatch()
  emu.addMemoryCallback(function()
    local y = emu.getState()["cpu.y"] & 0xFF
    if hs == nil or y ~= 8 + hs * 2 then cur = nil; return end
    cur = { sh = H.readByte(SHLD + hs * 2), brk = H.readByte(TIMER + hs * 2) ~= 0, f = H.frame }
  end, emu.callbackType.exec, H.sym("CalcTargetDmg"))
  emu.addMemoryCallback(function()
    if cur then cur.din = H.readWord(0xF0) end
  end, emu.callbackType.exec, H.sym("Ot6HitJoin"))
  emu.addMemoryCallback(function()
    if cur and cur.din then
      cur.dout, cur.heal = H.readWord(0xF0), (H.readByte(0xF2) & 1) == 1
      cur.broke = not cur.brk and H.readByte(TIMER + hs * 2) ~= 0
      hits[#hits + 1] = cur
      H.log(string.format("[hit] f%d head before: shields %d broken %s; damage %d -> %d%s",
        cur.f, cur.sh, tostring(cur.brk), cur.din, cur.dout, cur.broke and " (this hit broke it)" or ""))
    end
    cur = nil
  end, emu.callbackType.exec, H.sym("CalcMaxDmg"))
end
-- what OT6's factor owes a hit, from the state before it: shielded x0.5
-- (Ot6ShieldedMulW's 8/16, floored), Broken x2 (under vanilla's sign guard)
local function owed(h)
  if h.heal then return h.din end
  if h.brk then return h.din < 0x8000 and h.din * 2 or h.din end
  if h.sh > 0 then return h.din // 2 end
  return h.din
end
local function checkHits(what)
  for _, h in ipairs(hits) do
    H.assertEq(h.dout, owed(h), string.format(
      "%s: the hit at f%d (shields %d, broken %s before it%s) is judged on the state before it lands",
      what, h.f, h.sh, tostring(h.brk), h.broke and ", and it broke the head" or ""))
  end
end

local function report(tag)
  return H.call(function()
    H.log(string.format(
      "%s shields=%d/%d timer=%02X revealed=%02X hp=%d alive=%s",
      tag, shields(), maxShield(), timer(), revealed(), headHp(),
      tostring(headAlive())))
  end)
end

-- per-frame HP watcher on the head: every discrete drop is recorded with the
-- broken-timer state at observation time.  The breaking hit's damage is
-- computed in the same CalcTargetDmg call that sets the timer (chip runs
-- before the broken-double join), and the HP write lands frames later during
-- the animation, so a drop observed with the timer up is a hit that ran the
-- broken-double path.
local drops = {}
local prevHp, prevShellHp = nil, nil
local function sampleDrops()
  local hp = headHp()
  if prevHp ~= nil and hp < prevHp then
    local d = prevHp - hp
    drops[#drops + 1] = { d = d, broken = timer() ~= 0 }
    H.log(string.format("hp drop: head -%d (timer %02X, shields %d)",
      d, timer(), shields()))
  end
  prevHp = hp
  local sh = H.readWord(MHP + shell * 2)
  if prevShellHp ~= nil and sh < prevShellHp then
    H.log(string.format("hp drop: shell -%d (a beam that missed the head's window)",
      prevShellHp - sh))
  end
  prevShellHp = sh
end

-- ------------------------------------------------------------- driver --
-- Sequences run from the settled top command menu, on the MagiTek cursor:
--   beam at the default target    A A A
--   Heal Force (2,0), both lists  A dn dn A A  (self-target by default)
-- Only Terra beams, so every drop on the head is one caster's Fire Beam.
-- Vicks and Wedge heal, and Terra heals on any turn she doesn't beam.
--
-- When Terra beams is read off the shell, whose own turn is what hides and
-- shows the head (AIScript _256: each turn past its 10-tick timer toggles
-- the head).  A beam lands 165-527 frames after it is ordered, so a beam
-- ordered while the shell's turn is near lands after the hide, retargets
-- to the shell, and the shell answers with its Mega Volt counter.  At
-- shift 40 on 594e2fa1 that happened twice and the second counter killed
-- Terra (77 HP max, 52 left after two head hits): the old driver beamed
-- whenever the head was up, nobody could revive her, and the drive timed
-- out with two of four shields gone
-- (build/attempts/wt/break-draws/diag3-s40.log).  Across shifts 20/40/45,
-- every beam ordered with the shell's gauge already full or its turn
-- running ($3AA0 bits 3/5/6) went to the shell, and every beam ordered on
-- a running gauge at 16..150 of 256 hit the head; the gauge gained at most
-- 111 between order and landing, and the one order at 235 strayed.  The
-- old driver failed 19 of 60 shifts (60 distinct battle keys) this way:
-- 10 with Terra killed by a counter, 9 with her alive but 9-12 of her
-- beams spent on the shell, too few on the head inside the budget
-- (build/attempts/wt/break-draws/summary-nc-oldpolicy.txt).
--
-- Terra's turns tend to arrive just as the shell's does, so beaming only
-- when her turn happens to open inside the window starved the drive (one
-- beam in 40000 frames at shift 40, build/attempts/wt/break-draws/
-- try1-s40.log).  So she waits for it the way a player would: her command
-- menu stays open until the head is up and the shell's gauge has restarted
-- and sits in its first half, then she beams.  Battle time runs at the top
-- menu (wait mode stops it only in the lists): in try2-s40.log Terra held
-- from f2728 (shell gauge 0, flags $29: its turn queued) to f4888 (gauge 9,
-- flags $01: that turn and the next one ran, the head up again).  Below half HP she heals instead of waiting, so a stray that slips
-- through anyway costs a counter she survives rather than the fight.
--
-- The owner's way (everyone Fire Beams while the head shows, Heal Forces
-- while it hides, no menu held) breaks the head faster (3758-7951 frames)
-- and plays more like a person, but it is not this file's policy: at 4 of
-- 60 shifts a second beam already ordered when the head broke landed
-- broken and killed it, so the fight ended with nothing left to recover
-- (build/attempts/wt/whelk-rhythm/summary-rhythm2.txt).
local BEAM = { "a", "a", "a" }
local HEAL = { "a", "down", "down", "a", "a" }
local GAUGE_OPEN = 128
local mStreak, mSeq, mIdx, mStall, mNoMenu = 0, nil, 1, 0, 0
local beamsOrdered = 0
local holding = false

local function shellGauge() return H.readByte(MGAUGE + shell * 2) end
local function beamWindow()
  local g = shellGauge()
  return headAlive() and (H.readByte(MFLAGS + shell * 2) & 0x68) == 0
     and g > 0 and g < GAUGE_OPEN
end
local function terraHp() return H.readWord(PHP + terra * 2) end
local function terraSafe()
  return terraHp() * 2 > H.readWord(PMAXHP + terra * 2)
end

-- the sequence for this window's owner, or nil to hold the menu open.
-- In the branch after the break (3b) everyone beams while the head shows,
-- so a hit reaches it inside its Broken window.
local beamAll = false
local function seqFor(actor)
  if beamAll then return headAlive() and BEAM or HEAL end
  if actor ~= terra then return HEAL end
  local why = (not terraSafe() and "heal") or (beamWindow() and "beam")
    or "hold"
  if why ~= "hold" or not holding then
    H.log(string.format("terra turn f%d: %s (head up=%s, shell gauge=%d "
      .. "flags=%02X, terra hp=%d/%d)", H.frame, why,
      tostring(headAlive()), shellGauge(), H.readByte(MFLAGS + shell * 2),
      terraHp(), H.readWord(PMAXHP + terra * 2)))
  end
  holding = why == "hold"
  if why == "beam" then
    beamsOrdered = beamsOrdered + 1
    return BEAM
  end
  if why == "heal" then return HEAL end
  return nil
end

-- Terra is the only beamer and nothing in this fight revives her, so her
-- fall ends the measurement: say so instead of driving out the budget.
local function assertTerraUp()
  if terraHp() == 0 then
    error(string.format("TERRA fell (the only beamer; nothing here revives) "
      .. "with the head at %d/4 shields after %d beam(s) ordered",
      shields(), beamsOrdered), 0)
  end
end

local function policyPulse()
  if H.readByte(MENU) == 0 then
    mStreak, mSeq, mIdx, mStall, holding = 0, nil, 1, 0, false
    mNoMenu = mNoMenu + 1
    return mNoMenu % 2 == 0 and { "a" } or {}
  end
  mNoMenu = 0
  mStreak = mStreak + 1
  if mStreak < 4 then return {} end
  if mSeq == nil then
    mSeq, mIdx = seqFor(H.readByte(ACTOR)), 1
    if mSeq == nil then return {} end   -- Terra waits at her open menu
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
    for s = 0, 3 do
      if H.readByte(CHID + s * 2) == CHAR_TERRA then terra = s end
    end
    H.assertEq(terra ~= nil, true, "TERRA has a party slot (the only beamer)")
    H.log(string.format("head slot %d, shell slot %d, terra slot %d",
      hs, shell, terra))
    armHitWatch()

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
  -- 1h. the gauge under the head
  H.waitUntil(function() return gaugeShown() end, 600,
    "the head's shield gauge drawn: emblem, then its count tile, palette 0", 1),
  H.call(function()
    colourCheck()
    local _, lead, count = headLine()
    H.assertEq(lead >> 8, GAUGE, "the shield emblem draws under the gauge attribute (palette 0)")
    H.assertEq(count >> 8, GAUGE, "the shield count draws under the gauge attribute (palette 0)")
    H.assertEq(qmarksShown(), true,
      "the head's two unrevealed weaknesses drawn as '?' in the '?' attribute")
    H.assertEq(palsLoaded() < 3, true,
      "precondition: the formation left a monster palette unloaded (the spare v0.45's grey took)")
    H.assertEq(palBits(hs), ownBits(hs), "the head starts on its own palette")
    H.screenshot("break_gauge")
  end),

  -- 2+3. Terra beams the head until it breaks (watcher rides the pred)
  H.driveUntil(function()
    sampleDrops()
    assertTerraUp()
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
    -- 3b. broken x2 for a flags3-$20 beam: the head's drop record is
    -- [unbroken chip(s)..., the breaking hit]; the breaking hit ran with the
    -- timer up and must be ~4x the first unbroken chip.  Every drop is one
    -- caster's Fire Beam, so the ratio needs no stat equalization.
    local parts = {}
    for _, e in ipairs(drops) do
      parts[#parts + 1] = string.format("%d%s", e.d, e.broken and "B" or "")
    end
    H.log(string.format("head drop record: %s", table.concat(parts, " ")))
    H.assertEq(#drops >= 2, true, "two chip hits recorded on the head")
    local first, last = drops[1], drops[#drops]
    H.assertEq(first.broken, false, "first chip landed unbroken")
    H.assertEq(last.broken, true, "breaking hit landed with the timer up")
    -- #542: the breaking beam landed on a shielded head, so its drop is
    -- the chip's (weak x2 * shielded x0.5 both), inside vanilla's spread
    -- [224/255, 255/224]; v0.45's was ~4x (190 190 193 784B)
    H.assertEq(last.d * 100 >= first.d * 85 and last.d * 100 <= first.d * 118, true,
      string.format("the breaking beam's drop (%d) is the shielded chip's (%d), not the Broken double",
        last.d, first.d))
    checkHits("to the break")
    local brk = 0
    for _, h in ipairs(hits) do
      if h.broke then
        brk = brk + 1
        H.assertEq(h.sh, 1, "the breaking hit found one shield left")
        H.assertEq(h.dout, h.din // 2, "the breaking hit is halved as a shielded hit (#542)")
      end
    end
    H.assertEq(brk, 1, "exactly one hit broke the head, and the watcher saw it")
    H.screenshot("break_broken")
  end),
  -- 3b, the branch: from a snapshot at the break, everyone beams while the
  -- head shows until a hit lands on it Broken, which is doubled; then the
  -- run goes back to the snapshot, so 3h and 4 see the head as the break
  -- left it.
  H.call(function()
    H.setPad({})
    H.vars.brkSnap = H.requestSaveState()
  end),
  H.waitFrames(2),
  H.call(function()
    H.checkReq(H.vars.brkSnap, "snapshot at the break")
    H.vars.hitsAtBreak = #hits
    beamAll = true
    mStreak, mSeq, mIdx, mStall, holding = 0, nil, 1, 0, false
  end),
  H.driveUntil(function()
    for i = H.vars.hitsAtBreak + 1, #hits do
      if hits[i].brk then return true end
    end
    if timer() == 0 then
      error(string.format("the head recovered (timer 0, shields %d) before a hit landed on it Broken",
        shields()), 0)
    end
    return false
  end, 6000, { H.call(pulseTick) }, "a hit on the Broken head"),
  H.call(function()
    H.setPad({})
    checkHits("after the break")
    local h
    for i = H.vars.hitsAtBreak + 1, #hits do
      if hits[i].brk then h = hits[i]; break end
    end
    H.assertEq(h.dout, h.din * 2, "a hit on the head already Broken is doubled")
    H.vars.numAt = H.readByte(0x632E)
  end),
  -- the doubled beam's numeral on the head (the manual's picture of a
  -- break, tools/manual/shots.py "break"): the numeral counter moves, on a
  -- thread aimed at the head (target 4 + its slot)
  H.waitUntil(function()
    local c = H.readByte(0x632E)
    return c ~= H.vars.numAt and c ~= 0 and H.readByte(0x631E + ((c - 1) & 3)) == 4 + hs
  end, 900, "the doubled beam's numeral on the head", 1),
  H.waitFrames(12),
  H.call(function()
    H.screenshot("break_double")
    beamAll = false
    mStreak, mSeq, mIdx, mStall, holding = 0, nil, 1, 0, false
    H.vars.backReq = H.requestLoadState(H.vars.brkSnap.blob)
  end),
  H.waitFrames(2),
  H.call(function()
    H.checkReq(H.vars.backReq, "back to the snapshot at the break")
    H.rearmInputInjection()
  end),
  -- 3h. broken: the broken shield in the gauge, and the head on its own
  -- palette (#543).  The head may be retracted into its shell for a while.
  H.waitUntil(function() return brokenShown() end, 3000,
    "the broken head's gauge shows the broken shield", 1),
  -- the grey stood the head on a spare palette (one the formation left
  -- unloaded, bits 2*palsLoaded()..4) for as long as it was broken; now it
  -- never does.  Palette 3 (bits 6) is the engine's own flash and retract
  -- animations' and is not the grey's.
  H.call(function() H.vars.onSpare, H.vars.spareSeen = 0, 0 end),
  H.repeatN(180, { H.call(function()
    local b = palBits(hs)
    if b < 6 and b // 2 >= palsLoaded() then H.vars.onSpare = H.vars.onSpare + 1 end
    if timer() > 0 then H.vars.spareSeen = H.vars.spareSeen + 1 end
  end), H.waitFrames(1) }),
  H.call(function()
    H.assertEq(H.vars.spareSeen, 180, "the head stayed broken through the look")
    H.assertEq(brokenShown(), true, "the gauge shows the broken shield and no count")
    H.assertEq(H.vars.onSpare, 0,
      "the broken head's sprite never stands on a spare palette: no grey (#543)")
    H.assertEq(palBits(shell), ownBits(shell), "the shell keeps its own palette")
    H.screenshot("break_broken_look")
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
  -- The recovery is only a recovery while the head lives: a head killed
  -- after its break ends the battle (AIScript _308, boss_death), and the
  -- field then reads timer 0 and shields 4 at its old slot whatever
  -- happened, so a dead head would pass the wait below without anything
  -- having recovered.  Watch its HP every frame of the wait.
  H.waitUntil(function()
    if headHp() == 0 then
      error(string.format("the head died after its break (hp 0, timer %02X, "
        .. "shields %d), so the battle ended before its recovery could be "
        .. "observed", timer(), shields()), 0)
    end
    return timer() == 0 and shields() == 4
  end, 12000, "broken head to recover", 1),
  H.waitFrames(30),
  report("recovered"),
  H.call(function()
    H.assertEq(headHp() > 0, true, "the head is alive at its recovery")
    H.assertEq(shields(), 4, "shields restored to max")
    H.assertEq(revealed() & 0x01, 0x01, "revealed weakness survives recovery")
  end),
  H.call(function()
    H.assertEq(palBits(hs), ownBits(hs), "the recovered head draws from its own palette")
    H.screenshot("break_recovered")
  end),
})
