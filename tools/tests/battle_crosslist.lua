-- @suite savestate=figaro_cleared
-- battle_crosslist.lua -- Tools shows Cure 2.

-- TERRA's pool is topped up with a Sleeping Bag on the world map when she
-- arrives under her max (the replay brings her here at 19 of 34), and the R
-- below is asserted to be one her pool pays for.
--
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
local P = H.newPacer({ tag = "desert" })   -- one pool's row (#306)
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
-- #252: a subject KO'd, petrified or zombied never reaches the window this
-- file waits for (nobody here cures it); say so at once rather than at the
-- wait's timeout.  Statuses time or a hit clears (Sleep, Stop, Muddle) are
-- waited out as before.
local LASTING = { Death = true, Petrify = true, Zombie = true }
local function mustAct(slot, who, what)
  local c = slot and H.controlTaken(slot)
  if c and LASTING[c.name] then
    error(string.format("%s: %s cannot take a command: %s (H.controlTaken)", what, who, c.name), 0)
  end
end
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

-- ---- TERRA's MP, topped up the way a player would ---------------------------
-- What TERRA's pool holds on arrival is the line's play, not this suite's: the
-- replay of 87dae4e9 (and main's own at 8a8868d2) brings her here at 19 of 34
-- MP, where the old capture had 34 (build/attempts/wt/v050-gogo-kits/fix3/).
-- So the suite stages it as a player does on the world map: a Sleeping Bag on
-- her from the field Item menu when her pool is under its max, and then
-- asserts what it needs.  The field Item path is careKernel's (lib/ot6_field
-- .lua): $05 main (Item row 0) -A-> $08 list ($4B the bag slot) -A-> $19
-- picked up -A on the same slot-> $70 target ($4B the menu slot, $69+slot the
-- character) -A-> used.  BAG_NOCARE (a lab global, for the negative only)
-- skips the bag.
local SLEEPING_BAG = 0xF6
local function sleepingBagOn(char, what)
  local ph, n0, done = 0, nil, false
  local function st() return H.menuRunning() and H.readByte(0x26) or -1 end
  local function steer(cur, want)
    if cur == want then return { "a" } end
    return { [cur < want and "down" or "up"] = true }
  end
  local function ctl() return H.hasControl() or (H.worldMode() and H.worldHasControl()) end
  local function full() return H.charMp(char) >= H.charMaxMp(char) end
  return H.cond(function() return not full() and BAG_NOCARE == nil end, {
    H.withReset(H.driveUntil(function()
      return done and not H.menuRunning() and ctl()
    end, 6000, {
      H.call(function()
        n0 = n0 or H.invCountOf(SLEEPING_BAG)
        if n0 == 0 then error(what .. ": TERRA's pool is under its max and the bag holds no Sleeping Bag", 0) end
        ph = (ph + 1) % 12
        if H.invCountOf(SLEEPING_BAG) < n0 then done = true end
        local s, held = st(), {}
        if done then
          if s ~= -1 then held = { "b" } end
        elseif s == -1 then
          if ctl() then held = { "x" } end
        elseif s == 0x05 then
          held = steer(H.readByte(0x4B), 0)
        elseif s == 0x08 then
          held = steer(H.readByte(0x4B), H.invSlotOf(SLEEPING_BAG))
        elseif s == 0x19 then
          held = (H.readByte(0x4B) == H.invSlotOf(SLEEPING_BAG)) and { "a" } or { "b" }
        elseif s == 0x70 then
          local t
          for k = 0, 3 do if H.readByte(0x69 + k) == char then t = k end end
          if t ~= nil then held = steer(H.readByte(0x4B), t) end
        end
        if ph < 4 then H.setPad(held) else H.setPad({}) end
      end),
    }, what .. ": a Sleeping Bag on TERRA"), function() ph, n0, done = 0, nil, false end),
    H.call(function()
      H.log(string.format("[bag] %s: a Sleeping Bag on TERRA: MP %d/%d", what, H.charMp(char), H.charMaxMp(char)))
    end),
  }, {
    H.call(function()
      H.log(string.format("[bag] %s: no Sleeping Bag (TERRA MP %d/%d%s)", what, H.charMp(char), H.charMaxMp(char),
        BAG_NOCARE ~= nil and ", BAG_NOCARE" or ""))
    end),
  })
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
  -- pace one pool's stretch of the dismount row, not the clock (#306)
  H.waitUntil(function() return H.worldSettled() end, 1500, "the world map settled", 5),
  sleepingBagOn(0x00, "crosslist"),
  H.waitUntil(function() return H.worldSettled() and H.worldHasControl() end, 1500, "the world map after the bag", 5),
  H.call(function() P.plan() end),
  H.driveUntil(function() return H.battleLoadStarted() end, 20000, {
    H.call(function() H.setPad(P.pad()) end),
  }, "desert encounter"),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  H.waitFrames(90),
  H.call(function()
    P.assertGroup("the desert encounter")
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
    if H.battleActive() then mustAct(terra, "TERRA", "her real spell list open") end
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
    -- the R must be one the game takes (#555: a point the pool cannot pay
    -- for is refused): whichever of her rows the cursor rests on, its price
    -- at one point is in her pool
    local pool = H.readWord(0x3c08 + terra*2)
    for i = 0, 53 do
      local id = H.readByte(0x2092 + terra * 0x13C + i * 4)
      if id ~= 0xFF then
        local price = H.battleSpellPrice(terra, id, 1)
        H.assertEq(price <= pool, true, string.format(
          "TERRA's pool (%d MP) pays spell $%02X at one point (%d MP), so the R is taken", pool, id, price))
      end
    end
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
