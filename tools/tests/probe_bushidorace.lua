-- probe_bushidorace.lua -- can the boost spend change AFTER the bushido
-- latch has frozen the tech?
--
-- The late-boost gate (Ot6Boost's $32cc test) was built for the MAGIC
-- path, where the tier consumer -- Ot6QueueFold inside CreateAction -- runs
-- at the same instant $32cc goes live, so a boost change any time before
-- the gate closes is read by fold and charge alike: always consistent.
--
-- Bushido's tier consumer runs EARLIER.  UpdateMenuState_37's A-branch
-- (btlgfx_main.asm:19082) latches Ot6BushidoTier's level into $2bb0,y at
-- the moment A is pressed, then `inc w7e7bcb` starts the menu CLOSING --
-- and only when C2's GetPlayerAction (battle_main.asm:12643) drains the
-- $2bae queue does CreateNormalAction run and $32cc go live.  Between
-- those two moments the menu is still "open" by Ot6Boost's own gate
-- ($7bca is nonzero until the close animation lands), so L/R edges are
-- still accepted and change $3e9d -- which the latched tech no longer
-- reads, but Ot6ActionEnd still charges.
--
-- Driven here with the real input path, no RAM pokes on the boost side:
-- raise pending to 3 with three R edges in the gauge window, press A
-- (tempest latched), then mash L edges during the close.  If any L lands,
-- the executed attack stays tempest ($5b) while ActionEnd charges the
-- lowered pending -- tempest for free at the limit.  The per-frame trace
-- of ($7bca, $7bc2, $7bcb, pending, $32cc) is the evidence either way.
local H = dofile("/Users/mtklein/ot6/.claude/worktrees/agent-a1ed6959a07898907/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/.claude/worktrees/agent-a1ed6959a07898907/build/states/battle_doorstep.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local KNOWN = 0x2020
local ST_BUSHIDO = 0x37

local PARTY = { 0, 1, 2 }
local GUARDS = { 2, 3 }
local function ST3(e) return 0x3EF8 + e end

local actor
local spells = {}
local trace = {}
local pendAt = { r3 = nil, latch = nil, execu = nil }
local bpAfter, bpBefore = nil, 5

local function st() return H.readByte(MSTATE) end
local function bp() return H.readByte(0x3E9C + actor * 2) end
local function pend() return H.readByte(0x3E9D + actor * 2) end
local function cmdptr() return H.readByte(0x32CC + actor * 2) end
local function inWindow() return st() == ST_BUSHIDO end

local function pinCyan()
  H.writeWord(KNOWN, 7)
  for _, s in ipairs(PARTY) do
    H.writeByte(0x3ED8 + s * 2, 0x02)                 -- CHAR::CYAN
    local st1 = 0x3EE4 + s * 2
    H.writeByte(st1, H.readByte(st1) & 0xF7)          -- clear magitek
    H.writeByte(0x202E + s * 12, 0x07)                -- Bushido, alone
    H.writeByte(0x2031 + s * 12, 0xFF)
    H.writeByte(0x2034 + s * 12, 0xFF)
    H.writeByte(0x2037 + s * 12, 0xFF)
    H.writeByte(0x3BA4 + s * 2, H.readByte(0x3BA4 + s * 2) | 0x02)
    H.writeByte(0x3BA5 + s * 2, H.readByte(0x3BA5 + s * 2) | 0x02)
    H.writeWord(0x3BF4 + s * 2, 999)
  end
  if actor then H.writeByte(0x3E9C + actor * 2, 5) end -- full bank (setup only)
end

local function pinGuards()
  for _, s in ipairs(GUARDS) do
    local e = 8 + s * 2
    H.writeByte(ST3(e), H.readByte(ST3(e)) | 0x10)     -- stopped
    H.writeWord(0x3BFC + s * 2, 0xF000)                -- nobody dies
  end
end

local function snap(tag)
  trace[#trace + 1] = string.format(
    "  f%04d %-9s menu=%d st=%02x closing=%d pend=%d cmdptr=%02x bp=%d",
    H.frame, tag, H.readByte(MENU), st(), H.readByte(0x7BCB),
    pend(), cmdptr(), bp())
end

H.run({ maxFrames = 40000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  H.call(function()
    emu.addMemoryCallback(function(_, v) spells[#spells + 1] = v end,
      emu.callbackType.write, 0x7E3410, 0x7E3410)
  end),
  H.driveUntil(function() return H.readByte(MENU) ~= 0 end, 3000, {
    H.call(function() pinCyan(); pinGuards() end), H.waitFrames(1),
  }, "a battle menu opens"),
  H.call(function()
    actor = H.readByte(ACTOR)
    H.log(string.format("cyan installed in slot %d", actor))
  end),
  H.driveUntil(inWindow, 900, {
    H.call(function() pinCyan(); pinGuards(); H.setPad({ "a" }) end),
    H.waitFrames(2),
    H.call(function() H.setPad({}) end),
    H.waitFrames(14),
  }, "the swdtech window opens (menu state $37)"),
  H.waitFrames(6),
  -- three R edges through the real input path: pending 0 -> 3
  H.repeatN(3, {
    H.hold({ "r" }), H.waitFrames(2), H.release(), H.waitFrames(4),
  }),
  H.call(function()
    pendAt.r3 = pend()
    H.assertEq(pendAt.r3, 3, "three R edges banked pending 3 in the gauge")
    H.assertEq(bp(), 5, "bank still full before the latch")
    bpBefore = bp()
    snap("pre-latch")
  end),
  -- A latches the tech (tempest: 3-bp band, all techs known) and starts
  -- the menu close.  From the very next frame, mash L edges and record
  -- what the gate does with them.
  H.hold({ "a" }), H.waitFrames(2), H.release(),
  H.call(function() pendAt.latch = pend(); snap("latched") end),
  H.repeatN(14, {
    H.hold({ "l" }), H.call(function() snap("L-dn") end), H.waitFrames(1),
    H.release(),     H.call(function() snap("L-up") end), H.waitFrames(1),
  }),
  H.call(function() snap("mash-done") end),
  H.waitUntil(function() return #spells > 0 end, 1200, "the tech executed", 5),
  H.call(function()
    pendAt.execu = pend()
    snap("exec")
  end),
  H.waitUntilSoft(function() return pend() == 0 end, 900, "pending consumed", 10),
  H.waitFrames(120),
  H.call(function()
    bpAfter = bp()
    snap("settled")
    H.log("frame trace:")
    for _, l in ipairs(trace) do H.log(l) end
    local ids = {}
    for _, v in ipairs(spells) do ids[#ids + 1] = string.format("%02x", v) end
    H.log("executed attack ids: " .. table.concat(ids, " "))
    local tech = nil
    for _, v in ipairs(spells) do
      if v >= 0x55 and v <= 0x5C then tech = v - 0x55 end
    end
    H.log(string.format(
      "VERDICT: latched pending=%d, pending at exec=%d, tech executed=%s, bp %d -> %d",
      pendAt.latch or -1, pendAt.execu or -1, tostring(tech), bpBefore, bpAfter))
    if tech == 6 and bpAfter == 2 then
      H.log("VERDICT: CONSISTENT -- L edges after the latch were refused; tempest cost 3")
    elseif tech == 6 and bpAfter > 2 then
      H.log(string.format(
        "VERDICT: INCONSISTENT -- tempest delivered but only %d bp charged: "
        .. "the close-window race is real", bpBefore - bpAfter))
    else
      H.log("VERDICT: UNEXPECTED SHAPE -- read the trace")
    end
  end),
})
