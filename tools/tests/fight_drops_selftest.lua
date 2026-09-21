-- @manual standalone: lua tools/tests/fight_drops_selftest.lua
-- fight_drops_selftest.lua -- every place the fight driver drops a plan
-- goes through Driver:dropPlan (#245): the recovery trace gets a drop
-- event with the reason, and the care budget the plan claimed is released.
--
-- No emulator.  The driver reads the battle RAM through emu.read, which
-- is a table here: each case parks a plan on the driver, arranges the
-- bytes the steer reads so the row/cell/list it wants is not there, and
-- calls button() once.  Before the fix the lore, throw, skill and throw-
-- steer paths cleared self.plan by hand (no event, careActor kept), and
-- the item/spell paths and frame's actor change went through traceDrop
-- alone (an event, careActor kept).  The negative control is the old
-- shape of any one path: put `self.plan, self.planActor = nil, nil` back
-- at the lore row and the "lore_unavailable" case fails with no drop event.
local mem = {}
local printed = {}
emu = {
  eventType = { inputPolled = 1, startFrame = 2 },
  callbackType = { exec = 1, read = 2, write = 3 },
  memType = { snesWorkRam = 1, snesPrgRom = 2 },
  addEventCallback = function() return 1 end,
  removeEventCallback = function() end,
  addMemoryCallback = function() return 1 end,
  read = function(a) return mem[a] or 0 end,
  readWord = function(a) return (mem[a] or 0) | ((mem[a + 1] or 0) << 8) end,
  write = function(a, v) mem[a] = v end,
  writeWord = function(a, v) mem[a] = v & 0xFF; mem[a + 1] = v >> 8 end,
  setInput = function() end,
  getState = function() return {} end,
}
OT6_SYMS = setmetatable({}, { __index = function() return 0 end })
local rawPrint = print
print = function(s) printed[#printed + 1] = s end   -- the trace flushes through print
local H = dofile("tools/tests/lib/ot6.lua")

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local MLISTPTR, ITEMLIST, BATTINV = 0x302C, 0x4005, 0x2686
local ST_CMD, ST_ITEM, ST_MAGIC, ST_LORE, ST_THROW, ST_TOOLS = 0x05, 0x0A, 0x0E, 0x1B, 0x2D, 0x30

local function word(a, v) mem[a] = v & 0xFF; mem[a + 1] = v >> 8 end
local function reset()
  for k in pairs(mem) do mem[k] = nil end
  printed = {}
  mem[MENU], mem[ACTOR] = 1, 0
  -- a live magic list with nothing in it (every cell $FF), so a spell or
  -- lore the plan names is not found; a throw/tools list with one row
  -- that is not the wanted item; a bag with no Fenix Down
  word(MLISTPTR, 0x2100)
  for i = 0, 79 do mem[0x2100 + (i + 1) * 4] = 0xFF end
  mem[ITEMLIST], mem[ITEMLIST + 3] = 0x22, 0xFF
  for i = 0, 3 do mem[BATTINV + i * 5] = 0xFF end
  mem[0x3BF4], mem[0x3C1C] = 100, 100   -- entity 0 stands
end

local function drops()
  local out = {}
  for _, s in ipairs(printed) do
    if s:find('"event":"drop"', 1, true) then
      out[#out + 1] = s:match('"reason":"([^"]+)"')
    end
  end
  return out
end

local function case(name, state, plan, act)
  reset()
  mem[MSTATE] = state
  local F = H.newFightDriver("drops", { actionTrace = true })
  local D = F.driver
  H.frame = 100
  D.plan, D.planActor = plan, 0
  D.recovery.plan(0, plan, H.frame)
  if plan.kind == "item" or plan.kind == "heal" then D.careActor = 0 end
  local held = act(D)
  assert(D.plan == nil and D.planActor == nil, name .. ": the plan is gone")
  assert(D.careActor == nil, name .. ": the care budget is released")
  assert(held ~= nil and held[1] == "b", name .. ": B out")
  F.idle()                     -- flushes the trace to print
  local seen = drops()
  assert(#seen >= 1 and seen[1] == name,
    name .. ": the recovery trace carries the drop (saw " .. table.concat(seen, ",") .. ")")
  return seen
end

local press = function(D) return D:button(0) end

case("lore_unavailable", ST_LORE, { kind = "lore", lore = 3, row = 2 }, press)
case("throw_unavailable", ST_THROW, { kind = "throw", item = 0xAB, row = 1 }, press)
case("skill_row_missing", ST_TOOLS, { kind = "skill", cmd = 0x09, skill = 0xA8, row = 1 }, press)
case("item_unavailable", ST_ITEM, { kind = "item", item = 0xF0, target = 1, row = 3, reason = "revive" }, press)
case("spell_unavailable", ST_MAGIC, { kind = "heal", spell = 0x2D, target = 1, row = 2 }, press)
-- the throw steer's give-up: the row is there but the cursor never
-- reaches it inside the 40-pulse budget
case("throw_steer", ST_THROW, { kind = "throw", item = 0x22, row = 1 }, function(D)
  mem[0x8963], mem[0x8967] = 1, 1    -- cursor parked on column 1, row 1
  local held
  for i = 1, 40 do
    mem[0x7B7D] = i                  -- a moving target cell, so the parked-window
    held = D:button(0)               -- watchdog (13 still pulses) does not fire first
  end
  return held
end)
-- the window moved to another actor before the plan landed (frame's drop;
-- cadence 2 keeps this pulse off button(), which would plan for the new actor)
case("actor_changed", ST_CMD, { kind = "item", item = 0xE9, target = 1, row = 3 }, function(D)
  mem[ACTOR] = 1
  D.menuStreak, D.tick = 10, 0
  D.opts.cadence = 2
  D:frame()
  return { "b" }
end)

-- the two the fix leaves alone, still through dropPlan: an unplanned reel
-- window and a list window the plan did not open
case("slot_unplanned", 0x08, { kind = "fight", row = 0 }, press)
case("window_unplanned", 0x16, { kind = "fight", row = 0 }, press)

rawPrint("fight_drops_selftest: PASS -- 9 drop paths, each a dropPlan with its reason "
  .. "in the recovery trace and the care budget released")
