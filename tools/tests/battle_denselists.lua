-- @suite slow
-- battle_denselists.lua -- the battle Magic, Lore and Rage lists are packed
-- (#541): each caster's Magic window lists exactly the spells he can cast
-- right now, in the Config's Magic Order with an esper's or a shield's spells
-- in their places among them, with no blank cells and no blank rows to scroll
-- through; Strago's Lore window lists exactly the lores his loadout offers,
-- one to a row from the top; and no window's cursor or scroll can rest past
-- its last entry.
--
-- Six fixtures, each into a real random battle (paced on the map it stands
-- on): worldmap_narshe (TERRA early: Cure and Fire, nothing else), fc_landing
-- (three wearers of three stones), wor_ancient_hunt (TERRA late, CELES, CYAN,
-- RELM, each with a stone), wob_esper_mtn_hunt (STRAGO's first lores),
-- wor_gogo (GOGO, who casts whatever the others can, and STRAGO with six
-- lores, so his window scrolls) and wor_gau (GAU's Rage list).  Nothing is
-- written: the stones and gear are what the play put on them.
--
-- What is asserted, per seated member with a list:
--   * the list's rows (the window's own cells, $208e + slot*$13c) are the
--     expected spells in order and then empty, the expected set computed
--     here from the learned table, the worn stone's GenjuProp row, the worn
--     items' Ot6ItemGrantTbl rows and STRAGO's Analyze (GOGO: the union of the
--     others'), the order from the Config's Magic Order; $3cf8 holds the count;
--   * walking the window from its first cell with Right (Lore: Down) visits
--     every cell in order and each step lands on a listed entry; the line the
--     cursor sits on is in the window's BG3 text (VRAM) with that row's names;
--   * past the last entry Right and Down move nothing, and the scroll is never
--     past the packed list's top;
--   * Up from the first cell opens the stone's summon window when one is worn,
--     and Down closes it onto the list;
--   * A on each enabled row stages that row's spell (or lore, or rage) as the
--     action ($7a85), backed out with B (a row that commits at once, with
--     nothing to target, ends the walk for that member).
-- Mutants: the v0.45 ROM (lists unpacked) fails the first rows check; a ROM
-- whose Ot6ListClamp returns at once fails the walk past the last entry.
local H = dofile("tools/tests/lib/ot6.lua")

local FIXTURES = {
  { state = "build/states/worldmap_narshe.mss.lua", tag = "early" },
  { state = "build/states/fc_landing.mss.lua", tag = "stones" },
  { state = "build/states/wor_ancient_hunt.mss.lua", tag = "late" },
  { state = "build/states/wob_esper_mtn_hunt.mss.lua", tag = "lore" },
  { state = "build/states/wor_gogo.mss.lua", tag = "gogo" },
  { state = "build/states/wor_gau.mss.lua", tag = "rage" },
}

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD, ST_TRANS, ST_MAGIC, ST_ESPER, ST_LORE, ST_RAGE = 0x05, 0x01, 0x0E, 0x16, 0x1B, 0x1E
local CMD_MAGIC, CMD_XMAGIC, CMD_LORE, CMD_RAGE = 0x02, 0x17, 0x0C, 0x10
local LISTPTR = { [0] = 0x208E, [1] = 0x21CA, [2] = 0x2306, [3] = 0x2442 }
local STAGED = 0x7A85
local GOGO, STRAGO, ANALYZE = 0x0C, 0x07, 0x18
local MAGICNAME = H.sym("MagicName") & 0x3FFFFF
local ATTACKNAME = H.sym("AttackName") & 0x3FFFFF

local function st() return H.readByte(MSTATE) end
local function hx(t)
  local s = {}
  for _, v in ipairs(t) do s[#s + 1] = string.format("%02x", v) end
  return table.concat(s, " ")
end

-- the Config's Magic Order (CalcMagicOrder's MagicOrderTbl, InitSpellList's
-- three offset tables): black $00-$17, effect $18-$2c, white $2d-$35
local GROUPS = { black = { 0x00, 0x17 }, effect = { 0x18, 0x2C }, white = { 0x2D, 0x35 } }
local ORDERS = {
  [0] = { "white", "black", "effect" }, [1] = { "white", "effect", "black" },
  [2] = { "black", "effect", "white" }, [3] = { "black", "white", "effect" },
  [4] = { "effect", "white", "black" }, [5] = { "effect", "black", "white" },
}
local function ordered(set)
  local out = {}
  for _, g in ipairs(ORDERS[H.readByte(0x1D54) & 0x07]) do
    for id = GROUPS[g][1], GROUPS[g][2] do
      if set[id] then out[#out + 1] = id end
    end
  end
  return out
end

-- what a seated member can cast, from the save's own sources
local function knownSet(slot)
  local actor, c = H.readByte(0x3ED8 + slot * 2), H.readByte(0x3ED9 + slot * 2)
  local set = {}
  if actor >= 0x0C then return set end
  H.assertEq(H.charActor(c), actor, string.format("slot %d's record %d is its actor", slot, c))
  for id = 0, 0x35 do if H.knowsSpell(c, id) then set[id] = true end end
  if actor == STRAGO then set[ANALYZE] = true end
  return set
end
local function expectedMagic(slot)
  local actor = H.readByte(0x3ED8 + slot * 2)
  if actor ~= GOGO then return ordered(knownSet(slot)) end
  local set = {}
  for s = 0, 3 do
    local a = H.readByte(0x3ED8 + s * 2)
    if s ~= slot and a < 0x0C then
      for id in pairs(knownSet(s)) do set[id] = true end
    end
  end
  return ordered(set)
end
local function expectedLores()
  local out = {}
  for y = 0, 23 do
    if H.readByte(0x306A + y) == y + 0x8B then out[#out + 1] = y end
  end
  return out
end
local function expectedRages()
  local out = {}
  for i = 0, 255 do
    local r = H.readByte(0x257E + i)
    if r == 0xFF then break end
    out[#out + 1] = r
  end
  return out
end

local function cmdRow(slot, cmd)
  for r = 0, 3 do if H.readByte(0x202E + slot * 12 + r * 3) == cmd then return r end end
  return nil
end

-- the rows check: a segment's cells are `want`, then empty
local function checkRows(slot, first, count, want, what)
  local got = {}
  for r = 0, count - 1 do got[#got + 1] = H.readByte(LISTPTR[slot] + (first + r) * 4) end
  local exp = {}
  for r = 1, count do exp[r] = want[r] or 0xFF end
  H.log(string.format("[dense] %s: rows %s", what, hx(got)))
  H.assertEq(hx(got), hx(exp), what .. ": the list's rows are the expected entries, packed, then empty")
end

-- ---------------------------------------------------------------- VRAM text
local VR = emu.memType.snesVideoRam
local LINES = { 0x7C20, 0x7C60, 0x7CA0, 0x7CE0, 0x7D20 }   -- _c18291's five, text half
local function cells(line, col, n)
  local t = {}
  for k = 0, n - 1 do t[#t + 1] = emu.read((line + col + k) * 2, VR) end
  return t
end
local function nameBytes(base, size, rec)
  local t = {}
  for k = 0, size - 1 do t[#t + 1] = H.readRomByte(base + size * rec + k) end
  return t
end
local BLANK7 = { 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF }
local function magicLineShown(left, right)
  local L = hx(nameBytes(MAGICNAME, 7, left))
  local R = right and hx(nameBytes(MAGICNAME, 7, right)) or hx(BLANK7)
  for _, line in ipairs(LINES) do
    if hx(cells(line, 3, 7)) == L and hx(cells(line, 12, 7)) == R then return true end
  end
  return false
end
local function textShown(bytes)
  local want = hx(bytes)
  for _, line in ipairs(LINES) do
    for col = 0, 32 - #bytes do
      if hx(cells(line, col, #bytes)) == want then return true end
    end
  end
  return false
end

-- ------------------------------------------------------- the walk (coroutine)
local function frame(pad) coroutine.yield(pad or {}) end
local function idle(n) for _ = 1, n do frame({}) end end
local function press(btn) for _ = 1, 4 do frame({ [btn] = true }) end idle(10) end

-- per kind: list state, command, cursor cells, columns, step button
local KIND = {
  magic = { st = ST_MAGIC, cmd = CMD_MAGIC, scroll = 0x8913, cols = 2, step = "right" },
  lore = { st = ST_LORE, cmd = CMD_LORE, scroll = 0x891F, cols = 1, step = "down" },
  rage = { st = ST_RAGE, cmd = CMD_RAGE, scroll = 0x892B, cols = 2, step = "right" },
}
local function cursorIndex(k, slot)
  local sc, col, row = H.readByte(k.scroll + slot), H.readByte(k.scroll + 4 + slot), H.readByte(k.scroll + 8 + slot)
  return (sc + row) * k.cols + (k.cols == 2 and col or 0), sc
end
local function topOf(k, n)
  local rows = (k.cols == 2) and (n + 1) // 2 or n
  return math.max(0, rows - 4)
end

-- bring up `slot`'s window for `k`; false if the member never gets a turn
local function openWindow(k, slot, tag)
  local row = cmdRow(slot, k.cmd)
  for _ = 1, 12000 do
    local s = st()
    if H.readByte(MENU) ~= 0 and s ~= ST_TRANS then
      local act = H.readByte(ACTOR) & 3
      if act ~= slot then
        press(s == ST_CMD and "x" or "b")
      elseif s == k.st then
        idle(30)
        return true
      elseif s == ST_CMD then
        local cur = H.readByte(0x890F + slot) & 3
        if cur == row then press("a") else press(cur < row and "down" or "up") end
      else
        press("b")
      end
    else
      frame({})
    end
  end
  error(tag .. ": the member's " .. k.st .. " window never came up", 0)
end
-- per fixture: a worn stone seen on a member's magic walk, the Up checks made, the walks a lost control ended
local stoneSeen, upChecked, lostMid = {}, {}, {}
local function closeWindow(k, slot)
  for _ = 1, 40 do
    if st() ~= k.st and st() ~= ST_ESPER then return end
    press("b")
  end
end

local function walk(kindName, slot, want, tag)
  local k = KIND[kindName]
  local n = #want
  openWindow(k, slot, tag)
  H.screenshot(string.format("battle_denselists_%s_%s_slot%d", tag, kindName, slot))
  -- every cell in order, from the first
  for _ = 1, 64 do
    local i, sc = cursorIndex(k, slot)
    if i == 0 and sc == 0 then break end
    press(k.cols == 2 and "left" or "up")
  end
  local i = cursorIndex(k, slot)
  H.assertEq(i, 0, tag .. ": the cursor reaches the first cell")
  for step = 0, n - 1 do
    i = cursorIndex(k, slot)
    H.assertEq(i, step, string.format("%s: step %d lands on cell %d", tag, step, step))
    if kindName == "magic" then
      local r = step // 2
      H.assertEq(magicLineShown(want[2 * r + 1], want[2 * r + 2]), true,
        string.format("%s: the window shows row %d as %s / %s", tag, r, hx({ want[2 * r + 1] }),
          want[2 * r + 2] and hx({ want[2 * r + 2] }) or "blank"))
    elseif kindName == "lore" then
      H.assertEq(textShown({ table.unpack(nameBytes(ATTACKNAME, 10, want[step + 1] + 0x8B - 0x51), 1, 6) }), true,
        string.format("%s: the window shows lore %d's name on its row", tag, want[step + 1]))
    end
    if step < n - 1 then press(k.step) end
  end
  -- past the last entry nothing moves, and the scroll stays inside the list
  for _, b in ipairs({ k.step, "right", "down", "down", "right" }) do
    press(b)
    local j, sc = cursorIndex(k, slot)
    H.assertEq(j, n - 1, string.format("%s: %s past the last entry stays on it (cell %d of %d)", tag, b, j, n))
    H.assertEq(sc <= topOf(k, n), true, string.format("%s: scroll %d within the top %d", tag, sc, topOf(k, n)))
  end
  H.screenshot(string.format("battle_denselists_%s_%s_slot%d_end", tag, kindName, slot))
  -- back to the first cell; Up there opens the summon when a stone is worn
  for _ = 1, 64 do
    local j, sc = cursorIndex(k, slot)
    if j == 0 and sc == 0 then break end
    press(k.cols == 2 and "left" or "up")
  end
  -- a member who lost control during the walk (Petrify, Zombie or Death: the same mask the walks test at a
  -- member's start) keeps a window the engine closes at the next press (v0.50 line's wob_esper_mtn_hunt capture:
  -- STRAGO petrified while his list was walked, "st 0E ... s1 40", and Up took the menu to $14, $01, $0F;
  -- build/attempts/wt/v050-line-deaths/suites/): its walk ends there, said, and the fixture's other members
  -- carry the summon check (asserted per fixture below)
  if (H.readByte(0x3EE4 + slot * 2) & 0xC2) ~= 0 then
    H.log(string.format("[dense] %s slot %d lost control during its %s walk (status1 $%02X): the rest of its walk "
      .. "is the engine's window, not the list's; ended here", tag, slot, kindName, H.readByte(0x3EE4 + slot * 2)))
    lostMid[tag] = (lostMid[tag] or 0) + 1
    if kindName == "magic" and H.readByte(LISTPTR[slot]) ~= 0xFF then stoneSeen[tag] = true end
    closeWindow(k, slot)
    return 0
  end
  if kindName == "magic" and H.readByte(LISTPTR[slot]) ~= 0xFF then
    stoneSeen[tag] = true
    upChecked[tag] = (upChecked[tag] or 0) + 1
    press("up")
    idle(10)
    H.assertEq(st(), ST_ESPER, tag .. ": Up from the first cell opens the worn stone's summon")
    press("down")             -- the summon window closes with Down or Right
    for _ = 1, 60 do if st() == k.st then break end frame({}) end
    H.assertEq(st(), k.st, tag .. ": Down from the summon returns to the list")
  end
  -- A on each enabled row stages that row's entry
  local confirmed = 0
  for c = 0, n - 1 do
    for _ = 1, 64 do
      local j = cursorIndex(k, slot)
      if j == c then break end
      press(j < c and k.step or (k.cols == 2 and "left" or "up"))
    end
    H.assertEq(cursorIndex(k, slot), c, string.format("%s: back on cell %d to confirm it", tag, c))
    local rowAddr = nil         -- the rage list has no flags byte
    if kindName ~= "rage" then rowAddr = LISTPTR[slot] + ((kindName == "lore") and (55 + c) or (1 + c)) * 4 end
    local greyed = rowAddr and (H.readByte(rowAddr + 1) & 0x80) ~= 0
    if not greyed then
      local before = H.readByte(STAGED)
      press("a")
      idle(8)
      if kindName == "rage" and st() == k.st and (H.readByte(ACTOR) & 3) == slot then
        -- the rage window greys a row its MP cannot pay (Ot6RageConfirmMP);
        -- its A buzzes and stays
        H.log(string.format("[dense] %s: rage cell %d refused (greyed)", tag, c))
        goto nextcell
      end
      for _ = 1, 40 do              -- settle: targeting, or committed at once
        if st() ~= ST_TRANS and st() ~= k.st then break end
        frame({})
      end
      local got = H.readByte(STAGED)
      H.assertEq(got, want[c + 1], string.format("%s: A on cell %d stages %02x (was %02x)", tag, c, want[c + 1], before))
      confirmed = confirmed + 1
      if H.readByte(MENU) == 0 or (H.readByte(ACTOR) & 3) ~= slot or st() == ST_CMD then
        H.log(string.format("[dense] %s: cell %d committed at once; the walk ends here", tag, c))
        return confirmed
      end
      for _ = 1, 20 do
        if st() == k.st then break end
        press("b")
      end
      if st() ~= k.st then
        -- some targetings back out to the command window, not the list
        -- (vanilla's): open the list again and go on from the next cell
        H.log(string.format("[dense] %s: B from cell %d's targeting left the list (state %02x); reopening",
          tag, c, st()))
        openWindow(k, slot, tag)
      end
    else
      H.log(string.format("[dense] %s: cell %d is greyed (not confirmed)", tag, c))
    end
    ::nextcell::
  end
  closeWindow(k, slot)
  return confirmed
end

local function checkBattle(tag)
  local seen = {}
  for slot = 0, 3 do
    local actor = H.readByte(0x3ED8 + slot * 2)
    if actor < 0x10 then
      local want = expectedMagic(slot)
      seen[#seen + 1] = string.format("slot %d actor %02x: %d spells %s", slot, actor, #want, hx(want))
      checkRows(slot, 1, 54, want, string.format("%s slot %d (actor %02x) magic", tag, slot, actor))
      H.assertEq(H.readByte(0x3CF8 + slot * 2), #want, string.format("%s slot %d: $3cf8 counts its spells", tag, slot))
      checkRows(slot, 55, 24, actor > GOGO and {} or expectedLores(),
        string.format("%s slot %d lores", tag, slot))
    end
  end
  for _, s in ipairs(seen) do H.log("[dense] " .. tag .. " " .. s) end
end

local function walks(tag)
  for slot = 0, 3 do
    local actor = H.readByte(0x3ED8 + slot * 2)
    if actor < 0x10 and (H.readByte(0x3EE4 + slot * 2) & 0xC2) == 0 then
      if cmdRow(slot, CMD_MAGIC) then
        local want = expectedMagic(slot)
        if #want > 0 then
          local c = walk("magic", slot, want, tag)
          H.log(string.format("[dense] %s slot %d magic: %d cells walked, %d confirmed", tag, slot, #want, c))
        end
      end
      -- (and after each walk, the same test: a member petrified during its magic walk has no lore window)
      if cmdRow(slot, CMD_LORE) and (H.readByte(0x3EE4 + slot * 2) & 0xC2) == 0 then
        local want = expectedLores()
        local c = walk("lore", slot, want, tag)
        H.log(string.format("[dense] %s slot %d lore: %d rows walked, %d confirmed", tag, slot, #want, c))
      end
      if cmdRow(slot, CMD_RAGE) and (H.readByte(0x3EE4 + slot * 2) & 0xC2) == 0 then
        local want = expectedRages()
        H.assertEq(H.readByte(0x3A9A), #want, tag .. ": the rage count is the packed list's length")
        local c = walk("rage", slot, want, tag)
        H.log(string.format("[dense] %s slot %d rage: %d cells walked, %d confirmed", tag, slot, #want, c))
      end
    end
  end
end

-- into a random battle: the field's pace, or on the world map a pace
-- between the party's tile and a walkable neighbour
local function worldPace(tag)
  local A, B
  return H.driveUntil(function() return H.battleLoadStarted() end, 60000, {
    H.call(function()
      if A ~= nil then return end
      local x0, y0 = H.worldX(), H.worldY()
      -- a straight pace over tiles with random battles ($40) and no
      -- entrance on them: a town's tile has no $40, so a pace never walks in
      local function fights(x, y) return (H.worldTileProp(x, y) & 0x0050) == 0x0040 end
      for _, d in ipairs({ { 0, 1 }, { 1, 0 }, { 0, -1 }, { -1, 0 }, { 0, 2 }, { 2, 0 }, { 0, -2 }, { -2, 0 } }) do
        local ok = fights(x0, y0)
        local sx, sy = (d[1] > 0 and 1) or (d[1] < 0 and -1) or 0, (d[2] > 0 and 1) or (d[2] < 0 and -1) or 0
        for k = 1, math.abs(d[1]) + math.abs(d[2]) do ok = ok and fights(x0 + sx * k, y0 + sy * k) end
        if ok then A, B = { x0, y0 }, { x0 + d[1], y0 + d[2] }; break end
      end
      H.assertEq(A ~= nil, true, tag .. ": a walkable pace on the world map")
    end),
    H.worldNavTo(function() return B[1] end, function() return B[2] end,
      { maxFrames = 8000, arrive = function() return H.battleLoadStarted() end }),
    H.call(function() A, B = B, A end),
  }, tag .. ": a random battle on the world map")
end

local steps = { H.waitFrames(20) }
for _, f in ipairs(FIXTURES) do
  local co
  steps[#steps + 1] = H.loadState(f.state)
  steps[#steps + 1] = H.waitFrames(30)
  steps[#steps + 1] = H.cond(function() return H.worldMode() end, {
    H.waitUntil(function() return H.worldHasControl() end, 3000, f.tag .. ": world control", 5),
    worldPace(f.tag),
    H.release(),
    H.waitUntil(function() return H.battleActive() end, 1200, f.tag .. ": battle up", 2),
    H.waitFrames(30),
  }, { H.paceToEncounter(f.tag, 0) })
  steps[#steps + 1] = H.call(function() checkBattle(f.tag) end)
  steps[#steps + 1] = H.driveUntil(function() return co ~= nil and coroutine.status(co) == "dead" end, 200000, {
    H.call(function()
      if co == nil then co = coroutine.create(function() walks(f.tag) end) end
      local ok, pad = coroutine.resume(co)
      if not ok then error(pad, 0) end
      H.setPad(pad or {})
    end),
  }, f.tag .. ": the windows walked")
  steps[#steps + 1] = H.call(function()
    if stoneSeen[f.tag] then
      H.assertEq((upChecked[f.tag] or 0) >= 1, true, string.format("%s: the summon's Up was checked on a member "
        .. "wearing a stone (%d check(s); %d walk(s) ended by a lost control)", f.tag, upChecked[f.tag] or 0,
        lostMid[f.tag] or 0))
    end
  end)
  steps[#steps + 1] = H.release()
end

H.run({ maxFrames = 1500000 }, steps)
