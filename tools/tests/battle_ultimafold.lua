-- @suite slow
-- battle_ultimafold.lua -- Ultima is Fire's fourth fold for TERRA (#378).
--
-- kits.md: after a very late story unlock (event switch $00BF, set when
-- TERRA rejoins in the World of Ruin at Mobliz), TERRA casting Fire at 3 BP
-- folds past Fire 3 into Ultima (Ot6FoldSteps / Ot6FoldTier).  The fold is
-- the boost's purchase: the cast is priced as Ultima (its own 80 MP) and
-- takes no damage multiplier (Ot6QueueFold marks it, OT6_ULTIMAFOLD, and
-- Ot6BoostLevel answers 0 for it).  Before the unlock, Fire at 3 BP is Fire
-- 3, as for everyone.
--
-- Played: Continue fc-alcove-v1 (TERRA L26 knows Fire and Drain), walk onto
-- the continent into a random battle, and cast through the real menu
-- (H.kitBattle); everyone else Defends.  Each cast in whatever battle is
-- up: one where TERRA cannot cast (this map's Apokryphos mutes) is fought
-- out and the next taken, and a cast cut off or charged no MP is played
-- again.  In order:
--   1. Drain at 1 BP -- the control for the multiplier watch: a spell
--      outside the tier families is multiplied, and the watch sees
--      Ot6BoostDmg write $11b0;
--   2. Fire at 3 BP, the switch clear: the list prices Fire at Fire 3's 51,
--      the cast is Fire 3 ($09) and costs 51;
--   3. the switch set (one declared write, tools/state_write_waivers.txt:
--      the unlock is World of Ruin story the route does not reach), then
--      Fire at 3 BP: the list prices Fire at Ultima's 80, the cast is Ultima
--      ($14) and costs 80, and Ot6BoostDmg writes no $11b0 for it.
-- Old-ROM red and mutants: build/attempts/wt/v027-kits/ultimafold/.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, CMD_MAGIC = 0x00, 0x02
local FIRE, FIRE3, DRAIN, ULTIMA = 0x00, 0x09, 0x04, 0x14
local SPELL_PTR = { [0] = 0x0000, [1] = 0x013C, [2] = 0x0278, [3] = 0x03B4 }
local SW = 0x1E80 + (0xBF >> 3)
local SWBIT = 1 << (0xBF & 7)

local seat, recs, rec = nil, {}, nil
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
    if H.readByte(0x3ED8 + e) ~= TERRA then return end
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

local listCost = {}
-- the casts, in order; each in whatever battle is up (a battle that ends
-- before a cast resolves, or one where TERRA cannot cast -- this map's
-- Apokryphos mutes -- is fought out and the next one taken; a cast that
-- charged no MP is not counted and is played again)
local CASTS = {
  { spell = DRAIN, boost = 1, tag = "drain" },
  { spell = FIRE, boost = 3, tag = "fire3" },
  { spell = FIRE, boost = 3, tag = "ultima" },
}
local nDone, turns, mode, nrec = 0, 0, nil, 0
local plan = {}
local proxy = setmetatable({}, { __index = function(_, i) return plan[i] end, __len = function() return #plan end })
local function terraCasts()
  local e = seat * 2
  return H.readWord(0x3BF4 + e) > 0 and (H.readByte(0x3EE4 + e) & 0xE2) == 0
    and (H.readByte(0x3EE5 + e) & 0xB8) == 0
end
local function checkCast(i, r)
  if i == 1 then
    H.assertEq(r.spell == DRAIN and r.pend == 1, true, "cast 1 was Drain at 1 BP")
    H.assertEq(r.writes >= 1, true, "the watch sees Ot6BoostDmg multiply a boosted Drain (the control)")
  elseif i == 2 then
    H.log(string.format("[ultima] the list priced Fire at %s with 3 BP pending, the switch clear",
      tostring(listCost.fire3)))
    H.assertEq(listCost.fire3, 51, "the list prices a 3-BP Fire at Fire 3's 51")
    H.assertEq(r.spell, FIRE3, "a 3-BP Fire before the unlock casts Fire 3 ($09)")
    H.assertEq(r.mp0 - r.mp1, 51, "and costs Fire 3's 51")
    H.writeByte(SW, H.readByte(SW) | SWBIT)
    H.log("[ultima] switch $00BF set (declared expedient: TERRA's World of Ruin return)")
  else
    H.log(string.format("[ultima] the list priced Fire at %s with 3 BP pending, the switch set",
      tostring(listCost.ultima)))
    H.assertEq(listCost.ultima, 80, "the list prices a 3-BP Fire at Ultima's 80")
    H.assertEq(r.spell, ULTIMA, "a 3-BP Fire after the unlock casts Ultima ($14)")
    H.assertEq(r.mp0 - r.mp1, 80, "and costs Ultima's 80")
    H.assertEq(r.writes, 0, "the folded Ultima takes no damage multiplier (Ot6BoostDmg wrote no $11b0)")
  end
end

H.run({ maxFrames = 600000 }, {
  H.bootCheckpoint("fc-alcove-v1"),
  H.call(function()
    arm()
    H.assertEq(H.readByte(SW) & SWBIT, 0, "switch $00BF is clear at the alcove (TERRA has not rejoined in the WoR)")
  end),
  H.fcAlcoveToBattle("ultima"),
  H.driveUntil(function() return nDone == #CASTS end, 500000, {
    H.cond(function() return not H.battleLoadStarted() end, { H.fcPace("ultima") }, {}),
    H.call(function()
      turns = turns + 1
      H.assertEq(turns <= 12, true, "the three casts within 12 tries")
      seat = nil
      for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == TERRA then seat = s end end
      H.assertEq(seat ~= nil, true, "TERRA is seated")
      nrec, plan, mode = #recs, {}, "cast"
      if not terraCasts() then
        mode = "fightout"
        H.log(string.format("[ultima] TERRA cannot cast here (status %02X %02X): this battle is fought out",
          H.readByte(0x3EE4 + seat * 2), H.readByte(0x3EE5 + seat * 2)))
        return
      end
      local c = CASTS[nDone + 1]
      H.log(string.format("[ultima] cast %d: $%02X at %d BP; TERRA seat %d, MP %d, bank %d", nDone + 1, c.spell,
        c.boost, seat, mp(), H.readByte(0x3E9C + seat * 2)))
      plan = { { who = TERRA, cmd = CMD_MAGIC, spell = c.spell, boost = c.boost } }
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
    H.log("[ultima] PASS: Fire 3 before the unlock, Ultima after it, priced 80, unmultiplied")
  end),
})
