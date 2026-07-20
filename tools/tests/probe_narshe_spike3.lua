-- probe_narshe_spike3.lua -- SPIKE phase 3 (poked lineage, never FRONTIER):
-- boots spike_defense.mss (defense live, party 1 = TERRA+EDGAR+CELES at
-- {20,10}) and answers the remaining Battle-for-Narshe questions:
--
--  A. MARCH TIMELINE: 2,000 idle frames logging every live object's tile
--     (the twelve raiders included) every 150 frames, plus every battle
--     that fires while all three parties just STAND in their lanes --
--     does a march colliding with an INACTIVE party open a fight?  Each
--     battle is named (formation words) and kill-bitted; the raider
--     first-win/second-win switches ($013E.. beaten-once, $061C..$0627
--     alive) are dumped after each so the respawn/despawn ladder is
--     measured rather than believed.
--
--  B. THE DESCENT: walk party 1 from {20,10} to KEFKA's doorstep
--     {19,36}.  navTo kill-bits every march collision en route (spare =
--     Kefka's species $014A) and re-plans around the wandering NPCs.
--
--  C. KEFKA: A into NPC_1 -> _ccbca0 -> battle 57 (formation 505,
--     KEFKA_NARSHE $014A alone).  Log the seeded OT6 surface: 6/6
--     shields, class row OT6_SLASH|OT6_PIERCE ($03), weak elements =
--     vanilla | $09 (fire|poison add, Ot6ElemAddTbl).  Then END it with
--     the kill-bit -- recording that the scripted finish (if_b_switch
--     $40 -> _ccbcb1, raiders vanish) accepts a kill-bit win, exactly as
--     Vargas/TunnelArmr do -- and ride the esper scene (map 23, then
--     Arvis's map 30 with STARTUP_EVENT) to the first controllable
--     frame.  Mints spike_kefka_won.mss there.  The honest fixture will
--     fight him for real; this run only proves the doors open.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local DEFENSE = "/Users/mtklein/ot6/build/states/spike_defense.mss.lua"

local KEFKA = 0x014A

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end

-- battle_vargas's entity map: monster slot s -> entity offset 8+2s
local function SH(s)  return 0x3E38 + (8 + s * 2) end
local function SMX(s) return 0x3E39 + (8 + s * 2) end
local function RVE(s) return 0x3E89 + (8 + s * 2) end
local function WKE(s) return 0x3BE0 + (8 + s * 2) end
local function WKC(s) return 0x3E9C + (8 + s * 2) end
local function RVC(s) return 0x3E9D + (8 + s * 2) end
local function MHP(s) return 0x3BFC + s * 2 end

local function objXY(i)
  local b = i * 0x29
  return H.readWord(0x086a + b) >> 4, H.readWord(0x086d + b) >> 4
end

local function objTable(tag)
  local t = {}
  for i = 16, 40 do
    local x, y = objXY(i)
    if x > 0 and x < 40 and y > 4 and y < 52 then
      t[#t + 1] = string.format("o%d(%d,%d)", i, x, y)
    end
  end
  H.log(string.format("[objs %s] f%d %s", tag, H.frame, table.concat(t, " ")))
end

local function raiderFlags(tag)
  local alive, once = {}, {}
  for id = 0x061C, 0x0627 do alive[#alive + 1] = sw(id) end
  for id = 0x013E, 0x0149 do once[#once + 1] = sw(id) end
  H.log(string.format("[raiders %s] alive=%s once=%s", tag,
    table.concat(alive, ""), table.concat(once, "")))
end

local fights = 0
local function killBitAll()
  for slot = 0, 5 do
    if H.readByte(0x3aa8 + slot * 2) % 2 == 1 then
      H.writeByte(0x3eec + slot * 2, H.readByte(0x3eec + slot * 2) | 0x80)
    end
  end
end

H.run({ maxFrames = 90000 }, {
  H.loadState(DEFENSE),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 22, "defense boot: map 22")
    H.assertEq(sw(0x0132), 1, "defense boot: live")
    H.assertEq(H.readByte(0x1a6d), 1, "defense boot: party 1")
    objTable("boot")
    raiderFlags("boot")
  end),

  -- ==================================================================== --
  -- B. THE DESCENT, AT ONCE.  Three strategies died before this one:
  --  * navTo mid-defense from a cold start (run 1): BFS reported no path
  --    for thousands of frames -- probe_narshe_map showed why: the south
  --    corridors are ONE TILE WIDE and at t=0 they are plugged by the
  --    raiders' own home-row objects (rows 33/34) -- and meanwhile an
  --    east-lane march threaded the 4-6 tile throat (parties cover only
  --    x=18/20/22 of it) and reached BANON: GameOver at ~f6100 of
  --    defense time, misread as "$0803 churn" until a map guard existed.
  --  * stand-and-clear (run 2): the parties are speed bumps, not a wall;
  --    5 fights in 4,000 frames and the same east threader still got
  --    through.  GameOver again, now measured: the standing default
  --    CANNOT hold the field.  Active play is mandatory -- vanilla's
  --    design, confirmed the hard way.
  -- So: descend IMMEDIATELY.  Every collision we take kill-bits to a win
  -- in ~250 frames and RESETS that raider's entire march (first-win
  -- handler repositions him home and replays his move list), and battle
  -- time freezes every other march.  The clock that matters is the
  -- east-lane threader's ~6,000 field frames; the descent + Kefka must
  -- beat it.
  -- ==================================================================== --
  H.call(function() H.log("[descent] launching at defense t=0") end),
  -- ------------------------------------------------------------------ --
  -- Waypoint pusher.  bfsPath cannot plan this route: probe_narshe_map2
  -- flood-filled both regions with the model's own z-tracking and found
  -- ZERO crossings, yet probe_narshe_edge measured the ENGINE letting
  -- the party step (18,11) down -- a two-tile ledge slide to (18,13) --
  -- with live-z canStep agreeing.  The model's z CARRY prunes edges the
  -- real walk allows, so the descent follows raider o25's measured march
  -- REVERSED (phase-A object trace), one waypoint at a time: navTo when
  -- BFS can see the hop, axis-alternating held pushes when it cannot.
  -- Battles: kill-bit (each win resets that raider's march), Kefka's
  -- $014A spared.  GameOver tripwire throughout.
  -- ------------------------------------------------------------------ --
  (function()
    local WAY = {
      { 18, 11 }, { 18, 13 }, { 18, 16 }, { 17, 17 }, { 17, 20 },
      { 16, 21 }, { 15, 22 }, { 14, 23 }, { 13, 24 }, { 14, 26 },
      { 15, 27 }, { 16, 28 }, { 18, 28 }, { 18, 30 }, { 18, 33 },
      { 18, 34 }, { 19, 35 }, { 19, 36 },
    }
    local wi = 1
    local aPh, battN, holdF, axis = 0, 0, 0, 1
    local hb = -600
    return H.driveUntil(function()
      if map() ~= 22 and not H.battleLoadStarted() then
        error(string.format(
          "left map 22 outside a battle (map=%d f%d) -- a march reached BANON",
          map(), H.frame), 0)
      end
      return wi > #WAY and H.hasControl() and H.tileAligned()
    end, 20000, {
      H.call(function()
        aPh = (aPh + 1) % 8
        battN = H.battleLoadStarted() and battN + 1 or 0
        if H.frame - hb >= 600 then
          hb = H.frame
          H.log(string.format("[descent] f%d at (%d,%d) wp %d/%d z=$%02X",
            H.frame, H.fieldX(), H.fieldY(), wi, #WAY, H.readByte(0x00b2)))
        end
        if battN >= 3 then
          if battN == 3 then
            fights = fights + 1
            local w = H.formationWords()
            H.log(string.format(
              "[descent] BATTLE #%d f%d words %04X %04X %04X %04X %04X %04X $055E=%02X",
              fights, H.frame, w[1], w[2], w[3], w[4], w[5], w[6],
              H.readByte(0x055e)))
          end
          if H.formationHas({ [KEFKA] = true }) then H.setPad({}); return end
          killBitAll()
          H.setPad(aPh < 4 and { "a" } or {})
          return
        end
        if H.dialogWaiting() then H.setPad(aPh < 4 and { "a" } or {}); return end
        if not (H.hasControl() and H.tileAligned()) then H.setPad({}); return end
        -- waypoint bookkeeping: advance past any waypoint we sit on (or
        -- slid past along its axis)
        while wi <= #WAY and H.fieldX() == WAY[wi][1]
              and H.fieldY() == WAY[wi][2] do
          H.log(string.format("[descent] waypoint %d (%d,%d) reached f%d",
            wi, WAY[wi][1], WAY[wi][2], H.frame))
          wi = wi + 1
          holdF, axis = 0, 1
        end
        if wi > #WAY then H.setPad({}); return end
        local tx, ty = WAY[wi][1], WAY[wi][2]
        local dx, dy = tx - H.fieldX(), ty - H.fieldY()
        -- pick the press: alternate axes every 40 held frames so a
        -- model-refused edge gets its other approach
        holdF = holdF + 1
        if holdF % 40 == 0 then axis = -axis end
        local press
        if (axis > 0 and dy ~= 0) or dx == 0 then
          press = dy > 0 and "down" or "up"
        else
          press = dx > 0 and "right" or "left"
        end
        if holdF > 600 then
          error(string.format(
            "[descent] stuck at (%d,%d) short of waypoint %d (%d,%d)",
            H.fieldX(), H.fieldY(), wi, tx, ty), 0)
        end
        H.setPad({ [press] = true })
      end),
    }, "waypoint descent to Kefka's doorstep")
  end)(),
  H.call(function()
    objTable("doorstep")
    raiderFlags("doorstep")
    H.log(string.format("[descent] at (%d,%d) f%d party=%d",
      H.fieldX(), H.fieldY(), H.frame, H.readByte(0x1a6d)))
    H.screenshot("spike_kefka_doorstep")
  end),
  H.saveState("spike_doorstep.mss"),

  -- ==================================================================== --
  -- C. KEFKA.  Face down into NPC_1 {19,37}, A, battle 57.  Run 3 timed
  -- out here with a blind press pattern and no instrumentation; this
  -- round logs the whole activation surface every 120 frames.
  -- ==================================================================== --
  (function()
    local aPh, hb = 0, -120
    return H.driveUntil(function()
      return H.battleLoadStarted()
    end, 4000, {
      H.call(function()
        aPh = (aPh + 1) % 8
        if H.frame - hb >= 120 then
          hb = H.frame
          local w = H.formationWords()
          H.log(string.format(
            "[kefka-try] f%d (%d,%d) face=%d ev=%s dlg=%s batt=%s $02BC-area=%02X " ..
            "words %04X %04X %04X",
            H.frame, H.fieldX(), H.fieldY(),
            H.readByte(0x087f + H.readWord(0x0803)),
            tostring(H.eventRunning()), tostring(H.dialogWaiting()),
            tostring(H.battleLoadStarted()), H.readByte(0x1ed7),
            w[1], w[2], w[3]))
        end
        if H.dialogWaiting() then H.setPad(aPh < 4 and { "a" } or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        if H.fieldX() == 19 and H.fieldY() == 36 then
          H.setPad(aPh < 4 and { "down" } or (aPh == 4 and { "a" } or {}))
          return
        end
        H.setPad({})
      end),
    }, "A into KEFKA -> battle up")
  end)(),
  H.call(function()
    local w = H.formationWords()
    H.log(string.format("[kefka] battle up f%d words %04X %04X %04X %04X %04X %04X",
      H.frame, w[1], w[2], w[3], w[4], w[5], w[6]))
  end),
  H.waitUntil(function() return H.battleActive() end, 3000, "Kefka fight up", 10),
  H.waitFrames(120),
  H.call(function()
    local ks = -1
    for s = 0, 5 do
      if H.readByte(0x3aa8 + s * 2) % 2 == 1
         and H.readWord(0x57c0 + s * 2) == KEFKA then ks = s end
    end
    H.assertEq(ks >= 0, true, "KEFKA_NARSHE $014A present")
    H.log(string.format(
      "[kefka] slot=%d hp=%d shields=%d/%d class=$%02X weak=$%02X revE=$%02X revC=$%02X",
      ks, H.readWord(MHP(ks)), H.readByte(SH(ks)), H.readByte(SMX(ks)),
      H.readByte(WKC(ks)), H.readByte(WKE(ks)),
      H.readByte(RVE(ks)), H.readByte(RVC(ks))))
    H.assertEq(H.readByte(SH(ks)), 6, "6 shields seeded (Ot6ShieldTbl $014A)")
    H.assertEq(H.readByte(WKC(ks)), 0x03,
      "class row OT6_SLASH|OT6_PIERCE ($03)")
    H.assertEq(H.readByte(WKE(ks)) & 0x09, 0x09,
      "weak elements carry the fire|poison add (Ot6ElemAddTbl $014A)")
    H.screenshot("spike_kefka_battle")
  end),
  -- kill-bit the fight down and record that the scripted win path takes it
  (function()
    local aPh = 0
    return H.driveUntil(function() return not H.battleLoadStarted() end,
      20000, {
      H.call(function()
        aPh = (aPh + 1) % 8
        if H.monstersPresent() > 0 then killBitAll() end
        H.setPad(aPh < 4 and { "a" } or {})
      end),
    }, "Kefka down (kill-bit)")
  end)(),
  H.logStep(function()
    return string.format("Kefka fight torn down at f%d; riding _ccbcb1", H.frame)
  end),

  -- the win tail: raiders vanish, esper scene (map 23), Arvis (map 30).
  -- first calm controllable frame anywhere = the mint.
  (function()
    local cnt = 0
    return H.advanceStory(function()
      local ok = H.hasControl() and H.tileAligned() and bright() >= 15
             and not H.dialogWaiting() and not H.eventRunning()
             and not H.battleLoadStarted() and not H.worldMode()
      cnt = ok and cnt + 1 or 0
      return cnt >= 60
    end, 40000)
  end)(),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(sw(0x0139), 1, "$0139 SET -- the battle-won latch")
    H.assertEq(sw(0x0612), 0, "$0612 clear -- KEFKA's NPC gone")
    H.assertEq(sw(0x061D), 0, "$061D clear -- raiders retired")
    H.log(string.format("[kefka_won] f%d map=%d (%d,%d) $0046=%d",
      H.frame, map(), H.fieldX(), H.fieldY(), sw(0x0046)))
    for c = 0, 15 do
      if (H.readByte(0x1850 + c) & 0x07) ~= 0 then
        local base = 0x1600 + 37 * c
        H.log(string.format("char %2d actor=%02X level=%d hp=%d/%d",
          c, H.readByte(base), H.readByte(base + 8),
          H.readWord(base + 9), H.readWord(base + 11)))
      end
    end
    H.screenshot("spike_kefka_won")
  end),
  H.saveState("spike_kefka_won.mss"),
  H.logStep(function()
    return string.format("spike 3 complete at f%d -- v0.3's stop line reached", H.frame)
  end),
})
