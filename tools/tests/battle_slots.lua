-- @suite
-- battle_slots.lua -- boost-tiered Slot (Setzer), the chance-verb canon
-- (ROADMAP.md:79-82, kits.md:405-410) applied to the reels: on chance verbs
-- boost buys CERTAINTY in the verb's own vocabulary.  Slot's vocabulary is
-- vanilla's single rig byte (w7e6179, one Rand at the first A press) and the
-- drift/avoid machinery it drives:
--   blessed icon (rig & SlotRateTbl[icon] == 0): reels 2/3 drift up to
--     w7e617d extra icons TOWARD the pair/triple (vanilla budget 4);
--   cursed icon: no help, and a landed pair gets w7e617c bit 7 -- reel 3
--     REFUSES to stop on the completing icon (the rigged miss).
--
-- The hooks under test (ot6_kits.asm; C1 shims in btlgfx_main.asm):
--   Ot6SlotRig    -- latches the spin's tier ($57ba) at the first press and
--                    stores the rig byte: untouched at 0-1 bp, forced 0 (or
--                    $3c under the $2f49.2 joker-doom battle gate) at 2-3 bp.
--   Ot6SlotDrift  -- blessed drift budget: 4 to the byte below 3 bp, $ff
--                    (longer than the 16-icon strip, and every icon appears
--                    on every strip, so the seek always lands) at 3 bp.
--   Ot6SlotMiss   -- the rigged miss: vanilla avoid-mark at 0 bp, bought off
--                    at 1+ bp (the pair is blessed instead).  A 7-pair under
--                    the joker gate stays refused at every tier.
--   Ot6SlotCommit -- re-banks the latched tier into OT6_BOOST_REVEALED at
--                    the commit press, so Ot6ActionEnd charges exactly the
--                    tier the reels were spun with.
--   Ot6BoostDmg's $0f gate -- slot attacks never get the damage multiplier
--                    (certainty INSTEAD of multiplication, kits.md).
--
-- METHOD.  battle_doorstep + poked-in SETZER (battle_steal's install
-- pattern: ids/commands poked, monsters stopped + HP-pinned +
-- death-protected so every spin is attributable and nothing dies).  The
-- mechanism cells are asserted directly, and the racy ones (w7e617d is
-- decremented by the spin driver within frames of the press that stores it)
-- through write callbacks that record WHO wrote WHAT -- the hook writes from
-- bank $f0, vanilla's inline stores and the driver's decrements from $c1.
-- A STOPPED reel's position can be poked (the next press re-reads it), and a
-- stopped reel can be RESTARTED (clear its stop flag) to replay the driver's
-- boundary walk from a chosen position -- that is how the rigged miss is
-- demonstrated deterministically: restarted at $24 in avoid mode the driver
-- must SKIP the completing boundary $20 (REEL3 index 2 = icon 3) and halt at
-- $10 (icon 1); the same restart in tier-1's bless mode must HALT at $20,
-- the very boundary vanilla refused.  Same drive, one pending byte
-- different: the tier is the only variable.
--
-- FAIL-BEFORE / PASS-AFTER.  On the pre-change ROM the 0-bp arm passes with
-- identical observables (byte-vanilla evidence) and every tier arm fails
-- (no latch, no forced rig, no bought-off miss, no $f0 writer, damage
-- multiplied); on the post-change ROM all arms pass.  Both runs are recorded
-- in the change's report; the suite keeps the pass-after side green.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_doorstep.mss.lua"

local MENU, ACTOR = 0x7BCA, 0x62CA
local RIG, HELP1, MARK, DRIFT = 0x6179, 0x617B, 0x617C, 0x617D
local POS  = { 0x7B8C, 0x7B8D, 0x7B8E }   -- reel 1/2/3 position (icon = >>4)
local STOP = { 0x7B8F, 0x7B90, 0x7B91 }   -- reel stopped flags
local PRESS = { 0x7B92, 0x7B93, 0x7B94 }  -- press latches 1/2/3
local LATCH, JOKER = 0x57BA, 0x2F49
local SETZER, NONE = 0x09, 0xFF
local PARTY = { 0, 1, 2 }
local function ENT_C(s) return s * 2 end
local function ENT_M(s) return 8 + s * 2 end
local function bp(s)   return H.readByte(0x3E9C + s * 2) end
local function pend(s) return H.readByte(0x3E9D + s * 2) end

-- the reel strips (SlotReelTbl, btlgfx_main.asm @a800), mirrored so asserts
-- can name icons: icon = strip[pos >> 4]
local REEL = {
  { 0,4,5,3,4,5,2,5,1,4,5,3,5,2,3,1 },
  { 0,4,1,5,3,4,1,5,4,3,2,5,4,3,2,5 },
  { 0,1,3,4,2,5,4,3,1,5,4,3,2,5,4,5 },
}
local function icon(r) return REEL[r][(H.readByte(POS[r]) >> 4) + 1] end

-- sym("Ot6SlotRig") -- the literal keeps compose.py injecting the symbol;
-- its absence from OT6_SYMS identifies a pre-change ROM, so the byte-vanilla
-- T0 arm can pass there too (every tier arm still fails hard pre-change)
local function hasTiers()
  return type(OT6_SYMS) == "table" and OT6_SYMS["Ot6SlotRig"] ~= nil
end

local actor, msPresent = nil, {}
local results = {}      -- $2bb0-row writes from bank $c1 = the slot commit
local driftW = {}       -- w7e617d writes: { k = writer bank, v = value }
local mulHits = {}      -- Ot6BoostDmg multiplier writes during cmd $0f
local hp3, d3, hp0, d0

local function lastF0Drift()
  for i = #driftW, 1, -1 do
    if driftW[i].k == 0xF0 then return driftW[i].v end
  end
  return nil
end

local function stageEnemies(hp)
  for _, m in ipairs(msPresent) do
    local e = ENT_M(m)
    if hp then H.writeWord(0x3BFC + m * 2, 0xF000) end                -- never dies
    H.writeByte(0x3EF8 + e, H.readByte(0x3EF8 + e) | 0x10)            -- stopped
    H.writeByte(0x3AA1 + e, H.readByte(0x3AA1 + e) | 0x04)            -- death-proof
  end
end

local function hpsum()
  local t = 0
  for _, m in ipairs(msPresent) do t = t + H.readWord(0x3BFC + m * 2) end
  return t
end

local function installSetzer()
  for _, s in ipairs(PARTY) do
    H.writeByte(0x3ED8 + s * 2, SETZER)
    H.writeByte(0x202E + s * 12, 0x0F)                                -- Slot, alone
    H.writeByte(0x2031 + s * 12, NONE)
    H.writeByte(0x2034 + s * 12, NONE)
    H.writeByte(0x2037 + s * 12, NONE)
    if actor and s ~= actor then
      -- non-actors are WOUNDED, not stopped: a stopped character's pending
      -- menu stays open forever and starves the actor's next turn (measured
      -- here: menu parked on slot 01, state 05, 12000+ frames).  A dead row
      -- raises no menus at all, so every spin is the actor's.
      H.writeByte(0x3EE4 + s * 2, H.readByte(0x3EE4 + s * 2) | 0x80)
      H.writeWord(0x3BF4 + s * 2, 0)
    else
      H.writeByte(0x3EE4 + s * 2, H.readByte(0x3EE4 + s * 2) & 0x77)  -- -magitek -wound
      H.writeByte(0x3EE5 + s * 2, H.readByte(0x3EE5 + s * 2) & 0xCF)  -- -muddle/-berserk
      H.writeWord(0x3BF4 + s * 2, 999)                                -- actor hp pinned
    end
  end
end

local function pin() stageEnemies(true); installSetzer() end
local function pinNoHp() stageEnemies(false); installSetzer() end     -- damage windows

-- tap A until pred holds (a press while its stage is ineligible is
-- vanilla-ignored, so the cadence cannot double-press)
local function pressAUntilFn(predFn, what)
  return H.driveUntil(predFn, 3000, {
    H.call(function() pin(); H.setPad({ "a" }) end),
    H.waitFrames(3), H.call(function() H.setPad({}) end), H.waitFrames(11),
  }, what)
end
local function pressAUntil(addr, what)
  return pressAUntilFn(function() return H.readByte(addr) ~= 0 end, what)
end
-- the commit press: detected by the C1 queue write (C2 can drain the row
-- within a frame, so polling the queue could miss it)
local function pressCommit(what)
  return H.repeatN(1, {
    H.call(function() results = {} end),
    pressAUntilFn(function() return #results > 0 end, what),
  })
end

-- wait for the actor's command menu, press A on the (poked, only) Slot row,
-- wait for the live reel state ($7bc2 = 8, UpdateMenuState_08) with a fresh
-- spin (the open chain's state $32 cleared the press/stop flags).  driveUntil
-- checks its predicate BEFORE each tap, so no tap can land after state 8 is
-- already live and steal the first reel-stop press.
local function openReels()
  local ph = 0
  return H.repeatN(1, {
    H.driveUntil(function()
      ph = ph + 1
      if ph % 600 == 0 then
        H.log(string.format(
          "[menuwait ph=%d] menu=%02x actor=%02x st=%02x close=%02x " ..
          "s0=%02x/%02x s1=%02x/%02x s2=%02x/%02x cmdq=%02x %02x %02x %02x ord=%02x,%02x,%02x,%02x",
          ph, H.readByte(MENU), H.readByte(ACTOR), H.readByte(0x7BC2),
          H.readByte(0x7BCB),
          H.readByte(0x3EE4), H.readByte(0x3EF8),
          H.readByte(0x3EE6), H.readByte(0x3EFA),
          H.readByte(0x3EE8), H.readByte(0x3EFC),
          H.readByte(0x2BAE), H.readByte(0x2BB6),
          H.readByte(0x2BBE), H.readByte(0x2BC6),
          H.readByte(0x64D6), H.readByte(0x64D7),
          H.readByte(0x64D8), H.readByte(0x64D9)))
      end
      return H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == actor
    end, 12000, { H.call(pin), H.waitFrames(1) }, "setzer's menu"),
    H.waitFrames(20),
    H.driveUntil(function()
      return H.readByte(0x7BC2) == 0x08 and H.readByte(PRESS[1]) == 0
             and H.readByte(STOP[1]) == 0
    end, 1200, {
      H.call(function() pin(); H.setPad({ "a" }) end),
      H.waitFrames(3), H.call(function() H.setPad({}) end), H.waitFrames(20),
    }, "slot window open (state 8)"),
    H.waitFrames(12),
  })
end

-- restart a stopped reel from a chosen position: clear its stop flag and let
-- the driver replay its boundary walk against the CURRENT mode cells
-- (w7e617b/c/d) -- pure vanilla driver mechanics, used to demonstrate what
-- those cells make physically possible
local function restartReel(r, pos)
  return H.call(function()
    H.writeByte(POS[r], pos)
    H.writeByte(STOP[r], 0)
  end)
end

local function waitStop(r, what)
  return H.waitUntil(function() return H.readByte(STOP[r]) ~= 0 end, 900, what, 2)
end

H.run({ maxFrames = 250000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.enterEncounter(),
  H.driveUntil(function() return H.readByte(MENU) ~= 0 end, 3000, {
    H.call(function()
      for m = 0, 5 do
        if H.readByte(0x3AA8 + m * 2) % 2 == 1 then
          local seen = false
          for _, x in ipairs(msPresent) do if x == m then seen = true end end
          if not seen then msPresent[#msPresent + 1] = m end
        end
      end
      pin()
    end),
    H.waitFrames(1),
  }, "menu opens (Setzer installed)"),
  H.call(function()
    actor = H.readByte(ACTOR)
    H.log(string.format("actor slot %d id=$%02x monsters={%s} joker=$%02x",
      actor, H.readByte(0x3ED8 + actor * 2),
      table.concat(msPresent, ","), H.readByte(JOKER)))
    pin()
    -- the commit press writes the result index to $2bb0,y from bank $c1
    emu.addMemoryCallback(function(a, v)
      pcall(function()
        local s = emu.getState()
        if s["cpu.k"] == 0xC1 then results[#results + 1] = { addr = a, v = v } end
      end)
    end, emu.callbackType.write, 0x7E2BB0, 0x7E2BC9)
    -- who writes the drift budget, and what: the hook stores from $f0, the
    -- vanilla inline store / the driver's decrements from $c1
    emu.addMemoryCallback(function(_, v)
      pcall(function()
        local s = emu.getState()
        driftW[#driftW + 1] = { k = s["cpu.k"], v = v }
      end)
    end, emu.callbackType.write, 0x7E617D, 0x7E617D)
    -- the Ot6BoostDmg multiplier path parks its loop counter in OT6_SCR_BIT
    -- ($3ece) BEFORE multiplying; a write from INSIDE Ot6BoostDmg while the
    -- current command is slot ($b5 = $0f) is the multiplier running -- the
    -- exemption says it never may.  ($3ece is shared OT6 scratch and $b5
    -- goes stale between actions, so both the pc range AND the command gate
    -- are needed: a naive bank filter records 100k+ innocents.)
    local BOOSTDMG = H.sym("Ot6BoostDmg")
    emu.addMemoryCallback(function(_, v)
      -- CHEAP GUARDS FIRST.  Same conjunction as before -- `v > 0`, the
      -- command gate, and the pc range -- reordered, nothing dropped: the
      -- two byte tests are exact and order-free, so the recorded set is
      -- identical.  It matters because $3ece is shared OT6 scratch written
      -- tens of thousands of times a run (the comment above measured "100k+
      -- innocents"), and emu.getState() serialises the whole machine into a
      -- fresh Lua table on EVERY call.  Paying that before the one-byte
      -- tests was most of this test's wall clock.
      if not (v > 0 and H.readByte(0xB5) == 0x0F) then return end
      pcall(function()
        local s = emu.getState()
        local pc = (s["cpu.k"] << 16) | s["cpu.pc"]
        if pc >= BOOSTDMG and pc < BOOSTDMG + 0xA0 then
          mulHits[#mulHits + 1] = v
        end
      end)
    end, emu.callbackType.write, 0x7E3ECE, 0x7E3ECE)
  end),

  -- ============================================================= ARM T0: 0 bp
  -- byte-vanilla, incl. the rigged miss.  All-cursed rig poked after the
  -- draw; forced pair of 3s; reel 3 restarted at $24 in the resulting avoid
  -- mode must SKIP the completing boundary $20 and halt at $10.  Economy:
  -- +1 regen, nothing charged.  (This arm must pass IDENTICALLY on the
  -- pre-change ROM.)
  H.call(function()
    H.writeByte(0x3E9C + actor * 2, 2)
    H.writeByte(0x3E9D + actor * 2, 0)
    driftW = {}
  end),
  openReels(),
  pressAUntil(PRESS[1], "t0 press1"),
  H.call(function()
    if hasTiers() then
      H.assertEq(H.readByte(LATCH), 0, "t0: latch = 0 (tier-0 spin)")
    else
      H.log("t0: pre-change ROM (no Ot6SlotRig symbol) -- latch not asserted")
    end
    H.log(string.format("t0: rig drawn $%02x, poking $ff (all-cursed)", H.readByte(RIG)))
    H.writeByte(RIG, 0xFF)
  end),
  waitStop(1, "t0 reel1 stops"),
  H.call(function() H.writeByte(POS[1], 0x30) end),   -- icon1 = REEL1[3] = 3
  pressAUntil(PRESS[2], "t0 press2"),
  H.call(function()
    H.assertEq(H.readByte(HELP1), 0xFF, "t0: cursed reel 2 gets no help (w7e617b = $ff)")
  end),
  waitStop(2, "t0 reel2 stops"),
  H.call(function() H.writeByte(POS[2], 0x40) end),   -- icon2 = REEL2[4] = 3: a pair
  pressAUntil(PRESS[3], "t0 press3"),
  H.call(function()
    H.assertEq(H.readByte(MARK), 0x83,
      "t0: THE RIGGED MISS -- the cursed pair is avoid-marked (icon|$80)")
  end),
  waitStop(3, "t0 reel3 stops (naturally)"),
  restartReel(3, 0x24),   -- replay the walk into the completing boundary $20
  waitStop(3, "t0 reel3 re-stops"),
  H.call(function()
    H.assertEq(H.readByte(POS[3]), 0x10,
      "t0: avoid mode SKIPPED the completing boundary $20 and halted at $10")
    H.assertEq(icon(3), 1, "t0: the miss stands (icon 1, no triple)")
    H.assertEq(lastF0Drift() == nil, true, "t0: no $f0 writer touched the drift budget")
  end),
  pressCommit("t0 commit"),
  H.call(function()
    H.assertEq(results[#results].v, 7, "t0: non-triple resolves lagomorph (index 7)")
  end),
  H.driveUntil(function() return bp(actor) == 3 end, 6000,
    { H.call(pin), H.waitFrames(1) }, "t0: unboosted turn regens +1 (2->3)"),
  H.call(function()
    H.assertEq(pend(actor), 0, "t0: nothing pending after the turn")
  end),

  -- ============================================================= ARM T1: 1 bp
  -- the rigged miss is BOUGHT OFF.  Identical drive to T0 -- same poked rig,
  -- same forced pair, same reel-3 restart -- one pending byte different.
  H.call(function()
    H.writeByte(0x3E9C + actor * 2, 5)
    H.writeByte(0x3E9D + actor * 2, 1)
    driftW = {}
  end),
  openReels(),
  pressAUntil(PRESS[1], "t1 press1"),
  H.call(function()
    H.assertEq(H.readByte(LATCH), 1, "t1: latch = 1")
    H.writeByte(RIG, 0xFF)          -- tier 1 keeps the drawn rig: curse it all
  end),
  waitStop(1, "t1 reel1 stops"),
  H.call(function() H.writeByte(POS[1], 0x30) end),
  pressAUntil(PRESS[2], "t1 press2"),
  H.call(function()
    H.assertEq(H.readByte(HELP1), 0xFF,
      "t1: reel-2 help is still rig-rolled at 1 bp (cursed: no help)")
  end),
  waitStop(2, "t1 reel2 stops"),
  H.call(function() H.writeByte(POS[2], 0x40) end),
  pressAUntil(PRESS[3], "t1 press3"),
  H.call(function()
    H.assertEq(H.readByte(MARK), 0x03,
      "t1: the pair is BLESSED, not avoid-marked (the miss is bought off)")
    H.assertEq(lastF0Drift(), 0x04,
      "t1: the hook budgeted vanilla's 4 (an $f0 write -- the bless is Ot6SlotMiss's)")
  end),
  waitStop(3, "t1 reel3 stops (naturally)"),
  restartReel(3, 0x24),   -- the very walk vanilla refused...
  waitStop(3, "t1 reel3 re-stops"),
  H.call(function()
    H.assertEq(H.readByte(POS[3]), 0x20,
      "t1: ...now HALTS on the completing boundary $20")
    H.assertEq(icon(3), 3, "t1: the triple lands")
  end),
  pressCommit("t1 commit"),
  H.call(function()
    H.assertEq(results[#results].v, 4, "t1: triple 3s resolve index 4 (icon+1)")
  end),
  H.driveUntil(function() return pend(actor) == 0 and H.readByte(MENU) ~= 0 end, 9000,
    { H.call(pin), H.waitFrames(1) }, "t1: action resolves"),
  H.call(function()
    H.assertEq(bp(actor), 4, "t1: 5 bp - 1 spent = 4, regen skipped")
  end),

  -- ============================================================= ARM T2: 2 bp
  -- the machine cheats FOR you: the rig byte is FORCED benevolent (an $f0
  -- store), reel 2 is blessed toward the pair with vanilla's 4-icon budget,
  -- and the drift walk itself is replayed: restarted three icons shy of the
  -- match it must spend two budget icons and halt on the pair.
  H.call(function()
    H.writeByte(0x3E9C + actor * 2, 5)
    H.writeByte(0x3E9D + actor * 2, 2)
    driftW = {}
  end),
  openReels(),
  pressAUntil(PRESS[1], "t2 press1"),
  H.call(function()
    H.assertEq(H.readByte(LATCH), 2, "t2: latch = 2")
    local want = (H.readByte(JOKER) & 4) ~= 0 and 0x3C or 0x00
    H.assertEq(H.readByte(RIG), want,
      string.format("t2: rig forced benevolent ($%02x)", want))
  end),
  waitStop(1, "t2 reel1 stops"),
  H.call(function() H.writeByte(POS[1], 0x30) end),
  pressAUntil(PRESS[2], "t2 press2"),
  H.call(function()
    H.assertEq(H.readByte(HELP1), 0x03, "t2: reel 2 is blessed toward icon 3")
    H.assertEq(lastF0Drift(), 0x04, "t2: with vanilla's 4-icon budget (the $f0 store)")
  end),
  waitStop(2, "t2 reel2 stops (naturally)"),
  H.call(function() H.writeByte(DRIFT, 0x04) end),  -- replay with a fresh budget
  restartReel(2, 0x64),   -- $60 -> icon 1, $50 -> icon 4, $40 -> icon 3 (match)
  waitStop(2, "t2 reel2 re-stops"),
  H.call(function()
    H.assertEq(H.readByte(POS[2]), 0x40, "t2: reel 2 DRIFTED to the pair ($64 -> $40)")
    H.assertEq(H.readByte(DRIFT), 0x02, "t2: spending two of the four budget icons")
    H.assertEq(icon(2), 3, "t2: a machine-made pair of 3s")
  end),
  pressAUntil(PRESS[3], "t2 press3"),
  H.call(function()
    H.assertEq(H.readByte(MARK), 0x03, "t2: the pair is blessed onward")
  end),
  waitStop(3, "t2 reel3 stops (naturally)"),
  restartReel(3, 0x24),   -- match at the first boundary: budget-independent
  waitStop(3, "t2 reel3 re-stops"),
  H.call(function()
    H.assertEq(icon(3), 3, "t2: triple")
  end),
  pressCommit("t2 commit"),
  H.call(function()
    H.assertEq(results[#results].v, 4, "t2: index 4")
  end),
  H.driveUntil(function() return pend(actor) == 0 and H.readByte(MENU) ~= 0 end, 9000,
    { H.call(pin), H.waitFrames(1) }, "t2: action resolves"),
  H.call(function()
    H.assertEq(bp(actor), 3, "t2: 5 bp - 2 spent = 3")
  end),

  -- ============================================================= ARM T3: 3 bp
  -- the reel is CHOSEN.  Reel 1 parked on icon 5 (dragon); with the
  -- whole-strip budget reels 2 and 3 must seek it from WHEREVER the presses
  -- fell -- no restarts, no position pokes -- and the queued result is the
  -- chosen triple.  Damage D3 recorded for the exemption ratio.
  H.call(function()
    H.writeByte(0x3E9C + actor * 2, 5)
    H.writeByte(0x3E9D + actor * 2, 3)
    driftW = {}
  end),
  openReels(),
  pressAUntil(PRESS[1], "t3 press1"),
  H.call(function()
    H.assertEq(H.readByte(LATCH), 3, "t3: latch = 3")
    local want = (H.readByte(JOKER) & 4) ~= 0 and 0x3C or 0x00
    H.assertEq(H.readByte(RIG), want, "t3: rig forced benevolent")
  end),
  waitStop(1, "t3 reel1 stops"),
  H.call(function() H.writeByte(POS[1], 0x50) end),   -- icon1 = REEL1[5] = 5
  pressAUntil(PRESS[2], "t3 press2"),
  H.call(function()
    H.assertEq(H.readByte(HELP1), 0x05, "t3: reel 2 seeks the chosen icon")
    H.assertEq(lastF0Drift(), 0xFF, "t3: with the whole-strip budget")
  end),
  waitStop(2, "t3 reel2 stops"),
  H.call(function()
    H.assertEq(icon(2), 5, "t3: reel 2 FOUND it, wherever the press fell")
    driftW = {}
  end),
  pressAUntil(PRESS[3], "t3 press3"),
  H.call(function()
    H.assertEq(H.readByte(MARK), 0x05, "t3: pair blessed")
    H.assertEq(lastF0Drift(), 0xFF, "t3: whole-strip budget again")
  end),
  waitStop(3, "t3 reel3 stops"),
  H.call(function()
    H.assertEq(icon(3), 5, "t3: reel 3 completed the CHOSEN triple")
    stageEnemies(true)
    hp3 = hpsum()
  end),
  pressCommit("t3 commit"),
  H.call(function()
    H.assertEq(results[#results].v, 6, "t3: triple 5s resolve index 6 (megaflare)")
    H.assertEq(pend(actor), 3, "t3: commit re-banked the latched tier")
  end),
  H.driveUntil(function() return pend(actor) == 0 and H.readByte(MENU) ~= 0 end, 12000,
    { H.call(pinNoHp), H.waitFrames(1) },   -- NO hp re-pin: the damage must stand
    "t3: chosen triple resolves"),
  H.call(function()
    H.assertEq(bp(actor), 2, "t3: 5 bp - 3 spent = 2")
    d3 = hp3 - hpsum()
    H.log(string.format("t3: boosted triple-5 damage = %d", d3))
    H.assertEq(d3 > 0, true, "t3: the chosen attack dealt damage")
  end),

  -- ==================================================== ARM T3b: exemption A/B
  -- the SAME attack at 0 bp: reels stopped anywhere, then all three
  -- positions parked on icon 5 before the commit press (the result mapper
  -- reads final positions).  Unboosted damage D0 must sit in the same band
  -- as D3 -- the multiplier would have made D3 ~8x D0.
  H.call(function()
    H.writeByte(0x3E9C + actor * 2, 2)
    H.writeByte(0x3E9D + actor * 2, 0)
  end),
  openReels(),
  pressAUntil(PRESS[1], "t3b press1"),
  waitStop(1, "t3b reel1 stops"),
  pressAUntil(PRESS[2], "t3b press2"),
  waitStop(2, "t3b reel2 stops"),
  pressAUntil(PRESS[3], "t3b press3"),
  waitStop(3, "t3b reel3 stops"),
  H.call(function()
    H.writeByte(POS[1], 0x50)       -- REEL1[5]=5, REEL2[3]=5, REEL3[5]=5:
    H.writeByte(POS[2], 0x30)       --   the same triple 5s, tier 0
    H.writeByte(POS[3], 0x50)
    stageEnemies(true)
    hp0 = hpsum()
  end),
  pressCommit("t3b commit"),
  H.call(function()
    H.assertEq(results[#results].v, 6, "t3b: same result index at 0 bp")
  end),
  H.driveUntil(function() return bp(actor) == 3 end, 12000,
    { H.call(pinNoHp), H.waitFrames(1) }, "t3b: unboosted triple resolves (+1 regen)"),
  H.call(function()
    d0 = hp0 - hpsum()
    H.log(string.format("exemption: D0=%d D3=%d ratio=%.2f", d0, d3, d3 / d0))
    H.assertEq(d0 > 0, true, "t3b: the unboosted attack dealt damage")
    H.assertEq(d3 < d0 * 2, true,
      "EXEMPTION: boosted slot damage is NOT multiplied (x8 would show here)")
    H.assertEq(#mulHits, 0,
      "EXEMPTION: Ot6BoostDmg's multiplier path never ran under cmd $0f")
  end),

  -- ================================================= ARM T3j: the joker gate
  -- $2f49.2 poked on: even at 3 bp the rig is $3c, a 7 gets no reel-2 help,
  -- and a forced 7-pair keeps the vanilla avoid mark -- the battle's own
  -- prohibition cannot be bought.  (BP is still spent: certainty was offered
  -- on every OTHER icon.)
  H.call(function()
    H.writeByte(JOKER, H.readByte(JOKER) | 0x04)
    H.writeByte(0x3E9C + actor * 2, 5)
    H.writeByte(0x3E9D + actor * 2, 3)
  end),
  openReels(),
  pressAUntil(PRESS[1], "t3j press1"),
  H.call(function()
    H.assertEq(H.readByte(RIG), 0x3C, "t3j: joker-gated rig ($3c) even at 3 bp")
  end),
  waitStop(1, "t3j reel1 stops"),
  H.call(function() H.writeByte(POS[1], 0x00) end),   -- icon1 = 0: the 7
  pressAUntil(PRESS[2], "t3j press2"),
  H.call(function()
    H.assertEq(H.readByte(HELP1), 0xFF, "t3j: no reel-2 help toward 7s")
  end),
  waitStop(2, "t3j reel2 stops"),
  H.call(function() H.writeByte(POS[2], 0x00) end),   -- forced 7-pair
  pressAUntil(PRESS[3], "t3j press3"),
  H.call(function()
    H.assertEq(H.readByte(MARK), 0x80, "t3j: the 7-pair stays avoid-marked at 3 bp")
  end),
  waitStop(3, "t3j reel3 stops"),
  H.call(function()
    -- park reel 3 on a SAFE icon: 7-7-BAR is the self-doom result and 7-7-7
    -- may be script-forbidden here; 7-7-4 is a plain lagomorph
    H.writeByte(POS[3], 0x30)       -- REEL3[3] = 4
  end),
  pressCommit("t3j commit"),
  H.call(function()
    H.assertEq(results[#results].v, 7, "t3j: no bought 777 -- lagomorph")
  end),
  H.driveUntil(function() return pend(actor) == 0 and H.readByte(MENU) ~= 0 end, 9000,
    { H.call(pin), H.waitFrames(1) }, "t3j: action resolves"),
  H.call(function()
    H.assertEq(bp(actor), 2, "t3j: the spend stands (certainty was offered elsewhere)")
    H.writeByte(JOKER, H.readByte(JOKER) & 0xFB)
    H.screenshot("slots_tiers_done")
  end),
})
