-- @manual standalone: lua tools/tests/item_care_selftest.lua
-- item_care_selftest.lua -- the suites' fight-out driver weighs the bag, and the spend line names why it weighs
-- none when it does not (#388's review round).
-- battle_lockekit's fight-out (H.fightBattleByMenu) wiped on #388's fire-out-v1: STRAGO alone, 428/1034 HP under
-- a 437 round, "no heal saves it (the bag holds no heal)" with 81 Potions and 28 Fenix Downs in the bag, and two
-- fallen members never raised (build/attempts/wt/v041-cleave-bumrush/land4/suite_battle_lockekit.log.gz).  The
-- bag was never read: fightBattleByMenu built its driver with no options, so opts.items was nil and the care
-- lines' item row was nil (Driver:makePlanRules: `(self.opts.items and mayHeal) and cmdRow(...)`), and the spend
-- line's default reason for an empty heal list was "the bag holds no heal".
-- Pure functions, stubbed inputs: no ROM, no emulator, no gameplay claim (the played evidence is in the commit
-- that added this file).  Every assertion runs twice: against the lib as it is (it must hold) and against a
-- mutant of the lib function's own source -- one edit, loaded beside the real one -- under which it must fail.
emu = {
  eventType = { inputPolled = 1, startFrame = 2 },
  callbackType = { exec = 1, read = 2, write = 3 },
  memType = { snesWorkRam = 1, snesPrgRom = 2 },
  addEventCallback = function() return 1 end,
  removeEventCallback = function() end,
  addMemoryCallback = function() return 1 end,
  read = function() return 0 end,
  readWord = function() return 0 end,
  write = function() end,
  writeWord = function() end,
  setInput = function() end,
  getState = function() return {} end,
  getMemorySize = function() return 0 end,
}
OT6_SYMS = setmetatable({}, { __index = function() return 0 end })
local rawPrint = print
print = function() end
local function slurp(path)
  local f = assert(io.open(path, "rb"), path)
  local s = f:read("a"); f:close(); return s
end
local lib = slurp("tools/tests/lib/ot6.lua")
local H = dofile("tools/tests/lib/ot6.lua")
local function plain(s) return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")) end
local function mutant(name, from, to)
  local a = lib:find("\nfunction M%." .. name .. "%(")
  assert(a, "M." .. name .. " in the lib")
  local b = lib:find("\nend\n", a, true)
  local src = lib:sub(a + 1, b + 4)
  local _, count = src:gsub(plain(from), "")
  assert(count == 1, string.format("mutant of M.%s: '%s' occurs %d times", name, from, count))
  src = src:gsub(plain(from), (to:gsub("%%", "%%%%")))
  local chunk = assert(load("local M = setmetatable({}, { __index = ... })\n" .. src
    .. "\nreturn M." .. name, "mutant " .. name, "t", _G))
  return chunk(H)
end
local checks = {}
local function check(what, name, from, to, f)
  assert(type(H[name]) == "function", "FAIL " .. what .. ": the lib has no M." .. name)
  local ok, r = pcall(f)
  assert(ok and r == true, "FAIL " .. what .. ": " .. tostring(r))
  local real = H[name]
  H[name] = mutant(name, from, to)
  local mok, mr = pcall(f)
  H[name] = real
  assert(not mok or mr ~= true, string.format("FAIL %s: the mutant ('%s' -> '%s') passed it too", what, from, to))
  checks[#checks + 1] = what
end

-- the fight-out driver's options
check("fightBattleByMenu's driver weighs the bag (opts.items)", "fightByMenuOpts",
  "return { items = true }", "return {}", function()
    return H.fightByMenuOpts().items == true
  end)

-- why the care lines weigh no item
local lockekit = { items = nil, mayHeal = true, kept = nil, row = nil, hasRow = true }
check("item care off says so, not \"the bag holds no heal\" (battle_lockekit's driver before the fix)",
  "itemCareOff", 'if not o.items then return "this driver weighs no item', 'if false then return "this driver weighs no item',
  function()
    local why = H.itemCareOff(lockekit)
    return why ~= nil and why:find("opts.items", 1, true) ~= nil
  end)
check("an item row in hand: the bag is weighed, no reason", "itemCareOff",
  "if o.row ~= nil then return nil end", "", function()
    return H.itemCareOff({ items = false, mayHeal = false, row = 3, hasRow = true }) == nil
  end)
check("the healer's gate is named", "itemCareOff",
  'if not o.mayHeal then return "the bag is the healer', 'if false then return "the bag is the healer', function()
    local why = H.itemCareOff({ items = true, mayHeal = false, row = nil, hasRow = true })
    return why ~= nil and why:find("opts.healer", 1, true) ~= nil
  end)

-- the spend line's sentence carries the reason it is handed
check("the spend line says the reason, with no heal in the list", "spendDecision",
  'local why = o.why or', 'local why = nil or', function()
    local _, s = H.spendDecision({ hp = 428, maxhp = 1034, roundCost = 437, bp = 5, heals = {}, refused = {},
      why = H.itemCareOff(lockekit) })
    return s:find("opts.items", 1, true) ~= nil and s:find("the bag holds no heal", 1, true) == nil
  end)

print = rawPrint
for _, w in ipairs(checks) do print("ok: " .. w) end
print(string.format("item_care_selftest: %d check(s), each red under its mutant", #checks))
