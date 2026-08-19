-- gen_narshe_battle.lua -- the Battle for Narshe, from the reunion staging
-- to KEFKA's fall: v0.3's final beat and its stop line.  Boots
-- reunion_ready.mss, the map-22 staging the reunion cutscene ends on
-- (party at (20,9), $0045 set), and generates three states:
--
--   narshe_battle.mss   the defense live: parties assigned and parked at
--                       {20,10}/{18,10}/{22,10}, twelve marches walking,
--                       $0132=1, first controllable frame after "Go!!"
--   kefka_entry.mss  party 1 at (19,36), KEFKA one tile below, the
--                       descent done.  This is battle_kefka's boot; a suite
--                       test should be a savestate load plus a short fight
--                       rather than a 5,400-frame descent.
--
-- (kefka_won.mss belongs to gen_kefka_won, one file downstream; see step 5.)
--
-- Issue #75: this file plays with real input.  The battle-clear write that
-- used to clear every descent collision and KEFKA himself is gone, and this
-- script writes no emulated game state.  What replaced it:
--  * descent collisions are fought: the menu-episode fighter below
--    (gen_scenario's cadence) spends each actor's turn, with boost banked to
--    2 and dumped, EDGAR on Tools -> AutoCrossbow from tier 2, CELES on
--    Runic from tier 3, and everyone else on Fight.  Collision battles
--    auto-engage the collided party (gen_moogle's measured rule), so the
--    same fighter serves whichever squad a march runs into; a win resets
--    that raider's whole march as the battle-clear write win did, and
--    battle time freezes all field clocks, so the descent's measured
--    field-frame race (~5400 to the entry point vs ~6100 for a march to
--    reach BANON) is unaffected by how long the fights take.
--  * KEFKA is fought with real input, the first input-driven Kefka in this
--    chain.  His authored profile (bosses-wob.md #10): 3000 HP, gauge
--    6/6, class row $03 = slash|pierce, weak byte $09 = poison|fire.
--    P1 = TERRA+EDGAR+CELES was picked for those axes (fire,
--    BioBlaster poison, and slash/Runic); the fighter's Fights chip the
--    class row, AutoCrossbow adds pierce volume, and Runic (tier 3)
--    handles the Ice 2 telegraph.  Whether he takes damage while
--    shielded is the break system's concern (shields attenuate and
--    the break doubles; battle_break.lua); the fighter only plays.
--  * Losses are handled the way a player handles them: a retry ladder
--    (gen_scenario's) reloads an in-run checkpoint, which is the script's
--    equivalent of reloading a save, and escalates the fighter's
--    tier, which reshuffles every subsequent ATB interleaving and roll.
--    Three descent attempts (a wipe mid-descent or a march reaching BANON
--    ends the attempt), three KEFKA attempts (battle 57's loss path warps
--    the party to the {25,5} save point, which is detected and not fatal).
--    A third loss fails the generation with every attempt's numbers
--    recorded, so a partial measured result is reported rather than a
--    fabricated pass (#74).
--
-- Every field mechanism here was measured first (probe_narshe_spike*,
-- probe_kefka_npc, probe_kefka_fight; spike lineage, commits
-- a74de44/3909646/a3cd55b/510ed0d):
--  * BANON {20,7} -> _ccc605 "Prepared?" -> A picks Yes; the map-5 info
--    scene's choice converges either way.
--  * party_menu 3, RESET: state machine $2d -A-> $2e -A-> swap; cursor
--    cell = $4b+$4a+$5a; pool rows 8 wide; party p = cells $10+4p+s
--    drawn as three 2x2 boxes; Start commits iff every party non-empty
--    (else $69 error splash, self-recovering).  The driver is state-fed
--    and verifies every landing in $7E9D89.
--  * The split: P1 = TERRA+EDGAR+CELES (fire, BioBlaster poison and
--    slash/Runic, three of the four axes Kefka's rows chip under),
--    P2 = CYAN+SABIN, P3 = LOCKE+GAU.  The commit is confirmed by $1850's
--    low 3 bits per character.
--  * The defense cannot be held passively (measured twice: an east-lane
--    march reaches BANON at ~f6100 of defense time past any standing
--    formation), and bfsPath cannot see the cliff route to Kefka
--    (the model's z-carry prunes a real two-tile ledge slide at
--    (18,11), probe_narshe_edge).  So the descent launches immediately and
--    walks raider o25's measured march reversed, 18 waypoints with an
--    axis-alternating held pusher.  Field-frame timing is preserved
--    under input-driven fighting because battles freeze all field clocks.
--  * KEFKA (NPC_1, no_react, no collision): activation needs a clean
--    edge-A, because any held direction starves CheckNPCs (player.asm:142).
--    battle 57 = formation 505 = KEFKA_NARSHE $014A alone.  The win
--    runs the scripted if_b_switch $40 branch; the loss branch parks
--    the party at the {25,5} save point.
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

-- ----------------------------------------------- the input-driven fighter --
-- gen_scenario's menu-episode machine, generalized: presses start only once
-- the battle-menu flag has held 4 straight frames, then one button per
-- 30-frame pulse (6 held, 24 released, because battle menus ignore input
-- during their open animation every turn).  The per-turn sequence is built
-- from the acting character's live id and banked BP:
--     boost prefix        bank to 2, dump up to 3 (bosses-wob's "sit at
--                         2-3 BP" doctrine; battle_boost's mechanics)
--     EDGAR (4), tier 2+  down A A A   Tools -> AutoCrossbow, his kit's
--                                      whole-side opener (kits.md)
--     CELES (6), tier 3+  down A A     Runic, which absorbs KEFKA's Ice 2
--     SABIN (5), tier 3+  down A A A   Blitz -> Pummel (menu-picked,
--                                      battle_vargas's tools-shell list)
--     everyone else       A A          Fight, default target
-- A sequence that leaves the menu open (a target prompt the route did not
-- know about, or an MP refusal) taps A for two more pulses, backs out with B
-- and rebuilds from wherever the cursor is.
local BCHID, BCHP, BCMAXHP = 0x3ed8, 0x3bf4, 0x3c1c
local MENU, ACTOR = 0x7bca, 0x62ca -- battle menu open flag / whose menu
local BP = 0x3e9c                  -- banked boost points, +slot*2
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
  if id == 6 and tier >= 3 then
    return push("down", "a", "a")                             -- Runic
  end
  if id == 5 and tier >= 3 then
    return push("down", "a", "a", "a")                        -- Pummel
  end
  return push("a", "a")                                       -- Fight
end

local fights = 0
-- One fighter instance drives one stretch of play (a descent attempt, a
-- KEFKA attempt).  Call .frame(battN) every frame a battle is up (battN =
-- consecutive battle frames, caller-debounced), .idle() on the falling
-- edge; read .lost for a wipe verdict.
local function mkFighter(tier, tag)
  local F = { lost = nil }
  local bt = nil
  local mStreak, mSeq, mIdx, mTick, mStall = 0, nil, 1, 0, 0
  local phase = 0
  function F.frame(battN)
    phase = (phase + 1) % 8
    if battN == 3 then
      fights = fights + 1
      bt = { n = fights, f0 = H.frame, wiped = 0 }
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
    if bt then
      bt.lastParty = partyLine()
      if battN % 300 == 0 then
        H.log(string.format("[%s] #%d f%d party [%s] vs %s",
          tag, bt.n, H.frame, partyLine(), monsterLine()))
      end
      -- wipe watch: every fielded entity at 0 HP, 90 straight frames
      -- (past any mid-round revive the policy could produce)
      local wiped, any = true, false
      for e = 0, 3 do
        if H.readWord(BCMAXHP + e * 2) > 0 then
          any = true
          if H.readWord(BCHP + e * 2) > 0 then wiped = false end
        end
      end
      bt.wiped = (any and wiped) and bt.wiped + 1 or 0
      if bt.wiped >= 90 and not F.lost then
        F.lost = string.format("PARTY WIPED in battle #%d at f%d " ..
          "(started f%d, %d frames in, tier %d) -- party [%s] vs %s",
          bt.n, H.frame, bt.f0, H.frame - bt.f0, tier, partyLine(),
          monsterLine())
        H.log("[" .. tag .. "] " .. F.lost)
        H.screenshot(string.format("narshe_lost%d", bt.n))
      end
    end
    -- act: outside a settled menu, edge-tap A (opening dialogs, the shell
    -- text, victory pages); inside one, run the episode machine
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
      H.log(string.format("[%s] #%d cast f%d slot=%d char=%d bp=%d seq=%s",
        tag, bt.n, H.frame, slot, id, H.readByte(BP + slot * 2),
        table.concat(mSeq, ",")))
    end
    mTick = mTick + 1
    local ph = mTick % 30
    local btn
    if mIdx <= #mSeq then
      btn = mSeq[mIdx]
    elseif mStall < 2 then
      btn = "a"                 -- a prompt the sequence did not know
    elseif mStall < 4 then
      btn = "b"                 -- back out (an MP refusal, a dead end)
    else
      mSeq = nil                -- rebuild from wherever the cursor is
      H.setPad({})
      return
    end
    if ph < 6 then H.setPad({ [btn] = true }) else H.setPad({}) end
    if ph == 29 then
      if mIdx <= #mSeq then mIdx = mIdx + 1 else mStall = mStall + 1 end
    end
  end
  function F.idle(what)
    if bt then
      H.log(string.format("[%s] battle #%d done at f%d (%d frames) -- " ..
        "party [%s]%s", tag, bt.n, H.frame, H.frame - bt.f0,
        bt.lastParty or "?", what and (" -- " .. what) or ""))
      bt = nil
    end
    mStreak, mSeq = 0, nil
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
-- collision fought.  One attempt is one full descent from the narshe_battle
-- state; it ends done (party 1 parked at (19,36)), lost (a wipe read by the
-- fighter, or map 22 left outside a battle, since the game-over fade and the
-- march-reached-BANON endings both leave the map), or errors (a stuck
-- waypoint is a route or model failure rather than a fight outcome).
local descBlob, descDone = nil, false
local descLost = nil
local WAY = {
  { 18, 11 }, { 18, 13 }, { 18, 16 }, { 17, 17 }, { 17, 20 },
  { 16, 21 }, { 15, 22 }, { 14, 23 }, { 13, 24 }, { 14, 26 },
  { 15, 27 }, { 16, 28 }, { 18, 28 }, { 18, 30 }, { 18, 33 },
  { 18, 34 }, { 19, 35 }, { 19, 36 },
}
-- #122 added a few dozen cycles to every battle's init, which shifted the
-- descent's RNG alignment chain-wide.  The retained run this fixed against
-- (build/test-runs/narshe_battle.*) measured waypoints 13-16 -- (18,28)
-- through (18,34) -- as a raider (formation FFFF 001C 0065 ...) the same
-- march bumps into two to four times in a row with no rest between.  TERRA
-- (slot 0, 241 hp, the squishiest of the three and the only actor whose
-- scripted plan ever lands a hit on $001C -- EDGAR's AutoCrossbow and
-- CELES's Runic never touch it, see the header) does not reliably survive
-- that stretch, and once she is down nobody's plan can chip $001C at all:
-- $0065 dies to AutoCrossbow, $001C sits untouched at full HP, and the
-- fight cannot end (measured: battle #13 stalled at hp=355 sh=3 for the
-- full 88000-frame episode budget, all 3 attempts, identically).  A player
-- would rest before a gauntlet like that; WAY_CARE_AFTER is the same call,
-- landing right before it.
local WAY_CARE_AFTER = 12
local function descentBody(tier, wi0, wi1)
  local wi = wi0
  local battN, holdF, axis = 0, 0, 1
  local elapsed = 0
  local hb = -600
  local F = mkFighter(tier, "descent")
  return H.driveUntil(function()
    elapsed = elapsed + 1
    if elapsed >= 88000 and descLost == nil then
      descLost = string.format("descent episode unresolved after %d frames " ..
        "at (%d,%d), waypoint %d/%d (tier %d) -- retrying the defense " ..
        "checkpoint", elapsed, H.fieldX(), H.fieldY(), wi, #WAY, tier)
      H.log("[descent] LOST -- " .. descLost)
      return true
    end
    if F.lost and not H.battleLoadStarted() then
      descLost = F.lost
      return true                       -- wiped; the ladder decides
    end
    if map() ~= 22 and not H.battleLoadStarted() then
      descLost = string.format("left map 22 outside a battle (map=%d f%d " ..
        "at wp %d/%d) -- a march reached BANON or the wipe's fade ran",
        map(), H.frame, wi, #WAY)
      H.log("[descent] " .. descLost)
      return true
    end
    return wi > wi1 and H.hasControl() and H.tileAligned()
  end, 90000, {
    H.call(function()
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
  }, string.format("the descent to Kefka's entry point (tier %d, wp %d-%d)",
    tier, wi0, wi1))
end
local function descentAttempt(n)
  local ldReq
  local tier = math.min(n + 1, 3)
  return H.cond(function() return not descDone end, {
    H.cond(function() return n > 1 end, {
      H.logStep(function()
        return string.format("[descent] ATTEMPT %d -- reloading the " ..
          "defense-live checkpoint after a loss (%s)", n, tostring(descLost))
      end),
      H.call(function() ldReq = H.requestLoadState(descBlob) end),
      H.waitFrames(2),
      H.call(function() H.checkReq(ldReq, "descent attempt " .. n) end),
      H.waitFrames(60),
    }, {}),
    H.call(function() descLost = nil end),
    -- There is no value in a deliberately Fight-only opening trial here:
    -- EDGAR was selected for this party specifically because AutoCrossbow
    -- clears the four-enemy waves.  Attempt 1 uses that authored kit; later
    -- attempts add CELES's Runic and vary the battle timeline.
    descentBody(tier, 1, WAY_CARE_AFTER),
    H.release(),
    H.waitFrames(10),
    -- The rest a player takes before the recurring 001C+0065 raider
    -- corridor (waypoints 13-16, see WAY_CARE_AFTER above).  Skipped when
    -- this attempt already lost above it, so a failed care roll does not
    -- masquerade as a fresh attempt.
    H.cond(function() return descLost == nil end, {
      H.fieldCare({ tag = "care before the raider corridor " .. n,
                    threshold = 0.85, mpFloor = 0.5 }),
    }, {}),
    H.cond(function() return descLost == nil end, {
      descentBody(tier, WAY_CARE_AFTER + 1, #WAY),
      H.release(),
      H.waitFrames(10),
    }, {}),
    H.call(function()
      if descLost == nil then
        descDone = true
        H.log(string.format("[descent] attempt %d reached the entry point " ..
          "after %d collision fights", n, fights))
      end
    end),
  }, {})
end

-- -------------------------------------------------------- the KEFKA step --
-- One attempt: clean edge-A activation, the authored seed asserted, the
-- fight played to its end, and the verdict read off the scripted branch:
-- the win scene on the stage vs the {25,5} lose-path save point.
local kefkaBlob, kefkaWon = nil, false
local kefkaLost = nil
local function kefkaBody(tier)
  local F = mkFighter(tier, "kefka")
  local battN, seedChecked, postN, evN = 0, false, 0, 0
  return H.driveUntil(function()
    -- the verdict is only readable once the battle module has gone (an
    -- "Annihilated" screen zeroes the HP table, which
    -- battleLoadStarted still reads as a battle; the taps below page
    -- it).  Field coords are stale while the battle owns the RAM, so
    -- nothing positional is read until then either.
    if battN > 0 or H.battleLoadStarted() then return false end
    if H.fieldX() == 25 and H.fieldY() == 5 then
      -- battle 57's scripted loss branch: the party parked at the {25,5}
      -- save point (the defense-lost regroup)
      kefkaLost = kefkaLost or F.lost or string.format(
        "battle 57 LOST at f%d (tier %d): the lose path parked the party " ..
        "at the {25,5} save point", H.frame, tier)
      return true
    end
    postN = postN + 1
    evN = (H.eventRunning() or H.dialogWaiting()) and evN + 1 or evN
    -- Win verdict: the stage held by the win scene (_ccbcb1) for a
    -- sustained stretch, with the lose-path warp given ample time to
    -- have landed the party at {25,5} instead.  Both endings run events,
    -- so the discriminator is the save-point position, not the event.
    if postN >= 600 and evN >= 60 then
      if F.lost then kefkaLost = F.lost end   -- wiped yet no warp: record it
      return true
    end
    return false
  end, 90000, {
    H.call(function()
      battN = H.battleLoadStarted() and battN + 1 or 0
      if battN >= 3 then
        postN, evN = 0, 0
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
            "fighting him for real (tier %d)", monHp(ks), monShields(ks),
            tier))
          H.screenshot("kefka_engaged")
        end
        F.frame(battN)
        return
      end
      F.idle()
      if H.dialogWaiting() then
        H.setPad(H.frame % 8 < 4 and { "a" } or {})
        return
      end
      H.setPad({})
    end),
  }, "the KEFKA fight, played (tier " .. tier .. ")")
end
local function kefkaAttempt(n)
  local ldReq
  return H.cond(function() return not kefkaWon end, {
    H.cond(function() return n > 1 end, {
      H.logStep(function()
        return string.format("[kefka] ATTEMPT %d -- reloading the entry point " ..
          "after a loss (%s)", n, tostring(kefkaLost))
      end),
      H.call(function() ldReq = H.requestLoadState(kefkaBlob) end),
      H.waitFrames(2),
      H.call(function() H.checkReq(ldReq, "kefka attempt " .. n) end),
      H.waitFrames(60),
    }, {}),
    H.call(function() kefkaLost = nil end),
    -- activation: face him once (a held DOWN that cannot step), release,
    -- then edge-A only, because a held direction starves CheckNPCs
    H.hold({ "down" }), H.waitFrames(4), H.release(), H.waitFrames(8),
    H.driveUntil(function() return H.battleLoadStarted() end, 2000, {
      H.cond(function() return true end, {
        H.hold({ "a" }), H.waitFrames(8), H.release(), H.waitFrames(8),
      }),
    }, "clean A into KEFKA -> battle 57"),
    H.waitUntil(function() return H.battleActive() end, 3000, "Kefka up", 10),
    kefkaBody(n),
    H.call(function()
      if kefkaLost == nil then
        kefkaWon = true
        H.log(string.format("[kefka] attempt %d WON battle 57 " ..
          "at f%d", n, H.frame))
        H.screenshot("kefka_won_played")
      end
    end),
  }, {})
end

-- Budgets: the battle-clear-write era ran this file in ~120k frames;
-- input-driven fights spend real ATB rounds on every descent collision and
-- on KEFKA himself, and the ladders may replay the descent and the fight up
-- to three times each.
H.run({ maxFrames = 600000 }, {
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
    -- already happened, parties 2 and 3 are queued behind the same fight,
    -- and from here on nothing can heal them without a Y switch this
    -- generator never makes.  If this ever fires it is a finding about the
    -- walk to BANON, which plays its battles; the fix would be a care stop
    -- BEFORE the assignment, while one menu visit can still reach all
    -- seven.
    H.assertPartyStanding("narshe_battle")
    H.screenshot("narshe_battle")
  end),

  -- The old power-only Optimum call at the reunion staging was a no-op: the
  -- active character there is the scenario Moogle, while the seven heroes
  -- are only an assignment pool.  After the split the actual combined
  -- lineage has no spare Dirk or LeatherArmor anyway -- LOCKE still owns
  -- those -- and CELES already carries the MithrilBlade deliberately handed
  -- to her by the TunnelArmr route.  Preserve and name that intent rather
  -- than inventing equipment the playthrough did not acquire.
  H.call(function()
    H.assertEq(H.readByte(0x1600 + 37 * 6 + 0x1F), 0x0A,
      "CELES retains the TunnelArmr route's MithrilBlade for reunion")
  end),
  -- This party's authored verbs are all row-exempt: TERRA's Magic, EDGAR's
  -- Tools and CELES's Runic.  The descent is a physical gauntlet and the
  -- combined lineage legitimately has no spare body armor for CELES, so the
  -- back row is the player's available defensive preparation.  Tier 1 may
  -- still spend early turns on Fight (and accept its damage penalty); from
  -- tier 2 onward the route uses the three verbs this formation was built
  -- around.
  H.setRows({ [0] = true, [4] = true, [6] = true },
    { tag = "Narshe defense rows" }),
  H.saveState("narshe_battle.mss"),

  -- ==================================================================== --
  -- 3. The descent, started immediately, up to three input-driven attempts.
  --    The ladder's
  --    checkpoint is the defense-live moment the generation above captured;
  --    re-capturing it in memory keeps the reload in-run.
  -- ==================================================================== --
  (function()
    local ckReq
    return H.cond(function() return true end, {
      H.call(function() ckReq = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(ckReq, "defense-live checkpoint")
        descBlob = ckReq.blob
        H.log(string.format("[descent] checkpoint captured (%d bytes) at " ..
          "(%d,%d) f%d", #descBlob, H.fieldX(), H.fieldY(), H.frame))
      end),
    })
  end)(),
  descentAttempt(1),
  descentAttempt(2),
  descentAttempt(3),
  H.call(function()
    if not descDone then
      error(string.format("[descent] no attempt survived of 3 tries " ..
        "-- last loss: %s -- the per-attempt numbers above are the balance " ..
        "finding (#74-style); do not rig this segment", tostring(descLost)), 0)
    end
  end),

  -- Heal, before the entry point is captured.  The descent fights every
  -- collision it walks into and nothing in it heals, so the fixture this
  -- step generates shipped CELES dead at 0/217 with a Fenix Down still in
  -- the bag (measured on the pre-rename kefka_doorstep artifact,
  -- tools/audit_party_hp.py, 2026-08-11).  Everything downstream boots that:
  -- the KEFKA ladder below, battle_kefka, gen_kefka_won.  A two-character
  -- party walking into KEFKA reads as a hard boss rather than as a descent
  -- that lost somebody, which is exactly the misreading this whole class of
  -- bug produces.
  --
  -- Party 1 is TERRA, EDGAR and CELES, and TERRA and CELES both know Cure,
  -- so this casts and only reaches for the bag to revive.  mpFloor 0.75
  -- because KEFKA is the very next fight and both healers are in this
  -- party: a caster drained in the corridor walks into the boss with no
  -- Cure.  0.75 was measured to keep essentially all of the item saving
  -- while leaving the caster ready.
  --
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
    -- The exit contract.  The care stop above is the fix; this is what makes
    -- the generator fail loudly instead of shipping a casualty into the
    -- KEFKA fight and everything downstream of it.  A failure here means the
    -- descent cost more than the bag could answer, which is a finding about
    -- supplies and not a reason to lower the bar.
    H.assertPartyStanding("kefka_entry")
    H.log(string.format("[entry point] f%d after %d fights (all attempts)",
      H.frame, fights))
    H.screenshot("kefka_entry")
  end),
  H.saveState("kefka_entry.mss"),

  -- ==================================================================== --
  -- 4. KEFKA, played with real input: up to three attempts off the entry point
  --    just generated.  The checkpoint is re-captured in memory so a loss
  --    reloads the exact state battle_kefka and gen_kefka_won will boot.
  -- ==================================================================== --
  (function()
    local ckReq
    return H.cond(function() return true end, {
      H.call(function() ckReq = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(ckReq, "entry point checkpoint")
        kefkaBlob = ckReq.blob
        H.log(string.format("[kefka] entry point checkpoint captured " ..
          "(%d bytes) f%d", #kefkaBlob, H.frame))
      end),
    })
  end)(),
  kefkaAttempt(1),
  kefkaAttempt(2),
  kefkaAttempt(3),
  H.call(function()
    if not kefkaWon then
      error(string.format("[kefka] battle 57 not won in 3 attempts " ..
        "-- last loss: %s -- the per-attempt numbers above are the balance " ..
        "finding (#74-style); do not rig this fight", tostring(kefkaLost)), 0)
    end
  end),

  -- ==================================================================== --
  -- 5. Stop at the stop line.  The win above is v0.3's milestone;
  --    everything after it (the esper scene, Arvis, the walk to control)
  --    is v0.4's first link and stalls the walker (issue #3).  The tail
  --    lives in gen_kefka_won.lua, deliberately outside SAVESTATES.
  -- ==================================================================== --
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
