-- @suite
-- battle_breakwob_sidetrips.lua -- the World of Balance break rows for the side trips off the story's path: the
-- forests by Albrook (world groups 20, 17, 18, and 15 and 26, which deal the same bodies), walked from the opera's
-- landing, and the airship's islands, the bomb isle (27) and Triangle Island (124, 28), re-verified from the built
-- ROM (battle_breakwor_sidetrips's shape: pure ROM bytes, no savestate).
-- docs/design/wob-side-trips.md section 2 is the design; the tables below are its, and the only place the
-- expectations live.
--
--   1. Bug, ChickenLip, Grenade and Intangir carry exactly their designed Ot6ShieldTbl rows, keep their vanilla
--      weak and absorb bytes, and have no Ot6ElemAddTbl row;
--   2. every species of every formation of those world groups has a key in the hands of the four that first meets
--      it (the forests: the post-opera four; the islands: the four the wheel is handed to, SETZER among them), and
--      each group still deals the species it is checked for;
--   3. the lessons: the Grenade answers a Fight that does not break it with Exploder, so it is keyed by the point
--      (LOCKE's knife, whose boosted swing breaks it in one; EDGAR's tools) and the blow (SABIN's blitzes, which
--      it does not answer), and not by the blades; the Intangir absorbs every element, so every other hand keys it,
--      SETZER's special too.
-- All mismatches are logged before the verdict.
local H = dofile("tools/tests/lib/ot6.lua")

local SLASH, PIERCE, BLUDG, SPECIAL = 0x01, 0x02, 0x04, 0x08
local FIRE, ICE, BOLT, POISON, WIND, HOLY, EARTH, WATER = 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80

-- species -> { name, shields, class mask, vanilla weak byte, vanilla absorb byte }
local WANT = {
  [0x0E8] = { "Bug", 2, SLASH | PIERCE, ICE | WATER, 0 },
  [0x03D] = { "ChickenLip", 2, SLASH | BLUDG, ICE, 0 },
  [0x0AA] = { "Grenade", 3, PIERCE | BLUDG, ICE | WATER, FIRE },
  [0x0A3] = { "Intangir", 4, SLASH | PIERCE | BLUDG | SPECIAL, 0, 0xFF },
}
local BUG, CHICKENLIP, GRENADE, INTANGIR = 0x0E8, 0x03D, 0x0AA, 0x0A3
-- the world groups (RandBattleGroup index = WorldBattleGroup byte) and the species each must deal
local GROUPS = { { 20, "the forest east of Albrook", { BUG }, "post-opera" },
  { 17, "the forest west of Albrook", { CHICKENLIP }, "post-opera" },
  { 18, "the forest by Maranda", { CHICKENLIP }, "post-opera" },
  { 15, "the southern continent's grass (ChickenLip x5 beside the Jokers)", { CHICKENLIP }, "post-opera" },
  { 26, "the southern forest's other sector (Bug, FossilFang)", { BUG }, "post-opera" },
  { 27, "the bomb isle", { GRENADE }, "airship" },
  { 124, "Triangle Island", { INTANGIR }, "airship" }, { 28, "Triangle Island's shore", { INTANGIR }, "airship" } }
-- the hands that meet each group: the forests, the post-opera four on foot (post-opera-v1: CELES's RegalCutlass,
-- slash; LOCKE's MithrilKnife, pierce; EDGAR's Mithril Pike and AutoCrossbow, pierce; SABIN's Kaiser and Pummel,
-- bludgeon); the islands, the four the wheel is handed to (terra-returned-v1: LOCKE's knife, pierce; EDGAR's
-- Blizzard, slash, and his tools, pierce; SABIN's Poison Claw, slash, and Pummel, bludgeon; SETZER's cards, special)
local POST_OPERA = SLASH | PIERCE | BLUDG
local AIRSHIP = SLASH | PIERCE | BLUDG | SPECIAL

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
    local rbg = H.sym("RandBattleGroup") & 0x3FFFFF
    local bm  = H.sym("BattleMonsters") & 0x3FFFFF
    local function groupForms(n)
      local out = {}
      for slot = 0, 3 do
        local word = rom16(rbg + n * 8 + slot * 2)
        for k = 0, ((word & 0x8000) ~= 0) and 3 or 0 do out[#out + 1] = (word & 0x3FF) + k end
      end
      return out
    end
    local function formSpecies(f)
      local rec = bm + f * 15
      local pres, hi = H.readRomByte(rec + 1), H.readRomByte(rec + 14)
      local out = {}
      for s = 0, 5 do
        if (pres & (1 << s)) ~= 0 then out[#out + 1] = H.readRomByte(rec + 2 + s) | (((hi >> s) & 1) << 8) end
      end
      return out
    end

    -- 1. the four rows
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
    H.log(string.format("checked %d designed rows (the forests', the bomb isle's and Triangle Island's bodies)", #ids))

    -- 2. the world groups against the four's hands
    for _, g in ipairs(GROUPS) do
      local seen, n = {}, 0
      for _, f in ipairs(groupForms(g[1])) do
        for _, sp in ipairs(formSpecies(f)) do
          n = n + 1
          seen[sp] = true
          local hands = g[4] == "airship" and AIRSHIP or POST_OPERA
          if (classOf(sp) & hands) == 0 then
            problem("formation %d (%s): species $%03X (class $%02X) has no key in the %s four's hands", f, g[2], sp,
              classOf(sp), g[4])
          end
        end
      end
      for _, sp in ipairs(g[3]) do
        if not seen[sp] then problem("world group %d (%s) no longer deals species $%03X", g[1], g[2], sp) end
      end
      H.log(string.format("checked %d formation-species pairs of world group %d (%s)", n, g[1], g[2]))
    end

    -- 3. the lessons
    if (classOf(GRENADE) & SLASH) ~= 0 then
      problem("$0AA Grenade: a blade (slash) keys it; its keys are the point (one boosted swing, or a tool) and the blow "
        .. "(a blitz)")
    end
    if (classOf(GRENADE) & PIERCE) == 0 then problem("$0AA Grenade: LOCKE's point and EDGAR's tools (pierce) hold no key") end
    if (classOf(GRENADE) & BLUDG) == 0 then problem("$0AA Grenade: SABIN's blitzes (bludgeon) hold no key") end
    if absorb(INTANGIR) ~= 0xFF then problem("$0A3 Intangir: no longer absorbs every element") end
    if (classOf(INTANGIR) & AIRSHIP) ~= AIRSHIP then
      problem("$0A3 Intangir: class $%02X, want every hand the four hold ($%02X): it absorbs every element",
        classOf(INTANGIR), AIRSHIP)
    end
    H.log("the lessons: the Grenade takes the point and the blow, not the blades; the Intangir takes every hand but magic")
    H.assertEq(#problems, 0, "WoB side trips break row mismatches")
    H.log("WoB side trips break rows verified against the built ROM")
  end),
})
