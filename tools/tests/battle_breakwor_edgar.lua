-- @suite
-- battle_breakwor_edgar.lua -- the World of Ruin break rows from Tzen to
-- Edgar (north of Tzen to Nikeah, the South Figaro continent, the Figaro
-- cave and the castle's basements, the engine room's Tentacles), re-verified
-- from the built ROM (battle_breakwor_sabin's shape: pure ROM bytes, no
-- savestate).  docs/design/route-wor-edgar.md section 8 is the design these
-- rows come from; WANT below is its table, and the only place the
-- expectations live.
--
--   1. every designed species carries exactly its designed Ot6ShieldTbl
--      row (the first row for the species, the one Ot6SeedShields takes),
--      keeps its vanilla weak byte, and has no Ot6ElemAddTbl row;
--   2. every species the stretch can draw -- every formation of its world
--      groups, field maps and event group -- has an authored row, and a
--      key for the party that meets it there: a break class (authored,
--      else the floor) the party holds, or a weakness (vanilla or added)
--      one of its elements carries.  CELES + SABIN hold slash and bludg,
--      ice, bolt, fire and holy; at the Tentacles EDGAR adds pierce and
--      poison;
--   3. at the Tentacles the classes carry the fight: three of the four
--      absorb one of the party's fire, ice or bolt, so every Tentacle has
--      a class key for the three members together, and each member holds
--      a class key on at least three of the four (CELES's slash misses
--      `$13D`, the design's one).
--   4. special (¤) is a common key (guidelines, #347): the designed rows
--      that take it are the cave's reaper and demon; the count is logged.
--
-- All mismatches are logged before the verdict, so a red run names every
-- missing or wrong row at once.
local H = dofile("tools/tests/lib/ot6.lua")

local SLASH, PIERCE, BLUDG, SPECIAL = 0x01, 0x02, 0x04, 0x08
local FIRE, ICE, BOLT, POISON, HOLY, WATER = 0x01, 0x02, 0x04, 0x08, 0x20, 0x80

-- species -> { name, shields, class mask, vanilla weak byte }
local WANT = {
  -- north of Tzen to Nikeah (world groups 37-39)
  [0x035] = { "Bloompire",  1, SLASH,          FIRE },
  [0x058] = { "Buffalax",   3, BLUDG,          FIRE | WATER },
  [0x03C] = { "Lizard",     3, SLASH | PIERCE, ICE },
  [0x030] = { "Delta Bug",  2, BLUDG | PIERCE, FIRE },
  -- the South Figaro continent (world groups 41-44)
  [0x0C3] = { "Nohrabbit",  1, SLASH,          WATER },
  [0x0B9] = { "Latimeria",  3, SLASH | PIERCE, BOLT },
  [0x097] = { "Maliga",     2, SLASH | BLUDG,  ICE | BOLT | WATER },
  [0x05F] = { "Sand Horse", 2, SLASH | PIERCE, ICE | WATER },
  -- the Figaro cave and the castle's basements (groups 137-140)
  [0x049] = { "Humpty",     2, BLUDG,          FIRE | HOLY },
  [0x04B] = { "Cruller",    3, BLUDG,          FIRE | HOLY },
  [0x0A9] = { "NeckHunter", 3, SLASH | PIERCE | SPECIAL, POISON },  -- a reaper: ¤ (#347)
  [0x0D7] = { "Dante",      4, SLASH | BLUDG | SPECIAL,  POISON },  -- a demon: ¤ (#347)
  [0x08B] = { "Drop",       2, BLUDG | PIERCE, BOLT | WATER },
  -- the engine room's Tentacles (event group 84)
  [0x11B] = { "Tentacle",   5, SLASH | PIERCE, ICE | WATER },
  [0x13C] = { "Tentacle",   5, SLASH | BLUDG,  FIRE },
  [0x13D] = { "Tentacle",   5, BLUDG | PIERCE, 0 },
  [0x13E] = { "Tentacle",   5, SLASH | PIERCE, 0 },
}

-- the hands (route-wor-edgar.md 8.1)
local DUO = { cls = SLASH | BLUDG, el = ICE | BOLT | FIRE | HOLY,
              what = "CELES + SABIN (slash, bludg; ice, bolt, fire, holy)" }
local TRIO = { cls = SLASH | BLUDG | PIERCE, el = ICE | BOLT | FIRE | HOLY | POISON,
               what = "CELES + SABIN + EDGAR (+ pierce, poison)" }
-- where the stretch draws from (section 3), and who meets it there.  The
-- Black Drgn's desert (group 40) is on the walk to Nikeah; the cave's maps
-- are walked out again with EDGAR, but the duo's key is the stricter one.
local WORLD_GROUPS = { 37, 38, 39, 40, 41, 42, 43, 44 }
local FIELD_MAPS   = { 68, 90, 92, 53, 62, 63, 64 }
local EVENT_GROUPS = { 84 }
local TENTACLES    = { 0x11B, 0x13C, 0x13D, 0x13E }

H.run({ maxFrames = 600 }, {
  H.waitFrames(30),
  H.call(function()
    local problems = {}
    local function problem(fmt, ...)
      local msg = string.format(fmt, ...)
      problems[#problems + 1] = msg
      H.log("MISMATCH: " .. msg)
    end
    local function rom16(a)
      return H.readRomByte(a) | (H.readRomByte(a + 1) << 8)
    end
    -- the shipped tables; the first row per species is the one the engine
    -- takes (Ot6SeedShields, Ot6ElemAdd both stop at the first match)
    local function readTable(a)
      local rows = {}
      while true do
        local sp = rom16(a)
        if sp == 0xFFFF then break end
        if rows[sp] == nil then
          rows[sp] = { H.readRomByte(a + 2), H.readRomByte(a + 3) }
        end
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

    -- 1. the designed rows
    local ids = {}
    for sp in pairs(WANT) do ids[#ids + 1] = sp end
    table.sort(ids)
    for _, sp in ipairs(ids) do
      local w = WANT[sp]
      local name, shields, mask, vweak = w[1], w[2], w[3], w[4]
      local got = shield[sp]
      if got == nil then
        problem("$%03X %s has no Ot6ShieldTbl row (want %d, class $%02X)", sp, name, shields, mask)
      else
        if got[1] ~= shields then
          problem("$%03X %s shields %d, want %d", sp, name, got[1], shields)
        end
        if got[2] ~= mask then
          problem("$%03X %s class mask $%02X, want $%02X", sp, name, got[2], mask)
        end
      end
      if weak(sp) ~= vweak then
        problem("$%03X %s weak byte $%02X, want vanilla $%02X", sp, name, weak(sp), vweak)
      end
      if elemAdd[sp] ~= nil then
        problem("$%03X %s has an Ot6ElemAddTbl row (elements $%02X); the design adds none",
          sp, name, elemAdd[sp][1])
      end
    end
    H.log(string.format("checked %d designed rows", #ids))

    -- 2. every species of every formation the stretch can draw
    local rbg = H.sym("RandBattleGroup") & 0x3FFFFF
    local sbg = H.sym("SubBattleGroup") & 0x3FFFFF
    local ebg = H.sym("EventBattleGroup") & 0x3FFFFF
    local bm  = H.sym("BattleMonsters") & 0x3FFFFF
    local formations, order = {}, {}
    local function addWord(word, where, hand)
      -- bit 15: the formation is base + rand(0..3) (field/battle.asm)
      local base = word & 0x1FF
      for k = 0, ((word & 0x8000) ~= 0) and 3 or 0 do
        local f = base + k
        if formations[f] == nil then
          formations[f] = { where = where, hand = hand }
          order[#order + 1] = f
        end
      end
    end
    local function addGroup(g, where, hand)
      for slot = 0, 3 do addWord(rom16(rbg + g * 8 + slot * 2), where, hand) end
    end
    for _, g in ipairs(WORLD_GROUPS) do addGroup(g, "world group " .. g, DUO) end
    for _, m in ipairs(FIELD_MAPS) do
      local g = H.readRomByte(sbg + m)
      addGroup(g, string.format("map %d (group %d)", m, g), DUO)
    end
    for _, g in ipairs(EVENT_GROUPS) do
      addWord(rom16(ebg + g * 4), "event group " .. g, TRIO)
      addWord(rom16(ebg + g * 4 + 2), "event group " .. g, TRIO)
    end

    local species = 0
    local seen = {}
    for _, f in ipairs(order) do
      local rec = bm + f * 15
      local pres, hi = H.readRomByte(rec + 1), H.readRomByte(rec + 14)
      local where, hand = formations[f].where, formations[f].hand
      local members = 0
      for s = 0, 5 do
        if (pres & (1 << s)) ~= 0 then
          members = members + 1
          local sp = H.readRomByte(rec + 2 + s) | (((hi >> s) & 1) << 8)
          local key = f * 1024 + sp
          if not seen[key] then
            seen[key] = true
            species = species + 1
            if shield[sp] == nil then
              problem("formation %d (%s): species $%03X has no authored row", f, where, sp)
            end
            if (classOf(sp) & hand.cls) == 0 and (weakOf(sp) & hand.el) == 0 then
              problem("formation %d (%s): species $%03X (class $%02X, weak $%02X) has no key for %s",
                f, where, sp, classOf(sp), weakOf(sp), hand.what)
            end
          end
        end
      end
      if members == 0 then problem("formation %d (%s) has no monsters", f, where) end
    end
    H.log(string.format("checked %d formations, %d formation-species pairs", #order, species))

    -- 3. the Tentacles: each absorbs one of the party's spell elements, so
    -- the classes carry the fight
    local absorbing = 0
    for _, sp in ipairs(TENTACLES) do
      if (absorb(sp) & (FIRE | ICE | BOLT)) ~= 0 then absorbing = absorbing + 1 end
      if (classOf(sp) & TRIO.cls) == 0 then
        problem("Tentacle $%03X (class $%02X) has no class key for %s", sp, classOf(sp), TRIO.what)
      end
    end
    H.log(string.format("the Tentacles: %d of 4 absorb one of the party's fire, ice or bolt", absorbing))
    local members = { { "CELES", SLASH }, { "SABIN", SLASH | BLUDG }, { "EDGAR", SLASH | PIERCE } }
    for _, m in ipairs(members) do
      local n = 0
      for _, sp in ipairs(TENTACLES) do
        if (classOf(sp) & m[2]) ~= 0 then n = n + 1 end
      end
      H.log(string.format("the Tentacles: %s holds a class key on %d of 4", m[1], n))
      if n < 3 then problem("the Tentacles: %s holds a class key on only %d of 4 (want 3+)", m[1], n) end
    end

    local nspecial, nids = 0, 0
    for sp in pairs(WANT) do
      nids = nids + 1
      if shield[sp] and (shield[sp][2] & SPECIAL) ~= 0 then nspecial = nspecial + 1 end
    end
    H.log(string.format("special: %d of %d designed species take ¤ in this ROM", nspecial, nids))

    H.assertEq(#problems, 0, "WoR Tzen-to-Edgar break row mismatches")
    H.log("WoR Tzen-to-Edgar break rows verified against the built ROM")
  end),
})
