-- @suite savestate=wor_grave
-- battle_careguards.lua -- the fight driver's status guards on a plan (#348,
-- the review of f8f9ad66): three branches of Dullahan's fight, each from the
-- party on the grave (wor_grave), the grave pressed with A as the route does,
-- and the fight played by the driver one call a frame.
--
--   A. Muddled after the plan.  The first time an actor's plan stands in a
--      window past the command list (a list or the target select), Muddle
--      ($3EE5 bit 5) is written onto that actor.  The driver must back out
--      and defer: no confirm and no commit for that actor while the bit
--      stands.  (Measured in play at the Sealed Gate cave: SABIN's Pummel,
--      planned a beat before Muddle landed, was committed and the engine
--      aimed it at TERRA -- gen_gate_cave_save's first cave fight.)
--   B. A Zombie at the plan.  At the first window, before the driver's
--      first frame, one member is Zombied ($3EE4 bit 1) at a third of its HP, with the driver's Zombie cure off
--      (opts.zombieCure = false, the line before #263) so the heal lines are
--      what is asked.  No heal or party cure may be planned on it: a cure on
--      a Zombie is damage.
--   C. Zombied after the plan.  At the first window one member is put at a
--      third of its HP; the
--      first time a heal on it stands in the item list or the target
--      select, Zombie is written onto it.  The driver must back out: no
--      heal confirmed on it after the write.
--
-- WHAT IS STAGED: the status bits and, in B and C, one member's HP -- this
-- file's waiver lines (tools/state_write_waivers.txt).  Statuses landing at
-- a chosen frame cannot be had on cue; the property is the driver's reaction,
-- not the fight's.  Everything else is the driver's own presses.  Each branch
-- is red on main's lib (no back-out, the Zombie a heal candidate) and on
-- f8f9ad66's for B (the heal planned, backed out and planned again).
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/wor_grave.mss.lua"
local ST1, ST2, MENU, MSTATE = 0x3EE4, 0x3EE5, 0x7BCA, 0x7BC2
local ST_CMD = 0x05
local F, branch, written, victim, viol, seen = nil, nil, nil, nil, {}, {}

local function up() return H.battleLoadStarted() and H.monstersPresent() > 0 end
local function hp(e) return H.readWord(0x3BF4 + e * 2) end
local function maxhp(e) return H.readWord(0x3C1C + e * 2) end

-- one frame of the driver, and the branch's watch on it
local function tick()
  if not up() then F.idle(); return end
  F.frame()
  local D = F.driver
  local p, a = D.plan, D.planActor
  local st = H.readByte(MSTATE)
  if branch == "A" then
    if not written and p ~= nil and a ~= nil and not p.committed and p.kind ~= "defer" and p.kind ~= "switch"
       and H.readByte(MENU) ~= 0 and st ~= ST_CMD and st ~= 0x00 and st ~= 0x01 then
      victim, written = a, H.frame
      H.writeByte(ST2 + a * 2, H.readByte(ST2 + a * 2) | 0x20)
      H.log(string.format("[careguards] A: f%d actor %d's %s plan stands in state $%02X: Muddle written onto it",
        H.frame, a, p.kind, st))
    elseif written and (H.readByte(ST2 + victim * 2) & 0x20) ~= 0 then
      if D.confirmed ~= nil and D.confirmed.actor == victim and not seen.conf then
        seen.conf = true
        viol[#viol + 1] = string.format("f%d: a command confirmed for the muddled actor %d (%s)", H.frame, victim,
          tostring(D.confirmed.kind))
      end
      if p ~= nil and a == victim and p.committed and not seen.commit then
        seen.commit = true
        viol[#viol + 1] = string.format("f%d: the muddled actor %d's %s committed", H.frame, victim, p.kind)
      end
      if p ~= nil and a == victim and p.kind == "defer" then seen.defer = true end
    end
  elseif branch == "B" then
    if p ~= nil and p.target == victim and (p.kind == "heal" or (p.kind == "item"
       and type(p.reason) == "string" and p.reason:sub(1, 5) ~= "cure " and p.reason ~= "revive"))
       and (H.readByte(ST1 + victim * 2) & 0x02) ~= 0 and not seen[p] then
      seen[p] = true
      viol[#viol + 1] = string.format("f%d: actor %d planned a %s (%s) on the Zombie, entity %d", H.frame,
        a or -1, p.kind, tostring(p.reason), victim)
    end
    if p ~= nil and p.all and p.kind == "heal" and not seen[p] then
      seen[p] = true
      viol[#viol + 1] = string.format("f%d: actor %d planned a party cure with entity %d Zombied", H.frame,
        a or -1, victim)
    end
  elseif branch == "C" then
    if not written and p ~= nil and p.target == victim and (p.kind == "heal" or p.kind == "item")
       and (st == 0x38 or st == 0x0A or st == 0x0E) then
      written = H.frame
      H.writeByte(ST1 + victim * 2, H.readByte(ST1 + victim * 2) | 0x02)
      H.log(string.format("[careguards] C: f%d actor %d's %s on entity %d stands in state $%02X: Zombie written "
        .. "onto entity %d", H.frame, a or -1, p.kind, victim, st, victim))
    elseif written and D.confirmed ~= nil and D.confirmed.target == victim
       and (D.confirmed.kind == "heal" or D.confirmed.kind == "item") and not seen.conf then
      seen.conf = true
      viol[#viol + 1] = string.format("f%d: a %s confirmed on the Zombie, entity %d", H.frame,
        tostring(D.confirmed.kind), victim)
    end
  end
end

-- a branch: the grave, A, the opening, the staging at the first window, the fight
local function run(name, opts, stage)
  return H.seqStep({
    H.loadState(STATE),
    H.waitFrames(10),
    H.call(function()
      branch, written, victim, viol, seen = name, nil, nil, {}, {}
      F = H.newFightDriver("careguards " .. name, opts)
    end),
    H.faceAndHoldA("up", function() return H.battleLoadStarted() end, 3000, "the grave: face up, A"),
    H.release(),
    H.waitUntil(function() return up() and H.readByte(MENU) == 0 end, 3000, name .. ": the fight is up", 1),
    -- B and C stage at the first command window, before the driver's first
    -- frame: staged as the fight opens, Dullahan's first blow (570 on SABIN
    -- in the prev lib's run) took the member down before any window opened,
    -- and the branch tested nothing
    H.waitUntil(function() return stage == nil or (up() and H.readByte(MENU) ~= 0) end, 3000,
      name .. ": the first command window", 1),
    H.call(function() if stage then stage() end end),
    H.driveUntil(function()
      return (written ~= nil and H.frame - written > 1800) or not up()
    end, 12000, { H.call(tick) }, name .. ": the driver's play"),
    H.release(),
  })
end

H.run({ maxFrames = 80000 }, {
  -- A. muddled after the plan
  run("A", { tactical = true, boost = true, items = true, runic = true }),
  H.call(function()
    H.assertEq(written ~= nil, true, "A: an actor's plan stood past the command list (Muddle written)")
    H.assertEq(#viol, 0, "A: no command confirmed or committed for the muddled actor: "
      .. table.concat(viol, "; "))
    H.assertEq(seen.defer == true, true, "A: the muddled actor's window was deferred (the Muddle rule's plan)")
    H.log("[careguards] A PASSED: the driver backed out and deferred")
  end),
  -- B. a Zombie at the plan
  run("B", { tactical = true, boost = true, items = true, runic = true, zombieCure = false }, function()
    -- SABIN (entity 1 in the route's order) at a third of his HP, Zombied
    victim = 1
    H.writeWord(0x3BF4 + victim * 2, maxhp(victim) // 3)
    H.writeByte(ST1 + victim * 2, H.readByte(ST1 + victim * 2) | 0x02)
    written = H.frame
    H.log(string.format("[careguards] B: entity %d Zombied at %d/%d at the first window", victim,
      hp(victim), maxhp(victim)))
  end),
  H.call(function()
    H.assertEq(#viol, 0, "B: no heal or party cure planned with a Zombie as its patient: " .. table.concat(viol, "; "))
    H.log("[careguards] B PASSED: no heal planned on the Zombie")
  end),
  -- C. Zombied after the plan
  run("C", { tactical = true, boost = true, items = true, runic = true, zombieCure = false }, function()
    victim = 1
    H.writeWord(0x3BF4 + victim * 2, maxhp(victim) // 3)
    H.log(string.format("[careguards] C: entity %d at %d/%d at the first window", victim, hp(victim),
      maxhp(victim)))
  end),
  H.call(function()
    H.assertEq(written ~= nil, true, "C: a heal on the hurt member stood in a list or the target select (Zombie written)")
    H.assertEq(#viol, 0, "C: no heal confirmed on the member Zombied after the plan: " .. table.concat(viol, "; "))
    H.log("[careguards] C PASSED: the heal was backed out")
  end),
})
