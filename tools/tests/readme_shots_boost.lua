-- @manual
-- readme_shots_boost.lua -- battle_boost.lua's banking driver, then screenshots
-- of the boost pips at pending 1/2/3 and of the boosted action resolving
-- (README boost bullet).  Not a test.
-- battle_boost: L/R boost-select in the battle menu, end to end.
--   R raises the active character's pending boost (cap 3, never past bp),
--   L lowers it, the party-window pip cell tracks live, and the boosted
--   action consumes the points (and skips that turn's +1 regen).
--   ...and the repaint request that press raises (OT6_RESTAGE) is spent or
--   dropped rather than left standing (see the first R press below).
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_entry.mss.lua"
local MSTATE, RESTAGE = 0x7BC2, 0x57D4   -- menu state; the gate's request byte
local ST_CMD = 0x05                      -- the battle command window
local function pend(slot) return H.readByte(0x3e9d + slot*2) end
local function bp(slot) return H.readByte(0x3e9c + slot*2) end
local actor
local cellSeen, cellFrames = {}, 0
local markSeen, parkFrames = {}, 0
local restageTrace = {}                  -- OT6_RESTAGE, sampled per frame

-- sfx request counters: boost feedback must be audible. Each request is an
-- inc (nonzero write) consumed by UpdateSfx's stz, so count nonzero writes.
local sfx = { ching = 0, click = 0, error = 0 }
local sfxRefs = {}
local function sfxWatch()
  sfxRefs[1] = emu.addMemoryCallback(function(addr, value)
    if value == 0 then return end
    if addr == 0x7e6281 then sfx.ching = sfx.ching + 1 end
  end, emu.callbackType.write, 0x7e6281, 0x7e6281)
  -- $94/$95 are direct-page writes: the cpu issues them in bank 0's wram
  -- mirror, so the callback must watch $000094, not $7e0094
  sfxRefs[2] = emu.addMemoryCallback(function(addr, value)
    if value == 0 then return end
    if addr == 0x000094 then sfx.click = sfx.click + 1 end
    if addr == 0x000095 then sfx.error = sfx.error + 1 end
  end, emu.callbackType.write, 0x000094, 0x000095)
end
local function sfxUnwatch()
  emu.removeMemoryCallback(sfxRefs[1], emu.callbackType.write, 0x7e6281, 0x7e6281)
  emu.removeMemoryCallback(sfxRefs[2], emu.callbackType.write, 0x000094, 0x000095)
end
H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.enterEncounter(),
  H.waitFrames(240),
  -- every character opens with 1 bp (Ot6InitBP) and an unboosted action
  -- regens +1 (Ot6ActionEnd), so the first slot whose menu opens takes two
  -- real actions and arrives at this test's window holding 3.  The submit
  -- is driven by menu state ($7BC2) rather than by a fixed button
  -- sequence.  The bank action is the row-2 beam (Heal Force, row 3, is
  -- priced out of the opening MP).  The item window fails two ways: the
  -- intro bag is empty, and Wait mode stops time while a list is open, so
  -- holding A in state $0a freezes the fight.  Any other ready character
  -- defers focus with X, vanilla's own turn-cycling key.  Two beams into
  -- shielded guards cannot end the fight (shielded damage is halved), and
  -- each is an ordinary unboosted action worth +1 bp (Ot6ActionEnd), twice,
  -- on top of the 1 bp the actor opened with (Ot6InitBP).  $01 is
  -- transitional, so the driver leaves the pad alone; anything unknown
  -- gets B to back out.
  (function()
    local mf, downs = 0, 0
    return H.driveUntil(function()
      if H.readByte(0x7bca) == 0 then return false end
      local act = H.readByte(0x62ca)
      if actor == nil then
        actor = act
        H.log("banking bp on the first active slot: " .. actor)
      end
      return act == actor and bp(actor) >= 3
    end, 12000, {
      H.call(function()
        if H.readByte(0x7bca) == 0 then mf, downs = 0, 0; H.setPad({}); return end
        local act = H.readByte(0x62ca)
        if actor ~= nil and act == actor and bp(actor) >= 3 then
          H.setPad({}); return
        end
        mf = mf + 1
        if (mf - 1) % 8 >= 4 then H.setPad({}); return end
        local st = H.readByte(0x7bc2)
        local btn
        if actor ~= nil and act ~= actor then
          btn = st == 0x05 and "x" or "b"   -- defer focus; back out first
        elseif st == 0x05 then btn = "a"    -- open the magitek list
        elseif st == 0x2a then
          if downs < 2 then
            if (mf - 1) % 8 == 0 then downs = downs + 1 end
            btn = "down"
          else btn = "a" end                -- the row-2 beam
        elseif st == 0x38 then btn = "a"    -- confirm the default target
        -- (an offensive confirm defaults to the enemy-side pick, never the
        -- party, and this fixture stages one monster)
        elseif st == 0x01 then H.setPad({}); return
        else btn = "b" end
        if (mf - 1) % 8 == 0 then
          H.log(string.format("bank: f%d st=%02x press %s (act=%d bp=%d)",
            H.frame, st, btn, act, bp(act)))
        end
        H.setPad({ [btn] = true })
      end),
    }, "bank 3 bp by real beam turns")
  end)(),
  H.call(function()
    H.assertEq(bp(actor), 3, "3 bp banked by real turns (1 open + 2 regen)")
    H.log(string.format("banked: slot %d bp=%d hp %d %d %d", actor, bp(actor),
      H.readWord(0x3BF4), H.readWord(0x3BF6), H.readWord(0x3BF8)))
    sfxWatch()
  end),
  H.waitFrames(30), H.call(function() H.screenshot("rb_pend0_bp3") end),
  H.pressButtons({ "r" }, 6), H.waitFrames(30),
  H.call(function() H.screenshot("rb_pend1") end),
  H.pressButtons({ "r" }, 6), H.waitFrames(30),
  H.call(function() H.screenshot("rb_pend2") end),
  H.pressButtons({ "r" }, 6), H.waitFrames(30),
  H.call(function() H.screenshot("rb_pend3") end),
  H.pressButtons({ "a" }, 6), H.waitFrames(30),
  H.call(function() H.screenshot("rb_pend3_list") end),
  H.pressButtons({ "b" }, 6), H.waitFrames(30),
  H.pressButtons({ "l" }, 6), H.waitFrames(30),
  H.call(function() H.screenshot("rb_pend2b") end),
  (function()
    local n = 0
    return H.driveUntil(function() return bp(actor) ~= 3 end, 10000, {
      H.call(function()
        n = n + 1
        if n % 2 == 0 then H.screenshot(string.format("rb_act_f%d_m%02x", H.frame, H.readByte(MSTATE))) end
        if H.readByte(0x7bca) ~= 0 then H.setPad({ "a" }) end
      end),
      H.waitFrames(4),
      H.call(function() H.setPad({}) end),
      H.waitFrames(4),
    }, "boosted action lands")
  end)(),
  H.repeatN(40, { H.call(function() H.screenshot(string.format("rb_post_f%d", H.frame)) end), H.waitFrames(6) }),
})
