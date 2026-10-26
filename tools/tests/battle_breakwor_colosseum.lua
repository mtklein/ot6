-- @suite
-- battle_breakwor_colosseum.lua -- the World of Ruin break rows and data for the Colosseum & Shadow arc,
-- re-verified from the built ROM (battle_breakwor_dreams' shape: pure ROM bytes, no savestate).
-- docs/design/route-wor-colosseum.md sections 2-4 are the design; the tables below are its, and the only place
-- the expectations live.
--
--   1. the Colosseum's own bodies (met nowhere else: no random or event group deals them) carry exactly their
--      designed Ot6ShieldTbl rows and keep their vanilla weak and absorb bytes, with no Ot6ElemAddTbl row;
--   2. the route's wagers: each one's ColosseumProp record names the opponent and the prize the route plays
--      for, and each opponent has an authored row (Test Rider's is the Narshe arc's, the Opinicus's Ebot's
--      Rock's, checked there);
--   3. every species of every formation of the plain by Maranda's Falcon (world group 49, where SHADOW's first
--      fights are; the Cyan arc's rows, checked there) has an authored row and a key for the four the cabin
--      seats (SHADOW, CELES, CYAN, TERRA); and the lesson: among the four's blades, SHADOW's alone keys the
--      Crawler;
--   4. #383: the skeans' spells ($51-$53, ThrowToolsOffsetTbl) carry the pierce class in Ot6SkillClassTbl.
-- All mismatches are logged before the verdict.
local H = dofile("tools/tests/lib/ot6.lua")

local SLASH, PIERCE, BLUDG, SPECIAL = 0x01, 0x02, 0x04, 0x08
local FIRE, ICE, BOLT, POISON, WIND, HOLY, EARTH, WATER = 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80

-- species -> { name, shields, class mask, vanilla weak byte, vanilla absorb byte }
local WANT = {
  [0x037] = { "Siegfried (the Colosseum's)", 6, SLASH | PIERCE, 0xFF, 0 },
  [0x040] = { "Chupon (the Colosseum's)", 0, 0, ICE | WATER, FIRE },
  [0x07F] = { "SrBehemoth (the Colosseum's)", 6, PIERCE | BLUDG, FIRE | HOLY, POISON },
}
-- the route's wagers (gen_wor_colosseum's STRIKER and WAGERS): item -> { opponent species, prize }.  The
-- Striker's record names Chupon and the Striker back; with SHADOW waiting ($01EF) the fight is his
-- (CheckColosseumShadow, formation $23E)
local WAGERS = {
  { 0x29, "Striker", 0x040, 0x29 },
  { 0x05, "Assassin", 0x09C, 0x07 },
  { 0x2A, "Stunner", 0x09C, 0x31 },
  { 0x7B, "Regal Crown", 0x0C8, 0x81 },
  { 0x16, "Soul Sabre", 0x0C8, 0x15 },
}
-- the hands the cabin seats after the Colosseum (route-wor-colosseum.md section 3): SHADOW (the Striker:
-- pierce; his skeans fire, water, bolt), CELES (a blade; Ice), CYAN (katanas; Quadra Slice wind), TERRA (a
-- blade; Fire, Ice, Bolt)
local SHADOW = { "SHADOW", PIERCE, FIRE | WATER | BOLT }
local CELES = { "CELES", SLASH, ICE }
local CYAN = { "CYAN", SLASH, WIND }
local TERRA = { "TERRA", SLASH, FIRE | ICE | BOLT }

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

    -- 1. the Colosseum's own bodies
    local dealt = {}
    for _, kind in ipairs({ "random", "event" }) do
      for g = 0, 255 do
        for _, f in ipairs(groupForms(kind == "event" and "event" or "random", g)) do
          for _, sp in ipairs(formSpecies(f)) do dealt[sp] = true end
        end
      end
    end
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
      if dealt[sp] then problem("$%03X %s is dealt by a random or event group: not the Colosseum's own", sp, w[1]) end
    end
    H.log(string.format("checked %d designed rows (the Colosseum's own bodies)", #ids))

    -- 2. the route's wagers
    local col = H.sym("ColosseumProp") & 0x3FFFFF
    for _, w in ipairs(WAGERS) do
      local opp, prize = H.readRomByte(col + w[1] * 4), H.readRomByte(col + w[1] * 4 + 2)
      if opp ~= (w[3] & 0xFF) then problem("the %s's opponent byte $%02X, the route plays against $%03X", w[2], opp, w[3]) end
      if prize ~= w[4] then problem("the %s's prize $%02X, the route plays for $%02X", w[2], prize, w[4]) end
      if shield[w[3]] == nil then problem("the %s's opponent $%03X has no authored row", w[2], w[3]) end
    end
    H.log(string.format("checked %d wagers' records", #WAGERS))

    -- 3. the plain by Maranda's Falcon (world group 49)
    local four = { SHADOW, CELES, CYAN, TERRA }
    local cls, el = 0, 0
    for _, m in ipairs(four) do cls, el = cls | m[2], el | m[3] end
    local plain, seen, n = {}, {}, 0
    for _, f in ipairs(groupForms("random", 49)) do
      for _, sp in ipairs(formSpecies(f)) do
        n = n + 1
        if shield[sp] == nil then problem("formation %d (world group 49): species $%03X has no authored row", f, sp) end
        if not keys(sp, cls, el) then
          problem("formation %d (world group 49): species $%03X (class $%02X, weak $%02X) has no key for the four",
            f, sp, classOf(sp), weakOf(sp))
        end
        if not seen[sp] then seen[sp] = true; plain[#plain + 1] = sp end
      end
    end
    H.log(string.format("checked %d formation-species pairs of world group 49 (%d species)", n, #plain))
    local crawler = 0x05B
    if not seen[crawler] then problem("world group 49 no longer deals the Crawler") end
    if (classOf(crawler) & PIERCE) == 0 then problem("$05B Crawler: SHADOW's blade (pierce) holds no key") end
    if (classOf(crawler) & SLASH) ~= 0 then problem("$05B Crawler: the others' blades (slash) key it too") end
    H.log("the Crawler: SHADOW's blade keys it, and the blades of CELES, CYAN and TERRA do not")

    -- 4. the skeans pierce (#383)
    local tbl, got = H.sym("Ot6SkillClassTbl") & 0x3FFFFF, {}
    local a = tbl
    while H.readRomByte(a) ~= 0xFF do got[H.readRomByte(a)] = H.readRomByte(a + 1); a = a + 2 end
    for _, sp in ipairs({ { 0x51, "Fire Skean" }, { 0x52, "Water Edge" }, { 0x53, "Bolt Edge" } }) do
      if got[sp[1]] ~= PIERCE then
        problem("spell $%02X %s: Ot6SkillClassTbl class $%02X, want pierce ($02)", sp[1], sp[2], got[sp[1]] or 0)
      end
    end
    H.assertEq(#problems, 0, "WoR Colosseum & Shadow arc break row and data mismatches")
    H.log("WoR Colosseum & Shadow arc break rows and data verified against the built ROM")
  end),
})
