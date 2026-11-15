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
local PHASE, COELECITE = 0x0BC, 0x0B3
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
  { { "if not noDeath and self:deathAnswer(slot, e, a) == e then return hp end\n", "" },
    { "if dk ~= nil and killed == nil then killed = dk end", "" } },
  function(H)
    battle({ [0] = { ALLOVER, 8000 }, [1] = { QUIET, 5000 } })
    local p = driver(H):counterAimPlan(0, { kind = "fight", row = 0, aim = 0 })
    return p.aimHard == 1
  end)
-- a counter's L.5 Doom lands on the one who struck alone (#528: CheckRetal
-- presets $b8, ChooseTarget keeps it for $2C targeting), not on a partner
-- at a multiple of five
local function lone5(H)
  local FIGHT = { cmd = 0x00 }
  battle({ [0] = { APOK, 9000 } }, { party = { [0] = 40 } })
  local top, _, _, _, k = driver(H):counterWorst(0, 0, FIGHT, 3000)
  if not (top == 3000 and k == 0) then return false end
  battle({ [0] = { APOK, 9000 } }, { party = { [0] = 41, [1] = 40 } })
  top, _, _, _, k = driver(H):counterWorst(0, 0, FIGHT, 3000)
  if not (top < 3000 and k == nil) then return false end
  -- and a Fight from level 41 stays on it with the partner at 40
  local p = driver(H):counterAimPlan(0, { kind = "fight", row = 0, aim = 0 })
  return p.aimHard == nil and p.aim == 0
end
check("a lone Apokryphos's counter L.5 Doom kills the actor at level 40, not a partner at 40 (deathAnswer asks a counter's reach)",
  { { 'return M.deathReach(M.readRomByte(r), true, M.readRomByte(r + 2))', 'return M.deathReach(M.readRomByte(r))' } }, lone5)
check("a lone Apokryphos's counter L.5 Doom kills the actor at level 40, not a partner at 40 (M.deathReach's counter rule)",
  { { 'if ((f2 or 0) & 0x10) == 0 then return "attacker" end', "if false then end" } }, lone5)
check("a dying Coelecite beside one other body answers with Magnitude8 (if_num_monsters 1 on the bodies the hit leaves)",
  { { "if u.monsters == nil then u.monsters = n - (u.dies == true and 1 or 0) end",
      "if u.monsters == nil then u.monsters = n end" } },
  function(H)
    battle({ [0] = { COELECITE, 400 }, [1] = { QUIET, 5000 } })
    local _, _, atks = driver(H):counterWorst(0, 0, { cmd = 0x00, dies = true }, 3000)
    return #atks == 1 and atks[1] == 0xBC
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
check("a Fire spread by its scored contract (tc.all) with the Oscar standing becomes a Fight",
  { { "local spread = plan.all or (tc ~= nil and tc.all) or", "local spread = plan.all or" } },
  function(H)
    battle({ [0] = { QUIET, 5000 }, [1] = { OSCAR, 7000 } })
    local p = driver(H):counterMagicPlan(0, { kind = "magic", spell = FIRE,
      targetContract = { chars = 0, monsters = 3, all = true } })
    return p.kind == "fight" and p.reason == "counter_magic"
  end)
check("a Fire at the Phase (Blow Fish, 1000, on any hit) goes to the body beside it from 900 HP, stays from 3000",
  { { "if killed == nil and top < hp then return nil end", "if killed == nil then return nil end" } },
  function(H)
    battle({ [0] = { QUIET, 5000 }, [1] = { PHASE, 7000 } })
    local p = driver(H):counterMagicPlan(0, { kind = "magic", spell = FIRE, aim = 1 })
    if not (p.kind == "magic" and p.aimHard == nil and p.aim == 1) then return false end
    battle({ [0] = { QUIET, 5000 }, [1] = { PHASE, 7000 } }); w16(0x3BF4, 900)
    p = driver(H):counterMagicPlan(0, { kind = "magic", spell = FIRE, aim = 1 })
    return p.kind == "magic" and p.aimHard == 0
  end)

check("the verb veto (#372) does not price a Death: a Pummel beside the Sky Base is not refused",
  { { "    u.noDeath = true\n", "" } },
  function(H)
    battle({ [0] = { QUIET, 5000 }, [2] = { SKYBASE, 9000 } })
    return driver(H):counterVetoed(0, { cmd = 0x0A, atk = 0x5D }, { 0, 2 }, "Pummel", false) == false
  end)

-- #530: Roulette's cursor stops on any standing member, so a guarded actor
-- still draws a Roulette that can take the partner beside him
check("a Fire at the Veteran from a guarded actor still draws a Roulette that kills the unguarded partner (#530)",
  { { 'if r == "party" or r == "roulette" then', 'if r == "party" then' } },
  function(H)
    battle({ [1] = { VETERAN, 6000 } }, { party = { [0] = 41, [1] = 41 }, guard = true })
    local _, _, _, _, k = driver(H):counterWorst(1, 0, { cmd = 0x02, atk = FIRE }, 3000)
    if k ~= 1 then return false end
    -- the partner guarded too: it lands on nobody
    w8(0x3AA1 + 2, 0x04)
    _, _, _, _, k = driver(H):counterWorst(1, 0, { cmd = 0x02, atk = FIRE }, 3000)
    return k == nil
  end)

-- #533: the FossilFang answers a Fight with Sand Storm on every member
local FOSSIL = 0x023
local function fourAt19() return { party = { [0] = 19, [1] = 19, [2] = 19, [3] = 19 } } end
check("the FossilFang's Sand Storm answer to a Fight is priced on all four members, not the one who struck (#533)",
  { { "if (m == e or spreads) and hp > 0", "if m == e and hp > 0" } },
  function(H)
    battle({ [0] = { FOSSIL, 3000 } }, fourAt19())
    local d = driver(H)
    local all, a, wide = d:counterPartyTake(0, 0, { cmd = 0x00 })
    local one = d:counterHit(0, 0, 0x69, 3000, true)
    return a == 0x69 and wide and one > 0 and all == 4 * one
  end)
check("a Fight at the FossilFang re-aims at the body beside it that answers a Fight with nothing (#533)",
  { { "if not wide or price == 0 then return plan end", "do return plan end" } },
  function(H)
    battle({ [0] = { FOSSIL, 3000 }, [1] = { QUIET, 3000 } }, fourAt19())
    local p = driver(H):counterPartyPlan(0, { kind = "fight", row = 0, aim = 0 })
    return p.kind == "fight" and p.aimHard == 1 and p.aim == 1
  end)
-- the rule before the #533 review: the targeting byte alone (a spread group, no MANUAL bit, no Roulette)
local TARGETING_ONLY = { { 'return M.answerReach(a) == "party"', [[local t = M.readRomByte((M.sym("MagicProp") & 0x3FFFFF) + a * 14)
  return a < 0xEE and (t & 0x80) == 0 and (t & 0x01) == 0 and (t & 0x0C) ~= 0]] } }
check("an answer on the one who struck alone is no party-wide counter (M.answerSpreads reads the reach)",
  { { 'return M.answerReach(a) == "party"', "return true" } },
  function(H)
    -- the Phase answers any hit with Blow Fish, which reaches the one who struck
    battle({ [0] = { PHASE, 7000 }, [1] = { QUIET, 3000 } }, fourAt19())
    local p = driver(H):counterPartyPlan(0, { kind = "fight", row = 0, aim = 0 })
    return p.aimHard == nil and p.aim == 0 and H.answerSpreads(0x69) and not H.answerSpreads(0xEE)
  end)
check("EDGAR at a lone FossilFang takes his tool (AutoCrossbow: answered with nothing) for the Fight (#533)",
  { { "local d = draws({ cmd = verb.cmd, atk = verb.skill }, all)", "local d = price" } },
  function(H)
    battle({ [0] = { FOSSIL, 3000 } }, fourAt19())
    w8(0x3ED8, 0x04)                                  -- entity 0 is EDGAR
    w8(0x202E + 3 * 3, 0x09)                          -- his Tools row
    w8(0x2686, 0xAA); w8(0x2686 + 3, 5)               -- AutoCrossbow x5 in the battle bag
    local p = driver(H):counterPartyPlan(0, { kind = "fight", row = 0, aim = 0 })
    return p.kind == "skill" and p.cmd == 0x09 and p.skill == 0xAA and p.reason == "counter_party"
  end)
check("a killing blow at the FossilFang stands (the kill ends its answers)",
  { { 'if plan.reason == "finish" then return plan end', "" } },
  function(H)
    battle({ [0] = { FOSSIL, 300 }, [1] = { QUIET, 3000 } }, fourAt19())
    local p = driver(H):counterPartyPlan(0, { kind = "fight", row = 0, aim = 0, reason = "finish" })
    return p.aimHard == nil and p.aim == 0
  end)

-- #533 review: Magnitude8 ($BC, the dying Coelecite's) and Quartr ($11, the
-- Necromancer's) carry no random-target bit, so as counters they land on the
-- one who struck: neither is a party-wide answer
check("a Magnitude8 counter is no party-wide answer (the preset $b8 is kept)", TARGETING_ONLY,
  function(H)
    battle({ [0] = { COELECITE, 400 }, [1] = { QUIET, 5000 } }, fourAt19())
    local _, a, wide = driver(H):counterPartyTake(0, 0, { cmd = 0x00, dies = true })
    return not H.answerSpreads(0xBC) and not wide and a == 0xBC
  end)
check("a Quartr counter is no party-wide answer", TARGETING_ONLY,
  function(H) return not H.answerSpreads(0x11) and H.answerSpreads(0x69) end)

-- the shared re-aim filter (Driver:reaimOk, #533 review) in the counter and Vanish guards
check("the FossilFang re-aim skips a Vanished body for one that stands in reach",
  { { "    if s ~= aim and self:reaimOk(actor, s, plan) then", "    if s ~= aim and monAlive(s) and self:focusReachable(s) then" } },
  function(H)
    battle({ [0] = { FOSSIL, 3000 }, [1] = { QUIET, 100 }, [2] = { QUIET, 3000 } }, fourAt19())
    w8(0x3EE4 + (4 + 1) * 2, 0x10)                    -- slot 1 Vanished
    local p = driver(H):counterPartyPlan(0, { kind = "fight", row = 0, aim = 0 })
    return p.kind == "fight" and p.aimHard == 2 and p.rejected[0] == true
  end)
check("a Fight off a Vanished body skips a body whose answer kills the striker (Allo Ver's Doom)",
  { { "      if self:reaimOk(actor, s, plan) then\n        M.log", "      if true then\n        M.log" } },
  function(H)
    battle({ [0] = { QUIET, 3000 }, [1] = { ALLOVER, 100 }, [2] = { QUIET, 3000 } })
    w8(0x3EE4 + 4 * 2, 0x10)                          -- slot 0 Vanished
    local p = driver(H):dodgePlan(0, { kind = "fight", row = 0, aim = 0 })
    return p.kind == "fight" and p.aimHard == 2
  end)

print(string.format("counter_death_selftest: PASS -- %d cases, each failed by its own mutant: %s", n,
  table.concat(said, "; ")))
