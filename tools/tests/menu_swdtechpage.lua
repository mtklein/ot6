-- @suite frontier=arvis_wake
-- menu_swdtechpage.lua -- issue #39: the field Skills->SwdTech page RENDERS.
--
-- The v0.5 loadout configurator (#8 Layer B) shipped with its pos_text labels
-- written as bare string literals in field_menu.asm.  menu_main.asm includes
-- ending_anim.asm BEFORE field_menu.asm, and ending_anim.asm installs the
-- ending-credits .charmap and never removes it -- so those literals assembled
-- to credits-font tiles, and (unlike menu_text_en.inc's encode pipeline) got
-- no $00 terminator, so every DrawPosText call streamed the ROM bytes that
-- follow the label into the BG1A tilemap until it happened upon a zero: the
-- whole page body became overlapping glyph soup.  menu_bushidoloadout stayed
-- green through all of it because it (a) force-jumps zMenuState to $7b from
-- the top menu instead of walking the player's path and (b) asserts only the
-- $1e1d word and menu state -- not one rendered cell.  This test closes BOTH
-- gaps:
--
--   * PATH: it drives the real UI -- X -> Skills -> character -> SwdTech row
--     -> A -- so SkillsOption_02 (field_menu.asm), not a forced state, opens
--     the configurator;
--   * RENDER: it asserts the BG1A tilemap shadow cell-by-cell: the title,
--     the 1x..3x labels, each slot's tech name, the " MP" cost suffix, the
--     LEARNED pool -- and, the class-closer, that the rows BETWEEN them are
--     still all-zero (a runaway unterminated draw can not leave them blank).
--
-- issue #38 refloored the page: every Bushido tech costs at least 1 BP, so the
-- 0x row is RETIRED and the window is three rows -- 1x/2x/3x at tilemap rows
-- 4/6/8.  The stored format did NOT move (the same packed word at $1e1d, four
-- 3-bit fields; word slot 0 is simply never read), so this test's install and
-- its AUTO word are unchanged.  Row 10 -- where the old 3x row drew -- joins
-- the blank-canary set: nothing may draw there any more, and a runaway draw
-- would still carpet it.
--
-- Fixture: arvis_wake (same boot as menu_bushidoloadout / menu_esperdetail).
-- Its lead has no Bushido command, so the SwdTech row is installed the house
-- "install state" way (menu_esperdetail pins esper bits the same way): the
-- lead's third battle-command byte becomes BUSHIDO, and $1cf7 = $07 -- the
-- natural learned set of the owner's scenario-band Cyan (Dispatch, Retort,
-- Slash; the LV14-era set from the #39 report), loadout word $0000 = AUTO.
-- With exactly 3 of 8 techs learned the ceiling is 2, so the three-rung auto
-- window (base = max(0, ceiling-2) = 0) draws Dispatch/Retort/Slash at
-- 1x/2x/3x -- every learned tech reachable, none duplicated -- and the pool
-- holds the same three names.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/arvis_wake.mss.lua"

local ZMENUSTATE, ZCURSOR = 0x26, 0x4b
local BUSHIDO_ROW_COLOR = 0x7b          -- zSkillsTextColor::Bushido
local CMD3 = 0x1618                     -- lead char's 3rd battle command
local LEARNED, LOADOUT = 0x1cf7, 0x1e1d
local BATTLE_CMD_BUSHIDO = 0x07
local ST_MAIN, ST_CHAR, ST_SKILLS, ST_LOADOUT = 0x05, 0x06, 0x0a, 0x7b

local function st() return H.readByte(ZMENUSTATE) end

-- BG1 screen A tilemap shadow (wBG1Tiles::ScreenA = $7e3849, menu_ram.inc):
-- 2 bytes per cell (char, color), 64 bytes per row; cell(x,y) = char byte.
local BG1A = 0x3849
local function cell(x, y) return H.readByte(BG1A + x * 2 + y * 64) end

-- menu text codec (ff6/tools/char_table/text_en.json): 'A'=$80.. 'a'=$9a..
-- '0'=$b4.. ' '=$ff.
local T = { B=0x81, U=0x94, S=0x92, H=0x87, I=0x88, D=0x83, O=0x8e, L=0x8b,
            A=0x80, T=0x93, E=0x84, R=0x91, N=0x8d, M=0x8c, P=0x8f, SP=0xff }
local TITLE = { T.B,T.U,T.S,T.H,T.I,T.D,T.O,T.SP,T.L,T.O,T.A,T.D,T.O,T.U,T.T }
local POOL  = { T.L,T.E,T.A,T.R,T.N,T.E,T.D }
local lo = { a=0x9a,c=0x9c,e=0x9e,h=0xa1,i=0xa2,l=0xa5,o=0xa8,p=0xa9,r=0xab,
             s=0xac,t=0xad,x=0xb1 }
local DISPATCH = { T.D,lo.i,lo.s,lo.p,lo.a,lo.t,lo.c,lo.h }
local RETORT   = { T.R,lo.e,lo.t,lo.o,lo.r,lo.t }
local SLASH    = { T.S,lo.l,lo.a,lo.s,lo.h }
local DIGIT0, DIGIT9 = 0xb4, 0xbd

local function assertRun(x0, y, bytes, what)
  for i, b in ipairs(bytes) do
    H.assertEq(cell(x0 + i - 1, y), b,
      string.format("%s: cell {%d,%d}", what, x0 + i - 1, y))
  end
end

-- The class-closer: a row the configurator never draws on must be untouched
-- ($00 from ClearBG1ScreenA).  Before the fix the runaway draws carpeted rows
-- 1..19 of BG1A with ROM code bytes, so every one of these failed.
local function assertRowBlank(y, what)
  for x = 0, 31 do
    H.assertEq(cell(x, y), 0, string.format("%s: cell {%d,%d} blank", what, x, y))
  end
end

-- One slot row: name at col 5, then a 1-digit MP cost at col 18 + " MP".
local function assertSlotRow(y, name, techname)
  assertRun(5, y, name, techname)
  local d = cell(18, y)
  H.assertEq(d >= DIGIT0 and d <= DIGIT9, true,
    string.format("%s: cost digit at {18,%d} (got %02x)", techname, y, d))
  assertRun(19, y, { T.SP, T.M, T.P }, techname .. " ' MP'")
end

H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.waitUntil(function() return H.hasControl() end, 400, "field control", 5),

  -- install state: SwdTech command on the lead + the scenario-band learned
  -- set (Dispatch/Retort/Slash), AUTO loadout word.
  H.call(function()
    H.writeByte(CMD3, BATTLE_CMD_BUSHIDO)
    H.writeByte(LEARNED, 0x07)
    H.writeByte(LOADOUT, 0)
    H.writeByte(LOADOUT + 1, 0)
  end),

  -- the player's path: X -> main menu -> Skills -> lead character -> submenu
  H.pressButtons({ "x" }, 4),
  H.waitUntil(function() return st() == ST_MAIN end, 600, "main menu", 5),
  H.waitFrames(20),
  H.pressButtons({ "down" }, 2),            -- Items -> Skills
  H.waitFrames(6),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_CHAR end, 300, "character select", 5),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_SKILLS end, 300, "skills submenu", 5),
  H.waitFrames(10),
  H.call(function()
    H.assertEq(H.readByte(BUSHIDO_ROW_COLOR), 0x20,
      "SwdTech row enabled (install-state command took)")
  end),

  -- cursor to the SwdTech row (row 2: Espers, Magic, SwdTech), A opens the
  -- configurator through SkillsOption_02 -- the exact edge no test drove.
  H.driveUntil(function()
    return st() == ST_SKILLS and H.readByte(ZCURSOR) == 2
  end, 600, { H.pressButtons({ "down" }, 2), H.waitFrames(6) },
    "skills cursor to SwdTech"),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_LOADOUT end, 300,
    "configurator open via the player path", 5),
  H.waitFrames(90),                         -- draws + DMA settle

  H.call(function()
    -- chrome
    assertRun(2, 1, TITLE, "title BUSHIDO LOADOUT")
    assertRun(2, 13, POOL, "LEARNED caption")
    assertRun(2, 4,  { 0xb5, lo.x }, "label 1x")
    assertRun(2, 6,  { 0xb6, lo.x }, "label 2x")
    assertRun(2, 8,  { 0xb7, lo.x }, "label 3x")
    -- #38: no 0x label anywhere on the page -- the retired rung must not be
    -- drawn at its old home (row 4) nor anywhere else in the label column.
    for _, y in ipairs({ 4, 6, 8, 10 }) do
      H.assertEq(cell(2, y) == 0xb4 and cell(3, y) == lo.x, false,
        string.format("no 0x label at row %d (#38 retired the free rung)", y))
    end
    -- the three boost slots: ceiling 2 -> base 0 -> Dispatch/Retort/Slash
    assertSlotRow(4, DISPATCH, "slot 1x Dispatch")
    assertSlotRow(6, RETORT,   "slot 2x Retort")
    assertSlotRow(8, SLASH,    "slot 3x Slash")
    -- the LEARNED pool: exactly the three learned names, left column
    assertRun(2, 15, DISPATCH, "pool Dispatch")
    assertRun(2, 17, RETORT,   "pool Retort")
    assertRun(2, 19, SLASH,    "pool Slash")
    H.assertEq(cell(2, 21), 0, "no 4th pool row (only 3 learned)")
    H.assertEq(cell(17, 15), 0, "right pool column empty (only 3 learned)")
    -- spray canaries: undrawn rows are still cleared
    assertRowBlank(0,  "row 0")
    assertRowBlank(3,  "row 3 (between labels)")
    assertRowBlank(10, "row 10 (#38: the retired 4th slot row)")
    assertRowBlank(12, "row 12 (above LEARNED)")
    -- and the title row past the title text
    for x = 17, 31 do
      H.assertEq(cell(x, 1), 0, string.format("title row tail blank {%d,1}", x))
    end
    H.screenshot("swdtech_page_player_path")
    H.log("PASSED: Skills->SwdTech via the player's path renders -- title, "
      .. "labels, slots, costs, pool correct; undrawn rows still blank")
  end),
})
