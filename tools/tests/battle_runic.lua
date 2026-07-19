-- battle_runic.lua -- Celes's signature: a Runic absorb pays MP *and* a
-- boost point.
--
--   tools/tests/run.sh tools/tests/battle_runic.lua
--
-- Vanilla already does the MP half.  Cmd_0b (battle_main.asm:4079-4085)
-- sets $3E4C.2 on the actor and ends her turn; the next runic-able attack
-- to resolve runs RunicEffect (:8483), which sweeps all ten entities,
-- clears the stance bit, drops anyone CheckStatus rejects, enrolls the
-- survivors in $EE and retargets the whole attack into an MP restore
-- aimed at them (:8517-8523).  OT6 adds one instruction's worth of hook
-- at the enrolment point -- Ot6RunicBP (ot6.asm) -- so the same absorb
-- also banks +1 BP, capped at 5 like every other BP source.
--
-- Celes is not recruitable until the v0.3 arc, so she is INSTALLED the
-- way battle_bushido installs Cyan: CHAR::CELES ($06) into $3ED8, a
-- Runic-only command list ($202E, stride 12), magitek status cleared.
-- She enters the stance for REAL through battle_fold's muddle idiom --
-- a confused character with a one-command list runs RandCharAction into
-- that command, no menu input -- and is un-muddled the moment the stance
-- bit appears, so nothing re-queues it (QueueAction :496-498 would clear
-- $3E4C.2 on her next action, which doubles as this test's guard that
-- she never took a turn mid-measurement).
--
-- THE CONTROL IS THE POINT.  Terra casts twice into the same standing
-- stance; the ONLY difference is the spell's own runic-able flag --
-- MagicProp byte 3 bit 3, the gate RunicEffect tests at :8486-8488.
-- Every id that reaches $3410 is classified by reading that byte out of
-- the ROM (C4/6AC0 -> PRG 0x046AC0), so the test asserts against the
-- shipped data rather than a hardcoded spell list:
--   negative -- magitek status left ON, so muddle rolls MagiTek beams
--     ($83-$8A, bit 3 CLEAR).  Stance stays up, MP flat, BP FLAT.
--   positive -- magitek cleared and a Magic-only list, so she rolls real
--     magic (Fire $00 / Cure $2D, bit 3 SET).  Stance clears, MP rises,
--     BP +1.
-- Same character, same stance, same turn state, same measurement -- so a
-- +1 that showed up in both would be a turn-tick regen, not an absorb,
-- and the negative phase fails loudly.  An Ot6RunicBP that unconditally
-- incremented, or one hooked before RunicEffect's gates, dies there.
--
-- Also asserted:
--   - the BANK CAP: an absorb at 5 BP stays 5.  It must not wrap to 0
--     (a plain inc) and must not mint a 6th pip Ot6Boost would let her
--     spend (`cmp $3e9c`, ot6.asm).
--   - the HUD really moves: the party-window pip glyph for Celes's own
--     menu row is read out of VRAM and must equal Ot6PipCellTbl's cell
--     for her new bank.  The pips stage from live $3E9C at window_open
--     (btlgfx_main.asm:9514-9516 -> DrawCharNames -> Ot6PipGlyph_ext),
--     so this is the assert that the absorb is visible to a player and
--     not just true in RAM.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"

local CELES = 0x06                   -- character id, $3ED8 stride 2
local CMD_RUNIC, CMD_MAGIC = 0x0b, 0x02
local RUNIC_BIT = 0x04               -- $3E4C.2, set by Cmd_0b
local MAGIC_PROP = 0x046AC0          -- MagicProp C4/6AC0 -> PRG offset
local MUDDLE, MAGITEK, STOP = 0x20, 0x08, 0x10
-- Ot6PipCellTbl (ot6.asm): pip cluster cell per spendable bp 0-5
local PIP = { [0] = 0x72, 0x73, 0x75, 0x76, 0x77, 0x79 }

local function bp(s)     return H.readByte(0x3e9c + s * 2) end
local function pend(s)   return H.readByte(0x3e9d + s * 2) end
local function mp(s)     return H.readWord(0x3c08 + s * 2) end
local function hp(s)     return H.readWord(0x3bf4 + s * 2) end
local function stance(s) return H.readByte(0x3e4c + s * 2) & RUNIC_BIT ~= 0 end
local function st1(s)    return 0x3ee4 + s * 2 end   -- status 1 (magitek)
local function st2(s)    return 0x3ee5 + s * 2 end   -- status 2 (muddle)
local function st3(s)    return 0x3ef8 + s * 2 end   -- status 3 (stop)

-- the spell's OWN absorb flag, straight out of the shipped table
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


-- the newest resolved id of the requested class since the phase mark
local function sawClass(want)
  for i = mark + 1, #spells do
    if runicable(spells[i]) == want then return spells[i] end
  end
  return nil
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
  -- keep the CASTER solvent.  She casts on a muddle roll over and over,
  -- and intro-stat MP runs out fast; a broke caster still writes her
  -- chosen spell to $3410 but the action never resolves, so the phase
  -- either times out or (worse) reports a spell that no RunicEffect ever
  -- saw.  Celes's MP is deliberately NOT pinned -- it is the measurement.
  if terra then H.writeWord(0x3c08 + terra * 2, 200) end
  -- HOLD CELES OUT OF THE TURN ORDER once she is in the stance.  She must
  -- not act (a turn would clear $3E4C.2 and pay a regen), but she also
  -- must not be STOPPED -- RunicEffect's CheckStatus gate drops a stopped
  -- runic-er outright (battle_main.asm:8500-8503), which would delete the
  -- very thing under test.  So instead her ATB is held un-ready: $3219,X
  -- counts down and 0 means full (UpdateBattleTime, battle_main.asm:2680),
  -- so a nonzero pin keeps her off the queue while leaving every flag
  -- RunicEffect actually reads untouched.  Without this she takes a turn,
  -- opens a menu, and that open menu parks the whole action queue -- the
  -- caster then never casts (measured: 24000 frames, nobody acting).
  if holdCeles and celes then H.writeByte(0x3219 + celes * 2, 0x60) end
  if celes then
    -- give her a POOL to absorb into.  The slot Celes is installed over
    -- belongs to a Narshe-raid trooper whose max MP ($3C30,X -- "max mp",
    -- battle_main.asm:13326) is 0, so vanilla's restore clamps straight
    -- back to 0 and the MP half of the absorb is invisible (measured:
    -- mp 1 -> 0 across a confirmed absorb).  Max only; her CURRENT MP is
    -- the measurement and is never pinned.
    H.writeWord(0x3c30 + celes * 2, 99)
    H.writeByte(0x3ed8 + celes * 2, CELES)
    H.writeByte(st1(celes), H.readByte(st1(celes)) & ~MAGITEK & 0xff)
    H.writeByte(0x202e + celes * 12, CMD_RUNIC)
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

-- SERVICE FOREIGN MENUS while waiting.  A ready character's open menu
-- parks the action queue: measured, every ATB byte sat full ($3219,X = 0)
-- for 24000 frames with one menu up and nobody acting.  Confirming it
-- lets the queue move so the muddled caster can cast.  Never Celes's own
-- menu -- that would spend her turn and drop the stance.
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
local function enterRunic(label)
  return H.repeatN(1, {
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
        -- muddled, she owns no menu -- but somebody else's open menu will
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

local before = {}
local function snapshot()
  before = { bp = bp(celes), mp = mp(celes), stance = stance(celes) }
end

-- Baseline the bank, but only AFTER her own Runic turn has finished
-- paying out.  Cmd_0b sets $3E4C.2 while the action executes; the turn's
-- +1 regen lands later, at EndAction (Ot6ActionEnd) -- so a bank pinned
-- the instant the stance appears gets one point added out from under the
-- measurement, which is exactly how the first draft of this test read
-- +1 in its own negative control.  Settle, pin, then re-read: the assert
-- makes a stray turn tick fail HERE and loudly, instead of quietly
-- becoming the +1 a later phase would credit to the absorb.
local function baseline(value)
  return H.repeatN(1, {
    pinnedWait(180),
    H.call(function()
      H.writeByte(0x3e9c + celes * 2, value)
      H.writeByte(0x3e9d + celes * 2, 0)
      H.writeWord(0x3c08 + celes * 2, 1)   -- room for an absorb to show
    end),
    pinnedWait(90),
    H.call(function()
      H.assertEq(bp(celes), value,
        "the bank settled at the baseline (no stray turn tick in the window)")
      H.assertEq(stance(celes), true, "and Runic is still standing")
      snapshot()
      H.log(string.format("baseline: bp=%d mp=%d stance=%s",
        before.bp, before.mp, tostring(before.stance)))
    end),
  })
end

H.run({ maxFrames = 60000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
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
    H.log(string.format("terra=slot %d, celes=slot %d (char id $%02x)",
      terra, celes, H.readByte(0x3ed8 + celes * 2)))
    -- the classifier itself must not be vacuous: prove it separates the
    -- two families before anything leans on it
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

  -- ------------------------------- 2. NEGATIVE CONTROL: an unabsorbable hit --
  castPhase(false, "negative", 20000),
  H.call(function()
    H.log("negative phase ids: " .. idList(mark)
      .. string.format("  | bp %d -> %d, mp %d -> %d, stance %s",
        before.bp, bp(celes), before.mp, mp(celes), tostring(stance(celes))))
    local id = sawClass(false)
    H.assertEq(id ~= nil, true, "a non-runic-able attack really resolved")
    H.assertEq(sawClass(true), nil,
      "and nothing runic-able slipped into the control window")
    -- the stance is untouched, which also proves Celes never took a turn
    -- (QueueAction would have cleared $3E4C.2) -- so the flat BP below is
    -- a real negative, not a turn she happened not to get
    H.assertEq(stance(celes), true,
      "an unabsorbed attack leaves Runic standing (and Celes never acted)")
    H.assertEq(bp(celes), before.bp,
      "an attack Runic cannot eat banks NO bp")
    H.assertEq(mp(celes), before.mp,
      "and restores no mp either -- nothing was absorbed")
  end),

  -- ------------------------------------- 3. POSITIVE: the absorb pays both --
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
    H.assertEq(mp(celes) > before.mp, true,
      "the vanilla half still happens: the spell became MP")
    H.assertEq(bp(celes), before.bp + 1,
      "and the OT6 half: the absorb banked exactly +1 bp")
    H.assertEq(pend(celes), 0, "with nothing pending to spend")
    H.screenshot("runic_absorbed")
  end),

  -- ------------------------------------------------ 4. the player can SEE it --
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
  end),
})
