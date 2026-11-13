-- @manual standalone: lua tools/tests/driver_gaps_selftest.lua
-- driver_gaps_selftest.lua -- four gaps in the harness's play code, each
-- run on stubbed RAM (no ROM, no emulator, no gameplay claim):
--   #471  the [status] line names Mute and Muddle (M.statusNames, and the
--         driver's watcher says each landing and each clear);
--   #470  the scripted kit driver clears what it learned about a plan entry
--         as each battle starts (M.freshKitEntries), its others give care
--         while the plan plays and spend their bank in the fight-out; and the
--         fight driver re-plans a plan whose monster fell before the confirm
--         (M.namedBodyFell);
--   #449  the field care's walk down a long item list is progress, not a
--         stall (the kernel's steer).
-- Every assertion runs twice: against the lib as it is (it must hold) and
-- against a mutant -- one edit to the lib's source, made here -- under which
-- it must fail.
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
local LIB, FIELD = slurp("tools/tests/lib/ot6.lua"), slurp("tools/tests/lib/ot6_field.lua")
local function plain(s) return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")) end
-- the two library halves loaded as a run loads them, either one with one edit
local function load2(lib, field)
  local L = assert(load(lib, "=ot6.lua"))()
  assert(load(field, "=ot6_field.lua"))(L)
  return L
end
local function edited(src, from, to)
  local _, count = src:gsub(plain(from), "")
  assert(count == 1, "the line '" .. from .. "' occurs " .. count .. " times")
  return (src:gsub(plain(from), (to:gsub("%%", "%%%%"))))
end
local H = load2(LIB, FIELD)
local checks, n = {}, 0
-- f(L) must hold on the lib, and fail on the lib with `from` -> `to` in the
-- half `half` names ("lib" or "field")
local function check(what, half, from, to, f)
  n = n + 1
  local ok, r = pcall(f, H)
  assert(ok and r == true, "FAIL " .. what .. ": " .. tostring(r))
  local M2 = half == "field" and load2(LIB, edited(FIELD, from, to)) or load2(edited(LIB, from, to), FIELD)
  local mok, mr = pcall(f, M2)
  assert(not mok or mr ~= true, string.format("FAIL %s: the mutant ('%s' -> '%s') passed it too", what, from, to))
  checks[#checks + 1] = what
end
local function said(pat)
  for _, s in ipairs(printed) do if s:find(pat, 1, true) then return true end end
  return false
end
local function word(a, v) mem[a] = v & 0xFF; mem[a + 1] = v >> 8 end
local function clear() for k in pairs(mem) do mem[k] = nil end; printed = {} end
local function has(t, b) for _, x in ipairs(t) do if x == b then return true end end return false end

-- ---- #471: the [status] line names Mute and Muddle ---------------------------
local function namesHave(L, s2, name)
  for _, x in ipairs(L.statusNames(0, s2, 0, 0, nil)) do if x == name then return true end end
  return false
end
check("M.statusNames names Mute (STATUS2 $08), the status Barb-e's counter landed unsaid (#471)", "lib",
  'if (s2 & M.ST2_MUTE) ~= 0 then names[#names + 1] = "Mute" end', "", function(L)
    return namesHave(L, 0x08, "Mute") and not namesHave(L, 0x00, "Mute")
  end)
check("M.statusNames names Muddle (STATUS2 $20)", "lib",
  'if (s2 & M.ST2_MUDDLE) ~= 0 then names[#names + 1] = "Muddle" end', "", function(L)
    return namesHave(L, 0x20, "Muddle") and not namesHave(L, 0x08, "Muddle")
  end)
-- the driver's watcher on stubbed battle RAM: entity 0 standing, muted, then not
local ST2 = 0x3EE5
local function watchCase(L)
  clear()
  local D = L.newFightDriver("st", {}).driver
  D.battleTick, D.startFrame = 10, 0
  word(0x3C1C, 1500); word(0x3BF4, 900)
  mem[ST2] = 0x08
  D:watchStatuses()
  local on = said("[status] f+10 entity 0 char 0 is under MUTE")
  mem[ST2] = 0x00
  D.battleTick = 11
  D:watchStatuses()
  return on and said("entity 0's Mute is CLEARED")
end
check("the driver's [status] watcher says a Mute landing and its clear", "lib",
  'if (s2 & M.ST2_MUTE) ~= 0 then names[#names + 1] = "Mute" end', "", watchCase)
check("the clear line walks the logged list (M.STATUS_LOGGED) that holds Mute", "lib",
  '"Mute", "Muddle", "Blind"', '"Muddle", "Blind"', watchCase)

-- ---- #470 (2): a plan whose monster fell before the confirm is re-planned -----
local alive = function(set) return function(s) return set[s] == true end end
check("a Fight's class-key aim (no kill order) that fell is named (#470: classtarget s13)", "lib",
  "if named ~= nil and not o.alive(named) then return named end", "", function(L)
    return L.namedBodyFell({ kind = "fight", aim = 2, alive = alive({ [3] = true }) }) == 2
      and L.namedBodyFell({ kind = "fight", aim = 2, alive = alive({ [2] = true }) }) == nil
  end)
check("a body the plan names outright (aimHard) is held to even under a kill order", "lib",
  "local named = o.aimHard", "local named = nil", function(L)
    return L.namedBodyFell({ kind = "lore", aimHard = 1, ordered = true, alive = alive({}) }) == 1
  end)
check("a kill order's aim, an item, a heal, a party cast or a contract is not named", "lib",
  'if named == nil and o.kind ~= "lore" and not o.ordered then named = o.aim end',
  "if named == nil then named = o.aim end", function(L)
    local dead = alive({})
    return L.namedBodyFell({ kind = "fight", aim = 2, ordered = true, alive = dead }) == nil
      and L.namedBodyFell({ kind = "lore", aim = 2, alive = dead }) == nil
      and L.namedBodyFell({ kind = "item", aim = 2, alive = dead }) == nil
      and L.namedBodyFell({ kind = "heal", aim = 2, alive = dead }) == nil
      and L.namedBodyFell({ kind = "magic", aim = 2, ally = true, alive = dead }) == nil
      and L.namedBodyFell({ kind = "fight", aim = 2, contract = true, alive = dead }) == nil
  end)

-- ---- the scripted kit driver (M.kitBattle) on stubbed battle RAM ---------------
-- LOCKE (seat 0), SETZER (seat 1) and two more, one monster (slot 0) standing;
-- the window open is `actor`'s at state `st`
local MENU, ACTOR, MSTATE, HP = 0x7BCA, 0x62CA, 0x7BC2, 0x3BF4
local LOCKE, SETZER = 0x01, 0x09
local CMD = 0x05
local function kitFrame(actor, st)
  clear()
  mem[MENU], mem[ACTOR], mem[MSTATE] = 1, actor, st
  mem[0x3ED8], mem[0x3ED8 + 2], mem[0x3ED8 + 4], mem[0x3ED8 + 6] = LOCKE, SETZER, 0x02, 0x05
  for e = 0, 3 do word(HP + e * 2, 1500); word(0x3C1C + e * 2, 1500); mem[0x3AA0 + e * 2] = 1; mem[0x4001 + e] = 0xFF end
  mem[0x3F45], mem[0x3A77], mem[0x3A75], mem[0xE9F9] = 0x01, 1, 1, 15
  mem[0x3AA8] = 1; word(0x3BFC, 900)
  -- each seat's commands: Fight, Item, Magic, Defend-side rows
  for a = 0, 3 do
    mem[0x202E + a * 12], mem[0x202E + a * 12 + 3], mem[0x202E + a * 12 + 6] = 0x00, 0x01, 0x02
    mem[0x202E + a * 12 + 9] = 0x0F
  end
end
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

-- (1) a plan table played again starts as asked
check("kitBattle clears an entry's greyed flag as a battle starts: a reused plan is played (#470, #468's runicblade)",
  "lib", "      k, cool, aim = 1, 0, nil\n      M.freshKitEntries(plan)\n", "      k, cool, aim = 1, 0, nil\n",
  function(L)
    kitFrame(0, CMD)
    -- the battle before muted LOCKE: his Magic entry was greyed there
    local plan = { { who = LOCKE, cmd = 0x02, spell = 0x00 } }
    plan[1].greyed, plan[1].greyLogged, plan[1].goneLogged = true, true, true
    local pressed = drive(L, L.kitBattle(plan, { care = false }), 30)
    -- his Magic row (2) is steered to, not the Fight the greyed entry plays
    return plan[1].greyed == nil and plan[1].goneLogged == nil and has(pressed, "down")
      and not said("is greyed")
  end)
check("setzerBattle clears its entries the same way", "lib",
  "Z.inFlight = 0; M.freshKitEntries(plan); M.logRomIdentity", "Z.inFlight = 0; M.logRomIdentity", function(L)
    kitFrame(0, CMD)
    local plan = { { row = 0x59 } }
    plan[1].refusedSeen, plan[1].aimRefused, plan[1].confirmedAt = true, "walk", 5
    local realCare = L.newSpinnerCare
    L.newSpinnerCare = function()
      local f = function() return false end
      return { reset = f, watch = f, spinnerTaken = f, allyZombie = f, window = f }
    end
    local stepObj = L.setzerBattle(plan, {})
    L.newSpinnerCare = realCare
    drive(L, stepObj, 3)
    return plan[1].refusedSeen == nil and plan[1].aimRefused == nil and plan[1].confirmedAt == nil
      and plan[1].row == 0x59
  end)

-- (3) the others' care while the plan plays, and the fight-out's bank
local POTION = 0xE9
check("kitBattle: while the plan plays, another member's window gives a hurt member a Potion, not a Defend (#470)",
  "lib", "if care ~= nil and (careActor == a or (careActor == nil and care.wants(a))) then", "if false then",
  function(L)
    -- SETZER's window (seat 1) while LOCKE's entry waits; seat 2 at 300/1500
    kitFrame(1, CMD)
    word(HP + 4, 300)
    mem[0x2686], mem[0x2686 + 3] = POTION, 9
    for i = 1, 251 do mem[0x2686 + i * 5] = 0xFF end
    local pressed = drive(L, L.kitBattle({ { who = LOCKE, cmd = 0x00 } }, {}), 30)
    -- the cursor walks down to Item (row 1); a Defend would be RIGHT
    return has(pressed, "down") and not has(pressed, "right") and said("[care]")
  end)
check("kitBattle: opts.care = false leaves the others' windows to the script (a Defend)", "lib",
  "if opts.care ~= false and M.newSpinnerCare ~= nil then", "if M.newSpinnerCare ~= nil then", function(L)
    kitFrame(1, CMD)
    word(HP + 4, 300)
    mem[0x2686], mem[0x2686 + 3] = POTION, 9
    for i = 1, 251 do mem[0x2686 + i * 5] = 0xFF end
    local pressed = drive(L, L.kitBattle({ { who = LOCKE, cmd = 0x00 } }, { care = false }), 30)
    return has(pressed, "right") and not has(pressed, "down")
  end)
check("kitBattle: the fight-out raises the pending boost to the bank (R) before the Fight (#470)", "lib",
  'if opts.idle == "defend" then defend(st) else fight(a, st, true) end',
  'if opts.idle == "defend" then defend(st) else fight(a, st) end', function(L)
    kitFrame(0, CMD)
    mem[0x3E9C] = 2                     -- LOCKE's bank: 2, nothing pending
    -- each R raises the pending boost by one, up to the bank
    local realSet, wasR = L.setPad, false
    L.setPad = function(b)
      local r = b ~= nil and b.r == true
      if r and not wasR then mem[0x3E9D] = math.min((mem[0x3E9D] or 0) + 1, mem[0x3E9C]) end
      wasR = r
      return realSet(b)
    end
    local pressed = drive(L, L.kitBattle({}, {}), 40)
    L.setPad = realSet
    local rs = 0
    for _, b in ipairs(pressed) do if b == "r" then rs = rs + 1 end end
    return pressed[1] == "r" and rs == 2 and mem[0x3E9D] == 2 and has(pressed, "a")
  end)

-- (2) in the fight driver: its target select with the aimed monster fallen
-- (battle_classtarget s13's frame: slot 2 dead, the cursor fell to slot 3)
local function confirmCase(L, aim)
  kitFrame(0, 0x38)
  mem[0x3AA8], mem[0x3A75] = 0, 0x08
  word(0x3BFC, 0)
  mem[0x3AA8 + 4] = 1; word(0x3BFC + 4, 0)
  mem[0x3AA8 + 6] = 1; word(0x3BFC + 6, 500)
  mem[0x7B7E], mem[0x7B7D] = 0x08, 0
  local D = L.newFightDriver("gate", {}).driver
  L.frame = 100
  D.menuStreak = 10
  D.plan, D.planActor = { kind = "fight", aim = aim, row = 0, boostLeft = 0 }, 0
  return D:button(0), D
end
check("Driver: a Fight whose aimed monster fell before the confirm backs out (B) to re-plan (#470)", "lib",
  "    if fell ~= nil then\n      M.log(string.format(\"[%s] actor=%d: the %s plan's monster",
  "    if false then\n      M.log(string.format(\"[%s] actor=%d: the %s plan's monster", function(L)
    local r, D = confirmCase(L, 2)
    local backed = r ~= nil and r[1] == "b" and D.plan == nil and said("fell before the confirm")
    -- its aim standing under the cursor: confirmed as before
    local r2 = confirmCase(L, 3)
    return backed and r2 ~= nil and r2[1] == "a" and not said("fell before the confirm")
  end)

-- ---- #449: the field care walks a long item list ------------------------------
-- The kernel on a stubbed field menu: one member (char 0) at 100/1000 HP, the
-- bag's only heal a Tonic in row 150 of the item list.  The menu answers each
-- press the way the field menu does: $26 the screen, $4B the cursor (the item
-- list's absolute row, CalcLongListIndex: one column in the English build).
local function careCase(L)
  clear()
  for i = 0, 255 do mem[0x1869 + i] = 0xFF; mem[0x1969 + i] = 0 end
  mem[0x1869 + 150], mem[0x1969 + 150] = 0xE8, 5
  local hp, maxhp = 100, 1000
  L.partyMembers = function() return { 0 } end
  L.charHp = function() return hp end
  L.charMaxHp = function() return maxhp end
  L.charMp = function() return 0 end
  L.charMaxMp = function() return 0 end
  L.charStatus1 = function() return 0 end
  L.battleLoadStarted = function() return false end
  L.worldMode = function() return true end
  mem[0x26], mem[0x4B], mem[0x69] = 0x05, 0, 0
  local held = {}
  L.setPad = function(b)
    local now = {}
    for k2, v in pairs(b or {}) do
      local nm = type(k2) == "number" and v or (v and k2)
      if nm then now[nm] = true end
    end
    for nm in pairs(now) do
      if not held[nm] then                 -- a press (the menu acts on the edge)
        local st, cur = mem[0x26], mem[0x4B]
        if st == 0x05 then
          if nm == "a" and cur == 0 then mem[0x26], mem[0x4B] = 0x08, 0
          elseif nm == "down" then mem[0x4B] = cur + 1 elseif nm == "up" and cur > 0 then mem[0x4B] = cur - 1 end
        elseif st == 0x08 then
          if nm == "down" and cur < 255 then mem[0x4B] = cur + 1
          elseif nm == "up" and cur > 0 then mem[0x4B] = cur - 1
          elseif nm == "a" then mem[0x26] = 0x19
          elseif nm == "b" then mem[0x26] = 0x05 end
        elseif st == 0x19 then
          if nm == "a" then mem[0x26], mem[0x28], mem[0x4B] = 0x70, cur, 0
          elseif nm == "b" then mem[0x26] = 0x08 end
        elseif st == 0x70 then
          if nm == "a" and cur == 0 then
            hp = maxhp
            mem[0x1969 + mem[0x28]] = mem[0x1969 + mem[0x28]] - 1
          elseif nm == "b" then mem[0x26] = 0x08 end
        end
      end
    end
    held = now
  end
  local K = L.careKernel({ tag = "care", magic = false, tent = false, tincture = false, threshold = 0.9 })
  for _ = 1, 6000 do
    K.serveFrame()
    if K.served() then break end
  end
  return said("[care] used $E8 on char 0: 100 -> 1000 hp") and not said("stalled")
end
check("the field care walks 150 rows down the item list to a Tonic (#449: no 'stalled 1201 frames')", "field",
  "      if steerBest[sk] ~= nil then stall = 0 end\n", "", careCase)

print = rawPrint
print(string.format("driver_gaps_selftest: PASS -- %d assertions, each failed by its own mutant: %s",
  n, table.concat(checks, "; ")))
