-- @suite savestate=figaro_cleared
-- battle_crosslist.lua -- Tools shows Cure 2.

-- What is asserted:
--   1. the cycle ran.  OT6_RESTAGE saw $80 and $7ba5 went mid-cycle
--      ($8x) during the R->B window, so the test cannot pass by boost or the
--      restage gate being disabled outright.
--   2. the strand is repaired.  After leaving browse mid-cycle, $7ba5 reads 0.
--   3. the tools window contains only tools.  Edgar's window renders his real
--      tools' names and no magic-list name survives anywhere in the BG1
--      text region.
--   4. the list data is sound.  wItemList holds exactly the tool
--      ids his real bag carries.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/figaro_cleared.mss.lua"

local MENU, ACTOR, MSTATE, CMDROW = 0x7BCA, 0x62CA, 0x7BC2, 0x890F
local ST_CMD, ST_SPELL, ST_TOOLS, ST_TRANS = 0x05, 0x0E, 0x30, 0x01
local CMD_MAGIC, CMD_TOOLS = 0x02, 0x09
local STAGE = 0x7BA5

local NAMES = {
  [0xA3] = "NoiseBlaster", [0xAA] = "AutoCrossbow",
  -- "Bio Blaster", "Chain Saw", "Air Anchor" carry spaces the contiguous
  -- glyph match below cannot span; ids still assert via wItemList.
}

local function up(c)  return 0x80 + (c:byte() - ("A"):byte()) end
local function lo(c)  return 0x9a + (c:byte() - ("a"):byte()) end
local function glyphs(s)
  local t = {}
  for i = 1, #s do
    local c = s:sub(i, i)
    t[i] = (c >= "A" and c <= "Z") and up(c) or lo(c)
  end
  return t
end

local function findName(seq)
  local vr = emu.memType.snesVideoRam
  for w = 0x6000, 0x7FF0 do
    local hit = true
    for i = 1, #seq do
      if (emu.readWord((w + i - 1) * 2, vr) & 0xFF) ~= seq[i] then hit = false break end
    end
    if hit then return w end
  end
  return nil
end

local function cmdRowOf(slot, cmd)
  for r = 0, 3 do
    if H.readByte(0x202E + slot*12 + r*3) == cmd then return r end
  end
  return nil
end

-- the real tool ids in the battle bag ($2686, 5-byte entries), read not
-- written: the set wItemList must reproduce
local function bagTools()
  local t = {}
  for i = 0, 251 do
    local id = H.readByte(0x2686 + i*5)
    if id >= 0xA3 and id <= 0xAA and H.readByte(0x2686 + i*5 + 3) > 0 then
      t[id] = true
    end
  end
  return t
end

local terra, edgar
local sawFresh, sawMidCycle = false, false

-- steer the menu toward `who`'s command window (everyone else defers with
-- X), then run `phase` there; 4-on/4-off command-window cadence.
local mf = 0
local function windowOf(who, onCmd)
  if H.readByte(MENU) == 0 then
    return (H.frame % 8 < 4) and { a = true } or {}
  end
  mf = mf + 1
  if (mf - 1) % 8 >= 4 then return {} end
  local act = H.readByte(ACTOR) & 3
  local st = H.readByte(MSTATE)
  if st == ST_TRANS then return {} end
  local btn
  if act ~= who then
    btn = (st == ST_CMD) and "x" or "b"
  else
    btn = onCmd(st)
  end
  return btn and { [btn] = true } or {}
end

H.run({ maxFrames = 60000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(30),
  H.hold({ "b" }),
  H.driveUntil(function() return H.readByte(0x11fa) & 3 == 0 end, 900, {
    H.waitFrames(1),
  }, "chocobo dismount"),
  H.release(),
  H.waitFrames(120),
  H.driveUntil(function() return H.battleLoadStarted() end, 20000, {
    H.call(function()
      if not H.worldMode() or not H.worldHasControl() then H.setPad({}); return end
      local phase = (H.frame // 120) % 2
      H.setPad(phase == 0 and { left = true } or { right = true })
    end),
  }, "desert encounter"),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  H.waitFrames(90),
  H.call(function()
    for slot = 0, 3 do
      local chid = H.readByte(0x3ED8 + slot*2)
      if chid == 0x00 then terra = slot end
      if chid == 0x04 then edgar = slot end
    end
    H.assertEq(terra ~= nil, true, "TERRA is really in this party")
    H.assertEq(edgar ~= nil, true, "EDGAR is really in this party")
    H.assertEq(cmdRowOf(terra, CMD_MAGIC) ~= nil, true,
      "her Magic command is real")
    H.assertEq(cmdRowOf(edgar, CMD_TOOLS) ~= nil, true,
      "his Tools command is real")
    local tools, n = bagTools(), 0
    for _ in pairs(tools) do n = n + 1 end
    H.assertEq(n >= 2, true, "the bag really carries the bought tools")
    -- positive controls: the restage request fires and the cycle starts
    emu.addMemoryCallback(function(_, v)
      if v == 0x80 then sawFresh = true end
    end, emu.callbackType.write, 0x7e57d4, 0x7e57d4)
    emu.addMemoryCallback(function(_, v)
      if v >= 0x80 and v <= 0x83 then sawMidCycle = true end
    end, emu.callbackType.write, 0x7e7ba5, 0x7e7ba5)
  end),

  -- open Terra's real magic list (walk the cursor to her Magic row)
  H.driveUntil(function()
    return (H.readByte(ACTOR) & 3) == terra and H.readByte(MSTATE) == ST_SPELL
  end, 20000, {
    H.call(function()
      H.setPad(windowOf(terra, function(st)
        if st == ST_CMD then
          local want = cmdRowOf(terra, CMD_MAGIC)
          local cur = H.readByte(CMDROW + terra) & 3
          if cur == want then return "a" end
          return (cur < want) and "down" or "up"
        end
        return "b"
      end))
    end),
  }, "her real spell list open"),
  H.call(function() H.setPad({}) end),   -- drop any held press at the boundary
  H.waitFrames(20),
  H.call(function()
    H.assertEq(H.readByte(MSTATE), ST_SPELL,
      "still browsing her list when the R lands (no leaked confirm)")
    H.log(string.format("pre-R: pend=%d bp=%d stage=%02x",
      H.readByte(0x3e9d + terra*2), H.readByte(0x3e9c + terra*2),
      H.readByte(STAGE)))
  end),

  H.hold({ "r" }),
  H.driveUntil(function() return H.readByte(0x3e9d + terra*2) == 1 end, 120, {
    H.waitFrames(1),
  }, "the R edge commits (pending 1)"),
  H.hold({ "b" }), H.waitFrames(4), H.release(),
  H.waitFrames(14),
  H.call(function()
    H.assertEq(sawFresh, true, "R raised a fresh restage request ($80)")
    H.assertEq(sawMidCycle, true, "the restage cycle started ($7ba5 = $8x)")
    H.assertEq(H.readByte(MSTATE) ~= ST_SPELL, true, "B left magic browse")
    H.assertEq(H.readByte(STAGE), 0,
      "the abandoned restage hands the shared staging byte $7ba5 back closed")
  end),

  -- cross-character, the sighting's own shape: EDGAR opens his real Tools
  -- window next and it must be an uncorrupted window
  H.driveUntil(function()
    return (H.readByte(ACTOR) & 3) == edgar and H.readByte(MSTATE) == ST_TOOLS
  end, 20000, {
    H.call(function()
      H.setPad(windowOf(edgar, function(st)
        if st == ST_CMD then
          local want = cmdRowOf(edgar, CMD_TOOLS)
          local cur = H.readByte(CMDROW + edgar) & 3
          if cur == want then return "a" end
          return (cur < want) and "down" or "up"
        end
        return "b"
      end))
    end),
  }, "his real tools window open"),
  H.call(function() H.setPad({}) end),
  H.waitFrames(12),                             -- let every row finish drawing
  H.call(function()
    H.setPad({})
    H.screenshot("crosslist_tools_after")
    -- 4. the list data is sound: wItemList reproduces exactly the
    --    bag's real tool set, nothing else
    local want = bagTools()
    local seen = {}
    for i = 0, 7 do
      local id = H.readByte(0x4005 + i*3)
      if id ~= 0xFF then
        H.assertEq(want[id] == true, true,
          string.format("wItemList row %d ($%02x) is a tool the bag holds", i, id))
        seen[id] = true
      end
    end
    for id in pairs(want) do
      H.assertEq(seen[id] == true, true,
        string.format("the bag's tool $%02x reached wItemList", id))
    end
    -- 3a. his real tools' names render in the window
    for id, nm in pairs(NAMES) do
      if want[id] then
        H.assertEq(findName(glyphs(nm)) ~= nil, true,
          "\"" .. nm .. "\" renders in the tools window")
      end
    end
    -- 3b. and no magic-list row survives ("Fire" and "Cure" are both in
    --     Terra's list on this fixture, so the scan has something to find)
    for _, nm in ipairs({ "Fire", "Cure" }) do
      H.assertEq(findName(glyphs(nm)), nil,
        "no stale magic row (\"" .. nm .. "\") in the tools window")
    end
    H.log("PASSED: an abandoned boost-restage no longer bleeds the magic list into the next window")
  end),
})
