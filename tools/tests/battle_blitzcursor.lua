-- @suite savestate=vargas_won slow
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
-- the actual cursor RAM, never a screenshot.
--
-- ISSUE #75 CONVERSION -- every input is the game's own.  The old file poked
-- the config byte every frame, installed a synthetic four-Blitz Sabin,
-- normalized the cursor triple by writing it, and forced the "fresh
-- command-window open" by writing the menu-state index $7bc2.  All four
-- stagings are gone:
--   * the CONFIG BIT is set in the REAL field Config menu (main menu ->
--     Config -> the Cursor row -> dpad; ChangeConfigOption_06, config.asm:
--     Right = tsb $40 = Memory, Left = trb = Reset), gated on reading
--     $1d4e back -- and flipped BETWEEN battles, because that is the only
--     place a player can flip it;
--   * SABIN is the real one (vargas_won), his real two-blitz list -- a
--     1x2 grid, so the MOVED coordinate is the COLUMN, not the row;
--   * the normalize is a d-pad walk verified by re-reading the cell;
--   * the "fresh open" is SABIN'S NEXT TURN: he commits a real Defend, the
--     bystanders take their turns, and his next command window runs
--     UpdateMenuState_04's gated clear exactly as every turn does.
-- A measured consequence reshaped the phases: battle RAM is reinitialized
-- per battle, so a NEW battle's cursor says nothing about the setting --
-- each variant must prove itself WITHIN one battle.  Hence: battle 1 under
-- MEMORY (moved column survives a fresh open), flee, flip to Reset in the
-- field, battle 2 under RESET (moved column snaps back).  The pair still
-- pins the bit sense: the old unconditional reset fails MEMORY, an
-- inverted-sense fix fails one of the two.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/vargas_won.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD, ST_TOOLS, ST_TGT = 0x05, 0x30, 0x38
local CMD_BLITZ = 0x0A
local CMDTBL, ITEMLIST, KNOWN = 0x202E, 0x4005, 0x1D28
local SABIN = 0x05
local CONFIG, CURSOR_MEM = 0x1D4E, 0x40   -- bit6: set = Memory, clear = Reset
local SCROLL, CUR_COL, CUR_ROW = 0x895F, 0x8963, 0x8967
-- field menu constants (menu_bushidoloadout's family)
local ZMENUSTATE, ZCURSOR, ZCFGROW = 0x26, 0x4B, 0x4E
local ST_MAIN, ST_CONFIG = 0x05, 0x0E
local MAIN_ROW_CONFIG = 5                 -- Items Skills Equip Relic Status CONFIG
local CFG_ROW_CURSOR = 6                  -- ChangeConfigOption_06 = the Cursor row

local function map() return H.mapId() & 0x1ff end

local slotOf = {}
local ph, hb = 0, -600
local function sab() return slotOf[SABIN] end

-- bystander turns: real Defends; dialogs paged (the family machine's core)
local function consume()
  ph = ph + 1
  if H.readByte(MENU) == 0 then
    H.setPad(ph % 8 < 4 and { a = true } or {})
    return true
  end
  if H.readByte(ACTOR) ~= sab() then
    local step = ph % 40
    if step < 4 then H.setPad({ right = true })
    elseif step >= 20 and step < 24 then H.setPad({ a = true })
    else H.setPad({}) end
    return true
  end
  return false                            -- Sabin's own window: caller's turn
end

-- wait for Sabin's command window (a FRESH open -- through UpdateMenuState_04)
local function sabinWindow(what)
  return H.driveUntil(function()
    return H.battleLoadStarted() and H.readByte(MENU) ~= 0
       and H.readByte(ACTOR) == sab() and H.readByte(MSTATE) == ST_CMD
  end, 30000, {
    H.call(function() if not consume() then H.setPad({}) end end),
    H.waitFrames(1),
  }, what)
end

-- from Sabin's command window: walk onto Blitz and open the list
local function openBlitz(what)
  return H.driveUntil(function() return H.readByte(MSTATE) == ST_TOOLS end,
    1200, {
      H.call(function()
        if consume() then return end
        ph = ph + 1
        local edge = ph % 10 < 5
        local a = H.readByte(ACTOR)
        if H.readByte(MSTATE) ~= ST_CMD then H.setPad({}) return end
        local wantCell = nil
        for i = 0, 3 do
          if H.readByte(CMDTBL + a * 12 + i * 3) == CMD_BLITZ then wantCell = i end
        end
        assert(wantCell, "SABIN's real command list carries Blitz")
        local cur = H.readByte(0x890F + a)
        if cur == wantCell then H.setPad(edge and { a = true } or {})
        elseif cur < wantCell then H.setPad(edge and { down = true } or {})
        else H.setPad(edge and { up = true } or {}) end
      end),
      H.waitFrames(1),
    }, what)
end

-- commit a real Defend from Sabin's command window (closes his turn, so the
-- NEXT window is a fresh UpdateMenuState_04 open)
local function sabinDefends(what)
  return H.driveUntil(function()
    return H.readByte(MENU) == 0 or H.readByte(ACTOR) ~= sab()
  end, 3000, {
    H.call(function()
      if consume() then return end
      ph = ph + 1
      local step = ph % 40
      local st = H.readByte(MSTATE)
      if st == ST_TOOLS then                       -- still in the list: back out
        if step < 4 then H.setPad({ b = true }) else H.setPad({}) end
      elseif st == ST_CMD then
        -- the command cursor may still sit on Blitz (we just backed out of
        -- it); walk it to row 0 first or the A below reopens the list.
        if H.readByte(0x890F + sab()) > 0 then
          if step < 4 then H.setPad({ up = true }) else H.setPad({}) end
        elseif step < 4 then H.setPad({ right = true })   -- Fight -> Def
        elseif step >= 20 and step < 24 then H.setPad({ a = true })
        else H.setPad({}) end
      elseif st == ST_TGT then
        if step < 4 then H.setPad({ a = true }) else H.setPad({}) end
      else
        H.setPad({})
      end
    end),
    H.waitFrames(1),
  }, what)
end

-- field: drive the REAL Config menu until the cursor bit reads `wantMem`.
-- The check is $1d4e read back -- the test never writes it.
local function setConfigCursor(wantMem, what)
  return H.repeatN(1, {
    H.driveUntil(function() return H.readByte(ZMENUSTATE) == ST_MAIN end, 1200,
      { H.pressButtons({ "x" }, 4), H.waitFrames(30) }, what .. ": main menu"),
    H.waitFrames(20),
    H.driveUntil(function()
      return H.readByte(ZMENUSTATE) == ST_MAIN and H.readByte(ZCURSOR) == MAIN_ROW_CONFIG
    end, 900, { H.pressButtons({ "down" }, 2), H.waitFrames(10) },
      what .. ": main-menu cursor on Config"),
    H.pressButtons({ "a" }, 4),
    H.waitUntil(function() return H.readByte(ZMENUSTATE) == ST_CONFIG end, 400,
      what .. ": config page 1", 5),
    H.waitFrames(20),
    H.driveUntil(function()
      return H.readByte(ZMENUSTATE) == ST_CONFIG
         and H.readByte(ZCFGROW) == CFG_ROW_CURSOR
    end, 900, { H.pressButtons({ "down" }, 2), H.waitFrames(10) },
      what .. ": config cursor on the Cursor row"),
    H.driveUntil(function()
      local set = (H.readByte(CONFIG) & CURSOR_MEM) ~= 0
      return set == wantMem
    end, 600, {
      H.pressButtons({ wantMem and "right" or "left" }, 2), H.waitFrames(10),
    }, what .. ": the Cursor option reads " .. (wantMem and "MEMORY" or "RESET")),
    H.call(function()
      H.log(string.format("%s: $1d4e = $%02x (set via the real Config menu)",
        what, H.readByte(CONFIG)))
    end),
    -- back out to the field
    H.pressButtons({ "b" }, 4), H.waitFrames(20),
    H.pressButtons({ "b" }, 4), H.waitFrames(30),
    H.waitUntil(function() return H.hasControl() end, 900,
      what .. ": back on the field", 5),
  })
end

-- pace the ledge lane to a natural encounter
local function encounter(what)
  return (function()
    local lane = nil
    local BACK = { left = "right", right = "left", up = "down", down = "up" }
    return H.repeatN(1, {
      H.driveUntil(function() return H.battleLoadStarted() end, 12600, {
        H.call(function()
          if not (H.hasControl() and H.tileAligned()) then H.setPad({}) return end
          if map() ~= 98 then error("paced off map 98 (now " .. map() .. ")", 0) end
          local x, y = H.fieldX(), H.fieldY()
          if lane == nil then
            for _, d in ipairs({ "right", "left", "up", "down" }) do
              if H.canStep(x, y, d) then lane = { ax = x, ay = y, out = d, back = BACK[d] } break end
            end
            if lane == nil then H.setPad({}) return end  -- passability not
          end                                            -- settled this frame
          H.setPad({ [(x == lane.ax and y == lane.ay) and lane.out or lane.back] = true })
        end),
        H.waitFrames(1),
      }, what),
      H.release(),
      H.waitUntil(function() return H.battleActive() end, 900, "battle armed", 5),
      H.waitFrames(240),
      H.call(function()
        slotOf = {}
        for s = 0, 3 do
          local id = H.readByte(0x3ED8 + s * 2)
          if id ~= 0xFF then slotOf[id] = s end
        end
        assert(slotOf[SABIN], "SABIN present (vargas_won party)")
      end),
    })
  end)()
end

-- the positive control + move, shared by both variants: normalize the cursor
-- to col 0 with the d-pad (verified by reading it back), then one RIGHT walks
-- it to col 1 -- the list is live, and the moved coordinate is real.
local function moveCursorRight(tag)
  return H.repeatN(1, {
    H.driveUntil(function()
      local a = H.readByte(ACTOR)
      return H.readByte(MSTATE) == ST_TOOLS and H.readByte(CUR_COL + a) == 0
         and H.readByte(CUR_ROW + a) == 0 and H.readByte(SCROLL + a) == 0
    end, 900, {
      H.call(function()
        ph = ph + 1
        local edge = ph % 10 < 5
        local a = H.readByte(ACTOR)
        if H.readByte(MSTATE) ~= ST_TOOLS then H.setPad({}) return end
        if H.readByte(CUR_ROW + a) > 0 then H.setPad(edge and { up = true } or {})
        elseif H.readByte(CUR_COL + a) > 0 then H.setPad(edge and { left = true } or {})
        else H.setPad({}) end
      end),
      H.waitFrames(1),
    }, tag .. ": cursor walked to the top-left cell"),
    H.pressButtons({ "right" }, 4), H.waitFrames(10),
    H.call(function()
      H.assertEq(H.readByte(CUR_COL + sab()), 1,
        tag .. ": RIGHT walked the blitz cursor off column 0 -- the list is "
        .. "live, and the moved position is real d-pad work")
    end),
  })
end

H.run({ maxFrames = 200000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000,
    "field control on map 98"),
  H.call(function()
    H.assertEq(map(), 98, "vargas_won on map 98, the Kolts ledge")
    local mask = H.readByte(KNOWN)
    local n = 0
    for i = 0, 7 do n = n + ((mask >> i) & 1) end
    H.log(string.format("$1d28 = $%02x (%d learned), $1d4e = $%02x as saved",
      mask, n, H.readByte(CONFIG)))
    H.assertEq(n >= 2, true,
      "two learned blitzes -- the 1x2 grid gives RIGHT a cell to land on")
  end),

  -- ---- battle 1, under MEMORY (set in the real Config menu first) --------
  setConfigCursor(true, "pre-battle config"),
  encounter("a ledge encounter fires (memory variant)"),
  sabinWindow("sabin's first command window (memory)"),
  openBlitz("blitz list opens (memory)"),
  H.waitFrames(10),
  moveCursorRight("memory variant"),

  -- the fresh open: Sabin himself Defends, the table turns, and his next
  -- command window re-runs UpdateMenuState_04's gated clear.
  sabinDefends("sabin commits a Defend (memory)"),
  sabinWindow("sabin's NEXT command window -- a fresh $04 open (memory)"),
  openBlitz("blitz reopens (memory)"),
  H.waitFrames(10),
  H.call(function()
    local a = sab()
    H.log(string.format("memory reopen: col=%d row=%d scroll=%d config=$%02x",
      H.readByte(CUR_COL + a), H.readByte(CUR_ROW + a), H.readByte(SCROLL + a),
      H.readByte(CONFIG)))
    H.assertEq(H.readByte(CUR_COL + a), 1,
      "MEMORY: the fresh command-window open KEPT the moved cursor (col 1) -- "
      .. "the old unconditional Ot6BlitzListOpen reset fails here")
    H.screenshot("blitzcursor_memory")
  end),

  -- ---- between battles: flee, and flip the real Config to RESET ----------
  H.call(function() H.setPad({}) end),
  H.driveUntil(function() return not H.battleLoadStarted() end, 12000, {
    H.call(function()
      -- back out of any open LIST first -- wait mode freezes battle time
      -- while a list is up, so held L+R can never count down under one
      -- (measured: run 2 held for 9000 frames beneath the reopened blitz
      -- window).  The command window does NOT freeze time (battle_vargas's
      -- header), so once the state is back at $05 the L+R hold runs.
      ph = ph + 1
      local st = H.readByte(MSTATE)
      if H.readByte(MENU) ~= 0 and st ~= ST_CMD and st ~= 0x01 then
        H.setPad(ph % 10 < 5 and { b = true } or {})
      else
        H.setPad({ l = true, r = true })
      end
    end),
    H.waitFrames(1),
  }, "the memory-variant battle is fled (L+R)"),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000,
    "back on the field after the flee", 5),
  H.waitFrames(30),
  setConfigCursor(false, "mid-test config flip"),

  -- ---- battle 2, under RESET ---------------------------------------------
  encounter("a ledge encounter fires (reset variant)"),
  sabinWindow("sabin's first command window (reset)"),
  openBlitz("blitz list opens (reset)"),
  H.waitFrames(10),
  moveCursorRight("reset variant"),
  sabinDefends("sabin commits a Defend (reset)"),
  sabinWindow("sabin's NEXT command window -- a fresh $04 open (reset)"),
  openBlitz("blitz reopens (reset)"),
  H.waitFrames(10),
  H.call(function()
    local a = sab()
    H.log(string.format("reset reopen: col=%d row=%d scroll=%d config=$%02x",
      H.readByte(CUR_COL + a), H.readByte(CUR_ROW + a), H.readByte(SCROLL + a),
      H.readByte(CONFIG)))
    H.assertEq(H.readByte(CUR_COL + a), 0,
      "RESET: the fresh command-window open snapped the cursor back to the "
      .. "top -- the shell's gated clear ran and Blitz honored it")
    H.screenshot("blitzcursor_reset")
    H.log("PASSED: blitz honors Config>Cursor set in the REAL config menu -- "
      .. "memory keeps the moved column across a real turn, reset zeroes it")
  end),
})
