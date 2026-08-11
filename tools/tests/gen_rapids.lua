-- gen_rapids.lua -- from scenario_hub.mss into TERRA/BANON/EDGAR's scenario:
-- the resumed raft ride down the lower Lete River and the landing on the
-- World of Balance north-east of Narshe.
-- Generates two states:
--   rapids_start.mss  map 113 at the ride's re-entry tile (104,61), TERRA +
--                     EDGAR + BANON aboard with the RAFT sprite, upstream of
--                     the step's one forced fight.  This is the cheap entry
--                     point for anything that wants `battle 8, RIVER`
--                     without replaying the hub.
--   rapids_done.mss   the World of Balance at (93,41), on foot and
--                     controllable: the ride finished, the overland walk to
--                     Narshe not started.  gen_terra_narshe rides from here.
--
-- One event, three doors.  BANON {8,10}, TERRA {7,11} and EDGAR {9,11} on the
-- hub map are three NPCs sharing one `set_npc_event _cb094e`
-- (npc_prop.asm:489, :497, :505), so the split is three ways rather than
-- five, and which of the three is talked to does not matter.  TERRA (obj 19)
-- is the one used here, because the states are named for her.
--
-- The upstream step's two hazards do not occur here.
-- gen_scenario.lua's river needed a steering driver and two hand-walked
-- handoffs.  This continuation needs neither, and the reason is worth
-- recording: _cb094e (:39355-39461) contains no
-- `choice` opcode and no `player_ctrl_on` between its map load and its last
-- `wait_obj`.  Read the whole event and what is left is four
-- `obj_script SLOT_1, ASYNC { move … }` / `wait_obj SLOT_1` pairs with
-- battles between them.  Specifically:
--
--   * The vanilla grind loop is upstream.  It is _cb07f2's option 0
--     (:39152-39197, `if_switch $0176=0, _cb07f2`), reached from the ride
--     _cb0657 starts.  This event re-enters map 113 at (104,61), past it.
--     Nothing on this step asks the player which way to go, so the
--     driver below does not steer a cursor; it asserts that no multiple
--     choice opens ($056F >= 2 while the dialog is input-ready is a
--     hard error), which states the same fact as a test.
--   * The facing-down handoffs belong to map 114.  _cb051c/_cb055c both open
--     `if_switch $01B2=0, EventReturn`, where $01B2 is bit 2 of $1EB6, the
--     engine's live control-flags byte, meaning "facing down"
--     (field/event.asm:5415-5432), and they are EventTrigger::_114's
--     (event_trigger.asm:464-468).  This step never loads map 114.  It runs
--     113 -> world, end of story.
--
-- Control is on for the entire ride, so hasControl() is not a progress gate
-- here and is never used as one below.  :39391 `call _cacb95`, and _cacb95
-- ends `update_party / player_ctrl_on` (:31276-31283), runs before
-- `load_map 113`.  The field control flag therefore reads true from the
-- first frame on the raft while the object script owns SLOT_1's movement
-- anyway.  Every gate in this script is map id + position + the world-mode
-- word; the pad is neutral except for A into a battle or an open dialog.
--
-- The step has one forced fight and up to two more on a coin flip.  The
-- survey called `battle 8, RIVER` (:39412) "the scenario's only combat",
-- which is true of the forced fights but not of the step:
--       :39428  call _cb048f   ->  if_rand ; battle 8, RIVER   (:38659-38666)
--       :39446  call _cb0486   ->  if_rand ; battle 7, RIVER   (:38653-38658)
-- are both real, both on this step's critical path, and each fires about half
-- the time.  So the driver names and logs every battle it meets, and the
-- run's battle count is reported rather than assumed.
--
-- Issue #75: the fights are played rather than write-cleared, and this
-- generator makes no state writes.  The driver's edge-tapped A is the fighter
-- (A opens the acting character's command list, A confirms its first entry, A
-- takes the default target): TERRA and EDGAR Fight the default enemy while
-- BANON's first command is Health, the free party heal his presence provides.
-- Banon's death is an immediate game over, which is why the
-- battle-clear write was here at all.  The driver watches his battle HP
-- every frame (slot found via $3ED8+2s == 14 on each fight's rising edge)
-- and fails the run with the fight's numbers if he stays at 0, giving a
-- #74-style balance finding at the moment of loss instead of a
-- timeout at the game-over screen.  gen_scenario's river fights the same
-- way and carries the fuller rationale.
--
-- rapids_done is verified by reload.  A calm capture does not imply a calm
-- boot on the world map: gen_sabin_gau measured a
-- reproducible boot-into-battle from a capture whose live timeline sailed
-- on calm (2026-08-03, the input-driven-root pilot).  So the world-map
-- generation here is captured in memory, reloaded (becoming the consumer's
-- timeline), and only emitted once the reload sits calm at (93,41) for 300
-- frames; a boot battle is fled with real input (hold L+R, since WoB randoms
-- are runnable) and the post-battle world reload restores this tile
-- with the danger counter zeroed, where the next attempt recaptures.
--
-- What `battle N` resolves to (field/event.asm EventBattle, :1910-1922): the
-- group index is scaled by four (two formation words per group) and
-- UpdateBattleGrpRng takes the second word 1/4 of the time.  So from
-- event_battle_group.dat: group 8 -> formation 35 (3/4) or 37 (1/4); group 7
-- -> formation 38 (3/4) or 39 (1/4).  The species, hp and OT6 shield counts
-- are read off battle RAM on each fight's rising edge and logged, because a
-- balance claim about this step has to rest on what the ROM seeds.
local H = dofile("tools/tests/lib/ot6.lua")
local HUB = "build/states/scenario_hub.mss.lua"

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
local function objX(i) return H.readWord(0x086a + 0x29 * i) >> 4 end
local function objY(i) return H.readWord(0x086d + 0x29 * i) >> 4 end
local function facing() return H.readByte(0x087f + H.readWord(0x0803)) end
local function seq(steps) return H.cond(function() return true end, steps) end

-- multiple-choice state (src/field/text.asm): $056F is the option count and
-- is only final once the dialog is input-ready; it is field RAM the battle
-- module scribbles, so it is never read during a fight.
local CH_MAX = 0x056F
-- battle readouts: species $57c0+2i, hp $3bfc+2i, shields $3e40+2i
-- (even = current, odd = max -- metrics_battle.lua:110)
local function monSpecies(i) return H.readWord(0x57c0 + i * 2) end
local function monHp(i) return H.readWord(0x3bfc + i * 2) end
local function monMaxHp(i) return H.readWord(0x3c1c + i * 2) end
local function monShields(i) return H.readByte(0x3e40 + i * 2) end
local function monPresent(i) return H.readByte(0x3aa8 + i * 2) % 2 == 1 end

local FACE = { up = 0, right = 1, down = 2, left = 3 }
local NEIGHBOURS = {
  { 0, 1, "up" }, { 0, -1, "down" }, { -1, 0, "right" }, { 1, 0, "left" },
}

-- gen_scenario_locke's talkToObj, unchanged: approach re-resolved every 30
-- frames, facing computed from the live delta, a soft round before a hard one.
local function talkToObj(obj, what, maxF)
  local engaged = false
  local function objAt() return objX(obj), objY(obj) end
  local function adjacent()
    local ox, oy = objAt()
    return math.abs(ox - H.fieldX()) + math.abs(oy - H.fieldY()) == 1
  end
  local apFrame, apPick = -1000, nil
  local function approach()
    if H.frame - apFrame >= 30 then
      apFrame = H.frame
      local ox, oy = objAt()
      apPick = { ox, oy + 1 }
      for _, c in ipairs(NEIGHBOURS) do
        local cx, cy = ox + c[1], oy + c[2]
        if H.bfsPath(cx, cy) then apPick = { cx, cy }; break end
      end
    end
    return apPick
  end
  local function walkStep()
    return H.navTo(function() return approach()[1] end,
                   function() return approach()[2] end, {
      maxFrames = maxF or 20000,
      playBattles = true,
      arrive = function()
        return engaged or (adjacent() and H.hasControl() and H.tileAligned())
      end,
    })
  end
  local function pokeStep(round, budget, hard)
    local started, waited, aPh = 0, 0, 0
    return H.driveUntil(function()
      started = (H.eventRunning() or H.dialogWaiting()) and started + 1 or 0
      if started >= 6 then engaged = true; return true end
      waited = waited + 1
      return not hard and waited > budget
    end, budget + 120, {
      H.call(function()
        aPh = (aPh + 1) % 8
        if not (H.hasControl() and H.tileAligned() and adjacent()) then
          H.setPad({}); return
        end
        local ox, oy = objAt()
        local dx, dy = ox - H.fieldX(), oy - H.fieldY()
        local dir = dx == 1 and "right" or dx == -1 and "left"
                 or dy == 1 and "down" or "up"
        if facing() ~= FACE[dir] then H.setPad({ [dir] = true }); return end
        H.setPad(aPh < 4 and { "a" } or {})
      end),
    }, string.format("%s: activation round %d", what, round))
  end
  return seq({
    H.call(function() engaged, apFrame, apPick = false, -1000, nil end),
    walkStep(), pokeStep(1, 600, false),
    -- flat, not repeatN: it cannot replay navTo/driveUntil bodies
    H.cond(function() return not engaged end,
      { walkStep(), pokeStep(2, 900, true) }, {}),
    H.release(),
  })
end

-- ------------------------------------------------------------ the driver --
-- FIGHT every battle with real input (issue #75 -- see the header), tap every
-- dialog, refuse every choice, touch nothing else.  `fights` accumulates
-- one row per fight so the run can report what it actually met instead of
-- what the route expected.
--
-- THE FIGHTER is gen_scenario's menu-episode machine (its header carries
-- the full story): tap-A alone never heals, because BANON's first command
-- is FIGHT and his Health is ROW 1 (char_prop.asm:321).  From a settled
-- battle menu (flag held 4 straight frames), one button per 30-frame
-- pulse, 6 held + 24 released:
--     BANON (14)          down A A     Health
--     EDGAR (4), tier 2+  down A A A   Tools -> AutoCrossbow (escalation)
--     everyone else       A A          Fight, default target
-- A loss (Banon down 90 straight frames, or a wipe) sets `lost` for the
-- retry ladder instead of erroring: reload the rapids_start checkpoint,
-- escalate the tier, ride again.  Three attempts, then fail with every
-- attempt's numbers on the record.
local BCHID, BCHP = 0x3ed8, 0x3bf4
local MENU, ACTOR = 0x7bca, 0x62ca
local BP = 0x3e9c                  -- banked boost points, +slot*2
local fights = {}
local lost = nil
-- The per-turn action, built LIVE (the boost prefix reads the actor's
-- banked BP this instant) -- gen_scenario's seqFor, minus SABIN (this
-- raft is TERRA + EDGAR + BANON).  Boost is the system's own lever: bank
-- to the threshold, dump it on the action (R raises pending, cap 3).
-- This party has no third attacker to escalate to, so tier 3 varies the
-- BANKING instead -- dump at 1 BP rather than 2 -- which changes every
-- input from the first turn on and reshuffles the whole ride.
local function seqFor(id, tier, slot)
  local bp = H.readByte(BP + slot * 2)
  local boostMin = tier >= 3 and 1 or 2
  local boost = bp >= boostMin and math.min(bp, 3) or 0
  local seq = {}
  for _ = 1, boost do seq[#seq + 1] = "r" end
  local function push(...)
    for _, b in ipairs({ ... }) do seq[#seq + 1] = b end
    return seq
  end
  if id == 14 then return push("down", "a", "a") end          -- Health
  if id == 4 and tier >= 2 then
    return push("down", "a", "a", "a")                        -- AutoCrossbow
  end
  return push("a", "a")                                       -- Fight
end
local function rideUntil(pred, what, budget, tier)
  tier = tier or 1
  local phase, battN, dlgN, hb = 0, 0, 0, -900
  local bt = nil                 -- live fight: { row, banon, dead }
  local mStreak, mSeq, mIdx, mTick, mStall = 0, nil, 1, 0, 0
  local function partyLine()
    local p = {}
    for e = 0, 3 do
      p[#p + 1] = string.format("%d/%d", H.readWord(BCHP + e * 2),
        H.readWord(0x3c1c + e * 2))
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
  return H.driveUntil(pred, budget or 40000, {
    H.call(function()
      phase = (phase + 1) % 8
      if H.frame - hb >= 900 then
        hb = H.frame
        H.log(string.format("rapids f%d map=%d (%d,%d) ctl=%s batt=%s dlg=%s " ..
          "ev=%s bright=%d chMax=%d world=%s fights=%d",
          H.frame, map(), H.fieldX(), H.fieldY(), tostring(H.hasControl()),
          tostring(H.battleLoadStarted()), tostring(H.dialogWaiting()),
          tostring(H.eventRunning()), bright(), H.readByte(CH_MAX),
          tostring(H.worldMode()), #fights))
      end

      battN = H.battleLoadStarted() and battN + 1 or 0
      dlgN  = H.dialogWaiting() and dlgN + 1 or 0

      -- 1. A CHOICE HERE WOULD MEAN THE ROUTE IS WRONG.  _cb094e has no
      --    `choice` opcode, so any prompt with >= 2 options is a fork this
      --    file does not know about -- and A-mashing an unknown fork on this
      --    river is exactly how the upstream step found the vanilla grind
      --    loop.  Fail loudly instead.  Read only when no battle is up (the
      --    battle module scribbles $056F) and only once the dialog is
      --    input-ready (it counts options as the text types out,
      --    field/text.asm:684).
      if battN == 0 and H.dialogWaiting() and H.readByte(CH_MAX) >= 2 then
        H.screenshot("rapids_unexpected_choice")
        error(string.format("rapids: a %d-option choice opened on map %d at " ..
          "f%d -- _cb094e has no `choice` opcode, so the route is wrong",
          H.readByte(CH_MAX), map(), H.frame), 0)
      end

      -- 2. battle: name it once on the rising edge, then FIGHT it -- the
      --    same edge-tapped A drives menus, targets and victory text
      --    (TERRA/EDGAR Fight, BANON Health -- see the header).  No writes.
      if battN >= 3 then
        if battN == 3 then
          local w = H.formationWords()
          local row = { frame = H.frame, slots = {} }
          H.log(string.format("rapids: BATTLE #%d up f%d formation words " ..
            "(%04X %04X %04X %04X %04X %04X)", #fights + 1, H.frame,
            w[1], w[2], w[3], w[4], w[5], w[6]))
          for i = 0, 5 do
            if monPresent(i) then
              H.log(string.format("   slot %d species $%04X hp=%d/%d shields=%d",
                i, monSpecies(i), monHp(i), monMaxHp(i), monShields(i)))
              row.slots[#row.slots + 1] = {
                sp = monSpecies(i), hp = monMaxHp(i), sh = monShields(i) }
            end
          end
          fights[#fights + 1] = row
          bt = { row = row, banon = nil, dead = 0, f0 = H.frame }
          H.screenshot(string.format("rapids_battle%d", #fights))
        end
        if bt then
          bt.gone = 0
          bt.lastParty = partyLine()
          -- Banon's slot once the load has settled (the char-id table is
          -- battle scratch; 30 straight frames of the HP signal prove the
          -- battle module owns it)
          if battN == 30 and bt.banon == nil then
            for s = 0, 3 do
              if H.readByte(BCHID + s * 2) == 14 then bt.banon = s end
            end
            H.log(string.format("rapids: #%d banon slot=%s party [%s]",
              #fights, tostring(bt.banon), partyLine()))
          end
          if battN % 300 == 0 then
            H.log(string.format("rapids: #%d f%d party [%s] vs %s",
              #fights, H.frame, partyLine(), monsterLine()))
          end
          if bt.banon then
            bt.dead = H.readWord(BCHP + bt.banon * 2) == 0 and bt.dead + 1
                      or 0
            local wiped = true
            for e = 0, 3 do
              if H.readWord(0x3c1c + e * 2) > 0
                 and H.readWord(BCHP + e * 2) > 0 then wiped = false end
            end
            if bt.dead >= 90 or wiped then
              lost = string.format("%s in battle #%d at f%d (started f%d, " ..
                "tier %d) -- party [%s] vs %s",
                wiped and "PARTY WIPED" or "BANON DOWN", #fights, H.frame,
                bt.f0, tier, partyLine(), monsterLine())
              H.log("rapids: " .. lost)
              H.screenshot(string.format("rapids_lost%d", #fights))
              return            -- the attempt's pred sees `lost` and ends
            end
          end
        end
        -- act: outside a settled menu, edge-tap A; inside one, run the
        -- episode machine (see the header)
        if bt == nil or bt.banon == nil or H.readByte(MENU) == 0 then
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
          H.log(string.format("rapids: #%d cast f%d slot=%d char=%d bp=%d " ..
            "seq=%s | party [%s] vs %s", #fights, H.frame, slot, id,
            H.readByte(BP + slot * 2), table.concat(mSeq, ","), partyLine(),
            monsterLine()))
        end
        mTick = mTick + 1
        local ph = mTick % 30
        local btn
        if mIdx <= #mSeq then
          btn = mSeq[mIdx]
        elseif mStall < 2 then
          btn = "a"               -- a prompt the sequence did not know
        elseif mStall < 4 then
          btn = "b"               -- back out (an MP refusal, a dead end)
        else
          mSeq = nil              -- rebuild from wherever the cursor is
          H.setPad({})
          return
        end
        if ph < 6 then H.setPad({ [btn] = true }) else H.setPad({}) end
        if ph == 29 then
          if mIdx <= #mSeq then mIdx = mIdx + 1 else mStall = mStall + 1 end
        end
        return
      end
      -- falling edge, debounced like the rising one (shared signal RAM)
      if bt then
        bt.gone = (bt.gone or 0) + 1
        if bt.gone >= 3 then
          H.log(string.format("rapids: battle #%d done at f%d (%d frames) " ..
            "-- party [%s]", #fights, H.frame, H.frame - bt.f0,
            bt.lastParty or "?"))
          bt = nil
        end
      end

      -- 3. plain dialog: edge-tap through it ($0168's "…ride the rapids
      --    toward Narshe" is TEXT_ONLY but still waits for a keypress)
      if dlgN >= 3 then H.setPad(phase < 4 and { "a" } or {}); return end

      -- 4. the raft moving, fades, map loads: hands off
      H.setPad({})
    end),
  }, what)
end

-- n consecutive frames on `m` with the screen fully up and no fight running.
-- Says why it is not satisfied every 600 frames: a settle predicate that just
-- returns false is the worst thing in this harness to debug.
local function onMap(m, n)
  local cnt, hb = 0, -600
  return function()
    local okMap, okBright = map() == m, bright() >= 15
    local okBatt = not H.battleLoadStarted()
    local ok = okMap and okBright and okBatt
    cnt = ok and cnt + 1 or 0
    if not ok and H.frame - hb >= 600 then
      hb = H.frame
      H.log(string.format("onMap(%d) f%d blocked: map=%s(%d) bright=%s(%d) " ..
        "batt=%s at (%d,%d) ev=%s", m, H.frame, tostring(okMap), map(),
        tostring(okBright), bright(), tostring(okBatt),
        H.fieldX(), H.fieldY(), tostring(H.eventRunning())))
    end
    return cnt >= (n or 20)
  end
end

local function onWorld(n)
  local cnt, hb = 0, -600
  return function()
    local ok = H.worldMode() and H.worldHasControl() and H.worldAligned()
           and bright() >= 15 and not H.battleLoadStarted()
    cnt = ok and cnt + 1 or 0
    if not ok and H.frame - hb >= 600 then
      hb = H.frame
      H.log(string.format("onWorld f%d blocked: $1F64=%04X world=%s ctl=%s " ..
        "algn=%s bright=%d batt=%s field=(%d,%d) map=%d", H.frame,
        H.readWord(0x1f64), tostring(H.worldMode()),
        tostring(H.worldHasControl()), tostring(H.worldAligned()), bright(),
        tostring(H.battleLoadStarted()), H.fieldX(), H.fieldY(), map()))
    end
    return cnt >= (n or 20)
  end
end

local function logParty(tag)
  for c = 0, 15 do
    if (H.readByte(0x1850 + c) & 0x07) ~= 0 then
      local base = 0x1600 + 37 * c
      H.log(string.format("%s char %2d actor=%02X level=%d hp=%d/%d mp=%d/%d",
        tag, c, H.readByte(base), H.readByte(base + 8),
        H.readWord(base + 9), H.readWord(base + 11),
        H.readWord(base + 13), H.readWord(base + 15)))
    end
  end
end

-- 120000 was the battle-clear-write-era budget; input-driven fights spend
-- real ATB rounds, and the reload-verified generation replays its own boot
-- ------------------------------------------------------ the retry ladder --
-- gen_scenario's ladder, on this step's own checkpoint: a lost ride 2 is
-- accepted, the rapids_start-moment capture is reloaded (a player
-- reloading their save), and the ride is taken again with the fighter
-- escalated (tier 2+ spends EDGAR's turns on AutoCrossbow), which
-- reshuffles every subsequent interleaving and roll.  Three attempts,
-- then fail with every attempt's numbers already logged.
local rideBlob, rideWon = nil, false
local function ride2Attempt(n)
  local ldReq
  return H.cond(function() return not rideWon end, {
    H.cond(function() return n > 1 end, {
      H.logStep(function()
        return string.format("rapids: ATTEMPT %d -- reloading the " ..
          "rapids_start checkpoint after a loss (%s)", n, tostring(lost))
      end),
      H.call(function() ldReq = H.requestLoadState(rideBlob) end),
      H.waitFrames(2),
      H.call(function() H.checkReq(ldReq, "attempt " .. n .. ": reload") end),
      H.waitFrames(60),
    }, {}),
    H.call(function() lost = nil end),
    (function()
      local worldPred = onWorld(20)
      return rideUntil(function() return lost ~= nil or worldPred() end,
        string.format("the rest of the rapids, attempt %d: out onto the " ..
          "world map", n), 110000, n)
    end)(),
    H.release(),
    H.waitFrames(30),
    H.call(function()
      if lost == nil then
        rideWon = true
        H.log(string.format("rapids: attempt %d WON the ride (%d fights " ..
          "logged so far, lost attempts included)", n, #fights))
      end
    end),
  }, {})
end

-- THE RELOAD-VERIFIED WORLD GENERATE (gen_sabin_gau's pattern, see the
-- header).  Capture in memory, reload the capture -- becoming the
-- consumer's timeline -- and give it 300 frames.  Calm and parked at
-- (93,41) -> that blob is the generated savestate.  A battle instead ->
-- FLEE it with real input (hold L+R; risking a couple of rounds of chip on
-- BANON beats fighting a fight the fixture's consumers will never see) and
-- recapture: the party never stepped, so the post-battle world reload
-- restores this exact tile with the danger counter zeroed.  Three attempts,
-- then fail the generation loudly rather than emit a state nobody can boot.
local genBlob, genDone = nil, false
local function genAttempt(n)
  local tag = string.format("[rapids_done] generation attempt %d", n)
  local saveReq, loadReq
  return H.cond(function() return not genDone end, {
    H.call(function() saveReq = H.requestSaveState() end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(saveReq, tag .. ": capture")
      genBlob = saveReq.blob
      H.log(string.format("%s: captured %d bytes at world (%d,%d) f%d -- " ..
        "reloading to verify the consumer's boot", tag, #genBlob,
        H.worldX(), H.worldY(), H.frame))
      loadReq = H.requestLoadState(genBlob)
    end),
    H.waitFrames(2),
    H.call(function() H.checkReq(loadReq, tag .. ": verify reload") end),
    H.waitFrames(300),
    H.cond(function()
      return H.worldMode() and H.worldHasControl() and H.worldAligned()
         and H.worldX() == 93 and H.worldY() == 41
    end, {
      H.call(function()
        genDone = true
        H.log(tag .. ": reload stayed calm at (93,41) -- verified")
      end),
    }, {
      H.logStep(function()
        return string.format("%s: reload NOT calm ($E8=%02X bls=%s at " ..
          "%d,%d) -- flee, re-settle, recapture", tag, H.readByte(0x00e8),
          tostring(H.battleLoadStarted()), H.worldX(), H.worldY())
      end),
      H.driveUntil(function()
        return H.worldMode() and H.worldHasControl() and H.worldAligned()
      end, 20000, {
        H.call(function()
          if H.battleLoadStarted() then
            H.setPad({ l = true, r = true })   -- flee, with real input
          else
            H.setPad({})
          end
        end),
      }, tag .. ": flee the boot battle, ride out the world reload"),
      H.release(),
      H.waitFrames(30),
      H.call(function()
        -- the party never STEPPED, so the post-battle reload restores this
        -- exact tile (move.asm:916-921); drift here is a harness bug
        H.assertEq(H.worldX() == 93 and H.worldY() == 41, true,
          tag .. ": still parked on (93,41) after the flee")
      end),
    }),
  }, {})
end

H.run({ maxFrames = 200000 }, {
  H.loadState(HUB),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 9, "booted on map 9, the scenario hub")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq((H.readByte(0x185d) & 0x07) ~= 0, true,
      "SCENARIO_MOG (char 13) is the party")
    H.assertEq(sw(0x0021), 0, "$0021 clear -- TERRA/BANON's scenario not done")
    H.assertEq(sw(0x032C), 1, "$032C set -- TERRA's scenario NPC is on the map")
    H.assertEq(sw(0x0133), 1,
      "$0133 set -- the (8,6) save point takes its short, ctrl-restoring path")
    local p = H.bfsPath(objX(19), objY(19) + 1)
    H.log(string.format("[hub] f%d at (%d,%d); TERRA obj 19 at (%d,%d), " ..
      "approach from below: %s", H.frame, H.fieldX(), H.fieldY(),
      objX(19), objY(19), p and (#p .. " steps") or "no path"))
  end),

  -- ===================================================================== --
  -- ENTER.  Talk to TERRA (obj 19, {7,11}) -> _cb094e.
  -- ===================================================================== --
  talkToObj(19, "TERRA's scenario NPC"),

  -- ===================================================================== --
  -- THE RIDE, PART 1: the hub tear-down, dlg $0168, and `load_map 113,
  -- {104,61}`.  Generate before the forced fight so a battle test can boot
  -- here.
  -- ===================================================================== --
  rideUntil(onMap(113, 20), "the raft re-entry on map 113", 30000),
  H.release(),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 113, "on map 113, the LETE RIVER, aboard the raft")
    H.assertEq(H.battleLoadStarted(), false, "no battle")
    H.assertEq(#fights, 0, "generated UPSTREAM of the forced fight")
    H.assertEq(H.readByte(CH_MAX), 0, "no choice prompt open")
    -- the party _cb094e assembled: TERRA (0) + EDGAR (4) + BANON (14).
    -- $185E is the byte that settles the WEDGE/BANON symbol collision:
    -- const.inc gives both id 14 and the disassembly's picker prints the
    -- first match, so the event reads `vehicle WEDGE` and means Banon.
    H.assertEq((H.readByte(0x1850) & 0x07) ~= 0, true, "TERRA in the party")
    H.assertEq((H.readByte(0x1854) & 0x07) ~= 0, true, "EDGAR in the party")
    H.assertEq((H.readByte(0x185e) & 0x07) ~= 0, true,
      "BANON in the party ($185E -- char 14, the `WEDGE` the event names)")
    H.assertEq((H.readByte(0x185d) & 0x07) ~= 0, false, "SCENARIO_MOG gone")
    H.assertEq(sw(0x0021), 0, "$0021 still clear -- the scenario is not done")
    logParty("[rapids_start]")
    H.log(string.format("[rapids_start] f%d map=%d (%d,%d) bright=%d ctl=%s",
      H.frame, map(), H.fieldX(), H.fieldY(), bright(),
      tostring(H.hasControl())))
    H.screenshot("rapids_start")
  end),
  H.saveState("rapids_start.mss"),
  H.logStep(function()
    return string.format("rapids_start generated at frame %d", H.frame)
  end),
  -- the ladder's checkpoint: the same moment rapids_start captures
  (function()
    local ckReq
    return seq({
      H.call(function() ckReq = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(ckReq, "rapids_start checkpoint")
        rideBlob = ckReq.blob
        H.log(string.format("rapids: ride-2 checkpoint captured (%d bytes) " ..
          "at f%d", #rideBlob, H.frame))
      end),
    })
  end)(),

  -- ===================================================================== --
  -- THE RIDE, PART 2: `battle 8, RIVER`, the two if_rand fights, and the
  -- spill onto the World of Balance at (93,41) (:39455-39459).  Up to
  -- three input-driven attempts (see the ladder above).
  -- ===================================================================== --
  ride2Attempt(1),
  ride2Attempt(2),
  ride2Attempt(3),
  H.call(function()
    if not rideWon then
      error(string.format("rapids: BANON did not survive any of 3 " ..
        "attempts -- last loss: %s -- the per-attempt numbers above are " ..
        "the balance finding (#74-style); do not rig this segment",
        tostring(lost)), 0)
    end
  end),
  H.call(function()
    H.assertEq(H.worldMode(), true, "on the world map (set_script_mode WORLD)")
    H.assertEq(H.readWord(0x1f64) & 0x3FF, 0, "on the World of Balance")
    H.assertEq(H.worldX(), 93, "world spawn x=93 (`load_map 0, {93,41}`)")
    H.assertEq(H.worldY(), 41, "world spawn y=41")
    H.assertEq(H.readByte(0x11fa) & 0x03, 0,
      "on foot -- the RAFT sprite was cosmetic and `vehicle … NONE` cleared it")
    H.assertEq(H.worldHasControl(), true, "controllable")
    H.assertEq(H.battleLoadStarted(), false, "no battle")
    H.assertEq(sw(0x0021), 0, "$0021 still clear -- the scenario is not done")
    H.assertEq((H.readByte(0x185e) & 0x07) ~= 0, true, "BANON still aboard")
    H.assertEq(#fights >= 1, true,
      string.format("the forced `battle 8, RIVER` was met (%d fights)", #fights))
    for i, f in ipairs(fights) do
      local parts = {}
      for _, s in ipairs(f.slots) do
        parts[#parts + 1] = string.format("$%04X hp%d sh%d", s.sp, s.hp, s.sh)
      end
      H.log(string.format("[battles] #%d f%d: %s", i, f.frame,
        table.concat(parts, " | ")))
    end
    logParty("[rapids_done]")
    H.log(string.format("[rapids_done] f%d world (%d,%d) $1F64=%04X",
      H.frame, H.worldX(), H.worldY(), H.readWord(0x1f64)))
    H.screenshot("rapids_done")
  end),
  genAttempt(1),
  genAttempt(2),
  genAttempt(3),
  H.call(function()
    H.assertEq(genDone, true,
      "a reload-verified calm world capture within 3 attempts")
    H.emitBlob("rapids_done.mss", genBlob)
  end),
  H.logStep(function()
    return string.format("rapids_done generated at frame %d, %d fights won",
      H.frame, #fights)
  end),
})
