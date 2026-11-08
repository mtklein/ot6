-- @manual standalone: lua tools/tests/lore_loadout_selftest.lua
-- lore_loadout_selftest.lua -- why STRAGO's boss-fight lores never reached his turns in Kefka's Tower (#512), and
-- the field step that slots them (H.loreLoadout).  His battle Lore list is his five-slot loadout plus Aqua Rake,
-- the free row (ot6_lore.asm, Ot6LoreMask); on AUTO the five are the first five lores he knows in id order.  At
-- the Poltergeist (wor-kt-doom-v1: 12 lores) they are Aero, Blow Fish, Revenge, L.5 Doom and Reflect???, so
-- GrandTrain (id 22), which the lab arm named as his nuke lore, was never in the list, and Pearl Wind (id 8),
-- the heal arm's, he has not learned: both arms played the very fights of the arms without them
-- (build/attempts/wt/v039-kefka-tower-2/, a4 against a5).  M.loreList models the ROM's mask (battle_lore checks
-- the ROM's own), M.loreLoadoutFor picks the slots a player would set, M.fightLores reads a fight's opts, and
-- Driver:loreAbsent says, once a battle, why a named lore line is inert.  Pure functions and stubbed RAM: no ROM,
-- no emulator, no gameplay claim (the played evidence is the Poltergeist lab in the commit that added this file).
-- Every assertion runs twice: against the lib as it is (it must hold) and against a mutant -- one edit to the lib
-- function's own source -- under which it must fail.
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
local lib = slurp("tools/tests/lib/ot6.lua")
local H = dofile("tools/tests/lib/ot6.lua")
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
  assert(not mok or mr ~= true, string.format("FAIL %s: the mutant ('%s' -> '%s') passed it too", what, from, to))
  checks[#checks + 1] = what
end
local function mask(ids)
  local m = 0
  for _, id in ipairs(ids) do m = m | (1 << id) end
  return m
end
local function eq(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end
local AQUA, AERO, BLOWFISH, REVENGE, PEARLWIND, DOOM5, REFLECT, DISCHORD, SOUR, RIPPLER, STONE, GRANDTRAIN, EXPLODER =
  3, 4, 5, 7, 8, 9, 12, 16, 17, 19, 20, 22, 23
-- STRAGO's lores in wor-kt-doom-v1 (and wor-kt-poltergeist-v1), the tracked saves of v0.40:
-- "lores12=Aqua Rake,Aero,Blow Fish,Revenge,L.5 Doom,Reflect???,Dischord,Sour Mouth,Rippler,Stone,GrandTrain,Exploder"
local KT = mask({ AQUA, AERO, BLOWFISH, REVENGE, DOOM5, REFLECT, DISCHORD, SOUR, RIPPLER, STONE, GRANDTRAIN, EXPLODER })
local AUTO = { 0, 0, 0, 0, 0 }

-- ---- the battle list (Ot6LoreMask's model) ----------------------------------
check("AUTO at the Poltergeist offers the first five he knows and Aqua Rake: not GrandTrain (the drop, #512)",
  "loreAuto", "#t < M.LORE_SLOTS and ", "", function()
    local l = H.loreList(KT, AUTO)
    local n = 0
    for _ in pairs(l) do n = n + 1 end
    return n == 6 and l[AQUA] and l[AERO] and l[BLOWFISH] and l[REVENGE] and l[DOOM5] and l[REFLECT]
      and not l[GRANDTRAIN] and not l[DISCHORD]
  end)
check("a manual loadout offers its own five and Aqua Rake, not AUTO's",
  "loreList", "if manual then", "if false then", function()
    local l = H.loreList(KT, { GRANDTRAIN + 1, STONE + 1, 0, 0, 0 })
    return l[GRANDTRAIN] == true and l[STONE] == true and l[AQUA] == true and not l[AERO]
  end)
check("a slot storing a lore he has not learned offers nothing (Ot6LoreSlot's validation)",
  "loreList", "and (learned >> id) & 1 == 1 then set[id] = true end",
  "then set[id] = true end", function()
    local l = H.loreList(KT, { PEARLWIND + 1, GRANDTRAIN + 1, 0, 0, 0 })
    return l[PEARLWIND] == nil and l[GRANDTRAIN] == true
  end)

-- ---- the slots a player sets (M.loreLoadoutFor) ------------------------------
check("GrandTrain wanted: AUTO's first four kept, GrandTrain over the fifth (Reflect???)",
  "loreLoadoutFor", "slots[put] = id", "slots[put] = slots[put]", function()
    local s, missing = H.loreLoadoutFor(KT, AUTO, { GRANDTRAIN })
    local load = {}
    for i = 1, 5 do load[i] = s[i] and s[i] + 1 or 0 end
    return eq(s, { AERO, BLOWFISH, REVENGE, DOOM5, GRANDTRAIN }) and #missing == 0
      and H.loreList(KT, load)[GRANDTRAIN] == true
  end)
check("two wanted lores take the last two slots, the more wanted kept where it lands",
  "loreLoadoutFor", "(slots[i] == nil or not wanted[slots[i]])", "(slots[i] == nil or true)", function()
    local s = H.loreLoadoutFor(KT, AUTO, { GRANDTRAIN, STONE })
    return eq(s, { AERO, BLOWFISH, REVENGE, STONE, GRANDTRAIN })
  end)
check("Pearl Wind, never learned on the line, needs no slot and is named as missing (the a5 arm)",
  "loreLoadoutFor", "if (learned >> id) & 1 == 0 then missing[#missing + 1] = id",
  "if false then missing[#missing + 1] = id", function()
    local s, missing = H.loreLoadoutFor(KT, AUTO, { PEARLWIND })
    return s == nil and #missing == 1 and missing[1] == PEARLWIND
  end)
check("a wanted lore already offered moves nothing (no menu opened)",
  "loreLoadoutFor", "if #lacking == 0 then return nil, missing end", "", function()
    return H.loreLoadoutFor(KT, AUTO, { AERO }) == nil
      and H.loreLoadoutFor(KT, { AERO + 1, GRANDTRAIN + 1, 0, 0, 0 }, { GRANDTRAIN }) == nil
      and H.loreLoadoutFor(KT, AUTO, {}) == nil
  end)
check("a manual loadout is edited where it stands, not reset to AUTO",
  "loreLoadoutFor", "if manual then\n    for i = 1, M.LORE_SLOTS do\n      local id = (load[i] or 0) - 1",
  "if false then\n    for i = 1, M.LORE_SLOTS do\n      local id = (load[i] or 0) - 1", function()
    local s = H.loreLoadoutFor(KT, { STONE + 1, EXPLODER + 1, RIPPLER + 1, 0, 0 }, { GRANDTRAIN })
    return eq({ s[1], s[2], s[3], s[5] }, { STONE, EXPLODER, RIPPLER, GRANDTRAIN }) and s[4] == nil
  end)

-- ---- the lores a fight's opts name (M.fightLores) ----------------------------
check("a fight's opts name its lores, Aqua Rake (the free row) never: the a5 and pg0 arms' opts",
  "fightLores", "if so.pearlWind then add(M.LORE_PEARL_WIND) end", "", function()
    return eq(H.fightLores({ nukeLore = { AQUA, GRANDTRAIN } }), { GRANDTRAIN })
      and eq(H.fightLores({ strago = { pearlWind = true } }), { PEARLWIND })
      and eq(H.fightLores({ nukeLore = function() end, strago = { dischord = { [0x0D2] = true } } }), { DISCHORD })
      and #H.fightLores({}) == 0
  end)

-- ---- the driver says why a named lore line is inert (Driver:loreAbsent) -------
local function said(pat)
  for _, s in ipairs(printed) do if s:find(pat, 1, true) then return true end end
  return false
end
local function absentCase(L)
  for k in pairs(mem) do mem[k] = nil end
  printed = {}
  mem[0x1D29], mem[0x1D2A], mem[0x1D2B] = KT & 0xFF, (KT >> 8) & 0xFF, (KT >> 16) & 0xFF
  for _, id in ipairs({ AQUA, AERO, BLOWFISH, REVENGE, DOOM5, REFLECT }) do mem[0x306A + id] = id + 0x8B end
  local D = L.newFightDriver("lab", { nukeLore = { GRANDTRAIN } }).driver
  local inert = D:loreAbsent(GRANDTRAIN, "nuke lore")
  local twice = D:loreAbsent(GRANDTRAIN, "nuke lore")
  local n1 = #printed
  local pw = D:loreAbsent(PEARLWIND, "Pearl Wind")
  local aero = D:loreAbsent(AERO, "nuke lore")
  return inert == true and twice == true and aero == false and pw == true
    and said("lore $16 is not in STRAGO's battle list -- learned, but not in his five")
    and said("lore $08 is not in STRAGO's battle list -- he has not learned it")
    and n1 == 2 and #printed == 4   -- each line twice: the [ot6note] and [ot6] copies M.log prints
end
do
  n = n + 1
  local ok, r = pcall(absentCase, H)
  assert(ok and r == true, "FAIL the driver says once a battle why a named lore is inert: " .. tostring(r))
  for _, m in ipairs({
    { "  if M.loreOffered(lid) then return false end", "  if true then return false end", "never inert" },
    { "  if self.inertSaid[key] then return true end", "", "said every turn" },
  }) do
    local _, count = lib:gsub(plain(m[1]), "")
    assert(count == 1, "the driver's line '" .. m[1] .. "' occurs " .. count .. " times")
    local Hm = assert(load((lib:gsub(plain(m[1]), (m[2]:gsub("%%", "%%%%")))), "=mutant ot6.lua"))()
    local mok, mr = pcall(absentCase, Hm)
    assert(not mok or mr ~= true, "FAIL Driver:loreAbsent: the mutant (" .. m[3] .. ") passed it too")
  end
  checks[#checks + 1] = "the driver says once a battle why a named lore line is inert: GrandTrain learned but "
    .. "outside his five, Pearl Wind not learned; an offered lore is not inert (Driver:loreAbsent, stubbed RAM)"
end

print = rawPrint
print(string.format("lore_loadout_selftest: PASS -- %d assertions, each failed by its own mutant: %s",
  n, table.concat(checks, "; ")))
