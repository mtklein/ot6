-- @suite savestate=vargas_won
-- battle_blitzlist.lua -- v0.3 Blitz-as-menu: the selector itself.
--
-- Vanilla Blitz had no window: UpdateMenuState_3d (btlgfx_main.asm, now
-- deleted) read button codes off a 64-frame rolling pad-edge buffer.  The
-- command now hands off to Ot6BlitzListOpen (ot6.asm), which fills wItemList
-- with the LEARNED blitzes -- each row keyed by its resolved attack id $5D+i
-- (Pummel $5d .. Bum Rush $64) -- and reuses the Tools window shell (menu
-- state $30).  The row draw flips the Tools template's $0e item-name code to
-- $0f so ListTextCmd_0f renders each row from AttackName; the confirm shim
-- subtracts $5D back to the raw index cmd $0a stores, exactly the byte
-- UpdateMenuState_3d used to write, so FixPlayerAttack (validates i against
-- $1d28, adds +$5d) and everything downstream are untouched.
--
-- ISSUE #75 CONVERSION -- a REAL SABIN, his REAL learned set, real cursors.
-- This file used to install CHAR::SABIN into every magitek-intro slot, write
-- the known-blitz mask $1d28 by hand, pin HP, and POKE the saved-cursor
-- triple to select a row.  It now boots vargas_won -- Sabin on Mt. Kolts
-- right after his own boss fight -- paces the ledge until a natural
-- encounter fires, waits for SABIN's own menu, and opens his real Blitz
-- command.  The learned set is whatever the save holds (the
-- menu_blitzpage_sabin doctrine): $1d28 is READ, the rows are derived from
-- it, and the not-drawn negative control is the save's own first unlearned
-- blitz.  The selection cursor is WALKED with the d-pad and verified by
-- re-reading the cell -- the battle_vargas idiom -- never written.
--
-- What is asserted:
--   1. LEARNED-ONLY ROWS + STAMPED COSTS.  wItemList packs exactly the
--      learned attack ids in ladder order, then $ff; every learned name
--      (AttackName bytes, read from the ROM) is drawn, the first unlearned
--      name is NOT; each row's Qty cell carries its Ot6AbilityCostTbl price
--      (read from the ROM -- a retune moves both sides), and the real
--      ladder spans one- and two-digit prices on screen (Pummel 4,
--      AuraBolt 10 at this fixture's level).
--   2. THE OLD CODE IS DEAD.  Mashing Pummel's vanilla combo directions
--      (LEFT RIGHT LEFT) as pad edges in the open list queues nothing: the
--      menu stays open, no action commits.  Only the cursor + A selects.
--   3. SELECTION RESOLVES.  The cursor is WALKED onto Pummel's row with the
--      d-pad (verified by re-reading the saved-cursor cells) and A lands
--      attack $5d in $3410 ("last skill used").
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/vargas_won.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD, ST_TOOLS = 0x05, 0x30
local CMD_BLITZ = 0x0A
local CMDTBL, ITEMLIST, KNOWN = 0x202E, 0x4005, 0x1D28
local SABIN = 0x05
local PUMMEL, BLITZ_ATK0 = 0x5D, 0x5D
local SCROLL, CUR_COL, CUR_ROW = 0x895F, 0x8963, 0x8967

-- the two ROM authorities: names as ListTextCmd_0f draws them, prices as
-- Ot6CostFor charges them.
local ATKNAME = H.sym("AttackName") & 0x3FFFFF
local ATKNAME_0, NAME_SIZE = 0x51, 10
local function nameSeq(id)              -- leading glyph run, $ff tail trimmed
  local t, rec = {}, id - ATKNAME_0
  for i = 0, NAME_SIZE - 1 do
    local b = H.readRomByte(ATKNAME + rec * NAME_SIZE + i)
    t[#t + 1] = b
  end
  while #t > 0 and t[#t] == 0xff do table.remove(t) end
  return t
end
local function nameText(id)
  local s = ""
  for _, b in ipairs(nameSeq(id)) do
    if b >= 0x80 and b <= 0x99 then s = s .. string.char(65 + b - 0x80)
    elseif b >= 0x9a and b <= 0xb3 then s = s .. string.char(97 + b - 0x9a)
    else s = s .. "?" end
  end
  return s
end
local COSTTBL = H.sym("Ot6AbilityCostTbl") & 0x3FFFFF
local function costOf(id)
  local x = 0
  while true do
    local key = H.readRomByte(COSTTBL + x)
    if key == 0xff then return 0 end
    if key == id then return H.readRomByte(COSTTBL + x + 1) end
    x = x + 2
  end
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

local function map() return H.mapId() & 0x1ff end

-- wait for SABIN's own menu, consuming other characters' turns with a real
-- Defend (battle_naturalmp's pattern).
local slotOf = {}
local function menuFor(charId, what)
  local ph = 0
  local function up()
    return H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == slotOf[charId]
  end
  return H.driveUntil(up, 20000, {
    H.call(function()
      ph = ph + 1
      if H.readByte(MENU) == 0 then
        -- no menu up: page any battle dialog with A (the battle_vargas
        -- hazard -- a monster dialog blocks the queue until dismissed)
        H.setPad(ph % 8 < 4 and { a = true } or {})
      elseif H.readByte(ACTOR) ~= slotOf[charId] then
        local step = ph % 40
        if step < 4 then H.setPad({ right = true })
        elseif step >= 20 and step < 24 then H.setPad({ a = true })
        else H.setPad({}) end
      else
        H.setPad({})
      end
    end),
  }, what)
end

local spells = {}
local learned, firstUnlearned = {}, nil

H.run({ maxFrames = 90000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000,
    "field control on map 98"),
  H.call(function()
    H.assertEq(map(), 98, "vargas_won on map 98, the Kolts ledge")
    local mask = H.readByte(KNOWN)
    for i = 0, 7 do
      if (mask >> i) & 1 == 1 then learned[#learned + 1] = BLITZ_ATK0 + i
      elseif firstUnlearned == nil then firstUnlearned = BLITZ_ATK0 + i end
    end
    local names = {}
    for _, id in ipairs(learned) do
      names[#names + 1] = string.format("%s(%d MP)", nameText(id), costOf(id))
    end
    H.log(string.format("$1d28 = $%02x as saved: %s; first unlearned = %s",
      mask, table.concat(names, " "), nameText(firstUnlearned)))
    H.assertEq(#learned >= 2, true,
      "a post-Vargas Sabin knows at least Pummel and AuraBolt -- two rows, "
      .. "so the list, the costs and the walk below all have work to do")
    H.assertEq(firstUnlearned ~= nil, true,
      "at least one unlearned blitz for the not-drawn negative control")
    -- the real ladder must span one- and two-digit prices on screen, or the
    -- stamped-cost assertion only exercises one width
    local lo, hi = false, false
    for _, id in ipairs(learned) do
      if costOf(id) < 10 then lo = true else hi = true end
    end
    H.assertEq(lo and hi, true,
      "the learned prices span one- and two-digit (Pummel 4 / AuraBolt 10)")
    emu.addMemoryCallback(function(_, v) spells[#spells + 1] = v end,
      emu.callbackType.write, 0x7E3410, 0x7E3410)
  end),

  -- pace the auto-detected lane until a natural encounter fires
  (function()
    local battN, waited, lane = 0, 0, nil
    local BACK = { left = "right", right = "left", up = "down", down = "up" }
    return H.driveUntil(function()
      waited = waited + 1
      battN = H.battleLoadStarted() and battN + 1 or 0
      if battN >= 1 then H.setPad({}) return true end
      if map() ~= 98 then error("paced off map 98 (now " .. map() .. ")", 0) end
      return waited >= 12000
    end, 12600, {
      H.call(function()
        if not (H.hasControl() and H.tileAligned()) then H.setPad({}) return end
        local x, y = H.fieldX(), H.fieldY()
        if lane == nil then
          for _, d in ipairs({ "right", "left", "up", "down" }) do
            if H.canStep(x, y, d) then lane = { ax = x, ay = y, out = d, back = BACK[d] } break end
          end
        end
        H.setPad({ [(x == lane.ax and y == lane.ay) and lane.out or lane.back] = true })
      end),
      H.waitFrames(1),
    }, "a ledge encounter fires")
  end)(),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle armed", 5),
  H.waitFrames(240),
  H.call(function()
    for s = 0, 3 do
      local id = H.readByte(0x3ED8 + s * 2)
      if id ~= 0xFF then slotOf[id] = s end
    end
    assert(slotOf[SABIN], "SABIN present (vargas_won party)")
  end),

  -- open the blitz menu: SABIN's real command row, walked to and confirmed.
  menuFor(SABIN, "sabin's command window"),
  H.waitFrames(30),
  (function()
    local ph = 0
    return H.driveUntil(function() return H.readByte(MSTATE) == ST_TOOLS end,
      1200, {
        H.call(function()
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
      }, "the blitz list opens (tools-shell state $30)")
  end)(),
  H.waitFrames(20),                    -- let every row finish drawing
  H.call(function() H.screenshot("blitzlist_window") end),
  -- the spike deliverable: the open Blitz menu with each name's MP cost drawn.
  H.call(function() H.screenshot("blitz_cost_display") end),

  -- 1. LEARNED-ONLY ROWS + STAMPED MP COST -----------------------------------
  H.call(function()
    local ids, qty = {}, {}
    for i = 0, 7 do
      ids[i] = H.readByte(ITEMLIST + i * 3)
      qty[i] = H.readByte(ITEMLIST + i * 3 + 1)     -- wItemList::Qty = the cost
    end
    H.log(string.format("wItemList ids : %02x %02x %02x %02x %02x %02x %02x %02x",
      ids[0], ids[1], ids[2], ids[3], ids[4], ids[5], ids[6], ids[7]))
    H.log(string.format("wItemList cost: %3d %3d %3d %3d %3d %3d %3d %3d",
      qty[0], qty[1], qty[2], qty[3], qty[4], qty[5], qty[6], qty[7]))
    for i, id in ipairs(learned) do
      H.assertEq(ids[i - 1], id, string.format(
        "row %d is the save's learned %s ($%02x)", i - 1, nameText(id), id))
      H.assertEq(qty[i - 1], costOf(id), string.format(
        "%s's stamped cost is the charge table's %d", nameText(id), costOf(id)))
    end
    H.assertEq(ids[#learned], 0xFF,
      "the list terminates after the learned blitzes -- unlearned never packs")

    for _, id in ipairs(learned) do
      H.assertEq(findName(nameSeq(id)) ~= nil, true,
        "\"" .. nameText(id) .. "\" is drawn in the menu")
    end
    H.assertEq(findName(nameSeq(firstUnlearned)), nil,
      "\"" .. nameText(firstUnlearned) .. "\" is NOT drawn -- an unlearned "
      .. "blitz never appears")
  end),

  -- 2. THE OLD CODE IS DEAD ---------------------------------------------------
  -- Pummel's vanilla combo was LEFT RIGHT LEFT A.  Its DIRECTIONS, mashed as
  -- pad edges in the open list, must only walk the cursor -- never queue.
  H.call(function() H.assertEq(H.readByte(MSTATE), ST_TOOLS, "in the list before the mash") end),
  H.pressButtons({ "left" }, 4),  H.waitFrames(4),
  H.pressButtons({ "right" }, 4), H.waitFrames(4),
  H.pressButtons({ "left" }, 4),  H.waitFrames(4),
  H.call(function()
    H.assertEq(H.readByte(MSTATE), ST_TOOLS,
      "mashing the old blitz combo directions queued nothing -- still in the menu")
    H.assertEq(H.readByte(MENU) ~= 0, true, "the battle menu is still up")
  end),

  -- 3. SELECTION RESOLVES -----------------------------------------------------
  -- The cursor is WALKED back onto Pummel's row 0 with the d-pad -- the mash
  -- above may have moved it -- and verified by re-reading the saved-cursor
  -- cells (issue #75: the pokes are gone).
  (function()
    local ph = 0
    return H.driveUntil(function()
      local a = H.readByte(ACTOR)
      return H.readByte(MSTATE) == ST_TOOLS
         and H.readByte(CUR_ROW + a) == 0 and H.readByte(CUR_COL + a) == 0
         and H.readByte(SCROLL + a) == 0
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
    }, "cursor walked onto Pummel (row 0, col 0)")
  end)(),
  H.call(function()
    H.assertEq(H.readByte(ITEMLIST), PUMMEL, "row 0 is Pummel")
  end),
  H.waitFrames(4),
  H.pressButtons({ "a" }, 4), H.waitFrames(8),
  H.driveUntil(function()
    for _, v in ipairs(spells) do if v == PUMMEL then return true end end
    return false
  end, 6000, {
    H.call(function()
      if H.readByte(MENU) ~= 0 and H.readByte(MSTATE) ~= ST_TOOLS then H.setPad({ a = true })
      else H.setPad({}) end
    end),
    H.waitFrames(3),
  }, "the picked Pummel resolves to attack $5d"),
  H.call(function()
    H.assertEq(H.readByte(0x3410), PUMMEL,
      "the selected blitz resolved to Pummel ($5d)")
    H.log("PASSED: the real Sabin's blitz menu lists his learned set only, "
      .. "prices it from the charge table, ignores the old combo, and resolves")
    H.screenshot("blitzlist_resolved")
  end),
})
