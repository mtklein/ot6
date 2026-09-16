-- @manual
-- probe_rowdef.lua -- map the command window's Row ($24) and Def. ($27)
-- side windows (#188): which press opens each from command select ($05),
-- every $7BC2 transition on the way in and out, which presses close them,
-- and which do nothing there.  The v0.17 baseline's train_done attempt 1
-- sat in $24 for 304 frames with LEFT held (the no-effect trip at f4832):
-- LEFT is what OPENS Row from the command window (btlgfx_main.asm
-- UpdateMenuState_05 @7c07: `and #$0f / cmp #$02` -> UpdateMenuState_22),
-- and inside $24 LEFT is not read at all (UpdateMenuState_24 @7e81: A
-- commits, B or RIGHT closes).  Boots first_battle (the menu is up at
-- f+1), traces $7BC2 every frame, and records each press's effect.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/first_battle.mss.lua"

local MENU, MSTATE, ACTOR, CMDROW = 0x7BCA, 0x7BC2, 0x62CA, 0x890F
local QUEUE = 0x7BC3                    -- the queued states behind $7BC2
local ST_CMD, ST_ROW, ST_DEF = 0x05, 0x24, 0x27

local lastSt, trail = nil, {}
local function trace(label)
  local st = H.readByte(MSTATE)
  if st ~= lastSt then
    local q = string.format("%02X.%02X.%02X", H.readByte(QUEUE),
      H.readByte(QUEUE + 1), H.readByte(QUEUE + 2))
    H.log(string.format("[rowdef] f%d %s: $7BC2 -> $%02X (queue %s menu=%02X "
      .. "actor=%d cursor=%d)", H.frame, label, st, q, H.readByte(MENU),
      H.readByte(ACTOR) & 3, H.readByte(CMDROW + (H.readByte(ACTOR) & 3)) & 3))
    trail[#trail + 1] = string.format("$%02X", st)
    lastSt = st
  end
end

-- hold `pad` for `hold` frames, then release, tracing every frame for
-- `total` frames; the log line at the end says where it ended up
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
    H.log(string.format("[rowdef] after %s: st=$%02X cursor=%d trail so far: %s",
      label, H.readByte(MSTATE),
      H.readByte(CMDROW + (H.readByte(ACTOR) & 3)) & 3, table.concat(trail, " ")))
  end)
end

H.run({ maxFrames = 6000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitUntil(function() return H.battleActive() end, 300, "battle active", 5),
  H.waitUntil(function()
    return H.readByte(MENU) ~= 0 and H.readByte(MSTATE) == ST_CMD
  end, 600, "command select ($05) up", 5),
  H.waitFrames(30),
  H.call(function()
    lastSt = nil
    trace("baseline")
    H.screenshot("rowdef_cmd")
  end),

  -- Row: LEFT opens it; LEFT held inside does nothing; B closes it
  press({ "left" }, 4, 60, "LEFT at $05"),
  say("LEFT at $05"),
  H.call(function()
    H.assertEq(H.readByte(MSTATE), ST_ROW, "LEFT at command select opens Row ($24)")
    H.screenshot("rowdef_row")
  end),
  press({ "left" }, 120, 150, "LEFT held 120 frames in $24"),
  say("LEFT held in $24"),
  H.call(function()
    H.assertEq(H.readByte(MSTATE), ST_ROW, "LEFT does nothing inside Row: still $24")
  end),
  press({ "b" }, 4, 60, "B in $24"),
  say("B in $24"),
  H.call(function()
    H.assertEq(H.readByte(MSTATE), ST_CMD, "B closes Row back to command select ($05)")
  end),

  -- Row again, closed by RIGHT this time (UpdateMenuState_24 @7eb4)
  press({ "left" }, 4, 60, "LEFT at $05 (second time)"),
  press({ "right" }, 4, 60, "RIGHT in $24"),
  say("RIGHT in $24"),
  H.call(function()
    H.assertEq(H.readByte(MSTATE), ST_CMD, "RIGHT closes Row back to command select ($05)")
  end),

  -- Def.: RIGHT opens it; RIGHT held inside does nothing; B closes it
  press({ "right" }, 4, 60, "RIGHT at $05"),
  say("RIGHT at $05"),
  H.call(function()
    H.assertEq(H.readByte(MSTATE), ST_DEF, "RIGHT at command select opens Def. ($27)")
    H.screenshot("rowdef_def")
  end),
  press({ "right" }, 120, 150, "RIGHT held 120 frames in $27"),
  say("RIGHT held in $27"),
  H.call(function()
    H.assertEq(H.readByte(MSTATE), ST_DEF, "RIGHT does nothing inside Def.: still $27")
  end),
  press({ "b" }, 4, 60, "B in $27"),
  say("B in $27"),
  H.call(function()
    H.assertEq(H.readByte(MSTATE), ST_CMD, "B closes Def. back to command select ($05)")
  end),

  -- Def. again, closed by LEFT this time (UpdateMenuState_27 @7e46)
  press({ "right" }, 4, 60, "RIGHT at $05 (second time)"),
  press({ "left" }, 4, 60, "LEFT in $27"),
  say("LEFT in $27"),
  H.call(function()
    H.assertEq(H.readByte(MSTATE), ST_CMD, "LEFT closes Def. back to command select ($05)")
    H.log("[rowdef] full trail: " .. table.concat(trail, " "))
    H.setPad({})
  end),
})
