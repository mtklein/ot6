-- @suite slow
-- battle_esperearring.lua -- an esper rank that copies an earring counts as one earring piece (#551;
-- docs/design/esper-rework.md; ot6_esper.asm Ot6EsperApply): Maduin's Earrings and Bahamut's Hero Ring each add a
-- piece the way vanilla's CalcEquipEffect counts worn ones, the first setting the single-earring bit (relic effects
-- 3, $11D7 bit 1, the battle's $3C45) and the second the double (relic effects 1, $11D5 bit 1, $3C44), and no count
-- goes past the double.  RelicDmgEffect then raises a spell's damage by 1/4 for the single and 1/2 for the double.
--
-- Continue post-opera-v1.  C is the first seated member who knows Fire, Ice or Bolt (on this save CELES and Ice).
-- The earring rungs are found by their bytes, not by esper: every ladder record whose relic-effects byte (+4)
-- carries $02 (two today: Maduin's rung 5, Bahamut's rung 5, whose $03 also carries the Atlas Armlet's +1/4 to
-- Fight); "rank" below means C's count on that stone is the rung's cost, "no rank" one short of it (rank 4: the
-- same stat rungs, so the same Mag.Pwr in every case).  A snapshot on the world map; then one branch per case from
-- it, each staging C's two counts on the live esper page ($317C00) and C's two relic slots ($1623/$1624) -- both
-- declared in state_write_waivers.txt, a mechanism expedient: the property is how the battle counts the pieces, and
-- a signature takes 500 Magic Points in one stone -- then walking into a random battle (the same one in every
-- branch: the same snapshot, the same steps) where C casts the spell once, unboosted, through the real menu while
-- the others Defend, and the party then Fights it out.
--   none           no rank, no relic               magic x1
--   earring        no rank, Earrings worn          x1 1/4 (vanilla's one piece, unchanged)
--   rank           Maduin's rank, nothing worn     x1 1/4
--   rank2          Bahamut's rank, nothing worn    x1 1/4, and the atlas bit
--   rank+earring   Maduin's rank, Earrings worn    x1 1/2
--   rank2+hero     Bahamut's rank, Hero Ring worn  x1 1/2
--   both           both ranks, nothing worn        x1 1/2, and the atlas bit
--   both+two       both ranks, two Earrings worn   x1 1/2 (never past vanilla's two pieces)
-- Measured: C's single and double bits at the battle's open ($3C45 / $3C44 bit 1, and the atlas bit, $3C44 bit 0),
-- and every RelicDmgEffect pass C makes ($11B0 at its entry and at its plp/rts): each pass must be what the bits say
-- (magic: +in/2 for the double, else +in/4 for the single; physical: +in/4 for the atlas bit), C's spell passes
-- must carry the case's multiplier, and the first spell pass's input must be the same in every case (so the
-- multiplier, not the spell, moved).  A ROM with the pre-#551 fold (one earring rung, never a second) fails
-- rank+earring, rank2+hero, both and both+two (build/attempts/wt/v048-earring/).
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local NAMES = { [0] = "TERRA", "LOCKE", "CYAN", "SHADOW", "EDGAR", "SABIN", "CELES", "STRAGO", "RELM",
  "SETZER", "MOG", "GAU" }
local LIVE = 0x317C00
local COSTS = { 10, 30, 75, 200, 500 }
local CMD_MAGIC = 0x02
local EARRINGS, HERO_RING, NONE = 0xC3, 0xC9, 0xFF
local LADDER = H.sym("Ot6LadderTbl") & 0x3FFFFF
local RELIC = H.sym("RelicDmgEffect")
local function rom(a) return emu.read(a, emu.memType.snesPrgRom) end
local function seated(c) local b = H.readByte(0x1850 + c); return b ~= 0 and (b & 7) == H.readByte(0x1A6D) end
local function hex(v) return string.format("$%02X", v) end

local C, SPELL                        -- the caster and the spell
local RUNG = {}                       -- the earring rungs: { slot, k, bytes4 }
local function stage(slot, n)
  local a = LIVE + 0x10 + (C * 26 + slot) * 2
  emu.write(a, n & 0xFF, emu.memType.snesMemory)
  emu.write(a + 1, n >> 8, emu.memType.snesMemory)
end
local function wear(r1, r2)
  emu.write(0x1600 + 37 * C + 0x23, r1, emu.memType.snesMemory)
  emu.write(0x1600 + 37 * C + 0x24, r2, emu.memType.snesMemory)
end

-- name, rank on RUNG[1] and RUNG[2], the two relic slots, the spell's multiplier (0, 1/4, 1/2 as 0, 4, 2)
local CASES = {
  { "none", false, false, NONE, NONE, 0 },
  { "earring", false, false, EARRINGS, NONE, 4 },
  { "rank", true, false, NONE, NONE, 4 },
  { "rank2", false, true, NONE, NONE, 4 },
  { "rank+earring", true, false, EARRINGS, NONE, 2 },
  { "rank2+hero", false, true, HERO_RING, NONE, 2 },
  { "both", true, true, NONE, NONE, 2 },
  { "both+two", true, true, EARRINGS, EARRINGS, 2 },
}

local snap
local A0, B0, A, B
local cur                             -- the case being recorded
local seatX                           -- C's battle index (seat * 2), this battle
local pend                            -- the RelicDmgEffect pass in flight

-- RelicDmgEffect (battle_main.asm): skipped when $11A4 bit 0; physical when $11A2 bit 0 (unless $11A3 bit 7);
-- physical: +1/4 for $3C44 bit 0 (atlas); magic: +1/2 for $3C44 bit 1 (double), else +1/4 for $3C45 bit 1 (single)
local function model(p)
  if p.a4 & 1 ~= 0 then return p.inv, "skipped" end
  local phys = (p.a3 & 0x80) == 0 and (p.a2 & 1) ~= 0
  local add, why = 0, nil
  if phys then
    if p.lo & 0x01 ~= 0 then add, why = p.inv >> 2, "physical, atlas" else why = "physical" end
  elseif p.lo & 0x02 ~= 0 then add, why = p.inv >> 1, "magic, double"
  elseif p.hi & 0x02 ~= 0 then add, why = p.inv >> 2, "magic, single"
  else why = "magic" end
  local out = p.inv + add
  if out > 0xFFFF then out = 0xFFFF end
  return out, why, phys
end

local function arm()
  local exit = RELIC + 0x3B
  H.assertEq(rom(exit & 0x3FFFFF) == 0x28 and rom((exit + 1) & 0x3FFFFF) == 0x60, true,
    string.format("RelicDmgEffect's plp/rts at %06X (its @0d85)", exit))
  emu.addMemoryCallback(function()
    if not cur or seatX == nil then return end
    local x = emu.getState()["cpu.x"] & 0xFF
    if x ~= seatX then pend = nil; return end
    pend = { inv = H.readWord(0x11B0), a2 = H.readByte(0x11A2), a3 = H.readByte(0x11A3), a4 = H.readByte(0x11A4),
      lo = H.readByte(0x3C44 + x), hi = H.readByte(0x3C45 + x), spell = H.readByte(0x3410) }
  end, emu.callbackType.exec, RELIC, RELIC)
  emu.addMemoryCallback(function()
    if not pend then return end
    local p = pend
    pend = nil
    p.out = H.readWord(0x11B0)
    local want, why, phys = model(p)
    p.want, p.why, p.phys = want, why, phys
    cur.passes[#cur.passes + 1] = p
  end, emu.callbackType.exec, exit, exit)
end

local function open(tag)
  return H.seqStep({
    H.driveUntil(function() return H.battleLoadStarted() end, 60000, {
      H.worldNavTo(function() return B[1] end, function() return B[2] end,
        { maxFrames = 3000, arrive = function() return H.battleLoadStarted() end }),
      H.call(function() A, B = B, A end),
    }, tag .. ": a random battle"),
    H.waitUntil(function() return H.battleActive() end, 1200, tag .. ": the battle is up", 1),
  })
end

local results = {}
local function branch(cs, restore)
  local name, r1, r2, s1, s2, mult = table.unpack(cs)
  local r = { name = name, mult = mult, passes = {} }
  r.atlas = s1 == HERO_RING or s2 == HERO_RING or (r2 and RUNG[2].b4 & 0x01 ~= 0) or (r1 and RUNG[1].b4 & 0x01 ~= 0)
  results[#results + 1] = r
  local steps = {}
  if restore then
    local req
    steps[#steps + 1] = H.call(function() H.setPad({}); req = H.requestLoadState(snap.blob) end)
    steps[#steps + 1] = H.waitFrames(2)
    steps[#steps + 1] = H.call(function() H.checkReq(req, "the snapshot on the map"); H.rearmInputInjection() end)
  end
  steps[#steps + 1] = H.call(function()
    A, B = A0, B0
    local q1, q2 = RUNG[1], RUNG[2]
    stage(q1.slot, COSTS[q1.k + 1] - (r1 and 0 or 1))
    stage(q2.slot, COSTS[q2.k + 1] - (r2 and 0 or 1))
    wear(s1, s2)
    H.log(string.format("[earring] %s: %s's counts %d on ladder slot %d and %d on slot %d; relics %s %s", name,
      NAMES[C], COSTS[q1.k + 1] - (r1 and 0 or 1), q1.slot, COSTS[q2.k + 1] - (r2 and 0 or 1), q2.slot, hex(s1),
      hex(s2)))
  end)
  steps[#steps + 1] = open(name)
  steps[#steps + 1] = H.call(function()
    seatX = nil
    for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == C then seatX = s * 2 end end
    H.assertEq(seatX ~= nil, true, name .. ": " .. NAMES[C] .. " is in the battle")
    r.lo, r.hi = H.readByte(0x3C44 + seatX), H.readByte(0x3C45 + seatX)
    H.log(string.format("[earring] %s: %s seat %d at the open: relic effects $3C44 %s, $3C45 %s (single %d, double "
      .. "%d, atlas %d)", name, NAMES[C], seatX // 2, hex(r.lo), hex(r.hi), (r.hi >> 1) & 1, (r.lo >> 1) & 1,
      r.lo & 1))
    cur = r
  end)
  steps[#steps + 1] = H.kitBattle({ { who = C, cmd = CMD_MAGIC, spell = SPELL, boost = 0 } }, { maxFrames = 60000 })
  steps[#steps + 1] = H.cond(function() return H.battleLoadStarted() end, { H.fightBattleByMenu(40000) }, {})
  steps[#steps + 1] = H.call(function() cur = nil; seatX = nil end)
  return H.seqStep(steps)
end

local function claims()
  local bad = 0
  local function claim(ok, what)
    H.log(string.format("[earring] %s %s", ok and "ok:" or "NOT:", what))
    if not ok then bad = bad + 1 end
  end
  local in0
  for _, r in ipairs(results) do
    local single, double, atlas = (r.hi >> 1) & 1, (r.lo >> 1) & 1, r.lo & 1
    local wantS, wantD = r.mult ~= 0 and 1 or 0, r.mult == 2 and 1 or 0
    claim(single == wantS and double == wantD, string.format("%s: single %d, double %d at the open (want %d, %d)",
      r.name, single, double, wantS, wantD))
    claim(atlas == (r.atlas and 1 or 0), string.format("%s: atlas bit %d at the open (want %d: a Hero Ring rung or "
      .. "a worn Hero Ring)", r.name, atlas, r.atlas and 1 or 0))
    local spells = 0
    for _, p in ipairs(r.passes) do
      H.log(string.format("[earring] %s: pass spell %s, $11A2 %s: in %d -> out %d (%s: want %d)", r.name,
        hex(p.spell), hex(p.a2), p.inv, p.out, p.why, p.want))
      claim(p.out == p.want, string.format("%s: the pass is what the bits say (%d -> %d, %s)", r.name, p.inv, p.out,
        p.why))
      if not p.phys and p.a4 & 1 == 0 and p.spell == SPELL then
        spells = spells + 1
        local want = r.mult == 0 and p.inv or (p.inv + (p.inv >> (r.mult == 4 and 2 or 1)))
        claim(p.out == want, string.format("%s: the spell's damage %d -> %d, x%s", r.name, p.inv, p.out,
          r.mult == 0 and "1" or (r.mult == 4 and "1 1/4" or "1 1/2")))
        if spells == 1 then
          if in0 == nil then in0 = p.inv end
          claim(p.inv == in0, string.format("%s: the first spell pass's input %d is the first case's %d", r.name,
            p.inv, in0))
        end
      end
      if p.phys then
        claim(p.out == p.inv + (atlas == 1 and (p.inv >> 2) or 0), string.format("%s: a Fight pass x%s, not doubled",
          r.name, atlas == 1 and "1 1/4" or "1"))
      end
    end
    claim(spells >= 1, string.format("%s: %s's spell made %d damage pass(es)", r.name, NAMES[C], spells))
  end
  H.assertEq(bad, 0, "every claim above holds")
end

H.run({ maxFrames = 900000 }, {
  H.bootCheckpoint("post-opera-v1"),
  H.call(function()
    for s = 0, 25 do
      for k = 0, 4 do
        local b4 = rom(LADDER + (s * 5 + k) * 14 + 4)
        if b4 & 0x02 ~= 0 then RUNG[#RUNG + 1] = { slot = s, k = k, b4 = b4 } end
      end
    end
    H.assertEq(#RUNG, 2, "two ladder rungs carry the earring bit (Maduin's Earrings, Bahamut's Hero Ring)")
    if RUNG[1].b4 & 0x01 ~= 0 then RUNG[1], RUNG[2] = RUNG[2], RUNG[1] end   -- the Hero Ring's second
    H.log(string.format("[earring] earring rungs: slot %d rung %d (+4 %s), slot %d rung %d (+4 %s)", RUNG[1].slot,
      RUNG[1].k + 1, hex(RUNG[1].b4), RUNG[2].slot, RUNG[2].k + 1, hex(RUNG[2].b4)))
    for c = 0, 11 do
      if C == nil and seated(c) then
        for _, sp in ipairs({ 0x00, 0x01, 0x02 }) do
          if C == nil and H.knowsSpell(c, sp) then C, SPELL = c, sp end
        end
      end
    end
    H.assertEq(C ~= nil, true, "precondition: a seated member who knows Fire, Ice or Bolt")
    H.log(string.format("[earring] C = %s, spell %s, relics %s %s", NAMES[C], hex(SPELL),
      hex(H.readByte(0x1600 + 37 * C + 0x23)), hex(H.readByte(0x1600 + 37 * C + 0x24))))
    local x, y = H.worldX(), H.worldY()
    local function plain(tx, ty) return (H.worldTileProp(tx, ty) & 0x50) == 0x40 end
    A0 = { x, y }
    for _, d in ipairs({ { -1, 0 }, { 0, -1 }, { 0, 1 }, { 1, 0 } }) do
      if B0 == nil and plain(x + d[1], y + d[2]) then B0 = { x + d[1], y + d[2] } end
    end
    H.assertEq(plain(x, y) and B0 ~= nil, true, "two plain tiles that roll random battles")
    arm()
  end),
  H.call(function() H.setPad({}); snap = H.requestSaveState() end),
  H.waitFrames(2),
  H.call(function() H.checkReq(snap, "the snapshot on the map") end),
  H.lazy(function()
    local steps = {}
    for i, cs in ipairs(CASES) do steps[#steps + 1] = branch(cs, i > 1) end
    return H.seqStep(steps)
  end),
  H.call(claims),
  H.logStep("[earring] PASS: an earring rank counts as one earring piece, up to vanilla's two-piece double"),
})
