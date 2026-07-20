-- probe_ctrboost.lua -- does a pending boost leak into COUNTERATTACKS?
--
-- Counterattacks execute through ExecRetal (battle_main.asm:12430), which
-- ends at its own `jmp EndAction` -- not the hooked one -- so they never
-- reach Ot6ActionEnd: a counter neither charges pending boost nor earns
-- the +1 regen.  Right for the charge; but the EXEC-time hooks read
-- pending with x = the countering character, so the boost is DELIVERED
-- without ever being paid:
--   - black belt counters are command $00 fight (battle_main.asm:12621
--     `stz $3a7a`), so Ot6FightBoost adds 2*pending swings to the free
--     counter -- measured here via the $3a70 swing count;
--   - INTERCEPTOR counters are command $02 attack $fc/$fd (:12606), no
--     Ot6BoostDmg exemption -- same class, x2/x4/x8 on the dog (not
--     measurable on this fixture: synthetic $3416 procs load the attack
--     but its damage never applies without the real dog state);
--   - retort counters are command $07 -- exempt only because bushido
--     already is.
-- Pending boost is compose-time state: it is nonzero exactly while the
-- player is lining up their NEXT action, which is exactly when a counter
-- can fire.  Black Belt is a WoB relic and Cyan's retort stance makes
-- "hit while composing" the common case in the v0.3 arc.
--
-- Measured: slot 0 wears a synthetic black belt ($3c58 bit 1), guards
-- swing at the parked party.  Phase A pending 0, phase B pending 3.
-- Every $3a70 write is logged with the counterattack flag ($b1.0):
-- FightAttack stores the vanilla swing count (1), then Ot6FightBoost
-- stores 1+2*pending -- a [1,7] pair on a $b1.0=1 action is the leak.
local H = dofile("/Users/mtklein/ot6/.claude/worktrees/agent-a1ed6959a07898907/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/.claude/worktrees/agent-a1ed6959a07898907/build/states/battle_doorstep.mss.lua"

local swings = {}           -- {frame=, v=, ctr=} for every $3a70 write
local results = {}

local function pend0() return H.readByte(0x3E9D) end
local function bp0() return H.readByte(0x3E9C) end

local function pinField(pendWant)
  for s = 0, 3 do
    H.writeWord(0x3BF4 + s * 2, 999)                        -- party hp
    local st1 = 0x3EE4 + s * 2                              -- magitek blocks
    H.writeByte(st1, H.readByte(st1) & 0xF7)                --  the counter's
  end                                                       --  CheckStatus
  H.writeByte(0x3C58, H.readByte(0x3C58) | 0x02)            -- black belt, slot 0
  H.writeByte(0x3419, H.readByte(0x3419) & 0xFE)            -- ...and in the
                                                            -- target mask the
                                                            -- equip load derives
  H.writeByte(0x3E9D, pendWant)                             -- pending boost
  H.writeByte(0x3E9C, 5)                                    -- full bank
end

local function counterSwing()
  for _, w in ipairs(swings) do
    if w.ctr == 1 then return w end
  end
  return nil
end

local function maxCounterSwing()
  -- max $3a70 on a counterattack, excluding the $ff end sentinel: the
  -- peak is the swing count Ot6FightBoost left (1 vanilla; 1+2*pending
  -- when the leak is live -- the countdown 7,6,..,0 follows it)
  local m = nil
  for _, w in ipairs(swings) do
    if w.ctr == 1 and w.v < 255 and (m == nil or w.v > m) then m = w.v end
  end
  return m
end

local function phaseSteps(tag, pendWant)
  return {
    H.call(function()
      swings = {}
      pinField(pendWant)
      H.log(string.format("phase %s: pending pinned %d, black belt armed",
        tag, pendWant))
    end),
    H.driveUntil(function() return counterSwing() ~= nil end, 30000, {
      H.call(function()
        if counterSwing() == nil then pinField(pendWant) end
      end),
      H.waitFrames(1),
    }, tag .. ": a black belt counter fired"),
    H.waitFrames(240),      -- let the counter finish (all its swings land)
    H.call(function()
      local parts = {}
      for _, w in ipairs(swings) do
        parts[#parts + 1] = string.format("f%05d:%d%s", w.frame, w.v,
          w.ctr == 1 and "*" or "")
      end
      H.log("  $3a70 writes (*=counterattack): " .. table.concat(parts, " "))
      results[tag] = { swings = maxCounterSwing(), pendAfter = pend0(),
                       bpAfter = bp0() }
      H.log(string.format("phase %s: counter swing count %d; after it pending=%d bp=%d",
        tag, results[tag].swings, pend0(), bp0()))
    end),
  }
end

H.run({ maxFrames = 90000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  H.call(function()
    for s = 0, 5 do
      if H.readWord(0x3BFC + s * 2) > 0 then H.writeWord(0x3BFC + s * 2, 0xF000) end
    end
    emu.addMemoryCallback(function(_, v)
      swings[#swings + 1] = { frame = H.frame, v = v,
                              ctr = H.readByte(0xB1) & 1 }
    end, emu.callbackType.write, 0x7E3A70, 0x7E3A70)
  end),
  H.waitFrames(60),
  H.repeatN(1, phaseSteps("A", 0)),
  H.repeatN(1, phaseSteps("B", 3)),
  H.call(function()
    local a, b = results.A, results.B
    H.log(string.format(
      "VERDICT: counter swings with pending 0 = %d, with pending 3 = %d",
      a.swings, b.swings))
    H.log(string.format(
      "VERDICT: after phase B's counter pending=%d bp=%d (%s)",
      b.pendAfter, b.bpAfter,
      (b.pendAfter == 3 and b.bpAfter == 5)
        and "never charged: delivered unpaid" or "charged?"))
    if b.swings > a.swings then
      H.log("VERDICT: INCONSISTENT -- the pending boost swings on a free counter")
    else
      H.log("VERDICT: counters ignore pending boost -- consistent")
    end
    -- regression gate (for the $b1.0 counterattack gate in the exec
    -- hooks): a counter's swing count must not scale with pending.
    H.assertEq(a.swings, b.swings,
      "a counterattack's swing count does not scale with pending boost")
    H.assertEq(b.pendAfter, 3, "and the counter never charges the pending")
  end),
})
