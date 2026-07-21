-- @suite
-- battle_blitzcursor.lua -- v0.3 Blitz-as-menu: it obeys Config>Cursor.
--
-- Vanilla's battle command lists (Magic, Tools, Item, ...) REMEMBER where the
-- cursor sat across a character's turns when Config>Cursor = MEMORY, and snap
-- back to the top when it = RESET.  The whole decision is made once per turn,
-- in the command-window-open state UpdateMenuState_04 (btlgfx_main.asm:13343):
-- it long-reads the config byte f:$001d4e and, when bit6 (#$40) is CLEAR
-- (Reset), stz-loops the entire 92-byte saved-cursor block $890f..$896a to
-- zero; when SET (Memory) it SKIPS that loop, so every list's saved cursor
-- survives.  Each list then loads its own per-slot saved cursor unconditionally
-- on open.  (Sense proven from that branch: set = keep = Memory.)
--
-- Blitz reuses the TOOLS shell, so its cursor lives in the Tools triple
-- ($895f scroll / $8963 col / $8967 row, indexed by the active slot $62ca) --
-- the very bytes UpdateMenuState_04 keeps-or-clears.  Ot6BlitzListOpen (ot6.asm)
-- used to zero that triple UNCONDITIONALLY on every open, which overrode the
-- shell's decision and made Blitz ALWAYS reset -- ignoring the setting.  That
-- was the owner's playtest bug; the fix deletes the reset and lets the shell's
-- gated clear stand.  This test drives the config bit BOTH ways and asserts on
-- the actual cursor RAM ($8967 row), never a screenshot.
--
--   * positive control: a poke normalizes the row to 0, then a real DOWN in the
--     open list moves it to 1 -- so the list under test is genuinely live and
--     navigable, not a dead window the asserts would pass against quietly.
--   * MEMORY (bit6 set):   after a fresh command-window-open the row is STILL 1
--     -- the moved position was remembered, exactly like Tools/Magic.
--   * RESET  (bit6 clear): after a fresh command-window-open the row is 0 --
--     the shell zeroed the triple and Blitz honored that.
-- The pair pins the bit sense: the OLD unconditional reset fails MEMORY (it
-- would read 0), and an inverted-sense fix fails one of the two.
--
-- The "fresh command-window-open" is forced by poking the menu-state index
-- $7bc2 = $04 (UpdateMenuStateTbl dispatches on it, btlgfx_main.asm:12545) and
-- then waiting for the command list ($05) to come back -- that re-runs
-- UpdateMenuState_04's gated clear exactly as a new turn would, without waiting
-- out an ATB.  Reaching $05 is asserted (driveUntil), so a poke that silently
-- did nothing cannot masquerade as a reopen.
--
-- Sabin is installed the way battle_blitzlist does it (every slot = CHAR::SABIN
-- with an all-Blitz command list); the known-blitz set is written directly.  We
-- learn FOUR blitzes ($0f) so the list fills a 2x2 grid and a DOWN has a row-1
-- cell to land on.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD, ST_TOOLS = 0x05, 0x30
local CMD_BLITZ = 0x0A
local CMDTBL, KNOWN = 0x202E, 0x1D28
local CONFIG, CURSOR_MEM = 0x1D4E, 0x40      -- $1d4e bit6: set = Memory, clear = Reset
local SCROLL, CUR_COL, CUR_ROW = 0x895F, 0x8963, 0x8967
local LEARNED = 0x0F                          -- Pummel/AuraBolt/Suplex/FireDance: a full 2x2

local PARTY = { 0, 1, 2 }
local wantMem = true                          -- current variant; re-applied every frame

-- Install a full-Blitz Sabin in every slot AND pin the config bit for the
-- variant under test, every frame -- enemies act between our steps, and a
-- savestate's own config byte must not leak in.
local function pin()
  H.writeByte(KNOWN, LEARNED)
  local c = H.readByte(CONFIG)
  if wantMem then c = c | CURSOR_MEM else c = c & (0xFF - CURSOR_MEM) end
  H.writeByte(CONFIG, c)
  for _, s in ipairs(PARTY) do
    H.writeByte(0x3ED8 + s * 2, 0x05)                 -- CHAR::SABIN
    local st1 = 0x3EE4 + s * 2
    H.writeByte(st1, H.readByte(st1) & 0xF7)          -- clear magitek
    for i = 0, 3 do H.writeByte(CMDTBL + s * 12 + i * 3, CMD_BLITZ) end
    H.writeWord(0x3BF4 + s * 2, 999)                  -- nobody dies mid-bench
  end
end

local slot                                    -- active slot, latched at the first menu

-- Mash A from the command list until the tools-shell (blitz) list shows ($30).
local function openBlitz(label)
  return H.driveUntil(function() return H.readByte(MSTATE) == ST_TOOLS end, 900, {
    H.call(function() pin(); H.setPad({ "a" }) end),
    H.waitFrames(2),
    H.call(function() H.setPad({}) end),
    H.waitFrames(14),
  }, label)
end

-- Force a fresh turn-start command window: poke the state index to $04 and wait
-- for the command list ($05) to reappear, PROVING UpdateMenuState_04 ran.  Wrap
-- the two steps as one composite (repeatN 1) so it splices into the top list.
local function forceCommandOpen(label)
  return H.repeatN(1, {
    H.call(function() pin(); H.setPad({}); H.writeByte(MSTATE, ST_CMD - 1) end),  -- $04
    H.driveUntil(function() return H.readByte(MSTATE) == ST_CMD end, 600, {
      H.call(pin), H.waitFrames(1),
    }, label),
  })
end

H.run({ maxFrames = 60000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.enterEncounter(),

  -- install Sabin (MEMORY variant first) until a menu belongs to somebody
  H.call(function() wantMem = true end),
  H.driveUntil(function() return H.readByte(MENU) ~= 0 end, 3000, {
    H.call(pin), H.waitFrames(1),
  }, "a battle menu opens"),
  H.call(function()
    slot = H.readByte(ACTOR)
    H.log(string.format("sabin in slot %d, known $%02x, config $%02x (memory)",
      slot, H.readByte(KNOWN), H.readByte(CONFIG)))
  end),

  -- open the blitz list, first time
  openBlitz("blitz list opens"),
  H.waitFrames(6),

  -- POSITIVE CONTROL: normalize the saved cursor to the top, then DOWN it.
  H.call(function()
    H.writeByte(SCROLL + slot, 0)
    H.writeByte(CUR_COL + slot, 0)
    H.writeByte(CUR_ROW + slot, 0)
  end),
  H.waitFrames(3),
  H.call(function()
    H.assertEq(H.readByte(CUR_ROW + slot), 0, "cursor normalized to the top row")
  end),
  H.call(function() pin(); H.setPad({ "down" }) end), H.waitFrames(4),
  H.call(function() pin(); H.setPad({}) end),         H.waitFrames(8),
  H.call(function()
    H.assertEq(H.readByte(CUR_ROW + slot), 1,
      "DOWN walked the blitz cursor off the top row -- the list is live")
  end),

  -- MEMORY: a fresh command-window-open must KEEP the moved row.
  forceCommandOpen("command window reopened, forced (memory)"),
  openBlitz("blitz reopens (memory)"),
  H.waitFrames(6),
  H.call(function()
    H.log(string.format("memory reopen: row=%d col=%d scroll=%d",
      H.readByte(CUR_ROW + slot), H.readByte(CUR_COL + slot), H.readByte(SCROLL + slot)))
    H.assertEq(H.readByte(CUR_ROW + slot), 1,
      "MEMORY: reopened blitz remembered the moved cursor (row 1)")
    H.screenshot("blitzcursor_memory")
  end),

  -- RESET: same starting row, bit cleared -> the fresh open snaps back to top.
  H.call(function() wantMem = false end),
  H.call(function()
    H.assertEq(H.readByte(CUR_ROW + slot), 1, "still on row 1 before the reset run")
  end),
  forceCommandOpen("command window reopened, forced (reset)"),
  openBlitz("blitz reopens (reset)"),
  H.waitFrames(6),
  H.call(function()
    H.log(string.format("reset reopen: row=%d col=%d scroll=%d, config $%02x",
      H.readByte(CUR_ROW + slot), H.readByte(CUR_COL + slot), H.readByte(SCROLL + slot),
      H.readByte(CONFIG)))
    H.assertEq(H.readByte(CUR_ROW + slot), 0,
      "RESET: reopened blitz snapped the cursor back to the top (row 0)")
    H.screenshot("blitzcursor_reset")
    H.log("PASSED: blitz honors Config>Cursor -- memory keeps row 1, reset zeroes it")
  end),
})
