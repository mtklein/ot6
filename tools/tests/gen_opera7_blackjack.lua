-- gen_opera7_blackjack.lua -- v0.5 terminal step: ultros2_entry -> defeat
-- Ultros 2 -> ride the Setzer/coin-toss/Blackjack sequence -> generate
-- blackjack.

-- The terminal is the first stable, controllable world-map frame after the
-- Blackjack lands outside Vector.  Source (_cac128 -> _cb2007 -> _cb2379)
-- gives the durable story invariants:
--   $034B=0  Ultros 2 NPC / Opera battle gate cleared
--   $005D=1  Setzer accepted the party's bargain
--   $005E=1  the Blackjack arrival sequence completed
--   $0246=0  the active airship is the Blackjack (not the Falcon)
-- The world load is map 0 at {140,203}; the parked airship is {137,202}.

local H = dofile("tools/tests/lib/ot6.lua")
local DOOR = "build/states/ultros2_entry.mss.lua"

local ULTROS2 = 0x012d
local aPhase = 0

local function sw(id)
  return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1
end
local function map() return H.mapId() & 0x1FF end

local function pulseAdvance()
  aPhase = (aPhase + 1) % 8
  H.setPad(aPhase < 4 and { "a", "start" } or {})
end

-- ------------------------------------------------------- CELES's kit back --
-- The opera takes CELES's gear off and gives it to the bag: the performance
-- intro runs `remove_equip CELES` beside `char_party CELES, 7`
-- (event_main.asm:27273, and :27785 on the other fork).  Nothing in the
-- chain ever put it back, so she rejoined for the Blackjack with all five
-- equipment bytes at $FF and walked into Vector that way -- the class of
-- fixture bug tools/audit_equipment.py exists to catch.

local EMPTY = 0xFF
local CH_CELES = 6
local function gear(c, off) return H.readByte(0x1600 + 37 * c + off) end
local function ordOf(c) return (H.readByte(0x1850 + c) >> 3) & 0x03 end

-- Fill one empty gear slot from the bag.  Both guards matter, for
-- gen_tunnelarmr's fillSlot reasons: H.equipWeapon's list seek walks the
-- menu's pre-filtered rows, so an item the bag does not hold makes it time
-- out rather than fail cleanly, and a slot that already holds something
-- does not want overwriting.  Slot n's byte is +$1F+n (R-Hand, L-Hand,
-- Helmet, Armor, Relic 1, Relic 2; ff6/notes/field-ram.txt:905-923).
local function fill(c, pos, slot, id, tag)
  return H.cond(function()
    return gear(c, 0x1F + slot) == EMPTY and H.invCountOf(id) > 0
  end, { H.equipWeapon(pos, id, { slot = slot, tag = tag }) }, {})
end

local BCHID, BCHP, BCMAXHP = 0x3ed8, 0x3bf4, 0x3c1c
local MENU, ACTOR = 0x7bca, 0x62ca
local BP = 0x3e9c
local function monSpecies(i) return H.readWord(0x57c0 + i * 2) end
local function monHp(i) return H.readWord(0x3bfc + i * 2) end
local function monShields(i) return H.readByte(0x3e40 + i * 2) end
local function monPresent(i) return H.readByte(0x3aa8 + i * 2) % 2 == 1 end
local function partyLine()
  local p = {}
  for e = 0, 3 do
    p[#p + 1] = string.format("%d/%d", H.readWord(BCHP + e * 2),
      H.readWord(BCMAXHP + e * 2))
  end
  return table.concat(p, " ")
end
local function monsterLine()
  local m = {}
  for i = 0, 5 do
    if monPresent(i) then
      m[#m + 1] = string.format("$%04X hp=%d sh=%d", monSpecies(i),
        monHp(i), monShields(i))
    end
  end
  return table.concat(m, " | ")
end
local function seqFor(id, tier, slot)
  local bp = H.readByte(BP + slot * 2)
  local boost = bp >= 2 and math.min(bp, 3) or 0
  local seq = {}
  for _ = 1, boost do seq[#seq + 1] = "r" end
  local function push(...)
    for _, b in ipairs({ ... }) do seq[#seq + 1] = b end
    return seq
  end
  if id == 4 and tier >= 2 then
    return push("down", "a", "a", "a")                        -- AutoCrossbow
  end
  if id == 5 and tier >= 3 then
    return push("down", "a", "a", "a")                        -- Pummel
  end
  return push("a", "a")                                       -- Fight
end
local function mkFighter(tier, tag)
  local F = { lost = nil }
  local bt = nil
  local mStreak, mSeq, mIdx, mTick, mStall = 0, nil, 1, 0, 0
  local phase = 0
  function F.frame(battN)
    phase = (phase + 1) % 8
    if battN == 3 then
      bt = { f0 = H.frame, wiped = 0 }
      local w = H.formationWords()
      H.log(string.format("[%s] battle up f%d (%04X %04X %04X %04X %04X %04X)",
        tag, H.frame, w[1], w[2], w[3], w[4], w[5], w[6]))
    end
    if bt then
      bt.lastParty = partyLine()
      if battN % 300 == 0 then
        H.log(string.format("[%s] f%d party [%s] vs %s",
          tag, H.frame, partyLine(), monsterLine()))
      end
      local wiped, any = true, false
      for e = 0, 3 do
        if H.readWord(BCMAXHP + e * 2) > 0 then
          any = true
          if H.readWord(BCHP + e * 2) > 0 then wiped = false end
        end
      end
      bt.wiped = (any and wiped) and bt.wiped + 1 or 0
      if bt.wiped >= 90 and not F.lost then
        F.lost = string.format("PARTY WIPED at f%d (started f%d, %d frames " ..
          "in, tier %d) -- party [%s] vs %s", H.frame, bt.f0,
          H.frame - bt.f0, tier, partyLine(), monsterLine())
        H.log("[" .. tag .. "] " .. F.lost)
      end
    end
    if bt == nil or H.readByte(MENU) == 0 then
      mStreak, mSeq = 0, nil
      H.setPad(phase < 4 and { "a" } or {})
      return
    end
    mStreak = mStreak + 1
    if mStreak < 4 then H.setPad({}); return end
    if mSeq == nil then
      local slot = H.readByte(ACTOR) & 3
      local id = H.readByte(BCHID + slot * 2)
      mSeq, mIdx, mTick, mStall = seqFor(id, tier, slot), 1, 0, 0
      H.log(string.format("[%s] cast f%d slot=%d char=%d bp=%d seq=%s",
        tag, H.frame, slot, id, H.readByte(BP + slot * 2),
        table.concat(mSeq, ",")))
    end
    mTick = mTick + 1
    local ph = mTick % 30
    local btn
    if mIdx <= #mSeq then
      btn = mSeq[mIdx]
    elseif mStall < 2 then
      btn = "a"
    elseif mStall < 4 then
      btn = "b"
    else
      mSeq = nil
      H.setPad({})
      return
    end
    if ph < 6 then H.setPad({ [btn] = true }) else H.setPad({}) end
    if ph == 29 then
      if mIdx <= #mSeq then mIdx = mIdx + 1 else mStall = mStall + 1 end
    end
  end
  function F.idle()
    if bt then
      H.log(string.format("[%s] battle done at f%d (%d frames) -- party [%s]",
        tag, H.frame, H.frame - bt.f0, bt.lastParty or "?"))
      bt = nil
    end
    mStreak, mSeq = 0, nil
  end
  return F
end

-- ------------------------------------------------------ the fight ladder --
local u2Blob, u2Won = nil, false
local u2Lost = nil
local function fightBody(tier)
  local F = mkFighter(tier, "ultros2")
  local battN, postN = 0, 0
  return H.driveUntil(function()
    if F.lost then
      u2Lost = F.lost
      return true                       -- reload beats riding the fail path
    end
    if battN > 0 or H.battleLoadStarted() then return false end
    -- the event's own fork: the win branch (_cac128) clears $034B almost
    -- immediately; the loss branch does not.  Give it 1200 post-battle
    -- frames to show.
    if sw(0x034B) == 0 then return true end
    postN = postN + 1
    if postN >= 1200 then
      u2Lost = u2Lost or string.format("battle 104 ended at f%d (tier %d) " ..
        "with $034B still set -- the loss branch (_cabdba) is running",
        H.frame, tier)
      return true
    end
    return false
  end, 90000, {
    H.call(function()
      battN = H.battleLoadStarted() and battN + 1 or 0
      if battN >= 3 then
        postN = 0
        if battN == 150 then
          H.assertEq(H.formationHas({ [ULTROS2] = true }), true,
            "battle 104 contains Ultros 2 ($012d)")
          H.screenshot("ultros2_engaged")
        end
        F.frame(battN)
        return
      end
      F.idle()
      pulseAdvance()
    end),
  }, "Ultros 2, played (tier " .. tier .. ")")
end
local function attempt(n)
  local ldReq
  return H.cond(function() return not u2Won end, {
    H.cond(function() return n > 1 end, {
      H.logStep(function()
        return string.format("[ultros2] ATTEMPT %d -- reloading the " ..
          "entry point after a loss (%s)", n, tostring(u2Lost))
      end),
      H.call(function() ldReq = H.requestLoadState(u2Blob) end),
      H.waitFrames(2),
      H.call(function() H.checkReq(ldReq, "ultros2 attempt " .. n) end),
      H.waitFrames(60),
    }, {}),
    H.call(function() u2Lost = nil end),
    -- the entry-point contract is one advance from the WoB story battle 104
    H.driveUntil(function() return H.battleLoadStarted() end, 20000, {
      H.call(pulseAdvance),
    }, "enter Ultros 2"),
    H.waitUntil(function() return H.battleActive() end, 4000,
      "Ultros 2 active", 10),
    fightBody(n),
    H.call(function()
      if u2Lost == nil then
        u2Won = true
        H.log(string.format("[ultros2] attempt %d WON battle 104 " ..
          "at f%d", n, H.frame))
        H.screenshot("ultros2_won_played")
      end
    end),
  }, {})
end

-- Budget: the battle-clear-write era ran in 90k frames; the input-driven
-- fight costs real ATB rounds and the ladder may replay it three times.
H.run({ maxFrames = 400000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(sw(0x034B), 1, "$034B set -- Ultros 2 present before battle")
    H.assertEq(sw(0x005D), 0, "$005D clear before Setzer's bargain")
  end),

  -- the ladder's checkpoint is the booted entry point
  (function()
    local ckReq
    return H.cond(function() return true end, {
      H.call(function() ckReq = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(ckReq, "entry point checkpoint")
        u2Blob = ckReq.blob
        H.log(string.format("[ultros2] entry point checkpoint captured " ..
          "(%d bytes) f%d", #u2Blob, H.frame))
      end),
    })
  end)(),
  attempt(1),
  attempt(2),
  attempt(3),
  H.call(function()
    if not u2Won then
      error(string.format("[ultros2] battle 104 not won in 3 " ..
        "attempts -- last loss: %s -- the per-attempt numbers above are " ..
        "the balance finding (#74-style); do not rig this fight",
        tostring(u2Lost)), 0)
    end
  end),
  H.call(function()
    H.log(string.format("[post-ultros] f%d map=%d (%d,%d) ctl=%s 332=%d 5D=%d 5E=%d",
      H.frame,map(),H.fieldX(),H.fieldY(),tostring(H.hasControl()),
      sw(0x0332),sw(0x005D),sw(0x005E)))
  end),

  -- The Opera finale drops the party inside the Blackjack (map 7) with
  -- control restored at {12,10}.  Setzer is the NPC at {12,8}; this
  -- conversation, not the battle tail itself, begins the coin-toss bargain.
  H.driveUntil(function()
    return map()==7 and H.hasControl() and H.tileAligned()
  end,12000,{H.call(pulseAdvance)},"ride Opera finale to Blackjack interior"),
  H.navTo(12,9,{maxFrames=1000,playBattles=true}),
  H.driveUntil(function() return sw(0x005D)==1 end,6000,{
    H.call(function()
      aPhase=(aPhase+1)%8
      H.setPad(aPhase<4 and {"up","a"} or {})
    end)
  },"talk to Setzer and win the bargain"),

  -- _cac128 completes the Opera finale; its tail and the subsequent
  -- Blackjack scenes are linear.  Pulse both dialog advance keys while the
  -- event owns control, then release once the final world load is stable.
  -- No battle exists on this stretch, and battleLoadStarted reads wrong
  -- during the world arrival redraw (see below), so the ride does not touch
  -- monster RAM at all.
  (function()
    local calm,hb = 0,0
    return H.driveUntil(function()
      local ok = sw(0x034B) == 0 and sw(0x005D) == 1 and sw(0x005E) == 1
             and sw(0x0246) == 0 and map() == 0
             and H.worldHasControl() and H.worldAligned()
             and not H.battleLoadStarted()
      calm = ok and calm + 1 or 0
      return calm >= 30
    end, 60000, {
      H.call(function()
        hb=hb+1
        if hb%300==0 then H.log(string.format("[ride] f%d m%d (%d,%d) ctl=%s 332=%d 5D=%d 5E=%d",
          H.frame,map(),H.fieldX(),H.fieldY(),tostring(H.hasControl()),
          sw(0x0332),sw(0x005D),sw(0x005E))) end
        if sw(0x034B) == 0 and sw(0x005D) == 1 and sw(0x005E) == 1
           and map() == 0 and H.worldHasControl() then
          H.setPad({})
        else
          pulseAdvance()
        end
      end),
    }, "ride Setzer's bargain and Blackjack arrival")
  end)(),
  H.release(),
  H.waitFrames(30),

  --   f19494..f19521   $7E3BF4 = $5554   worldHasControl() true
  --   f19521..f19596   $7E3BF4 = $0000   worldHasControl() FALSE  (75 frames)
  --   f19596..f20094   $7E3BF4 = $5554   worldHasControl() true

  -- The ride's own terminator already requires 30 consecutive good frames, so
  -- it exits correctly; the blind waitFrames(30) then landed in
  -- the dead window and asserted there ("world map is controllable: got
  -- false, want true").  Nothing here is relaxed: the run still has to reach
  -- a controllable, aligned world frame, and the state is now
  -- generated on one rather than possibly inside the redraw.  That matters
  -- because every downstream generator boots this .mss and would otherwise
  -- inherit a first frame the battle gate reports as a battle.
  (function()
    local calm = 0
    return H.waitUntil(function()
      calm = (map() == 0 and H.worldHasControl() and H.worldAligned())
             and calm + 1 or 0
      return calm >= 45
    end, 6000, "a settled, controllable world frame to generate on", 1)
  end)(),

  -- ------------------------------------------------- CELES's kit, restored --
  -- Here rather than earlier because this is the first frame after the
  -- arrival cutscene where she is back in the party and the player has the
  -- menu; the whole opera between the strip and this point is scripted.
  -- The char-select row is asserted rather than assumed: H.equipWeapon
  -- seeks the cursor to a fixed row, and the row is the party's order field
  -- ($1850 bits 3-4), so a reordered party would otherwise dress the wrong
  -- character.
  H.call(function()
    H.assertEq(ordOf(CH_CELES), 3, "CELES is char-select row 3")
    H.log(string.format("[kit] CELES gear before: %02X %02X %02X %02X %02X",
      gear(CH_CELES, 0x1F), gear(CH_CELES, 0x20), gear(CH_CELES, 0x21),
      gear(CH_CELES, 0x22), gear(CH_CELES, 0x23)))
  end),
  fill(CH_CELES, 3, 0, 0x0A, "CELES MithrilBlade"),
  fill(CH_CELES, 3, 1, 0x5B, "CELES Heavy Shld"),
  fill(CH_CELES, 3, 2, 0x6A, "CELES Hair Band"),
  fill(CH_CELES, 3, 3, 0x84, "CELES LeatherArmor"),
  fill(CH_CELES, 3, 4, 0xB1, "CELES Star Pendant"),
  -- Settle again: closing the menu over the world map costs frames the same
  -- way the arrival redraw does, and the fixture has to be generated on a
  -- real world frame for the reasons in the block above.
  (function()
    local calm = 0
    return H.waitUntil(function()
      calm = (map() == 0 and H.worldHasControl() and H.worldAligned())
             and calm + 1 or 0
      return calm >= 45
    end, 6000, "a settled world frame again after the equip stop", 1)
  end)(),

  -- Ultros can leave somebody barely standing even on a decisive win.  The
  -- Blackjack arrival is the first player-controlled field menu after that
  -- fight, so use it as the natural recovery stop before banking the route's
  -- terminal fixture.  This also makes the release checkpoint friendly to a
  -- human who starts playing from it, rather than merely technically alive.
  H.fieldCare({ tag = "post-opera recovery", threshold = 0.60 }),

  H.call(function()
    -- The exit contract for the kit.  Without it a silently no-op equip
    -- stop and a working one both report the same green.
    H.assertEq(gear(CH_CELES, 0x1F) ~= EMPTY, true,
      "CELES leaves the Blackjack holding a weapon")
    H.log(string.format("[kit] CELES gear after:  %02X %02X %02X %02X %02X",
      gear(CH_CELES, 0x1F), gear(CH_CELES, 0x20), gear(CH_CELES, 0x21),
      gear(CH_CELES, 0x22), gear(CH_CELES, 0x23)))
    H.assertEq(sw(0x034B), 0, "$034B clear -- Ultros 2 / Opera complete")
    H.assertEq(sw(0x005D), 1, "$005D set -- Setzer accepted the bargain")
    H.assertEq(sw(0x005E), 1, "$005E set -- Blackjack arrival completed")
    H.assertEq(sw(0x0246), 0, "$0246 clear -- active airship is Blackjack")
    H.assertEq(map(), 0, "on the World of Balance map")
    H.assertEq(H.worldHasControl(), true, "world map is controllable")
    H.assertEq(H.worldAligned(), true, "world position is tile-aligned")
    H.assertPartyStanding("the Blackjack checkpoint")
    H.log(string.format("[blackjack] f%d world (%d,%d), parked airship expected at (137,202)",
      H.frame, H.worldX(), H.worldY()))
    H.screenshot("blackjack")
  end),
  H.saveState("blackjack.mss"),
  H.logStep(function()
    return string.format(
      "blackjack generated at frame %d -- Opera complete, Setzer allied, Blackjack acquired",
      H.frame)
  end),
})
