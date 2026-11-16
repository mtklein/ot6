-- @suite slow
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
-- battle_densekits.lua -- MOG's Dance list and LOCKE's thief list are packed
-- (#541's sequel): each lists exactly what its owner knows, from the top,
-- with no blank cell in the middle, and neither cursor rests past the last
-- entry.
--
-- Played from water-rondo-v1 (cold Continue on the Blackjack's tile outside
-- Nikeah: LOCKE, EDGAR, SABIN and MOG): the party walks into a world-map
-- encounter.  There MOG knows three dances of eight (Wind Song, Water Rondo,
-- Dusk Requiem: vanilla cells 0, 5 and 6), and LOCKE five rows of eight
-- (Steal, Filch, Bestow and Mug down the left, Trickshot at the top of the
-- right).  EDGAR and SABIN pass their turns (X).
--
-- What is asserted:
--   * the Dance list ($267E, the window's own cells) is the dances known,
--     in id order, then empty; the window shows each row's two names on one
--     line;
--   * the thief list ($4005, the tools shell's cells) is the learned rows in
--     the table's order, down the left column and then the right, then
--     empty (the at-join three, then the story's rows as their event
--     switches say);
--   * on every listed cell of either window, each of Right and Down lands
--     on a listed cell, and on the last entry whenever vanilla's move would
--     have landed on an empty one; every frame either window is up, the
--     cursor is on a listed cell;
--   * the window's open moves a remembered cursor that points past a
--     shorter list onto its last entry before the window's first frame
--     (the open clamp; see the two synthetic arms);
--   * A on the Dance list's last cell stages that dance ($7A85) or buzzes.
-- Two SYNTHETIC arms (declared writes, state_write_waivers.txt): the story
-- never takes a row back, so LOCKE's list cannot lose a middle row or shrink
-- under his cursor in play.  With the thief list closed and its cursor on
-- Trickshot, Mug's event switch ($001E) is cleared: the list reopens as
-- Steal, Filch, Bestow, Trickshot down the left, the right column empty, and
-- the cursor (Trickshot's old cell, now past the end) is on Trickshot's new
-- one from the first frame.  MOG's Dance cursor is written to the last cell
-- (row 3, right) before his window reopens: it opens on his last dance.
-- Mutants (build/attempts/wt/v046-dense-2/): the ROM before the change, a
-- vanilla dance loop, the clamp returning at once, the open clamps removed.
local H = dofile("tools/tests/lib/ot6.lua")

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD, ST_TRANS, ST_DANCE, ST_TOOLS = 0x05, 0x01, 0x21, 0x30
local CMD_STEAL, CMD_DANCE = 0x05, 0x13
local LOCKE, MOG = 0x01, 0x0A
local DLIST, DCOL, DROW = 0x267E, 0x8937, 0x893B
local TLIST, TCOL, TROW = 0x4005, 0x8963, 0x8967
local KITMODE = 0x6168                  -- w7e6168: 3 = the thief list
local STAGED = 0x7A85
local L = { STEAL = 0x56, FILCH = 0x57, BESTOW = 0x58, MUG = 0xE0, TRICK = 0xE1, DIS = 0xE2, APP = 0xE3,
  MARK = 0xE4 }
local THIEF_ORDER = { L.STEAL, L.FILCH, L.BESTOW, L.MUG, L.TRICK, L.DIS, L.APP, L.MARK }
local MUG_SW = 0x001E
local DANCENAME = H.sym("DanceName") & 0x3FFFFF

local function st() return H.readByte(MSTATE) end
local function hx(t)
  local s = {}
  for _, v in ipairs(t) do s[#s + 1] = string.format("%02x", v) end
  return table.concat(s, " ")
end
local function slotOf(actor)
  for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == actor then return s end end
  return nil
end
local function cmdRow(slot, cmd)
  for r = 0, 3 do if H.readByte(0x202E + slot * 12 + r * 3) == cmd then return r end end
  return nil
end

-- the lists, expected from the save's own sources and read from the cells
local function expectedDances()
  local out, mask = {}, H.readByte(0x1D4C)
  for id = 0, 7 do if (mask >> id) & 1 == 1 then out[#out + 1] = id end end
  return out
end
-- the thief cells: the k-th learned row at cell (k % 4) * 2 + k // 4
local function expectedThief()
  local cells, k = {}, 0
  for _, id in ipairs(THIEF_ORDER) do
    if H.lockeKnows(id) then cells[(k % 4) * 2 + k // 4] = id; k = k + 1 end
  end
  return cells, k
end
local function danceCells()
  local t = {}
  for i = 0, 7 do t[#t + 1] = H.readByte(DLIST + i) end
  return t
end
local function thiefCells()
  local t = {}
  for i = 0, 7 do t[#t + 1] = H.readByte(TLIST + i * 3) end
  return t
end

-- per list: the cursor cells, the cell's entry, and the reading order (the
-- index of a cell in the list's order, and back)
local KIND = {
  dance = { st = ST_DANCE, cmd = CMD_DANCE, col = DCOL, row = DROW,
    entry = function(cell) return H.readByte(DLIST + cell) end,
    index = function(col, row) return row * 2 + col end,
    cellOf = function(i) return i end },
  thief = { st = ST_TOOLS, cmd = CMD_STEAL, col = TCOL, row = TROW,
    entry = function(cell) return H.readByte(TLIST + cell * 3) end,
    index = function(col, row) return col * 4 + row end,
    cellOf = function(i) return (i % 4) * 2 + i // 4 end },
}
local function up(k)
  return st() == k.st and (k ~= KIND.thief or H.readByte(KITMODE) == 3)
end
local function cursor(k, slot)
  local col, row = H.readByte(k.col + slot), H.readByte(k.row + slot)
  return col, row, row * 2 + col
end

-- ---------------------------------------------------------------- VRAM text
local VR = emu.memType.snesVideoRam
local LINES = { 0x7C20, 0x7C60, 0x7CA0, 0x7CE0, 0x7D20 }
local function lineBytes(line)
  local t = {}
  for c = 0, 31 do t[#t + 1] = emu.read((line + c) * 2, VR) end
  return t
end
local function findOn(bytes, pat)
  for c = 1, #bytes - #pat + 1 do
    local ok = true
    for j = 1, #pat do if bytes[c + j - 1] ~= pat[j] then ok = false; break end end
    if ok then return c end
  end
  return nil
end
local function danceName6(id)
  local t = {}
  for j = 0, 5 do t[#t + 1] = H.readRomByte(DANCENAME + 12 * id + j) end
  return t
end
-- row r of the Dance window shows `left` and then `right` (or no other
-- known dance's name after `left`) on one of the window's text lines
local function danceRowShown(left, right, known)
  for _, line in ipairs(LINES) do
    local b = lineBytes(line)
    local cl = findOn(b, danceName6(left))
    if cl then
      if right then
        local cr = findOn(b, danceName6(right))
        if cr and cr > cl then return true end
      else
        local other = false
        for _, id in ipairs(known) do
          if id ~= left then
            local c = findOn(b, danceName6(id))
            if c and c > cl then other = true end
          end
        end
        if not other then return true end
      end
    end
  end
  return false
end

-- ------------------------------------------------ the every-frame watch
-- while either window is up, the cursor is on a listed cell
local watch = { frames = 0, bad = 0, first = nil }
local function watchFrame()
  for name, k in pairs(KIND) do
    if up(k) and H.readByte(MENU) ~= 0 then
      local slot = H.readByte(ACTOR) & 3
      local col, row, cell = cursor(k, slot)
      local any = k.entry(k.cellOf(0)) ~= 0xFF
      watch.frames = watch.frames + 1
      if any and k.entry(cell) == 0xFF then
        watch.bad = watch.bad + 1
        watch.first = watch.first or string.format("f%d %s slot %d at col %d row %d (cell %d, empty)", H.frame,
          name, slot, col, row, cell)
      end
    end
  end
end

-- ------------------------------------------------------- the walk (coroutine)
local function frame(pad) coroutine.yield(pad or {}) end
local function idle(n) for _ = 1, n do frame({}) end end
local function press(btn) for _ = 1, 4 do frame({ [btn] = true }) end idle(10) end

-- bring up `slot`'s window for `k`; other members pass their turns
local function openWindow(k, slot, tag, onFirst)
  local row = cmdRow(slot, k.cmd)
  H.assertEq(row ~= nil, true, string.format("%s: slot %d's command list has command $%02X", tag, slot, k.cmd))
  for _ = 1, 20000 do
    local s = st()
    if H.readByte(MENU) ~= 0 and s ~= ST_TRANS then
      local act = H.readByte(ACTOR) & 3
      if act ~= slot then
        press(s == ST_CMD and "x" or "b")
      elseif up(k) then
        if onFirst then onFirst() end
        idle(30)
        return
      elseif s == ST_CMD then
        local cur = H.readByte(0x890F + slot) & 3
        if cur == row then
          -- A, then wait frame by frame for the window (onFirst reads its
          -- first frame)
          for _ = 1, 4 do frame({ a = true }) end
          for _ = 1, 60 do
            if up(k) then break end
            frame({})
          end
        else
          press(cur < row and "down" or "up")
        end
      else
        press("b")
      end
    else
      frame({})
    end
  end
  error(tag .. ": the window never came up", 0)
end
local function closeWindow(k)
  for _ = 1, 40 do
    if not up(k) then return end
    press("b")
  end
end

-- steer the cursor onto cell `want`, along the list's own order: the row
-- first in a list read across the rows (the Dance list), the column first in
-- one read down the columns (the thief list), so no step crosses an empty
-- cell short of the target (a step onto one lands on the last entry)
local function steerTo(k, slot, want, tag)
  local rowsFirst = k == KIND.dance
  for _ = 1, 24 do
    local col, row = cursor(k, slot)
    if col == want % 2 and row == want // 2 then return end
    if (rowsFirst and row ~= want // 2) or (not rowsFirst and col == want % 2) then
      press(row < want // 2 and "down" or "up")
    else
      press(col < want % 2 and "right" or "left")
    end
  end
  local col, row = cursor(k, slot)
  H.assertEq(row * 2 + col, want, tag .. ": the cursor reaches cell " .. want)
end

-- where vanilla's GetCursorInput takes a press: Right steps across a row and
-- wraps to the next one's left; Down steps down; the bottom row goes nowhere
local function vanillaMove(col, row, btn)
  if btn == "right" then
    if col == 0 then return 1, row end
    if row == 3 then return nil end
    return 0, row + 1
  end
  if row == 3 then return nil end
  return col, row + 1
end

-- every listed cell: its entry, then Right and Down from it
local function walkMoves(k, slot, want, n, tag)
  local last = k.cellOf(n - 1)
  for i = 0, n - 1 do
    local cell = k.cellOf(i)
    for _, btn in ipairs({ "right", "down" }) do
      steerTo(k, slot, cell, tag)
      H.assertEq(k.entry(cell), want[cell], string.format("%s: cell %d (entry %d) holds $%02X", tag, cell, i,
        want[cell]))
      local vc, vr = vanillaMove(cell % 2, cell // 2, btn)
      press(btn)
      local col, row, now = cursor(k, slot)
      H.assertEq(k.entry(now) ~= 0xFF, true, string.format("%s: %s from cell %d lands on a listed cell (col %d row %d)",
        tag, btn, cell, col, row))
      if vc ~= nil and k.entry(vr * 2 + vc) == 0xFF then
        H.assertEq(now, last, string.format("%s: %s from cell %d, onto empty cell %d, rests on the last entry "
          .. "(cell %d)", tag, btn, cell, vr * 2 + vc, last))
      elseif vc ~= nil then
        H.assertEq(now, vr * 2 + vc, string.format("%s: %s from cell %d lands on cell %d", tag, btn, cell, vr * 2 + vc))
      end
    end
  end
end

local function checkCells(got, want, what)
  local exp = {}
  for i = 0, 7 do exp[#exp + 1] = want[i] or 0xFF end
  H.log(string.format("[densekits] %s: cells %s", what, hx(got)))
  H.assertEq(hx(got), hx(exp), what .. ": the list's cells are the expected entries, packed, then empty")
end

local function thiefArm(slot)
  local k = KIND.thief
  local want, n = expectedThief()
  H.log(string.format("[densekits] LOCKE (slot %d) knows %d rows", slot, n))
  openWindow(k, slot, "thief")
  checkCells(thiefCells(), want, "thief")
  H.screenshot("battle_densekits_thief")
  walkMoves(k, slot, want, n, "thief")
  -- leave the cursor on the last row, then close the list
  steerTo(k, slot, k.cellOf(n - 1), "thief")
  local keepCol, keepRow = cursor(k, slot)
  closeWindow(k)
  -- SYNTHETIC: Mug's switch cleared, so the list loses a middle row (the
  -- story never does this; the reopen's packing and open clamp are the
  -- mechanism under test)
  H.assertEq(H.lockeKnows(L.MUG), true, "the synthetic arm needs Mug learned (its switch set)")
  H.assertEq(n >= 5, true, "the synthetic arm needs a row after Mug, so Mug is a middle row")
  local a = 0x1E80 + (MUG_SW >> 3)
  H.writeByte(a, H.readByte(a) & ~(1 << (MUG_SW & 7)) & 0xFF)
  local want2, n2 = expectedThief()
  H.assertEq(n2, n - 1, "Mug's switch cleared: one row fewer")
  local firstCol, firstRow
  openWindow(k, slot, "thief, Mug cleared", function()
    firstCol, firstRow = cursor(k, slot)
  end)
  checkCells(thiefCells(), want2, "thief, Mug cleared")
  H.screenshot("battle_densekits_thief_mugless")
  local lastCell = k.cellOf(n2 - 1)
  H.log(string.format("[densekits] thief reopened: the cursor left at col %d row %d (index %d of %d); first "
    .. "frame col %d row %d", keepCol, keepRow, k.index(keepCol, keepRow), n2, firstCol, firstRow))
  H.assertEq(k.index(keepCol, keepRow) >= n2, true,
    "the remembered cursor points past the shorter list (the open clamp's precondition)")
  H.assertEq(firstRow * 2 + firstCol, lastCell, string.format("the reopened list's first frame has the cursor on "
    .. "its last row (cell %d), not the remembered col %d row %d", lastCell, keepCol, keepRow))
  walkMoves(k, slot, want2, n2, "thief, Mug cleared")
  closeWindow(k)
end

local function danceArm(slot)
  local k = KIND.dance
  local ids = expectedDances()
  local want, n = {}, #ids
  for i, id in ipairs(ids) do want[i - 1] = id end
  H.log(string.format("[densekits] MOG (slot %d) knows %d dances: %s", slot, n, hx(ids)))
  H.assertEq(n >= 2 and n <= 7, true, "MOG knows some dances, not all eight (a list that can have a gap)")
  local gap = false
  for i, id in ipairs(ids) do if id ~= i - 1 then gap = true end end
  H.assertEq(gap, true, "MOG's dances are not 0..n-1 (vanilla's cells would show a gap)")
  openWindow(k, slot, "dance")
  checkCells(danceCells(), want, "dance")
  for r = 0, (n - 1) // 2 do
    H.assertEq(danceRowShown(want[2 * r], want[2 * r + 1], ids), true, string.format("dance: the window shows row %d "
      .. "as dance %d / %s", r, want[2 * r], want[2 * r + 1] and tostring(want[2 * r + 1]) or "blank"))
  end
  H.screenshot("battle_densekits_dance")
  walkMoves(k, slot, want, n, "dance")
  closeWindow(k)
  -- SYNTHETIC: the cursor written to the last cell (row 3, right), past the
  -- list, before the window reopens
  H.writeByte(DCOL + slot, 1)
  H.writeByte(DROW + slot, 3)
  local firstCol, firstRow
  openWindow(k, slot, "dance, cursor past the list", function()
    firstCol, firstRow = cursor(k, slot)
  end)
  H.assertEq(firstRow * 2 + firstCol, n - 1, string.format("the reopened Dance list's first frame has the cursor on "
    .. "its last dance (cell %d), not cell 7 (col %d row %d)", n - 1, firstCol, firstRow))
  -- A on the last cell stages its dance, or buzzes (a price the pool cannot pay)
  local before = H.readByte(STAGED)
  press("a")
  idle(8)
  if up(k) and (H.readByte(ACTOR) & 3) == slot then
    H.log(string.format("[densekits] dance: A on cell %d refused (greyed); nothing staged", n - 1))
  else
    H.assertEq(H.readByte(STAGED), want[n - 1], string.format("dance: A on cell %d stages dance %d (was %02x)", n - 1,
      want[n - 1], before))
  end
end

local function walks()
  local ls, ms = slotOf(LOCKE), slotOf(MOG)
  H.assertEq(ls ~= nil and ms ~= nil, true, "LOCKE and MOG are seated (water-rondo-v1's party)")
  thiefArm(ls)
  danceArm(ms)
end

-- ---- the world: walk two tiles until an encounter fires (battle_waterrondo's)
local W = nil
local function walkIn()
  local wp = 1
  return H.seqStep({
    H.call(function()
      local x, y = H.worldX(), H.worldY()
      for _, d in ipairs({ { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        if W == nil and H.worldPassable(x + d[1], y + d[2]) and H.worldPassable(x + 2 * d[1], y + 2 * d[2]) then
          W = { { x + 2 * d[1], y + 2 * d[2] }, { x + d[1], y + d[2] } }
        end
      end
      assert(W, "two walkable tiles in a line beside the save tile, away from Nikeah")
    end),
    H.driveUntil(function() return H.battleLoadStarted() end, 40000, {
      H.call(function()
        if H.battleLoadStarted() or not H.worldHasControl() or not H.worldAligned() then
          if not H.worldHasControl() then H.setPad({}) end
          return
        end
        local x, y = H.worldX(), H.worldY()
        if x == W[wp][1] and y == W[wp][2] then wp = wp % 2 + 1 end
        local tx, ty = W[wp][1], W[wp][2]
        local dir = tx > x and "right" or tx < x and "left" or ty > y and "down" or "up"
        H.setPad({ [dir] = true })
      end),
      H.waitFrames(1),
    }, "a world-map encounter fires"),
    H.release(),
    H.waitUntil(function() return H.battleActive() end, 1200, "battle armed", 5),
    H.waitFrames(30),
  })
end

local co
H.run({ maxFrames = 200000 }, {
  H.waitFrames(20),
  H.bootCheckpoint("water-rondo-v1"),
  walkIn(),
  H.driveUntil(function() return co ~= nil and coroutine.status(co) == "dead" end, 150000, {
    H.call(function()
      if co == nil then co = coroutine.create(walks) end
      watchFrame()
      local ok, pad = coroutine.resume(co)
      if not ok then error(pad, 0) end
      H.setPad(pad or {})
    end),
  }, "the two windows walked"),
  H.release(),
  H.call(function()
    H.log(string.format("[densekits] watch: %d window frames, %d with the cursor on an empty cell%s", watch.frames,
      watch.bad, watch.first and (" (first: " .. watch.first .. ")") or ""))
    H.assertEq(watch.bad, 0, "every frame either window is up, the cursor is on a listed cell")
  end),
})
