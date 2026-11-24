-- @suite
-- menu_runeknt.lua -- Celes's command reads "RuneKnt" in every window that
-- draws it (#563).
--
-- The Runic command ($0B) opens the Rune Knight's list since #563
-- (ot6_rune.asm), and its name in the command windows is BattleCmdName's
-- record $0B, "RuneKnt" (the list's first row keeps the name Runic).  Three
-- windows draw that record:
--   * the field Status screen's command box (status.asm DrawCmdName: BG3
--     screen A, column 20, row 14 + 2 x the command's slot);
--   * GOGO's command picker on his Status screen (DrawCmdNameGogo: BG3
--     screen B, column 0, row 2 + 2 x the list row; the list is $7E9D8A,
--     its first row the blank);
--   * the battle command window (btlgfx MenuTextCmd_0d: the menu's BG3 map,
--     whose base is the register shadow $897F's, column 4, row 9 + 2 x the
--     command's row).
--
-- Boot: cold Continue of wor-opera-v1, on the World of Ruin's map beside
-- the Falcon by the Opera House (CELES, RELM, GOGO and STRAGO seated).
-- Then, all through the controller, nothing written:
--   0. the ROM's record $0B is the seven cells of "RuneKnt";
--   1. Status, CELES: the row of her command box that holds $0B draws the
--      record's tiles, and her other three rows draw theirs (screenshot
--      runeknt_status);
--   2. Status, GOGO, A on a command slot: the picker offers $0B (CELES is
--      recruited), the cursor goes to it, its row draws the record's tiles
--      (screenshot runeknt_gogo), and B leaves his commands as they were;
--   3. a random battle: with CELES's command window up and the cursor on
--      the command, its row draws the record's tiles, and her other rows
--      theirs (screenshot runeknt_battle).  She then raises Runic through the
--      list and the battle is fought out through the menu.
-- Old-ROM red (record $0B reads "Runic"): build/attempts/wt/v051-spellblade/sb2/D/.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local ZMENUSTATE, ZCURSOR, ZCHARID = 0x26, 0x4b, 0x69
local CELES, GOGO, CMD_RUNIC, CMD_MIMIC = 0x06, 0x0C, 0x0B, 0x12
local ST_MAIN, ST_CHAR, ST_STATUS, ST_GOGO_LIST = 0x05, 0x06, 0x0c, 0x6a
local WANT = { 0x91, 0xAE, 0xA7, 0x9E, 0x8A, 0xA7, 0xAD }   -- R u n e K n t
local CMDNAMES = H.sym("BattleCmdName") & 0x3FFFFF
local NAME_SIZE = 7

local function st() return H.menuRunning() and H.readByte(ZMENUSTATE) or -1 end
local VR = emu.memType.snesVideoRam
-- VRAM word addresses of the field menu's BG3 screens A and B
local BG3A_V, BG3B_V = 0x4000, 0x4400
local function vcell(base, x, y) return emu.readWord((base + y * 32 + x) * 2, VR) end
local function record(cmd)
  local t = {}
  for i = 0, NAME_SIZE - 1 do t[#t + 1] = H.readRomByte(CMDNAMES + cmd * NAME_SIZE + i) end
  return t
end
local function hx(t)
  local s = {}
  for _, b in ipairs(t) do s[#s + 1] = string.format("%02X", b) end
  return table.concat(s, " ")
end
local function text(t)
  local s = ""
  for _, b in ipairs(t) do
    if b >= 0x80 and b <= 0x99 then s = s .. string.char(65 + b - 0x80)
    elseif b >= 0x9a and b <= 0xb3 then s = s .. string.char(97 + b - 0x9a)
    elseif b == 0xff then s = s .. " " else s = s .. "." end
  end
  return s
end
-- the seven tiles (low bytes) a window draws from (x, y) of a BG3 map
local function drawn(base, x, y)
  local t = {}
  for i = 0, NAME_SIZE - 1 do t[#t + 1] = vcell(base, x + i, y) & 0xFF end
  return t
end
local function cmdOf(char, slot) return H.readByte(0x1600 + 37 * char + 0x16 + slot) end
local function cmdsOf(char) return string.format("%02X %02X %02X %02X", cmdOf(char, 0), cmdOf(char, 1), cmdOf(char, 2),
  cmdOf(char, 3)) end

local function mainRow(row, what)
  return H.driveUntil(function() return st() == ST_MAIN and H.readByte(ZCURSOR) == row end, 900,
    { H.pressButtons({ "down" }, 2), H.waitFrames(8) }, what)
end
local function openMain(what)
  return H.driveUntil(function() return st() == ST_MAIN end, 1200,
    { H.pressButtons({ "x" }, 4), H.waitFrames(30) }, what)
end
local function closeMenu(what)
  return H.driveUntil(function() return H.worldHasControl() end, 1800,
    { H.pressButtons({ "b" }, 3), H.waitFrames(30) }, what)
end
-- the field menu's Status screen for one character, from the map
local function statusOf(char, what)
  return H.seqStep({
    openMain(what .. ": main menu"),
    H.waitFrames(20),
    mainRow(4, what .. ": Status"),
    H.pressButtons({ "a" }, 2),
    H.waitUntil(function() return st() == ST_CHAR end, 300, what .. ": character select", 5),
    H.waitFrames(10),
    H.driveUntil(function() return st() == ST_CHAR and H.readByte(ZCHARID + H.readByte(ZCURSOR)) == char end, 900,
      { H.pressButtons({ "down" }, 2), H.waitFrames(8) }, what .. ": the character"),
    H.pressButtons({ "a" }, 2),
    H.waitUntil(function() return st() == ST_STATUS end, 300, what .. ": the Status screen", 5),
    H.waitFrames(60),
  })
end

-- walking for an encounter: back and forth beside the landing (menu_painterpage_wor's lap)
local home, away
local function lap()
  local goal, wplan, idx
  return H.driveUntil(function() return H.battleLoadStarted() end, 30000, {
    H.call(function()
      if not H.worldHasControl() or not H.worldSettled() then wplan = nil; H.setPad({}) return end
      if not H.worldAligned() then return end
      local x, y = H.worldX(), H.worldY()
      goal = goal or away
      if wplan == nil or idx > #wplan then
        if x == goal[1] and y == goal[2] then goal = (goal == away) and home or away end
        wplan, idx = H.worldBfs(goal[1], goal[2]), 1
        if not wplan or #wplan == 0 then wplan = nil; H.setPad({}) return end
      end
      local dir = wplan[idx]; idx = idx + 1
      H.setPad({ [dir] = true })
    end),
  }, "a random encounter")
end

local gogoBefore, listRow = nil, nil
local rested, battleSeen = 0, false
-- the battle command window, read once the cursor has rested on CELES's
-- Runic row for twenty frames (the window is drawn by then)
local function battleWindow()
  rested = rested + 1
  if rested < 20 then return false end
  if battleSeen then return true end
  battleSeen = true
  local seat
  for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == CELES then seat = s end end
  H.assertEq(H.readByte(0x62CA), seat, "the open command window is CELES's")
  -- the menu's BG3 map: the register shadow's base (battle_runic's pipWordRow)
  local reg = H.readByte(0x897f)
  local base = (reg - (reg % 4)) * 256
  local found = false
  for r = 0, 3 do
    local cmd = H.readByte(0x202E + seat * 12 + r * 3)
    if cmd ~= 0xFF then
      H.assertEq(hx(drawn(base, 4, 9 + r * 2)), hx(record(cmd)), string.format(
        "the battle command window's row %d (command $%02X) draws BattleCmdName's record (\"%s\")", r, cmd,
        text(record(cmd))))
      if cmd == CMD_RUNIC then
        found = true
        H.assertEq(H.readByte(0x890F + seat) & 3, r, "the cursor rests on the command")
        H.assertEq(hx(drawn(base, 4, 9 + r * 2)), hx(WANT), string.format(
          "the battle command window draws \"RuneKnt\" on CELES's row %d", r))
      end
    end
  end
  H.assertEq(found, true, "CELES's battle commands hold $0B")
  H.screenshot("runeknt_battle")
  H.log("BATTLE OK: CELES's command window reads RuneKnt")
  return true
end

H.run({ maxFrames = 200000 }, {
  H.bootCheckpoint("wor-opera-v1"),
  H.waitUntil(function() return H.worldSettled() end, 1200, "world settled", 5),
  H.call(function()
    local active, seated = H.readByte(0x1A6D) & 7, {}
    for _, c in ipairs({ CELES, GOGO }) do
      local pb = H.readByte(0x1850 + c)
      seated[c] = (pb & 7) == active and (pb & 0x40) ~= 0
    end
    H.assertEq(seated[CELES] and seated[GOGO], true, "CELES and GOGO are seated (gen_wor_opera's party beside the "
      .. "Falcon: wor-opera-v1)")
    -- 0. the record
    H.assertEq(hx(record(CMD_RUNIC)), hx(WANT), "BattleCmdName's record $0B encodes \"RuneKnt\" (91 AE A7 9E 8A A7 AD)")
    H.assertEq(text(record(CMD_RUNIC)), "RuneKnt", "and reads RuneKnt")
    gogoBefore = cmdsOf(GOGO)
    H.log(string.format("commands: CELES %s, GOGO %s", cmdsOf(CELES), gogoBefore))
    local x, y = H.worldX(), H.worldY()
    home = { x, y }
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      if away == nil and H.worldBfs(x + d[1], y + d[2]) then away = { x + d[1], y + d[2] } end
    end
    H.assertEq(away ~= nil, true, "a walkable world tile beside the landing")
  end),

  -- 1. CELES's Status screen
  statusOf(CELES, "CELES"),
  H.call(function()
    local found = false
    for k = 0, 3 do
      local cmd = cmdOf(CELES, k)
      -- (Magic's row is blank while she has no MP to show, CheckRelicCmd; she has)
      if cmd ~= 0xFF then
        H.assertEq(hx(drawn(BG3A_V, 20, 14 + k * 2)), hx(record(cmd)), string.format(
          "CELES's Status command box, slot %d (command $%02X), draws BattleCmdName's record (\"%s\")", k, cmd,
          text(record(cmd))))
      end
      if cmd == CMD_RUNIC then
        found = true
        H.assertEq(hx(drawn(BG3A_V, 20, 14 + k * 2)), hx(WANT), string.format(
          "CELES's Status command box draws \"RuneKnt\" in slot %d (BG3A {20,%d})", k, 14 + k * 2))
      end
    end
    H.assertEq(found, true, "CELES's commands hold $0B")
    H.screenshot("runeknt_status")
    H.log("STATUS OK: CELES's command box reads RuneKnt")
  end),
  closeMenu("out to the map"),

  -- 2. GOGO's command picker
  statusOf(GOGO, "GOGO"),
  -- A on his Mimic slot does nothing (field_menu.asm @2254): any other slot
  H.driveUntil(function() return cmdOf(GOGO, H.readByte(ZCURSOR)) ~= CMD_MIMIC end, 900,
    { H.pressButtons({ "down" }, 2), H.waitFrames(8) }, "GOGO's command cursor off Mimic"),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_GOGO_LIST end, 300, "GOGO's command list", 5),
  H.waitFrames(20),
  H.call(function()
    local n, t = H.readByte(0x9d89), {}
    for i = 0, n - 1 do
      t[#t + 1] = string.format("%02X", H.readByte(0x9d8a + i))
      if H.readByte(0x9d8a + i) == CMD_RUNIC then listRow = i end
    end
    H.log(string.format("GOGO's list offers %s", table.concat(t, " ")))
    H.assertEq(listRow ~= nil, true, "GOGO's command list offers $0B (CELES is recruited)")
    -- the 16th row is drawn on another screen (Ot6LeoRow16); a recruited
    -- CELES's command comes well before it
    H.assertEq(listRow < 15, true, "the row is one of the list's first fifteen (BG3 screen B)")
  end),
  H.driveUntil(function() return st() == ST_GOGO_LIST and H.readByte(ZCURSOR) == listRow end, 900,
    { H.pressButtons({ "down" }, 2), H.waitFrames(8) }, "GOGO's list cursor on the command"),
  H.waitFrames(20),
  H.call(function()
    H.assertEq(hx(drawn(BG3B_V, 0, 2 + listRow * 2)), hx(WANT), string.format(
      "GOGO's command picker draws \"RuneKnt\" on row %d (BG3B {0,%d})", listRow, 2 + listRow * 2))
    H.screenshot("runeknt_gogo")
    H.log("GOGO OK: his command picker reads RuneKnt")
  end),
  H.pressButtons({ "b" }, 3),
  H.waitUntil(function() return st() == ST_STATUS end, 300, "back on GOGO's Status screen", 5),
  H.waitFrames(20),
  H.call(function() H.assertEq(cmdsOf(GOGO), gogoBefore, "B left GOGO's commands as they were") end),
  closeMenu("out to the map"),

  -- 3. the battle command window
  lap(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle up", 5),
  H.kitBattle({ { who = CELES, cmd = CMD_RUNIC, self = true, openWhen = battleWindow } },
    { untilPlanDone = true, idle = "defend", maxFrames = 40000 }),
  H.call(function() H.assertEq(battleSeen, true, "CELES's command window was read") end),
  H.fightBattleByMenu(40000),
  H.waitUntil(function() return not H.battleLoadStarted() and H.worldHasControl() end, 6000, "back on the map", 5),
  H.call(function() H.log("PASS: RuneKnt in the Status screen, GOGO's command picker and the battle command window") end),
})
