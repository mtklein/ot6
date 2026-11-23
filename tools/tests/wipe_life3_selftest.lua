-- @manual standalone: lua tools/tests/wipe_life3_selftest.lua
-- wipe_life3_selftest.lua -- a lost battle cannot read as won, and a party
-- that Life 3 raises does not read as wiped (#564).  RAM is a stub table;
-- no emulator, no ROM, no gameplay claim.
--
-- The case: MagiMaster's dying Ultima took all four to 0 HP at once, three
-- wearing Life 3; the engine raised the three and the battle was won.  The
-- driver printed four [death] lines and a [wipe], then the battle read WON
-- (build/attempts/wt/v051-wipe-win/wor_tower.2026-11-22.log.gz:
-- '[end] f250800 $166 HP 0: e0 3591 shell=0 life3=1, e1 3470 ... life3=1,
-- e2 3623 ... life3=1, e3 3219 shell=0 life3=0', '[wipe] f+30413',
-- 'partyhp=448,433,452,0', 'battle $162 WON after 31262 ticks').  The
-- verdict was right and the [wipe] line was not.
--
-- Checked here, each against the library as it is (must hold) and against a
-- mutant of its source (must fail):
--   1. the outcome: a battle whose end reading carries LoseBattle's bit,
--      or every seat at 0, is LOST even with every monster dead (vanilla's
--      CheckBattleEnd reads the party first), and the MagiMaster ending
--      (three raised, bit clear) is WON;
--   2. M.wipeHeld: the wipe is held back only while LoseBattle's bit is
--      clear AND a fallen member carried Life 3 not yet answered;
--   3. Driver:watchHits on the stub, frame by frame through the MagiMaster
--      ending: four [death] lines (three saying Life 3), one [allfell], no
--      [wipe], three [raised] lines; the same ending with no Life 3 on
--      anyone prints the [wipe] at once; and a held wipe is said once
--      LoseBattle's bit sets.
emu = { eventType = { inputPolled = 1 }, callbackType = { exec = 1 },
        addEventCallback = function() return 1 end, addMemoryCallback = function() return 1 end }
local LIB = "tools/tests/lib/ot6.lua"

local function slurp(path)
  local f = assert(io.open(path, "rb"), path)
  local s = f:read("a"); f:close(); return s
end
local libSrc = slurp(LIB)

local mem, logged = {}, {}
local function w8(a, v) mem[a] = v & 0xFF end
local function w16(a, v) mem[a] = v & 0xFF; mem[a + 1] = (v >> 8) & 0xFF end

local function libFrom(src)
  local path = os.tmpname()
  local f = assert(io.open(path, "wb")); f:write(src); f:close()
  local H = dofile(path)
  os.remove(path)
  H.readByte = function(a) return mem[a] or 0 end
  H.readWord = function(a) return (mem[a] or 0) | ((mem[a + 1] or 0) << 8) end
  H.log = function(s) logged[#logged + 1] = s end
  return H
end
local REAL = libFrom(libSrc)
local function plain(s) return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")) end
local function mutantLib(edits)
  local src = libSrc
  for _, e in ipairs(edits) do
    local n
    src, n = src:gsub(plain(e[1]), (e[2]:gsub("%%", "%%%%")), 1)
    assert(n == 1, "mutant edit not found: " .. e[1])
  end
  return libFrom(src)
end

local n, said = 0, {}
local function check(what, edits, f)
  n = n + 1
  local ok, r = pcall(f, REAL)
  assert(ok and r == true, "FAIL " .. what .. ": " .. tostring(r))
  local mok, mr = pcall(f, mutantLib(edits))
  assert(not mok or mr ~= true, "FAIL " .. what .. ": the mutant passed it too")
  said[#said + 1] = what
end

-- the four seats as MagiMaster met them (wor_tower 2026-11-22, '[open] ...
-- e0 3591/3591, e1 3470/3470, e2 3623/3623, e3 3219/3219'; chars 0, 6, 8, 7)
local SEATS = { { 0, 3591 }, { 6, 3470 }, { 8, 3623 }, { 7, 3219 } }
local function rows(hps)
  local t = {}
  for e = 0, 3 do t[e + 1] = { actor = SEATS[e + 1][1], present = true, hp = hps[e + 1], maxhp = SEATS[e + 1][2] } end
  return t
end
-- the end reading for one MagiMaster slot, dead (STATUS1 Wound)
local function ending(H, hps, flags)
  local st1, xp, hp = {}, {}, {}
  for s = 0, 5 do st1[s], xp[s], hp[s] = 0, 0, 0 end
  st1[0], xp[0] = 0x80, 0
  return H.battleOutcome({ xp = xp, st1 = st1, hp = hp, egg = {}, random = false, mul16 = 16,
    alive = 0, aliveMask = 0, veldt = false, colosseum = false, left = 0, gone = 1,
    lost = H.wipeVerdict(rows(hps), flags), seated = { [0] = true, true, true, true },
    filled = { [0] = true } })
end

-- 1. the outcome
check("a loss with the boss dead beside it reads LOST (LoseBattle's bit, every seat at 0)",
  { { 'if o.lost then kind = "lost"', 'if false then kind = "lost"' } },
  function(H)
    return ending(H, { 0, 0, 0, 0 }, 0x0D).kind == "lost"
       and ending(H, { 0, 0, 0, 0 }, 0x0C).kind == "lost"
       and ending(H, { 448, 0, 0, 0 }, 0x0D).kind == "lost"
  end)
check("MagiMaster's ending, three raised and the bit clear, reads WON",
  { { "if (flags & 0x01) ~= 0 then return true end\n  return alive == 0",
      "if (flags & 0x01) ~= 0 then return true end\n  return alive < 4" } },
  function(H) return ending(H, { 448, 433, 452, 0 }, 0x0C).kind == "won" end)

-- 2. M.wipeHeld
local function d(e, life3, raised) return { e = e, life3 = life3, raised = raised } end
check("the wipe is held for a Life 3 carrier only while LoseBattle's bit is clear",
  { { "  if (flags & 0x01) ~= 0 then return nil end\n  local held = {}", "  local held = {}" } },
  function(H)
    local four = { d(0, true), d(1, true), d(2, true), d(3, false) }
    local h = H.wipeHeld(0x0C, four)
    return h ~= nil and #h == 3 and h[1] == 0 and h[3] == 2 and H.wipeHeld(0x0D, four) == nil
  end)
check("no Life 3 on anyone, or every carrier already raised and fallen again: no hold",
  { { "if d ~= nil and d.life3 and not d.raised then", "if d ~= nil then" } },
  function(H)
    return H.wipeHeld(0x0C, { d(0, false), d(1, false), d(2, false), d(3, false) }) == nil
       and H.wipeHeld(0x0C, { d(0, true, true), d(1, false), d(0, false) }) == nil
  end)

-- 3. Driver:watchHits through the ending, frame by frame
local function seat(H, hps, life3)
  for e = 0, 3 do
    w8(0x3ED8 + e * 2, SEATS[e + 1][1]); w8(0x3AA0 + e * 2, 1)
    w16(0x3BF4 + e * 2, hps[e + 1]); w16(0x3C1C + e * 2, SEATS[e + 1][2])
    w8(0x3EF9 + e * 2, life3[e + 1] and 0x04 or 0)
  end
end
local function drive(H, life3, lostAfter)
  for k in pairs(mem) do mem[k] = nil end
  for i = #logged, 1, -1 do logged[i] = nil end
  H.partyWipedInBattle = function()
    local r = {}
    for e = 0, 3 do
      r[e + 1] = { actor = H.readByte(0x3ED8 + e * 2), present = true, hp = H.readWord(0x3BF4 + e * 2),
                   maxhp = H.readWord(0x3C1C + e * 2) }
    end
    return H.wipeVerdict(r, H.readByte(0x3EBC))
  end
  local dr = H.newFightDriver("wipe life3", {}).driver
  dr.battleTick = 30000
  local full = { 3591, 3470, 3623, 3219 }
  w8(0x3EBC, 0x0C)
  seat(H, full, life3); dr:watchHits()
  -- the Ultima: every seat at 0, the Life 3 bits cleared as the raises queue
  seat(H, { 0, 0, 0, 0 }, { false, false, false, false })
  for _ = 1, 3 do dr.battleTick = dr.battleTick + 1; dr:watchHits() end
  -- a raise that never comes: LoseBattle's bit sets with the four still down
  if lostAfter then
    w8(0x3EBC, 0x0D)
    for _ = 1, 3 do dr.battleTick = dr.battleTick + 1; dr:watchHits() end
    life3 = { false, false, false, false }
  end
  -- the raises land one by one, at an eighth of max HP, where Life 3 was on
  local hp = { 0, 0, 0, 0 }
  for _, e in ipairs({ 2, 1, 0 }) do
    if life3[e + 1] then hp[e + 1] = full[e + 1] // 8 end
    seat(H, hp, { false, false, false, false })
    dr.battleTick = dr.battleTick + 1; dr:watchHits()
  end
  local c = { death = 0, deathL3 = 0, allfell = 0, wipe = 0, raised = 0, raisedL3 = 0 }
  for _, s in ipairs(logged) do
    if s:find("%[death%]") then
      c.death = c.death + 1
      if s:find("Life 3 was on", 1, true) then c.deathL3 = c.deathL3 + 1 end
    end
    if s:find("%[allfell%]") then c.allfell = c.allfell + 1 end
    if s:find("%[wipe%]") then c.wipe = c.wipe + 1 end
    if s:find("%[raised%]") then
      c.raised = c.raised + 1
      if s:find("by Life 3", 1, true) then c.raisedL3 = c.raisedL3 + 1 end
    end
  end
  return c
end
check("the MagiMaster ending reads four deaths, one [allfell], three Life 3 raises and no [wipe]",
  { { "    if held ~= nil then\n      if not self.allFellSaid then", "    if false then\n      if not self.allFellSaid then" } },
  function(H)
    local c = drive(H, { true, true, true, false })
    return c.death == 4 and c.deathL3 == 3 and c.allfell == 1 and c.wipe == 0
       and c.raised == 3 and c.raisedL3 == 3
  end)
check("the same ending with no Life 3 on anyone prints the [wipe] at once",
  { { "    if hp > 0 and hp ~= 0xFFFF and maxhp > 0 then\n      self.life3Seen[e] =",
      "    if maxhp > 0 then\n      self.life3Seen[e] =" } },
  function(H)
    local c = drive(H, { false, false, false, false })
    local c3 = drive(H, { true, true, true, false })
    return c.death == 4 and c.deathL3 == 0 and c.allfell == 0 and c.wipe == 1 and c.raised == 0
       and c3.wipe == 0 and c3.allfell == 1
  end)
check("a held wipe is said once LoseBattle's bit sets",
  { { "local held = M.wipeHeld(M.readByte(0x3ebc), self.battleDeaths)",
      "local held = M.wipeHeld(0, self.battleDeaths)" } },
  function(H)
    local c = drive(H, { true, true, true, false }, true)
    return c.death == 4 and c.allfell == 1 and c.wipe == 1 and c.raised == 0
  end)

print(string.format("wipe_life3_selftest: %d checks held on the library and failed on their mutants", n))
for _, s in ipairs(said) do print("  ok: " .. s) end
