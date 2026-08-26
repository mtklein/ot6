-- probe_multihit.lua -- measures whether shield chipping is per hit or
-- once per action.
--
-- The engine's multi-hit mechanism is $3a70, "number of attacks
-- remaining in this action (0 = 1 attack)"; ExecAttack loops while
-- decrementing it. Quadra Slam/Slice set it to 3; a boosted Fight sets
-- it to 1 + 2*BP. Both reach the same loop, so a boosted Fight stands
-- in for a Quadra Slam.
--
-- Setup: Guard A ($0c) gets six shields, class-weak to the party's
-- weapon, and zero element weaknesses, so nothing but a class hit can
-- chip it. Guard B ($0e) is weak to nothing, the control for whether
-- the counter is counting hits rather than frames. The party is
-- berserked onto a Fight-only command list with magitek cleared, and
-- one subject is given 3 BP / 3 pending, so its next auto-Fight swings
-- 1+2*3 = 7 times.
--
-- Swings alternate hands and an empty hand swings nothing, so with one
-- weapon equipped half of those swings land. Shield writes are grouped
-- by action, keyed on $3a70 counting down inside one volley (not by
-- frame: a volley spans multiple frames).
--
-- Phase 2 then runs the identical volley into a two-shield enemy, to
-- measure what a volley's remaining hits do once its earlier hits have
-- broken the target.

local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_entry.mss.lua"

local A, B = 0x0c, 0x0e
local WEAPON = 0x0a          -- MithrilBlade: Ot6WeapClassTbl slash ($01)
local WCLASS = 0x01

local function shieldA() return H.readByte(0x3E38 + A) end
local function shieldB() return H.readByte(0x3E38 + B) end

local ATB_FAST = 0x1000
local function keepAlive()
  H.writeWord(0x3C00, 20000)
  H.writeWord(0x3C02, 20000)
  for c = 0, 2 do
    local a = 0x3BF4 + c * 2
    if H.readWord(a) > 0 and H.readWord(a) < 200 then H.writeWord(a, 400) end
  end
  for slot = 0, 3 do H.writeWord(0x3AC8 + slot * 2, ATB_FAST) end
end

-- ------------------------------------------------------------- recording --
local chips, shieldWrites, swingCounts = {}, {}, {}
local refs = {}
local phase1best = 0
local controlHeld = nil

local function resetLog() chips, shieldWrites, swingCounts = {}, {}, {} end

local function arm()
  refs.cchip = emu.addMemoryCallback(function()
    chips[#chips + 1] = {
      frame = H.frame,
      y = emu.getState()["cpu.y"] & 0xFF,
      n = H.readByte(0x3a70),          -- attacks remaining in this action
      cls = H.readByte(0x57b8),        -- OT6_ATKCLASS
      sa = shieldA(), sb = shieldB(),
    }
  end, emu.callbackType.exec, H.sym("Ot6ClassChip"), H.sym("Ot6ClassChip"))
  refs.chip = emu.addMemoryCallback(function()
    chips[#chips + 1] = { frame = H.frame, y = 0xEE, n = H.readByte(0x3a70),
                          cls = 0xEE, sa = shieldA(), sb = shieldB() }
  end, emu.callbackType.exec, H.sym("Ot6Chip"), H.sym("Ot6Chip"))
  for _, e in ipairs({ A, B }) do
    local a = 0x7e0000 + 0x3E38 + e
    refs["sh" .. e] = emu.addMemoryCallback(function(addr, value)
      shieldWrites[#shieldWrites + 1] = { frame = H.frame, e = e, v = value,
                                          n = H.readByte(0x3a70) }
    end, emu.callbackType.write, a, a)
  end
  refs.swing = emu.addMemoryCallback(function(addr, value)
    swingCounts[#swingCounts + 1] = { frame = H.frame, v = value }
  end, emu.callbackType.write, 0x7e3a70, 0x7e3a70)
end

local function disarm()
  if not refs.cchip then return end
  emu.removeMemoryCallback(refs.cchip, emu.callbackType.exec,
    H.sym("Ot6ClassChip"), H.sym("Ot6ClassChip"))
  emu.removeMemoryCallback(refs.chip, emu.callbackType.exec,
    H.sym("Ot6Chip"), H.sym("Ot6Chip"))
  for _, e in ipairs({ A, B }) do
    local a = 0x7e0000 + 0x3E38 + e
    emu.removeMemoryCallback(refs["sh" .. e], emu.callbackType.write, a, a)
  end
  emu.removeMemoryCallback(refs.swing, emu.callbackType.write,
    0x7e3a70, 0x7e3a70)
  refs = {}
end

-- ------------------------------------------------------------------- lab --
local subject

local function setupLab()
  keepAlive()
  for _, e in ipairs({ A, B }) do
    H.writeByte(0x3BCC + e, 0x00)     -- absorb
    H.writeByte(0x3BCD + e, 0x00)     -- null
    H.writeByte(0x3BE0 + e, 0x00)     -- NO element weakness at all
    H.writeByte(0x3BE1 + e, 0x00)     -- resist
    H.writeByte(0x3E88 + e, 0)        -- not broken
    H.writeByte(0x3E89 + e, 0)
    H.writeByte(0x3E9D + e, 0)
  end
  H.writeByte(0x3E9C + A, WCLASS)     -- A: class-weak to the party's weapon
  H.writeByte(0x3E38 + A, 6)          -- six shields: room for a whole volley
  H.writeByte(0x3E39 + A, 6)
  H.writeByte(0x3E9C + B, 0x00)       -- B: weak to nothing.  the control.
  H.writeByte(0x3E38 + B, 6)
  H.writeByte(0x3E39 + B, 6)
  H.writeByte(0x3EC8, 0x00)
  for slot = 0, 3 do
    H.writeByte(0x202e + slot * 12, 0x00)
    H.writeByte(0x2031 + slot * 12, 0xff)
    H.writeByte(0x2034 + slot * 12, 0xff)
    H.writeByte(0x2037 + slot * 12, 0xff)
    local st1 = 0x3ee4 + slot * 2
    H.writeByte(st1, H.readByte(st1) & 0xf7)      -- clear magitek
    local st2 = 0x3ee5 + slot * 2
    H.writeByte(st2, H.readByte(st2) | 0x10)      -- berserk
    H.writeByte(0x3B90 + slot * 2, 0x00)          -- no weapon element
  end
  for _, a in ipairs({ 0x3CA8, 0x3CAA, 0x3CAC }) do H.writeByte(a, WEAPON) end
end


-- one dump of everything recorded since the last resetLog()
local function report(tag)
  H.log("== " .. tag .. " ==")
  H.log("-- $3a70 writes (action volleys)")
  for i, s in ipairs(swingCounts) do
    if i <= 60 then
      H.log(string.format("  swing %2d f%-6d $3a70 <- %02X", i, s.frame, s.v))
    end
  end
  H.log("-- chip hook entries")
  for i, c in ipairs(chips) do
    if i <= 60 then
      H.log(string.format("  chip %2d f%-6d %-9s y=%02X $3a70=%02X " ..
        "atkclass=%02X shields=%d,%d", i, c.frame,
        c.y == 0xEE and "(element)" or "(class)", c.y, c.n, c.cls, c.sa, c.sb))
    end
  end
  -- group shield writes by action rather than by frame.  $3a70 counts down
  -- within one action's volley and is set afresh at the next action, so a
  -- write whose remaining-count is higher than the previous write's begins
  -- a new action.
  H.log("-- shield writes, grouped by ACTION")
  local actions, cur, prevN = {}, nil, nil
  for _, w in ipairs(shieldWrites) do
    if cur == nil or prevN == nil or w.n > prevN or w.e ~= cur.e then
      cur = { e = w.e, frame = w.frame, w = {} }
      actions[#actions + 1] = cur
    end
    table.insert(cur.w, w)
    prevN = w.n
  end
  local best, bestKey = 0, nil
  for i, a in ipairs(actions) do
    local vals = {}
    for _, w in ipairs(a.w) do
      vals[#vals + 1] = string.format("%d($3a70=%02X)", w.v, w.n)
    end
    H.log(string.format("  action %d (entity %02X, from f%d): %d chip(s): %s",
      i, a.e, a.frame, #a.w, table.concat(vals, " -> ")))
    if #a.w > best then best, bestKey = #a.w, i end
  end
  H.log(string.format("  MOST CHIPS IN ONE ACTION: %d (action %s)", best,
    tostring(bestKey)))
  H.log(string.format("  final: A shields=%d timer=%02X | B shields=%d " ..
    "timer=%02X", shieldA(), H.readByte(0x3E88 + A), shieldB(),
    H.readByte(0x3E88 + B)))
  H.screenshot("multihit_p" .. (phase1best > 0 and 2 or 1))
  if best > phase1best then phase1best = best end
  -- guard against reporting "measured" when nothing was measured
  local boosted = false
  for _, s in ipairs(swingCounts) do if s.v == 0x07 then boosted = true end end
  H.assertEq(boosted, true, "a boosted volley (1+2*3 = 7) ran in " .. tag)
  return best
end

H.run({ maxFrames = 40000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.enterEncounter(),
  H.waitFrames(240),
  H.call(function()
    local menuHolder = H.readByte(0x62ca)
    subject = (menuHolder + 1) % 3
    setupLab()
    arm()
    H.log(string.format("lab: subject slot %d (menu holder %d), A cweak=%02X " ..
      "sh=%d, B cweak=%02X sh=%d", subject, menuHolder,
      H.readByte(0x3E9C + A), shieldA(), H.readByte(0x3E9C + B), shieldB()))
  end),
  -- let the pre-queued entry action flush unboosted, then boost the subject
  H.waitFrames(300),
  H.call(function()
    keepAlive()
    H.writeByte(0x3e9c + subject * 2, 3)   -- bp to spend
    H.writeByte(0x3e9d + subject * 2, 3)   -- pending: 1 + 2*3 = 7 -> 8 swings
    H.log("subject boosted: bp=3 pending=3")
  end),
  H.repeatN(40, { H.call(keepAlive), H.waitFrames(20) }),

  H.call(function()
    report("phase 1: six shields, room for the whole volley")
    -- the control is judged here, at the end of the phase it belongs to.
    controlHeld = (shieldB() == 6)
  end),

  -- Phase 2: the same volley into a 2-shield enemy, to measure whether a
  -- break mid-volley stops the remaining hits from chipping.
  H.call(function()
    resetLog()
    -- both guards, since a berserk Fight picks its target at random.
    for _, e in ipairs({ A, B }) do
      H.writeByte(0x3E9C + e, WCLASS)
      H.writeByte(0x3E38 + e, 2)
      H.writeByte(0x3E39 + e, 6)
      H.writeByte(0x3E88 + e, 0)
    end
    H.writeByte(0x3e9c + subject * 2, 3)
    H.writeByte(0x3e9d + subject * 2, 3)
    keepAlive()
    H.log("phase 2: both guards 2 shields and class-weak, subject re-boosted")
  end),
  -- re-arm the boost every cycle: Ot6ActionEnd consumes the pending charge
  -- each turn, so a single poke only survives until the subject's next
  -- action. Wait for a chip that landed with >= 3 attacks still queued,
  -- i.e. one inside a boosted volley. Guards are re-armed to two live
  -- shields whenever they are broken or empty.
  H.driveUntil(function()
    for _, w in ipairs(shieldWrites) do if w.n >= 3 then return true end end
    return false
  end, 8000, {
    H.call(function()
      keepAlive()
      for _, e in ipairs({ A, B }) do
        if H.readByte(0x3E88 + e) ~= 0 or H.readByte(0x3E38 + e) == 0 then
          H.writeByte(0x3E88 + e, 0)
          H.writeByte(0x3E38 + e, 2)
        end
      end
      H.writeByte(0x3e9c + subject * 2, 3)
      H.writeByte(0x3e9d + subject * 2, 3)
    end),
    H.waitFrames(20),
  }, "a boosted volley lands on a 2-shield guard"),
  H.waitFrames(120),
  H.call(function()
    disarm()
    report("phase 2: two shields, the volley breaks it mid-way")
    H.assertEq(phase1best >= 2, true, "one action chipped more than one shield")
    H.assertEq(controlHeld, true,
      "phase 1's class-weak-to-nothing control never chipped")

    -- asserts phase 2's finding: a volley that breaks its target mid-way
    -- stops chipping while its remaining hits keep landing.
    local run, target = {}, nil
    for _, c in ipairs(chips) do
      if c.n == 0x07 then
        run, target = { c }, c.y
      elseif #run > 0 and c.y == target and c.n < run[#run].n then
        run[#run + 1] = c
      end
    end
    local zeroed = 0
    for _, c in ipairs(run) do
      local sh = (target == A) and c.sa or c.sb
      if sh == 0 then zeroed = zeroed + 1 end
    end
    H.log(string.format("phase 2 volley: %d hook entries on entity %02X, " ..
      "%d of them with the target already at zero shields",
      #run, target or 0xFF, zeroed))
    H.assertEq(#run >= 4, true, "the breaking volley hit its target 4+ times")
    H.assertEq(zeroed >= 1, true,
      "later hits of the breaking volley found the target already broken " ..
      "and chipped nothing")
  end),
})
