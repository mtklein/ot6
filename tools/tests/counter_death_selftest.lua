-- @manual standalone: lua tools/tests/counter_death_selftest.lua  (after ninja build/ot6.sfc)
-- counter_death_selftest.lua -- the Death answers the counter rules price
-- (#523): Driver:counterMagicPlan, Driver:counterAimPlan and
-- Driver:counterWorst on a stubbed battle.  RAM is a stub table, the ROM's
-- AI scripts, MagicProp and MonsterProp records come from build/ot6.sfc;
-- no emulator, no gameplay claim.  Every case runs against the library as
-- it is (it must hold) and against a mutant of the library's own source
-- (one or more edits, loaded as a second library) under which it must
-- fail.  counter_selftest covers the readers (M.retalAnswer,
-- M.deathLands, M.deathReach) on the same records.
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
local MONPROP = sym("MonsterProp") & 0x3FFFFF

local mem = {}
local function w8(a, v) mem[a] = v & 0xFF end
local function w16(a, v) mem[a] = v & 0xFF; mem[a + 1] = (v >> 8) & 0xFF end

-- a library from source text, its reads on the stub
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

local FIGHT_ROW, MAGIC_ROW = 0x00, 0x02
local OSCAR, SKYBASE, VETERAN, ALLOVER, APOK, RETAINER, QUIET = 0x0B7, 0x0FC, 0x0FB, 0x0BB, 0x00C, 0x007, 0x00D
local FIRE, METEOR = 0x00, 0x13
-- a battle: party entity 0 (and `others`) at 3000 HP, Fight and Magic on
-- the command table, no command queued; `mons[slot] = { species, hp }`
local function battle(mons, o)
  o = o or {}
  for k in pairs(mem) do mem[k] = nil end
  for x = 0, 18, 2 do w8(0x32CC + x, 0xFF); w8(0x32CD + x, 0xFF) end
  w8(0x3403, 0xFF)
  for e = 0, 3 do w8(0x3ED8 + e * 2, 0xFF) end
  for e, lv in pairs(o.party or { [0] = 41 }) do
    w16(0x3BF4 + e * 2, 3000); w16(0x3C1C + e * 2, 3000); w8(0x3B18 + e * 2, lv); w8(0x3ED8 + e * 2, e)
  end
  if o.guard then w8(0x3AA1, 0x04) end
  for r, c in ipairs({ FIGHT_ROW, MAGIC_ROW, 0x01, 0xFF }) do w8(0x202E + (r - 1) * 3, c) end
  for s, m in pairs(mons) do
    w16(0x57C0 + s * 2, m[1]); w16(0x3BFC + s * 2, m[2]); w8(0x3AA8 + s * 2, 1)
    w8(0x322D + 8 + s * 2, rom:byte(MONPROP + m[1] * 32 + 0x1F + 1))
  end
end
local function driver(H)
  local d = H.newFightDriver("counter death", { tactical = true }).driver
  d.focusList = function() return nil end
  d.chipAim = function() return nil end
  d.dmgSeen = d.dmgSeen or {}
  return d
end

local n, said = 0, {}
-- f(H) must hold on the real library and fail on the mutant's
local function check(what, edits, f)
  n = n + 1
  local ok, r = pcall(f, REAL)
  assert(ok and r == true, "FAIL " .. what .. ": " .. tostring(r))
  local mok, mr = pcall(f, mutantLib(edits))
  assert(not mok or mr ~= true, string.format("FAIL %s: the mutant (%s) passed it too", what,
    table.concat((function() local t = {} for _, e in ipairs(edits) do t[#t + 1] = "'" .. e[1] .. "'" end return t end)(), ", ")))
  said[#said + 1] = what
end
local SPELL_DEAD = { { 'if M.attackClass(b) ~= "wound" then return nil end', "do return nil end" } }

check("a Fire aimed at the Evil Oscar goes to the body beside it (#521, kept)",
  { { 'if M.specialClass(M.readByte(0x322D + 8 + slot * 2)) == "wound" and not guarded(e) then return e end', "" } },
  function(H)
    battle({ [0] = { QUIET, 5000 }, [1] = { OSCAR, 7000 } })
    local p = driver(H):counterMagicPlan(0, { kind = "magic", spell = FIRE, aim = 1 })
    return p.kind == "magic" and p.aimHard == 0
  end)
check("a Fire aimed at the Sky Base (Blaster) goes to the body beside it",
  SPELL_DEAD,
  function(H)
    battle({ [0] = { QUIET, 5000 }, [2] = { SKYBASE, 9000 } })
    local p = driver(H):counterMagicPlan(0, { kind = "magic", spell = FIRE, aim = 2 })
    return p.kind == "magic" and p.aimHard == 0
  end)
check("a caster with a Death guard casts at the Sky Base as planned",
  { { "local function guarded(m) return (M.readByte(0x3AA1 + m * 2) & 0x04) ~= 0 end",
      "local function guarded(m) return false end" } },
  function(H)
    battle({ [0] = { QUIET, 5000 }, [2] = { SKYBASE, 9000 } }, { guard = true })
    local p = driver(H):counterMagicPlan(0, { kind = "magic", spell = FIRE, aim = 2 })
    return p.kind == "magic" and p.aimHard == nil and p.aim == 2
  end)
check("a Fire at a lone Veteran (Roulette) becomes a Fight (it answers a Fight with nothing)",
  SPELL_DEAD,
  function(H)
    battle({ [1] = { VETERAN, 6000 } })
    local p = driver(H):counterMagicPlan(0, { kind = "magic", spell = FIRE })
    return p.kind == "fight" and p.reason == "counter_magic"
  end)
check("a Fight aimed at Allo Ver (Doom on any hit) goes to the body beside it",
  { { "if self:deathAnswer(slot, e, a, true) ~= nil then return hp end\n", "" },
    { "if dk ~= nil and killed == nil then killed = dk end", "" } },
  function(H)
    battle({ [0] = { ALLOVER, 8000 }, [1] = { QUIET, 5000 } })
    local p = driver(H):counterAimPlan(0, { kind = "fight", row = 0, aim = 0 })
    return p.aimHard == 1
  end)
check("a lone Apokryphos's L.5 Doom kills the actor at level 40, a partner at 40, nobody at 41",
  { { 'if not onlyE and M.deathReach(b(0)) == "party" then', "if false then" } },
  function(H)
    local FIGHT = { cmd = 0x00 }
    battle({ [0] = { APOK, 9000 } }, { party = { [0] = 40 } })
    local top, _, _, _, k = driver(H):counterWorst(0, 0, FIGHT, 3000)
    if not (top == 3000 and k == 0) then return false end
    battle({ [0] = { APOK, 9000 } }, { party = { [0] = 41, [1] = 40 } })
    top, _, _, _, k = driver(H):counterWorst(0, 0, FIGHT, 3000)
    if not (top < 3000 and k == 1) then return false end
    battle({ [0] = { APOK, 9000 } }, { party = { [0] = 41, [1] = 41 } })
    top, _, _, _, k = driver(H):counterWorst(0, 0, FIGHT, 3000)
    return top < 3000 and k == nil
  end)
check("the Apokryphos beside another body answers nothing (if_num_monsters 1, on the bodies standing)",
  { { "if u.monsters == nil then", "if false then" },
    { "if alive.monsters == nil then alive.monsters = n end", "" } },
  function(H)
    battle({ [0] = { APOK, 9000 }, [1] = { QUIET, 5000 } }, { party = { [0] = 40 } })
    local _, _, _, _, k = driver(H):counterWorst(0, 0, { cmd = 0x00 }, 3000)
    return k == nil
  end)
-- a partner (entity 1) who wears a Death guard can take the Retainer's kill
local function guardedPartner() w16(0x3BF4 + 2, 3000); w8(0x3B18 + 2, 41); w8(0x3AA1 + 2, 0x04) end
check("a finishing Fight on a Retainer (its dying Tradeoff) goes to the body beside it while a guarded partner stands",
  { { "if not unknown and top < hp and killed == nil then return plan end", "if true then return plan end" } },
  function(H)
    battle({ [0] = { RETAINER, 400 }, [2] = { QUIET, 5000 } }); guardedPartner()
    local d = driver(H); d.dmgSeen[0] = 900
    local p = d:counterAimPlan(0, { kind = "fight", row = 0, aim = 0, reason = "finish" })
    return p.aimHard == 2
  end)
check("with no guarded partner the Retainer's kill costs a life whoever lands it: the finish stays",
  { { "or not self:guardStands(e)) then", ") then" } },
  function(H)
    battle({ [0] = { RETAINER, 400 }, [2] = { QUIET, 5000 } })
    local d = driver(H); d.dmgSeen[0] = 900
    local p = d:counterAimPlan(0, { kind = "fight", row = 0, aim = 0, reason = "finish" })
    return p.aimHard == nil and p.aim == 0
  end)
check("a Fight that leaves a Retainer standing (100 against 5000) stays on it; one that may kill it (6000) moves",
  { { "and (mayKill == false or (u.dies ~= true and mayKill == nil) or not self:guardStands(e)) then",
      "and (u.dies ~= true and mayKill == nil or not self:guardStands(e)) then" } },
  function(H)
    battle({ [0] = { RETAINER, 5000 }, [2] = { QUIET, 5000 } }); guardedPartner()
    local d = driver(H); d.dmgSeen[0] = 100
    local p = d:counterAimPlan(0, { kind = "fight", row = 0, aim = 0 })
    if p.aimHard ~= nil or p.aim ~= 0 then return false end
    d = driver(H); d.dmgSeen[0] = 6000
    p = d:counterAimPlan(0, { kind = "fight", row = 0, aim = 0 })
    return p.aimHard == 2
  end)
check("nothing measured yet, a Fight on a Retainer at full HP stays on it",
  { { "and (mayKill == false or (u.dies ~= true and mayKill == nil) or not self:guardStands(e)) then",
      "and (mayKill == false or not self:guardStands(e)) then" } },
  function(H)
    battle({ [0] = { RETAINER, 5000 }, [2] = { QUIET, 5000 } }); guardedPartner()
    local p = driver(H):counterAimPlan(0, { kind = "fight", row = 0, aim = 0 })
    return p.aimHard == nil and p.aim == 0
  end)
check("a re-aim skips the body a queued Fight takes first (pkN_s6), else goes to the least HP",
  { { "local function landsOn(s) return monAlive(s) and not self:mayFallFirst(actor, s) end",
      "local function landsOn(s) return monAlive(s) end" } },
  function(H)
    local function setup(seen)
      battle({ [0] = { QUIET, 500 }, [1] = { OSCAR, 7000 }, [2] = { QUIET, 9000 } },
        { party = { [0] = 41, [1] = 41 } })
      w8(0x32CC + 2, 0x05); w8(0x3520 + 0x05 * 2 + 1, 0x01)   -- entity 1's queued Fight, at slot 0
      local d = driver(H); d.dmgSeen[1] = seen
      return d:counterMagicPlan(0, { kind = "magic", spell = FIRE, aim = 1 })
    end
    local p = setup(800)
    if p.aimHard ~= 2 then return false end
    p = setup(100)
    return p.aimHard == 0
  end)
check("a cast re-aimed off the Oscar names the new body in a scored command's contract",
  { { "if tc ~= nil and not tc.all then plan.targetContract = { chars = 0, monsters = 1 << best, all = false } end\n    return plan\n  end\n  local fight",
      "return plan\n  end\n  local fight" } },
  function(H)
    battle({ [0] = { QUIET, 5000 }, [1] = { OSCAR, 7000 } })
    local p = driver(H):counterMagicPlan(0, { kind = "magic", spell = FIRE,
      targetContract = { chars = 0, monsters = 2, all = false } })
    return p.aimHard == 0 and p.targetContract.monsters == 1
  end)
check("a Fight re-aimed off a killing body names the new body in a scored command's contract",
  { { "if tc ~= nil and not tc.all then plan.targetContract = { chars = 0, monsters = 1 << best, all = false } end\n  return plan\nend",
      "return plan\nend" } },
  function(H)
    battle({ [0] = { ALLOVER, 8000 }, [1] = { QUIET, 5000 } })
    local p = driver(H):counterAimPlan(0, { kind = "fight", row = 0,
      targetContract = { chars = 0, monsters = 1, all = false } })
    return p.aimHard == 1 and p.targetContract.monsters == 2
  end)
check("a Meteor (every body) with the Oscar standing, and a Fire spread over it, become Fights",
  { { "local spread = plan.all or (tc ~= nil and tc.all) or ((t & 0x01) == 0 and (t & 0x0C) ~= 0)",
      "local spread = false" } },
  function(H)
    battle({ [0] = { QUIET, 5000 }, [1] = { OSCAR, 7000 } })
    local p = driver(H):counterMagicPlan(0, { kind = "magic", spell = METEOR })
    if p.kind ~= "fight" then return false end
    p = driver(H):counterMagicPlan(0, { kind = "magic", spell = FIRE, all = true })
    return p.kind == "fight"
  end)

print(string.format("counter_death_selftest: PASS -- %d cases, each failed by its own mutant: %s", n,
  table.concat(said, "; ")))
