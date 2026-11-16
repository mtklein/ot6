-- @manual standalone: lua tools/tests/relm_policy_selftest.lua
-- relm_policy_selftest.lua -- the fight driver's use of RELM's list (#538,
-- M.relmPolicy; docs/design/kit-relm.md section 5): which row, on whom, in
-- what order, against hand-built battle snapshots.  Pure function, no ROM,
-- no emulator, no gameplay claim (the played evidence is the line's [relm]
-- lines and battle_relmkit / battle_relmwor).  Every assertion runs twice:
-- against the lib as it is (it must hold) and against a mutant of
-- M.relmPolicy's own source -- one edit, made here -- under which it must
-- fail.
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
local function mutant(from, to)
  local a = lib:find("\nfunction M%.relmPolicy%(")
  assert(a, "M.relmPolicy in the lib")
  local b = lib:find("\nend\n", a, true)
  local src = lib:sub(a + 1, b + 4)
  local _, count = src:gsub(plain(from), "")
  assert(count == 1, string.format("mutant: '%s' occurs %d times", from, count))
  src = src:gsub(plain(from), (to:gsub("%%", "%%%%")))
  local chunk = assert(load("local M = setmetatable({}, { __index = ... })\n" .. src
    .. "\nreturn M.relmPolicy", "mutant", "t", _G))
  return chunk(H)
end
assert(H.BATTLE_RELM ~= nil, "the lib exports BATTLE.RELM (M.BATTLE_RELM)")

-- a snapshot: RELM at seat 1 with everything learned, three allies up, two
-- monsters, nothing broken, nothing painted
local function snap(f)
  local s = { event = true, relm = 1, mp = 500, bank = 1, knows = {}, press = 0, gestured = false,
    party = {}, mons = {} }
  for _, id in ipairs({ 0xE9, 0xEA, 0xEB, 0xEC, 0xED, 0xEE, 0xEF }) do s.knows[id] = true end
  for seat = 0, 3 do
    s.party[seat] = { up = true, gift = false, coat = seat == 0, tint = 0, gauge = 0x40, queued = false,
      maxhp = 4000 + seat * 100, atk = 100 + seat * 10, wpn = 0, bank = 1, fights = true }
  end
  for slot = 0, 1 do
    s.mons[slot] = { up = true, ticks = 0, sh = 3, weak = 0, absorb = 0, null = 0, rev = 0, weakC = 0, revC = 0,
      still = false, under = false }
  end
  if f then f(s) end
  return s
end
local function pick(s) local d = H.relmPolicy(s); return d and d.id, d end

local n = 0
local function check(what, from, to, f)
  n = n + 1
  local ok, r = pcall(f)
  assert(ok and r == true, "FAIL " .. what .. ": " .. tostring(r))
  local real = H.relmPolicy
  H.relmPolicy = mutant(from, to)
  local mok, mr = pcall(f)
  H.relmPolicy = real
  assert(not mok or mr ~= true, string.format("FAIL %s: the mutant ('%s' -> '%s') passed it too", what, from, to))
end

check("a random battle keeps her Fight", "if not s.event then return nil end", "", function()
  return pick(snap(function(s) s.event = false; s.party[0].coat = false end)) == nil
end)
check("nothing pays: her Fight (a coat stands, nothing broken or weak)", "if not any then", "if true then", function()
  return pick(snap()) == nil
end)
check("Varnish when no coat stands, on the lowest max HP", "p.maxhp < bestH", "p.maxhp > bestH", function()
  local id, d = pick(snap(function(s) s.party[0].coat = false end))
  return id == 0xEB and d.seat == 0
end)
check("Tint on the strongest ally whose weapon lacks the press target's weakness", "((p.wpn or 0) & w) == 0",
  "true", function()
  local id, d = pick(snap(function(s)
    s.mons[0].weak = 0x06; s.mons[0].absorb = 0x02     -- weak to ice and bolt, absorbs ice
    s.party[3].wpn = 0x04                              -- the strongest holds bolt already
  end))
  return id == 0xEA and d.seat == 2 and d.colour == 2
end)
check("Tint passes over an ally with no Fight row", "p.fights and ", "", function()
  local id, d = pick(snap(function(s) s.mons[0].weak = 0x01; s.party[3].fights = false end))
  return id == 0xEA and d.seat == 2
end)
check("Tint passes over an ally already tinted", "(p.tint or 0) == 0", "true", function()
  local id, d = pick(snap(function(s) s.mons[0].weak = 0x01; s.party[3].tint = 2 end))
  return id == 0xEA and d.seat == 2
end)
check("Still Life on a Broken body with more than half its break left", "m.ticks > 8", "m.ticks > 12", function()
  local id, d = pick(snap(function(s) s.mons[1].ticks = 11 end))
  return id == 0xEC and d.slot == 1
end)
check("Still Life passes over a body marked or held", "not m.still", "true", function()
  local id = pick(snap(function(s) s.mons[1].ticks = 11; s.mons[1].still = true end))
  return id ~= 0xEC
end)
check("Underpainting on four shields with a key revealed", "m.sh >= 4", "m.sh >= 5", function()
  local id, d = pick(snap(function(s) s.mons[1].sh = 4; s.mons[1].weakC = 0x02; s.mons[1].revC = 0x02 end))
  return id == 0xED and d.slot == 1
end)
check("Underpainting waits for a revealed key", "((m.weak & m.rev) ~= 0 or (m.weakC & m.revC) ~= 0)", "true",
  function()
  local id = pick(snap(function(s) s.mons[1].sh = 5; s.mons[1].weakC = 0x02 end))
  return id ~= 0xED
end)
check("Gesture while a body is Broken, on the strongest ally under half a gauge", "p.gauge < 0x80", "true",
  function()
  local id, d = pick(snap(function(s)
    s.mons[0].ticks = 4; s.mons[0].still = true       -- Broken, Still Life held already
    s.party[3].gauge = 0x90                            -- the strongest is over half
  end))
  return id == 0xEE and d.seat == 2
end)
check("no Gesture off a Gestured turn", "not s.gestured", "true", function()
  local id = pick(snap(function(s) s.mons[0].ticks = 4; s.mons[0].still = true; s.gestured = true end))
  return id ~= 0xEE
end)
check("Portrait while a body is Broken, on the ally with the most banked", "(p.bank or 0) > bestB",
  "(p.bank or 0) < bestB", function()
  local id, d = pick(snap(function(s)
    s.mons[0].ticks = 4; s.mons[0].still = true
    for seat = 0, 3 do s.party[seat].queued = true end -- nobody to Gesture
    s.party[2].bank = 3
  end))
  return id == 0xE9 and d.seat == 2
end)
check("Masterpiece at three banked with a body Broken", "s.bank >= 3", "s.bank >= 4", function()
  local id, d = pick(snap(function(s) s.bank = 3; s.mons[0].ticks = 4 end))
  return id == 0xEF and d.boost == 3
end)
check("Masterpiece at three banked when two allies hold two", "two >= 2", "two >= 3", function()
  local id = pick(snap(function(s) s.bank = 3; s.party[0].bank = 2; s.party[2].bank = 2 end))
  return id == 0xEF
end)
check("no Masterpiece with fewer than two allies to gift", "takers >= 2", "takers >= 1", function()
  local id = pick(snap(function(s)
    s.bank = 3; s.mons[0].ticks = 4; s.mons[0].still = true
    s.party[0].gift = true; s.party[2].gift = true
  end))
  return id ~= 0xEF
end)
check("each row leaves the MP floor", "s.mp - R.PRICE[id] >= floor", "s.mp >= R.PRICE[id]", function()
  local id = pick(snap(function(s) s.mp = 25; s.party[0].coat = false end))
  return id == nil
end)
print = rawPrint
print(string.format("relm_policy_selftest: %d checks, each with its mutant red", n))
