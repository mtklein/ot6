-- @suite savestate=kolts_cave
-- battle_doom.lua -- what the fight driver does about a Condemned member
-- (#190, H.doomCount / H.doomRule).
--
-- Condemned counts $3B05 down and casts Doom at 0; nothing in the bag
-- clears the bit (lib/ot6.lua, M.statusCure's note), and a Fenix Down
-- after the Doom raises the member clear of it.  gen_fc_escape logged the
-- count under Nerapa and never planned on it.  The driver reads the count
-- as a clock: a member the Doom takes before their next turn gets no heal
-- (the HP goes with the Doom), and on their own last turn they spend every
-- pip on the attack lines rather than die holding boost.
--
-- This is a focused mechanism test and stages with sanctioned expedient
-- writes, because Condemned on the WoB route is Nerapa's opening on the
-- FC escape, hours of play from any fixture:
--   * Condemned is POKED in the engine's own shape -- STATUS2 bit 0 and
--     the $3B05 count (StartCondemn @09b4 writes exactly those two);
--   * B's patient's HP is POKED to half, under the driver's care line, so
--     the heal line has somebody to refuse, battle_healerdown's shape;
--   * the battle bag's Fenix Downs are zeroed, so no raise outranks the
--     care decision B observes.
-- The battle is a natural Mt. Kolts cave encounter paced into from
-- kolts_cave; the driver is the route's own.
--
-- B. the heal refused.  The poke lands inside a decision: the driver's
--    opts.holdFor hook runs first thing in each of its decisions, and the
--    test stages B there, on the very frame the decision reads the board,
--    for the first decision whose care block is sure to weigh a patient:
--      - the actor has an Item row and the bag a Potion or Tonic;
--      - the round's care turn is open to it (nobody else took it);
--      - the monsters stand above the finisher window (more than 200 HP
--        in all), so no "kill first" closes care;
--      - another member's next turn is at least a count and two visits of
--        its status counter away.
--    That member is condemned at 1 and hurt to half.  The Doom then lands
--    within one count (128 frames: four visits at most carry the
--    accumulator), before that member's turn, and nothing can land in
--    between the poke and the decision.  Until B is staged, and from the
--    poke until the Doom, every other decision Defends (opts.holdFor), so
--    no damage dealt or care spent can close the care block on the draw's
--    luck.  Asserted: inside the staged decision, before its plan line,
--    the driver says it is throwing no heal at the patient, naming the
--    count the patient's $3B05 held as it said so and a next turn that
--    count beats; no heal or cure names the patient before its Doom; the
--    patient's own turn does not come first; the Doom lands as nobody's
--    action and the CLEARED line says so.
--    A try is lost, not failed, when an action (a monster's) kills the
--    patient before its Doom: the machine goes back to the battle's open
--    (a snapshot taken there), under a new driver, and the next try passes
--    over one more qualifying decision, at most TRIES_B times.
-- A. the condemned actor's last turn.  After B's Doom, the next decision of
--    a member with a Fight row, a living ally, a full gauge longer than two
--    counts and an accumulator that does not carry on its next visit is
--    condemned at 2 (256 frames) as it opens, the same way (the others
--    Defend until its Doom): its plan is an attack, its boost is every pip
--    it holds, and the driver said why.  (Poked at a command window's
--    opening frame instead, behind this B, A's actor made no decision before
--    its Doom on 22 of 24 seed shifts: build/attempts/wt/v044-esper-rework-7/
--    lab/d3.)
-- The count's own clock is measured on the way in visits of the members'
-- status counters (watchCounts): each count steps on the visit its
-- accumulator carries, and four visits at the running clock's gap are
-- H.COUNT_FRAMES.
-- Negative control: stub H.doomRule to return nil and B goes red -- the
-- staged decision heals the patient, and no refusal is said.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/kolts_cave.mss.lua"

local CMDTBL, BCHID, BP = 0x202E, 0x3ED8, 0x3E9C
local ST1, ST2, DOOM_COUNT, ATB, ATB_CONST = 0x3EE4, 0x3EE5, 0x3B05, 0x3218, 0x3AC8
local CMD_FIGHT, CMD_ITEM = 0x00, 0x01
-- the driver's finisher window: monsters at this many HP or fewer in all close its care block (makePlanRules)
local FINISHER_HP = 200

local lines, saidAt = {}, {}
local rawLog = H.log

local function map() return H.mapId() & 0x1ff end
local function hp(e) return H.readWord(0x3BF4 + e * 2) end
local function maxhp(e) return H.readWord(0x3C1C + e * 2) end
local function hasRow(e, cmd)
  for row = 0, 3 do
    if H.readByte(CMDTBL + e * 12 + row * 3) == cmd
       and (H.readByte(CMDTBL + e * 12 + row * 3 + 1) & 0x80) == 0 then return true end
  end
  return false
end
-- the ATB ticks until entity e's gauge fills (0 = full: its turn is queued, or its window is open)
local function etaOf(e) return H.atbEta(H.readWord(ATB + e * 2), H.readWord(ATB_CONST + e * 2)) end
-- frames until entity e's next turn, as the driver's doomLast reads it: for the member acting now
-- (`acting`), a full refill; for anyone else, wherever its gauge stands, so a full gauge is a turn
-- already queued (0), not a full refill away (01822cae)
local function turnFrames(e, acting)
  local const = H.readWord(ATB_CONST + e * 2)
  local eta = etaOf(e)
  local period = const > 0 and math.ceil(0xFF00 / const) or nil
  local ticks = acting and period or eta
  return ticks and ticks * 2 or nil
end
local function monTotal()
  local t = 0
  for s = 0, 5 do
    if H.monStanding(s) then t = t + H.readWord(0x3BFC + s * 2) end
  end
  return t
end
local function bagHas(id)
  for i = 0, 251 do
    if H.readByte(0x2686 + i * 5) == id and H.readByte(0x2686 + i * 5 + 3) > 0 then return true end
  end
  return false
end

-- one visit of a status counter: DecCounters every 16 battle-time ticks of 2 frames
local VISIT_FRAMES = 32
-- B's patient: its next turn at least a count and two visits away, so the Doom (within one count) comes first
local B_TURN_FRAMES = H.COUNT_FRAMES + 2 * VISIT_FRAMES

local F = nil
local doomedA, bpA, lineA, frameA = nil, nil, nil, nil
local doomedB, actorB, lineB, frameB, hpB = nil, nil, nil, nil, nil
local deathFrame, deathLine = nil, nil
-- B's staging: "stage" (no decision has qualified yet), "wait" (staged, the Doom pending), "A" (B done)
local phase = "stage"
local TRIES_B = 4
-- A's battles: B's, then the cave's next encounters while one ends with no decision qualified for A
local TRIES_A, battlesA = 3, 0
local skipB, qualifiedB, triesB, whyNotB = 0, 0, {}, {}
local snapReq, loadReq, snap0, lines0 = nil, nil, nil, nil

-- Every line the driver says is kept, and once B's member is condemned, so
-- is what that member's count and gauge read on the frame it was said: the
-- driver reads them on that same frame, so B's refusal is checked against
-- the state it described.
H.log = function(msg)
  lines[#lines + 1] = tostring(msg)
  if doomedB ~= nil then
    saidAt[#lines] = {
      frame = H.frame,
      count = H.doomCount({ s2 = H.readByte(ST2 + doomedB * 2),
                            count = H.readByte(DOOM_COUNT + doomedB * 2) }),
      turn = turnFrames(doomedB),
    }
  end
  return rawLog(msg)
end

-- The count's clock is visits, not frames.  DecCounters visits each entity
-- every 16 battle-time ticks; a visit adds the entity's speed constant
-- ($3add: 64 at normal speed) to its $3adc accumulator, and the count steps
-- on the visit that carries out of it.  Battle time stops while an action
-- plays out, so a count measured in frames is its clock plus whatever froze
-- it (wt/v026-driver's kolts_cave draw: one count took 339 frames for its
-- four visits).  So each visit is seen as the accumulator moving by exactly
-- the entity's speed constant -- any other change to the byte is not a
-- visit (on wt/v044-esper-rework-6 the byte moving at all read as a visit,
-- and the shortest gap came out 23 and 25 frames on 6 of 24 seed shifts,
-- build/attempts/wt/v044-esper-rework-6/v044-esper-land/build/lab/sl/doom2)
-- -- and a count is checked against the visits its own speed constants
-- give; the frames are the shortest gap between two visits, the running
-- clock's.
local ACC, SPEED, NORMAL_SPEED = 0x3ADC, 0x3ADD, 64
local lastCount, lastCountFrame, periods, decremented
local accLast, visits, sim, periodVisits, visitFrame, minVisit, notVisits, notVisitSaid
local function resetModel()
  lastCount, lastCountFrame, periods, decremented = {}, {}, {}, {}
  accLast, visits, sim, periodVisits, visitFrame, minVisit = {}, {}, {}, {}, {}, nil
  notVisits, notVisitSaid = 0, 0
end
resetModel()
-- a new battle (A's next encounter): the counts, accumulators and visits of the last one mean nothing in it; the
-- periods and visit gaps already measured stand
local function newBattleModel()
  lastCount, lastCountFrame, decremented = {}, {}, {}
  accLast, visits, sim, visitFrame = {}, {}, {}, {}
end

local function watchCounts()
  for e = 0, 3 do
    -- Read the raw $3B05 byte while the Condemned bit is set, not H.doomCount.
    -- A decrement is the byte stepping down while still condemned, or the bit
    -- clearing straight from 2 or more.  The step to 1 is DecCounters calling
    -- CondemnDeath, which queues the Doom (CreateImmediateAction).  With
    -- nothing ahead of it the Doom lands on the frame of the step, so the
    -- byte is never seen at 1 and the bit clearing IS the step (measured: 2
    -- -> clear 128 frames after 3 -> 2).  Behind other actions it waits, and
    -- the byte reads 1 with the bit set until it lands (measured 18 and 243
    -- frames): that clear is the queue's timing, not the count's, and is not
    -- a step.
    local condemned = (H.readByte(ST2 + e * 2) & 0x01) ~= 0
    -- visits are counted whatever the bit reads: the visit that carries the
    -- count to its Doom can clear the bit before this frame samples it
    do
      local acc, speed = H.readByte(ACC + e * 2), H.readByte(SPEED + e * 2)
      if accLast[e] ~= nil and acc ~= accLast[e] then
        if speed > 0 and ((acc - accLast[e]) & 0xFF) == speed then
          visits[e] = (visits[e] or 0) + 1
          -- the visits this count should take: the accumulator replayed from
          -- where the last step left it, with each visit's live constant,
          -- until it carries
          if sim[e] ~= nil and sim[e].want == nil then
            sim[e].acc = sim[e].acc + speed
            sim[e].n = sim[e].n + 1
            if sim[e].acc > 0xFF then sim[e].want = sim[e].n end
            sim[e].speeds[speed] = true
          end
          if visitFrame[e] ~= nil then
            local g = H.frame - visitFrame[e]
            if minVisit == nil or g < minVisit then minVisit = g end
          end
          visitFrame[e] = H.frame
        else
          -- not a visit: the byte written some other way.  The next visit's gap is measured from the next visit.
          notVisits = notVisits + 1
          if notVisitSaid < 8 then
            notVisitSaid = notVisitSaid + 1
            rawLog(string.format("[test] f%d entity %d's $3adc moved %d -> %d with $3add %d: not a visit",
              H.frame, e, accLast[e], acc, speed))
          end
          visitFrame[e] = nil
        end
      end
      accLast[e] = acc
    end
    local b = condemned and H.readByte(DOOM_COUNT + e * 2) or nil
    local stepped = lastCount[e] ~= nil and lastCountFrame[e] ~= nil
      and ((b ~= nil and b < lastCount[e]) or (b == nil and lastCount[e] >= 2))
    if stepped then
      -- Skip the partial first cycle.  The poke lands mid-accumulator (the
      -- engine's $3adc / CalcSpeed is not reset by writing the count byte), so
      -- the gap from the poke to the FIRST decrement is a fraction of a cycle,
      -- not the count's cadence.  Only the gap between two real decrements is
      -- a full cycle, so a period is recorded from the second decrement on
      -- (#190, M.COUNT_FRAMES).  A's count (poked at 2) steps twice before its
      -- Doom, so it gives one period; B's (poked at 1) steps once and gives none.
      if decremented[e] then
        periods[#periods + 1] = H.frame - lastCountFrame[e]
        local sp = {}
        for k in pairs(sim[e].speeds) do sp[#sp + 1] = k end
        table.sort(sp)
        periodVisits[#periodVisits + 1] = { e = e, got = visits[e], want = sim[e].want,
                                            speeds = table.concat(sp, "/") }
      end
      decremented[e] = true
      visits[e] = 0
      sim[e] = { acc = accLast[e] or 0, n = 0, speeds = {} }
    end
    if b ~= lastCount[e] then lastCount[e], lastCountFrame[e] = b, H.frame end
  end
end

-- B's patient dead by an action (a monster's, or a member's) since its poke, before its Doom: the [death]
-- line's attribution, or nil
local function killedB()
  if doomedB == nil or lineB == nil or hp(doomedB) > 0 then return nil end
  for i = lineB + 1, #lines do
    local l = lines[i]
    if l:find("%[death%] f%+%d+ entity " .. doomedB .. " char") and not l:find("by nobody", 1, true) then
      return l:match("(by slot %d+ cmd %$%x+ atk %$%x+)") or l:match("(by entity %d+ char %d+ cmd %$%x+ atk %$%x+)")
        or "an action"
    end
  end
  return nil
end

-- Why this decision cannot be B's (nil: it can), and the patient it would condemn
local function qualifyB(x)
  if hp(x) == 0 or maxhp(x) == 0 then return "the actor is down" end
  if not hasRow(x, CMD_ITEM) then return "the actor has no Item row" end
  if not (bagHas(0xE9) or bagHas(0xE8)) then
    error("no Potion or Tonic in the battle bag: nothing for the heal line to refuse", 0)
  end
  local c = F.driver.careActor
  if c ~= nil and c ~= x and hp(c) > 0 then
    return string.format("the round's care turn went to actor %d", c)
  end
  local total = monTotal()
  if total <= FINISHER_HP then
    return string.format("the monsters stand at %d HP in all, inside the finisher window (<= %d)", total, FINISHER_HP)
  end
  local p, best, seen = nil, nil, {}
  for e = 0, 3 do
    if e ~= x and hp(e) > 0 and maxhp(e) > 0 and (H.readByte(ST1 + e * 2) & 0xC2) == 0 then
      local tf = turnFrames(e)
      seen[#seen + 1] = string.format("e%d %s", e, tostring(tf))
      if tf ~= nil and tf >= B_TURN_FRAMES and (best == nil or tf > best) then p, best = e, tf end
    end
  end
  if p == nil then
    return string.format("no other member's next turn is %d frames away (%s)", B_TURN_FRAMES,
      #seen > 0 and table.concat(seen, ", ") or "none standing")
  end
  return nil, p
end

local function stageB(x, p)
  -- doomedA's corpse does not exist yet (A follows B), but a monster can kill a member before B; with a Fenix
  -- Down in the battle bag the raise block, ahead of the heal loop, would plan the raise -- correct play, not
  -- the decision #190's rule is about.  The bag's Fenix Downs (id $F0) are zeroed.
  for i = 0, 251 do
    if H.readByte(0x2686 + i * 5) == 0xF0 then H.writeByte(0x2686 + i * 5 + 3, 0) end
  end
  local before = turnFrames(p)
  H.writeByte(ST2 + p * 2, H.readByte(ST2 + p * 2) | 0x01)
  H.writeByte(DOOM_COUNT + p * 2, 2)
  hpB = math.max(1, maxhp(p) // 2)
  H.assertEq(hpB * 100 // maxhp(p) < F.driver:healPct(), true, "B's patient at half its HP is under the care line")
  H.writeWord(0x3BF4 + p * 2, hpB)
  doomedB, actorB, frameB = p, x, H.frame
  H.log(string.format("[test] f%d Condemned poked onto entity %d char %d (count 1, %d frames; its next turn %d "
    .. "frames away; $3adc %d) and its HP set to %d/%d (the care line %d%%), as actor %d's decision opens "
    .. "(qualifying decision %d, try %d; the monsters at %d HP in all, the care turn %s)",
    H.frame, p, H.readByte(BCHID + p * 2), H.COUNT_FRAMES, before, H.readByte(ACC + p * 2), hpB, maxhp(p),
    F.driver:healPct(), x, qualifiedB, #triesB + 1, monTotal(), F.driver.careActor == nil and "open" or ("actor " .. F.driver.careActor .. "'s")))
  lineB = #lines
end

-- Why this decision cannot be A's (nil: it can)
local function qualifyA(x)
  if x == doomedB or hp(x) == 0 or maxhp(x) == 0 then return "the actor is down" end
  if not hasRow(x, CMD_FIGHT) then return "the actor has no Fight row" end
  local allies = 0
  for p = 0, 3 do if p ~= x and hp(p) > 0 and maxhp(p) > 0 then allies = allies + 1 end end
  if allies == 0 then return "no ally stands" end
  local full = turnFrames(x, true)
  if (full or 0) < 2 * H.COUNT_FRAMES then
    return string.format("its full gauge is %s frames, under two counts", tostring(full))
  end
  -- the [status] line reads the count on the frame after the poke: a poke whose accumulator carries on its next
  -- visit could show the count already stepped to 1
  local acc, speed = H.readByte(ACC + x * 2), H.readByte(SPEED + x * 2)
  if acc + speed > 0xFF then
    return string.format("its count would step on its next visit ($3adc %d + $3add %d)", acc, speed)
  end
  return nil
end

local function stageA(x)
  H.writeByte(ST2 + x * 2, H.readByte(ST2 + x * 2) | 0x01)
  H.writeByte(DOOM_COUNT + x * 2, 3)
  doomedA, bpA, lineA, frameA = x, H.readByte(BP + x * 2), #lines, H.frame
  H.log(string.format("[test] f%d Condemned poked onto entity %d char %d as its decision opens: count 2 (%d "
    .. "frames), its next turn %s frames away, %d BP held", H.frame, x, H.readByte(BCHID + x * 2),
    2 * H.COUNT_FRAMES, tostring(turnFrames(x, true)), bpA))
end

-- opts.holdFor: called first thing in every decision the driver makes (makePlanRules); true Defends.  B is
-- staged first; then A, the same way; every decision that is neither Defends until the last Doom lands.
local whyNotA = {}
local function holdFor(_, x)
  if phase == "A" then
    if doomedA ~= nil then return true end
    local why = qualifyA(x)
    if why ~= nil then
      if whyNotA[x] ~= why then
        whyNotA[x] = why
        rawLog(string.format("[test] f%d actor %d's decision is not A's (it Defends): %s", H.frame, x, why))
      end
      return true
    end
    stageA(x)
    return false
  end
  if phase == "wait" then return true end
  local why, p = qualifyB(x)
  if why ~= nil then
    if whyNotB[x] ~= why then
      whyNotB[x] = why
      rawLog(string.format("[test] f%d actor %d's decision is not B's (it Defends): %s", H.frame, x, why))
    end
    return true
  end
  qualifiedB = qualifiedB + 1
  if qualifiedB <= skipB then
    rawLog(string.format("[test] f%d actor %d's decision qualifies (%d), and is passed over: an earlier try "
      .. "staged there", H.frame, x, qualifiedB))
    return true
  end
  stageB(x, p)
  phase = "wait"
  return false
end

-- pace the auto-detected lane until a natural encounter fires (a step; called again for A's next battle)
local function paceEncounter()
  local battN, waited, lane = 0, 0, nil
  local BACK = { left = "right", right = "left", up = "down", down = "up" }
  -- each pace starts its own count and finds its own lane (A's later battles start wherever the last one left
  -- the party)
  return H.seqStep({ H.call(function() battN, waited, lane = 0, 0, nil end), H.driveUntil(function()
    waited = waited + 1
    battN = H.battleLoadStarted() and battN + 1 or 0
    if battN >= 1 then H.setPad({}) return true end
    if map() ~= 96 then error("paced off map 96 (now " .. map() .. ")", 0) end
    return waited >= 8000
  end, 8600, {
    H.call(function()
      if not (H.hasControl() and H.tileAligned()) then H.setPad({}) return end
      local x, y = H.fieldX(), H.fieldY()
      if lane == nil then
        for _, d in ipairs({ "right", "left", "up", "down" }) do
          if H.canStep(x, y, d) then lane = { ax = x, ay = y, out = d, back = BACK[d] } break end
        end
      end
      H.setPad({ [(x == lane.ax and y == lane.ay) and lane.out or lane.back] = true })
    end),
    H.waitFrames(1),
  }, "a cave encounter fires") })
end

local function newDriver()
  -- freeRound = "care": a Mt. Kolts encounter can open as a preemptive
  -- strike, whose free round otherwise defers every top-up one turn for an
  -- attack (#186), skipping the heal-candidate loop where #190's refusal
  -- lives.
  F = H.newFightDriver("doom", { tactical = true, boost = true, bank = 2,
                                 items = true, healPercent = 60,
                                 freeRound = "care", holdFor = holdFor })
end

H.run({ maxFrames = 120000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000,
    "field control in cave 96"),
  H.call(function() H.assertEq(map(), 96, "kolts_cave on map 96") end),

  paceEncounter(),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle armed", 5),
  -- the battle's open, kept: a lost B try goes back to it
  H.call(function() snapReq = H.requestSaveState() end),
  H.waitFrames(2),
  H.call(function()
    H.checkReq(snapReq, "the snapshot at the battle's open")
    snap0, lines0 = snapReq.blob, #lines
    rawLog(string.format("[test] f%d the snapshot at the battle's open: formation $%03X, monsters at %d HP in all",
      H.frame, H.readWord(0x11E0) & 0x3FF, monTotal()))
  end),

  -- B, at most TRIES_B tries
  H.repeatN(TRIES_B, {
    H.cond(function()
      if doomedB == nil then return true end
      local by = killedB()
      if by == nil then return false end
      triesB[#triesB + 1] = string.format("entity %d at qualifying decision %d: killed %s", doomedB, qualifiedB, by)
      rawLog(string.format("[test] B's try on entity %d (qualifying decision %d) lost: killed %s before its Doom; "
        .. "back to the battle's open under a new driver, passing over one more qualifying decision",
        doomedB, qualifiedB, by))
      return true
    end, {
      H.cond(function() return doomedB ~= nil end, {
        H.call(function() loadReq = H.requestLoadState(snap0) end),
        H.waitFrames(2),
        H.call(function()
          H.checkReq(loadReq, "the snapshot at the battle's open")
          for i = #lines, lines0 + 1, -1 do lines[i] = nil end
          saidAt = {}
          resetModel()
          skipB, qualifiedB, whyNotB, phase = #triesB, 0, {}, "stage"
          doomedB, actorB, lineB, frameB, hpB, deathFrame, deathLine = nil, nil, nil, nil, nil, nil, nil
        end),
      }, {}),
      H.call(newDriver),
      -- the decisions Defend until one qualifies and B is staged inside it; then they Defend until the Doom
      (function()
        local n = 0
        return H.driveUntil(function()
          watchCounts()
          n = n + 1
          if not H.battleLoadStarted() then return true end
          if doomedB == nil and n > 9000 then
            local said = {}
            for e, w in pairs(whyNotB) do said[#said + 1] = string.format("actor %d: %s", e, w) end
            error("no decision qualified for B in 9000 frames of Defends (" .. table.concat(said, "; ") .. ")", 0)
          end
          if doomedB ~= nil and deathFrame == nil and hp(doomedB) == 0 then deathFrame, deathLine = H.frame, #lines end
          return deathFrame ~= nil and H.frame - deathFrame > 60
        end, 12000, {
          H.call(function() F.frame() end),
          H.waitFrames(1),
        }, "B staged in a decision, and its patient's Doom lands")
      end)(),
    }, {}),
  }),
  H.call(function()
    H.assertEq(doomedB ~= nil and killedB() == nil and hp(doomedB) == 0, true, string.format(
      "B's patient fell to its Doom, not an action, within %d tries (lost: %s)", TRIES_B,
      #triesB > 0 and table.concat(triesB, "; ") or "none"))
    phase = "A"
  end),

  -- A. the next decision of a member with a Fight row, a living ally, and a
  -- full gauge longer than two counts is condemned at 2 as it opens (qualifyA);
  -- the others Defend until A's Doom lands
  -- A battle the party wins before any decision qualifies for A (the v0.50 line's kolts_cave capture: EDGAR's
  -- AutoCrossbow, the plan of B's own staged decision, took all three monsters' 402 HP in one action, and battle_doom
  -- went red on "a decision qualified for A ()") is not A's: the party paces to the cave's next encounter and A
  -- is staged there, at most TRIES_A battles.  A asks only for a decision of a member with a Fight row, a living
  -- ally and a long gauge; nothing in it reads B's battle.
  H.repeatN(TRIES_A, {
    H.cond(function() return doomedA == nil or hp(doomedA) ~= 0 end, {
      H.cond(function() return not H.battleLoadStarted() end, {
        H.call(function()
          battlesA = battlesA + 1
          rawLog(string.format("[test] f%d the battle ended with no decision qualified for A: to the cave's next "
            .. "encounter (A's battle %d)", H.frame, battlesA + 1))
        end),
        H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 6000, "field control after the battle"),
        paceEncounter(),
        H.release(),
        H.waitUntil(function() return H.battleActive() end, 900, "battle armed", 5),
        H.call(function() newBattleModel(); newDriver() end),
      }, {}),
      H.driveUntil(function()
        watchCounts()
        if not H.battleLoadStarted() then return true end
        return doomedA ~= nil and hp(doomedA) == 0
      end, 12000, {
        H.call(function() F.frame() end),
        H.waitFrames(1),
      }, "A staged in a decision, and its Doom lands"),
    }, {}),
  }),
  H.call(function()
    local said = {}
    for e, w in pairs(whyNotA) do said[#said + 1] = string.format("actor %d: %s", e, w) end
    H.assertEq(doomedA ~= nil, true, "a decision qualified for A (" .. table.concat(said, "; ") .. ")")
  end),

  H.call(function()
    H.setPad({})
    -- B. no heal on the hurt, condemned patient
    local planB = nil
    for i = lineB + 1, #lines do
      if lines[i]:find("actor=" .. actorB .. " char=%d+ plan=") then planB = i break end
    end
    H.assertEq(planB ~= nil, true, string.format("actor %d's staged decision made a plan", actorB))
    local refused, refusedAt, refusedCount, healed, ownTurn = nil, nil, nil, nil, nil
    for i = lineB + 1, deathLine do
      local s = lines[i]
      if refused == nil then
        local n = s:match("actor=" .. actorB .. " no heal on entity " .. doomedB .. " %(%d+/%d+%): it is "
          .. "CONDEMNED at (%d+) %(x %d+ frames%) and the Doom beats its next turn")
        if n ~= nil then refused, refusedAt, refusedCount = s, i, tonumber(n) end
      end
      if s:find("heal entity " .. doomedB .. " %(") or s:find("cure entity " .. doomedB .. " %(") then healed = s end
      if ownTurn == nil and s:find("%[board%] n=%d+ tick=%d+ form=%$%x+ who=" .. doomedB .. " ") then ownTurn = s end
    end
    H.log(string.format("[test] actor %d's staged decision on entity %d: %s", actorB, doomedB,
      refused or healed or "neither a refusal nor a heal named the patient"))
    H.assertEq(refused ~= nil, true, string.format("actor %d refused the heal on the condemned "
      .. "entity %d and said why", actorB, doomedB))
    H.assertEq(refusedAt < planB, true, "...inside the staged decision, before its plan")
    local at = saidAt[refusedAt]
    H.log(string.format("[test] the refusal was said at f%d, %d frames after the poke at count 1: "
      .. "entity %d's count read %s there and its next turn was %s frames away",
      at.frame, at.frame - frameB, doomedB, tostring(at.count), tostring(at.turn)))
    H.assertEq(refusedCount, at.count,
      "...naming the count the member's $3B05 held on the frame it was said")
    H.assertEq(at.count ~= nil and at.count <= 1, true,
      "...a count at or under the 1 it was poked at (it only runs down)")
    -- the refusal names a race against the member's next turn, so that turn
    -- has to be known where it was said (#252: a nil turn used to pass)
    H.assertEq(at.turn ~= nil, true, "...with the member's next turn known when it was said")
    H.assertEq(at.count * H.COUNT_FRAMES <= at.turn, true,
      "...and the Doom did beat the member's next turn then (count x "
      .. H.COUNT_FRAMES .. " <= frames to it)")
    H.assertEq(healed, nil, "no heal or cure plan named the condemned member before the Doom")
    H.assertEq(ownTurn, nil, "the condemned member's own turn did not come before its Doom")
    -- the Doom landed, and the driver read it as nobody's action
    local death, cleared = nil, nil
    for i = lineB + 1, #lines do
      local s = lines[i]
      if death == nil and s:find("%[death%] f%+%d+ entity " .. doomedB .. " char") then death = s end
      if cleared == nil and s:find("entity " .. doomedB .. "'s Condemned is CLEARED") then cleared = s end
    end
    H.assertEq(death ~= nil, true, "the Doom killed the condemned member ([death] line)")
    H.assertEq(death:find("by nobody", 1, true) ~= nil, true, "...attributed to no monster action")
    H.assertEq(cleared ~= nil and cleared:find("the Doom landed", 1, true) ~= nil, true,
      "...and the CLEARED line says the Doom landed")

    -- A. the condemned actor's own last turn
    local status, planKind, spendLine = nil, nil, nil
    for i = lineA + 1, #lines do
      local s = lines[i]
      if status == nil and s:find("%[status%] f%+%d+ entity " .. doomedA .. " char %d+ is under CONDEMNED") then status = s end
      if spendLine == nil and s:find("actor=" .. doomedA .. " is CONDEMNED at %d+ %(x %d+ frames%) and its next turn is a full gauge away") then spendLine = s end
      local kind = s:match("actor=" .. doomedA .. " char=%d+ plan=(%S+)")
      if kind and planKind == nil then planKind = kind end
    end
    H.assertEq(status ~= nil, true, "the driver said the [status] line for the Condemned")
    H.assertEq(status:find("the count reads 2", 1, true) ~= nil, true, "...with the count shown, 2")
    H.assertEq(spendLine ~= nil, true, "the driver said the condemned actor's turn is its last and spends its BP")
    H.assertEq(planKind ~= nil and planKind ~= "item" and planKind ~= "heal", true,
      "the condemned actor's plan is an attack, not care (plan=" .. tostring(planKind) .. ")")
    if bpA > 0 then
      H.assertEq(spendLine:find("spends its " .. bpA .. " BP", 1, true) ~= nil, true,
        "...spending the " .. bpA .. " BP it held")
    else
      H.log("[test] the condemned actor held 0 BP at its window: the spend is asserted on the line, not the pips")
    end

    table.sort(periods)
    H.log(string.format("[test] count decrements measured %d frames apart (%s) against "
      .. "H.COUNT_FRAMES=%d; the Doom on entity %d landed %d frames after its poke at count 1",
      #periods > 0 and periods[1] or -1, table.concat(periods, ","), H.COUNT_FRAMES, doomedB,
      deathFrame - frameB))
    -- (#252: this used to sit inside `if #periods > 0`, so no measurement passed)
    H.assertEq(#periods > 0, true, "a count decrement was measured")
    local said = {}
    for _, v in ipairs(periodVisits) do
      said[#said + 1] = string.format("entity %d %s visit(s), %s by its speed ($3add %s)",
        v.e, tostring(v.got), tostring(v.want), v.speeds)
    end
    H.log(string.format("[test] visits per measured count: %s; shortest gap between visits %s frames; "
      .. "%d accumulator change(s) that were not visits",
      table.concat(said, "; "), tostring(minVisit), notVisits))
    for i, v in ipairs(periodVisits) do
      H.assertEq(v.got ~= nil and v.got == v.want, true, string.format(
        "count %d (entity %d) stepped on the visit its accumulator carried: %s visit(s), want %s",
        i, v.e, tostring(v.got), tostring(v.want)))
    end
    -- H.COUNT_FRAMES prices a count at normal speed: 256 / 64 visits, each
    -- 16 ticks of 2 frames while the clock runs
    H.assertEq(minVisit ~= nil and (256 // NORMAL_SPEED) * minVisit == H.COUNT_FRAMES, true,
      string.format("%d visits at the running clock's %s frames each are H.COUNT_FRAMES=%d",
        256 // NORMAL_SPEED, tostring(minVisit), H.COUNT_FRAMES))
  end),
})
