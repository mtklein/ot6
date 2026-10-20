-- @suite
-- battle_breakwor_locke.lua -- the World of Ruin break rows for the Locke
-- arc (the Phoenix Cave and the Red Dragon; Doom Gaze, met in the sky on
-- the way), re-verified from the built ROM (battle_breakwor_thamasa's
-- shape: pure ROM bytes, no savestate).  docs/design/route-wor-locke.md
-- section 3 is the design; WANT below is its table, and the only place the
-- expectations live.
--
--   1. each species carries exactly its designed Ot6ShieldTbl row, keeps its
--      vanilla weak and absorb bytes, and has exactly its designed
--      Ot6ElemAddTbl row (holy on the Phase, none else);
--   2. every species the arc can draw -- the cave's two pools (field groups
--      174 on map 315 and 175 on map 313), the Red Dragon (event group 138)
--      and Doom Gaze (event group 93, the Falcon's deck) -- has an authored
--      row, and every gauged one a key for the hands that meet it: each of
--      the cave's two parties (gen_wor_phoenix's groups, as they stand in
--      wor-phoenix-v1) alone, party 2 at the Red Dragon, and the four who
--      fly from the tower (wor-thamasa-v1) at Doom Gaze;
--   3. the lessons: party 1 holds no ice, so the cave's ice-weak bodies give
--      it keys of its own (holy on the Phase, a class on the rest), and the
--      Red Dragon keeps its ice and water and drinks fire.
-- All mismatches are logged before the verdict.
local H = dofile("tools/tests/lib/ot6.lua")

local SLASH, PIERCE, BLUDG, SPECIAL = 0x01, 0x02, 0x04, 0x08
local FIRE, ICE, BOLT, POISON, WIND, HOLY, EARTH, WATER = 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80

-- species -> { name, shields, class mask, vanilla weak byte, vanilla absorb byte, elements added }
local WANT = {
  [0x0BC] = { "Phase", 2, SPECIAL, ICE, FIRE, HOLY },
  [0x0BF] = { "Parasoul", 2, SLASH | PIERCE, ICE, FIRE, 0 },
  [0x0F1] = { "Necromancr", 2, SLASH | SPECIAL, FIRE | HOLY, POISON, 0 },
  [0x0F7] = { "Trixter", 2, PIERCE | SPECIAL, HOLY, 0, 0 },
  [0x0EC] = { "Aquila", 3, SLASH | PIERCE, ICE, FIRE, 0 },
  [0x0E2] = { "Chaos Drgn", 4, PIERCE | BLUDG, ICE, FIRE, 0 },
  [0x0E9] = { "Sea Flower", 2, SLASH, ICE | BOLT, FIRE | WATER, 0 },
  [0x093] = { "Uroburos", 1, BLUDG, ICE, FIRE, 0 },
  [0x153] = { "Red Dragon", 6, PIERCE, ICE | WATER, FIRE, 0 },
  [0x11D] = { "Doom Gaze", 8, PIERCE | SPECIAL, FIRE | HOLY, ICE | POISON, 0 },
}

-- the hands (route-wor-locke.md 3; wor-phoenix-v1's kit,
-- build/attempts/wt/v032-locke-arc/data/wor-phoenix-v1_dump.txt): party 1
-- TERRA (Man Eater; Fire, Pearl, Merton), STRAGO (Pearl Rod; Aqua Rake,
-- Aero), SABIN (Dragon Claw; Blitzes: bludgeon, fire, holy, wind), CYAN
-- (Tempest); party 2 CELES (Falchion; Ice, Tritoch's ice, bolt and
-- poison), RELM (Gravity Rod), MOG (Partisan), UMARO (Bone Club; ice)
local TERRA  = { "TERRA", PIERCE, FIRE | HOLY }
local STRAGO = { "STRAGO", BLUDG, HOLY | WATER | WIND }
local SABIN  = { "SABIN", SLASH | BLUDG, FIRE | HOLY | WIND }
local CYAN   = { "CYAN", SLASH, WIND }
local CELES  = { "CELES", SLASH, ICE | BOLT | POISON }
local RELM   = { "RELM", BLUDG, EARTH }
local MOG    = { "MOG", PIERCE, 0 }
local UMARO  = { "UMARO", BLUDG, ICE }
local function union(what, list)
  local h = { cls = 0, el = 0, what = what }
  for _, m in ipairs(list) do
    h.cls = h.cls | m[2]
    h.el = h.el | m[3]
  end
  return h
end
local PARTY1 = union("party 1 (TERRA, STRAGO, SABIN, CYAN)", { TERRA, STRAGO, SABIN, CYAN })
local PARTY2 = union("party 2 (CELES, RELM, MOG, UMARO)", { CELES, RELM, MOG, UMARO })
local SKY = union("the four from the tower (TERRA, CELES, RELM, STRAGO)", { TERRA, CELES, RELM, STRAGO })

local GROUPS = {
  { "field", 174, PARTY1 }, { "field", 175, PARTY1 },
  { "field", 174, PARTY2 }, { "field", 175, PARTY2 }, { "event", 138, PARTY2 },
  { "event", 93, SKY },
}
-- the maps' pools (SubBattleGroup, a byte a map) are the ones the design read
local POOLS = { [315] = 174, [313] = 175 }

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
    if (PARTY1.el & ICE) ~= 0 then problem("the hands table gives party 1 ice; the design's premise is that it has none") end
    local iceWeak = 0
    for sp, w in pairs(WANT) do
      if (weak(sp) & ICE) ~= 0 and sp ~= 0x11D then
        iceWeak = iceWeak + 1
        if not keys(sp, PARTY1.cls, PARTY1.el & ~ICE) and sp ~= 0x153 then
          problem("$%03X %s: ice-weak, and party 1 (no ice) has no key", sp, w[1])
        end
      end
    end
    H.log(string.format("%d of the cave's bodies are weak to ice; party 1 keys each without it", iceWeak))
    if (weakOf(0x0BC) & HOLY) == 0 then problem("$0BC: holy is not the Phase's key") end
    if (weakOf(0x0BC) & ICE) == 0 then problem("$0BC: the Phase lost its vanilla ice") end
    if (absorb(0x153) & FIRE) == 0 then problem("$153: the Red Dragon no longer drinks fire") end
    H.assertEq(#problems, 0, "WoR Locke arc break row mismatches")
    H.log("WoR Locke arc (Phoenix Cave) break rows verified against the built ROM")
  end),
})
