-- @suite
-- menu_painterpage_wor.lua -- Relm's Painter page with her whole list, the
-- page for a Gogo who carries Sketch, and the Fake Mustache (#549).
--
-- menu_painterpage covers the page early in her learning; this one covers
-- the far end and the two arms the early save cannot reach.  The numbers come
-- from the battle's tables in the ROM as there (Ot6PaintRowTbl's order and
-- learn test, Ot6PaintName, Ot6PaintCostTbl), never from a copy here.
--
-- Boot: cold Continue of wor-gogo-v1, on the World of Ruin's map past the
-- Zone Eater (TERRA, STRAGO, RELM L53, GOGO seated; $02E8, $0240 and $00BA
-- set, so all eight rows are learned; a Fake Mustache in the bag).  Then,
-- all through the controller:
--   1. RELM's list: the Painter row white; her page draws all eight rows,
--      each its name and price (screenshot painterpage_complete); TERRA,
--      STRAGO and GOGO (Mimic, Lore, Tools, Item) have it grey and A on it
--      refuses;
--   2. GOGO is given Sketch on the Status screen (his command menu, the
--      Lore slot): his Painter row turns white and his page shows RELM's
--      rows, as his battle list does (#547);
--   3. the Fake Mustache goes on RELM through the Relic menu: her Painter
--      row is grey and A on it refuses (screenshot painterpage_mustache),
--      because in battle she has Control and no painter's list.  The test
--      reads the six worn pieces' relic-effects byte (ItemProp+10, bit $10),
--      the byte the battle's command rewrite tests; checked here: the Fake
--      Mustache's record carries the bit and no rung of the esper ladder
--      (Ot6LadderTbl's +5, the same byte) does, so gear is the whole answer;
--   4. the field menu and the battle agree: in the next random battle
--      RELM's command rows hold Control ($0E) and no Sketch ($0D), and
--      GOGO's hold Sketch.  The battle is then fought through the Fight menu.
-- Nothing is written.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local ZMENUSTATE, ZCURSOR, ZSELINDEX = 0x26, 0x4b, 0x28
local ZCHARID = 0x69
local PAINTER_COLOR = 0x81
local CHAR_RELM, CHAR_GOGO = 0x08, 0x0c
local CMD_SKETCH, CMD_CONTROL, CMD_LORE, CMD_TOOLS = 0x0d, 0x0e, 0x0c, 0x09
-- the commands that colour a Skills row (_c34d78 and the Painter row's scan)
local ROW_CMDS = { [0x02] = true, [0x07] = true, [0x0a] = true, [0x0c] = true, [0x10] = true, [0x13] = true,
  [0x05] = true, [0x0d] = true }
local plainCmd
local FAKE_MUSTACHE = 0xd7
local ST_MAIN, ST_CHAR, ST_SKILLS, ST_PAINTER = 0x05, 0x06, 0x0a, 0x31
local ST_GOGO_LIST = 0x6a
local ROW_PAINTER = 8
local WHITE, GREY = 0x20, 0x24
local NAMES_CH = { [0] = "TERRA", "LOCKE", "CYAN", "SHADOW", "EDGAR", "SABIN", "CELES", "STRAGO",
  "RELM", "SETZER", "MOG", "GAU", "GOGO", "UMARO" }

local function st() return H.menuRunning() and H.readByte(ZMENUSTATE) or -1 end

local VR = emu.memType.snesVideoRam
local function vcell(base, x, y) return emu.readWord((base + y * 32 + x) * 2, VR) end
local BG3A_V, BG3B_V = 0x4000, 0x4400
local function enc(ch)
  local b = ch:byte()
  if ch == " " then return 0xff end
  if b >= 65 and b <= 90 then return 0x80 + b - 65 end
  return 0x9a + b - 97
end
local function assertVText(base, x0, y, text, what)
  for i = 1, #text do
    H.assertEq(vcell(base, x0 + i - 1, y) & 0xff, enc(text:sub(i, i)),
      string.format("%s: '%s' letter %d at {%d,%d}", what, text, i, x0 + i - 1, y))
  end
end

local BG1A = 0x3849
local function cell(x, y) return H.readByte(BG1A + x * 2 + y * 64) end
local ZERO_CHAR, PAD = 0xb4, 0xff
local MP_SUFFIX = { 0xff, 0x8c, 0x8f }

local ROWTBL = H.sym("Ot6PaintRowTbl") & 0x3FFFFF
local NAMES = H.sym("Ot6PaintName") & 0x3FFFFF
local COSTS = H.sym("Ot6PaintCostTbl") & 0x3FFFFF
local ITEMPROP = H.sym("ItemProp") & 0x3FFFFF
local LADDER = H.sym("Ot6LadderTbl") & 0x3FFFFF
local ID0, REC, ROWS, NAME_SIZE = 0xe8, 4, 8, 10
local LADDER_RECS, LADDER_REC = 26 * 5, 14   -- ot6_esper.asm: 26 espers x 5 rungs x OT6_REC
local RELIC_CONTROL = 0x10                   -- ItemProp+10 / $11d6: Sketch -> Control
local RELM_LEVEL = 0x1600 + 37 * CHAR_RELM + 8
local function rowId(i) return H.readRomByte(ROWTBL + i * REC) end
local function learned(i)
  local a, b = H.readRomByte(ROWTBL + i * REC + 2), H.readRomByte(ROWTBL + i * REC + 3)
  if b ~= 0 then return (H.readByte(0x1E80 + a) & b) ~= 0 end
  return a == 0 or a - 1 < H.readByte(RELM_LEVEL)
end
local function nameBytes(id)
  local t = {}
  for k = 0, NAME_SIZE - 1 do t[k + 1] = H.readRomByte(NAMES + (id - ID0) * NAME_SIZE + k) end
  return t
end
local function costOf(id) return H.readRomByte(COSTS + id - ID0) end

local NAME_COL, COST_COL = 3, 16
local function assertAllRows(tag)
  for i = 0, ROWS - 1 do
    local id, y = rowId(i), 1 + i * 2
    H.assertEq(learned(i), true, string.format("%s: row %d ($%02X) is learned on this save", tag, i, id))
    for k, b in ipairs(nameBytes(id)) do
      H.assertEq(cell(NAME_COL + k - 1, y), b, string.format("%s: row %d ($%02X) name, cell {%d,%d}", tag, i, id,
        NAME_COL + k - 1, y))
    end
    local cost = costOf(id)
    if cost == 0 then
      for x = COST_COL, COST_COL + 4 do
        H.assertEq(cell(x, y), PAD, string.format("%s: row %d costs 0: blank at {%d,%d}", tag, i, x, y))
      end
    else
      local tens = cost // 10
      H.assertEq(cell(COST_COL, y), tens > 0 and (ZERO_CHAR + tens) or PAD,
        string.format("%s: row %d ($%02X) cost %d, tens", tag, i, id, cost))
      H.assertEq(cell(COST_COL + 1, y), ZERO_CHAR + cost % 10,
        string.format("%s: row %d ($%02X) cost %d, ones", tag, i, id, cost))
      for k, b in ipairs(MP_SUFFIX) do
        H.assertEq(cell(COST_COL + 1 + k, y), b, string.format("%s: row %d ' MP'", tag, i))
      end
    end
  end
  assertVText(BG3B_V, 23, 5, "Painter", tag .. ": the title box")
  H.log(string.format("PAGE OK (%s): all eight rows, names and prices from the battle's tables", tag))
end

local function hasCmd(char, cmd)
  for i = 0, 3 do
    if H.readByte(0x1600 + 37 * char + 0x16 + i) == cmd then return true end
  end
  return false
end
local function wears(char, item)
  for s = 0, 5 do
    if H.readByte(0x1600 + 37 * char + 0x1f + s) == item then return true end
  end
  return false
end

local slots = {}
local function slotOf(char)
  for s = 0, 3 do if slots[s] == char then return s end end
end

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
-- the field menu's Skills list for one character, from the field
local function openSkills(char, what)
  return H.seqStep({
    openMain(what .. ": main menu"),
    H.waitFrames(20),
    mainRow(1, what .. ": Skills"),
    H.pressButtons({ "a" }, 2),
    H.waitUntil(function() return st() == ST_CHAR end, 300, what .. ": character select", 5),
    H.waitFrames(10),
    H.driveUntil(function() return st() == ST_CHAR and H.readByte(ZCHARID + H.readByte(ZCURSOR)) == char end, 900,
      { H.pressButtons({ "down" }, 2), H.waitFrames(8) }, what .. ": the character"),
    H.pressButtons({ "a" }, 2),
    H.waitUntil(function() return st() == ST_SKILLS end, 300, what .. ": the Skills list", 5),
    H.waitFrames(20),
  })
end
local function toPainter(what)
  return H.driveUntil(function() return st() == ST_SKILLS and H.readByte(ZCURSOR) == ROW_PAINTER end, 900,
    { H.pressButtons({ "down" }, 2), H.waitFrames(6) }, what)
end
local function assertColor(char, want, tag)
  H.assertEq(H.readByte(ZCHARID + H.readByte(ZSELINDEX)), char, tag .. ": the list is " .. NAMES_CH[char] .. "'s")
  H.assertEq(H.readByte(PAINTER_COLOR), want, string.format("%s: %s's Painter row is %s", tag, NAMES_CH[char],
    want == WHITE and "white" or "grey"))
  assertVText(BG3A_V, 2, 21, "Painter", tag .. ": the ninth row")
  H.assertEq(vcell(BG3A_V, 2, 21) >> 8, want, tag .. ": the row's attribute is that colour")
end
local function refuses(tag)
  return H.seqStep({
    toPainter(tag .. ": cursor to Painter"),
    H.pressButtons({ "a" }, 2),
    H.waitFrames(30),
    H.call(function()
      H.assertEq(st(), ST_SKILLS, tag .. ": A on the grey row refuses")
      H.log("REFUSE OK (" .. tag .. ")")
    end),
  })
end
local function opensPage(tag, shot)
  return H.seqStep({
    toPainter(tag .. ": cursor to Painter"),
    H.pressButtons({ "a" }, 2),
    H.waitUntil(function() return st() == ST_PAINTER end, 300, tag .. ": the page opens", 5),
    H.waitFrames(90),
    H.call(function()
      assertAllRows(tag)
      if shot then H.screenshot(shot) end
    end),
    H.pressButtons({ "b" }, 3),
    H.waitUntil(function() return st() == ST_SKILLS end, 300, tag .. ": B back to the list", 5),
    H.waitFrames(20),
  })
end

-- walking for an encounter: back and forth beside the save (battle_relmwor's lap)
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

local function battleCmds(char)
  for a = 0, 3 do
    if H.readByte(0x3ED8 + a * 2) == char then
      local t = {}
      for r = 0, 3 do t[#t + 1] = H.readByte(0x202E + a * 12 + r * 3) end
      return t
    end
  end
end

H.run({ maxFrames = 200000 }, {
  H.bootCheckpoint("wor-gogo-v1"),
  H.waitUntil(function() return H.worldSettled() end, 1200, "world settled", 5),
  H.call(function()
    -- the party in menu order: $1850's slot bits for the active party
    local active = H.readByte(0x1A6D) & 7
    for c = 0, 15 do
      local pb = H.readByte(0x1850 + c)
      if (pb & 7) == active and (pb & 0x40) ~= 0 then slots[(pb >> 3) & 3] = c end
    end
    H.log(string.format("party: %s %s %s %s", NAMES_CH[slots[0]] or "-", NAMES_CH[slots[1]] or "-",
      NAMES_CH[slots[2]] or "-", NAMES_CH[slots[3]] or "-"))
    H.assertEq(slotOf(CHAR_RELM) ~= nil and slotOf(CHAR_GOGO) ~= nil, true, "RELM and GOGO are seated")
    for i = 0, ROWS - 1 do
      H.assertEq(learned(i), true, string.format("row %d ($%02X) is learned: RELM L%d, the three switches set", i,
        rowId(i), H.readByte(RELM_LEVEL)))
    end
    H.assertEq(hasCmd(CHAR_GOGO, CMD_SKETCH), false, "GOGO starts without Sketch (Mimic, Lore, Tools, Item)")
    H.assertEq(hasCmd(CHAR_GOGO, CMD_LORE), true, "GOGO carries Lore, the slot Sketch takes")
    H.assertEq(H.invCountOf(FAKE_MUSTACHE) > 0, true, "a Fake Mustache is in the bag")
    H.assertEq(wears(CHAR_RELM, FAKE_MUSTACHE), false, "RELM does not wear it yet")
    -- the static half of the Mustache arm
    H.assertEq(H.readRomByte(ITEMPROP + FAKE_MUSTACHE * 30 + 10) & RELIC_CONTROL, RELIC_CONTROL,
      "the Fake Mustache's relic-effects byte (ItemProp+10) carries Sketch -> Control ($10)")
    for r = 0, LADDER_RECS - 1 do
      H.assertEq(H.readRomByte(LADDER + r * LADDER_REC + 5) & RELIC_CONTROL, 0, string.format(
        "esper ladder rung %d (stone %d, rung %d) does not turn Sketch into Control: gear is the whole answer", r,
        r // 5, r % 5))
    end
    local x, y = H.worldX(), H.worldY()
    home = { x, y }
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      if away == nil and H.worldBfs(x + d[1], y + d[2]) then away = { x + d[1], y + d[2] } end
    end
    H.assertEq(away ~= nil, true, "a walkable world tile beside the save")
  end),

  -- 1. RELM's complete page; the others grey
  openSkills(CHAR_RELM, "RELM"),
  H.call(function() assertColor(CHAR_RELM, WHITE, "RELM") end),
  opensPage("RELM complete", "painterpage_complete"),
  H.call(function()
    H.assertEq(H.readByte(ZCURSOR), ROW_PAINTER, "back on the list on Painter")
  end),
  closeMenu("out to the map"),
  openSkills(0, "TERRA"),
  H.call(function() assertColor(0, GREY, "TERRA") end),
  refuses("TERRA"),
  closeMenu("out"),
  openSkills(0x07, "STRAGO"),
  H.call(function() assertColor(0x07, GREY, "STRAGO") end),
  refuses("STRAGO"),
  closeMenu("out"),
  openSkills(CHAR_GOGO, "GOGO"),
  H.call(function() assertColor(CHAR_GOGO, GREY, "GOGO without Sketch") end),
  refuses("GOGO without Sketch"),
  closeMenu("out"),

  -- 2. GOGO takes Sketch in his Lore slot, on the Status screen
  openMain("Status: main menu"),
  H.waitFrames(20),
  mainRow(4, "Status"),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_CHAR end, 300, "Status: character select", 5),
  H.waitFrames(10),
  H.driveUntil(function() return st() == ST_CHAR and H.readByte(ZCHARID + H.readByte(ZCURSOR)) == CHAR_GOGO end, 900,
    { H.pressButtons({ "down" }, 2), H.waitFrames(8) }, "Status: GOGO"),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() ~= ST_CHAR and st() ~= -1 end, 300, "GOGO's status", 5),
  H.waitFrames(40),
  H.driveUntil(function()
    return H.readByte(0x1600 + 37 * CHAR_GOGO + 0x16 + H.readByte(ZCURSOR)) == CMD_LORE
  end, 900, { H.pressButtons({ "down" }, 2), H.waitFrames(8) }, "GOGO's command cursor on Lore"),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_GOGO_LIST end, 300, "GOGO's command list", 5),
  H.waitFrames(20),
  H.call(function()
    local n, has = H.readByte(0x9d89), false
    for i = 0, n - 1 do if H.readByte(0x9d8a + i) == CMD_SKETCH then has = true end end
    H.assertEq(has, true, "GOGO's command list offers Sketch (RELM is seated)")
  end),
  H.driveUntil(function()
    return st() == ST_GOGO_LIST and H.readByte(0x9d8a + H.readByte(ZCURSOR)) == CMD_SKETCH
  end, 900, { H.pressButtons({ "down" }, 2), H.waitFrames(8) }, "GOGO's list cursor on Sketch"),
  H.pressButtons({ "a" }, 2),
  H.waitFrames(40),
  H.call(function()
    H.assertEq(hasCmd(CHAR_GOGO, CMD_SKETCH), true, "GOGO carries Sketch now")
    H.log("GOGO OK: Sketch in his Lore slot, through his command list")
  end),
  -- and his Tools slot becomes a command with no Skills row, so the Painter
  -- row is the only row that opens his Skills menu (CheckSkillValid's nine)
  H.driveUntil(function()
    return H.readByte(0x1600 + 37 * CHAR_GOGO + 0x16 + H.readByte(ZCURSOR)) == CMD_TOOLS
  end, 900, { H.pressButtons({ "down" }, 2), H.waitFrames(8) }, "GOGO's command cursor on Tools"),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_GOGO_LIST end, 300, "GOGO's command list again", 5),
  H.waitFrames(20),
  H.call(function()
    local n, offered = H.readByte(0x9d89), {}
    for i = 0, n - 1 do
      local c = H.readByte(0x9d8a + i)
      offered[#offered + 1] = string.format("%02X", c)
      if plainCmd == nil and not ROW_CMDS[c] and not hasCmd(CHAR_GOGO, c) and c ~= 0xff then plainCmd = c end
    end
    H.log("GOGO's list offers " .. table.concat(offered, " "))
    H.assertEq(plainCmd ~= nil, true, "GOGO's list offers a command that opens no Skills row")
  end),
  H.driveUntil(function()
    return st() == ST_GOGO_LIST and H.readByte(0x9d8a + H.readByte(ZCURSOR)) == plainCmd
  end, 900, { H.pressButtons({ "down" }, 2), H.waitFrames(8) }, "GOGO's list cursor on that command"),
  H.pressButtons({ "a" }, 2),
  H.waitFrames(40),
  H.call(function()
    for i = 0, 3 do
      local c = H.readByte(0x1600 + 37 * CHAR_GOGO + 0x16 + i)
      H.assertEq(ROW_CMDS[c] == nil or c == CMD_SKETCH, true, string.format(
        "GOGO's command %d ($%02X) opens no Skills row but Painter's", i, c))
    end
    H.log(string.format("GOGO OK: Tools gave way to $%02X; Sketch is his only Skills command", plainCmd))
  end),
  closeMenu("out"),
  openSkills(CHAR_GOGO, "GOGO with Sketch"),
  H.call(function()
    assertColor(CHAR_GOGO, WHITE, "GOGO with Sketch")
    for i = 0, 7 do
      H.assertEq(H.readByte(0x79 + i), GREY, string.format(
        "GOGO's Skills row %d is grey: the Painter row alone let his Skills menu open", i))
    end
  end),
  opensPage("GOGO with Sketch", "painterpage_gogo"),
  closeMenu("out"),

  -- 3. the Fake Mustache on RELM
  H.equipLoadout(CHAR_RELM, { { 4, FAKE_MUSTACHE } }, { tag = "RELM: Fake Mustache" }),
  H.waitUntil(function() return H.worldSettled() end, 1800, "back on the map", 5),
  H.call(function() H.assertEq(wears(CHAR_RELM, FAKE_MUSTACHE), true, "RELM wears the Fake Mustache") end),
  openSkills(CHAR_RELM, "RELM with the Mustache"),
  H.call(function()
    assertColor(CHAR_RELM, GREY, "RELM with the Mustache")
    H.screenshot("painterpage_mustache")
  end),
  refuses("RELM with the Mustache"),
  closeMenu("out"),

  -- 4. the battle agrees
  lap(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle up", 5),
  H.waitFrames(30),
  H.call(function()
    local r, g = battleCmds(CHAR_RELM), battleCmds(CHAR_GOGO)
    H.assertEq(r ~= nil and g ~= nil, true, "RELM and GOGO are in the battle")
    local function has(t, c) for _, v in ipairs(t) do if v == c then return true end end return false end
    H.log(string.format("battle commands: RELM %02X %02X %02X %02X, GOGO %02X %02X %02X %02X",
      r[1], r[2], r[3], r[4], g[1], g[2], g[3], g[4]))
    H.assertEq(has(r, CMD_CONTROL) and not has(r, CMD_SKETCH), true,
      "in battle RELM with the Mustache has Control and no Sketch: no painter's list, as the field said")
    H.assertEq(has(g, CMD_SKETCH), true, "in battle GOGO has Sketch: his list opens, as the field said")
    H.log("BATTLE OK: the field menu and the battle agree")
  end),
  H.fightBattleByMenu(40000),
})
