-- @manual standalone: lua tools/tests/plan_gate_selftest.lua
-- plan_gate_selftest.lua -- when the fight driver may plan a turn (#510), and
-- the cure line's order among zombies (M.zombieOrder, #508's review).
-- The engine can open a command window for a member who fell after its turn
-- was queued: tomb_zombie at c24a73d3, entity 0 Wounded at pf2157, its window
-- open at pf2180 ($7BCA 01, $62CA 00, state $05) until the engine took it off
-- the queue at pf2321 and closed it at pf2334
-- (build/attempts/wt/v039-down-actor/probe_c24.log), and the driver planned
-- "cure entity 3's Zombie" for it.  M.planGate is the gate makePlan sits
-- behind (Driver:button), M.planBackOut the check a held plan passes each
-- pulse.  Pure functions, stubbed inputs: no ROM, no emulator, no gameplay
-- claim (the played evidence is in the commit that added this file).
-- Every assertion runs twice: against the lib as it is (it must hold) and
-- against a mutant of the lib function's own source -- one edit, made here,
-- loaded beside the real one -- under which it must fail.
-- The driver's half is stubbed the way fight_drops_selftest stubs it: emu.read
-- is a table, and Driver:button runs once on it; its mutant is the lib with
-- the gate's hold edited out, loaded whole beside the real one.
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
print = function(s) printed[#printed + 1] = tostring(s) end
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
local checks, n = {}, 0
local function check(what, name, from, to, f)
  n = n + 1
  local ok, r = pcall(f)
  assert(ok and r == true, "FAIL " .. what .. ": " .. tostring(r))
  local real = H[name]
  H[name] = mutant(name, from, to)
  local mok, mr = pcall(f)
  H[name] = real
  assert(not mok or mr ~= true, string.format("FAIL %s: the mutant ('%s' -> '%s') passed it too",
    what, from, to))
  checks[#checks + 1] = what
end

-- ---- the planning gate -------------------------------------------------------
local CMD = 0x05
-- the probe's frame: window open at command select, entity 0 Wounded at 0 HP
local fallen = { menu = 0x01, st = CMD, s1 = 0x80, hp = 0 }
check("a fallen member's open command window is not planned (#510's frame: STATUS1 $80, HP 0)",
  "actorDown", "(s1 & 0xC0) ~= 0 then return true", "false then return true", function()
    -- HP 0 alone would also say down; the Wound bit has to say it with HP left
    -- (the engine sets it a frame before the HP: pf2156 $80 at 1798)
    return H.planGate(fallen) == "down" and H.planGate({ menu = 1, st = CMD, s1 = 0x80, hp = 1798 }) == "down"
  end)
check("a statue's window is not planned (Petrify, STATUS1 $40)",
  "actorDown", "0xC0", "0x80", function()
    return H.planGate({ menu = 1, st = CMD, s1 = 0x40, hp = 900 }) == "down"
  end)
check("a member at 0 HP without Wound or Zombie is down",
  "actorDown", "return o.hp == 0 and", "return false and", function()
    return H.planGate({ menu = 1, st = CMD, s1 = 0x00, hp = 0 }) == "down"
  end)
check("an hp the caller does not give says nothing (battle_healpolicy's status-only planBackOut calls)",
  "actorDown", "return o.hp == 0 and", "return (o.hp or 0) == 0 and", function()
    return H.actorDown({ s1 = 0x00 }) == false and H.planBackOut({ kind = "fight", st1 = 0x00, st2 = 0 }) == nil
      and H.actorDown({ s1 = 0x80 }) == true
  end)
check("a zombie (0 HP, STATUS1 $02, no Wound) passes the gate: the zombie rule defers it",
  "actorDown", "and (s1 & M.ST1_ZOMBIE) == 0", "", function()
    return H.planGate({ menu = 1, st = CMD, s1 = 0x02, hp = 0 }) == nil
  end)
check("a standing member at command select is planned",
  "planGate", 'if M.actorDown({ s1 = o.s1, hp = o.hp }) then return "down" end',
  'if true then return "down" end', function()
    return H.planGate({ menu = 1, st = CMD, s1 = 0x00, hp = 1500 }) == nil
  end)
check("no plan with the window closed ($7BCA 0), whatever the state byte reads",
  "planGate", 'if (o.menu or 0) == 0 then return "closed" end', "", function()
    -- the probe's pf2335: menu 00 with the actor byte still 00, state 00 --
    -- and a closed window with a stale $05 left in the state byte
    return H.planGate({ menu = 0, st = CMD, s1 = 0x00, hp = 1500 }) == "closed"
  end)
check("no plan outside command select (the state the window shows is $05)",
  "planGate", "if o.st ~= 0x05 then", "if false then", function()
    return H.planGate({ menu = 1, st = 0x0A, s1 = 0x00, hp = 1500 }) == "state"
      and H.planGate({ menu = 1, st = 0x38, s1 = 0x00, hp = 1500 }) == "state"
  end)
check("a held plan whose actor fell backs out",
  "planBackOut", 'if M.actorDown({ s1 = o.st1, hp = o.hp }) then return "down" end', "", function()
    return H.planBackOut({ kind = "item", st1 = 0x80, hp = 0 }) == "down"
      and H.planBackOut({ kind = "item", st1 = 0x00, hp = 1500 }) == nil
      and H.planBackOut({ kind = "item", committed = true, st1 = 0x80, hp = 0 }) == nil
      and H.planBackOut({ kind = "item", st1 = 0x02, hp = 0 }) == "zombied"
  end)

-- ---- the cure line's order among zombies (M.zombieOrder) ---------------------
local function eq(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end
local function since(t) return function(e) return t[e] end end
check("zombies take their places by landing tick, the longest-standing first",
  "zombieOrder", "if a.t ~= b.t then return a.t < b.t end", "if a.t ~= b.t then return a.t > b.t end", function()
    -- tomb_zombie at 63e0f747: entity 3 Zombied since f+5, entity 1 since f+493
    return eq(H.zombieOrder({ 0, 1, 2, 3 }, since({ [1] = 493, [3] = 5 })), { 0, 3, 2, 1 })
  end)
check("a tie in landing tick goes to entity order",
  "zombieOrder", "return a.e < b.e", "return a.e > b.e", function()
    return eq(H.zombieOrder({ 0, 3, 1, 2 }, since({ [3] = 40, [1] = 40 })), { 0, 1, 3, 2 })
  end)
check("a zombie standing before the watcher's first tick (-1) goes first",
  "zombieOrder", "if a.t ~= b.t then return a.t < b.t end", "if a.t ~= b.t then return (a.t < 0 and 1e9 or a.t) < (b.t < 0 and 1e9 or b.t) end", function()
    return eq(H.zombieOrder({ 2, 0, 1, 3 }, since({ [0] = 7, [3] = -1 })), { 2, 3, 1, 0 })
  end)
check("the actor keeps first place, a zombie itself (the zombie rule defers it)",
  "zombieOrder", "for i = 2, #order do", "for i = 1, #order do", function()
    return eq(H.zombieOrder({ 1, 0, 2, 3 }, since({ [1] = 900, [2] = 3 })), { 1, 0, 2, 3 })
  end)
check("the places that hold no zombie keep their members",
  "zombieOrder", "for k, i in ipairs(at) do order[i] = zs[k].e end",
  "for k, e in ipairs(zs) do order[k + 1] = e.e end", function()
    -- entities 0 and 2 stand; the zombies at places 3 and 4 swap, 0 and 2 stay put
    return eq(H.zombieOrder({ 1, 0, 2, 3 }, since({ [0] = nil, [2] = 50, [3] = 10 })), { 1, 0, 3, 2 })
  end)

-- ---- the gate in the driver (Driver:button) ----------------------------------
local MENU, ACTOR, MSTATE, ST1, HP = 0x7BCA, 0x62CA, 0x7BC2, 0x3EE4, 0x3BF4
local function word(a, v) mem[a] = v & 0xFF; mem[a + 1] = v >> 8 end
-- #510's frame: entity 0's window open at command select, entity 0 Wounded at
-- 0 HP; entity 3 Zombied (the cure the dead member planned); 1 and 2 stand
local function fallenFrame()
  for k in pairs(mem) do mem[k] = nil end
  printed = {}
  mem[MENU], mem[ACTOR], mem[MSTATE] = 1, 0, CMD
  for e = 0, 3 do word(0x3C1C + e * 2, 1700) end
  mem[ST1] = 0x80
  word(HP + 2, 213); word(HP + 4, 1500)
  mem[ST1 + 6] = 0x02
end
local function said(pat)
  for _, s in ipairs(printed) do if s:find(pat, 1, true) then return true end end
  return false
end
local function driverCase(lib0)
  local F = lib0.newFightDriver("gate", {})
  local D = F.driver
  lib0.frame = 100
  fallenFrame()
  D.menuStreak = 10
  local held = D:button(0)
  local noPlan = D.plan == nil and D.careActor == nil and (held == nil or #held == 0)
    and said("actor=0 is down")
  -- a plan held from before the fall: B out of the item list, the care budget released
  fallenFrame()
  mem[MSTATE] = 0x0A
  D.plan, D.planActor, D.careActor = { kind = "item", item = 0xF1, target = 3, row = 3, idx = 0 }, 0, 0
  local back = D:button(0)
  return noPlan and said("went down after its item")
    and D.plan == nil and D.careActor == nil and back ~= nil and back[1] == "b"
end
do
  n = n + 1
  local ok, r = pcall(driverCase, H)
  assert(ok and r == true, "FAIL the driver plans nothing for a fallen member's window: " .. tostring(r))
  -- the mutant: the gate's hold taken out of Driver:button, the lib loaded whole
  local from = 'if why ~= nil then return nil end'
  local _, count = lib:gsub(plain(from), "")
  assert(count == 1, "the driver's gate line occurs " .. count .. " times")
  local mlib = lib:gsub(plain(from), 'if why ~= nil and why ~= "down" then return nil end')
  local Hm = assert(load(mlib, "=mutant ot6.lua"))()
  local mok, mr = pcall(driverCase, Hm)
  assert(not mok or mr ~= true, "FAIL the driver's gate: the mutant (no hold for a fallen member) passed it too")
  checks[#checks + 1] = "the driver plans nothing for a fallen member's open window, and a plan held "
    .. "through the fall backs out with its care turn released (Driver:button, stubbed RAM)"
end

print = rawPrint
print(string.format("plan_gate_selftest: PASS -- %d assertions, each failed by its own mutant: %s",
  n, table.concat(checks, "; ")))
