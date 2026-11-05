-- @manual standalone: lua tools/tests/raise_threat_selftest.lua  (after ninja build/ot6.sfc)
-- raise_threat_selftest.lua -- what the raise rule's bar is made of (#508).
-- A Fenix Down's HP has to clear the ordinary damage the living enemy
-- deals; an attack that kills at any HP (Doom, X-Zone, a Wound Special) is
-- no hit HP clears, and a fraction (Demi, Quartr) measured on a member at
-- full HP is no price for a raise at 1/8 of it.  The classes come from the
-- built ROM's MagicProp records at ff6/rom/ff6-en.dbg's symbol; RAM is a
-- stub table.  No emulator, no gameplay claim (the played evidence is in
-- the commit that added this file).
-- Every assertion runs twice: against the lib as it is (it must hold) and
-- against a mutant of the lib function's own source -- one edit, made
-- here, loaded beside the real one -- under which it must fail.
emu = { eventType = { inputPolled = 1 }, addEventCallback = function() return 1 end }
local H = dofile("tools/tests/lib/ot6.lua")

local function slurp(path)
  local f = assert(io.open(path, "rb"), path)
  local s = f:read("a"); f:close(); return s
end
local rom = slurp("build/ot6.sfc")
local dbg = slurp("ff6/rom/ff6-en.dbg")
local lib = slurp("tools/tests/lib/ot6.lua")
local function symbol(name)
  local val = dbg:match('sym\tid=%d+,name="' .. name .. '",addrsize=absolute,scope=%d+,def=%d+,ref=[%d+]+,val=0x(%x+),seg=%d+,type=lab')
  return assert(tonumber(val, 16), name .. " in ff6-en.dbg")
end
local MAGIC = symbol("MagicProp") & 0x3FFFFF
-- the lib's ROM and RAM readers, stubbed: the ROM from the file, RAM a table
local ram = {}
H.sym = function(name) return symbol(name) end
H.readRomByte = function(a) return rom:byte(a + 1) end
H.readByte = function(a) return ram[a] or 0 end
local function rec(a) return function(i) return rom:byte(MAGIC + a * 14 + i + 1) end end
local function bytesOf(t) return function(i) return t[i + 1] or 0 end end

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

-- ---- the records ------------------------------------------------------------
assert(rom:byte(MAGIC + 0x0D * 14 + 11) == 0x80 and rom:byte(MAGIC + 0x0D * 14 + 7) == 0,
  "Doom ($0D) in MagicProp: Wound in status 1 (+$0a), power 0")
assert(rom:byte(MAGIC + 0x30 * 14 + 11) & 0x80 ~= 0 and rom:byte(MAGIC + 0x30 * 14 + 5) & 0x05 == 0x05,
  "Life ($30) in MagicProp: Wound in +$0a beside the heal and status-lift flags (+4 bits 0, 2)")
check("Doom ($0D) and X-Zone ($12) kill at any HP",
  "attackClass", "(byteAt(10) & 0x80) ~= 0", "(byteAt(10) & 0x40) ~= 0",
  function() return H.attackClass(rec(0x0D)) == "wound" and H.attackClass(rec(0x12)) == "wound" end)
check("Life, Life 2 and Revive ($30, $31, $50) are heals, though they name Wound",
  "attackClass", 'if (f4 & 0x01) ~= 0 then return "heal" end', "",
  function()
    return H.attackClass(rec(0x30)) == "heal" and H.attackClass(rec(0x31)) == "heal"
      and H.attackClass(rec(0x50)) == "heal"
  end)
check("an attack that lifts Wound is no Wound attack (synthetic: +4 = $04, +$0a = $80)",
  "attackClass", "(f4 & 0x04) == 0 and ", "",
  function() return H.attackClass(bytesOf({ 0, 0, 0, 0, 0x04, 0, 0, 0, 0, 0, 0x80 })) == nil end)
check("Demi ($10) and Quartr ($11) take a fraction",
  "attackClass", 'if (f4 & 0x80) ~= 0 then return "fraction" end', "",
  function() return H.attackClass(rec(0x10)) == "fraction" and H.attackClass(rec(0x11)) == "fraction" end)
-- ordinary damage, Blow Fish's fixed 1000 with it, is what HP has to clear
assert(H.attackClass(rec(0x00)) == nil and H.attackClass(rec(0x0F)) == nil and H.attackClass(rec(0x90)) == nil,
  "Fire, Flare and Blow Fish are ordinary damage")
-- the whole Wound class in this ROM, for the record (an enemy skill among
-- them reaches the ledger through a command other than Magic)
local wound = {}
for a = 0, 0xED do if H.attackClass(rec(a)) == "wound" then wound[#wound + 1] = string.format("$%02X", a) end end

-- ---- a monster's Special ----------------------------------------------------
check("a Special whose status is 7 sets Wound, with damage or without ($07, $47)",
  "specialClass", "& 0x3F) == 0x07", "& 0xFF) == 0x07",
  function() return H.specialClass(0x07) == "wound" and H.specialClass(0x47) == "wound" end)
check("a Special that multiplies damage ($27) or sets another status ($06) is not",
  "specialClass", "== 0x07 and", ">= 0x07 and",
  function() return H.specialClass(0x27) == nil and H.specialClass(0x06) == nil end)

-- ---- the action -------------------------------------------------------------
local SKILL = tonumber(wound[5]:sub(2), 16)    -- an enemy skill past the Magic range
assert(SKILL >= 0x36, "a Wound attack past the Magic command's range: " .. table.concat(wound, " "))
check("an enemy skill with Wound is HP-blind whatever command carries it",
  "actClass", "if atk >= 0xEE then return nil end", "if atk >= 0x36 then return nil end",
  function() return H.actClass(0x0C, SKILL, 0) == "wound" end)
check("a Special reads its own slot's byte ($322d + 8 + 2 * slot)",
  "actClass", "M.readByte(0x322D + 8 + slot * 2)", "M.readByte(0x322D + slot * 2)",
  function()
    ram = { [0x322D + 8 + 2 * 2] = 0x47 }
    local r = H.actClass(0x00, 0xEF, 2) == "wound" and H.actClass(0x00, 0xEF, 1) == nil
    ram = {}
    return r
  end)
check("an item's id is no attack (cmd $01 with $0D is not Doom)",
  "actClass", "cmd == 0x01 or ", "",
  function() return H.actClass(0x01, 0x0D, 0) == nil end)

-- ---- the status landing -----------------------------------------------------
check("a Wound enemy skill that leaves the victim Wounded is a status landing, not a hit",
  "statusDrop", 'and M.actClass(cmd, atk, slot) == "wound" then', "and false then",
  function()
    return H.statusDrop(0x00, 0x80, 0x0C, SKILL, 0, 0, 0) == true
      and H.statusDrop(0x00, 0x00, 0x0C, SKILL, 0, 0, 0) == false     -- it missed: HP lost is a hit
      and H.statusDrop(0x00, 0x80, 0x00, 0xEE, 0, 0, 0) == false      -- a Battle that killed is a hit
  end)

-- ---- the ledger -------------------------------------------------------------
-- Phoenix Cave's shape (fix6_k0_s0 at c24a73d3): a Demi took STRAGO 2334 ->
-- 1167, and an ordinary spell later took 467 off him.  Under the old ledger
-- the Demi's 1167 was "the smallest hit" until the 467 came in.
local function phoenix()
  local L = H.ledgerCommit(nil, { cmd = 0x02, party = 0x4 },
    { { e = 2, drop = 1167, last = 2334, hp = 1167, frac = 0x10 } })
  return L
end
check("a fraction is not the smallest hit, nor the ordinary worst; the living's worst keeps it",
  "ledgerCommit", "if d.frac ~= nil then\n      -- (the raise's", "if false then\n      -- (the raise's",
  function()
    local L = phoenix()
    return L.on[2] == nil and L.min == nil and L.lb == nil and L.maxOn[2] == 1167
  end)
check("a fraction's attack is kept for the raise's pricing, out of the ordinary worst",
  "ledgerCommit", "if d.frac ~= nil then\n      L.fracAtks", "if false then\n      L.fracAtks",
  function()
    local L = phoenix()
    return L.fracAtks ~= nil and L.fracAtks[0x10] == true and L.ordMax == nil
  end)
check("an ordinary hit still goes in every column",
  "ledgerCommit", "if L.ordMax == nil or v > L.ordMax then L.ordMax = v end", "",
  function()
    local L = H.ledgerCommit(phoenix(), { cmd = 0x02, party = 0x4 },
      { { e = 2, drop = 467, last = 467, hp = 0 } })
    return L.lbOn[2] == 467 and L.ordMaxOn[2] == 467 and L.ordMax == 467 and L.maxOn[2] == 1167
  end)

-- ---- the raise's price ------------------------------------------------------
local function takeOf(atk, hp) return H.fixedTake(rec(atk), hp, 3219) end
-- the #503 wipe's Necromancer: Quartr took STRAGO 3219 -> 805
local function quartr()
  return H.ledgerCommit(nil, { cmd = 0x02, party = 0x8 },
    { { e = 3, drop = 2414, last = 3219, hp = 805, frac = 0x11 } })
end
check("a Quartr is priced on the raise's 402, not on the 3219 it was measured on (301)",
  "raiseWorst", "local w = L.ordMaxOn and L.ordMaxOn[e] or L.ordMax", "local w = L.maxOn and L.maxOn[e] or L.max",
  function() return H.raiseWorst(quartr(), 3, 402, takeOf) == 301 end)
check("a slot whose only landing was a fraction still prices one",
  "raiseWorst", "local t = takeOf(atk, raiseHp)", "local t = nil",
  function() return H.raiseWorst(quartr(), 3, 402, takeOf) == 301 end)
check("the ordinary worst stands over a smaller fraction (467 over Demi's 145 of 291)",
  "raiseWorst", "if t ~= nil and (w == nil or t > w) then w = t end", "if t ~= nil then w = t end",
  function()
    local L = H.ledgerCommit(phoenix(), { cmd = 0x02, party = 0x4 }, { { e = 2, drop = 467, last = 467, hp = 0 } })
    return H.raiseWorst(L, 2, 291, takeOf) == 467
  end)

-- ---- the decision ------------------------------------------------------------
-- the Quartr alone: the raise to 402 survives a round of it (one action, 301)
do
  local L = quartr()
  local _, ok, why = H.raiseDecision({ maxhp = 3219, power = 2, smallestHit = L.min,
    roundCost = H.raiseWorst(L, 3, 402, takeOf) })
  assert(ok == true, "a raise to 402 under a Quartr-only enemy stands: " .. tostring(why))
  -- the old bar: the 2414 the Quartr took off full HP, refused
  local _, okOld = H.raiseDecision({ maxhp = 3219, power = 2, smallestHit = 2414, roundCost = 2414 })
  assert(okOld == false, "the old bar refuses it")
end
-- ordinary damage stays as it was: Doom Gaze's Battle (1622 off STRAGO,
-- old_base_k4_s5 in build/attempts/wt/v039-doomgaze/lab/logs) refuses a
-- 402 raise that a Potion cannot lift clear of it
do
  local _, ok = H.raiseDecision({ maxhp = 3221, power = 2, smallestHit = 1622, roundCost = 1622,
    topUpFirst = true, topUp = 250 })
  assert(ok == false, "a 402 raise under a 1622 Battle is still refused")
end

print(string.format("raise_threat_selftest: PASS -- %d assertions, each failed by its own mutant: %s; "
  .. "the ROM's Wound attacks: %s", n, table.concat(checks, "; "), table.concat(wound, " ")))
