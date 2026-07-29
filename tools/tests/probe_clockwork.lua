-- probe_clockwork.lua -- issue #33 MEASUREMENT ONLY: frame timelines for
-- (a) when the boost pips visibly change vs the Ot6ActionEnd charge, and
-- (b) when a weakness reveal visibly appears vs the damage frame, and
-- whether it propagates to a same-species sibling.
--
-- battle_doorstep opening fight (Guard x2 -- same species), staged exactly
-- as battle_mpcost.lua's PROVEN drive: every slot an all-Bushido CYAN, the
-- boost banked by the swdtech submenu row (row r = boost r), guards
-- stopped + HP-pinned + shield-pinned so the one measured tech is the only
-- damage in the window.  Guards' class-weak mask is opened to $0f so the
-- class chip must fire and reveal.  No behavior asserted: the probe logs a
-- frame-stamped event stream.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_doorstep.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local KNOWN = 0x2020
local GUARD_HP = 0x3000
local ev = {}
local function E(msg) H.log(string.format("f%06d %s", H.frame, msg)) end

local actor, msPresent = nil, {}
local watching = false
local pinActor = true          -- until the submenu latch; then hands off
local spells = {}

local function inWindow() return H.readByte(MSTATE) == 0x30 end

local function pinField()
  H.writeWord(KNOWN, 4)                               -- ceiling 4: window {1..4}
  for s = 0, 3 do
    if H.readByte(0x3ED8 + s * 2) ~= 0xFF then
      H.writeByte(0x3ED8 + s * 2, 0x02)               -- CHAR::CYAN
      local st1 = 0x3EE4 + s * 2
      H.writeByte(st1, H.readByte(st1) & 0xF7)        -- clear magitek
      H.writeByte(0x202E + s * 12, 0x07)              -- Bushido, alone
      H.writeByte(0x2031 + s * 12, 0xFF)
      H.writeByte(0x2034 + s * 12, 0xFF)
      H.writeByte(0x2037 + s * 12, 0xFF)
      H.writeByte(0x3BA4 + s * 2, H.readByte(0x3BA4 + s * 2) | 0x02)
      H.writeByte(0x3BA5 + s * 2, H.readByte(0x3BA5 + s * 2) | 0x02)
      H.writeWord(0x3BF4 + s * 2, 999)                -- nobody dies
      H.writeWord(0x3C30 + s * 2, 99)                 -- real max MP
      H.writeWord(0x3C08 + s * 2, 50)                 -- MP 50: the tech's cost
                                                      -- is affordable (guests
                                                      -- carry 0 MP -> the
                                                      -- universal fizzle ate
                                                      -- every earlier run)
    end
  end
  if actor and pinActor then
    H.writeByte(0x3E9C + actor * 2, 5)                -- full bp bank
    H.writeByte(0x3E9D + actor * 2, 1)                -- pending boost 1
  end
  for _, m in ipairs(msPresent) do
    local e = 8 + m * 2
    H.writeByte(0x3BE8 + m * 2, 0)      -- no element weak (class path only)
    H.writeByte(0x3EA4 + m * 2, 0x0F)   -- weak to EVERY weapon class
    H.writeByte(0x3E88 + e, 0)          -- never broken
    H.writeByte(0x3EF8 + e, H.readByte(0x3EF8 + e) | 0x10)   -- stopped
    if H.readWord(0x3BFC + m * 2) ~= GUARD_HP then
      H.writeWord(0x3BFC + m * 2, GUARD_HP)
    end
    H.writeByte(0x3E40 + m * 2, 8)      -- shields pinned high: chip, no break
  end
end

-- per-frame sampled state (log transitions only)
local last = {}
local function sample()
  if not watching then return end
  pinField()
  -- pips: actor's menu-row live cell, both bands
  local reg = H.readByte(0x897f)
  local base = ((reg - (reg % 4)) * 256) * 2
  local row
  for r = 0, 3 do if H.readByte(0x64d6 + r) == actor then row = r end end
  if row then
    local lo = emu.readWord(base + (1 + row * 2) * 0x40 + 40, emu.memType.snesVideoRam)
    local hi = emu.readWord(base + (9 + row * 2) * 0x40 + 40, emu.memType.snesVideoRam)
    local k = string.format("pipvram %04x/%04x", lo, hi)
    if last.pip ~= k then last.pip = k; E(k) end
  end
  -- actor bookkeeping cells
  local k2 = string.format("bp=%d pend=%d cmdptr=%02x menu=%02x mstate=%02x",
    H.readByte(0x3E9C + actor * 2), H.readByte(0x3E9D + actor * 2),
    H.readByte(0x32CC + actor * 2), H.readByte(MENU), H.readByte(MSTATE))
  if last.book ~= k2 then last.book = k2; E(k2) end
  -- reveal state per monster: revealed-class RAM plus the hud shadow cells
  -- and their VRAM copy ('?' = $bf)
  for _, m in ipairs(msPresent) do
    local sh = {}
    for c = 0, 4 do sh[c + 1] = string.format("%04x",
      H.readWord(H.shadowLine(m) + 4 + c * 2)) end
    local anchor = H.readWord(H.shadowLine(m))
    local vr = ""
    if anchor ~= 0 then
      local w = {}
      for c = 0, 4 do w[c + 1] = string.format("%04x",
        emu.readWord((anchor + c) * 2, emu.memType.snesVideoRam)) end
      vr = " vram=" .. table.concat(w, ",")
    end
    local k3 = string.format("m%d rcls=%02x shadow=%s%s", m,
      H.readByte(0x3EA5 + m * 2), table.concat(sh, ","), vr)
    if last["m" .. m] ~= k3 then last["m" .. m] = k3; E(k3) end
  end
  -- veils that shape what is visible
  local k4 = string.format("scriptbusy=%d hudveil=%d bg3size16=%d fontdirty=%d",
    H.readByte(0x57BF), H.readByte(0x57BE),
    (H.readByte(0x896F) & 0x40) ~= 0 and 1 or 0, H.readByte(0x57B9))
  if last.veil ~= k4 then last.veil = k4; E(k4) end
end

H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.enterEncounter(),
  H.waitFrames(240),
  H.call(function()
    for m = 0, 5 do
      if H.readByte(0x3AA8 + m * 2) % 2 == 1 then msPresent[#msPresent + 1] = m end
    end
    local sp = {}
    for _, m in ipairs(msPresent) do sp[#sp + 1] = string.format("%04x",
      H.readWord(0x57C0 + m * 2)) end
    H.log("monsters(species) = " .. table.concat(sp, " "))
    pinField()
    emu.addMemoryCallback(function(_, v) spells[#spells + 1] = v end,
      emu.callbackType.write, 0x7E3410, 0x7E3410)
  end),
  H.driveUntil(function() return H.readByte(MENU) ~= 0 end, 3000, {
    H.call(pinField), H.waitFrames(1),
  }, "a battle menu opens"),
  H.call(function()
    actor = H.readByte(ACTOR)
    H.log("actor slot " .. actor .. " (installed CYAN, bushido window {1..4})")
    pinField()
    -- write watches: the mechanical events
    emu.addMemoryCallback(function(a, v)
      E(string.format("WRITE bp[%04x]=%d", a & 0xFFFF, v))
    end, emu.callbackType.write, 0x7E3E9C + actor * 2, 0x7E3E9C + actor * 2)
    emu.addMemoryCallback(function(a, v)
      E(string.format("WRITE pend[%04x]=%d", a & 0xFFFF, v))
    end, emu.callbackType.write, 0x7E3E9D + actor * 2, 0x7E3E9D + actor * 2)
    emu.addMemoryCallback(function(a, v)
      E(string.format("WRITE mrcls[%04x]=%02x", a & 0xFFFF, v))
    end, emu.callbackType.write, 0x7E3EA9, 0x7E3EAB)
    emu.addMemoryCallback(function(a, v)
      E(string.format("WRITE mhp[%04x]=%02x", a & 0xFFFF, v))
    end, emu.callbackType.write, 0x7E3BFC, 0x7E3C07)
    emu.addMemoryCallback(function(a, v)
      E(string.format("WRITE numeralctr=%02x", v))
    end, emu.callbackType.write, 0x7E632E, 0x7E632E)
    -- exec attributions.  literal refs for compose.py's collector:
    -- H.sym("Ot6ActionEnd") H.sym("Ot6HitJoin") H.sym("Ot6ClassChip")
    -- H.sym("Ot6Chip") H.sym("GfxCmd_0b")
    local function execAt(name, fn)
      local addr = H.sym(name)
      emu.addMemoryCallback(fn, emu.callbackType.exec, addr, addr)
    end
    execAt("Ot6ActionEnd", function() E("EXEC Ot6ActionEnd") end)
    execAt("Ot6HitJoin", function()
      E(string.format("EXEC Ot6HitJoin cmd=%02x atk=%02x tmask=%02x/%02x atkcls=%02x",
        H.readByte(0xB5), H.readByte(0x3A7D), H.readByte(0xB8), H.readByte(0xB9),
        H.readByte(0x57B8)))
    end)
    execAt("Ot6ClassChip", function() E("EXEC Ot6ClassChip") end)
    execAt("GfxCmd_0b", function() E("EXEC GfxCmd_0b (damage numeral)") end)
    watching = true
    emu.addEventCallback(function() sample() end, emu.eventType.startFrame)
    E("setup done; bp=5 pend=1 (pinned until latch)")
  end),
  -- open the swdtech submenu, cursor to row 1 (= boost 1), confirm, and let
  -- it run to execution with the actor's cells UNPINNED from the latch on
  H.driveUntil(inWindow, 1500, {
    H.call(function() pinField(); H.setPad({ "a" }) end),
    H.waitFrames(2),
    H.call(function() H.setPad({}) end),
    H.waitFrames(14),
  }, "swdtech submenu opens (tools shell $30)"),
  H.call(function()
    pinField()
    H.writeByte(0x895F + actor, 0)          -- scroll
    H.writeByte(0x8963 + actor, 0)          -- column 0
    H.writeByte(0x8967 + actor, 2)          -- row 2 = boost 2
    E("submenu open; cursor at row 2")
  end),
  H.waitFrames(2),
  H.driveUntil(function() return not inWindow() end, 900, {
    H.call(function() pinField(); H.setPad({ "a" }) end),
    H.waitFrames(2),
    H.call(function() H.setPad({}) end),
    H.waitFrames(14),
  }, "submenu closes on a latch"),
  H.call(function() pinActor = false; E("latched; actor cells unpinned") end),
  -- no more input: another character's OPEN LIST pauses execution (wait
  -- mode), so the un-driven others just sit at their command menus while
  -- the latched tech runs to resolution
  H.driveUntil(function()
    return H.readByte(0x3E9C + actor * 2) ~= 5
  end, 12000, {
    H.call(function() pinField() end),
    H.waitFrames(2),
  }, "the boosted tech resolves (bp charged)"),
  H.call(function() E("charge observed (bp changed)") end),
  H.waitFrames(400),
  H.call(function()
    watching = false
    H.log("---- clockwork timeline ----")
    for _, line in ipairs(ev) do H.log(line) end
    H.log("---- end timeline ----")
    H.screenshot("clockwork_after")
  end),
  H.logStep(function() return "probe_clockwork complete" end),
})
