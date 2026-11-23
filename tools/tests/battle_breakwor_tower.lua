-- @suite
-- battle_breakwor_tower.lua -- the World of Ruin break rows for Kefka's Tower (maps 287-355, 409-412: pool groups
-- 208-227, event battles 98, 99, 100, 112, 114, 135, 136, 140), re-verified from the built ROM
-- (battle_breakwor_sidetrips's shape: pure ROM bytes, no savestate).  docs/design/route-wor-kefka-tower.md section 3
-- is the design; the tables below are its, and the only place the expectations live.
--
--   1. every designed species carries exactly its Ot6ShieldTbl row, keeps its vanilla weak and absorb bytes, and has
--      no Ot6ElemAddTbl row;
--   2. every species of every formation the tower's twenty pool groups and eight event battles deal has an authored
--      row, and a key for each party whose lane meets it (LANES);
--   3. the lessons: the factory's machines turn the blades (no sword, no katana) and take a point and a blow
--      (what the four classes' pierce and bludgeon became: a dagger, a spear or a ranged hit, and a blunt or a
--      ranged one; two different classes) and bolt; the three statues each take the cards or the brush (what
--      special became), and between them a blade, a point and a blow, four classes or more; the Guardian the
--      tower fights ($112) has a gauge, and the World of Balance's ($111) still has none.
-- All mismatches are logged before the verdict.
local H = dofile("tools/tests/lib/ot6.lua")

local SWORD, DAGGER, BLUNT, RANGED, KATANA, SPEAR = 0x01, 0x02, 0x04, 0x08, 0x10, 0x20   -- ot6_class.asm (#566)
-- a hand is W(item): the class the built ROM gives the weapon (Ot6WeapClassTbl); SK(ability) a skill's own
-- (Ot6SkillClassTbl).  Read from the ROM, so a hand follows the classes the build has.
local W, SK = H.weaponClass, H.skillClass
local FIRE, ICE, BOLT, POISON, WIND, HOLY, EARTH, WATER = 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80
-- what each of the four classes became (tools/six_classes/classes.py CHILDREN): slash a sword or a katana, pierce a
-- dagger, a spear or a ranged hit, bludgeon a blunt or a ranged one
local EDGE, POINT, BLOW = SWORD | KATANA, DAGGER | SPEAR | RANGED, BLUNT | RANGED
local function nbits(m) local n = 0; while m ~= 0 do n = n + (m & 1); m = m >> 1 end; return n end

-- species -> { name, shields, class mask, vanilla weak byte, vanilla absorb byte }
local WANT = {
  [0x084] = { "Brontaur", 3, DAGGER | BLUNT, ICE, 0 },
  [0x0B7] = { "Evil Oscar", 3, KATANA | BLUNT, FIRE, 0xFE },
  [0x080] = { "Vectaur", 2, SPEAR | KATANA, ICE | WATER, 0 },
  [0x0E0] = { "GtBehemoth", 3, DAGGER | BLUNT, 0, 0 },
  [0x00D] = { "Dark Force", 3, BLUNT | RANGED, HOLY, 0 },
  [0x0BD] = { "Outsider", 3, SWORD | DAGGER, HOLY, POISON },
  [0x06A] = { "Madam", 3, KATANA | RANGED, POISON, 0 },
  [0x007] = { "Retainer", 3, KATANA | BLUNT, POISON, 0 },
  [0x0C1] = { "Hemophyte", 2, KATANA | RANGED, 0, 0 },
  [0x0FB] = { "Veteran", 3, SWORD | DAGGER, 0, 0 },
  [0x0F9] = { "Didalos", 3, BLUNT | RANGED, FIRE | HOLY, POISON },
  [0x016] = { "Steroidite", 4, SPEAR | RANGED, HOLY, 0 },
  [0x056] = { "Mover", 1, KATANA | RANGED, 0, POISON },
  [0x025] = { "Doom Drgn", 4, SPEAR | BLUNT, 0, 0 },
  [0x0E4] = { "Vectagoyle", 3, BLUNT | RANGED, 0, 0 },
  [0x09B] = { "Land Worm", 3, DAGGER | KATANA, ICE, EARTH },
  [0x0FD] = { "IronHitman", 2, SPEAR | RANGED, BOLT | WATER, 0 },
  [0x0D9] = { "Dueller", 3, SPEAR | RANGED, BOLT | WATER, 0 },
  [0x0EA] = { "Fortis", 4, SPEAR | RANGED, BOLT | WATER, 0 },
  [0x0ED] = { "Junk", 2, SPEAR | RANGED, BOLT | WATER, 0 },
  [0x0F6] = { "Innoc", 3, SPEAR | RANGED, BOLT | WATER, 0 },
  [0x105] = { "Prometheus", 4, SPEAR | RANGED, BOLT | WATER, 0 },
  [0x0FC] = { "Sky Base", 2, SPEAR | RANGED, BOLT | WATER, 0 },
  [0x0A1] = { "Scullion", 4, SPEAR | RANGED, BOLT | WATER, 0 },
  [0x10C] = { "Inferno", 6, SPEAR | RANGED, BOLT, FIRE },
  [0x142] = { "Striker", 3, SPEAR | KATANA, FIRE, ICE },
  [0x141] = { "Rough", 3, KATANA | RANGED, ICE, BOLT },
  [0x112] = { "Guardian", 10, SPEAR | RANGED, BOLT | WATER, 0 },
  [0x127] = { "Doom", 10, KATANA | RANGED, HOLY, ICE | POISON },
  [0x128] = { "Goddess", 8, SPEAR | RANGED, 0, BOLT | HOLY },
  [0x129] = { "Poltrgeist", 8, BLUNT | RANGED, POISON, FIRE | WIND },
  [0x17D] = { "Atma", 10, SPEAR | KATANA, 0, POISON | WIND | HOLY | EARTH | WATER },
  [0x150] = { "Gold Drgn", 6, SPEAR | KATANA, WATER, BOLT },
  [0x151] = { "Skull Drgn", 6, BLUNT | RANGED, FIRE | HOLY, POISON },
}
local MACHINES = { 0x0FD, 0x0D9, 0x0EA, 0x0ED, 0x0F6, 0x105, 0x0FC, 0x0A1, 0x10C, 0x112 }
local STATUES = { 0x127, 0x128, 0x129 }
local EVENTS = { 98, 99, 100, 112, 114, 135, 136, 140 }
-- the three parties the route seats (route-wor-kefka-tower.md section 4) and the lanes they walk (section 2): the
-- pool groups and event battles each meets, the class keys its weapons hold and the elements its spells, skeans
-- and lores reach at wor-desert-v1.  A species keys a party when either meets it.
--   party 1: TERRA (a blade, the Falchion $15; Fire, Ice, Bolt), RELM (a rod, the Magus Rod $3C), EDGAR (a knife,
--            the Man Eater $06), SETZER (cards, the Trump $50): the north-west,
--            303, 304, 292, the machines' hall 352, 295; the chamber's east column, the Goddess (354)
--   party 2: CELES (a blade, the Falchion; Ice), STRAGO (a rod, the Pearl Rod $39; Aqua Rake), LOCKE (the Wing
--            Edge $4C), MOG (a spear, the Partisan $20): 338, 331
--            (Atma), 329, 409, 292, 294, 335 (the Gold Dragon), 354; the chamber's middle, Guardian (291), 287,
--            the Poltergeist (334)
--   party 3: CYAN (katanas, the Strato $31), SHADOW (the Striker $29; the skeans he throws, $51-$53: fire,
--            water, bolt), SABIN (claws, the Dragon Claw $58; fire, holy), GOGO (a knife, the Man Eater): 339, the factory 410 (Inferno), 296, 293, 354 (the Skull Dragon); the chamber's west
--            column, Doom (355)
-- The chamber's gate switches shut each column behind the party that enters it, so the order the weights fall
-- in sets the lanes (route-wor-kefka-tower.md section 2): party 1 east, party 3 west, party 2 the middle.
local LANES = TOWER_LANES or {
  { "party 1", W(0x15) | W(0x3C) | W(0x06) | W(0x50), FIRE | ICE | BOLT, { 208, 209, 210, 211, 212, 213, 220, 221,
    226 }, { 99 } },
  { "party 2", W(0x15) | W(0x39) | W(0x4C) | W(0x20), ICE | WATER, { 208, 211, 214, 215, 216, 217, 218, 226, 227, 220, 221 },
    { 112, 135, 140, 100 } },
  { "party 3", W(0x31) | W(0x29) | SK(0x51) | W(0x58) | W(0x06), FIRE | BOLT | WATER | HOLY, { 208, 222, 223, 224, 225, 226, 220, 221 },
    { 114, 136, 98 } },
}

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
    local rbg = H.sym("RandBattleGroup") & 0x3FFFFF
    local ebg = H.sym("EventBattleGroup") & 0x3FFFFF
    local bm = H.sym("BattleMonsters") & 0x3FFFFF
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
    H.log(string.format("checked %d designed rows (the tower's bodies)", #ids))

    -- 2. the tower's pools and event battles: every species authored, and keyed by each party that meets it
    local seen, n = {}, 0
    local function check(f, what, lane)
      for _, sp in ipairs(formSpecies(f)) do
        n = n + 1
        seen[sp] = true
        if shield[sp] == nil then problem("formation %d (%s): species $%03X has no authored row", f, what, sp) end
        if lane and (classOf(sp) & lane[2]) == 0 and (weakOf(sp) & lane[3]) == 0 then
          problem("formation %d (%s): species $%03X (class $%02X, weak $%02X) has no key for %s", f, what, sp,
            classOf(sp), weakOf(sp), lane[1])
        end
      end
    end
    for g = 208, 227 do
      for _, f in ipairs(groupForms("random", g)) do check(f, "pool group " .. g) end
    end
    for _, e in ipairs(EVENTS) do
      for _, f in ipairs(groupForms("event", e)) do check(f, "event battle " .. e) end
    end
    for _, lane in ipairs(LANES) do
      for _, g in ipairs(lane[4]) do
        for _, f in ipairs(groupForms("random", g)) do check(f, "pool group " .. g, lane) end
      end
      for _, e in ipairs(lane[5]) do
        for _, f in ipairs(groupForms("event", e)) do check(f, "event battle " .. e, lane) end
      end
    end
    for _, sp in ipairs(ids) do
      if not seen[sp] then problem("$%03X %s is no longer dealt by the tower", sp, WANT[sp][1]) end
    end
    H.log(string.format("checked %d formation-species pairs of pool groups 208-227, the %d event battles and the "
      .. "three lanes", n, #EVENTS))

    -- 3. the lessons
    for _, sp in ipairs(MACHINES) do
      local nm = WANT[sp][1]
      if (classOf(sp) & EDGE) ~= 0 then problem("$%03X %s: a machine the blades (a sword, a katana) key", sp, nm) end
      if (classOf(sp) & POINT) == 0 or (classOf(sp) & BLOW) == 0 or nbits(classOf(sp) & (POINT | BLOW)) < 2 then
        problem("$%03X %s: a machine not keyed by a point and a blow, two classes (class $%02X)", sp, nm, classOf(sp))
      end
      if (weakOf(sp) & BOLT) == 0 then problem("$%03X %s: a machine Bolt does not key", sp, nm) end
    end
    local hands = 0
    for _, sp in ipairs(STATUES) do
      if (classOf(sp) & (W(0x50) | W(0x3F))) == 0 then problem("$%03X %s: a statue neither the cards nor the brush keys", sp,
        WANT[sp][1]) end
      hands = hands | classOf(sp)
    end
    if (hands & EDGE) == 0 or (hands & POINT) == 0 or (hands & BLOW) == 0 or nbits(hands) < 4 then
      problem("the three statues together key class mask $%02X, want a blade, a point and a blow, four classes or more", hands)
    end
    if shield[0x111] == nil or shield[0x111][1] ~= 0 then problem("$111 Guardian (the WoB's): not shieldless") end
    H.log("the lessons: the machines turn the blades and take the point, the blow and bolt; each statue takes the "
      .. "brush, the three every hand; the tower's Guardian has a gauge")
    H.assertEq(#problems, 0, "WoR Kefka's Tower break row mismatches")
    H.log("WoR Kefka's Tower break rows verified against the built ROM")
  end),
})
