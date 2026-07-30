-- probe_multihit.lua -- #54 phase 1: PER HIT, or once per action?
--
--   tools/tests/run.sh tools/tests/probe_multihit.lua
--
-- The whole multi-hit design rests on one rule nobody had measured: when an
-- action strikes N times, does it chip N shields or one?  DESIGN.md:147 and
-- break-impl.md:30-34 both assert per-hit; neither cites a measurement.
--
-- WHY BOOSTED FIGHT IS THE RIGHT INSTRUMENT.  The engine has exactly one
-- multi-hit mechanism: `$3a70`, "number of attacks (0 = 1 attack)", and one
-- loop that consumes it --
--     @3288:  plx / dec $3a70 / bmi @3291 / pea ExecAttack-1
--   (battle_main.asm:8322-8328)
-- Quadra Slam and Quadra Slice reach that loop by setting $3a70 = 3
-- (AttackerEffect_32, battle_main.asm:10782-10784); a boosted Fight reaches
-- the SAME loop by setting $3a70 = 1 + 2*BP (Ot6FightBoost, ot6_boost.asm:
-- 240-248).  So whatever the loop does about chipping, it does for both --
-- and a boosted Fight can be driven in the opening guard fight, while a
-- Quadra Slam needs Cyan at level 15.  Measuring the loop measures the rule.
--
-- LAB: battle_class's, narrowed.  Guard A ($0c) gets SIX shields, class-weak
-- = the class of the weapon every party right hand is holding, and ZERO
-- element weaknesses (so no beam, and no poison DOT -- see #60 -- can move a
-- shield).  Guard B ($0e) is left class-weak 0 and element-weak 0: nothing
-- may ever chip it, which is the control for "the counter is counting hits,
-- not frames".  The party is berserked onto a Fight-only command list
-- (battle_hits's driver) with magitek cleared, and ONE subject is given
-- 3 BP / 3 pending, so its next auto-Fight swings 1+2*3 = 7 times.
--
-- Swings alternate hands and an empty hand swings nothing (ot6_boost.asm:
-- 220-224), so with one weapon equipped half of those 8 swings land.  The
-- probe does not predict the number -- it records $3a70 at every chip and
-- groups shield writes BY ACTION, keyed on $3a70 counting down inside one
-- volley.  Not by frame: a volley spans three of them, and the frame key
-- undercounted this probe's own headline 4 -> 2 before it was fixed.
--
-- Phase 2 then runs the identical volley into a TWO-shield enemy, which is
-- the question the design needs next: what do a volley's remaining hits do
-- once their own earlier hits have broken the target?

local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_doorstep.mss.lua"

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
  -- group shield writes BY ACTION, not by frame.  $3a70 counts DOWN within
  -- one action's volley (dec at battle_main.asm:8324) and is set afresh at
  -- the next action, so a write whose remaining-count is HIGHER than the
  -- previous write's begins a new action.  Frames are the wrong key: the
  -- 8-swing volley spans three of them, and keying on frames undercounted
  -- it 4 -> 2 in this probe's first version.
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
  -- the probe must not report "measured" having measured nothing
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
    -- the control is judged HERE, at the end of the phase it belongs to:
    -- phase 2 deliberately makes B chippable so the volley cannot miss the
    -- experiment by picking the wrong berserk target.
    controlHeld = (shieldB() == 6)
  end),

  -- PHASE 2: THE SAME VOLLEY INTO A 2-SHIELD ENEMY.  Does the break stop
  -- the rest of the volley chipping, and does the volley continue?
  -- Ot6Chip / Ot6ClassChip both bail on `lda OT6_BROKEN_TICKS,y / bne done`
  -- (ot6_break.asm:829-830, :927-929), so the prediction is: two chips,
  -- then break, then the remaining hits land damage and chip nothing.
  H.call(function()
    resetLog()
    -- BOTH guards, because a berserk Fight picks its target at random and
    -- the first run of this phase spent its whole volley on the guard that
    -- could not chip -- measuring nothing while looking fine.
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
  -- re-arm the boost every cycle until a 7-swing volley is actually seen:
  -- Ot6ActionEnd consumes the pending charge and skips that turn's regen,
  -- so a single poke only survives until the subject's next action, and a
  -- fixed wait let phase 2 finish having measured nothing (observed).
  -- Wait for a chip that landed with >= 3 attacks still queued -- i.e. one
  -- that happened INSIDE a boosted volley.  Waiting on "a guard broke" is
  -- not enough (two ordinary Fights broke one first, and the phase exited
  -- having measured nothing), and waiting on "$3a70 was 7" is not enough
  -- either (the volley can spend itself on a guard that cannot chip).
  -- Guards are re-armed to two live shields whenever they are broken or
  -- empty, so a 2-shield target is standing when the volley arrives.
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

    -- PHASE 2'S OWN FINDING, pinned so the probe cannot report it without
    -- having seen it: the breaking volley entered the chip hook four times
    -- on its target, and the last hits found it already at zero shields --
    -- so a volley that breaks its target mid-way stops CHIPPING while its
    -- remaining hits keep LANDING (and collect Ot6BrokenDmg's x2 instead).
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
