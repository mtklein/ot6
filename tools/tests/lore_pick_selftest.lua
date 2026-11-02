-- @manual standalone: lua tools/tests/lore_pick_selftest.lua  (after ninja build/ot6.sfc)
-- lore_pick_selftest.lua -- the nuke picker's arithmetic (#388,
-- opts.nukeLore = "best"): M.loreHit and M.bestLore against the built
-- ROM's MagicProp records and hand-checked numbers.  No emulator: the
-- targets are synthetic, so this holds for any body the game can field.
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
local MAGIC = symbol("MagicProp")
H.sym = function(s) assert(s == "MagicProp", "unexpected symbol " .. s); return MAGIC end
H.readRomByte = function(a) return rom:byte(a + 1) end

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

local CLEANSWEEP, AQUA_RAKE, AERO, QUASAR, GRANDTRAIN = 0x02, 0x03, 0x04, 0x15, 0x16
local WIND, WATER = 0x10, 0x80
local function rec(lore) return MAGIC + (0x8B + lore) * 14 end
-- the records the cases below were worked from
local function want(lore, power, elem, f2)
  local r = rec(lore)
  assert(rom:byte(r + 7) == power and rom:byte(r + 2) == elem and rom:byte(r + 3) == f2,
    string.format("lore $%02X in MagicProp: power %d, element $%02X, flags $%02X; read %d, $%02X, $%02X",
      lore, power, elem, f2, rom:byte(r + 7), rom:byte(r + 2), rom:byte(r + 3)))
end
want(GRANDTRAIN, 84, 0x00, 0x20)   -- no element; magic defense ignored
want(AQUA_RAKE, 71, 0x90, 0x00)    -- water and wind
want(AERO, 125, 0x10, 0x00)        -- wind
want(CLEANSWEEP, 50, 0x80, 0x40)   -- water, not split
for _, l in ipairs(H.NUKE_LORES) do
  local r = rec(l)
  assert(rom:byte(r + 7) > 0, string.format("lore $%02X deals damage (power %d)", l, rom:byte(r + 7)))
end

-- STRAGO at L51 with magic power 60 (the battle's $3B41, half added)
local S = { level = 51, magpow = 60 }
local function body(t) t.hp = t.hp or 60000; t.mdef = t.mdef or 0; return t end

-- by hand, GrandTrain: base 84*4 + (60*84*51 >> 5) = 336 + 8032 = 8368;
-- least 8368*224 >> 8 = 7322, +1 = 7323; most 8368*255 >> 8 = 8335, +1 =
-- 8336; magic defense ignored; the middle (7323 + 8336) // 2 = 7829
check("GrandTrain on a body at mdef 200: 7829, its magic defense ignored",
  "loreHit", "flags2 = f2,", "flags2 = 0,",
  function() return H.loreHit(GRANDTRAIN, S, body({ mdef = 200 }), false) == 7829 end)
check("split across bodies it halves (7829 -> 3914)",
  "loreHit", "if split and (f2 & 0x40) == 0 then d = d // 2 end", "",
  function() return H.loreHit(GRANDTRAIN, S, body({}), true) == 3914 end)
check("CleanSweep's record says not to split: the same on one body or several",
  "loreHit", "if split and (f2 & 0x40) == 0 then", "if split then",
  function()
    return H.loreHit(CLEANSWEEP, S, body({}), true) == H.loreHit(CLEANSWEEP, S, body({}), false)
  end)
check("capped at the body's HP",
  "loreHit", "d = math.min(d, t.hp or d)", "",
  function() return H.loreHit(GRANDTRAIN, S, body({ hp = 300 }), false) == 300 end)
check("a body that absorbs wind is healed by Aqua Rake: a negative score",
  "loreHit", "then return -d end", "then return d end",
  function() return H.loreHit(AQUA_RAKE, S, body({ absorb = WIND }), true) < 0 end)

local ALL = { { lore = AQUA_RAKE, cost = 22 }, { lore = AERO, cost = 41 }, { lore = GRANDTRAIN, cost = 64 } }
check("three bodies that null wind: GrandTrain, not Aero or Aqua Rake",
  "bestLore", "if s > best then best = s end", "if s > best and c.lore ~= 0x16 then best = s end",
  function()
    local t = { body({ null = WIND }), body({ null = WIND }), body({ null = WIND }) }
    return H.bestLore(ALL, S, t, 999) == GRANDTRAIN
  end)
check("a water-weak pair: Aqua Rake (the double beats Aero and GrandTrain)",
  "bestLore", "c.score >= best * M.LORE_PICK_NEAR and", "c.score >= 0 and c.cost > 22 and",
  function() return H.bestLore(ALL, S, { body({ weak = WATER }), body({ weak = WATER }) }, 999) == AQUA_RAKE end)
check("the MP the caster may spend: under 64, GrandTrain is not offered",
  "bestLore", "if c.cost <= mpFree then", "if true then",
  function()
    local t = { body({ null = WIND }), body({ null = WIND }) }
    return H.bestLore(ALL, S, t, 63) == nil
  end)
-- bodies with a few hundred HP each: every lore kills them all, so the
-- scores tie at the HP and the cheapest is the one a player casts
check("bodies every lore kills: the cheapest (Aqua Rake)",
  "bestLore", "(pick == nil or c.cost < pick.cost", "(pick == nil or c.cost > pick.cost",
  function()
    local t = { body({ hp = 400 }), body({ hp = 400 }), body({ hp = 400 }) }
    return H.bestLore(ALL, S, t, 999) == AQUA_RAKE
  end)
check("a body that absorbs every element in hand and nothing else on the field: no lore",
  "bestLore", "if best <= 0 then return nil, 0, 0 end", "",
  function()
    local wet = { { lore = AQUA_RAKE, cost = 22 }, { lore = AERO, cost = 41 } }
    return H.bestLore(wet, S, { body({ absorb = WIND | WATER }) }, 999) == nil
  end)

print(string.format("lore_pick_selftest: PASS -- %d assertions, each failed by its own mutant: %s",
  n, table.concat(checks, "; ")))
