-- @suite savestate=kolts_cave
-- battle_doom.lua -- what the fight driver does about a Condemned member
-- (#190, H.doomCount / H.doomRule).
--
-- Condemned counts $3B05 down and casts Doom at 0; nothing in the bag
-- clears the bit (lib/ot6.lua, M.statusCure's note), and a Fenix Down
-- after the Doom raises the member clear of it.  gen_fc_escape logged the
-- count under Nerapa and never planned on it.  The driver now reads the
-- count as a clock: a member the Doom takes before their next turn gets
-- no heal (the HP goes with the Doom), and on their own last turn they
-- spend every pip on the attack lines rather than die holding boost.
--
-- This is a focused mechanism test and stages with sanctioned expedient
-- writes, because Condemned on the WoB route is Nerapa's opening on the
-- FC escape, hours of play from any fixture:
--   * Condemned is POKED in the engine's own shape -- STATUS2 bit 0 and
--     the $3B05 count (StartCondemn @09b4 writes exactly those two);
--   * the patient's HP is POKED down to a third, the way battle_healerdown
--     pokes its corpse, so the heal line has somebody to refuse.
-- The battle is a natural Mt. Kolts cave encounter paced into from
-- kolts_cave; the driver is the route's own.
--
-- Two windows, two halves of the rule:
--   A. the actor whose command window is open is condemned at 2 (256
--      frames, under any full gauge here): its plan is an attack, its
--      boost is every pip it holds, and the driver said why;
--   B. at the next window of another, uncondemned actor, a third member
--      is condemned at 1 (128 frames) and hurt to a third: the driver
--      says it is throwing no heal at them, and no heal or item plan
--      names them before the Doom lands.
-- Then the Doom lands (a [death] line with nobody's action attributed)
-- and the CLEARED line says so.  The count's own clock is measured on the
-- way (frames between decrements) and logged beside H.COUNT_FRAMES.
-- Negative control: stub H.doomRule to nil and A goes red -- the actor
-- plans without spending, or heals.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/kolts_cave.mss.lua"

local MENU, ACTOR, MSTATE, CMDTBL, BCHID, BP = 0x7BCA, 0x62CA, 0x7BC2, 0x202E, 0x3ED8, 0x3E9C
local ST2, DOOM_COUNT, ATB, ATB_CONST = 0x3EE5, 0x3B05, 0x3218, 0x3AC8
local ST_CMD, CMD_FIGHT, CMD_ITEM = 0x05, 0x00, 0x01

local lines = {}
local rawLog = H.log
H.log = function(msg)
  lines[#lines + 1] = tostring(msg)
  return rawLog(msg)
end

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
local function turnFrames(e)
  local const = H.readWord(ATB_CONST + e * 2)
  local eta = H.atbEta(H.readWord(ATB + e * 2), const)
  local period = const > 0 and math.ceil(0xFF00 / const) or nil
  local ticks = (eta == 0 or eta == nil) and period or eta
  return ticks and ticks * 2 or nil
end
local function bagHas(id)
  for i = 0, 251 do
    if H.readByte(0x2686 + i * 5) == id and H.readByte(0x2686 + i * 5 + 3) > 0 then return true end
  end
  return false
end

local F = nil
local doomedA, bpA, lineA, frameA = nil, nil, nil, nil
local doomedB, actorB, lineB, frameB = nil, nil, nil, nil
local deathFrame, deathLine = nil, nil
local lastCount, lastCountFrame, periods, decremented = {}, {}, {}, {}

local function watchCounts()
  for e = 0, 3 do
    -- Read the raw $3B05 byte while the Condemned bit is set, not H.doomCount.
    -- A decrement is the byte stepping down while still condemned, OR the bit
    -- clearing while the byte was still positive: the Doom fires at 1 and
    -- clears the bit in the same DecCounters visit, so that last step reads as
    -- byte -> nil (never an observable 1), yet the interval into it is still a
    -- full cycle.
    local condemned = (H.readByte(ST2 + e * 2) & 0x01) ~= 0
    local b = condemned and H.readByte(DOOM_COUNT + e * 2) or nil
    local stepped = lastCount[e] ~= nil and lastCountFrame[e] ~= nil
      and ((b ~= nil and b < lastCount[e]) or (b == nil and lastCount[e] > 0))
    if stepped then
      -- Skip the partial first cycle.  The poke lands mid-accumulator (the
      -- engine's $3adc / CalcSpeed is not reset by writing the count byte), so
      -- the gap from the poke to the FIRST decrement is a fraction of a cycle,
      -- not the count's cadence -- measured here at 84 frames against a real
      -- 128.  Only the gap between two real decrements is a full cycle, so a
      -- period is recorded from the second decrement on (#190, M.COUNT_FRAMES).
      if decremented[e] then periods[#periods + 1] = H.frame - lastCountFrame[e] end
      decremented[e] = true
    end
    if b ~= lastCount[e] then lastCount[e], lastCountFrame[e] = b, H.frame end
  end
end

H.run({ maxFrames = 90000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000,
    "field control in cave 96"),
  H.call(function() H.assertEq(map(), 96, "kolts_cave on map 96") end),

  -- pace the auto-detected lane until a natural encounter fires
  (function()
    local battN, waited, lane = 0, 0, nil
    local BACK = { left = "right", right = "left", up = "down", down = "up" }
    return H.driveUntil(function()
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
    }, "a cave encounter fires")
  end)(),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle armed", 5),

  H.call(function()
    -- freeRound = "care": this Mt. Kolts encounter opens as a preemptive
    -- strike, whose free round otherwise defers every top-up one turn for an
    -- attack (#186), skipping the heal-candidate loop where #190's refusal
    -- lives.  The lever keeps the heals so the condemned member is actually
    -- weighed as a patient -- which is the decision this test observes.
    F = H.newFightDriver("doom", { tactical = true, boost = true, bank = 2,
                                   items = true, healPercent = 60,
                                   freeRound = "care" })
  end),

  -- A. the first open command window of a member with a Fight row and a
  -- living ally: condemn that member at 2 (256 frames)
  H.driveUntil(function()
    watchCounts()
    if H.readByte(MENU) == 0 or H.readByte(MSTATE) ~= ST_CMD then return false end
    local e = H.readByte(ACTOR) & 3
    if hp(e) == 0 or maxhp(e) == 0 or not hasRow(e, CMD_FIGHT) then return false end
    local allies = 0
    for p = 0, 3 do if p ~= e and hp(p) > 0 and maxhp(p) > 0 then allies = allies + 1 end end
    if allies == 0 then return false end
    H.writeByte(ST2 + e * 2, H.readByte(ST2 + e * 2) | 0x01)
    H.writeByte(DOOM_COUNT + e * 2, 3)
    doomedA, bpA, lineA, frameA = e, H.readByte(BP + e * 2), #lines, H.frame
    H.log(string.format("[test] f%d Condemned poked onto entity %d char %d at its open command "
      .. "window: count 2 (%d frames), its next turn %s frames away, %d BP held",
      H.frame, e, H.readByte(BCHID + e * 2), 2 * H.COUNT_FRAMES, tostring(turnFrames(e)), bpA))
    return true
  end, 20000, {
    H.call(function() F.frame() end),
    H.waitFrames(1),
  }, "a member's command window is open with an ally standing"),

  -- B. the next command window of ANOTHER member with an Item row (and a
  -- Potion or Tonic in the bag): condemn a third member at 1 and hurt
  -- them to a third, so the heal line has a patient to refuse
  H.driveUntil(function()
    watchCounts()
    if H.readByte(MENU) == 0 or H.readByte(MSTATE) ~= ST_CMD then return false end
    local e = H.readByte(ACTOR) & 3
    if e == doomedA or hp(e) == 0 or maxhp(e) == 0 or not hasRow(e, CMD_ITEM) then return false end
    if not (bagHas(0xE9) or bagHas(0xE8)) then
      error("no Potion or Tonic in the battle bag: nothing for the heal line to refuse", 0)
    end
    local c = nil
    for p = 0, 3 do
      if p ~= e and p ~= doomedA and hp(p) > 0 and maxhp(p) > 0
         and (turnFrames(p) == nil or turnFrames(p) >= H.COUNT_FRAMES) then c = p end
    end
    if c == nil then return false end
    H.writeByte(ST2 + c * 2, H.readByte(ST2 + c * 2) | 0x01)
    H.writeByte(DOOM_COUNT + c * 2, 2)
    H.writeWord(0x3BF4 + c * 2, math.max(1, maxhp(c) // 3))
    -- doomedA's corpse (its own Doom already landed) is a revivable body, and
    -- the driver's raise block sits ahead of the heal loop: with a Fenix Down
    -- in the battle bag (the mog-gear route now carries one) it returns a
    -- revive before it ever weighs healing the condemned member -- correct,
    -- higher-priority play, but not the decision #190's rule is about.  Zero
    -- the battle-bag Fenix (id $F0) so this turn's care decision is the heal
    -- we mean to see refused; the corpse stays down, which part C still wants.
    for i = 0, 251 do
      if H.readByte(0x2686 + i * 5) == 0xF0 then H.writeByte(0x2686 + i * 5 + 3, 0) end
    end
    doomedB, actorB, lineB, frameB = c, e, #lines, H.frame
    H.log(string.format("[test] f%d Condemned poked onto entity %d char %d (count 1, %d frames; "
      .. "its next turn %s frames away) and its HP set to %d/%d, at actor %d's open command window",
      H.frame, c, H.readByte(BCHID + c * 2), H.COUNT_FRAMES, tostring(turnFrames(c)), hp(c),
      maxhp(c), e))
    return true
  end, 20000, {
    H.call(function() F.frame() end),
    H.waitFrames(1),
  }, "another member's command window is open with a third member standing"),

  -- ...then keep fighting until the Doom has landed on both (or the battle ends)
  H.driveUntil(function()
    watchCounts()
    if not H.battleLoadStarted() then return true end
    if deathFrame == nil and hp(doomedB) == 0 then deathFrame, deathLine = H.frame, #lines end
    return hp(doomedA) == 0 and hp(doomedB) == 0 and H.frame - deathFrame > 60
  end, 6000, {
    H.call(function() F.frame() end),
    H.waitFrames(1),
  }, "the Doom lands on both condemned members"),

  H.call(function()
    H.setPad({})
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
    -- B. no heal on the hurt, condemned third member
    local refused, healed = nil, nil
    for i = lineB + 1, (deathLine or #lines) do
      local s = lines[i]
      if refused == nil and s:find("no heal on entity " .. doomedB .. " %(") and s:find("CONDEMNED at 1") then refused = s end
      if s:find("heal entity " .. doomedB .. " %(") or s:find("cure entity " .. doomedB .. " %(") then healed = s end
    end
    H.assertEq(refused ~= nil, true, string.format("actor %d refused the heal on the condemned "
      .. "entity %d and said why", actorB, doomedB))
    H.assertEq(healed, nil, "no heal or cure plan named the condemned member before the Doom")
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
    table.sort(periods)
    H.log(string.format("[test] count decrements measured %d frames apart (%s) against "
      .. "H.COUNT_FRAMES=%d; the Doom on entity %d landed %d frames after its poke at count 1",
      #periods > 0 and periods[1] or -1, table.concat(periods, ","), H.COUNT_FRAMES, doomedB,
      (deathFrame or 0) - frameB))
    if #periods > 0 then
      H.assertEq(periods[1] >= H.COUNT_FRAMES - 34 and periods[1] <= H.COUNT_FRAMES + 34, true,
        string.format("the shortest measured count is one entity visit off %d frames (got %d)",
          H.COUNT_FRAMES, periods[1]))
    end
  end),
})
