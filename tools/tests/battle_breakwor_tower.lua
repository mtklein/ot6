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
--   3. the lessons: the factory's machines turn the blades (no slash) and take the point and the blow (pierce and
--      bludgeon) and bolt; the three statues each take the brush and the cards (special), and between them every
--      other hand (slash, pierce, bludgeon); the Guardian the tower fights ($112) has a gauge, and the World of
--      Balance's ($111) still has none.
-- All mismatches are logged before the verdict.
local H = dofile("tools/tests/lib/ot6.lua")

local SLASH, PIERCE, BLUDG, SPECIAL = 0x01, 0x02, 0x04, 0x08
local FIRE, ICE, BOLT, POISON, WIND, HOLY, EARTH, WATER = 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80
local PB = PIERCE | BLUDG

-- species -> { name, shields, class mask, vanilla weak byte, vanilla absorb byte }
local WANT = {
  [0x084] = { "Brontaur", 3, PB, ICE, 0 },
  [0x0B7] = { "Evil Oscar", 3, SLASH | SPECIAL, FIRE, 0xFE },
  [0x080] = { "Vectaur", 2, SLASH | PIERCE, ICE | WATER, 0 },
  [0x0E0] = { "GtBehemoth", 3, PB, 0, 0 },
  [0x00D] = { "Dark Force", 3, BLUDG | SPECIAL, HOLY, 0 },
  [0x0BD] = { "Outsider", 3, SLASH | PIERCE, HOLY, POISON },
  [0x06A] = { "Madam", 3, SLASH | SPECIAL, POISON, 0 },
  [0x007] = { "Retainer", 3, SLASH | BLUDG, POISON, 0 },
  [0x0C1] = { "Hemophyte", 2, SLASH | SPECIAL, 0, 0 },
  [0x0FB] = { "Veteran", 3, SLASH | PIERCE, 0, 0 },
  [0x0F9] = { "Didalos", 3, BLUDG | SPECIAL, FIRE | HOLY, POISON },
  [0x016] = { "Steroidite", 4, PB, HOLY, 0 },
  [0x056] = { "Mover", 1, SLASH | BLUDG, 0, POISON },
  [0x025] = { "Doom Drgn", 4, PIERCE | SPECIAL, 0, 0 },
  [0x0E4] = { "Vectagoyle", 3, BLUDG | SPECIAL, 0, 0 },
  [0x09B] = { "Land Worm", 3, SLASH | PIERCE, ICE, EARTH },
  [0x0FD] = { "IronHitman", 2, PB, BOLT | WATER, 0 },
  [0x0D9] = { "Dueller", 3, PB, BOLT | WATER, 0 },
  [0x0EA] = { "Fortis", 4, PB, BOLT | WATER, 0 },
  [0x0ED] = { "Junk", 2, PB, BOLT | WATER, 0 },
  [0x0F6] = { "Innoc", 3, PB, BOLT | WATER, 0 },
  [0x105] = { "Prometheus", 4, PB, BOLT | WATER, 0 },
  [0x0FC] = { "Sky Base", 2, PB, BOLT | WATER, 0 },
  [0x0A1] = { "Scullion", 4, PB, BOLT | WATER, 0 },
  [0x10C] = { "Inferno", 6, PB, BOLT, FIRE },
  [0x142] = { "Striker", 3, SLASH | PIERCE, FIRE, ICE },
  [0x141] = { "Rough", 3, SLASH | BLUDG, ICE, BOLT },
  [0x112] = { "Guardian", 10, PB, BOLT | WATER, 0 },
  [0x127] = { "Doom", 10, SLASH | SPECIAL, HOLY, ICE | POISON },
  [0x128] = { "Goddess", 8, PIERCE | SPECIAL, 0, BOLT | HOLY },
  [0x129] = { "Poltrgeist", 8, BLUDG | SPECIAL, POISON, FIRE | WIND },
  [0x17D] = { "Atma", 10, SLASH | PIERCE, 0, POISON | WIND | HOLY | EARTH | WATER },
  [0x150] = { "Gold Drgn", 6, SLASH | PIERCE, WATER, BOLT },
  [0x151] = { "Skull Drgn", 6, BLUDG | SPECIAL, FIRE | HOLY, POISON },
}
local MACHINES = { 0x0FD, 0x0D9, 0x0EA, 0x0ED, 0x0F6, 0x105, 0x0FC, 0x0A1, 0x10C, 0x112 }
local STATUES = { 0x127, 0x128, 0x129 }
local EVENTS = { 98, 99, 100, 112, 114, 135, 136, 140 }
-- the three parties the route seats (route-wor-kefka-tower.md section 4) and the lanes they walk (section 2): the
-- pool groups and event battles each meets, the class keys its weapons hold and the elements its spells, skeans
-- and lores reach at wor-desert-v1.  A species keys a party when either meets it.
--   party 1: TERRA (a blade; Fire, Ice, Bolt), RELM (a rod), EDGAR (a knife), SETZER (cards): the north-west,
--            303, 304, 292, the machines' hall 352, 295; Guardian and the Poltergeist after the chamber
--   party 2: CELES (a blade; Ice), STRAGO (a rod; Aqua Rake), LOCKE (the Wing Edge), MOG (a spear): 338, 331
--            (Atma), 329, 409, 292, 294, 335 (the Gold Dragon), 354; the Goddess
--   party 3: CYAN (katanas), SHADOW (the Striker; his skeans fire, water, bolt), SABIN (claws; fire, holy), GOGO (a
--            knife): 339, the factory 410 (Inferno), 296, 293, 354 (the Skull Dragon); Doom
local LANES = TOWER_LANES or {
  { "party 1", SLASH | BLUDG | PIERCE | SPECIAL, FIRE | ICE | BOLT, { 208, 209, 210, 211, 212, 213, 220, 221 },
    { 140, 100 } },
  { "party 2", SLASH | BLUDG | PIERCE, ICE | WATER, { 208, 211, 214, 215, 216, 217, 218, 226, 227, 220, 221 },
    { 112, 135, 99 } },
  { "party 3", SLASH | PIERCE, FIRE | BOLT | WATER | HOLY, { 208, 222, 223, 224, 225, 226, 220, 221 },
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
      if (classOf(sp) & SLASH) ~= 0 then problem("$%03X %s: a machine the blades (slash) key", sp, nm) end
      if (classOf(sp) & PB) ~= PB then problem("$%03X %s: a machine not keyed by the point and the blow", sp, nm) end
      if (weakOf(sp) & BOLT) == 0 then problem("$%03X %s: a machine Bolt does not key", sp, nm) end
    end
    local hands = 0
    for _, sp in ipairs(STATUES) do
      if (classOf(sp) & SPECIAL) == 0 then problem("$%03X %s: a statue the brush and cards (special) do not key", sp,
        WANT[sp][1]) end
      hands = hands | classOf(sp)
    end
    if (hands & (SLASH | PIERCE | BLUDG)) ~= (SLASH | PIERCE | BLUDG) then
      problem("the three statues together key class mask $%02X, want every hand", hands)
    end
    if shield[0x111] == nil or shield[0x111][1] ~= 0 then problem("$111 Guardian (the WoB's): not shieldless") end
    H.log("the lessons: the machines turn the blades and take the point, the blow and bolt; each statue takes the "
      .. "brush, the three every hand; the tower's Guardian has a gauge")
    H.assertEq(#problems, 0, "WoR Kefka's Tower break row mismatches")
    H.log("WoR Kefka's Tower break rows verified against the built ROM")
  end),
})
