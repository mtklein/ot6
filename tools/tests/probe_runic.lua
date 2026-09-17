-- @manual
-- probe_runic.lua -- map CELES's Runic command (#188).  Runic has no list
-- window: OpenCmdMenuTbl[$0B] is _c17795 (target select, btlgfx_main.asm),
-- and Runic's command-row targeting byte makes it a self-target, so
-- key_target_2 goes straight to the roulette/self branch.  The generators
-- drive it blind (gen_narshe_battle:141 and gen_kefka_won:67 push
-- down,a,a; gen_tunnelarmr:487 down,a), so this measures what those
-- presses walk through: every $7BC2 write from A on the Runic row, B out
-- of whatever opens, and A through to the commit.
--
-- Boots zozo_arrival (LOCKE/EDGAR/SABIN/CELES in Zozo, map 221), paces a
-- lane to a natural encounter, consumes other windows with a real Defend,
-- and on CELES's window: A on Runic, B, A on Runic, A.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/zozo_arrival.mss.lua"

local MENU, MSTATE, ACTOR, CMDROW, CMDTBL = 0x7BCA, 0x7BC2, 0x62CA, 0x890F, 0x202E
local ST_CMD = 0x05
local CMD_RUNIC, WHO = 0x0B, 0x06

local function map() return H.mapId() & 0x1ff end
local slotOf = {}

-- every write to $7BC2 that changes it, while `tracing`
local tracing, lastSt, trail, label = false, nil, {}, "-"
local function arm()
  emu.addMemoryCallback(function(_, v)
    if not tracing or v == lastSt then return end
    lastSt = v
    trail[#trail + 1] = string.format("$%02X", v)
    H.log(string.format("[runic] f%d %s: $7BC2 -> $%02X (menu=%02X actor=%d)",
      H.frame, label, v, H.readByte(MENU), H.readByte(ACTOR) & 3))
  end, emu.callbackType.write, 0x7E7BC2, 0x7E7BC2)
end
local function say(what)
  return H.call(function()
    H.log(string.format("[runic] after %s: st=$%02X trail: %s", what,
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

local function tgt()
  return string.format("chars=%02X mons=%02X all=%02X runic=%02X",
    H.readByte(0x7B7D), H.readByte(0x7B7E), H.readByte(0x7B7F),
    H.readByte(0x3E4C + (H.readByte(ACTOR) & 3) * 2))
end

H.run({ maxFrames = 60000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000,
    "field control"),
  H.call(function()
    H.log(string.format("[runic] map %d at (%d,%d)", map(), H.fieldX(), H.fieldY()))
    arm()
  end),
  (function()
    local lane = nil
    local m0 = nil
    local BACK = { left = "right", right = "left", up = "down", down = "up" }
    return H.driveUntil(function() return H.battleLoadStarted() end, 20000, {
      H.call(function()
        if not (H.hasControl() and H.tileAligned()) then H.setPad({}) return end
        m0 = m0 or map()
        if map() ~= m0 then error("paced off map " .. m0 .. " (now " .. map() .. ")", 0) end
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
    }, "an encounter fires")
  end)(),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle armed", 5),
  H.call(function()
    for s = 0, 3 do
      local id = H.readByte(0x3ED8 + s * 2)
      if id ~= 0xFF then slotOf[id] = s end
    end
    assert(slotOf[WHO], "CELES present")
    tracing, label = true, "battle start"
  end),
  menuFor("celes's command window"),
  say("first CELES window"),
  H.waitFrames(20),
  cursorTo(CMD_RUNIC, "command cursor on Runic"),
  H.waitFrames(20),
  say("cursor walk"),
  H.call(function()
    local a = H.readByte(ACTOR) & 3
    local r = nil
    for i = 0, 3 do if H.readByte(CMDTBL + a * 12 + i * 3) == CMD_RUNIC then r = i end end
    H.log(string.format("[runic] Runic row %d bytes %02X %02X %02X", r,
      H.readByte(CMDTBL + a * 12 + r * 3), H.readByte(CMDTBL + a * 12 + r * 3 + 1),
      H.readByte(CMDTBL + a * 12 + r * 3 + 2)))
  end),
  press("a", 4, 90, "A on the Runic row"),
  say("A on Runic"),
  H.call(function()
    H.log("[runic] " .. tgt())
    H.screenshot("runic_probe_open")
  end),
  press("b", 4, 90, "B after A on Runic"),
  say("B after A on Runic"),
  H.call(function() H.log("[runic] " .. tgt()) end),
  H.cond(function() return H.readByte(MSTATE) == ST_CMD end, {
    press("a", 4, 90, "A on Runic (second time)"),
    say("A on Runic (second time)"),
  }, {}),
  press("left", 4, 40, "LEFT in Runic target select"),
  say("LEFT in Runic target select"),
  H.call(function() H.log("[runic] " .. tgt()) end),
  press("a", 4, 240, "A (commit)"),
  say("A commit"),
  H.call(function() H.log("[runic] " .. tgt()); H.screenshot("runic_probe_committed") end),
  H.call(function() label = "until CELES's next window" end),
  menuFor("celes's second command window"),
  say("second CELES window"),
  H.call(function() tracing = false; H.setPad({}) end),
})
