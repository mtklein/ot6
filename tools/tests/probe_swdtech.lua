-- @manual
-- probe_swdtech.lua -- map CYAN's SwdTech (Bushido) window (#188).  The
-- coverage table listed vanilla's $37 select / $36 close as unhandled, but
-- OT6 replaced the numeral gauge: OpenCmdMenuTbl[$07] is _c1_bushido_open
-- (btlgfx_main.asm), which calls Ot6BushidoListOpen (bushido mode,
-- w7e6168=2) and jumps into OpenToolsWindow, and UpdateMenuState_35 (the
-- only writer of the $37 entry) is dead.  The confirm is
-- Ot6BushidoConfirm (ot6_cmdmenu.asm): row i banks boost i+1, is refused
-- with a buzz when the bank is short, and queues the tech and closes the
-- menu with no target select.  This measures all of it on a real fight.
--
-- Boots camp_escaped (SABIN/CYAN/SHADOW on the world map by the Imperial
-- camp), paces left/right to a natural encounter, consumes other windows
-- with a real Defend, and on CYAN's window: SwdTech in (A), out (B), in
-- again, A on a row past the bank (refused), A on row 0 (commit).  Every
-- $7BC2 write is recorded by a write callback.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/camp_escaped.mss.lua"

local MENU, MSTATE, ACTOR, CMDROW, CMDTBL = 0x7BCA, 0x7BC2, 0x62CA, 0x890F, 0x202E
local ST_CMD, ST_TOOLS = 0x05, 0x30
local CMD_SWDTECH, WHO = 0x07, 0x02
local ITEMLIST, BLCOL, BLROW, BP = 0x4005, 0x8963, 0x8967, 0x3E9C

local function map() return H.mapId() & 0x1ff end
local slotOf = {}

-- every write to $7BC2 that changes it, while `tracing`
local tracing, lastSt, trail, label = false, nil, {}, "-"
local function arm()
  emu.addMemoryCallback(function(_, v)
    if not tracing or v == lastSt then return end
    lastSt = v
    trail[#trail + 1] = string.format("$%02X", v)
    H.log(string.format("[swdtech] f%d %s: $7BC2 -> $%02X (menu=%02X actor=%d)",
      H.frame, label, v, H.readByte(MENU), H.readByte(ACTOR) & 3))
  end, emu.callbackType.write, 0x7E7BC2, 0x7E7BC2)
end
local function say(what)
  return H.call(function()
    H.log(string.format("[swdtech] after %s: st=$%02X trail: %s", what,
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

H.run({ maxFrames = 90000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(30),
  H.call(function() arm() end),
  H.driveUntil(function() return H.battleLoadStarted() end, 25000, {
    H.call(function()
      if not H.worldMode() or not H.worldHasControl() then H.setPad({}) return end
      H.setPad(((H.frame // 120) % 2 == 0) and { left = true } or { right = true })
    end),
  }, "a world encounter fires"),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle armed", 5),
  H.call(function()
    for s = 0, 3 do
      local id = H.readByte(0x3ED8 + s * 2)
      if id ~= 0xFF then slotOf[id] = s end
    end
    assert(slotOf[WHO], "CYAN present")
    tracing, label = true, "battle start"
  end),
  menuFor("cyan's command window"),
  say("first CYAN window"),
  H.waitFrames(20),
  cursorTo(CMD_SWDTECH, "command cursor on SwdTech"),
  H.waitFrames(20),
  say("cursor walk"),
  press("a", 4, 90, "A on the SwdTech row"),
  say("A on SwdTech"),
  H.call(function()
    local a = H.readByte(ACTOR) & 3
    local l = {}
    for i = 0, 7 do
      l[#l + 1] = string.format("%02X.%02X.%02X", H.readByte(ITEMLIST + i * 3),
        H.readByte(ITEMLIST + i * 3 + 1), H.readByte(ITEMLIST + i * 3 + 2))
    end
    H.log(string.format("[swdtech] wItemList: %s $6168=%02X bp=%d mp=%d",
      table.concat(l, " "), H.readByte(0x6168), H.readByte(BP + a * 2),
      H.readWord(0x3C08 + a * 2)))
    H.assertEq(H.readByte(MSTATE), ST_TOOLS, "A on SwdTech lands in the tools-shell list ($30)")
    H.screenshot("swdtech_probe_open")
  end),
  press("b", 4, 90, "B in the SwdTech list"),
  say("B in the SwdTech list"),
  H.call(function()
    H.assertEq(H.readByte(MSTATE), ST_CMD, "B closes the SwdTech list to command select")
  end),
  press("a", 4, 90, "A on SwdTech (second time)"),
  say("A on SwdTech (second time)"),
  press("down", 4, 30, "DOWN in the list (row 1)"),
  say("DOWN to row 1"),
  press("a", 4, 90, "A on row 1 (boost 2)"),
  say("A on row 1"),
  H.call(function()
    local a = H.readByte(ACTOR) & 3
    H.log(string.format("[swdtech] row 1 at bp=%d: st=$%02X row=%d", H.readByte(BP + a * 2),
      H.readByte(MSTATE), H.readByte(BLROW + a)))
  end),
  H.cond(function() return H.readByte(MSTATE) == ST_TOOLS end, {
    press("up", 4, 30, "UP in the list (row 0)"),
    press("a", 4, 240, "A on row 0 (commit)"),
    say("A on row 0"),
  }, {}),
  H.call(function() H.screenshot("swdtech_probe_committed") end),
  H.call(function() label = "until CYAN's next window" end),
  menuFor("cyan's second command window"),
  say("second CYAN window"),
  H.call(function() tracing = false; H.setPad({}) end),
})
