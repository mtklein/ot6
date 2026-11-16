-- @suite slow
-- menu_densemagic.lua -- the field Skills > Magic page is packed (#541): it
-- lists exactly the spells the character can cast right now, in the Config's
-- Magic Order with a worn stone's or shield's spells in their places among
-- them, two to a row from the top, and the page scrolls only as far as the
-- list reaches.  The cursor never rests past the last spell.
--
-- Fixtures: fc_landing (TERRA wearing a stone, LOCKE and EDGAR wearing
-- theirs), then on the same save TERRA's stone swapped through the real
-- Skills > Espers walk (H.equipEsper) for another the party owns, and
-- wor_gogo (TERRA, STRAGO with his Analyze, RELM, and GOGO, whose page is the
-- union of the others').  Nothing is written.
--
-- Per character with a Magic page:
--   * the page's list ($7e9d89, the array its draw, its A and its MP line
--     read) is the expected spells in order and then $ff, the expected set
--     computed here (H.knowsSpell: the learned table, the worn stone, the
--     worn shields; STRAGO's Analyze; GOGO: the party's union);
--   * the scroll's top ($5c) is ceil(n/2) - 8, at least 0;
--   * the BG1 text the page shows: each on-screen row's two cells hold the
--     two spells' names (or blanks past the last);
--   * walking from the first cell with Right visits every spell in order
--     ($4b, the index the A and the description read, follows), and Right
--     and Down past the last spell move nothing, the scroll within the top.
-- Mutants: the v0.45 ROM (the page unpacked) fails the list check; a ROM
-- whose Ot6MagicClampDense returns at once fails the walk past the end.
local H = dofile("tools/tests/lib/ot6.lua")

local ZM, CUR = 0x26, 0x4B
local ST_MAIN, ST_CHAR, ST_SKILLS, ST_MAGIC = 0x05, 0x06, 0x0A, 0x1A
local LIST = 0x7E9D89
local MAGIC_ROW_COLOR = 0x7A            -- zSkillsTextColor::Magic (menu_ram.inc)
local BG1A = 0x3849                     -- wBG1Tiles::ScreenA (menu_ram.inc)
local STRAGO, GOGO, ANALYZE = 0x07, 0x0C, 0x18
local MAGICNAME = H.sym("MagicName") & 0x3FFFFF
local GENJUPROP = H.sym("GenjuProp") & 0x3FFFFF

local function st() return H.menuRunning() and H.readByte(ZM) or -1 end
local function hx(t)
  local s = {}
  for _, v in ipairs(t) do s[#s + 1] = string.format("%02x", v) end
  return table.concat(s, " ")
end

local GROUPS = { black = { 0x00, 0x17 }, effect = { 0x18, 0x2C }, white = { 0x2D, 0x35 } }
local ORDERS = {
  [0] = { "white", "black", "effect" }, [1] = { "white", "effect", "black" },
  [2] = { "black", "effect", "white" }, [3] = { "black", "white", "effect" },
  [4] = { "effect", "white", "black" }, [5] = { "effect", "black", "white" },
}
local function ordered(set)
  local out = {}
  for _, g in ipairs(ORDERS[H.readByte(0x1D54) & 0x07]) do
    for id = GROUPS[g][1], GROUPS[g][2] do if set[id] then out[#out + 1] = id end end
  end
  return out
end

-- the active party in menu order (its character-select rows)
local function activeParty() return H.readByte(0x1A6D) & 0x07 end
local function charAt(p)
  for c = 0, 15 do
    local pb = H.readByte(0x1850 + c)
    if (pb & 0x07) ~= 0 and (pb & 0x07) == activeParty() and ((pb >> 3) & 0x03) == p then return c end
  end
  return nil
end
local function ownSet(c)
  local set = {}
  if H.charActor(c) >= GOGO then return set end
  for id = 0, 0x35 do if H.knowsSpell(c, id) then set[id] = true end end
  if H.charActor(c) == STRAGO then set[ANALYZE] = true end
  return set
end
local function expected(c)
  if H.charActor(c) ~= GOGO then return ordered(ownSet(c)) end
  local set = {}
  for p = 0, 3 do
    local o = charAt(p)
    if o and o ~= c then for id in pairs(ownSet(o)) do set[id] = true end end
  end
  return ordered(set)
end

local function openMagic(p, tag)
  return H.seqStep({
    H.waitUntil(function() return H.hasControl() or (H.worldMode() and H.worldHasControl()) end, 3000,
      tag .. ": control", 5),
    H.driveUntil(function() return st() == ST_MAIN end, 1200,
      { H.pressButtons({ "x" }, 4), H.waitFrames(30) }, tag .. ": main menu"),
    H.waitFrames(20),
    H.driveUntil(function() return st() == ST_MAIN and H.readByte(CUR) == 1 end, 900,
      { H.pressButtons({ "down" }, 2), H.waitFrames(10) }, tag .. ": cursor on Skills"),
    H.pressButtons({ "a" }, 2),
    H.waitUntil(function() return st() == ST_CHAR end, 300, tag .. ": character select", 5),
    H.waitFrames(10),
    H.driveUntil(function() return st() == ST_CHAR and H.readByte(CUR) == p end, 600,
      { H.pressButtons({ "down" }, 2), H.waitFrames(10) }, tag .. ": cursor on the character"),
    H.pressButtons({ "a" }, 2),
    H.waitUntil(function() return st() == ST_SKILLS end, 300, tag .. ": skills submenu", 5),
    H.waitFrames(10),
    -- the Skills list offers Magic only to a character with the Magic
    -- command (GOGO without it: the row is grey and A refuses it)
    H.cond(function() return H.readByte(MAGIC_ROW_COLOR) == 0x20 end, {
      H.driveUntil(function() return st() == ST_SKILLS and H.readByte(CUR) == 1 end, 600,
        { H.pressButtons({ "down" }, 2), H.waitFrames(8) }, tag .. ": cursor on Magic"),
      H.pressButtons({ "a" }, 2),
      H.waitUntil(function() return st() == ST_MAGIC end, 500, tag .. ": the Magic page", 5),
      H.waitFrames(40),
    }, { H.call(function() H.log(string.format("[dense] %s: the Skills list offers no Magic page here", tag)) end) }),
  })
end
local function closeMenu(tag)
  return H.seqStep({
    H.driveUntil(function()
      if H.worldMode() then return st() ~= ST_MAGIC and H.worldHasControl() and H.worldSettled() end
      return H.hasControl() and not H.dialogWaiting()
    end, 1500, { H.pressButtons({ "b" }, 3), H.waitFrames(20) }, tag .. ": menu closed"),
    H.waitFrames(30),
  })
end

local function index() return (H.readByte(0x4A) + H.readByte(0x4E)) * 2 + H.readByte(0x4D) end

-- the BG1 text of on-screen row j (GetListTextPos: tilemap row 2($49+j)+1)
local function rowCells(j, col)
  local t = (((H.readByte(0x49) + j) * 2) + 1) & 0x1F
  local out = {}
  for k = 0, 6 do out[#out + 1] = H.readByte(BG1A + t * 64 + (col + k) * 2) end
  return out
end
local function nameOf(id)
  local out = {}
  for k = 0, 6 do out[#out + 1] = H.readRomByte(MAGICNAME + 7 * id + k) end
  return out
end
local BLANK = { 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF }

local function checkPage(c, tag)
  local want = expected(c)
  local n = #want
  local got = {}
  for i = 0, 53 do got[#got + 1] = H.readByte(LIST + i) end
  local exp = {}
  for i = 1, 54 do exp[i] = want[i] or 0xFF end
  H.log(string.format("[dense] %s: char %d (actor %02x) wants %d: %s", tag, c, H.charActor(c), n, hx(want)))
  H.assertEq(hx(got), hx(exp), tag .. ": the page's list is the expected spells, packed, then empty")
  local top = math.max(0, (n + 1) // 2 - 8)
  H.assertEq(H.readByte(0x5C), top, tag .. ": the page scrolls only as far as the list reaches")
  for j = 0, 7 do
    local i = (H.readByte(0x4A) + j) * 2
    H.assertEq(hx(rowCells(j, 3)), hx(i < n and nameOf(want[i + 1]) or BLANK),
      string.format("%s: on-screen row %d's left cell shows %s", tag, j, i < n and hx({ want[i + 1] }) or "nothing"))
    H.assertEq(hx(rowCells(j, 16)), hx(i + 1 < n and nameOf(want[i + 2]) or BLANK),
      string.format("%s: on-screen row %d's right cell shows %s", tag, j, i + 1 < n and hx({ want[i + 2] }) or "nothing"))
  end
  return want
end

local function walkPage(c, tag)
  local want, n = nil, 0
  local function edge(b) return { H.pressButtons({ b }, 2), H.waitFrames(8) } end
  return H.seqStep({
    H.call(function()
      want = checkPage(c, tag)
      n = #want
      H.screenshot("menu_densemagic_" .. tag)
    end),
    H.driveUntil(function() return index() == 0 end, 1200, edge("left"), tag .. ": the first cell"),
    H.driveUntil(function() return n <= 1 or index() == n - 1 end, 3000, {
      H.call(function()
        H.assertEq(index() < n, true, string.format("%s: the cursor on cell %d of %d", tag, index(), n))
        H.assertEq(H.readByte(CUR), index(), tag .. ": $4b, what A and the description read, is the cell")
      end),
      H.pressButtons({ "right" }, 2), H.waitFrames(8),
    }, tag .. ": every cell in order"),
    H.repeatN(6, {
      H.pressButtons({ "right" }, 2), H.waitFrames(8),
      H.pressButtons({ "down" }, 2), H.waitFrames(8),
      H.call(function()
        H.assertEq(index(), math.max(0, n - 1), tag .. ": Right and Down past the last spell stay on it")
        H.assertEq(H.readByte(0x4A) <= H.readByte(0x5C), true, tag .. ": the scroll within the top")
      end),
    }),
    H.call(function()
      H.screenshot("menu_densemagic_" .. tag .. "_end")
      H.log(string.format("[dense] %s: %d cells walked; past the end the cursor stayed on cell %d", tag, n, index()))
    end),
  })
end

-- the character at a row is resolved when the step is reached
local current
local function pageAt(p, tag)
  return H.seqStep({
    H.call(function() current = charAt(p) end),
    H.cond(function() return current ~= nil and #expected(current) > 0 end, {
      openMagic(p, tag),
      H.seqStep({ (function()
        local inner
        return { tick = function()
          if inner == nil then
            inner = (st() == ST_MAGIC) and walkPage(current, tag) or H.seqStep({})
          end
          return inner:tick()
        end, reset = function() if inner then inner:reset() end inner = nil end }
      end)() }),
      closeMenu(tag),
    }, { H.call(function()
      H.log(string.format("[dense] %s: %s", tag, current and ("char " .. current .. " has no spells; no page")
        or "no one at this row"))
    end) }),
  })
end

-- a stone the party owns that nobody wears, other than TERRA's
local swapTo
local function pickSwap()
  for e = 0, 26 do
    local owned = (H.readByte(0x1A69 + (e >> 3)) >> (e & 7)) & 1 == 1
    local worn = false
    for c = 0, 15 do if H.readByte(0x1600 + 37 * c + 0x1E) == e then worn = true end end
    if owned and not worn then return e end
  end
  return nil
end

-- a step built when it is first reached, from what the run has read by then
local function lazy(build)
  local s = nil
  return {
    tick = function()
      if s == nil then s = H.seqStep({ build() }) end
      return s:tick()
    end,
    reset = function() if s then s:reset() end; s = nil end,
  }
end
local function terraRow()
  for p = 0, 3 do if charAt(p) and H.charActor(charAt(p)) == 0 then return p end end
  error("TERRA is not in the active party", 0)
end

H.run({ maxFrames = 400000 }, {
  H.waitFrames(20),
  H.loadState("build/states/fc_landing.mss.lua"),
  H.waitFrames(30),
  pageAt(0, "stones_row0"), pageAt(1, "stones_row1"), pageAt(2, "stones_row2"), pageAt(3, "stones_row3"),
  H.call(function()
    swapTo = pickSwap()
    H.assertEq(swapTo ~= nil, true, "a stone the party owns and nobody wears")
    H.log(string.format("[dense] swapping TERRA's stone %02x for %02x", H.readByte(0x1600 + 0x1E), swapTo))
  end),
  lazy(function()
    return H.equipEsper(terraRow(), swapTo, { tag = "swap" })
  end),
  lazy(function() return pageAt(terraRow(), "swapped_terra") end),
  H.loadState("build/states/wor_gogo.mss.lua"),
  H.waitFrames(30),
  pageAt(0, "gogo_row0"), pageAt(1, "gogo_row1"), pageAt(2, "gogo_row2"), pageAt(3, "gogo_row3"),
})
