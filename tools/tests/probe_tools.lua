-- @manual
-- probe_tools.lua -- map EDGAR's Tools window family (#188): the open
-- state $2E (UpdateMenuState_2e / OpenToolsWindow builds wItemList, then
-- hands off through menu-state-data entry $0f = $01,$30), the select
-- state $30, and the close state $2F (CloseToolsWindow -> entry 0 =
-- $01,$05).  Only $30 was in the driver's KNOWN_ST; every Edgar fight
-- passes through the other two.  Boots kolts_cave (TERRA/LOCKE/EDGAR on
-- map 96), paces a lane until a random fires -- battle_toolslist's own
-- arm -- waits for EDGAR's window, walks the command cursor to his real
-- Tools row, A, and traces every $7BC2 transition: in (A), out (B),
-- and A on a tool row through to target select ($38) and back.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/kolts_cave.mss.lua"

local MENU, MSTATE, ACTOR, CMDROW, CMDTBL = 0x7BCA, 0x7BC2, 0x62CA, 0x890F, 0x202E
local QUEUE = 0x7BC3
local ST_CMD, ST_TOOLS_OPEN, ST_TOOLS, ST_TOOLS_CLOSE, ST_TGT =
  0x05, 0x2E, 0x30, 0x2F, 0x38
local CMD_TOOLS, EDGAR = 0x09, 0x04
local ITEMLIST = 0x4005

local slotOf = {}
local lastSt, trail = nil, {}
local function trace(label)
  local st = H.readByte(MSTATE)
  if st ~= lastSt then
    local a = H.readByte(ACTOR) & 3
    H.log(string.format("[tools] f%d %s: $7BC2 -> $%02X (queue %02X.%02X.%02X "
      .. "menu=%02X actor=%d cursor=%d)", H.frame, label, st,
      H.readByte(QUEUE), H.readByte(QUEUE + 1), H.readByte(QUEUE + 2),
      H.readByte(MENU), a, H.readByte(CMDROW + a) & 3))
    trail[#trail + 1] = string.format("$%02X", st)
    lastSt = st
  end
end

local function press(pad, hold, total, label)
  local n = 0
  local pads = {}
  for _, b in ipairs(pad) do pads[b] = true end
  return H.driveUntil(function() return n >= total end, total + 10, {
    H.call(function()
      n = n + 1
      H.setPad(n <= hold and pads or {})
      trace(label)
    end),
  }, label)
end

local function say(label)
  return H.call(function()
    H.log(string.format("[tools] after %s: st=$%02X trail so far: %s", label,
      H.readByte(MSTATE), table.concat(trail, " ")))
  end)
end

local function cmdRow(actor, cmd)
  for r = 0, 3 do
    if H.readByte(CMDTBL + actor * 12 + r * 3) == cmd then return r end
  end
  return nil
end

-- wait for EDGAR's own menu, consuming other characters' turns with a real
-- Defend (RIGHT opens Def., A commits it): battle_toolslist's menuFor
local function menuFor(charId, what)
  local ph = 0
  local function up()
    return H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == slotOf[charId]
  end
  return H.driveUntil(up, 20000, {
    H.call(function()
      ph = ph + 1
      if H.readByte(MENU) == 0 then
        H.setPad(ph % 8 < 4 and { a = true } or {})
      elseif H.readByte(ACTOR) ~= slotOf[charId] then
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

local function map() return H.mapId() & 0x1ff end

H.run({ maxFrames = 60000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000,
    "field control in cave 96"),
  H.call(function() H.assertEq(map(), 96, "kolts_cave on map 96") end),

  -- pace the auto-detected lane until a natural encounter fires
  (function()
    local battN, waited, lane = 0, 0, nil
    local BACK = { left = "right", right = "left", up = "down", down = "up" }
    return H.driveUntil(function()
      waited = waited + 1
      battN = H.battleLoadStarted() and battN + 1 or 0
      if battN >= 1 then H.setPad({}) return true end
      if map() ~= 96 then error("paced off map 96 (now " .. map() .. ")", 0) end
      return waited >= 8000
    end, 8600, {
      H.call(function()
        if not (H.hasControl() and H.tileAligned()) then H.setPad({}) return end
        local x, y = H.fieldX(), H.fieldY()
        if lane == nil then
          for _, d in ipairs({ "right", "left", "up", "down" }) do
            if H.canStep(x, y, d) then lane = { ax = x, ay = y, out = d, back = BACK[d] } break end
          end
        end
        H.setPad({ [(x == lane.ax and y == lane.ay) and lane.out or lane.back] = true })
      end),
      H.waitFrames(1),
    }, "a cave encounter fires")
  end)(),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle armed", 5),
  H.waitFrames(240),

  H.call(function()
    for s = 0, 3 do
      local id = H.readByte(0x3ED8 + s * 2)
      if id ~= 0xFF then slotOf[id] = s end
    end
    assert(slotOf[EDGAR], "EDGAR present (kolts party)")
  end),
  menuFor(EDGAR, "edgar's command window"),
  H.waitFrames(30),

  -- walk the command cursor to the real Tools row, then open it
  (function()
    local ph = 0
    return H.driveUntil(function()
      local a = H.readByte(ACTOR) & 3
      return (H.readByte(CMDROW + a) & 3) == cmdRow(a, CMD_TOOLS)
    end, 600, {
      H.call(function()
        ph = (ph + 1) % 12
        local a = H.readByte(ACTOR) & 3
        local cur, want = H.readByte(CMDROW + a) & 3, cmdRow(a, CMD_TOOLS)
        assert(want, "EDGAR has a Tools row")
        H.setPad(ph < 4 and { [cur < want and "down" or "up"] = true } or {})
      end),
    }, "command cursor on Tools")
  end)(),
  H.waitFrames(20),
  H.call(function()
    lastSt = nil
    trace("baseline (cursor on Tools)")
    H.log(string.format("[tools] wItemList: %02X %02X %02X %02X %02X %02X %02X %02X",
      H.readByte(ITEMLIST), H.readByte(ITEMLIST + 3), H.readByte(ITEMLIST + 6),
      H.readByte(ITEMLIST + 9), H.readByte(ITEMLIST + 12), H.readByte(ITEMLIST + 15),
      H.readByte(ITEMLIST + 18), H.readByte(ITEMLIST + 21)))
  end),

  -- in: A on the Tools row
  press({ "a" }, 4, 90, "A on Tools row"),
  say("A on Tools row"),
  H.call(function()
    H.assertEq(H.readByte(MSTATE), ST_TOOLS, "A on Tools lands in tools select ($30)")
    H.screenshot("tools_probe_open")
  end),
  -- out: B from the list
  press({ "b" }, 4, 90, "B in $30"),
  say("B in $30"),
  H.call(function()
    H.assertEq(H.readByte(MSTATE), ST_CMD, "B closes the tools list back to command select ($05)")
  end),
  -- in again, then A on the first tool row -> target select, and back out
  press({ "a" }, 4, 90, "A on Tools row (second time)"),
  press({ "a" }, 4, 90, "A on tool row 0"),
  say("A on tool row 0"),
  H.call(function()
    H.assertEq(H.readByte(MSTATE), ST_TGT, "A on a tool row opens target select ($38)")
    H.screenshot("tools_probe_target")
  end),
  press({ "b" }, 4, 90, "B in $38"),
  say("B in $38"),
  H.call(function()
    H.assertEq(H.readByte(MSTATE), ST_TOOLS, "B from target select returns to the tools list ($30)")
  end),
  press({ "b" }, 4, 90, "B in $30 (second time)"),
  say("B in $30 (second time)"),
  H.call(function()
    H.assertEq(H.readByte(MSTATE), ST_CMD, "B closes the tools list back to command select ($05)")
    H.log("[tools] full trail: " .. table.concat(trail, " "))
    H.setPad({})
  end),
})
