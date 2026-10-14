-- @suite slow
-- battle_ultimafold.lua -- Ultima is Fire's fourth fold for TERRA (#378).
--
-- kits.md: after a very late story unlock (event switch $00BF, set when
-- TERRA rejoins in the World of Ruin at Mobliz), TERRA casting Fire at 3 BP
-- folds past Fire 3 into Ultima (Ot6FoldSteps / Ot6FoldTier).  The fold is
-- the boost's purchase: the cast is priced as Ultima (its own 80 MP) and
-- takes no damage multiplier (Ot6QueueFold marks it, OT6_ULTIMAFOLD, and
-- Ot6BoostLevel answers 0 for it).  The unlock is TERRA's: anyone else's
-- Fire at 3 BP is Fire 3.
--
-- Played: Continue the wor-terra-v1 battery, the save the route makes as
-- TERRA rejoins at Mobliz (gen_wor_terra: the play sets $00BF; nothing
-- here writes it, #424), pace two World of Ruin tiles into a random battle,
-- and cast through the real menu (H.kitBattle); everyone else Defends.
-- Each cast in whatever battle is up: one where its caster cannot cast is
-- fought out and the next taken, and a cast cut off or charged no MP is
-- played again.  In order:
--   1. TERRA's Drain at 1 BP -- the control for the multiplier watch: a
--      spell outside the tier families is multiplied, and the watch sees
--      Ot6BoostDmg write $11b0;
--   2. CELES's Fire at 3 BP -- the control for the unlock: the list prices
--      her Fire at Fire 3's 51, the cast is Fire 3 ($09) and costs 51;
--   3. TERRA's Fire at 3 BP: the list prices Fire at Ultima's 80, the cast
--      is Ultima ($14) and costs 80, and Ot6BoostDmg writes no $11b0 for it.
-- Old-ROM red and mutants: build/attempts/wt/v027-kits/final-matrix/
-- (<rom>__battle_ultimafold.out, from the alcove), and for this boot
-- build/attempts/wt/v031-cleanup/ (#424).
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, CELES, CMD_MAGIC = 0x00, 0x06, 0x02
local FIRE, FIRE3, DRAIN, ULTIMA = 0x00, 0x09, 0x04, 0x14
local SPELL_PTR = { [0] = 0x0000, [1] = 0x013C, [2] = 0x0278, [3] = 0x03B4 }
local SW = 0x1E80 + (0xBF >> 3)
local SWBIT = 1 << (0xBF & 7)

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
  H.log(string.format("[ultima] cast %d: spell $%02X at %d BP (f%d), MP %d -> %d, Ot6BoostDmg $11b0 writes %d",
    #recs, rec.spell, rec.pend, rec.f, rec.mp0, rec.mp1, rec.writes))
  rec = nil
  return true
end

-- the world map's entrance tiles (ShortEntrancePtrs / LongEntrancePtrs,
-- route_data.py's reading): a pace must not step onto one (wor-terra-v1's
-- save stands beside Mobliz's door)
local function entranceSet(m)
  local set = {}
  -- (literal names: compose.py collects the H.sym strings it can see)
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
-- the casts, in order; each in whatever battle is up (a battle that ends
-- before a cast resolves, or one where the caster cannot cast, is fought
-- out and the next one taken; a cast that charged no MP is not counted and
-- is played again)
local CASTS = {
  { who = TERRA, spell = DRAIN, boost = 1, tag = "drain" },
  { who = CELES, spell = FIRE, boost = 3, tag = "fire3" },
  { who = TERRA, spell = FIRE, boost = 3, tag = "ultima" },
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
    H.assertEq(r.spell == DRAIN and r.pend == 1, true, "cast 1 was TERRA's Drain at 1 BP")
    H.assertEq(r.writes >= 1, true, "the watch sees Ot6BoostDmg multiply a boosted Drain (the control)")
  elseif i == 2 then
    H.log(string.format("[ultima] the list priced CELES's Fire at %s with 3 BP pending", tostring(listCost.fire3)))
    H.assertEq(listCost.fire3, 51, "the list prices CELES's 3-BP Fire at Fire 3's 51")
    H.assertEq(r.spell, FIRE3, "CELES's 3-BP Fire casts Fire 3 ($09): the unlock is TERRA's alone")
    H.assertEq(r.mp0 - r.mp1, 51, "and costs Fire 3's 51")
  else
    H.log(string.format("[ultima] the list priced TERRA's Fire at %s with 3 BP pending", tostring(listCost.ultima)))
    H.assertEq(listCost.ultima, 80, "the list prices TERRA's 3-BP Fire at Ultima's 80")
    H.assertEq(r.spell, ULTIMA, "TERRA's 3-BP Fire after the unlock casts Ultima ($14)")
    H.assertEq(r.mp0 - r.mp1, 80, "and costs Ultima's 80")
    H.assertEq(r.writes, 0, "the folded Ultima takes no damage multiplier (Ot6BoostDmg wrote no $11b0)")
  end
end

H.run({ maxFrames = 600000 }, {
  H.bootCheckpoint("wor-terra-v1"),
  H.call(function()
    arm()
    H.assertEq(H.readByte(SW) & SWBIT, SWBIT, "switch $00BF is set: the play brought TERRA back at Mobliz")
  end),
  H.driveUntil(function() return nDone == #CASTS end, 500000, {
    H.cond(function() return not H.battleLoadStarted() end, { worldBattle("ultima") }, {}),
    H.call(function()
      turns = turns + 1
      H.assertEq(turns <= 12, true, "the three casts within 12 tries")
      local c = CASTS[nDone + 1]
      seat, who = nil, c.who
      for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == c.who then seat = s end end
      H.assertEq(seat ~= nil, true, string.format("character $%02X is seated", c.who))
      nrec, plan, mode = #recs, {}, "cast"
      if not canCast() then
        mode = "fightout"
        H.log(string.format("[ultima] $%02X cannot cast here (status %02X %02X): this battle is fought out", c.who,
          H.readByte(0x3EE4 + seat * 2), H.readByte(0x3EE5 + seat * 2)))
        return
      end
      H.log(string.format("[ultima] cast %d: $%02X's $%02X at %d BP; seat %d, MP %d, bank %d", nDone + 1, c.who,
        c.spell, c.boost, seat, mp(), H.readByte(0x3E9C + seat * 2)))
      plan = { { who = c.who, cmd = CMD_MAGIC, spell = c.spell, boost = c.boost } }
    end),
    H.cond(function() return mode == "fightout" end, { H.kitBattle({}, {}) }, {
      H.kitBattle(proxy, { untilPlanDone = true, idle = "defend", maxFrames = 60000,
        onList = function() local c = CASTS[nDone + 1]; listCost[c.tag] = costOf(c.spell) end,
        planDone = function() return close() end }),
      H.call(function()
        if #recs == nrec then H.log("[ultima] the battle ended before the cast resolved: not counted"); return end
        local r = recs[#recs]
        if r.mp0 == r.mp1 then H.log("[ultima] the cast charged no MP (it did not resolve): not counted"); return end
        checkCast(nDone + 1, r)
        nDone = nDone + 1
      end),
    }),
  }, "the three casts"),
  H.call(function()
    H.log("[ultima] PASS: with $00BF set by play, CELES's 3-BP Fire is Fire 3 and TERRA's is Ultima, priced 80, "
      .. "unmultiplied")
  end),
})
