-- probe_bushido.lua -- the measurement instrument behind battle_bushido.
--
--   tools/tests/run.sh tools/tests/probe_bushido.lua build/states/probe_bushido.log
--
-- Cyan is not recruitable until the v0.3 arc, so he is INSTALLED into the
-- opening guard fight: every party slot gets CHAR::CYAN ($3ED8), a
-- Bushido-only command list ($202E stride 12), the weapon SWDTECH flag
-- ($3BA4/$3BA5 bit 1 -- UpdateCmd_02 greys the command without it,
-- battle_main.asm:13690), and a pinned $2020 (techs known - 1).
--
-- What this probe answers, none of which the source alone settles:
--   1. does the command list actually offer Bushido after the poke, and
--      does one A press land in menu state $37 (the swdtech window)?
--   2. is $7BCA (menu open, Ot6Boost's gate) still nonzero INSIDE that
--      window -- i.e. does L/R still move the boost there?
--   3. what does w7e7b82 do over time now?  vanilla ticked it every 4
--      frames; the conversion should leave it dead flat.
--   4. what does a short A press in the window latch, and what attack id
--      reaches $3410 ("last spell used", InitTarget_02 battle_main.asm:6545)?
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"

local MENU, ACTOR, MSTATE, BAR, KNOWN = 0x7BCA, 0x62CA, 0x7BC2, 0x7B82, 0x2020
local PARTY = { 0, 1, 2 }
local actor, ceiling = nil, 7
local trace, barSeen, spells = {}, {}, {}

local function pinCyan()
  H.writeWord(KNOWN, ceiling)
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
    H.writeByte(0x3E9C + s * 2, 5)                    -- a full bank to spend
  end
end

local function snap(tag)
  trace[#trace + 1] = string.format(
    "%-13s menu=%02x state=%02x actor=%d bar=%02x lvl=%d pend=%s",
    tag, H.readByte(MENU), H.readByte(MSTATE), H.readByte(ACTOR),
    H.readByte(BAR), H.readByte(BAR) // 32,
    actor and H.readByte(0x3E9D + actor * 2) or "?")
  H.log("[probe] " .. trace[#trace])
end

local function sampleBar()
  local v = H.readByte(BAR)
  barSeen[v] = (barSeen[v] or 0) + 1
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
    H.writeWord(0x3C00, 3000); H.writeWord(0x3C02, 3000)
    emu.addMemoryCallback(function(_, v) spells[#spells + 1] = v end,
      emu.callbackType.write, 0x7E3410, 0x7E3410)
  end),
  -- install Cyan every frame until a menu belongs to somebody
  H.driveUntil(function() return H.readByte(MENU) ~= 0 end, 3000, {
    H.call(pinCyan), H.waitFrames(1),
  }, "a battle menu opens"),
  H.call(function()
    actor = H.readByte(ACTOR)
    H.log("[probe] actor slot " .. actor)
    snap("menu-open")
    H.screenshot("bushido_cmdlist")
  end),
  -- (2a) does R move the boost from the COMMAND menu?
  H.pressButtons({ "r" }, 6), H.waitFrames(20),
  H.call(function() snap("after-R") end),
  -- (1) short A presses: does one reach the swdtech window?
  H.driveUntil(function() return H.readByte(MSTATE) == 0x37 end, 900, {
    H.call(function() pinCyan(); H.setPad({ "a" }) end),
    H.waitFrames(2),
    H.call(function() H.setPad({}) end),
    H.waitFrames(14),
  }, "swdtech window (menu state $37)"),
  H.call(function()
    snap("window-open")
    H.screenshot("bushido_window")
  end),
  -- (3) is the bar dead?  sample every frame for two seconds.
  H.repeatN(120, { H.call(function() pinCyan(); sampleBar() end), H.waitFrames(1) }),
  H.call(function()
    local parts = {}
    for v, n in pairs(barSeen) do
      parts[#parts + 1] = string.format("%02x x%d", v, n)
    end
    table.sort(parts)
    H.log("[probe] bar values over 120 frames in-window: " .. table.concat(parts, ", "))
  end),
  -- (2b) does R still move the boost INSIDE the window, and does the bar follow?
  H.pressButtons({ "r" }, 6), H.waitFrames(20),
  H.call(function() snap("in-window-R") end),
  H.pressButtons({ "r" }, 6), H.waitFrames(20),
  H.call(function() snap("in-window-RR") end),
  H.pressButtons({ "r" }, 6), H.waitFrames(20),
  H.call(function() snap("in-window-RRR") end),
  H.pressButtons({ "r" }, 6), H.waitFrames(20),
  H.call(function() snap("in-window-R4") end),
  H.call(function() H.screenshot("bushido_boosted") end),
  -- (4) latch it and watch what executes
  H.driveUntil(function() return H.readByte(MSTATE) ~= 0x37 end, 900, {
    H.call(function() H.setPad({ "a" }) end),
    H.waitFrames(2),
    H.call(function() H.setPad({}) end),
    H.waitFrames(14),
  }, "the window closes on a latch"),
  H.call(function() snap("latched") end),
  H.driveUntil(function() return #spells > 0 end, 6000, {
    H.call(function() if H.readByte(MENU) ~= 0 then H.setPad({ "a" }) end end),
    H.waitFrames(4),
    H.call(function() H.setPad({}) end),
    H.waitFrames(26),
  }, "an attack reaches $3410"),
  H.waitFrames(180),
  H.call(function()
    local ids = {}
    for _, v in ipairs(spells) do ids[#ids + 1] = string.format("%02x", v) end
    H.log("[probe] $3410 attack ids: " .. table.concat(ids, " "))
    snap("resolved")
    H.log("[probe] trace:")
    for _, t in ipairs(trace) do H.log("[probe]   " .. t) end
    H.screenshot("bushido_resolved")
  end),
})
