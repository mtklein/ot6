-- @manual standalone: lua tools/tests/plan_gate_selftest.lua
-- plan_gate_selftest.lua -- when the fight driver may plan a turn (#510),
-- what any driver presses at a fallen member's window (M.downStep; the
-- scripted kit and SETZER drivers, #511), and the cure line's order among
-- zombies (M.zombieOrder, #508's review).
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
  getMemorySize = function() return 0 end,
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
  -- the menu queue: only the fallen member's window (the probe's q=00,FF,FF,FF)
  mem[0x4001], mem[0x4002], mem[0x4003], mem[0x4004] = 0x00, 0xFF, 0xFF, 0xFF
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
    and said("actor=0 is down") and said("waiting for the engine to close it")
  -- entity 2 queued behind the fallen member (battle_doom's case): X hands the window on
  fallenFrame()
  mem[0x4003] = 0x01
  D.downHold = nil
  local pass = D:button(0)
  noPlan = noPlan and D.plan == nil and pass ~= nil and pass[1] == "x"
    and said("handing the window on (X) to actor 2's")
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
  -- the mutants, each the lib loaded whole with one edit to Driver:button:
  -- the gate's hold taken out, and the hand-on to a queued member taken out
  for _, m in ipairs({
    { 'if why ~= nil then return nil end', 'if why ~= nil and why ~= "down" then return nil end',
      "no hold for a fallen member" },
    { 'if behind ~= nil then return "x", "hand-on", behind end', '', "no hand-on to a queued member" },
  }) do
    local _, count = lib:gsub(plain(m[1]), "")
    assert(count == 1, "the driver's line '" .. m[1] .. "' occurs " .. count .. " times")
    local mlib = lib:gsub(plain(m[1]), (m[2]:gsub("%%", "%%%%")))
    local Hm = assert(load(mlib, "=mutant ot6.lua"))()
    local mok, mr = pcall(driverCase, Hm)
    assert(not mok or mr ~= true, "FAIL the driver's gate: the mutant (" .. m[3] .. ") passed it too")
  end
  checks[#checks + 1] = "the driver plans nothing for a fallen member's open window, hands it on (X) "
    .. "when another member is queued behind it, and a plan held "
    .. "through the fall backs out with its care turn released (Driver:button, stubbed RAM)"
end

-- ---- what a fallen member's window gets (M.downStep, #511) -----------------
-- The lib loaded whole with one edit (M.downStep reads the lib's BATTLE
-- table, which a lone function's mutant cannot see).
local function libMutant(from, to)
  local _, count = lib:gsub(plain(from), "")
  assert(count == 1, "the lib's line '" .. from .. "' occurs " .. count .. " times")
  return assert(load((lib:gsub(plain(from), (to:gsub("%%", "%%%%")))), "=mutant ot6.lua"))()
end
local function checkLib(what, from, to, f)
  n = n + 1
  local ok, r = pcall(f, H)
  assert(ok and r == true, "FAIL " .. what .. ": " .. tostring(r))
  local mok, mr = pcall(f, libMutant(from, to))
  assert(not mok or mr ~= true, string.format("FAIL %s: the mutant ('%s' -> '%s') passed it too", what, from, to))
  checks[#checks + 1] = what
end
local NOQ = { [0] = 0xFF, 0xFF, 0xFF, 0xFF }
local function step(L, st, queue, held, spun)
  return L.downStep({ actor = 0, st = st, queue = queue or NOQ, held = held or 0, spun = spun })
end
checkLib("a fallen member's window at command select with nobody queued is held (no button)",
  'if behind ~= nil then return "x", "hand-on", behind end\n    return nil, "hold"',
  'if behind ~= nil then return "x", "hand-on", behind end\n    return "x", "hold"', function(L)
    return step(L, CMD) == nil and step(L, 0x01) == nil
  end)
checkLib("a transitional state ($01) gets no button",
  'return nil, "hold"   -- a transitional state passes on its own', 'return "b", "hold"', function(L)
    return step(L, 0x01) == nil
  end)
checkLib("with members queued, X hands the window to the queue's front (the smallest position)",
  "(behind == nil or q[e] < q[behind])", "(behind == nil or q[e] > q[behind])", function(L)
    local b, why, to = step(L, CMD, { [0] = 0x00, 0x02, 0x01, 0xFF })
    return b == "x" and why == "hand-on" and to == 2
  end)
checkLib("past M.DOWN_HOLD_CAP frames the member Defends (RIGHT at command select), queue or not",
  'if capped then return "right", "cap" end', "", function(L)
    local cap = L.DOWN_HOLD_CAP
    return step(L, CMD, NOQ, cap - 1) == nil and step(L, CMD, NOQ, cap) == "right"
      and step(L, CMD, { [0] = 0, 0xFF, 0x01, 0xFF }, cap) == "right"
  end)
checkLib("the Def. window the cap opened is confirmed (A); one the member had open as it fell is backed out of",
  'if st == BATTLE.ST_DEF and capped then return "a", "cap" end', "", function(L)
    return step(L, 0x27, NOQ, L.DOWN_HOLD_CAP) == "a" and step(L, 0x27, NOQ, 10) == "b"
  end)
checkLib("a list, target select or side window open as the member fell is backed out of (B)",
  'return "b", "back-out"', 'return nil, "back-out"', function(L)
    for _, st in ipairs({ 0x0A, 0x0E, 0x30, 0x38, 0x24, 0x27, 0x2D }) do
      if step(L, st) ~= "b" then return "state " .. st end
    end
    return true
  end)
checkLib("a Slot spin whose first A landed is finished (A); one not started is backed out of",
  'if st == BATTLE.ST_SLOT and o.spun then return "a", "spin" end', "", function(L)
    return step(L, 0x08, NOQ, 0, true) == "a" and step(L, 0x08, NOQ, 0, false) == "b"
  end)

-- ---- the scripted drivers (M.kitBattle, M.setzerBattle; #511) ------------------
-- Their battle step run on stubbed RAM: LOCKE (seat 0), SETZER (seat 1) and
-- two more, one monster; the window open is `actor`'s at state `st`, and
-- `downSeat` is Wounded at 0 HP.
local LOCKE, SETZER = 0x01, 0x09
local function scriptedFrame(actor, st, downSeat)
  for k in pairs(mem) do mem[k] = nil end
  printed = {}
  mem[MENU], mem[ACTOR], mem[MSTATE] = 1, actor, st
  mem[0x3ED8], mem[0x3ED8 + 2], mem[0x3ED8 + 4], mem[0x3ED8 + 6] = LOCKE, SETZER, 0x02, 0x05
  for e = 0, 3 do word(HP + e * 2, 1500); mem[0x3AA0 + e * 2] = 1; mem[0x4001 + e] = 0xFF end
  word(HP + downSeat * 2, 0); mem[ST1 + downSeat * 2] = 0x80
  mem[0x3F45], mem[0x3A77], mem[0x3A75], mem[0xE9F9] = 0x01, 1, 1, 15
  word(0x3BFC, 900)
  for a = 0, 3 do mem[0x202E + a * 12] = 0x00; mem[0x202E + a * 12 + 3] = 0x0F end
end
-- run the battle step `frames` frames; the buttons it pressed, in order
local function drive(L, stepObj, frames, onFrame)
  local pressed, realSet = {}, L.setPad
  L.setPad = function(b)
    for k2, v in pairs(b or {}) do
      local nm = type(k2) == "number" and v or (v and k2)
      if nm then pressed[#pressed + 1] = nm end
    end
    return realSet(b)
  end
  local ok, err = pcall(function()
    for f = 1, frames do
      L.frame = 1000 + f
      if onFrame then onFrame(f) end
      stepObj:tick()
    end
  end)
  L.setPad = realSet
  assert(ok, err)
  return pressed
end
-- (setzerBattle's care for a Zombied or Muddled SETZER lives in ot6_field.lua,
-- which compose.py adds to a run: a care that never steps in stands for it)
local function noCare(L)
  L.newSpinnerCare = function()
    local f = function() return false end
    return { reset = f, watch = f, spinnerTaken = f, allyZombie = f, window = f }
  end
  return L
end
local function has(t, b) for _, x in ipairs(t) do if x == b then return true end end return false end
local function only(t, set) for _, x in ipairs(t) do if not set[x] then return false end end return true end
checkLib("kitBattle: a defend entry's member fell in its Def. window -- no A, the entry not recorded, k stays",
  'local dn = M.downWindow(downHold, a, st, "kit")', "local dn = nil", function(L)
    -- #511's case: a p.defend entry recorded 'a Defend' at state $27 for a dead member
    scriptedFrame(0, 0x27, 0)
    local pressed = drive(L, L.kitBattle({ { who = LOCKE, defend = true } }, {}), 40)
    return #L.vars.kit == 0 and has(pressed, "b") and not has(pressed, "a")
      and said("actor=0 is down") and said("backing out of the window it had open")
  end)
checkLib("kitBattle: a fallen member's command window is handed on (X) to the member queued behind it",
  'local dn = M.downWindow(downHold, a, st, "kit")', "local dn = nil", function(L)
    scriptedFrame(0, CMD, 0)
    mem[0x4002] = 0x00
    local pressed = drive(L, L.kitBattle({ { who = LOCKE, cmd = 0x00 } }, {}), 40)
    return #L.vars.kit == 0 and has(pressed, "x") and only(pressed, { x = true })
      and said("handing the window on (X) to actor 1's")
  end)
checkLib("kitBattle: a fallen member's window with nobody queued is held, then Defended past the cap (logged)",
  'if capped then return "right", "cap" end', "", function(L)
    scriptedFrame(0, CMD, 0)
    local early = drive(L, L.kitBattle({}, {}), 200)
    if #early ~= 0 then return "pressed before the cap: " .. table.concat(early, " ") end
    scriptedFrame(0, CMD, 0)
    local pressed = drive(L, L.kitBattle({}, {}), L.DOWN_HOLD_CAP + 40, function(f)
      if f == L.DOWN_HOLD_CAP + 2 then mem[MSTATE] = 0x27 end   -- (RIGHT opened the Def. window)
    end)
    return pressed[1] == "right" and pressed[2] == "a" and only(pressed, { right = true, a = true })
      and not has({ table.unpack(pressed, 2) }, "right") and said("Defending for it so the window closes")
  end)
checkLib("setzerBattle: SETZER fell with his window open -- no plan row steered, nothing pressed (held)",
  'local dn = M.downWindow(Z.down, a, st, "setzer")', "local dn = nil", function(L)
    scriptedFrame(1, CMD, 1)
    local pressed = drive(L, noCare(L).setzerBattle({ { row = "defend" } }, {}), 40)
    return #pressed == 0 and said("actor=1 is down") and said("waiting for the engine to close it")
  end)
checkLib("setzerBattle: another member's fallen window is not Defended for the plan; it is handed on (X)",
  'local dn = M.downWindow(Z.down, a, st, "setzer")', "local dn = nil", function(L)
    -- LOCKE (not SETZER) fell; SETZER is queued behind him
    scriptedFrame(0, CMD, 0)
    mem[0x4002] = 0x00
    local pressed = drive(L, noCare(L).setzerBattle({ { row = 0x59 } }, {}), 40)
    return has(pressed, "x") and only(pressed, { x = true })
  end)
checkLib("kitBattle: a standing member's window is steered as before, another member down",
  "if not M.actorDown({ s1 = s1, hp = hp }) then return nil end", "if true then return false end", function(L)
    scriptedFrame(0, CMD, 3)
    local pressed = drive(L, L.kitBattle({ { who = LOCKE, defend = true } }, {}), 40)
    return has(pressed, "right")
  end)

print = rawPrint
print(string.format("plan_gate_selftest: PASS -- %d assertions, each failed by its own mutant: %s",
  n, table.concat(checks, "; ")))
