-- @suite
-- battle_breakwob_desert.lua -- the World of Balance break rows for the Figaro desert and the plains to South Figaro (world groups 1, 12, 3 and 5), re-verified from the built ROM
-- (battle_breakwor_sidetrips's shape: pure ROM bytes, no savestate).  docs/design/break-coverage-wob.md section 2
-- is the design; the tables below are its, and the only place the expectations live.
--
--   1. each designed species carries exactly its Ot6ShieldTbl row, keeps its vanilla weak and absorb bytes, and its
--      Ot6ElemAddTbl row is the one it had (the plains' poison adds) or none;
--   2. every species of every formation the area's pools deal has an authored row and a key for each party that
--      meets it there;
--   3. the lessons: EDGAR's pike (pierce) keys every body; the Bio Blaster's poison keys the plains and heals the FossilFang, whose bones turn the blade.
-- All mismatches are logged before the verdict.
local H = dofile("tools/tests/lib/ot6.lua")

local SLASH, PIERCE, BLUDG, SPECIAL = 0x01, 0x02, 0x04, 0x08
local FIRE, ICE, BOLT, POISON, WIND, HOLY, EARTH, WATER = 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80

-- species -> { name, shields, class mask, vanilla weak byte, vanilla absorb byte, Ot6ElemAddTbl elements (0: no row) }
local WANT = {
  [0x05C] = { "Sand Ray", 2, SLASH | PIERCE, ICE | WATER, 0, POISON },
  [0x023] = { "FossilFang", 3, PIERCE | BLUDG, FIRE | ICE | HOLY | WATER, POISON, 0 },
  [0x015] = { "Rhinotaur", 2, PIERCE | BLUDG, 0, BOLT, POISON },
  [0x012] = { "Rhodox", 2, SLASH | PIERCE, 0, 0, POISON },
  [0x0A8] = { "GreaseMonk", 2, PIERCE | BLUDG, POISON, 0, 0 },
}
-- the pools: { "map", map, its SubBattleGroup, label } or { "world", RandBattleGroup index, label }, and the
-- species each must deal
local POOLS = {
  { "world", 1, "the Figaro desert", { 0x05C } },
  { "world", 12, "the desert by Figaro Castle", { 0x023, 0x05C } },
  { "world", 3, "the plains to South Figaro", { 0x012, 0x015, 0x0A8 } },
  { "world", 5, "the plains by Figaro Castle", { 0x012, 0x015, 0x0A8 } },
}
-- the parties that meet the area (their hands: weapon classes, and the elements their spells, tools and weapons
-- reach), from the tracked checkpoints and the route's battle logs (break-coverage-wob.md section 2); the pools
-- each meets (nil: all)
local PARTIES = {
  { "TERRA, LOCKE, EDGAR", { { "TERRA", PIERCE, FIRE }, { "LOCKE", SLASH, 0 }, { "EDGAR", PIERCE, POISON } }, nil },
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
    local rbg = H.sym("RandBattleGroup") & 0x3FFFFF
    local sbg = H.sym("SubBattleGroup") & 0x3FFFFF
    local bm = H.sym("BattleMonsters") & 0x3FFFFF
    local function groupForms(n)
      local out = {}
      for slot = 0, 3 do
        local word = rom16(rbg + n * 8 + slot * 2)
        for k = 0, ((word & 0x8000) ~= 0) and 3 or 0 do out[#out + 1] = (word & 0x1FF) + k end
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

    -- 2. the pools against the parties that meet them
    for pi, p in ipairs(POOLS) do
      local group = p[1] == "map" and H.readRomByte(sbg + p[2]) or p[2]
      if p[1] == "map" and group ~= p[3] then
        problem("map %d (%s) deals pool group %d, want %d", p[2], p[4], group, p[3])
      end
      local label = p[1] == "map" and p[4] or p[3]
      local seen, n = {}, 0
      for _, f in ipairs(groupForms(group)) do
        for _, sp in ipairs(formSpecies(f)) do
          n = n + 1
          seen[sp] = true
          if shield[sp] == nil then
            problem("formation %d (%s, group %d): species $%03X has no authored row", f, label, group, sp)
          end
          for _, party in ipairs(PARTIES) do
            local meets = party[3] == nil
            for _, k in ipairs(party[3] or {}) do meets = meets or k == pi end
            if meets then
              local cls, el = 0, 0
              for _, m in ipairs(party[2]) do cls, el = cls | m[2], el | m[3] end
              if (classOf(sp) & cls) == 0 and (weakOf(sp) & el) == 0 then
                problem("formation %d (%s): species $%03X (class $%02X, weak $%02X) has no key for %s", f, label,
                  sp, classOf(sp), weakOf(sp), party[1])
              end
            end
          end
        end
      end
      for _, sp in ipairs(p[#p]) do
        if not seen[sp] then problem("group %d (%s) no longer deals species $%03X", group, label, sp) end
      end
      H.log(string.format("checked %d formation-species pairs of group %d (%s)", n, group, label))
    end

    -- 3. the lessons
    for _, sp in ipairs({ 0x05C, 0x023, 0x015, 0x012, 0x0A8 }) do
      if (classOf(sp) & PIERCE) == 0 then problem("$%03X %s: EDGAR's pike (pierce) holds no key", sp, WANT[sp][1]) end
    end
    if (absorb(0x023) & POISON) == 0 then problem("$023 FossilFang no longer absorbs poison (the Bio Blaster trap)") end
    if (weakOf(0x0A8) & POISON) == 0 then problem("$0A8 GreaseMonk: the Bio Blaster (poison) holds no key") end
    if (classOf(0x023) & SLASH) ~= 0 then problem("$023 FossilFang: the blade keys the bones") end
    H.log("the lessons: EDGAR's pike keys every body; the Bio Blaster keys the plains and heals the FossilFang")
    H.assertEq(#problems, 0, "WoB desert break row mismatches")
    H.log("WoB desert break rows verified against the built ROM")
  end),
})
