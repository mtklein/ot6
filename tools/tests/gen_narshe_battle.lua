-- gen_narshe_battle.lua -- the BATTLE FOR NARSHE, reunion staging to
-- KEFKA's fall: v0.3's climax and its stop line.  Boots
-- reunion_ready.mss -- the map-22 staging the reunion cutscene ends on
-- (party at (20,9), $0045 set) -- and mints three states:
--
--   narshe_battle.mss   the defense LIVE: parties assigned and parked at
--                       {20,10}/{18,10}/{22,10}, twelve marches walking,
--                       $0132=1, first controllable frame after "Go!!"
--   kefka_doorstep.mss  party 1 at (19,36), KEFKA one tile below, the
--                       descent done -- battle_kefka's boot (a suite test
--                       must be a pure savestate load + a short fight,
--                       not a 5,400-frame descent)
--   kefka_won.mss       the first controllable frame after the win tail
--                       (the esper scene, Arvis's house) -- v0.3's stop
--                       line and the boot for whatever comes after
--
-- THE HONEST BOOT does not exist yet: reunion_ready.mss needs all three
-- scenario flags in one playthrough, and SABIN's chain is still growing
-- its back half.  The plumbing is ready (see the Makefile's stacking
-- block): when his ending lands, the s2_/t3_ stacks replay his chain and
-- Terra's on top of locke_done and gen_terra_done's reunion fork mints
-- reunion_ready.  UNTIL THEN this generator is validated on the POKED
-- twin: `cp spike_staging -> spike_reunion_ready` and run with
-- OT6_STACK=spike_ -- compose rewrites every state basename, so the same
-- file boots the spike state and mints spike_narshe_battle /
-- spike_kefka_doorstep (the stacking mechanism validating the fixture
-- generator, no duplication).  THE MAP-23 ESPER STALL, corrected: the win
-- tail parks at $CCBEBA (the reunion cutscene) on EVERY boot, honest
-- included -- not a poked-boot rostering bug as first thought.  Its
-- dialogs never set the field dialog flags ($00BA/$00D3 = 0, measured),
-- so a tap-on-dialogWaiting driver never advances them.  Step 5 taps A
-- unconditionally through map 23 instead; measured to walk the PC off
-- $CCBEBA to the overworld (probe_esper_stall's tap-through).
--
-- EVERY MECHANISM HERE WAS MEASURED FIRST (probe_narshe_spike*,
-- probe_kefka_npc, probe_kefka_fight -- spike lineage, commits
-- a74de44/3909646/a3cd55b/510ed0d):
--  * BANON {20,7} -> _ccc605 "Prepared?" -> A picks Yes; the map-5 info
--    scene's choice converges either way.
--  * party_menu 3, RESET: state machine $2d -A-> $2e -A-> swap; cursor
--    cell = $4b+$4a+$5a; pool rows 8 wide; party p = cells $10+4p+s
--    drawn as three 2x2 boxes; Start commits iff every party non-empty
--    (else $69 error splash, self-recovering).  The driver is state-fed
--    and verifies every landing in $7E9D89.
--  * THE SPLIT: P1 = TERRA+EDGAR+CELES (fire + BioBlaster poison +
--    slash/Runic -- three of the four axes Kefka's rows chip under),
--    P2 = CYAN+SABIN, P3 = LOCKE+GAU.  Proof of commit: $1850 low 3
--    bits per character.
--  * THE DEFENSE CANNOT BE HELD PASSIVELY (measured twice: an east-lane
--    march reaches BANON at ~f6100 of defense time past any standing
--    formation) and the cliff route to Kefka is INVISIBLE to bfsPath
--    (the model's z-carry prunes a real two-tile ledge slide at
--    (18,11), probe_narshe_edge).  So the descent launches AT ONCE and
--    walks raider o25's measured march reversed -- 18 waypoints, an
--    axis-alternating held pusher, every collision kill-bitted (each
--    win resets that raider's entire march; battle time freezes all
--    clocks).  Doorstep at ~f5400, comfortably inside the threader's
--    window, and runs are deterministic so the race is a fixed win.
--  * KEFKA (NPC_1, no_react, no collision): activation needs a CLEAN
--    edge-A -- any held direction starves CheckNPCs (player.asm:142).
--    battle 57 = formation 505 = KEFKA_NARSHE $014A alone: hp 3000,
--    gauge 6/6, class row $03, weak byte EXACTLY $09 (the ElemAdd row).
--    The kill-bit ends it through the scripted if_b_switch $40 win
--    (227 frames) -- battle_kefka fights him for REAL from the doorstep
--    mint; this chain run only needs the win.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local BOOT = "/Users/mtklein/ot6/build/states/reunion_ready.mss.lua"

local KEFKA = 0x014A

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end

-- ---------------------------------------------------------- menu driving --
local function mst() return H.readByte(0x0026) end
local function menuUp() return H.readByte(0x0059) ~= 0 end
local function cell9d(c) return H.readByte(0x7E9D89 + c) end
local function cursorCell()
  return H.readByte(0x004b) + H.readByte(0x004a) + H.readByte(0x005a)
end
local function decode(cell)
  if cell < 0x10 then
    return { area = "pool", col = cell % 8, row = cell >= 8 and 1 or 0 }
  end
  local b = cell - 0x10
  return { area = "party", col = b >> 1, row = b & 1 }
end
local function stepToward(cur, tgt)
  local c, t = decode(cur), decode(tgt)
  if c.area == "pool" and t.area == "party" then return "down"
  elseif c.area == "party" and t.area == "pool" then return "up"
  elseif c.area == "pool" then
    if c.row ~= t.row then return c.row < t.row and "down" or "up" end
    if c.col ~= t.col then return c.col < t.col and "right" or "left" end
  else
    if c.col ~= t.col then return c.col < t.col and "right" or "left" end
    if c.row ~= t.row then return c.row < t.row and "down" or "up" end
  end
  return nil
end
local function menuAct(tgt, btn, doneState, what)
  local phase, settled = 0, 0
  return H.driveUntil(function()
    return mst() == doneState and cursorCell() == tgt and settled >= 8
  end, 4000, {
    H.call(function()
      phase = (phase + 1) % 10
      if mst() == doneState then
        settled = settled + 1
        H.setPad({})
        return
      end
      settled = 0
      if mst() == 0x69 then H.setPad({}); return end
      local cur = cursorCell()
      if cur ~= tgt then
        local b = stepToward(cur, tgt)
        if not b then H.setPad({}); return end
        H.setPad(phase < 4 and { [b] = true } or {})
        return
      end
      H.setPad(phase < 4 and { [btn] = true } or {})
    end),
  }, what)
end
local function assign(srcCell, dstCell, charId, name)
  return H.cond(function() return true end, {
    H.waitUntil(function() return mst() == 0x2d end, 600,
      name .. ": menu at $2d", 5),
    menuAct(srcCell, "a", 0x2e, name .. ": pick"),
    menuAct(dstCell, "a", 0x2d, name .. ": drop"),
    H.call(function()
      H.assertEq(cell9d(dstCell), charId, name .. " in the party cell")
      H.assertEq(cell9d(srcCell), 0xFF, name .. "'s pool cell empty")
    end),
  })
end
local function partyOf(c) return H.readByte(0x1850 + c) & 0x07 end

local function killBitAll()
  for slot = 0, 5 do
    if H.readByte(0x3aa8 + slot * 2) % 2 == 1 then
      H.writeByte(0x3eec + slot * 2, H.readByte(0x3eec + slot * 2) | 0x80)
    end
  end
end

local function landed(m, n)
  local cnt, hb = 0, -600
  return function()
    local ok = map() == m and H.hasControl() and H.tileAligned()
           and bright() >= 15 and not H.battleLoadStarted()
           and not H.dialogWaiting() and not H.worldMode()
    cnt = ok and cnt + 1 or 0
    if not ok and H.frame - hb >= 600 then
      hb = H.frame
      H.log(string.format("landed(%d) f%d: map=%d ctl=%s dlg=%s ev=%s (%d,%d)",
        m, H.frame, map(), tostring(H.hasControl()),
        tostring(H.dialogWaiting()), tostring(H.eventRunning()),
        H.fieldX(), H.fieldY()))
    end
    return cnt >= (n or 20)
  end
end

local fights = 0

H.run({ maxFrames = 120000 }, {
  H.loadState(BOOT),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 22, "booted on map 22, the reunion staging")
    H.assertEq(sw(0x0045), 1, "$0045 set -- the staging handoff ran")
    H.assertEq(sw(0x0132), 0, "$0132 clear -- the defense is not live yet")
    H.assertEq(H.hasControl(), true, "controllable")
    H.log(string.format("[boot] (%d,%d) $001E=%d $0021=%d $0044=%d",
      H.fieldX(), H.fieldY(), sw(0x001E), sw(0x0021), sw(0x0044)))
  end),

  -- ==================================================================== --
  -- 1. BANON {20,7}: stand at (20,8), face up, clean A.  "Prepared?" ->
  --    Yes -> the map-5 info scene -> party_menu 3, RESET.
  -- ==================================================================== --
  H.navTo(20, 8, { maxFrames = 6000 }),
  (function()
    local aPh = 0
    return H.driveUntil(menuUp, 8000, {
      H.call(function()
        aPh = (aPh + 1) % 8
        if H.dialogWaiting() then H.setPad(aPh < 4 and { "a" } or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        if H.fieldX() == 20 and H.fieldY() == 8 then
          H.setPad(aPh < 4 and { "up" } or (aPh == 4 and { "a" } or {}))
          return
        end
        H.setPad({})
      end),
    }, "Banon -> Prepared? -> party menu")
  end)(),
  H.waitUntil(function() return mst() == 0x2d end, 900, "menu at $2d", 5),
  H.waitFrames(20),
  H.call(function()
    local pool = {}
    for c = 0, 15 do pool[#pool + 1] = string.format("%02X", cell9d(c)) end
    H.log("[assign] pool: " .. table.concat(pool, " "))
    -- the fixed split rests on the pool order the reunion builds:
    -- TERRA LOCKE CYAN EDGAR SABIN CELES GAU at cells 0-6
    for i, want in ipairs({ 0x00, 0x01, 0x02, 0x04, 0x05, 0x06, 0x0B }) do
      H.assertEq(cell9d(i - 1), want,
        string.format("pool cell %d is char $%02X", i - 1, want))
    end
  end),

  -- ==================================================================== --
  -- 2. THE ASSIGNMENT: P1=TERRA+EDGAR+CELES P2=CYAN+SABIN P3=LOCKE+GAU.
  -- ==================================================================== --
  assign(0, 0x10, 0x00, "TERRA -> P1s0"),
  assign(3, 0x11, 0x04, "EDGAR -> P1s1"),
  assign(5, 0x12, 0x06, "CELES -> P1s2"),
  assign(2, 0x14, 0x02, "CYAN -> P2s0"),
  assign(4, 0x15, 0x05, "SABIN -> P2s1"),
  assign(1, 0x18, 0x01, "LOCKE -> P3s0"),
  assign(6, 0x19, 0x0B, "GAU -> P3s1"),
  H.waitUntil(function() return mst() == 0x2d end, 600, "menu at $2d for commit", 5),
  H.pressButtons({ "start" }, 6),
  H.waitUntil(function() return not menuUp() end, 1200, "menu closed", 5),
  H.logStep("assignment committed; riding the battle-start event"),
  H.advanceStory(landed(22), 30000),
  H.waitFrames(30),

  H.call(function()
    H.assertEq(map(), 22, "defense: map 22")
    H.assertEq(sw(0x0132), 1, "defense LIVE ($0132)")
    H.assertEq(sw(0x0612), 1, "KEFKA's NPC on the map ($0612)")
    H.assertEq((H.readByte(0x1eb9) & 0x40) ~= 0, true, "Y switching enabled ($01CE)")
    H.assertEq(H.readByte(0x1a6d), 1, "party 1 active")
    H.assertEq(H.fieldX() == 20 and H.fieldY() == 10, true, "party 1 at {20,10}")
    H.assertEq(partyOf(0), 1, "TERRA in party 1")
    H.assertEq(partyOf(4), 1, "EDGAR in party 1")
    H.assertEq(partyOf(6), 1, "CELES in party 1")
    H.assertEq(partyOf(2), 2, "CYAN in party 2")
    H.assertEq(partyOf(5), 2, "SABIN in party 2")
    H.assertEq(partyOf(1), 3, "LOCKE in party 3")
    H.assertEq(partyOf(11), 3, "GAU in party 3")
    for id = 0x061C, 0x0627 do
      H.assertEq(sw(id), 1, string.format("raider $%04X marching", id))
    end
    H.screenshot("narshe_battle")
  end),
  H.saveState("narshe_battle.mss"),

  -- ==================================================================== --
  -- 3. THE DESCENT, AT ONCE: o25's march reversed, collisions kill-bitted,
  --    GameOver tripwired.  ~5,400 frames to the doorstep.
  -- ==================================================================== --
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
          H.log(string.format("[descent] f%d at (%d,%d) wp %d/%d",
            H.frame, H.fieldX(), H.fieldY(), wi, #WAY))
        end
        if battN >= 3 then
          if battN == 3 then
            fights = fights + 1
            local w = H.formationWords()
            H.log(string.format(
              "[descent] BATTLE #%d f%d words %04X %04X %04X %04X %04X %04X",
              fights, H.frame, w[1], w[2], w[3], w[4], w[5], w[6]))
          end
          if H.formationHas({ [KEFKA] = true }) then H.setPad({}); return end
          killBitAll()
          H.setPad(aPh < 4 and { "a" } or {})
          return
        end
        if H.dialogWaiting() then H.setPad(aPh < 4 and { "a" } or {}); return end
        if not (H.hasControl() and H.tileAligned()) then H.setPad({}); return end
        while wi <= #WAY and H.fieldX() == WAY[wi][1]
              and H.fieldY() == WAY[wi][2] do
          wi = wi + 1
          holdF, axis = 0, 1
        end
        if wi > #WAY then H.setPad({}); return end
        local tx, ty = WAY[wi][1], WAY[wi][2]
        local dx, dy = tx - H.fieldX(), ty - H.fieldY()
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
    }, "the descent to Kefka's doorstep")
  end)(),
  H.call(function()
    H.assertEq(H.fieldX() == 19 and H.fieldY() == 36, true,
      "party 1 at (19,36), KEFKA one tile below")
    H.assertEq(H.readByte(0x1a6d), 1, "still party 1")
    H.log(string.format("[doorstep] f%d after %d collision fights",
      H.frame, fights))
    H.screenshot("kefka_doorstep")
  end),
  H.saveState("kefka_doorstep.mss"),

  -- ==================================================================== --
  -- 4. KEFKA: clean edge-A activation, the seed asserted, kill-bit win.
  --    battle_kefka fights him for real from the doorstep mint; the
  --    chain only needs the scripted $40 win here.
  -- ==================================================================== --
  H.hold({ "down" }), H.waitFrames(4), H.release(), H.waitFrames(8),
  H.driveUntil(function() return H.battleLoadStarted() end, 2000, {
    H.cond(function() return true end, {
      H.hold({ "a" }), H.waitFrames(8), H.release(), H.waitFrames(8),
    }),
  }, "clean A into KEFKA -> battle 57"),
  H.waitUntil(function() return H.battleActive() end, 3000, "Kefka up", 10),
  H.waitFrames(150),
  H.call(function()
    local ks = -1
    for s = 0, 5 do
      if H.readByte(0x3aa8 + s * 2) % 2 == 1
         and H.readWord(0x57c0 + s * 2) == KEFKA then ks = s end
    end
    H.assertEq(ks >= 0, true, "KEFKA_NARSHE $014A on the field")
    H.assertEq(H.readByte(0x3E38 + 8 + ks * 2), 6, "gauge 6/6 seeded")
    H.assertEq(H.readByte(0x3E9C + 8 + ks * 2), 0x03, "class row $03")
    H.assertEq(H.readByte(0x3BE0 + 8 + ks * 2), 0x09, "weak byte exactly $09")
  end),
  (function()
    local aPh = 0
    return H.driveUntil(function() return not H.battleLoadStarted() end,
      20000, {
      H.call(function()
        aPh = (aPh + 1) % 8
        if H.monstersPresent() > 0 then killBitAll() end
        H.setPad(aPh < 4 and { "a" } or {})
      end),
    }, "Kefka down (kill-bit; the $40 win)")
  end)(),

  -- ==================================================================== --
  -- 5. STOP AT THE STOP LINE.  The $40 win above IS v0.3's milestone;
  --    everything after it (the esper scene, Arvis, the walk to control)
  --    is v0.4's first link and stalls the walker (issue #3).  Bundling
  --    it here made a past-the-stop-line bug fail a v0.3 mint rule --
  --    the frontier chain halted at a fixture the release needs even
  --    though the fight it gates had been won moments earlier.  The
  --    tail lives in gen_kefka_won.lua, deliberately outside FRONTIER.
  -- ==================================================================== --
  H.waitFrames(30),
  H.call(function()
    -- the win verdict is battle_kefka's, verbatim: the $40 path leaves the
    -- party OFF the {25,5} lose-path save point with the win scene owning
    -- the stage.  ($0139 is NOT set here -- it latches later, inside the
    -- win scene's tail; asserting it at battle-exit was measured wrong.)
    local atSave = H.fieldX() == 25 and H.fieldY() == 5
    H.assertEq(atSave, false,
      "NOT at the {25,5} save point -- the lose path did not run")
    H.assertEq(H.eventRunning() or H.dialogWaiting(), true,
      "the win scene owns the stage (_ccbcb1)")
    H.assertEq(H.battleLoadStarted(), false, "the fight is over")
    H.log(string.format("[narshe_battle] the $40 win stands at f%d", H.frame))
  end),
  H.logStep(function()
    return string.format("Kefka beaten at frame %d -- v0.3's stop line; the win tail is gen_kefka_won's (issue #3)", H.frame)
  end),
})
