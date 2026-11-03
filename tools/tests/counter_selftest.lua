-- @manual standalone: lua tools/tests/counter_selftest.lua  (after ninja build/ot6.sfc)
-- counter_selftest.lua -- the counter rule's readers (#372) against the
-- built ROM's bytes and hand-checked numbers.  No emulator.
--   M.retalAnswer: the AI walker's own walk over a retaliation section
--     (battle_main.asm NextAICmd @1ab4, AICmd_fc @1a91, conditionmiss
--     @1a9b with FindAIScriptEnd @1a43, AICmd_fe/ff @1a7b).
--   M.magicHitRange / M.physHitRange: CalcMagicDmg @2b69, CalcDmg's
--     physical half @2ba6 and CalcDmgMod @0c9e.
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
  return assert(tonumber(val, 16), name .. " in ff6-en.dbg") & 0x3FFFFF
end
local PTRS, SCRIPTS, MAGIC = symbol("AIScriptPtrs"), symbol("AIScript"), symbol("MagicProp")
local function scriptOf(species)
  local off = rom:byte(PTRS + species * 2 + 1) | (rom:byte(PTRS + species * 2 + 2) << 8)
  return function(i) return rom:byte(SCRIPTS + off + i + 1) end
end
local function bytesOf(t) return function(i) return t[i + 1] or 0xFF end end
local function ids(list)
  local t = {}
  for _, a in ipairs(list) do t[#t + 1] = string.format("%02X", a) end
  table.sort(t)
  return table.concat(t, ",")
end

-- A mutant: the lib function's source with `from` (which must occur
-- exactly once in it) replaced by `to`, loaded against a proxy of the lib
-- table so the real function is untouched.
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
-- f(lib) must hold for the real lib and fail with `name` swapped for the mutant
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
local FIGHT, BLITZ, PUMMEL = 0x00, 0x0A, 0x5D

-- ---- the walker -----------------------------------------------------------
-- Aspik ($059): `if_cmd FIGHT / attack BATTLE / end_if / if_hit / attack GIGA_VOLT`
check("$059 answers a Fight with Battle ($EE) alone, certain (end_if ends the script)",
  "retalAnswer", "if op == 0xFE or op == 0xFF then return end", "if op == 0xFF then return end",
  function()
    local a, sure = H.retalAnswer(scriptOf(0x059), { cmd = FIGHT })
    return ids(a) == "EE" and sure
  end)
check("$059 answers a Pummel with Giga Volt ($B9) alone (a missed if_cmd skips past end_if)",
  "retalAnswer", "j = pastEndIf(j + 4)\n", "j = j + 4\n",
  function()
    local a, sure = H.retalAnswer(scriptOf(0x059), { cmd = BLITZ, atk = PUMMEL })
    return ids(a) == "B9" and sure
  end)
-- $148: `if_self_dead ... end_if / if_hit / attack NOTHING,NOTHING,$07 /
-- set_target / if_var ...`: the if_var after the attack gates only what
-- follows it (the first cut of the walker began a fresh block there and
-- dropped the $07: the mutant restores that)
check("$148 answers a Fight with $07 (a condition after an attack gates only what follows)",
  "retalAnswer", "local c, a, b = byteAt(j + 1), byteAt(j + 2), byteAt(j + 3)",
  "out, seen = {}, {} local c, a, b = byteAt(j + 1), byteAt(j + 2), byteAt(j + 3)",
  function()
    local a, sure = H.retalAnswer(scriptOf(0x148), { cmd = FIGHT })
    return ids(a) == "07" and not sure
  end)
-- synthetic: if_cmd FIGHT / Battle / if_hit / Giga Volt / end_if
local mid = { 0xFF, 0xFC, 0x01, 0x00, 0x00, 0xEE, 0xFC, 0x05, 0x00, 0x00, 0xB9, 0xFE, 0xFF }
check("mid-block: a Fight draws Battle and, past if_hit, the spell",
  "retalAnswer", "elseif c == 0x05 then holds = true", "elseif c == 0x05 then holds = false",
  function() return ids(H.retalAnswer(bytesOf(mid), { cmd = FIGHT })) == "B9,EE" end)
check("mid-block: a Blitz misses if_cmd and draws nothing",
  "retalAnswer", "if c == 0x01 then holds = either(use.cmd, a, b)", "if c == 0x01 then holds = true",
  function() return ids(H.retalAnswer(bytesOf(mid), { cmd = BLITZ })) == "" end)
-- $0F3: `if_num_monsters 1 / attack $B3 / end_if / attack Battle /
-- wait ($FD) / attack Battle,Battle,$EF` (#376).  $FD ends THIS counter's
-- walk (AICmd_fd @1a74 saves the pointer to $f2 and returns), but
-- ExecAIRetal @4bf4 keeps it ($3D20) with the blocks skipped so far ($f5
-- -> $3241), and the next counter, reaching a command with the same count
-- ($f5 == $f4, NextAICmd @1ab4), jumps there: the attack after the $FD
-- answers the following hit.  Both registers read $FF at the battle's open
-- (build/attempts/wt/v026-driver/376/aiinit.log), so the first counter
-- walks from the top.  "What can answer this verb" is the union of the
-- two, so the walk goes on through $FD: the $EF stays in (and with it the
-- unpriced Special that keeps the rule from vetoing on $0F3).
check("$0F3 answers a Fight with $EF too: the counter after a $FD resumes past it",
  "retalAnswer", "if op == 0xFE or op == 0xFF then return end",
  "if op == 0xFE or op == 0xFF or op == 0xFD then return end",
  function()
    local a = H.retalAnswer(scriptOf(0x0F3), { cmd = FIGHT })
    return ids(a) == "B3,EE,EF"
  end)
-- synthetic: an undecided condition (FC 0C, HP below) is walked both ways
local fork = { 0xFF, 0xFC, 0x0C, 0x00, 0x50, 0xB9, 0xFE, 0xFC, 0x05, 0x00, 0x00, 0xEE, 0xFE, 0xFF }
check("an undecided condition is walked both ways and the answer is not certain",
  "retalAnswer", "walk(pastEndIf(j + 4))             -- the miss", "",
  function()
    local a, sure = H.retalAnswer(bytesOf(fork), { cmd = FIGHT })
    return ids(a) == "B9,EE" and not sure
  end)

-- ---- the magical model ----------------------------------------------------
local gv = MAGIC + 0xB9 * 14
assert(rom:byte(gv + 7) == 110 and rom:byte(gv + 2) == 0x04 and rom:byte(gv + 3) & 1 == 0,
  "Giga Volt in MagicProp: power 110 (+6), lightning (+1), magical (+2 bit 0 clear)")
-- by hand, Aspik in battle (level 12; magic power 2, AddHalf -> 3):
-- base 110*4 + (3*110*12 >> 5) = 440 + 123 = 563
-- least: 563*224 >> 8 = 492, +1 = 493; mdef 0: 493*255 >> 8 = 491, +1 = 492
-- most:  563*255 >> 8 = 560, +1 = 561; mdef 0: 561*255 >> 8 = 558, +1 = 559
check("Giga Volt from Aspik on mdef 0: 492..559",
  "magicHitRange", "* (o.level or 1)) >> 5)", "* 1) >> 5)",
  function()
    local lo, hi = H.magicHitRange({ power = 110, level = 12, magpow = 3, mdef = 0, elem = 0x04 })
    return lo == 492 and hi == 559
  end)
-- mdef 40: 493*215 >> 8 = 414, +1 = 415; 561*215 >> 8 = 471, +1 = 472
check("the same on mdef 40: 415..472",
  "magicHitRange", "((d * (255 - mdef)) >> 8) + 1", "((d * 255) >> 8) + 1",
  function()
    local lo, hi = H.magicHitRange({ power = 110, level = 12, magpow = 3, mdef = 40, elem = 0x04 })
    return lo == 415 and hi == 472
  end)
check("lightning-weak doubles it (1118)",
  "magicHitRange", "then d = d * 2 end", "then d = d end",
  function()
    local _, hi = H.magicHitRange({ power = 110, level = 12, magpow = 3, mdef = 0, elem = 0x04, weak = 0x04 })
    return hi == 1118
  end)
check("lightning-null zeroes it",
  "magicHitRange", "((o.null or 0) & e) ~= 0 then return 0 end", "false then return 0 end",
  function()
    local _, hi = H.magicHitRange({ power = 110, level = 12, magpow = 3, mdef = 0, elem = 0x04, null = 0x04 })
    return hi == 0
  end)
check("a physical spell is no magical damage",
  "magicHitRange", "(o.flags2 or 0) & 0x01 ~= 0 or ", "",
  function() return H.magicHitRange({ power = 110, flags2 = 0x01, level = 12, magpow = 3 }) == nil end)

-- ---- the physical model ---------------------------------------------------
-- Battle by hand, Aspik's battle power 2, level 12, def 0:
-- least (vigor 56, unraised 8): ((8 + 56) * 12 >> 8) * 12 = 3 * 12 = 36;
--   36*224 >> 8 = 31, +1 = 32; def 0: 32*255 >> 8 = 31, +1 = 32
-- most (vigor 63, 8 raised to 14): ((14 + 63) * 12 >> 8) * 12 = 36;
--   36*255 >> 8 = 35, +1 = 36; def 0: 36*255 >> 8 = 35, +1 = 36
check("Aspik's Battle on def 0: 32..36",
  "physHitRange", "* lv) >> 8) * lv", "* lv) >> 8)",
  function()
    local lo, hi = H.physHitRange({ power = 2, level = 12, def = 0 })
    return lo == 32 and hi == 36
  end)
-- power 13, level 13, vigor 60, def 0:
-- least: ((52 + 60) * 13 >> 8) * 13 = 5 * 13 = 65; 65*224 >> 8 = 56, +1 = 57;
--   57*255 >> 8 = 56, +1 = 57
-- most: 52 raised to ((26 + 52) >> 1) + 52 = 91; ((91 + 60) * 13 >> 8) * 13 =
--   7 * 13 = 91; 91*255 >> 8 = 90, +1 = 91; 91*255 >> 8 = 90, +1 = 91
check("power 13, level 13, vigor 60, def 0: 57..91 (the raise counted at the top only)",
  "physHitRange", "if raise then a = (((a >> 1) + a) >> 1) + a end", "",
  function()
    local lo, hi = H.physHitRange({ power = 13, level = 13, vigor = 60, def = 0 })
    return lo == 57 and hi == 91
  end)
-- def 100: 91*155 >> 8 = 55, +1 = 56 (most)
check("defense 100 takes it to 56 at most",
  "physHitRange", "((d * (255 - def)) >> 8) + 1", "((d * 255) >> 8) + 1",
  function()
    local _, hi = H.physHitRange({ power = 13, level = 13, vigor = 60, def = 100 })
    return hi == 56
  end)
check("the back row halves it (91 -> 45)",
  "physHitRange", "if o.backRow then d = d >> 1 end", "",
  function()
    local _, hi = H.physHitRange({ power = 13, level = 13, vigor = 60, def = 0, backRow = true })
    return hi == 45
  end)

-- ---- the Phoenix Cave's answers (#503) -------------------------------------
-- Necromancr ($0F1): `if_cmd FIGHT / end_if / if_hit / attack DEMI, QUARTR,
-- NOTHING`; Phase ($0BC): `if_self_dead / end_if / if_hit / attack
-- BLOW_FISH` (ai_script.asm _241, _188)
local LORE, AQUA_RAKE = 0x0C, 0x8E
check("$0F1 answers a Fight with nothing (its if_cmd FIGHT block is empty)",
  "retalAnswer", "if c == 0x01 then holds = either(use.cmd, a, b)", "if c == 0x01 then holds = false",
  function()
    local a, sure = H.retalAnswer(scriptOf(0x0F1), { cmd = FIGHT })
    return ids(a) == "" and sure
  end)
check("$0F1 answers Aqua Rake with Demi or Quartr ($10, $11)",
  "retalAnswer", "elseif c == 0x05 then holds = true", "elseif c == 0x05 then holds = false",
  function()
    local a, sure = H.retalAnswer(scriptOf(0x0F1), { cmd = LORE, atk = AQUA_RAKE, elem = 0x80 })
    return ids(a) == "10,11" and sure
  end)
local function rec(a) return function(i) return rom:byte(MAGIC + a * 14 + i + 1) end end
assert(rom:byte(MAGIC + 0x90 * 14 + 10) == 0x1A, "Blow Fish in MagicProp: attacker special effect $1A (+9)")
assert(rom:byte(MAGIC + 0x11 * 14 + 5) & 0x80 ~= 0 and rom:byte(MAGIC + 0x11 * 14 + 7) == 12,
  "Quartr in MagicProp: the fraction flag (+4 bit 7), power 12 (+6)")
check("Blow Fish takes 1000 (AttackerEffect_1a), whatever the HP",
  "fixedTake", "if byteAt(9) == 0x1A then return 1000 end", "",
  function() return H.fixedTake(rec(0x90), 557, 2227) == 1000 end)
-- the wipe's own numbers: SABIN 2227 -> 557, STRAGO 3219 -> 805
check("Quartr takes 12/16 of the HP standing (2227 -> 1670 off, 3219 -> 2414 off)",
  "fixedTake", "maxHp or hp) * byteAt(6)) >> 4", "maxHp or hp) * byteAt(6)) >> 3",
  function() return H.fixedTake(rec(0x11), 2227, 2227) == 1670 and H.fixedTake(rec(0x11), 3219, 3219) == 2414 end)
check("Demi takes half of the HP standing, not of the max (557 -> 278 off)",
  "fixedTake", "(byteAt(2) & 0x04) ~= 0 and maxHp or hp", "maxHp",
  function() return H.fixedTake(rec(0x10), 557, 2227) == 278 end)
check("Flare is not priced here (monHitOn's magical model is)",
  "fixedTake", "if (byteAt(4) & 0x80) ~= 0 then", "if true then",
  function() return H.fixedTake(rec(0x0F), 557, 2227) == nil end)

-- review of 6813106a: heals, a fraction at 1 HP, the engine's counter order, if_self_dead
assert(rom:byte(MAGIC + 0x30 * 14 + 5) == 0xA5 and rom:byte(MAGIC + 0x31 * 14 + 5) == 0xA5,
  "Life and Life 2 in MagicProp: the heal flag (+4 bit 0) beside the fraction flag (bit 7)")
check("a heal is no take, though Life and Life 2 carry the fraction flag",
  "fixedTake", "if (byteAt(4) & 0x01) ~= 0 then return 0 end", "",
  function() return H.fixedTake(rec(0x30), 3000, 3000) == 0 and H.fixedTake(rec(0x31), 3000, 3000) == 0 end)
check("Demi on a member at 1 HP takes 1 (CalcDmgRatio's inc), so it kills",
  "fixedTake", "return math.max(1, (((byteAt(2)", "return math.max(0, (((byteAt(2)",
  function() return H.fixedTake(rec(0x10), 1, 2227) == 1 end)
-- $152 on STRAGO at 1800: Blow Fish in slot 0, Quartr in slots 2 and 3.
-- The engine's order (slot 5 first) is Quartr, Quartr, Blow Fish:
-- 1800 -> 450 -> 113 -> dead; slot order would be 1800 -> 800 -> 200 -> 50.
local function chain152()
  local function quartr(left) return H.fixedTake(rec(0x11), left, 3219) end
  local function blow(left) return H.fixedTake(rec(0x90), left, 3219) end
  return H.counterChain({ { slot = 0, take = blow }, { slot = 2, take = quartr }, { slot = 3, take = quartr } }, 1800)
end
check("the counters queue from slot 5 down: Quartr, Quartr, then Blow Fish kills a STRAGO at 1800",
  "counterChain", "return a.slot > b.slot", "return a.slot < b.slot",
  function() local t, each = chain152(); return t == 1800 and each[3] == 1350 and each[2] == 337 and each[0] == 113 end)
check("Phase ($0BC) answers a killing Fight with nothing (if_self_dead / end_if)",
  "retalAnswer", "use.dies ~= nil then holds = use.dies", "use.dies ~= nil then holds = not use.dies",
  function()
    local dead = H.retalAnswer(scriptOf(0x0BC), { cmd = FIGHT, dies = true })
    local alive = H.retalAnswer(scriptOf(0x0BC), { cmd = FIGHT, dies = false })
    return ids(dead) == "" and ids(alive) == "90"
  end)

print(string.format("counter_selftest: PASS -- %d assertions, each failed by its own mutant: %s",
  n, table.concat(checks, "; ")))
