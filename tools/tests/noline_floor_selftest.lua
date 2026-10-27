-- @manual standalone: lua tools/tests/noline_floor_selftest.lua  (after ninja build/ot6.sfc)
-- noline_floor_selftest.lua -- the no-line fallback's care floor (#443) and
-- the Mute cure for a seat whose attack is Magic (#444).  Synthetic
-- contracts: RAM is a stub table, the item records come from build/ot6.sfc
-- at ff6/rom/ff6-en.dbg's symbols; no emulator, no gameplay claim (the
-- played evidence is cited in lib/ot6.lua at Driver:noLineItemPick and
-- Driver:cureFor).
--
--   1. Driver:noLineItemPick: a seat with no Fight row and no Magic line
--      spends a Tonic, else a Potion, from above the bag's care floor; a
--      Tonic at its floor gives way to a Potion above its own; only with
--      neither above its floor does the turn dip below (the last of either);
--      an empty bag picks nothing.  #443's rg3mut mutant (any Tonic or
--      Potion with one left, the floor ignored) passed 18 of 18 tower runs
--      (build/attempts/wt/v031-relics-grey/lab/rg3mut_*); here it fails
--      case 1b.
--   2. Driver:cureFor on Mute: a Muted seat with a Magic row and no Fight
--      row (the Fanatics' Tower) is cured with the cheapest Mute cure in
--      gil above its floor (an Echo Screen before a Remedy); a Muted seat
--      that can still Fight, and an unmuted seat, are not; with the Echo
--      Screens at their floor the Remedy is the cure.
-- Negative controls (build/attempts/wt/v038-magimaster/mut/): the floor
-- ignored in noLineItemPick fails 1b; cureFor's Mute branch removed fails
-- 2a.
emu = { eventType = { inputPolled = 1 }, addEventCallback = function() return 1 end }
local H = dofile("tools/tests/lib/ot6.lua")

local function slurp(path)
  local f = assert(io.open(path, "rb"), path)
  local s = f:read("a"); f:close(); return s
end
local rom = slurp("build/ot6.sfc")
local dbg = slurp("ff6/rom/ff6-en.dbg")
local symMemo = {}
H.sym = function(name)
  if symMemo[name] == nil then
    local val = dbg:match('sym\tid=%d+,name="' .. name .. '",addrsize=absolute,scope=%d+,def=%d+,ref=[%d+]+,val=0x(%x+),seg=%d+,type=lab')
    symMemo[name] = assert(tonumber(val, 16), name .. " in ff6-en.dbg")
  end
  return symMemo[name]
end
H.readRomByte = function(off) return rom:byte(off + 1) end
H.readRomWord = function(off) return rom:byte(off + 1) | (rom:byte(off + 2) << 8) end
local mem = {}
H.readByte = function(a) return mem[a] or 0 end
H.readWord = function(a) return (mem[a] or 0) | ((mem[a + 1] or 0) << 8) end
H.log = function() end

local n = 0
local function check(ok, what)
  if not ok then error("FAILED: " .. what, 0) end
  n = n + 1
end

-- the battle cells the stubs fill (lib/ot6.lua's BATTLE table)
local BATTINV, CMDTBL, ST2 = 0x2686, 0x202E, 0x3EE5
local TONIC, POTION, REMEDY, ECHO = 0xE8, 0xE9, 0xF5, 0xFB
local CMD_FIGHT, CMD_MAGIC, CMD_ITEM = 0x00, 0x02, 0x01
-- the battle bag: { { id, count }, ... } in slots 0.., the rest empty
local function bag(items)
  mem = {}
  for s = 0, 251 do mem[BATTINV + s * 5] = 0xFF end
  for s, it in ipairs(items) do
    mem[BATTINV + (s - 1) * 5] = it[1]
    mem[BATTINV + (s - 1) * 5 + 3] = it[2]
  end
end
local function driver(reserve)
  return H.newFightDriver("floor", { items = true, reserve = reserve }).driver
end
local function picked(p) return p and string.format("$%02X x%d (%s)", p.it, p.have, p.floor) or "nothing" end

-- 1. the no-line fallback's floor
local floor = { [TONIC] = 5, [POTION] = 3 }
bag({ { TONIC, 9 }, { POTION, 9 } })
local p = driver(floor):noLineItemPick(floor)
check(p and p.it == TONIC and p.idx == 0 and p.floor == "within the care floor",
  "1a: Tonics above their floor: a Tonic, from above it (got " .. picked(p) .. ")")
bag({ { TONIC, 5 }, { POTION, 9 } })
p = driver(floor):noLineItemPick(floor)
check(p and p.it == POTION and p.idx == 1 and p.floor == "within the care floor",
  "1b: the Tonics at their floor (5 of 5): a Potion from above its own, not the floor's Tonic (got " .. picked(p) .. ")")
bag({ { TONIC, 5 }, { POTION, 3 } })
p = driver(floor):noLineItemPick(floor)
check(p and p.it == TONIC and p.floor == "BELOW the care floor: nothing else left",
  "1c: both at their floors: the turn dips below, a Tonic (got " .. picked(p) .. ")")
bag({ { POTION, 2 } })
p = driver(floor):noLineItemPick(floor)
check(p and p.it == POTION and p.floor == "BELOW the care floor: nothing else left",
  "1d: no Tonic, the Potions under their floor: the last Potion (got " .. picked(p) .. ")")
bag({ { REMEDY, 4 } })
p = driver(floor):noLineItemPick(floor)
check(p == nil, "1e: no Tonic or Potion: nothing (got " .. picked(p) .. ")")

-- 2. Mute where Magic is the attack
-- entity 0's rows: `rows` (command ids, $FF empty), Mute set or not; the Magic
-- row greyed while Muted (flags bit 7), as UpdateCmd_05 greys it
local function seat(rows, muted)
  for r = 0, 3 do
    mem[CMDTBL + r * 3] = rows[r + 1] or 0xFF
    mem[CMDTBL + r * 3 + 1] = (muted and rows[r + 1] == CMD_MAGIC) and 0x80 or 0
  end
  mem[ST2] = muted and H.ST2_MUTE or 0
end
local TOWER = { CMD_MAGIC, 0xFF, 0xFF, CMD_ITEM }
local OUTSIDE = { CMD_FIGHT, CMD_MAGIC, 0xFF, CMD_ITEM }
local cureFloor = { [ECHO] = 1, [REMEDY] = 2 }
bag({ { REMEDY, 10 }, { ECHO, 4 } })
seat(TOWER, true)
local item, what = driver(cureFloor):cureFor(0)
check(item == ECHO and what == "Mute",
  string.format("2a: a Muted seat whose only attack is Magic: an Echo Screen (got %s, %s)",
    item and string.format("$%02X", item) or "nil", tostring(what)))
bag({ { REMEDY, 10 }, { ECHO, 1 } })
seat(TOWER, true)
item, what = driver(cureFloor):cureFor(0)
check(item == REMEDY and what == "Mute",
  string.format("2b: the Echo Screens at their floor: a Remedy (got %s, %s)",
    item and string.format("$%02X", item) or "nil", tostring(what)))
bag({ { REMEDY, 10 }, { ECHO, 4 } })
seat(OUTSIDE, true)
item, what = driver(cureFloor):cureFor(0)
check(what == nil, "2c: a Muted seat that can still Fight: no cure (got " .. tostring(what) .. ")")
seat(TOWER, false)
item, what = driver(cureFloor):cureFor(0)
check(what == nil, "2d: an unmuted seat: no cure (got " .. tostring(what) .. ")")

print(string.format("noline_floor_selftest: %d checks ok", n))
