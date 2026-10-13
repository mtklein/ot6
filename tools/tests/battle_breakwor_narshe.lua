-- @suite
-- battle_breakwor_narshe.lua -- the World of Ruin break rows for the Narshe
-- arc (the town, the mines, the moogle cave, the cliffs, Umaro's cave; the
-- Ice Dragon, Tritoch and Umaro), re-verified from the built ROM
-- (battle_breakwor_cyan's shape: pure ROM bytes, no savestate).
-- docs/design/route-wor-narshe.md section 4 is the design; WANT below is its
-- table, and the only place the expectations live.
--
--   1. each species carries exactly its designed Ot6ShieldTbl row, keeps its
--      vanilla weak and absorb bytes, and has no Ot6ElemAddTbl row;
--   2. every species the arc can draw -- the town and the cliffs (field
--      group 189), the mines (190), the moogle cave and the cliffs above
--      (191), Umaro's cave (166, 167, 168), the plain at Narshe's gate
--      (world group 51) and the event groups 117 (Umaro), 119 (Tritoch),
--      132 (the Ice Dragon) and 152 (the Pugs' chest) -- has an authored
--      row, and every gauged one a key for the hands that meet it, but the
--      one declared lesson: the Test Rider in town before MOG joins;
--   3. the lessons: MOG's spear (pierce) is the Test Rider's only key and
--      the Ice Dragon's class key (its keys are the spear and TERRA's fire,
--      not the blades); each of the four holds a key on Tritoch and Umaro;
--      every boss absorbs ice and is weak to fire; the Psychot absorbs fire; Tritoch's record $144 carries a real
--      row while the World of Balance's $114/$115 stay shieldless.
-- All mismatches are logged before the verdict.
local H = dofile("tools/tests/lib/ot6.lua")

local SLASH, PIERCE, BLUDG, SPECIAL = 0x01, 0x02, 0x04, 0x08
local FIRE, ICE, BOLT, POISON, WIND, HOLY, EARTH, WATER = 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80

-- species -> { name, shields, class mask, vanilla weak byte, vanilla absorb byte }
local WANT = {
  [0x0F8] = { "Red Wolf", 2, SLASH | PIERCE, 0, 0 },
  [0x0CE] = { "Nastidon", 2, SLASH | BLUDG, FIRE, 0 },
  [0x09C] = { "Test Rider", 3, PIERCE, POISON, 0 },
  [0x0C4] = { "Wizard", 2, SLASH | PIERCE | SPECIAL, BOLT | POISON, 0 },
  [0x0DA] = { "Psychot", 1, PIERCE | SPECIAL, ICE, FIRE },
  [0x0E7] = { "Mag Roader (ice)", 2, PIERCE | BLUDG, 0, 0 },
  [0x0F3] = { "Mag Roader (fire)", 2, PIERCE | BLUDG, 0, 0 },
  [0x0C9] = { "Poppers", 1, SLASH | PIERCE, FIRE, 0 },
  [0x0CD] = { "Kiwok", 2, SLASH | PIERCE, ICE, 0 },
  [0x0C6] = { "Ceritops", 3, PIERCE | BLUDG, FIRE, BOLT },
  [0x0B4] = { "Anemone", 2, SLASH, FIRE | BOLT, BOLT | WATER },
  [0x09E] = { "Tomb Thumb", 2, PIERCE | SPECIAL, BOLT | WATER, 0 },
  [0x054] = { "Pug", 4, SLASH | SPECIAL, FIRE | BOLT, WATER },
  [0x0FF] = { "Pugs", 4, SLASH | SPECIAL, FIRE, WATER },
  [0x110] = { "Umaro", 6, SLASH | PIERCE, FIRE | POISON, ICE },
  [0x144] = { "Tritoch", 10, SLASH | PIERCE, FIRE, ICE },
  [0x149] = { "Ice Dragon", 6, PIERCE | BLUDG, FIRE, ICE },
}

-- the hands (route-wor-narshe.md 5.4, 6): the three who walk into Narshe
-- (wor-cyan-v1's kit: TERRA knows Fire and Quake, CELES Ice, CYAN's
-- Tempest is wind), MOG's spear with them once he joins, and UMARO's club
-- and Storm on the plain at the end with MOG, TERRA and CELES
local TERRA = { "TERRA", SLASH, FIRE | EARTH }
local CELES = { "CELES", SLASH, ICE }
local CYAN  = { "CYAN", SLASH, WIND }
local MOG   = { "MOG", PIERCE, 0 }
local UMARO = { "UMARO", BLUDG, ICE }
local function union(what, list)
  local h = { cls = 0, el = 0, what = what }
  for _, m in ipairs(list) do h.cls = h.cls | m[2]; h.el = h.el | m[3] end
  return h
end
local FIRST = union("the three who walk in (CYAN, TERRA, CELES)", { CYAN, TERRA, CELES })
local SECOND = union("the four with MOG (CYAN, TERRA, CELES, MOG)", { CYAN, TERRA, CELES, MOG })
local THIRD = union("the four with UMARO (UMARO, MOG, TERRA, CELES)", { UMARO, MOG, TERRA, CELES })

-- the town before MOG (189: maps 32 and 33), the moogle cave (191: 37, 38);
-- after MOG the town again, the mines (190: 36), the cliffs (189, 191: 33,
-- 34, 35), Umaro's cave (166, 167, 168: 281, 282, 283) and its events; the
-- plain at the gate with UMARO
local GROUPS = {
  { "field", 189, FIRST }, { "field", 191, FIRST },
  { "field", 189, SECOND }, { "field", 190, SECOND }, { "field", 191, SECOND },
  { "field", 166, SECOND }, { "field", 167, SECOND }, { "field", 168, SECOND },
  { "event", 132, SECOND }, { "event", 119, SECOND }, { "event", 117, SECOND }, { "event", 152, SECOND },
  { "world", 51, THIRD },
}
-- the one declared lesson: the town's Test Rider cannot be broken before
-- MOG's spear arrives
local LESSON = { [0x09C] = FIRST.what }

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
    local triples, seen, nform, lessons = 0, {}, {}, 0
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
            local has = keys(sp, hand.cls, hand.el)
            if gauged(sp) and not has then
              if LESSON[sp] == hand.what then
                lessons = lessons + 1
                H.log(string.format("formation %d (%s): $%03X has no key for %s: the declared lesson", f, where, sp,
                  hand.what))
              else
                problem("formation %d (%s): species $%03X (class $%02X, weak $%02X) has no key for %s",
                  f, where, sp, classOf(sp), weakOf(sp), hand.what)
              end
            elseif LESSON[sp] == hand.what then
              problem("formation %d (%s): $%03X is keyed for %s; the design makes it MOG's to break", f, where, sp,
                hand.what)
            end
          end
        end
      end
    end
    local nf = 0
    for _ in pairs(nform) do nf = nf + 1 end
    H.log(string.format("checked %d formations, %d formation-species-hands triples, %d declared lesson(s)", nf,
      triples, lessons))
    if lessons == 0 then problem("the Test Rider lesson was never met: is $09C still in field group 189?") end
    -- the maps' pools (SubBattleGroup, a byte a map) are the ones the design read
    for m, g in pairs({ [32] = 189, [33] = 189, [34] = 191, [35] = 191, [36] = 190, [37] = 191, [38] = 191,
      [281] = 166, [282] = 167, [283] = 168 }) do
      local got = H.readRomByte(sbg + m)
      if got ~= g then problem("map %d's pool is group %d, the design read %d", m, got, g) end
    end

    -- 3. the lessons
    local RIDER, DRAGON, TRITOCH, UMAROSP = 0x09C, 0x149, 0x144, 0x110
    if classOf(RIDER) ~= PIERCE then problem("$09C: the Test Rider's only class key is not pierce") end
    if (classOf(DRAGON) & PIERCE) == 0 then problem("$149: MOG's spear (pierce) does not key the Ice Dragon") end
    for _, sp in ipairs({ DRAGON, TRITOCH, UMAROSP }) do
      if (absorb(sp) & ICE) == 0 then problem("$%03X no longer absorbs ice", sp) end
      if (weakOf(sp) & FIRE) == 0 then problem("$%03X is not weak to fire", sp) end
      -- Tritoch and Umaro: each of the four holds a key; the Ice Dragon's
      -- keys are MOG's spear and fire (TERRA's), not the blades (the design:
      -- who the party brings decides how it breaks)
      for _, m in ipairs({ CYAN, TERRA, CELES, MOG }) do
        local ok = keys(sp, m[2], m[3])
        H.log(string.format("$%03X: %s %s", sp, m[1], ok and "holds a key" or "holds NO key"))
        local want = sp ~= DRAGON or m == MOG or m == TERRA
        if ok ~= want then
          problem("$%03X: %s %s", sp, m[1], want and "holds no key" or "holds a key the design keeps from the blades")
        end
      end
    end
    if (absorb(0x0DA) & FIRE) == 0 then problem("$0DA: the Psychot no longer absorbs fire") end
    for _, sp in ipairs({ 0x114, 0x115 }) do
      if shield[sp] == nil or shield[sp][1] ~= 0 then problem("$%03X (the WoB's Tritoch) is gauged", sp) end
    end
    H.assertEq(#problems, 0, "WoR Narshe break row mismatches")
    H.log("WoR Narshe break rows verified against the built ROM")
  end),
})
