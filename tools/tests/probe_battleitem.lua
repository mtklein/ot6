-- probe_battleitem.lua -- WHICH ITEM does battle-menu row N actually use?
-- Reads and pad presses only (issue #75).
--
-- THE OPEN QUESTION.  newFightDriver picks a heal by scanning the BATTLE
-- inventory ($2686, 5 bytes/entry) for the item id it wants, and then
-- steers the item window's cursor -- the documented SUM of $8947 (scroll)
-- and $894F (row) -- to that index.  Traced at battle 11 (solo LOCKE), the
-- whole sequence lands: command list -> Item, item window ($0A), steer,
-- A, target select ($38), confirm.  And the Potion is still in the bag
-- afterwards and his HP never moved.  So the navigation is right and the
-- INDEX is wrong: the row the window confirms is not the $2686 index the
-- driver counted to.
--
-- The other candidate ordering is the FIELD inventory ($1869 ids / $1969
-- counts), which is a different list with different holes in it.  This
-- probe settles it by ground truth rather than by reading menu code: park
-- the cursor on a KNOWN row, use it, and see which item's count went down.
--
-- ANSWER, measured 2026-08-09: the mapping is CORRECT.  Cursor sum 1
-- consumed $2686 index 1 ($E9, a Potion, 5 -> 4).  The driver's indexing
-- is not the bug, and the whole item path -- command list -> Item -> row
-- -> target -> confirm -> the count going down -- works on this party
-- through exactly the cells newFightDriver uses.
--
-- So whatever fails at battle 11 is specific to that fight, and the two
-- things it does not share with this one are worth the next probe: LOCKE
-- is SOLO there (this party is three), and his target mask therefore has
-- one bit in it.  Read newFightDriver's ST_TGT branch with that in mind --
-- if `chars` ever reads 0 for a solo party, the steer loop compares 0 < 0,
-- presses UP forever and never confirms, and the turn simply expires.
-- That is a hypothesis, NOT a measurement; it has not been observed.
--
--   OT6_KEEP_RUNS=1 OT6_NO_PUBLISH=1 tools/tests/run.sh tools/tests/probe_battleitem.lua
local H = dofile("tools/tests/lib/ot6.lua")
-- vargas_entry, not first_battle: the opening battle carries an EMPTY
-- bag ($2686 reads FF x0 straight across, measured), so there is nothing
-- to select and the target window never opens.  The Vargas entry point is one
-- A press from `battle 66` and the party walks in with Tonics, Potions and
-- Fenix Downs -- a real bag to index into.
local STATE = "build/states/vargas_entry.mss.lua"

local MSTATE, ACTOR = 0x7BC2, 0x62CA
local CMDTBL, CMDROW = 0x202E, 0x890F
local ITEMSCR, ITEMROW, BATTINV = 0x8947, 0x894F, 0x2686
local ST_CMD, ST_ITEM, ST_TGT = 0x05, 0x0A, 0x38
local CMD_ITEM = 0x01

local function tapUntil(btn, pred, what, budget)
  local ph = 0
  return H.driveUntil(pred, budget or 1800, {
    H.call(function()
      ph = (ph + 1) % 12
      H.setPad(ph < 4 and { btn } or {})
    end),
  }, what)
end

local function st() return H.readByte(MSTATE) end
local function actor() return H.readByte(ACTOR) & 3 end
local function sum()
  return H.readByte(ITEMSCR + actor()) + H.readByte(ITEMROW + actor())
end

-- both candidate orderings, side by side
local function battInv(n)
  local out = {}
  for i = 0, (n or 11) do
    local id, qty = H.readByte(BATTINV + i * 5), H.readByte(BATTINV + i * 5 + 3)
    out[#out + 1] = string.format("%d:%02X x%d", i, id, qty)
  end
  return table.concat(out, " ")
end
local function fieldInv(n)
  local out = {}
  for i = 0, (n or 11) do
    out[#out + 1] = string.format("%d:%02X x%d", i,
      H.readByte(0x1869 + i), H.readByte(0x1969 + i))
  end
  return table.concat(out, " ")
end
local function battQty(i) return H.readByte(BATTINV + i * 5 + 3) end

local function cmdRowOf(cmd)
  for row = 0, 3 do
    if H.readByte(CMDTBL + actor() * 12 + row * 3) == cmd then return row end
  end
  return nil
end

local before = {}
local TARGET_ROW = 1          -- the row we will park on and use

H.run({ maxFrames = 40000 }, {
  H.loadState(STATE),
  H.waitFrames(30),
  H.waitUntil(function() return H.hasControl() end, 900, "field control", 5),
  -- one press opens the fight the fixture is parked in front of
  tapUntil("a", function() return H.battleLoadStarted() end, "battle 66 up", 3000),
  H.release(), H.waitFrames(60),
  tapUntil("a", function() return st() == ST_CMD end, "a command menu"),
  H.release(), H.waitFrames(20),
  H.call(function()
    H.log("battle inv: " .. battInv())
    H.log("field inv:  " .. fieldInv())
    H.log(string.format("actor=%d item cmd row=%s", actor(),
      tostring(cmdRowOf(CMD_ITEM))))
    H.screenshot("bi_cmd")
  end),

  -- into the item window
  H.driveUntil(function()
    return st() == ST_CMD and (H.readByte(CMDROW + actor()) & 3) == cmdRowOf(CMD_ITEM)
  end, 1800, {
    H.call(function()
      local cur, want = H.readByte(CMDROW + actor()) & 3, cmdRowOf(CMD_ITEM) or 0
      H.setPad((H.frame % 12 < 4)
        and { [cur < want and "down" or "up"] = true } or {})
    end),
  }, "command cursor on Item"),
  H.release(), H.waitFrames(20),
  tapUntil("a", function() return st() == ST_ITEM end, "item window open"),
  H.release(), H.waitFrames(30),
  H.call(function()
    H.log(string.format("item window open: scroll=%d row=%d sum=%d",
      H.readByte(ITEMSCR + actor()), H.readByte(ITEMROW + actor()), sum()))
    H.screenshot("bi_item_row0")
  end),

  -- walk to a KNOWN row and photograph it
  H.driveUntil(function() return sum() == TARGET_ROW end, 2400, {
    H.call(function()
      local cur = sum()
      H.setPad((H.frame % 12 < 4)
        and { [cur < TARGET_ROW and "down" or "up"] = true } or {})
    end),
  }, "item cursor on row " .. TARGET_ROW),
  H.release(), H.waitFrames(30),
  H.call(function()
    H.log(string.format("parked: scroll=%d row=%d sum=%d",
      H.readByte(ITEMSCR + actor()), H.readByte(ITEMROW + actor()), sum()))
    for i = 0, 11 do before[i] = battQty(i) end
    H.screenshot("bi_item_parked")
  end),

  -- use it on whoever the target cursor offers, then read the ground truth
  tapUntil("a", function() return st() == ST_TGT end, "target select"),
  H.release(), H.waitFrames(20),
  tapUntil("a", function() return st() ~= ST_TGT end, "confirm"),
  H.release(), H.waitFrames(180),
  H.call(function()
    H.log("battle inv after: " .. battInv())
    local moved = {}
    for i = 0, 11 do
      if battQty(i) ~= before[i] then
        moved[#moved + 1] = string.format("index %d (id $%02X): %d -> %d",
          i, H.readByte(BATTINV + i * 5), before[i], battQty(i))
      end
    end
    if #moved == 0 then
      H.log("VERDICT: NOTHING was consumed -- the confirm did not use an item")
    else
      H.log("VERDICT: cursor sum " .. TARGET_ROW .. " consumed " ..
        table.concat(moved, ", "))
    end
    H.screenshot("bi_after")
  end),
})
