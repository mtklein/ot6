-- @suite
-- battle_breakwor_gau.lua -- the World of Ruin break rows for the Gau arc
-- (the Veldt cave: its pool, Allo Ver's monster chest and the SrBehemoth),
-- re-verified from the built ROM (battle_breakwor_locke's shape: pure ROM
-- bytes, no savestate).  docs/design/route-wor-gau.md section 3 is the
-- design; WANT below is its table, and the only place the expectations
-- live.
--
--   1. each species carries exactly its designed Ot6ShieldTbl row and keeps
--      its vanilla weak and absorb bytes, with no Ot6ElemAddTbl row;
--   2. every species the cave can deal -- its pool (field group 132 on map
--      353), the monster chest at (6,8) (event group 153) and the dog's
--      master (event group 82) -- has an authored row, and every gauged one
--      a key for the four who walk it (TERRA, CELES, RELM and GAU, as
--      wor-veldt-cave-v1 seats them);
--   3. the lesson: GAU alone holds a key to every body here (his fists and
--      his beasts' bludgeon, Were-Rat's poison), and the cave drinks
--      CELES's ice (Toe Cutter, the SrBehemoth).
-- All mismatches are logged before the verdict.
local H = dofile("tools/tests/lib/ot6.lua")

local SLASH, PIERCE, BLUDG, SPECIAL = 0x01, 0x02, 0x04, 0x08
local FIRE, ICE, BOLT, POISON, WIND, HOLY, EARTH, WATER = 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80

-- species -> { name, shields, class mask, vanilla weak byte, vanilla absorb byte }
local WANT = {
  [0x08F] = { "Toe Cutter", 3, PIERCE | BLUDG, FIRE | WIND, ICE },
  [0x07E] = { "Rhyos", 4, BLUDG, 0, 0 },
  [0x0BB] = { "Allo Ver", 3, SLASH | BLUDG, FIRE | HOLY, POISON },
  [0x119] = { "SrBehemoth", 6, PIERCE | BLUDG, FIRE | POISON, ICE },
}

-- the hands (wor-veldt-cave-v1's kit: build/attempts/wt/v033-wor-gau/data/):
-- TERRA (a dagger; Fire, Pearl), CELES (two blades; Ice, bolt and poison),
-- RELM (a rod; earth), GAU (no weapon: his fists; his beasts: Were-Rat's
-- Poison, Rhinotaur's Mega Volt, the physical specials)
local TERRA = { "TERRA", PIERCE, FIRE | HOLY }
local CELES = { "CELES", SLASH, ICE | BOLT | POISON }
local RELM = { "RELM", BLUDG, EARTH }
local GAU = { "GAU", BLUDG, POISON | BOLT }
local function union(what, list)
  local h = { cls = 0, el = 0, what = what }
  for _, m in ipairs(list) do
    h.cls = h.cls | m[2]
    h.el = h.el | m[3]
  end
  return h
end
local FOUR = union("the four (TERRA, CELES, RELM, GAU)", { TERRA, CELES, RELM, GAU })
local GAU_ALONE = union("GAU alone", { GAU })

local GROUPS = { { "field", 132, FOUR }, { "event", 153, FOUR }, { "event", 82, FOUR } }
local POOLS = { [353] = 132 }

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

    -- 2. every species of every formation the cave can deal.  A formation
    -- index is ten bits: the monster chest's word is $0203, formation 515
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
    local gauKeys = 0
    for _, sp in ipairs(ids) do
      if keys(sp, GAU_ALONE.cls, GAU_ALONE.el) then
        gauKeys = gauKeys + 1
      else
        problem("$%03X %s: GAU alone holds no key", sp, WANT[sp][1])
      end
    end
    H.log(string.format("GAU alone keys %d of the cave's %d bodies", gauKeys, #ids))
    for _, sp in ipairs({ 0x08F, 0x119 }) do
      if (absorb(sp) & ICE) == 0 then problem("$%03X %s no longer drinks CELES's ice", sp, WANT[sp][1]) end
    end
    if (weakOf(0x119) & POISON) == 0 then problem("$119: the SrBehemoth lost its vanilla poison (Were-Rat's key)") end
    H.assertEq(#problems, 0, "WoR Gau arc break row mismatches")
    H.log("WoR Gau arc (the Veldt cave) break rows verified against the built ROM")
  end),
})
