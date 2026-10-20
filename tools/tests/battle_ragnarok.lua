-- @suite slow
-- battle_ragnarok.lua -- Ragnarok's Ultima is a multiplier spell (#447).
--
-- kits.md, Terra: "everyone else gets Ultima by equipping Ragnarok, and
-- that Ultima is a multiplier spell like any other"; TERRA's own Ultima is
-- her Fire's fourth fold, which takes no multiplier (battle_ultimafold).
-- Both cast spell $14; Ot6BoostLevel tells them apart by the fold's mark
-- (OT6_ULTIMAFOLD, set by Ot6QueueFold), so "an Ultima cast from a
-- Ragnarok's list keeps it".  The route reaches the stone for the first
-- time in #447 (gen_wor_ragnarok: the weapon shop's back room, taken as the
-- stone, onto the seated member other than TERRA with the most magic; the
-- test finds that wearer in the save's own party record).
--
-- Played: Continue the wor-ragnarok-v1 battery (the play's save outside
-- Narshe, one member wearing Ragnarok: nothing here writes it), pace two World of
-- Ruin tiles into a random battle, and cast through the real menu
-- (H.kitBattle); everyone else Defends.  Each cast in whatever battle is
-- up: one where its caster cannot cast is fought out and the next taken,
-- and a cast cut off or charged no MP is played again.  In order:
--   1. TERRA's Fire at 3 BP -- the control: the fold, Ultima ($14) priced
--      80, and Ot6BoostDmg writes no $11b0 for it;
--   2. the wearer's Ultima at 1 BP -- from Ragnarok's list: it holds no tier, so
--      the boost buys the multiplier and prices it as any boosted spell
--      (Ot6BoostPriceFor: 80 x 5 / 2 past the two-digit ceiling, 99); cast
--      as Ultima ($14), costs 99, and Ot6BoostDmg writes $11b0 for it.
-- Mutants (build/attempts/wt/v032-narshe-locke-3/lab/rk2_mut{A,B,C}, patched
-- by mkmut.py beside them; the first round is build/attempts/wt/
-- v032-narshe-locke/lab/rm_mut{A,B}, ROMs patched by hand): Ot6BoostLevel
-- answering 0 for every Ultima (A) turns cast 2 red; Ragnarok's list
-- without Ultima (B) turns the list red; every Ultima multiplied (C) turns
-- the control, cast 1, red.  Draws: lab/rk2_k*_s* (K = 0-5 world-map
-- battles fought first, seed shifts 0 and 7: 12 runs; the first sweep,
-- lab/rk_k*_s*, was K = 0-4: 10 runs, one red, rk_k4_s7).  The same 12 with
-- the [key] line: round2/lab/r3_*, 11 distinct battle keys (round2/keys.txt).
-- The red one, restored where RELM lay dead on the world map (round2/snap/):
-- the care revives her ($F0) and both casts resolve.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, CMD_MAGIC = 0x00, 0x02
local FIRE, ULTIMA = 0x00, 0x14
local RAGNAROK = 16
local SPELL_PTR = { [0] = 0x0000, [1] = 0x013C, [2] = 0x0278, [3] = 0x03B4 }

local seat, who, recs, rec = nil, nil, {}, nil
local function mp() return H.readWord(0x3C08 + seat * 2) end
local function costOf(id)
  for i = 0, 53 do
    local at = 0x2092 + SPELL_PTR[seat] + i * 4
    if H.readByte(at) == id then return H.readByte(at + 3) end
  end
end

-- the multiplier watch: $11b0 written from inside Ot6BoostDmg (its @store)
local BD = H.sym("Ot6BoostDmg")
local inBD = 0
local function arm()
  -- the key of every battle (reads only): $be at the open plus the formation,
  -- so a sweep's distinct draws can be counted (TESTING.md, "Tests that survive any draw")
  local seedAt = H.seedStoreAddr()
  emu.addMemoryCallback(function()
    H.log(string.format("[key] battle key be%02X-g%04X f%d map %d", emu.getState()["cpu.a"] & 0xff,
      H.readWord(0x11e0), H.frame, H.worldId()))
  end, emu.callbackType.exec, seedAt, seedAt)
  emu.addMemoryCallback(function(_, v)
    if seat == nil or rec ~= nil then return end
    if H.readByte(0x3A7C) ~= CMD_MAGIC or H.readByte(0x3A7D) ~= v then return end
    local e = seat * 2
    if H.readByte(0x3ED8 + e) ~= who then return end
    rec = { spell = v, pend = H.readByte(0x3E9D + e), mp0 = mp(), f = H.frame }
    inBD = 0
  end, emu.callbackType.write, 0x7E3410, 0x7E3410)
  emu.addMemoryCallback(function()
    if rec == nil then return end
    local s = emu.getState()
    local pc = (s["cpu.k"] << 16) | s["cpu.pc"]
    if pc >= BD and pc < BD + 0xC0 then inBD = inBD + 1 end
  end, emu.callbackType.write, 0x7E11B0, 0x7E11B1)
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    if rec == nil or rec.ended or seat == nil then return end
    if (emu.getState()["cpu.x"] & 0xff) == seat * 2 then rec.ended = H.frame end
  end, emu.callbackType.exec, ae, ae)
end
local function close()
  if rec == nil or not rec.ended or H.frame <= rec.ended + 1 then return false end
  rec.mp1, rec.writes = mp(), inBD
  recs[#recs + 1] = rec
  H.log(string.format("[ragnarok] cast %d: spell $%02X at %d BP (f%d), MP %d -> %d, Ot6BoostDmg $11b0 writes %d",
    #recs, rec.spell, rec.pend, rec.f, rec.mp0, rec.mp1, rec.writes))
  rec = nil
  return true
end

-- the world map's entrance tiles (battle_ultimafold's reading): a pace
-- must not step onto one (the save stands south of Narshe's gate)
local function entranceSet(m)
  local set = {}
  for _, t in ipairs({ { H.sym("ShortEntrancePtrs"), 6, false }, { H.sym("LongEntrancePtrs"), 7, true } }) do
    local base = t[1] & 0x3FFFFF
    local function w(o) return H.readRomByte(base + o) | (H.readRomByte(base + o + 1) << 8) end
    for o = w(m * 2), w(m * 2 + 2) - 1, t[2] do
      local x, y = H.readRomByte(base + o), H.readRomByte(base + o + 1)
      local len = t[3] and (H.readRomByte(base + o + 2) & 0x7F) or 0
      local vert = t[3] and (H.readRomByte(base + o + 2) & 0x80) ~= 0
      for i = 0, len do set[(vert and x or x + i) .. "," .. (vert and y + i or y)] = true end
    end
  end
  return set
end

-- two world tiles, paced until a random battle loads
local function worldBattle(tag)
  local A, B
  return H.seqStep({
    H.waitUntil(function() return H.worldSettled() end, 3000, tag .. ": the world map, settled", 5),
    -- a fight can leave the caster down (a K-battle history met one that
    -- struck first: build/attempts/wt/v032-narshe-locke-3/lab/rk_k4_s7);
    -- a person revives before the next try, and fieldCare does
    H.fieldCare({ tag = tag .. ": care before the pace", threshold = 0.95 }),
    H.call(function()
      local x, y = H.worldX(), H.worldY()
      local doors = entranceSet(H.worldId())
      A, B = { x, y }, nil
      for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 2, 0 }, { -2, 0 }, { 0, 2 }, { 0, -2 } }) do
        local bx, by = x + d[1], y + d[2]
        if B == nil and H.worldPassable(bx, by) and not doors[bx .. "," .. by] then B = { bx, by } end
      end
      H.assertEq(B ~= nil, true, string.format("%s: a passable world tile beside (%d,%d)", tag, x, y))
      H.log(string.format("[%s] pacing world (%d,%d) <-> (%d,%d)", tag, A[1], A[2], B[1], B[2]))
    end),
    H.driveUntil(function() return H.battleLoadStarted() end, 60000, {
      H.worldNavTo(function() return B[1] end, function() return B[2] end,
        { maxFrames = 4000, arrive = function() return H.battleLoadStarted() end }),
      H.call(function() A, B = B, A end),
    }, tag .. ": a random battle on the world map"),
    H.waitUntil(function() return H.battleActive() end, 1200, tag .. ": the battle is up", 2),
    H.waitFrames(30),
  })
end

local listCost = {}
local CASTS = {
  { who = TERRA, spell = FIRE, boost = 3, tag = "fold" },
  { who = nil, spell = ULTIMA, boost = 1, tag = "ragnarok" }, -- who: Ragnarok's wearer, found at boot
}
local nDone, turns, mode, nrec = 0, 0, nil, 0
local plan = {}
local proxy = setmetatable({}, { __index = function(_, i) return plan[i] end, __len = function() return #plan end })
local function canCast()
  local e = seat * 2
  return H.readWord(0x3BF4 + e) > 0 and (H.readByte(0x3EE4 + e) & 0xE2) == 0
    and (H.readByte(0x3EE5 + e) & 0xB8) == 0
end
local function checkCast(i, r)
  if i == 1 then
    H.log(string.format("[ragnarok] the list priced TERRA's Fire at %s with 3 BP pending", tostring(listCost.fold)))
    H.assertEq(listCost.fold, 80, "the list prices TERRA's 3-BP Fire at Ultima's 80 (the fold)")
    H.assertEq(r.spell, ULTIMA, "TERRA's 3-BP Fire casts Ultima ($14)")
    H.assertEq(r.writes, 0, "the folded Ultima takes no multiplier (the control: Ot6BoostDmg wrote no $11b0)")
  else
    H.log(string.format("[ragnarok] the list priced $%02X's Ultima at %s with 1 BP pending", who,
      tostring(listCost.ragnarok)))
    H.assertEq(listCost.ragnarok, 99, "the wearer's list holds Ultima from Ragnarok, priced 99 at 1 BP (80 "
      .. "boosted, at the ceiling)")
    H.assertEq(r.spell == ULTIMA and r.pend == 1, true, "cast 2 was the wearer's Ultima at 1 BP")
    H.assertEq(r.mp0 - r.mp1, 99, "and costs the list's 99")
    H.assertEq(r.writes >= 1, true, "Ragnarok's Ultima takes the multiplier (Ot6BoostDmg wrote $11b0)")
  end
end

H.run({ maxFrames = 600000 }, {
  H.bootCheckpoint("wor-ragnarok-v1"),
  H.call(function()
    arm()
    local wearers = {}
    for ch = 0, 15 do
      if H.readByte(0x1600 + 37 * ch + 0x1E) == RAGNAROK then wearers[#wearers + 1] = ch end
    end
    H.assertEq(#wearers, 1, "exactly one character wears Ragnarok: the play put it on one")
    H.assertEq(wearers[1] ~= TERRA, true, "Ragnarok's wearer is not TERRA (her Ultima is the fold's)")
    CASTS[2].who = wearers[1]
    H.log(string.format("[ragnarok] Ragnarok's wearer: character $%02X", wearers[1]))
    H.assertEq(H.readByte(0x1E80 + (0xBF >> 3)) & (1 << (0xBF & 7)) ~= 0, true,
      "switch $00BF is set: TERRA's fold is unlocked (the control)")
  end),
  H.driveUntil(function() return nDone == #CASTS end, 500000, {
    H.cond(function() return not H.battleLoadStarted() end, { worldBattle("ragnarok") }, {}),
    H.call(function()
      turns = turns + 1
      H.assertEq(turns <= 12, true, "the two casts within 12 tries")
      local c = CASTS[nDone + 1]
      seat, who = nil, c.who
      for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == c.who then seat = s end end
      H.assertEq(seat ~= nil, true, string.format("character $%02X is seated", c.who))
      nrec, plan, mode = #recs, {}, "cast"
      if not canCast() then
        mode = "fightout"
        H.log(string.format("[ragnarok] $%02X cannot cast here (status %02X %02X): this battle is fought out", c.who,
          H.readByte(0x3EE4 + seat * 2), H.readByte(0x3EE5 + seat * 2)))
        return
      end
      H.log(string.format("[ragnarok] cast %d: $%02X's $%02X at %d BP; seat %d, MP %d, bank %d", nDone + 1, c.who,
        c.spell, c.boost, seat, mp(), H.readByte(0x3E9C + seat * 2)))
      plan = { { who = c.who, cmd = CMD_MAGIC, spell = c.spell, boost = c.boost } }
    end),
    H.cond(function() return mode == "fightout" end, { H.kitBattle({}, {}) }, {
      H.kitBattle(proxy, { untilPlanDone = true, idle = "defend", maxFrames = 60000,
        onList = function() local c = CASTS[nDone + 1]; listCost[c.tag] = costOf(c.spell) end,
        planDone = function() return close() end }),
      H.call(function()
        if #recs == nrec then H.log("[ragnarok] the battle ended before the cast resolved: not counted"); return end
        local r = recs[#recs]
        if r.mp0 == r.mp1 then H.log("[ragnarok] the cast charged no MP (it did not resolve): not counted"); return end
        checkCast(nDone + 1, r)
        nDone = nDone + 1
      end),
    }),
  }, "the two casts"),
  H.call(function()
    H.log("[ragnarok] PASS: TERRA's folded Ultima is unmultiplied and the wearer's Ultima from Ragnarok, boosted, is "
      .. "multiplied")
  end),
})
