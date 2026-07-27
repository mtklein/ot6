-- gen_opera7_blackjack.lua -- v0.5 terminal leg: ultros2_doorstep -> defeat
-- Ultros 2 -> ride the Setzer/coin-toss/Blackjack sequence -> mint blackjack.
--
-- The terminal is the first stable, controllable world-map frame after the
-- Blackjack lands outside Vector.  Source (_cac128 -> _cb2007 -> _cb2379)
-- gives the durable story invariants:
--   $034B=0  Ultros 2 NPC / Opera battle gate cleared
--   $005D=1  Setzer accepted the party's bargain
--   $005E=1  the Blackjack arrival sequence completed
--   $0246=0  the active airship is the Blackjack (not the Falcon)
-- The world load is map 0 at {140,203}; the parked airship is {137,202}.
--
-- This is a route fixture, not a combat test, so it uses the established
-- kill-bit idiom after positively identifying Ultros 2 ($012d).  The real
-- battle contract remains battle_ultros2.lua, which boots the same doorstep.
local H = dofile("tools/tests/lib/ot6.lua")
local DOOR = "build/states/ultros2_doorstep.mss.lua"

local ULTROS2 = 0x012d
local aPhase = 0

local function sw(id)
  return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1
end
local function map() return H.mapId() & 0x1FF end

local function killBitAll()
  if not H.battleLoadStarted() then return end
  for slot = 0, 5 do
    if (H.readByte(0x3aa8 + slot * 2) & 1) ~= 0 then
      H.writeByte(0x3eec + slot * 2,
        H.readByte(0x3eec + slot * 2) | 0x80)
    end
  end
end

local function pulseAdvance()
  aPhase = (aPhase + 1) % 8
  H.setPad(aPhase < 4 and { "a", "start" } or {})
end

H.run({ maxFrames = 90000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(sw(0x034B), 1, "$034B set -- Ultros 2 present before battle")
    H.assertEq(sw(0x005D), 0, "$005D clear before Setzer's bargain")
  end),

  -- The doorstep contract is one advance from the WoB story battle 104.
  H.driveUntil(function() return H.battleLoadStarted() end, 20000, {
    H.call(pulseAdvance),
  }, "enter Ultros 2"),
  H.waitUntil(function() return H.battleActive() end, 4000, "Ultros 2 active", 10),
  H.call(function()
    H.assertEq(H.formationHas({ [ULTROS2] = true }), true,
      "battle 104 contains Ultros 2 ($012d)")
    H.screenshot("ultros2_route_seed")
  end),

  -- Route fixtures clear their gate fight deterministically; battle_ultros2
  -- independently exercises the authored shield/class behavior.
  H.driveUntil(function() return not H.battleLoadStarted() end, 20000, {
    H.call(function()
      killBitAll()
      pulseAdvance()
    end),
  }, "defeat Ultros 2 (route kill-bit)"),
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
  H.navTo(12,9,{maxFrames=1000}),
  H.driveUntil(function() return sw(0x005D)==1 end,6000,{
    H.call(function()
      aPhase=(aPhase+1)%8
      H.setPad(aPhase<4 and {"up","a"} or {})
    end)
  },"talk to Setzer and win the bargain"),

  -- _cac128 completes the Opera finale; its tail and the subsequent
  -- Blackjack scenes are linear.  Pulse both dialog advance keys while the
  -- event owns control, then release once the final world load is stable.
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
        if H.battleLoadStarted() then killBitAll() end
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

  -- ...and then WAIT FOR IT AGAIN, because a fixed 30-frame pause lands in a
  -- window where the world map makes the battle gate lie.  Measured here on
  -- the Blackjack arrival, per frame for 600 frames after the ride:
  --
  --   f19494..f19521   $7E3BF4 = $5554   worldHasControl() true
  --   f19521..f19596   $7E3BF4 = $0000   worldHasControl() FALSE  (75 frames)
  --   f19596..f20094   $7E3BF4 = $5554   worldHasControl() true
  --
  -- $7E3BF4 is the party battle-HP table only while the BATTLE module owns
  -- that RAM; the world module reuses the same bytes for map data, and it
  -- zeroes them for 75 frames during the arrival redraw.  Since 62ccab7
  -- (#24) M.battleLoadStarted() is "slot 0 is not $FFFF", so it reads $0000
  -- as a live battle, and worldHasControl() -- which is gated on it -- goes
  -- false.  The old predicate rejected 0 and never saw this.
  --
  -- The ride's own terminator already demands 30 consecutive good frames, so
  -- it exits legitimately; the blind waitFrames(30) then walked straight
  -- into the dead window and asserted there ("world map is controllable: got
  -- false, want true").  Nothing here is relaxed: the run still has to reach
  -- a genuinely controllable, aligned world frame, and now the state is
  -- MINTED on one too rather than possibly inside the redraw -- which
  -- matters, because every downstream generator boots this .mss and would
  -- inherit a first frame the battle gate calls a battle.
  (function()
    local calm = 0
    return H.waitUntil(function()
      calm = (map() == 0 and H.worldHasControl() and H.worldAligned())
             and calm + 1 or 0
      return calm >= 45
    end, 6000, "a settled, controllable world frame to mint on", 1)
  end)(),

  H.call(function()
    H.assertEq(sw(0x034B), 0, "$034B clear -- Ultros 2 / Opera complete")
    H.assertEq(sw(0x005D), 1, "$005D set -- Setzer accepted the bargain")
    H.assertEq(sw(0x005E), 1, "$005E set -- Blackjack arrival completed")
    H.assertEq(sw(0x0246), 0, "$0246 clear -- active airship is Blackjack")
    H.assertEq(map(), 0, "on the World of Balance map")
    H.assertEq(H.worldHasControl(), true, "world map is controllable")
    H.assertEq(H.worldAligned(), true, "world position is tile-aligned")
    H.log(string.format("[blackjack] f%d world (%d,%d), parked airship expected at (137,202)",
      H.frame, H.worldX(), H.worldY()))
    H.screenshot("blackjack")
  end),
  H.saveState("blackjack.mss"),
  H.logStep(function()
    return string.format(
      "blackjack minted at frame %d -- Opera complete, Setzer allied, Blackjack acquired",
      H.frame)
  end),
})
