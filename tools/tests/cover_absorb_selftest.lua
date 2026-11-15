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
    w8(0x322D + 8 + s * 2, rom:byte(MONPROP + m[1] * 32 + 0x1F + 1))
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
-- TERRA (entity 1) has a cast ready unless `castless`: a damaging verb the token does not catch, so a Defend
-- waits on something (the stall guard, #533 review)
local function castFor(d, castless)
  w8(0x202E + 12 + 3, 0x02)          -- entity 1's Magic row
  d.magicOnlyLine = function(_, m) if m == 1 and not castless then return { kind = "magic", spell = 0x00 } end end
  return d
end
local SETZER_FLOOR = 20000 + 46 * 30     -- the floor plus one toss at level 46 (M.setzerGil: 30 a level)
local FIGHT_STANDS = { { 'return alt or { kind = "defend", reason = "love_token" }', "return plan" } }
check("SETZER under his own Love Token (he guards the lone body), the purse above his floor: Coin Toss, not the Fight",
  FIGHT_STANDS,
  function(H)
    battle(SETZER, { [0] = { QUIET, 9000, guard = 0x00 } }, { gil = 60000 })
    local p = castFor(driver(H)):coverPlan(0, fight(0))
    return p.kind == "skill" and p.cmd == 0x0F and p.skill == 0x59 and p.boostLeft == 0
  end)
check("the Coin Toss threshold: the purse at exactly the floor plus a toss tosses, one gil under Defends",
  { { "if gil - M.setzerGil(M.readByte(0x3B18 + actor * 2), 30, 0) < (o.gilFloor or 20000) then return nil end",
      "if gil - M.setzerGil(M.readByte(0x3B18 + actor * 2), 30, 0) <= (o.gilFloor or 20000) then return nil end" } },
  function(H)
    battle(SETZER, { [0] = { QUIET, 9000, guard = 0x00 } }, { gil = SETZER_FLOOR })
    local p = castFor(driver(H)):coverPlan(0, fight(0))
    if not (p.kind == "skill" and p.skill == 0x59) then return false end
    battle(SETZER, { [0] = { QUIET, 9000, guard = 0x00 } }, { gil = SETZER_FLOOR - 1 })
    return castFor(driver(H)):coverPlan(0, fight(0)).kind == "defend"
  end)
check("SETZER's Coin Toss honours his policy's o.coin = false: Defend",
  { { "if row == nil or self.skillDead[BATTLE.CMD_SLOT] or o.coin == false then return nil end",
      "if row == nil or self.skillDead[BATTLE.CMD_SLOT] then return nil end" } },
  function(H)
    battle(SETZER, { [0] = { QUIET, 9000, guard = 0x00 } }, { gil = 60000 })
    local d = castFor(driver(H)); d.opts.setzer = { coin = false }
    return d:coverPlan(0, fight(0)).kind == "defend"
  end)
check("no gil in a random battle unless o.gilInRandoms: Defend there, Coin Toss with the lever",
  { { "if M.readByte(M.RANDBTL) ~= 0 and not o.gilInRandoms then return nil end", "" } },
  function(H)
    battle(SETZER, { [0] = { QUIET, 9000, guard = 0x00 } }, { gil = 60000 })
    w8(0x57BD, 1)                                   -- a random battle (M.RANDBTL)
    if castFor(driver(H)):coverPlan(0, fight(0)).kind ~= "defend" then return false end
    local d = castFor(driver(H)); d.opts.setzer = { gilInRandoms = true }
    return d:coverPlan(0, fight(0)).skill == 0x59
  end)
check("EDGAR whose blows the token turns on TERRA: his tool, not the Fight",
  { { 'local alt = self:handVerb(actor, "love_token")\n  if alt ~= nil then return alt end', "local alt = nil" } },
  function(H)
    battle(EDGAR, { [0] = { QUIET, 9000, guard = 0x02 } }, { cmds = { 0x00, 0x01, 0x09, 0xFF } })
    w8(0x2686, 0xAA); w8(0x2686 + 3, 5)    -- AutoCrossbow x5 in the battle bag
    local p = driver(H):coverPlan(0, fight(0))
    return p.kind == "skill" and p.cmd == 0x09 and p.skill == 0xAA and p.reason == "love_token"
  end)
check("a member with no verb the token misses (TERRA, Fight and Item only) Defends while a partner can cast",
  { { "    if other == nil then\n      local key", "    if true then\n      local key" } },
  function(H)
    battle(TERRA, { [0] = { QUIET, 9000, guard = 0x00 } }, { cmds = { 0x00, 0x01, 0xFF, 0xFF } })
    return castFor(driver(H)):coverPlan(0, fight(0)).kind == "defend"
  end)
check("with no member holding such a verb the Fight stands (a Defend would stall the fight)",
  { { "    if other == nil then\n      local key", "    if false then\n      local key" } },
  function(H)
    battle(TERRA, { [0] = { QUIET, 9000, guard = 0x00 } }, { cmds = { 0x00, 0x01, 0xFF, 0xFF } })
    local p = castFor(driver(H), true):coverPlan(0, fight(0))
    return p.kind == "fight" and p.aimHard == nil
  end)
check("the Fight still goes to another standing body without the token (#466, kept)",
  { { "self:markRejected(plan, aim)\n      plan.aim, plan.aimHard = s, s", "plan.aim, plan.aimHard = aim, nil" } },
  function(H)
    battle(SETZER, { [0] = { QUIET, 9000, guard = 0x00 }, [1] = { QUIET, 9000 } }, { gil = 60000 })
    local p = driver(H):coverPlan(0, fight(0))
    return p.kind == "fight" and p.aimHard == 1
  end)

-- ---- #529: the absorbed weapon ------------------------------------------------------
-- entity 0 (EDGAR) swings item `w` (default $0E, ice) in his main hand
local function iceHand(w) w8(0x1600 + 37 * EDGAR + 0x1F, w or ICE_WEAPON); w8(0x1600 + 37 * EDGAR + 0x20, 0xFF) end
check("a Fight at a body that absorbs the hand's ice re-aims at the body beside it that does not",
  { { "  if not before then\n", "  if false then\n" } },
  function(H)
    battle(EDGAR, { [0] = { QUIET, 9000, absorb = 0x02 }, [1] = { QUIET, 9000 } })
    iceHand()
    local p = driver(H):absorbWeaponPlan(0, fight(0))
    return p.kind == "fight" and p.aimHard == 1 and p.aim == 1
  end)
check("the absorb byte is the slot's live one: a body whose ROM absorbs nothing but whose live record drinks ice",
  { { "  return (M.readByte(0x3BCC + 8 + slot * 2) & e) ~= 0\nend",
      "  return (M.monsterAbsorb(M.readWord(0x57C0 + slot * 2)) & e) ~= 0\nend" } },
  function(H)
    battle(EDGAR, { [0] = { QUIET, 9000, absorb = 0x02 } })
    iceHand()
    return driver(H):absorbWeaponPlan(0, fight(0)).kind ~= "fight"
  end)
check("and a body whose live record absorbs nothing takes the Fight, whatever its species' ROM byte",
  { { "  return (M.readByte(0x3BCC + 8 + slot * 2) & e) ~= 0\nend", "  return true\nend" } },
  function(H)
    battle(EDGAR, { [0] = { QUIET, 9000, absorb = 0x00 } })
    iceHand()
    local p = driver(H):absorbWeaponPlan(0, fight(0))
    return p.kind == "fight" and p.aimHard == nil
  end)
check("M.ABSORB_REAIM = false is the guard before #529 whole: the species' ROM byte (the FossilFang drinks poison)",
  { { "local function absorbs(s) return M.absorbedHand(s, r, before) and (l == nil or M.absorbedHand(s, l, before)) end",
      "local function absorbs(s) return M.absorbedHand(s, r) and (l == nil or M.absorbedHand(s, l)) end" } },
  function(H)
    battle(EDGAR, { [0] = { 0x023, 9000, absorb = 0x00 }, [1] = { QUIET, 9000 } })
    iceHand(0x38)                                  -- a weapon whose element is $08 (poison)
    H.ABSORB_REAIM = false
    local p = driver(H):absorbWeaponPlan(0, fight(0))
    H.ABSORB_REAIM = nil
    return p.kind ~= "fight"
  end)
check("the re-aim judges the body the executor steers to (the kill order's first), not the plan's aim",
  { { "  else\n    aim = self:fightAimOf(plan)\n  end", "  else\n    aim = plan.aim\n  end" } },
  function(H)
    battle(EDGAR, { [0] = { QUIET, 9000, absorb = 0x02 }, [1] = { QUIET, 9000 } })
    iceHand()
    local d = driver(H)
    d.focusList = function() return { { slot = 0 } } end
    local p = d:absorbWeaponPlan(0, fight(1))
    return p.kind == "fight" and p.aimHard == 1
  end)

-- ---- the shared re-aim filter (Driver:reaimOk, #533 review) -------------------------
local ALLOVER = 0x0BB          -- answers any hit with Doom
local function vanish(s) w8(0x3EE4 + (4 + s) * 2, 0x10) end
local function image(s) w8(0x3EE5 + (4 + s) * 2, 0x04) end
check("the absorb re-aim skips a Vanished body and a body under Image",
  { { "  if M.dodges({ s1 = M.readByte(0x3EE4 + (4 + s) * 2), s2 = M.readByte(0x3EE5 + (4 + s) * 2) }) ~= nil then\n    return false\n  end\n  if M.loveGuardOf(s) ~= nil then return false end",
      "  if M.loveGuardOf(s) ~= nil then return false end" } },
  function(H)
    battle(EDGAR, { [0] = { QUIET, 9000, absorb = 0x02 }, [1] = { QUIET, 100 }, [2] = { QUIET, 200 }, [3] = { QUIET, 9000 } })
    vanish(1); image(2); iceHand()
    local p = driver(H):absorbWeaponPlan(0, fight(0))
    return p.kind == "fight" and p.aimHard == 3
  end)
check("the absorb re-aim skips a body under Love Token",
  { { "  if M.loveGuardOf(s) ~= nil then return false end\n  if type(OT6_SYMS)", "  if type(OT6_SYMS)" } },
  function(H)
    battle(EDGAR, { [0] = { QUIET, 9000, absorb = 0x02 }, [1] = { QUIET, 100, guard = 0x02 }, [2] = { QUIET, 9000 } })
    iceHand()
    local p = driver(H):absorbWeaponPlan(0, fight(0))
    return p.kind == "fight" and p.aimHard == 2
  end)
check("the absorb re-aim skips a body whose answer to a Fight kills the striker (Allo Ver's Doom)",
  { { "      if killed ~= nil or top >= hp then return false end", "" } },
  function(H)
    battle(EDGAR, { [0] = { QUIET, 9000, absorb = 0x02 }, [1] = { ALLOVER, 100 }, [2] = { QUIET, 9000 } })
    iceHand()
    local p = driver(H):absorbWeaponPlan(0, fight(0))
    return p.kind == "fight" and p.aimHard == 2
  end)
check("no guard re-aims onto a body an earlier guard turned the plan off (plan.rejected)",
  { { "  if plan ~= nil and plan.rejected ~= nil and plan.rejected[s] then return false end\n", "" } },
  function(H)
    battle(EDGAR, { [0] = { QUIET, 9000, absorb = 0x02 }, [1] = { QUIET, 100 }, [2] = { QUIET, 9000 } })
    iceHand()
    local f = fight(0); f.rejected = { [1] = true }
    local p = driver(H):absorbWeaponPlan(0, f)
    return p.kind == "fight" and p.aimHard == 2 and p.rejected[0] == true
  end)
check("the Love Token re-aim reads the same filter: it skips a body whose element the hand drinks",
  { { "    if self:reaimOk(actor, s, plan) then\n      M.log(string.format(\"[%s] actor=%d Fight re-aimed: slot %d is under Love Token",
      "    if monAlive(s) and M.loveGuardOf(s) == nil then\n      M.log(string.format(\"[%s] actor=%d Fight re-aimed: slot %d is under Love Token" } },
  function(H)
    battle(EDGAR, { [0] = { QUIET, 9000, guard = 0x02 }, [1] = { QUIET, 9000, absorb = 0x02 }, [2] = { QUIET, 9000 } })
    iceHand()
    local p = driver(H):coverPlan(0, fight(0))
    return p.kind == "fight" and p.aimHard == 2
  end)

print(string.format("cover_absorb_selftest: PASS -- %d cases, each failed by its own mutant: %s", n,
  table.concat(said, "; ")))
