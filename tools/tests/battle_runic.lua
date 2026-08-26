-- @suite slow
-- battle_runic.lua -- Celes's Runic absorb pays MP and a boost point, and a
-- boosted raise buys the stance N turns of duration.
--
-- Cmd_0b sets $3E4C.2 on the actor and ends her turn; RunicEffect resolves
-- the next runic-able attack, clears the stance bit, and retargets it into
-- an MP restore.  Ot6RunicBP additionally banks +1 BP, capped at 5.
-- Ot6RunicRaise latches OT6_RUNICTURNS from the pending boost; Ot6RunicHold
-- ticks it down each of Celes's QueueActions and holds the stance up while
-- it is nonzero; the BP earn from an absorb landing on a held stance is
-- capped at +1 per round.
--
-- Celes is installed over a live party slot (CHAR::CELES $06 into $3ED8, a
-- Runic-only command list at $202E stride 12, magitek status cleared) and
-- raises the stance through a muddle-into-single-command idiom.  A spell's
-- runic-able flag is MagicProp byte 3 bit 3, read live out of the ROM via
-- H.sym so the test tracks shipped data rather than a hardcoded list:
--   negative: magitek status left on, so muddle rolls MagiTek beams (bit 3
--     clear).  The stance stays up, MP is flat, and BP is flat.
--   positive: magitek cleared and a Magic-only list, so she rolls real
--     magic (Fire $00, Cure $2D, bit 3 set).  The stance clears, MP rises,
--     and BP goes up by 1.
--
-- Phases: 1-2 enter the stance and baseline the bank; 2. negative control;
-- 3. positive (MP and +1 BP); 4. the party-window pip glyph reflects the
-- new bank; 5. the bank caps at 5 rather than wrapping, and an unboosted
-- Runic latches 0 turns; 6. a boosted raise latches N turns per tier;
-- 7. several absorbs landing in one round of a held stance bank only +1 BP
-- total, not one per absorb; 8. the stance survives exactly the paid turns
-- and drops on the next one.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_entry.mss.lua"

local CELES = 0x06                   -- character id, $3ED8 stride 2
local CMD_RUNIC, CMD_MAGIC = 0x0b, 0x02
local RUNIC_BIT = 0x04               -- $3E4C.2, set by Cmd_0b
local MAGIC_PROP = H.sym("MagicProp") & 0x3FFFFF   -- PRG offset, survives C4 growth
local MUDDLE, MAGITEK, STOP = 0x20, 0x08, 0x10
-- Ot6PipCellTbl (ot6.asm): pip cluster cell per spendable bp 0-5
local PIP = { [0] = 0x72, 0x73, 0x75, 0x76, 0x77, 0x79 }

-- OT6_RUNICTURNS / OT6_RUNICPAID (ot6_memory.inc), in the shadow tail
local RUNICTURNS, RUNICPAID = 0xed8e, 0xed96
local CMD_FIGHT = 0x00

local function bp(s)     return H.readByte(0x3e9c + s * 2) end
local function turns(s)  return H.readByte(RUNICTURNS + s * 2) end
local function pend(s)   return H.readByte(0x3e9d + s * 2) end
local function mp(s)     return H.readWord(0x3c08 + s * 2) end
local function hp(s)     return H.readWord(0x3bf4 + s * 2) end
local function stance(s) return H.readByte(0x3e4c + s * 2) & RUNIC_BIT ~= 0 end
local function st1(s)    return 0x3ee4 + s * 2 end   -- status 1 (magitek)
local function st2(s)    return 0x3ee5 + s * 2 end   -- status 2 (muddle)
local function st3(s)    return 0x3ef8 + s * 2 end   -- status 3 (stop)

-- the spell's own absorb flag, read out of the shipped table
local function runicable(id)
  return H.readRomByte(MAGIC_PROP + id * 14 + 3) & 0x08 ~= 0
end

-- party-window pip cell for an arbitrary menu row.  lib's pipWord() is
-- row 0 only; Ot6Boost derives the same address as $7800 + (1+row*2)*32
-- + 20 words, which is byte 0x68 + row*0x80 from the map base.
local function pipWordRow(row)
  local reg = H.readByte(0x897f)
  local base = ((reg - (reg % 4)) * 256) * 2
  return emu.readWord(base + 0x68 + row * 0x80, emu.memType.snesVideoRam)
end

local function rowOf(slot)
  for r = 0, 3 do
    if H.readByte(0x64d6 + r) == slot then return r end
  end
  return nil
end

local terra, celes = nil, nil
local spells, mark, cycles = {}, 0, 0
local holdCeles = false   -- see pin(): keeps her in the stance, off the queue
-- while nonzero, pin() keeps this many BP pending on Celes so that whatever
-- turn she next takes is a boosted one.  The boost is read at the action
-- rather than at the menu, so this is re-armed every frame until the thing
-- under test has happened, then cleared.
local armBoost = 0
-- the single command pin() keeps in Celes's list.  Runic for every phase that
-- needs her to raise the stance, and Fight for the expiry walk, where she has
-- to take ordinary turns; a Runic-only list would re-raise the stance on each
-- one and the duration could never be observed running out.
local celesCmd = CMD_RUNIC
local droppedEarly = false

-- Frames on which Celes's stance bit went from set to clear.  A clear
-- paired with an absorbable id resolved in the same window is RunicEffect
-- ending the stance; a clear without one is a turn she was held out of.
local stanceClears = {}
local stanceUp = false    -- shadow of $3E4C.2, kept from the written value


-- the newest resolved id of the requested class since the phase mark
local function sawClass(want)
  for i = mark + 1, #spells do
    if runicable(spells[i]) == want then return spells[i] end
  end
  return nil
end

local function countClass(want, from)
  local n = 0
  for i = from + 1, #spells do
    if runicable(spells[i]) == want then n = n + 1 end
  end
  return n
end

local function idList(from)
  local out = {}
  for i = from + 1, #spells do
    out[#out + 1] = string.format("%02x%s", spells[i],
      runicable(spells[i]) and "*" or "")
  end
  return table.concat(out, " ")
end

-- held every frame: guards never act, nobody dies out from under a
-- measurement, and Celes keeps her installed identity
local function pin()
  H.writeByte(0x3f04, H.readByte(0x3f04) | STOP)
  H.writeByte(0x3f06, H.readByte(0x3f06) | STOP)
  H.writeWord(0x3c00, 3000)
  H.writeWord(0x3c02, 3000)
  for s = 0, 3 do
    if hp(s) > 0 then H.writeWord(0x3bf4 + s * 2, 400) end
  end
  -- keep the caster (Terra) solvent: a broke caster still writes her spell
  -- to $3410 but the action never resolves.  Celes's own MP is not pinned
  -- -- it is the measurement.
  if terra then H.writeWord(0x3c08 + terra * 2, 200) end
  -- Hold Celes out of the turn order once she is in the stance: she must
  -- not act (a turn clears $3E4C.2) but must not be stopped either
  -- (RunicEffect's CheckStatus gate drops a stopped runic-er).  Her ATB
  -- ($3219,X, counts down to 0=full) is held un-ready instead, leaving
  -- every flag RunicEffect reads untouched.
  if holdCeles and celes then H.writeByte(0x3219 + celes * 2, 0x60) end
  if armBoost > 0 and celes then
    H.writeByte(0x3e9c + celes * 2, 5)          -- a bank she can spend from
    H.writeByte(0x3e9d + celes * 2, armBoost)   -- ...and the pending spend
  end
  if celes then
    -- give her a pool to absorb into: the slot she is installed over has 0
    -- max MP, which would clamp the MP half of the absorb invisible.
    -- Max only; current MP is the measurement and is never pinned.
    H.writeWord(0x3c30 + celes * 2, 99)
    H.writeByte(0x3ed8 + celes * 2, CELES)
    H.writeByte(st1(celes), H.readByte(st1(celes)) & ~MAGITEK & 0xff)
    H.writeByte(0x202e + celes * 12, celesCmd)
    H.writeByte(0x2031 + celes * 12, 0xff)
    H.writeByte(0x2034 + celes * 12, 0xff)
    H.writeByte(0x2037 + celes * 12, 0xff)
  end
end

-- park everyone who is neither the caster nor the rune knight
local function benchOthers()
  for s = 0, 3 do
    if s ~= terra and s ~= celes and hp(s) > 0 then
      H.writeByte(st3(s), H.readByte(st3(s)) | STOP)
    end
  end
end

-- a wait that keeps holding the pins (plain waitFrames does not)
local function pinnedWait(n)
  return H.repeatN(n, { H.call(pin), H.waitFrames(1) })
end

-- Service other characters' menus while waiting: a ready character's open
-- menu parks the action queue, so confirming it lets the queue move so the
-- muddled caster can cast.  Never Celes's own menu, which would spend her
-- turn and drop the stance.
local function serviceWait(cycles_)
  return H.repeatN(cycles_, {
    H.call(function()
      pin()
      if H.readByte(0x7bca) ~= 0 and H.readByte(0x62ca) ~= celes then
        H.setPad({ "a" })
      end
    end),
    H.waitFrames(4),
    H.call(function() H.setPad({}) end),
    H.waitFrames(26),
  })
end

local function muddle(s, on)
  local v = H.readByte(st2(s))
  H.writeByte(st2(s), on and (v | MUDDLE) or (v & ~MUDDLE & 0xff))
end

-- arm Terra to roll one class of attack: beams (magitek status left on)
-- or real magic (magitek cleared, Magic-only list)
local function armTerra(magic)
  local v = H.readByte(st1(terra))
  H.writeByte(st1(terra), magic and (v & ~MAGITEK & 0xff) or (v | MAGITEK))
  H.writeByte(0x202e + terra * 12, magic and CMD_MAGIC or 0x0f)
  H.writeByte(0x2031 + terra * 12, 0xff)
  H.writeByte(0x2034 + terra * 12, 0xff)
  H.writeByte(0x2037 + terra * 12, 0xff)
end

-- drive Celes into the stance for real, then freeze her there.
-- (repeatN(1, ...) is the public way to fold a step LIST into the single
-- step object H.run's sequencer expects.)
--
-- The window is made absorb-proof before it opens: the caster is disarmed
-- to the beam family (which RunicEffect's gate refuses) and her queue
-- drained ($32CC,x = $ff, "nothing queued") before the stance goes up, so
-- no runic-able spell can resolve mid-raise and clear the stance before
-- the test observes it.
local function enterRunic(label)
  return H.repeatN(1, {
    H.call(function()
      muddle(terra, false)
      armTerra(false)           -- beams only: nothing absorbable can commit
    end),
    H.driveUntil(function() return H.readByte(0x32cc + terra * 2) == 0xff end,
      6000, { H.call(pin), H.waitFrames(1) },
      "the caster has nothing absorbable queued (" .. label .. ")"),
    -- she needs a turn to raise the stance, so let her back onto the
    -- queue for exactly as long as that takes
    H.call(function() holdCeles = false end),
    H.driveUntil(function()
      return H.readByte(0x7bca) ~= 0 and H.readByte(0x62ca) ~= celes
    end, 6000, {
      H.call(function()
        pin()
        if H.readByte(0x7bca) ~= 0 and H.readByte(0x62ca) == celes then
          H.setPad({ "a" })
        end
      end),
      H.waitFrames(4),
      H.call(function() H.setPad({}) end),
      H.waitFrames(20),
    }, "a menu that is not Celes's (" .. label .. ")"),
    H.driveUntil(function() return stance(celes) end, 8000, {
      H.call(function()
        pin(); muddle(celes, true)
        -- muddled, she owns no menu, but somebody else's open menu will
        -- park the queue and starve her of the turn she needs
        if H.readByte(0x7bca) ~= 0 and H.readByte(0x62ca) ~= celes then
          H.setPad({ "a" })
        end
      end),
      H.waitFrames(4),
      H.call(function() H.setPad({}) end),
      H.waitFrames(16),
    }, "Celes raises Runic (" .. label .. ")"),
    H.call(function()
      muddle(celes, false)
      holdCeles = true          -- stance is up: freeze her out of the turn order
      H.log(string.format("%s: runic up ($3e4c=$%02x), bp=%d mp=%d",
        label, H.readByte(0x3e4c + celes * 2), bp(celes), mp(celes)))
    end),
  })
end

-- run one cast phase: arm Terra, wait for an attack of the wanted class
-- to resolve, and hand back what changed
local function castPhase(want, label, maxFrames)
  return H.repeatN(1, {
    H.call(function()
      mark = #spells
      armTerra(want)
    end),
    H.driveUntil(function() return sawClass(want) ~= nil end, maxFrames, {
      H.call(function()
        pin(); benchOthers(); muddle(terra, true)
        if H.readByte(0x7bca) ~= 0 and H.readByte(0x62ca) ~= celes then
          H.setPad({ "a" })
        end
        cycles = cycles + 1
        if cycles % 50 == 0 then    -- only chatters if a phase is dragging
          H.log(string.format("  %s waiting: menu=$%02x actor=%d "
            .. "caster[atb=$%02x mp=%d] celes[atb=$%02x stance=%s] ids=%s",
            label, H.readByte(0x7bca), H.readByte(0x62ca),
            H.readByte(0x3219 + terra * 2), mp(terra),
            H.readByte(0x3219 + celes * 2), tostring(stance(celes)),
            idList(mark)))
        end
      end),
      H.waitFrames(4),
      H.call(function() H.setPad({}) end),
      H.waitFrames(16),
    }, label .. ": a " .. (want and "runic-able" or "non-runic-able")
       .. " attack resolves"),
    H.call(function() muddle(terra, false) end),
    serviceWait(8),                    -- let the action finish resolving
  })
end

-- raise the stance with N boost points pending, so Ot6RunicRaise latches N
-- turns of duration.  Wraps enterRunic; armBoost is cleared the instant the
-- stance is up, or every later turn would be boosted too.
--
-- Between arms the stance is reset to a fresh-battle state, or the next
-- arm's driveUntil(stance) would be satisfied by the previous arm's
-- still-standing stance and never exercise a real raise.
local function resetStance()
  H.writeByte(RUNICTURNS + celes * 2, 0)
  H.writeByte(0x3e4c + celes * 2,
    H.readByte(0x3e4c + celes * 2) & ~RUNIC_BIT & 0xff)
end

local function enterRunicBoosted(n, label)
  return H.repeatN(1, {
    H.call(function() resetStance(); armBoost = n end),
    enterRunic(label),
    H.call(function()
      armBoost = 0
      H.log(string.format("%s: runic up with %d pending -> OT6_RUNICTURNS=%d",
        label, n, turns(celes)))
      H.assertEq(turns(celes), n, string.format(
        "Ot6RunicRaise latched %d turns of stance from a %d-BP raise", n, n))
    end),
  })
end

-- let the caster land N absorbable spells into a standing stance.  This is
-- castPhase's twin, but it waits for a count rather than for one, because the
-- milking phase is about what several absorbs do to one bank.
local function milkPhase(n, label, maxFrames)
  return H.repeatN(1, {
    H.call(function()
      mark = #spells
      armTerra(true)
    end),
    H.driveUntil(function() return countClass(true, mark) >= n end, maxFrames, {
      H.call(function()
        pin(); benchOthers(); muddle(terra, true)
        if H.readByte(0x7bca) ~= 0 and H.readByte(0x62ca) ~= celes then
          H.setPad({ "a" })
        end
        cycles = cycles + 1
        if cycles % 50 == 0 then
          H.log(string.format("  %s waiting: %d/%d absorbed so far, "
            .. "celes[bp=%d mp=%d stance=%s turns=%d] ids=%s",
            label, countClass(true, mark), n, bp(celes), mp(celes),
            tostring(stance(celes)), turns(celes), idList(mark)))
        end
      end),
      H.waitFrames(4),
      H.call(function() H.setPad({}) end),
      H.waitFrames(16),
    }, label .. ": " .. n .. " absorbable spells resolve into the stance"),
    H.call(function() muddle(terra, false) end),
    serviceWait(8),
  })
end

-- drive Celes through ordinary turns, watching that the shield holds
local function turnWalk(untilFn, label, maxFrames)
  return H.driveUntil(untilFn, maxFrames, {
    H.call(function()
      pin(); benchOthers(); muddle(celes, true)
      if not stance(celes) then droppedEarly = true end
      if H.readByte(0x7bca) ~= 0 and H.readByte(0x62ca) ~= celes then
        H.setPad({ "a" })
      end
    end),
    H.waitFrames(4),
    H.call(function() H.setPad({}) end),
    H.waitFrames(16),
  }, label)
end

local before = {}
local function snapshot()
  before = { bp = bp(celes), mp = mp(celes), stance = stance(celes) }
end

-- Baseline the bank only after her own Runic turn has finished paying out:
-- the turn's own +1 regen lands later, at EndAction, so a bank pinned the
-- instant the stance appears would gain a point out from under the
-- measurement.  Settle, pin, then re-read.
local function baseline(value)
  local at, from = 0, 0
  return H.repeatN(1, {
    H.call(function() at, from = #spells, H.frame end),
    pinnedWait(180),
    H.call(function()
      H.writeByte(0x3e9c + celes * 2, value)
      H.writeByte(0x3e9d + celes * 2, 0)
      H.writeWord(0x3c08 + celes * 2, 1)   -- room for an absorb to show
    end),
    pinnedWait(90),
    H.call(function()
      -- An absorb landing inside the settle is the one event that clears
      -- the stance without moving the bank (at a full bank the +1 is
      -- capped away), so check the ids that resolved in the window instead.
      local stray = nil
      for i = at + 1, #spells do
        if runicable(spells[i]) then stray = spells[i] end
      end
      H.assertEq(stray and string.format("$%02x", stray) or "none", "none",
        "nothing absorbable resolved while the baseline settled")
      H.assertEq(bp(celes), value,
        "the bank settled at the baseline (no stray turn tick in the window)")
      -- with the absorb ruled out, any remaining clear in this window is a
      -- turn the ATB pin was supposed to prevent.
      local drops = 0
      for _, f in ipairs(stanceClears) do
        if f >= from then drops = drops + 1 end
      end
      H.assertEq(drops, 0,
        "and she took no turn while it settled (the ATB pin held)")
      H.assertEq(stance(celes), true, "and Runic is still standing")
      snapshot()
      H.log(string.format("baseline: bp=%d mp=%d stance=%s",
        before.bp, before.mp, tostring(before.stance)))
    end),
  })
end

H.run({ maxFrames = 200000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.enterEncounter(),
  H.waitFrames(240),

  -- ---------------------------------------------------------- install --
  H.call(function()
    for s = 0, 3 do
      if H.readByte(0x3ed8 + s * 2) == 0 then terra = s end
    end
    H.assertEq(terra ~= nil, true, "found Terra (the only natural caster here)")
    for s = 0, 3 do
      if s ~= terra and hp(s) > 0 and celes == nil then celes = s end
    end
    H.assertEq(celes ~= nil, true, "found a live slot to install Celes into")
    pin()
    benchOthers()
    emu.addMemoryCallback(function(_, v) spells[#spells + 1] = v end,
      emu.callbackType.write, 0x7e3410, 0x7e3410)
    -- Edge-detect off the written value rather than a read-back, so it does
    -- not depend on whether the write callback runs before or after the
    -- store lands.
    stanceUp = stance(celes)
    emu.addMemoryCallback(function(_, v)
      local was = stanceUp
      stanceUp = v & RUNIC_BIT ~= 0
      if was and not stanceUp then stanceClears[#stanceClears + 1] = H.frame end
    end, emu.callbackType.write, 0x7e3e4c + celes * 2, 0x7e3e4c + celes * 2)
    H.log(string.format("terra=slot %d, celes=slot %d (char id $%02x)",
      terra, celes, H.readByte(0x3ed8 + celes * 2)))
    -- the classifier itself must do something: check it separates the
    -- two families before anything depends on it
    H.assertEq(runicable(0x00), true, "MagicProp says Fire is runic-able")
    H.assertEq(runicable(0x2d), true, "MagicProp says Cure is runic-able")
    H.assertEq(runicable(0x17), false, "MagicProp says Merton is not")
    H.assertEq(runicable(0x8a), false, "MagicProp says TekMissile is not")
  end),

  -- ------------------------------------------------- 1. enter the stance --
  enterRunic("first"),
  H.call(function()
    H.assertEq(stance(celes), true, "Cmd_0b really set $3E4C.2")
    H.screenshot("runic_stance")
  end),
  baseline(2),                           -- a bank with room to grow

  -- ------------------------------- 2. negative control: an unabsorbable hit --
  castPhase(false, "negative", 20000),
  H.call(function()
    H.log("negative phase ids: " .. idList(mark)
      .. string.format("  | bp %d -> %d, mp %d -> %d, stance %s",
        before.bp, bp(celes), before.mp, mp(celes), tostring(stance(celes))))
    local id = sawClass(false)
    H.assertEq(id ~= nil, true, "a non-runic-able attack really resolved")
    H.assertEq(sawClass(true), nil,
      "and nothing runic-able slipped into the control window")
    -- the stance is untouched, which also shows Celes never took a turn
    -- (QueueAction would have cleared $3E4C.2), so the flat BP below is
    -- a real negative rather than a turn she happened not to get
    H.assertEq(stance(celes), true,
      "an unabsorbed attack leaves Runic standing (and Celes never acted)")
    H.assertEq(bp(celes), before.bp,
      "an attack Runic cannot eat banks NO bp")
    H.assertEq(mp(celes), before.mp,
      "and restores no mp either -- nothing was absorbed")
  end),

  -- ------------------------------------- 3. positive: the absorb pays both --
  baseline(2),
  castPhase(true, "positive", 24000),
  H.call(function()
    H.log("positive phase ids: " .. idList(mark)
      .. string.format("  | bp %d -> %d, mp %d -> %d, stance %s",
        before.bp, bp(celes), before.mp, mp(celes), tostring(stance(celes))))
    local id = sawClass(true)
    H.assertEq(id ~= nil, true, "a runic-able spell really resolved")
    H.assertEq(stance(celes), false,
      "RunicEffect consumed the stance ($3E4C.2 cleared)")
    -- positive control for the stance-clear watch itself: a real absorb
    -- just happened, so it must have caught at least one edge.
    H.assertEq(#stanceClears > 0, true,
      "the stance-clear watch registered this absorb (it is not blind)")
    H.assertEq(mp(celes) > before.mp, true,
      "the vanilla half still happens: the spell became MP")
    H.assertEq(bp(celes), before.bp + 1,
      "and the OT6 half: the absorb banked exactly +1 bp")
    H.assertEq(pend(celes), 0, "with nothing pending to spend")
    H.screenshot("runic_absorbed")
  end),

  -- ------------------------------------------------ 4. the player can see it --
  H.driveUntil(function()
    return H.readByte(0x7bca) ~= 0 and rowOf(celes) ~= nil
  end, 6000, {
    H.call(pin), H.waitFrames(4),
  }, "a battle menu open with Celes on screen"),
  H.waitFrames(30),
  H.call(function()
    local row = rowOf(celes)
    local w = pipWordRow(row)
    H.log(string.format("celes menu row %d: pip word $%04x (bank %d wants $%02x)",
      row, w, bp(celes), PIP[bp(celes)]))
    H.assertEq(w >> 8, 0x21, "the pip cell carries the pip palette")
    H.assertEq(w & 0xff, PIP[bp(celes)],
      "the party window shows the post-absorb bank, so the +1 is visible")
    H.screenshot("runic_pips")
  end),

  -- ------------------------------------------------------ 5. the bank cap --
  enterRunic("capped"),
  baseline(5),                           -- a full bank
  castPhase(true, "capped", 24000),
  H.call(function()
    H.log("capped phase ids: " .. idList(mark)
      .. string.format("  | bp %d -> %d, mp %d -> %d",
        before.bp, bp(celes), before.mp, mp(celes)))
    H.assertEq(sawClass(true) ~= nil, true, "a runic-able spell resolved again")
    H.assertEq(stance(celes), false, "and was absorbed")
    H.assertEq(mp(celes) > before.mp, true, "mp still restored at a full bank")
    -- a bare `inc` would read 6 here; a wrapped byte would read 0
    H.assertEq(bp(celes), 5, "an absorb at 5 bp stays 5 -- capped, not wrapped")
    -- everything above was an unboosted Runic: Ot6RunicRaise latches 0,
    -- Ot6RunicHold does nothing, and the stance restore is gated on the
    -- same 0.
    H.assertEq(turns(celes), 0,
      "an UNBOOSTED Runic latches no duration (phases 1-5 were vanilla)")
  end),

  -- ============================= boost buys the stance a duration ======
  --
  -- ------------------------------------ 6. the raise latches a duration --
  enterRunicBoosted(1, "boost1"),
  enterRunicBoosted(2, "boost2"),
  enterRunicBoosted(3, "boosted"),

  -- ------------------------------- 7. the milking test: the BP loop --
  -- Celes is held off the turn order throughout (enterRunic leaves holdCeles
  -- set), so no ActionEnd of hers fires and the whole phase is one round.
  -- Several absorbs, one round: the bank must move by exactly +1.
  baseline(2),
  milkPhase(3, "milked", 40000),
  H.call(function()
    local absorbs = countClass(true, mark)
    H.log(string.format("milked phase ids: %s  | %d absorbs, bp %d -> %d, "
      .. "mp %d -> %d, stance %s, turns %d", idList(mark), absorbs,
      before.bp, bp(celes), before.mp, mp(celes),
      tostring(stance(celes)), turns(celes)))
    -- first, check the phase did enough work: a phase that absorbed once
    -- would pass the +1 below for the wrong reason, and a phase that absorbed
    -- none would pass the stance assert too
    H.assertEq(absorbs >= 3, true,
      "several absorbable casts really landed on the standing stance")
    -- duration, half one: an absorb no longer ends the stance.
    H.assertEq(stance(celes), true,
      "the stance is STILL standing after all of them (absorbs no longer "
      .. "end it -- that is what the duration bought)")
    -- the ruling: once per round.  The count is of absorbable casts that
    -- resolved, an upper bound on absorb events rather than an exact count.
    H.assertEq(bp(celes), before.bp + 1, string.format(
      "%d absorbable casts inside one round bank exactly ONE bp -- the earn "
      .. "is capped per round, so an extended stance cannot refund the boost "
      .. "that bought it", absorbs))
    -- and the cap is on the BP only: the MP half is per absorb, untouched
    -- and uncapped -- vanilla's own restore.
    H.assertEq(mp(celes) > before.mp, true,
      "while every absorb still paid its MP -- only the BP earn is capped")
    H.screenshot("runic_milked")
  end),

  -- ------------------------------------------- 8. and it runs out --
  -- The duration is spent by Celes taking turns, one per QueueAction
  -- (Ot6RunicHold).  She is put back on the queue with a Fight-only list;
  -- Runic-only would re-raise the stance every turn.  The caster stays
  -- disarmed to beams for the whole walk, so nothing absorbable can touch
  -- $3E4C.2 except her own QueueAction.
  H.call(function()
    armTerra(false)               -- beams: nothing absorbable can interfere
    celesCmd = CMD_FIGHT          -- ordinary turns, not re-raises
    H.writeByte(0x202e + celes * 12, CMD_FIGHT)
    droppedEarly = false
    holdCeles = false             -- ...and let her onto the queue at last
    H.log(string.format("expiry walk begins: turns=%d stance=%s",
      turns(celes), tostring(stance(celes))))
    -- the walk's predicate is checked BEFORE its body, so if turns were
    -- already 0 it would return instantly and droppedEarly could never be
    -- observed.
    H.assertEq(turns(celes) > 0, true,
      "the expiry walk starts with shielded turns still owed")
  end),
  turnWalk(function() return turns(celes) == 0 end,
    "Celes spends all three shielded turns", 40000),
  H.call(function()
    H.log(string.format("counter ran out: turns=%d stance=%s bp=%d",
      turns(celes), tostring(stance(celes)), bp(celes)))
    H.assertEq(droppedEarly, false,
      "the stance stood through every one of the turns it paid for")
    H.assertEq(stance(celes), true,
      "and is still standing on the last of them -- she ACTED under it, "
      .. "which vanilla's QueueAction clear (:511) never allowed")
  end),
  turnWalk(function() return not stance(celes) end,
    "the turn AFTER the last one drops it", 40000),
  H.call(function()
    H.log(string.format("expired: turns=%d stance=%s", turns(celes),
      tostring(stance(celes))))
    H.assertEq(stance(celes), false,
      "3 BP bought three turns of shield, not a permanent one")
    H.assertEq(turns(celes), 0, "and the counter stays spent")
    H.screenshot("runic_expired")
  end),
})
