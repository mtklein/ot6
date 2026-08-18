-- @suite savestate=arvis_wake
-- menu_lorepage.lua -- issue #122: the field Skills->Lore loadout page (Strago)
-- renders.  MenuState_80 and Ot6Lore* (ot6_lore.asm, ot6_lore_page.asm) is the
-- Bushido page's single-column-of-five shape, with a per-row MP price (the
-- lore's own vanilla MagicProp cost) where the Rage/Bushido pages state one
-- flat number, because unlike a possess-verb, every lore prices differently.
--
-- The staging problem (and why this file writes state at all).  No savestate
-- in the fixture chain contains Strago: he joins in v0.13's unrouted stretch,
-- well past every state this tree can currently generate.  The owner's
-- ruling (menu_ragepage.lua's own precedent, issue #75's "instrumenting a
-- mechanism a person cannot produce on cue is not a claim about play") is
-- that a focused unit-style test may use write expedients to reach a page
-- that real play cannot reach yet.  So this test boots arvis_wake -- the
-- shallowest field savestate (Terra, alone, moments after the Whelk/esper
-- scene) -- and pokes Strago into the party by hand.
--
-- What got poked, and why it is MORE than the party byte alone.  The plan
-- going in was "just flip $1850+7 the way $1850+0 already reads"; Strago's
-- own $1600+37*7 character record was assumed to already carry New Game
-- defaults, on the theory that InitNewGame's global lore/rage bitfield init
-- (field/init.asm, the same file) would have a sibling that populates every
-- character's record regardless of party membership. Measured false: probed
-- directly, arvis_wake's $1600+37*7 reads all zero/$FF (actor=$FF, all four
-- commands $00), because a character's record is populated by the char_prop
-- event command at the moment their own recruitment scene runs
-- (event_main.asm has `char_prop STRAGO, STRAGO` deep in the Thamasa
-- content), and arvis_wake is nowhere near there. What IS already correct,
-- and does not need a poke, is $1D29-$1D2B (the party-wide learned-lore
-- bitfield): InitNewGame writes it unconditionally at New Game
-- (field/init.asm:150-162, from the InitLore table, {$88,$00,$10} ->
-- ids 3, 7, 20 in this build), so the page has real content to show from
-- the very first render without any bitfield poke.
--
-- So the record poke sources CharProp (field/char_prop.asm's CharProp table,
-- 22-byte records, the ROM template char_prop STRAGO,STRAGO copies from at
-- his real join) rather than fabricating stats: record 7 is read at runtime
-- and its command/stat bytes are copied into the save's $1600+37*7 layout
-- (field-ram.txt's own field offsets), so what lands in the save is the same
-- "New Game defaults" a real join would install, just installed early. This
-- is confirmed self-consistent rather than assumed: CharProp[7]'s second
-- command byte reads $0C, which is BATTLE_CMD::LORE (const.inc), so the
-- Skills list's Lore row gates white for the same reason a real Strago's
-- would.
--
-- Everything the PAGE itself reads ($1D29-$1D2B, OT6_LORELOAD, MagicProp,
-- AttackName) is either already correct on this save or is read fresh from
-- ROM at assertion time, so the render assertions below are not deriving
-- their expectation from the same poke that produced the fixture -- the
-- names and prices come from the ROM tables the drawing code itself reads,
-- exactly as menu_ragepage.lua and menu_thiefpage.lua do.
--
-- Party math, and the one dead end this test's first draft measured on the
-- way here.  field-ram.txt documents $1850+n as `verbbppp` (v=visible
-- e=enabled r=row bb=battle order ppp=party) and calls it the "master"
-- copy, so the first draft copied char 0's $1850 byte ($C1) straight to
-- $1850+7 before pressing X.  Measured false: OpenMenu (field/menu.asm)
-- calls PushCharFlags on entry, which REBUILDS $1850 from each character's
-- $0867+41*id "object settings" byte (obj.asm's PushCharFlags: new
-- $1850,y = ($0867,x & $e7) | (old $1850,y's battle-order bits)) -- so a
-- direct $1850 poke made before X is clobbered the instant the menu opens,
-- and InitCharProp (which builds zCharID) runs later in that same
-- open-menu sequence, so a poke made after detecting the menu is already
-- too late (zCharID is already built by then).  The real "master" copy
-- while the game is live is therefore $0867+41*id, not $1850 -- confirmed
-- by probing both addresses across the X-menu transition.  So this test
-- pokes Strago's field-object settings byte with Terra's (both come up
-- $C1: visible+enabled+order 0+party 1), and lets PushCharFlags derive
-- $1850+7 from it automatically, the same way it derives Terra's own.
-- InitCharProp (menu_init.asm) then rebuilds zCharID by scanning char ids
-- 0..15 in order and keeping the LAST id that matches a given (party,
-- order) pair, so this does not add a second party member: it replaces
-- Terra with Strago in the one HUD slot, which is exactly what a
-- single-character drive needs and keeps the poke to the minimum that
-- reaches the page.
--
-- Real content from the first render.  InitLore's three starting lores (ids
-- 3, 7, 20) are fewer than the five loadout slots, so AUTO's window fills
-- slots 0-2 and leaves 3-4 genuinely empty -- the shared "- EMPTY -" marker
-- (menu_ragepage.lua's Ot6RageEmptyTiles, reused verbatim by this page's own
-- @blank arm) is reachable on the very first open, with no isolation arm
-- needed the way the Rage page's InitRage floor (9 >= 8 slots) required one.
--
-- Geometry (ot6_lore_page.asm's own header table, and #43's cadence rule
-- shared by every field-menu configurator): this window shows only ODD
-- tilemap rows 1-15 whole; row 1 title, row 3 hint + Y=AUTO, rows 5/7/9/11/13
-- the five slots (name col 3, price "nn MP" col 16), row 15 LEARNED
-- (caption col 3, count col 11) sharing its row with the AUTO/MANUAL word
-- (col 16) -- unlike the Rage/Bushido pages, which give the mode its own
-- row, because this page's row budget is one slot tighter (5 slots + title +
-- hint + learned = 8 of the window's 8 odd rows, no row to spare).  The
-- cursor gutter (cursor_x = 8*col - 16) and the even-row/row>15 canary are
-- copied from menu_ragepage.lua's pattern, duplicated rather than shared per
-- that file's own note on lib/compose.py's fixed savestate-signature files.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/arvis_wake.mss.lua"

local ZMENUSTATE, ZCURSOR = 0x26, 0x4b
local ZCHARID = 0x69                    -- zCharID::Slot1..4 (menu_ram.inc)
-- zSkillsTextColor is a ram_scope (menu_ram.inc:189-200) with no exported
-- debug symbol per byte (H.sym errors on it -- probed directly).  Its order
-- is Genju,Magic,Bushido,Blitz,Lore,Rage,Dance,Thief; menu_ragepage.lua names
-- Rage (index 5) $7e and menu_thiefpage.lua names Thief (index 7) $80, both
-- consistent with one byte per index from a $79 base, so Lore (index 4) is
-- $7d.  Read, not written; if this address is wrong the gate assertion below
-- fails loudly with the actual byte rather than silently mis-testing.
local LORE_ROW_COLOR = 0x7d
local CHAR_STRAGO = 0x07                -- CHAR::STRAGO (const.inc)
local ST_MAIN, ST_CHAR, ST_SKILLS, ST_LORELOAD = 0x05, 0x06, 0x0a, 0x80
local SKILLS_ROW_LORE = 4               -- Espers Magic SwdTech Blitz LORE Rage Dance

local function st() return H.readByte(ZMENUSTATE) end

-- BG1 screen A tilemap shadow (wBG1Tiles::ScreenA = $7e3849, menu_ram.inc):
-- 2 bytes per cell (char, color), 64 bytes per row; cell(x,y) = char byte.
local BG1A = 0x3849
local function cell(x, y) return H.readByte(BG1A + x * 2 + y * 64) end

-- menu text codec (ff6/tools/char_table/text_en.json): 'A'=$80.. 'a'=$9a..
-- '0'=$b4.. ' '=$ff.  Identical table to menu_ragepage.lua/menu_thiefpage.lua
-- on purpose: this page's chrome strings need no character outside it.
local T = { A=0x80, C=0x82, D=0x83, E=0x84, G=0x86, H=0x87, L=0x8b, M=0x8c,
            N=0x8d, O=0x8e, P=0x8f, R=0x91, S=0x92, T=0x93, U=0x94, W=0x96,
            Y=0x98, DASH=0xc4, SLASH=0xc0, EQ=0xd2, SP=0xff }
local TITLE   = { T.L,T.O,T.R,T.E,T.SP,T.L,T.O,T.A,T.D,T.O,T.U,T.T } -- LORE LOADOUT
local LEARNED = { T.L,T.E,T.A,T.R,T.N,T.E,T.D }
local HINT    = { T.L,T.SLASH,T.R,T.SP,T.S,T.W,T.A,T.P,T.S }        -- L/R SWAPS
local MODE_AUTO   = { T.A,T.U,T.T,T.O,T.SP,T.SP }
local MODE_MANUAL = { T.M,T.A,T.N,T.U,T.A,T.L }
local MODE_HINT   = { T.Y,T.EQ,T.A,T.U,T.T,T.O }                    -- Y=AUTO
local EMPTY_TX = { T.DASH,T.SP,T.E,T.M,T.P,T.T,T.Y,T.SP,T.DASH,T.SP } -- "- EMPTY - "
local ZERO_CHAR = 0xb4
local MP_SUFFIX = { T.SP, T.M, T.P }
local PAD = 0xff

-- AttackName, read out of the ROM the drawing code reads (Ot6DrawLoreName ->
-- Ot6LoreNameBase := AttackName+58*ITEM_SIZE; lore id 0..23 -> record 58+id,
-- attack id $8b+id).
local ATKNAME = H.sym("AttackName") & 0x3FFFFF
local NAME_SIZE = 10                    -- AttackName::ITEM_SIZE
local LORE_REC0 = 58
local function nameBytes(id)
  local t = {}
  for i = 0, NAME_SIZE - 1 do t[i + 1] = H.readRomByte(ATKNAME + (LORE_REC0 + id) * NAME_SIZE + i) end
  return t
end
local function nameText(id)
  local s = ""
  for _, b in ipairs(nameBytes(id)) do
    if b == PAD then s = s .. "."
    elseif b >= 0x80 and b <= 0x99 then s = s .. string.char(65 + b - 0x80)
    elseif b >= 0x9a and b <= 0xb3 then s = s .. string.char(97 + b - 0x9a)
    else s = s .. "?" end
  end
  return s
end

-- MagicProp, the vanilla spell table Ot6LoreRowCost reads (spell id = lore
-- id + $8b; 14-byte records; +5 is the MP cost -- ot6_lore.asm's own
-- arithmetic, mirrored here rather than trusted).
local MAGICPROP = H.sym("MagicProp") & 0x3FFFFF
local MAGICPROP_REC = 14
local function loreCost(id) return H.readRomByte(MAGICPROP + (id + 0x8b) * MAGICPROP_REC + 5) end

-- CharProp, the ROM "New Game defaults" template char_prop STRAGO,STRAGO
-- copies from at his real join (field/char_prop.asm).  22-byte records:
-- hp,mp,cmd1..4,str,agi,stam,magpwr,batpwr,def,magdef,evade,mblock,
-- weapon,shield,helmet,armor,relic1,relic2,run|level|fixed.
local CHARPROP = H.sym("CharProp") & 0x3FFFFF
local CHARPROP_REC = 22
local STRAGO_REC = CHARPROP + CHAR_STRAGO * CHARPROP_REC
local BATTLE_CMD_LORE = 0x0c            -- const.inc BATTLE_CMD::LORE

-- ---- page geometry, mirroring ot6_lore_page.asm's own header table ----
local TITLE_ROW, HINT_ROW, LEARNED_ROW = 1, 3, 15
local LEFT_COL, COST_COL = 3, 16
local COUNT_COL = 11                    -- just past "LEARNED " at 3..9
local MODE_HINT_COL = 16                -- shares row 3 with the hint's own text
local MODE_ROW, MODE_COL = 15, 16       -- shares row 15 with LEARNED's count
local NSLOTS = 5
local function slotRow(slot) return 5 + slot * 2 end   -- odd rows 5/7/9/11/13

local function assertRun(x0, y, bytes, what)
  for i, b in ipairs(bytes) do
    H.assertEq(cell(x0 + i - 1, y), b,
      string.format("%s: cell {%d,%d}", what, x0 + i - 1, y))
  end
end

local function assertRowBlank(y, what)
  for x = 0, 31 do
    H.assertEq(cell(x, y), 0, string.format("%s: cell {%d,%d} blank", what, x, y))
  end
end

-- The cursor gutter canary (#43 round 3), menu_ragepage.lua's shape, single
-- column: entry n's sprite reserves tilemap columns cx/8, cx/8+1 and slot n's
-- text must start at column cx/8+2 (vanilla: cursor_x = 8*col - 16).
local CURSOR_POS = H.sym("Ot6LoreCursorPos") & 0x3FFFFF
local function cursorEntry(n)
  return H.readRomByte(CURSOR_POS + n * 2), H.readRomByte(CURSOR_POS + n * 2 + 1)
end
local function assertCursorGutter(n, what)
  local cx, cy = cursorEntry(n)
  local col, y = cx // 8, (cy - 116) // 6 + 1
  H.assertEq(y % 2 == 1 and y >= 1 and y <= 15, true, string.format(
    "%s: cursor entry %d (y=%d) points at tilemap row %d, which this window "
    .. "does not show whole", what, n, cy, y))
  H.assertEq(y, slotRow(n), string.format(
    "%s: cursor entry %d must point at slot %d's row", what, n, n))
  for _, x in ipairs({ col, col + 1 }) do
    H.assertEq(cell(x, y), 0, string.format(
      "%s: cursor entry %d sits at x=%d, so tilemap {%d,%d} is under the "
      .. "sprite and must be blank", what, n, cx, x, y))
  end
  H.assertEq(cell(col + 2, y) ~= 0, true, string.format(
    "%s: cursor entry %d at x=%d reserves columns %d-%d, so slot %d must start "
    .. "at column %d (vanilla: cursor_x = 8*col - 16)",
    what, n, cx, col, col + 1, n, col + 2))
  H.assertEq(col + 2, LEFT_COL, string.format(
    "%s: cursor entry %d and slot %d's draw column must agree", what, n, n))
  for x = 0, col + 1 do
    H.assertEq(cell(x, y), 0, string.format(
      "%s: {%d,%d} is left of the cursored row's first glyph (column %d)",
      what, x, y, col + 2))
  end
end

local function assertModeBlock(auto, what)
  H.assertEq(#MODE_AUTO, #MODE_MANUAL,
    "the two mode words must be the same width, or a MANUAL -> AUTO revert "
    .. "leaves the tail of MANUAL on screen")
  assertRun(MODE_COL, MODE_ROW, auto and MODE_AUTO or MODE_MANUAL,
    string.format("%s: the page states %s", what, auto and "AUTO" or "MANUAL"))
end

local function assertFilledRow(slot, id)
  local y = slotRow(slot)
  assertRun(LEFT_COL, y, nameBytes(id),
    string.format("slot %d name %s", slot, nameText(id)))
  local cost = loreCost(id)
  local tens = cost // 10
  H.assertEq(cell(COST_COL, y), tens > 0 and (ZERO_CHAR + tens) or PAD,
    string.format("slot %d (%s) cost %d MP: tens cell {%d,%d}",
      slot, nameText(id), cost, COST_COL, y))
  H.assertEq(cell(COST_COL + 1, y), ZERO_CHAR + (cost % 10),
    string.format("slot %d cost %d: ones cell {%d,%d}", slot, cost, COST_COL + 1, y))
  assertRun(COST_COL + 2, y, MP_SUFFIX, string.format("slot %d ' MP'", slot))
end

-- An unset slot: "- EMPTY - " over the name field, and the price field
-- blanked to PAD ($ff) x5 rather than left as whatever the last redraw put
-- there (Ot6LoreBlankCost -- the overwrite property every one of these
-- pages relies on).
local function assertEmptyRow(slot)
  local y = slotRow(slot)
  H.assertEq(#EMPTY_TX, NAME_SIZE,
    "the empty marker must be exactly a name field wide")
  assertRun(LEFT_COL, y, EMPTY_TX, string.format("empty slot %d '- EMPTY -'", slot))
  for i = 0, 4 do
    H.assertEq(cell(COST_COL + i, y), PAD,
      string.format("empty slot %d: blanked price cell {%d,%d}", slot, COST_COL + i, y))
  end
end

-- The full chrome + geometry sweep.  win[1..5] = the id each slot shows, or
-- nil for empty; nKnown = the LEARNED count (the whole bitfield, not the
-- slots -- InitLore's floor is 3, below 5, so this is never masked by the
-- window the way the Rage page's 9-known/8-slot floor is on its first open).
local function assertPage(win, nKnown, what)
  assertRun(LEFT_COL, TITLE_ROW, TITLE, what .. ": title LORE LOADOUT")
  assertRun(LEFT_COL, HINT_ROW, HINT, what .. ": L/R SWAPS control hint")
  assertRun(MODE_HINT_COL, HINT_ROW, MODE_HINT, what .. ": Y=AUTO revert control")
  assertRun(LEFT_COL, LEARNED_ROW, LEARNED, what .. ": LEARNED caption")
  assertRun(COUNT_COL, LEARNED_ROW,
    { ZERO_CHAR + (nKnown // 10) % 10, ZERO_CHAR + (nKnown % 10) },
    string.format("%s: LEARNED count = %02d", what, nKnown))

  for slot = 0, NSLOTS - 1 do
    if win[slot + 1] then assertFilledRow(slot, win[slot + 1])
    else assertEmptyRow(slot) end
  end

  -- The even-row / past-row-15 canary (#43's cadence rule): this window
  -- shows only odd rows 1-15 whole, and this page uses every one of them
  -- (title, hint, five slots, learned+mode) with none to spare.
  for y = 0, 27 do
    if y % 2 == 0 or y > 15 then
      assertRowBlank(y, string.format(
        "%s: row %d is unusable (%s) and must stay blank", what, y,
        y > 15 and "outside the window" or "even: unshown scanlines"))
    end
  end
  -- title row: head (cursor gutter) and tail past "LORE LOADOUT" (3..14)
  for _, x in ipairs({ 0, 1, 2 }) do
    H.assertEq(cell(x, TITLE_ROW), 0,
      string.format("%s: {%d,%d} is the cursor gutter", what, x, TITLE_ROW))
  end
  for x = LEFT_COL + #TITLE, 31 do
    H.assertEq(cell(x, TITLE_ROW), 0,
      string.format("%s: title row tail blank {%d,%d}", what, x, TITLE_ROW))
  end
  -- hint row: head, the gap between the hint and Y=AUTO, and the tail
  for _, x in ipairs({ 0, 1, 2 }) do
    H.assertEq(cell(x, HINT_ROW), 0,
      string.format("%s: {%d,%d} is the cursor gutter", what, x, HINT_ROW))
  end
  for x = LEFT_COL + #HINT, MODE_HINT_COL - 1 do
    H.assertEq(cell(x, HINT_ROW), 0,
      string.format("%s: hint/Y=AUTO gap blank {%d,%d}", what, x, HINT_ROW))
  end
  for x = MODE_HINT_COL + #MODE_HINT, 31 do
    H.assertEq(cell(x, HINT_ROW), 0,
      string.format("%s: hint row tail blank {%d,%d}", what, x, HINT_ROW))
  end
  -- each slot row: head, the name/price gap, and the tail past the price
  for slot = 0, NSLOTS - 1 do
    local y = slotRow(slot)
    for _, x in ipairs({ 0, 1, 2 }) do
      H.assertEq(cell(x, y), 0, string.format(
        "%s: {%d,%d} is the cursor gutter", what, x, y))
    end
    for x = LEFT_COL + NAME_SIZE, COST_COL - 1 do
      H.assertEq(cell(x, y), 0, string.format(
        "%s: slot %d name/price gap blank {%d,%d}", what, slot, x, y))
    end
    for x = COST_COL + 5, 31 do
      H.assertEq(cell(x, y), 0, string.format(
        "%s: slot %d row tail blank {%d,%d}", what, slot, x, y))
    end
  end
  -- LEARNED/mode row: head, LEARNED/count gap, count/mode gap, tail
  for _, x in ipairs({ 0, 1, 2 }) do
    H.assertEq(cell(x, LEARNED_ROW), 0,
      string.format("%s: {%d,%d} is the cursor gutter", what, x, LEARNED_ROW))
  end
  for x = LEFT_COL + #LEARNED, COUNT_COL - 1 do
    H.assertEq(cell(x, LEARNED_ROW), 0, string.format(
      "%s: LEARNED/count gap blank {%d,%d}", what, x, LEARNED_ROW))
  end
  for x = COUNT_COL + 2, MODE_COL - 1 do
    H.assertEq(cell(x, LEARNED_ROW), 0, string.format(
      "%s: count/mode gap blank {%d,%d}", what, x, LEARNED_ROW))
  end
  for x = MODE_COL + #MODE_AUTO, 31 do
    H.assertEq(cell(x, LEARNED_ROW), 0, string.format(
      "%s: LEARNED row tail blank {%d,%d}", what, x, LEARNED_ROW))
  end
  -- the cursor gutter canary, on every slot
  for n = 0, NSLOTS - 1 do assertCursorGutter(n, what) end
end

-- KNOWN: the save's own learned-lore ids, ascending -- derived at boot, not
-- assumed, per the same discipline menu_ragepage.lua's KNOWN uses.
local KNOWN = {}

H.run({ maxFrames = 40000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.waitUntil(function() return H.worldHasControl() or H.hasControl() end,
    600, "control on the world map", 5),

  -- ==================================================================== --
  -- The pokes.  Every write here is one of the two kinds check_state_writes
  -- wants declared: (1) the party-byte copy that stands Strago up as the
  -- only reachable member of arvis_wake's one-person party, and (2) the
  -- character-record fields CharProp's own ROM template supplies for him,
  -- sourced from ROM rather than fabricated (see header).  Nothing here
  -- touches $1D29-$1D2B (the lore bitfield) or OT6_LORELOAD (the loadout):
  -- both are already what a real save carries, and the page's own render is
  -- checked against them, not against anything this block wrote.
  -- ==================================================================== --
  H.call(function()
    local leadChar, leadByte = nil, nil
    for c = 0, 15 do
      local b = H.readByte(0x1850 + c)
      if (b & 0x07) ~= 0 and leadChar == nil then leadChar, leadByte = c, b end
    end
    H.assertEq(leadChar ~= nil, true, "arvis_wake's party is not empty")
    H.log(string.format("lead character = %d, $1850 byte = $%02X", leadChar, leadByte))

    -- (1) field-object settings byte ($0867 + 41*id, obj.asm's PushCharFlags
    -- stride): the real "master" copy while the field is live (see header).
    -- Strago takes over the lead's (party, order) bits; $1850+7 is left for
    -- PushCharFlags to derive when the X menu opens.
    local leadObj = H.readByte(0x0867 + 41 * leadChar)
    H.writeByte(0x0867 + 41 * CHAR_STRAGO, leadObj)

    -- (2) character record: CharProp[STRAGO]'s own bytes, at their real
    -- $1600+37*7 field offsets (field-ram.txt).
    local base = 0x1600 + 37 * CHAR_STRAGO
    H.writeByte(base + 0x00, CHAR_STRAGO)          -- actor
    local NAME = { 0x92, 0x93, 0x91, 0x80, 0x86, 0x8e } -- S T R A G O
    for i = 0, 5 do H.writeByte(base + 0x02 + i, NAME[i + 1]) end
    H.writeByte(base + 0x08, 1)                    -- level
    local hp = H.readRomByte(STRAGO_REC + 0)
    local mp = H.readRomByte(STRAGO_REC + 1)
    H.writeWord(base + 0x09, hp)                   -- current HP
    H.writeWord(base + 0x0B, hp)                   -- max HP (boost bits 0)
    H.writeWord(base + 0x0D, mp)                   -- current MP
    H.writeWord(base + 0x0F, mp)                   -- max MP (boost bits 0)
    for i = 0, 3 do
      H.writeByte(base + 0x16 + i, H.readRomByte(STRAGO_REC + 2 + i))   -- commands
    end
    for i = 0, 3 do
      H.writeByte(base + 0x1A + i, H.readRomByte(STRAGO_REC + 6 + i))   -- vigor..magpwr
    end
    -- $161E (esper) is already $FF ("no esper") from InitNewGame's clear
    -- pass; left untouched.
    for i = 0, 3 do
      H.writeByte(base + 0x1F + i, H.readRomByte(STRAGO_REC + 15 + i))  -- weapon..armor
    end
    for i = 0, 1 do
      H.writeByte(base + 0x23 + i, H.readRomByte(STRAGO_REC + 19 + i))  -- relics
    end

    H.assertEq(H.readRomByte(STRAGO_REC + 3), BATTLE_CMD_LORE,
      "CharProp[STRAGO]'s second command is BATTLE_CMD::LORE -- the poked "
      .. "record's gate to the Skills list's Lore row comes from the ROM's "
      .. "own New Game template, not a hardcoded byte")
  end),

  -- derive KNOWN from the save's own (unpoked) bitfield
  H.call(function()
    for id = 0, 23 do
      if (H.readByte(0x1d29 + (id >> 3)) >> (id & 7)) & 1 == 1 then
        KNOWN[#KNOWN + 1] = id
      end
    end
    local names = {}
    for _, id in ipairs(KNOWN) do names[#names + 1] = id .. ":" .. nameText(id) end
    H.log(string.format("$1d29-$1d2b as saved (InitLore, unpoked): %d lores -- %s",
      #KNOWN, table.concat(names, " ")))
    H.assertEq(#KNOWN > 0 and #KNOWN < NSLOTS, true,
      "InitLore grants three starting lores in this build -- fewer than the "
      .. "five slots, so this test's first render exercises both a filled "
      .. "and an empty row with no isolation arm needed")
    for i = 0, NSLOTS - 1 do
      H.assertEq(H.readByte(0x1e27 + i), 0,
        string.format("OT6_LORELOAD+%d is $00 as saved -- AUTO needs no zeroing", i))
    end
  end),

  -- the player's path: X -> main menu -> Skills -> STRAGO -> the Lore row -> A.
  H.driveUntil(function() return st() == ST_MAIN end, 1200,
    { H.pressButtons({ "x" }, 4), H.waitFrames(30) }, "main menu"),
  H.waitFrames(20),
  H.call(function()
    local ids = {}
    for s = 0, 3 do
      ids[#ids + 1] = string.format("slot %d = char $%02x", s, H.readByte(ZCHARID + s))
    end
    H.log("party: " .. table.concat(ids, ", "))
    H.assertEq(H.readByte(ZCHARID + 0), CHAR_STRAGO,
      "the poked party byte put STRAGO in the one HUD slot (replacing Terra, "
      .. "who shared the same party/order bits)")
  end),
  H.pressButtons({ "down" }, 2),            -- Items -> Skills
  H.waitFrames(6),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_CHAR end, 300, "character select", 5),
  H.waitFrames(10),
  H.driveUntil(function() return H.readByte(ZCURSOR) == 0 end, 900,
    { H.pressButtons({ "down" }, 2), H.waitFrames(8) }, "cursor onto STRAGO"),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_SKILLS end, 300, "skills submenu", 5),
  H.waitFrames(10),
  H.call(function()
    local color = H.readByte(LORE_ROW_COLOR)
    if color ~= 0x20 then
      H.screenshot("lorepage_grey_gate_STOP")
      error(string.format(
        "Lore row is NOT white for STRAGO (zSkillsTextColor::Lore = $%02X, "
        .. "want $20).  Per the task's instruction this is a STOP: capture "
        .. "the evidence and report rather than forcing zMenuState.  "
        .. "Screenshot: lorepage_grey_gate_STOP", color), 0)
    end
    H.assertEq(color, 0x20,
      "Lore row enabled -- the poked record carries BATTLE_CMD::LORE")
  end),

  -- cursor down to the Lore row, A opens the configurator through
  -- SkillsOption_04, the edge no test had driven before.
  H.driveUntil(function()
    return st() == ST_SKILLS and H.readByte(ZCURSOR) == SKILLS_ROW_LORE
  end, 900, { H.pressButtons({ "down" }, 2), H.waitFrames(6) },
    "skills cursor to Lore"),
  H.pressButtons({ "a" }, 2),
  H.waitUntil(function() return st() == ST_LORELOAD end, 300,
    "lore configurator open via the player path", 5),
  H.waitFrames(90),                         -- draws + DMA settle

  -- ---- the full page a real (if hand-installed) Strago opens: AUTO's
  -- window = KNOWN[1..3], slots 3-4 genuinely empty ----
  H.call(function()
    local win = {}
    for s = 1, #KNOWN do win[s] = KNOWN[s] end
    assertPage(win, #KNOWN, "AUTO, opened untouched")
    -- opening the page writes nothing: AUTO is computed per slot on the fly
    -- (Ot6LoreShow), so an un-edited page leaves every loadout byte at zero.
    for i = 0, NSLOTS - 1 do
      H.assertEq(H.readByte(0x1e27 + i), 0,
        string.format("opening the page did not seed OT6_LORELOAD+%d", i))
    end
    assertModeBlock(true, "opened untouched")
    H.screenshot("lorepage_player_path")
    H.log("RENDER OK: Skills->Lore via the player's path for a (hand-staged) "
      .. "STRAGO -- title, three filled slots against AttackName/MagicProp "
      .. "verbatim, two genuinely-empty slots (InitLore's three lores is "
      .. "below the five-slot floor), LEARNED counting the whole bitfield; "
      .. "nothing on an even row, nothing past row 15, nothing in the "
      .. "cursor gutter")
  end),

  -- ---- one L/R cycle: goes MANUAL, the cursored slot's name moves on ----
  H.pressButtons({ "r" }, 3),
  H.waitFrames(40),
  H.call(function()
    -- Ot6LoreSeed freezes the AUTO window (KNOWN[1..3] into slots 0-2,
    -- slots 3-4 stay $00 -- the window ran out before reaching them), then
    -- the cycle walks the cursored slot (0) from its current id to the next
    -- learned one.
    H.assertEq(H.readByte(0x1e27 + 0), KNOWN[2] + 1,
      "R cycled slot 0 to the next learned lore (stored byte = id + 1)")
    for i = 2, #KNOWN do
      H.assertEq(H.readByte(0x1e27 + i - 1), KNOWN[i] + 1,
        string.format("the first edit froze AUTO's window into slot %d", i - 1))
    end
    for i = #KNOWN, NSLOTS - 1 do
      H.assertEq(H.readByte(0x1e27 + i), 0,
        string.format("slot %d had no AUTO window entry to freeze, stays unset", i))
    end
    assertFilledRow(0, KNOWN[2])
    for slot = #KNOWN, NSLOTS - 1 do assertEmptyRow(slot) end
    assertModeBlock(false, "after the first edit")
    H.assertEq(H.readByte(ZMENUSTATE), ST_LORELOAD, "still on the lore page")
    H.screenshot("lorepage_after_cycle")
    H.log("LIVE: R redrew slot 0 as '" .. nameText(KNOWN[2])
      .. "', the first edit froze the AUTO window into the loadout bytes, and "
      .. "the mode indicator followed it from AUTO to MANUAL in the same frame")
  end),

  -- ---- Y reverts, and the indicator comes back with it ----
  H.pressButtons({ "y" }, 3),
  H.waitFrames(40),
  H.call(function()
    for i = 0, NSLOTS - 1 do
      H.assertEq(H.readByte(0x1e27 + i), 0,
        string.format("Y cleared OT6_LORELOAD+%d: the loadout is AUTO again", i))
    end
    assertModeBlock(true, "after Y")
    local win = {}
    for s = 1, #KNOWN do win[s] = KNOWN[s] end
    for slot = 0, NSLOTS - 1 do
      if win[slot + 1] then assertFilledRow(slot, win[slot + 1])
      else assertEmptyRow(slot) end
    end
    H.screenshot("lorepage_reverted")
    H.log("REVERT: Y put the page back on AUTO -- the five bytes are zero, "
      .. "the window is recomputed, and 'MANUAL' left nothing of itself "
      .. "behind in the six-cell field")
  end),
})
