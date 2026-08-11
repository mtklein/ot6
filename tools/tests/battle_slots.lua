-- @suite slow
-- battle_slots.lua -- boost-tiered Slot (Setzer), the chance-verb canon
-- (ROADMAP.md "Design canon", kits.md "Boost-tiered Steal") applied to the
-- reels: on chance verbs boost buys CERTAINTY in the verb's own vocabulary.
-- Slot's vocabulary is
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
--   Ot6SlotDrift  -- blessed drift budget: 4 to the byte below 3 bp, $ff at
--                    3 bp (longer than the 16-icon strip).
--   Ot6SlotMiss   -- the rigged miss: vanilla avoid-mark at 0 bp, bought off
--                    at 1+ bp.  A 7-pair under the joker gate stays refused.
--   Ot6SlotCommit -- re-banks the latched tier into OT6_BOOST_REVEALED at
--                    the commit press, so Ot6ActionEnd charges exactly the
--                    tier the reels were spun with.
--   Ot6BoostDmg's $0f gate -- slot attacks never get the damage multiplier.
--
-- ISSUE #75 SPLIT.  battle_slotsboot (the input-driven model this file now
-- follows) proves tier 0 and tier 3 end to end on a NATURAL checkpoint boot:
-- latch 0/3, rig forced benevolent at 3, the chosen triple, the 3-bp
-- charge, the regen, and the multiplier exemption watch -- so this file's
-- old poked tier-3 arm is DELETED as covered.  What remains here splits in
-- two:
--
--   INPUT-DRIVEN HALF (zero writes): a second natural boot of the
--   terra-returned-v1 SRAM checkpoint (battle_slotsboot's cold-Continue /
--   disembark / walk / choose-the-draw pattern, verbatim), driving the two
--   tiers slotsboot leaves unproven with real R presses on earned bp:
--     H1 (1 bp): latch = 1, the 1-bp charge with regen skipped, and the
--        commit re-bank -- tier 1 leaves the drawn rig alone, so no rig
--        value is asserted (asserting one would need the poke this file
--        just gave up; the rig's tier-1 hands-off half lives in the
--        quarantine lab where the byte can be planted).
--     H2 (2 bp, banked by two real unboosted spins): latch = 2, THE RIG
--        FORCED BENEVOLENT ($00, or $3c under a real joker gate) -- read,
--        not written -- reel-2 help blessed toward the icon reel 1 really
--        stopped on, with vanilla's 4-icon budget stored by the $f0 hook,
--        and the 2-bp charge.
--
--   *** LABELED QUARANTINE LAB (issue #75) -- the icon/rig-byte arms ***
--   No player input selects a reel icon: the reels free-run at frame rate
--   and a press stops them wherever the frame parity fell, so "a cursed
--   pair of 3s", "the same triple at tier 0 and tier 3" (the exemption
--   A/B), and "a 7-pair under the joker gate" are unproducible on cue by
--   any input-driven drive.  Those arms are MECHANISM unit tests (burn-down plan
--   systemic call 2) and stay below as one loudly-labeled block on the old
--   entry-point install rig -- rig bytes planted, reel positions parked,
--   stopped reels restarted to replay the driver's boundary walk, monsters
--   staged so nothing dies mid-observation.  The block keeps this file's
--   waiver lines and MAY NEVER PRODUCE FIXTURES.  Arms: T0 byte-vanilla +
--   the rigged miss; T1 the miss bought off (same drive, one pending byte
--   different); T2 the drift walk replayed on a fresh budget; T3b the
--   exemption A/B damage ratio on identical triples; T3j the joker gate
--   refusing a bought 7-pair at 3 bp.
--
-- OT6_ANCHOR_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_doorstep.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local RIG, HELP1, MARK, DRIFT = 0x6179, 0x617B, 0x617C, 0x617D
local POS  = { 0x7B8C, 0x7B8D, 0x7B8E }   -- reel 1/2/3 position (icon = >>4)
local STOP = { 0x7B8F, 0x7B90, 0x7B91 }   -- reel stopped flags
local PRESS = { 0x7B92, 0x7B93, 0x7B94 }  -- press latches 1/2/3
local LATCH, JOKER = 0x57BA, 0x2F49
local SETZER, NONE = 0x09, 0xFF
local PARTY = { 0, 1, 2 }
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

local actor, msPresent = nil, {}
local results = {}      -- $2bb0-row writes from bank $c1 = the slot commit
local driftW = {}       -- w7e617d writes: { k = writer bank, v = value }
local mulHits = {}      -- Ot6BoostDmg multiplier writes during cmd $0f

local function lastF0Drift()
  for i = #driftW, 1, -1 do
    if driftW[i].k == 0xF0 then return driftW[i].v end
  end
  return nil
end

local function armWatches()
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
  -- the exemption watch (cheap guards first -- see battle_slotsboot's twin)
  local BOOSTDMG = H.sym("Ot6BoostDmg")
  emu.addMemoryCallback(function(_, v)
    if not (v > 0 and H.readByte(0xB5) == 0x0F) then return end
    pcall(function()
      local s = emu.getState()
      local pc = (s["cpu.k"] << 16) | s["cpu.pc"]
      if pc >= BOOSTDMG and pc < BOOSTDMG + 0xA0 then
        mulHits[#mulHits + 1] = v
      end
    end)
  end, emu.callbackType.write, 0x7E3ECE, 0x7E3ECE)
end

local steps = {}
local function add(t) for _, s in ipairs(t) do steps[#steps + 1] = s end end

-- ========================================================================
-- INPUT-DRIVEN HALF -- the natural checkpoint boot (battle_slotsboot's pattern)
-- ========================================================================
local slotOf = {}
local function ent() return actor * 2 end
local function onFoot()
  return (H.readByte(0x11FA) & 3) == 0 and H.readByte(0x11F3) == 0
end

-- wait for a character's menu; consume any other character's menu with a
-- real Defend (right swaps Fight->Def, then A)
local function menuFor(charId, what)
  local ph = 0
  local function up()
    return H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == slotOf[charId]
  end
  return H.driveUntil(up, 30000, {
    H.call(function()
      ph = ph + 1
      if H.readByte(MENU) ~= 0 and H.readByte(ACTOR) ~= slotOf[charId] then
        local step = ph % 40
        if step < 4 then H.setPad({ right = true })
        elseif step >= 20 and step < 24 then H.setPad({ a = true })
        else H.setPad({}) end
      else
        H.setPad({})
      end
    end),
  }, what)
end

local function openSlotWindow(what)
  local row = nil
  return H.repeatN(1, {
    H.call(function()
      row = nil
      for r = 0, 3 do
        if H.readByte(0x202E + slotOf[SETZER] * 12 + r * 3) == 0x0F then
          row = r
        end
      end
      H.assertEq(row ~= nil, true, "setzer's menu offers Slot")
    end),
    H.driveUntil(function()
      return H.readByte(0x890F + slotOf[SETZER]) == row
    end, 900, {
      H.call(function()
        local cur = H.readByte(0x890F + slotOf[SETZER])
        if cur < row then H.setPad({ down = true })
        elseif cur > row then H.setPad({ up = true }) end
      end),
      H.waitFrames(3), H.call(function() H.setPad({}) end), H.waitFrames(10),
    }, what .. ": cursor on the Slot row"),
    H.driveUntil(function()
      return H.readByte(MSTATE) == 0x08 and H.readByte(PRESS[1]) == 0
             and H.readByte(STOP[1]) == 0
    end, 1500, {
      H.call(function() H.setPad({ a = true }) end),
      H.waitFrames(3), H.call(function() H.setPad({}) end), H.waitFrames(20),
    }, what .. ": slot window open"),
    H.waitFrames(12),
  })
end

local function pressAUntilFnH(predFn, what)
  return H.driveUntil(predFn, 3000, {
    H.call(function() H.setPad({ a = true }) end),
    H.waitFrames(3), H.call(function() H.setPad({}) end), H.waitFrames(11),
  }, what)
end
local function pressAUntilH(addr, what)
  return pressAUntilFnH(function() return H.readByte(addr) ~= 0 end, what)
end
local function pressCommitH(what)
  return H.repeatN(1, {
    H.call(function() results = {} end),
    pressAUntilFnH(function() return #results > 0 end, what),
  })
end
local function waitStopH(r, what)
  return H.waitUntil(function() return H.readByte(STOP[r]) ~= 0 end, 900, what, 2)
end

-- one full spin played through real input at the CURRENT pending tier; asserts run via `checks`
local function playedSpin(tag, checks)
  return {
    openSlotWindow(tag),
    pressAUntilH(PRESS[1], tag .. " press1"),
    H.call(function() if checks.afterPress1 then checks.afterPress1() end end),
    waitStopH(1, tag .. " reel1"),
    pressAUntilH(PRESS[2], tag .. " press2"),
    H.call(function() if checks.afterPress2 then checks.afterPress2() end end),
    waitStopH(2, tag .. " reel2"),
    pressAUntilH(PRESS[3], tag .. " press3"),
    waitStopH(3, tag .. " reel3"),
    pressCommitH(tag .. " commit"),
    H.call(function() if checks.afterCommit then checks.afterCommit() end end),
  }
end

add({
  -- cold Continue (the checkpoint's $307ff0=3 preselects slot 3)
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function() return H.worldMode() end, 3000,
    "cold Continue to the world", 10),
  H.waitUntil(function()
    return (emu.getState()["ppu.screenBrightness"] or 0) >= 15
  end, 900, "fade-in", 10),
  H.waitFrames(60),
  H.call(function() H.assertEntryContract("terra-returned-v1") end),

  -- disembark guard
  (function()
    local ph2 = 0
    return H.driveUntil(function()
      return onFoot() and H.worldHasControl() and H.worldAligned()
    end, 8000, {
      H.call(function()
        ph2 = ph2 + 1
        H.setPad((ph2 % 45) < 6 and { b = true } or {})
      end),
    }, "disembark the grounded Blackjack")
  end)(),
  H.release(),
  H.waitFrames(30),
})

-- walk the plain and CHOOSE the draw (slotsboot's check: this run needs FOUR
-- resolutions, so the floor is higher)
add({ H.call(function() H.vars.suitable = false end) })
for n = 1, 6 do
  local w = {
    (function()
      local ph = 0
      local pattern = { "down", "down", "right", "right", "down", "down",
                        "left", "left" }
      return H.driveUntil(function() return H.battleLoadStarted() end, 40000, {
        H.call(function()
          ph = ph + 1
          local dir = pattern[(math.floor(ph / 20) % #pattern) + 1]
          H.setPad({ [dir] = true })
        end),
      }, "a real world encounter fires (draw " .. n .. ")")
    end)(),
    H.release(),
    H.waitUntil(function() return H.battleActive() end, 900,
      "battle active (draw " .. n .. ")", 30),
    H.waitFrames(240),
    H.call(function()
      msPresent = {}
      for m = 0, 5 do
        if H.readByte(0x3AA8 + m * 2) % 2 == 1 then
          msPresent[#msPresent + 1] = m
        end
      end
      local mhp = 0
      for _, m in ipairs(msPresent) do mhp = mhp + H.readWord(0x3BFC + m * 2) end
      H.vars.suitable = (#msPresent >= 2 and mhp >= 900)
      H.log(string.format("draw %d: %d bodies, %d total max HP -> %s",
        n, #msPresent, mhp, H.vars.suitable and "FIGHT" or "flee"))
    end),
    H.cond(function() return not H.vars.suitable end, {
      H.fleeBattle(9000),
      H.waitUntil(function()
        return H.worldMode() and H.worldHasControl()
      end, 1200, "back on the plain after fleeing draw " .. n, 10),
      H.waitFrames(30),
    }, {}),
  }
  if n == 1 then add(w)
  else add({ H.cond(function() return not H.vars.suitable end, w, {}) }) end
end

add({
  H.call(function()
    H.assertEq(H.vars.suitable, true,
      "the pool dealt a four-resolution formation within six draws")
    for s = 0, 3 do
      local id = H.readByte(0x3ED8 + s * 2)
      if id ~= 0xFF then slotOf[id] = s end
    end
    H.assertEq(slotOf[SETZER] ~= nil, true, "SETZER present")
    actor = slotOf[SETZER]
    H.log(string.format("setzer slot %d monsters={%s} joker=$%02x",
      actor, table.concat(msPresent, ","), H.readByte(JOKER)))
    armWatches()
  end),

  -- ---------------------------------------------- H1: the tier-1 spin
  menuFor(SETZER, "setzer menu (H1)"),
  H.call(function()
    H.assertEq(bp(actor), 1, "battle opens at 1 bp (Ot6InitBP)")
  end),
  H.pressButtons({ "r" }, 6), H.waitFrames(20),
  H.call(function()
    H.assertEq(pend(actor), 1, "one real R press banks pending 1")
  end),
})
add(playedSpin("H1", {
  afterPress1 = function()
    H.assertEq(H.readByte(LATCH), 1,
      "H1: Ot6SlotRig latched tier 1 at the first press")
    H.log(string.format("H1: rig drawn $%02x (tier 1 leaves it alone -- "
      .. "value is the roll's own)", H.readByte(RIG)))
  end,
  afterCommit = function()
    H.assertEq(pend(actor), 1, "H1: the commit re-banked the latched tier 1")
  end,
}))
add({
  (function()
    local hb = -600
    return H.driveUntil(function()
      if H.frame - hb >= 600 then
        hb = H.frame
        H.log(string.format("[H1 resolve f%d] pend=%d bp=%d menu=%02x "
          .. "act=%02x st=%02x live=%s mons=%d", H.frame, pend(actor),
          bp(actor), H.readByte(MENU), H.readByte(ACTOR), H.readByte(MSTATE),
          tostring(H.battleLoadStarted()), H.monstersPresent()))
      end
      return pend(actor) == 0 or not H.battleLoadStarted()
    end, 15000, {
      H.call(function()
        -- battle MESSAGES (the result banner) block the queue until
        -- dismissed -- codex_ctx's measured lesson; tap A through them
        H.setPad(H.readByte(MENU) == 0 and H.frame % 8 < 4
                 and { a = true } or {})
      end),
      H.waitFrames(1),
    }, "H1: the tier-1 spin resolves")
  end)(),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(bp(actor), 0,
      "H1: 1 bp - 1 spent = 0, regen skipped on a boosted turn")
  end),

  -- ------------------------------- bank 2 bp with two unboosted spins
  menuFor(SETZER, "setzer menu (bank spin 1)"),
})
add(playedSpin("bank1", {}))
add({
  H.driveUntil(function() return bp(actor) == 1 end, 15000, {
    H.call(function()
      H.setPad(H.readByte(MENU) == 0 and H.frame % 8 < 4
               and { a = true } or {})
    end),
    H.waitFrames(1),
  }, "bank1: unboosted spin regens 0 -> 1"),
  menuFor(SETZER, "setzer menu (bank spin 2)"),
})
add(playedSpin("bank2", {}))
add({
  H.driveUntil(function() return bp(actor) == 2 end, 15000, {
    H.call(function()
      H.setPad(H.readByte(MENU) == 0 and H.frame % 8 < 4
               and { a = true } or {})
    end),
    H.waitFrames(1),
  }, "bank2: unboosted spin regens 1 -> 2"),

  -- ---------------------------------------------- H2: the tier-2 spin
  menuFor(SETZER, "setzer menu (H2)"),
  H.repeatN(2, { H.pressButtons({ "r" }, 6), H.waitFrames(20) }),
  H.call(function()
    H.assertEq(pend(actor), 2, "two real R presses bank pending 2")
    driftW = {}
  end),
})
add(playedSpin("H2", {
  afterPress1 = function()
    H.assertEq(H.readByte(LATCH), 2, "H2: latched tier 2")
    local want = (H.readByte(JOKER) & 4) ~= 0 and 0x3C or 0x00
    H.assertEq(H.readByte(RIG), want, string.format(
      "H2: THE RIG FORCED BENEVOLENT ($%02x) at 2 bp -- read off the "
      .. "machine, not written to it", want))
  end,
  afterPress2 = function()
    -- reel 1 stopped wherever the real press fell; the bless must aim
    -- reel 2 at THAT icon (unless it is the joker-gated 7)
    local i1 = icon(1)
    local gated = i1 == 0 and (H.readByte(JOKER) & 4) ~= 0
    if gated then
      H.log("H2: reel 1 landed the gated 7 -- no help, documented exception")
      H.assertEq(H.readByte(HELP1), 0xFF, "H2: 7s stay gated")
    else
      H.assertEq(H.readByte(HELP1), i1, string.format(
        "H2: reel 2 blessed toward reel 1's actual icon %d", i1))
      H.assertEq(lastF0Drift(), 0x04,
        "H2: with vanilla's 4-icon budget, stored by the $f0 hook")
    end
  end,
  afterCommit = function()
    H.assertEq(pend(actor), 2, "H2: the commit re-banked the latched tier 2")
  end,
}))
add({
  (function()
    local hb = -600
    return H.driveUntil(function()
      if H.frame - hb >= 600 then
        hb = H.frame
        H.log(string.format("[H2 resolve f%d] pend=%d bp=%d menu=%02x "
          .. "act=%02x st=%02x live=%s mons=%d", H.frame, pend(actor),
          bp(actor), H.readByte(MENU), H.readByte(ACTOR), H.readByte(MSTATE),
          tostring(H.battleLoadStarted()), H.monstersPresent()))
      end
      return pend(actor) == 0 or not H.battleLoadStarted()
    end, 15000, {
      H.call(function()
        H.setPad(H.readByte(MENU) == 0 and H.frame % 8 < 4
                 and { a = true } or {})
      end),
      H.waitFrames(1),
    }, "H2: the tier-2 spin resolves")
  end)(),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(bp(actor), 0, "H2: 2 bp - 2 spent = 0")
    H.assertEq(#mulHits, 0,
      "EXEMPTION (unrigged half): the damage multiplier never ran under cmd "
      .. "$0f across all four natural resolutions")
    H.log("unrigged half complete: tier-1 and tier-2 latch/rig/bless/economy "
      .. "on a natural boot")
  end),
})

-- ========================================================================
-- *** LABELED QUARANTINE LAB (issue #75) -- see the header. ***
-- Fault injection for the icon-specific machinery: rig bytes planted, reel
-- positions parked, stopped reels restarted.  MAY NEVER PRODUCE FIXTURES.
-- ========================================================================
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
      -- menu stays open forever and starves the actor's next turn.
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

local function pressAUntilFn(predFn, what)
  return H.driveUntil(predFn, 3000, {
    H.call(function() pin(); H.setPad({ "a" }) end),
    H.waitFrames(3), H.call(function() H.setPad({}) end), H.waitFrames(11),
  }, what)
end
local function pressAUntil(addr, what)
  return pressAUntilFn(function() return H.readByte(addr) ~= 0 end, what)
end
local function pressCommit(what)
  return H.repeatN(1, {
    H.call(function() results = {} end),
    pressAUntilFn(function() return #results > 0 end, what),
  })
end

local function openReels()
  return H.repeatN(1, {
    H.driveUntil(function()
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
local function restartReel(r, pos)
  return H.call(function()
    H.writeByte(POS[r], pos)
    H.writeByte(STOP[r], 0)
  end)
end

local function waitStop(r, what)
  return H.waitUntil(function() return H.readByte(STOP[r]) ~= 0 end, 900, what, 2)
end

local hp3, d3, hp0, d0

add({
  H.call(function()
    H.log("*** entering the LABELED QUARANTINE LAB (entry-point install rig; "
      .. "see header) ***")
    msPresent = {}
    actor = nil
  end),
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
    H.log(string.format("lab actor slot %d id=$%02x monsters={%s} joker=$%02x",
      actor, H.readByte(0x3ED8 + actor * 2),
      table.concat(msPresent, ","), H.readByte(JOKER)))
    pin()
    mulHits = {}
  end),

  -- ============================================================= ARM T0: 0 bp
  -- byte-vanilla, incl. the rigged miss.  All-cursed rig poked after the
  -- draw; forced pair of 3s; reel 3 restarted at $24 in the resulting avoid
  -- mode must SKIP the completing boundary $20 and halt at $10.  Economy:
  -- +1 regen, nothing charged.
  H.call(function()
    H.writeByte(0x3E9C + actor * 2, 2)
    H.writeByte(0x3E9D + actor * 2, 0)
    driftW = {}
  end),
  openReels(),
  pressAUntil(PRESS[1], "t0 press1"),
  H.call(function()
    H.assertEq(H.readByte(LATCH), 0, "t0: latch = 0 (tier-0 spin)")
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
  -- the drift walk itself, replayed: restarted three icons shy of the match
  -- it must spend two budget icons and halt on the pair.
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

  -- ==================================================== ARM T3b: exemption A/B
  -- the same triple at 3 bp and then at 0 bp: unboosted damage D0 must sit
  -- in the same range as boosted D3 -- the multiplier would have made D3 ~8x.
  H.call(function()
    H.writeByte(0x3E9C + actor * 2, 5)
    H.writeByte(0x3E9D + actor * 2, 3)
    driftW = {}
  end),
  openReels(),
  pressAUntil(PRESS[1], "t3 press1"),
  H.call(function()
    H.assertEq(H.readByte(LATCH), 3, "t3: latch = 3")
  end),
  waitStop(1, "t3 reel1 stops"),
  H.call(function() H.writeByte(POS[1], 0x50) end),   -- icon1 = REEL1[5] = 5
  pressAUntil(PRESS[2], "t3 press2"),
  waitStop(2, "t3 reel2 stops"),
  H.call(function()
    H.assertEq(icon(2), 5, "t3: reel 2 sought the chosen icon (whole-strip budget)")
  end),
  pressAUntil(PRESS[3], "t3 press3"),
  waitStop(3, "t3 reel3 stops"),
  H.call(function()
    H.assertEq(icon(3), 5, "t3: the triple completes")
    stageEnemies(true)
    hp3 = hpsum()
  end),
  pressCommit("t3 commit"),
  H.call(function()
    H.assertEq(results[#results].v, 6, "t3: triple 5s resolve index 6 (megaflare)")
  end),
  H.driveUntil(function() return pend(actor) == 0 and H.readByte(MENU) ~= 0 end, 12000,
    { H.call(pinNoHp), H.waitFrames(1) },   -- NO hp re-pin: the damage must stand
    "t3: boosted triple resolves"),
  H.call(function()
    d3 = hp3 - hpsum()
    H.log(string.format("t3: boosted triple-5 damage = %d", d3))
    H.assertEq(d3 > 0, true, "t3: the boosted attack dealt damage")
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

H.run({ maxFrames = 400000 }, steps)
