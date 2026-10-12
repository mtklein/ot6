-- @suite
-- battle_breakwor_terra.lua -- the World of Ruin break rows for TERRA's arc
-- (Mobliz and Phunbaba's four records), re-verified from the built ROM
-- (battle_breakwor_falcon's shape: pure ROM bytes, no savestate).
-- docs/design/route-wor-terra.md section 6 is the design; WANT below is its
-- table, and the only place the expectations live.
--
--   1. each Phunbaba record carries exactly its designed Ot6ShieldTbl row
--      (the first row for the species), keeps its vanilla weak byte
--      (poison) and absorb byte (bolt), and has no Ot6ElemAddTbl row;
--   2. every species the arc can draw -- the event groups 128-131 and the
--      world groups the route walks (the Solitary Island's 29/30, the
--      plain outside Mobliz 37/38) -- has an authored row, and every gauged
--      one a key for the hands that meet it;
--   3. the lessons: battle 128 draws no gauge (TERRA alone, a loss the
--      story plays on from); in 129 and 130 every one of the four but
--      CELES (whose turn is Runic against his bolts) holds a key; in 131
--      TERRA's own blade keys him, whichever two of the four the
--      BabaBreaths left beside her.
-- All mismatches are logged before the verdict.
local H = dofile("tools/tests/lib/ot6.lua")

local SLASH, PIERCE, BLUDG, SPECIAL = 0x01, 0x02, 0x04, 0x08
local FIRE, ICE, BOLT, POISON, WIND, HOLY = 0x01, 0x02, 0x04, 0x08, 0x10, 0x20

-- species -> { name, shields, class mask, vanilla weak byte }
local WANT = {
  [0x16A] = { "Phunbaba 1 (TERRA alone)", 0, 0, POISON },
  [0x16B] = { "Phunbaba 2 (the first visit)", 4, BLUDG | SPECIAL, POISON },
  [0x16C] = { "Phunbaba 3 (the return)", 5, BLUDG | SPECIAL, POISON },
  [0x16D] = { "Phunbaba 4 (TERRA morphed)", 12, SLASH | BLUDG | SPECIAL, POISON },
}

-- the hands (route-wor-terra.md 6): the four as they reach Mobliz
-- (wor-falcon-v1's kit), and TERRA as she joins (the Break Blade)
local CELES  = { "CELES", SLASH, FIRE | ICE | BOLT }
local SABIN  = { "SABIN", SLASH | BLUDG, FIRE | HOLY | WIND }
local EDGAR  = { "EDGAR", SLASH | PIERCE, BOLT | POISON }
local SETZER = { "SETZER", SPECIAL | PIERCE, 0 }
local TERRA  = { "TERRA", SLASH, FIRE }
local function union(what, list)
  local h = { cls = 0, el = 0, what = what }
  for _, m in ipairs(list) do h.cls = h.cls | m[2]; h.el = h.el | m[3] end
  return h
end
local FOUR = union("the four", { CELES, SABIN, EDGAR, SETZER })
local TERRA_ALONE = union("TERRA alone", { TERRA })

local WORLD_GROUPS = { 29, 30, 37, 38 }
local EVENT_GROUPS = { [128] = TERRA_ALONE, [129] = FOUR, [130] = FOUR, [131] = TERRA_ALONE }

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
      if (absorb(sp) & BOLT) == 0 then problem("$%03X %s absorb byte $%02X has lost vanilla bolt", sp, w[1], absorb(sp)) end
      if elemAdd[sp] ~= nil then
        problem("$%03X %s has an Ot6ElemAddTbl row (elements $%02X); the design adds none", sp, w[1], elemAdd[sp][1])
      end
    end
    H.log(string.format("checked %d designed rows", #ids))

    -- 2. every species of every formation the arc can draw
    local rbg = H.sym("RandBattleGroup") & 0x3FFFFF
    local ebg = H.sym("EventBattleGroup") & 0x3FFFFF
    local bm  = H.sym("BattleMonsters") & 0x3FFFFF
    local formations, order = {}, {}
    local function addWord(word, where, hand)
      local base = word & 0x1FF
      for k = 0, ((word & 0x8000) ~= 0) and 3 or 0 do
        local f = base + k
        if formations[f] == nil then
          formations[f] = { where = where, hand = hand }
          order[#order + 1] = f
        end
      end
    end
    for _, g in ipairs(WORLD_GROUPS) do
      for slot = 0, 3 do addWord(rom16(rbg + g * 8 + slot * 2), "world group " .. g, FOUR) end
    end
    for g, hand in pairs(EVENT_GROUPS) do
      addWord(rom16(ebg + g * 4), "event group " .. g, hand)
      addWord(rom16(ebg + g * 4 + 2), "event group " .. g, hand)
    end
    table.sort(order)
    local pairs_, seen = 0, {}
    for _, f in ipairs(order) do
      local rec = bm + f * 15
      local pres, hi = H.readRomByte(rec + 1), H.readRomByte(rec + 14)
      local where, hand = formations[f].where, formations[f].hand
      for s = 0, 5 do
        if (pres & (1 << s)) ~= 0 then
          local sp = H.readRomByte(rec + 2 + s) | (((hi >> s) & 1) << 8)
          local key = f * 1024 + sp
          if not seen[key] then
            seen[key] = true
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
    H.log(string.format("checked %d formations, %d formation-species pairs", #order, pairs_))

    -- 3. the lessons
    if gauged(0x16A) then problem("battle 128 draws a gauge on $16A (TERRA alone; the loss is the story's)") end
    for _, sp in ipairs({ 0x16B, 0x16C }) do
      for _, m in ipairs({ SABIN, EDGAR, SETZER }) do
        local ok = keys(sp, m[2], m[3])
        H.log(string.format("$%03X: %s %s", sp, m[1], ok and "holds a key" or "holds NO key"))
        if not ok then problem("$%03X: %s holds no key", sp, m[1]) end
      end
    end
    local tk = (classOf(0x16D) & TERRA[2]) ~= 0
    H.log(string.format("$16D: TERRA's blade (slash) %s", tk and "is a key" or "is NOT a key"))
    if not tk then problem("$16D: TERRA's blade (slash) does not key Phunbaba 4") end
    local four = { CELES, SABIN, EDGAR, SETZER }
    for i = 1, 4 do
      for j = i + 1, 4 do
        local h = union("", { TERRA, four[i], four[j] })
        if not keys(0x16D, h.cls, h.el) then
          problem("$16D: TERRA with %s and %s holds no key", four[i][1], four[j][1])
        end
      end
    end
    H.assertEq(#problems, 0, "WoR Terra break row mismatches")
    H.log("WoR Terra break rows verified against the built ROM")
  end),
})
