-- @suite savestate=kolts_cave
-- battle_zombieraise.lua -- no Fenix Down on a zombied corpse (#245,
-- M.raiseDecision's `zombie`).
--
-- A Fenix Down on a member carrying STATUS1 $02 never lands: vector_crash
-- spent 8 that way in the v0.18 qualification, each `actor 1's Fenix Down
-- on entity 2 never landed (841 ticks) -- forgetting it`
-- (build/attempts/v018-qual1.log:8551, #220), and the field care's
-- Revivify clears the bit between fights (ff443cb0).  The driver's raise
-- rule now reads the bit off STATUS1 (raiseOk) and M.raiseDecision
-- refuses with the reason, so the bag is not spent in the fight.
--
-- This is a focused mechanism test and stages with sanctioned expedient
-- writes: at a member's open command window an ally is POKED to 0 HP with
-- STATUS1 $80|$02 (dead and Zombie, the shape a zombied member's death
-- leaves), because Zombie is a monster special's roll (Zombone in the
-- Sealed Gate cave, hours from any fixture) and the driver's read is the
-- property under test.  The battle is a natural Mt. Kolts cave encounter
-- paced into from kolts_cave; the driver is the route's own, with the
-- kolts_cave bag's own Fenix Downs.
--
-- Asserted, from the poke:
--   1. the driver said why it throws no Fenix Down at the zombie (the
--      ZOMBIE line), and the plan that line governed -- the next plan
--      made, in the same planning call -- is that same actor's and is
--      not a Fenix Down on the zombie;
--   2. no actor plans one over the next three windows, and the bag's
--      Fenix count is what it was.
-- The raise rule is not every plan's first question: the kill-this-turn
-- press, a dying actor's boost spend (#175) and the finisher window
-- (monsters at 200 HP or less) all plan ahead of it.  So the drive runs
-- until the rule has spoken about the corpse, and 1 reads the plan the
-- ZOMBIE line preceded, whichever actor's it was, rather than the poked
-- window's own plan (a wor-sabin chain draw: actor 1 inside one round of
-- death spent its pip on a Fight before any raise was weighed, and actor
-- 2 said why at its window next, #290).
-- Negative controls: stub H.raiseDecision to ignore `zombie` (the old
-- rule) and 1 goes red -- the actor plans the throw; wrap the driver's
-- plan call to throw the Fenix Down at the zombie after saying the ZOMBIE
-- line anyway and 1's plan check goes red.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/kolts_cave.mss.lua"

local MENU, ACTOR, MSTATE, CMDTBL, BCHID, BATTINV = 0x7BCA, 0x62CA, 0x7BC2, 0x202E, 0x3ED8, 0x2686
local ST1 = 0x3EE4
local ST_CMD, CMD_ITEM, FENIX_DOWN = 0x05, 0x01, 0xF0

local F = nil
local lines = {}
local plans = {}   -- log line -> the plan that line announced (item, target)
local rawLog = H.log
H.log = function(msg)
  lines[#lines + 1] = tostring(msg)
  -- the driver sets its plan, then says "actor=A char=C plan=kind"
  if F ~= nil and F.driver.plan ~= nil and lines[#lines]:find("actor=%d+ char=%d+ plan=") then
    plans[#lines] = { kind = F.driver.plan.kind, item = F.driver.plan.item,
                      target = F.driver.plan.target }
  end
  return rawLog(msg)
end

local function map() return H.mapId() & 0x1ff end
local function hp(e) return H.readWord(0x3BF4 + e * 2) end
local function maxhp(e) return H.readWord(0x3C1C + e * 2) end
local function hasItemRow(e)
  for row = 0, 3 do
    if H.readByte(CMDTBL + e * 12 + row * 3) == CMD_ITEM
       and (H.readByte(CMDTBL + e * 12 + row * 3 + 1) & 0x80) == 0 then return true end
  end
  return false
end
local function fenixCount()
  for i = 0, 251 do
    if H.readByte(BATTINV + i * 5) == FENIX_DOWN then return H.readByte(BATTINV + i * 5 + 3) end
  end
  return 0
end

local zombie, actor0, pokeFrame, pokeLine, fenix0 = nil, nil, nil, nil, nil
local plansAfter = 0

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
    F = H.newFightDriver("zombieraise", { tactical = true, boost = true, bank = 2,
                                          items = true, healPercent = 50 })
    fenix0 = fenixCount()
    H.assertEq(fenix0 > 0, true, "the kolts_cave bag carries a Fenix Down (" .. fenix0 .. ")")
  end),

  -- the driver fights until a member with an Item row holds the command
  -- window with an ally standing; that ally is the zombied corpse
  H.driveUntil(function()
    if H.readByte(MENU) == 0 or H.readByte(MSTATE) ~= ST_CMD then return false end
    local e = H.readByte(ACTOR) & 3
    if hp(e) == 0 or maxhp(e) == 0 or not hasItemRow(e) then return false end
    local ally = nil
    for p = 0, 3 do if p ~= e and hp(p) > 0 and maxhp(p) > 0 then ally = p; break end end
    if ally == nil then return false end
    -- the poke (see the header): dead, and a Zombie
    H.writeWord(0x3BF4 + ally * 2, 0)
    H.writeByte(ST1 + ally * 2, H.readByte(ST1 + ally * 2) | 0x80 | 0x02)
    zombie, actor0, pokeFrame, pokeLine = ally, e, H.frame, #lines
    H.log(string.format("[test] f%d entity %d char %d poked to 0 HP with STATUS1 $%02X (dead + "
      .. "Zombie) while entity %d holds the command window (menu=%02X st=%02X); fenix=%d",
      H.frame, ally, H.readByte(BCHID + ally * 2), H.readByte(ST1 + ally * 2), e,
      H.readByte(MENU), H.readByte(MSTATE), fenixCount()))
    return true
  end, 20000, {
    H.call(function() F.frame() end),
    H.waitFrames(1),
  }, "a member's command window is open with an ally standing"),

  -- ...and on through three more plans and the raise rule's word on the
  -- corpse (the ZOMBIE line, or a throw), or the battle's end
  H.driveUntil(function()
    if not H.battleLoadStarted() then return true end
    plansAfter = 0
    local spoke = false
    for i = pokeLine + 1, #lines do
      if lines[i]:find("actor=%d char=%d+ plan=") then plansAfter = plansAfter + 1 end
      if lines[i]:find("no raise: Fenix Down would put entity " .. zombie .. " at", 1, true)
         or lines[i]:find("revive entity " .. zombie .. " with Fenix Down", 1, true) then
        spoke = true
      end
    end
    return plansAfter >= 4 and spoke
  end, 9000, {
    H.call(function() F.frame() end),
    H.waitFrames(1),
  }, "three more windows after the poke and the raise rule's word on the corpse"),

  H.call(function()
    H.setPad({})
    local e = zombie
    local whyLine, revives, firstPlan = nil, {}, nil
    for i = pokeLine + 1, #lines do
      if whyLine == nil and lines[i]:find("no raise: Fenix Down would put entity " .. e .. " at", 1, true)
         and lines[i]:find("ZOMBIE", 1, true) then whyLine = i end
      if lines[i]:find("revive entity " .. e .. " with Fenix Down", 1, true) then revives[#revives + 1] = i end
      if firstPlan == nil and lines[i]:find("actor=" .. actor0 .. " char=%d+ plan=") then firstPlan = i end
    end
    -- 1. the reason, and the plan it governed: the next plan line after
    -- it, which the same planning call announces
    H.assertEq(whyLine ~= nil, true, string.format("the driver said why it throws no Fenix "
      .. "Down at entity %d (the ZOMBIE line; actor %d's first plan after the poke at log "
      .. "line %s)", e, actor0, tostring(firstPlan)))
    local whyActor = tonumber(lines[whyLine]:match("actor=(%d+) no raise"))
    local govLine = nil
    for i = whyLine + 1, #lines do
      if lines[i]:find("actor=%d char=%d+ plan=") then govLine = i; break end
    end
    local govActor = govLine and tonumber(lines[govLine]:match("actor=(%d+) char="))
    local gov = govLine and plans[govLine]
    H.assertEq(gov ~= nil and govActor == whyActor
      and not (gov.item == FENIX_DOWN and gov.target == e), true,
      string.format("...and the plan it governed is actor %s's own and no Fenix Down on "
        .. "entity %d (why at log line %d; next plan at %s: actor %s, %s item %s target %s)",
        tostring(whyActor), e, whyLine, tostring(govLine), tostring(govActor),
        gov and gov.kind or "?", gov and gov.item and string.format("$%02X", gov.item) or "-",
        gov and tostring(gov.target) or "-"))
    H.assertEq(#revives, 0, string.format("no actor planned a Fenix Down on the zombied "
      .. "entity %d over %d windows (revive lines at %s)", e, plansAfter,
      #revives > 0 and table.concat(revives, ",") or "none"))
    -- 2. the bag
    H.assertEq(fenixCount(), fenix0, "the bag's Fenix count is what it was (" .. fenix0 .. ")")
    H.log(string.format("[test] zombieraise: entity %d poked at f%d; %d plan(s) after it, "
      .. "0 Fenix Downs planned on it; why at log line %d: %s", e, pokeFrame, plansAfter,
      whyLine, lines[whyLine]))
  end),
})
