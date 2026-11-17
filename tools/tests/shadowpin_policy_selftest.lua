-- @manual standalone: lua tools/tests/shadowpin_policy_selftest.lua
-- shadowpin_policy_selftest.lua -- the fight driver's use of SHADOW's trap (#546, M.shadowPolicy;
-- docs/design/kit-shadow-pin.md section 6): which monster he pins or hobbles, with what, against hand-built
-- battle snapshots.  Pure function, no ROM, no emulator, no gameplay claim (the played evidence is the line's
-- [shadow] lines and battle_shadowpin).  Every assertion runs twice: against the lib as it is (it must hold) and
-- against a mutant of M.shadowPolicy's own source -- one edit, made here -- under which it must fail.
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
  local a = lib:find("\nfunction M%.shadowPolicy%(")
  assert(a, "M.shadowPolicy in the lib")
  local b = lib:find("\nend\n", a, true)
  local src = lib:sub(a + 1, b + 4)
  local _, count = src:gsub(plain(from), "")
  assert(count == 1, string.format("mutant: '%s' occurs %d times", from, count))
  src = src:gsub(plain(from), (to:gsub("%%", "%%%%")))
  local chunk = assert(load("local M = setmetatable({}, { __index = ... })\n" .. src
    .. "\nreturn M.shadowPolicy", "mutant", "t", _G))
  return chunk(H)
end

-- a snapshot: an event battle, SHADOW's Throw row there, two monsters that take Slow and Stop, nothing Slowed,
-- Stopped or Broken; the bag holds a Dirk (150 gil), a Shuriken (30) and a Fire Skean (500), all spare
local function snap(f)
  local s = { event = true, row = true, mons = {}, bag = {
    { id = 0x00, price = 150, sold = true, throw = true, spare = true },
    { id = 0x41, price = 30, sold = true, throw = true, spare = true },
    { id = 0xAB, price = 10, sold = true, throw = true, spare = true },
    { id = 0xE9, price = 5, sold = true, throw = false, spare = true },
  } }
  s.mons[0] = { up = true, st3 = 0, broken = 0, allowed = 0xFF, hp = 3000, species = 0x044 }
  s.mons[1] = { up = true, st3 = 0, broken = 0, allowed = 0xFF, hp = 5000, species = 0x001 }
  if f then f(s) end
  return s
end
local function pick(s) return H.shadowPolicy(s) end

local n = 0
local function check(what, from, to, f)
  n = n + 1
  local ok, r = pcall(f)
  assert(ok and r == true, "FAIL " .. what .. ": " .. tostring(r))
  local real = H.shadowPolicy
  H.shadowPolicy = mutant(from, to)
  local mok, mr = pcall(f)
  H.shadowPolicy = real
  assert(not mok or mr ~= true, string.format("FAIL %s: the mutant ('%s' -> '%s') passed it too", what, from, to))
end

check("a random battle keeps the Fight and skean lines", "if not s.event or not s.row then return nil end",
  "if not s.row then return nil end", function()
  return pick(snap(function(s) s.event = false end)) == nil
end)
check("hobble the free monster with the most HP", "m.hp > hobble.hp", "m.hp < hobble.hp", function()
  local d = pick(snap())
  return d.kind == "hobble" and d.slot == 1
end)
check("pin a Slowed monster before hobbling another", "local aim, kind = pin, \"pin\"",
  "local aim, kind = nil, \"pin\"", function()
  local d = pick(snap(function(s) s.mons[0].st3 = 0x04 end))
  return d.kind == "pin" and d.slot == 0
end)
check("never pin a Broken one", "m.broken == 0 and ", "", function()
  local d = pick(snap(function(s) s.mons[0].st3 = 0x04; s.mons[0].broken = 9 end))
  return d.kind == "hobble" and d.slot == 1
end)
check("never pin a Stop-immune one (it stays hobbled)", "and m.allowed & 0x10 ~= 0 then", "then", function()
  local d = pick(snap(function(s) s.mons[0].st3 = 0x04; s.mons[0].allowed = 0xEF end))
  return d.kind == "hobble" and d.slot == 1
end)
check("nothing at a pinned one", "m.st3 & 0x10 == 0", "true", function()
  local d = pick(snap(function(s)
    s.mons[0].st3 = 0x10; s.mons[0].hp = 9000; s.mons[1].st3 = 0x04; s.mons[1].allowed = 0xEF
  end))
  return d == nil
end)
check("never hobble a Slow-immune one", "m.allowed & 0x04 ~= 0", "true", function()
  local d = pick(snap(function(s) s.mons[1].allowed = 0xEB end))
  return d.kind == "hobble" and d.slot == 0
end)
check("nobody standing to throw at: no line", "m and m.up and", "m and", function()
  return pick(snap(function(s) s.mons[0].up = false; s.mons[1].up = false end)) == nil
end)
-- the line names the body it aims at by the slot's live species, not the formation's opening line-up: the
-- v0.48 line's Telstar battle logged "hobble slot 3 $FFFF" for a Soldier called in mid-battle (formation $03D
-- opens with slot 0 alone)
check("the line names the aimed body's species", "species = s.mons[aim.slot].species", "species = 0xFFFF",
  function()
  local d = pick(snap(function(s)
    s.mons[0].up = false
    s.mons[3] = { up = true, st3 = 0, broken = 0, allowed = 0xFF, hp = 100, species = 0x001 }
    s.mons[1].up = false
  end))
  return d.kind == "hobble" and d.slot == 3 and d.species == 0x001
end)
check("the cheapest throwable, never a skean", "(it.id < 0xAB or it.id > 0xAF)", "true", function()
  local d = pick(snap())
  return d.item == 0x41 and d.price == 30
end)
check("only what the bag can throw", "it.throw and ", "", function()
  local d = pick(snap())
  return d.item == 0x41
end)
check("not from the reserve", "it.throw and it.spare and", "it.throw and", function()
  local d = pick(snap(function(s) s.bag[2].spare = false end))
  return d.item == 0x00
end)
check("never a weapon no shop sells (M.itemSold)", "it.spare and it.sold and", "it.spare and", function()
  -- the Imp Halberd: no shop sells it; priced here below the Shuriken, so only the sold test can refuse it
  local d = pick(snap(function(s) s.bag[#s.bag + 1] = { id = 0x24, price = 2, sold = false, throw = true, spare = true } end))
  return d.item == 0x41
end)
check("nothing to throw: the Fight", "if item == nil then return { kind = \"none\"",
  "if false then return { kind = \"none\"", function()
  local d = pick(snap(function(s) s.bag = { { id = 0xAB, price = 10, sold = true, throw = true, spare = true } } end))
  return d.kind == "none"
end)
print = rawPrint
print(string.format("shadowpin_policy_selftest: %d checks, each with its mutant red", n))
