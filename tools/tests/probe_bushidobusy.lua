-- @suite
-- probe_bushidobusy.lua -- the bushido latch race, with C2 busy.
--
-- probe_bushidorace measured the idle case: $32cc goes live ONE frame
-- after the A latch (GetPlayerAction drains the $2bae queue on the next
-- C2 loop pass), so the Ot6Boost gate refuses every post-latch L/R edge
-- and the charge always matches the latched tech.  But GetPlayerAction
-- only runs when C2 is between actions.  If ANOTHER entity's action is
-- still executing when A latches -- C2 parked inside ExecCmd for the
-- animation -- the latched action sits in $2bae with $32cc still $ff,
-- the menu walks its close with $7bca nonzero, and Ot6Boost has nothing
-- left to gate with: the latch froze the tech, but pending is still
-- writable, and Ot6ActionEnd will charge whatever it reads later.
--
-- Repro on real paths only: Cyan parks in the OPEN gauge with 3 boosts
-- banked (state 37 idles; the guard fight goes on around it -- that
-- real-time risk is vanilla's own swdtech design).  One guard is left
-- live.  The moment its queued action starts executing (its $32cc
-- transitions live -> $ff at dequeue, battle_main.asm @017a, and ExecCmd
-- then owns C2 for the whole animation), press A and mash L.  If the L
-- edges land while Cyan's own $32cc is still $ff, the executed tech
-- stays tempest while the charge shrinks -- the inconsistency the idle
-- probe could not reach.
local H = dofile("/Users/mtklein/ot6/.claude/worktrees/agent-a1ed6959a07898907/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/.claude/worktrees/agent-a1ed6959a07898907/build/states/battle_doorstep.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local KNOWN = 0x2020
local ST_BUSHIDO = 0x37
local GUARD_LIVE = 2                -- monster slot: entity $0c, $32cc+$0c
local GUARD_STOP = 3

local PARTY = { 0, 1, 2 }
local function ST3(e) return 0x3EF8 + e end

local actor
local spells = {}
local trace = {}
local sawGuardPtr = false
local bpBefore, pendLatch, pend2

local function st() return H.readByte(MSTATE) end
local function bp() return H.readByte(0x3E9C + actor * 2) end
local function pend() return H.readByte(0x3E9D + actor * 2) end
local function cmdptr() return H.readByte(0x32CC + actor * 2) end
local function guardPtr() return H.readByte(0x32CC + 8 + GUARD_LIVE * 2) end
local function inWindow() return st() == ST_BUSHIDO end

local function pinCyan(withBank)
  H.writeWord(KNOWN, 7)
  -- Oblivion (tech 7) is now selectable at BP3 once the divine is unspent
  -- (Ot6BushidoTier). This probe is about the busy-C2 charge race at the
  -- TEMPEST rung, not the divine, so pin every character's divine SPENT
  -- ($3ECB low nibble) -- Ot6BushidoTier then drops BP3 back to Tempest (6).
  H.writeByte(0x3ECB, 0x0F)
  for _, s in ipairs(PARTY) do
    H.writeByte(0x3ED8 + s * 2, 0x02)
    local st1 = 0x3EE4 + s * 2
    H.writeByte(st1, H.readByte(st1) & 0xF7)
    H.writeByte(0x202E + s * 12, 0x07)
    H.writeByte(0x2031 + s * 12, 0xFF)
    H.writeByte(0x2034 + s * 12, 0xFF)
    H.writeByte(0x2037 + s * 12, 0xFF)
    H.writeByte(0x3BA4 + s * 2, H.readByte(0x3BA4 + s * 2) | 0x02)
    H.writeByte(0x3BA5 + s * 2, H.readByte(0x3BA5 + s * 2) | 0x02)
    H.writeWord(0x3BF4 + s * 2, 999)
    if withBank then H.writeByte(0x3E9C + s * 2, 5) end
  end
end

local function pinGuards()
  local e = 8 + GUARD_STOP * 2
  H.writeByte(ST3(e), H.readByte(ST3(e)) | 0x10)   -- slot 3 stopped
  for _, s in ipairs({ GUARD_LIVE, GUARD_STOP }) do
    H.writeWord(0x3BFC + s * 2, 0xF000)
  end
end

local function snap(tag)
  trace[#trace + 1] = string.format(
    "  f%04d %-10s menu=%d st=%02x pend=%d cmd=%02x bp=%d guard=%02x",
    H.frame, tag, H.readByte(MENU), st(), pend(), cmdptr(), bp(), guardPtr())
end

H.run({ maxFrames = 40000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.enterEncounter(),
  H.call(function()
    emu.addMemoryCallback(function(_, v) spells[#spells + 1] = v end,
      emu.callbackType.write, 0x7E3410, 0x7E3410)
  end),
  H.driveUntil(function() return H.readByte(MENU) ~= 0 end, 3000, {
    H.call(function() pinCyan(true); pinGuards() end), H.waitFrames(1),
  }, "a battle menu opens"),
  H.call(function()
    actor = H.readByte(ACTOR)
    H.log(string.format("cyan slot %d parks in the gauge; guard slot %d live",
      actor, GUARD_LIVE))
  end),
  -- into the gauge; short presses with a long tail so A is UP on the
  -- entry frame (a held A instalatches: state 37 reads the $04 autofire
  -- word on its first frame -- this cadence measured clean in
  -- probe_bushidorace)
  H.driveUntil(inWindow, 1200, {
    H.call(function() H.setPad({ "a" }) end),
    H.waitFrames(2),
    H.call(function() H.setPad({}) end),
    H.waitFrames(14),
  }, "the swdtech window opens (menu state $37)"),
  H.waitFrames(6),
  H.repeatN(3, {
    H.hold({ "r" }), H.waitFrames(2), H.release(), H.waitFrames(4),
  }),
  H.call(function()
    H.assertEq(pend(), 3, "three R edges banked pending 3 in the gauge")
    bpBefore = bp()
    snap("parked")
  end),
  -- park until the live guard's queued action starts executing: its
  -- $32cc goes live when its AI queues, then back to $ff at dequeue --
  -- and from that frame C2 is inside ExecCmd for the whole animation.
  H.driveUntil(function()
    local g = guardPtr()
    if g ~= 0xFF then sawGuardPtr = true end
    return sawGuardPtr and g == 0xFF
  end, 6000, {
    H.call(function() pinCyan(true) end), H.waitFrames(1),
  }, "the live guard's action starts executing"),
  H.call(function()
    pendLatch = pend()
    snap("guard-exec")
  end),
  -- latch NOW, inside the guard's animation, and mash L
  H.hold({ "a" }), H.waitFrames(2), H.release(),
  H.call(function() snap("latched"); spells = {} end),
  H.repeatN(20, {
    H.hold({ "l" }), H.call(function() snap("L-dn") end), H.waitFrames(1),
    H.release(),     H.call(function() snap("L-up") end), H.waitFrames(1),
  }),
  H.call(function() pend2 = pend(); snap("mash-done") end),
  H.waitUntil(function()
    for _, v in ipairs(spells) do
      if v >= 0x55 and v <= 0x5C then return true end
    end
    return false
  end, 2400, "cyan's tech executed", 5),
  H.call(function() snap("exec") end),
  -- Ot6ActionEnd runs when the ACTION finishes, well after the attack
  -- loads; wait for the consume itself (pending -> 0), then settle.
  H.waitUntilSoft(function() return pend() == 0 end, 1800, "pending consumed", 10),
  H.waitFrames(120),
  H.call(function()
    snap("settled")
    H.log("frame trace:")
    for _, l in ipairs(trace) do H.log(l) end
    local ids = {}
    for _, v in ipairs(spells) do ids[#ids + 1] = string.format("%02x", v) end
    H.log("post-latch attack ids: " .. table.concat(ids, " "))
    local tech = nil
    for _, v in ipairs(spells) do
      if v >= 0x55 and v <= 0x5C then tech = v - 0x55 end
    end
    local bpAfter = bp()
    H.log(string.format(
      "VERDICT: pending at latch=%d, tech executed=%s, bp %d -> %d",
      pendLatch or -1, tostring(tech), bpBefore or -1, bpAfter))
    if tech == 6 and bpAfter == 2 then
      H.log("VERDICT: CONSISTENT even under a busy C2 -- charge matches the latch")
    elseif tech == 6 and bpAfter > 2 then
      H.log(string.format(
        "VERDICT: INCONSISTENT -- tempest delivered for %d bp: the busy-C2 "
        .. "latch window is real", (bpBefore or 5) - bpAfter))
    else
      H.log("VERDICT: UNEXPECTED SHAPE -- read the trace (was the latch "
        .. "actually inside the guard's animation?)")
    end
    -- regression gate for the Ot6Boost $2bae ring check: before it, one
    -- post-latch L edge landed here (pend 3 -> 2) and tempest charged 2.
    H.assertEq(tech, 6, "the latched tempest is what executed")
    H.assertEq(pend2, 3, "every post-latch L edge was refused (pending held at 3)")
    H.assertEq(bpAfter, 2, "and the charge matches the latch: 3 bp paid")
  end),
})
