-- gen_sfigaro.lua -- from locke_scenario.mss (LOCKE alone, one step past the
-- three-way hub, map 75 at (47,43)) through occupied South Figaro to the
-- entry point of the rich man's secret passage.  The first link of the v0.3
-- Locke chain.
-- Generates two states:
--   sfigaro_town.mss     map 75, the gate soldier beaten and LOCKE wearing
--                        the merchant's clothes with the old man's cider
--   sfigaro_passage.mss  map 86 (7,51), inside the secret passage the
--                        grandson's password opens

-- Five things this script had to measure, each of which broke a first
-- attempt.

-- 2. The merchant's clothes are required, not decoration.  Map 86's
--    grandson, npc 4 at {6,10}, is the gate: `if_switch $0104=1, _ca7bf8`
--    else "Only people dressed as merchants may pass through"
--    (event_main.asm:18747-18752).  Nothing else on the route opens.

-- 3. One fight covers both errands.  The cafe's cider runner (map 78
--    npc 6 at {75,39}, spawn switch $0307, `_ca7d7d` -> `_ca7db8`) runs
--    `battle 10` and then, win or steal, ends `switch $01D0=1` ("Took the
--    old man's cider!", :19061).  Steal it and the same scene also hands
--    over the clothes.  The item-shop merchant on map 85 gives the clothes
--    alone, so the cafe is strictly the cheaper stop.

-- 5. A destination coordinate is not an arrival test.  `go` used to treat
--    "standing on (dx,dy)" as arrival for every crossing; map 78's front
--    room contains a walkable (22,44), the same tile the town door lands on,
--    so the walk to the exit registered arrival twenty tiles early on the
--    wrong map and the settle then waited 12000 frames for a map id that
--    never came.  Only a same-map warp has no map change to watch.

local H = dofile("tools/tests/lib/ot6.lua")
local L = H.newSeedSweep("cider steal")
local DOOR = "build/states/locke_scenario.mss.lua"

-- map compares stay masked: loaders leave flag bits in $1F64's high byte
local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
-- event switch id -> live bit (event bitfield base $1E80, bit = id & 7)
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
-- a bare step list cannot be spliced into a step list (Lua truncates a
-- non-final table.unpack to one value); H.cond with an always-true
-- predicate is the library's public way to wrap a list into a single step
local function seq(steps) return H.cond(function() return true end, steps) end

-- all eight for door staging: a door at the head of a stair can only be
-- entered diagonally (gen_edgar's finding), and a diagonal candidate has to
-- clear one extra test, that the engine produces that move there
local DIAGSTAGE = {
  { 0, 1, "up" }, { 0, -1, "down" }, { -1, 0, "right" }, { 1, 0, "left" },
  { -1, 1, "upright" }, { -1, -1, "downright" },
  { 1, -1, "downleft" }, { 1, 1, "upleft" },
}

local WATCH = { 0x0103, 0x0104, 0x0105, 0x0107, 0x001C, 0x001D, 0x001E,
                0x0317, 0x01D0, 0x01F0, 0x01F1 }
local function where(tag)
  local out = {}
  for _, s in ipairs(WATCH) do out[#out + 1] = string.format("%04X=%d", s, sw(s)) end
  H.log(string.format("[%s] f%d map=%d (%d,%d) bright=%d ctl=%s | %s",
    tag, H.frame, map(), H.fieldX(), H.fieldY(), bright(),
    tostring(H.hasControl()), table.concat(out, " ")))
end

-- Settle after a map load: a fully lit screen plus whatever else the caller
-- names, held for 20 consecutive frames, then the 30-frame margin every
-- field fixture uses.  Both halves are needed (gen_kolts's header): a
-- cutscene can report control on a black screen, and a single-sample gate
-- passes mid-load while the field module still holds the old map's state.
-- It drives rather than waits so a dialog on the arrival tile cannot stall
-- it; on a quiet field advanceStory holds the pad empty.
local function settled(n, extra)
  local cnt = 0
  return function()
    local ok = bright() >= 15 and (not extra or extra())
    cnt = ok and cnt + 1 or 0
    return cnt >= n
  end
end
local function settleField(dstMap, maxF)
  return seq({
    H.waitFrames(60),
    H.advanceStory(settled(20, function()
      return not H.worldMode() and H.tileAligned()
         and not H.battleLoadStarted() and not H.dialogWaiting()
         and (dstMap == nil or map() == dstMap)
    end), maxF or 12000, { playBattles = true }),
    H.waitFrames(30),
  })
end

local aPhase = 0

-- One short step to a waypoint on the current map.  See note 4: long BFS
-- queries on map 75 run the 4096-node cap dry and answer "no path" for
-- tiles that are plainly walkable, so every cross-town walk is a chain of
-- these rather than one query.
local function hop(tx, ty, what)
  return seq({
    H.navTo(tx, ty, { maxFrames = 12000, playBattles = true }),
    H.release(),
    H.call(function()
      H.assertEq(H.fieldX(), tx, what .. ": at x=" .. tx)
      H.assertEq(H.fieldY(), ty, what .. ": at y=" .. ty)
    end),
  })
end

-- One crossing, all three kinds in one step:
--   * ordinary walkable entrance tile    -> navTo straight onto it
--   * door tile (a wall until CheckDoor)  -> stage on a neighbour, hold in
--   * same-map warp (maps 78/83/86 are built out of them)
-- CheckDoor (field/player.asm:958-1010) only opens a tile whose tilemap
-- byte is $15/$17/$1C, and only for a party standing directly above or
-- below it; anything else stays a wall however long the button is held.
local function go(sx, sy, dm, dx, dy, what)
  local pick, startMap
  local function arrived()                       -- see note 5
    if dm ~= startMap then return map() ~= startMap end
    return H.fieldX() == dx and H.fieldY() == dy
  end
  local pickAt = -1000
  local function stage()
    if pick == nil or (H.frame - pickAt >= 90 and not arrived()) then
      pickAt = H.frame
      local fresh
      if H.bfsPath(sx, sy) then
        fresh = { sx, sy, nil }                  -- walkable: stand on it
      else
        for _, c in ipairs(DIAGSTAGE) do
          local cx, cy, move = sx + c[1], sy + c[2], c[3]
          local press = H.movePress(move)
          if H.bfsPath(cx, cy)
             and (press == move or H.canStep(cx, cy, move)) then
            fresh = { cx, cy, press }; break
          end
        end
      end
      fresh = fresh or pick or { sx, sy + 1, "up" }
      if pick == nil or fresh[1] ~= pick[1] or fresh[2] ~= pick[2]
         or fresh[3] ~= pick[3] then
        pick = fresh
        H.log(string.format("%s: staging (%d,%d)%s at f%d", what,
          pick[1], pick[2],
          pick[3] and (", hold " .. pick[3] .. " into (" .. sx .. "," .. sy .. ")")
                  or " (walk straight onto the entrance tile)", H.frame))
      end
    end
    return pick
  end
  return seq({
    H.call(function() pick, startMap = nil, map() end),
    H.navTo(function() return stage()[1] end, function() return stage()[2] end,
      { maxFrames = 20000, arrive = arrived, playBattles = true }),
    H.cond(function() return stage()[3] ~= nil end, {
      H.driveUntil(arrived, 1800, {
        H.call(function()
          aPhase = (aPhase + 1) % 8
          if H.dialogWaiting() then H.setPad(aPhase < 4 and { "a" } or {}); return end
          local hold = stage()[3]
          H.setPad(hold and { [hold] = true } or {})
        end),
      }, what .. ": hold into the door"),
    }, {}),
    H.release(),
    settleField(dm),
    H.call(function()
      H.assertEq(map(), dm, what .. ": landed on map " .. dm)
      H.log(string.format("%s: DONE map=%d (%d,%d) f%d", what,
        map(), H.fieldX(), H.fieldY(), H.frame))
    end),
  })
end

-- gen_scenario.lua's choice-steering idiom, unchanged in shape.  $056F is
-- the option count and is only final once dialogWaiting() is true (it is
-- built up as the text types out, and it is meaningless during a battle);
-- $056E is the 0-based selection; the steering presses are edges because
-- $056D latches a held direction to exactly one row (field/text.asm:368-425).
local function rideUntil(pred, what, budget, choices)
  local phase, dlgN = 0, 0
  -- `choices` ({ want, max, what } per prompt, in order) through
  -- H.newChoice (lib/ot6_field.lua): steered only once the dialog waits,
  -- each landed row asserted when its window closes
  local C = H.newChoice(choices or {}, { tag = what,
    onUp = function(n, max, c)
      H.log(string.format("%s: CHOICE #%d up (%d options) -- taking %d :: %s",
        what, n, max, c.want, c.what))
    end })
  return H.driveUntil(pred, budget or 20000, {
    H.call(function()
      phase = (phase + 1) % 8
      dlgN = H.dialogWaiting() and dlgN + 1 or 0
      if C.frame(phase) then return end
      if dlgN >= 3 then H.setPad(phase < 4 and { "a" } or {}); return end
      H.setPad({})
    end),
  }, what)
end

-- talk to `obj`, then ride what it says (steering `choices`) back to a
-- settled, controllable field
local function talkThrough(obj, what, choices, budget)
  local calm = 0
  return seq({
    H.talkToObj(obj, what),
    rideUntil(function()
      local ok = H.hasControl() and H.tileAligned() and bright() >= 15
             and not H.dialogWaiting() and not H.eventRunning()
             and not H.battleLoadStarted()
      calm = ok and calm + 1 or 0
      return calm >= 30
    end, what, budget or 20000, choices),
    H.release(),
  })
end

-- The boost is banked with real input.  Steal is the shipped boost-tiered
-- chance verb (Ot6StealBoostLevel): 0 bp rolls raw vanilla odds, and 3 bp
-- clamps the level term so vanilla's own `bcs` guarantees the steal.  LOCKE
-- opens the fight with 1 bp (Ot6InitBP) and regens +1 per unboosted action
-- (Ot6ActionEnd), and a steal attempt is itself an action, so the driver
-- steals unboosted while the bank grows (attempts 1-2 may land on their own
-- dice, and each pays Ot6StealCost's 4 MP); once the bank reads >= 3 it
-- presses R-R-R first and takes the guaranteed steal.  Worst case is three
-- attempts, 12 MP, against the pool the fixture logs.  The merchant's
-- reaction script (`if_cmd STEAL`, AIScript::_314) sets b_switch $4C and
-- ends the fight; the caller asserts $1DD2 bit 4.

-- The menu machine is armr-style: presses start only after the menu flag
-- holds 4 consecutive pulses, a new sequence is only built while the menu
-- is the command window (state $05, because a stray A from any other state
-- could queue FIGHT and kill the merchant, which this fight must never
-- produce), and any other state without a running sequence is backed out
-- with B.
local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD = 0x05
local B_SWITCH_LIVE = 0x3EBD          -- $3EB4 + ($4C >> 3); bit4 = $4C
-- What a Steal costs this attempt (#219).  Two ROM facts, neither of
-- them written out here as a number: the base is Ot6StealCost's own
-- immediate (`lda #imm / rtl`, the single authority for Steal's price),
-- and the boost ladder is H.boostPrice, the library's transcription of
-- Ot6BoostPriceFor.  Measured on this build: 4 MP unboosted, 63 at the
-- guaranteed tier, against the mp 70 LOCKE reaches his third attempt
-- with (build/attempts/boost-price-driver/lab/sfigaro-lane/diag-1.log:
-- `STEAL attempt 3 ... mp=70 (boost 3 -- guaranteed, 63 MP)` then
-- `attempt 4 ... mp=7`).  That is a seven-MP margin on a segment whose
-- ladder ends in "stolen within 3 attempts", so the ladder asks whether
-- he can pay before pressing R three times into a row the engine would
-- grey and a turn the MP gate would fizzle.
--
-- The gate is written against the rule, not against a number.  The canon
-- is "a price escalates exactly when Ot6BoostDmg multiplies the action",
-- and Ot6BoostDmg refuses cmd $05, so Steal is FLAT at every boost level
-- (the owner's chance-verb exemption, 2026-09-17): boost buys it the
-- rare/guarantee ladder, which is certainty rather than magnitude, and
-- the BP is what pays for it.  H.boostEscalates is the library's copy of
-- that gate, so this call follows the rule wherever it goes next rather
-- than having to be found and edited again.  The ladder keeps working
-- either way, because a cheaper guaranteed tier only ever passes a gate
-- it already passed -- the 63 quoted above was the escalating price, and
-- the gate now reads 4.
local STEAL_CMD = 0x05
local stealBase = nil
local function stealPrice(boost)
  if stealBase == nil then
    local ofs = H.sym("Ot6StealCost") & 0x3FFFFF
    H.assertEq(H.readRomByte(ofs), 0xA9,
      "Ot6StealCost still opens with LDA #imm -- the +1 read is Steal's price")
    stealBase = H.readRomByte(ofs + 1)
  end
  if not H.boostEscalates(STEAL_CMD) then return stealBase end
  return H.boostPrice(stealBase, boost)
end

local function stealDriver(what, maxF)
  local mStreak, mSeq, mIdx, mSub, mNoMenu, tries = 0, nil, 1, 0, 0, 0
  return H.driveUntil(function() return not H.battleLoadStarted() end,
    maxF or 30000, {
      H.call(function()
        if H.readByte(MENU) == 0 then
          mStreak, mSeq, mIdx, mSub = 0, nil, 1, 0
          mNoMenu = mNoMenu + 1
          H.setPad(mNoMenu % 2 == 0 and { "a" } or {})
          return
        end
        mNoMenu = 0
        mStreak = mStreak + 1
        if mStreak < 4 then H.setPad({}); return end
        if mSeq == nil then
          if H.readByte(MSTATE) ~= ST_CMD then
            H.setPad(mStreak % 8 < 4 and { "b" } or {})  -- unwind to the window
            return
          end
          local actor = H.readByte(ACTOR)
          local bank = H.readByte(0x3E9C + actor * 2)
          local mp = H.readWord(0x3C08 + actor * 2)
          tries = tries + 1
          local top = stealPrice(3)
          local guaranteed = bank >= 3 and mp >= top
          if guaranteed then
            mSeq = { "r", "r", "r", "down", "a", "a", "a" }  -- guaranteed tier
          else
            mSeq = { "down", "a", "a", "a" }                 -- vanilla odds; bank grows
          end
          mIdx, mSub = 1, 0
          H.log(string.format(
            "%s: STEAL attempt %d f%d actor=%d bank=%d mp=%d %s $3EBD=%02X",
            what, tries, H.frame, actor, bank, mp,
            guaranteed and string.format("(boost 3 -- guaranteed, %d MP)", top)
              or (bank >= 3
                  and string.format("(unboosted %d MP: the guaranteed tier is %d, "
                        .. "over the pool)", stealPrice(0), top)
                  or string.format("(unboosted, %d MP)", stealPrice(0))),
            H.readByte(B_SWITCH_LIVE)))
        end
        if mIdx <= #mSeq then
          H.setPad(mSub < 6 and { mSeq[mIdx] } or {})
          mSub = mSub + 1
          if mSub >= 16 then
            mSub = 0
            mIdx = mIdx + 1
            if mIdx > #mSeq then mSeq = nil end
          end
          return
        end
      end),
    }, what .. ": steal the clothes")
end

-- ===================================================================== --
-- The gate soldier, battle 11: HeavyArmor $09F x1 (formation 64), fought
-- three times per generate (B1, R1, R2).  #193 / docs/design/sfigaro-gate.md.
--
-- Map 75 rolls no randoms; the HeavyArmor the v0.17 qualification lost to
-- is this fight.  L12 LOCKE (279 HP, back row) takes a 52-59 Battle a
-- turn and, once the soldier is under half, a ~150-168 TekLaser; his
-- shields re-seed to 3 after every break.  The lib's fight driver closes
-- its whole care block once the monsters' total HP is <= 200 (the
-- finisher gate, lib/ot6.lua makePlan `totalMon > 200`), and the
-- soldier's last 200 HP is three chips and a break away, so every
-- baseline loss was LOCKE at 130-137/279 in that window planning a
-- 0-BP chip and eating the laser (build/attempts/locke-solo-lab/
-- sweep-baseline, seeds 0/2/3; seed 1's R1 at 22/279 after the driver
-- itself said "item $E9 saves").  The lab (lab_sfigaro_gate.lua) measured
-- the policies (15 seeds each, the whole $021e cycle): the shipped driver
-- lost 3/15, bank 0 alone won 15/15 but finished one fight at 15 HP,
-- healPercent 75 alone won 15/15 finishing one at 1 HP; this is the one
-- that won with a margin (15/15, no fight ending under 196 HP, 2.1
-- Potions a fight): the ride and driver as H.rideOut ships them with the
-- bank at 0 (every pip spent as it exists: the break comes sooner, so
-- fewer enemy turns), plus the one press a person makes there -- a Potion
-- when LOCKE is under GATE.endgameFloor inside the finisher window.
--
-- The ladder is the lib's (H.clearGateSoldier) in shape, with two changes:
-- the ride is this file's gateRide, and a lost fight ends the ride on the
-- wipe (the seat-based verdict held 90 frames, as the cider sweep does)
-- so the next rung reloads the pre-fight blob and re-engages on a new
-- seed.  Without that exit the run canary's pad freeze (a wipe counts as
-- a game over, #166) left the annihilated screen unpressed and the
-- attempt was filed as `no-progress` 1800 frames later, never as a loss.
-- ===================================================================== --
local GATE = {
  -- H.rideOut's driver (lib/ot6_field.lua rideOut) with bank 3 -> 0
  driver = { tactical = true, boost = true, bank = 0, items = true,
             healPercent = 60, cadence = 12 },
  endgameFloor = 175,      -- TekLaser measured up to 168 raw (the lab)
  endgameTotalMon = 200,   -- the lib's finisher gate
  wipeFrames = 90,         -- the cider sweep's wipe hold
}
local ITEMSCR, ITEMROW, BATTINV = 0x8947, 0x894F, 0x2686
local ST_ITEM, ST_TGT = 0x0A, 0x38
local BCHP, BCMAXHP = 0x3BF4, 0x3C1C
local POTION = 0xE9
local function battInvIdx(id)
  for i = 0, 251 do
    if H.readByte(BATTINV + i * 5) == id
       and H.readByte(BATTINV + i * 5 + 3) > 0 then return i end
  end
  return nil
end
local function totalMon()
  local t = 0
  for s = 0, 5 do t = t + H.readWord(0x3BFC + s * 2) end
  return t
end
-- The endgame Potion steer (the lib's item steer in shape: the absolute
-- row is scroll + cursor per actor; the battle bag is 5 bytes an entry,
-- +0 id, +3 count).  Returns true when it owned the frame.
local function newEndgameSteer(what)
  local plan, pulse = nil, 0
  return function()
    if H.readByte(MENU) == 0 then
      plan, pulse = nil, 0
      return false
    end
    local actor = H.readByte(ACTOR) & 3
    local st = H.readByte(MSTATE)
    if plan == nil then
      if st ~= ST_CMD then return false end
      local hp = H.readWord(BCHP + actor * 2)
      if hp == 0 or hp >= GATE.endgameFloor
         or totalMon() > GATE.endgameTotalMon then return false end
      local idx = battInvIdx(POTION)
      if idx == nil then return false end
      plan, pulse = { idx = idx }, 0
      H.log(string.format("[%s] endgame: f%d LOCKE %d/%d under the floor " ..
        "(%d) with the monsters at %d HP (<= %d, the driver's finisher " ..
        "gate): Item -> Potion (bag row %d) instead of the driver's turn",
        what, H.frame, hp, H.readWord(BCMAXHP + actor * 2), GATE.endgameFloor,
        totalMon(), GATE.endgameTotalMon, idx))
    end
    pulse = pulse + 1
    if pulse > 900 then
      H.log(string.format("[%s] endgame: f%d the Potion steer did not land " ..
        "in 900 frames (state %02X); handing the window back", what, H.frame, st))
      plan = nil
      return false
    end
    local on = pulse % 8 < 4
    if st == ST_CMD then
      local cur = H.readByte(0x890F + actor) & 3
      if cur == 3 then H.setPad(on and { "a" } or {})
      else H.setPad(on and { cur < 3 and "down" or "up" } or {}) end
    elseif st == ST_ITEM then
      local cur = H.readByte(ITEMSCR + actor) + H.readByte(ITEMROW + actor)
      if cur < plan.idx then H.setPad(on and { "down" } or {})
      elseif cur > plan.idx then H.setPad(on and { "up" } or {})
      else H.setPad(on and { "a" } or {}) end
    elseif st == ST_TGT then
      H.setPad(on and { "a" } or {})
    else
      H.setPad(on and { "b" } or {})
    end
    return true
  end
end
-- H.rideOut in shape, with the endgame steer ahead of the driver and the
-- wipe exit.  `lost` is the ride's verdict for the ladder: nil, or a
-- string naming the loss.
local function gateRide(what, budget, onLost)
  local phase, calm, wipedN = 0, 0, 0
  local F = H.newFightDriver(what, GATE.driver)
  local steer = newEndgameSteer(what)
  return seq({
    H.driveUntil(function()
      wipedN = H.partyWipedInBattle() and wipedN + 1 or 0
      if wipedN >= GATE.wipeFrames then
        onLost(string.format("PARTY WIPED at f%d (the lib's wipe " ..
          "predicate, %d frames)", H.frame, GATE.wipeFrames))
        return true
      end
      local ok = H.hasControl() and H.tileAligned() and bright() >= 15
             and not H.battleLoadStarted() and not H.dialogWaiting()
             and map() == 75
      calm = ok and calm + 1 or 0
      return calm >= 20
    end, budget or 30000, {
      H.call(function()
        phase = (phase + 1) % 8
        if H.battleLoadStarted() then
          if not steer() then F.frame() end
          return
        end
        F.idle()
        if H.hasControl() then H.setPad({}); return end
        H.setPad(phase < 4 and { "a" } or {})
      end),
    }, what),
    H.release(),
    H.waitFrames(30),
  })
end
-- Is the lane open?  A route to the probe tile from a SETTLED, controllable
-- frame -- never from the frame a fight ended on.
--
-- MEASURED, build/attempts/boost-price-driver/lab/sfigaro-lane/diag-1.log: the win
-- frame reads no route at all, and thirty frames later the same tile is
-- 34 steps away.  An uncapped reach walk taken beside each probe says why:
--
--   [laneprobe] B1 ... f12159 (30,43) ctl=true tile=true reach=4991 dist=nil  path=false
--   [laneprobe] B1 ... f12189 (30,43) ctl=true tile=true reach=4992 dist=34   path=true
--
-- 4991 tiles were already reachable on the win frame, so the gate was
-- open; exactly ONE tile joined the set thirty frames later, and the
-- probe tile came with it.  The only term in the passability model that
-- moves while a map stays loaded is the object layer at $7E2000
-- (ot6_field.lua stepAllowed's last test) -- the tilemap and the two prop
-- tables are loaded once per map -- so a townsperson was standing on the
-- probe tile and then stepped off it.  Where the town's NPCs are when the
-- field resumes is decided by how long the battle ran, which is why any
-- shift in battle length flips a one-frame probe; the fight driver
-- pricing its boosts (#219) is one such shift.
--
-- A person answers "can I get there" by walking, and a townsperson in the
-- doorway is something they wait a beat for.  So this waits for a frame
-- that shows the route and asserts on THAT.  Soft, so a lane that really
-- is shut fails as an assert -- a bug to fix, not a seed to re-roll.
local LANE_SETTLE = 900
local function laneSettles(probeX, probeY, tag)
  local key, t0 = "lane open: " .. tag, nil
  return seq({
    H.call(function() t0 = H.frame end),
    H.waitUntilSoft(function()
      return H.hasControl() and H.tileAligned() and bright() >= 15
         and not H.battleLoadStarted() and not H.dialogWaiting()
         and map() == 75 and H.bfsPath(probeX, probeY) ~= nil
    end, LANE_SETTLE, key, 10),
    -- said every time, so the log shows whether the settle was needed
    -- rather than leaving it to be inferred
    H.logStep(function()
      return string.format("[lane] %s: (%d,%d) read %s at f%d, %d frame(s) "
        .. "after the fight", tag, probeX, probeY,
        H.vars[key] and "open" or "SHUT", H.frame, H.frame - t0)
    end),
    H.call(function()
      H.assertEq(H.vars[key], true, string.format(
        "%s: the lane is open again -- a settled controllable frame with a "
        .. "route to (%d,%d) inside %d frames", tag, probeX, probeY,
        LANE_SETTLE))
    end),
  })
end

local function clearGate(probeX, probeY, tag)
  local blob, won = nil, false
  local L = H.newSeedSweep((tag or "gate soldier") .. " battle 11")
  local function fightOnce(n)
    local loadReq, lost = nil, nil
    return H.cond(function() return won end, {}, {
      H.logStep(function()
        return string.format("%s: battle 11 attempt %d at f%d", tag, n, H.frame)
      end),
      n > 1 and seq({
        H.call(function() loadReq = H.requestLoadState(blob) end),
        H.waitFrames(2),
        H.call(function()
          H.checkReq(loadReq, tag .. ": pre-fight reload")
          -- the restored snapshot restarts the experiment: the canary's
          -- count (and its pad freeze, which the reload thaws) belong to
          -- the lost attempt (#163)
          H.gameOverFired = 0
        end),
        H.waitFrames(90),
      }) or seq({}),
      L.spread(n),                       -- spread the battle RNG phase
      H.talkToObj(26, tag .. ": the gate soldier (battle 11)"),
      gateRide(tag .. ": ride battle 11 out", 30000, function(why) lost = why end),
      H.cond(function() return lost == nil end, {
        -- heal-after-every-battle, as rideOut's settle does
        H.careStop("care after battle (" .. tag .. ": ride battle 11 out)"),
      }, {}),
      H.call(function()
        -- The battle's own verdict, read directly: field byte $1DD1 bit 0
        -- = 1 means THIS battle was lost.  A ride that ended on the wipe
        -- never reached the scripted reset, so it is the ride's verdict.
        won = lost == nil and (H.readByte(0x1DD1) & 1) == 0
        H.log(string.format(
          "%s: attempt %d %s ($1DD1.0=%d) at (%d,%d) f%d, probe=%s",
          tag, n, won and "WON" or ("LOST (" .. (lost or "scenario reset")
            .. "; reloading the pre-fight blob)"),
          H.readByte(0x1DD1) & 1, H.fieldX(), H.fieldY(), H.frame,
          tostring(H.bfsPath(probeX, probeY) ~= nil)))
      end),
    })
  end
  return H.cond(function() return H.objX(26) == 30 and H.objY(26) == 42 end, {
    H.logStep(function()
      return string.format("%s: the gate soldier is on his post (%d,%d) " ..
        "at f%d; fighting him", tag, H.objX(26), H.objY(26), H.frame)
    end),
    H.fieldCare({ tag = "care before " .. tag, threshold = 0.95 }),
    (function()
      local req
      return seq({
        H.call(function() req = H.requestSaveState() end),
        H.waitFrames(2),
        H.call(function()
          H.checkReq(req, tag .. ": retry blob")
          blob = req.blob
        end),
      })
    end)(),
    L.watch(),
    fightOnce(1), fightOnce(2), fightOnce(3),
    L.report(),
    H.call(function()
      H.assertEq(won, true,
        tag .. ": battle 11 won within 3 attempts (boosted Fights + the endgame Potion)")
    end),
    laneSettles(probeX, probeY, tag),
  }, {
    H.logStep(function() return tag .. ": the lane is already open" end),
  })
end

-- allowGameOver: the cider-steal sweep deliberately survives a lost
-- battle 10 (#163); its aftermath ride reads H.gameOverFired as a loss
-- and the next attempt reloads.  (The gate-soldier ladder above, clearGate,
-- ends its ride on the wipe and reloads the same way.)
H.run({ maxFrames = 350000, allowGameOver = true }, {
  H.loadState(DOOR),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(map(), 75, "booted on map 75, occupied South Figaro")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(sw(0x0105), 1, "$0105 -- LOCKE's scenario is live")
    H.assertEq(sw(0x001E), 0, "$001E clear -- the scenario is not done")
  end),
  H.equipLoadout(1, {
    { 0, 0x00 }, -- Dirk
    { 2, 0x69 }, -- Leather Hat
    { 3, 0x84 }, -- LeatherArmor
  }, { tag = "LOCKE occupied-town kit" }),

  -- The back row halves the soldier's physical.  It does not win battle 11.
  -- The note that used to sit here said front row, on a comparison that was
  -- never run: "front and back measure identically" came from two runs with
  -- no equipment, where LOCKE did eight damage either way because he was
  -- punching.  The note that replaced it claimed the back row won the fight
  -- ("shields 3 -> 0 three times over, 495 hp -> 0, LOCKE never below 112")
  -- and that is falsified, so it is gone rather than left for contrast.

  H.setRows({ [1] = true }, { tag = "locke solo rows" }),
  H.call(function()
    where("boot")
  end),

  -- ===================================================================== --
  -- BEAT 0 (#213): the item shop.  The shop's bump door (44,30) is in the
  -- starting pocket east of the gate soldier, and nowhere else: from the
  -- main street past the cafe the reachable set ends at x=37
  -- (probe_locke_tonic.lua, whose first version booted sfigaro_town and
  -- read no path).  The counter keeper, map 85 npc at {106,52} (spawn
  -- $0300), runs `_ca7884`: `shop_menu 8` while $00A4 is clear, which it is
  -- for the whole scenario -- Tonic row 0, Fenix Down, no Potion.  It is
  -- the scenario's only Tonic counter: the seeded chain walked in with 20
  -- and reached locke_done with 7 (sfigaro_passage 18, sfigaro_escape 7).
  -- TONIC to 78: the L13 band the scenario reaches (65) plus that
  -- measured spend (13).  Fenix Down stays at the 12 the common route
  -- carries (~level).  Probe: 58 Tonics, gil 10825 -> 7925.
  -- ===================================================================== --
  H.call(function()
    H.log(string.format("[shop] item shop stop begins: gil=%d tonic=%d potion=%d fenix=%d f%d",
      H.gil(), H.invCountOf(0xE8), H.invCountOf(0xE9), H.invCountOf(0xF0), H.frame))
  end),
  H.navTo(44, 32, { maxFrames = 12000, playBattles = true }),
  H.release(),
  H.driveUntil(function() return map() == 85 end, 1200, {
    H.hold({ "up" }), H.waitFrames(8),
  }, "A0 into the item shop (the bump door at (44,30))"),
  H.release(),
  settleField(85),
  H.shopTalk(106, 52, "South Figaro item shop (occupied)"),
  H.call(function()
    H.assertEq(H.shopId(), 8, "the counter opened shop 8 ($0201) -- $00A4 clear")
    H.assertEq(H.shopRowOf(8, 0xE8) ~= nil, true, "shop 8 sells Tonics")
  end),
  H.buyItem(0xE8, function() return 78 - H.invCountOf(0xE8) end, "TONIC to 78"),
  H.shopClose("South Figaro item shop (occupied)"),
  H.bagArrange({ 0xE9, 0xF0, 0xE8, 0xF2, 0xF5 },
    { tag = "bag: combat items on top (South Figaro item shop)" }),
  H.call(function()
    H.assertEq(H.invCountOf(0xE8) >= 78, true,
      "LOCKE leaves the shop with 78 Tonics -- the L13 band plus the scenario's measured spend")
    H.log(string.format("[shop] item shop done: tonic=%d potion=%d fenix=%d gil=%d f%d",
      H.invCountOf(0xE8), H.invCountOf(0xE9), H.invCountOf(0xF0), H.gil(), H.frame))
  end),
  H.navTo(104, 57, { maxFrames = 20000, playBattles = true }),
  H.driveUntil(function() return map() == 75 end, 3000, {
    H.hold({ "down" }), H.waitFrames(8),
  }, "A1 out of the item shop"),
  H.release(),
  settleField(75),
  H.call(function() where("item shop done") end),

  -- ===================================================================== --
  -- BEAT 1: the soldier who bars the gate.  Map 75 npc 10 = obj 26, spawn
  -- switch $030C, at {30,42}: _ca854f (event_main.asm:20296) opens
  -- `dlg $0174 "Halt!"` + `battle 11, TOWN_EXT` -> formation 64,
  -- HeavyArmor $09F.  He blocks the route: (30,42) is the only tile joining
  -- the starting pocket to the rest of town, and BFS reaches exactly 107
  -- tiles until he is gone.  The fight can be won any way (the clothes
  -- branches belong to a different fight), and it is input-driven now: solo
  -- LOCKE on boosted Fights, with the retry sweep around the engagement.
  -- The probe tile is the cafe entry point the win must open.
  -- ===================================================================== --
  clearGate(22, 43, "B1 (open the town)"),
  -- clearGate's own settled probe is this assertion (the gate is the only
  -- thing between the pocket and (22,43)); this stop keeps the map check
  -- and the switch dump, and re-reads the lane through the same settle
  -- rather than taking a second one-frame sample of a live NPC layer.
  laneSettles(22, 43, "the town opened: the cafe entry point"),
  H.call(function()
    H.assertEq(map(), 75, "still in town after battle 11")
    where("town open")
  end),

  -- ===================================================================== --
  -- BEAT 2: the cafe's cider runner.  Map 78 npc 6 = obj 22 at {75,39},
  -- behind the annex warp (33,46)->(74,43).  `battle 10, TOWN_INT` ->
  -- formation 43, Merchant $13A (slot 1, $13B, is the b.day suit the steal
  -- swaps him for).  Steal from him rather than killing him; see note 1.
  -- ===================================================================== --
  go(22, 42, 78, 26, 52, "C1 town (22,42) -> map 78 (26,52) [CAFE]"),
  go(33, 46, 78, 74, 43, "C2 map 78 (33,46) -> (74,43) [annex warp]"),
  -- The steal has its own retry sweep: an attempt that ends the fight
  -- without b_switch $4C (LOCKE down, or the fight won another way) reloads
  -- the pre-talk blob and re-engages at a different frame phase.  The
  -- formation assert still runs on every attempt.
  (function()
    local blob, stolen = nil, false
    local function stealAttempt(n)
      local loadReq
      local wipedN, lostEarly = 0, nil
      return H.cond(function() return stolen end, {}, {
        H.logStep(function()
          return string.format("cider steal attempt %d at f%d", n, H.frame)
        end),
        n > 1 and seq({
          H.call(function() loadReq = H.requestLoadState(blob) end),
          H.waitFrames(2),
          H.call(function()
            H.checkReq(loadReq, "cider: pre-talk reload")
            -- the restored snapshot restarts the experiment: the canary's
            -- count (and its pad freeze, which the reload thaws) belong
            -- to the lost attempt (#163)
            H.gameOverFired = 0
          end),
          H.waitFrames(90),
        }) or seq({}),
        L.spread(n),                     -- spread the battle RNG phase (#83)
        H.talkToObj(22, "the cider runner"),
        -- ride the two dialogs into the fight directly: advanceStory's
        -- playBattles mode would blind-tap A in the fight, and A on the
        -- resting cursor is FIGHT, which would kill the merchant
        (function()
          local ph = 0
          return H.driveUntil(function() return H.battleLoadStarted() end, 9000, {
            H.call(function()
              ph = (ph + 1) % 8
              H.setPad(ph < 4 and { "a" } or {})
            end),
          }, "the cider scene reaches battle 10")
        end)(),
        H.release(),
        H.waitUntil(function() return H.battleActive() end, 6000,
          "battle 10 up", 10),
        H.waitFrames(90),
        H.call(function()
          H.assertEq(H.formationHas({ [0x013A] = true }), true,
            "battle 10 is formation 43 -- Merchant $13A")
          local w = H.formationWords()
          H.log(string.format(
            "battle 10: %04X %04X %04X %04X %04X %04X  $3EBD=%02X",
            w[1], w[2], w[3], w[4], w[5], w[6], H.readByte(B_SWITCH_LIVE)))
        end),
        stealDriver("the cider runner"),
        -- The aftermath ride is soft: on the steal the scene settles back on
        -- map 78, and on a loss the game-over screen never settles.  A hard
        -- timeout here would abort the whole generate instead of letting the
        -- ladder reload and retry, so this ride gives up after its budget
        -- and lets the $1DD2 check below decide.
        -- #163: a lost battle 10 (LOCKE down) is a wipe, and a wipe zeroes
        -- every battle-HP word, which battleLoadStarted() reads as "no
        -- battle" -- so stealDriver ends on the first wiped frame and this
        -- ride's A-taps would press into the Annihilated screen for the
        -- rest of its 20000-frame budget.  The lib's wipe predicate held
        -- 90 straight frames, or the run canary's count (it now counts a
        -- 300-frame battle-side wipe as a game over and freezes the pad;
        -- allowGameOver on the run keeps the sweep alive for the
        -- reload), ends the ride as a named loss instead.
        (function()
          local ph, calm, waited = 0, 0, 0
          return H.driveUntil(function()
            wipedN = H.partyWipedInBattle() and wipedN + 1 or 0
            if (H.gameOverFired or 0) > 0 and not lostEarly then
              lostEarly = string.format("GAME OVER counted by the canary " ..
                "at f%d", H.frame)
            elseif wipedN >= 90 and not lostEarly then
              lostEarly = string.format("PARTY WIPED at f%d (the lib's " ..
                "wipe predicate, 90 frames)", H.frame)
            end
            if lostEarly then return true end
            local ok = H.hasControl() and H.tileAligned() and bright() >= 15
                   and not H.battleLoadStarted() and not H.dialogWaiting()
                   and map() == 78
            calm = ok and calm + 1 or 0
            waited = waited + 1
            return calm >= 20 or waited >= 20000
          end, 20500, {
            H.call(function()
              ph = (ph + 1) % 8
              if lostEarly or H.hasControl() then H.setPad({}); return end
              H.setPad(ph < 4 and { "a" } or {})
            end),
          }, "ride the steal's aftermath out (soft)")
        end)(),
        H.release(),
        H.waitFrames(30),
        H.call(function()
          stolen = lostEarly == nil and (H.readByte(0x1dd2) >> 4) & 1 == 1
            and map() == 78 and H.hasControl()
          H.log(string.format("cider attempt %d: $1DD2=%02X map=%d -> %s", n,
            H.readByte(0x1dd2), map(),
            stolen and "STOLEN" or (lostEarly and ("LOST: " .. lostEarly ..
              "; retrying") or "no steal; retrying")))
        end),
      })
    end
    return seq({
      (function()
        local req
        return seq({
          H.call(function() req = H.requestSaveState() end),
          H.waitFrames(2),
          H.call(function()
            H.checkReq(req, "cider: retry blob")
            blob = req.blob
          end),
        })
      end)(),
      L.watch(),
      stealAttempt(1), stealAttempt(2), stealAttempt(3),
      L.report(),
      H.call(function()
        H.assertEq(stolen, true,
          "the clothes were STOLEN within 3 attempts")
      end),
    })
  end)(),
  H.call(function()
    where("after the steal")
    H.log(string.format("post-fight $1DD2=%02X (b_switch $4C=%d $4D=%d)",
      H.readByte(0x1dd2), (H.readByte(0x1dd2) >> 4) & 1,
      (H.readByte(0x1dd2) >> 5) & 1))
    H.assertEq((H.readByte(0x1dd2) >> 4) & 1, 1,
      "b_switch $4C -- the steal's reaction script fired")
    H.assertEq(sw(0x01D0), 1, "$01D0 -- took the old man's cider")
    H.assertEq(sw(0x0104), 1, "$0104 -- wearing the merchant's clothes")
    H.assertEq(sw(0x0103), 0, "$0103 clear -- not the soldier's uniform")
  end),

  -- back out of the annex and into town
  go(75, 42, 78, 34, 45, "C3 map 78 (75,42) -> (34,45) [annex warp back]"),
  go(26, 53, 75, 22, 44, "C4 map 78 (26,53) -> town (22,44)"),
  H.call(function()
    H.assertEq(map(), 75, "back in South Figaro")
    where("sfigaro_town")
    for c = 0, 15 do
      if (H.readByte(0x1850 + c) & 0x07) ~= 0 then
        local base = 0x1600 + 37 * c
        H.log(string.format("char %2d actor=%02X level=%d hp=%d/%d",
          c, H.readByte(base), H.readByte(base + 8),
          H.readWord(base + 9), H.readWord(base + 11)))
      end
    end
    H.screenshot("sfigaro_town")
  end),
  H.saveState("sfigaro_town.mss"),
  H.logStep(function()
    return string.format("sfigaro_town generated at frame %d", H.frame)
  end),

  -- ===================================================================== --
  -- BEAT 3: the cider buys the old man's story.  Map 86 npc 1 = obj 17 at
  -- {28,17}, reached only through town (37,40) -> map 86 (36,22).  The
  -- room has one outside door and one same-map warp, and the warp only
  -- leads to the (9,8) landing and back.  _ca7b88 (:18670) takes the
  -- $01D0 branch _ca7bae: "there is one that leads to the rich man's
  -- house... give my grandson the password", ending `switch $0107=1`.
  -- The walk there is broken into hops (note 4): (22,44) -> (37,41) is a
  -- 49-step query and it is the one that runs the BFS cap dry.
  -- ===================================================================== --
  hop(19, 44, "W1 west along the canal"),
  hop(19, 34, "W2 north to the main street"),
  hop(24, 34, "W3 east along the main street"),
  hop(30, 36, "W4 to the top of the SE lane"),

  clearGate(30, 43, "R1 (into the SE quarter)"),
  hop(30, 43, "W5 down the SE lane"),
  hop(34, 43, "W6 east"),
  hop(34, 46, "W7 south"),
  hop(36, 46, "W8 to the old man's entry point"),
  go(37, 40, 86, 36, 22, "E1 town (37,40) -> map 86 (36,22)"),
  talkThrough(17, "the old man (cider -> $0107)"),
  H.call(function()
    where("after the old man")
    H.assertEq(sw(0x0107), 1, "$0107 -- he named the secret passage")
  end),

  -- ===================================================================== --
  -- BEAT 4: the grandson and the password.  Map 86 npc 4 = obj 20 at
  -- {6,10}, in the other map-86 house, the one town (34,35) enters at
  -- (4,6), so this is out to town and back in, not a warp.  _ca7bcd
  -- (:18738) tests $0107 before the "you may proceed" branch, so with the
  -- old man already told, one conversation goes straight to the prompt.
  -- ===================================================================== --
  go(36, 23, 75, 37, 42, "E2 map 86 (36,23) -> town (37,42)"),
  hop(34, 43, "W9 back west across the SE quarter"),
  -- and back out of the SE quarter, so the same soldier is in the way again
  clearGate(34, 35, "R2 (out of the SE quarter)"),
  go(34, 35, 86, 4, 6, "E3 town (34,35) -> map 86 (4,6)"),
  talkThrough(20, "the grandson (the password)", {
    { want = 1, max = 3, what = 'dlg $00E0 "The password is..." -- 1 = ' ..
      '"Courage".  Options 0 ("Rose bud") and 2 ("Failure") BOTH jump to ' ..
      '_ca7c28, "You are an Imperial spy!", which fades out and calls ' ..
      '_ca85ba -- the scenario reset that dumps LOCKE back on (47,43) with ' ..
      'both disguise switches cleared (event_main.asm:18754-18762)' },
  }),
  H.call(function()
    where("after the password")
    H.assertEq(sw(0x01F1), 1, "$01F1 -- the secret entrance is open")
    -- _ca7c11 -> _caed21 rewrites BG1 at (4,15) (event_main.asm:100170):
    -- the staircase tile that read $E0/p1=$F7 (solid wall) is now floor
    H.log(string.format("(4,15) map byte=$%02X p1=$%02X",
      H.maptile(4, 15), H.readByte(0x7E7600 + H.maptile(4, 15))))
  end),

  H.openChest{ stand = { 15, 11 }, face = "up", bit = 30, what = "Tonic",
               item = 0xE8,
               nav = { playBattles = true } },

  H.fieldCare({ tag = "care before the secret passage", threshold = 0.85 }),

  go(4, 15, 86, 7, 51, "E4 map 86 (4,15) -> (7,51) [the secret passage]"),
  H.call(function()
    H.assertEq(map(), 86, "still map 86 -- the passage is a same-map warp")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(H.tileAligned(), true, "tile-aligned")
    H.assertEq(H.battleLoadStarted(), false, "no battle")
    where("sfigaro_passage")
    -- The casualty contract (see the care stop above): this fixture is what
    -- gen_celes boots from, and gen_celes performs zero state writes of its
    -- own, so a party member down or near fatal here is a loss shipped
    -- straight through to celes_freed, not a state of the story getting
    -- somewhere.
    H.assertPartyStanding("sfigaro_passage")
    H.screenshot("sfigaro_passage")
  end),
  H.saveState("sfigaro_passage.mss"),
  H.logStep(function()
    return string.format("sfigaro_passage generated at frame %d", H.frame)
  end),
})
