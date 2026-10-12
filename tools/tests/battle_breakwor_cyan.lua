-- @suite
-- battle_breakwor_cyan.lua -- the World of Ruin break rows for CYAN's arc
-- (the plains round Zozo, Jidoor and Maranda, Mt. Zozo, the Storm Dragon),
-- re-verified from the built ROM (battle_breakwor_terra's shape: pure ROM
-- bytes, no savestate).  docs/design/route-wor-cyan.md section 6 is the
-- design; WANT below is its table, and the only place the expectations live.
--
--   1. each species carries exactly its designed Ot6ShieldTbl row, keeps its
--      vanilla weak and absorb bytes, and has no Ot6ElemAddTbl row;
--   2. every species the arc can draw -- the world groups at the Falcon's
--      landings (48, 49, 50), Mt. Zozo's field groups (160, 161, 162) and
--      the Storm Dragon's event group 133 -- has an authored row, and every
--      gauged one a key for the hands that meet it;
--   3. the lessons: CYAN's katana (slash) keys the Storm Dragon, and each of
--      the four who fight it holds a key; it absorbs wind, so CYAN's
--      Tempest heals it; a Luridan herd is keyed by CYAN's Stunner (slash)
--      and by the Tempest (its vanilla wind weakness); the Scrapper absorbs
--      poison beside the Punishers (the Bio Blaster heals it); the Mantodea
--      takes a blade.
-- All mismatches are logged before the verdict.
local H = dofile("tools/tests/lib/ot6.lua")

local SLASH, PIERCE, BLUDG, SPECIAL = 0x01, 0x02, 0x04, 0x08
local FIRE, ICE, BOLT, POISON, WIND, HOLY, EARTH, WATER = 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80

-- species -> { name, shields, class mask, vanilla weak byte, vanilla absorb byte }
local WANT = {
  [0x05B] = { "Crawler", 3, PIERCE | BLUDG, ICE, 0 },
  [0x099] = { "Geckorex", 3, SLASH | PIERCE, ICE, 0 },
  [0x03B] = { "Reach Frog", 2, BLUDG, ICE, 0 },
  [0x0D2] = { "Mantodea", 3, SLASH | BLUDG, FIRE, 0 },
  [0x087] = { "Sprinter", 3, PIERCE | SLASH, BOLT, 0 },
  [0x0B0] = { "Spek Tor", 1, SLASH | PIERCE | BLUDG, WATER, 0 },
  [0x08E] = { "Luridan", 2, SLASH | PIERCE, FIRE | WIND, 0 },
  [0x0F2] = { "Borras", 4, BLUDG | SLASH, POISON, 0 },
  [0x0DD] = { "Punisher", 3, SLASH | PIERCE, POISON, 0 },
  [0x0C5] = { "Scrapper", 2, SLASH | BLUDG, 0, POISON },
  [0x014] = { "Ursus", 2, BLUDG | SLASH, FIRE, 0 },
  [0x14B] = { "Storm Drgn", 14, SLASH | PIERCE, BOLT, WIND },
}

-- the hands (route-wor-cyan.md 6): the four who reach Mt. Zozo first
-- (wor-terra-v1's kit), and CYAN as the cabin dresses him (his Tempest)
local TERRA = { "TERRA", SLASH, FIRE }
local CELES = { "CELES", SLASH, FIRE | ICE | BOLT }
local SABIN = { "SABIN", SLASH | BLUDG, FIRE | HOLY | WIND }
local EDGAR = { "EDGAR", SLASH | PIERCE, BOLT | POISON }
local CYAN  = { "CYAN", SLASH, WIND }
local function union(what, list)
  local h = { cls = 0, el = 0, what = what }
  for _, m in ipairs(list) do h.cls = h.cls | m[2]; h.el = h.el | m[3] end
  return h
end
local FIRST = union("the four who first climb (TERRA, CELES, SABIN, EDGAR)", { TERRA, CELES, SABIN, EDGAR })
local SECOND = union("the four with CYAN (CYAN, TERRA, CELES, SABIN)", { CYAN, TERRA, CELES, SABIN })

-- world groups at the landings (both trips), Mt. Zozo's field groups
-- (179: 160, 176: 161, 177/178: 162), the dragon's event group
local GROUPS = {
  { "world", 48, SECOND }, { "world", 49, SECOND }, { "world", 50, SECOND },
  { "world", 48, FIRST }, { "world", 49, FIRST }, { "world", 50, FIRST },
  { "field", 160, FIRST }, { "field", 161, FIRST }, { "field", 162, FIRST },
  { "field", 160, SECOND }, { "field", 161, SECOND },
  { "event", 133, SECOND },
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
      if elemAdd[sp] ~= nil then
        problem("$%03X %s has an Ot6ElemAddTbl row (elements $%02X); the design adds none", sp, w[1], elemAdd[sp][1])
      end
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
    local pairs_, seen, nform = 0, {}, {}
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
            pairs_ = pairs_ + 1
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
    H.log(string.format("checked %d formations, %d formation-species-hands triples", nf, pairs_))
    -- the field groups are Mt. Zozo's maps' own (SubBattleGroup, a byte a map)
    for m, g in pairs({ [179] = 160, [176] = 161, [177] = 162, [178] = 162 }) do
      local got = H.readRomByte(sbg + m)
      if got ~= g then problem("map %d's pool is group %d, the design read %d", m, got, g) end
    end

    -- 3. the lessons
    local STORM = 0x14B
    local ck = (classOf(STORM) & CYAN[2]) ~= 0
    H.log(string.format("$14B: CYAN's katana (slash) %s", ck and "is a key" or "is NOT a key"))
    if not ck then problem("$14B: CYAN's katana (slash) does not key the Storm Dragon") end
    for _, m in ipairs({ CYAN, TERRA, CELES, SABIN }) do
      local ok = keys(STORM, m[2], m[3])
      H.log(string.format("$14B: %s %s", m[1], ok and "holds a key" or "holds NO key"))
      if not ok then problem("$14B: %s holds no key on the Storm Dragon", m[1]) end
    end
    if (absorb(STORM) & WIND) == 0 then problem("$14B: the Storm Dragon no longer absorbs wind (the Tempest lesson)") end
    local lk = (classOf(0x08E) & SLASH) ~= 0 and (weakOf(0x08E) & WIND) ~= 0
    H.log(string.format("$08E: CYAN's Stunner (slash) and Tempest (wind) %s the Luridan", lk and "both key" or "do NOT both key"))
    if not lk then problem("$08E: the Luridan is not keyed by both slash and wind") end
    if (absorb(0x0C5) & POISON) == 0 then problem("$0C5: the Scrapper no longer absorbs poison") end
    if (classOf(0x0D2) & SLASH) == 0 then problem("$0D2: the Mantodea takes no blade") end
    H.assertEq(#problems, 0, "WoR Cyan break row mismatches")
    H.log("WoR Cyan break rows verified against the built ROM")
  end),
})
