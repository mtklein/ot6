-- @suite
-- battle_breakwor_sidetrips.lua -- the World of Ruin break rows for the side trips by the Falcon: the Cactrot
-- desert beside Maranda (world group 111) and the dinosaur forest north of Gau's father's house (world group 54),
-- re-verified from the built ROM (battle_breakwor_colosseum's shape: pure ROM bytes, no savestate).
-- docs/design/route-wor-side-trips.md section 2 is the design; the tables below are its, and the only place the
-- expectations live.
--
--   1. Hoover, Cactrot, Tyranosaur and Brachosaur carry exactly their designed Ot6ShieldTbl rows, keep their
--      vanilla weak and absorb bytes, and have no Ot6ElemAddTbl row;
--   2. every species of every formation of world groups 111 and 54 has an authored row and a key for the four
--      the cabin seats (SHADOW, CELES, CYAN, TERRA);
--   3. the lessons: the desert's Hoover takes the blades (the cabin's swords and katanas); the forest's hide turns
--      them (neither dinosaur takes a sword or a katana) and SHADOW's point (his Striker) and the mages' ice key
--      both; the Cactrot's one shield, so the hit that breaks it is the hit that kills it.
-- All mismatches are logged before the verdict.
local H = dofile("tools/tests/lib/ot6.lua")

local SWORD, DAGGER, BLUNT, RANGED, KATANA, SPEAR = 0x01, 0x02, 0x04, 0x08, 0x10, 0x20   -- ot6_class.asm (#566)
-- a hand is W(item): the class the built ROM gives the weapon (Ot6WeapClassTbl); SK(ability) a skill's own
-- (Ot6SkillClassTbl).  Read from the ROM, so a hand follows the classes the build has.
local W, SK = H.weaponClass, H.skillClass
local FIRE, ICE, BOLT, POISON, WIND, HOLY, EARTH, WATER = 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80

-- species -> { name, shields, class mask, vanilla weak byte, vanilla absorb byte }
local WANT = {
  [0x03E] = { "Hoover", 2, KATANA | RANGED, ICE | WATER, 0 },
  [0x04C] = { "Cactrot", 1, RANGED, ICE | WATER, 0 },
  [0x027] = { "Tyranosaur", 3, DAGGER | RANGED, ICE, 0 },
  [0x026] = { "Brachosaur", 6, DAGGER | BLUNT, ICE, 0 },
}
local HOOVER, CACTROT, TYRANOSAUR, BRACHOSAUR = 0x03E, 0x04C, 0x027, 0x026
-- the world groups (RandBattleGroup index = WorldBattleGroup byte) and the species each must deal
local GROUPS = { { 111, "the Cactrot desert", { HOOVER, CACTROT } },
  { 54, "the dinosaur forest", { TYRANOSAUR, BRACHOSAUR } } }
-- the hands the cabin seats at wor-colosseum-v1 (route-wor-colosseum.md section 3): SHADOW (the Striker $29, and
-- what he throws: the Shuriken $41 and the skeans $51-$53, fire, water, bolt), CELES (a blade, the Falchion $15;
-- Ice), CYAN (katanas, the Strato $31; Quadra Slice wind), TERRA (a blade, the Falchion; Fire, Ice, Bolt)
local SHADOW = { "SHADOW", W(0x29) | W(0x41) | SK(0x51), FIRE | WATER | BOLT }
local CELES = { "CELES", W(0x15), ICE }
local CYAN = { "CYAN", W(0x31), WIND }
local TERRA = { "TERRA", W(0x15), FIRE | ICE | BOLT }

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
    local rbg = H.sym("RandBattleGroup") & 0x3FFFFF
    local ebg = H.sym("EventBattleGroup") & 0x3FFFFF
    local bm  = H.sym("BattleMonsters") & 0x3FFFFF
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


    -- 1. the four rows
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
    H.log(string.format("checked %d designed rows (the desert's and the forest's bodies)", #ids))

    -- 2. the two world groups against the four
    local four = { SHADOW, CELES, CYAN, TERRA }
    local cls, el = 0, 0
    for _, m in ipairs(four) do cls, el = cls | m[2], el | m[3] end
    for _, g in ipairs(GROUPS) do
      local seen, n = {}, 0
      for _, f in ipairs(groupForms("random", g[1])) do
        for _, sp in ipairs(formSpecies(f)) do
          n = n + 1
          seen[sp] = true
          if shield[sp] == nil then
            problem("formation %d (%s, world group %d): species $%03X has no authored row", f, g[2], g[1], sp)
          end
          if not keys(sp, cls, el) then
            problem("formation %d (%s): species $%03X (class $%02X, weak $%02X) has no key for the four", f, g[2],
              sp, classOf(sp), weakOf(sp))
          end
        end
      end
      for _, sp in ipairs(g[3]) do
        if not seen[sp] then problem("world group %d (%s) no longer deals species $%03X", g[1], g[2], sp) end
      end
      H.log(string.format("checked %d formation-species pairs of world group %d (%s)", n, g[1], g[2]))
    end

    -- 3. the lessons
    if (classOf(HOOVER) & (W(0x15) | W(0x31))) == 0 then problem("$03E Hoover: the blades (the swords, the katanas) hold no key") end
    if (weakOf(HOOVER) & WATER) == 0 then problem("$03E Hoover: SHADOW's Water Edge holds no key") end
    for _, sp in ipairs({ TYRANOSAUR, BRACHOSAUR }) do
      local nm = WANT[sp][1]
      if (classOf(sp) & (SWORD | KATANA)) ~= 0 then problem("$%03X %s: the blades (a sword, a katana) key it", sp, nm) end
      if (classOf(sp) & W(0x29)) == 0 then problem("$%03X %s: SHADOW's point (the Striker) holds no key", sp, nm) end
      if (weakOf(sp) & ICE) == 0 then problem("$%03X %s: the mages' Ice holds no key", sp, nm) end
    end
    if shield[CACTROT] == nil or shield[CACTROT][1] ~= 1 then
      problem("$04C Cactrot: not one shield, so the breaking hit is not the kill")
    end
    H.log("the lessons: the desert takes the blades; the forest's hide turns them and takes the point and Ice; "
      .. "the Cactrot's one shield")
    H.assertEq(#problems, 0, "WoR side trips break row mismatches")
    H.log("WoR side trips break rows verified against the built ROM")
  end),
})
