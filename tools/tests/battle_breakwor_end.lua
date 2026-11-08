-- @suite
-- battle_breakwor_end.lua -- the break rows for Kefka's battle (event battle 101: formations 471, 512, 513, 514, the
-- four tiers battle_main.asm's FinalBattleIDTbl chains), re-verified from the built ROM (battle_breakwor_tower's
-- shape: pure ROM bytes, no savestate).  docs/design/route-wor-the-end.md section 2 is the design; the table below
-- is its, and the only place the expectations live.
--
--   1. every designed species carries exactly its Ot6ShieldTbl row, keeps its vanilla weak and absorb bytes, and has
--      no Ot6ElemAddTbl row;
--   2. event battle 101 deals formation 471, and FinalBattleIDTbl chains 471 -> 512 -> 513 -> 514; every species of
--      the four has an authored row;
--   3. the lessons: each tier between its bodies takes every hand (slash, pierce, bludgeon, special), so any four the
--      order menu puts in front hold a key in every tier; Kefka takes every hand.
-- All mismatches are logged before the verdict.
local H = dofile("tools/tests/lib/ot6.lua")

local SLASH, PIERCE, BLUDG, SPECIAL = 0x01, 0x02, 0x04, 0x08
local FIRE, ICE, BOLT, POISON, WIND, HOLY, EARTH, WATER = 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80
local HANDS = SLASH | PIERCE | BLUDG | SPECIAL
local ALL = 0xFF

-- species -> { name, shields, class mask, vanilla weak byte, vanilla absorb byte }
local WANT = {
  [0x157] = { "Short Arm", 6, PIERCE | BLUDG, WATER, 0 },
  [0x158] = { "Long Arm", 6, SLASH | PIERCE, WIND, 0 },
  [0x159] = { "Face", 8, BLUDG | SPECIAL, FIRE, 0 },
  [0x15D] = { "Hit", 6, SLASH | BLUDG, POISON, 0 },
  [0x15A] = { "Tiger", 6, SLASH | PIERCE, ICE, EARTH },
  [0x15B] = { "Tools", 6, PIERCE | BLUDG, BOLT, 0 },
  [0x15C] = { "Magic", 8, SLASH | SPECIAL, EARTH, 0 },
  [0x15E] = { "Girl", 3, SLASH | PIERCE, ALL, ALL },
  [0x15F] = { "Sleep", 8, BLUDG | SPECIAL, 0, 0 },
  [0x12A] = { "Kefka", 12, HANDS, 0, 0 },
}
local TIERS = { 0x1D7, 0x200, 0x201, 0x202 }

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
    local ebg = H.sym("EventBattleGroup") & 0x3FFFFF
    local bm = H.sym("BattleMonsters") & 0x3FFFFF
    local ids = H.sym("FinalBattleIDTbl") & 0x3FFFFF
    local function formSpecies(f)
      local rec = bm + f * 15
      local pres, hi = H.readRomByte(rec + 1), H.readRomByte(rec + 14)
      local out = {}
      for s = 0, 5 do
        if (pres & (1 << s)) ~= 0 then out[#out + 1] = H.readRomByte(rec + 2 + s) | (((hi >> s) & 1) << 8) end
      end
      return out
    end

    -- 1. the designed rows
    local list = {}
    for sp in pairs(WANT) do list[#list + 1] = sp end
    table.sort(list)
    for _, sp in ipairs(list) do
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
    H.log(string.format("checked %d designed rows (Kefka's battle)", #list))

    -- 2. the battle: event battle 101 opens on 471, and the tier table chains the four
    for k = 0, 1 do
      local f = rom16(ebg + 101 * 4 + 2 * k) & 0x3FF
      if f ~= TIERS[1] then problem("event battle 101 slot %d deals formation %d, want %d", k, f, TIERS[1]) end
    end
    for k = 1, 3 do
      local from, to = rom16(ids + 2 * (k - 1)), rom16(ids + 2 * k)
      if from ~= TIERS[k] or to ~= TIERS[k + 1] then
        problem("FinalBattleIDTbl step %d: $%03X -> $%03X, want $%03X -> $%03X", k, from, to, TIERS[k], TIERS[k + 1])
      end
    end
    local n = 0
    for t, f in ipairs(TIERS) do
      local hands = 0
      for _, sp in ipairs(formSpecies(f)) do
        n = n + 1
        if WANT[sp] == nil then problem("formation %d (tier %d): species $%03X is not designed here", f, t, sp) end
        if shield[sp] == nil then problem("formation %d (tier %d): species $%03X has no authored row", f, t, sp) end
        hands = hands | classOf(sp)
      end
      -- 3. the lessons: every hand in every tier
      if (hands & HANDS) ~= HANDS then
        problem("formation %d (tier %d): its bodies together key class mask $%02X, want every hand ($%02X)", f, t,
          hands, HANDS)
      end
    end
    if (classOf(0x12A) & HANDS) ~= HANDS then problem("$12A Kefka: class mask $%02X, want every hand", classOf(0x12A)) end
    H.log(string.format("checked %d formation-species pairs of the four tiers; the lessons: every hand in every tier, "
      .. "and every hand finds Kefka", n))
    H.assertEq(#problems, 0, "Kefka's battle break row mismatches")
    H.log("Kefka's battle break rows verified against the built ROM")
  end),
})
