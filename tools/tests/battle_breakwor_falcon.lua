-- @suite
-- battle_breakwor_falcon.lua -- the World of Ruin break rows from Edgar to
-- the Falcon (the Kohlingen continent, Darill's Tomb, Dullahan, the tomb's
-- monster chest), re-verified from the built ROM (battle_breakwor_edgar's
-- shape: pure ROM bytes, no savestate).  docs/design/route-wor-falcon.md
-- section 8 is the design these rows come from; WANT below is its table,
-- and the only place the expectations live.
--
--   1. every designed species carries exactly its designed Ot6ShieldTbl
--      row (the first row for the species, the one Ot6SeedShields takes),
--      keeps its vanilla weak byte, and has no Ot6ElemAddTbl row;
--   2. every species the arc can draw -- every formation of its world
--      groups, field maps and event groups -- has an authored row, and
--      every gauged one a key for the party that meets it there: a break
--      class (authored, else the floor) the party holds, or a weakness
--      (vanilla or added) one of its elements carries.  On the Kohlingen
--      continent that is CELES + SABIN + EDGAR (the walk there is made
--      before SETZER joins); in the tomb, the four.  A row of 0 shields
--      (the Presenter) draws no gauge by design; its formation must hold
--      a gauged body the party keys;
--   3. the bodies the design hangs a lesson on: special is a common key
--      (guidelines, owner 2026-10-01), so SETZER's Cards key each of the
--      six special bodies (the Bogy, the Deep Eye, the Orog, the
--      Osteosaur, the PowerDemon, Dullahan); every member of the four
--      holds a key on the Bogy, and on Dullahan, who absorbs ice, with
--      either of SETZER's weapons; the Narshe Whelk's rows, which the
--      chest pair grows from, are unchanged.
--
-- All mismatches are logged before the verdict, so a red run names every
-- missing or wrong row at once.
local H = dofile("tools/tests/lib/ot6.lua")

local SLASH, PIERCE, BLUDG, SPECIAL = 0x01, 0x02, 0x04, 0x08
local FIRE, ICE, BOLT, POISON, WIND, HOLY = 0x01, 0x02, 0x04, 0x08, 0x10, 0x20

-- species -> { name, shields, class mask, vanilla weak byte }
local WANT = {
  -- the Kohlingen continent (world groups 45-47)
  [0x089] = { "Harpiai",    3, SLASH | PIERCE,   WIND },
  [0x0DB] = { "Muus",       2, SLASH | BLUDG,    0 },
  [0x0A7] = { "Deep Eye",   2, PIERCE | SPECIAL, FIRE },
  [0x0D3] = { "Bogy",       3, SLASH | SPECIAL,  0 },
  -- Darill's Tomb (groups 149-151)
  [0x005] = { "Orog",       3, SLASH | BLUDG | SPECIAL,  FIRE | HOLY },
  [0x010] = { "Osteosaur",  3, BLUDG | SPECIAL,          FIRE | HOLY },
  [0x06F] = { "PowerDemon", 3, SLASH | PIERCE | SPECIAL, FIRE | HOLY },
  [0x061] = { "Mad Oscar",  4, SLASH,            FIRE },
  [0x091] = { "Exoray",     2, SLASH | PIERCE,   FIRE | HOLY },
  -- the grave (event group 85)
  [0x11C] = { "Dullahan",  10, PIERCE | BLUDG | SPECIAL, FIRE },
  -- the monster chest beside the save point (event group 116)
  [0x101] = { "Presenter",  0, 0,                FIRE },
  [0x135] = { "Whelk Head", 6, PIERCE,           FIRE },
}

-- the hands (route-wor-falcon.md 8.1).  SABIN's wind is Air Blade (L30),
-- held at wor-edgar-v1; his holy is AuraBolt.
local CELES  = { "CELES", SLASH, FIRE | ICE | BOLT }
local SABIN  = { "SABIN", SLASH | BLUDG, FIRE | HOLY | WIND }
local EDGAR  = { "EDGAR", SLASH | PIERCE, BOLT | POISON }
local CARDS  = { "SETZER (Cards)", SPECIAL, 0 }
local DARTS  = { "SETZER (Darts)", PIERCE, 0 }
local function union(what, ...)
  local h = { cls = 0, el = 0, what = what }
  for _, m in ipairs({ ... }) do h.cls = h.cls | m[2]; h.el = h.el | m[3] end
  return h
end
local TRIO = union("CELES + SABIN + EDGAR (slash, pierce, bludg; fire, ice, bolt, poison, holy, wind)",
  CELES, SABIN, EDGAR)
local FOUR = union("the four (+ SETZER: special or pierce)", CELES, SABIN, EDGAR, CARDS, DARTS)

-- where the arc draws from (section 3), and who meets it there.  Group 44
-- is the castle's desert on both sides (rows from the Edgar arc); groups
-- 45-47 are walked first by the trio.
local WORLD_GROUPS = { 44, 45, 46, 47 }
local FIELD_MAPS   = { 298, 299, 300 }
local EVENT_GROUPS = { 85, 116 }

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
    local function keys(sp, cls, el) return (classOf(sp) & cls) ~= 0 or (weakOf(sp) & el) ~= 0 end

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

    -- 2. every species of every formation the arc can draw
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
    for _, g in ipairs(WORLD_GROUPS) do addGroup(g, "world group " .. g, TRIO) end
    for _, m in ipairs(FIELD_MAPS) do
      local g = H.readRomByte(sbg + m)
      addGroup(g, string.format("map %d (group %d)", m, g), FOUR)
    end
    for _, g in ipairs(EVENT_GROUPS) do
      addWord(rom16(ebg + g * 4), "event group " .. g, FOUR)
      addWord(rom16(ebg + g * 4 + 2), "event group " .. g, FOUR)
    end

    local pairs_ = 0
    local seen = {}
    for _, f in ipairs(order) do
      local rec = bm + f * 15
      local pres, hi = H.readRomByte(rec + 1), H.readRomByte(rec + 14)
      local where, hand = formations[f].where, formations[f].hand
      local members, gaugedKeyed = 0, 0
      for s = 0, 5 do
        if (pres & (1 << s)) ~= 0 then
          members = members + 1
          local sp = H.readRomByte(rec + 2 + s) | (((hi >> s) & 1) << 8)
          local gauged = shield[sp] == nil or shield[sp][1] > 0
          local keyed = keys(sp, hand.cls, hand.el)
          if gauged and keyed then gaugedKeyed = gaugedKeyed + 1 end
          local key = f * 1024 + sp
          if not seen[key] then
            seen[key] = true
            pairs_ = pairs_ + 1
            if shield[sp] == nil then
              problem("formation %d (%s): species $%03X has no authored row", f, where, sp)
            end
            if gauged and not keyed then
              problem("formation %d (%s): species $%03X (class $%02X, weak $%02X) has no key for %s",
                f, where, sp, classOf(sp), weakOf(sp), hand.what)
            end
          end
        end
      end
      if members == 0 then problem("formation %d (%s) has no monsters", f, where) end
      if members > 0 and gaugedKeyed == 0 then
        problem("formation %d (%s) holds no gauged body %s can key", f, where, hand.what)
      end
    end
    H.log(string.format("checked %d formations, %d formation-species pairs", #order, pairs_))

    -- 3. the bodies the design hangs a lesson on
    local special = { 0x0D3, 0x0A7, 0x005, 0x010, 0x06F, 0x11C }
    for _, sp in ipairs(special) do
      local ok = keys(sp, CARDS[2], CARDS[3])
      H.log(string.format("special: %s %s on $%03X %s", CARDS[1],
        ok and "holds a key" or "holds NO key", sp, WANT[sp][1]))
      if not ok then
        problem("special: %s holds no key on $%03X %s (class $%02X, weak $%02X)",
          CARDS[1], sp, WANT[sp][1], classOf(sp), weakOf(sp))
      end
    end
    local cardsKeyed = 0
    for _, sp in ipairs(ids) do
      if keys(sp, CARDS[2], CARDS[3]) then cardsKeyed = cardsKeyed + 1 end
    end
    H.log(string.format("special: %s holds a key on %d of %d designed species",
      CARDS[1], cardsKeyed, #ids))
    local four = { CELES, SABIN, EDGAR, CARDS }
    for _, m in ipairs(four) do
      local ok = keys(0x0D3, m[2], m[3])
      H.log(string.format("the Bogy: %s %s", m[1], ok and "holds a key" or "holds NO key"))
      if not ok then
        problem("the Bogy: %s holds no key (class $%02X, weak $%02X)", m[1], classOf(0x0D3), weakOf(0x0D3))
      end
    end
    local dullahan = { CELES, SABIN, EDGAR, DARTS, CARDS }
    for _, m in ipairs(dullahan) do
      local ok = keys(0x11C, m[2], m[3])
      H.log(string.format("Dullahan: %s %s", m[1], ok and "holds a key" or "holds NO key"))
      if not ok then problem("Dullahan: %s holds no key", m[1]) end
    end
    if (absorb(0x11C) & ICE) == 0 then
      problem("Dullahan absorb byte $%02X has lost vanilla ice", absorb(0x11C))
    end
    local narshe = { [0x100] = { "Whelk (Narshe shell)", 0, 0 },
                     [0x134] = { "Head (Narshe Whelk)", 4, PIERCE } }
    for sp, w in pairs(narshe) do
      local got = shield[sp]
      if got == nil or got[1] ~= w[2] or got[2] ~= w[3] then
        problem("$%03X %s row changed: got %s, want %d * $%02X", sp, w[1],
          got and string.format("%d * $%02X", got[1], got[2]) or "none", w[2], w[3])
      end
    end

    H.assertEq(#problems, 0, "WoR Edgar-to-Falcon break row mismatches")
    H.log("WoR Edgar-to-Falcon break rows verified against the built ROM")
  end),
})
