-- @manual standalone: lua tools/tests/cover_absorb_selftest.lua  (after ninja build/ot6.sfc)
-- cover_absorb_selftest.lua -- two guards on a Fight that cannot do what it
-- is for, on a stubbed battle: RAM is a stub table, the ROM's ItemProp,
-- MagicProp and MonsterProp records come from build/ot6.sfc; no emulator,
-- no gameplay claim.
--   #531  Driver:coverPlan: a Fight whose every body is under Love Token
--         lands on a party member (the bodyguard, the swinger himself or an
--         ally); with no cast, it becomes a verb the cover does not take (the
--         hand's other verb, SETZER's Coin Toss) or Defend, never the Fight.
--   #529  Driver:absorbWeaponPlan: a Fight at a body that absorbs the hand's
--         element re-aims at a body that does not, and the absorb byte is
--         the slot's live one ($3BCC), not the species' ROM byte.
-- Every case runs against the library as it is (it must hold) and against a
-- mutant of the library's own source (one or more edits, loaded as a second
-- library) under which it must fail.
emu = { eventType = { inputPolled = 1 }, addEventCallback = function() return 1 end }
local LIB = "tools/tests/lib/ot6.lua"

local function slurp(path)
  local f = assert(io.open(path, "rb"), path)
  local s = f:read("a"); f:close(); return s
end
local rom = slurp("build/ot6.sfc")
local dbg = slurp("ff6/rom/ff6-en.dbg")
local libSrc = slurp(LIB)
local symMemo = {}
local function sym(name)
  if symMemo[name] == nil then
    local val = dbg:match('sym\tid=%d+,name="' .. name .. '",addrsize=absolute,scope=%d+,def=%d+,ref=[%d+]+,val=0x(%x+),seg=%d+,type=lab')
    symMemo[name] = assert(tonumber(val, 16), name .. " in ff6-en.dbg")
  end
  return symMemo[name]
end
-- the weapon guard reads the hands only where the ROM's symbols are loaded (a pure-Lua stage has none)
OT6_SYMS = { ItemProp = sym("ItemProp") }
local ITEMPROP, MONPROP = sym("ItemProp") & 0x3FFFFF, sym("MonsterProp") & 0x3FFFFF

local mem = {}
local function w8(a, v) mem[a] = v & 0xFF end
local function w16(a, v) mem[a] = v & 0xFF; mem[a + 1] = (v >> 8) & 0xFF end

local function libFrom(src)
  local path = os.tmpname()
  local f = assert(io.open(path, "wb")); f:write(src); f:close()
  local H = dofile(path)
  os.remove(path)
  H.sym = sym
  H.readRomByte = function(off) return rom:byte(off + 1) end
  H.readRomWord = function(off) return rom:byte(off + 1) | (rom:byte(off + 2) << 8) end
  H.readByte = function(a) return mem[a] or 0 end
  H.readWord = function(a) return (mem[a] or 0) | ((mem[a + 1] or 0) << 8) end
  H.log = function() end
  return H
end
local REAL = libFrom(libSrc)
local function plain(s) return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")) end
local function mutantLib(edits)
  local src = libSrc
  for _, e in ipairs(edits) do
    local _, count = src:gsub(plain(e[1]), "")
    assert(count == 1, string.format("mutant edit '%s' occurs %d times in the lib", e[1], count))
    src = src:gsub(plain(e[1]), (e[2]:gsub("%%", "%%%%")))
  end
  return libFrom(src)
end

local SETZER, EDGAR, TERRA = 0x09, 0x04, 0x00
local QUIET = 0x00D            -- a body whose ROM absorbs nothing (MonsterProp +23 = 0)
local ICE_WEAPON = 0x0E        -- a weapon whose element is $02 (ItemProp +15), checked below
-- a battle: party entity 0 (character `ch`, level 46) and entity 1, 3000 HP each; entity 0's command
-- table `cmds` (Fight, Item, Slot, none by default); monsters `mons[slot] = { species, hp }`
local function battle(ch, mons, o)
  o = o or {}
  for k in pairs(mem) do mem[k] = nil end
  for x = 0, 18, 2 do w8(0x32CC + x, 0xFF); w8(0x32CD + x, 0xFF) end
  for e = 0, 3 do w8(0x3ED8 + e * 2, 0xFF) end
  for e = 0, 1 do
    w16(0x3BF4 + e * 2, 3000); w16(0x3C1C + e * 2, 3000); w8(0x3B18 + e * 2, 46)
    -- present, not controlling, not seized (CheckCoverTarget's reads)
    w8(0x3AA0 + e * 2, 1); w8(0x32B9 + e * 2, 0x80); w8(0x3359 + e * 2, 0x80)
  end
  w8(0x3ED8, ch); w8(0x3ED8 + 2, TERRA)
  for r, c in ipairs(o.cmds or { 0x00, 0x01, 0x0F, 0xFF }) do w8(0x202E + (r - 1) * 3, c) end
  for s, m in pairs(mons) do
    w16(0x57C0 + s * 2, m[1]); w16(0x3BFC + s * 2, m[2]); w8(0x3AA8 + s * 2, 1)
    w8(0x336C + 8 + s * 2, m.guard or 0xFF)
    w8(0x3BCC + 8 + s * 2, m.absorb or rom:byte(MONPROP + m[1] * 32 + 23 + 1))
  end
  -- gil ($1860-$1862)
  local gil = o.gil or 0
  w16(0x1860, gil & 0xFFFF); w8(0x1862, gil >> 16)
end
local function driver(H)
  local d = H.newFightDriver("cover absorb", { tactical = true }).driver
  d.focusList = function() return nil end
  d.magicOnlyLine = function() return nil end
  return d
end

local n, said = 0, {}
local function check(what, edits, f)
  n = n + 1
  local ok, r = pcall(f, REAL)
  assert(ok and r == true, "FAIL " .. what .. ": " .. tostring(r))
  local mok, mr = pcall(f, mutantLib(edits))
  assert(not mok or mr ~= true, string.format("FAIL %s: the mutant (%s) passed it too", what,
    table.concat((function() local t = {} for _, e in ipairs(edits) do t[#t + 1] = "'" .. e[1] .. "'" end return t end)(), ", ")))
  said[#said + 1] = what
end
assert(rom:byte(ITEMPROP + ICE_WEAPON * 30 + 0x0F + 1) == 0x02 and (rom:byte(ITEMPROP + ICE_WEAPON * 30 + 1) & 0x07) == 1,
  "precondition: item $0E is a weapon whose element is $02")
assert(rom:byte(MONPROP + QUIET * 32 + 23 + 1) == 0, "precondition: species $00D's ROM absorbs nothing")
local function fight(aim) return { kind = "fight", row = 0, boostLeft = 0, aim = aim } end

-- ---- #531: Love Token ---------------------------------------------------------------
local FIGHT_STANDS = { { 'return alt or { kind = "defend", reason = "love_token" }', "return plan" } }
check("SETZER under his own Love Token (he guards the lone body), the purse above his floor: Coin Toss, not the Fight",
  FIGHT_STANDS,
  function(H)
    battle(SETZER, { [0] = { QUIET, 9000, guard = 0x00 } }, { gil = 60000 })
    local p = driver(H):coverPlan(0, fight(0))
    return p.kind == "skill" and p.cmd == 0x0F and p.skill == 0x59 and p.boostLeft == 0
  end)
check("SETZER with the purse at his floor: Defend (no Coin Toss, no Fight into himself)",
  { { "if gil - M.setzerGil(M.readByte(0x3B18 + actor * 2), 30, 0) >= (o.gilFloor or 20000) then", "if true then" } },
  function(H)
    battle(SETZER, { [0] = { QUIET, 9000, guard = 0x00 } }, { gil = 20000 })
    local p = driver(H):coverPlan(0, fight(0))
    return p.kind == "defend"
  end)
check("EDGAR whose blows the token turns on TERRA: his tool, not the Fight",
  { { 'local alt = self:handVerb(actor, "love_token")', "local alt = nil" } },
  function(H)
    battle(EDGAR, { [0] = { QUIET, 9000, guard = 0x02 } }, { cmds = { 0x00, 0x01, 0x09, 0xFF } })
    w8(0x2686, 0xAA); w8(0x2686 + 3, 5)    -- AutoCrossbow x5 in the battle bag
    local p = driver(H):coverPlan(0, fight(0))
    return p.kind == "skill" and p.cmd == 0x09 and p.skill == 0xAA and p.reason == "love_token"
  end)
check("the Fight still goes to another standing body without the token (#466, kept)",
  { { "plan.aim, plan.aimHard = s, s\n      if tc ~= nil", "plan.aim, plan.aimHard = aim, nil\n      if tc ~= nil" } },
  function(H)
    battle(SETZER, { [0] = { QUIET, 9000, guard = 0x00 }, [1] = { QUIET, 9000 } }, { gil = 60000 })
    local p = driver(H):coverPlan(0, fight(0))
    return p.kind == "fight" and p.aimHard == 1
  end)

-- ---- #529: the absorbed weapon ------------------------------------------------------
-- entity 0 (EDGAR) swings item $0E (ice) in his main hand
local function iceHand() w8(0x1600 + 37 * EDGAR + 0x1F, ICE_WEAPON); w8(0x1600 + 37 * EDGAR + 0x20, 0xFF) end
check("a Fight at a body that absorbs the hand's ice re-aims at the body beside it that does not",
  { { "if M.ABSORB_REAIM ~= false then", "if false then" } },
  function(H)
    battle(EDGAR, { [0] = { QUIET, 9000, absorb = 0x02 }, [1] = { QUIET, 9000 } })
    iceHand()
    local p = driver(H):absorbWeaponPlan(0, fight(0))
    return p.kind == "fight" and p.aimHard == 1 and p.aim == 1
  end)
check("the absorb byte is the slot's live one: a body whose ROM absorbs nothing but whose live record drinks ice",
  { { "return (M.readByte(0x3BCC + 8 + slot * 2) & e) ~= 0",
      "return (M.monsterAbsorb(M.readWord(0x57C0 + slot * 2)) & e) ~= 0" } },
  function(H)
    battle(EDGAR, { [0] = { QUIET, 9000, absorb = 0x02 } })
    iceHand()
    -- no other body: the hand's other verb (no Tools row here) falls to the no-line turn or the window handed on
    local p = driver(H):absorbWeaponPlan(0, fight(0))
    return p.kind ~= "fight"
  end)
check("and a body whose live record absorbs nothing takes the Fight, whatever its species' ROM byte",
  { { "return (M.readByte(0x3BCC + 8 + slot * 2) & e) ~= 0", "return true" } },
  function(H)
    battle(EDGAR, { [0] = { QUIET, 9000, absorb = 0x00 } })
    iceHand()
    local p = driver(H):absorbWeaponPlan(0, fight(0))
    return p.kind == "fight" and p.aimHard == nil
  end)
check("the re-aim judges the body the executor steers to (the kill order's first), not the plan's aim",
  { { "local aim = self:fightAimOf(plan)\n  if aim == nil then return plan end\n  local r, l = handsOf(actor)",
      "local aim = plan.aim\n  if aim == nil then return plan end\n  local r, l = handsOf(actor)" } },
  function(H)
    battle(EDGAR, { [0] = { QUIET, 9000, absorb = 0x02 }, [1] = { QUIET, 9000 } })
    iceHand()
    local d = driver(H)
    d.focusList = function() return { { slot = 0 } } end
    local p = d:absorbWeaponPlan(0, fight(1))
    return p.kind == "fight" and p.aimHard == 1
  end)

print(string.format("cover_absorb_selftest: PASS -- %d cases, each failed by its own mutant: %s", n,
  table.concat(said, "; ")))
