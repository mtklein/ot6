-- @suite
-- battle_breakwor_dreams.lua -- the World of Ruin break rows for the Dreams
-- arc (CYAN's dream: the dreamscape, the dream's train and Doma, the cave in
-- Magitek armor, the Dream Stooges and Wrexsoul; the Ancient Castle and its
-- Blue Dragon), re-verified from the built ROM (battle_breakwor_gogo's
-- shape: pure ROM bytes, no savestate).  docs/design/route-wor-dreams.md
-- section 3 is the design; WANT below is its table, and the only place the
-- expectations live.
--
--   1. each species carries exactly its designed Ot6ShieldTbl row and keeps
--      its vanilla weak and absorb bytes, with no Ot6ElemAddTbl row;
--   2. every species of every formation the arc can deal -- the dreamscape
--      (field group 183, map 317), the dream's train and its Doma (181, maps
--      321, 144, 322, 126), the cave (182, maps 319 and 320), the stooges
--      (event group 90), Wrexsoul (92), the Ancient Castle's cave, halls and
--      courtyard (143, 144, 145 on maps 401, 406, 407) and the Blue Dragon
--      (137) -- has an authored row, and every gauged one a key for the hands
--      that meet it there;
--   3. the lessons: TERRA alone keys every body of the dreamscape (she walks
--      it alone until the stooges run); the bolt beam keys every body of the
--      cave (the three ride Magitek armor there); the three stooges take
--      three different class pairs; the Soul Savers take the brush (¤) and
--      no other class; CYAN alone keys every body of the Ancient Castle (his
--      katana, back with every SwdTech); the Blue Dragon keeps its vanilla
--      bolt weakness and water absorb.
-- All mismatches are logged before the verdict.
local H = dofile("tools/tests/lib/ot6.lua")

local SLASH, PIERCE, BLUDG, SPECIAL = 0x01, 0x02, 0x04, 0x08
local FIRE, ICE, BOLT, POISON, WIND, HOLY, EARTH, WATER = 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80

-- species -> { name, shields, class mask, vanilla weak byte, vanilla absorb byte }
local WANT = {
  [0x0BE] = { "Barb-e", 3, SLASH | SPECIAL, POISON, 0 },
  [0x0AB] = { "Critic", 2, SLASH | BLUDG, 0, 0 },
  [0x085] = { "Allosaurus", 3, PIERCE | BLUDG, FIRE | HOLY, 0 },
  [0x0B1] = { "Parasite", 2, SLASH, FIRE, 0 },
  [0x0AC] = { "Pan Dora", 3, BLUDG | SPECIAL, FIRE | HOLY, POISON },
  [0x00A] = { "Rain Man", 2, BLUDG | SPECIAL, ICE | HOLY | WATER, 0 },
  [0x004] = { "Samurai", 3, SLASH | PIERCE, POISON, 0 },
  [0x01E] = { "Suriander", 3, SLASH | BLUDG, HOLY, 0 },
  [0x09D] = { "PlutoArmor", 3, PIERCE, BOLT | WATER, 0 },
  [0x095] = { "Sky Cap", 2, PIERCE | SPECIAL, BOLT | WIND | WATER, 0 },
  [0x0FE] = { "Io", 4, PIERCE | BLUDG, BOLT | HOLY | WATER, 0 },
  [0x11F] = { "Curley", 4, SLASH | SPECIAL, ICE | WATER, FIRE },
  [0x120] = { "Larry", 4, PIERCE | BLUDG, FIRE, ICE | WIND },
  [0x121] = { "Moe", 4, SLASH | BLUDG, 0, BOLT },
  [0x122] = { "Wrexsoul", 6, SLASH | SPECIAL, ICE, FIRE | HOLY },
  [0x167] = { "SoulSaver", 2, SPECIAL, ICE, FIRE | HOLY },
  [0x0A6] = { "Enuo", 2, SLASH | BLUDG, HOLY, 0 },
  [0x06D] = { "Goblin", 3, SLASH | PIERCE, HOLY, 0 },
  [0x057] = { "Figaliz", 3, SLASH | BLUDG, ICE, 0 },
  [0x045] = { "Lethal Wpn", 4, SLASH | BLUDG, BOLT | WATER, 0 },
  [0x051] = { "Boxed Set", 3, SLASH | BLUDG, HOLY, 0 },
  [0x152] = { "Blue Drgn", 6, SLASH | PIERCE, BOLT, WATER },
}

-- the hands, as the arc seats them (route-wor-dreams.md section 2): in the dream TERRA (a blade; Fire, Ice,
-- Bolt), CELES (a blade; Ice) and RELM (a rod: Pearl Rod holy); in the cave the three in Magitek armor, whose
-- rows are the beams (fire, bolt, ice), Bio Blast (poison) and TERRA's Tek Missile (pierce), with no Fight;
-- at the Ancient Castle CYAN (a katana; Quadra Slice wind) beside the three
local TERRA = { "TERRA", SLASH, FIRE | ICE | BOLT }
local CELES = { "CELES", SLASH, ICE }
local RELM = { "RELM", BLUDG, HOLY }
local CYAN = { "CYAN", SLASH, WIND }
local MAGITEK = { "the Magitek rows", PIERCE, FIRE | ICE | BOLT | POISON }
local function union(what, list)
  local h = { cls = 0, el = 0, what = what, members = list }
  for _, m in ipairs(list) do
    h.cls = h.cls | m[2]
    h.el = h.el | m[3]
  end
  return h
end
local TERRA_ALONE = union("TERRA alone", { TERRA })
local DREAM = union("the dream's three (TERRA, CELES, RELM)", { TERRA, CELES, RELM })
local CAVE = union("the three in Magitek armor", { MAGITEK })
local BOLT_BEAM = union("the bolt beam alone", { { "the bolt beam", 0, BOLT } })
local ANCIENT = union("the castle's four (CYAN, CELES, RELM, TERRA)", { CYAN, CELES, RELM, TERRA })
local CYAN_ALONE = union("CYAN alone", { CYAN })

local GROUPS = { { "field", 183, TERRA_ALONE }, { "field", 183, DREAM }, { "field", 181, DREAM },
  { "field", 182, CAVE }, { "event", 90, DREAM }, { "event", 92, DREAM }, { "field", 143, ANCIENT },
  { "field", 144, ANCIENT }, { "field", 145, ANCIENT }, { "event", 137, ANCIENT } }
local POOLS = { [317] = 183, [321] = 181, [144] = 181, [322] = 181, [126] = 181, [319] = 182, [320] = 182,
  [401] = 143, [406] = 144, [407] = 145 }

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

    -- 2. every species of every formation the arc can deal (a formation index is ten bits)
    local rbg = H.sym("RandBattleGroup") & 0x3FFFFF
    local ebg = H.sym("EventBattleGroup") & 0x3FFFFF
    local bm  = H.sym("BattleMonsters") & 0x3FFFFF
    local sbg = H.sym("SubBattleGroup") & 0x3FFFFF
    local function groupForms(kind, n)
      local out = {}
      if kind == "event" then
        out[#out + 1] = rom16(ebg + n * 4) & 0x3FF
        out[#out + 1] = rom16(ebg + n * 4 + 2) & 0x3FF
      else
        for slot = 0, 3 do
          local word = rom16(rbg + n * 8 + slot * 2)
          for k = 0, ((word & 0x8000) ~= 0) and 3 or 0 do out[#out + 1] = (word & 0x3FF) + k end
        end
      end
      return out
    end
    local function formSpecies(f)
      local rec = bm + f * 15
      local pres, hi = H.readRomByte(rec + 1), H.readRomByte(rec + 14)
      local out = {}
      for s = 0, 5 do
        if (pres & (1 << s)) ~= 0 then out[#out + 1] = H.readRomByte(rec + 2 + s) | (((hi >> s) & 1) << 8) end
      end
      return out
    end
    local triples, seen, nform, met = 0, {}, {}, {}
    for _, g in ipairs(GROUPS) do
      local kind, n, hand = g[1], g[2], g[3]
      for _, f in ipairs(groupForms(kind, n)) do
        nform[f] = true
        for _, sp in ipairs(formSpecies(f)) do
          local k2 = f .. "|" .. hand.what .. ":" .. sp
          met[sp] = true
          if not seen[k2] then
            seen[k2] = true
            triples = triples + 1
            if shield[sp] == nil then problem("formation %d (%s group %d): species $%03X has no authored row", f, kind, n, sp) end
            if gauged(sp) and not keys(sp, hand.cls, hand.el) then
              problem("formation %d (%s group %d): species $%03X (class $%02X, weak $%02X) has no key for %s",
                f, kind, n, sp, classOf(sp), weakOf(sp), hand.what)
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
    local function every(list, hand, what)
      local n = 0
      for _, sp in ipairs(list) do
        if keys(sp, hand.cls, hand.el) then n = n + 1 else problem("$%03X %s: %s holds no key", sp, WANT[sp][1], what) end
      end
      H.log(string.format("%s keys %d of %d", what, n, #list))
    end
    local function speciesOf(kind, n)
      local out, s = {}, {}
      for _, f in ipairs(groupForms(kind, n)) do
        for _, sp in ipairs(formSpecies(f)) do
          if not s[sp] then s[sp] = true; out[#out + 1] = sp end
        end
      end
      table.sort(out)
      return out
    end
    every(speciesOf("field", 183), TERRA_ALONE, "TERRA alone (the dreamscape)")
    every(speciesOf("field", 182), BOLT_BEAM, "the bolt beam (the cave)")
    local castle = {}
    for _, g in ipairs({ { "field", 143 }, { "field", 144 }, { "field", 145 }, { "event", 137 } }) do
      for _, sp in ipairs(speciesOf(g[1], g[2])) do castle[#castle + 1] = sp end
    end
    every(castle, CYAN_ALONE, "CYAN alone (the Ancient Castle)")
    local pairs3 = {}
    for _, sp in ipairs({ 0x11F, 0x120, 0x121 }) do
      local cl = classOf(sp)
      if pairs3[cl] then problem("$%03X %s takes the class pair $%02X another stooge takes", sp, WANT[sp][1], cl) end
      pairs3[cl] = true
    end
    if classOf(0x167) ~= SPECIAL then
      problem("$167 SoulSaver: class $%02X, want the brush alone ($%02X)", classOf(0x167), SPECIAL)
    end
    if (weakOf(0x152) & BOLT) == 0 or (absorb(0x152) & WATER) == 0 then
      problem("$152: the Blue Dragon lost its vanilla bolt weakness or its water absorb")
    end
    H.assertEq(#problems, 0, "WoR Dreams arc break row mismatches")
    H.log("WoR Dreams arc (CYAN's dream, the Ancient Castle) break rows verified against the built ROM")
  end),
})
