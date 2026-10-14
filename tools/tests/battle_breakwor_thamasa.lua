-- @suite
-- battle_breakwor_thamasa.lua -- the World of Ruin break rows for the Jidoor
-- and Thamasa arc (Owzer's house and Chadarnook, the plains, Thamasa's gate,
-- the Fanatics' Tower; the Holy Dragon and MagiMaster), re-verified from the
-- built ROM (battle_breakwor_narshe's shape: pure ROM bytes, no savestate).
-- docs/design/route-wor-thamasa.md section 4 is the design; WANT below is its
-- table, and the only place the expectations live.
--
--   1. each species carries exactly its designed Ot6ShieldTbl row, keeps its
--      vanilla weak and absorb bytes, and has exactly its designed
--      Ot6ElemAddTbl row (earth on the two reflecting casters, none else);
--   2. every species the arc can draw -- Owzer's basement (field group 157)
--      and its event groups 146, 147, 148, 151 and 86 (Chadarnook), the
--      plains by Jidoor's gate (world groups 48, 49), Thamasa's plain (55,
--      56), the tower's floors (field groups 152-156, 159) and its events
--      139 (the Holy Dragon) and 145 (MagiMaster) -- has an authored row,
--      and every gauged one a key for the hands that meet it: Owzer's three
--      (CYAN, TERRA, CELES), the four on the plains (TERRA, CELES, RELM,
--      STRAGO), and inside the tower the same four's spells only (no
--      class: the tower is magic-only);
--   3. the lessons: the Mantodea takes RELM's brush (special); L.20 and
--      L.70 Magic start with Reflect and their key is earth (Quake, which
--      Reflect does not bounce); the Holy Dragon has no weakness and no
--      Reflect (OT6's Break is its key); the goddess carries no gauge.
-- All mismatches are logged before the verdict.
local H = dofile("tools/tests/lib/ot6.lua")

local SLASH, PIERCE, BLUDG, SPECIAL = 0x01, 0x02, 0x04, 0x08
local FIRE, ICE, BOLT, POISON, WIND, HOLY, EARTH, WATER = 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80

-- species -> { name, shields, class mask, vanilla weak byte, vanilla absorb byte, elements added }
local WANT = {
  [0x0CC] = { "Vindr", 1, SLASH | PIERCE, FIRE, 0, 0 },
  [0x0AD] = { "SoulDancer", 2, SLASH | SPECIAL, POISON, 0, 0 },
  [0x092] = { "Crusher", 3, PIERCE | BLUDG, FIRE, 0, 0 },
  [0x077] = { "Wild Cat", 1, SLASH | PIERCE, FIRE | WATER, 0, 0 },
  [0x009] = { "Dahling", 2, SLASH | SPECIAL, POISON, 0, 0 },
  [0x033] = { "Nightshade", 2, SLASH, FIRE, WATER, 0 },
  [0x050] = { "Still Life", 4, SLASH | SPECIAL, FIRE, 0, 0 },
  [0x11E] = { "Chadarnook (goddess)", 0, 0, FIRE, HOLY | WATER, 0 },
  [0x148] = { "Chadarnook (demon)", 6, SLASH | PIERCE, FIRE | HOLY, BOLT, 0 },
  [0x0D2] = { "Mantodea", 3, SLASH | BLUDG | SPECIAL, FIRE, 0, 0 },
  [0x02B] = { "Harpy", 2, PIERCE | SPECIAL, 0, 0, 0 },
  [0x08A] = { "GloomShell", 3, PIERCE | BLUDG, ICE, 0, 0 },
  [0x0D4] = { "Prussian", 3, SLASH | BLUDG, 0, 0, 0 },
  [0x132] = { "L.10 Magic", 1, SPECIAL, FIRE | HOLY, POISON, 0 },
  [0x130] = { "L.20 Magic", 2, SPECIAL, 0, POISON, EARTH },
  [0x125] = { "L.30 Magic", 2, SPECIAL, POISON, HOLY, 0 },
  [0x12B] = { "L.40 Magic", 2, SPECIAL, BOLT, POISON, 0 },
  [0x133] = { "L.50 Magic", 2, SPECIAL, FIRE | HOLY, POISON, 0 },
  [0x139] = { "L.60 Magic", 3, SPECIAL, FIRE, ICE, 0 },
  [0x143] = { "L.70 Magic", 3, SPECIAL, ICE | WATER, FIRE, EARTH },
  [0x163] = { "L.80 Magic", 3, SPECIAL, POISON, 0, 0 },
  [0x164] = { "L.90 Magic", 0, 0, 0, WIND, 0 },
  [0x055] = { "Magic Urn", 0, 0, 0, 0xFF, 0 },
  [0x024] = { "White Drgn", 6, SPECIAL, 0, HOLY, 0 },
  [0x166] = { "MagiMaster", 8, SPECIAL, nil, nil, 0 },   -- WallChange rewrites his bytes in battle
}

-- the hands (route-wor-thamasa.md 4, 5.5, 6): Owzer's three (wor-narshe-v1's
-- kit: TERRA's natural Fire and Pearl, CELES's Ice and Tritoch's Ice, Bolt
-- and Poison, CYAN's Ifrit), the four on the plains with RELM's brush and
-- STRAGO's rod, and the same four's spells in the tower (TERRA's Quake too)
local TERRA  = { "TERRA", SLASH, FIRE | HOLY | EARTH }
local CELES  = { "CELES", SLASH, ICE | BOLT | POISON }
local CYAN   = { "CYAN", SLASH, FIRE }
local RELM   = { "RELM", SPECIAL, 0 }
local STRAGO = { "STRAGO", BLUDG, WIND | WATER }
local function union(what, list, magicOnly)
  local h = { cls = 0, el = 0, what = what }
  for _, m in ipairs(list) do
    if not magicOnly then h.cls = h.cls | m[2] end
    h.el = h.el | m[3]
  end
  return h
end
local OWZER = union("Owzer's three (CYAN, TERRA, CELES)", { CYAN, TERRA, CELES })
local PLAINS = union("the four on the plains (TERRA, CELES, RELM, STRAGO)", { TERRA, CELES, RELM, STRAGO })
local TOWER = union("the four's spells in the tower", { TERRA, CELES, RELM, STRAGO }, true)

local GROUPS = {
  { "field", 157, OWZER }, { "event", 146, OWZER }, { "event", 147, OWZER }, { "event", 148, OWZER },
  { "event", 151, OWZER }, { "event", 86, OWZER },
  { "world", 48, PLAINS }, { "world", 49, PLAINS }, { "world", 55, PLAINS }, { "world", 56, PLAINS },
  { "field", 152, TOWER }, { "field", 153, TOWER }, { "field", 154, TOWER }, { "field", 155, TOWER },
  { "field", 156, TOWER }, { "field", 159, TOWER }, { "event", 139, TOWER }, { "event", 145, TOWER },
}
-- keys the design gives by OT6's Break alone (no element the party casts):
-- the Holy Dragon, and MagiMaster, whose weakness is drawn in battle
local BREAK_ONLY = { [0x024] = true, [0x166] = true }

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
      if w[4] ~= nil and weak(sp) ~= w[4] then
        problem("$%03X %s weak byte $%02X, want vanilla $%02X", sp, w[1], weak(sp), w[4])
      end
      if w[5] ~= nil and absorb(sp) ~= w[5] then
        problem("$%03X %s absorb byte $%02X, want vanilla $%02X", sp, w[1], absorb(sp), w[5])
      end
      local add = elemAdd[sp] and elemAdd[sp][1] or 0
      if add ~= w[6] then problem("$%03X %s adds elements $%02X, want $%02X", sp, w[1], add, w[6]) end
    end
    H.log(string.format("checked %d designed rows", #ids))

    -- 2. every species of every formation the arc can draw
    local rbg = H.sym("RandBattleGroup") & 0x3FFFFF
    local ebg = H.sym("EventBattleGroup") & 0x3FFFFF
    local bm  = H.sym("BattleMonsters") & 0x3FFFFF
    local sbg = H.sym("SubBattleGroup") & 0x3FFFFF
    local formations, order = {}, {}
    local function addWord(word, where, hand)
      local base = word & 0x1FF
      for k = 0, ((word & 0x8000) ~= 0) and 3 or 0 do
        local f = base + k
        local key = f .. "|" .. hand.what
        if formations[key] == nil then
          formations[key] = { f = f, where = where, hand = hand }
          order[#order + 1] = key
        end
      end
    end
    for _, g in ipairs(GROUPS) do
      local kind, n, hand = g[1], g[2], g[3]
      if kind == "event" then
        addWord(rom16(ebg + n * 4), "event group " .. n, hand)
        addWord(rom16(ebg + n * 4 + 2), "event group " .. n, hand)
      else
        for slot = 0, 3 do addWord(rom16(rbg + n * 8 + slot * 2), kind .. " group " .. n, hand) end
      end
    end
    table.sort(order)
    local triples, seen, nform = 0, {}, {}
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
          if not seen[k2] then
            seen[k2] = true
            triples = triples + 1
            if shield[sp] == nil then problem("formation %d (%s): species $%03X has no authored row", f, where, sp) end
            if gauged(sp) and not keys(sp, hand.cls, hand.el) and not BREAK_ONLY[sp] then
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
    -- the maps' pools (SubBattleGroup, a byte a map) are the ones the design read
    for m, g in pairs({ [207] = 157, [363] = 152, [359] = 153, [360] = 154, [361] = 155, [364] = 155,
      [365] = 156, [366] = 156, [367] = 156, [368] = 156, [369] = 156, [370] = 159 }) do
      local got = H.readRomByte(sbg + m)
      if got ~= g then problem("map %d's pool is group %d, the design read %d", m, got, g) end
    end

    -- 3. the lessons
    if (classOf(0x0D2) & SPECIAL) == 0 then problem("$0D2: RELM's brush (special) does not key the Mantodea") end
    for _, sp in ipairs({ 0x130, 0x143 }) do
      local mstat = H.readRomByte(prop + sp * 32 + 29)   -- MonsterProp +29: status 3 at start (bit 7 Reflect)
      if (mstat & 0x80) == 0 then problem("$%03X no longer starts with Reflect (MonsterProp+29 $%02X)", sp, mstat) end
      if (weakOf(sp) & EARTH) == 0 then problem("$%03X: earth (Quake) is not its key", sp) end
    end
    if weak(0x024) ~= 0 then problem("$024: the Holy Dragon has a weakness ($%02X); Break was to be its key", weak(0x024)) end
    if shield[0x11E] == nil or shield[0x11E][1] ~= 0 then problem("$11E: the goddess carries a gauge") end
    H.assertEq(#problems, 0, "WoR Jidoor and Thamasa break row mismatches")
    H.log("WoR Jidoor and Thamasa break rows verified against the built ROM")
  end),
})
