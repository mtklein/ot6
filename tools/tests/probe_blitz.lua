-- @manual
-- probe_blitz.lua -- map SABIN's Blitz window and the command window's
-- transitional states around it (#188).  OT6 retired vanilla's $3D pad-edge
-- state: OpenCmdMenuTbl[$0A] is _c1776b (btlgfx_main.asm), which calls
-- Ot6BlitzListOpen and jumps into OpenToolsWindow, so Blitz should ride the
-- Tools shell ($2E -> $01 -> $30) and its confirm queues with no target
-- select (@8809 "blitz mode? queue it").  Also traced here, because every
-- turn walks them: $04 (the command window opening, UpdateMenuState_04),
-- $0F/$10 (UpdateMenuState_05 sees $7BCB set and closes the command
-- window, CloseCmdWindow queues entry 5 = $01,$10), and the ally-target
-- status window $3F/$41/$40 (an ally-targeted item or cure goes $0A -> $3F
-- -> $01 -> $41 -> $38, and B back out of the target walks $40).
--
-- Boots vargas_won (TERRA/LOCKE/EDGAR/SABIN on Mt. Kolts, map 98), paces a
-- lane to a natural encounter, consumes other windows with a real Defend,
-- and on SABIN's window: Blitz in (A), out (B), in again and A on Pummel
-- (commit); on his next window: Item, A on the first item, A (ally target
-- select), B, B, then Defend.  Every $7BC2 write is recorded by a write
-- callback, so a one-frame state shows in the trail.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/vargas_won.mss.lua"

local MENU, MSTATE, ACTOR, CMDROW, CMDTBL = 0x7BCA, 0x7BC2, 0x62CA, 0x890F, 0x202E
local ST_CMD, ST_TOOLS, ST_ITEM, ST_TGT = 0x05, 0x30, 0x0A, 0x38
local CMD_BLITZ, CMD_ITEM, SABIN = 0x0A, 0x01, 0x05
local ITEMLIST, BLCOL, BLROW = 0x4005, 0x8963, 0x8967
local PUMMEL = 0x5D

local function map() return H.mapId() & 0x1ff end
local slotOf = {}

-- every write to $7BC2 that changes it, while `tracing`
local tracing, lastSt, trail, label = false, nil, {}, "-"
local function arm()
  emu.addMemoryCallback(function(_, v)
    if not tracing or v == lastSt then return end
    lastSt = v
    trail[#trail + 1] = string.format("$%02X", v)
    H.log(string.format("[blitz] f%d %s: $7BC2 -> $%02X (menu=%02X actor=%d)",
      H.frame, label, v, H.readByte(MENU), H.readByte(ACTOR) & 3))
  end, emu.callbackType.write, 0x7E7BC2, 0x7E7BC2)
end
local function say(what)
  return H.call(function()
    H.log(string.format("[blitz] after %s: st=$%02X trail: %s", what,
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

-- wait for SABIN's own window at $05, consuming other windows with Defend
local function menuFor(what)
  local ph = 0
  return H.driveUntil(function()
    return H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == slotOf[SABIN]
       and H.readByte(MSTATE) == ST_CMD
  end, 30000, {
    H.call(function()
      ph = ph + 1
      if H.readByte(MENU) == 0 then
        H.setPad(ph % 8 < 4 and { a = true } or {})
      elseif H.readByte(ACTOR) ~= slotOf[SABIN] then
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
  H.waitFrames(20),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000,
    "field control on Mt. Kolts"),
  H.call(function() H.assertEq(map(), 98, "vargas_won on map 98"); arm() end),
  (function()
    local lane = nil
    local BACK = { left = "right", right = "left", up = "down", down = "up" }
    return H.driveUntil(function() return H.battleLoadStarted() end, 12600, {
      H.call(function()
        if not (H.hasControl() and H.tileAligned()) then H.setPad({}) return end
        local x, y = H.fieldX(), H.fieldY()
        if lane == nil then
          for _, d in ipairs({ "right", "left", "up", "down" }) do
            if H.canStep(x, y, d) then lane = { ax = x, ay = y, out = d, back = BACK[d] } break end
          end
          if lane == nil then H.setPad({}) return end
        end
        H.setPad({ [(x == lane.ax and y == lane.ay) and lane.out or lane.back] = true })
      end),
      H.waitFrames(1),
    }, "a Kolts encounter fires")
  end)(),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle armed", 5),
  H.call(function()
    for s = 0, 3 do
      local id = H.readByte(0x3ED8 + s * 2)
      if id ~= 0xFF then slotOf[id] = s end
    end
    assert(slotOf[SABIN], "SABIN present")
    -- the first window's open, from the battle start
    tracing, label = true, "battle start (first window open)"
  end),
  menuFor("sabin's command window"),
  say("first SABIN window"),
  H.waitFrames(20),
  cursorTo(CMD_BLITZ, "command cursor on Blitz"),
  H.waitFrames(20),
  say("cursor walk"),

  press("a", 4, 90, "A on the Blitz row"),
  say("A on Blitz"),
  H.call(function()
    local l = {}
    for i = 0, 7 do l[#l + 1] = string.format("%02X", H.readByte(ITEMLIST + i * 3)) end
    H.log("[blitz] wItemList ids: " .. table.concat(l, " ")
      .. string.format(" $6168=%02X", H.readByte(0x6168)))
    H.assertEq(H.readByte(MSTATE), ST_TOOLS, "A on Blitz lands in the tools-shell list ($30)")
    H.screenshot("blitz_probe_open")
  end),
  press("b", 4, 90, "B in the Blitz list"),
  say("B in the Blitz list"),
  H.call(function()
    H.assertEq(H.readByte(MSTATE), ST_CMD, "B closes the Blitz list to command select")
  end),
  press("a", 4, 90, "A on Blitz (second time)"),
  say("A on Blitz (second time)"),
  -- walk the list cursor to Pummel and commit
  (function()
    local ph = 0
    return H.driveUntil(function()
      local a = H.readByte(ACTOR) & 3
      local want
      for i = 0, 7 do if H.readByte(ITEMLIST + i * 3) == PUMMEL then want = i break end end
      assert(want, "Pummel is in the Blitz list")
      return H.readByte(BLCOL + a) == want % 2 and H.readByte(BLROW + a) == want // 2
    end, 600, {
      H.call(function()
        ph = (ph + 1) % 12
        local a = H.readByte(ACTOR) & 3
        local want
        for i = 0, 7 do if H.readByte(ITEMLIST + i * 3) == PUMMEL then want = i break end end
        local cc, cr = H.readByte(BLCOL + a), H.readByte(BLROW + a)
        local d = cc ~= want % 2 and (want % 2 > cc and "right" or "left")
                  or (want // 2 > cr and "down" or "up")
        H.setPad(ph < 4 and { [d] = true } or {})
      end),
    }, "list cursor on Pummel")
  end)(),
  say("list walk"),
  press("a", 4, 240, "A on Pummel (commit)"),
  say("A on Pummel"),
  H.call(function() H.screenshot("blitz_probe_committed") end),

  -- the next SABIN window: an ally-targeted item, into target select and out
  H.call(function() label = "between SABIN windows" end),
  menuFor("sabin's second command window"),
  say("second SABIN window"),
  H.waitFrames(20),
  cursorTo(CMD_ITEM, "command cursor on Item"),
  press("a", 4, 90, "A on the Item row"),
  say("A on Item"),
  H.call(function()
    H.assertEq(H.readByte(MSTATE), ST_ITEM, "A on Item opens item select ($0A)")
  end),
  -- walk the item cursor (scroll $8947 + row $894F) to the first Tonic or
  -- Potion in the battle bag ($2686, 5-byte rows), then A: an ally target
  (function()
    local ph = 0
    local function want()
      for i = 0, 251 do
        local id = H.readByte(0x2686 + i * 5)
        if (id == 0xE8 or id == 0xE9) and H.readByte(0x2686 + i * 5 + 3) > 0 then return i end
      end
      error("no Tonic or Potion in the battle bag", 0)
    end
    local function cur()
      local a = H.readByte(ACTOR) & 3
      return H.readByte(0x8947 + a) + H.readByte(0x894F + a)
    end
    return H.driveUntil(function() return cur() == want() end, 1200, {
      H.call(function()
        ph = (ph + 1) % 12
        H.setPad(ph < 4 and { [cur() < want() and "down" or "up"] = true } or {})
      end),
    }, "item cursor on a Tonic/Potion")
  end)(),
  say("item walk"),
  -- the first A picks the row up (set_item_one @8b23: w7e7b02 = 1, carry
  -- clear, no target yet); the second A on the same row opens the target
  press("a", 4, 60, "A on the Tonic/Potion row"),
  say("A on the Tonic/Potion row"),
  press("a", 4, 90, "second A on the Tonic/Potion row"),
  say("second A on the Tonic/Potion row"),
  H.call(function()
    H.assertEq(H.readByte(MSTATE), ST_TGT, "A on a curative opens ally target select ($38)")
  end),
  H.call(function() H.screenshot("blitz_probe_itemtarget") end),
  press("b", 4, 90, "B in target select"),
  say("B in target select"),
  press("b", 4, 90, "B in item select"),
  say("B in item select"),
  H.call(function()
    H.assertEq(H.readByte(MSTATE), ST_CMD, "B B lands back at command select")
  end),
  press("right", 4, 40, "RIGHT (Def.)"),
  press("a", 4, 240, "A on Def. (commit)"),
  say("Defend commit"),
  H.call(function() tracing = false; H.setPad({}) end),
})
