-- @manual standalone: lua tools/tests/care_stock_selftest.lua
-- care_stock_selftest.lua -- H.careStockPotions past L43 (#419).
--
-- No emulator.  The Potion target at a counter that sells no Tonics is the
-- combat reserve a few levels ahead, the field care the bag's Tonics do not
-- carry, and the legs' spend.  With the four-level look-ahead and a spend
-- of 10 it passed the 99 stack from about L43 and raised, so the World of
-- Ruin's later counters (v0.30 on) could not call it.  The reserve now stops
-- at the Potion band's cap (79, audit_supplies.py POTION_BAND_CAP) and the
-- target at the stack's 99.  The negative control is the old body, which
-- raises at L43.
local mem = {}
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
print = function() end
local H = dofile("tools/tests/lib/ot6.lua")
loadfile("tools/tests/lib/ot6_field.lua")(H)
print = rawPrint
H.log = function() end

local tonics = 4
H.invCountOf = function(id) return id == 0xE8 and tonics or 0 end

local ok = true
local function check(what, cond)
  rawPrint(string.format("%s: %s", cond and "ok" or "FAILED", what))
  if not cond then ok = false end
end

-- the old body (before #419), the negative control
local function old(level, opts)
  opts = opts or {}
  local ahead = opts.ahead or 4
  local reserve = math.ceil((level + ahead) * 1.5)
  local gap = math.max(0, 99 * 50 - 50 * (opts.tonics or H.invCountOf(0xE8)))
  local want = reserve + math.ceil(gap / 250) + (opts.spend or 0)
  if want > 99 then error("past the 99 stack") end
  return want
end

-- below the cap nothing moved: L35 + 4 ahead is a reserve of 59, the 4
-- Tonics leave 4750 HP of field care (19 Potions), and a spend of 10
check("L35, spend 10: 59 + 19 + 10 = 88, as before",
  H.careStockPotions(35, { spend = 10 }) == 88 and old(35, { spend = 10 }) == 88)
-- the issue's case: L43, spend 10 -> 71 + 19 + 10 = 100
check("the old body raises at L43 with a spend of 10 (the negative control)",
  not pcall(old, 43, { spend = 10 }))
check("L43, spend 10: capped at the stack's 99",
  select(2, pcall(H.careStockPotions, 43, { spend = 10 })) == 99)
-- the reserve's own cap: L60 + 4 is a reserve of 96 uncapped; with 99
-- Tonics there is no field-care gap, so the target is the reserve alone
tonics = 99
check("L60, 99 Tonics, no spend: the reserve stops at 79",
  H.careStockPotions(60, {}) == H.POTION_BAND_CAP and H.POTION_BAND_CAP == 79)
check("L49 (a reserve of 80 uncapped), 99 Tonics: 79",
  H.careStockPotions(49, {}) == 79)
check("L48 (a reserve of 78), 99 Tonics: 78, under the cap",
  H.careStockPotions(48, {}) == 78)

rawPrint("care_stock selftest: " .. (ok and "ok" or "FAILED"))
os.exit(ok and 0 or 1)
