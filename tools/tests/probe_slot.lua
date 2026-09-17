-- @manual
-- probe_slot.lua -- map SETZER's Slot window (#188): OpenSlotWindow
-- (UpdateMenuState_06) and the reel state $08 (UpdateMenuState_08,
-- btlgfx_main.asm).  In $08 the first A starts the spin (w7e7b92, the rig
-- draw), each later A stops the next reel once it is ready
-- (w7e7b8f/90/91), the reel-3 stop queues the result and sets $7BCB, and B
-- backs out only before the first A (@7fec: b92|b93|b94 all clear ->
-- UpdateMenuState_07).  This measures every $7BC2 write on the way in, out
-- and through a spin on a real fight.
--
--   OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/terra-returned-v1 \
--     tools/tests/run.sh tools/tests/probe_slot.lua
--
-- Cold-Continues terra-returned-v1 (LOCKE/EDGAR/SABIN/SETZER at the grounded
-- Blackjack, battle_slotsboot's boot), walks the plain to a world
-- encounter, consumes other windows with a real Defend, and on SETZER's
-- window: Slot in (A), out (B), in again, then A pulses through a spin.
--
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local MENU, MSTATE, ACTOR, CMDROW, CMDTBL = 0x7BCA, 0x7BC2, 0x62CA, 0x890F, 0x202E
local ST_CMD, ST_SLOT = 0x05, 0x08
local CMD_SLOT, WHO = 0x0F, 0x09
local STOP = { 0x7B8F, 0x7B90, 0x7B91 }
local PRESS = { 0x7B92, 0x7B93, 0x7B94 }

local function map() return H.mapId() & 0x1ff end
local slotOf = {}

-- every write to $7BC2 that changes it, while `tracing`
local tracing, lastSt, trail, label = false, nil, {}, "-"
local function arm()
  emu.addMemoryCallback(function(_, v)
    if not tracing or v == lastSt then return end
    lastSt = v
    trail[#trail + 1] = string.format("$%02X", v)
    H.log(string.format("[slot] f%d %s: $7BC2 -> $%02X (menu=%02X actor=%d)",
      H.frame, label, v, H.readByte(MENU), H.readByte(ACTOR) & 3))
  end, emu.callbackType.write, 0x7E7BC2, 0x7E7BC2)
end
local function say(what)
  return H.call(function()
    H.log(string.format("[slot] after %s: st=$%02X trail: %s", what,
      H.readByte(MSTATE), table.concat(trail, " ")))
    trail = {}
  end)
end
local function press(b, hold, total, what)
  local n = 0
  return H.driveUntil(function() return n >= total end, total + 10, {
    H.call(function()
      if n == 0 then label = what end
      n = n + 1
      H.setPad(n <= hold and { [b] = true } or {})
    end),
  }, what)
end
local function cmdRow(actor, cmd)
  for r = 0, 3 do
    if H.readByte(CMDTBL + actor * 12 + r * 3) == cmd then return r end
  end
  return nil
end

-- wait for WHO's own window at $05, consuming other windows with Defend
local function menuFor(what)
  local ph = 0
  return H.driveUntil(function()
    return H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == slotOf[WHO]
       and H.readByte(MSTATE) == ST_CMD
  end, 30000, {
    H.call(function()
      ph = ph + 1
      if H.readByte(MENU) == 0 then
        H.setPad(ph % 8 < 4 and { a = true } or {})
      elseif H.readByte(ACTOR) ~= slotOf[WHO] then
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

local function cursorTo(cmd, what)
  local ph = 0
  return H.driveUntil(function()
    local a = H.readByte(ACTOR) & 3
    return (H.readByte(CMDROW + a) & 3) == cmdRow(a, cmd)
  end, 600, {
    H.call(function()
      ph = (ph + 1) % 12
      local a = H.readByte(ACTOR) & 3
      local cur, want = H.readByte(CMDROW + a) & 3, cmdRow(a, cmd)
      assert(want, what .. ": row present")
      H.setPad(ph < 4 and { [cur < want and "down" or "up"] = true } or {})
    end),
  }, what)
end

local function reels()
  return string.format("press %d%d%d ready %02X/%02X/%02X", H.readByte(PRESS[1]),
    H.readByte(PRESS[2]), H.readByte(PRESS[3]), H.readByte(STOP[1]),
    H.readByte(STOP[2]), H.readByte(STOP[3]))
end

H.run({ maxFrames = 120000 }, {
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
  H.call(function() H.assertEntryContract("terra-returned-v1"); arm() end),
  (function()
    local ph2 = 0
    return H.driveUntil(function()
      return (H.readByte(0x11FA) & 3) == 0 and H.readByte(0x11F3) == 0
         and H.worldHasControl() and H.worldAligned()
    end, 8000, {
      H.call(function()
        ph2 = ph2 + 1
        H.setPad((ph2 % 45) < 6 and { b = true } or {})
      end),
    }, "disembark the grounded Blackjack")
  end)(),
  H.release(),
  H.waitFrames(30),
  (function()
    local ph = 0
    local pattern = { "down", "down", "right", "right", "down", "down", "left", "left" }
    return H.driveUntil(function() return H.battleLoadStarted() end, 40000, {
      H.call(function()
        ph = ph + 1
        H.setPad({ [pattern[(math.floor(ph / 20) % #pattern) + 1]] = true })
      end),
    }, "a real world encounter fires")
  end)(),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle armed", 30),
  H.call(function()
    for s = 0, 3 do
      local id = H.readByte(0x3ED8 + s * 2)
      if id ~= 0xFF then slotOf[id] = s end
    end
    assert(slotOf[WHO], "SETZER present")
    tracing, label = true, "battle start"
  end),
  menuFor("setzer's command window"),
  say("first SETZER window"),
  H.waitFrames(20),
  cursorTo(CMD_SLOT, "command cursor on Slot"),
  H.waitFrames(20),
  say("cursor walk"),
  press("a", 4, 90, "A on the Slot row"),
  say("A on Slot"),
  H.call(function()
    H.log("[slot] " .. reels())
    H.assertEq(H.readByte(MSTATE), ST_SLOT, "A on Slot lands in the reel state ($08)")
    H.screenshot("slot_probe_open")
  end),
  press("b", 4, 120, "B in the Slot window (before the spin)"),
  say("B before the spin"),
  H.call(function()
    H.assertEq(H.readByte(MSTATE), ST_CMD, "B before the first A closes Slot to command select")
  end),
  press("a", 4, 90, "A on Slot (second time)"),
  say("A on Slot (second time)"),
  press("a", 4, 40, "A (start the spin)"),
  say("A start"),
  H.call(function() H.log("[slot] " .. reels()) end),
  press("b", 4, 60, "B during the spin"),
  say("B during the spin"),
  H.call(function()
    H.log("[slot] " .. reels())
    H.assertEq(H.readByte(MSTATE), ST_SLOT, "B after the first A does not close Slot")
  end),
  -- A pulses (4 on, 11 off) until the menu closes or leaves $08
  (function()
    local n = 0
    return H.driveUntil(function()
      return H.readByte(MSTATE) ~= ST_SLOT and n > 20
    end, 3000, {
      H.call(function()
        if n == 0 then label = "A pulses through the spin" end
        n = n + 1
        H.setPad((n % 15) < 4 and { a = true } or {})
      end),
    }, "the spin resolves")
  end)(),
  H.call(function() H.setPad({}); H.log("[slot] " .. reels()) end),
  H.waitFrames(120),
  say("spin through commit"),
  H.call(function() H.screenshot("slot_probe_committed") end),
  H.call(function() label = "until SETZER's next window" end),
  menuFor("setzer's second command window"),
  say("second SETZER window"),
  H.call(function() tracing = false; H.setPad({}) end),
})
