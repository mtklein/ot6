-- @suite
-- battle_breakwor_sabin.lua -- the World of Ruin break rows from the
-- Solitary Island to Tzen's collapsing house, re-verified from the built
-- ROM (the battle_breakgate shape: pure ROM bytes, no savestate).
-- docs/design/route-wor-sabin.md section 8 is the design these rows come
-- from; WANT below is its table, and the only place the expectations live.
--
--   1. every designed species carries exactly its designed Ot6ShieldTbl
--      row (the first row for the species, the one Ot6SeedShields takes),
--      keeps its vanilla weak byte, and has no Ot6ElemAddTbl row;
--   2. every species the stretch can draw has an authored row, and every
--      formation it can draw holds a key for Celes alone with a sword and
--      her own Ice (the weakest hand section 8 designs for): a species
--      whose break class (authored, else the floor) includes slash, or
--      whose weakness (vanilla or added) includes ice.
--
-- All mismatches are logged before the verdict, so a red run names every
-- missing or wrong row at once.
local H = dofile("tools/tests/lib/ot6.lua")

local SLASH, PIERCE, BLUDG = 0x01, 0x02, 0x04
local FIRE, ICE, BOLT, HOLY, WATER = 0x01, 0x02, 0x04, 0x20, 0x80

-- species -> { name, shields, class mask, vanilla weak byte }
local WANT = {
  -- the Solitary Island (world groups 29, 30)
  [0x072] = { "Peepers",    1, SLASH,          ICE | WATER },
  [0x0B2] = { "EarthGuard", 1, SLASH,          WATER },
  [0x0D5] = { "Black Drgn", 4, SLASH,          FIRE | HOLY },
  -- the plains (world groups 31, 34 on the route; 33, 35, 36 beside it)
  [0x021] = { "Mesosaur",   3, SLASH | PIERCE, ICE },
  [0x031] = { "Gilomantis", 3, SLASH | BLUDG,  FIRE },
  [0x07C] = { "Chitonid",   3, BLUDG,          BOLT },
  [0x098] = { "Gigan Toad", 2, SLASH | PIERCE, ICE },
  [0x0CA] = { "Lunaris",    2, SLASH | PIERCE, 0 },
  [0x0E6] = { "Osprey",     2, SLASH | PIERCE, ICE },
  -- Tzen's collapsing house (map 311; its monster box is event group 150)
  [0x0E1] = { "Scorpion",   2, SLASH | PIERCE, 0 },
  [0x02C] = { "HermitCrab", 2, SLASH | BLUDG,  WATER },
  [0x0C0] = { "Pm Stalker", 2, SLASH,          FIRE | HOLY },
}

-- where the stretch draws from (section 4): world groups (40 is the other
-- Black Drgn desert of section 8.2), the house's map, its event group
local WORLD_GROUPS = { 29, 30, 31, 33, 34, 35, 36, 40 }
local FIELD_MAPS   = { 311 }
local EVENT_GROUPS = { 150 }

-- the weakest hand section 8 designs for: Celes alone, a sword, her Ice
local HAND_CLASSES, HAND_ELEMS = SLASH, ICE

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
    -- (H.sym takes string literals only: compose.py resolves them)
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

    -- 1. the designed rows
    local ids = {}
    for sp in pairs(WANT) do ids[#ids + 1] = sp end
    table.sort(ids)
    for _, sp in ipairs(ids) do
      local w = WANT[sp]
      local name, shields, mask, vweak = w[1], w[2], w[3], w[4]
      local got = shield[sp]
      if got == nil then
        problem("$%03X %s has no Ot6ShieldTbl row (want %d, class $%02X)",
          sp, name, shields, mask)
      else
        if got[1] ~= shields then
          problem("$%03X %s shields %d, want %d", sp, name, got[1], shields)
        end
        if got[2] ~= mask then
          problem("$%03X %s class mask $%02X, want $%02X", sp, name, got[2], mask)
        end
      end
      if weak(sp) ~= vweak then
        problem("$%03X %s weak byte $%02X, want vanilla $%02X",
          sp, name, weak(sp), vweak)
      end
      if elemAdd[sp] ~= nil then
        problem("$%03X %s has an Ot6ElemAddTbl row (elements $%02X); the "
          .. "design adds none", sp, name, elemAdd[sp][1])
      end
    end
    H.log(string.format("checked %d designed rows", #ids))

    -- 2. every formation the stretch can draw
    local rbg = H.sym("RandBattleGroup") & 0x3FFFFF
    local sbg = H.sym("SubBattleGroup") & 0x3FFFFF
    local ebg = H.sym("EventBattleGroup") & 0x3FFFFF
    local bm  = H.sym("BattleMonsters") & 0x3FFFFF
    local formations, order = {}, {}
    local function addWord(word, where)
      -- bit 15: the formation is base + rand(0..3) (field/battle.asm)
      local base = word & 0x1FF
      for k = 0, ((word & 0x8000) ~= 0) and 3 or 0 do
        local f = base + k
        if formations[f] == nil then
          formations[f] = where
          order[#order + 1] = f
        end
      end
    end
    local function addGroup(g, where)
      for slot = 0, 3 do addWord(rom16(rbg + g * 8 + slot * 2), where) end
    end
    for _, g in ipairs(WORLD_GROUPS) do addGroup(g, "world group " .. g) end
    for _, m in ipairs(FIELD_MAPS) do
      local g = H.readRomByte(sbg + m)
      addGroup(g, string.format("map %d (group %d)", m, g))
    end
    for _, g in ipairs(EVENT_GROUPS) do
      addWord(rom16(ebg + g * 4), "event group " .. g)
      addWord(rom16(ebg + g * 4 + 2), "event group " .. g)
    end

    for _, f in ipairs(order) do
      local rec = bm + f * 15
      local pres, hi = H.readRomByte(rec + 1), H.readRomByte(rec + 14)
      local keyed, members, named = false, {}, {}
      for s = 0, 5 do
        if (pres & (1 << s)) ~= 0 then
          local sp = H.readRomByte(rec + 2 + s) | (((hi >> s) & 1) << 8)
          members[#members + 1] = string.format("$%03X", sp)
          local row = shield[sp]
          if row == nil and not named[sp] then
            named[sp] = true
            problem("formation %d (%s): species $%03X has no authored row",
              f, formations[f], sp)
          end
          -- what the engine seeds: the authored class, else the floor class
          local cls = row and row[2] or H.readRomByte(floor + sp)
          local el = weak(sp) | (elemAdd[sp] and elemAdd[sp][1] or 0)
          if (cls & HAND_CLASSES) ~= 0 or (el & HAND_ELEMS) ~= 0 then
            keyed = true
          end
        end
      end
      if #members == 0 then
        problem("formation %d (%s) has no monsters", f, formations[f])
      elseif not keyed then
        problem("formation %d (%s: %s) has no key for Celes's sword or Ice",
          f, formations[f], table.concat(members, " "))
      end
    end
    H.log(string.format("checked %d formations", #order))

    H.assertEq(#problems, 0, "WoR island-to-Tzen break row mismatches")
    H.log("WoR island-to-Tzen break rows verified against the built ROM")
  end),
})
