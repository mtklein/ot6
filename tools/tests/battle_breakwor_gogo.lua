-- @suite
-- battle_breakwor_gogo.lua -- the World of Ruin break rows for the Gogo arc
-- (the Zone Eater and its belly, Ebot's Rock and Hidon, the Opera House's
-- Dirt Dragon, and Doom Gaze in the sky), re-verified from the built ROM
-- (battle_breakwor_gau's shape: pure ROM bytes, no savestate).
-- docs/design/route-wor-gogo.md section 3 is the design; WANT below is its
-- table, and the only place the expectations live.
--
--   1. each species carries exactly its designed Ot6ShieldTbl row and keeps
--      its vanilla weak and absorb bytes, with no Ot6ElemAddTbl row;
--   2. every species of every formation the arc can deal -- Triangle
--      Island (world group 32), the belly's pools (field groups 170 and
--      171 on maps 276-278), Ebot's Rock's (193 and 194 on maps 404 and
--      405) and Hidon (event group 94), the Dirt Dragon (event group 134)
--      and Doom Gaze (event group 93) -- has an authored row, and every
--      gauged one a key for the party that meets it there;
--   3. the lessons: the Zone Eater draws no gauge (the fight is to be
--      eaten); every belly body is keyed by two of the four who walk it;
--      STRAGO's rod alone keys every body at Ebot's Rock (his quest); the
--      Dirt Dragon keeps its vanilla wind and water.
-- All mismatches are logged before the verdict.
local H = dofile("tools/tests/lib/ot6.lua")

local SLASH, PIERCE, BLUDG, SPECIAL = 0x01, 0x02, 0x04, 0x08
local FIRE, ICE, BOLT, POISON, WIND, HOLY, EARTH, WATER = 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80

-- species -> { name, shields, class mask, vanilla weak byte, vanilla absorb byte }
local WANT = {
  [0x171] = { "Zone Eater", 0, 0, HOLY, ICE },
  [0x0DC] = { "Karkass", 3, SLASH | BLUDG, FIRE | HOLY, POISON },
  [0x07D] = { "Wart Puck", 3, PIERCE | BLUDG, FIRE, 0 },
  [0x068] = { "Ogor", 3, SLASH | PIERCE, BOLT | POISON, 0 },
  [0x0F0] = { "Tap Dancer", 2, SLASH | BLUDG, POISON, 0 },
  [0x067] = { "Covert", 3, PIERCE | BLUDG, HOLY, POISON },
  [0x0FA] = { "Woolly", 3, SLASH, FIRE, ICE | BOLT | POISON | WIND | EARTH | WATER },
  [0x069] = { "Warlock", 2, BLUDG | SPECIAL, BOLT | POISON, 0 },
  [0x074] = { "Slatter", 2, PIERCE | BLUDG, HOLY, 0 },
  [0x09A] = { "Cluck", 2, SLASH | BLUDG, ICE, POISON },
  [0x0A5] = { "Eland", 2, PIERCE | BLUDG, BOLT, 0 },
  [0x0B5] = { "Hipocampus", 2, PIERCE | BLUDG, FIRE | HOLY, POISON },
  [0x070] = { "Displayer", 3, BLUDG | SPECIAL, FIRE | HOLY, POISON },
  [0x0C8] = { "Opinicus", 3, SLASH | BLUDG, FIRE | HOLY, POISON },
  [0x123] = { "Hidon", 6, PIERCE | BLUDG, FIRE | HOLY | EARTH, POISON },
  [0x126] = { "Hidonite (poison claw)", 2, SLASH | BLUDG, EARTH, POISON },
  [0x160] = { "Hidonite (confuclaw)", 2, SLASH | BLUDG, 0, FIRE | ICE | BOLT | POISON | WIND | HOLY | WATER },
  [0x161] = { "Hidonite (zombi claw)", 2, PIERCE | BLUDG, FIRE | HOLY, POISON },
  [0x162] = { "Hidonite (mega claw)", 2, BLUDG, FIRE | ICE | BOLT | POISON | WIND | HOLY | EARTH | WATER, 0 },
  [0x14C] = { "Dirt Drgn", 6, PIERCE | BLUDG, WIND | WATER, 0 },
  [0x11D] = { "Doom Gaze", 8, PIERCE | SPECIAL, FIRE | HOLY, ICE | POISON },
}

-- the hands, as the arc seats them (route-wor-gogo.md section 2): TERRA (a dagger; Fire, Pearl), CELES (a
-- blade; Ice), RELM (a rod; Chocobo Brush in the bag: special), STRAGO (a rod; Pearl Rod holy), GOGO (a rod
-- or a dagger; his Mimic copies the others)
local TERRA = { "TERRA", PIERCE, FIRE | HOLY }
local CELES = { "CELES", SLASH, ICE }
local RELM = { "RELM", BLUDG | SPECIAL, 0 }
local STRAGO = { "STRAGO", BLUDG, HOLY }
local GOGO = { "GOGO", BLUDG | PIERCE, 0 }
local function union(what, list)
  local h = { cls = 0, el = 0, what = what, members = list }
  for _, m in ipairs(list) do
    h.cls = h.cls | m[2]
    h.el = h.el | m[3]
  end
  return h
end
local BELLY = union("the belly's four (TERRA, CELES, RELM, STRAGO)", { TERRA, CELES, RELM, STRAGO })
local EBOT = union("Ebot's four (STRAGO, RELM, GOGO, TERRA)", { STRAGO, RELM, GOGO, TERRA })
local DOOM = union("Doom Gaze's four (CELES, RELM, GOGO, STRAGO)", { CELES, RELM, GOGO, STRAGO })
local STRAGO_ALONE = union("STRAGO alone", { STRAGO })

local GROUPS = { { "world", 32, BELLY }, { "field", 170, BELLY }, { "field", 171, BELLY }, { "field", 193, EBOT },
  { "field", 194, EBOT }, { "event", 94, EBOT }, { "event", 134, EBOT }, { "event", 93, DOOM } }
local POOLS = { [276] = 170, [277] = 170, [278] = 171, [404] = 193, [405] = 194 }

H.run({ maxFrames = 600 }, {
  H.waitFrames(30),
  H.call(function()
    local problems = {}
    local function problem(fmt, ...)
      local msg = string.format(fmt, ...)
      problems[#problems + 1] = msg
      H.log("MISMATCH: " .. msg)
    end
    local function rom16(a) return H.readRomByte(a) | (H.readRomByte(a + 1) << 8) end
    local function readTable(a)
      local rows = {}
      while true do
        local sp = rom16(a)
        if sp == 0xFFFF then break end
        if rows[sp] == nil then rows[sp] = { H.readRomByte(a + 2), H.readRomByte(a + 3) } end
        a = a + 4
      end
      return rows
    end
    local shield = readTable(H.sym("Ot6ShieldTbl") & 0x3FFFFF)
    local elemAdd = readTable(H.sym("Ot6ElemAddTbl") & 0x3FFFFF)
    local prop = H.sym("MonsterProp") & 0x3FFFFF
    local floor = H.sym("OT6_FLOOR_CLASS") & 0x3FFFFF
    local function weak(sp) return H.readRomByte(prop + sp * 32 + 25) end
    local function absorb(sp) return H.readRomByte(prop + sp * 32 + 23) end
    local function classOf(sp) return shield[sp] and shield[sp][2] or H.readRomByte(floor + sp) end
    local function weakOf(sp) return weak(sp) | (elemAdd[sp] and elemAdd[sp][1] or 0) end
    local function keys(sp, cls, el) return (classOf(sp) & cls) ~= 0 or (weakOf(sp) & el) ~= 0 end
    local function gauged(sp) return shield[sp] == nil or shield[sp][1] > 0 end

    -- 1. the designed rows
    local ids = {}
    for sp in pairs(WANT) do ids[#ids + 1] = sp end
    table.sort(ids)
    for _, sp in ipairs(ids) do
      local w = WANT[sp]
      local got = shield[sp]
      if got == nil then
        problem("$%03X %s has no Ot6ShieldTbl row (want %d, class $%02X)", sp, w[1], w[2], w[3])
      else
        if got[1] ~= w[2] then problem("$%03X %s shields %d, want %d", sp, w[1], got[1], w[2]) end
        if got[2] ~= w[3] then problem("$%03X %s class mask $%02X, want $%02X", sp, w[1], got[2], w[3]) end
      end
      if weak(sp) ~= w[4] then problem("$%03X %s weak byte $%02X, want vanilla $%02X", sp, w[1], weak(sp), w[4]) end
      if absorb(sp) ~= w[5] then
        problem("$%03X %s absorb byte $%02X, want vanilla $%02X", sp, w[1], absorb(sp), w[5])
      end
      if elemAdd[sp] then problem("$%03X %s adds elements $%02X, want none", sp, w[1], elemAdd[sp][1]) end
    end
    H.log(string.format("checked %d designed rows", #ids))

    -- 2. every species of every formation the arc can deal (a formation index is ten bits; a world
    -- group's words are RandBattleGroup's, as a field group's)
    local rbg = H.sym("RandBattleGroup") & 0x3FFFFF
    local ebg = H.sym("EventBattleGroup") & 0x3FFFFF
    local bm  = H.sym("BattleMonsters") & 0x3FFFFF
    local sbg = H.sym("SubBattleGroup") & 0x3FFFFF
    local formations, order = {}, {}
    local function addForm(f, where, hand)
      local key = f .. "|" .. hand.what
      if formations[key] == nil then
        formations[key] = { f = f, where = where, hand = hand }
        order[#order + 1] = key
      end
    end
    for _, g in ipairs(GROUPS) do
      local kind, n, hand = g[1], g[2], g[3]
      if kind == "event" then
        addForm(rom16(ebg + n * 4) & 0x3FF, "event group " .. n, hand)
        addForm(rom16(ebg + n * 4 + 2) & 0x3FF, "event group " .. n, hand)
      else
        for slot = 0, 3 do
          local word = rom16(rbg + n * 8 + slot * 2)
          for k = 0, ((word & 0x8000) ~= 0) and 3 or 0 do addForm((word & 0x3FF) + k, kind .. " group " .. n, hand) end
        end
      end
    end
    table.sort(order)
    local triples, seen, nform, met = 0, {}, {}, {}
    for _, key in ipairs(order) do
      local fr = formations[key]
      local f, where, hand = fr.f, fr.where, fr.hand
      nform[f] = true
      local rec = bm + f * 15
      local pres, hi = H.readRomByte(rec + 1), H.readRomByte(rec + 14)
      for s = 0, 5 do
        if (pres & (1 << s)) ~= 0 then
          local sp = H.readRomByte(rec + 2 + s) | (((hi >> s) & 1) << 8)
          local k2 = key .. ":" .. sp
          met[sp] = true
          if not seen[k2] then
            seen[k2] = true
            triples = triples + 1
            if shield[sp] == nil then problem("formation %d (%s): species $%03X has no authored row", f, where, sp) end
            if gauged(sp) and not keys(sp, hand.cls, hand.el) then
              problem("formation %d (%s): species $%03X (class $%02X, weak $%02X) has no key for %s",
                f, where, sp, classOf(sp), weakOf(sp), hand.what)
            end
          end
        end
      end
    end
    local nf = 0
    for _ in pairs(nform) do nf = nf + 1 end
    H.log(string.format("checked %d formations, %d formation-species-hands triples", nf, triples))
    for sp in pairs(met) do
      if WANT[sp] == nil then problem("species $%03X is met on this arc and has no line in WANT", sp) end
    end
    for _, sp in ipairs(ids) do
      if not met[sp] then problem("$%03X %s is in WANT but no group of the arc deals it", sp, WANT[sp][1]) end
    end
    for m, g in pairs(POOLS) do
      local got = H.readRomByte(sbg + m)
      if got ~= g then problem("map %d's pool is group %d, the design read %d", m, got, g) end
    end

    -- 3. the lessons
    if shield[0x171] == nil or shield[0x171][1] ~= 0 then
      problem("$171 the Zone Eater draws a gauge: the island's fight is to be eaten")
    end
    for _, sp in ipairs({ 0x0DC, 0x07D, 0x068, 0x0F0, 0x067, 0x0FA }) do
      local n = 0
      for _, m in ipairs(BELLY.members) do if keys(sp, m[2], m[3]) then n = n + 1 end end
      if n < 2 then problem("$%03X %s: %d of the belly's four hold a key, want two or more", sp, WANT[sp][1], n) end
    end
    local stragoKeys = 0
    for _, sp in ipairs({ 0x069, 0x074, 0x09A, 0x0A5, 0x0B5, 0x070, 0x0C8, 0x123, 0x126, 0x160, 0x161, 0x162 }) do
      if keys(sp, STRAGO_ALONE.cls, STRAGO_ALONE.el) then
        stragoKeys = stragoKeys + 1
      else
        problem("$%03X %s: STRAGO alone holds no key", sp, WANT[sp][1])
      end
    end
    H.log(string.format("STRAGO alone keys %d of Ebot's Rock's 12 bodies", stragoKeys))
    if (weakOf(0x14C) & (WIND | WATER)) ~= (WIND | WATER) then
      problem("$14C: the Dirt Dragon lost its vanilla wind and water")
    end
    H.assertEq(#problems, 0, "WoR Gogo arc break row mismatches")
    H.log("WoR Gogo arc (the belly, Ebot's Rock, the Opera House, Doom Gaze) break rows verified against the built ROM")
  end),
})
