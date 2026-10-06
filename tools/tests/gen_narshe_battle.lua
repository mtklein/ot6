-- gen_narshe_battle.lua -- the Battle for Narshe, from the reunion staging
-- to KEFKA's fall: v0.3's final beat and its stop line.  Boots
-- reunion_ready.mss, the map-22 staging the reunion cutscene ends on
-- (party at (20,9), $0045 set), and generates three states:

--   narshe_battle.mss   the defense live: parties assigned and parked at
--                       {20,10}/{18,10}/{22,10}, twelve marches walking,
--                       $0132=1, first controllable frame after "Go!!"
--   kefka_entry.mss  party 1 at (19,36), KEFKA one tile below, the
--                       descent done.  This is battle_kefka's boot; a suite
--                       test should be a savestate load plus a short fight
--                       rather than a 5,400-frame descent.

local H = dofile("tools/tests/lib/ot6.lua")
local BOOT = "build/states/reunion_ready.mss.lua"

local KEFKA = 0x014A

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end

-- ---------------------------------------------------------- menu driving --
local function mst() return H.readByte(0x0026) end
local function menuUp() return H.readByte(0x0059) ~= 0 end
local function cell9d(c) return H.readByte(0x7E9D89 + c) end
-- the seats themselves are H.partySelect (lib/ot6_field.lua): each member
-- found in the pool, walked to its group's lowest empty seat, both cells
-- asserted, START to commit
local function partyOf(c) return H.readByte(0x1850 + c) & 0x07 end

-- ------------------------------------------------------- the descent fighter --
-- #311: the descent is fought by the library's driver, the one KEFKA's fight
-- below uses (#257), rather than the input-sequence fighter this file used to
-- carry.  That fighter had no heal line, named whatever tool the cursor's
-- row held (the Bio Blaster, $A4, a poison spell at 8 MP, where KEFKA's lab
-- measured the AutoCrossbow), and raised its kit tier with each reload of
-- its own three-rung ladder: attempt 1 tier 2 (EDGAR's Tools), attempts 2-3
-- tier 3 (CELES's Runic and SABIN's Pummel too) -- a ladder that re-rolled
-- the descent with a stronger plan until it passed ('PARTY WIPED in battle
-- #6 at f25806' rescued by attempt 2, build/attempts/wt/kefka-lab/).
-- The driver plays every collision the way it plays KEFKA: EDGAR's
-- AutoCrossbow named by id (pierce, ignores defence, 4 MP), the bank of two
-- pips spent up to three, TERRA's care turn with the bag's Potions.  CELES
-- keeps the Fight: the raiders' script is physical, so Runic has nothing
-- to absorb here.  One descent, played once; a loss raises the wipe it is
-- and the segment runner's standard bounded retry (the boot snapshot, a
-- moved seed, a counted `[retry]` line) is the only reload.
local DESCENT = { tactical = true, boost = true, bank = 2, items = true,
  healer = 0, healPercent = 70, tool = H.AUTOCROSSBOW }
local BCHP, BCMAXHP = 0x3bf4, 0x3c1c
local function partyLine()
  local p = {}
  for e = 0, 3 do
    p[#p + 1] = string.format("%d/%d", H.readWord(BCHP + e * 2),
      H.readWord(BCMAXHP + e * 2))
  end
  return table.concat(p, " ")
end
local function monSpecies(i) return H.readWord(0x57c0 + i * 2) end
local function monHp(i) return H.readWord(0x3bfc + i * 2) end
local function monShields(i) return H.readByte(0x3e40 + i * 2) end
local function monPresent(i) return H.readByte(0x3aa8 + i * 2) % 2 == 1 end

local fights = 0
-- One fighter drives the whole descent.  Call .frame(battN) every frame a
-- battle is up (battN = consecutive battle frames), .idle() otherwise, and
-- .watch() every frame of the drive: a wipe zeroes every battle-HP word,
-- which the battle gate reads as "no battle" (#163), so the loss is read
-- outside it -- the lib's wipe predicate held 90 straight frames, or the
-- run canary's game-over count.
local function mkFighter(tag)
  local F = {}
  local D = H.newFightDriver(tag, DESCENT)
  local bt, wipeN = nil, 0
  local function lost(what)
    H.screenshot(string.format("narshe_lost%d", bt and bt.n or 0))
    error(string.format("[%s] THE PARTY IS WIPED -- %s in battle #%s at f%d " ..
      "(started f%s) -- party [%s]", tag, what, bt and tostring(bt.n) or "?",
      H.frame, bt and tostring(bt.f0) or "?", bt and bt.lastParty or partyLine()), 0)
  end
  function F.watch()
    wipeN = H.partyWipedInBattle() and wipeN + 1 or 0
    if wipeN >= 90 then lost("the battle table read wiped for 90 frames") end
    if (H.gameOverFired or 0) > 0 then lost("the run canary counted a game over") end
  end
  function F.frame(battN)
    if battN == 3 then
      fights = fights + 1
      bt = { n = fights, f0 = H.frame }
      local w = H.formationWords()
      H.log(string.format("[%s] battle #%d up f%d party=%d " ..
        "(%04X %04X %04X %04X %04X %04X)", tag, bt.n, H.frame,
        H.readByte(0x1a6d), w[1], w[2], w[3], w[4], w[5], w[6]))
      for i = 0, 5 do
        if monPresent(i) then
          H.log(string.format("   slot %d species $%04X hp=%d shields=%d",
            i, monSpecies(i), monHp(i), monShields(i)))
        end
      end
    end
    if bt then bt.lastParty = partyLine() end
    D.frame()
  end
  function F.idle()
    if bt then
      H.log(string.format("[%s] battle #%d done at f%d (%d frames) -- " ..
        "party [%s]", tag, bt.n, H.frame, H.frame - bt.f0, bt.lastParty or "?"))
      bt = nil
    end
    D.idle()
  end
  return F
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

-- ------------------------------------------------------ the descent step --
-- o25's march reversed, an axis-alternating held pusher, with every
-- collision fought.  The descent ends done (party 1 parked at (19,36)) or
-- raises: a wipe read by the fighter (class wipe, retried by the runner),
-- map 22 left outside a battle (a march reached BANON), or a stuck waypoint
-- (a route or model failure rather than a fight outcome).
local WAY = {
  { 18, 11 }, { 18, 13 }, { 18, 16 }, { 17, 17 }, { 17, 20 },
  { 16, 21 }, { 15, 22 }, { 14, 23 }, { 13, 24 }, { 14, 26 },
  { 15, 27 }, { 16, 28 }, { 18, 28 }, { 18, 30 }, { 18, 33 },
  { 18, 34 }, { 19, 35 }, { 19, 36 },
}
local WAY_CARE_AFTER = 12
local descentF = nil
local function descentBody(wi0, wi1)
  local wi = wi0
  local battN, holdF, axis = 0, 0, 1
  local hb = -600
  return H.driveUntil(function()
    if map() ~= 22 and not H.battleLoadStarted() then
      error(string.format("[descent] left map 22 outside a battle (map=%d f%d " ..
        "at wp %d/%d) -- a march reached BANON", map(), H.frame, wi, #WAY), 0)
    end
    return wi > wi1 and H.hasControl() and H.tileAligned()
  end, 90000, {
    H.call(function()
      descentF = descentF or mkFighter("descent")
      local F = descentF
      F.watch()                           -- every frame, outside the gate
      battN = H.battleLoadStarted() and battN + 1 or 0
      if H.frame - hb >= 600 then
        hb = H.frame
        H.log(string.format("[descent] f%d at (%d,%d) wp %d/%d",
          H.frame, H.fieldX(), H.fieldY(), wi, #WAY))
      end
      if battN >= 3 then
        if H.formationHas({ [KEFKA] = true }) then H.setPad({}); return end
        F.frame(battN)
        return
      end
      F.idle()
      if H.dialogWaiting() then
        H.setPad(H.frame % 8 < 4 and { "a" } or {})
        return
      end
      if not (H.hasControl() and H.tileAligned()) then H.setPad({}); return end
      while wi <= wi1 and H.fieldX() == WAY[wi][1]
            and H.fieldY() == WAY[wi][2] do
        wi = wi + 1
        holdF, axis = 0, 1
      end
      if wi > wi1 then H.setPad({}); return end
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
  }, string.format("the descent to Kefka's entry point (wp %d-%d)", wi0, wi1))
end
-- The descent, played once.  WAY_CARE_AFTER splits it at the rest a player
-- takes before the recurring 001C+0065 raider corridor (waypoints 13-16).
local function descent()
  return H.cond(function() return true end, {
    descentBody(1, WAY_CARE_AFTER),
    H.release(),
    H.waitFrames(10),
    H.fieldCare({ tag = "care before the raider corridor",
                  threshold = 0.85, mpFloor = 0.5 }),
    descentBody(WAY_CARE_AFTER + 1, #WAY),
    H.release(),
    H.waitFrames(10),
    H.call(function()
      H.log(string.format("[descent] reached the entry point after %d " ..
        "collision fights", fights))
    end),
  })
end

-- -------------------------------------------------------- the KEFKA step --
-- One attempt: clean edge-A activation, the authored seed asserted, the
-- fight played to its end by the library's driver with FIGHT (the table
-- battle_kefka and gen_kefka_won carry verbatim, #257; the lab behind it is
-- under build/attempts/wt/kefka-lab/), and the verdict read off the scripted
-- branch: the win scene on the stage vs the {25,5} lose-path save point.
-- There is no KEFKA ladder.  A lost battle 57 is raised here as the wipe it
-- is (the runner's class=wipe), and the segment runner's standard bounded
-- retry is the only reload: the boot snapshot, a moved seed, a counted
-- `[retry] attempt n/3 FAILED` line.
-- The KEFKA fighter (#257), verbatim in battle_kefka, gen_narshe_battle and
-- gen_kefka_won.  Each lever was measured in build/attempts/wt/kefka-lab/:
--   runic   CELES holds Runic.  KEFKA's script is Fight plus spells, and a
--           spell that lands unabsorbed can take a member in one action:
--           every attributed [death] in the lab was Ice 2 (atk $06) or Drain
--           ($04) on one member, from 282-349 HP.
--   cure    false.  Runic absorbs the party's own casts too: with it up,
--           TERRA's Cure never landed ("restores ?" on every cast, her HP
--           falling while her MP paid).  The heal line is the bag.
--   healer  TERRA (0) takes the one care turn a round, with Potions (the
--           driver's own choice in battle), so CELES's turn stays Runic and
--           EDGAR, the harder hitter, keeps swinging.  The top-up fraction is
--           the driver's healPercent; 85 bought no margin over 70 and spent
--           2-7 Potions a fight.
--   tool    AutoCrossbow, from the ROM's data: $AA is OT6_PIERCE
--           (Ot6WeapClassTbl), power 125, ignores defence, 4 MP
--           (Ot6AbilityCostTbl), and pierce is one of KEFKA's shield classes
--           (row $03).  The Bio Blaster ($A4) the old fighter's cursor named
--           resolves as spell $7D (ThrowToolsItemTbl): power 20 poison, 8 MP.
--           The driver names the tool by id, and the boost it cannot pay for
--           stays on the Fight it falls back to.
--   boost   banked to 2 and spent, up to 3; a member inside one priced round
--           of death spends every pip first (the driver's spend rule).
local FIGHT = { tactical = true, boost = true, bank = 2, items = true,
  cure = false, runic = true, healer = 0, healPercent = 70,
  tool = H.AUTOCROSSBOW }
local function kefkaFight()
  local F = H.newFightDriver("kefka", FIGHT)
  local battN, seedChecked, postN, evN, wipeN = 0, false, 0, 0, 0
  local lastParty = "?"
  local function lost(what)
    error(string.format("battle 57 (KEFKA): THE PARTY IS WIPED -- %s at f%d, " ..
      "the last living reading [%s]; no ladder reloads it (#257)", what,
      H.frame, lastParty), 0)
  end
  return H.driveUntil(function()
    -- the loss is read on every frame, before the battle gate: a wipe
    -- zeroes the HP table (#163)
    if wipeN >= 90 then lost("the battle table read wiped for 90 frames") end
    if (H.gameOverFired or 0) > 0 then lost("the run canary counted a game over") end
    if battN > 0 or H.battleLoadStarted() then return false end
    if H.fieldX() == 25 and H.fieldY() == 5 then
      lost("the lose path parked the party at the {25,5} save point")
    end
    postN = postN + 1
    evN = (H.eventRunning() or H.dialogWaiting()) and evN + 1 or evN
    return postN >= 600 and evN >= 60
  end, 90000, {
    H.call(function()
      wipeN = H.partyWipedInBattle() and wipeN + 1 or 0
      if wipeN > 0 then H.setPad({}); return end
      battN = H.battleLoadStarted() and battN + 1 or 0
      if battN >= 3 then
        postN, evN = 0, 0
        lastParty = partyLine()
        if battN == 150 and not seedChecked then
          seedChecked = true
          local ks = -1
          for s = 0, 5 do
            if monPresent(s) and monSpecies(s) == KEFKA then ks = s end
          end
          H.assertEq(ks >= 0, true, "KEFKA_NARSHE $014A on the field")
          H.assertEq(H.readByte(0x3E38 + 8 + ks * 2), 6, "gauge 6/6 seeded")
          H.assertEq(H.readByte(0x3E9C + 8 + ks * 2), 0x03, "class row $03")
          H.assertEq(H.readByte(0x3BE0 + 8 + ks * 2), 0x09,
            "weak byte exactly $09")
          H.log(string.format("[kefka] seed verified: hp=%d sh=%d -- " ..
            "fighting him for real, party [%s]", monHp(ks), monShields(ks),
            partyLine()))
          H.screenshot("kefka_engaged")
        end
        F.frame()
        return
      end
      F.idle()
      if H.dialogWaiting() then
        H.setPad(H.frame % 8 < 4 and { "a" } or {})
        return
      end
      H.setPad({})
    end),
  }, "the KEFKA fight, played once")
end

-- Budgets: input-driven fights spend real ATB rounds on every descent
-- collision and on KEFKA himself.
-- allowGameOver: a lost fight is read by the fight's own watch (the descent
-- fighter's, kefkaFight's), which raises it as the wipe it is with the
-- battle and the party's last reading; the runner's retry reloads.
H.run({ maxFrames = 300000, allowGameOver = true }, {
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
  -- The approach and the activation are separate, and the activation holds
  -- no direction at all, because a held direction starves CheckNPCs
  -- (player.asm:142).  Face him once with a held UP that cannot step,
  -- release, then use edge-A only.
  H.navTo(20, 8, { maxFrames = 6000, playBattles = true }),
  H.hold({ "up" }), H.waitFrames(8), H.release(), H.waitFrames(6),
  H.call(function()
    local po = H.readWord(0x0803)
    H.assertEq(H.fieldX() == 20 and H.fieldY() == 8, true, "at BANON's entry point")
    H.assertEq(H.readByte(0x087f + po), 0, "facing UP at BANON (EVENT_DIR 0)")
    H.assertEq(H.readByte(0x7E2000 + 7 * 256 + 20) & 0x80, 0,
      "BANON's object occupies {20,7}")
  end),
  (function()
    local aPh, hb = 0, -600
    return H.driveUntil(menuUp, 8000, {
      H.call(function()
        aPh = (aPh + 1) % 8
        if H.frame - hb >= 600 then
          hb = H.frame
          H.log(string.format("[banon] f%d (%d,%d) ctl=%s dlg=%s $59=%02X",
            H.frame, H.fieldX(), H.fieldY(), tostring(H.hasControl()),
            tostring(H.dialogWaiting()), H.readByte(0x0059)))
        end
        H.setPad(aPh < 4 and { "a" } or {})   -- pure edge-A, no direction
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
  -- 2. The assignment: P1=TERRA+EDGAR+CELES P2=CYAN+SABIN P3=LOCKE+GAU.
  -- ==================================================================== --
  H.partySelect({ { 0x00, 0x04, 0x06 },   -- P1 TERRA EDGAR CELES
                   { 0x02, 0x05 },         -- P2 CYAN SABIN
                   { 0x01, 0x0B } },       -- P3 LOCKE GAU
    { tag = "assign", menuWait = 600 }),
  H.logStep("assignment committed; riding the battle-start event"),
  H.advanceStory(landed(22), 30000, { playBattles = true }),
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
    -- All three parties, not just the one being steered: the split has
    -- already happened, and from here on nothing can heal parties 2/3
    -- without a Y switch this generator never makes.
    H.assertPartyStanding("narshe_battle")
    H.screenshot("narshe_battle")
  end),

  -- The combined run has no spare Dirk or LeatherArmor for CELES --
  -- LOCKE still owns those -- and she already carries the MithrilBlade
  -- from the TunnelArmr route.
  H.call(function()
    H.assertEq(H.readByte(0x1600 + 37 * 6 + 0x1F), 0x0A,
      "CELES retains the TunnelArmr route's MithrilBlade for reunion")
  end),
  -- This party's authored verbs (TERRA's Magic, EDGAR's Tools, CELES's
  -- Runic) are all row-exempt, so the back row is free defensive
  -- preparation for the physical descent gauntlet.
  H.setRows({ [0] = true, [4] = true, [6] = true },
    { tag = "Narshe defense rows" }),
  H.saveState("narshe_battle.mss"),

  -- ==================================================================== --
  -- 3. The descent, started immediately, played once (#311).
  -- ==================================================================== --
  descent(),

  -- It cannot heal parties 2 and 3 -- the menu shows the active party and
  -- this generator never switches with Y -- but it does not need to: they
  -- never leave the staging tile.  The assertion below covers them anyway.
  H.fieldCare({ tag = "care before KEFKA", threshold = 0.95,
                mpFloor = 0.75 }),

  H.call(function()
    H.assertEq(H.fieldX() == 19 and H.fieldY() == 36, true,
      "party 1 at (19,36), KEFKA one tile below")
    H.assertEq(H.readByte(0x1a6d), 1, "still party 1")
    for c = 0, 15 do
      if (H.readByte(0x1850 + c) & 0x07) ~= 0 then
        local base = 0x1600 + 37 * c
        H.log(string.format("char %2d party=%d level=%d hp=%d/%d mp=%d/%d",
          c, H.readByte(0x1850 + c) & 0x07, H.readByte(base + 8),
          H.readWord(base + 9), H.readWord(base + 11),
          H.readWord(base + 13), H.readWord(base + 15)))
      end
    end
    -- The exit contract: a failure here means the descent cost more than
    -- the bag could answer.
    H.assertPartyStanding("kefka_entry")
    H.log(string.format("[entry point] f%d after %d fights", H.frame, fights))
    H.screenshot("kefka_entry")
  end),
  H.saveState("kefka_entry.mss"),

  -- ==================================================================== --
  -- 4. KEFKA, played with real input, once, off the entry point just
  --    generated: the exact state battle_kefka and gen_kefka_won will boot.
  -- ==================================================================== --
  H.hold({ "down" }), H.waitFrames(4), H.release(), H.waitFrames(8),
  H.driveUntil(function() return H.battleLoadStarted() end, 2000, {
    H.hold({ "a" }), H.waitFrames(8), H.release(), H.waitFrames(8),
  }, "clean A into KEFKA -> battle 57"),
  H.waitUntil(function() return H.battleActive() end, 3000, "Kefka up", 10),
  kefkaFight(),
  H.call(function()
    H.log(string.format("[kefka] battle 57 WON at f%d", H.frame))
    H.screenshot("kefka_won_played")
  end),

  H.call(function()
    local atSave = H.fieldX() == 25 and H.fieldY() == 5
    H.assertEq(atSave, false,
      "NOT at the {25,5} save point -- the lose path did not run")
    H.assertEq(H.battleLoadStarted(), false, "the fight is over")
    H.log(string.format("[narshe_battle] the win stands at f%d", H.frame))
  end),
  H.logStep(function()
    return string.format("Kefka beaten at frame %d -- v0.3's stop line; the win tail is gen_kefka_won's (issue #3)", H.frame)
  end),
})
