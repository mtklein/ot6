-- @suite slow
-- battle_slotsboot.lua -- boost-tiered Slot on a natural boot: cold-Continue
-- the terra-returned-v1 SRAM checkpoint (party LOCKE EDGAR SABIN SETZER,
-- save-point boundary F, lettered in tools/tests/savestate_graph.py; the
-- Continue restores the party on foot at the grounded Blackjack's tile),
-- walk the plain south of Zozo into a world encounter, and drive real Slot
-- spins with real button presses.  No pokes on either side (issue #75): BP
-- accumulates through Ot6ActionEnd's own regen (battle opens at 1, +1 per
-- unboosted turn), boost is spent with real R presses, and the reels are
-- stopped by real A presses.  Whatever icons they land on, the tier promises
-- are asserted as invariants of the mechanism's own cells.
--
-- Issue #75 conversion: headroom comes from target selection rather than
-- staging.  The monster-side stop, death-proof and HP-floor pins are gone; in
-- their place the encounter is chosen: unsuitable draws are fled (L+R, the
-- engine's own run mechanic, battle_steal's formation-variance idiom) until
-- the plain south of Zozo deals a formation with enough bodies and HP to
-- survive three Slot resolutions with the enemy side acting freely.  Unforced
-- spins mostly resolve Lagomorph (a party heal) and the boosted
-- spin's chosen triple is reel 1's real stop, so the fight's damage
-- budget is small; the check below is calibrated from the pool's measured
-- draws.  The bench still answers its menus with real Defends and the
-- party takes the enemy's real hits.
--
-- The three spins:
--   spin 1 (0 bp): nothing is pending, the turn regens +1 bp (1 -> 2), and
--     the spin resolves whatever vanilla dealt.
--   spin 2 (0 bp): bp 2 -> 3.
--   spin 3 (3 bp, three real R presses): the reel is chosen, so whatever icon
--     reel 1 was stopped on, reels 2 and 3 must find it (whole-strip drift
--     budget), the queued result is that icon's triple, and Ot6ActionEnd
--     charges exactly 3 with no regen.  If reel 1 lands the 7 in a battle
--     whose $2f49.2 forbids joker doom, the promise is documented to fold,
--     because the battle gate outranks boost, and it is asserted per that
--     rule instead.
--
-- The Ot6BoostDmg exemption rides the whole run as a write-watch: the
-- multiplier's $f0-bank OT6_SCR_BIT store must never happen under cmd $0f.
--
-- Boot drive is probe_mp_universal's, verbatim where possible (the checkpoint
-- cold Continue, the disembark guard, the encounter walk).
--
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local RIG, HELP1, MARK, DRIFT = 0x6179, 0x617B, 0x617C, 0x617D
local POS  = { 0x7B8C, 0x7B8D, 0x7B8E }
local STOP = { 0x7B8F, 0x7B90, 0x7B91 }
local PRESS = { 0x7B92, 0x7B93, 0x7B94 }
local LATCH, JOKER = 0x57BA, 0x2F49
local SETZER = 0x09

local REEL = {
  { 0,4,5,3,4,5,2,5,1,4,5,3,5,2,3,1 },
  { 0,4,1,5,3,4,1,5,4,3,2,5,4,3,2,5 },
  { 0,1,3,4,2,5,4,3,1,5,4,3,2,5,4,5 },
}
local function icon(r) return REEL[r][(H.readByte(POS[r]) >> 4) + 1] end

local slotOf, msPresent = {}, {}
local actor = nil
local function ent() return actor * 2 end
local function bp()   return H.readByte(0x3E9C + ent()) end
local function pend() return H.readByte(0x3E9D + ent()) end
local results, mulHits = {}, {}

local function onFoot()
  return (H.readByte(0x11FA) & 3) == 0 and H.readByte(0x11F3) == 0
end

-- wait for a character's menu; consume any other character's menu with a
-- real Defend (right swaps Fight->Def, then A), probe_mp_universal's idiom
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

-- move the command cursor onto the Slot row (verified against the live
-- cursor cell w7e890f+slot, because an unchecked down-press can miss and put
-- the A taps on Fight), confirm, and wait for the live reel state.
-- Setzer's real command list rows live at $202e+slot*12 (3 bytes per row).
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
      H.log(string.format("%s: Slot on row %d", what, row))
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

local function pressAUntilFn(predFn, what)
  return H.driveUntil(predFn, 3000, {
    H.call(function() H.setPad({ a = true }) end),
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
local function waitStop(r, what)
  return H.waitUntil(function() return H.readByte(STOP[r]) ~= 0 end, 900, what, 2)
end

H.run({ maxFrames = 400000 }, {
  -- cold Continue (the checkpoint's $307ff0=3 preselects slot 3), using the
  -- probe_mp_universal boot unchanged
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

  -- disembark guard (normally exits at 0 frames; see probe_mp_universal)
  (function()
    local ph, ph2 = 0, 0
    return H.driveUntil(function()
      ph = ph + 1
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

  -- walk the plain until a real encounter fires, and choose it: a draw
  -- without the headroom to survive three Slot resolutions is fled (L+R)
  -- and the walk resumes.  Check calibrated from the pool's measured draws
  -- (2026-08-10: the first draw dealt 3 bodies / 1237 total max HP, well
  -- over the >= 2 bodies / >= 600 HP floor).
  (function()
    local ph = 0
    local pattern = { "down", "down", "right", "right", "down", "down",
                      "left", "left" }
    local walkStep = function()
      return H.driveUntil(function() return H.battleLoadStarted() end, 40000, {
        H.call(function()
          ph = ph + 1
          local dir = pattern[(math.floor(ph / 20) % #pattern) + 1]
          H.setPad({ [dir] = true })
        end),
      }, "a real world encounter fires")
    end
    local surveyStep = H.call(function()
      msPresent = {}
      for m = 0, 5 do
        if H.readByte(0x3AA8 + m * 2) % 2 == 1 then
          msPresent[#msPresent + 1] = m
        end
      end
      local mhp = 0
      for _, m in ipairs(msPresent) do mhp = mhp + H.readWord(0x3BFC + m * 2) end
      H.vars.mhpTotal = mhp
      H.vars.suitable = (#msPresent >= 2 and mhp >= 600)
      H.log(string.format("draw: %d bodies, %d total max HP -> %s",
        #msPresent, mhp, H.vars.suitable and "FIGHT" or "flee"))
    end)
    local attempt = function(n)
      return H.cond(function() return not H.vars.suitable end, {
        walkStep(),
        H.release(),
        H.waitUntil(function() return H.battleActive() end, 900,
          "battle active (draw " .. n .. ")", 30),
        H.waitFrames(240),
        surveyStep,
        H.cond(function() return not H.vars.suitable end, {
          H.fleeBattle(9000),
          H.waitUntil(function()
            return H.worldMode() and H.worldHasControl()
          end, 1200, "back on the plain after fleeing draw " .. n, 10),
          H.waitFrames(30),
        }, {}),
      }, {})
    end
    local steps = {}
    for n = 1, 6 do steps[#steps + 1] = attempt(n) end
    steps[#steps + 1] = H.call(function()
      H.assertEq(H.vars.suitable, true,
        "the pool dealt a survivable formation within six draws")
    end)
    return H.repeatN(1, steps)
  end)(),

  H.call(function()
    for s = 0, 3 do
      local id = H.readByte(0x3ED8 + s * 2)
      if id ~= 0xFF then slotOf[id] = s end
    end
    H.assertEq(slotOf[SETZER] ~= nil, true, "SETZER present")
    actor = slotOf[SETZER]
    H.log(string.format("setzer slot %d monsters={%s} joker=$%02x",
      actor, table.concat(msPresent, ","), H.readByte(JOKER)))
    -- the C1 commit write of the result index
    emu.addMemoryCallback(function(a, v)
      pcall(function()
        local s = emu.getState()
        if s["cpu.k"] == 0xC1 then results[#results + 1] = { addr = a, v = v } end
      end)
    end, emu.callbackType.write, 0x7E2BB0, 0x7E2BC9)
    -- the exemption watch: Ot6BoostDmg's multiplier parks its counter in
    -- OT6_SCR_BIT ($3ece) before multiplying, so a write from inside the proc
    -- under cmd $0f means the multiplier ran, which the exemption forbids
    -- ($3ece is shared OT6 scratch, so the pc range is load-bearing)
    local BOOSTDMG = H.sym("Ot6BoostDmg")
    emu.addMemoryCallback(function(_, v)
      -- cheap guards first: the same conjunction, reordered.  See the
      -- matching watch in battle_slots.lua for the measurement: emu.getState()
      -- serialises the machine on every call, and $3ece is shared OT6
      -- scratch written tens of thousands of times a run.
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

  -- ------------------------------- spin 1: 0 bp, no boost bytes written ----
  menuFor(SETZER, "setzer menu (spin 1)"),
  H.call(function()
    H.assertEq(bp(), 1, "battle opens at 1 bp (Ot6InitBP)")
    H.assertEq(pend(), 0, "nothing pending")
  end),
  openSlotWindow("spin1"),
  pressAUntil(PRESS[1], "spin1 press1"),
  H.call(function()
    H.assertEq(H.readByte(LATCH), 0, "spin1: latched tier 0")
    H.log(string.format("spin1: rig=$%02x (vanilla draw, untouched)", H.readByte(RIG)))
  end),
  waitStop(1, "spin1 reel1"), pressAUntil(PRESS[2], "spin1 press2"),
  waitStop(2, "spin1 reel2"), pressAUntil(PRESS[3], "spin1 press3"),
  waitStop(3, "spin1 reel3"),
  pressCommit("spin1 commit"),
  H.call(function()
    local i1, i2, i3 = icon(1), icon(2), icon(3)
    local want = (i1 == i2 and i2 == i3) and i1 + 1
      or ((i1 == 0 and i2 == 0 and i3 == 2) and 0 or 7)
    H.assertEq(results[#results].v, want,
      string.format("spin1: result matches the landed icons (%d,%d,%d)", i1, i2, i3))
    H.assertEq(pend(), 0, "spin1: still nothing pending at commit")
  end),
  H.driveUntil(function() return bp() == 2 end, 9000,
    { H.waitFrames(1) }, "spin1: unboosted turn regens 1 -> 2"),

  -- ------------------------------------------------ spin 2: 0 bp, bank to 3
  menuFor(SETZER, "setzer menu (spin 2)"),
  openSlotWindow("spin2"),
  pressAUntil(PRESS[1], "spin2 press1"),
  waitStop(1, "spin2 reel1"), pressAUntil(PRESS[2], "spin2 press2"),
  waitStop(2, "spin2 reel2"), pressAUntil(PRESS[3], "spin2 press3"),
  waitStop(3, "spin2 reel3"),
  pressCommit("spin2 commit"),
  H.driveUntil(function() return bp() == 3 end, 9000,
    { H.waitFrames(1) }, "spin2: bp 2 -> 3"),

  -- ------------------------------- spin 3: three real R presses, icon chosen
  menuFor(SETZER, "setzer menu (spin 3)"),
  H.waitFrames(20),
  H.repeatN(3, { H.pressButtons({ "r" }, 6), H.waitFrames(20) }),
  H.call(function()
    H.assertEq(pend(), 3, "three R presses banked pending 3 (real input)")
    H.assertEq(bp(), 3, "bp untouched until the action ends")
  end),
  openSlotWindow("spin3"),
  pressAUntil(PRESS[1], "spin3 press1"),
  H.call(function()
    H.assertEq(H.readByte(LATCH), 3, "spin3: latched tier 3 at the first press")
    local want = (H.readByte(JOKER) & 4) ~= 0 and 0x3C or 0x00
    H.assertEq(H.readByte(RIG), want, "spin3: rig forced benevolent")
  end),
  waitStop(1, "spin3 reel1"),
  H.call(function()
    H.log(string.format("spin3: reel 1 stopped on icon %d (pos $%02x)",
      icon(1), H.readByte(POS[1])))
  end),
  pressAUntil(PRESS[2], "spin3 press2"),
  H.call(function()
    -- the chosen icon is reel 1's real stop.  In a joker-forbidden battle a
    -- timed 7 is the documented exception: no help and no bought triple.
    local chosen = icon(1)
    local gated = chosen == 0 and (H.readByte(JOKER) & 4) ~= 0
    if gated then
      H.assertEq(H.readByte(HELP1), 0xFF, "spin3: 7s stay gated ($2f49.2)")
    else
      -- (w7e617d is not asserted here: the seek decrements it live; the
      -- whole-strip budget is proven by the icon asserts below and by
      -- battle_slots' write-watch)
      H.assertEq(H.readByte(HELP1), chosen, "spin3: reel 2 seeks the chosen icon")
    end
  end),
  waitStop(2, "spin3 reel2"),
  pressAUntil(PRESS[3], "spin3 press3"),
  waitStop(3, "spin3 reel3"),
  pressCommit("spin3 commit"),
  H.call(function()
    local chosen = icon(1)
    local gated = chosen == 0 and (H.readByte(JOKER) & 4) ~= 0
    if gated then
      H.log("spin3: joker-gated 7 -- triple not bought (documented exception)")
    else
      H.assertEq(icon(2), chosen, "spin3: reel 2 landed the chosen icon")
      H.assertEq(icon(3), chosen, "spin3: reel 3 landed the chosen icon")
      H.assertEq(results[#results].v, chosen + 1,
        string.format("spin3: THE CHOSEN TRIPLE queued (icon %d -> index %d)",
          chosen, chosen + 1))
    end
    H.assertEq(pend(), 3, "spin3: the commit banked the latched tier")
    H.screenshot("slotsboot_chosen")
  end),
  H.driveUntil(function() return pend() == 0 end, 15000,
    { H.waitFrames(1) }, "spin3: the boosted action resolves"),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(bp(), 0, "spin3: 3 bp charged in full, no regen on a boosted turn")
    H.assertEq(#mulHits, 0,
      "EXEMPTION: the damage multiplier never ran under cmd $0f (natural run)")
    H.log("battle_slotsboot complete")
  end),
})
